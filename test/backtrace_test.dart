import 'dart:io';

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
      expect(frames[0]['column'], 5);
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

    test('includes application and vendor source excerpts', () {
      final temporary = Directory.systemTemp.createTempSync('errorgap-dart-');
      addTearDown(() => temporary.deleteSync(recursive: true));
      final appRoot = Directory('${temporary.path}/app')..createSync();
      final vendorRoot = Directory('${temporary.path}/vendor')..createSync();
      File('${appRoot.path}/checkout.dart').writeAsStringSync('''
void checkout() {
  throw StateError('app source');
}
''');
      File('${vendorRoot.path}/guard.dart').writeAsStringSync('''
void requireInventory() {
  throw StateError('vendor source');
}
''');

      const stack = '''
#0      checkout (package:my_app/checkout.dart:3:3)
#1      requireInventory (package:vendor_inventory/guard.dart:3:3)
''';
      final frames = parseStackTrace(
        stack,
        applicationPackages: const <String>['my_app'],
        packageSourceRoots: <String, String>{
          'my_app': appRoot.path,
          'vendor_inventory': vendorRoot.path,
        },
      );

      expect(frames[0]['in_app'], isTrue);
      expect(frames[1]['in_app'], isFalse);
      expect(frames[0]['source'], <String, Object?>{
        'start_line': 1,
        'lines': <String>[
          'void checkout() {',
          "  throw StateError('app source');",
          '}',
        ],
      });
      expect(
        (frames[1]['source']! as Map<String, Object?>)['lines'],
        contains("  throw StateError('vendor source');"),
      );
    });

    test('makes file URIs relative to the configured root', () {
      final temporary = Directory.systemTemp.createTempSync('errorgap-root-');
      addTearDown(() => temporary.deleteSync(recursive: true));
      final source = File('${temporary.path}/main.dart')
        ..writeAsStringSync("throw StateError('boom');\n");
      final frames = parseStackTrace(
        '#0      main (${source.uri}:1:1)',
        rootDirectory: temporary.path,
      );
      expect(frames.single['file'], 'main.dart');
      expect(frames.single['in_app'], isTrue);
      expect(frames.single['source'], isNotNull);
    });
  });
}
