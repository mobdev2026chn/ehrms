// Attendance tab of the admin Staff Detail screen (web: staffManagement/attendances.tsx).
// Month view of one staff member's attendance: summary counters, every day of the
// month with its status, and per-day actions (present / half day / absent / leave /
// week off - comp off / note).
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../../config/app_colors.dart';
import '../../../../../config/app_text_styles.dart';
import '../../../../../services/admin_staff_detail_service.dart';
import '../staff_detail_common.dart';

class StaffAttendanceTab extends StatefulWidget {
  const StaffAttendanceTab({super.key, required this.staff});

  final Map<String, dynamic> staff;

  @override
  State<StaffAttendanceTab> createState() => _StaffAttendanceTabState();
}

class _Day {
  _Day({
    required this.date,
    required this.key,
    this.att,
    this.schedule,
    required this.isWeekOff,
    required this.holidayName,
    required this.isHoliday,
    required this.isSandwich,
    required this.notOnboarded,
    required this.locked,
    required this.lockReason,
    required this.shiftId,
    required this.shiftLabel,
    required this.shiftUnassigned,
  });

  final DateTime date;
  final String key;
  final Map<String, dynamic>? att;
  final Map<String, dynamic>? schedule;
  final bool isWeekOff;
  final String holidayName;
  final bool isHoliday;
  final bool isSandwich;
  final bool notOnboarded;
  final bool locked;
  final String lockReason;
  final String shiftId;
  final String shiftLabel;
  final bool shiftUnassigned;

  String get status => sdStr(att?['status']);
  bool get isPresent => status == 'present';
  bool get isHalfDay => status == 'half_day';
  bool get isLeave => status == 'leave' || isSandwich;
  String get note => sdStr(att?['note']);
}

class _StaffAttendanceTabState extends State<StaffAttendanceTab> {
  final _service = AdminStaffDetailService();

  late DateTime _month;
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _attendance = {};
  Map<String, dynamic> _schedule = {};
  Map<String, dynamic> _activeShift = {};
  List<Map<String, dynamic>>? _leaveBalances;
  bool _busy = false;

  String get _staffId => sdId(widget.staff);
  DateTime? get _joining => sdDate(widget.staff['joiningDate']);

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final j = _joining;
    _month = (j != null && j.isAfter(now)) ? DateTime(j.year, j.month) : DateTime(now.year, now.month);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _service.getMonthlyAttendance(_staffId, _month.year, _month.month),
        _service.getSchedule(_staffId, _month.year, _month.month),
        _service.getActiveShift(_staffId),
      ]);
      if (!mounted) return;
      setState(() {
        _attendance = results[0];
        _schedule = results[1];
        _activeShift = results[2];
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = sdErrorText(e);
        _loading = false;
      });
    }
  }

  Future<List<Map<String, dynamic>>?> _balances() async {
    if (_leaveBalances != null) return _leaveBalances;
    try {
      final b = await _service.getLeaveBalances(_staffId);
      _leaveBalances = b;
      return b;
    } catch (e) {
      if (mounted) sdShowError(context, e);
      return null;
    }
  }

  // ───────────── day model ─────────────

  List<_Day> _buildDays() {
    final byDate = <String, Map<String, dynamic>>{};
    for (final a in (_attendance['attendances'] as List? ?? const []).whereType<Map>()) {
      final m = Map<String, dynamic>.from(a);
      final d = sdDate(m['date']);
      if (d != null) byDate[sdKey(d)] = m;
    }
    final scheduleDays = _schedule['days'] is Map ? Map<String, dynamic>.from(_schedule['days']) : <String, dynamic>{};
    final today = _schedule['todayShift'] is Map ? Map<String, dynamic>.from(_schedule['todayShift']) : null;
    final sandwich = ((_attendance['sandwichLeaveDates'] as List?) ?? const []).map((e) => e.toString()).toSet();
    final policy = _attendance['attendancePolicy'] is Map ? _attendance['attendancePolicy'] as Map : const {};
    final allowWeekOff = policy['allowAttendanceOnWeeklyOff'] == true;
    final allowHoliday = policy['allowAttendanceOnHolidays'] == true;

    final assignment = _activeShift['assignment'];
    final activeShiftId = assignment is Map ? sdId(assignment['shiftTemplateId']) : '';

    final now = DateTime.now();
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final isCurrent = _month.year == now.year && _month.month == now.month;
    final lastDay = isCurrent ? now.day : daysInMonth;
    final joining = _joining;
    final joinKey = joining == null ? '' : sdKey(joining);

    final out = <_Day>[];
    for (var d = lastDay; d >= 1; d--) {
      final date = DateTime(_month.year, _month.month, d);
      if (date.isAfter(now)) continue;
      final key = sdKey(date);
      final att = byDate[key];
      final sch = scheduleDays[key] is Map ? Map<String, dynamic>.from(scheduleDays[key]) : null;
      final status = sdStr(att?['status']);
      final worked = status == 'present' || status == 'half_day' || status == 'leave';
      final unassigned = !worked && sdStr(sch?['shiftName']) == 'Shift Not Assigned';
      final isWeekOff = worked || unassigned ? false : ((sch?['isOff'] == true) || status == 'week_off');
      final holidayName = sdStr(sch?['holidayName']);
      final holidayOnRoster = holidayName.isNotEmpty && sch?['isHoliday'] != false && !isWeekOff && !unassigned;
      final isHoliday = holidayOnRoster && status != 'present' && status != 'half_day';
      final notOnboarded = joinKey.isNotEmpty && key.compareTo(joinKey) < 0;

      final wo = att?['weekOffDetails'];
      final compOpen = wo is Map && (wo['type'] == 'Comp Off' || wo['workLogged'] == true);
      String reason = '';
      if (notOnboarded) {
        reason = 'This date falls before the staff member was onboarded, so attendance cannot be recorded for it.';
      } else if (!compOpen) {
        final holidayOpensWeekOff = holidayName.isNotEmpty && allowHoliday;
        if (unassigned) {
          reason = 'No shift is assigned to this staff member for this date.';
        } else if (isWeekOff && !allowWeekOff && !holidayOpensWeekOff) {
          reason =
              'This is a weekly off. The attendance template assigned to this staff member does not allow attendance on weekly offs.';
        } else if (holidayOnRoster && !allowHoliday) {
          reason =
              'This is a holiday. The attendance template assigned to this staff member does not allow attendance on holidays.';
        }
      }

      final shiftName = sdStr(sch?['shiftName']);
      final shiftLabel = unassigned
          ? 'Shift Not Assigned'
          : (shiftName.isNotEmpty && sch?['isOff'] != true
              ? '$shiftName${sdStr(sch?['timingLabel']).isNotEmpty ? ' · ${sch!['timingLabel']}' : ''}'
              : sdStr(today?['shiftName']));

      out.add(_Day(
        date: date,
        key: key,
        att: att,
        schedule: sch,
        isWeekOff: isWeekOff,
        holidayName: holidayName,
        isHoliday: isHoliday,
        isSandwich: sandwich.contains(key),
        notOnboarded: notOnboarded,
        locked: reason.isNotEmpty,
        lockReason: reason,
        shiftId: sdStr(sch?['shiftTemplateId']).isNotEmpty
            ? sdStr(sch?['shiftTemplateId'])
            : (sdStr(today?['shiftTemplateId']).isNotEmpty ? sdStr(today?['shiftTemplateId']) : activeShiftId),
        shiftLabel: shiftLabel,
        shiftUnassigned: unassigned,
      ));
    }
    return out;
  }

  (String, Color, Color) _statusOf(_Day d) {
    if (d.notOnboarded) return ('Not Onboarded', kSdMuted, kSdSoft);
    if (d.isSandwich) return ('Sandwich Leave', AppColors.error, AppColors.errorBg);
    if (d.isHalfDay) return ('Half Day', AppColors.warning, AppColors.warningBg);
    if (d.isPresent) return ('Present', AppColors.success, AppColors.successBg);
    if (d.isLeave) {
      final ld = d.att?['leaveDetails'];
      final name = ld is Map ? sdStr(ld['leaveType'], 'Leave') : 'Leave';
      return (name, const Color(0xFF7C3AED), const Color(0xFFEDE9FE));
    }
    if (d.isWeekOff) {
      final wo = d.att?['weekOffDetails'];
      return (wo is Map && wo['type'] == 'Comp Off' ? 'Comp Off' : 'Week Off', AppColors.info,
          AppColors.infoBg);
    }
    if (d.isHoliday) return ('Holiday', const Color(0xFF0891B2), const Color(0xFFECFEFF));
    if (d.shiftUnassigned) return ('No Shift', kSdMuted, kSdSoft);
    return ('Absent', AppColors.error, AppColors.errorBg);
  }

  // ───────────── actions ─────────────

  Future<void> _run(Future<Map<String, dynamic>> Function() call, String fallbackOk) async {
    setState(() => _busy = true);
    try {
      final res = await call();
      if (!mounted) return;
      setState(() => _busy = false);
      sdShowSuccess(context, sdStr(res['message'], fallbackOk));
      _leaveBalances = null;
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      sdShowError(context, e);
    }
  }

  Future<void> _markPresent(_Day d) async {
    if (d.shiftId.isEmpty) {
      sdShowError(context, StaffDetailApiException('No shift is assigned to this staff member for this date.'));
      return;
    }
    final result = await showDialog<(TimeOfDay, TimeOfDay?)>(
      context: context,
      builder: (_) => _TimesDialog(title: 'Mark Present', checkOutOptional: true),
    );
    if (result == null) return;
    await _run(
      () => _service.markPresent(
        staffId: _staffId,
        date: d.key,
        shiftId: d.shiftId,
        checkInTime: sdTimeOfDay(result.$1),
        checkOutTime: result.$2 == null ? null : sdTimeOfDay(result.$2!),
      ),
      'Attendance marked present.',
    );
  }

  Future<void> _markHalfDay(_Day d) async {
    final balances = await _balances();
    if (balances == null || !mounted) return;
    final leaveNames = _leaveNames(balances);
    if (leaveNames.isEmpty) {
      sdShowError(context, StaffDetailApiException('No leave types are assigned to this staff member.'));
      return;
    }
    final result = await showDialog<(TimeOfDay, TimeOfDay?, String)>(
      context: context,
      builder: (_) => _TimesDialog(title: 'Mark Half Day', checkOutOptional: false, leaveTypes: leaveNames),
    );
    if (result == null) return;
    await _run(
      () => _service.markHalfDay(
        staffId: _staffId,
        date: d.key,
        shiftId: d.shiftId,
        checkInTime: sdTimeOfDay(result.$1),
        checkOutTime: sdTimeOfDay(result.$2!),
        leaveType: result.$3,
      ),
      'Half Day attendance recorded successfully',
    );
  }

  List<String> _leaveNames(List<Map<String, dynamic>> balances) {
    final seen = <String>{};
    final names = <String>[];
    for (final b in balances) {
      final n = sdStr(b['leaveTypeName']);
      if (n.isNotEmpty && seen.add(n.toLowerCase())) names.add(n);
    }
    return names;
  }

  Future<void> _markAbsent(_Day d) async {
    final ok = await sdConfirm(context,
        title: 'Mark Absent',
        message: 'Mark ${DateFormat('dd MMM yyyy').format(d.date)} as absent? The day will be deducted.',
        confirmText: 'Mark Absent',
        danger: true);
    if (!ok) return;
    await _run(() => _service.markAbsent(staffId: _staffId, date: d.key), 'Absent attendance recorded successfully');
  }

  Future<void> _markLeave(_Day d) async {
    final balances = await _balances();
    if (balances == null || !mounted) return;
    if (balances.isEmpty) {
      sdShowError(context, StaffDetailApiException('No leave types are assigned to this staff member.'));
      return;
    }
    final ld = d.att?['leaveDetails'];
    final current = ld is Map ? sdStr(ld['leaveType']) : '';
    final chosen = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Select Leave Type', style: AppTextStyles.headingMedium),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final b in balances)
                    if (sdStr(b['leaveTypeName']).isNotEmpty)
                      ListTile(
                        title: Text(sdStr(b['leaveTypeName']),
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                        subtitle: Text(
                            'Balance: ${sdNum(b['balance']).toStringAsFixed(1)} · ${sdStr(b['leaveTypeCategory'], 'paid')}',
                            style: AppTextStyles.caption.copyWith(color: kSdMuted)),
                        trailing: sdStr(b['leaveTypeName']) == current
                            ? const Icon(Icons.check_circle_rounded, color: AppColors.success)
                            : null,
                        onTap: () => Navigator.pop(ctx, sdStr(b['leaveTypeName'])),
                      ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (chosen == null) return;
    await _run(() => _service.markLeave(staffId: _staffId, date: d.key, leaveType: chosen),
        'Leave attendance recorded successfully');
  }

  Future<void> _weekOff(_Day d) async {
    final result = await showDialog<(String, String?)>(
      context: context,
      builder: (_) => const _WeekOffDialog(),
    );
    if (result == null) return;
    await _run(
      () => _service.convertWeekOff(
        staffId: _staffId,
        date: d.key,
        leaveType: result.$1,
        alternateWorkDate: result.$2,
        policyName: 'Weekly Off',
      ),
      'Week Off configuration saved successfully.',
    );
  }

  Future<void> _note(_Day d) async {
    final text = await sdAskText(context,
        title: d.note.isEmpty ? 'Add Note' : 'Edit Note',
        label: 'Note',
        initial: d.note,
        required: false,
        confirmText: 'Save');
    if (text == null) return;
    await _run(() => _service.saveAttendanceNote(staffId: _staffId, date: d.key, note: text), 'Note saved successfully.');
  }

  void _openDay(_Day d) {
    final (label, color, bg) = _statusOf(d);
    final pd = d.att?['presentDetails'];
    final fine = d.att?['fineAdjustment'];
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        Widget action(IconData icon, String text, VoidCallback onTap, {Color c = kSdInk}) => ListTile(
              dense: true,
              leading: Icon(icon, color: c, size: 20),
              title: Text(text, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c)),
              onTap: () {
                Navigator.pop(ctx);
                onTap();
              },
            );
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                    child: Text(DateFormat('EEEE, dd MMM yyyy').format(d.date),
                        style: AppTextStyles.headingSmall),
                  ),
                  SdPill(label, color: color, bg: bg),
                ]),
                const SizedBox(height: 10),
                if (d.shiftLabel.isNotEmpty) SdKeyValue('Shift', d.shiftLabel),
                if (d.holidayName.isNotEmpty) SdKeyValue('Holiday', d.holidayName),
                if (pd is Map) ...[
                  SdKeyValue('Check In', sdStr(pd['checkInTime'], '-')),
                  SdKeyValue('Check Out', sdStr(pd['checkOutTime'], '-')),
                  if (pd['totalHours'] != null) SdKeyValue('Total Hours', sdStr(pd['totalHours'])),
                  if (sdStr(pd['device']).isNotEmpty) SdKeyValue('Device', sdStr(pd['device'])),
                  if (sdStr(pd['location']).isNotEmpty) SdKeyValue('Location', sdStr(pd['location'])),
                ],
                if (fine is Map && sdNum(fine['totalFine']) > 0)
                  SdKeyValue('Fine', '${sdMoney(fine['totalFine'])} (${sdStr(fine['status'], 'Pending')})'),
                if (d.note.isNotEmpty) SdKeyValue('Note', d.note),
                const Divider(height: 20),
                if (d.locked)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: kSdSoft, borderRadius: BorderRadius.circular(12)),
                    child: Row(children: [
                      const Icon(Icons.lock_outline_rounded, size: 18, color: kSdMuted),
                      const SizedBox(width: 8),
                      Expanded(child: Text(d.lockReason, style: AppTextStyles.bodySmall)),
                    ]),
                  )
                else if (d.isSandwich)
                  const Text('Sandwich Leave is derived from the leave rules and cannot be edited here.',
                      style: TextStyle(fontSize: 12.5, color: kSdMuted))
                else ...[
                  action(Icons.check_circle_outline_rounded, 'Mark Present', () => _markPresent(d),
                      c: AppColors.success),
                  action(Icons.timelapse_rounded, 'Mark Half Day', () => _markHalfDay(d), c: AppColors.warning),
                  action(Icons.cancel_outlined, 'Mark Absent', () => _markAbsent(d), c: AppColors.error),
                  action(Icons.event_busy_outlined, 'Mark Leave', () => _markLeave(d), c: const Color(0xFF7C3AED)),
                  action(Icons.weekend_outlined, 'Week Off / Comp Off', () => _weekOff(d),
                      c: AppColors.info),
                ],
                if (!d.notOnboarded)
                  action(Icons.sticky_note_2_outlined, d.note.isEmpty ? 'Add Note' : 'Edit Note', () => _note(d)),
              ],
            ),
          ),
        );
      },
    );
  }

  // ───────────── UI ─────────────

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final canNext = DateTime(_month.year, _month.month + 1).isBefore(DateTime(now.year, now.month + 1));
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          SdMonthBar(
            month: _month,
            canGoNext: canNext,
            onChanged: (m) {
              setState(() => _month = m);
              _load();
            },
          ),
          if (_busy) const LinearProgressIndicator(minHeight: 2),
          if (_loading)
            const SdLoading()
          else if (_error != null)
            SdErrorView(message: _error!, onRetry: _load)
          else ...[
            _buildSummary(),
            ..._buildDayList(),
          ],
        ],
      ),
    );
  }

  Widget _buildSummary() {
    final a = _attendance;
    Widget tile(String label, dynamic v, Color c, double w) => Container(
          width: w,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(color: c.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
          child: Column(children: [
            Text(sdNum(v) % 1 == 0 ? sdNum(v).toInt().toString() : sdNum(v).toStringAsFixed(1),
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: c)),
            const SizedBox(height: 4),
            Text(label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500, color: kSdMuted)),
          ]),
        );
    return SdCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SdSectionTitle('Attendance Summary', icon: Icons.insights_rounded),
          LayoutBuilder(builder: (context, box) {
            final w = (box.maxWidth - 16) / 3;
            return Wrap(spacing: 8, runSpacing: 8, children: [
              tile('Present', a['presentCount'], AppColors.success, w),
              tile('Half Day', a['halfDayCount'], AppColors.warning, w),
              tile('Absent', a['absentCount'], AppColors.error, w),
              tile('Paid Leave', a['paidLeaveCount'], const Color(0xFF7C3AED), w),
              tile('Unpaid Leave', a['unpaidLeaveCount'], const Color(0xFFBE185D), w),
              tile('Week Off', a['weeklyOffCount'], AppColors.info, w),
              tile('Holiday', a['holidayCount'], const Color(0xFF0891B2), w),
              tile('Payable Days', a['payableDays'], kSdInk, w),
              tile('Working Days', a['totalPayableDays'], kSdMuted, w),
            ]);
          }),
        ],
      ),
    );
  }

  List<Widget> _buildDayList() {
    final days = _buildDays();
    if (days.isEmpty) {
      return const [SdEmptyView(message: 'No days to show for this month', icon: Icons.event_busy_outlined)];
    }
    return days.map((d) {
      final (label, color, bg) = _statusOf(d);
      final pd = d.att?['presentDetails'];
      String sub = d.shiftLabel;
      if (pd is Map && (d.isPresent || d.isHalfDay)) {
        final inT = sdStr(pd['checkInTime']);
        final outT = sdStr(pd['checkOutTime']);
        sub = outT.isNotEmpty && outT != 'NA' ? '$inT - $outT' : inT;
      } else if (d.holidayName.isNotEmpty && d.isHoliday) {
        sub = d.holidayName;
      }
      return InkWell(
        onTap: () => _openDay(d),
        borderRadius: BorderRadius.circular(16),
        child: SdCard(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 48,
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(12)),
                child: Column(children: [
                  Text('${d.date.day}', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: color)),
                  Text(DateFormat('EEE').format(d.date).toUpperCase(),
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: kSdMuted)),
                ]),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(sub.isEmpty ? '-' : sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: kSdInk)),
                    if (d.note.isNotEmpty)
                      Text('Note: ${d.note}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.caption.copyWith(color: kSdMuted)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (d.locked) const Padding(padding: EdgeInsets.only(right: 4), child: Icon(Icons.lock_outline_rounded, size: 16, color: kSdSubtle)),
              SdPill(label, color: color, bg: bg),
            ],
          ),
        ),
      );
    }).toList();
  }
}

/// Check-in / check-out (and, for half day, leave type) picker.
class _TimesDialog extends StatefulWidget {
  const _TimesDialog({required this.title, required this.checkOutOptional, this.leaveTypes});
  final String title;
  final bool checkOutOptional;
  final List<String>? leaveTypes;

  @override
  State<_TimesDialog> createState() => _TimesDialogState();
}

class _TimesDialogState extends State<_TimesDialog> {
  TimeOfDay _in = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay? _out;
  String? _leave;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (!widget.checkOutOptional) _out = const TimeOfDay(hour: 13, minute: 0);
  }

  Widget _timeRow(String label, TimeOfDay? value, ValueChanged<TimeOfDay> onPicked, {VoidCallback? onClear}) {
    return InkWell(
      onTap: () async {
        final t = await showTimePicker(context: context, initialTime: value ?? const TimeOfDay(hour: 18, minute: 0));
        if (t != null) onPicked(t);
      },
      child: InputDecorator(
        decoration: sdInput(label).copyWith(
          suffixIcon: onClear != null && value != null
              ? IconButton(tooltip: 'Clear', icon: const Icon(Icons.close_rounded, size: 18), onPressed: onClear)
              : const Icon(Icons.access_time_rounded, size: 18),
        ),
        child: Text(value == null ? 'Not set' : sdTimeOfDay(value), style: const TextStyle(fontSize: 13.5)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title, style: AppTextStyles.headingMedium),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _timeRow('Check In', _in, (t) => setState(() => _in = t)),
          const SizedBox(height: 10),
          _timeRow(widget.checkOutOptional ? 'Check Out (optional)' : 'Check Out', _out,
              (t) => setState(() => _out = t),
              onClear: widget.checkOutOptional ? () => setState(() => _out = null) : null),
          if (widget.leaveTypes != null) ...[
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _leave,
              isExpanded: true,
              decoration: sdInput('Leave for the other half'),
              items: widget.leaveTypes!
                  .map((l) => DropdownMenuItem(value: l, child: Text(l, style: const TextStyle(fontSize: 13.5))))
                  .toList(),
              onChanged: (v) => setState(() => _leave = v),
            ),
          ],
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: const TextStyle(fontSize: 12, color: AppColors.error)),
            ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          style: sdPrimaryButton(),
          onPressed: () {
            if (widget.leaveTypes != null) {
              if (_leave == null) {
                setState(() => _error = 'Select a leave type.');
                return;
              }
              Navigator.pop(context, (_in, _out, _leave!));
            } else {
              Navigator.pop(context, (_in, _out));
            }
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _WeekOffDialog extends StatefulWidget {
  const _WeekOffDialog();

  @override
  State<_WeekOffDialog> createState() => _WeekOffDialogState();
}

class _WeekOffDialogState extends State<_WeekOffDialog> {
  String _type = 'Week Off';
  DateTime? _alternate;
  String? _error;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Week Off', style: AppTextStyles.headingMedium),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _type,
            decoration: sdInput('Type'),
            items: const [
              DropdownMenuItem(value: 'Week Off', child: Text('Week Off')),
              DropdownMenuItem(value: 'Comp Off', child: Text('Comp Off')),
            ],
            onChanged: (v) => setState(() => _type = v ?? 'Week Off'),
          ),
          if (_type == 'Comp Off') ...[
            const SizedBox(height: 10),
            InkWell(
              onTap: () async {
                final tomorrow = DateTime.now().add(const Duration(days: 1));
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _alternate ?? tomorrow,
                  firstDate: DateTime(tomorrow.year, tomorrow.month, tomorrow.day),
                  lastDate: DateTime(tomorrow.year + 1, 12, 31),
                  helpText: 'Alternate work date',
                );
                if (picked != null) setState(() => _alternate = picked);
              },
              child: InputDecorator(
                decoration: sdInput('Alternate Work Date'),
                child: Text(_alternate == null ? 'Select a future date' : sdFmtDate(_alternate),
                    style: const TextStyle(fontSize: 13.5)),
              ),
            ),
          ],
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: const TextStyle(fontSize: 12, color: AppColors.error)),
            ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          style: sdPrimaryButton(),
          onPressed: () {
            if (_type == 'Comp Off' && _alternate == null) {
              setState(() => _error = 'Please select an alternate work date for Comp Off.');
              return;
            }
            Navigator.pop(context, (_type, _type == 'Comp Off' ? sdKey(_alternate!) : null));
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
