import 'package:errorgap/errorgap.dart';
import 'package:test/test.dart';

void main() {
  test('traceCall records the trace id it sends on the http span', () async {
    final spans = ErrorgapSpanCollector();
    Map<String, String> sent = const {};
    final result = await spans.traceCall('GET /api/orders/7', (headers) {
      sent = headers;
      return 'ok';
    });
    expect(result, 'ok');
    final span = spans.snapshot().single;
    expect(span.kind, 'http');
    expect(span.function, 'GET /api/orders/7');
    expect(
        span.traceId,
        matches(RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
    expect(sent, {'x-errorgap-trace': span.traceId});
    expect(span.toJson()['trace_id'], span.traceId);
    expect(span.toJson()['fn_name'], 'GET /api/orders/7');
  });

  test('traceCall records the span when it throws; finish is idempotent',
      () async {
    final spans = ErrorgapSpanCollector();
    await expectLater(
      spans.traceCall<void>(
          'POST /api/pay', (_) => throw StateError('offline')),
      throwsStateError,
    );
    final call = spans.startCall('GET /api/menu');
    call.finish();
    call.finish();
    expect(spans.snapshot().map((s) => s.function),
        ['POST /api/pay', 'GET /api/menu']);
  });
}
