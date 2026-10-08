// Shift Roster (web: features/admin/staff/settings/ShiftRoaster):
//   GET  /admin/settings/shift-roster/data            assignments + overrides
//   GET  /admin/settings/shift-roster/month-schedule  resolved month per staff
//   GET  /admin/settings/shift-roster/week-offs       weekly offs / holidays per staff
//   GET  /admin/settings/shift-roster/preview         read-only template preview
//   POST /admin/settings/shift-roster/permanent       { employeeIds, shiftTemplateId, effectiveFrom }
//   POST /admin/settings/shift-roster/temporary       { employeeIds, shiftTemplateId, weekOffTemplateId?, effectiveFrom, effectiveTo, reason? }
//   POST /admin/settings/shift-roster/override        { staffId, date, overrideType, shiftTemplateId?, reason }

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../config/app_colors.dart';
import '../../../services/admin_settings_service.dart';
import 'settings_common.dart';

class ShiftRosterScreen extends StatefulWidget {
  const ShiftRosterScreen({super.key});

  @override
  State<ShiftRosterScreen> createState() => _ShiftRosterScreenState();
}

class _ShiftRosterScreenState extends State<ShiftRosterScreen> {
  final _svc = AdminSettingsService.instance;
  List<Map<String, dynamic>>? _staff;
  List<Map<String, dynamic>> _shifts = [];
  List<Map<String, dynamic>> _weekOffs = [];
  List<Map<String, dynamic>> _assignments = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Future.wait([
        _svc.listStaff(),
        _svc.listTemplates(AttendanceTemplateKind.shift.basePath),
        _svc.listTemplates(AttendanceTemplateKind.weeklyOff.basePath),
        _svc.rosterData().then((d) => d.assignments),
      ]);
      if (!mounted) return;
      setState(() {
        _staff = r[0].where((s) => (s['status'] ?? 'Active') != 'Deactive').toList()
          ..sort((a, b) => AdminSettingsService.staffName(a).compareTo(AdminSettingsService.staffName(b)));
        _shifts = r[1].where((t) => t['isActive'] != false).toList();
        _weekOffs = r[2].where((t) => t['isActive'] != false).toList();
        _assignments = r[3];
        _error = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _error = settingsErrorText(e));
        if (_staff != null) showSettingsError(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: settingsAppBar('Shift Roster', bottom: settingsTabBar(['Calendar', 'Permanent', 'Temporary'])),
        body: _error != null && _staff == null
            ? SettingsErrorView(message: _error!, onRetry: _load)
            : _staff == null
                ? const SettingsLoading()
                : TabBarView(children: [
                    _CalendarTab(staff: _staff!, shifts: _shifts),
                    _AssignTab(
                      temporary: false,
                      staff: _staff!,
                      shifts: _shifts,
                      weekOffs: _weekOffs,
                      assignments: _assignments,
                      onChanged: _load,
                    ),
                    _AssignTab(
                      temporary: true,
                      staff: _staff!,
                      shifts: _shifts,
                      weekOffs: _weekOffs,
                      assignments: _assignments,
                      onChanged: _load,
                    ),
                  ]),
      ),
    );
  }
}

String _ymd(dynamic v) {
  final s = v?.toString() ?? '';
  return s.length >= 10 ? s.substring(0, 10) : s;
}

String _dayLabel(Map<String, dynamic> d) {
  if (d['isHoliday'] == true) return 'Holiday${(d['holidayName'] ?? '').toString().isEmpty ? '' : ': ${d['holidayName']}'}';
  if (d['isOff'] == true) return 'Week off';
  final name = (d['shiftName'] ?? '').toString();
  if (name.isEmpty) return 'No shift';
  final timing = (d['timingLabel'] ?? '').toString();
  return timing.isEmpty ? name : '$name · $timing';
}

Color _dayColor(Map<String, dynamic> d) {
  if (d['isHoliday'] == true) return AppColors.info;
  if (d['isOff'] == true) return AppColors.textCaption;
  if ((d['shiftName'] ?? '').toString().isEmpty) return AppColors.error;
  return d['source'] == 'temporary' ? AppColors.indigo : AppColors.success;
}

// ------------------------------------------------------------------ calendar

class _CalendarTab extends StatefulWidget {
  const _CalendarTab({required this.staff, required this.shifts});
  final List<Map<String, dynamic>> staff;
  final List<Map<String, dynamic>> shifts;

  @override
  State<_CalendarTab> createState() => _CalendarTabState();
}

class _CalendarTabState extends State<_CalendarTab> with AutomaticKeepAliveClientMixin {
  final _svc = AdminSettingsService.instance;
  String? _staffId;
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  List<Map<String, dynamic>>? _days;
  List<String> _weeklyOffDays = [];
  bool _loading = false;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    if (widget.staff.isNotEmpty) {
      _staffId = AdminSettingsService.idOf(widget.staff.first);
      _load();
    }
  }

  Future<void> _load() async {
    final id = _staffId;
    if (id == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await Future.wait([
        _svc.monthSchedule(staffIds: [id], year: _month.year, month: _month.month),
        _svc.monthlyWeekOffs(year: _month.year, month: _month.month),
      ]);
      final sched = r[0] as List<Map<String, dynamic>>;
      final wo = r[1] as Map<String, dynamic>;
      if (!mounted || id != _staffId) return;
      setState(() {
        _days = sched.isEmpty ? [] : AdminSettingsService.asList(sched.first['days']);
        _weeklyOffDays = ((AdminSettingsService.asMap(wo['weeklyOffDays'])[id] as List?) ?? const []).map((e) => e.toString()).toList();
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = settingsErrorText(e);
        });
      }
    }
  }

  void _shiftMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta));
    _load();
  }

  Future<void> _openDay(Map<String, dynamic> day) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _OverrideSheet(staffId: _staffId!, day: day, shifts: widget.shifts),
    );
    if (saved == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (widget.staff.isEmpty) return const SettingsEmptyView(message: 'No active staff.');
    final first = DateTime(_month.year, _month.month, 1);
    final lead = first.weekday - 1; // Monday-first grid
    final byDate = {for (final d in _days ?? const <Map<String, dynamic>>[]) _ymd(d['date']): d};
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          SettingsDropdown<String>(
            label: 'Staff',
            value: _staffId,
            items: [
              for (final s in widget.staff)
                DropdownMenuItem(
                  value: AdminSettingsService.idOf(s),
                  child: Text('${AdminSettingsService.staffName(s)}${(s['employeeId'] ?? '').toString().isEmpty ? '' : ' (${s['employeeId']})'}',
                      overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (v) {
              setState(() {
                _staffId = v;
                _days = null;
              });
              _load();
            },
          ),
          const SizedBox(height: 12),
          Row(children: [
            IconButton(tooltip: 'Previous month', onPressed: () => _shiftMonth(-1), icon: const Icon(Icons.chevron_left_rounded)),
            Expanded(
              child: Text(DateFormat('MMMM yyyy').format(_month),
                  textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: AppColors.textPrimary)),
            ),
            IconButton(tooltip: 'Next month', onPressed: () => _shiftMonth(1), icon: const Icon(Icons.chevron_right_rounded)),
          ]),
          if (_weeklyOffDays.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('Weekly offs this month: ${_weeklyOffDays.join(', ')}',
                  style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
            ),
          if (_loading && _days == null)
            const Padding(padding: EdgeInsets.all(40), child: SettingsLoading())
          else if (_error != null)
            SizedBox(height: 240, child: SettingsErrorView(message: _error!, onRetry: _load))
          else ...[
            Row(children: [
              for (final w in const ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
                Expanded(
                  child: Center(child: Text(w, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                ),
            ]),
            const SizedBox(height: 6),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7, mainAxisSpacing: 4, crossAxisSpacing: 4, childAspectRatio: 0.72),
              itemCount: lead + daysInMonth,
              itemBuilder: (_, i) {
                if (i < lead) return const SizedBox.shrink();
                final dayNum = i - lead + 1;
                final key = fmtYmd(DateTime(_month.year, _month.month, dayNum));
                final d = byDate[key];
                final color = d == null ? AppColors.divider : _dayColor(d);
                final short = d == null
                    ? ''
                    : d['isHoliday'] == true
                        ? 'HOL'
                        : d['isOff'] == true
                            ? 'OFF'
                            : (d['shiftName'] ?? '-').toString();
                return InkWell(
                  onTap: d == null ? null : () => _openDay(d),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: d?['hasOverride'] == true ? AppColors.brand : color.withValues(alpha: 0.4)),
                    ),
                    child: Column(children: [
                      Text('$dayNum', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                      const SizedBox(height: 2),
                      Expanded(
                        child: Text(short,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: color)),
                      ),
                    ]),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            const Wrap(spacing: 8, runSpacing: 8, children: [
              SettingsChip('Permanent', color: AppColors.success, background: AppColors.successBg),
              SettingsChip('Temporary', color: AppColors.indigo, background: AppColors.indigoBg),
              SettingsChip('Week off'),
              SettingsChip('Holiday', color: AppColors.info, background: AppColors.infoBg),
              SettingsChip('Override (gold border)', color: AppColors.brandDark, background: AppColors.brandLight),
            ]),
            const SizedBox(height: 12),
            const Text('Tap a day to override the shift for that date.', style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
          ],
        ],
      ),
    );
  }
}

class _OverrideSheet extends StatefulWidget {
  const _OverrideSheet({required this.staffId, required this.day, required this.shifts});
  final String staffId;
  final Map<String, dynamic> day;
  final List<Map<String, dynamic>> shifts;

  @override
  State<_OverrideSheet> createState() => _OverrideSheetState();
}

class _OverrideSheetState extends State<_OverrideSheet> {
  String _type = 'work_shift';
  String? _shift;
  final _reason = TextEditingController();
  bool _saving = false;

  List<Map<String, dynamic>> get _options => widget.shifts.where((s) => s['shiftType'] != 'rotational').toList();

  @override
  void initState() {
    super.initState();
    final current = widget.day['shiftTemplateId']?.toString();
    if (current != null && _options.any((s) => AdminSettingsService.idOf(s) == current)) _shift = current;
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit(String type) async {
    if (type == 'work_shift' && _shift == null) {
      showSettingsError(context, 'Select a shift.');
      return;
    }
    setState(() => _saving = true);
    try {
      final msg = await AdminSettingsService.instance.saveDailyOverride(
        staffId: widget.staffId,
        date: _ymd(widget.day['date']),
        overrideType: type,
        shiftTemplateId: type == 'work_shift' ? _shift : null,
        reason: _reason.text,
      );
      if (!mounted) return;
      showSettingsSuccess(context, msg ?? (type == 'delete' ? 'Override removed' : 'Shift override saved'));
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showSettingsError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.day;
    final date = DateTime.tryParse(_ymd(d['date']));
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(date == null ? 'Day' : DateFormat('EEEE, dd MMM yyyy').format(date),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          Text('Current: ${_dayLabel(d)}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          if (d['hasOverride'] == true && (d['overrideReason'] ?? '').toString().isNotEmpty)
            Text('Override reason: ${d['overrideReason']}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
          const SizedBox(height: 16),
          SettingsDropdown<String>(
            label: 'Change to',
            value: _type,
            items: const [
              DropdownMenuItem(value: 'work_shift', child: Text('Work shift')),
              DropdownMenuItem(value: 'weekly_off', child: Text('Weekly off')),
              DropdownMenuItem(value: 'holiday', child: Text('Holiday')),
              DropdownMenuItem(value: 'leave', child: Text('Leave')),
            ],
            onChanged: (v) => setState(() => _type = v ?? 'work_shift'),
          ),
          if (_type == 'work_shift') ...[
            const SizedBox(height: 12),
            SettingsDropdown<String>(
              label: 'Shift',
              value: _shift,
              items: [
                for (final s in _options)
                  DropdownMenuItem(value: AdminSettingsService.idOf(s), child: Text((s['name'] ?? '-').toString())),
              ],
              onChanged: (v) => setState(() => _shift = v),
            ),
          ],
          const SizedBox(height: 12),
          TextField(controller: _reason, decoration: settingsInput('Reason')),
          SettingsSaveBar(saving: _saving, onSave: () => _submit(_type), label: 'Save override'),
          if (d['hasOverride'] == true)
            TextButton(
              onPressed: _saving ? null : () => _submit('delete'),
              child: const Text('Remove existing override', style: TextStyle(color: AppColors.error)),
            ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }
}

// ------------------------------------------------------- permanent/temporary

class _AssignTab extends StatefulWidget {
  const _AssignTab({
    required this.temporary,
    required this.staff,
    required this.shifts,
    required this.weekOffs,
    required this.assignments,
    required this.onChanged,
  });
  final bool temporary;
  final List<Map<String, dynamic>> staff;
  final List<Map<String, dynamic>> shifts;
  final List<Map<String, dynamic>> weekOffs;
  final List<Map<String, dynamic>> assignments;
  final Future<void> Function() onChanged;

  @override
  State<_AssignTab> createState() => _AssignTabState();
}

class _AssignTabState extends State<_AssignTab> with AutomaticKeepAliveClientMixin {
  final _svc = AdminSettingsService.instance;
  final Set<String> _selected = {};
  String? _shift;
  String? _weekOff;
  DateTime _from = DateTime.now();
  DateTime? _to;
  final _reason = TextEditingController();
  bool _saving = false;
  bool _previewing = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Map<String, dynamic>? get _shiftTpl {
    for (final s in widget.shifts) {
      if (AdminSettingsService.idOf(s) == _shift) return s;
    }
    return null;
  }

  String _staffName(dynamic idOrMap) {
    if (idOrMap is Map) {
      final m = Map<String, dynamic>.from(idOrMap);
      if ((m['name'] ?? m['firstName']) != null) return AdminSettingsService.staffName(m);
    }
    final id = AdminSettingsService.idOf(idOrMap);
    for (final s in widget.staff) {
      if (AdminSettingsService.idOf(s) == id) return AdminSettingsService.staffName(s);
    }
    return 'Staff';
  }

  Future<void> _pickStaff() async {
    final result = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _StaffPickerSheet(staff: widget.staff, initial: _selected),
    );
    if (result != null) {
      setState(() => _selected
        ..clear()
        ..addAll(result));
    }
  }

  String? _validate() {
    if (_selected.isEmpty) return 'Select at least one staff member.';
    if (_shift == null) return 'Select a shift template.';
    if (widget.temporary) {
      if (_to == null) return 'Select the end date.';
      if (_to!.isBefore(DateTime(_from.year, _from.month, _from.day))) return 'End date cannot be before start date';
    }
    return null;
  }

  Future<void> _preview() async {
    final err = _validate();
    if (err != null) {
      showSettingsError(context, err);
      return;
    }
    setState(() => _previewing = true);
    try {
      final data = await _svc.shiftPreview(
        staffIds: _selected.toList(),
        templateId: _shift!,
        effectiveFrom: fmtYmd(_from),
        year: _from.year,
        month: _from.month,
      );
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => _PreviewSheet(data: data, from: _from),
      );
    } catch (e) {
      if (mounted) showSettingsError(context, e);
    } finally {
      if (mounted) setState(() => _previewing = false);
    }
  }

  Future<void> _assign() async {
    final err = _validate();
    if (err != null) {
      showSettingsError(context, err);
      return;
    }
    setState(() => _saving = true);
    try {
      final rotational = _shiftTpl?['shiftType'] == 'rotational';
      final msg = widget.temporary
          ? await _svc.assignTemporaryShift(
              staffIds: _selected.toList(),
              shiftTemplateId: _shift!,
              weekOffTemplateId: rotational ? null : _weekOff,
              effectiveFrom: fmtYmd(_from),
              effectiveTo: fmtYmd(_to!),
              reason: _reason.text,
            )
          : await _svc.assignPermanentShift(staffIds: _selected.toList(), shiftTemplateId: _shift!, effectiveFrom: fmtYmd(_from));
      if (!mounted) return;
      showSettingsSuccess(context, msg ?? 'Shift assigned');
      setState(() {
        _selected.clear();
        _reason.clear();
      });
      await widget.onChanged();
    } catch (e) {
      if (mounted) showSettingsError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    final current = widget.assignments.where((a) {
      if (a['assignmentType'] != (widget.temporary ? 'temporary' : 'permanent')) return false;
      final to = DateTime.tryParse((a['effectiveTo'] ?? '').toString());
      return to == null || !to.toLocal().isBefore(todayDate);
    }).toList();
    final rotational = _shiftTpl?['shiftType'] == 'rotational';
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: widget.onChanged,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          SettingsSectionTitle(widget.temporary ? 'New temporary assignment' : 'New permanent assignment'),
          SettingsFormCard(padding: const EdgeInsets.all(16), children: [
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48), alignment: Alignment.centerLeft),
              onPressed: _pickStaff,
              icon: const Icon(Icons.people_alt_outlined, size: 20),
              label: Text(_selected.isEmpty ? 'Select staff *' : '${_selected.length} staff selected'),
            ),
            const SizedBox(height: 12),
            SettingsDropdown<String>(
              label: 'Shift template *',
              value: _shift,
              items: [
                for (final s in widget.shifts)
                  DropdownMenuItem(
                    value: AdminSettingsService.idOf(s),
                    child: Text('${s['name']} (${s['shiftType'] ?? 'standard'})', overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (v) => setState(() => _shift = v),
            ),
            if (widget.temporary && !rotational) ...[
              const SizedBox(height: 12),
              SettingsDropdown<String>(
                label: 'Week off template (optional)',
                value: _weekOff ?? '',
                items: [
                  const DropdownMenuItem(value: '', child: Text('Keep staff\'s own')),
                  for (final w in widget.weekOffs)
                    DropdownMenuItem(value: AdminSettingsService.idOf(w), child: Text((w['name'] ?? '-').toString())),
                ],
                onChanged: (v) => setState(() => _weekOff = (v == null || v.isEmpty) ? null : v),
              ),
            ],
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  onPressed: () async {
                    final d = await pickSettingsDate(context, initial: _from, first: widget.temporary ? todayDate : null);
                    if (d != null) setState(() => _from = d);
                  },
                  icon: const Icon(Icons.event_outlined, size: 18),
                  label: Text('From ${fmtDisplayDate(_from)}'),
                ),
              ),
              if (widget.temporary) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    onPressed: () async {
                      final d = await pickSettingsDate(context, initial: _to ?? _from, first: _from);
                      if (d != null) setState(() => _to = d);
                    },
                    icon: const Icon(Icons.event_outlined, size: 18),
                    label: Text(_to == null ? 'To *' : 'To ${fmtDisplayDate(_to)}'),
                  ),
                ),
              ],
            ]),
            if (widget.temporary) ...[
              const SizedBox(height: 12),
              TextField(controller: _reason, decoration: settingsInput('Reason (optional)')),
            ],
          ]),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                onPressed: _previewing || _saving ? null : _preview,
                child: _previewing
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Preview'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                onPressed: _saving ? null : _assign,
                child: _saving
                    ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onPrimary))
                    : const Text('Assign'),
              ),
            ),
          ]),
          SettingsSectionTitle(widget.temporary ? 'Active temporary assignments (${current.length})' : 'Current permanent assignments (${current.length})'),
          if (current.isEmpty)
            const Text('None.', style: TextStyle(color: AppColors.textSecondary, fontSize: 13))
          else
            for (final a in current)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: SettingsListCard(
                  leading: settingsIconTile(Icons.schedule_outlined, size: 40),
                  title: _staffName(a['staffId']),
                  subtitle: '${AdminSettingsService.asMap(a['shiftTemplateId'])['name'] ?? 'Shift'} · '
                      '${fmtDisplayDate(a['effectiveFrom'])} → ${a['effectiveTo'] == null ? 'ongoing' : fmtDisplayDate(a['effectiveTo'])}'
                      '${(a['reason'] ?? '').toString().isEmpty ? '' : ' · ${a['reason']}'}',
                ),
              ),
        ],
      ),
    );
  }
}

class _StaffPickerSheet extends StatefulWidget {
  const _StaffPickerSheet({required this.staff, required this.initial});
  final List<Map<String, dynamic>> staff;
  final Set<String> initial;

  @override
  State<_StaffPickerSheet> createState() => _StaffPickerSheetState();
}

class _StaffPickerSheetState extends State<_StaffPickerSheet> {
  late final Set<String> _sel = {...widget.initial};
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final q = _q.trim().toLowerCase();
    final list = widget.staff.where((s) {
      if (q.isEmpty) return true;
      return AdminSettingsService.staffName(s).toLowerCase().contains(q) ||
          (s['employeeId'] ?? '').toString().toLowerCase().contains(q) ||
          (s['department'] ?? '').toString().toLowerCase().contains(q);
    }).toList();
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.8,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 12, 0),
          child: Row(children: [
            Text('Select staff (${_sel.length})', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            const Spacer(),
            TextButton(
              onPressed: () => setState(() {
                final ids = list.map(AdminSettingsService.idOf).toSet();
                _sel.containsAll(ids) ? _sel.removeAll(ids) : _sel.addAll(ids);
              }),
              child: const Text('Select all'),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
          child: TextField(
            decoration: settingsInput('Search', suffixIcon: const Icon(Icons.search_rounded, size: 20)),
            onChanged: (v) => setState(() => _q = v),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: list.length,
            itemBuilder: (_, i) {
              final s = list[i];
              final id = AdminSettingsService.idOf(s);
              return CheckboxListTile(
                value: _sel.contains(id),
                activeColor: AppColors.primary,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(AdminSettingsService.staffName(s), style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                subtitle: Text([s['employeeId'], s['department']].where((e) => e != null && e.toString().isNotEmpty).join(' · '), style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                onChanged: (v) => setState(() => v == true ? _sel.add(id) : _sel.remove(id)),
              );
            },
          ),
        ),
        SettingsSaveBar(saving: false, onSave: () => Navigator.pop(context, _sel), label: 'Done'),
      ]),
    );
  }
}

class _PreviewSheet extends StatelessWidget {
  const _PreviewSheet({required this.data, required this.from});
  final Map<String, dynamic> data;
  final DateTime from;

  @override
  Widget build(BuildContext context) {
    final t = AdminSettingsService.asMap(data['template']);
    final staff = AdminSettingsService.asList(data['staff']);
    final fromKey = fmtYmd(from);
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.8,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
          child: Text('Preview · ${t['name'] ?? ''}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            '${DateFormat('MMMM yyyy').format(DateTime(toInt(data['year']) ?? from.year, toInt(data['month']) ?? from.month))} · read-only, nothing is saved',
            style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(8),
            children: [
              for (final s in staff)
                ExpansionTile(
                  title: Text((s['name'] ?? '-').toString(), style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                  subtitle: Text((s['employeeId'] ?? '').toString(), style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                  children: [
                    for (final d in AdminSettingsService.asList(s['days']).where((d) => (d['date'] ?? '').toString().compareTo(fromKey) >= 0))
                      ListTile(
                        dense: true,
                        leading: Text(
                          DateFormat('dd EEE').format(DateTime.tryParse(_ymd(d['date'])) ?? from),
                          style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                        ),
                        title: Text(_dayLabel(d), style: TextStyle(color: _dayColor(d), fontSize: 13, fontWeight: FontWeight.w500)),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ]),
    );
  }
}
