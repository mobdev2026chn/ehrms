import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_colors.dart';
import '../services/attendance_service.dart';
import '../services/attendance_template_store.dart';

const String _keyPrefix = 'absent_alert_shown';
const Duration _firstAbsentAlertOffset = Duration(minutes: 10);
const Duration _secondAbsentAlertOffset = Duration(hours: 2);

/// In-memory guard so we never show more than one dialog (e.g. if two screens call at once).
bool _absentAlertShowing = false;
Timer? _absentAlertTimer;
String? _scheduledAbsentAlertKey;

/// Blinking icon for the absent alert (repeating opacity pulse).
class _BlinkingAlertIcon extends StatefulWidget {
  const _BlinkingAlertIcon();

  @override
  State<_BlinkingAlertIcon> createState() => _BlinkingAlertIconState();
}

class _BlinkingAlertIconState extends State<_BlinkingAlertIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Opacity(
          opacity: _animation.value,
          child: child,
        );
      },
      child: const Text('🚨', style: TextStyle(fontSize: 56), textAlign: TextAlign.center),
    );
  }
}

/// Shows the "Absent Notification" popup after shift start +10 minutes and
/// shift start +2 hours, only until shift end, when user has not punched in.
Future<void> showAbsentAlertIfNeeded(
  BuildContext context, {
  required bool hasPunchInToday,
  bool suppressAlert = false,
}) async {
  final now = DateTime.now();
  if (hasPunchInToday || suppressAlert) {
    _cancelScheduledAbsentAlert();
    return;
  }

  final schedule = await _loadAbsentAlertSchedule(now);
  if (schedule == null || !now.isBefore(schedule.shiftEnd)) {
    _cancelScheduledAbsentAlert();
    return;
  }

  final prefs = await SharedPreferences.getInstance();
  final firstKey = _alertKey(schedule.shiftStart, '10m');
  final secondKey = _alertKey(schedule.shiftStart, '2h');
  final firstShown = prefs.getBool(firstKey) == true;
  final secondShown = prefs.getBool(secondKey) == true;

  final shouldShowFirst =
      !firstShown &&
      !now.isBefore(schedule.firstAlertAt) &&
      now.isBefore(schedule.secondAlertAt) &&
      now.isBefore(schedule.shiftEnd);
  final shouldShowSecond =
      !secondShown &&
      !now.isBefore(schedule.secondAlertAt) &&
      now.isBefore(schedule.shiftEnd);

  if (!shouldShowFirst && !shouldShowSecond) {
    _scheduleNextAbsentAlert(
      context,
      schedule: schedule,
      hasPunchInToday: hasPunchInToday,
      suppressAlert: suppressAlert,
      firstShown: firstShown,
      secondShown: secondShown,
    );
    return;
  }

  if (_absentAlertShowing) return;

  if (!context.mounted) return;

  // Mark as shown before displaying so a second call (e.g. from another screen) does not stack another dialog
  _absentAlertShowing = true;
  await prefs.setBool(shouldShowFirst ? firstKey : secondKey, true);

  try {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext ctx) {
      final colorScheme = Theme.of(ctx).colorScheme;
      return Dialog(
        backgroundColor: Colors.transparent,
        child: Material(
          color: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 340),
            decoration: BoxDecoration(
              color: const Color(0xFF2A2A2A).withOpacity(0.85),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF0D0D0D), width: 2),
              boxShadow: [
                BoxShadow(
                  color: colorScheme.shadow.withOpacity(0.2),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _BlinkingAlertIcon(),
                const SizedBox(height: 20),
                Text(
                  'Absent Notification',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white.withOpacity(0.9),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'You have not logged in today. Please update your attendance.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.4,
                    color: Colors.white.withOpacity(0.8),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: Material(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      onTap: () {
                        Navigator.of(ctx, rootNavigator: true).pop();
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 14),
                        child: Text(
                          'OK',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
    );
  } finally {
    _absentAlertShowing = false;
    _scheduleNextAbsentAlert(
      context,
      schedule: schedule,
      hasPunchInToday: false,
      suppressAlert: suppressAlert,
      firstShown: (shouldShowFirst || firstShown),
      secondShown: (shouldShowSecond || secondShown),
    );
  }
}

void _scheduleNextAbsentAlert(
  BuildContext context, {
  required _AbsentAlertSchedule schedule,
  required bool hasPunchInToday,
  required bool suppressAlert,
  required bool firstShown,
  required bool secondShown,
}) {
  if (hasPunchInToday || suppressAlert || !context.mounted) {
    _cancelScheduledAbsentAlert();
    return;
  }

  final now = DateTime.now();
  DateTime? target;
  String? targetSlot;

  if (!firstShown &&
      now.isBefore(schedule.firstAlertAt) &&
      schedule.firstAlertAt.isBefore(schedule.shiftEnd)) {
    target = schedule.firstAlertAt;
    targetSlot = '10m';
  } else if (!secondShown &&
      now.isBefore(schedule.secondAlertAt) &&
      schedule.secondAlertAt.isBefore(schedule.shiftEnd)) {
    target = schedule.secondAlertAt;
    targetSlot = '2h';
  }

  if (target == null || targetSlot == null) {
    _cancelScheduledAbsentAlert();
    return;
  }

  final targetKey = _alertKey(schedule.shiftStart, targetSlot);
  if (_scheduledAbsentAlertKey == targetKey) return;

  _cancelScheduledAbsentAlert();
  _scheduledAbsentAlertKey = targetKey;
  _absentAlertTimer = Timer(target.difference(now), () async {
    _scheduledAbsentAlertKey = null;
    if (!context.mounted) return;
    final latestState = await _resolveTodayAttendanceState(
      fallbackHasPunchInToday: hasPunchInToday,
      fallbackSuppressAlert: suppressAlert,
    );
    if (!context.mounted) return;
    await showAbsentAlertIfNeeded(
      context,
      hasPunchInToday: latestState.hasPunchInToday,
      suppressAlert: latestState.suppressAlert,
    );
  });
}

void _cancelScheduledAbsentAlert() {
  _absentAlertTimer?.cancel();
  _absentAlertTimer = null;
  _scheduledAbsentAlertKey = null;
}

Future<({bool hasPunchInToday, bool suppressAlert})> _resolveTodayAttendanceState({
  required bool fallbackHasPunchInToday,
  required bool fallbackSuppressAlert,
}) async {
  try {
    final response = await AttendanceService().getTodayAttendance();
    if (response['success'] == true && response['data'] is Map<String, dynamic>) {
      final raw = response['data'] as Map<String, dynamic>;
      final data = flattenTodayAttendancePayload(raw) ?? raw;
      final punchIn = data['punchIn']?.toString().trim();
      final hasPunchIn = punchIn != null && punchIn.isNotEmpty;
      final hasPunchInRoot = data['hasPunchIn'] == true;
      return (
        hasPunchInToday: hasPunchIn || hasPunchInRoot,
        suppressAlert: shouldSuppressAbsentAlert(data),
      );
    }
  } catch (_) {}
  return (
    hasPunchInToday: fallbackHasPunchInToday,
    suppressAlert: fallbackSuppressAlert,
  );
}

/// Merges nested attendance document (`data`) with root-level fields from
/// GET `/api/attendance/today`. The dashboard previously used only the inner
/// document, which dropped [isHoliday], [isWeeklyOff], comp-off flags, etc.
Map<String, dynamic>? flattenTodayAttendancePayload(dynamic apiBody) {
  if (apiBody is! Map) return null;
  final root = Map<String, dynamic>.from(apiBody);
  final out = <String, dynamic>{};
  final inner = root['data'];
  if (inner is Map) {
    out.addAll(Map<String, dynamic>.from(inner));
  }
  const keysFromRoot = <String>[
    'isHoliday',
    'isWeeklyOff',
    'isAlternateWorkDate',
    'isCompensationWeekOff',
    'isCompensationCompOff',
    'isOnLeave',
    'isPaidLeaveToday',
    'halfDayLeave',
    'template',
    'branch',
    'shiftAssigned',
    'checkInAllowed',
    'checkOutAllowed',
    'hasPunchIn',
    'hasPunchOut',
    'checkedIn',
    'punchIn',
    'punchOut',
    'status',
    'leaveType',
    'session',
    'halfDaySession',
    'address',
    'fineAmount',
    'fineHours',
    'lateMinutes',
    'earlyMinutes',
    'netPerDaySalary',
  ];
  for (final k in keysFromRoot) {
    if (root.containsKey(k)) out[k] = root[k];
  }
  return out.isEmpty ? null : out;
}

/// True if [value] is a non-empty string (or value) that parses as [DateTime].
/// Used for attendance collection [punchIn] / [punchOut] fields from the API.
bool hasParsablePunchDateTime(dynamic value) {
  if (value == null) return false;
  final s = value.toString().trim();
  if (s.isEmpty) return false;
  return DateTime.tryParse(s) != null;
}

/// Whether the today API payload implies the user is **checked in** and should see **Punch Out**.
/// Matches backend `getTodayAttendance`: [checkedIn], else [hasPunchIn]/[hasPunchOut], else parsed [punchIn]/[punchOut].
bool isAwaitingPunchOutFromTodayAttendance(Map<String, dynamic>? attendance) {
  if (attendance == null) return false;
  final checkedIn = attendance['checkedIn'];
  if (checkedIn is bool) return checkedIn;

  final hasInFlag = attendance['hasPunchIn'] == true;
  final hasOutFlag = attendance['hasPunchOut'] == true;
  final hasInTime = hasParsablePunchDateTime(attendance['punchIn']);
  final hasOutTime = hasParsablePunchDateTime(attendance['punchOut']);
  final hasIn = hasInFlag || hasInTime;
  final hasOut = hasOutFlag || hasOutTime;
  return hasIn && !hasOut;
}

/// Same rule as [isAwaitingPunchOutFromTodayAttendance] using only cached punch strings (e.g. prefs).
bool isAwaitingPunchOutFromCachedPunchStrings({
  required String? punchIn,
  required String? punchOut,
}) {
  return hasParsablePunchDateTime(punchIn) && !hasParsablePunchDateTime(punchOut);
}

bool shouldSuppressAbsentAlert(Map<String, dynamic>? todayAttendance) {
  if (todayAttendance == null) return false;

  final isHoliday = todayAttendance['isHoliday'] == true;
  final isOnLeave = todayAttendance['isOnLeave'] == true;
  final isPaidLeaveToday = todayAttendance['isPaidLeaveToday'] == true;
  final hasHalfDayLeave = todayAttendance['halfDayLeave'] is Map;
  final isWeeklyOff = todayAttendance['isWeeklyOff'] == true;
  final isCompensationWeekOff = todayAttendance['isCompensationWeekOff'] == true;
  final isCompensationCompOff = todayAttendance['isCompensationCompOff'] == true;

  if (isHoliday ||
      isOnLeave ||
      isPaidLeaveToday ||
      hasHalfDayLeave ||
      isWeeklyOff ||
      isCompensationWeekOff ||
      isCompensationCompOff) {
    return true;
  }

  // Fallback when only attendance record / dashboard stats fields exist (no API flags).
  final statusRaw = todayAttendance['status']?.toString().trim() ?? '';
  final sl = statusRaw.toLowerCase();
  if (sl == 'on leave' ||
      sl == 'holiday' ||
      sl == 'week off' ||
      sl == 'comp off' ||
      sl.contains('compensation week off')) {
    return true;
  }

  return false;
}

Future<_AbsentAlertSchedule?> _loadAbsentAlertSchedule(DateTime now) async {
  Map<String, dynamic>? details = await AttendanceTemplateStore.loadTemplateDetails();
  Map<String, dynamic>? template = _extractTemplate(details);

  if (!_hasValidShiftTimings(template)) {
    try {
      final response = await AttendanceService().getTodayAttendance();
      if (response['success'] == true && response['data'] is Map<String, dynamic>) {
        details = Map<String, dynamic>.from(response['data'] as Map<String, dynamic>);
        await AttendanceTemplateStore.saveTemplateDetails(details);
        template = _extractTemplate(details);
      }
    } catch (_) {}
  }

  if (!_hasValidShiftTimings(template)) return null;

  final shiftStart = _parseTimeOnDate(
    template!['shiftStartTime']?.toString(),
    now,
  );
  var shiftEnd = _parseTimeOnDate(
    template['shiftEndTime']?.toString(),
    now,
  );
  if (shiftStart == null || shiftEnd == null) return null;
  if (!shiftEnd.isAfter(shiftStart)) {
    shiftEnd = shiftEnd.add(const Duration(days: 1));
  }

  return _AbsentAlertSchedule(
    shiftStart: shiftStart,
    shiftEnd: shiftEnd,
    firstAlertAt: shiftStart.add(_firstAbsentAlertOffset),
    secondAlertAt: shiftStart.add(_secondAbsentAlertOffset),
  );
}

Map<String, dynamic>? _extractTemplate(Map<String, dynamic>? details) {
  if (details == null) return null;
  final template = details['template'];
  if (template is Map<String, dynamic>) return template;
  if (template is Map) return Map<String, dynamic>.from(template);
  if (details['shiftStartTime'] != null || details['shiftEndTime'] != null) {
    return details;
  }
  return null;
}

bool _hasValidShiftTimings(Map<String, dynamic>? template) {
  final start = template?['shiftStartTime']?.toString().trim();
  final end = template?['shiftEndTime']?.toString().trim();
  return start != null && start.isNotEmpty && end != null && end.isNotEmpty;
}

DateTime? _parseTimeOnDate(String? raw, DateTime date) {
  if (raw == null || raw.trim().isEmpty) return null;
  final parts = raw.trim().split(':');
  if (parts.length < 2) return null;
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  final second = parts.length > 2 ? int.tryParse(parts[2]) ?? 0 : 0;
  if (hour == null || minute == null) return null;
  return DateTime(date.year, date.month, date.day, hour, minute, second);
}

String _alertKey(DateTime shiftStart, String slot) {
  final datePart =
      '${shiftStart.year}${shiftStart.month.toString().padLeft(2, '0')}${shiftStart.day.toString().padLeft(2, '0')}';
  return '${_keyPrefix}_${datePart}_$slot';
}

class _AbsentAlertSchedule {
  final DateTime shiftStart;
  final DateTime shiftEnd;
  final DateTime firstAlertAt;
  final DateTime secondAlertAt;

  const _AbsentAlertSchedule({
    required this.shiftStart,
    required this.shiftEnd,
    required this.firstAlertAt,
    required this.secondAlertAt,
  });
}
