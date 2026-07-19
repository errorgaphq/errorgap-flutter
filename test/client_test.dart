import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:errorgap/errorgap.dart';
import 'package:test/test.dart';

class CapturedRequest {
  CapturedRequest({
    required this.method,
    required this.path,
    required this.headers,
    required this.body,
  });

  final String method;
  final String path;
  final Map<String, String> headers;
  final Map<String, Object?>? body;
}

class FakeIngestor {
  FakeIngestor._(this._server);

  final HttpServer _server;
  final List<CapturedRequest> requests = <CapturedRequest>[];

  static Future<FakeIngestor> start({int status = 201}) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final ingestor = FakeIngestor._(server);
    server.listen((HttpRequest request) async {
      final raw = await utf8.decoder.bind(request).join();
      Map<String, Object?>? decoded;
      try {
        decoded = jsonDecode(raw) as Map<String, Object?>;
      } catch (_) {
        decoded = null;
      }
      final headers = <String, String>{};
      request.headers.forEach((String name, List<String> values) {
        if (values.isNotEmpty) headers[name.toLowerCase()] = values.first;
      });
      ingestor.requests.add(CapturedRequest(
        method: request.method,
        path: request.uri.path,
        headers: headers,
        body: decoded,
      ));
      request.response.statusCode = status;
      request.response.headers.set('content-type', 'application/json');
      request.response.write('{"group_id":"g_1"}');
      await request.response.close();
    });
    return ingestor;
  }

  String get endpoint => 'http://127.0.0.1:${_server.port}';

  Future<void> close() async {
    await _server.close(force: true);
  }
}

void main() {
  group('ErrorgapClient', () {
    late FakeIngestor ingestor;

    setUp(() async {
      ingestor = await FakeIngestor.start();
    });

    tearDown(() async {
      await ingestor.close();
    });

    test('posts to /api/projects/:slug/notices with canonical headers',
        () async {
      final cfg = ErrorgapConfiguration(
        endpoint: ingestor.endpoint,
        projectSlug: 'demo',
        apiKey: 'flk_test',
        async: false,
      );
      final client = ErrorgapClient(cfg);
      final result = await client.notify(StateError('test'));
      expect(result.success, isTrue);

      expect(ingestor.requests.length, 1);
      final req = ingestor.requests.first;
      expect(req.method, 'POST');
      expect(req.path, '/api/projects/demo/notices');
      expect(req.headers['x-errorgap-project-key'], 'flk_test');
      expect(
          req.headers['user-agent']!.startsWith('errorgap-flutter/'), isTrue);

      await client.shutdown();
    });

    test('async queues and flushes', () async {
      final cfg = ErrorgapConfiguration(
        endpoint: ingestor.endpoint,
        projectSlug: 'demo',
        apiKey: 'flk_test',
      );
      final client = ErrorgapClient(cfg);
      final result = await client.notify(StateError('x'));
      expect(result.queued, isTrue);
      expect(result.status, 202);
      await client.flush();
      expect(ingestor.requests.length, 1);
      await client.shutdown();
    });

    test('rejects missing projectSlug', () async {
      final cfg = ErrorgapConfiguration(endpoint: ingestor.endpoint);
      final client = ErrorgapClient(cfg);
      final result = await client.notify(StateError('x'));
      expect(result.error, isNotNull);
      expect(ingestor.requests, isEmpty);
      await client.shutdown();
    });

    test('posts APM transactions and normalized query spans', () async {
      final cfg = ErrorgapConfiguration(
        endpoint: ingestor.endpoint,
        projectSlug: 'demo',
        apiKey: 'flk_test',
        async: false,
        apmEnabled: true,
        environment: 'production',
      );
      final client = ErrorgapClient(cfg);
      final result = await client.notifyTransaction(ErrorgapTransaction(
        method: 'POST',
        path: '/checkout/{orderId}',
        pathRaw: '/checkout/42',
        statusCode: 201,
        durationMs: 125,
        spans: <ErrorgapSpan>[
          ErrorgapSpan.database(
            "SELECT * FROM orders WHERE id = 42 AND state = 'paid'",
            durationMs: 12,
            file: 'lib/checkout.dart',
            line: 30,
            function: 'Checkout.load',
          ),
        ],
      ));

      expect(result.success, isTrue);
      final request = ingestor.requests.single;
      expect(request.path, '/api/projects/demo/transactions');
      expect(request.body!['environment'], 'production');
      final spans = request.body!['spans']! as List<Object?>;
      final span = spans.single! as Map<String, Object?>;
      expect(
        span['sql'],
        'SELECT * FROM orders WHERE id = ? AND state = ?',
      );
      expect(span['fn_name'], 'Checkout.load');
      await client.shutdown();
    });

    test('forwards logs at or above the configured level', () async {
      final cfg = ErrorgapConfiguration(
        endpoint: ingestor.endpoint,
        projectSlug: 'demo',
        async: false,
        logsEnabled: true,
        minimumLogLevel: 'warn',
      );
      final client = ErrorgapClient(cfg);
      final logger = ErrorgapLogger(client, source: 'flutter.checkout');

      final ignored = await logger.debug('not sent');
      expect(ignored.status, 204);
      final delivered = await logger.warning('gateway timeout');
      expect(delivered.success, isTrue);

      final request = ingestor.requests.single;
      expect(request.path, '/api/projects/demo/logs');
      expect(request.body!['level'], 'warn');
      expect(request.body!['source'], 'flutter.checkout');
      expect(request.body!['message'], 'gateway timeout');
      await client.shutdown();
    });

    test('drops all telemetry in ignored environments', () async {
      final cfg = ErrorgapConfiguration(
        endpoint: ingestor.endpoint,
        projectSlug: 'demo',
        environment: 'test',
        ignoreEnvironments: <String>['test'],
        async: false,
        apmEnabled: true,
        logsEnabled: true,
      );
      final client = ErrorgapClient(cfg);
      expect((await client.notify(StateError('ignored'))).status, 202);
      expect(
        (await client.notifyTransaction(
          ErrorgapTransaction(durationMs: 1),
        ))
            .status,
        204,
      );
      expect((await client.notifyLog('ignored')).status, 204);
      expect(ingestor.requests, isEmpty);
      await client.shutdown();
    });

    test('reports failed jobs with spans and rethrows', () async {
      final cfg = ErrorgapConfiguration(
        endpoint: ingestor.endpoint,
        projectSlug: 'demo',
        async: false,
        apmEnabled: true,
      );
      final client = ErrorgapClient(cfg);

      await expectLater(
        client.trackJob<void>('ReceiptJob', (collector) {
          collector.database(
            "SELECT 1 FROM receipts WHERE id = 'abc'",
            durationMs: 8,
            file: 'lib/jobs.dart',
            line: 12,
            function: 'ReceiptJob.run',
          );
          throw StateError('receipt failed');
        }),
        throwsA(isA<StateError>()),
      );

      expect(
        ingestor.requests.map((request) => request.path),
        <String>[
          '/api/projects/demo/notices',
          '/api/projects/demo/transactions',
        ],
      );
      final transaction = ingestor.requests.last.body!;
      expect(transaction['kind'], 'job');
      expect(transaction['job_class'], 'ReceiptJob');
      expect(transaction['status_code'], 500);
      expect(transaction['spans'], isNotEmpty);
      await client.shutdown();
    });
  });
}
