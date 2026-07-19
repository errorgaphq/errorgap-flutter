class ErrorgapSpan {
  ErrorgapSpan({
    required this.kind,
    required this.durationMs,
    this.sql,
    this.file,
    this.line,
    this.function,
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

  Map<String, Object?> toJson() => <String, Object?>{
        'kind': kind,
        if (sql != null) 'sql': sql,
        if (file != null) 'file': file,
        if (line != null) 'line': line,
        if (function != null) 'fn_name': function,
        'duration_ms': durationMs,
      };
}

class ErrorgapTransaction {
  ErrorgapTransaction({
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
  })  : occurredAt = occurredAt ?? DateTime.now().toUtc(),
        spans = spans ?? <ErrorgapSpan>[];

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

  List<ErrorgapSpan> snapshot() => List<ErrorgapSpan>.unmodifiable(_spans);
}

String normalizeSql(String sql) => sql
    .replaceAll(RegExp(r"'(?:''|[^'])*'"), '?')
    .replaceAll(RegExp(r'\b\d+(?:\.\d+)?\b'), '?')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();
