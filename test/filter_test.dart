import 'package:errorgap/src/filter.dart';
import 'package:test/test.dart';

void main() {
  const defaults = <String>[
    'password',
    'token',
    'secret',
    'api_key',
    'authorization',
    'cookie',
  ];

  group('filterParams', () {
    test('masks filtered keys', () {
      final out = filterParams(<String, Object?>{
        'username': 'alice',
        'password': 'hunter2',
        'access_token': 'x',
      }, defaults);
      expect(out['username'], 'alice');
      expect(out['password'], '[FILTERED]');
      expect(out['access_token'], '[FILTERED]');
    });

    test('recurses into nested maps', () {
      final out = filterParams(<String, Object?>{
        'user': <String, Object?>{'name': 'alice', 'api_key': 'x'},
      }, defaults);
      final user = out['user']! as Map<String, Object?>;
      expect(user['name'], 'alice');
      expect(user['api_key'], '[FILTERED]');
    });

    test('case insensitive', () {
      final out = filterParams(<String, Object?>{
        'Authorization': 'Bearer xyz',
      }, defaults);
      expect(out['Authorization'], '[FILTERED]');
    });

    test('recurses into maps nested in lists', () {
      final out = filterParams(<String, Object?>{
        'items': <Object?>[
          <String, Object?>{'name': 'safe', 'access_token': 'secret'},
        ],
      }, defaults);
      final items = out['items']! as List<Object?>;
      final item = items.single! as Map<String, Object?>;
      expect(item['name'], 'safe');
      expect(item['access_token'], '[FILTERED]');
    });
  });
}
