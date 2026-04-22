/// Parses Mongo extended JSON dates and ISO strings from API JSON.
DateTime? parseMongoJsonDate(dynamic raw) {
  if (raw == null) return null;
  if (raw is DateTime) return raw;
  if (raw is int) {
    return DateTime.fromMillisecondsSinceEpoch(raw, isUtc: true).toLocal();
  }
  if (raw is Map) {
    final inner = raw[r'$date'] ?? raw['\$date'];
    if (inner is int) {
      return DateTime.fromMillisecondsSinceEpoch(inner, isUtc: true)
          .toLocal();
    }
    if (inner is String) {
      return DateTime.tryParse(inner)?.toLocal();
    }
    if (inner is Map && inner[r'$numberLong'] != null) {
      final n = int.tryParse(inner[r'$numberLong'].toString());
      if (n != null) {
        return DateTime.fromMillisecondsSinceEpoch(n, isUtc: true).toLocal();
      }
    }
  }
  final s = raw.toString().trim();
  if (s.isEmpty) return null;
  return DateTime.tryParse(s)?.toLocal();
}

/// India (IST) calendar day as `yyyy-MM-dd` for matching attendance rows to UI days.
///
/// Backend often stores the logical workday as UTC instant at **previous** calendar
/// day's 18:30Z (= midnight IST). Using the UTC date prefix (`split('T').first`)
/// shifts rows one day early in the app.
String? attendanceIndiaCalendarKey(dynamic dateField) {
  if (dateField == null) return null;
  if (dateField is DateTime) {
    return _utcInstantToIndiaYyyyMmDd(dateField);
  }
  if (dateField is int) {
    return _utcInstantToIndiaYyyyMmDd(
      DateTime.fromMillisecondsSinceEpoch(dateField, isUtc: true),
    );
  }
  if (dateField is String) {
    final t = dateField.trim();
    if (t.isEmpty) return null;
    if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(t)) return t;
    try {
      return _utcInstantToIndiaYyyyMmDd(DateTime.parse(t));
    } catch (_) {
      return null;
    }
  }
  final parsed = parseMongoJsonDate(dateField);
  if (parsed == null) return null;
  return _utcInstantToIndiaYyyyMmDd(parsed);
}

String _utcInstantToIndiaYyyyMmDd(DateTime instant) {
  final shifted = instant.toUtc().add(const Duration(hours: 5, minutes: 30));
  final y = shifted.year;
  final m = shifted.month;
  final d = shifted.day;
  return '${y.toString().padLeft(4, '0')}-'
      '${m.toString().padLeft(2, '0')}-'
      '${d.toString().padLeft(2, '0')}';
}
