import 'dart:convert';
import 'dart:io';

import 'package:errorgap/errorgap.dart';
import 'package:test/test.dart';

void main() {
  test(
      'a kind switched off in errorgap is not sent; unreadable settings fail open',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final seen = <String>[];
    String? settings =
        '{"errors_enabled":false,"apm_enabled":true,"poll_interval_seconds":600}';
    server.listen((HttpRequest request) async {
      await utf8.decoder.bind(request).join();
      seen.add('${request.method} ${request.uri.path}');
      if (request.method == 'GET') {
        request.response.statusCode = settings == null ? 500 : 200;
        request.response.write(settings ?? 'nope');
      } else {
        request.response.statusCode = 201;
        request.response.write('{}');
      }
      await request.response.close();
    });
    final sdk = ErrorgapClient(ErrorgapConfiguration(
      endpoint: 'http://127.0.0.1:${server.port}',
      projectSlug: 'demo',
      async: false,
      remoteSettings: true,
    ));

    expect(await sdk.refreshRemoteSettings(), isTrue);
    expect(seen.first, 'GET /api/projects/demo/config');
    final dropped = await sdk.notify(StateError('x'));
    expect(dropped.body, 'switched off for this project');
    expect(seen.where((line) => line.startsWith('POST')), isEmpty);
    expect(sdk.remoteEnabled('transactions'), isTrue);

    // Unreadable: what was known is kept.
    settings = null;
    expect(await sdk.refreshRemoteSettings(), isFalse);
    expect(sdk.remoteEnabled('notices'), isFalse);

    await sdk.shutdown();
    await server.close(force: true);
  });
}
