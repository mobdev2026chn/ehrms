// Salary settings (web: features/admin/staff/settings/Salary):
//   Payable days       GET/POST /admin/staff/payable-days, DELETE /:id
//   Salary components  GET/POST /admin/staff/salary-components, PUT/DELETE /:id
//   Salary templates   CRUD /admin/staff/salary-templates + assign/unassign staff
//   Salary access      GET /admin/staff/salary-access?search=&department=, PUT /:id

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../config/app_colors.dart';
import '../../../services/admin_settings_service.dart';
import 'settings_common.dart';
import 'template_staff_screen.dart';

class SalarySettingsScreen extends StatelessWidget {
  const SalarySettingsScreen({super.key, this.initialTab = 0});
  final int initialTab; // 0 payable days, 1 components, 2 templates, 3 access

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      initialIndex: initialTab,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: settingsAppBar(
          'Salary Settings',
          bottom: settingsTabBar(['Payable Days', 'Components', 'Templates', 'Salary Access'], scrollable: true),
        ),
        body: const TabBarView(children: [_PayableDaysTab(), _ComponentsTab(), _TemplatesTab(), _AccessTab()]),
      ),
    );
  }
}

// ------------------------------------------------------------------ payable

class _PayableDaysTab extends StatefulWidget {
  const _PayableDaysTab();
  @override
  State<_PayableDaysTab> createState() => _PayableDaysTabState();
}

class _PayableDaysTabState extends State<_PayableDaysTab> {
  final _svc = AdminSettingsService.instance;
  List<Map<String, dynamic>>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final l = await _svc.listPayableDays();
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

  Future<void> _add() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _PayableDaysSheet(),
    );
    if (created == true) _load();
  }

  Future<void> _delete(Map<String, dynamic> t) async {
    final ok = await confirmSettingsAction(context, title: 'Delete rule?', message: 'Delete "${t['name']}"?');
    if (!ok || !mounted) return;
    try {
      await _svc.deletePayableDays(AdminSettingsService.idOf(t));
      if (!mounted) return;
      showSettingsSuccess(context, 'Payable days rule deleted');
      setState(() => _items = _items?.where((e) => AdminSettingsService.idOf(e) != AdminSettingsService.idOf(t)).toList());
    } catch (e) {
      if (mounted) showSettingsError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      floatingActionButton: _fab(_add),
      body: settingsAsyncBody<Map<String, dynamic>>(
        items: _items,
        error: _error,
        onRefresh: _load,
        emptyText: 'No payable days rules yet.',
        builder: (items) => ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (_, i) {
            final t = items[i];
            final type = (t['type'] ?? '').toString();
            return SettingsListCard(
              leading: settingsIconTile(Icons.event_note_outlined, size: 40),
              title: (t['name'] ?? '-').toString(),
              subtitle: type == 'Fixed days' ? 'Fixed days · ${t['fixedDays'] ?? '-'} days' : type,
              trailing: IconButton(
                tooltip: 'Delete',
                icon: const Icon(Icons.delete_outline_rounded, color: AppColors.error),
                onPressed: () => _delete(t),
              ),
              footer: activeChip((t['status'] ?? 'Active') == 'Active'),
            );
          },
        ),
      ),
    );
  }
}

class _PayableDaysSheet extends StatefulWidget {
  const _PayableDaysSheet();
  @override
  State<_PayableDaysSheet> createState() => _PayableDaysSheetState();
}

class _PayableDaysSheetState extends State<_PayableDaysSheet> {
  final _name = TextEditingController();
  final _fixed = TextEditingController(text: '26');
  String _type = 'Calendar days';
  String _status = 'Active';
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _fixed.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      showSettingsError(context, 'Please enter a name.');
      return;
    }
    final fixed = int.tryParse(_fixed.text.trim());
    if (_type == 'Fixed days' && (fixed == null || fixed < 1 || fixed > 31)) {
      showSettingsError(context, 'Fixed days must be between 1 and 31.');
      return;
    }
    setState(() => _saving = true);
    try {
      await AdminSettingsService.instance.createPayableDays(name: _name.text.trim(), type: _type, fixedDays: fixed, status: _status);
      if (!mounted) return;
      showSettingsSuccess(context, 'Payable days rule created');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showSettingsError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Add payable days rule', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          const SizedBox(height: 16),
          TextField(controller: _name, decoration: settingsInput('Name *')),
          const SizedBox(height: 12),
          SettingsDropdown<String>(
            label: 'Rule type',
            value: _type,
            items: const [
              DropdownMenuItem(value: 'Calendar days', child: Text('Calendar days')),
              DropdownMenuItem(value: 'Exclude week offs', child: Text('Exclude week offs')),
              DropdownMenuItem(value: 'Fixed days', child: Text('Fixed days')),
            ],
            onChanged: (v) => setState(() => _type = v ?? 'Calendar days'),
          ),
          if (_type == 'Fixed days') ...[
            const SizedBox(height: 12),
            TextField(controller: _fixed, keyboardType: TextInputType.number, decoration: settingsInput('Fixed days *', suffix: 'days')),
          ],
          const SizedBox(height: 12),
          SettingsDropdown<String>(
            label: 'Status',
            value: _status,
            items: const [
              DropdownMenuItem(value: 'Active', child: Text('Active')),
              DropdownMenuItem(value: 'Inactive', child: Text('Inactive')),
            ],
            onChanged: (v) => setState(() => _status = v ?? 'Active'),
          ),
          SettingsSaveBar(saving: _saving, onSave: _save),
        ]),
      ),
    );
  }
}

Widget _fab(VoidCallback onTap) => FloatingActionButton.extended(
      heroTag: null,
      backgroundColor: AppColors.primary,
      foregroundColor: AppColors.onPrimary,
      onPressed: onTap,
      icon: const Icon(Icons.add_rounded),
      label: const Text('Add', style: TextStyle(fontWeight: FontWeight.w700)),
    );

// --------------------------------------------------------------- components

const _kCategories = <String, String>{
  'earnings': 'Earnings',
  'variables': 'Variables',
  'benefits': 'Benefits',
  'allowances': 'Allowances',
};

class _ComponentsTab extends StatefulWidget {
  const _ComponentsTab();
  @override
  State<_ComponentsTab> createState() => _ComponentsTabState();
}

class _ComponentsTabState extends State<_ComponentsTab> {
  final _svc = AdminSettingsService.instance;
  List<Map<String, dynamic>>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final l = await _svc.listSalaryComponents();
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

  Future<void> _edit([Map<String, dynamic>? c]) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ComponentSheet(component: c),
    );
    if (saved == true) _load();
  }

  Future<void> _delete(Map<String, dynamic> c) async {
    final ok = await confirmSettingsAction(context, title: 'Delete component?', message: 'Delete "${c['name']}"?');
    if (!ok || !mounted) return;
    try {
      await _svc.deleteSalaryComponent(AdminSettingsService.idOf(c));
      if (!mounted) return;
      showSettingsSuccess(context, 'Salary component deleted');
      setState(() => _items = _items?.where((e) => AdminSettingsService.idOf(e) != AdminSettingsService.idOf(c)).toList());
    } catch (e) {
      if (mounted) showSettingsError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      floatingActionButton: _fab(() => _edit()),
      body: settingsAsyncBody<Map<String, dynamic>>(
        items: _items,
        error: _error,
        onRefresh: _load,
        emptyText: 'No salary components yet.',
        builder: (items) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
          children: [
            for (final cat in _kCategories.entries) ...[
              SettingsSectionTitle(cat.value),
              ...items.where((c) => c['category'] == cat.key).map((c) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: SettingsListCard(
                      leading: settingsIconTile(c['type'] == 'Percentage' ? Icons.percent_rounded : Icons.currency_rupee_rounded, size: 40),
                      title: (c['name'] ?? '-').toString(),
                      subtitle: c['type'] == 'Percentage' ? '${c['amount']}% · Percentage' : '₹${c['amount']} · Fixed',
                      onTap: () => _edit(c),
                      trailing: PopupMenuButton<String>(
                        tooltip: 'More actions',
                        onSelected: (v) => v == 'edit' ? _edit(c) : _delete(c),
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'edit', child: Text('Edit')),
                          PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: AppColors.error))),
                        ],
                      ),
                    ),
                  )),
              if (!items.any((c) => c['category'] == cat.key))
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text('None', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ComponentSheet extends StatefulWidget {
  const _ComponentSheet({this.component});
  final Map<String, dynamic>? component;
  @override
  State<_ComponentSheet> createState() => _ComponentSheetState();
}

class _ComponentSheetState extends State<_ComponentSheet> {
  late final _name = TextEditingController(text: widget.component?['name']?.toString() ?? '');
  late final _amount = TextEditingController(text: widget.component?['amount']?.toString() ?? '');
  late String _category = widget.component?['category']?.toString() ?? 'earnings';
  late String _type = widget.component?['type']?.toString() ?? 'Fixed';
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = num.tryParse(_amount.text.trim());
    if (_name.text.trim().isEmpty) {
      showSettingsError(context, 'Please enter a component name.');
      return;
    }
    if (amount == null || amount < 0) {
      showSettingsError(context, 'Please enter a valid amount/percentage.');
      return;
    }
    if (_type == 'Percentage' && (amount <= 0 || amount > 100)) {
      showSettingsError(context, 'Percentage must be between 0 and 100.');
      return;
    }
    setState(() => _saving = true);
    try {
      await AdminSettingsService.instance.saveSalaryComponent(
        id: widget.component == null ? null : AdminSettingsService.idOf(widget.component),
        name: _name.text.trim(),
        category: _category,
        type: _type,
        amount: amount,
      );
      if (!mounted) return;
      showSettingsSuccess(context, widget.component == null ? 'Salary component created' : 'Salary component updated');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showSettingsError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(widget.component == null ? 'Add salary component' : 'Edit salary component',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          const SizedBox(height: 16),
          TextField(controller: _name, decoration: settingsInput('Component name *')),
          const SizedBox(height: 12),
          SettingsDropdown<String>(
            label: 'Category',
            value: _category,
            items: [for (final e in _kCategories.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
            onChanged: (v) => setState(() => _category = v ?? 'earnings'),
          ),
          const SizedBox(height: 12),
          SettingsDropdown<String>(
            label: 'Type',
            value: _type,
            items: const [
              DropdownMenuItem(value: 'Fixed', child: Text('Fixed amount')),
              DropdownMenuItem(value: 'Percentage', child: Text('Percentage (%)')),
            ],
            onChanged: (v) => setState(() => _type = v ?? 'Fixed'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: settingsInput(_type == 'Percentage' ? 'Percentage *' : 'Amount *', suffix: _type == 'Percentage' ? '%' : '₹'),
          ),
          SettingsSaveBar(saving: _saving, onSave: _save),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------- templates

class _TemplatesTab extends StatefulWidget {
  const _TemplatesTab();
  @override
  State<_TemplatesTab> createState() => _TemplatesTabState();
}

class _TemplatesTabState extends State<_TemplatesTab> {
  final _svc = AdminSettingsService.instance;
  List<Map<String, dynamic>>? _items;
  String? _error;
  static const _base = AdminSettingsService.salaryTemplatesPath;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final l = await _svc.listTemplates(_base);
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

  Future<void> _edit([Map<String, dynamic>? t]) async {
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => SalaryTemplateFormScreen(templateId: t == null ? null : AdminSettingsService.idOf(t)),
    ));
    if (saved == true) _load();
  }

  Future<void> _staff(Map<String, dynamic> t) async {
    final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => TemplateStaffScreen(
        basePath: _base,
        templateId: AdminSettingsService.idOf(t),
        templateName: (t['title'] ?? 'Salary Template').toString(),
      ),
    ));
    if (changed == true) _load();
  }

  Future<void> _delete(Map<String, dynamic> t) async {
    final ok = await confirmSettingsAction(context, title: 'Delete salary template?', message: 'Delete "${t['title']}"?');
    if (!ok || !mounted) return;
    try {
      await _svc.deleteTemplate(_base, AdminSettingsService.idOf(t));
      if (!mounted) return;
      showSettingsSuccess(context, 'Salary template deleted');
      setState(() => _items = _items?.where((e) => AdminSettingsService.idOf(e) != AdminSettingsService.idOf(t)).toList());
    } catch (e) {
      if (mounted) showSettingsError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      floatingActionButton: _fab(() => _edit()),
      body: settingsAsyncBody<Map<String, dynamic>>(
        items: _items,
        error: _error,
        onRefresh: _load,
        emptyText: 'No salary templates yet.',
        builder: (items) => ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (_, i) {
            final t = items[i];
            final pd = AdminSettingsService.asMap(t['payableDays']);
            final comps = _kCategories.keys.fold<int>(0, (a, k) => a + ((t[k] as List?)?.length ?? 0));
            final count = toInt(t['assignedStaff']) ?? 0;
            return SettingsListCard(
              leading: settingsIconTile(Icons.request_quote_outlined, size: 40),
              title: (t['title'] ?? '-').toString(),
              subtitle: '${pd['name'] ?? 'No payable days rule'} · $comps component${comps == 1 ? '' : 's'}',
              onTap: () => _edit(t),
              trailing: PopupMenuButton<String>(
                tooltip: 'More actions',
                onSelected: (v) {
                  if (v == 'edit') _edit(t);
                  if (v == 'staff') _staff(t);
                  if (v == 'delete') _delete(t);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Edit')),
                  PopupMenuItem(value: 'staff', child: Text('Assigned staff')),
                  PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: AppColors.error))),
                ],
              ),
              footer: InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: () => _staff(t),
                child: SettingsChip('$count staff assigned', color: AppColors.info, background: AppColors.infoBg),
              ),
            );
          },
        ),
      ),
    );
  }
}

class SalaryTemplateFormScreen extends StatefulWidget {
  const SalaryTemplateFormScreen({super.key, this.templateId});
  final String? templateId;

  @override
  State<SalaryTemplateFormScreen> createState() => _SalaryTemplateFormScreenState();
}

class _SalaryTemplateFormScreenState extends State<SalaryTemplateFormScreen> {
  final _svc = AdminSettingsService.instance;
  bool get _isEdit => widget.templateId != null;
  bool _loading = true;
  String? _error;
  bool _saving = false;

  final _title = TextEditingController();
  String? _payableDays;
  final Map<String, Set<String>> _selected = {for (final k in _kCategories.keys) k: <String>{}};
  List<Map<String, dynamic>> _payableOptions = [];
  List<Map<String, dynamic>> _components = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await Future.wait([_svc.listPayableDays(), _svc.listSalaryComponents()]);
      _payableOptions = r[0];
      _components = r[1];
      if (_isEdit) {
        final t = await _svc.getTemplate(AdminSettingsService.salaryTemplatesPath, widget.templateId!);
        _title.text = (t['title'] ?? '').toString();
        _payableDays = t['payableDays'] == null ? null : AdminSettingsService.idOf(t['payableDays']);
        for (final k in _kCategories.keys) {
          _selected[k] = ((t[k] as List?) ?? const []).map(AdminSettingsService.idOf).toSet();
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
    }
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      showSettingsError(context, 'Please enter a template title.');
      return;
    }
    if (_payableDays == null || _payableDays!.isEmpty) {
      showSettingsError(context, 'Please select a payable days rule.');
      return;
    }
    setState(() => _saving = true);
    final body = <String, dynamic>{
      'title': _title.text.trim(),
      'payableDays': _payableDays,
      for (final k in _kCategories.keys) k: _selected[k]!.toList(),
    };
    try {
      if (_isEdit) {
        await _svc.updateTemplate(AdminSettingsService.salaryTemplatesPath, widget.templateId!, body);
      } else {
        await _svc.createTemplate(AdminSettingsService.salaryTemplatesPath, body);
      }
      if (!mounted) return;
      showSettingsSuccess(context, _isEdit ? 'Salary template updated' : 'Salary template created');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showSettingsError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: settingsAppBar(_isEdit ? 'Edit Salary Template' : 'Add Salary Template'),
      body: _loading
          ? const SettingsLoading()
          : _error != null
              ? SettingsErrorView(message: _error!, onRetry: _load)
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                  children: [
                    const SettingsSectionTitle('Template'),
                    SettingsFormCard(children: [
                      TextField(controller: _title, decoration: settingsInput('Title *')),
                      const SizedBox(height: 12),
                      SettingsDropdown<String>(
                        label: 'Payable days rule *',
                        value: _payableDays,
                        items: [
                          for (final p in _payableOptions)
                            DropdownMenuItem(value: AdminSettingsService.idOf(p), child: Text((p['name'] ?? '-').toString())),
                        ],
                        onChanged: (v) => setState(() => _payableDays = v),
                      ),
                      if (_payableOptions.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text('Create a payable days rule first.', style: TextStyle(color: AppColors.error, fontSize: 12.5)),
                        ),
                      const SizedBox(height: 12),
                    ]),
                    for (final cat in _kCategories.entries) ...[
                      SettingsSectionTitle(cat.value),
                      if (!_components.any((c) => c['category'] == cat.key))
                        const Text('No components in this category.', style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
                      for (final c in _components.where((c) => c['category'] == cat.key))
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          activeColor: AppColors.primary,
                          controlAffinity: ListTileControlAffinity.leading,
                          value: _selected[cat.key]!.contains(AdminSettingsService.idOf(c)),
                          title: Text((c['name'] ?? '-').toString(), style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                          subtitle: Text(c['type'] == 'Percentage' ? '${c['amount']}%' : '₹${c['amount']}', style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                          onChanged: (v) => setState(() {
                            final id = AdminSettingsService.idOf(c);
                            v == true ? _selected[cat.key]!.add(id) : _selected[cat.key]!.remove(id);
                          }),
                        ),
                    ],
                  ],
                ),
      bottomNavigationBar: _loading || _error != null ? null : SettingsSaveBar(saving: _saving, onSave: _save),
    );
  }
}

// ------------------------------------------------------------------- access

class _AccessTab extends StatefulWidget {
  const _AccessTab();
  @override
  State<_AccessTab> createState() => _AccessTabState();
}

class _AccessTabState extends State<_AccessTab> {
  final _svc = AdminSettingsService.instance;
  List<Map<String, dynamic>>? _items;
  int _total = 0;
  int _granted = 0;
  String? _error;
  String _search = '';
  String _department = 'All';
  final Set<String> _departments = {};
  final Set<String> _busy = {};
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await _svc.listSalaryAccess(search: _search, department: _department);
      if (!mounted) return;
      setState(() {
        _items = r.staff;
        _total = r.total;
        _granted = r.granted;
        _error = null;
        for (final s in r.staff) {
          final d = (s['department'] ?? '').toString();
          if (d.isNotEmpty) _departments.add(d);
        }
      });
    } catch (e) {
      if (mounted) setState(() => _error = settingsErrorText(e));
    }
  }

  Future<void> _toggle(Map<String, dynamic> s, bool v) async {
    final id = AdminSettingsService.idOf(s);
    setState(() => _busy.add(id));
    try {
      final msg = await _svc.updateSalaryAccess(id, v);
      if (!mounted) return;
      setState(() {
        s['salaryDetailsAccess'] = v;
        _granted += v ? 1 : -1;
      });
      showSettingsSuccess(context, msg ?? (v ? 'Salary details access granted.' : 'Salary details access revoked.'));
    } catch (e) {
      if (mounted) showSettingsError(context, e);
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final depts = ['All', ..._departments.toList()..sort()];
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Row(children: [
          Expanded(
            child: TextField(
              decoration: settingsInput('Search name, ID, email', suffixIcon: const Icon(Icons.search_rounded, size: 20)),
              onChanged: (v) {
                _search = v;
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 400), _load);
              },
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 130,
            child: SettingsDropdown<String>(
              label: 'Department',
              value: _department,
              items: [for (final d in depts) DropdownMenuItem(value: d, child: Text(d, overflow: TextOverflow.ellipsis))],
              onChanged: (v) {
                setState(() {
                  _department = v ?? 'All';
                  _items = null;
                });
                _load();
              },
            ),
          ),
        ]),
      ),
      if (_items != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('$_granted of $_total staff can view their salary details',
                style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
          ),
        ),
      Expanded(
        child: settingsAsyncBody<Map<String, dynamic>>(
          items: _items,
          error: _error,
          onRefresh: _load,
          emptyText: 'No staff found.',
          builder: (items) => ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (_, i) {
              final s = items[i];
              final id = AdminSettingsService.idOf(s);
              return SettingsListCard(
                title: (s['name'] ?? '-').toString(),
                subtitle: [s['employeeId'], s['department'], s['designation']]
                    .where((e) => e != null && e.toString().isNotEmpty)
                    .join(' · '),
                trailing: _busy.contains(id)
                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                    : Switch.adaptive(
                        activeTrackColor: AppColors.primary,
                        value: s['salaryDetailsAccess'] == true,
                        onChanged: (v) => _toggle(s, v),
                      ),
              );
            },
          ),
        ),
      ),
    ]);
  }
}
