# errorgap (Flutter)

Flutter/Dart notifier for [Errorgap](https://errorgap.com). Hooks
`FlutterError.onError` (framework-level Dart errors) and
`PlatformDispatcher.instance.onError` (uncaught zone errors). Native
crashes (Android JNI, iOS Objective-C) are out of scope for v1; pair
with the native SDKs (`errorgap-android`, `errorgap-swift`) until a
Pigeon bridge ships.

Requires Dart 3.0+.

## Install

```yaml
dependencies:
  errorgap: ^0.1.0
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

## Configuration reference

| Field | Default | Notes |
|---|---|---|
| `endpoint` | `ERRORGAP_ENDPOINT` or `http://127.0.0.1:3030` | |
| `projectSlug` | `ERRORGAP_PROJECT_SLUG` | **Required** |
| `projectId` | `ERRORGAP_PROJECT_ID` | |
| `apiKey` | `ERRORGAP_API_KEY` | Sent as `x-errorgap-project-key` |
| `environment` | `ERRORGAP_ENVIRONMENT` or `production` | |
| `release` | — | |
| `async` | `true` | Background queue + worker |
| `filterKeys` | `[password, token, ...]` | Substring, case-insensitive |
| `timeoutSeconds` | `5` | HTTP request timeout |
| `queueSize` | `100` | Bounded queue |
| `deviceInfo` | `{}` | Caller-supplied device fingerprint |

## Graceful shutdown

```dart
await Errorgap.flush();
await Errorgap.shutdown();
```

## Development

```sh
dart pub get
dart test
```

## License

MIT.
