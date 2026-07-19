# Changelog

## 0.2.0 - 2026-07-19

- Add manual APM transactions, database/external spans, and background jobs.
- Add structured log delivery with level filtering.
- Include bounded application and package source excerpts in Dart backtraces.
- Add application-package classification, ignored environments, nested causes,
  SQL normalization, and web-safe platform configuration.

## 0.1.0

- Initial release: Dart-side error reporting for Errorgap.
- `Errorgap.init(...)` configuration with env-style defaults.
- Dart `StackTrace` parsing with `in_app` frame detection.
- Async delivery queue with `flush()`; the SDK never throws.
- Caller-supplied `deviceInfo` attached to every notice.
