/// Flutter / Dart notifier for [Errorgap](https://errorgap.com).
///
/// Wire into a Flutter app from `main`:
///
/// ```dart
/// void main() {
///   Errorgap.init(ErrorgapConfiguration(
///     endpoint: '...',
///     projectSlug: '...',
///     apiKey: '...',
///   ));
///
///   FlutterError.onError = (FlutterErrorDetails details) {
///     Errorgap.notify(details.exception, stackTrace: details.stack);
///   };
///   PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
///     Errorgap.notify(error, stackTrace: stack);
///     return true;
///   };
///
///   runApp(const MyApp());
/// }
/// ```
library errorgap;

import 'dart:async';

import 'src/apm.dart';
import 'src/client.dart';
import 'src/configuration.dart';
import 'src/logger.dart';
import 'src/notice.dart';
import 'src/platform_environment.dart';
import 'src/replay.dart';

export 'src/apm.dart'
    show
        ErrorgapSpan,
        ErrorgapSpanCollector,
        ErrorgapTracedCall,
        ErrorgapTransaction,
        errorgapTraceHeader,
        normalizeSql;
export 'src/client.dart'
    show DeliveryResult, ErrorgapClient, RateLimitedException;
export 'src/configuration.dart' show BeforeNotify, ErrorgapConfiguration;
export 'src/logger.dart' show ErrorgapLogger;
export 'src/notice.dart' show ErrorgapCausedBy, NoticeOptions;
export 'src/replay.dart' show ErrorgapHttpClient, ErrorgapReplayOptions;
export 'src/transaction_context.dart'
    show
        currentErrorgapTransactionId,
        newErrorgapTransactionId,
        withErrorgapTransaction;
export 'src/version.dart' show errorgapVersion;

class Errorgap {
  Errorgap._();

  static ErrorgapClient? _client;
  static ErrorgapReplayRecorder? _replay;

  /// Initialize the singleton client. Calling `init` a second time replaces
  /// the existing client (and disposes the previous one in the background).
  ///
  /// Session replay (a timeline of the app session, no screenshots) is on by
  /// default in iOS and Android apps and records only what the project's
  /// replay settings allow (Settings → Session replay). Pass `replay: false`
  /// to turn it off, or `replay: true` to record outside mobile.
  static void init(
    ErrorgapConfiguration configuration, {
    bool? replay,
    ErrorgapReplayOptions replayOptions = const ErrorgapReplayOptions(),
  }) {
    configuration.validate();
    final previous = _client;
    _replay?.stop();
    _replay = null;
    final client = ErrorgapClient(configuration);
    _client = client;
    if (replay ?? isMobilePlatform()) {
      final recorder = ErrorgapReplayRecorder(
          configuration, client.httpClient, replayOptions);
      _replay = recorder;
      client.observeErrors(recorder.errorStarted);
      recorder.start();
    }
    ErrorgapHttpClient.currentRecorder = () => _replay;
    if (previous != null) {
      // ignore: unawaited_futures
      previous.shutdown();
    }
  }

  /// Record the screen now showing in the session replay timeline. Call it
  /// from a `NavigatorObserver` (see the README).
  static void trackScreen(String name) => _replay?.screen(name);

  /// The app went to the background (`AppLifecycleListener.onHide`): ends the
  /// replay batch, and after 30 minutes away the next session starts.
  static void appPaused() => _replay?.paused();

  /// The app is in the foreground again (`AppLifecycleListener.onShow`).
  static void appResumed() => _replay?.resumed();

  static ErrorgapConfiguration? get configuration => _client?.configuration;
  static ErrorgapClient? get client => _client;

  static Future<DeliveryResult> notify(
    Object error, {
    Object? stackTrace,
    Map<String, Object?>? context,
    Map<String, Object?>? environment,
    Map<String, Object?>? session,
    Map<String, Object?>? params,
    bool? isFatal,
    bool sync = false,
  }) {
    final c = _client;
    if (c == null) {
      return Future<DeliveryResult>.value(
        DeliveryResult(error: StateError('Errorgap not initialized')),
      );
    }
    return c.notify(
      error,
      options: NoticeOptions(
        context: context,
        environment: environment,
        session: session,
        params: params,
        stackTrace: stackTrace,
        isFatal: isFatal,
      ),
      sync: sync,
    );
  }

  static Future<DeliveryResult> notifyTransaction(
    ErrorgapTransaction transaction, {
    bool sync = false,
  }) {
    final c = _client;
    if (c == null) return _notInitialized();
    return c.notifyTransaction(transaction, sync: sync);
  }

  static Future<DeliveryResult> notifyLog(
    String message, {
    String level = 'info',
    String? source,
    bool sync = false,
  }) {
    final c = _client;
    if (c == null) return _notInitialized();
    return c.notifyLog(message, level: level, source: source, sync: sync);
  }

  static ErrorgapLogger? logger({String? source}) {
    final c = _client;
    return c == null ? null : ErrorgapLogger(c, source: source);
  }

  static Future<T> trackJob<T>(
    String jobClass,
    FutureOr<T> Function(ErrorgapSpanCollector collector) operation, {
    String queue = 'default',
  }) {
    final c = _client;
    if (c == null) {
      return Future<T>.error(StateError('Errorgap not initialized'));
    }
    return c.trackJob(jobClass, operation, queue: queue);
  }

  static Future<void> flush({Duration timeout = const Duration(seconds: 5)}) {
    return _client?.flush(timeout: timeout) ?? Future<void>.value();
  }

  static Future<void> shutdown(
      {Duration timeout = const Duration(seconds: 5)}) {
    final c = _client;
    _client = null;
    _replay?.stop();
    _replay = null;
    return c?.shutdown(timeout: timeout) ?? Future<void>.value();
  }

  static Future<DeliveryResult> _notInitialized() =>
      Future<DeliveryResult>.value(
        DeliveryResult(error: StateError('Errorgap not initialized')),
      );
}
