import 'dart:convert';

/// Compact JSON for WebSocket envelope / landmarks uplink.
///
/// - No whitespace
/// - Omits `null` map values
/// - Rounds doubles to [fractionDigits] (default 4) to shrink payload
String encodeCompactWsJson(
  Object? value, {
  int fractionDigits = 4,
}) {
  return jsonEncode(_compact(value, fractionDigits));
}

Object? _compact(Object? value, int fractionDigits) {
  if (value == null) return null;
  if (value is bool || value is String || value is int) return value;
  if (value is num) {
    final d = value.toDouble();
    if (d.isNaN || d.isInfinite) return 0;
    final scale = _pow10(fractionDigits);
    return (d * scale).round() / scale;
  }
  if (value is Map) {
    final out = <String, Object?>{};
    value.forEach((key, v) {
      if (v == null) return;
      final c = _compact(v, fractionDigits);
      if (c == null) return;
      out['$key'] = c;
    });
    return out;
  }
  if (value is Iterable) {
    return value.map((e) => _compact(e, fractionDigits)).toList(growable: false);
  }
  return value;
}

int _pow10(int n) {
  var p = 1;
  for (var i = 0; i < n; i++) {
    p *= 10;
  }
  return p;
}
