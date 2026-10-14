# Changelog

## 0.7.1 - 2026-10-13

First published release of the 0.7 changes (0.7.0 was tagged but not
published: the changelog entry was missing).

- `beforeNotify`: see each notice before it is sent and return it, changed or
  not, or `null` to drop it. A hook that throws is skipped.
- Rate limits: after a 429 or 503 the client stops sending for the server's
  `Retry-After` (`client.paused`, `RateLimitedException`).
- Remote settings: errors, performance data and logs can each be switched off
  for a project in Errorgap (Project settings › What SDKs send) and installed
  apps follow within ten minutes of running. Fails open.
  `remoteSettings: false` ignores the project's switches.
- `filterKeys` are applied to the session as well as params.

## 0.6.0 - 2026-10-13

- Session replay keeps only sessions that hit an error. A session's events
  (the newest 300) are held in memory and nothing is sent until an error is
  reported; then everything held goes up and the rest of the session follows.
  A session that ends without an error is never sent.

## 0.5.0 - 2026-10-11

- Session replay: a timeline of each app session (app start, screens, failed
  API calls, reported errors linked to their error group, backgrounding),
  shown on error groups and incidents in Errorgap. Timeline only, no
  screenshots. On by default in iOS and Android apps, and it records only what
  the project's replay settings allow; `Errorgap.init(config, replay: false)`
  turns it off. Record screens with `Errorgap.trackScreen`, the app lifecycle
  with `Errorgap.appPaused` / `appResumed`, and failed calls with
  `ErrorgapHttpClient`.

## 0.4.0 - 2026-10-04

- `ErrorgapSpanCollector.traceCall` / `startCall` trace an API call: the
  request gets an `x-errorgap-trace` header and its `http` span records the
  same id, so errorgap links the call to the server request that answered it.

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
