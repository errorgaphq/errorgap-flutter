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
      expect(req.headers['user-agent']!.startsWith('errorgap-flutter/'), isTrue);

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
  });
}
