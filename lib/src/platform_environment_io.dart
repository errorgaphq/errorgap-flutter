import 'dart:io';

String? environmentValue(String key) {
  final value = Platform.environment[key];
  return value == null || value.isEmpty ? null : value;
}

String currentDirectory() => Directory.current.path;
