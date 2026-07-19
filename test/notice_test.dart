import 'package:errorgap/errorgap.dart';
import 'package:errorgap/src/notice.dart' as nt;
import 'package:test/test.dart';

class CheckoutFailure implements Exception, ErrorgapCausedBy {
  CheckoutFailure(this.message, this.cause, this.causeStackTrace);

  final String message;
  final Object cause;
  final StackTrace causeStackTrace;

  @override
  Object get errorgapCause => cause;

  @override
  Object get errorgapCauseStackTrace => causeStackTrace;

  @override
  String toString() => message;
}

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

    test('appends frames from explicit cause chains', () {
      final cause = StateError('database unavailable');
      final error = CheckoutFailure(
        'checkout failed',
        cause,
        StackTrace.fromString(
          '#0      Database.load (package:demo/database.dart:20:4)',
        ),
      );
      final notice = nt.buildNotice(
        error,
        cfg(),
        NoticeOptions(
          stackTrace: StackTrace.fromString(
            '#0      Checkout.run (package:demo/checkout.dart:10:2)',
          ),
        ),
      );
      final errors = notice['errors']! as List<Map<String, Object?>>;
      final frames = errors.single['backtrace']! as List<Map<String, Object?>>;
      expect(frames, hasLength(2));
      expect(frames[0]['function'], 'Checkout.run');
      expect(frames[1]['function'], 'Database.load');
      expect(frames[1]['index'], 1);
    });

    test('includes the configured root directory', () {
      final config = cfg()..rootDirectory = '/app';
      final notice = nt.buildNotice(
        StateError('x'),
        config,
        NoticeOptions(),
      );
      final context = notice['context']! as Map<String, Object?>;
      expect(context['root_directory'], '/app');
    });
  });
}
