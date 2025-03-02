import 'dart:async';

import '../constants.dart';
import '../dialog.dart';
import '../event_manager/event_manager.dart';
import '../event_manager/internal_events.dart';
import '../request_sender.dart';
import '../rtc_session.dart' as RTCSession;
import '../sip_message.dart';
import '../timers.dart';
import '../transactions/transaction_base.dart';
import '../ua.dart';

class DialogRequestSender {
  DialogRequestSender(this._dialog, this._request, this._eventHandlers) {
    // RFC3261 14.1 Modifying an Existing Session. UAC Behavior.
    _reattempt = false;
  }
  final Dialog _dialog;
  UA get _ua => _dialog.ua;
  final OutgoingRequest _request;
  final EventManager _eventHandlers;
  bool _reattempt = false;
  Timer? _reattemptTimer;
  RequestSender? _request_sender;
  RequestSender? get request_sender => _request_sender;
  OutgoingRequest get request => _request;

  void send() {
    EventManager handlers = EventManager();
    handlers.on(EventOnRequestTimeout(), (EventOnRequestTimeout value) {
      _eventHandlers.emit(EventOnRequestTimeout());
    });
    handlers.on(EventOnTransportError(), (EventOnTransportError value) {
      _eventHandlers.emit(EventOnTransportError());
    });
    handlers.on(EventOnAuthenticated(), (EventOnAuthenticated event) {
      _eventHandlers.emit(EventOnAuthenticated(request: event.request));
    });
    handlers.on(EventOnReceiveResponse(), (EventOnReceiveResponse event) {
      final response = event.response;
      if (response != null) {
        _receiveResponse(response);
      }
    });

    _request_sender = RequestSender(_ua, _request, handlers);

    request_sender?.send();

    // RFC3261 14.2 Modifying an Existing Session -UAC BEHAVIOR-.
    if ((_request.method == SipMethod.INVITE ||
            (_request.method == SipMethod.UPDATE && _request.body != null)) &&
        request_sender?.clientTransaction?.state !=
            TransactionState.TERMINATED) {
      _dialog.uac_pending_reply = true;
      TransactionBase? eventHandlers = request_sender?.clientTransaction;
      void Function(EventStateChanged data)? stateChanged;
      stateChanged = (EventStateChanged data) {
        if (request_sender?.clientTransaction?.state ==
                TransactionState.ACCEPTED ||
            request_sender?.clientTransaction?.state ==
                TransactionState.COMPLETED ||
            request_sender?.clientTransaction?.state ==
                TransactionState.TERMINATED) {
          if (stateChanged != null) {
            eventHandlers?.remove(EventStateChanged(), stateChanged);
          }
          _dialog.uac_pending_reply = false;
        }
      };

      eventHandlers?.on(EventStateChanged(), stateChanged);
    }
  }

  void _receiveResponse(IncomingMessage response) {
    // RFC3261 12.2.1.2 408 or 481 is received for a request within a dialog.
    if (response.status_code == 408 || response.status_code == 481) {
      _eventHandlers.emit(EventOnDialogError(response: response));
    } else if (response.method == SipMethod.INVITE &&
        response.status_code == 491) {
      if (_reattempt != null) {
        if (response.status_code >= 200 && response.status_code < 300) {
          _eventHandlers.emit(EventOnSuccessResponse(response: response));
        } else if (response.status_code >= 300) {
          _eventHandlers.emit(EventOnErrorResponse(response: response));
        }
      } else {
        final int local_seqnum = _dialog.local_seqnum?.toInt() ?? 0 + 1;
        _dialog.local_seqnum = local_seqnum;
        _request.cseq = local_seqnum;
        _reattemptTimer = setTimeout(() {
          // TODO(cloudwebrtc): look at dialog state instead.
          if (_dialog.owner.status != RTCSession.C.STATUS_TERMINATED) {
            _reattempt = true;
            _request_sender?.send();
          }
        }, 1000);
      }
    } else if (response.status_code >= 200 && response.status_code < 300) {
      _eventHandlers.emit(EventOnSuccessResponse(response: response));
    } else if (response.status_code >= 300) {
      _eventHandlers.emit(EventOnErrorResponse(response: response));
    }
  }
}
