import 'source_reader.dart';

/// Parses `StackTrace.toString()` into Errorgap wire-format frames.
///
/// When package roots are supplied, readable application and dependency
/// sources include a bounded excerpt so the dashboard can render source
/// without a repository integration.
List<Map<String, Object?>> parseStackTrace(
  Object? stackTrace, {
  String? rootDirectory,
  List<String> applicationPackages = const <String>[],
  Map<String, String> packageSourceRoots = const <String, String>{},
  bool sourceContextEnabled = true,
  int startIndex = 0,
}) {
  if (stackTrace == null) return <Map<String, Object?>>[];
  final text = stackTrace.toString();
  if (text.isEmpty) return <Map<String, Object?>>[];

  final frames = <Map<String, Object?>>[];
  var index = startIndex;

  for (final raw in text.split('\n')) {
    final value = raw.trim();
    if (value.isEmpty || !value.startsWith('#')) continue;
    final match = _framePattern.firstMatch(value);
    if (match == null) continue;

    final function = match.group(1)?.trim();
    final location = match.group(2) ?? '';
    final parsed = _splitFileLineColumn(location);
    final normalizedFile = _normalizeFile(parsed.file, rootDirectory);
    final frame = <String, Object?>{
      'file': normalizedFile,
      'line': parsed.line,
      'function': function,
      'in_app': _isInApp(
        parsed.file,
        applicationPackages: applicationPackages,
        rootDirectory: rootDirectory,
      ),
      'index': index,
    };
    if (parsed.column != null) frame['column'] = parsed.column;
    if (sourceContextEnabled) {
      final source = readSourceExcerpt(
        parsed.file,
        parsed.line,
        rootDirectory: rootDirectory,
        packageSourceRoots: packageSourceRoots,
      );
      if (source != null) frame['source'] = source;
    }
    frames.add(frame);
    index += 1;
  }

  return frames;
}

final RegExp _framePattern = RegExp(r'^#\d+\s+(.+?)\s+\((.+)\)\s*$');

class _FileLineColumn {
  _FileLineColumn(this.file, this.line, this.column);

  final String file;
  final int? line;
  final int? column;
}

_FileLineColumn _splitFileLineColumn(String location) {
  final match = RegExp(r'^(.+?):(\d+)(?::(\d+))?$').firstMatch(location);
  if (match == null) {
    return _FileLineColumn(
        location.isEmpty ? '<unknown>' : location, null, null);
  }
  return _FileLineColumn(
    match.group(1) ?? '<unknown>',
    int.tryParse(match.group(2) ?? ''),
    int.tryParse(match.group(3) ?? ''),
  );
}

String _normalizeFile(String file, String? rootDirectory) {
  var value = file;
  if (value.startsWith('file:')) {
    try {
      value = Uri.parse(value).toFilePath();
    } catch (_) {
      return file;
    }
  }
  final root = rootDirectory;
  if (root != null && root.isNotEmpty) {
    final normalizedRoot = root.endsWith('/') ? root : '$root/';
    if (value.startsWith(normalizedRoot)) {
      return value.substring(normalizedRoot.length);
    }
  }
  return value;
}

bool _isInApp(
  String location, {
  required List<String> applicationPackages,
  required String? rootDirectory,
}) {
  if (location.isEmpty || location.startsWith('dart:')) return false;
  if (location.contains('package:flutter/')) return false;
  if (location.contains('package:errorgap/')) return false;
  if (location.contains('/.pub-cache/') ||
      location.contains('/.dart_tool/') ||
      location.contains('/flutter/packages/')) {
    return false;
  }

  if (location.startsWith('package:')) {
    final package = location.substring('package:'.length).split('/').first;
    return applicationPackages.isEmpty || applicationPackages.contains(package);
  }

  if (rootDirectory != null && rootDirectory.isNotEmpty) {
    var value = location;
    if (value.startsWith('file:')) {
      try {
        value = Uri.parse(value).toFilePath();
      } catch (_) {
        return false;
      }
    }
    return value == rootDirectory || value.startsWith('$rootDirectory/');
  }
  return true;
}
