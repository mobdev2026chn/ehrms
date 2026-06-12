// hrms/lib/screens/attendance/shift_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../config/app_colors.dart';
import '../../services/attendance_service.dart';
import '../../utils/holiday_off_util.dart';
import '../../utils/rotational_shift_util.dart';
import '../../utils/shift_policy_util.dart';
import '../../widgets/app_card.dart';
import '../../widgets/bottom_navigation_bar.dart';
import '../../widgets/profile_app_bar_actions.dart';

/// Full-page "Shift Time" view, opened from the dashboard Quick Action.
///
/// Computes the effective shift for any calendar day locally with
/// [effectiveShiftForCalendarDay] (the same rotational logic as the
/// assigned-shift header) — so the screen needs no attendance re-fetch. The
/// blue summary card and month calendar mirror the Attendance Calendar.
class ShiftScreen extends StatefulWidget {
  const ShiftScreen({
    super.key,
    required this.companyDoc,
    required this.staffShiftKey,
    required this.joiningDate,
    required this.todayTemplate,
    required this.referenceDate,
    this.appliedHeaderLine,
    this.initialMonthData,
  });

  /// Company doc carrying `settings.attendance.shifts` for resolution.
  final Map<String, dynamic>? companyDoc;

  /// Staff's assigned shift key (rotational wrapper or plain shift name).
  final String? staffShiftKey;

  /// Date of joining — bounds the calendar and anchors rotational cycles.
  final DateTime? joiningDate;

  /// Merged GET /attendance/today template — only applies to *today*.
  final Map<String, dynamic>? todayTemplate;

  /// "Today" reference used for the heading and today's resolution.
  final DateTime referenceDate;

  /// Compact line from an applied (swapped) shift, which overrides today's text.
  final String? appliedHeaderLine;

  /// Dashboard's already-loaded `/attendance/month` payload for the reference
  /// month (avoids a redundant fetch + throttle collision on open).
  final Map<String, dynamic>? initialMonthData;

  @override
  State<ShiftScreen> createState() => _ShiftScreenState();
}

/// What a single calendar day resolves to on the Shift screen.
enum _DayKind { working, weekOff, holiday, leave, none }

/// Resolved shift / status for one calendar day, after overlaying the staff's
/// holiday + weekly-off pattern and the month's attendance data (applied leaves
/// and the *actual* shift worked that day) on top of the rotational fallback.
class _ShiftDayInfo {
  const _ShiftDayInfo({
    required this.kind,
    this.shift,
    this.label,
    this.note,
    this.fromAttendance = false,
  });

  final _DayKind kind;

  /// Resolved shift window for a working day.
  final EffectiveShiftDay? shift;

  /// Short cell label (leave abbreviation).
  final String? label;

  /// Longer note (holiday name / leave type).
  final String? note;

  /// True when [shift] came from the day's own attendance record
  /// (`appliedShiftId`) rather than the rotational fallback — i.e. the shift
  /// the employee was actually assigned/worked that date.
  final bool fromAttendance;
}

/// Parsed per-month attendance overlay (applied leaves + the per-day
/// `appliedShiftId`). Mirrors the maps the Attendance Calendar builds.
class _MonthShiftData {
  _MonthShiftData({
    required this.statusByDate,
    required this.leaveTypeByDate,
    required this.leaveSet,
    required this.holidaySet,
    required this.holidayNameByDate,
    required this.weekOffSet,
    required this.alternateWorkSet,
    required this.appliedShiftIdByDate,
    required this.companyDocForApplied,
  });

  final Map<String, String> statusByDate;
  final Map<String, String> leaveTypeByDate;
  final Set<String> leaveSet;
  final Set<String> holidaySet;
  final Map<String, String> holidayNameByDate;

  /// Backend-computed week-off dates ('yyyy-MM-dd') — authoritative source that
  /// matches the Attendance Calendar (covers Sundays + any configured pattern).
  final Set<String> weekOffSet;

  /// Compensation work days that fall on a week-off (employee still works).
  final Set<String> alternateWorkSet;
  final Map<String, dynamic> appliedShiftIdByDate;

  /// Company doc (embedded shifts) used to resolve `appliedShiftId` → window.
  final Map<String, dynamic>? companyDocForApplied;
}

class _ShiftScreenState extends State<ShiftScreen> {
  final AttendanceService _attendanceService = AttendanceService();

  late DateTime _focusedDay;
  late DateTime _selectedDay;
  late final DateTime _today;
  late final DateTime _joiningMonthStart;

  /// Weekly-off pattern for the logged-in staff (their WeeklyHolidayTemplate or the
  /// business fallback). Layered on top of the shift template so week-off weekdays
  /// render as "Week Off" instead of the default shift window.
  HolidayOffConfig _offConfig = HolidayOffConfig.empty;

  /// Parsed attendance overlay keyed by `year-month`.
  final Map<String, _MonthShiftData> _months = {};

  /// `year-month` keys currently being fetched (de-dupes in-flight requests).
  final Set<String> _loadingMonths = {};

  @override
  void initState() {
    super.initState();
    final r = widget.referenceDate;
    _today = DateTime(r.year, r.month, r.day);
    _focusedDay = _today;
    _selectedDay = _today;
    final j = widget.joiningDate;
    _joiningMonthStart = j != null ? DateTime(j.year, j.month, 1) : DateTime(2020);
    _loadWeekOffConfig();

    // Seed the reference month from the dashboard's payload, then ensure the
    // focused month is loaded.
    final seed = widget.initialMonthData;
    if (seed != null) {
      _months[_monthKey(_today)] =
          _parseMonthData(seed, _today.year, _today.month);
    }
    _ensureMonthLoaded(_focusedDay);
  }

  Future<void> _loadWeekOffConfig() async {
    final config = await loadHolidayOffConfig();
    if (!mounted) return;
    setState(() => _offConfig = config);
  }

  // ── Month data ───────────────────────────────────────────────────────────

  String _monthKey(DateTime d) => '${d.year}-${d.month}';

  _MonthShiftData? _monthFor(DateTime d) => _months[_monthKey(d)];

  void _ensureMonthLoaded(DateTime d) {
    final key = _monthKey(d);
    if (_months.containsKey(key) || _loadingMonths.contains(key)) return;
    _fetchMonth(d.year, d.month);
  }

  Future<void> _fetchMonth(int year, int month) async {
    final key = '$year-$month';
    _loadingMonths.add(key);
    try {
      final result = await _attendanceService.getMonthAttendance(year, month);
      if (!mounted) return;
      if (result['success'] == true && result['data'] is Map) {
        final data = Map<String, dynamic>.from(result['data'] as Map);
        setState(() {
          _months[key] = _parseMonthData(data, year, month);
        });
      }
    } catch (_) {
      // Leave the month unparsed — cells fall back to rotational resolution.
    } finally {
      _loadingMonths.remove(key);
    }
  }

  /// Parses a `/attendance/month` payload into the per-day overlay maps.
  _MonthShiftData _parseMonthData(Map data, int year, int month) {
    final statusByDate = <String, String>{};
    final leaveTypeByDate = <String, String>{};
    final leaveSet = <String>{};
    final holidaySet = <String>{};
    final holidayNameByDate = <String, String>{};
    final weekOffSet = <String>{};
    final alternateWorkSet = <String>{};
    final appliedShiftIdByDate = <String, dynamic>{};

    String calDate(dynamic v) {
      if (v == null) return '';
      try {
        if (v is DateTime) {
          final u = v.toUtc();
          return '${u.year}-${u.month.toString().padLeft(2, '0')}-${u.day.toString().padLeft(2, '0')}';
        }
        final s = v.toString().trim();
        if (s.isEmpty) return '';
        if (s.contains('T')) return s.split('T').first;
        if (s.length >= 10 && s[4] == '-' && s[7] == '-') return s.substring(0, 10);
        final d = DateTime.parse(s).toUtc();
        return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      } catch (_) {
        return '';
      }
    }

    bool inMonth(String dateStr) {
      final parts = dateStr.split('-');
      if (parts.length != 3) return false;
      return (int.tryParse(parts[0]) ?? 0) == year &&
          (int.tryParse(parts[1]) ?? 0) == month;
    }

    final attendance = data['attendance'];
    if (attendance is List) {
      for (final entry in attendance) {
        if (entry is! Map) continue;
        final dateStr = calDate(entry['date']);
        if (dateStr.isEmpty || !inMonth(dateStr)) continue;
        statusByDate[dateStr] = (entry['status'] as String?) ?? 'Present';
        final leaveType = entry['leaveType'] as String?;
        if (leaveType != null && leaveType.trim().isNotEmpty) {
          leaveTypeByDate[dateStr] = leaveType.trim();
        }
        final applied = entry['appliedShiftId'];
        if (applied != null && applied.toString().trim().isNotEmpty) {
          appliedShiftIdByDate[dateStr] = applied;
        }
      }
    }

    final holidays = data['holidays'];
    if (holidays is List) {
      for (final h in holidays) {
        if (h is! Map) continue;
        final dateStr = calDate(h['date']);
        if (dateStr.isEmpty || !inMonth(dateStr)) continue;
        holidaySet.add(dateStr);
        final name = h['name']?.toString().trim();
        if (name != null && name.isNotEmpty) holidayNameByDate[dateStr] = name;
      }
    }

    void addStrings(dynamic list, Set<String> into) {
      if (list is List) {
        for (final v in list) {
          if (v is String && v.isNotEmpty) into.add(v);
        }
      }
    }

    addStrings(data['leaveDates'], leaveSet);
    addStrings(data['weekOffDates'], weekOffSet);
    addStrings(data['alternateWorkDatesInMonth'], alternateWorkSet);

    // Embedded shifts for appliedShiftId resolution prefer the month payload's
    // businessShifts; fall back to the profile company doc.
    Map<String, dynamic>? companyForApplied;
    final bs = data['businessShifts'];
    if (bs is List && bs.isNotEmpty) {
      companyForApplied = {
        'settings': {
          'attendance': {'shifts': List<dynamic>.from(bs)},
        },
      };
    } else {
      companyForApplied = widget.companyDoc;
    }

    return _MonthShiftData(
      statusByDate: statusByDate,
      leaveTypeByDate: leaveTypeByDate,
      leaveSet: leaveSet,
      holidaySet: holidaySet,
      holidayNameByDate: holidayNameByDate,
      weekOffSet: weekOffSet,
      alternateWorkSet: alternateWorkSet,
      appliedShiftIdByDate: appliedShiftIdByDate,
      companyDocForApplied: companyForApplied,
    );
  }

  bool get _isAtJoiningMonth {
    final focused = DateTime(_focusedDay.year, _focusedDay.month, 1);
    return !focused.isAfter(_joiningMonthStart);
  }

  /// Effective shift for [day]. Today's merged template is only valid for today.
  ///
  /// The staff's weekly-off pattern is applied on top of the resolved shift: a
  /// week-off weekday renders as "Week Off" rather than the shift template's
  /// default window (the shift row itself carries no week-off flag for standard
  /// templates — only the `byWeekCalendar` rotation does).
  EffectiveShiftDay? _shiftForDay(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    final base = effectiveShiftForCalendarDay(
      companyDoc: widget.companyDoc,
      staffShiftKey: widget.staffShiftKey,
      dayLocal: d,
      joiningDate: widget.joiningDate,
      attendanceTodayTemplate:
          isSameDay(d, _today) ? widget.todayTemplate : null,
    );
    if (base != null && base.isWeekOff) return base;
    if (_offConfig.isWeeklyOff(d)) {
      return EffectiveShiftDay(
        displayName: 'Week Off',
        startTime: null,
        endTime: null,
        shiftTypeLower: 'weekoff',
        openWorkHours: null,
        otBufferMinutes: null,
        rotationTemplateName: base?.rotationTemplateName,
        cycleLength: base?.cycleLength,
        cycleDayIndex1Based: base?.cycleDayIndex1Based,
        rotationalMode: base?.rotationalMode,
        isWeekOff: true,
      );
    }
    return base;
  }

  /// Resolves a stamped `appliedShiftId` to its shift window via company shifts.
  EffectiveShiftDay? _shiftFromAppliedId(dynamic appliedId, _MonthShiftData md) {
    final res = appliedShiftPastResolvedFromCompany(
      companyDoc: md.companyDocForApplied ?? widget.companyDoc,
      appliedShiftId: appliedId,
    );
    if (res == null) return null;
    return EffectiveShiftDay(
      displayName: res.shiftName,
      startTime: res.startTime,
      endTime: res.endTime,
      shiftTypeLower: res.isOpen ? 'open' : 'standard',
      openWorkHours: res.openWorkHours,
      isWeekOff: false,
    );
  }

  /// The effective day status, overlaying real attendance data when available.
  ///
  /// Priority: a day actually worked shows the shift stamped on its record (so
  /// reassigning the shift today never rewrites past days) → holiday → applied
  /// leave → week-off → rotational fallback for days without a record.
  _ShiftDayInfo _dayInfoFor(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    final dateStr = HolidayOffConfig.keyFor(d);
    final md = _monthFor(d);

    final status = md?.statusByDate[dateStr];
    final isPresent = status == 'Present' || status == 'Half Day';

    // 1. Worked → the shift stamped on that day's record (historical assignment).
    final appliedId = md?.appliedShiftIdByDate[dateStr];
    if (appliedId != null) {
      final shift = _shiftFromAppliedId(appliedId, md!);
      if (shift != null) {
        return _ShiftDayInfo(
          kind: _DayKind.working,
          shift: shift,
          fromAttendance: true,
        );
      }
    }

    // 2. Holiday (staff calendar or month payload), unless they worked it.
    final isHoliday =
        _offConfig.isHoliday(d) || (md?.holidaySet.contains(dateStr) ?? false);
    if (isHoliday && !isPresent) {
      return _ShiftDayInfo(
        kind: _DayKind.holiday,
        note: md?.holidayNameByDate[dateStr],
      );
    }

    // 3. Applied leave.
    if (md != null) {
      final leaveType = md.leaveTypeByDate[dateStr];
      if (leaveType != null && leaveType.isNotEmpty) {
        return _ShiftDayInfo(
          kind: _DayKind.leave,
          label: _leaveAbbrev(leaveType),
          note: leaveType,
        );
      }
      if (status == 'On Leave' ||
          (md.leaveSet.contains(dateStr) && !isPresent)) {
        return const _ShiftDayInfo(kind: _DayKind.leave, label: 'L', note: 'Leave');
      }
    }

    // 4. Week off. The backend-computed weekOffDates from /attendance/month is
    //    the authoritative source (matches the Attendance Calendar); the staff
    //    weekly-off pattern and rotational byWeekCalendar are fallbacks. A
    //    compensation work day overrides a week-off (the employee works it).
    final isAltWork = md?.alternateWorkSet.contains(dateStr) ?? false;
    final base = _shiftForDay(d);
    if (!isAltWork && !isPresent) {
      final monthWeekOff = md?.weekOffSet.contains(dateStr) ?? false;
      if (monthWeekOff ||
          (base != null && base.isWeekOff) ||
          _offConfig.isWeeklyOff(d)) {
        return _ShiftDayInfo(kind: _DayKind.weekOff, shift: base);
      }
    }

    // 5. Fallback → the currently allocated shift. An allocation stays in effect
    //    until it is actually changed, so the calendar should keep showing the
    //    previously allocated shift for every day (past, today, and future)
    //    rather than going blank where there is no attendance record yet. A real
    //    shift change still wins: a worked day shows its stamped appliedShiftId
    //    (step 1) and the rotation/assignment itself advances the allocation, so
    //    days after a change resolve to the new shift here.
    if (base == null) {
      return const _ShiftDayInfo(kind: _DayKind.none);
    }
    if (base.isWeekOff) {
      return _ShiftDayInfo(kind: _DayKind.weekOff, shift: base);
    }
    return _ShiftDayInfo(kind: _DayKind.working, shift: base);
  }

  /// 2-letter abbreviation for a leave type, e.g. "Casual Leave" → "CL".
  String _leaveAbbrev(String leaveType) {
    final t = leaveType.trim();
    if (t.isEmpty) return 'L';
    final words = t.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.length >= 2) {
      return (words[0][0] + words[1][0]).toUpperCase();
    }
    return t.length <= 3 ? t.toUpperCase() : t.substring(0, 2).toUpperCase();
  }

  String? _windowOf(EffectiveShiftDay? s) {
    if (s == null) return null;
    final a = s.startTime?.trim();
    final b = s.endTime?.trim();
    if (a == null || b == null || a.isEmpty || b.isEmpty) return null;
    return '${_formatTime12(a)} – ${_formatTime12(b)}';
  }

  /// Converts a 24-hour "HH:mm" time string to 12-hour clock time, e.g.
  /// "19:00" → "7:00 PM" (or "7:00p" when [compact] is set, for narrow
  /// calendar cells). Returns the input unchanged if it isn't "HH:mm".
  String _formatTime12(String time24, {bool compact = false}) {
    final parts = time24.split(':');
    if (parts.length != 2) return time24;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return time24;
    final period = h >= 12 ? 'PM' : 'AM';
    final h12 = h % 12 == 0 ? 12 : h % 12;
    final mm = m.toString().padLeft(2, '0');
    if (compact) return '$h12:$mm${period[0].toLowerCase()}';
    return '$h12:$mm $period';
  }


  void _shiftMonth(int delta) {
    final nd = DateTime(_focusedDay.year, _focusedDay.month + delta, 1);
    if (delta < 0 && nd.isBefore(_joiningMonthStart)) return;
    final maxMonth = DateTime(_today.year + 2, _today.month, 1);
    if (delta > 0 && nd.isAfter(maxMonth)) return;
    setState(() {
      _focusedDay = nd;
      _selectedDay = nd;
    });
    _ensureMonthLoaded(nd);
  }

  /// Pull-to-refresh: force-reload the focused month (and the weekly-off /
  /// holiday config) so a freshly-assigned shift or new leave shows without
  /// reopening the screen.
  Future<void> _refresh() async {
    final f = _focusedDay;
    final key = _monthKey(f);
    _months.remove(key);
    await Future.wait([
      _loadWeekOffConfig(),
      _attendanceService
          .getMonthAttendance(f.year, f.month, forceRefresh: true)
          .then((result) {
        if (!mounted) return;
        if (result['success'] == true && result['data'] is Map) {
          final data = Map<String, dynamic>.from(result['data'] as Map);
          setState(() {
            _months[key] = _parseMonthData(data, f.year, f.month);
          });
        }
      }).catchError((_) {}),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final refFmt = DateFormat('EEE, MMM d, yyyy').format(_today);
    final todayInfo = _dayInfoFor(_today);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleSpacing: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        title: const Text(
          'Shift Time',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: AppColors.textPrimary,
          ),
        ),
        actions: const [ProfileAppBarActions()],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        children: [
          // Text(
          //   'Your Shift',
          //   style: TextStyle(
          //     fontSize: 20,
          //     fontWeight: FontWeight.bold,
          //     color: AppColors.textPrimary,
          //   ),
          // ),
         // const SizedBox(height: 4),
          // Text(
          //   'Today\'s working window and the shift calendar.',
          //   style: TextStyle(
          //     fontSize: 13,
          //     height: 1.4,
          //     color: AppColors.textSecondary,
          //   ),
          // ),
          const SizedBox(height: 20),
          _buildTodayShiftCard(todayInfo, refFmt),
          if (todayInfo.kind == _DayKind.working && todayInfo.shift != null) ...[
            const SizedBox(height: 16),
            _buildDetailsCard(todayInfo.shift!),
          ],
          const SizedBox(height: 16),
          _buildPoliciesCard(),
          const SizedBox(height: 16),
          _buildShiftCalendarCard(),
          const SizedBox(height: 16),
          _buildSelectedDayCard(),
        ],
        ),
      ),
      bottomNavigationBar: const AppBottomNavigationBar(currentIndex: -1),
    );
  }

  /// Blue summary card — same design language as the dashboard / calendar.
  Widget _buildTodayShiftCard(_ShiftDayInfo info, String refFmt) {
    final snap = info.shift;
    final rotName = snap?.rotationTemplateName?.trim();
    final shiftName = snap?.displayName.trim() ?? '';
    final window = _windowOf(snap);
    final compactLine = widget.appliedHeaderLine ?? snap?.compactLine();

    // Status-only days (off / holiday / leave) show a single headline line.
    String? statusHeadline;
    switch (info.kind) {
      case _DayKind.weekOff:
        statusHeadline = 'Week Off';
        break;
      case _DayKind.holiday:
        statusHeadline = (info.note != null && info.note!.isNotEmpty)
            ? 'Holiday · ${info.note}'
            : 'Holiday';
        break;
      case _DayKind.leave:
        statusHeadline = (info.note != null && info.note!.isNotEmpty)
            ? 'On Leave · ${info.note}'
            : 'On Leave';
        break;
      case _DayKind.working:
      case _DayKind.none:
        statusHeadline = null;
        break;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blue.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.blue.shade100,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.access_time_rounded,
                  color: Colors.blue.shade800,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Today's working shift (this cycle)",
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.blue.shade900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      refFmt,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.blue.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (statusHeadline != null)
            Text(
              statusHeadline,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                height: 1.3,
                color: AppColors.textPrimary,
              ),
            )
          else ...[
            if (rotName != null && rotName.isNotEmpty) ...[
              Text(
                rotName,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 6),
            ],
            if (window != null) ...[
              Text(
                window,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  height: 1.1,
                  color: AppColors.textPrimary,
                ),
              ),
              if (shiftName.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  shiftName,
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ] else
              Text(
                (compactLine != null && compactLine.isNotEmpty)
                    ? compactLine
                    : 'No shift assigned',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  height: 1.3,
                  color: AppColors.textPrimary,
                ),
              ),
          ],
        ],
      ),
    );
  }

  /// Key/value breakdown of today's shift configuration.
  Widget _buildDetailsCard(EffectiveShiftDay s) {
    final shiftType = s.isWeekOff
        ? 'Week Off'
        : (s.isOpen ? 'Open Shift' : 'Standard');
    final cycleLabel =
        (s.cycleDayIndex1Based != null && s.cycleLength != null)
        ? 'Day ${s.cycleDayIndex1Based} of ${s.cycleLength}'
        : null;
    final otBuffer = (s.otBufferMinutes != null && s.otBufferMinutes! > 0)
        ? '${s.otBufferMinutes} min'
        : null;

    final rows = <Widget>[
      _detailRow(Icons.badge_outlined, 'Shift Name',
          s.displayName.trim().isNotEmpty ? s.displayName.trim() : '—'),
      _detailRow(
        Icons.schedule_outlined,
        'Timing',
        _windowOf(s) ??
            (s.isOpen ? 'Open · ${_requiredHoursLabel(s)}' : '—'),
      ),
      _detailRow(Icons.category_outlined, 'Shift Type', shiftType),
      _detailRow(Icons.hourglass_bottom_outlined, 'Required Hours',
          _requiredHoursLabel(s)),
      if (otBuffer != null)
        _detailRow(Icons.more_time_outlined, 'OT Buffer', otBuffer),
      if (cycleLabel != null)
        _detailRow(Icons.sync_outlined, 'Rotation Cycle', cycleLabel),
    ];

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Shift Details',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                color: AppColors.textSecondary.withValues(alpha: 0.12),
              ),
            rows[i],
          ],
        ],
      ),
    );
  }

  String _requiredHoursLabel(EffectiveShiftDay s) {
    final mins = s.requiredWorkMinutes();
    if (mins == null || mins <= 0) return '—';
    if (mins % 60 == 0) return '${mins ~/ 60}h';
    final h = mins ~/ 60;
    final m = mins % 60;
    return h > 0 ? '${h}h ${m}m' : '${m}m';
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Shift policies ──────────────────────────────────────────────────────────

  /// Break / Permission / Overtime / Half-Day availability for today's shift,
  /// resolved from the company shift row. Shows whether each function is enabled
  /// for the user and its allocated limit. The functions themselves are gated by
  /// these same policies (break via the break balance, permission via the
  /// permission balance, half-day in Apply Leave).
  Widget _buildPoliciesCard() {
    final policies = resolveShiftPoliciesForDay(
      companyDoc: widget.companyDoc,
      staffShiftKey: widget.staffShiftKey,
      dayLocal: _today,
      joiningDate: widget.joiningDate,
      attendanceTemplate: widget.todayTemplate,
    );

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Shift Policies',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          if (policies.graceTimeMinutes != null) ...[
            _infoRow(
              Icons.timelapse_outlined,
              'Grace Time',
              _minutesLabel(policies.graceTimeMinutes!),
            ),
          ] else ...[
            _infoRow(
              Icons.timelapse_outlined,
              'Grace Time',
              'Not Configured',
              valueColor: AppColors.textSecondary,
            ),
          ],
          _policyDivider(),
          _policyRow(
            Icons.coffee_outlined,
            'Break',
            policies.breakPolicy,
            allowedLabel: (p) => p.limitMinutes != null
                ? 'Allowed · ${_minutesLabel(p.limitMinutes!)}/day'
                : 'Allowed',
            unconfiguredLabel: 'Not Configured',
          ),
          _policyDivider(),
          _policyRow(
            Icons.timer_outlined,
            'Permission',
            policies.permission,
            allowedLabel: (p) => p.limitMinutes != null
                ? 'Allowed · ${_minutesLabel(p.limitMinutes!)}/month'
                : 'Allowed',
            unconfiguredLabel: 'Not Configured',
          ),
          _policyDivider(),
          _policyRow(
            Icons.more_time_outlined,
            'Overtime',
            policies.overtime,
            allowedLabel: (p) => p.multiplier != null
                ? 'Allowed · ${_multiplierLabel(p.multiplier!)}'
                : 'Allowed',
            unconfiguredLabel: 'Not Configured',
          ),
          _policyDivider(),
          _policyRow(
            Icons.hourglass_bottom_outlined,
            'Half Day',
            policies.halfDay,
            allowedLabel: (_) => 'Allowed',
            unconfiguredLabel: 'Not Configured',
          ),
        ],
      ),
    );
  }

  Widget _policyDivider() => Divider(
        height: 1,
        color: AppColors.textSecondary.withValues(alpha: 0.12),
      );

  /// Plain value row (no enabled/disabled styling) — used for informational
  /// shift settings like the late-arrival grace period.
  Widget _infoRow(IconData icon, String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: valueColor ?? AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _policyRow(
    IconData icon,
    String label,
    ShiftPolicyInfo info, {
    required String Function(ShiftPolicyInfo) allowedLabel,
    required String unconfiguredLabel,
    String disabledLabel = 'Not Allowed',
    Color? disabledColor,
  }) {
    final String value;
    final Color valueColor;
    switch (info.availability) {
      case PolicyAvailability.enabled:
        value = allowedLabel(info);
        valueColor = AppColors.success;
        break;
      case PolicyAvailability.disabled:
        value = disabledLabel;
        valueColor = disabledColor ?? Colors.red.shade600;
        break;
      case PolicyAvailability.unconfigured:
        value = unconfiguredLabel;
        valueColor = AppColors.textSecondary;
        break;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: valueColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// "90" → "1h 30m", "60" → "1h", "45" → "45 min".
  String _minutesLabel(int mins) {
    if (mins <= 0) return '0 min';
    if (mins % 60 == 0) return '${mins ~/ 60}h';
    if (mins < 60) return '$mins min';
    return '${mins ~/ 60}h ${mins % 60}m';
  }

  /// "1.5" → "1.5×", "2.0" → "2×".
  String _multiplierLabel(double m) {
    final s = m == m.roundToDouble() ? m.toInt().toString() : m.toString();
    return '$s×';
  }

  // ── Shift calendar ─────────────────────────────────────────────────────────

  Widget _buildShiftCalendarCard() {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D000000),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          _buildCalendarHeader(),
          TableCalendar(
            key: ValueKey('${_focusedDay.year}-${_focusedDay.month}'),
            firstDay: _joiningMonthStart,
            lastDay: DateTime(_today.year + 2, _today.month, _today.day),
            focusedDay: _focusedDay,
            // Pin the calendar's "today" to the screen's reference date so its
            // built-in today marker can't drift to DateTime.now() and produce a
            // second highlighted cell. Only the reference/selected day is marked.
            currentDay: _today,
            selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
            onDaySelected: (selectedDay, focusedDay) {
              setState(() {
                _selectedDay = selectedDay;
                _focusedDay = focusedDay;
              });
            },
            headerVisible: false,
            calendarFormat: CalendarFormat.month,
            availableGestures: AvailableGestures.none,
            daysOfWeekHeight: 28,
            rowHeight: 64,
            calendarBuilders: CalendarBuilders(
              defaultBuilder: (context, day, _) => _buildDayCell(day),
              // Selecting a day (tap) only updates the "Selected Day" card
              // below — it should not draw its own highlight box unless the
              // selected day is also today.
              selectedBuilder: (context, day, _) =>
                  _buildDayCell(day, isToday: isSameDay(day, _today)),
              todayBuilder: (context, day, _) =>
                  _buildDayCell(day, isToday: true),
              outsideBuilder: (context, day, _) => const SizedBox.shrink(),
            ),
          ),
          const SizedBox(height: 8),
          Divider(height: 1, color: colorScheme.outline.withValues(alpha: 0.4)),
          const SizedBox(height: 10),
          _buildLegend(),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget _buildCalendarHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(
              Icons.chevron_left_rounded,
              color: _isAtJoiningMonth
                  ? AppColors.textCaption
                  : AppColors.textPrimary,
            ),
            onPressed: _isAtJoiningMonth ? null : () => _shiftMonth(-1),
          ),
          Text(
            DateFormat('MMMM yyyy').format(_focusedDay),
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textPrimary,
            ),
            onPressed: () => _shiftMonth(1),
          ),
        ],
      ),
    );
  }

  Widget _buildDayCell(
    DateTime day, {
    bool isToday = false,
  }) {
    final info = _dayInfoFor(day);
    final snap = info.shift;
    final start = snap?.startTime?.trim();
    final end = snap?.endTime?.trim();
    final hasWindow =
        start != null && start.isNotEmpty && end != null && end.isNotEmpty;

    final Color bg;
    final Color border;
    if (isToday) {
      bg = AppColors.primary.withValues(alpha: 0.06);
      border = AppColors.primary.withValues(alpha: 0.5);
    } else if (info.kind == _DayKind.holiday) {
      bg = const Color(0xFFEEF0FF);
      border = Colors.transparent;
    } else if (info.kind == _DayKind.leave) {
      bg = const Color(0xFFDCEAFE);
      border = Colors.transparent;
    } else if (info.kind == _DayKind.weekOff) {
      bg = AppColors.inputFill;
      border = Colors.transparent;
    } else {
      bg = Colors.transparent;
      border = AppColors.textSecondary.withValues(alpha: 0.12);
    }

    // Times take priority over the shift name: green dot = in time (start),
    // red dot = out time (end).
    Widget detail;
    switch (info.kind) {
      case _DayKind.weekOff:
        detail = _cellNote('Off');
        break;
      case _DayKind.holiday:
        detail = _cellNote('Hol', color: const Color(0xFF4F46E5));
        break;
      case _DayKind.leave:
        detail = _cellNote(info.label ?? 'L', color: const Color(0xFF2563EB));
        break;
      case _DayKind.working:
        if (hasWindow) {
          detail = Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _timeRow(Colors.green, _formatTime12(start, compact: true)),
              const SizedBox(height: 1),
              _timeRow(Colors.red, _formatTime12(end, compact: true)),
            ],
          );
        } else if (snap?.isOpen ?? false) {
          // Open shifts have no fixed window — surface the required hours.
          final hrs = snap != null ? _requiredHoursLabel(snap) : '—';
          detail = Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _cellNote('Open', color: const Color(0xFF0D9488)),
              if (hrs != '—') _cellNote(hrs, color: AppColors.textSecondary),
            ],
          );
        } else {
          detail = const SizedBox.shrink();
        }
        break;
      case _DayKind.none:
        detail = const SizedBox.shrink();
        break;
    }

    // A uniform box for every day: fill the cell so 1-line and 2-line contents
    // (e.g. "Off" vs in/out times) render at the same size.
    return Padding(
      padding: const EdgeInsets.all(2),
      child: Container(
        width: double.infinity,
        height: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 1),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: border),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${day.day}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: isToday ? FontWeight.bold : FontWeight.w500,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            detail,
          ],
        ),
      ),
    );
  }

  /// One time line in a calendar cell: colored dot + HH:MM.
  Widget _timeRow(Color dotColor, String time) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 5,
          height: 5,
          decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
        ),
        const SizedBox(width: 3),
        Text(
          time,
          style: TextStyle(
            fontSize: 8.5,
            height: 1.0,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _cellNote(String text, {Color? color}) => Text(
        text,
        maxLines: 1,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 8.5,
          height: 1.0,
          fontWeight: FontWeight.w600,
          color: color ?? AppColors.textCaption,
        ),
      );

  Widget _buildLegend() {
    Widget item(Color color, String text, {bool circle = true}) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: color,
                shape: circle ? BoxShape.circle : BoxShape.rectangle,
                borderRadius: circle ? null : BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              text,
              style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
            ),
          ],
        );

    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 18,
      runSpacing: 8,
      children: [
        item(Colors.green, 'In time'),
        item(Colors.red, 'Out time'),
        item(AppColors.inputFill, 'Week Off', circle: false),
        item(const Color(0xFFEEF0FF), 'Holiday', circle: false),
        item(const Color(0xFFDCEAFE), 'Leave', circle: false),
      ],
    );
  }

  Widget _buildSelectedDayCard() {
    final info = _dayInfoFor(_selectedDay);
    final snap = info.shift;
    final window = _windowOf(snap);
    final dateStr = DateFormat('EEEE, d MMMM yyyy').format(_selectedDay);

    final String valueLine;
    switch (info.kind) {
      case _DayKind.weekOff:
        valueLine = 'Week Off';
        break;
      case _DayKind.holiday:
        valueLine = (info.note != null && info.note!.isNotEmpty)
            ? 'Holiday · ${info.note}'
            : 'Holiday';
        break;
      case _DayKind.leave:
        valueLine = (info.note != null && info.note!.isNotEmpty)
            ? 'On Leave · ${info.note}'
            : 'On Leave';
        break;
      case _DayKind.working:
        if (snap == null) {
          valueLine = 'No shift assigned';
        } else if (window != null) {
          // Show the shift time window, not the shift name.
          valueLine = window;
        } else {
          valueLine = snap.compactLine();
        }
        break;
      case _DayKind.none:
        valueLine = 'No shift assigned';
        break;
    }

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.event_note_outlined,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dateStr,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      valueLine,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
