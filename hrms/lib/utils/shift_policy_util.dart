/// Resolves the per-shift attendance policies (break / permission / overtime /
/// half-day) for the staff's *effective* shift on a given calendar day.
///
/// These live on `company.settings.attendance.shifts[]` as `breakPolicy`,
/// `permissionPolicy`, `overtimePolicy` and `halfDaySettings` (see app_backend
/// Company model). The same rotational resolution used by
/// [effectiveShiftForCalendarDay] picks the leaf shift row for the day, then we
/// read the four sub-objects off it. Mirrors the backend's `getShiftTimings`,
/// which surfaces the identical fields and enforces them at runtime.
library;

import 'rotational_shift_util.dart';

/// Tri-state availability of a shift function.
enum PolicyAvailability {
  /// Explicitly turned on for this shift.
  enabled,

  /// Explicitly turned off for this shift — the function must be blocked.
  disabled,

  /// No policy configured on this shift. Legacy/unconfigured: callers keep their
  /// prior default (breaks allowed with a default allowance, permission shown,
  /// overtime inherits the attendance template).
  unconfigured,
}

/// One resolved policy: whether the function is available and its allocated limit.
class ShiftPolicyInfo {
  const ShiftPolicyInfo({
    required this.availability,
    this.limitMinutes,
    this.multiplier,
  });

  final PolicyAvailability availability;

  /// Allocated limit in minutes where applicable (break allowance per day,
  /// permission monthly quota). `null` when the policy carries no minute limit.
  final int? limitMinutes;

  /// Overtime pay multiplier override (overtime only). `null` = inherit company
  /// default.
  final double? multiplier;

  /// True when the function may be used (enabled, or unconfigured → legacy allow).
  bool get isAllowed => availability != PolicyAvailability.disabled;

  /// True only when an admin explicitly switched the function on for this shift.
  bool get isExplicitlyEnabled => availability == PolicyAvailability.enabled;
}

/// The four shift functions resolved for one calendar day.
class ShiftPolicies {
  const ShiftPolicies({
    required this.breakPolicy,
    required this.permission,
    required this.overtime,
    required this.halfDay,
    this.graceTimeMinutes,
    this.shiftName,
  });

  final ShiftPolicyInfo breakPolicy;
  final ShiftPolicyInfo permission;
  final ShiftPolicyInfo overtime;
  final ShiftPolicyInfo halfDay;

  /// Late-arrival grace period in minutes, from the shift's `graceTime` (falling
  /// back to the attendance template's `gracePeriodMinutes`). `null` when neither
  /// is configured.
  final int? graceTimeMinutes;

  /// Resolved effective shift name for the day (for display), when known.
  final String? shiftName;

  static const ShiftPolicies empty = ShiftPolicies(
    breakPolicy: ShiftPolicyInfo(availability: PolicyAvailability.unconfigured),
    permission: ShiftPolicyInfo(availability: PolicyAvailability.unconfigured),
    overtime: ShiftPolicyInfo(availability: PolicyAvailability.unconfigured),
    halfDay: ShiftPolicyInfo(availability: PolicyAvailability.unconfigured),
  );
}

bool? _readBool(dynamic v) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) {
    final s = v.trim().toLowerCase();
    if (s == 'true' || s == '1' || s == 'yes') return true;
    if (s == 'false' || s == '0' || s == 'no') return false;
  }
  return null;
}

int? _readInt(dynamic v) {
  if (v is num) {
    final i = v.round();
    return i < 0 ? 0 : i;
  }
  final p = int.tryParse(v?.toString().trim() ?? '');
  if (p == null) return null;
  return p < 0 ? 0 : p;
}

double? _readDouble(dynamic v) {
  if (v is num) return v.toDouble();
  return double.tryParse(v?.toString().trim() ?? '');
}

Map<String, dynamic>? _asMap(dynamic v) {
  if (v is Map<String, dynamic>) return v;
  if (v is Map) return Map<String, dynamic>.from(v);
  return null;
}

/// Break allowance: `breakPolicy.{enabled, allowedMinutes}`. Absent → unconfigured
/// (legacy: breaks allowed with the backend's default ~60 min/day allowance).
ShiftPolicyInfo _breakFromRow(Map<String, dynamic> row) {
  final policy = _asMap(row['breakPolicy']);
  if (policy == null) {
    return const ShiftPolicyInfo(availability: PolicyAvailability.unconfigured);
  }
  final enabled = _readBool(policy['enabled']) ?? false;
  final allowed = _readInt(policy['allowedMinutes']);
  return ShiftPolicyInfo(
    availability:
        enabled ? PolicyAvailability.enabled : PolicyAvailability.disabled,
    limitMinutes: (allowed != null && allowed > 0) ? allowed : null,
  );
}

/// Permission quota: `permissionPolicy.{enabled, monthlyQuotaMinutes}`. Absent →
/// unconfigured (app default keeps the request flow available).
ShiftPolicyInfo _permissionFromRow(Map<String, dynamic> row) {
  final policy = _asMap(row['permissionPolicy']);
  if (policy == null) {
    return const ShiftPolicyInfo(availability: PolicyAvailability.unconfigured);
  }
  final enabled = _readBool(policy['enabled']) ?? false;
  final quota = _readInt(policy['monthlyQuotaMinutes']);
  return ShiftPolicyInfo(
    availability:
        enabled ? PolicyAvailability.enabled : PolicyAvailability.disabled,
    limitMinutes: (quota != null && quota > 0) ? quota : null,
  );
}

/// Overtime: `overtimePolicy.enabled` is tri-state — null means inherit the
/// attendance template's `allowOvertime`/`overtimeAllowed` (default allowed).
ShiftPolicyInfo _overtimeFromRow(
  Map<String, dynamic> row,
  Map<String, dynamic>? attendanceTemplate,
) {
  final policy = _asMap(row['overtimePolicy']);
  final multiplier = policy == null ? null : _readDouble(policy['multiplier']);
  final explicit = policy == null ? null : _readBool(policy['enabled']);
  if (explicit != null) {
    return ShiftPolicyInfo(
      availability:
          explicit ? PolicyAvailability.enabled : PolicyAvailability.disabled,
      multiplier: multiplier,
    );
  }
  // Inherit the attendance template toggle (default true when unspecified).
  final t = attendanceTemplate;
  final inherited = t == null
      ? null
      : (_readBool(t['overtimeAllowed']) ?? _readBool(t['allowOvertime']));
  if (inherited == null) {
    return ShiftPolicyInfo(
      availability: PolicyAvailability.unconfigured,
      multiplier: multiplier,
    );
  }
  return ShiftPolicyInfo(
    availability:
        inherited ? PolicyAvailability.enabled : PolicyAvailability.disabled,
    multiplier: multiplier,
  );
}

/// Late-arrival grace period: `graceTime.{value, unit}` on the shift row,
/// converted to minutes. Falls back to the attendance template's flat
/// `gracePeriodMinutes` when the shift row carries no `graceTime`.
int? _graceTimeFromRow(
  Map<String, dynamic> row,
  Map<String, dynamic>? attendanceTemplate,
) {
  final grace = _asMap(row['graceTime']);
  final value = grace == null ? null : _readInt(grace['value']);
  if (value != null) {
    final unit = (grace!['unit']?.toString() ?? 'minutes').toLowerCase();
    return unit == 'hours' ? value * 60 : value;
  }
  return _readInt(attendanceTemplate?['gracePeriodMinutes']);
}

/// Half-day: `halfDaySettings.enabled`. Absent `halfDaySettings` → unconfigured;
/// present but `enabled !== true` → disabled (Not Allowed).
ShiftPolicyInfo _halfDayFromRow(Map<String, dynamic> row) {
  final settings = _asMap(row['halfDaySettings']);
  if (settings == null) {
    return const ShiftPolicyInfo(availability: PolicyAvailability.unconfigured);
  }
  final enabled = _readBool(settings['enabled']) ?? false;
  return ShiftPolicyInfo(
    availability:
        enabled ? PolicyAvailability.enabled : PolicyAvailability.disabled,
  );
}

/// Resolves the leaf shift row that governs [dayLocal] for the staff, applying
/// the same wrapper-selection + rotational resolution as
/// [effectiveShiftForCalendarDay]. Returns null when no shifts are configured.
Map<String, dynamic>? resolveEffectiveShiftRowForDay({
  required Map<String, dynamic>? companyDoc,
  required String? staffShiftKey,
  required DateTime dayLocal,
  DateTime? joiningDate,
}) {
  final shifts = shiftsListFromCompany(companyDoc);
  if (shifts == null) return null;
  final key = (staffShiftKey ?? '').trim();

  Map<String, dynamic>? wrapper;
  if (key.isEmpty) {
    wrapper = shifts.first is Map
        ? Map<String, dynamic>.from(shifts.first as Map)
        : null;
  } else {
    wrapper = findShiftByStaffKey(shifts, key) ??
        (shifts.first is Map
            ? Map<String, dynamic>.from(shifts.first as Map)
            : null);
  }
  if (wrapper == null) return null;

  final anchor = joiningDate ?? dayLocal;
  final matched = resolveEffectiveShiftForDate(shifts, wrapper, dayLocal, anchor);
  return matched;
}

/// Builds [ShiftPolicies] for [dayLocal] using the staff's effective shift row.
///
/// [attendanceTemplate] is the merged GET /attendance/today template — only its
/// overtime toggle is consulted, and only when the shift's overtimePolicy leaves
/// `enabled` unset (tri-state inherit).
ShiftPolicies resolveShiftPoliciesForDay({
  required Map<String, dynamic>? companyDoc,
  required String? staffShiftKey,
  required DateTime dayLocal,
  DateTime? joiningDate,
  Map<String, dynamic>? attendanceTemplate,
}) {
  final row = resolveEffectiveShiftRowForDay(
    companyDoc: companyDoc,
    staffShiftKey: staffShiftKey,
    dayLocal: dayLocal,
    joiningDate: joiningDate,
  );
  return shiftPoliciesFromRow(row, attendanceTemplate: attendanceTemplate);
}

/// Builds [ShiftPolicies] directly from an explicit shift [row] — used when the
/// governing shift is already known (e.g. a historical day's stamped
/// `appliedShiftId` resolved via `shiftRowForAppliedShiftId`), so the policies,
/// grace and quotas come from the shift that was actually allocated that day
/// rather than from re-running rotational resolution. A null [row] falls back to
/// the attendance template for overtime/grace only.
ShiftPolicies shiftPoliciesFromRow(
  Map<String, dynamic>? row, {
  Map<String, dynamic>? attendanceTemplate,
}) {
  if (row == null) {
    // No shift row: fall back to the attendance template for overtime only.
    return ShiftPolicies(
      breakPolicy:
          const ShiftPolicyInfo(availability: PolicyAvailability.unconfigured),
      permission:
          const ShiftPolicyInfo(availability: PolicyAvailability.unconfigured),
      overtime: _overtimeFromRow(const {}, attendanceTemplate),
      halfDay:
          const ShiftPolicyInfo(availability: PolicyAvailability.unconfigured),
      graceTimeMinutes: _graceTimeFromRow(const {}, attendanceTemplate),
    );
  }
  final name = row['name']?.toString().trim();
  return ShiftPolicies(
    breakPolicy: _breakFromRow(row),
    permission: _permissionFromRow(row),
    overtime: _overtimeFromRow(row, attendanceTemplate),
    halfDay: _halfDayFromRow(row),
    graceTimeMinutes: _graceTimeFromRow(row, attendanceTemplate),
    shiftName: (name != null && name.isNotEmpty) ? name : null,
  );
}
