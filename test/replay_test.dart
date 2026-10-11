import 'dart:convert';

import 'package:errorgap/errorgap.dart';
import 'package:errorgap/src/replay.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

const endpoint = 'https://errorgap.example.com';
const sessions = '$endpoint/api/projects/app/sessions';

class Sent {
  Sent(this.method, this.url, this.headers, this.body);
  final String method;
  final String url;
  final Map<String, String> headers;
  final Map<String, Object?>? body;
}

MockClient fakeServer(List<Sent> sent,
    {bool enabled = true, double rate = 1, int sessionStatus = 201}) {
  return MockClient((request) async {
    final body = request.body.isEmpty
        ? null
        : jsonDecode(request.body) as Map<String, Object?>;
    sent.add(
        Sent(request.method, request.url.toString(), request.headers, body));
    if (request.url.path.endsWith('/sessions/config')) {
      return http.Response(
          jsonEncode({'enabled': enabled, 'sample_rate': rate}), 200);
    }
    if (request.url.toString() == sessions) {
      return http.Response('', sessionStatus);
    }
    if (request.url.path.endsWith('/notices')) {
      return http.Response('{"group_id":"group-3"}', 201);
    }
    return http.Response('{}', 503);
  });
}

ErrorgapConfiguration config() => ErrorgapConfiguration(
      endpoint: endpoint,
      projectSlug: 'app',
      apiKey: 'egp_key',
      release: '2.3.0',
      async: false,
    );

ErrorgapReplayRecorder recorder(http.Client http) => ErrorgapReplayRecorder(
      config(),
      http,
      const ErrorgapReplayOptions(
          appName: 'Acme', os: 'Android 14', flushInterval: Duration(hours: 1)),
    );

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

List<Map<String, Object?>> events(List<Sent> sent) => sent
    .where((s) => s.url == sessions)
    .expand((s) => (s.body!['events'] as List).cast<Map<String, Object?>>())
    .toList();

void main() {
  test('records nothing while replay is off for the project', () async {
    final sent = <Sent>[];
    final r = recorder(fakeServer(sent, enabled: false))..start();
    await settle();
    r.screen('Checkout');
    r.paused();
    await settle();
    expect(sent.map((s) => s.url), ['$sessions/config?api_key=egp_key']);
  });

  test(
      'records the start, screens, failed calls and errors linked to their group',
      () async {
    final sent = <Sent>[];
    final server = fakeServer(sent);
    final r = recorder(server)..start();
    await settle();

    r.screen('Checkout');
    r.screen('Checkout');
    final api = ErrorgapHttpClient(server, recorder: () => r);
    await api.post(Uri.parse('https://api.acme.example/orders?token=secret'));
    final done = r.errorStarted('StateError: token missing');
    done('group-3');
    await settle();

    final batches = sent.where((s) => s.url == sessions).toList();
    expect(batches.first.headers['x-errorgap-project-key'], 'egp_key');
    expect(
        batches.first.body!['session'], containsPair('browser', 'Acme 2.3.0'));
    expect(batches.first.body!['session'], containsPair('os', 'Android 14'));
    expect(events(sent).map((e) => '${e['type']}:${e['label']}'), [
      'page_load:App started',
      'navigation:Opened Checkout',
      'api_error:POST https://api.acme.example/orders → 503',
      'error:StateError: token missing',
    ]);
    expect(events(sent).last['group_id'], 'group-3');
    expect((batches.last.body!['session'] as Map)['outcome'], 'error');
  });

  test('a paused app ends the batch; a short pause keeps the session',
      () async {
    final sent = <Sent>[];
    final r = recorder(fakeServer(sent))..start();
    await settle();
    r.paused();
    await settle();
    r.resumed();
    r.screen('Home');
    await r.flush();

    final ids = sent
        .where((s) => s.url == sessions)
        .map((s) => (s.body!['session'] as Map)['id'])
        .toSet();
    expect(ids, hasLength(1));
    final labels = events(sent).map((e) => e['label']).toList();
    expect(
        labels,
        containsAllInOrder([
          'App went to the background',
          'Returned to the app',
          'Opened Home'
        ]));
  });

  test('stops recording the session when the server refuses it', () async {
    final sent = <Sent>[];
    final r = recorder(fakeServer(sent, sessionStatus: 204))..start();
    await settle();
    expect(r.recording, isFalse);
    r.screen('Home');
    await r.flush();
    expect(sent.where((s) => s.url == sessions), hasLength(1));
  });
}
