import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../rtc_session.dart' show RTCSession;
import '../rtc_session/dtmf.dart';
import '../rtc_session/info.dart';
import '../sip_message.dart';
import '../transactions/transaction_base.dart';
import 'events.dart';

typedef InitSuccessCallback = bool Function(RTCSession);

class EventStateChanged extends EventType {}

class EventNewTransaction extends EventType {
  EventNewTransaction({required this.transaction});
  TransactionBase transaction;
}

class EventTransactionDestroyed extends EventType {
  EventTransactionDestroyed({required this.transaction});
  TransactionBase transaction;
}

class EventSipEvent extends EventType {
  EventSipEvent({required this.request});
  IncomingRequest request;
}

class EventOnAuthenticated extends EventType {
  EventOnAuthenticated({this.request});
  OutgoingRequest? request;
}

class EventSdp extends EventType {
  EventSdp({required this.originator, required this.type, this.sdp});
  String originator;
  String type;
  String? sdp;
}

class EventSending extends EventType {
  EventSending({required this.request});
  OutgoingRequest request;
}

class EventSetRemoteDescriptionFailed extends EventType {
  EventSetRemoteDescriptionFailed({this.exception});
  dynamic exception;
}

class EventSetLocalDescriptionFailed extends EventType {
  EventSetLocalDescriptionFailed({this.exception});
  dynamic exception;
}

class EventFailedUnderScore extends EventType {
  EventFailedUnderScore({this.originator, this.cause});
  String? originator;
  ErrorCause? cause;
}

class EventGetUserMediaFailed extends EventType {
  EventGetUserMediaFailed({this.exception});
  dynamic exception;
}

class EventNewDTMF extends EventType {
  EventNewDTMF({required this.originator, this.request, required this.dtmf});
  String originator;
  dynamic request;
  DTMF dtmf;
}

class EventNewInfo extends EventType {
  EventNewInfo({required this.originator, this.request, required this.info});
  String originator;
  dynamic request;
  Info info;
}

class EventPeerConnection extends EventType {
  EventPeerConnection(this.peerConnection);
  RTCPeerConnection peerConnection;
}

class EventReplaces extends EventType {
  EventReplaces({this.request, required this.accept, required this.reject});
  dynamic request;
  void Function(InitSuccessCallback) accept;
  void Function() reject;
}

class EventUpdate extends EventType {
  EventUpdate({this.request, required this.callback, required this.reject});
  dynamic request;
  bool Function(Map<String, dynamic> options)? callback;
  bool Function(Map<String, dynamic> options) reject;
}

class EventReinvite extends EventType {
  EventReinvite({this.request, required this.callback, required this.reject});
  dynamic request;
  bool Function(Map<String, dynamic> options)? callback;
  bool Function(Map<String, dynamic> options) reject;
}

class EventIceCandidate extends EventType {
  EventIceCandidate(this.candidate, this.ready);
  RTCIceCandidate candidate;
  Future<Null> Function() ready;
}

class EventCreateAnswerFialed extends EventType {
  EventCreateAnswerFialed({this.exception});
  dynamic exception;
}

class EventCreateOfferFailed extends EventType {
  EventCreateOfferFailed({this.exception});
  dynamic exception;
}

class EventOnFialed extends EventType {}

class EventSucceeded extends EventType {
  EventSucceeded({this.response, this.originator});
  String? originator;
  IncomingMessage? response;
}

class EventOnTransportError extends EventType {
  EventOnTransportError() : super();
}

class EventOnRequestTimeout extends EventType {
  EventOnRequestTimeout({this.request});
  IncomingMessage? request;
}

class EventOnReceiveResponse extends EventType {
  EventOnReceiveResponse({this.response});
  IncomingMessage? response;

  @override
  void sanityCheck() {}
}

class EventOnDialogError extends EventType {
  EventOnDialogError({this.response});
  IncomingMessage? response;
}

class EventOnSuccessResponse extends EventType {
  EventOnSuccessResponse({this.response});
  IncomingMessage? response;
}

class EventOnErrorResponse extends EventType {
  EventOnErrorResponse({this.response});
  IncomingMessage? response;
}
