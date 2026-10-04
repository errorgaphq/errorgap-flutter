import 'dart:async';

import 'transaction_context.dart';

class ErrorgapSpan {
  ErrorgapSpan({
    required this.kind,
    required this.durationMs,
    this.sql,
    this.file,
    this.line,
    this.function,
    this.traceId,
  });

  factory ErrorgapSpan.database(
    String sql, {
    required double durationMs,
    String? file,
    int? line,
    String? function,
  }) =>
      ErrorgapSpan(
        kind: 'db',
        sql: normalizeSql(sql),
        file: file,
        line: line,
        function: function,
        durationMs: durationMs,
      );

  factory ErrorgapSpan.external({
    required double durationMs,
    String? file,
    int? line,
    String? function,
  }) =>
      ErrorgapSpan(
        kind: 'http',
        file: file,
        line: line,
        function: function,
        durationMs: durationMs,
      );

  final String kind;
  final String? sql;
  final String? file;
  final int? line;
  final String? function;
  final double durationMs;

  /// For a traced `http` call: the id sent in its `x-errorgap-trace` header.
  /// The server request that recorded the header links to it.
  final String? traceId;

  Map<String, Object?> toJson() => <String, Object?>{
        'kind': kind,
        if (sql != null) 'sql': sql,
        if (file != null) 'file': file,
        if (line != null) 'line': line,
        if (function != null) 'fn_name': function,
        if (traceId != null) 'trace_id': traceId,
        'duration_ms': durationMs,
      };
}

class ErrorgapTransaction {
  ErrorgapTransaction({
    String? id,
    this.kind = 'web',
    this.method,
    this.path,
    this.pathRaw,
    this.statusCode,
    required this.durationMs,
    this.environment,
    DateTime? occurredAt,
    List<ErrorgapSpan>? spans,
    this.jobClass,
    this.queue,
  })  : id = id ?? newErrorgapTransactionId(),
        occurredAt = occurredAt ?? DateTime.now().toUtc(),
        spans = spans ?? <ErrorgapSpan>[];

  /// Links errors raised during this transaction to it; see
  /// [withErrorgapTransaction].
  final String id;
  final String kind;
  final String? method;
  final String? path;
  final String? pathRaw;
  final int? statusCode;
  final double durationMs;
  final String? environment;
  final DateTime occurredAt;
  final List<ErrorgapSpan> spans;
  final String? jobClass;
  final String? queue;

  Map<String, Object?> toJson(String defaultEnvironment) => <String, Object?>{
        'id': id,
        'kind': kind,
        if (method != null) 'method': method,
        if (path != null) 'path': path,
        if (pathRaw != null) 'path_raw': pathRaw,
        if (statusCode != null) 'status_code': statusCode,
        'duration_ms': durationMs,
        'environment': environment ?? defaultEnvironment,
        'occurred_at': occurredAt.toUtc().toIso8601String(),
        'spans': spans.map((span) => span.toJson()).toList(growable: false),
        if (jobClass != null) 'job_class': jobClass,
        if (queue != null) 'queue': queue,
      };
}

class ErrorgapSpanCollector {
  final List<ErrorgapSpan> _spans = <ErrorgapSpan>[];

  void add(ErrorgapSpan span) => _spans.add(span);

  void database(
    String sql, {
    required double durationMs,
    String? file,
    int? line,
    String? function,
  }) {
    add(ErrorgapSpan.database(
      sql,
      durationMs: durationMs,
      file: file,
      line: line,
      function: function,
    ));
  }

  void external({
    required double durationMs,
    String? file,
    int? line,
    String? function,
  }) {
    add(ErrorgapSpan.external(
      durationMs: durationMs,
      file: file,
      line: line,
      function: function,
    ));
  }

  /// Start a traced API call. Send [ErrorgapTracedCall.headers] with the
  /// request and call [ErrorgapTracedCall.finish] when the response arrives:
  /// the `http` span records the trace id, and a server SDK that records the
  /// header links the server request to it.
  ErrorgapTracedCall startCall(String label) =>
      ErrorgapTracedCall._(label, this);

  /// Time a traced API call: [operation] gets the headers to send and its
  /// result is returned. The span is recorded even if it throws.
  ///
  /// ```dart
  /// final response = await spans.traceCall('GET /api/orders/7',
  ///     (headers) => http.get(ordersUri, headers: headers));
  /// ```
  Future<T> traceCall<T>(
    String label,
    FutureOr<T> Function(Map<String, String> headers) operation,
  ) async {
    final call = startCall(label);
    try {
      return await operation(call.headers);
    } finally {
      call.finish();
    }
  }

  List<ErrorgapSpan> snapshot() => List<ErrorgapSpan>.unmodifiable(_spans);
}

/// The header that links an API call to the server request answering it.
const String errorgapTraceHeader = 'x-errorgap-trace';

/// A traced outbound call in flight; see [ErrorgapSpanCollector.startCall].
class ErrorgapTracedCall {
  ErrorgapTracedCall._(this._label, this._collector)
      : traceId = newErrorgapTransactionId() {
    headers = Map<String, String>.unmodifiable(
        <String, String>{errorgapTraceHeader: traceId});
  }

  /// The id sent with the call.
  final String traceId;

  /// Headers to add to the request: `x-errorgap-trace: traceId`.
  late final Map<String, String> headers;

  final String _label;
  final ErrorgapSpanCollector _collector;
  final Stopwatch _stopwatch = Stopwatch()..start();
  bool _finished = false;

  /// Record the call's span, timed from [ErrorgapSpanCollector.startCall].
  /// Idempotent.
  void finish() {
    if (_finished) return;
    _finished = true;
    _stopwatch.stop();
    _collector.add(ErrorgapSpan(
      kind: 'http',
      function: _label,
      durationMs: _stopwatch.elapsedMicroseconds / 1000.0,
      traceId: traceId,
    ));
  }
}

String normalizeSql(String sql) => sql
    .replaceAll(RegExp(r"'(?:''|[^'])*'"), '?')
    .replaceAll(RegExp(r'\b\d+(?:\.\d+)?\b'), '?')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();
