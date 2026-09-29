/// Salary-related fine aggregation and date keys for attendance rows.
///
/// Use this anywhere the app needs **totals and breakdown** from stored
/// `fineAmount` / `lateMinutes` on attendance maps (salary overview, payroll
/// previews, dashboards, etc.). Punch-time fine **estimation** stays in
/// [fine_calculation_util.dart] (`calculateFine`, `calculatePayrollFine`).
library;

import 'package:intl/intl.dart';

/// Normalizes an attendance `date` field to `yyyy-MM-dd` for maps and calendar.
/// Plain `yyyy-MM-dd` is kept; ISO / Mongo instants use the **UTC** calendar day
/// (matches `app_backend` month attendance / `formatDateStringUTC`).
String? normalizeAttendanceDateKeyForSalary(dynamic rawValue) {
  try {
    final raw = (rawValue ?? '').toString().trim();
    if (raw.isEmpty) return null;
    if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(raw)) return raw;
    final parsed = DateTime.parse(raw);
    if (raw.contains('T') || raw.endsWith('Z')) {
      final u = parsed.toUtc();
      return '${u.year.toString().padLeft(4, '0')}-'
          '${u.month.toString().padLeft(2, '0')}-'
          '${u.day.toString().padLeft(2, '0')}';
    }
    return DateFormat('yyyy-MM-dd').format(parsed.toUtc());
  } catch (_) {
    try {
      final raw = (rawValue ?? '').toString();
      if (raw.contains('T')) {
        final part = raw.split('T').first;
        if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(part)) return part;
      }
      if (raw.contains(' ')) {
        final part = raw.split(' ').first;
        if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(part)) return part;
      }
    } catch (_) {}
    return null;
  }
}

double _round2(double v) => (v * 100).round() / 100;

double _fineLegAmount(dynamic leg) =>
    leg is Map ? ((leg['amount'] as num?)?.toDouble() ?? 0.0) : 0.0;

/// Minutes from HRMSbackend `updatedHours` ({hours, minutes}) or "HH:MM".
int _fineLegMinutes(dynamic leg) {
  if (leg is! Map) return 0;
  final u = leg['updatedHours'];
  if (u is Map) {
    final h = (u['hours'] as num?)?.toInt() ?? 0;
    final m = (u['minutes'] as num?)?.toInt() ?? 0;
    return h * 60 + m;
  }
  final a = leg['actualHours']?.toString() ?? '';
  final match = RegExp(r'^(\d{1,3}):(\d{2})').firstMatch(a);
  if (match != null) return int.parse(match.group(1)!) * 60 + int.parse(match.group(2)!);
  return 0;
}

/// Maps HRMSbackend's stored fine (`fineAdjustment`) onto the keys the app's
/// fine UI reads — the SAME figures the web shows. Fines are calculated only by
/// the backend (utils/fineCalculator.ts); the app never recalculates them.
///
/// `fineAdjustment`: `{ lateFine:{amount, updatedHours}, earlyExitFine:{...},
/// breakFine:{...}, totalFine }` → `lateFineAmount`, `earlyExitFineAmount`,
/// `breakFineAmount`, `fineAmount` (late + early), `totalFineAmount` (the
/// backend's totalFine = late + early + break), `lateMinutes`/`earlyMinutes`
/// (when not already set) and `fineHours` (minutes that were actually fined).
void applyServerFineFields(Map<String, dynamic> m) {
  final fa = m['fineAdjustment'];
  if (fa is! Map) return;
  final late = _fineLegAmount(fa['lateFine']);
  final early = _fineLegAmount(fa['earlyExitFine']);
  final brk = _fineLegAmount(fa['breakFine']);
  final total = (fa['totalFine'] as num?)?.toDouble() ?? (late + early + brk);
  final lateMin = _fineLegMinutes(fa['lateFine']);
  final earlyMin = _fineLegMinutes(fa['earlyExitFine']);
  final breakMin = _fineLegMinutes(fa['breakFine']);

  m['lateFineAmount'] = _round2(late);
  m['earlyExitFineAmount'] = _round2(early);
  m['breakFineAmount'] = _round2(brk);
  m['fineAmount'] = _round2(late + early);
  m['totalFineAmount'] = _round2(total);
  m['lateMinutes'] ??= lateMin;
  m['earlyMinutes'] ??= earlyMin;
  m['fineHours'] = (late > 0 ? lateMin : 0) + (early > 0 ? earlyMin : 0);
  m['breakFineMinutes'] = brk > 0 ? breakMin : 0;
}

/// The day's TOTAL attendance fine amount for a record.
///
/// HRMSbackend records (mapped by [applyServerFineFields]): the backend's own
/// `fineAdjustment.totalFine` — exactly what the web shows. Older records:
/// late/early (`fineAmount`) + break (`break.totalBreakFineAmount`) +
/// permission overage (`permissionFineAmount`).
double recordTotalFineAmount(dynamic raw) {
  if (raw is! Map) return 0.0;
  final server = raw['totalFineAmount'];
  if (server is num) return _round2(server.toDouble());
  final fa = raw['fineAdjustment'];
  if (fa is Map && fa['totalFine'] is num) {
    return _round2((fa['totalFine'] as num).toDouble());
  }
  final lateEarly = (raw['fineAmount'] as num?)?.toDouble() ?? 0.0;
  final breakObj = raw['break'];
  final breakFine = breakObj is Map
      ? ((breakObj['totalBreakFineAmount'] as num?)?.toDouble() ?? 0.0)
      : 0.0;
  final permissionFine = (raw['permissionFineAmount'] as num?)?.toDouble() ?? 0.0;
  final total = lateEarly + breakFine + permissionFine;
  return (total * 100).round() / 100;
}

/// The day's TOTAL fine MINUTES: late + early (`fineHours`) + break
/// (`break.totalBreakFineMins`) + permission overage (`permissionFineMinutes`).
int recordTotalFineMinutes(dynamic raw) {
  if (raw is! Map) return 0;
  if (raw['totalFineAmount'] is num) {
    // HRMSbackend record (see applyServerFineFields).
    return ((raw['fineHours'] as num?)?.toInt() ?? 0) +
        ((raw['breakFineMinutes'] as num?)?.toInt() ?? 0);
  }
  final lateEarly = (raw['fineHours'] as num?)?.toInt() ?? 0;
  final breakObj = raw['break'];
  final breakMins = breakObj is Map
      ? ((breakObj['totalBreakFineMins'] as num?)?.toInt() ?? 0)
      : 0;
  final permissionMins = (raw['permissionFineMinutes'] as num?)?.toInt() ?? 0;
  return lateEarly + breakMins + permissionMins;
}

/// Result of aggregating fines from attendance records (web `calculateTotalFine` rules).
class SalaryFineSummary {
  SalaryFineSummary({
    required this.totalFineAmount,
    required this.lateDays,
    required this.totalLateMinutes,
    required Map<String, double> dailyFineByDateKey,
  }) : dailyFineByDateKey = Map.unmodifiable(dailyFineByDateKey);

  /// Sum of applicable `fineAmount` values, rounded to 2 decimals.
  final double totalFineAmount;

  /// Late days: non–half-day rows with fine count always; half-day only when late minutes > 0.
  final int lateDays;

  /// Sum of `lateMinutes` contributed from rows that count toward [lateDays] (web semantics).
  final int totalLateMinutes;

  /// One entry per calendar day key (see [normalizeAttendanceDateKeyForSalary]); last write wins per day.
  final Map<String, double> dailyFineByDateKey;

  /// Shape used by legacy salary UI state (`_fineInfo`).
  Map<String, dynamic> toLegacyFineInfoMap() => {
        'totalFineAmount': totalFineAmount,
        'lateDays': lateDays,
        'totalLateMinutes': totalLateMinutes,
      };
}

/// Aggregates stored fines from attendance maps.
///
/// Rules match `frontend/src/utils/fineCalculation.util.ts` — `calculateTotalFine`:
/// - Half-day session (`halfDaySession` set): count fine only if `fineAmount > 0.01`;
///   then increment [lateDays] only if `lateMinutes > 0`.
/// - Otherwise: count if `fineAmount > 0`; increment [lateDays]; add `lateMinutes` (0 if absent).
///
/// **Status filtering**: none here. Pass only the records your feature should
/// include (e.g. month API rows, or pre-filter Present/Approved).
SalaryFineSummary aggregateSalaryFineSummary(Iterable<dynamic> records) {
  double totalFineAmount = 0;
  int lateDays = 0;
  int totalLateMinutes = 0;
  final dailyFineAmounts = <String, double>{};

  for (final raw in records) {
    if (raw is! Map) continue;
    final record = Map<String, dynamic>.from(raw);

    // Late/early fine and the day's TOTAL fine (late/early + break overage).
    final lateEarlyFine = (record['fineAmount'] as num?)?.toDouble() ?? 0.0;
    final recordFine = recordTotalFineAmount(record);
    final lateMinutes = (record['lateMinutes'] as num?)?.toInt() ?? 0;
    final hasHalfDaySession = record['halfDaySession'] != null;
    final shouldCountFine = hasHalfDaySession
        ? (recordFine > 0.01)
        : (recordFine > 0);

    if (!shouldCountFine) continue;

    totalFineAmount += recordFine;
    // "Late days" stays based on an actual late/early fine or late minutes, so a
    // break-only fine day still contributes to the total amount without inflating
    // the late-day count.
    if (hasHalfDaySession) {
      if (lateMinutes > 0) {
        lateDays++;
        totalLateMinutes += lateMinutes;
      }
    } else if (lateEarlyFine > 0 || lateMinutes > 0) {
      lateDays++;
      totalLateMinutes += lateMinutes;
    }

    try {
      final dateStr = record['date']?.toString();
      final key = normalizeAttendanceDateKeyForSalary(dateStr);
      if (key != null && key.isNotEmpty) {
        dailyFineAmounts[key] = recordFine;
      }
    } catch (_) {}
  }

  totalFineAmount = (totalFineAmount * 100).round() / 100;

  return SalaryFineSummary(
    totalFineAmount: totalFineAmount,
    lateDays: lateDays,
    totalLateMinutes: totalLateMinutes,
    dailyFineByDateKey: dailyFineAmounts,
  );
}
