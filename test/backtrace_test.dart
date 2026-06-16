import 'package:errorgap/src/backtrace.dart';
import 'package:test/test.dart';

void main() {
  group('parseStackTrace', () {
    test('returns empty for null', () {
      expect(parseStackTrace(null), isEmpty);
    });

    test('parses Dart-style frames', () {
      const stack = '''
#0      MyClass.method (package:my_app/file.dart:42:5)
#1      main (file:///path/to/main.dart:7:9)
''';
      final frames = parseStackTrace(stack);
      expect(frames.length, 2);
      expect(frames[0]['function'], 'MyClass.method');
      expect(frames[0]['file'], 'package:my_app/file.dart');
      expect(frames[0]['line'], 42);
      expect(frames[0]['in_app'], isTrue);
    });

    test('marks dart: SDK frames as not in_app', () {
      const stack = '#0      _runZoned (dart:async/zone.dart:1657:10)';
      final frames = parseStackTrace(stack);
      expect(frames.length, 1);
      expect(frames[0]['in_app'], isFalse);
    });

    test('marks package:flutter/ frames as not in_app', () {
      const stack =
          '#0      WidgetsBinding.handleBeginFrame (package:flutter/src/widgets/binding.dart:1015:5)';
      final frames = parseStackTrace(stack);
      expect(frames.length, 1);
      expect(frames[0]['in_app'], isFalse);
    });
  });
}
