// Parses break timestamps from the API into the device local [DateTime].
// Server / Mongo stores instants in UTC. Handles:
// - ISO-8601 with `Z` or numeric offset
// - Naive ISO (no zone): wall clock is **UTC** (some serializers omit `Z`)
// - Mongo extended JSON: { "\$date": "<iso>" | <epoch> }
// - Epoch: seconds vs ms (ms values are >= 1e10 for years 2001+)

import 'break_flow_log.dart';

bool _hasExplicitTimezone(String s) {
  final t = s.trim();
  if (t.endsWith('Z') || t.endsWith('z')) return true;
  return RegExp(r'[+-]\d{2}:\d{2}$').hasMatch(t) ||
      RegExp(r'[+-]\d{4}$').hasMatch(t);
}

/// Epoch from API: values this large are ms since epoch; smaller values are seconds.
int _utcMillisFromEpochNum(int signed) {
  final abs = signed.abs();
  if (abs >= 10000000000) return signed;
  return signed * 1000;
}

/// [d] comes from [DateTime.tryParse] on a **naive** string (no zone). Dart assigns
/// those components in local mode, but we reinterpret the same numbers as UTC wall
/// time then convert to local (matches Mongo UTC storage when `Z` is omitted).
DateTime _naiveIsoUtcWallComponentsToLocal(DateTime d) {
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

String _describeBreakRawForLog(dynamic v) {
  if (v == null) return 'null';
  if (v is DateTime) return 'DateTime(${v.toIso8601String()})';
  if (v is int || v is num) return '${v.runtimeType}($v)';
  if (v is String) {
    final len = v.length;
    final head = len > 64 ? '${v.substring(0, 64)}…' : v;
    return 'String(len=$len, head=$head)';
  }
  if (v is Map) {
    final keys = v.keys.take(8).map((k) => k.toString()).join(',');
    return 'Map(keys=[$keys])';
  }
  return v.runtimeType.toString();
}

DateTime? _parseApiDateTimeToLocalImpl(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) {
    return value.isUtc ? value.toLocal() : value;
  }
  if (value is int) {
    final ms = _utcMillisFromEpochNum(value);
    return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toLocal();
  }
  if (value is num) {
    final n = value.round();
    return _parseApiDateTimeToLocalImpl(n);
  }
  if (value is Map) {
    final inner = value[r'$date'] ?? value['date'] ?? value['Date'];
    return _parseApiDateTimeToLocalImpl(inner);
  }
  if (value is String) {
    final s = value.trim();
    if (s.isEmpty) return null;
    if (_hasExplicitTimezone(s)) {
      final d = DateTime.tryParse(s);
      return d?.toLocal();
    }
    if (RegExp(r'^\d{10,16}$').hasMatch(s)) {
      return _parseApiDateTimeToLocalImpl(int.parse(s));
    }
    final d = DateTime.tryParse(s);
    if (d == null) return null;
    return _naiveIsoUtcWallComponentsToLocal(d);
  }
  return null;
}

DateTime? parseApiDateTimeToLocal(dynamic value) {
  final out = _parseApiDateTimeToLocalImpl(value);
  if (breakDateTimeParseLoggingEnabled) {
    final wall = out != null
        ? '${out.hour}:${out.minute.toString().padLeft(2, '0')}'
        : '-';
    breakFlowLog(
      'parse ${_describeBreakRawForLog(value)} -> ${out?.toIso8601String() ?? "null"} (local $wall)',
    );
  }
  return out;
}

/// UTC calendar day boundary (same idea as attendance [date] / server check-in).
DateTime _startOfUtcDay([DateTime? fromUtc]) {
  final u = (fromUtc ?? DateTime.now().toUtc()).toUtc();
  return DateTime.utc(u.year, u.month, u.day);
}

/// Ongoing break timer should not use a [startLocal] from a **previous** UTC day
/// (e.g. yesterday's unclosed break). Server closes those rows; this is a client safety net.
DateTime breakStartTimeForDisplay(DateTime startLocal) {
  final startUtc = startLocal.toUtc();
  final todayStartUtc = _startOfUtcDay();
  if (startUtc.isBefore(todayStartUtc)) {
    return DateTime.now();
  }
  return startLocal;
}

/// Parse API [startTime] then apply [breakStartTimeForDisplay].
DateTime? breakDisplayStartFromApi(dynamic startTimeRaw) {
  final parsed = parseApiDateTimeToLocal(startTimeRaw);
  if (parsed == null) return null;
  return breakStartTimeForDisplay(parsed);
}
