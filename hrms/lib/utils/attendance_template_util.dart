/// Coerces JSON [raw] from `/attendance/today` into a typed map (or null).
Map<String, dynamic>? asAttendanceTemplateMap(dynamic raw) {
  if (raw == null) return null;
  if (raw is Map<String, dynamic>) return raw;
  if (raw is Map) return Map<String, dynamic>.from(raw);
  return null;
}

/// Backend sends `{}` when no template; treat empty maps like "no template".
bool isValidAttendanceTemplateMap(Map<String, dynamic>? template) {
  return template != null && template.isNotEmpty;
}

/// [profileAttendanceTemplateRef] is `staffData.attendanceTemplateId` (string id, `$oid` map, or populated doc).
bool profileIndicatesAttendanceTemplateRef(dynamic v) {
  if (v == null) return false;
  if (v is String) return v.trim().isNotEmpty;
  if (v is Map) {
    final m = Map<String, dynamic>.from(v);
    if (m.isEmpty) return false;
    final id = m['_id'] ?? m[r'$oid'];
    if (id != null && id.toString().trim().isNotEmpty) return true;
    if (m['name'] != null) return true;
    if (m['shiftStartTime'] != null || m['shiftEndTime'] != null) {
      return true;
    }
    return false;
  }
  return false;
}

/// True if today's API returned a usable template, or profile still has a template ref.
bool staffHasAssignedAttendanceTemplate({
  dynamic profileAttendanceTemplateRef,
  Map<String, dynamic>? todayAttendanceTemplate,
}) {
  if (isValidAttendanceTemplateMap(todayAttendanceTemplate)) return true;
  return profileIndicatesAttendanceTemplateRef(profileAttendanceTemplateRef);
}
