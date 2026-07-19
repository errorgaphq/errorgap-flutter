import 'client.dart';

/// Lightweight structured logger that forwards entries through Errorgap.
class ErrorgapLogger {
  ErrorgapLogger(this._client, {this.source});

  final ErrorgapClient _client;
  final String? source;

  Future<DeliveryResult> log(
    String message, {
    String level = 'info',
    bool sync = false,
  }) =>
      _client.notifyLog(message, level: level, source: source, sync: sync);

  Future<DeliveryResult> trace(String message, {bool sync = false}) =>
      log(message, level: 'trace', sync: sync);

  Future<DeliveryResult> debug(String message, {bool sync = false}) =>
      log(message, level: 'debug', sync: sync);

  Future<DeliveryResult> info(String message, {bool sync = false}) =>
      log(message, sync: sync);

  Future<DeliveryResult> warning(String message, {bool sync = false}) =>
      log(message, level: 'warn', sync: sync);

  Future<DeliveryResult> error(String message, {bool sync = false}) =>
      log(message, level: 'error', sync: sync);

  Future<DeliveryResult> fatal(String message, {bool sync = false}) =>
      log(message, level: 'fatal', sync: sync);
}
