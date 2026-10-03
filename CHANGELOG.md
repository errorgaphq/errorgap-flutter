# Changelog

## 0.3.0 - 2026-10-03

- Errors carry their APM transaction id: every `ErrorgapTransaction` has an
  `id` (sent with it), and errors reported inside `withErrorgapTransaction(id, ...)`
  or a failing `trackJob` carry it as `context.transaction_id`, so errorgap
  shows the error an interaction raised on its trace. Zone-scoped, so async
  work keeps it and concurrent work never shares it.

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
