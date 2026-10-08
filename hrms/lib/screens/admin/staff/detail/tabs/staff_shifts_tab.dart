// Shifts tab of the admin Staff Detail screen (web: staffManagement/shifts.tsx).
// Month calendar of the staff member's resolved shifts, with daily overrides.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../../config/app_colors.dart';
import '../../../../../config/app_text_styles.dart';
import '../../../../../services/admin_staff_detail_service.dart';
import '../staff_detail_common.dart';

class StaffShiftsTab extends StatefulWidget {
  const StaffShiftsTab({super.key, required this.staff});

  final Map<String, dynamic> staff;

  @override
  State<StaffShiftsTab> createState() => _StaffShiftsTabState();
}

class _StaffShiftsTabState extends State<StaffShiftsTab> {
  final _service = AdminStaffDetailService();

  late DateTime _month;
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _days = {};
  Map<String, dynamic>? _today;
  List<Map<String, dynamic>>? _templates;
  bool _busy = false;

  String get _staffId => sdId(widget.staff);
  String get _joinKey => sdIsoKey(widget.staff['joiningDate']);

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _service.getSchedule(_staffId, _month.year, _month.month);
      if (!mounted) return;
      setState(() {
        _days = data['days'] is Map ? Map<String, dynamic>.from(data['days']) : {};
        _today = data['todayShift'] is Map ? Map<String, dynamic>.from(data['todayShift']) : null;
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

  Map<String, dynamic>? _day(String key) => _days[key] is Map ? Map<String, dynamic>.from(_days[key]) : null;

  bool _unassigned(Map<String, dynamic>? d) => sdStr(d?['shiftName']) == 'Shift Not Assigned';

  /// Week offs on an "alternate" pattern land on Sundays - the web patches these the same way.
  bool _isOff(Map<String, dynamic>? d, DateTime date) {
    if (d == null) return false;
    if (d['weekOffPatternType'] == 'alternate' && date.weekday == DateTime.sunday && !_unassigned(d)) return true;
    return d['isOff'] == true;
  }

  Future<List<Map<String, dynamic>>?> _loadTemplates() async {
    if (_templates != null) return _templates;
    try {
      final t = await _service.getShiftTemplates();
      _templates = t.where((x) => x['isActive'] != false).toList();
      return _templates;
    } catch (e) {
      if (mounted) sdShowError(context, e);
      return null;
    }
  }

  Future<void> _override(DateTime date) async {
    final templates = await _loadTemplates();
    if (templates == null || !mounted) return;
    if (templates.isEmpty) {
      sdShowError(context, StaffDetailApiException('No shift templates found. Create one in Attendance settings.'));
      return;
    }
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (_) => _OverrideDialog(templates: templates, date: date),
    );
    if (result == null) return;
    await _save(() => _service.saveShiftOverride(
          staffId: _staffId,
          date: sdKey(date),
          overrideType: 'work_shift',
          shiftTemplateId: result.$1,
          reason: result.$2,
        ), 'Shift override saved successfully.');
  }

  Future<void> _removeOverride(DateTime date) async {
    final ok = await sdConfirm(context,
        title: 'Remove Override', message: 'Remove the manual shift override for ${sdFmtDate(date)}?', confirmText: 'Remove', danger: true);
    if (!ok) return;
    await _save(() => _service.saveShiftOverride(
          staffId: _staffId,
          date: sdKey(date),
          overrideType: 'delete',
          reason: 'Removing manual override',
        ), 'Override removed.');
  }

  Future<void> _save(Future<Map<String, dynamic>> Function() call, String ok) async {
    setState(() => _busy = true);
    try {
      final res = await call();
      if (!mounted) return;
      setState(() => _busy = false);
      sdShowSuccess(context, sdStr(res['message'], ok));
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      sdShowError(context, e);
    }
  }

  void _openDay(DateTime date) {
    final key = sdKey(date);
    final d = _day(key);
    final notOnboarded = _joinKey.isNotEmpty && key.compareTo(_joinKey) < 0;
    final off = _isOff(d, date);
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(DateFormat('EEEE, dd MMM yyyy').format(date),
                  style: AppTextStyles.headingMedium),
              const SizedBox(height: 10),
              if (notOnboarded)
                const SdKeyValue('Status', 'Not Onboarded')
              else if (d == null)
                const SdKeyValue('Shift', 'No schedule')
              else ...[
                SdKeyValue('Shift', off ? 'Weekly Off' : sdStr(d['shiftName'], '-')),
                if (!off && sdStr(d['timingLabel']).isNotEmpty) SdKeyValue('Timing', sdStr(d['timingLabel'])),
                if (sdStr(d['shiftType']).isNotEmpty) SdKeyValue('Type', sdStr(d['shiftType'])),
                SdKeyValue('Source', sdStr(d['source'], '-')),
                if (d['isHoliday'] == true || sdStr(d['holidayName']).isNotEmpty)
                  SdKeyValue('Holiday', sdStr(d['holidayName'], 'Holiday')),
                if (d['hasOverride'] == true) SdKeyValue('Override', sdStr(d['overrideReason'], 'Manual override')),
              ],
              const Divider(height: 20),
              if (!notOnboarded) ...[
                ListTile(
                  dense: true,
                  leading: Icon(Icons.edit_calendar_outlined, color: AppColors.primaryText),
                  title: const Text('Override Shift', style: TextStyle(fontWeight: FontWeight.w600)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _override(date);
                  },
                ),
                if (d?['hasOverride'] == true)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.delete_outline_rounded, color: AppColors.error),
                    title: const Text('Remove Override',
                        style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.error)),
                    onTap: () {
                      Navigator.pop(ctx);
                      _removeOverride(date);
                    },
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          SdMonthBar(
            month: _month,
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
            if (_today != null) _buildTodayCard(),
            _buildCalendar(),
            _buildLegend(),
          ],
        ],
      ),
    );
  }

  Widget _buildTodayCard() {
    final t = _today!;
    final off = _isOff(t, DateTime.now());
    return SdCard(
      child: Row(children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(Icons.today_rounded, size: 22, color: AppColors.primaryText),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text("Today's Shift", style: AppTextStyles.sectionLabel),
            const SizedBox(height: 4),
            Text(off ? 'Weekly Off' : sdStr(t['shiftName'], '-'),
                style: AppTextStyles.headingSmall),
            if (!off && sdStr(t['timingLabel']).isNotEmpty)
              Text(sdStr(t['timingLabel']), style: AppTextStyles.bodySmall),
          ]),
        ),
      ]),
    );
  }

  Widget _buildCalendar() {
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final lead = DateTime(_month.year, _month.month, 1).weekday % 7; // Sunday first
    final cells = <Widget>[
      for (final n in const ['S', 'M', 'T', 'W', 'T', 'F', 'S'])
        Center(child: Text(n, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: kSdMuted))),
      for (var i = 0; i < lead; i++) const SizedBox.shrink(),
    ];
    final now = DateTime.now();
    for (var day = 1; day <= daysInMonth; day++) {
      final date = DateTime(_month.year, _month.month, day);
      final key = sdKey(date);
      final d = _day(key);
      final notOnboarded = _joinKey.isNotEmpty && key.compareTo(_joinKey) < 0;
      final off = _isOff(d, date);
      final holiday = !off && d?['isHoliday'] == true;
      final unassigned = _unassigned(d);
      final isToday = date.year == now.year && date.month == now.month && date.day == now.day;
      Color bg = AppColors.surface;
      Color fg = kSdInk;
      String sub = '';
      if (notOnboarded) {
        bg = kSdSoft;
        fg = kSdSubtle;
        sub = 'N/A';
      } else if (off) {
        bg = AppColors.infoBg;
        fg = AppColors.info;
        sub = 'Off';
      } else if (holiday) {
        bg = const Color(0xFFECFEFF);
        fg = const Color(0xFF0891B2);
        sub = 'Hol';
      } else if (unassigned) {
        bg = kSdSoft;
        fg = kSdMuted;
        sub = '-';
      } else if (d != null) {
        sub = sdStr(d['shiftName']);
      }
      cells.add(InkWell(
        onTap: () => _openDay(date),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: isToday ? AppColors.primary : kSdHairline, width: isToday ? 1.6 : 1),
          ),
          padding: const EdgeInsets.all(3),
          child: Stack(children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('$day', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: fg)),
                if (sub.isNotEmpty)
                  Text(sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 9, fontWeight: FontWeight.w500, color: fg)),
              ],
            ),
            if (d?['hasOverride'] == true)
              const Positioned(
                top: 0,
                right: 0,
                child: CircleAvatar(radius: 3, backgroundColor: AppColors.brand),
              ),
          ]),
        ),
      ));
    }
    return SdCard(
      padding: const EdgeInsets.all(12),
      child: GridView.count(
        crossAxisCount: 7,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
        childAspectRatio: 0.8,
        children: cells,
      ),
    );
  }

  Widget _buildLegend() {
    Widget item(Color c, String l) => Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(999))),
          const SizedBox(width: 6),
          Text(l, style: AppTextStyles.caption.copyWith(color: kSdMuted)),
        ]);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Wrap(spacing: 16, runSpacing: 8, children: [
      item(AppColors.info.withValues(alpha: 0.35), 'Weekly Off'),
      item(const Color(0xFFA5F3FC), 'Holiday'),
      item(kSdLine, 'Not Assigned / Not Onboarded'),
      item(AppColors.brand, 'Manual Override'),
      ]),
    );
  }
}

class _OverrideDialog extends StatefulWidget {
  const _OverrideDialog({required this.templates, required this.date});
  final List<Map<String, dynamic>> templates;
  final DateTime date;

  @override
  State<_OverrideDialog> createState() => _OverrideDialogState();
}

class _OverrideDialogState extends State<_OverrideDialog> {
  String? _template;
  final _reason = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  String _label(Map<String, dynamic> t) {
    final timing = sdStr(t['startTime']).isNotEmpty ? ' (${t['startTime']} - ${t['endTime']})' : '';
    return '${sdStr(t['name'], 'Shift')}$timing';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Override · ${sdFmtDate(widget.date)}', style: AppTextStyles.headingMedium),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        DropdownButtonFormField<String>(
          initialValue: _template,
          isExpanded: true,
          decoration: sdInput('Shift Template'),
          items: widget.templates
              .map((t) => DropdownMenuItem(
                  value: sdId(t), child: Text(_label(t), overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5))))
              .toList(),
          onChanged: (v) => setState(() => _template = v),
        ),
        const SizedBox(height: 10),
        TextField(controller: _reason, maxLines: 2, decoration: sdInput('Reason')),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_error!, style: const TextStyle(fontSize: 12, color: AppColors.error)),
          ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          style: sdPrimaryButton(),
          onPressed: () {
            if (_template == null) {
              setState(() => _error = 'Please select a shift template.');
              return;
            }
            if (_reason.text.trim().isEmpty) {
              setState(() => _error = 'Reason is required for this override.');
              return;
            }
            Navigator.pop(context, (_template!, _reason.text.trim()));
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
