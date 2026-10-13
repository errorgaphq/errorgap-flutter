# errorgap (Flutter)

Flutter/Dart notifier for [Errorgap](https://errorgap.com). Reports errors,
inline Dart source, APM transactions/jobs, query and HTTP spans, and structured
logs. Flutter applications wire
`FlutterError.onError` (framework-level Dart errors) and
`PlatformDispatcher.instance.onError` (uncaught zone errors). Native
crashes (Android JNI, iOS Objective-C) are out of scope for v1; pair
with the native SDKs (`errorgap-android`, `errorgap-swift`) until a
Pigeon bridge ships.

Requires Dart 3.0+.

## Install

```yaml
dependencies:
  errorgap: ^0.4.0
```

## Configure

```dart
import 'package:errorgap/errorgap.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'dart:ui';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  Errorgap.init(ErrorgapConfiguration(
    endpoint:    'https://errorgap.example.com',
    projectSlug: 'your-project',
    apiKey:      const String.fromEnvironment('ERRORGAP_API_KEY'),
    environment: kReleaseMode ? 'production' : 'development',
    release:     const String.fromEnvironment('APP_VERSION'),
    apmEnabled:  true,
    logsEnabled: true,
    deviceInfo: <String, Object?>{
      'os_name': defaultTargetPlatform.toString(),
    },
  ));

  FlutterError.onError = (FlutterErrorDetails details) {
    Errorgap.notify(details.exception, stackTrace: details.stack);
    FlutterError.presentError(details);
  };

  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    Errorgap.notify(error, stackTrace: stack);
    return true;
  };

  runApp(const MyApp());
}
```

## Manual notification

```dart
try {
  await risky();
} catch (error, stack) {
  await Errorgap.notify(error, stackTrace: stack, context: <String, Object?>{
    'component': 'checkout',
  });
  rethrow;
}
```

`notify` returns a `DeliveryResult` (`status`, `body`, `error`, `queued`).
The SDK never throws.

## Hooks, filtering and rate limits

```dart
ErrorgapConfiguration(
  projectSlug: 'my-app',
  // return null to drop a notice, or return it changed
  beforeNotify: (notice) => notice,
);
```

`filterKeys` are masked at any depth in `params` and `session`. After a 429 the
client stops sending for the server's `Retry-After` (`client.paused`).

## Source excerpts

The SDK reads a bounded source window for file-backed Dart VM frames. Package
URIs need an explicit source-root mapping so both application and dependency
frames can ship source:

```dart
ErrorgapConfiguration(
  projectSlug: 'your-project',
  rootDirectory: '/app',
  applicationPackages: const ['my_flutter_app'],
  packageSourceRoots: const {
    'my_flutter_app': '/app/lib',
    'inventory_client': '/app/vendor/inventory_client/lib',
  },
);
```

Each excerpt is limited to six lines before and after the target and 400
characters per line. Source reading degrades safely on Flutter web and on
mobile builds where original Dart sources are not deployed.

## APM and jobs

```dart
await Errorgap.notifyTransaction(ErrorgapTransaction(
  method: 'POST',
  path: '/orders/{orderId}',
  pathRaw: '/orders/42',
  statusCode: 201,
  durationMs: 125,
  spans: [
    ErrorgapSpan.database(
      "SELECT * FROM orders WHERE id = 42",
      durationMs: 12,
      file: 'lib/orders.dart',
      line: 30,
      function: 'Orders.load',
    ),
    ErrorgapSpan.external(durationMs: 18),
  ],
));

await Errorgap.trackJob('ReceiptJob', (spans) async {
  spans.database('SELECT 1 FROM receipts WHERE id = 42', durationMs: 8);
  await generateReceipt();
}, queue: 'default');
```

`trackJob` reports a failed operation as both an error and a failed job
transaction, then rethrows it to preserve application behavior. SQL literals
are normalized to `?` so equivalent queries aggregate together.

### Link API calls to server traces

Trace a call to your API and errorgap links it to the server request that
answered it (when the server's errorgap SDK records the `x-errorgap-trace`
header — Rails, Laravel, Express, Django, Spring and the rest do):

```dart
final spans = ErrorgapSpanCollector();
final stopwatch = Stopwatch()..start();
final response = await spans.traceCall('GET /api/orders/7',
    (headers) => http.get(ordersUri, headers: headers));
await client.notifyTransaction(ErrorgapTransaction(
  path: 'OrderScreen',
  durationMs: stopwatch.elapsedMicroseconds / 1000,
  spans: spans.snapshot(),
));
```

`traceCall` records an `http` span carrying the trace id it sent; the app's
trace lists each traced call with a link to its server trace, and the server
trace shows how long the app waited. For manual timing use
`final call = spans.startCall(label)`, send `call.headers`, then `call.finish()`.

### Link errors to their transaction

Every `ErrorgapTransaction` has an `id`. Errors reported inside
`withErrorgapTransaction(id, () async { ... })` — and a failing `trackJob` —
carry it as `context.transaction_id`, so errorgap shows the error an
interaction raised on its trace:

```dart
final transaction = ErrorgapTransaction(path: '/checkout', durationMs: 0);
await withErrorgapTransaction(transaction.id, () => submitOrder());
```

The id is a zone value: async work started inside keeps it, and concurrent
work never shares it.

## Structured logs

```dart
final logger = Errorgap.logger(source: 'flutter.checkout');
await logger?.warning('payment gateway timeout');
await logger?.error('checkout failed');
```

Logs are disabled by default. Set `logsEnabled: true` and optionally
`minimumLogLevel` (`trace`, `debug`, `info`, `warn`, `error`, or `fatal`).

## Session replay

Session replay records a timeline of each app session, shown on error groups
and incidents in Errorgap. It is **timeline only**: no screenshots and no
widget snapshots.

| Event | Recorded when |
|---|---|
| `page_load` | The app starts ("App started"), or a new session starts after 30 minutes in the background ("App opened") |
| `navigation` | A screen is tracked, or the app returns from the background |
| `api_error` | A call through `ErrorgapHttpClient` fails or answers 5xx |
| `error` | An error is reported, linked to its error group |
| `exit` | The app goes to the background |

It is on by default in iOS and Android apps (off elsewhere, such as a Dart
server; pass `replay: true` to record there), and records only what the
project allows in **Settings → Session replay**: nothing while replay is off,
and a sampled share of sessions while it is on.

Only sessions that hit an error are kept. Until an error is reported, the
session's most recent 300 events are held in memory and nothing is sent; then
everything held goes up with the error and the rest of the session follows. A
session that ends without an error is never sent.

This package does not depend on Flutter, so wire the screens and the app
lifecycle in your app:

```dart
import 'package:flutter/widgets.dart';
import 'package:errorgap/errorgap.dart';

class ErrorgapNavigatorObserver extends NavigatorObserver {
  void _track(Route<dynamic>? route) {
    final name = route?.settings.name;
    if (name != null) Errorgap.trackScreen(name);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => _track(route);
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _track(previousRoute);
  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) => _track(newRoute);
}

// In your root widget's State:
late final AppLifecycleListener _lifecycle = AppLifecycleListener(
  onHide: Errorgap.appPaused,
  onShow: Errorgap.appResumed,
);

MaterialApp(navigatorObservers: [ErrorgapNavigatorObserver()], /* ... */);
```

Send your API calls through `ErrorgapHttpClient` to record the ones that fail:

```dart
final api = ErrorgapHttpClient(http.Client());
```

Options: `Errorgap.init(config, replay: false)` turns replay off, and
`replayOptions: ErrorgapReplayOptions(appName: 'Acme', device: 'Tablet')` names
the app and device class in the session list.

## Configuration reference

| Field | Default | Notes |
|---|---|---|
| `endpoint` | `ERRORGAP_ENDPOINT` or `http://127.0.0.1:3030` | |
| `projectSlug` | `ERRORGAP_PROJECT_SLUG` | **Required** |
| `projectId` | `ERRORGAP_PROJECT_ID` | |
| `apiKey` | `ERRORGAP_API_KEY` | Sent as `x-errorgap-project-key` |
| `environment` | `ERRORGAP_ENVIRONMENT` or `production` | |
| `release` | — | |
| `rootDirectory` | current directory on Dart VM | Source path base |
| `async` | `true` | Background queue + worker |
| `filterKeys` | `[password, token, ...]` | Substring, case-insensitive |
| `ignoreEnvironments` | `ERRORGAP_IGNORE_ENVIRONMENTS` | Comma-separated when read from env |
| `apmEnabled` | `false` | Enables transaction delivery |
| `apmSampleRate` | `1.0` | Range `0.0...1.0` |
| `logsEnabled` | `false` | Enables structured log delivery |
| `minimumLogLevel` | `info` | Lowest forwarded log level |
| `sourceContextEnabled` | `true` | Reads inline source when available |
| `timeoutSeconds` | `5` | HTTP request timeout |
| `queueSize` | `100` | Bounded queue |
| `deviceInfo` | `{}` | Caller-supplied device fingerprint |
| `applicationPackages` | `[]` | Packages classified as application code |
| `packageSourceRoots` | `{}` | Package URI to local source mappings |

## Graceful shutdown

```dart
await Errorgap.flush();
await Errorgap.shutdown();
```

## Verify the ingestion path

```sh
curl -sS -X POST "$ERRORGAP_ENDPOINT/api/projects/$ERRORGAP_PROJECT_SLUG/notices" \
  -H "content-type: application/json" \
  -H "x-errorgap-project-key: $ERRORGAP_API_KEY" \
  -d '{"errors":[{"type":"ErrorgapInstallTest","message":"Errorgap install verification"}],"context":{"environment":"development"}}'
```

Expect HTTP `201` with a JSON body containing `group_id`.

## Development

```sh
dart pub get
dart test
```

## License

MIT.
