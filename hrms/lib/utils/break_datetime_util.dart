// Parses break (and similar) timestamps from the API into local DateTime.
// Handles ISO with Z/offset, Mongo { $date: ... }, int epoch (ms or s).
// Naive ISO without a zone is treated as UTC wall time.

bool _hasExplicitTimezone(String s) {
  final t = s.trim();
  if (t.endsWith('Z') || t.endsWith('z')) return true;
  // +05:30, +0530, -08:00
  return RegExp(r'[+-]\d{2}:\d{2}$').hasMatch(t) ||
      RegExp(r'[+-]\d{4}$').hasMatch(t);
}

DateTime? parseApiDateTimeToLocal(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) {
    return value.isUtc ? value.toLocal() : value;
  }
  if (value is int) {
    final abs = value.abs();
    // Heuristic: seconds vs milliseconds since epoch
    final ms = abs < 2000000000000 ? value * 1000 : value;
    return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toLocal();
  }
  if (value is num) {
    return parseApiDateTimeToLocal(value.toInt());
  }
  if (value is Map) {
    final inner =
        value[r'$date'] ?? value['date'] ?? value['Date'];
    return parseApiDateTimeToLocal(inner);
  }
  if (value is String) {
    final s = value.trim();
    if (s.isEmpty) return null;
    if (_hasExplicitTimezone(s)) {
      final d = DateTime.tryParse(s);
      return d?.toLocal();
    }
    final d = DateTime.tryParse(s);
    if (d == null) return null;
    // No zone: interpret components as UTC (avoids "UTC instant shown as local wall" bug).
    return DateTime.utc(
      d.year,
      d.month,
      d.day,
      d.hour,
      d.minute,
      d.second,
      d.millisecond,
      d.microsecond,
    ).toLocal();
  }
  return null;
}
