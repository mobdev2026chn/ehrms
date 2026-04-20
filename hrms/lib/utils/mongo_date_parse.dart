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
