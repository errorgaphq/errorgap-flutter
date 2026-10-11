import 'dart:io';

String? environmentValue(String key) {
  final value = Platform.environment[key];
  return value == null || value.isEmpty ? null : value;
}

String currentDirectory() => Directory.current.path;

/// The app's OS for session replay, e.g. `iOS` or `Android`.
String operatingSystemLabel() {
  switch (Platform.operatingSystem) {
    case 'ios':
      return 'iOS';
    case 'android':
      return 'Android';
    case 'macos':
      return 'macOS';
    case 'windows':
      return 'Windows';
    case 'linux':
      return 'Linux';
    default:
      return Platform.operatingSystem;
  }
}

/// Session replay is on by default only in mobile apps.
bool isMobilePlatform() => Platform.isIOS || Platform.isAndroid;
