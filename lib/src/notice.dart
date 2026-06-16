import 'backtrace.dart';
import 'configuration.dart';
import 'filter.dart';
import 'version.dart';

const String notifierId = 'errorgap-flutter';

class NoticeOptions {
  NoticeOptions({
    this.context,
    this.environment,
    this.session,
    this.params,
    this.stackTrace,
    this.isFatal,
  });

  final Map<String, Object?>? context;
  final Map<String, Object?>? environment;
  final Map<String, Object?>? session;
  final Map<String, Object?>? params;
  final Object? stackTrace;
  final bool? isFatal;
}

Map<String, Object?> buildNotice(
  Object error,
  ErrorgapConfiguration config,
  NoticeOptions options,
) {
  final defaultContext = <String, Object?>{
    'notifier': notifierId,
    'notifier_version': errorgapVersion,
    'environment': config.environment,
  };
  if (config.release != null) {
    defaultContext['release'] = config.release;
  }
  if (options.isFatal != null) {
    defaultContext['is_fatal'] = options.isFatal;
  }
  if (options.context != null) {
    defaultContext.addAll(options.context!);
  }

  final defaultEnvironment = <String, Object?>{};
  defaultEnvironment.addAll(config.deviceInfo);
  if (options.environment != null) {
    defaultEnvironment.addAll(options.environment!);
  }

  final errorEntry = <String, Object?>{
    'type': error.runtimeType.toString(),
    'message': _errorMessage(error),
    'backtrace': parseStackTrace(options.stackTrace),
  };

  final notice = <String, Object?>{
    'received_at': DateTime.now().toUtc().toIso8601String(),
    'errors': <Map<String, Object?>>[errorEntry],
    'context': defaultContext,
    'environment': defaultEnvironment,
    'session': options.session ?? <String, Object?>{},
    'params': filterParams(options.params, config.filterKeys),
  };
  if (config.projectId != null) {
    notice['project_id'] = config.projectId;
  }
  return notice;
}

String _errorMessage(Object error) {
  if (error is Error) {
    return error.toString();
  }
  if (error is Exception) {
    return error.toString();
  }
  return error.toString();
}
