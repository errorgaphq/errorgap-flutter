import 'package:errorgap/errorgap.dart';
import 'package:test/test.dart';

void main() {
  group('ErrorgapConfiguration', () {
    test('defaults when nothing provided', () {
      final cfg = ErrorgapConfiguration();
      expect(cfg.endpoint.isNotEmpty, isTrue);
      expect(cfg.async, isTrue);
      expect(cfg.filterKeys.contains('password'), isTrue);
    });

    test('validate throws when projectSlug missing', () {
      final cfg = ErrorgapConfiguration();
      expect(() => cfg.validate(), throwsStateError);
    });

    test('validate passes when projectSlug present', () {
      final cfg = ErrorgapConfiguration(projectSlug: 'demo');
      cfg.validate();
    });
  });
}
