import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import 'configuration.dart';
import 'platform_environment.dart';

/// Options for session replay. Mobile sessions are timeline only: no
/// screenshots or view snapshots are taken.
class ErrorgapReplayOptions {
  const ErrorgapReplayOptions({
    this.appName,
    this.os,
    this.device = 'Mobile',
    this.flushInterval = const Duration(seconds: 10),
  });

  /// Shown with the release as the session's "browser", e.g. `Acme 2.3.0`.
  final String? appName;

  /// Defaults to the platform, e.g. `iOS` or `Android`.
  final String? os;

  /// `Mobile` or `Tablet`.
  final String device;

  /// How often recorded events are sent.
  final Duration flushInterval;
}

/// A session ends once the app has been paused this long.
const Duration replayBackgroundTimeout = Duration(minutes: 30);
const int replayMaxBatchEvents = 200;
const int _maxBufferedEvents = 1000;
const int _maxLabel = 200;

enum _State { pending, recording, skipped, stopped }

/// Records a session replay timeline: app start, screens, failed API calls,
/// reported errors and backgrounding. Whether a session is recorded is the
/// project's call: its replay settings are read when each session starts, and
/// a sampled share of sessions is recorded while replay is on.
class ErrorgapReplayRecorder {
  ErrorgapReplayRecorder(this._configuration, this._http, this._options);

  final ErrorgapConfiguration _configuration;
  final http.Client _http;
  final ErrorgapReplayOptions _options;
  final Random _random = Random();

  _State _state = _State.pending;
  String _sessionId = '';
  DateTime _startedAt = DateTime.now();
  bool _hadError = false;
  List<Map<String, Object?>> _events = <Map<String, Object?>>[];
  String? _lastScreen;
  DateTime? _pausedAt;
  Timer? _timer;

  bool get recording => _state == _State.recording;

  String get _base {
    final endpoint = _configuration.endpoint.endsWith('/')
        ? _configuration.endpoint
            .substring(0, _configuration.endpoint.length - 1)
        : _configuration.endpoint;
    return '$endpoint/api/projects/${_configuration.projectSlug}';
  }

  void start() => _newSession('App started');

  void stop() {
    _timer?.cancel();
    _timer = null;
    _state = _State.stopped;
    _events = <Map<String, Object?>>[];
  }

  /// A screen is now showing.
  void screen(String name) {
    if (name.isEmpty || name == _lastScreen) return;
    _lastScreen = name;
    _push('navigation', 'Opened $name');
  }

  /// The app went to the background.
  void paused() {
    if (_state == _State.stopped || _pausedAt != null) return;
    _pausedAt = DateTime.now();
    _push('exit', 'App went to the background');
    unawaited(flush(finalBatch: true));
  }

  /// The app is in the foreground again.
  void resumed() {
    final pausedAt = _pausedAt;
    if (_state == _State.stopped || pausedAt == null) return;
    _pausedAt = null;
    if (DateTime.now().difference(pausedAt) >= replayBackgroundTimeout) {
      _newSession('App opened');
    } else {
      _push('navigation', 'Returned to the app');
    }
  }

  /// An error is being reported; call the result with its group id once the
  /// server has answered.
  void Function(String? groupId) errorStarted(String label) {
    if (!_active) return (_) {};
    final t = _offset();
    final session = _sessionId;
    _hadError = true;
    var done = false;
    return (String? groupId) {
      if (done || session != _sessionId) return;
      done = true;
      _push('error', label, t: t, groupId: groupId);
      unawaited(flush());
    };
  }

  /// A call failed or answered 5xx (see `ErrorgapHttpClient`).
  void apiError(String method, Uri url, int status) {
    // No query string: it carries tokens and ids.
    final shown = (url.scheme == 'http' || url.scheme == 'https')
        ? '${url.origin}${url.path}'
        : url.path;
    _push('api_error',
        '${method.toUpperCase()} $shown → ${status == 0 ? 'failed' : status}');
  }

  Future<void> flush({bool finalBatch = false}) async {
    if (_state != _State.recording) return;
    var last = finalBatch;
    do {
      final batch = _events.take(replayMaxBatchEvents).toList();
      _events = _events.skip(batch.length).toList();
      if (batch.isEmpty && !last) return;
      await _send(_batch(batch, last));
      last = false;
    } while (_events.isNotEmpty && _state == _State.recording);
  }

  bool get _active => _state == _State.pending || _state == _State.recording;

  void _newSession(String label) {
    _timer?.cancel();
    _timer = null;
    _state = _State.pending;
    _sessionId = _uuid();
    _startedAt = DateTime.now();
    _hadError = false;
    _events = <Map<String, Object?>>[];
    _lastScreen = null;
    _push('page_load', label);
    unawaited(_decide(_sessionId));
  }

  Future<void> _decide(String session) async {
    var record = false;
    try {
      final key = _configuration.apiKey;
      final query = key == null || key.isEmpty
          ? ''
          : '?api_key=${Uri.encodeQueryComponent(key)}';
      final response = await _http
          .get(Uri.parse('$_base/sessions/config$query'))
          .timeout(Duration(seconds: _configuration.timeoutSeconds));
      if (response.statusCode == 200) {
        final config = jsonDecode(response.body) as Map<String, Object?>;
        final rate = (config['sample_rate'] as num?)?.toDouble() ?? 0;
        record = config['enabled'] == true && _random.nextDouble() < rate;
      }
    } catch (_) {
      // Settings unreadable (offline, wrong key): not recorded.
    }
    if (session != _sessionId || _state != _State.pending) return;
    if (!record) {
      _skip();
      return;
    }
    _state = _State.recording;
    _timer = Timer.periodic(_options.flushInterval, (_) => unawaited(flush()));
    await flush();
  }

  void _skip() {
    _timer?.cancel();
    _timer = null;
    _state = _State.skipped;
    _events = <Map<String, Object?>>[];
  }

  void _push(String type, String label, {int? t, String? groupId}) {
    if (!_active || _events.length >= _maxBufferedEvents) return;
    _events.add(<String, Object?>{
      't': t ?? _offset(),
      'type': type,
      'label': label.length > _maxLabel
          ? '${label.substring(0, _maxLabel - 1)}…'
          : label,
      if (groupId != null) 'group_id': groupId,
    });
  }

  Map<String, Object?> _batch(List<Map<String, Object?>> events, bool last) {
    final now = DateTime.now();
    final app = _options.appName ?? 'App';
    final release = _configuration.release;
    return <String, Object?>{
      'session': <String, Object?>{
        'id': _sessionId,
        'handle': null,
        'browser': release == null || release.isEmpty ? app : '$app $release',
        'os': _options.os ?? operatingSystemLabel(),
        'device': _options.device,
        'started_at': _startedAt.toUtc().toIso8601String(),
        'ended_at': now.toUtc().toIso8601String(),
        'duration_sec': _offset(now),
        'outcome': _hadError ? 'error' : (last ? 'completed' : 'abandoned'),
      },
      'events': events,
      'snapshots': const <Object>[],
    };
  }

  Future<void> _send(Map<String, Object?> body) async {
    final session = _sessionId;
    final headers = <String, String>{'content-type': 'application/json'};
    final key = _configuration.apiKey;
    if (key != null && key.isNotEmpty) headers['x-errorgap-project-key'] = key;
    try {
      final response = await _http
          .post(Uri.parse('$_base/sessions'),
              headers: headers, body: jsonEncode(body))
          .timeout(Duration(seconds: _configuration.timeoutSeconds));
      // Replay switched off, or the session belongs elsewhere: stop this session.
      const refused = <int>{204, 401, 404, 409};
      if (refused.contains(response.statusCode) &&
          session == _sessionId &&
          _state == _State.recording) {
        _skip();
      }
    } catch (_) {
      // Replay is best effort.
    }
  }

  int _offset([DateTime? now]) {
    final seconds =
        ((now ?? DateTime.now()).difference(_startedAt).inMilliseconds / 1000)
            .round();
    return seconds < 0 ? 0 : seconds;
  }

  String _uuid() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
        '${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}

/// An `http.Client` that records failed calls (network errors and 5xx) in
/// the session replay timeline. Use it for your app's API calls:
///
/// ```dart
/// final api = ErrorgapHttpClient(http.Client());
/// ```
class ErrorgapHttpClient extends http.BaseClient {
  ErrorgapHttpClient(this._inner,
      {ErrorgapReplayRecorder? Function()? recorder})
      : _recorder = recorder;

  final http.Client _inner;
  final ErrorgapReplayRecorder? Function()? _recorder;

  /// Set by `Errorgap.init`; the recorder of the current session, if any.
  static ErrorgapReplayRecorder? Function() currentRecorder = () => null;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final recorder = (_recorder ?? currentRecorder)();
    try {
      final response = await _inner.send(request);
      if (response.statusCode >= 500) {
        recorder?.apiError(request.method, request.url, response.statusCode);
      }
      return response;
    } catch (_) {
      recorder?.apiError(request.method, request.url, 0);
      rethrow;
    }
  }

  @override
  void close() => _inner.close();
}
