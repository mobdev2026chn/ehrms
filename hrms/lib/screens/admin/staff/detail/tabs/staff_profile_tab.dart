// Profile tab of the admin Staff Detail screen (web: staffManagement/profile.tsx).
// Each section is viewed read-only and edited in place; saving sends only that
// section's fields to PUT /admin/staff/:id, which writes only what it receives.
import 'package:flutter/material.dart';

import '../../../../../config/app_colors.dart';
import '../../../../../config/app_text_styles.dart';
import '../../../../../services/admin_staff_detail_service.dart';
import '../staff_detail_common.dart';

enum _Kind { text, date, select, email, number }

class _F {
  const _F(this.key, this.label, {this.kind = _Kind.text, this.options});
  final String key;
  final String label;
  final _Kind kind;
  final List<String>? options;
}

class _Section {
  const _Section(this.id, this.title, this.icon, this.fields);
  final String id;
  final String title;
  final IconData icon;
  final List<_F> fields;
}

const _designations = ['Junior', 'Senior', 'Team Lead', 'Manager'];
const _employmentTypes = ['Full Time', 'Part Time', 'Contract', 'Intern'];

const _sections = <_Section>[
  _Section('personal', 'Personal Details', Icons.badge_outlined, [
    _F('employeeId', 'Employee ID'),
    _F('firstName', 'First Name'),
    _F('lastName', 'Last Name'),
    _F('dob', 'Date of Birth', kind: _Kind.date),
    _F('gender', 'Gender', kind: _Kind.select, options: ['Male', 'Female', 'Other']),
    _F('bloodGroup', 'Blood Group',
        kind: _Kind.select, options: ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-']),
    _F('fatherName', "Father's Name"),
    _F('maritalStatus', 'Marital Status', kind: _Kind.select, options: ['Single', 'Married']),
    _F('spouseName', "Spouse's Name"),
  ]),
  _Section('contact', 'Contact Details', Icons.call_outlined, [
    _F('contact', 'Email ID', kind: _Kind.email),
    _F('phone', 'Phone Number'),
    _F('altPhone', 'Alternate Phone'),
  ]),
  _Section('address', 'Address', Icons.home_outlined, [
    _F('currentAddress', 'Current Address'),
    _F('currentState', 'Current State'),
    _F('currentCountry', 'Current Country'),
    _F('currentPincode', 'Current Pincode'),
    _F('permanentAddress', 'Permanent Address'),
    _F('permanentState', 'Permanent State'),
    _F('permanentCountry', 'Permanent Country'),
    _F('permanentPincode', 'Permanent Pincode'),
  ]),
  _Section('role', 'Employment & Role', Icons.work_outline_rounded, [
    _F('designation', 'Designation', kind: _Kind.select, options: _designations),
    _F('department', 'Department'),
    _F('jobPosition', 'Job Position'),
    _F('reportingManager', 'Reporting Manager', kind: _Kind.select),
    _F('employmentType', 'Employment Type', kind: _Kind.select, options: _employmentTypes),
    _F('joiningDate', 'Joining Date', kind: _Kind.date),
    _F('internStartDate', 'Intern Start Date', kind: _Kind.date),
    _F('internEndDate', 'Intern End Date', kind: _Kind.date),
    _F('branch', 'Branch', kind: _Kind.select),
  ]),
  _Section('statutory', 'Statutory & Bank', Icons.account_balance_outlined, [
    _F('pan', 'PAN'),
    _F('aadhaar', 'Aadhaar'),
    _F('uanNumber', 'UAN Number'),
    _F('pfNumber', 'PF Number'),
    _F('pfStartDate', 'PF Start Date', kind: _Kind.date),
    _F('esiNumber', 'ESI Number'),
    _F('esiStartDate', 'ESI Start Date', kind: _Kind.date),
    _F('bankName', 'Bank Name'),
    _F('accountHolderName', 'Account Holder Name'),
    _F('accountNumber', 'Account Number', kind: _Kind.number),
    _F('ifscCode', 'IFSC Code'),
    _F('bankBranch', 'Bank Branch'),
    _F('upiId', 'UPI ID'),
  ]),
  _Section('templates', 'Templates', Icons.tune_rounded, [
    _F('shiftTemplate', 'Shift Template', kind: _Kind.select),
    _F('attendanceTemplate', 'Attendance Template', kind: _Kind.select),
    _F('leaveTemplate', 'Leave Template', kind: _Kind.select),
    _F('holidayTemplate', 'Holiday Template', kind: _Kind.select),
    _F('weeklyOffTemplate', 'Weekly Off Template', kind: _Kind.select),
    _F('breakTemplate', 'Break Template', kind: _Kind.select),
    _F('permissionTemplate', 'Permission Template', kind: _Kind.select),
    _F('overtimeTemplate', 'Overtime Template', kind: _Kind.select),
    _F('salaryTemplate', 'Salary Template', kind: _Kind.select),
  ]),
];

/// Setup-response key holding the options of each template field.
const _templateSetupKeys = {
  'shiftTemplate': 'shiftTemplates',
  'attendanceTemplate': 'attendanceTemplates',
  'leaveTemplate': 'leaveTemplates',
  'holidayTemplate': 'holidayTemplates',
  'weeklyOffTemplate': 'weeklyOffTemplates',
  'breakTemplate': 'breakTemplates',
  'permissionTemplate': 'permissionTemplates',
  'overtimeTemplate': 'overtimeTemplates',
  'salaryTemplate': 'salaryTemplates',
};

class StaffProfileTab extends StatefulWidget {
  const StaffProfileTab({super.key, required this.staff, required this.onUpdated});

  final Map<String, dynamic> staff;
  final ValueChanged<Map<String, dynamic>> onUpdated;

  @override
  State<StaffProfileTab> createState() => _StaffProfileTabState();
}

class _StaffProfileTabState extends State<StaffProfileTab> {
  final _service = AdminStaffDetailService();

  late Map<String, String> _form;
  final Map<String, TextEditingController> _ctrls = {};
  final Set<String> _editing = {};
  String? _saving;

  // Lookups
  bool _lookupsLoading = true;
  String? _lookupsError;
  List<Map<String, dynamic>> _branches = [];
  Map<String, dynamic> _setup = {};
  Map<String, dynamic>? _activeShift;
  String? _activeShiftError;
  List<String> _managerOptions = [];
  List<String> _reportsTo = [];
  bool _managersLoading = false;

  String get _staffId => sdId(widget.staff);

  @override
  void initState() {
    super.initState();
    _form = _mapStaff(widget.staff);
    _loadLookups();
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  static String _dateKey(dynamic v) => sdIsoKey(v);

  Map<String, String> _mapStaff(Map<String, dynamic> s) {
    final ms = s['maritalStatus'];
    final pc = s['physicallyChallenged'];
    Map<String, dynamic> addr(dynamic a) => a is Map ? Map<String, dynamic>.from(a) : {'address': a};
    final cur = addr(s['currentAddress']);
    final perm = addr(s['permanentAddress']);
    return {
      'employeeId': sdStr(s['employeeId']),
      'firstName': sdStr(s['firstName']),
      'lastName': sdStr(s['lastName']),
      'dob': _dateKey(s['dateOfBirth'] ?? s['dob']),
      'gender': sdStr(s['gender']),
      'bloodGroup': sdStr(s['bloodGroup']),
      'fatherName': sdStr(s['fatherName']),
      'maritalStatus': (ms == 'Married' || ms is Map) ? 'Married' : 'Single',
      'spouseName': sdStr(s['spouseName'] ?? (ms is Map ? ms['spouseName'] : null)),
      'contact': sdStr(s['email'] ?? s['contact']),
      'phone': sdStr(s['phoneNumber'] ?? s['phone']),
      'altPhone': sdStr(s['alternatePhoneNumber'] ?? s['altPhone']),
      'currentAddress': sdStr(cur['address']),
      'currentState': sdStr(cur['state']),
      'currentCountry': sdStr(cur['country']),
      'currentPincode': sdStr(cur['pincode']),
      'permanentAddress': sdStr(perm['address']),
      'permanentState': sdStr(perm['state']),
      'permanentCountry': sdStr(perm['country']),
      'permanentPincode': sdStr(perm['pincode']),
      'designation': sdStr(s['designation']),
      'department': sdStr(s['department']),
      'jobPosition': sdStr(s['jobRole'] ?? s['jobPosition']),
      'reportingManager': sdStr(s['reportingManager']),
      'employmentType': sdStr(s['employmentType'], 'Full Time'),
      'joiningDate': _dateKey(s['joiningDate']),
      'internStartDate': _dateKey(s['startDate'] ?? s['internStartDate']),
      'internEndDate': _dateKey(s['endDate'] ?? s['internEndDate']),
      'branch': sdId(s['branch']),
      'pan': sdStr(s['panNumber'] ?? s['pan']),
      'aadhaar': sdStr(s['aadhaarNumber'] ?? s['aadhaar']),
      'uanNumber': sdStr(s['uanNumber']),
      'pfNumber': sdStr(s['pfNumber']),
      'pfStartDate': _dateKey(s['pfStartDate']),
      'esiNumber': sdStr(s['esiNumber']),
      'esiStartDate': _dateKey(s['esiStartDate']),
      'bankName': sdStr(s['bankName']),
      'accountHolderName': sdStr(s['accountHolderName']),
      'accountNumber': sdStr(s['accountNumber']),
      'ifscCode': sdStr(s['ifscCode']),
      'bankBranch': sdStr(s['branchName'] ?? s['bankBranch']),
      'upiId': sdStr(s['upiId']),
      'isPhysicallyChallenged': pc is Map ? 'Yes' : 'No',
      'workMode': s['workMode'] is Map ? sdStr((s['workMode'] as Map)['mode'], 'In Office') : 'In Office',
      for (final k in _templateSetupKeys.keys) k: sdId(s[k]),
    };
  }

  Future<void> _loadLookups() async {
    setState(() {
      _lookupsLoading = true;
      _lookupsError = null;
    });
    try {
      final results = await Future.wait([_service.getBranches(), _service.getSetup()]);
      if (!mounted) return;
      setState(() {
        _branches = results[0] as List<Map<String, dynamic>>;
        _setup = results[1] as Map<String, dynamic>;
        _lookupsLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _lookupsError = sdErrorText(e);
        _lookupsLoading = false;
      });
    }
    _loadActiveShift();
    _loadManagers();
  }

  Future<void> _loadActiveShift() async {
    try {
      final data = await _service.getActiveShift(_staffId);
      if (!mounted) return;
      setState(() {
        _activeShift = data;
        _activeShiftError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _activeShiftError = sdErrorText(e));
    }
  }

  Future<void> _loadManagers() async {
    final designation = (_form['designation'] ?? '').isEmpty ? 'Junior' : _form['designation']!;
    setState(() => _managersLoading = true);
    try {
      final data = await _service.getReportingManagers(designation: designation, excludeId: _staffId);
      if (!mounted) return;
      setState(() {
        _managerOptions = ((data['options'] as List?) ?? const []).map((e) => e.toString()).toList();
        _reportsTo = ((data['reportsTo'] as List?) ?? const []).map((e) => e.toString()).toList();
        _managersLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _managersLoading = false);
      sdShowError(context, e);
    }
  }

  TextEditingController _ctrl(String key) =>
      _ctrls.putIfAbsent(key, () => TextEditingController(text: _form[key] ?? ''));

  void _startEdit(_Section section) {
    setState(() {
      for (final f in section.fields) {
        if (f.kind == _Kind.text || f.kind == _Kind.email || f.kind == _Kind.number) {
          _ctrl(f.key).text = _form[f.key] ?? '';
        }
      }
      _editing.add(section.id);
    });
  }

  void _cancelEdit(_Section section) {
    setState(() {
      _form = _mapStaff(widget.staff);
      _editing.remove(section.id);
    });
    if (section.id == 'role') _loadManagers();
  }

  String? _validate(_Section section, Map<String, String> v) {
    switch (section.id) {
      case 'personal':
        if ((v['firstName'] ?? '').isEmpty) return 'First name is required.';
        if (v['maritalStatus'] == 'Married' && (v['spouseName'] ?? '').isEmpty) {
          return "Spouse's Name is required.";
        }
        break;
      case 'contact':
        final email = v['contact'] ?? '';
        if (email.isEmpty) return 'Email ID is required.';
        if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) return 'Please enter a valid Email ID.';
        if ((v['phone'] ?? '').isEmpty) return 'Phone number is required.';
        if ((v['altPhone'] ?? '').isEmpty) return 'Alternate Phone number is required.';
        String digits(String s) => s.replaceAll(RegExp(r'\D'), '');
        if (digits(v['phone']!) == digits(v['altPhone']!)) {
          return 'Phone number and Alternate Phone number cannot be the same.';
        }
        break;
      case 'role':
        if ((v['branch'] ?? '').isEmpty) {
          return _branches.isEmpty
              ? 'No branches are configured yet. Create a branch before assigning one.'
              : 'Branch is required.';
        }
        break;
    }
    return null;
  }

  Future<void> _save(_Section section) async {
    final values = <String, String>{};
    for (final f in section.fields) {
      values[f.key] = (f.kind == _Kind.text || f.kind == _Kind.email || f.kind == _Kind.number)
          ? _ctrl(f.key).text.trim()
          : (_form[f.key] ?? '');
    }
    final error = _validate(section, values);
    if (error != null) {
      sdShowError(context, StaffDetailApiException(error));
      return;
    }

    final payload = <String, dynamic>{...values};
    if (section.id == 'personal' && values['maritalStatus'] != 'Married') payload['spouseName'] = '';
    // Dates are only written when set; the backend ignores empty ones.
    for (final f in section.fields.where((f) => f.kind == _Kind.date)) {
      if ((payload[f.key] as String).isEmpty) payload.remove(f.key);
    }

    setState(() => _saving = section.id);
    try {
      final updated = await _service.updateStaff(_staffId, payload);
      if (!mounted) return;
      final merged = {...widget.staff, ...updated};
      setState(() {
        _form = _mapStaff(merged);
        _editing.remove(section.id);
        _saving = null;
      });
      widget.onUpdated(updated);
      sdShowSuccess(context, 'Profile section updated successfully.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = null);
      sdShowError(context, e);
    }
  }

  // ───────────── options ─────────────

  List<MapEntry<String, String>> _optionsFor(_F f) {
    final current = _form[f.key] ?? '';
    List<MapEntry<String, String>> opts;
    if (f.key == 'branch') {
      opts = _branches
          .map((b) => MapEntry(sdId(b), sdStr(b['branchName'] ?? b['name'], 'Branch')))
          .where((e) => e.key.isNotEmpty)
          .toList();
    } else if (f.key == 'reportingManager') {
      opts = _managerOptions.map((o) => MapEntry(o, o)).toList();
    } else if (_templateSetupKeys.containsKey(f.key)) {
      final list = (_setup[_templateSetupKeys[f.key]] as List?) ?? const [];
      opts = [
        const MapEntry('', 'None'),
        ...list.whereType<Map>().map((t) => MapEntry(sdId(t), sdStr(t['name'] ?? t['title'], 'Template'))),
      ];
    } else {
      opts = (f.options ?? const []).map((o) => MapEntry(o, o)).toList();
    }
    // A value already on the record stays selectable even when no longer offered, so saving
    // does not quietly clear it.
    if (current.isNotEmpty && !opts.any((e) => e.key == current)) {
      opts = [MapEntry(current, _displayValue(f, current)), ...opts];
    }
    if (f.key == 'reportingManager' && !opts.any((e) => e.key.isEmpty)) {
      opts = [const MapEntry('', 'None'), ...opts];
    }
    return opts;
  }

  String _displayValue(_F f, String value) {
    if (value.isEmpty) return '-';
    if (f.kind == _Kind.date) return sdFmtDate(value);
    if (f.key == 'branch') {
      final b = _branches.firstWhere((b) => sdId(b) == value, orElse: () => const {});
      final fromStaff = widget.staff['branch'];
      return sdStr(b['branchName'], fromStaff is Map ? sdStr(fromStaff['branchName'], value) : value);
    }
    if (_templateSetupKeys.containsKey(f.key)) {
      final list = (_setup[_templateSetupKeys[f.key]] as List?) ?? const [];
      final t = list.whereType<Map>().firstWhere((t) => sdId(t) == value, orElse: () => const {});
      if (t.isNotEmpty) return sdStr(t['name'] ?? t['title'], value);
      final raw = widget.staff[f.key];
      return raw is Map ? sdStr(raw['name'] ?? raw['title'], 'Assigned') : 'Assigned (inactive)';
    }
    return value;
  }

  // ───────────── UI ─────────────

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _loadLookups,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          if (_lookupsError != null)
            SdCard(
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: AppColors.error, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_lookupsError!, style: AppTextStyles.bodySmall)),
                  TextButton(onPressed: _loadLookups, child: const Text('Retry')),
                ],
              ),
            ),
          _buildActiveShiftCard(),
          for (final s in _sections) _buildSection(s),
          SdCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SdSectionTitle('Other', icon: Icons.info_outline_rounded),
                SdKeyValue('Work Mode', _form['workMode'] ?? '-'),
                SdKeyValue('Physically Challenged', _form['isPhysicallyChallenged'] ?? 'No'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveShiftCard() {
    final assignment = _activeShift?['assignment'];
    Widget body;
    if (_activeShiftError != null) {
      body = Row(children: [
        Expanded(child: Text(_activeShiftError!, style: AppTextStyles.bodySmall)),
        TextButton(onPressed: _loadActiveShift, child: const Text('Retry')),
      ]);
    } else if (_activeShift == null) {
      body = const Text('Loading...', style: AppTextStyles.bodySmall);
    } else if (assignment is! Map) {
      body = const Text('No shift assigned', style: AppTextStyles.bodySmall);
    } else {
      final t = assignment['shiftTemplateId'];
      final tm = t is Map ? t : const {};
      final timing = sdStr(tm['startTime']).isNotEmpty
          ? '${sdStr(tm['startTime'])} - ${sdStr(tm['endTime'])}'
          : (tm['workHours'] != null ? '${tm['workHours']}h Flexi' : '');
      body = Column(children: [
        SdKeyValue('Shift', sdStr(tm['name'], '-')),
        SdKeyValue('Type', sdStr(tm['shiftType'], '-')),
        if (timing.isNotEmpty) SdKeyValue('Timing', timing),
        SdKeyValue('Assignment', '${sdStr(assignment['assignmentType'], '-')} (${sdStr(_activeShift?['source'])})'),
        SdKeyValue('Effective From', sdFmtDate(assignment['effectiveFrom'])),
        if (assignment['effectiveTo'] != null) SdKeyValue('Effective To', sdFmtDate(assignment['effectiveTo'])),
      ]);
    }
    return SdCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [const SdSectionTitle('Active Shift', icon: Icons.schedule_rounded), body],
      ),
    );
  }

  Widget _buildSection(_Section section) {
    final editing = _editing.contains(section.id);
    final saving = _saving == section.id;
    final fields = section.fields.where((f) {
      if (f.key == 'spouseName') return _form['maritalStatus'] == 'Married';
      if (f.key == 'internStartDate' || f.key == 'internEndDate') return _form['employmentType'] == 'Intern';
      return true;
    }).toList();

    return SdCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SdSectionTitle(
            section.title,
            icon: section.icon,
            trailing: editing
                ? null
                : TextButton.icon(
                    onPressed: (_lookupsLoading && (section.id == 'role' || section.id == 'templates'))
                        ? null
                        : () => _startEdit(section),
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text('Edit'),
                    style: TextButton.styleFrom(foregroundColor: AppColors.primaryText, visualDensity: VisualDensity.compact),
                  ),
          ),
          if (!editing)
            ...fields.map((f) => SdKeyValue(f.label, _displayValue(f, _form[f.key] ?? '')))
          else ...[
            for (final f in fields) Padding(padding: const EdgeInsets.only(bottom: 12), child: _buildInput(f)),
            if (section.id == 'role' && _reportsTo.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text('Reports to: ${_reportsTo.join(' or ')}',
                    style: AppTextStyles.caption.copyWith(color: kSdMuted)),
              ),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: saving ? null : () => _cancelEdit(section),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: saving ? null : () => _save(section),
                    style: sdPrimaryButton(),
                    child: saving
                        ? SizedBox(
                            width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onPrimary))
                        : const Text('Save'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInput(_F f) {
    switch (f.kind) {
      case _Kind.text:
      case _Kind.email:
      case _Kind.number:
        return TextField(
          controller: _ctrl(f.key),
          keyboardType: f.kind == _Kind.email
              ? TextInputType.emailAddress
              : (f.kind == _Kind.number ? TextInputType.number : TextInputType.text),
          style: const TextStyle(fontSize: 14),
          decoration: sdInput(f.label),
        );
      case _Kind.date:
        final value = _form[f.key] ?? '';
        return InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () async {
            final initial = DateTime.tryParse(value) ?? DateTime.now();
            final picked = await showDatePicker(
              context: context,
              initialDate: initial,
              firstDate: DateTime(1940),
              lastDate: DateTime(DateTime.now().year + 5),
            );
            if (picked != null) setState(() => _form[f.key] = sdKey(picked));
          },
          child: InputDecorator(
            decoration: sdInput(f.label).copyWith(suffixIcon: const Icon(Icons.calendar_today_outlined, size: 18)),
            child: Text(value.isEmpty ? 'Select date' : sdFmtDate(value), style: const TextStyle(fontSize: 13.5)),
          ),
        );
      case _Kind.select:
        final opts = _optionsFor(f);
        final value = _form[f.key] ?? '';
        final hasValue = opts.any((e) => e.key == value);
        return DropdownButtonFormField<String>(
          key: ValueKey('${f.key}-$value-${opts.length}'),
          initialValue: hasValue ? value : null,
          isExpanded: true,
          decoration: sdInput(f.key == 'reportingManager' && _managersLoading ? '${f.label} (loading...)' : f.label),
          items: opts
              .map((e) => DropdownMenuItem(
                  value: e.key,
                  child: Text(e.value, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5))))
              .toList(),
          onChanged: (v) {
            setState(() => _form[f.key] = v ?? '');
            if (f.key == 'designation') _loadManagers();
          },
        );
    }
  }
}
