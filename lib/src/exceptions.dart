import 'utils.dart';

class ErrorImpl extends Error {
  ErrorImpl({
    required this.code,
    required this.name,
    this.parameter,
    required this.message,
  });

  int code;
  String name;
  String? parameter;
  dynamic value;
  String message;
  dynamic status;
}

class ConfigurationError extends ErrorImpl {
  ConfigurationError(String parameter, [dynamic value])
      : super(
            code: 1,
            name: 'CONFIGURATION_ERROR',
            parameter: parameter,
            message: (value == null)
                ? 'Missing parameter: $parameter'
                : 'Invalid value ${encoder.convert(value)} for parameter "$parameter"') {
    this.value = value;
  }
}

class InvalidStateError extends ErrorImpl {
  InvalidStateError(dynamic status)
      : super(
            code: 2,
            name: 'INVALID_STATE_ERROR',
            message: 'Invalid status: ${status.toString()}') {
    this.status = status;
    ;
  }
}

class NotSupportedError extends ErrorImpl {
  NotSupportedError(String message)
      : super(code: 3, name: 'NOT_SUPPORTED_ERROR', message: message);
}

class NotReadyError extends ErrorImpl {
  NotReadyError(String message)
      : super(code: 4, name: 'NOT_READY_ERROR', message: message);
}

class TypeError extends AssertionError {
  TypeError(String message) : super(message);
}
