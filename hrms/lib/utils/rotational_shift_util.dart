/// Resolves company embedded shifts (standard / rotational / open) per calendar day.
/// Parity with app_backend [getShiftTimings] + [resolveEffectiveShiftRaw].
library;

import 'package:flutter/foundation.dart';

String _calendarDateLog(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Set to `true` only when debugging shift calendar resolution (very chatty per day).
const _kLogShiftCalendarRows = false;

void _debugLogShiftCalendarRow({
  required DateTime dayLocal,
  required String message,
}) {
  if (!kDebugMode || !_kLogShiftCalendarRows) return;
  debugPrint('[ShiftCalendar] date=${_calendarDateLog(dayLocal)} $message');
}

double _shiftSpanHours(String startTime, String endTime) {
  final startParts = startTime.split(':');
  final endParts = endTime.split(':');
  final startHours = int.parse(startParts[0]);
  final startMinutes = int.parse(startParts[1]);
  final endHours = int.parse(endParts[0]);
  final endMinutes = int.parse(endParts[1]);
  var startTotal = startHours * 60 + startMinutes;
  var endTotal = endHours * 60 + endMinutes;
  var diff = endTotal - startTotal;
  if (diff < 0) diff += 24 * 60;
  return diff / 60;
}

int utcCalendarDayDiff(DateTime a, DateTime b) {
  final da = DateTime.utc(a.year, a.month, a.day);
  final db = DateTime.utc(b.year, b.month, b.day);
  return da.difference(db).inDays;
}

/// JS `Date.UTC(y,m,d).getUTCDay()`: 0 = Sunday … 6 = Saturday.
/// Uses the same Y/M/D interpretation as [utcCalendarDayDiff] (local date fields as UTC wall date).
int utcCalendarWeekdayJsStyle(DateTime attendanceDay) {
  final utc = DateTime.utc(
    attendanceDay.year,
    attendanceDay.month,
    attendanceDay.day,
  );
  final w = utc.weekday; // Dart: Mon=1 … Sun=7
  return w == DateTime.sunday ? 0 : w;
}

/// Rotational config: [rotationType] `weekly` | `daily` | `custom` | `byWeekday` (default custom).
/// - **weekly**: slot index from UTC calendar weekday, mod [cycleLengthDays] (or array length).
/// - **byWeekday**: [shiftIdsByWeekday] maps JS weekday (Sun=0) → shift id; UI cycle uses len 7.
/// - **custom** / **daily**: days since [anchorDay] on UTC calendar, mod cycle length (same as backend).
({int idx, int cycleLen, String rotationType}) computeRotationalCycleIndex(
  Map<String, dynamic> cfg,
  DateTime attendanceDay,
  DateTime anchorDay,
) {
  var rotType = (cfg['rotationType'] ?? 'custom').toString().toLowerCase().trim();
  if (rotType.isEmpty) rotType = 'custom';

  if (rotType == 'byweekday' || rotType == 'by_weekday') {
    final byWd =
        (cfg['shiftIdsByWeekday'] as List?)?.where((e) => e != null).toList() ??
            [];
    if (byWd.isEmpty) {
      return (idx: 0, cycleLen: 0, rotationType: rotType);
    }
    final jsDow = utcCalendarWeekdayJsStyle(attendanceDay);
    return (idx: jsDow, cycleLen: 7, rotationType: rotType);
  }

  final ids =
      (cfg['shiftIdsInCycle'] as List?)?.where((e) => e != null).toList() ?? [];
  final names = (cfg['shiftNamesInCycle'] as List?)
          ?.where((e) => e != null)
          .map((e) => e.toString())
          .toList() ??
      [];

  var cycleLen = (cfg['cycleLengthDays'] as num?)?.toInt() ?? 0;
  if (cycleLen <= 0) {
    cycleLen = ids.isNotEmpty ? ids.length : names.length;
  }
  if (cycleLen <= 0) {
    return (idx: 0, cycleLen: 0, rotationType: rotType);
  }

  int idx;
  if (rotType == 'weekly') {
    idx = utcCalendarWeekdayJsStyle(attendanceDay) % cycleLen;
  } else {
    var diff = utcCalendarDayDiff(attendanceDay, anchorDay);
    idx = diff % cycleLen;
    if (idx < 0) idx += cycleLen;
  }
  return (idx: idx, cycleLen: cycleLen, rotationType: rotType);
}

/// Normalizes Mongo ObjectId from JSON (hex string or `{ "\$oid": "..." }`).
/// Returns lowercase 24-char hex only (no arbitrary strings — avoids bad cycle matches).
String? mongoIdToHexString(dynamic v) {
  if (v == null) return null;
  if (v is String) {
    final t = v.trim();
    if (t.isEmpty) return null;
    if (RegExp(r'^[a-fA-F0-9]{24}$').hasMatch(t)) return t.toLowerCase();
    return null;
  }
  if (v is Map) {
    final o = v[r'$oid'] ?? v['\$oid'] ?? v['oid'];
    if (o != null) return mongoIdToHexString(o);
  }
  return null;
}

/// Like [mongoIdToHexString] but also pulls the first 24 hex run from `toString()` (legacy / odd serializers).
String? objectIdHexLoose(dynamic v) {
  final strict = mongoIdToHexString(v);
  if (strict != null) return strict;
  final s = v?.toString();
  if (s == null || s.isEmpty) return null;
  final m = RegExp(r'([a-fA-F0-9]{24})').firstMatch(s);
  return m != null ? m.group(1)!.toLowerCase() : null;
}

bool _sameObjectId(dynamic a, dynamic b) {
  final ha = objectIdHexLoose(a);
  final hb = objectIdHexLoose(b);
  if (ha != null && hb != null) return ha == hb;
  return false;
}

/// Staff row may omit [rotationalConfig] while another embedded shift row (same _id/name) still has the cycle.
Map<String, dynamic> wrapperWithMergedRotationalConfig(
  List<dynamic> shifts,
  Map<String, dynamic> wrapper,
) {
  if (shiftRowHasRotationalCycle(wrapper)) return wrapper;
  final wname = (wrapper['name'] ?? '').toString().trim().toLowerCase();
  final wid = objectIdHexLoose(wrapper['_id']);
  for (final raw in shifts) {
    if (raw is! Map) continue;
    final s = Map<String, dynamic>.from(raw);
    if (!shiftRowHasRotationalCycle(s)) continue;
    final rc = s['rotationalConfig'];
    if (rc is! Map) continue;
    final sname = (s['name'] ?? '').toString().trim().toLowerCase();
    final sid = objectIdHexLoose(s['_id']);
    final sameId = wid != null && sid != null && wid == sid;
    final sameName = wname.isNotEmpty && wname == sname;
    if (sameId || sameName) {
      final out = Map<String, dynamic>.from(wrapper);
      out['rotationalConfig'] = Map<String, dynamic>.from(rc);
      return out;
    }
  }
  return wrapper;
}

bool _isMongoObjectIdHexString(String raw) {
  final k = raw.trim();
  return k.length == 24 && RegExp(r'^[a-fA-F0-9]{24}$').hasMatch(k);
}

bool _shiftRowMatchesStaffKey(Map<String, dynamic> s, String keyRaw) {
  final k = keyRaw.trim();
  if (k.isEmpty) return false;
  // Staff may store embedded shift _id in shiftName/shiftId — match by id only (no name collision).
  if (_isMongoObjectIdHexString(k)) {
    final sid = mongoIdToHexString(s['_id']);
    return sid != null && sid == k.toLowerCase();
  }
  final sid = mongoIdToHexString(s['_id']);
  final kidHex = mongoIdToHexString(k);
  if (kidHex != null &&
      kidHex.length == 24 &&
      sid != null &&
      sid == kidHex) {
    return true;
  }
  final name = s['name']?.toString().trim();
  if (name != null && name.toLowerCase() == k.toLowerCase()) return true;
  return false;
}

/// Converts stored open-shift duration to **hours** (e.g. 540 → 9, 9 → 9).
double? normalizeOpenShiftHoursValue(double? raw) {
  if (raw == null || raw <= 0) return null;
  if (raw > 24 && raw <= 1440) return raw / 60.0;
  return raw;
}

double? _parsePositiveNumber(dynamic v) {
  if (v == null) return null;
  if (v is num) {
    final d = v.toDouble();
    return d > 0 ? d : null;
  }
  final p = double.tryParse(v.toString().trim());
  if (p != null && p > 0) return p;
  return null;
}

/// Open / template row: prefer [openWorkHours] (GET /attendance/today) then [workHours] (company embed).
double? readOpenWorkHoursFromShiftMap(Map<String, dynamic> m) {
  for (final key in ['openWorkHours', 'workHours']) {
    final parsed = _parsePositiveNumber(m[key]);
    final norm = normalizeOpenShiftHoursValue(parsed);
    if (norm != null && norm > 0) return norm;
  }
  return null;
}

/// Parity with app_backend [resolveOpenShiftWorkHoursRaw]: re-scan company.shifts when [shift] map lacks hours.
double? resolveOpenShiftWorkHoursFromCompany(
  Map<String, dynamic>? companyDoc,
  Map<String, dynamic> shift,
) {
  final direct = readOpenWorkHoursFromShiftMap(shift);
  if (direct != null && direct > 0) return direct;
  final shifts = shiftsListFromCompany(companyDoc);
  if (shifts == null) return null;
  final sid = mongoIdToHexString(shift['_id']);
  final sname = shift['name']?.toString().trim().toLowerCase();
  for (final raw in shifts) {
    if (raw is! Map) continue;
    final m = Map<String, dynamic>.from(raw);
    final mid = mongoIdToHexString(m['_id']);
    final nm = m['name']?.toString().trim().toLowerCase() ?? '';
    final idMatch = sid != null && mid != null && sid == mid;
    final nameMatch =
        sname != null && sname.isNotEmpty && nm == sname;
    if (!idMatch && !nameMatch) continue;
    final h = readOpenWorkHoursFromShiftMap(m);
    if (h != null && h > 0) return h;
  }
  return null;
}

int? readOtBufferMinutesFromMap(Map<String, dynamic>? m) {
  if (m == null || m.isEmpty) return null;
  final raw = m['otBufferMinutes'];
  if (raw is num) {
    final v = raw.round();
    return v < 0 ? 0 : v;
  }
  final p = int.tryParse(raw?.toString() ?? '');
  if (p == null) return null;
  return p < 0 ? 0 : p;
}

/// Merged template from GET /attendance/today (shiftType + openWorkHours set by server).
double? readOpenHoursFromAttendanceTodayTemplate(Map<String, dynamic>? t) {
  if (t == null || t.isEmpty) return null;
  final st = (t['shiftType'] ?? '').toString().toLowerCase().trim();
  if (st != 'open' && st != 'open shift') return null;
  for (final key in ['openWorkHours', 'workHours']) {
    final parsed = _parsePositiveNumber(t[key]);
    final norm = normalizeOpenShiftHoursValue(parsed);
    if (norm != null && norm > 0) return norm;
  }
  return null;
}

/// Stable shift assignment key from profile [staffData] (parity with app_backend staffShiftKeyFromStaff).
/// Handles [shiftId] as hex string or `{ "\$oid": "..." }`. When [attendanceTemplateName] is set and
/// [shiftName] equals it (HR sometimes stores the template title in shiftName), returns null so callers
/// can fall back to the first company shift like the server.
String? staffShiftKeyFromProfileMap(
  Map<String, dynamic> staffData, {
  String? attendanceTemplateName,
}) {
  final sid = objectIdHexLoose(staffData['shiftId']) ??
      mongoIdToHexString(staffData['shiftId']);
  if (sid != null && sid.isNotEmpty) return sid;
  final sn = staffData['shiftName']?.toString().trim();
  if (sn == null || sn.isEmpty) return null;
  final tl = attendanceTemplateName?.trim();
  if (tl != null && tl.isNotEmpty && sn == tl) return null;
  return sn;
}

/// When staff key is literally "open", prefer the open shift row (same as backend findShiftByStaffKey).
Map<String, dynamic>? findShiftByStaffKey(List<dynamic> shifts, String key) {
  final k = key.trim();
  if (k.isEmpty) return null;
  final keyLower = k.toLowerCase();
  if (keyLower == 'open' || keyLower == 'open shift') {
    for (final raw in shifts) {
      if (raw is! Map) continue;
      final s = Map<String, dynamic>.from(raw);
      final st = (s['shiftType'] ?? '').toString().toLowerCase();
      if (st == 'open' || st == 'open shift') return s;
      final nm = (s['name'] ?? '').toString().trim().toLowerCase();
      if (nm == 'open' || nm == 'open shift') return s;
    }
  }
  return findShiftByKey(shifts, key);
}

Map<String, dynamic>? findShiftByKey(List<dynamic> shifts, String key) {
  final k = key.trim();
  if (k.isEmpty) return null;
  final matches = <Map<String, dynamic>>[];
  for (final raw in shifts) {
    if (raw is! Map) continue;
    final s = Map<String, dynamic>.from(raw);
    if (_shiftRowMatchesStaffKey(s, k)) matches.add(s);
  }
  if (matches.isEmpty) return null;
  if (matches.length == 1) return matches.first;
  // Duplicate names in company.shifts: first row may be a legacy standard copy
  // without rotationalConfig; prefer the real rotational wrapper.
  for (final s in matches) {
    if (isRotationalShiftWrapper(s)) return s;
  }
  for (final s in matches) {
    if (shiftRowHasRotationalCycle(s)) return s;
  }
  return matches.first;
}

/// Non-empty [shiftIdsInCycle], [shiftNamesInCycle], or [shiftIdsByWeekday] on [rotationalConfig].
bool shiftRowHasRotationalCycle(Map<String, dynamic> wrapper) {
  final cfgRaw = wrapper['rotationalConfig'];
  if (cfgRaw is! Map) return false;
  final cfg = Map<String, dynamic>.from(cfgRaw);
  final ids =
      (cfg['shiftIdsInCycle'] as List?)?.where((e) => e != null).toList() ??
          [];
  final names =
      (cfg['shiftNamesInCycle'] as List?)?.where((e) => e != null).toList() ??
          [];
  final byWd =
      (cfg['shiftIdsByWeekday'] as List?)?.where((e) => e != null).toList() ??
          [];
  return ids.isNotEmpty || names.isNotEmpty || byWd.isNotEmpty;
}

/// Rotational wrapper: explicit [shiftType] **or** a cycle config (web often relies on config).
bool isRotationalShiftWrapper(Map<String, dynamic> wrapper) {
  final st = (wrapper['shiftType'] ?? '').toString().toLowerCase().trim();
  if (st == 'rotational') return true;
  return shiftRowHasRotationalCycle(wrapper);
}

/// Row that can be a **slot** in a rotation (has a concrete window or is clearly not a template).
/// Excludes the template row when it has a cycle config but no fixed window.
bool isLeafShiftRow(Map<String, dynamic> s) {
  if (!isRotationalShiftWrapper(s)) return true;
  final win = readStandardShiftWindowFromMap(s);
  final hasWindow = win.start != null && win.end != null;
  if (hasWindow && !shiftRowHasRotationalCycle(s)) {
    return true;
  }
  return false;
}

/// Resolves a rotational wrapper to the effective shift row for [attendanceDay].
Map<String, dynamic> resolveEffectiveShiftForDate(
  List<dynamic> shifts,
  Map<String, dynamic> wrapper,
  DateTime attendanceDay,
  DateTime anchorDay,
) {
  final wResolved = wrapperWithMergedRotationalConfig(shifts, wrapper);
  if (!isRotationalShiftWrapper(wResolved)) return wResolved;
  final cfgRaw = wResolved['rotationalConfig'];
  if (cfgRaw is! Map) return wResolved;
  final cfg = Map<String, dynamic>.from(cfgRaw);
  final rotType = (cfg['rotationType'] ?? 'custom').toString().toLowerCase().trim();

  if (rotType == 'byweekday' || rotType == 'by_weekday') {
    final entries =
        (cfg['shiftIdsByWeekday'] as List?)?.where((e) => e != null).toList() ??
            [];
    if (entries.isEmpty) return wResolved;
    final jsDow = utcCalendarWeekdayJsStyle(attendanceDay);
    for (final e in entries) {
      if (e is! Map) continue;
      final em = Map<String, dynamic>.from(e);
      if ((em['day'] as num?)?.toInt() != jsDow) continue;
      final effectiveIdRaw = em['shiftId'] ?? em['shift_id'];
      for (final raw in shifts) {
        if (raw is! Map) continue;
        final s = Map<String, dynamic>.from(raw);
        if (!isLeafShiftRow(s)) continue;
        if (_sameObjectId(effectiveIdRaw, s['_id'])) {
          return s;
        }
      }
      return wResolved;
    }
    return wResolved;
  }

  final ids =
      (cfg['shiftIdsInCycle'] as List?)?.where((e) => e != null).toList() ??
          [];
  final names = (cfg['shiftNamesInCycle'] as List?)
          ?.where((e) => e != null)
          .map((e) => e.toString())
          .toList() ??
      [];
  final cycle = computeRotationalCycleIndex(cfg, attendanceDay, anchorDay);
  if (cycle.cycleLen <= 0) return wResolved;
  final idx = cycle.idx;
  final effectiveIdRaw = ids.isNotEmpty ? ids[idx % ids.length] : null;
  final effectiveName =
      names.isNotEmpty ? names[idx % names.length] : null;
  final nameLower =
      effectiveName != null ? effectiveName.trim().toLowerCase() : '';

  Map<String, dynamic>? byId;
  if (effectiveIdRaw != null) {
    for (final raw in shifts) {
      if (raw is! Map) continue;
      final s = Map<String, dynamic>.from(raw);
      if (!isLeafShiftRow(s)) continue;
      if (_sameObjectId(effectiveIdRaw, s['_id'])) {
        byId = s;
        break;
      }
    }
  }
  if (byId != null) return byId;

  if (nameLower.isNotEmpty) {
    for (final raw in shifts) {
      if (raw is! Map) continue;
      final s = Map<String, dynamic>.from(raw);
      if (!isLeafShiftRow(s)) continue;
      if ((s['name']?.toString().trim().toLowerCase() ?? '') == nameLower) {
        return s;
      }
    }
  }
  return wResolved;
}

DateTime? parseJoiningDate(dynamic raw) {
  if (raw == null) return null;
  if (raw is DateTime) return raw;
  final s = raw.toString().trim();
  if (s.isEmpty) return null;
  return DateTime.tryParse(s);
}

/// Effective shift for one calendar day (after rotational resolution).
class EffectiveShiftDay {
  EffectiveShiftDay({
    required this.displayName,
    this.startTime,
    this.endTime,
    required this.shiftTypeLower,
    this.openWorkHours,
    this.otBufferMinutes,
    this.rotationTemplateName,
    this.cycleLength,
    this.cycleDayIndex1Based,
    this.rotationalMode,
  });

  final String displayName;
  final String? startTime;
  final String? endTime;
  final String shiftTypeLower;
  final double? openWorkHours;
  /// Standard / open shift OT buffer after shift end (company row).
  final int? otBufferMinutes;
  final String? rotationTemplateName;
  final int? cycleLength;
  final int? cycleDayIndex1Based;
  /// [rotationalConfig.rotationType]: `custom`, `daily`, or `weekly` when staff shift is rotational.
  final String? rotationalMode;

  /// Web calendar second line, e.g. `Rotation: ROTATION 1`.
  String? rotationCalendarFooter() {
    final r = rotationTemplateName?.trim();
    if (r == null || r.isEmpty) return null;
    return 'Rotation: $r';
  }

  bool get isOpen =>
      shiftTypeLower == 'open' || shiftTypeLower == 'open shift';

  /// Required work duration in minutes (standard: shift span; open: workHours * 60).
  int? requiredWorkMinutes() {
    if (isOpen) {
      final h = openWorkHours;
      if (h == null || h <= 0) return null;
      return (h * 60).round();
    }
    final a = startTime?.trim();
    final b = endTime?.trim();
    if (a == null || b == null || a.isEmpty || b.isEmpty) return null;
    try {
      return (_shiftSpanHours(a, b) * 60).round();
    } catch (_) {
      return null;
    }
  }

  /// Web-style: standard `Name - 10:00-19:00`; open `OPEN (Open • 9h • OT buffer 60m)`.
  String compactLine() {
    if (isOpen) {
      final h = openWorkHours;
      if (h != null && h > 0) {
        final label = h == h.roundToDouble() ? '${h.toInt()}h' : '${h}h';
        final nm = displayName.trim();
        final buf = otBufferMinutes;
        if (buf != null && buf > 0) {
          final short = nm.isNotEmpty ? nm : 'Open';
          return '$short ($short • $label • OT buffer ${buf}m)';
        }
        return '$nm · $label required'.trim();
      }
      return displayName.trim().isNotEmpty ? displayName : 'Open shift';
    }
    final a = startTime ?? '';
    final b = endTime ?? '';
    if (a.isNotEmpty && b.isNotEmpty) {
      return '$displayName · $a-$b';
    }
    return displayName;
  }
}

List<dynamic>? shiftsListFromCompany(Map<String, dynamic>? companyDoc) {
  if (companyDoc == null) return null;
  final settings = companyDoc['settings'];
  if (settings is! Map) return null;
  final att = settings['attendance'];
  if (att is! Map) return null;
  final shifts = att['shifts'];
  if (shifts is! List || shifts.isEmpty) return null;
  return shifts;
}

/// Web parity with `useGetBusinessQuery` / `GET /settings/business`: full shift rows
/// (including rotational `shiftIdsInCycle`, `shiftIdsByWeekday`) live on `data.business`.
/// Profile-populated `staff.businessId` may omit or strip embedded shifts.
Map<String, dynamic>? companyDocForShiftResolution({
  Map<String, dynamic>? profilePopulatedCompany,
  Map<String, dynamic>? businessFromSettingsBusinessApi,
}) {
  final api = businessFromSettingsBusinessApi;
  if (api != null && api['settings'] is Map) {
    return Map<String, dynamic>.from(api);
  }
  return profilePopulatedCompany;
}

String? trimmedTimeField(dynamic v) {
  if (v == null) return null;
  final s = v.toString().trim();
  if (s.isEmpty || s.toLowerCase() == 'null') return null;
  return s;
}

/// Company DB uses [startTime]/[endTime]. Merged GET /attendance/today template uses [shiftStartTime]/[shiftEndTime].
({String? start, String? end}) readStandardShiftWindowFromMap(
  Map<String, dynamic> m,
) {
  final a = trimmedTimeField(m['startTime']) ??
      trimmedTimeField(m['shiftStartTime']);
  final b =
      trimmedTimeField(m['endTime']) ?? trimmedTimeField(m['shiftEndTime']);
  return (start: a, end: b);
}

({String? start, String? end}) readStandardShiftWindowFromAttendanceTemplate(
  Map<String, dynamic>? t,
) {
  if (t == null || t.isEmpty) return (start: null, end: null);
  return readStandardShiftWindowFromMap(t);
}

/// When the resolved shift map omits times (serialization), re-read the same row from [shifts].
({String? start, String? end}) resolveStandardShiftWindowFromCompany(
  Map<String, dynamic>? companyDoc,
  Map<String, dynamic> shift,
) {
  var win = readStandardShiftWindowFromMap(shift);
  if (win.start != null && win.end != null) return win;
  final shifts = shiftsListFromCompany(companyDoc);
  if (shifts == null) return win;
  final sid = mongoIdToHexString(shift['_id']);
  final sname = shift['name']?.toString().trim().toLowerCase();
  for (final raw in shifts) {
    if (raw is! Map) continue;
    final sm = Map<String, dynamic>.from(raw);
    final mid = mongoIdToHexString(sm['_id']);
    final nm = sm['name']?.toString().trim().toLowerCase() ?? '';
    final idMatch = sid != null && mid != null && sid == mid;
    final nameMatch =
        sname != null && sname.isNotEmpty && nm == sname;
    if (!idMatch && !nameMatch) continue;
    win = readStandardShiftWindowFromMap(sm);
    if (win.start != null && win.end != null) return win;
  }
  return win;
}

/// Build [EffectiveShiftDay] for [day] using company.shifts and staff assignment.
///
/// [attendanceTodayTemplate]: merged template from GET /attendance/today (authoritative
/// openWorkHours when profile-populated company embed omits shift fields).
EffectiveShiftDay? effectiveShiftForCalendarDay({
  required Map<String, dynamic>? companyDoc,
  required String? staffShiftKey,
  required DateTime dayLocal,
  DateTime? joiningDate,
  Map<String, dynamic>? attendanceTodayTemplate,
}) {
  final shifts = shiftsListFromCompany(companyDoc);
  if (shifts == null) {
    _debugLogShiftCalendarRow(
      dayLocal: dayLocal,
      message: 'timings=n/a reason=no_company_shifts',
    );
    return null;
  }
  final key = (staffShiftKey ?? '').trim();

  /// Web / Node getShiftTimings: empty staff key → first embedded shift row.
  final Map<String, dynamic>? wrapper;
  if (key.isEmpty) {
    wrapper = shifts.first is Map
        ? Map<String, dynamic>.from(shifts.first as Map)
        : null;
    if (wrapper == null) {
      _debugLogShiftCalendarRow(
        dayLocal: dayLocal,
        message: 'timings=n/a reason=no_wrapper_shift',
      );
      return null;
    }
  } else {
    wrapper = findShiftByStaffKey(shifts, key) ??
        (shifts.first is Map
            ? Map<String, dynamic>.from(shifts.first as Map)
            : null);
  }
  if (wrapper == null) {
    _debugLogShiftCalendarRow(
      dayLocal: dayLocal,
      message: 'timings=n/a reason=no_wrapper_shift',
    );
    return null;
  }

  final anchor = joiningDate ?? dayLocal;
  final matched =
      resolveEffectiveShiftForDate(shifts, wrapper, dayLocal, anchor);

  final wrapperIsRotational = isRotationalShiftWrapper(wrapper);
  final rotationName = wrapperIsRotational
      ? (wrapper['name']?.toString().trim() ?? '')
      : '';
  int? cycleLen;
  int? cycleDay1;
  String? rotationalModeOut;
  if (wrapperIsRotational) {
    final cfgRaw = wrapper['rotationalConfig'];
    if (cfgRaw is Map) {
      final cfg = Map<String, dynamic>.from(cfgRaw);
      final cycle = computeRotationalCycleIndex(cfg, dayLocal, anchor);
      rotationalModeOut = cycle.rotationType;
      if (cycle.cycleLen > 0) {
        cycleLen = cycle.cycleLen;
        cycleDay1 = cycle.idx + 1;
      }
    }
  }

  var mType = (matched['shiftType'] ?? 'standard').toString().toLowerCase();
  final nameLower = (matched['name'] ?? '').toString().toLowerCase().trim();
  if (nameLower == 'open' || nameLower == 'open shift') {
    mType = 'open';
  }

  double? openH;
  Map<String, dynamic>? openSourceRow = matched;
  if (mType == 'open' || mType == 'open shift') {
    openH = resolveOpenShiftWorkHoursFromCompany(companyDoc, matched);
    if (openH != null && openH > 0) {
      final mid = mongoIdToHexString(matched['_id']);
      final mname = matched['name']?.toString().trim();
      for (final raw in shifts) {
        if (raw is! Map) continue;
        final sm = Map<String, dynamic>.from(raw);
        final sameId =
            mid != null && mongoIdToHexString(sm['_id']) == mid;
        final sameName = mname != null &&
            mname.isNotEmpty &&
            (sm['name']?.toString().trim() ?? '') == mname;
        if (sameId || sameName) {
          openSourceRow = sm;
          break;
        }
      }
    }
    if (openH == null || openH <= 0) {
      for (final raw in shifts) {
        if (raw is! Map) continue;
        final sm = Map<String, dynamic>.from(raw);
        final st = (sm['shiftType'] ?? '').toString().toLowerCase();
        final nm = (sm['name'] ?? '').toString().toLowerCase().trim();
        if (st == 'open' ||
            st == 'open shift' ||
            nm == 'open' ||
            nm == 'open shift') {
          openH = readOpenWorkHoursFromShiftMap(sm);
          if (openH != null && openH > 0) {
            openSourceRow = sm;
            break;
          }
        }
      }
    }
    if (openH == null || openH <= 0) {
      final fromToday =
          readOpenHoursFromAttendanceTodayTemplate(attendanceTodayTemplate);
      if (fromToday != null && fromToday > 0) openH = fromToday;
    }
    if (openH == null || openH <= 0) openH = 8;
    int? otBuf = readOtBufferMinutesFromMap(openSourceRow);
    if ((otBuf == null || otBuf <= 0) &&
        attendanceTodayTemplate != null &&
        attendanceTodayTemplate.isNotEmpty) {
      otBuf = readOtBufferMinutesFromMap(attendanceTodayTemplate);
    }
    final openName = matched['name']?.toString().trim() ?? 'Open';
    _debugLogShiftCalendarRow(
      dayLocal: dayLocal,
      message:
          'effectiveShift="$openName" type=open requiredHours=${openH}h '
          '${rotationName.isNotEmpty ? 'rotation="$rotationName" ' : ''}'
          '${rotationalModeOut != null ? 'mode=$rotationalModeOut ' : ''}'
          '${cycleDay1 != null && cycleLen != null ? 'cycleDay=$cycleDay1/$cycleLen' : ''}'
              .trim(),
    );
    return EffectiveShiftDay(
      displayName: openName,
      startTime: null,
      endTime: null,
      shiftTypeLower: 'open',
      openWorkHours: openH,
      otBufferMinutes: otBuf,
      rotationTemplateName: rotationName.isNotEmpty ? rotationName : null,
      cycleLength: cycleLen,
      cycleDayIndex1Based: cycleDay1,
      rotationalMode: wrapperIsRotational ? rotationalModeOut : null,
    );
  }

  var win = resolveStandardShiftWindowFromCompany(companyDoc, matched);
  if (win.start == null || win.end == null) {
    final tw = readStandardShiftWindowFromAttendanceTemplate(
      attendanceTodayTemplate,
    );
    win = (start: win.start ?? tw.start, end: win.end ?? tw.end);
  }
  final st = win.start ?? '';
  final en = win.end ?? '';
  int? stdOtBuf = readOtBufferMinutesFromMap(matched);
  if ((stdOtBuf == null || stdOtBuf <= 0) &&
      attendanceTodayTemplate != null &&
      attendanceTodayTemplate.isNotEmpty) {
    stdOtBuf = readOtBufferMinutesFromMap(attendanceTodayTemplate) ?? stdOtBuf;
  }
  final stdName = matched['name']?.toString().trim() ?? key;
  final windowLog = (st.isNotEmpty && en.isNotEmpty) ? '$st-$en' : 'n/a';
  _debugLogShiftCalendarRow(
    dayLocal: dayLocal,
    message:
        'effectiveShift="$stdName" type=$mType shiftWindow=$windowLog '
        '${rotationName.isNotEmpty ? 'rotation="$rotationName" ' : ''}'
        '${rotationalModeOut != null ? 'mode=$rotationalModeOut ' : ''}'
        '${cycleDay1 != null && cycleLen != null ? 'cycleDay=$cycleDay1/$cycleLen' : ''}'
            .trim(),
  );
  return EffectiveShiftDay(
    displayName: stdName,
    startTime: st.isNotEmpty ? st : null,
    endTime: en.isNotEmpty ? en : null,
    shiftTypeLower: mType,
    openWorkHours: null,
    otBufferMinutes: stdOtBuf,
    rotationTemplateName: rotationName.isNotEmpty ? rotationName : null,
    cycleLength: cycleLen,
    cycleDayIndex1Based: cycleDay1,
    rotationalMode: wrapperIsRotational ? rotationalModeOut : null,
  );
}
