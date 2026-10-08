// Add / edit form for every attendance template kind. Payloads mirror the web
// admin forms (features/admin/staff/settings/Attendance/*/pages/add*.tsx) and
// the backend models (models/admin/Attendance/*).

import 'package:flutter/material.dart';

import '../../../config/app_colors.dart';
import '../../../services/admin_settings_service.dart';
import 'settings_common.dart';

const kWeekDays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const _kOffWeeks = ['1st', '2nd', '3rd', '4th', 'Last'];

const _kRotationTypes = <String, String>{
  'daily': 'Daily Rotation',
  'weekly': 'Weekly Rotation',
  'monthly': 'Monthly Rotation',
  'calendar_date': 'Calendar Date Rotation',
  'joining_date': 'Joining Date Rotation',
  'custom': 'Custom Rotation',
  'week_day': 'Week Day Rotation',
};

class _HolidayRow {
  _HolidayRow({String name = '', this.date, this.type = 'national'}) : name = TextEditingController(text: name);
  final TextEditingController name;
  DateTime? date;
  String type;
}

class _LeaveRow {
  _LeaveRow({String name = '', String days = '', this.type = 'paid', this.carryForward = false, String maxCarry = ''})
      : name = TextEditingController(text: name),
        days = TextEditingController(text: days),
        maxCarry = TextEditingController(text: maxCarry);
  final TextEditingController name;
  final TextEditingController days;
  final TextEditingController maxCarry;
  String type;
  bool carryForward;
}

class _RangeRow {
  _RangeRow({this.from = 1, this.to = 1, this.templateId = ''});
  int from;
  int to;
  String templateId;
}

class AttendanceTemplateFormScreen extends StatefulWidget {
  const AttendanceTemplateFormScreen({super.key, required this.kind, this.templateId});
  final AttendanceTemplateKind kind;
  final String? templateId;

  @override
  State<AttendanceTemplateFormScreen> createState() => _AttendanceTemplateFormScreenState();
}

class _AttendanceTemplateFormScreenState extends State<AttendanceTemplateFormScreen> {
  final _svc = AdminSettingsService.instance;
  bool get _isEdit => widget.templateId != null;
  String get _seg => widget.kind.segment;

  bool _loading = true;
  String? _error;
  bool _saving = false;

  final _name = TextEditingController();
  final _desc = TextEditingController();
  bool _isActive = true;

  // attendance
  final Map<String, bool> _flags = {
    'requireGeofence': false,
    'requireSelfie': false,
    'allowAttendanceOnHolidays': false,
    'doublePayOnHolidays': false,
    'allowAttendanceOnWeeklyOff': false,
    'doublePayOnWeeklyOff': false,
    'sandwichLeave': false,
  };

  // holiday / leave
  final List<_HolidayRow> _holidays = [];
  final List<_LeaveRow> _leaves = [];

  // break
  final _duration = TextEditingController();
  String _fineRule = 'auto';
  final _customFine = TextEditingController();

  // overtime
  final _minOt = TextEditingController();
  final _maxOtHours = TextEditingController(text: '2');

  // permission
  final _permHours = TextEditingController(text: '0');
  final _permMinutes = TextEditingController(text: '0');

  // weekly off
  String _pattern = 'standard';
  final Set<String> _days = {'Saturday', 'Sunday'};
  final Map<String, Set<String>> _customOffWeeks = {};
  int _customDaysCount = 1;
  String _alternateWeeks = 'even';

  // shift
  String _shiftType = 'standard';
  String? _start;
  String? _end;
  final _grace = TextEditingController(text: '0');
  String _graceUnit = 'minutes';
  final _workHours = TextEditingController(text: '8');
  bool _halfDay = false;
  String? _firstHalfEnd;
  String? _secondHalfStart;
  final _firstHalfLogoutGrace = TextEditingController(text: '0');
  final _secondHalfLoginGrace = TextEditingController(text: '0');
  String _rotationType = 'daily';
  int _cycleLength = 3;
  String _weekStarts = 'Monday';
  List<String> _patternSlots = ['', '', ''];
  List<String> _weekDaySlots = List.filled(7, '');
  final List<_RangeRow> _ranges = [];
  String? _weeklyOffTemplateId;
  List<Map<String, dynamic>> _shiftOptions = [];
  List<Map<String, dynamic>> _weekOffOptions = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [
      _name, _desc, _duration, _customFine, _minOt, _maxOtHours, _permHours, _permMinutes,
      _grace, _workHours, _firstHalfLogoutGrace, _secondHalfLoginGrace,
    ]) {
      c.dispose();
    }
    for (final h in _holidays) {
      h.name.dispose();
    }
    for (final l in _leaves) {
      l.name.dispose();
      l.days.dispose();
      l.maxCarry.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_seg == 'shifts') {
        final results = await Future.wait([
          _svc.listTemplates(AttendanceTemplateKind.shift.basePath),
          _svc.listTemplates(AttendanceTemplateKind.weeklyOff.basePath),
        ]);
        _shiftOptions = results[0]
            .where((t) => t['shiftType'] != 'rotational' && AdminSettingsService.idOf(t) != widget.templateId)
            .toList();
        _weekOffOptions = results[1];
      }
      if (_isEdit) {
        final t = await _svc.getTemplate(widget.kind.basePath, widget.templateId!);
        _apply(t);
      }
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = settingsErrorText(e);
        });
      }
    }
  }

  String _dateOnly(dynamic v) {
    final s = v?.toString() ?? '';
    return s.length >= 10 ? s.substring(0, 10) : s;
  }

  void _apply(Map<String, dynamic> t) {
    _name.text = (t['name'] ?? '').toString();
    _desc.text = (t['description'] ?? '').toString();
    _isActive = t['isActive'] != false;
    switch (_seg) {
      case 'attendance-templates':
        for (final k in _flags.keys.toList()) {
          _flags[k] = t[k] == true;
        }
        break;
      case 'holiday-templates':
        for (final h in AdminSettingsService.asList(t['holidays'])) {
          _holidays.add(_HolidayRow(
            name: (h['name'] ?? '').toString(),
            date: DateTime.tryParse(_dateOnly(h['date'])),
            type: (h['type'] ?? 'national').toString(),
          ));
        }
        break;
      case 'leave-templates':
        for (final l in AdminSettingsService.asList(t['leaves'])) {
          _leaves.add(_LeaveRow(
            name: (l['name'] ?? '').toString(),
            days: (l['days'] ?? '').toString(),
            type: (l['type'] ?? 'paid').toString(),
            carryForward: l['carryForward'] == true,
            maxCarry: l['maxCarryForwardDays']?.toString() ?? '',
          ));
        }
        break;
      case 'break-templates':
        _duration.text = (t['duration'] ?? '').toString();
        _fineRule = (t['fineRule'] ?? 'auto').toString();
        _customFine.text = (t['customFineAmount'] ?? '').toString();
        break;
      case 'overtime-templates':
        _minOt.text = (t['minOvertime'] ?? '').toString();
        _maxOtHours.text = (t['maxOvertimeHours'] ?? '').toString();
        break;
      case 'permission-templates':
        _permHours.text = (t['hours'] ?? 0).toString();
        _permMinutes.text = (t['minutes'] ?? 0).toString();
        break;
      case 'weekly-off-templates':
        _pattern = (t['patternType'] ?? 'standard').toString();
        _days
          ..clear()
          ..addAll(((t['selectedDays'] as List?) ?? const []).map((e) => e.toString()));
        final cow = AdminSettingsService.asMap(t['customOffWeeks']);
        _customOffWeeks.clear();
        cow.forEach((k, v) => _customOffWeeks[k] = ((v as List?) ?? const []).map((e) => e.toString()).toSet());
        _customDaysCount = toInt(t['customDaysCount']) ?? 1;
        _alternateWeeks = (t['alternateWeeks'] ?? 'even').toString();
        break;
      case 'shifts':
        _shiftType = (t['shiftType'] ?? 'standard').toString();
        _start = t['startTime']?.toString();
        _end = t['endTime']?.toString();
        _grace.text = (t['graceTime'] ?? 0).toString();
        _graceUnit = (t['graceTimeUnit'] ?? 'minutes').toString();
        _workHours.text = (t['workHours'] ?? 8).toString();
        final hd = AdminSettingsService.asMap(t['halfDaySettings']);
        _halfDay = hd['enabled'] == true;
        _firstHalfEnd = hd['firstHalfEndTime']?.toString();
        _secondHalfStart = hd['secondHalfStartTime']?.toString();
        _firstHalfLogoutGrace.text = (hd['firstHalfLogoutGrace'] ?? 0).toString();
        _secondHalfLoginGrace.text = (hd['secondHalfLoginGrace'] ?? 0).toString();
        _rotationType = (t['rotationType'] ?? 'daily').toString();
        _cycleLength = toInt(t['cycleLength']) ?? 3;
        _weekStarts = (t['weekStarts'] ?? 'Monday').toString();
        _weeklyOffTemplateId = t['weeklyOffTemplateId'] == null ? null : AdminSettingsService.idOf(t['weeklyOffTemplateId']);
        final pattern = AdminSettingsService.asList(t['shiftPattern'])
          ..sort((a, b) => (toInt(a['dayIndex']) ?? 0).compareTo(toInt(b['dayIndex']) ?? 0));
        final ids = pattern.map((p) => p['shiftTemplateId'] == null ? '' : AdminSettingsService.idOf(p['shiftTemplateId'])).toList();
        if (_rotationType == 'week_day') {
          _weekDaySlots = List.generate(7, (i) => i < ids.length ? ids[i] : '');
        } else if (_rotationType == 'calendar_date') {
          _ranges.clear();
          for (var i = 0; i < ids.length; i++) {
            if (_ranges.isNotEmpty && _ranges.last.templateId == ids[i] && _ranges.last.to == i) {
              _ranges.last.to = i + 1;
            } else {
              _ranges.add(_RangeRow(from: i + 1, to: i + 1, templateId: ids[i]));
            }
          }
        } else {
          _patternSlots = List.generate(_cycleLength.clamp(1, 31), (i) => i < ids.length ? ids[i] : '');
        }
        break;
    }
  }

  // ------------------------------------------------------------ payload

  String? _validate() {
    if (_name.text.trim().isEmpty) return 'Please enter a name.';
    switch (_seg) {
      case 'holiday-templates':
        for (final h in _holidays) {
          if (h.name.text.trim().isEmpty || h.date == null) return 'Every holiday needs a name and a date.';
        }
        break;
      case 'leave-templates':
        for (final l in _leaves) {
          final d = num.tryParse(l.days.text.trim());
          if (l.name.text.trim().isEmpty || d == null || d < 0.5) return 'Every leave needs a name and at least 0.5 days.';
        }
        break;
      case 'break-templates':
        if ((int.tryParse(_duration.text.trim()) ?? 0) <= 0) return 'Enter the break duration in minutes.';
        break;
      case 'overtime-templates':
        if (int.tryParse(_minOt.text.trim()) == null) return 'Enter the overtime buffer duration in minutes.';
        break;
      case 'weekly-off-templates':
        if ((_pattern == 'standard' || _pattern == 'custom') && _days.isEmpty) return 'Please select at least one day.';
        break;
      case 'shifts':
        if (_shiftType == 'standard' && (_start == null || _end == null)) return 'Select the start and end time.';
        if (_shiftType == 'open' && (num.tryParse(_workHours.text.trim()) ?? 0) <= 0) return 'Enter the work hours.';
        if (_shiftType == 'rotational') {
          final needsWeekOff = _rotationType != 'custom' && _rotationType != 'week_day';
          if (needsWeekOff && (_weeklyOffTemplateId == null || _weeklyOffTemplateId!.isEmpty)) {
            return 'Please select a Weekly Off Template for Rotational Shift.';
          }
          if (_shiftOptions.isEmpty) return 'Create a standard or open shift first - rotations are built from them.';
          if (_rotationType == 'daily' && _patternSlots.any((s) => s.isEmpty)) return 'Select a shift for every day of the cycle.';
        }
        break;
    }
    return null;
  }

  Map<String, dynamic> _payload() {
    final body = <String, dynamic>{
      'name': _name.text.trim(),
      'isActive': _isActive,
    };
    if (_seg != 'shifts') body['description'] = _desc.text.trim();
    switch (_seg) {
      case 'attendance-templates':
        body.addAll(_flags);
        break;
      case 'holiday-templates':
        body['holidays'] = [
          for (final h in _holidays) {'name': h.name.text.trim(), 'date': fmtYmd(h.date!), 'type': h.type},
        ];
        break;
      case 'leave-templates':
        body['leaves'] = [
          for (final l in _leaves)
            {
              'name': l.name.text.trim(),
              'days': num.parse(l.days.text.trim()),
              'type': l.type,
              'carryForward': l.carryForward,
              if (l.carryForward && num.tryParse(l.maxCarry.text.trim()) != null)
                'maxCarryForwardDays': num.parse(l.maxCarry.text.trim()),
            },
        ];
        break;
      case 'break-templates':
        body['duration'] = int.parse(_duration.text.trim());
        body['fineRule'] = _fineRule;
        body['customFineAmount'] = _fineRule == 'custom' ? (num.tryParse(_customFine.text.trim()) ?? 0) : 0;
        break;
      case 'overtime-templates':
        body['minOvertime'] = int.parse(_minOt.text.trim());
        final max = num.tryParse(_maxOtHours.text.trim());
        if (max != null) body['maxOvertimeHours'] = max;
        break;
      case 'permission-templates':
        body['hours'] = int.tryParse(_permHours.text.trim()) ?? 0;
        body['minutes'] = int.tryParse(_permMinutes.text.trim()) ?? 0;
        break;
      case 'weekly-off-templates':
        body['patternType'] = _pattern;
        body['selectedDays'] = kWeekDays.where(_days.contains).toList();
        if (_pattern == 'alternate') body['alternateWeeks'] = _alternateWeeks;
        if (_pattern == 'custom') {
          body['customOffWeeks'] = {
            for (final d in kWeekDays.where(_days.contains)) d: _kOffWeeks.where((w) => _customOffWeeks[d]?.contains(w) ?? false).toList(),
          };
        }
        if (_pattern == 'custom_weekday') body['customDaysCount'] = _customDaysCount;
        break;
      case 'shifts':
        body['shiftType'] = _shiftType;
        if (_shiftType == 'rotational') {
          body['rotationType'] = _rotationType;
          body['cycleLength'] = _cycleLength;
          if (_rotationType == 'weekly') body['weekStarts'] = _weekStarts;
          final fallback = _shiftOptions.isEmpty ? '' : AdminSettingsService.idOf(_shiftOptions.first);
          List<Map<String, dynamic>> pattern;
          if (_rotationType == 'week_day') {
            pattern = [for (var i = 0; i < 7; i++) {'dayIndex': i + 1, 'shiftTemplateId': _weekDaySlots[i]}];
          } else if (_rotationType == 'custom') {
            pattern = [for (var i = 0; i < _patternSlots.length; i++) {'dayIndex': i + 1, 'shiftTemplateId': _patternSlots[i]}];
          } else if (_rotationType == 'calendar_date') {
            final map = List.filled(31, fallback);
            for (final r in _ranges) {
              final a = r.from.clamp(1, 31), b = r.to.clamp(1, 31);
              for (var d = a < b ? a : b; d <= (a < b ? b : a); d++) {
                map[d - 1] = r.templateId.isEmpty ? fallback : r.templateId;
              }
            }
            pattern = [for (var d = 1; d <= 31; d++) {'dayIndex': d, 'shiftTemplateId': map[d - 1]}];
          } else {
            pattern = [
              for (var i = 0; i < _patternSlots.length; i++)
                {'dayIndex': i + 1, 'shiftTemplateId': _patternSlots[i].isEmpty ? fallback : _patternSlots[i]},
            ];
          }
          body['shiftPattern'] = pattern;
          if (_rotationType != 'custom' && _rotationType != 'week_day' && _weeklyOffTemplateId != null) {
            body['weeklyOffTemplateId'] = _weeklyOffTemplateId;
          }
        } else {
          if (_shiftType == 'open') body['workHours'] = num.parse(_workHours.text.trim());
          if (_shiftType == 'standard') {
            body['startTime'] = _start;
            body['endTime'] = _end;
            body['graceTime'] = int.tryParse(_grace.text.trim()) ?? 0;
            body['graceTimeUnit'] = _graceUnit;
          }
          body['halfDaySettings'] = {
            'enabled': _halfDay,
            if (_halfDay && _firstHalfEnd != null) 'firstHalfEndTime': _firstHalfEnd,
            if (_halfDay && _secondHalfStart != null) 'secondHalfStartTime': _secondHalfStart,
            if (_halfDay) 'firstHalfLogoutGrace': int.tryParse(_firstHalfLogoutGrace.text.trim()) ?? 0,
            if (_halfDay) 'secondHalfLoginGrace': int.tryParse(_secondHalfLoginGrace.text.trim()) ?? 0,
          };
        }
        break;
    }
    return body;
  }

  Future<void> _save() async {
    final err = _validate();
    if (err != null) {
      showSettingsError(context, err);
      return;
    }
    setState(() => _saving = true);
    try {
      final body = _payload();
      if (_isEdit) {
        await _svc.updateTemplate(widget.kind.basePath, widget.templateId!, body);
      } else {
        await _svc.createTemplate(widget.kind.basePath, body);
      }
      if (!mounted) return;
      showSettingsSuccess(context, '${widget.kind.singular} ${_isEdit ? 'updated' : 'created'}');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) showSettingsError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: settingsAppBar('${_isEdit ? 'Edit' : 'Add'} ${widget.kind.singular}'),
      body: _loading
          ? const SettingsLoading()
          : _error != null
              ? SettingsErrorView(message: _error!, onRetry: _load)
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                  children: [
                    const SettingsSectionTitle('Basic details'),
                    SettingsFormCard(children: [
                      TextField(controller: _name, decoration: settingsInput('Template name *')),
                      if (_seg != 'shifts') ...[
                        const SizedBox(height: 12),
                        TextField(controller: _desc, maxLines: 2, decoration: settingsInput('Description')),
                      ],
                      const SizedBox(height: 12),
                    ]),
                    ..._kindFields(),
                    const SizedBox(height: 16),
                    SettingsFormCard(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4), children: [
                      SettingsSwitchTile(
                        title: 'Active',
                        subtitle: 'Only active templates can be assigned to staff',
                        value: _isActive,
                        onChanged: (v) => setState(() => _isActive = v),
                      ),
                    ]),
                  ],
                ),
      bottomNavigationBar: _loading || _error != null ? null : SettingsSaveBar(saving: _saving, onSave: _save),
    );
  }

  List<Widget> _kindFields() {
    switch (_seg) {
      case 'attendance-templates':
        return _attendanceFields();
      case 'holiday-templates':
        return _holidayFields();
      case 'leave-templates':
        return _leaveFields();
      case 'break-templates':
        return _breakFields();
      case 'overtime-templates':
        return _overtimeFields();
      case 'permission-templates':
        return _permissionFields();
      case 'weekly-off-templates':
        return _weekOffFields();
      case 'shifts':
        return _shiftFields();
    }
    return const [];
  }

  Widget _num(TextEditingController c, String label, {String? suffix, bool decimal = false}) => TextField(
        controller: c,
        keyboardType: TextInputType.numberWithOptions(decimal: decimal),
        decoration: settingsInput(label, suffix: suffix),
      );

  List<Widget> _attendanceFields() {
    const labels = {
      'requireGeofence': ('Require geofence', 'Staff must be inside the branch geofence to punch'),
      'requireSelfie': ('Require selfie', 'Capture a selfie on punch in/out'),
      'allowAttendanceOnHolidays': ('Allow attendance on holidays', null),
      'doublePayOnHolidays': ('Double pay on holidays', null),
      'allowAttendanceOnWeeklyOff': ('Allow attendance on weekly off', null),
      'doublePayOnWeeklyOff': ('Double pay on weekly off', null),
      'sandwichLeave': ('Sandwich leave', 'Count holidays/week-offs between leaves as leave'),
    };
    return [
      const SettingsSectionTitle('Rules'),
      for (final e in labels.entries)
        SettingsSwitchTile(
          title: e.value.$1,
          subtitle: e.value.$2,
          value: _flags[e.key] ?? false,
          onChanged: (v) => setState(() => _flags[e.key] = v),
        ),
    ];
  }

  List<Widget> _holidayFields() => [
        SettingsSectionTitle('Holidays (${_holidays.length})',
            trailing: TextButton.icon(
              onPressed: () => setState(() => _holidays.add(_HolidayRow())),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add'),
            )),
        if (_holidays.isEmpty)
          const Text('No holidays added.', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        for (final h in _holidays)
          Card(
            margin: const EdgeInsets.only(bottom: 12),
            color: AppColors.surface,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Color(0xFFECEEF1))),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 16),
              child: Column(children: [
                Row(children: [
                  Expanded(child: TextField(controller: h.name, decoration: settingsInput('Holiday name *'))),
                  IconButton(
                    tooltip: 'Remove',
                    icon: const Icon(Icons.delete_outline_rounded, color: AppColors.error),
                    onPressed: () => setState(() {
                      _holidays.remove(h);
                      h.name.dispose();
                    }),
                  ),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final d = await pickSettingsDate(context, initial: h.date);
                        if (d != null) setState(() => h.date = d);
                      },
                      icon: const Icon(Icons.event_outlined, size: 18),
                      label: Text(h.date == null ? 'Pick date *' : fmtDisplayDate(h.date)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SettingsDropdown<String>(
                      label: 'Type',
                      value: h.type,
                      items: const [
                        DropdownMenuItem(value: 'national', child: Text('National')),
                        DropdownMenuItem(value: 'regional', child: Text('Regional')),
                        DropdownMenuItem(value: 'company', child: Text('Company')),
                      ],
                      onChanged: (v) => setState(() => h.type = v ?? 'national'),
                    ),
                  ),
                ]),
              ]),
            ),
          ),
      ];

  List<Widget> _leaveFields() => [
        SettingsSectionTitle('Leave types (${_leaves.length})',
            trailing: TextButton.icon(
              onPressed: () => setState(() => _leaves.add(_LeaveRow())),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add'),
            )),
        if (_leaves.isEmpty) const Text('No leave types added.', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        for (final l in _leaves)
          Card(
            margin: const EdgeInsets.only(bottom: 12),
            color: AppColors.surface,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Color(0xFFECEEF1))),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 16),
              child: Column(children: [
                Row(children: [
                  Expanded(child: TextField(controller: l.name, decoration: settingsInput('Leave name *'))),
                  IconButton(
                    tooltip: 'Remove',
                    icon: const Icon(Icons.delete_outline_rounded, color: AppColors.error),
                    onPressed: () => setState(() {
                      _leaves.remove(l);
                      l.name.dispose();
                      l.days.dispose();
                      l.maxCarry.dispose();
                    }),
                  ),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: _num(l.days, 'Days *', decimal: true)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SettingsDropdown<String>(
                      label: 'Type',
                      value: l.type,
                      items: const [
                        DropdownMenuItem(value: 'paid', child: Text('Paid')),
                        DropdownMenuItem(value: 'unpaid', child: Text('Unpaid')),
                        DropdownMenuItem(value: 'sick', child: Text('Sick')),
                      ],
                      onChanged: (v) => setState(() => l.type = v ?? 'paid'),
                    ),
                  ),
                ]),
                SettingsSwitchTile(
                  title: 'Carry forward',
                  value: l.carryForward,
                  onChanged: (v) => setState(() => l.carryForward = v),
                ),
                if (l.carryForward) _num(l.maxCarry, 'Max carry forward days', decimal: true),
              ]),
            ),
          ),
      ];

  List<Widget> _breakFields() => [
        const SettingsSectionTitle('Break rules'),
        _num(_duration, 'Break duration *', suffix: 'min'),
        const SizedBox(height: 12),
        SettingsDropdown<String>(
          label: 'Fine rule',
          value: _fineRule,
          items: const [
            DropdownMenuItem(value: 'auto', child: Text('Auto')),
            DropdownMenuItem(value: '1x', child: Text('1x')),
            DropdownMenuItem(value: '2x', child: Text('2x')),
            DropdownMenuItem(value: '3x', child: Text('3x')),
            DropdownMenuItem(value: 'custom', child: Text('Custom amount')),
          ],
          onChanged: (v) => setState(() => _fineRule = v ?? 'auto'),
        ),
        if (_fineRule == 'custom') ...[
          const SizedBox(height: 12),
          _num(_customFine, 'Custom fine amount', suffix: '₹', decimal: true),
        ],
      ];

  List<Widget> _overtimeFields() => [
        const SettingsSectionTitle('Overtime rules'),
        _num(_minOt, 'Overtime buffer duration *', suffix: 'min'),
        const Padding(
          padding: EdgeInsets.only(top: 4, left: 4),
          child: Text('Minimum extra minutes an employee must work to qualify for overtime',
              style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
        ),
        const SizedBox(height: 12),
        _num(_maxOtHours, 'Maximum overtime hours', suffix: 'h', decimal: true),
      ];

  List<Widget> _permissionFields() => [
        const SettingsSectionTitle('Allowed permission'),
        Row(children: [
          Expanded(child: _num(_permHours, 'Hours')),
          const SizedBox(width: 10),
          Expanded(child: _num(_permMinutes, 'Minutes')),
        ]),
      ];

  Widget _dayChips() => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final d in kWeekDays)
            FilterChip(
              label: Text(d.substring(0, 3)),
              selected: _days.contains(d),
              selectedColor: AppColors.brandLight,
              checkmarkColor: AppColors.brandDark,
              onSelected: (v) => setState(() => v ? _days.add(d) : _days.remove(d)),
            ),
        ],
      );

  List<Widget> _weekOffFields() => [
        const SettingsSectionTitle('Pattern'),
        SettingsDropdown<String>(
          label: 'Pattern type',
          value: _pattern,
          items: const [
            DropdownMenuItem(value: 'standard', child: Text('Standard (fixed days every week)')),
            DropdownMenuItem(value: 'custom', child: Text('Custom (specific weeks of the month)')),
            DropdownMenuItem(value: 'custom_weekday', child: Text('Custom weekday (any N days a week)')),
            DropdownMenuItem(value: 'alternate', child: Text('Alternate Saturdays')),
          ],
          onChanged: (v) => setState(() => _pattern = v ?? 'standard'),
        ),
        const SizedBox(height: 12),
        if (_pattern == 'standard' || _pattern == 'custom') ...[
          const Text('Days off', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          const SizedBox(height: 8),
          _dayChips(),
        ],
        if (_pattern == 'custom')
          for (final d in kWeekDays.where(_days.contains))
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('$d off weeks', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                const SizedBox(height: 6),
                Wrap(spacing: 6, children: [
                  for (final w in _kOffWeeks)
                    FilterChip(
                      label: Text(w),
                      selected: _customOffWeeks[d]?.contains(w) ?? false,
                      selectedColor: AppColors.brandLight,
                      checkmarkColor: AppColors.brandDark,
                      onSelected: (v) => setState(() {
                        final s = _customOffWeeks.putIfAbsent(d, () => <String>{});
                        v ? s.add(w) : s.remove(w);
                      }),
                    ),
                ]),
              ]),
            ),
        if (_pattern == 'custom_weekday')
          Row(children: [
            const Expanded(child: Text('Days off per week', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.textPrimary))),
            IconButton(
              tooltip: 'Decrease',
              onPressed: _customDaysCount > 1 ? () => setState(() => _customDaysCount--) : null,
              icon: const Icon(Icons.remove_circle_outline_rounded),
            ),
            Text('$_customDaysCount', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            IconButton(
              tooltip: 'Increase',
              onPressed: _customDaysCount < 7 ? () => setState(() => _customDaysCount++) : null,
              icon: const Icon(Icons.add_circle_outline_rounded),
            ),
          ]),
        if (_pattern == 'alternate')
          SettingsDropdown<String>(
            label: 'Saturdays off',
            value: _alternateWeeks,
            items: const [
              DropdownMenuItem(value: 'even', child: Text('Even (2nd & 4th Saturdays off, all Sundays off)')),
              DropdownMenuItem(value: 'odd', child: Text('Odd (1st, 3rd & 5th Saturdays off, all Sundays off)')),
            ],
            onChanged: (v) => setState(() => _alternateWeeks = v ?? 'even'),
          ),
      ];

  Widget _timeButton(String label, String? value, ValueChanged<String> onPicked) => OutlinedButton.icon(
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48), alignment: Alignment.centerLeft),
        onPressed: () async {
          final t = await showTimePicker(context: context, initialTime: parseAmPm(value) ?? const TimeOfDay(hour: 9, minute: 0));
          if (t != null) onPicked(fmtAmPm(t));
        },
        icon: const Icon(Icons.schedule_rounded, size: 18),
        label: Text(value == null ? label : '$label: $value'),
      );

  void _autoHalfDay() {
    final s = parseAmPm(_start), e = parseAmPm(_end);
    if (s == null || e == null) return;
    var sm = s.hour * 60 + s.minute, em = e.hour * 60 + e.minute;
    if (em <= sm) em += 24 * 60;
    final mid = ((sm + em) ~/ 2) % (24 * 60);
    final t = fmtAmPm(TimeOfDay(hour: mid ~/ 60, minute: mid % 60));
    _firstHalfEnd = t;
    _secondHalfStart = t;
  }

  List<DropdownMenuItem<String>> _shiftItems({bool allowOff = false}) => [
        if (allowOff) const DropdownMenuItem(value: '', child: Text('Off')),
        for (final s in _shiftOptions)
          DropdownMenuItem(value: AdminSettingsService.idOf(s), child: Text((s['name'] ?? '-').toString(), overflow: TextOverflow.ellipsis)),
      ];

  void _setCycle(int n) {
    final len = n.clamp(1, 31);
    setState(() {
      _cycleLength = len;
      if (_patternSlots.length < len) {
        _patternSlots = [..._patternSlots, ...List.filled(len - _patternSlots.length, '')];
      } else {
        _patternSlots = _patternSlots.sublist(0, len);
      }
    });
  }

  List<Widget> _shiftFields() {
    final unit = switch (_rotationType) {
      'weekly' || 'joining_date' => 'Week',
      'monthly' => 'Month',
      _ => 'Day',
    };
    return [
      const SizedBox(height: 12),
      SettingsDropdown<String>(
        label: 'Shift type',
        value: _shiftType,
        items: const [
          DropdownMenuItem(value: 'standard', child: Text('Standard (fixed timings)')),
          DropdownMenuItem(value: 'open', child: Text('Open (flexible, fixed hours)')),
          DropdownMenuItem(value: 'rotational', child: Text('Rotational')),
        ],
        onChanged: (v) => setState(() => _shiftType = v ?? 'standard'),
      ),
      if (_shiftType == 'standard') ...[
        const SettingsSectionTitle('Timings'),
        _timeButton('Start time *', _start, (v) => setState(() {
              _start = v;
              _autoHalfDay();
            })),
        const SizedBox(height: 10),
        _timeButton('End time *', _end, (v) => setState(() {
              _end = v;
              _autoHalfDay();
            })),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _num(_grace, 'Grace time')),
          const SizedBox(width: 10),
          Expanded(
            child: SettingsDropdown<String>(
              label: 'Unit',
              value: _graceUnit,
              items: const [
                DropdownMenuItem(value: 'minutes', child: Text('Minutes')),
                DropdownMenuItem(value: 'hours', child: Text('Hours')),
              ],
              onChanged: (v) => setState(() => _graceUnit = v ?? 'minutes'),
            ),
          ),
        ]),
      ],
      if (_shiftType == 'open') ...[
        const SettingsSectionTitle('Work hours'),
        _num(_workHours, 'Work hours per day *', suffix: 'h', decimal: true),
      ],
      if (_shiftType != 'rotational') ...[
        const SettingsSectionTitle('Half day'),
        SettingsSwitchTile(title: 'Enable half day', value: _halfDay, onChanged: (v) => setState(() => _halfDay = v)),
        if (_halfDay) ...[
          _timeButton('First half ends', _firstHalfEnd, (v) => setState(() => _firstHalfEnd = v)),
          const SizedBox(height: 10),
          _timeButton('Second half starts', _secondHalfStart, (v) => setState(() => _secondHalfStart = v)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _num(_firstHalfLogoutGrace, 'First half logout grace', suffix: 'min')),
            const SizedBox(width: 10),
            Expanded(child: _num(_secondHalfLoginGrace, 'Second half login grace', suffix: 'min')),
          ]),
        ],
      ],
      if (_shiftType == 'rotational') ...[
        const SettingsSectionTitle('Rotation'),
        SettingsDropdown<String>(
          label: 'Rotation type',
          value: _rotationType,
          items: [for (final e in _kRotationTypes.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
          onChanged: (v) => setState(() => _rotationType = v ?? 'daily'),
        ),
        if (_rotationType != 'custom' && _rotationType != 'week_day') ...[
          const SizedBox(height: 12),
          SettingsDropdown<String>(
            label: 'Weekly off template *',
            value: _weeklyOffTemplateId,
            items: [
              for (final w in _weekOffOptions)
                DropdownMenuItem(value: AdminSettingsService.idOf(w), child: Text((w['name'] ?? '-').toString())),
            ],
            onChanged: (v) => setState(() => _weeklyOffTemplateId = v),
          ),
        ],
        if (_shiftOptions.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text('No standard or open shifts yet. Create one first to build a rotation.',
                style: TextStyle(color: AppColors.error, fontSize: 12.5)),
          ),
        if (_rotationType == 'weekly') ...[
          const SizedBox(height: 12),
          SettingsDropdown<String>(
            label: 'Week starts on',
            value: _weekStarts,
            items: [for (final d in kWeekDays) DropdownMenuItem(value: d, child: Text(d))],
            onChanged: (v) => setState(() => _weekStarts = v ?? 'Monday'),
          ),
        ],
        if (_rotationType == 'week_day') ...[
          const SettingsSectionTitle('Shift per weekday'),
          for (var i = 0; i < 7; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SettingsDropdown<String>(
                label: kWeekDays[i],
                value: _weekDaySlots[i],
                items: _shiftItems(allowOff: true),
                onChanged: (v) => setState(() => _weekDaySlots[i] = v ?? ''),
              ),
            ),
        ] else if (_rotationType == 'calendar_date') ...[
          SettingsSectionTitle('Date ranges',
              trailing: TextButton.icon(
                onPressed: () => setState(() => _ranges.add(_RangeRow())),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add range'),
              )),
          const Text('Days not covered use the first shift.', style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
          for (final r in _ranges)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(children: [
                SizedBox(
                  width: 70,
                  child: SettingsDropdown<int>(
                    label: 'From',
                    value: r.from,
                    items: [for (var d = 1; d <= 31; d++) DropdownMenuItem(value: d, child: Text('$d'))],
                    onChanged: (v) => setState(() => r.from = v ?? 1),
                  ),
                ),
                const SizedBox(width: 6),
                SizedBox(
                  width: 70,
                  child: SettingsDropdown<int>(
                    label: 'To',
                    value: r.to,
                    items: [for (var d = 1; d <= 31; d++) DropdownMenuItem(value: d, child: Text('$d'))],
                    onChanged: (v) => setState(() => r.to = v ?? 1),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: SettingsDropdown<String>(
                    label: 'Shift',
                    value: r.templateId,
                    items: _shiftItems(),
                    onChanged: (v) => setState(() => r.templateId = v ?? ''),
                  ),
                ),
                IconButton(
                  tooltip: 'Remove',
                  icon: const Icon(Icons.close_rounded, color: AppColors.error),
                  onPressed: () => setState(() => _ranges.remove(r)),
                ),
              ]),
            ),
        ] else ...[
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: Text('Cycle length ($unit${_cycleLength == 1 ? '' : 's'})', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.textPrimary))),
            IconButton(tooltip: 'Decrease', onPressed: _cycleLength > 1 ? () => _setCycle(_cycleLength - 1) : null, icon: const Icon(Icons.remove_circle_outline_rounded)),
            Text('$_cycleLength', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            IconButton(tooltip: 'Increase', onPressed: _cycleLength < 31 ? () => _setCycle(_cycleLength + 1) : null, icon: const Icon(Icons.add_circle_outline_rounded)),
          ]),
          for (var i = 0; i < _patternSlots.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SettingsDropdown<String>(
                label: '$unit ${i + 1}${_rotationType == 'daily' ? ' *' : ''}',
                value: _patternSlots[i],
                items: _shiftItems(allowOff: _rotationType == 'custom'),
                onChanged: (v) => setState(() => _patternSlots[i] = v ?? ''),
              ),
            ),
        ],
      ],
    ];
  }
}
