import 'constants.dart';
import 'dialog/request_sender.dart';
import 'event_manager/event_manager.dart';
import 'event_manager/internal_events.dart';
import 'exceptions.dart' as Exceptions;
import 'logger.dart';
import 'rtc_session.dart';
import 'sip_message.dart';
import 'transactions/transaction_base.dart';
import 'ua.dart';
import 'uri.dart';
import 'utils.dart' as Utils;

class Dialog_C {
  // Dialog states.
  static const int STATUS_EARLY = 1;
  static const int STATUS_CONFIRMED = 2;
}

class Id {
  Id(this.call_id, this.local_tag, this.remote_tag);

  factory Id.fromMap(Map<String, dynamic> map) {
    return Id(map['call_id'], map['local_tag'], map['remote_tag']);
  }

  String call_id;
  String local_tag;
  String remote_tag;

  @override
  String toString() {
    return call_id + local_tag + remote_tag;
  }
}

// RFC 3261 12.1.
class Dialog {
  Dialog(this._owner, dynamic message, String type, [int? state]) {
    state = state ?? Dialog_C.STATUS_CONFIRMED;

    if (!message.hasHeader('contact')) {
      throw Exceptions.TypeError(
          'unable to create a Dialog without Contact header field');
    }

    if (message is IncomingResponse) {
      state = (message.status_code < 200)
          ? Dialog_C.STATUS_EARLY
          : Dialog_C.STATUS_CONFIRMED;
    }

    dynamic contact = message.parseHeader('contact');

    // RFC 3261 12.1.1.
    if (type == 'UAS') {
      _id = Id.fromMap(<String, dynamic>{
        'call_id': message.call_id,
        'local_tag': message.to_tag,
        'remote_tag': message.from_tag,
      });

      _state = state;
      _remote_seqnum = message.cseq;
      _local_uri = message.parseHeader('to').uri;
      _remote_uri = message.parseHeader('from').uri;
      _remote_target = contact.uri;
      _route_set = message.getHeaders('record-route');
      _ack_seqnum = _remote_seqnum;
    }
    // RFC 3261 12.1.2.
    else if (type == 'UAC') {
      _id = Id.fromMap(<String, dynamic>{
        'call_id': message.call_id,
        'local_tag': message.from_tag,
        'remote_tag': message.to_tag,
      });

      _state = state;
      local_seqnum = message.cseq;
      _local_uri = message.parseHeader('from').uri;
      _remote_uri = message.parseHeader('to').uri;
      _remote_target = contact.uri;
      _route_set = message.getHeaders('record-route').reversed.toList();
      _ack_seqnum = null;
    }

    _ua.newDialog(this);
    logger.debug(
        '$type dialog created with status ${_state == Dialog_C.STATUS_EARLY ? 'EARLY' : 'CONFIRMED'}');
  }

  final RTCSession _owner;
  UA get _ua => _owner.ua;
  bool uac_pending_reply = false;
  bool uas_pending_reply = false;
  int? _state;
  int? _remote_seqnum;
  URI? _local_uri;
  URI? _remote_uri;
  URI? _remote_target;
  List<dynamic> _route_set = <dynamic>[];
  int? _ack_seqnum;
  Id? _id;
  num? local_seqnum;

  UA get ua => _ua;
  Id? get id => _id;

  RTCSession get owner => _owner;

  void update(dynamic message, String type) {
    _state = Dialog_C.STATUS_CONFIRMED;

    logger.debug('dialog ${_id.toString()}  changed to CONFIRMED state');

    if (type == 'UAC') {
      // RFC 3261 13.2.2.4.
      _route_set = message.getHeaders('record-route').reversed.toList();
    }
  }

  void terminate() {
    logger.debug('dialog ${_id.toString()} deleted');
    _ua.destroyDialog(this);
  }

  OutgoingRequest sendRequest(SipMethod method, Map<String, dynamic>? options) {
    options = options ?? <String, dynamic>{};
    List<dynamic> extraHeaders = Utils.cloneArray(options['extraHeaders']);
    EventManager eventHandlers =
        options['eventHandlers'] as EventManager? ?? EventManager();
    String body = options['body'] ?? null;
    OutgoingRequest request = _createRequest(method, extraHeaders, body);

    // Increase the local CSeq on authentication.
    eventHandlers.on(EventOnAuthenticated(), (EventOnAuthenticated event) {
      if (local_seqnum != null) {
        local_seqnum = local_seqnum! + 1;
      }
    });

    DialogRequestSender request_sender =
        DialogRequestSender(this, request, eventHandlers);

    request_sender.send();

    // Return the instance of OutgoingRequest.
    return request;
  }

  void receiveRequest(IncomingRequest request) {
    // Check in-dialog request.
    if (!_checkInDialogRequest(request)) {
      return;
    }

    // ACK received. Cleanup _ack_seqnum.
    if (request.method == SipMethod.ACK && _ack_seqnum != null) {
      _ack_seqnum = null;
    }
    // INVITE received. Set _ack_seqnum.
    else if (request.method == SipMethod.INVITE) {
      _ack_seqnum = request.cseq;
    }

    _owner.receiveRequest.call(request);
  }

  // RFC 3261 12.2.1.1.
  OutgoingRequest _createRequest(
      SipMethod method, List<dynamic> extraHeaders, String body) {
    extraHeaders = Utils.cloneArray(extraHeaders);

    final num _local_seqnum =
        local_seqnum ??= Utils.Math.floor(Utils.Math.randomDouble() * 10000);

    num cseq;
    if (method == SipMethod.CANCEL || method == SipMethod.ACK) {
      cseq = _local_seqnum;
    } else {
      local_seqnum = _local_seqnum + 1;
      cseq = _local_seqnum + 1;
    }

    OutgoingRequest request = OutgoingRequest(
        method,
        _remote_target,
        _ua,
        <String, dynamic>{
          'cseq': cseq,
          'call_id': _id?.call_id,
          'from_uri': _local_uri,
          'from_tag': _id?.local_tag,
          'to_uri': _remote_uri,
          'to_tag': _id?.remote_tag,
          'route_set': _route_set
        },
        extraHeaders,
        body);

    return request;
  }

  // RFC 3261 12.2.2.
  bool _checkInDialogRequest(IncomingRequest request) {
    final int? _request_cseq = request.cseq;
    var _remote_seqnum = this._remote_seqnum;
    if (_remote_seqnum == null) {
      _remote_seqnum = _request_cseq;
    } else if (_request_cseq == null) {
      //
    } else if (_request_cseq < _remote_seqnum) {
      if (request.method == SipMethod.ACK) {
        // We are not expecting any ACK with lower seqnum than the current one.
        // Or this is not the ACK we are waiting for.
        if (_ack_seqnum == null || request.cseq != _ack_seqnum) {
          return false;
        }
      } else {
        request.reply(500);

        return false;
      }
    } else if (_request_cseq > _remote_seqnum) {
      _remote_seqnum = request.cseq;
    }
    this._remote_seqnum = _remote_seqnum;
    TransactionBase? eventHandlers = request.server_transaction;
    // RFC3261 14.2 Modifying an Existing Session -UAS BEHAVIOR-.
    if (request.method == SipMethod.INVITE ||
        (request.method == SipMethod.UPDATE && request.body != null)) {
      if (uac_pending_reply == true) {
        request.reply(491);
      } else if (uas_pending_reply == true) {
        double retryAfter = ((Utils.Math.randomDouble() * 10) % 10) + 1;
        request.reply(500, null, <String>['Retry-After:$retryAfter']);
        return false;
      } else {
        uas_pending_reply = true;
        void Function(EventStateChanged state)? stateChanged;
        stateChanged = (EventStateChanged state) {
          final TransactionState? transactionState =
              request.server_transaction?.state;
          if (transactionState == TransactionState.ACCEPTED ||
              transactionState == TransactionState.COMPLETED ||
              transactionState == TransactionState.TERMINATED) {
            uas_pending_reply = false;

            if (stateChanged != null) {
              eventHandlers?.remove(EventStateChanged(), stateChanged);
            }
          }
        };
        eventHandlers?.on(EventStateChanged(), stateChanged);
      }

      // RFC3261 12.2.2 Replace the dialog's remote target URI if the request is accepted.
      if (request.hasHeader('contact')) {
        eventHandlers?.on(EventStateChanged(), (EventStateChanged state) {
          final TransactionState? transactionState =
              request.server_transaction?.state;
          if (transactionState == TransactionState.ACCEPTED) {
            _remote_target = request.parseHeader('contact').uri;
          }
        });
      }
    } else if (request.method == SipMethod.NOTIFY) {
      // RFC6665 3.2 Replace the dialog's remote target URI if the request is accepted.
      if (request.hasHeader('contact')) {
        eventHandlers?.on(EventStateChanged(), (EventStateChanged state) {
          final TransactionState? transactionState =
              request.server_transaction?.state;
          if (transactionState == TransactionState.COMPLETED) {
            _remote_target = request.parseHeader('contact').uri;
          }
        });
      }
    }
    return true;
  }
}
