import 'package:errorgap/errorgap.dart';
import 'package:test/test.dart';

void main() {
  group('ErrorgapConfiguration', () {
    test('defaults when nothing provided', () {
      final cfg = ErrorgapConfiguration();
      expect(cfg.endpoint.isNotEmpty, isTrue);
      expect(cfg.async, isTrue);
      expect(cfg.filterKeys.contains('password'), isTrue);
      expect(cfg.apmEnabled, isFalse);
      expect(cfg.logsEnabled, isFalse);
      expect(cfg.apmSampleRate, 1.0);
    });

    test('validate throws when projectSlug missing', () {
      final cfg = ErrorgapConfiguration();
      expect(() => cfg.validate(), throwsStateError);
    });

    test('validate passes when projectSlug present', () {
      final cfg = ErrorgapConfiguration(projectSlug: 'demo');
      cfg.validate();
    });

    test('validates APM sampling range', () {
      final cfg = ErrorgapConfiguration(
        projectSlug: 'demo',
        apmSampleRate: 1.1,
      );
      expect(() => cfg.validate(), throwsStateError);
    });

    test('recognizes ignored environments', () {
      final cfg = ErrorgapConfiguration(
        projectSlug: 'demo',
        environment: 'test',
        ignoreEnvironments: <String>['test'],
      );
      expect(cfg.isIgnoredEnvironment, isTrue);
    });
  });
}
