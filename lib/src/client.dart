import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import 'apm.dart';
import 'configuration.dart';
import 'notice.dart';
import 'version.dart';

class DeliveryResult {
  DeliveryResult({this.status, this.body, this.error, this.queued = false});

  final int? status;
  final String? body;
  final Object? error;
  final bool queued;

  bool get success =>
      error == null && status != null && status! >= 200 && status! < 300;
}

class _PendingDelivery {
  _PendingDelivery(this.resource, this.payload);

  final String resource;
  final Map<String, Object?> payload;
}

class ErrorgapClient {
  ErrorgapClient(this._configuration, {http.Client? httpClient})
      : _http = httpClient ?? http.Client() {
    _worker = _loop();
  }

  ErrorgapConfiguration _configuration;
  final http.Client _http;
  final Queue<_PendingDelivery> _queue = Queue<_PendingDelivery>();
  final Completer<void> _shutdown = Completer<void>();
  late final Future<void> _worker;
  int _inFlight = 0;

  ErrorgapConfiguration get configuration => _configuration;

  void configure(ErrorgapConfiguration configuration) {
    _configuration = configuration;
  }

  Future<DeliveryResult> notify(
    Object error, {
    NoticeOptions? options,
    bool sync = false,
  }) async {
    final validation = _validate();
    if (validation != null) return validation;
    if (_configuration.isIgnoredEnvironment) return _ignored();

    final notice = buildNotice(
      error,
      _configuration,
      options ?? NoticeOptions(),
    );
    return _submit('notices', notice, sync: sync);
  }

  Future<DeliveryResult> notifyTransaction(
    ErrorgapTransaction transaction, {
    bool sync = false,
  }) async {
    final validation = _validate();
    if (validation != null) return validation;
    if (_configuration.isIgnoredEnvironment || !_configuration.apmEnabled) {
      return _ignored(status: 204);
    }
    final rate = _configuration.apmSampleRate;
    if (rate <= 0 || (rate < 1 && Random().nextDouble() >= rate)) {
      return _ignored(status: 204);
    }
    return _submit(
      'transactions',
      transaction.toJson(_configuration.environment),
      sync: sync,
    );
  }

  Future<DeliveryResult> notifyLog(
    String message, {
    String level = 'info',
    String? source,
    bool sync = false,
  }) async {
    final validation = _validate();
    if (validation != null) return validation;
    final normalizedLevel = normalizeLogLevel(level);
    if (_configuration.isIgnoredEnvironment ||
        !_configuration.logsEnabled ||
        logLevelRank(normalizedLevel) <
            logLevelRank(normalizeLogLevel(_configuration.minimumLogLevel))) {
      return _ignored(status: 204);
    }
    return _submit(
      'logs',
      <String, Object?>{
        'message': message,
        'level': normalizedLevel,
        if (source != null && source.isNotEmpty) 'source': source,
        'environment': _configuration.environment,
        'occurred_at': DateTime.now().toUtc().toIso8601String(),
      },
      sync: sync,
    );
  }

  Future<T> trackJob<T>(
    String jobClass,
    FutureOr<T> Function(ErrorgapSpanCollector collector) operation, {
    String queue = 'default',
  }) async {
    final occurredAt = DateTime.now().toUtc();
    final stopwatch = Stopwatch()..start();
    final collector = ErrorgapSpanCollector();
    try {
      final value = await Future<T>.sync(() => operation(collector));
      stopwatch.stop();
      await notifyTransaction(ErrorgapTransaction(
        kind: 'job',
        statusCode: 200,
        durationMs: stopwatch.elapsedMicroseconds / 1000,
        occurredAt: occurredAt,
        spans: collector.snapshot(),
        jobClass: jobClass,
        queue: queue,
      ));
      return value;
    } catch (error, stackTrace) {
      stopwatch.stop();
      await notify(
        error,
        options: NoticeOptions(
          stackTrace: stackTrace,
          context: <String, Object?>{
            'source': 'errorgap-flutter job',
            'component': 'dart.job',
            'action': jobClass,
          },
          environment: <String, Object?>{'queue': queue},
        ),
      );
      await notifyTransaction(ErrorgapTransaction(
        kind: 'job',
        statusCode: 500,
        durationMs: stopwatch.elapsedMicroseconds / 1000,
        occurredAt: occurredAt,
        spans: collector.snapshot(),
        jobClass: jobClass,
        queue: queue,
      ));
      rethrow;
    }
  }

  Future<void> flush({Duration timeout = const Duration(seconds: 5)}) async {
    final deadline = DateTime.now().add(timeout);
    while ((_queue.isNotEmpty || _inFlight > 0) &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  Future<void> shutdown({Duration timeout = const Duration(seconds: 5)}) async {
    await flush(timeout: timeout);
    if (!_shutdown.isCompleted) _shutdown.complete();
    await _worker;
    _http.close();
  }

  DeliveryResult? _validate() {
    try {
      _configuration.validate();
      return null;
    } catch (error) {
      return DeliveryResult(error: error);
    }
  }

  DeliveryResult _ignored({int status = 202}) => DeliveryResult(
        status: status,
        body: 'ignored environment or disabled telemetry',
      );

  Future<DeliveryResult> _submit(
    String resource,
    Map<String, Object?> payload, {
    required bool sync,
  }) {
    if (sync || !_configuration.async) {
      return _deliver(_PendingDelivery(resource, payload));
    }
    if (_queue.length >= _configuration.queueSize) {
      return Future<DeliveryResult>.value(
        DeliveryResult(error: StateError('queue full')),
      );
    }
    _queue.add(_PendingDelivery(resource, payload));
    return Future<DeliveryResult>.value(
      DeliveryResult(status: 202, queued: true),
    );
  }

  Future<void> _loop() async {
    while (!_shutdown.isCompleted) {
      if (_queue.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        continue;
      }
      final pending = _queue.removeFirst();
      _inFlight++;
      try {
        await _deliver(pending);
      } finally {
        _inFlight--;
      }
    }
  }

  Future<DeliveryResult> _deliver(_PendingDelivery pending) async {
    final base = _configuration.endpoint.endsWith('/')
        ? _configuration.endpoint
            .substring(0, _configuration.endpoint.length - 1)
        : _configuration.endpoint;
    final uri = Uri.parse(
      '$base/api/projects/${_configuration.projectSlug}/${pending.resource}',
    );

    final headers = <String, String>{
      'content-type': 'application/json',
      'user-agent': 'errorgap-flutter/$errorgapVersion',
    };
    final apiKey = _configuration.apiKey;
    if (apiKey != null && apiKey.isNotEmpty) {
      headers['x-errorgap-project-key'] = apiKey;
    }

    try {
      final response = await _http
          .post(uri, headers: headers, body: jsonEncode(pending.payload))
          .timeout(Duration(seconds: _configuration.timeoutSeconds));
      return DeliveryResult(status: response.statusCode, body: response.body);
    } catch (error) {
      return DeliveryResult(error: error);
    }
  }
}

String normalizeLogLevel(String level) {
  final normalized = level.trim().toLowerCase();
  switch (normalized) {
    case 'warning':
    case 'warn':
      return 'warn';
    case 'err':
    case 'severe':
      return 'error';
    case 'fine':
    case 'finer':
    case 'finest':
      return 'debug';
    case 'trace':
    case 'debug':
    case 'info':
    case 'error':
    case 'fatal':
      return normalized;
    default:
      return 'info';
  }
}

int logLevelRank(String level) {
  switch (level) {
    case 'trace':
      return 0;
    case 'debug':
      return 10;
    case 'info':
      return 20;
    case 'warn':
      return 30;
    case 'error':
      return 40;
    case 'fatal':
      return 50;
    default:
      return 20;
  }
}
