import 'dart:convert';
import 'dart:io';

import 'package:errorgap/errorgap.dart';
import 'package:test/test.dart';

/// Answers every request with [status], recording each body.
Future<(HttpServer, List<Map<String, Object?>>)> stub(int status) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final bodies = <Map<String, Object?>>[];
  server.listen((HttpRequest request) async {
    final raw = await utf8.decoder.bind(request).join();
    bodies.add(jsonDecode(raw) as Map<String, Object?>);
    request.response.statusCode = status;
    if (status == 429) request.response.headers.set('retry-after', '120');
    request.response.write('{}');
    await request.response.close();
  });
  return (server, bodies);
}

ErrorgapClient client(HttpServer server, {BeforeNotify? beforeNotify}) =>
    ErrorgapClient(ErrorgapConfiguration(
      endpoint: 'http://127.0.0.1:${server.port}',
      projectSlug: 'demo',
      async: false,
      beforeNotify: beforeNotify,
    ));

void main() {
  test('a 429 pauses sending for Retry-After', () async {
    final (server, bodies) = await stub(429);
    final sdk = client(server);
    expect((await sdk.notify(StateError('one'))).status, 429);
    expect(sdk.paused, isTrue);
    expect((await sdk.notify(StateError('two'))).error,
        isA<RateLimitedException>());
    expect(bodies, hasLength(1));
    await sdk.shutdown();
    await server.close(force: true);
  });

  test('beforeNotify can drop or change a notice; a throwing hook is skipped',
      () async {
    final (server, bodies) = await stub(201);
    final drop = client(server, beforeNotify: (_) => null);
    final change = client(server, beforeNotify: (notice) {
      (notice['context'] as Map<String, Object?>)['team'] = 'billing';
      return notice;
    });
    final broken = client(server,
        beforeNotify: (_) => throw StateError('bug in the hook'));

    expect(
        (await drop.notify(StateError('no'))).body, 'dropped by beforeNotify');
    await change.notify(StateError('yes'));
    await broken.notify(StateError('still sent'));

    expect(bodies, hasLength(2));
    expect((bodies[0]['context'] as Map)['team'], 'billing');
    for (final sdk in [drop, change, broken]) {
      await sdk.shutdown();
    }
    await server.close(force: true);
  });

  test('sensitive session keys are masked', () async {
    final (server, bodies) = await stub(201);
    final sdk = client(server);
    await sdk.notify(
      StateError('x'),
      options: NoticeOptions(session: <String, Object?>{'auth_token': 't'}),
    );
    expect((bodies[0]['session'] as Map)['auth_token'], '[FILTERED]');
    await sdk.shutdown();
    await server.close(force: true);
  });
}
