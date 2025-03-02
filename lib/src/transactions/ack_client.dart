import 'package:sip_ua/src/sip_message.dart';

import '../event_manager/event_manager.dart';
import '../event_manager/internal_events.dart';
import '../logger.dart';
import '../transport.dart';
import '../ua.dart';
import '../utils.dart';
import 'transaction_base.dart';

class AckClientTransaction extends TransactionBase {
  AckClientTransaction(
      UA ua, Transport transport, OutgoingRequest request, this._eventHandlers)
      : super(ua: ua, transport: transport, request: request) {
    id = 'z9hG4bK${Math.floor(Math.random() * 10000000)}';

    String via = 'SIP/2.0/${transport.via_transport}';

    via += ' ${ua.configuration.via_host};branch=$id';

    request.setHeader('via', via);
  }

  final EventManager _eventHandlers;

  @override
  void send() {
    if (true != transport.send(request)) {
      onTransportError();
    }
  }

  @override
  void onTransportError() {
    logger.debug('transport error occurred for transaction $id');
    _eventHandlers.emit(EventOnTransportError());
  }
}
