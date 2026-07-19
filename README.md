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
  errorgap: ^0.2.0
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

## Structured logs

```dart
final logger = Errorgap.logger(source: 'flutter.checkout');
await logger?.warning('payment gateway timeout');
await logger?.error('checkout failed');
```

Logs are disabled by default. Set `logsEnabled: true` and optionally
`minimumLogLevel` (`trace`, `debug`, `info`, `warn`, `error`, or `fatal`).

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
