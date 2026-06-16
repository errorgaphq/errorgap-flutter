const String filteredValue = '[FILTERED]';

Map<String, Object?> filterParams(
  Map<String, Object?>? params,
  List<String> filterKeys,
) {
  if (params == null || params.isEmpty) return <String, Object?>{};
  final lowered = filterKeys.map((String k) => k.toLowerCase()).toList();
  return _walk(params, lowered);
}

Map<String, Object?> _walk(Map<String, Object?> input, List<String> lowered) {
  final out = <String, Object?>{};
  input.forEach((String key, Object? value) {
    if (_isSensitive(key, lowered)) {
      out[key] = filteredValue;
    } else if (value is Map<String, Object?>) {
      out[key] = _walk(value, lowered);
    } else if (value is Map) {
      // Coerce dynamic map keys to strings.
      final coerced = <String, Object?>{};
      value.forEach((Object? k, Object? v) => coerced[k.toString()] = v);
      out[key] = _walk(coerced, lowered);
    } else {
      out[key] = value;
    }
  });
  return out;
}

bool _isSensitive(String key, List<String> lowered) {
  final lk = key.toLowerCase();
  for (final needle in lowered) {
    if (lk.contains(needle)) return true;
  }
  return false;
}
