import 'package:errorgap/errorgap.dart';
import 'package:errorgap/src/notice.dart' as nt;
import 'package:test/test.dart';

void main() {
  ErrorgapConfiguration cfg() => ErrorgapConfiguration(
        projectSlug: 'demo',
        projectId: 'p_1',
        environment: 'test',
        release: '1.2.3',
        deviceInfo: <String, Object?>{
          'os_name': 'iOS',
          'app_version': '1.0',
        },
      );

  group('buildNotice', () {
    test('captures type and message', () {
      final notice = nt.buildNotice(
        ArgumentError('boom'),
        cfg(),
        NoticeOptions(),
      );
      final errors = notice['errors']! as List<Map<String, Object?>>;
      expect(errors[0]['type'], 'ArgumentError');
      expect((errors[0]['message']! as String).contains('boom'), isTrue);
    });

    test('includes notifier identification', () {
      final notice = nt.buildNotice(
        StateError('x'),
        cfg(),
        NoticeOptions(),
      );
      final context = notice['context']! as Map<String, Object?>;
      expect(context['notifier'], 'errorgap-flutter');
      expect(context['notifier_version'], errorgapVersion);
      expect(context['environment'], 'test');
      expect(context['release'], '1.2.3');
    });

    test('includes deviceInfo in environment', () {
      final notice = nt.buildNotice(
        StateError('x'),
        cfg(),
        NoticeOptions(),
      );
      final env = notice['environment']! as Map<String, Object?>;
      expect(env['os_name'], 'iOS');
      expect(env['app_version'], '1.0');
    });

    test('filters sensitive params', () {
      final notice = nt.buildNotice(
        StateError('x'),
        cfg(),
        NoticeOptions(params: <String, Object?>{
          'username': 'alice',
          'password': 'hunter2',
        }),
      );
      final params = notice['params']! as Map<String, Object?>;
      expect(params['username'], 'alice');
      expect(params['password'], '[FILTERED]');
    });

    test('includes project_id', () {
      final notice = nt.buildNotice(
        StateError('x'),
        cfg(),
        NoticeOptions(),
      );
      expect(notice['project_id'], 'p_1');
    });

    test('records isFatal flag', () {
      final notice = nt.buildNotice(
        StateError('x'),
        cfg(),
        NoticeOptions(isFatal: true),
      );
      final context = notice['context']! as Map<String, Object?>;
      expect(context['is_fatal'], isTrue);
    });
  });
}
