import 'dart:async';
import 'package:collection/collection.dart';

import 'constants.dart';
import 'constants.dart' as DartSIP_C;
import 'event_manager/event_manager.dart';
import 'event_manager/internal_events.dart';
import 'grammar.dart';
import 'logger.dart';
import 'name_addr_header.dart';
import 'request_sender.dart';
import 'sip_message.dart';
import 'timers.dart';
import 'transport.dart';
import 'ua.dart';
import 'uri.dart';
import 'utils.dart' as utils;

const int MIN_REGISTER_EXPIRES = 10; // In seconds.

class UnHandledResponse {
  UnHandledResponse(this.status_code, this.reason_phrase);
  int status_code;
  String reason_phrase;
}

class Registrator {
  Registrator(this._ua, [Transport? transport]) {
    int? reg_id = 1; // Force reg_id to 1.

    _transport = transport;

    // Call-ID and CSeq values RFC3261 10.2.
    _cseq = 0;

    _registrationTimer = null;

    // Ongoing Register request.
    _registering = false;

    // Set status.
    _registered = false;

    // Contact header.
    String contact = _ua.contact.toString();

    // Sip.ice media feature tag (RFC 5768).
    contact += ';+sip.ice';
    _contact = contact;

    // Custom headers for REGISTER and un-REGISTER.
    _extraHeaders = <String>[];

    // Custom Contact header params for REGISTER and un-REGISTER.
    _extraContactParams = '';

    // Custom Contact URI params for REGISTER and un-REGISTER.
    setExtraContactUriParams(
        _ua.configuration.register_extra_contact_uri_params ?? {});

    if (reg_id != null) {
      contact += ';reg-id=$reg_id';
      contact += ';+sip.instance="<urn:uuid:${_ua.configuration.instance_id}>"';
      _contact = contact;
    }
  }

  final UA _ua;
  Transport? _transport;
  URI get _registrar => _ua.configuration.registrar_server;
  int get _expires => _ua.configuration.register_expires;
  set _expires(int value) {
    _ua.configuration.register_expires = value;
  }

  final String _call_id = utils.createRandomToken(22);
  int _cseq = 0;
  URI get _to_uri => _ua.configuration.uri;
  Timer? _registrationTimer;
  bool _registering = false;
  bool _registered = false;
  String? _contact;
  List<String> _extraHeaders = <String>[];
  String _extraContactParams = '';

  bool get registered => _registered;

  Transport? get transport => _transport;

  void setExtraHeaders(List<String> extraHeaders) {
    if (extraHeaders is! List) {
      extraHeaders = <String>[];
    }
    _extraHeaders = extraHeaders;
  }

  void setExtraContactParams(Map<String, dynamic> extraContactParams) {
    if (extraContactParams is! Map) {
      extraContactParams = <String, dynamic>{};
    }

    // Reset it.
    _extraContactParams = '';

    extraContactParams.forEach((String param_key, dynamic param_value) {
      _extraContactParams += ';$param_key';
      if (param_value != null) {
        _extraContactParams += '=$param_value';
      }
    });
  }

  void setExtraContactUriParams(Map<String, dynamic> extraContactUriParams) {
    if (extraContactUriParams is! Map) {
      extraContactUriParams = <String, dynamic>{};
    }

    NameAddrHeader contact =
        Grammar.parse(_contact ?? '', 'Contact')[0]['parsed'];

    extraContactUriParams.forEach((String param_key, dynamic param_value) {
      contact.uri.setParam(param_key, param_value);
    });

    _contact = contact.toString();
  }

  void register() {
    if (_registering) {
      logger.debug('Register request in progress...');
      return;
    }

    List<String> extraHeaders = List<String>.from(_extraHeaders);

    extraHeaders
        .add('Contact: $_contact;expires=$_expires$_extraContactParams');
    extraHeaders.add('Expires: $_expires');

    if (_contact != null) logger.warn(_contact!);

    OutgoingRequest request = OutgoingRequest(
        SipMethod.REGISTER,
        _registrar,
        _ua,
        <String, dynamic>{
          'to_uri': _to_uri,
          'call_id': _call_id,
          'cseq': _cseq += 1
        },
        extraHeaders);

    EventManager handlers = EventManager();
    handlers.on(EventOnRequestTimeout(), (EventOnRequestTimeout value) {
      _registrationFailure(
          UnHandledResponse(408, DartSIP_C.causes.REQUEST_TIMEOUT),
          DartSIP_C.causes.REQUEST_TIMEOUT);
    });
    handlers.on(EventOnTransportError(), (EventOnTransportError value) {
      _registrationFailure(
          UnHandledResponse(500, DartSIP_C.causes.CONNECTION_ERROR),
          DartSIP_C.causes.CONNECTION_ERROR);
    });
    handlers.on(EventOnAuthenticated(), (EventOnAuthenticated value) {
      _cseq += 1;
    });
    handlers.on(EventOnReceiveResponse(), (EventOnReceiveResponse event) {
      {
        // Discard responses to older REGISTER/un-REGISTER requests.
        if (event.response?.cseq != _cseq) {
          return;
        }

        // Clear registration timer.
        if (_registrationTimer != null) {
          clearTimeout(_registrationTimer);
          _registrationTimer = null;
        }

        String? status_code = event.response?.status_code.toString();

        if (status_code != null) {
          if (utils.test1XX(status_code)) {
            // Ignore provisional responses.
          } else if (utils.test2XX(status_code)) {
            _registering = false;

            if (true != event.response?.hasHeader('Contact')) {
              logger.debug(
                  'no Contact header in response to REGISTER, response ignored');
              return;
            }

            List<dynamic> contacts = <dynamic>[];
            event.response?.headers?['Contact'].forEach((dynamic item) {
              contacts.add(item['parsed']);
            });
            // Get the Contact pointing to us and update the expires value accordingly.
            dynamic contact = contacts.firstWhereOrNull(
                (dynamic element) => element.uri.user == _ua.contact?.uri.user);

            if (contact == null) {
              logger
                  .debug('no Contact header pointing to us, response ignored');
              return;
            }

            dynamic expires = contact.getParam('expires');

            if (expires == null &&
                true == event.response?.hasHeader('expires')) {
              expires = event.response?.getHeader('expires');
            }

            expires ??= _expires;

            expires = num.tryParse(expires) ?? 0;

            if (expires < MIN_REGISTER_EXPIRES) {
              expires = MIN_REGISTER_EXPIRES;
            }

            // Re-Register or emit an event before the expiration interval has elapsed.
            // For that, decrease the expires value. ie: 3 seconds.
            _registrationTimer = setTimeout(() {
              clearTimeout(_registrationTimer);
              _registrationTimer = null;
              // If there are no listeners for registrationExpiring, reregistration.
              // If there are listeners, var the listening do the register call.
              if (!_ua.hasListeners(EventRegistrationExpiring())) {
                register();
              } else {
                _ua.emit(EventRegistrationExpiring());
              }
            }, (expires * 1000) - 5000);

            // Save gruu values.
            if (contact.hasParam('temp-gruu')) {
              _ua.contact?.temp_gruu =
                  contact.getParam('temp-gruu').replaceAll('"', '');
            }
            if (contact.hasParam('pub-gruu')) {
              _ua.contact?.pub_gruu =
                  contact.getParam('pub-gruu').replaceAll('"', '');
            }

            if (!_registered) {
              _registered = true;
              _ua.registered(response: event.response);
            }
          } // Interval too brief RFC3261 10.2.8.
          else if (true == status_code.contains(RegExp(r'^423$'))) {
            if (true == event.response?.hasHeader('min-expires')) {
              // Increase our registration interval to the suggested minimum.
              _expires = num.tryParse(event.response?.getHeader('min-expires'))
                      ?.toInt() ??
                  0;

              if (_expires < MIN_REGISTER_EXPIRES)
                _expires = MIN_REGISTER_EXPIRES;

              // Attempt the registration again immediately.
              register();
            } else {
              // This response MUST contain a Min-Expires header field.
              logger.debug(
                  '423 response received for REGISTER without Min-Expires');

              _registrationFailure(
                  event.response, DartSIP_C.causes.SIP_FAILURE_CODE);
            }
          }
        } else {
          String cause = utils.sipErrorCause(event.response?.status_code);
          _registrationFailure(event.response, cause);
        }
      }
    });

    RequestSender request_sender = RequestSender(_ua, request, handlers);

    _registering = true;
    request_sender.send();
  }

  void unregister(bool unregister_all) {
    if (_registered == null) {
      logger.debug('already unregistered');

      return;
    }

    _registered = false;

    // Clear the registration timer.
    if (_registrationTimer != null) {
      clearTimeout(_registrationTimer);
      _registrationTimer = null;
    }

    List<dynamic> extraHeaders = List<dynamic>.from(_extraHeaders);

    if (unregister_all) {
      extraHeaders.add('Contact: *$_extraContactParams');
    } else {
      extraHeaders.add('Contact: $_contact;expires=0$_extraContactParams');
    }

    extraHeaders.add('Expires: 0');

    OutgoingRequest request = OutgoingRequest(
        SipMethod.REGISTER,
        _registrar,
        _ua,
        <String, dynamic>{
          'to_uri': _to_uri,
          'call_id': _call_id,
          'cseq': _cseq += 1
        },
        extraHeaders);

    EventManager handlers = EventManager();
    handlers.on(EventOnRequestTimeout(), (EventOnRequestTimeout value) {
      _unregistered(null, DartSIP_C.causes.REQUEST_TIMEOUT);
    });
    handlers.on(EventOnTransportError(), (EventOnTransportError value) {
      _unregistered(null, DartSIP_C.causes.CONNECTION_ERROR);
    });
    handlers.on(EventOnAuthenticated(), (EventOnAuthenticated response) {
      // Increase the CSeq on authentication.

      _cseq += 1;
    });
    handlers.on(EventOnReceiveResponse(), (EventOnReceiveResponse event) {
      String? status_code = event.response?.status_code.toString();
      if (status_code != null) {
        if (utils.test2XX(status_code)) {
          _unregistered(event.response);
        } else if (utils.test1XX(status_code)) {
          // Ignore provisional responses.
        }
      }

      String cause = utils.sipErrorCause(event.response?.status_code);
      _unregistered(event.response, cause);
    });

    RequestSender request_sender = RequestSender(_ua, request, handlers);

    request_sender.send();
  }

  void close() {
    if (_registered) {
      unregister(false);
    }
  }

  void onTransportClosed() {
    _registering = false;
    if (_registrationTimer != null) {
      clearTimeout(_registrationTimer);
      _registrationTimer = null;
    }

    if (_registered) {
      _registered = false;
      _ua.unregistered();
    }
  }

  void _registrationFailure(dynamic response, String cause) {
    _registering = false;
    _ua.registrationFailed(response: response, cause: cause);

    if (_registered) {
      _registered = false;
      _ua.unregistered(response: response, cause: cause);
    }
  }

  void _unregistered([dynamic response, String? cause]) {
    _registering = false;
    _registered = false;
    _ua.unregistered(response: response, cause: cause);
  }
}
