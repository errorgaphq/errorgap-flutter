import 'dart:io' show Platform;

const List<String> defaultFilterKeys = <String>[
  'password',
  'password_confirmation',
  'token',
  'secret',
  'api_key',
  'authorization',
  'cookie',
];

class ErrorgapConfiguration {
  ErrorgapConfiguration({
    String? endpoint,
    this.projectSlug,
    this.projectId,
    this.apiKey,
    String? environment,
    this.release,
    this.async = true,
    List<String>? filterKeys,
    this.timeoutSeconds = 5,
    this.queueSize = 100,
    Map<String, Object?>? deviceInfo,
  })  : endpoint = endpoint ??
            _env('ERRORGAP_ENDPOINT') ??
            'http://127.0.0.1:3030',
        environment = environment ??
            _env('ERRORGAP_ENVIRONMENT') ??
            'production',
        filterKeys = filterKeys ?? List<String>.from(defaultFilterKeys),
        deviceInfo = deviceInfo ?? <String, Object?>{} {
    projectSlug ??= _env('ERRORGAP_PROJECT_SLUG');
    projectId ??= _env('ERRORGAP_PROJECT_ID');
    apiKey ??= _env('ERRORGAP_API_KEY');
  }

  String endpoint;
  String? projectSlug;
  String? projectId;
  String? apiKey;
  String environment;
  String? release;
  bool async;
  List<String> filterKeys;
  int timeoutSeconds;
  int queueSize;
  Map<String, Object?> deviceInfo;

  void validate() {
    final slug = projectSlug;
    if (slug == null || slug.trim().isEmpty) {
      throw StateError('Errorgap projectSlug is required');
    }
    if (endpoint.trim().isEmpty) {
      throw StateError('Errorgap endpoint is required');
    }
  }

  static String? _env(String key) {
    try {
      final value = Platform.environment[key];
      return (value != null && value.isNotEmpty) ? value : null;
    } catch (_) {
      // Platform.environment is unavailable on the web — degrade silently.
      return null;
    }
  }
}
