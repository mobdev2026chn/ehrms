// hrms/lib/screens/attendance/shift_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../config/app_colors.dart';
import '../../utils/rotational_shift_util.dart';
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

  @override
  State<ShiftScreen> createState() => _ShiftScreenState();
}

class _ShiftScreenState extends State<ShiftScreen> {
  late DateTime _focusedDay;
  late DateTime _selectedDay;
  late final DateTime _today;
  late final DateTime _joiningMonthStart;

  @override
  void initState() {
    super.initState();
    final r = widget.referenceDate;
    _today = DateTime(r.year, r.month, r.day);
    _focusedDay = _today;
    _selectedDay = _today;
    final j = widget.joiningDate;
    _joiningMonthStart = j != null ? DateTime(j.year, j.month, 1) : DateTime(2020);
  }

  bool get _isAtJoiningMonth {
    final focused = DateTime(_focusedDay.year, _focusedDay.month, 1);
    return !focused.isAfter(_joiningMonthStart);
  }

  /// Effective shift for [day]. Today's merged template is only valid for today.
  EffectiveShiftDay? _shiftForDay(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    return effectiveShiftForCalendarDay(
      companyDoc: widget.companyDoc,
      staffShiftKey: widget.staffShiftKey,
      dayLocal: d,
      joiningDate: widget.joiningDate,
      attendanceTodayTemplate:
          isSameDay(d, _today) ? widget.todayTemplate : null,
    );
  }

  String? _windowOf(EffectiveShiftDay? s) {
    if (s == null) return null;
    final a = s.startTime?.trim();
    final b = s.endTime?.trim();
    if (a == null || b == null || a.isEmpty || b.isEmpty) return null;
    return '$a – $b';
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
  }

  @override
  Widget build(BuildContext context) {
    final refFmt = DateFormat('EEE, MMM d, yyyy').format(_today);
    final todaySnap = _shiftForDay(_today);

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
      body: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        children: [
          Text(
            'Your Shift',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Today\'s working window and the shift calendar.',
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 20),
          _buildTodayShiftCard(todaySnap, refFmt),
          if (todaySnap != null) ...[
            const SizedBox(height: 16),
            _buildDetailsCard(todaySnap),
          ],
          const SizedBox(height: 16),
          _buildShiftCalendarCard(),
          const SizedBox(height: 16),
          _buildSelectedDayCard(),
        ],
      ),
      bottomNavigationBar: const AppBottomNavigationBar(currentIndex: -1),
    );
  }

  /// Blue summary card — same design language as the dashboard / calendar.
  Widget _buildTodayShiftCard(EffectiveShiftDay? snap, String refFmt) {
    final rotName = snap?.rotationTemplateName?.trim();
    final shiftName = snap?.displayName.trim() ?? '';
    final window = _windowOf(snap);
    final compactLine = widget.appliedHeaderLine ?? snap?.compactLine();

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
        _windowOf(s) ?? (s.isOpen ? 'Open (flexible)' : '—'),
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
              selectedBuilder: (context, day, _) =>
                  _buildDayCell(day, selected: true),
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
    bool selected = false,
    bool isToday = false,
  }) {
    final snap = _shiftForDay(day);
    final isOff = snap?.isWeekOff ?? false;
    final start = snap?.startTime?.trim();
    final end = snap?.endTime?.trim();
    final hasWindow =
        start != null && start.isNotEmpty && end != null && end.isNotEmpty;

    final Color bg;
    final Color border;
    if (selected) {
      bg = AppColors.primary.withValues(alpha: 0.12);
      border = AppColors.primary;
    } else if (isToday) {
      bg = AppColors.primary.withValues(alpha: 0.06);
      border = AppColors.primary.withValues(alpha: 0.5);
    } else if (isOff) {
      bg = AppColors.inputFill;
      border = Colors.transparent;
    } else {
      bg = Colors.transparent;
      border = AppColors.textSecondary.withValues(alpha: 0.12);
    }

    // Times take priority over the shift name: green dot = in time (start),
    // red dot = out time (end).
    Widget detail;
    if (isOff) {
      detail = _cellNote('Off');
    } else if (hasWindow) {
      detail = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _timeRow(Colors.green, start),
          const SizedBox(height: 1),
          _timeRow(Colors.red, end),
        ],
      );
    } else if (snap?.isOpen ?? false) {
      detail = _cellNote('Open');
    } else {
      detail = const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.all(2),
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
              fontWeight: isToday || selected
                  ? FontWeight.bold
                  : FontWeight.w500,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          detail,
        ],
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

  Widget _cellNote(String text) => Text(
        text,
        maxLines: 1,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 8.5,
          height: 1.0,
          fontWeight: FontWeight.w500,
          color: AppColors.textCaption,
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
      ],
    );
  }

  Widget _buildSelectedDayCard() {
    final snap = _shiftForDay(_selectedDay);
    final window = _windowOf(snap);
    final dateStr = DateFormat('EEEE, d MMMM yyyy').format(_selectedDay);

    final String valueLine;
    if (snap == null) {
      valueLine = 'No shift assigned';
    } else if (snap.isWeekOff) {
      valueLine = 'Week Off';
    } else if (window != null) {
      valueLine = '${snap.displayName} · $window';
    } else {
      valueLine = snap.compactLine();
    }

    return AppCard(
      child: Row(
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
    );
  }
}
