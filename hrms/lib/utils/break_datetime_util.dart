// Parses break (and similar) timestamps from the API into local DateTime.
// Handles ISO with Z/offset, Mongo { $date: ... }, int epoch (ms or s).
//
// Naive ISO (no zone): some environments send UTC wall components without `Z`
// (Node/Express usually includes Z; other gateways may strip it). Others send
// the same shape as **local** wall time. Treating naive strings only as UTC
// can shift the instant hours ahead of the device clock so the break timer
// stays at 00:00:00 (elapsed clamped). We pick UTC-wall vs local-wall by
// plausibility vs [DateTime.now] with a small skew window.

bool _hasExplicitTimezone(String s) {
  final t = s.trim();
  if (t.endsWith('Z') || t.endsWith('z')) return true;
  // +05:30, +0530, -08:00
  return RegExp(r'[+-]\d{2}:\d{2}$').hasMatch(t) ||
      RegExp(r'[+-]\d{4}$').hasMatch(t);
}

/// [d] is from [DateTime.tryParse] on a string **without** an explicit zone
/// (Dart interprets that as **local** wall clock).
DateTime _naiveIsoToLocalBestEffort(DateTime d) {
  final now = DateTime.now();
  const skew = Duration(seconds: 120);

  final asLocalWall = d.isUtc ? d.toLocal() : d;

  final asUtcLocal = DateTime.utc(
    d.year,
    d.month,
    d.day,
    d.hour,
    d.minute,
    d.second,
    d.millisecond,
    d.microsecond,
  ).toLocal();

  bool plausible(DateTime t) => !t.isAfter(now.add(skew));

  final okUtc = plausible(asUtcLocal);
  final okLoc = plausible(asLocalWall);

  if (okUtc && !okLoc) return asUtcLocal;
  if (okLoc && !okUtc) return asLocalWall;
  if (okUtc && okLoc) {
    return asUtcLocal.isAfter(asLocalWall) ? asUtcLocal : asLocalWall;
  }
  // Both appear far in the future — do **not** return [DateTime.now]: this parser is invoked
  // on every parent rebuild and a fresh "now" would keep resetting the break timer to 00:00:00.
  // Return the earlier candidate (smallest shift from a bogus future); UI may clamp once.
  return asUtcLocal.isBefore(asLocalWall) ? asUtcLocal : asLocalWall;
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
    final n = value.round();
    return parseApiDateTimeToLocal(n);
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
    // Plain integer string = epoch (ms or s) from some gateways.
    if (RegExp(r'^\d{10,16}$').hasMatch(s)) {
      return parseApiDateTimeToLocal(int.parse(s));
    }
    final d = DateTime.tryParse(s);
    if (d == null) return null;
    return _naiveIsoToLocalBestEffort(d);
  }
  return null;
}
