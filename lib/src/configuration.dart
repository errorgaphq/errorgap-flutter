import 'platform_environment.dart';

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
    String? rootDirectory,
    bool? async,
    List<String>? filterKeys,
    List<String>? ignoreEnvironments,
    bool? apmEnabled,
    double? apmSampleRate,
    bool? logsEnabled,
    String? minimumLogLevel,
    bool? sourceContextEnabled,
    this.timeoutSeconds = 5,
    this.queueSize = 100,
    Map<String, Object?>? deviceInfo,
    List<String>? applicationPackages,
    Map<String, String>? packageSourceRoots,
  })  : endpoint =
            endpoint ?? _env('ERRORGAP_ENDPOINT') ?? 'http://127.0.0.1:3030',
        environment =
            environment ?? _env('ERRORGAP_ENVIRONMENT') ?? 'production',
        rootDirectory = rootDirectory ??
            _env('ERRORGAP_ROOT_DIRECTORY') ??
            currentDirectory(),
        async = async ?? _envBool('ERRORGAP_ASYNC') ?? true,
        filterKeys = filterKeys ?? List<String>.from(defaultFilterKeys),
        ignoreEnvironments =
            ignoreEnvironments ?? _envList('ERRORGAP_IGNORE_ENVIRONMENTS'),
        apmEnabled = apmEnabled ?? _envBool('ERRORGAP_APM_ENABLED') ?? false,
        apmSampleRate =
            apmSampleRate ?? _envDouble('ERRORGAP_APM_SAMPLE_RATE') ?? 1.0,
        logsEnabled = logsEnabled ?? _envBool('ERRORGAP_LOGS_ENABLED') ?? false,
        minimumLogLevel =
            minimumLogLevel ?? _env('ERRORGAP_MINIMUM_LOG_LEVEL') ?? 'info',
        sourceContextEnabled = sourceContextEnabled ?? true,
        deviceInfo = deviceInfo ?? <String, Object?>{},
        applicationPackages = applicationPackages ?? <String>[],
        packageSourceRoots = packageSourceRoots ?? <String, String>{} {
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
  String? rootDirectory;
  bool async;
  List<String> filterKeys;
  List<String> ignoreEnvironments;
  bool apmEnabled;
  double apmSampleRate;
  bool logsEnabled;
  String minimumLogLevel;
  bool sourceContextEnabled;
  int timeoutSeconds;
  int queueSize;
  Map<String, Object?> deviceInfo;
  List<String> applicationPackages;
  Map<String, String> packageSourceRoots;

  bool get isIgnoredEnvironment => ignoreEnvironments.contains(environment);

  void validate() {
    final slug = projectSlug;
    if (slug == null || slug.trim().isEmpty) {
      throw StateError('Errorgap projectSlug is required');
    }
    if (endpoint.trim().isEmpty) {
      throw StateError('Errorgap endpoint is required');
    }
    if (apmSampleRate < 0 || apmSampleRate > 1) {
      throw StateError('Errorgap apmSampleRate must be between 0 and 1');
    }
    if (timeoutSeconds <= 0) {
      throw StateError('Errorgap timeoutSeconds must be greater than zero');
    }
    if (queueSize <= 0) {
      throw StateError('Errorgap queueSize must be greater than zero');
    }
  }

  static String? _env(String key) => environmentValue(key);

  static bool? _envBool(String key) {
    final value = _env(key)?.trim().toLowerCase();
    if (value == null) return null;
    if (value == '1' || value == 'true' || value == 'yes') return true;
    if (value == '0' || value == 'false' || value == 'no') return false;
    return null;
  }

  static double? _envDouble(String key) => double.tryParse(_env(key) ?? '');

  static List<String> _envList(String key) => (_env(key) ?? '')
      .split(',')
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toList(growable: false);
}
