import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'configuration.dart';
import 'notice.dart';
import 'version.dart';

class DeliveryResult {
  DeliveryResult({this.status, this.body, this.error, this.queued = false});

  final int? status;
  final String? body;
  final Object? error;
  final bool queued;

  bool get success =>
      error == null && status != null && status! >= 200 && status! < 300;
}

class ErrorgapClient {
  ErrorgapClient(this._configuration, {http.Client? httpClient})
      : _http = httpClient ?? http.Client() {
    _worker = _loop();
  }

  ErrorgapConfiguration _configuration;
  final http.Client _http;
  final Queue<Map<String, Object?>> _queue = Queue<Map<String, Object?>>();
  final Completer<void> _shutdown = Completer<void>();
  late final Future<void> _worker;
  int _inFlight = 0;

  ErrorgapConfiguration get configuration => _configuration;

  void configure(ErrorgapConfiguration configuration) {
    _configuration = configuration;
  }

  Future<DeliveryResult> notify(
    Object error, {
    NoticeOptions? options,
    bool sync = false,
  }) async {
    final opts = options ?? NoticeOptions();
    try {
      _configuration.validate();
    } catch (e) {
      return DeliveryResult(error: e);
    }

    final notice = buildNotice(error, _configuration, opts);

    if (sync || !_configuration.async) {
      return _deliver(notice);
    }

    if (_queue.length >= _configuration.queueSize) {
      return DeliveryResult(error: StateError('queue full'));
    }
    _queue.add(notice);
    return DeliveryResult(status: 202, queued: true);
  }

  Future<void> flush({Duration timeout = const Duration(seconds: 5)}) async {
    final deadline = DateTime.now().add(timeout);
    while ((_queue.isNotEmpty || _inFlight > 0) &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  Future<void> shutdown({Duration timeout = const Duration(seconds: 5)}) async {
    await flush(timeout: timeout);
    if (!_shutdown.isCompleted) _shutdown.complete();
    await _worker;
    _http.close();
  }

  Future<void> _loop() async {
    while (!_shutdown.isCompleted) {
      if (_queue.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        continue;
      }
      final notice = _queue.removeFirst();
      _inFlight++;
      try {
        await _deliver(notice);
      } finally {
        _inFlight--;
      }
    }
  }

  Future<DeliveryResult> _deliver(Map<String, Object?> notice) async {
    final base = _configuration.endpoint.endsWith('/')
        ? _configuration.endpoint
            .substring(0, _configuration.endpoint.length - 1)
        : _configuration.endpoint;
    final uri = Uri.parse(
        '$base/api/projects/${_configuration.projectSlug}/notices');

    final headers = <String, String>{
      'content-type': 'application/json',
      'user-agent': 'errorgap-flutter/$errorgapVersion',
    };
    final apiKey = _configuration.apiKey;
    if (apiKey != null && apiKey.isNotEmpty) {
      headers['x-errorgap-project-key'] = apiKey;
    }

    try {
      final response = await _http
          .post(uri, headers: headers, body: jsonEncode(notice))
          .timeout(Duration(seconds: _configuration.timeoutSeconds));
      return DeliveryResult(status: response.statusCode, body: response.body);
    } catch (e) {
      return DeliveryResult(error: e);
    }
  }
}
