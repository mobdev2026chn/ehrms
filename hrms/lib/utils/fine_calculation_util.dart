/// Fine Calculation Utility
/// Implements the same grace time and fine calculation logic as the backend
/// Matches the logic from backend/src/utils/fineCalculation.util.ts
library;

import 'package:flutter/foundation.dart';

import 'rotational_shift_util.dart' as rs;

/// Shift timing information
class ShiftTiming {
  final String name;
  final String startTime; // Format: "HH:mm" (e.g., "10:00")
  final String endTime; // Format: "HH:mm" (e.g., "19:00")
  final GraceTime? graceTime; // Optional shift-specific grace time

  ShiftTiming({
    required this.name,
    required this.startTime,
    required this.endTime,
    this.graceTime,
  });
}

/// Grace time configuration
class GraceTime {
  final int value;
  final String unit; // 'minutes' or 'hours'

  GraceTime({required this.value, this.unit = 'minutes'});
}

/// Fine settings configuration
class FineSettings {
  final bool enabled;
  final int graceTimeMinutes; // Default grace time in minutes (company level)
  final String calculationType; // 'shiftBased' or 'fixedPerHour'
  final double? finePerHour; // Optional fixed fine per hour

  FineSettings({
    required this.enabled,
    this.graceTimeMinutes = 10, // Default 10 minutes
    this.calculationType = 'shiftBased',
    this.finePerHour,
  });
}

/// Result of fine calculation
class FineCalculationResult {
  final int lateMinutes;
  final int fineHours; // in minutes (same as lateMinutes for late arrival)
  final double fineAmount;

  FineCalculationResult({
    required this.lateMinutes,
    required this.fineHours,
    required this.fineAmount,
  });
}

/// Calculate grace time in minutes from shift grace time setting
/// Falls back to default grace time if shift doesn't have one
int getGraceTimeMinutes(ShiftTiming? shiftTiming, int defaultGraceTimeMinutes) {
  if (shiftTiming?.graceTime != null) {
    final graceTime = shiftTiming!.graceTime!;
    if (graceTime.unit == 'hours') {
      return graceTime.value * 60;
    }
    return graceTime.value;
  }
  return defaultGraceTimeMinutes;
}

/// Calculate shift hours from start and end time
/// Handles overnight shifts correctly
double calculateShiftHours(String startTime, String endTime) {
  final startParts = startTime.split(':');
  final endParts = endTime.split(':');

  final startHours = int.parse(startParts[0]);
  final startMinutes = int.parse(startParts[1]);
  final endHours = int.parse(endParts[0]);
  final endMinutes = int.parse(endParts[1]);

  final startTotalMinutes = startHours * 60 + startMinutes;
  final endTotalMinutes = endHours * 60 + endMinutes;

  // Handle overnight shifts
  var diffMinutes = endTotalMinutes - startTotalMinutes;
  if (diffMinutes < 0) {
    diffMinutes += 24 * 60; // Add 24 hours for overnight shift
  }

  return diffMinutes / 60; // Convert to hours
}

/// Calculate late minutes and fine for a punch-in time
///
/// [punchInTime] - Actual punch-in time
/// [attendanceDate] - The attendance date (work day) to use for shift timing
/// [shiftTiming] - Shift timing with grace time (optional, can be null)
/// [fineSettings] - Fine configuration settings
/// [dailySalary] - One day's salary (for shift-based calculation)
/// [dailyNetSalary] - One day's net salary (for fixedPerHour calculation, optional)
/// [staffLabel] - Optional label for logs (e.g. staffId or employee name)
///
/// Returns FineCalculationResult with lateMinutes and fineAmount
FineCalculationResult calculateFine({
  required DateTime punchInTime,
  required DateTime attendanceDate,
  ShiftTiming? shiftTiming,
  required FineSettings fineSettings,
  double? dailySalary,
  double? dailyNetSalary,
  String? staffLabel,
}) {
  final shiftStartStr = shiftTiming?.startTime ?? "09:30";
  final shiftEndStr = shiftTiming?.endTime ?? "18:30";
  debugPrint('[Fine TEST] calculateFine called: punchIn=$punchInTime, date=$attendanceDate, shiftStart=$shiftStartStr, shiftEnd=$shiftEndStr, enabled=${fineSettings.enabled}, calculationType=${fineSettings.calculationType}, dailySalary=$dailySalary');

  // If fine settings are disabled, return zero
  if (!fineSettings.enabled) {
    debugPrint('[Fine TEST] => skip (fine disabled), lateMinutes=0, fineAmount=0');
    return FineCalculationResult(lateMinutes: 0, fineHours: 0, fineAmount: 0);
  }

  // Parse shift start time (format: "HH:mm")
  final startParts = shiftStartStr.split(':');
  final shiftHours = int.parse(startParts[0]);
  final shiftMinutes = int.parse(startParts[1]);

  // Use attendance date to set shift start time (ensures correct date context)
  final shiftStartDate = DateTime(
    attendanceDate.year,
    attendanceDate.month,
    attendanceDate.day,
    shiftHours,
    shiftMinutes,
  );

  // Get grace time (from shift or default) - convert to minutes
  final graceTimeMinutes = getGraceTimeMinutes(
    shiftTiming,
    fineSettings.graceTimeMinutes,
  );

  // Calculate grace time end
  final graceTimeEnd = shiftStartDate.add(Duration(minutes: graceTimeMinutes));

  // If punch-in is before or within grace time, no fine
  if (punchInTime.isBefore(graceTimeEnd) ||
      punchInTime.isAtSameMomentAs(graceTimeEnd)) {
    debugPrint('[Fine TEST] => within grace (graceMinutes=$graceTimeMinutes, graceEnd=$graceTimeEnd), lateMinutes=0, fineAmount=0');
    return FineCalculationResult(lateMinutes: 0, fineHours: 0, fineAmount: 0);
  }

  // Calculate late minutes from shift start time (not grace end)
  // This matches backend logic: late minutes are calculated from original shift start
  final lateMinutes = punchInTime.difference(shiftStartDate).inMinutes;

  if (lateMinutes <= 0) {
    debugPrint('[Fine TEST] => lateMinutes<=0, fineAmount=0');
    return FineCalculationResult(lateMinutes: 0, fineHours: 0, fineAmount: 0);
  }

  // Calculate shift hours
  final shiftHoursTotal = calculateShiftHours(
    shiftTiming?.startTime ?? "09:30",
    shiftTiming?.endTime ?? "18:30",
  );

  // Calculate fine amount
  double fineAmount = 0;
  String formulaLog = '';

  if (fineSettings.calculationType == 'fixedPerHour') {
    // Web parity: hourly rate = dailyNet÷shiftHours when possible, else config finePerHour
    final lateHours = lateMinutes / 60.0;
    final baseNet = dailyNetSalary ?? dailySalary;
    double finePerHour = 0;
    if (baseNet != null && baseNet > 0 && shiftHoursTotal > 0) {
      finePerHour = baseNet / shiftHoursTotal;
    }
    if (finePerHour <= 0 &&
        fineSettings.finePerHour != null &&
        fineSettings.finePerHour! > 0) {
      finePerHour = fineSettings.finePerHour!;
    }
    fineAmount = finePerHour * lateHours;
    formulaLog =
        'fixedPerHour: (net÷shiftH)×lateH = ($baseNet÷$shiftHoursTotal)×$lateHours => finePerHour=${finePerHour.toStringAsFixed(4)}';
  } else {
    // Shift-based calculation (default)
    // Daily Salary = Monthly Gross Salary / No. of days in month
    //   (payable-days denominator per company rule: calendar days /
    //    exclude week-offs / fixed days — supplied via [dailySalary])
    // Hourly Rate = Daily Salary / Shift Hours (work hrs)
    // Fine Amount = Hourly Rate * (Fine Minutes / 60)

    if (dailySalary != null && dailySalary > 0 && shiftHoursTotal > 0) {
      final hourlyRate = dailySalary / shiftHoursTotal;
      final lateHours = lateMinutes / 60;
      fineAmount = hourlyRate * lateHours;
      formulaLog = 'shiftBased: Fine = (DailySalary÷ShiftHours) × (Minutes÷60) = ($dailySalary÷$shiftHoursTotal) × ($lateMinutes÷60) = ${hourlyRate.toStringAsFixed(2)} × ${lateHours.toStringAsFixed(2)}';
    }
  }

  // Round to 2 decimal places
  final preRoundFineAmount = fineAmount;
  fineAmount = (fineAmount * 100).round() / 100;
  if (formulaLog.isNotEmpty) {
    final staffPart = staffLabel != null && staffLabel.isNotEmpty ? 'staff=$staffLabel | ' : '';
    debugPrint('[Fine FORMULA] $staffPart dailySalary=$dailySalary | lateMinutes=$lateMinutes | $formulaLog | => fineAmount=$fineAmount');
  }
  if (shiftHoursTotal > 0 && lateMinutes > 0 && dailySalary != null && dailySalary > 0) {
    final minuteHours = lateMinutes / 60.0;
    final hourlyRate = dailySalary / shiftHoursTotal;
    debugPrint(
      '[Fine][formula][test] Fine = (Daily Salary ÷ Shift Hours) × (Minutes ÷ 60) '
      '= ($dailySalary ÷ $shiftHoursTotal) × ($lateMinutes ÷ 60) '
      '= ${hourlyRate.toStringAsFixed(6)} × ${minuteHours.toStringAsFixed(6)} '
      '= ${(hourlyRate * minuteHours).toStringAsFixed(6)} | '
      'preRound=${preRoundFineAmount.toStringAsFixed(6)} final=$fineAmount',
    );
  }
  debugPrint('[Fine TEST] => result: lateMinutes=$lateMinutes, fineAmount=$fineAmount, shiftHoursTotal=$shiftHoursTotal');

  return FineCalculationResult(
    lateMinutes: lateMinutes,
    fineHours: lateMinutes, // Store in minutes for consistency
    fineAmount: fineAmount,
  );
}

/// Calculate fine for payroll based on attendance records
/// Aggregates fine amounts from multiple attendance records
///
/// [attendanceRecords] - List of attendance records with lateMinutes and fineAmount
/// [dailySalary] - One day's salary (gross or net based on calculation type)
/// [shiftHours] - Shift hours per day
/// [fineSettings] - Fine configuration settings
/// [dailyNetSalary] - One day's net salary (for fixedPerHour calculation, optional)
///
/// Returns total fine amount for payroll
double calculatePayrollFine({
  required List<Map<String, dynamic>> attendanceRecords,
  required double dailySalary,
  required double shiftHours,
  required FineSettings fineSettings,
  double? dailyNetSalary,
}) {
  debugPrint('[Fine TEST] calculatePayrollFine: records=${attendanceRecords.length}, dailySalary=$dailySalary, shiftHours=$shiftHours, enabled=${fineSettings.enabled}');

  if (!fineSettings.enabled) {
    // If fine settings are disabled, use existing fine amounts if available
    // ONLY for Present or Approved status
    // EXCLUDE Absent, Pending, etc.
    double total = 0;
    for (final record in attendanceRecords) {
      final status = (record['status'] as String? ?? '').trim().toLowerCase();
      
      // ONLY include Present or Approved status
      if (status != 'present' && status != 'approved') continue;
      
      total += (record['fineAmount'] as num?)?.toDouble() ?? 0.0;
    }
    debugPrint('[Fine TEST] calculatePayrollFine => (disabled) totalFine=$total');
    return total;
  }

  double totalFine = 0;

  for (final record in attendanceRecords) {
    final status = record['status'] as String?;

    // Calculate fine ONLY for Present or Approved status
    // EXCLUDE Absent, Pending, etc.
    final statusLower = (status ?? '').trim().toLowerCase();
    
    // ONLY include Present or Approved status
    if (statusLower != 'present' && statusLower != 'approved') continue;
    
    final lateMinutes = (record['lateMinutes'] as num?)?.toInt() ?? 0;

    if (lateMinutes > 0) {
      double fineAmount = 0;
      String formulaLog = '';

      if (fineSettings.calculationType == 'fixedPerHour') {
        final lateHours = lateMinutes / 60.0;
        final baseNet = dailyNetSalary ?? dailySalary;
        double finePerHour = 0;
        if (baseNet > 0 && shiftHours > 0) {
          finePerHour = baseNet / shiftHours;
        }
        if (finePerHour <= 0 &&
            fineSettings.finePerHour != null &&
            fineSettings.finePerHour! > 0) {
          finePerHour = fineSettings.finePerHour!;
        }
        fineAmount = finePerHour * lateHours;
        formulaLog =
            'fixedPerHour: fine = (net÷shiftH)×(lateMin÷60) = ($baseNet÷$shiftHours)×($lateMinutes÷60) = ${finePerHour.toStringAsFixed(4)}×${lateHours.toStringAsFixed(4)}';
      } else {
        // Shift-based calculation (default)
        if (dailySalary > 0 && shiftHours > 0) {
          final hourlyRate = dailySalary / shiftHours;
          final lateHours = lateMinutes / 60;
          fineAmount = hourlyRate * lateHours;
          formulaLog =
              'shiftBased: fine = (dailySalary÷shiftH)×(lateMin÷60) = ($dailySalary÷$shiftHours)×($lateMinutes÷60) = ${hourlyRate.toStringAsFixed(4)}×${lateHours.toStringAsFixed(4)}';
        }
      }

      // Round to 2 decimal places
      final preRoundFineAmount = fineAmount;
      fineAmount = (fineAmount * 100).round() / 100;
      totalFine += fineAmount;
      debugPrint(
        '[Fine][formula][test][payroll] date=${record['date']} | lateMinutes=$lateMinutes | $formulaLog | preRound=${preRoundFineAmount.toStringAsFixed(6)} | final=$fineAmount',
      );
      if (shiftHours > 0 && dailySalary > 0) {
        final minuteHours = lateMinutes / 60.0;
        final hourlyRate = dailySalary / shiftHours;
        debugPrint(
          '[Fine][formula][test][payroll] Fine = (Daily Salary ÷ Shift Hours) × (Minutes ÷ 60) '
          '= ($dailySalary ÷ $shiftHours) × ($lateMinutes ÷ 60) '
          '= ${hourlyRate.toStringAsFixed(6)} × ${minuteHours.toStringAsFixed(6)} '
          '= ${(hourlyRate * minuteHours).toStringAsFixed(6)} | '
          'preRound=${preRoundFineAmount.toStringAsFixed(6)} final=$fineAmount',
        );
      }
    } else {
      // Use existing fineAmount if available (for backward compatibility)
      final existingFine = (record['fineAmount'] as num?)?.toDouble() ?? 0.0;
      totalFine += existingFine;
      if (existingFine > 0) {
        debugPrint('[Fine TEST] payroll record: date=${record['date']}, using existing fineAmount=$existingFine');
      }
    }
  }

  debugPrint('[Fine TEST] calculatePayrollFine => totalFine=$totalFine');
  return totalFine;
}

/// Helper function to create ShiftTiming from attendance template data
/// This matches the backend's shift timing structure
ShiftTiming? createShiftTimingFromTemplate(Map<String, dynamic>? template) {
  if (template == null) return null;

  final startTime = template['shiftStartTime'] as String? ?? "09:30";
  final endTime = template['shiftEndTime'] as String? ?? "18:30";
  final gracePeriodMinutes = template['gracePeriodMinutes'] as int?;

  GraceTime? graceTime;
  if (gracePeriodMinutes != null) {
    graceTime = GraceTime(value: gracePeriodMinutes, unit: 'minutes');
  }

  return ShiftTiming(
    name: template['name'] as String? ?? 'Default Shift',
    startTime: startTime,
    endTime: endTime,
    graceTime: graceTime,
  );
}

/// Helper function to create ShiftTiming from business settings based on shift name
/// Fetches shift from settings.attendance.shifts[] array matching the shiftName or embedded shift _id.
/// When [attendanceDate] / [joiningDate] are set, rotational shifts resolve like the server (days since join modulo cycle).
ShiftTiming? createShiftTimingFromBusinessSettings(
  Map<String, dynamic>? businessSettings,
  String? shiftName, {
  DateTime? attendanceDate,
  DateTime? joiningDate,
}) {
  if (businessSettings == null || shiftName == null || shiftName.isEmpty) {
    return null;
  }

  // Navigate to settings.attendance.shifts
  final settings = businessSettings['settings'] as Map<String, dynamic>?;
  if (settings == null) return null;

  final attendance = settings['attendance'] as Map<String, dynamic>?;
  if (attendance == null) return null;

  final shifts = attendance['shifts'] as List?;
  if (shifts == null || shifts.isEmpty) return null;

  final wrapper = rs.findShiftByKey(shifts, shiftName) ??
      (shifts.first is Map
          ? Map<String, dynamic>.from(shifts.first as Map)
          : null);
  if (wrapper == null) return null;

  final day = attendanceDate ?? DateTime.now();
  final anchor = joiningDate ?? DateTime.now();
  final matchedShift =
      rs.resolveEffectiveShiftForDate(shifts, wrapper, day, anchor);

  // Extract shift timing information
  final startTime = matchedShift['startTime'] as String? ?? '09:30';
  final endTime = matchedShift['endTime'] as String? ?? '18:30';
  final graceTimeData = matchedShift['graceTime'] as Map<String, dynamic>?;

  GraceTime? graceTime;
  if (graceTimeData != null) {
    final value = graceTimeData['value'] as num?;
    final unit = graceTimeData['unit'] as String? ?? 'minutes';
    if (value != null) {
      graceTime = GraceTime(value: value.toInt(), unit: unit);
    }
  }

  return ShiftTiming(
    name: matchedShift['name'] as String? ?? shiftName,
    startTime: startTime,
    endTime: endTime,
    graceTime: graceTime,
  );
}

/// Helper function to create FineSettings from business/company settings
/// Falls back to defaults if not provided
/// Grace time is taken from the shift, not from fineSettings
FineSettings createFineSettingsFromBusinessSettings(
  Map<String, dynamic>? businessSettings,
) {
  if (businessSettings == null) {
    return FineSettings(
      enabled: true,
      graceTimeMinutes: 10, // Default 10 minutes (fallback)
      calculationType: 'shiftBased',
    );
  }

  // Extract fine settings from business settings
  // Navigate to settings.attendance.fineSettings
  final settings = businessSettings['settings'] as Map<String, dynamic>?;
  if (settings == null) {
    return FineSettings(
      enabled: true,
      graceTimeMinutes: 10,
      calculationType: 'shiftBased',
    );
  }

  final attendance = settings['attendance'] as Map<String, dynamic>?;
  if (attendance == null) {
    return FineSettings(
      enabled: true,
      graceTimeMinutes: 10,
      calculationType: 'shiftBased',
    );
  }

  final fineSettingsData = attendance['fineSettings'] as Map<String, dynamic>?;
  if (fineSettingsData == null) {
    return FineSettings(
      enabled: true,
      graceTimeMinutes: 10,
      calculationType: 'shiftBased',
    );
  }

  final fineEnabled = fineSettingsData['enabled'] as bool? ?? true;
  // Note: graceTimeMinutes here is a fallback, actual grace time comes from shift
  final defaultGraceTime = fineSettingsData['graceTimeMinutes'] as int? ?? 10;
  final calculationType =
      fineSettingsData['calculationType'] as String? ?? 'shiftBased';
  final finePerHour = fineSettingsData['finePerHour'] as num?;

  return FineSettings(
    enabled: fineEnabled,
    graceTimeMinutes: defaultGraceTime, // Fallback grace time
    calculationType: calculationType,
    finePerHour: finePerHour?.toDouble(),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Rule-based fine estimation (DB fine settings)
//
// The backend `/attendance/fine-calculation` endpoint returns a per-business
// fine config of the shape:
//   { calculationType, fineRules: [ { applyTo, type, customAmount,
//                                     customAmountUnit }, ... ] }
// where `applyTo` is one of 'lateArrival' | 'earlyExit' | 'both' (or null = all).
// These helpers mirror the rule matching + amount math used on the attendance
// screen (_hasFineRules / _matchFineRuleForAction / _computeFineFromRule) so
// request forms can preview the exact same per-user fine.
// ─────────────────────────────────────────────────────────────────────────────

/// True when the fine config carries explicit per-action rules.
bool fineConfigHasRules(Map<String, dynamic>? fineCalculation) {
  final rules = fineCalculation?['fineRules'];
  return rules is List && rules.isNotEmpty;
}

/// Finds the fine rule that applies to [actionApplyToType]
/// ('lateArrival' | 'earlyExit' | 'both'). A rule matches when its `applyTo`
/// is null/empty, equals the action, or equals 'both' — mirroring the backend.
Map<String, dynamic>? matchFineRuleForAction(
  Map<String, dynamic>? fineCalculation,
  String actionApplyToType,
) {
  final rulesRaw = fineCalculation?['fineRules'];
  if (rulesRaw is! List || rulesRaw.isEmpty) return null;
  for (final raw in rulesRaw) {
    if (raw is! Map) continue;
    final applyTo = raw['applyTo'];
    final s = applyTo?.toString().trim() ?? '';
    if (s.isEmpty || s == actionApplyToType || s == 'both') {
      return Map<String, dynamic>.from(raw);
    }
  }
  return null;
}

/// Computes the fine amount for [minutes] late/early using a single DB fine rule.
/// Supports custom (perMinute/perHour/fixed), halfday, fullday and salary-multiple
/// (1x/2x/3x) rule types. Mirrors attendance_screen._computeFineFromRule.
double computeFineFromRule({
  required Map<String, dynamic> rule,
  required int minutes,
  required double netPerDaySalary,
  required double shiftHours,
}) {
  if (minutes <= 0) return 0.0;
  final type = (rule['type']?.toString() ?? '').toLowerCase();

  if (type == 'custom') {
    final customAmount = (rule['customAmount'] as num?)?.toDouble() ?? 0.0;
    final unit =
        (rule['customAmountUnit']?.toString() ?? 'perHour').toLowerCase();
    if (unit == 'perminute') return customAmount * minutes;
    if (unit == 'perhour') return customAmount * (minutes / 60.0);
    if (unit == 'fixed') return customAmount;
    return customAmount * (minutes / 60.0);
  }

  if (type == 'halfday') return netPerDaySalary / 2.0;
  if (type == 'fullday') return netPerDaySalary;

  // Salary-multiple style rules (1xSalary / 2xSalary / 3xSalary).
  int multiplier = 1;
  if (type == '2xsalary') multiplier = 2;
  if (type == '3xsalary') multiplier = 3;

  final hourlyRate = shiftHours > 0 ? netPerDaySalary / shiftHours : 0.0;
  return hourlyRate * (minutes / 60.0) * multiplier;
}

/// Estimates the per-user fine (₹) for [minutes] of a given action
/// ('lateArrival' | 'earlyExit' | 'both'), reading the rules from
/// [fineCalculation] (the `/attendance/fine-calculation` payload).
///
/// - When the config has explicit rules: uses the matching rule, or returns 0
///   when no rule applies to the action (matches the backend, which only fines
///   actions that have a configured rule).
/// - When the config has no rules: falls back to the shift-based hourly formula
///   (netPerDaySalary ÷ shiftHours × lateHours).
///
/// Returns a value rounded to 2 decimals. Returns 0 when [minutes] or
/// [netPerDaySalary] are non-positive.
double estimateRuleBasedFine({
  required Map<String, dynamic>? fineCalculation,
  required String actionApplyToType,
  required int minutes,
  required double netPerDaySalary,
  required double shiftHours,
}) {
  if (minutes <= 0 || netPerDaySalary <= 0) return 0.0;

  double amount;
  if (fineConfigHasRules(fineCalculation)) {
    final rule = matchFineRuleForAction(fineCalculation, actionApplyToType);
    if (rule == null) return 0.0;
    amount = computeFineFromRule(
      rule: rule,
      minutes: minutes,
      netPerDaySalary: netPerDaySalary,
      shiftHours: shiftHours,
    );
  } else {
    final hourlyRate = shiftHours > 0 ? netPerDaySalary / shiftHours : 0.0;
    amount = hourlyRate * (minutes / 60.0);
  }
  return (amount * 100).round() / 100;
}
