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
    } else if (value is List) {
      out[key] = value.map((item) => _walkValue(item, lowered)).toList();
    } else {
      out[key] = value;
    }
  });
  return out;
}

Object? _walkValue(Object? value, List<String> lowered) {
  if (value is Map<String, Object?>) return _walk(value, lowered);
  if (value is Map) {
    final coerced = <String, Object?>{};
    value.forEach((Object? key, Object? item) {
      coerced[key.toString()] = item;
    });
    return _walk(coerced, lowered);
  }
  if (value is List) {
    return value.map((item) => _walkValue(item, lowered)).toList();
  }
  return value;
}

bool _isSensitive(String key, List<String> lowered) {
  final lk = key.toLowerCase();
  for (final needle in lowered) {
    if (lk.contains(needle)) return true;
  }
  return false;
}
