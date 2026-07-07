# Changelog

## 0.1.0

- Initial release: Dart-side error reporting for Errorgap.
- `Errorgap.init(...)` configuration with env-style defaults.
- Dart `StackTrace` parsing with `in_app` frame detection.
- Async delivery queue with `flush()`; the SDK never throws.
- Caller-supplied `deviceInfo` attached to every notice.
