/// Parse a Dart `StackTrace.toString()` output into Errorgap-format frames.
///
/// Dart stack traces look like:
///   #0      MyClass.method (package:my_app/file.dart:42:5)
///   #1      main (file:///path/to/main.dart:7:9)
List<Map<String, Object?>> parseStackTrace(Object? stackTrace) {
  if (stackTrace == null) return <Map<String, Object?>>[];
  final text = stackTrace.toString();
  if (text.isEmpty) return <Map<String, Object?>>[];

  final frames = <Map<String, Object?>>[];
  var index = 0;

  for (final raw in text.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    if (!line.startsWith('#')) continue;

    final match = _framePattern.firstMatch(line);
    if (match == null) continue;

    final function = match.group(1);
    final location = match.group(2) ?? '';
    final fileAndLine = _splitFileAndLine(location);

    frames.add(<String, Object?>{
      'file': fileAndLine.file,
      'line': fileAndLine.line,
      'function': function,
      'in_app': _isInApp(location),
      'index': index,
    });
    index += 1;
  }

  return frames;
}

final RegExp _framePattern = RegExp(r'^#\d+\s+(.+?)\s+\((.+)\)\s*$');

class _FileLine {
  _FileLine(this.file, this.line);
  final String? file;
  final int? line;
}

_FileLine _splitFileAndLine(String location) {
  // Match trailing ":line:column" or ":line".
  final m = RegExp(r'^(.+?):(\d+)(?::\d+)?$').firstMatch(location);
  if (m == null) return _FileLine(location, null);
  final file = m.group(1);
  final lineStr = m.group(2);
  return _FileLine(file, lineStr == null ? null : int.tryParse(lineStr));
}

bool _isInApp(String location) {
  if (location.isEmpty) return false;
  if (location.startsWith('dart:')) return false;
  if (location.contains('package:flutter/')) return false;
  if (location.contains('package:errorgap/')) return false;
  return true;
}
