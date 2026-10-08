// Module Access (admin only): /admin/settings/module-access
//   GET  /               eligible staff
//   GET  /:staffId       saved access { enabled, permissions[] }
//   PUT  /:staffId       { enabled, permissions[] }
//   GET  /:staffId/team  staff reporting to them
//   PUT  /:staffId/profile { designation?, password? }
// The module catalogue mirrors the web's shared/permissions/moduleRegistry.ts
// (the backend checks the same keys).

import 'package:flutter/material.dart';

import '../../../widgets/app_card.dart';
import '../../../config/app_colors.dart';
import '../../../services/admin_settings_service.dart';
import 'settings_common.dart';

class _Page {
  const _Page(this.key, this.label);
  final String key;
  final String label;
}

class _Module {
  const _Module(this.id, this.name, [this.pages = const []]);
  final String id;
  final String name;
  final List<_Page> pages;
  List<_Page> get items => pages.isEmpty ? [_Page(id, name)] : pages;
}

const _kModules = <_Module>[
  _Module('staff', 'Staff', [
    _Page('staff:profile', 'Profile'),
    _Page('staff:attendance', 'Attendance'),
    _Page('staff:salary-overview', 'Salary Overview'),
    _Page('staff:salary-structure', 'Salary Structure'),
    _Page('staff:leaves', 'Leaves'),
    _Page('staff:permissions', 'Permissions'),
    _Page('staff:shifts', 'Shifts'),
    _Page('staff:documents', 'Documents'),
    _Page('staff:expense-claim', 'Reimbursement'),
    _Page('staff:payslip-requests', 'Payslip Requests'),
  ]),
  _Module('attendance', 'Attendance'),
  _Module('overtime', 'Overtime'),
  _Module('payroll', 'Payroll'),
  _Module('approval', 'Approval', [
    _Page('approval:leave', 'Leave'),
    _Page('approval:permission', 'Permission'),
    _Page('approval:punch-in', 'Punch In'),
    _Page('approval:punch-out', 'Punch Out'),
    _Page('approval:fine', 'Fine'),
    _Page('approval:reimbursement', 'Reimbursement'),
    _Page('approval:payslip-requests', 'Payslip Requests'),
  ]),
  _Module('staffSettings', 'Staff Settings', [
    _Page('staff-settings:attendance', 'Attendance'),
    _Page('staff-settings:salary', 'Salary'),
    _Page('staff-settings:shift-roster', 'Shift Roster'),
    _Page('staff-settings:report', 'Report'),
  ]),
  _Module('hrmsGeo', 'HRMS Geo', [
    _Page('hrms-geo:dashboard', 'Dashboard'),
    _Page('hrms-geo:customer', 'Customer'),
    _Page('hrms-geo:travel-allowance', 'Travel Allowance'),
    _Page('hrms-geo:task', 'Task'),
    _Page('hrms-geo:tracking', 'Tracking'),
  ]),
  _Module('hrmsGeoSettings', 'HRMS Geo Settings', [
    _Page('hrms-geo-settings:employee-access', 'Employee Access'),
    _Page('hrms-geo-settings:custom-fields', 'Custom Fields'),
    _Page('hrms-geo-settings:form-templates', 'Form Templates'),
    _Page('hrms-geo-settings:general-settings', 'General Settings'),
    _Page('hrms-geo-settings:travel-allowance', 'Travel Allowance'),
  ]),
  _Module('exit-process', 'Exit Process'),
  _Module('recruitment', 'Recruitment', [
    _Page('recruitment:analytics', 'Analytics'),
    _Page('recruitment:job-openings', 'Job Openings'),
    _Page('recruitment:candidates', 'Candidates'),
    _Page('recruitment:appointments', 'Appointments'),
    _Page('recruitment:interview-process', 'Interview Process'),
    _Page('recruitment:offer-letter', 'Offer Letter'),
    _Page('recruitment:verification', 'Verification'),
    _Page('recruitment:communications', 'Communications'),
    _Page('recruitment:disposition', 'Candidate Disposition'),
  ]),
  _Module('loans', 'Loans', [
    _Page('loans:dashboard', 'Dashboard'),
    _Page('loans:all', 'Loan Management'),
    _Page('loans:salary-advance', 'Salary Advance'),
    _Page('loans:requests', 'Approvals'),
    _Page('loans:disbursement', 'Disbursement'),
    _Page('loans:payroll-recovery', 'Payroll Recovery'),
    _Page('loans:policies', 'Loan Policies'),
    _Page('loans:configuration', 'Configuration'),
  ]),
  _Module('interaction', 'Interaction', [
    _Page('interaction:chat', 'Chat'),
    _Page('interaction:polls', 'Polls & Surveys'),
  ]),
  _Module('celebration', 'Celebration'),
  _Module('announcements', 'Announcements'),
  _Module('performance', 'Performance', [
    _Page('performance:dashboard', 'Performance Dashboard'),
    _Page('performance:analytics', 'Performance Analytics'),
    _Page('performance:reviews', 'Performance Reviews'),
    _Page('performance:review-cycle', 'Review Cycle'),
    _Page('performance:manager-review', 'Manager Review'),
    _Page('performance:hr-review', 'HR Review'),
    _Page('performance:goals', 'Goals Management'),
    _Page('performance:my-goals', 'My Goals'),
    _Page('performance:goal-progress', 'Goal Progress'),
    _Page('performance:goal-approval', 'Goal Approval'),
    _Page('performance:kra-kpi', 'KRA / KPI'),
    _Page('performance:reports', 'PMS Reports'),
    _Page('performance:settings', 'Settings'),
  ]),
  _Module('lms', 'LMS', [
    _Page('lms:course-library', 'Course Library'),
    _Page('lms:live-sessions', 'Live Sessions'),
    _Page('lms:assessment', 'Assessment Management'),
    _Page('lms:scores-analytics', 'Scores & Analytics'),
    _Page('lms:certification', 'Certification'),
  ]),
  _Module('assetManagement', 'Asset Management', [
    _Page('asset-management:asset-types', 'Asset Types'),
    _Page('asset-management:assets', 'Assets'),
  ]),
  _Module('grievance', 'Grievance', [
    _Page('grievance:grievance', 'Grievance'),
    _Page('grievance:analytics', 'Analytics'),
    _Page('grievance:settings', 'Settings'),
  ]),
];

const _kDesignations = ['Junior', 'Senior', 'Team Lead', 'Manager'];
bool _canScopeToTeam(String d) => const ['team lead', 'team leader', 'manager'].contains(d.trim().toLowerCase());

class ModuleAccessScreen extends StatefulWidget {
  const ModuleAccessScreen({super.key});

  @override
  State<ModuleAccessScreen> createState() => _ModuleAccessScreenState();
}

class _ModuleAccessScreenState extends State<ModuleAccessScreen> {
  final _svc = AdminSettingsService.instance;
  List<Map<String, dynamic>>? _items;
  String? _error;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final l = await _svc.listModuleAccessStaff();
      if (mounted) {
        setState(() {
          _items = l;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = settingsErrorText(e));
    }
  }

  Future<void> _open(Map<String, dynamic> s) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => ModuleAccessDetailScreen(staff: s)),
    );
    if (saved == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final q = _search.trim().toLowerCase();
    final filtered = _items?.where((s) {
      if (q.isEmpty) return true;
      return AdminSettingsService.staffName(s).toLowerCase().contains(q) ||
          (s['employeeId'] ?? '').toString().toLowerCase().contains(q) ||
          (s['designation'] ?? '').toString().toLowerCase().contains(q) ||
          (s['department'] ?? '').toString().toLowerCase().contains(q);
    }).toList();
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: settingsAppBar('Module Access'),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            decoration: settingsInput('Search staff', suffixIcon: const Icon(Icons.search_rounded, size: 20)),
            onChanged: (v) => setState(() => _search = v),
          ),
        ),
        Expanded(
          child: settingsAsyncBody<Map<String, dynamic>>(
            items: filtered,
            error: _error,
            onRefresh: _load,
            emptyText: 'No staff found.',
            builder: (items) => ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (_, i) {
                final s = items[i];
                final ma = AdminSettingsService.asMap(s['moduleAccess']);
                final enabled = ma['enabled'] == true;
                final n = (ma['permissions'] as List?)?.length ?? 0;
                final name = AdminSettingsService.staffName(s);
                return SettingsListCard(
                  leading: CircleAvatar(
                    radius: 20,
                    backgroundColor: AppColors.brandLight,
                    child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.brandDark)),
                  ),
                  title: name,
                  subtitle: [s['employeeId'], s['designation'], s['department']]
                      .where((e) => e != null && e.toString().isNotEmpty)
                      .join(' · '),
                  onTap: () => _open(s),
                  trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textCaption),
                  footer: enabled
                      ? SettingsChip('Access enabled · $n item${n == 1 ? '' : 's'}',
                          color: AppColors.success, background: AppColors.successBg)
                      : const SettingsChip('No admin access'),
                );
              },
            ),
          ),
        ),
      ]),
    );
  }
}

class _Rights {
  _Rights({this.view = false, this.add = false, this.edit = false});
  bool view;
  bool add;
  bool edit;
  bool get any => view || add || edit;
}

class ModuleAccessDetailScreen extends StatefulWidget {
  const ModuleAccessDetailScreen({super.key, required this.staff});
  final Map<String, dynamic> staff;

  @override
  State<ModuleAccessDetailScreen> createState() => _ModuleAccessDetailScreenState();
}

class _ModuleAccessDetailScreenState extends State<ModuleAccessDetailScreen> {
  final _svc = AdminSettingsService.instance;
  String get _staffId => AdminSettingsService.idOf(widget.staff);

  bool _loading = true;
  String? _error;
  bool _saving = false;

  bool _enabled = false;
  final Map<String, _Rights> _rights = {};
  final Map<String, String> _scopes = {};
  final Set<String> _expanded = {};
  List<Map<String, dynamic>> _team = [];
  String? _teamError;

  late String _designation = (widget.staff['designation'] ?? '').toString();
  late final String _originalDesignation = _designation;
  final _password = TextEditingController();
  bool _showPassword = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final access = await _svc.getStaffModuleAccess(_staffId);
      _rights.clear();
      _scopes.clear();
      _enabled = access['enabled'] == true;
      for (final p in AdminSettingsService.asList(access['permissions'])) {
        final key = (p['key'] ?? '').toString();
        if (key.isEmpty) continue;
        _rights[key] = _Rights(view: p['view'] == true, add: p['add'] == true, edit: p['edit'] == true);
        final mod = (p['moduleId'] ?? '').toString();
        if (p['scope'] == 'all') {
          _scopes[mod] = 'all';
        } else {
          _scopes.putIfAbsent(mod, () => 'team');
        }
      }
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = settingsErrorText(e);
        });
      }
      return;
    }
    _loadTeam();
  }

  Future<void> _loadTeam() async {
    try {
      final t = await _svc.getModuleAccessTeam(_staffId);
      if (mounted) {
        setState(() {
          _team = t;
          _teamError = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _teamError = settingsErrorText(e));
    }
  }

  _Rights _r(String key) => _rights.putIfAbsent(key, () => _Rights());

  void _toggleRight(String key, String type) {
    final r = _r(key);
    setState(() {
      if (type == 'view') {
        if (r.view) {
          r
            ..view = false
            ..add = false
            ..edit = false;
        } else {
          r.view = true;
        }
      } else if (type == 'add') {
        r.add = !r.add;
        if (r.add) r.view = true;
      } else {
        r.edit = !r.edit;
        if (r.edit) r.view = true;
      }
      if (r.any) _enabled = true;
    });
  }

  void _toggleModule(_Module m, bool on) {
    setState(() {
      for (final p in m.items) {
        final r = _r(p.key);
        if (on) {
          if (!r.any) r.view = true;
        } else {
          r
            ..view = false
            ..add = false
            ..edit = false;
        }
      }
      if (on) _enabled = true;
    });
  }

  String _scopeOf(String moduleId) => _canScopeToTeam(_designation) ? (_scopes[moduleId] ?? 'team') : 'all';

  Future<void> _save() async {
    final pw = _password.text;
    if (pw.isNotEmpty && pw.length < 6) {
      showSettingsError(context, 'Password must be at least 6 characters');
      return;
    }
    setState(() => _saving = true);
    try {
      final designationChanged = _designation.trim().isNotEmpty && _designation != _originalDesignation;
      if (designationChanged || pw.isNotEmpty) {
        await _svc.updateModuleAccessProfile(
          _staffId,
          designation: designationChanged ? _designation : null,
          password: pw.isNotEmpty ? pw : null,
        );
      }
      final permissions = <Map<String, dynamic>>[
        for (final m in _kModules)
          for (final p in m.items)
            if (_rights[p.key]?.any ?? false)
              {
                'key': p.key,
                'moduleId': m.id,
                'label': p.label,
                'view': _rights[p.key]!.view,
                'add': _rights[p.key]!.add,
                'edit': _rights[p.key]!.edit,
                'scope': _scopeOf(m.id),
              },
      ];
      await _svc.saveStaffModuleAccess(_staffId, enabled: _enabled, permissions: permissions);
      if (!mounted) return;
      showSettingsSuccess(context, 'Changes saved successfully!');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showSettingsError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _pill(String key, String type, String label) {
    final r = _r(key);
    final on = type == 'view' ? r.view : type == 'add' ? r.add : r.edit;
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: ChoiceChip(
        label: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: on ? AppColors.brandDark : AppColors.textSecondary)),
        selected: on,
        showCheckmark: false,
        visualDensity: VisualDensity.compact,
        selectedColor: AppColors.brandLight,
        backgroundColor: AppColors.surface,
        side: BorderSide(color: on ? AppColors.brandBorder : const Color(0xFFE2E5EA)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        onSelected: (_) => _toggleRight(key, type),
      ),
    );
  }

  Widget _itemRow(_Page p) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Expanded(child: Text(p.label, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: AppColors.textPrimary))),
          _pill(p.key, 'view', 'View'),
          _pill(p.key, 'add', 'Add'),
          _pill(p.key, 'edit', 'Edit'),
        ]),
      );

  Widget _moduleCard(_Module m) {
    final active = m.items.where((p) => _rights[p.key]?.any ?? false).length;
    final all = active == m.items.length;
    final open = _expanded.contains(m.id);
    final scopeable = _canScopeToTeam(_designation);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: active > 0 ? AppColors.brandBorder : const Color(0xFFECEEF1)),
        boxShadow: kSoftCardShadow,
      ),
      child: Column(children: [
        ListTile(
          contentPadding: const EdgeInsets.only(left: 4, right: 8),
          leading: Checkbox(
            value: all ? true : (active > 0 ? null : false),
            tristate: true,
            activeColor: AppColors.primary,
            onChanged: (_) => _toggleModule(m, !all),
          ),
          title: Text(m.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: AppColors.textPrimary)),
          subtitle: Text(m.pages.isEmpty ? (active > 0 ? 'Granted' : 'Not granted') : '$active / ${m.pages.length} sub-modules enabled',
              style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
          trailing: Icon(open ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: AppColors.textSecondary),
          onTap: () => setState(() => open ? _expanded.remove(m.id) : _expanded.add(m.id)),
        ),
        if (open)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(children: [
              if (scopeable)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(children: [
                    const Text('Scope', style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                    const SizedBox(width: 10),
                    for (final s in const [('team', 'Team Mate'), ('all', 'All Staff')])
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(s.$2, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500)),
                          selected: _scopeOf(m.id) == s.$1,
                          selectedColor: AppColors.brandLight,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                          visualDensity: VisualDensity.compact,
                          onSelected: (_) => setState(() => _scopes[m.id] = s.$1),
                        ),
                      ),
                  ]),
                ),
              for (final p in m.items) _itemRow(p),
            ]),
          ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.staff;
    final designations = (_designation.isEmpty || _kDesignations.contains(_designation))
        ? _kDesignations
        : [_designation, ..._kDesignations];
    final total = _kModules.fold<int>(0, (a, m) => a + m.items.length);
    final granted = _rights.values.where((r) => r.any).length;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: settingsAppBar(AdminSettingsService.staffName(s)),
      body: _loading
          ? const SettingsLoading()
          : _error != null
              ? SettingsErrorView(message: _error!, onRetry: _load)
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                  children: [
                    const SettingsSectionTitle('User details'),
                    SettingsListCard(
                      leading: settingsIconTile(Icons.person_outline_rounded),
                      title: AdminSettingsService.staffName(s),
                      subtitle: [s['employeeId'], s['email'], s['phoneNumber'], s['department']]
                          .where((e) => e != null && e.toString().isNotEmpty)
                          .join(' · '),
                    ),
                    const SizedBox(height: 12),
                    SettingsDropdown<String>(
                      label: 'Designation',
                      value: _designation.isEmpty ? null : _designation,
                      items: [for (final d in designations) DropdownMenuItem(value: d, child: Text(d))],
                      onChanged: (v) => setState(() => _designation = v ?? _designation),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _password,
                      obscureText: !_showPassword,
                      decoration: settingsInput(
                        'New password (leave blank to keep)',
                        suffixIcon: IconButton(
                          tooltip: _showPassword ? 'Hide password' : 'Show password',
                          icon: Icon(_showPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20),
                          onPressed: () => setState(() => _showPassword = !_showPassword),
                        ),
                      ),
                    ),
                    SettingsSectionTitle('Team (${_team.length})'),
                    if (_teamError != null)
                      Row(children: [
                        Expanded(child: Text(_teamError!, style: const TextStyle(color: AppColors.error, fontSize: 12.5))),
                        TextButton(onPressed: _loadTeam, child: const Text('Retry')),
                      ])
                    else if (_team.isEmpty)
                      const Text('No one reports to this person.', style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5))
                    else
                      Wrap(spacing: 6, runSpacing: 6, children: [
                        for (final m in _team) SettingsChip('${m['name']}${(m['designation'] ?? '').toString().isEmpty ? '' : ' · ${m['designation']}'}'),
                      ]),
                    const SettingsSectionTitle('Module access'),
                    SettingsFormCard(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4), children: [
                      SettingsSwitchTile(
                        title: 'Admin module access',
                        subtitle: '$granted of $total items granted',
                        value: _enabled,
                        onChanged: (v) => setState(() => _enabled = v),
                      ),
                    ]),
                    const SizedBox(height: 12),
                    if (!_canScopeToTeam(_designation))
                      const Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: Text('Access is granted across all staff. Team Leads and Managers can be limited to their team.',
                            style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                      ),
                    for (final m in _kModules) _moduleCard(m),
                  ],
                ),
      bottomNavigationBar: _loading || _error != null ? null : SettingsSaveBar(saving: _saving, onSave: _save, label: 'Save changes'),
    );
  }
}
