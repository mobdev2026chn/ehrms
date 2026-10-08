// Loan Policies and Configuration (web loans/pages/LoanSettings.tsx + components/settings/*).
// Both screens read and write the one settings document: GET / PUT /admin/loans/settings.
//   Policies:      General Loan Settings · Loan Policy · Salary Advance Policy
//   Configuration: Loan Types · Interest Types · Approval Levels · Notifications
// Like the web, a save sends the whole draft (sections are replaced whole by the backend),
// with salaryAdvance.enabled mirrored from general.salaryAdvanceEnabled and the payroll
// deduction priority normalised against the current loan types.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../config/app_colors.dart';
import '../../../services/loan_service.dart';
import '../../../utils/error_message_utils.dart';
import '../../../utils/snackbar_utils.dart';
import '../../../widgets/app_tab_loader.dart';
import 'admin_loan_sheets.dart';

enum LoanSettingsGroup { policies, configuration }

const _approvalLevels = ['Manager', 'HR', 'Finance', 'Director'];
const _interestLabels = {'None': 'No Interest', 'Flat': 'Flat Interest', 'Reducing': 'Reducing Balance'};
const _employeeEvents = ['Loan Submitted', 'Loan Approved', 'Loan Rejected', 'Amount Credited', 'EMI Deducted', 'Last EMI Completed'];
const _adminEvents = ['New Loan Request', 'Approval Pending', 'Loan Overdue', 'Payroll Recovery Failed'];

const _tabs = <(String, String, LoanSettingsGroup)>[
  ('general', 'General', LoanSettingsGroup.policies),
  ('loan-policy', 'Loan Policy', LoanSettingsGroup.policies),
  ('salary-advance', 'Salary Advance', LoanSettingsGroup.policies),
  ('loan-types', 'Loan Types', LoanSettingsGroup.configuration),
  ('interest', 'Interest Types', LoanSettingsGroup.configuration),
  ('approval-levels', 'Approval Levels', LoanSettingsGroup.configuration),
  ('notifications', 'Notifications', LoanSettingsGroup.configuration),
];

Map<String, dynamic> _copy(Map<String, dynamic> m) => Map<String, dynamic>.from(jsonDecode(jsonEncode(m)) as Map);
Map<String, dynamic> _map(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
num _num(dynamic v) => v is num ? v : (num.tryParse('$v') ?? 0);
List<String> _strings(dynamic v) => v is List ? v.map((e) => '$e').toList() : <String>[];

class AdminLoanSettingsScreen extends StatefulWidget {
  const AdminLoanSettingsScreen({super.key, this.group = LoanSettingsGroup.policies, this.initialTab});
  final LoanSettingsGroup group;

  /// Tab key, e.g. 'salary-advance'.
  final String? initialTab;

  @override
  State<AdminLoanSettingsScreen> createState() => _AdminLoanSettingsScreenState();
}

class _AdminLoanSettingsScreenState extends State<AdminLoanSettingsScreen> {
  final _service = LoanService();
  Map<String, dynamic>? _base, _draft;
  String? _error;
  bool _saving = false;
  String? _policyTypeId;
  // Bumped after load / save so text fields re-read their initial values.
  int _epoch = 0;

  List<(String, String, LoanSettingsGroup)> get _myTabs => _tabs.where((t) => t.$3 == widget.group).toList();
  String get _title => widget.group == LoanSettingsGroup.policies ? 'Loan Policies' : 'Configuration';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = _normalise(await _service.adminSettings());
      if (!mounted) return;
      setState(() {
        _base = d;
        _draft = _copy(d);
        _error = null;
        _epoch++;
      });
    } catch (e) {
      if (mounted) setState(() => _error = ErrorMessageUtils.toUserFriendlyMessage(e));
    }
  }

  /// Fills sections the backend omitted so every tab can rely on a complete object.
  Map<String, dynamic> _normalise(Map<String, dynamic> d) {
    final out = _copy(d);
    for (final k in ['general', 'salaryAdvance', 'payroll', 'workflow', 'notifications']) {
      out[k] = _map(out[k]);
    }
    out['loanTypes'] = out['loanTypes'] is List ? out['loanTypes'] : <dynamic>[];
    final n = out['notifications'] as Map<String, dynamic>;
    n['channels'] = _map(n['channels']);
    n['employeeEvents'] = _map(n['employeeEvents']);
    n['adminEvents'] = _map(n['adminEvents']);
    final w = out['workflow'] as Map<String, dynamic>;
    w['levels'] = w['levels'] is List ? w['levels'] : <dynamic>[];
    return out;
  }

  bool get _dirty => _draft != null && jsonEncode(_draft) != jsonEncode(_base);

  Map<String, dynamic> get _general => _draft!['general'] as Map<String, dynamic>;
  Map<String, dynamic> get _advance => _draft!['salaryAdvance'] as Map<String, dynamic>;
  List<Map<String, dynamic>> get _types =>
      (_draft!['loanTypes'] as List).whereType<Map>().map((e) => e as Map<String, dynamic>).toList();

  void _edit(VoidCallback fn) => setState(fn);

  // ── Validation (web settingsModel.validateSettings) ──

  List<(String, String)> _problems() {
    final out = <(String, String)>[];
    bool between(num v, num min, num max) => v >= min && v <= max;
    final g = _general;
    if (!between(_num(g['maxActiveLoans']), 1, 20)) out.add(('general', 'Maximum active loans must be 1–20.'));
    if (!between(_num(g['minServiceMonths']), 0, 600)) out.add(('general', 'Minimum service must be 0 or more months.'));
    if (_num(g['minMonthlySalary']) < 0) out.add(('general', 'Minimum salary cannot be negative.'));
    final names = <String>{};
    for (final t in _types) {
      final name = '${t['name'] ?? ''}'.trim();
      final label = name.isEmpty ? 'Untitled loan type' : name;
      if (name.isEmpty) out.add(('loan-types', 'A loan type needs a name.'));
      if (!names.add(name.toLowerCase())) out.add(('loan-types', '$label: another loan type already uses this name.'));
      if (t['enabled'] != true) continue;
      final bad = !(_num(t['maxAmount']) > 0) ||
          !between(_num(t['minServiceMonths']), 0, 600) ||
          (t['interestMethod'] != 'None' && !between(_num(t['interestRate']), 0.01, 36)) ||
          !between(_num(t['minTenure']), 1, 120) ||
          !between(_num(t['maxTenure']), 1, 120) ||
          _num(t['maxTenure']) < _num(t['minTenure']) ||
          _strings(t['approvalFlow']).isEmpty;
      if (bad) out.add(('loan-policy', '$label has invalid fields (amount, tenure, interest or approval).'));
    }
    final a = _advance;
    if (!between(_num(a['maxPctOfNet']), 1, 100)) out.add(('salary-advance', 'Maximum advance must be 1–100% of net.'));
    if (!between(_num(a['interestRate']), 0, 36)) out.add(('salary-advance', 'Advance interest must be 0–36% p.a.'));
    if (!between(_num(a['maxSplitMonths']), 1, 3)) out.add(('salary-advance', 'Maximum split must be 1–3 months.'));
    if (_strings(a['approvalFlow']).isEmpty) out.add(('salary-advance', 'Select at least one advance approval level.'));
    final allowed = a['allowSplitRecovery'] == true ? _num(a['maxSplitMonths']) : 1;
    final def = a['defaultRecovery'] == '3 Months' ? 3 : (a['defaultRecovery'] == '2 Months' ? 2 : 1);
    if (def > allowed) out.add(('salary-advance', 'Default recovery exceeds the split limit.'));
    if (_strings(g['enabledInterestMethods']).isEmpty) out.add(('interest', 'Enable at least one interest type.'));
    final levels = (_draft!['workflow']['levels'] as List).whereType<Map>();
    if (!levels.any((l) => l['enabled'] == true)) out.add(('approval-levels', 'Enable at least one approval level.'));
    return out;
  }

  Future<void> _save() async {
    final problems = _problems();
    if (problems.isNotEmpty) {
      final first = problems.first;
      final tab = _tabs.firstWhere((t) => t.$1 == first.$1);
      SnackBarUtils.showSnackBar(
          context, '${first.$2}${tab.$3 != widget.group ? ' (fix it under ${tab.$2})' : ''}',
          isError: true);
      return;
    }
    final toSave = _copy(_draft!);
    (toSave['salaryAdvance'] as Map)['enabled'] = _general['salaryAdvanceEnabled'] == true;
    // Payroll deduction order: kept entries in order, deleted types dropped, new ones appended.
    final typeNames = _types.map((t) => '${t['name'] ?? ''}'.trim()).where((s) => s.isNotEmpty).toList();
    final known = {'Salary Advance', ...typeNames};
    final kept = _strings((toSave['payroll'] as Map)['priority']).toSet().where(known.contains).toList();
    (toSave['payroll'] as Map)['priority'] = [...kept, ...['Salary Advance', ...typeNames].where((n) => !kept.contains(n))];

    setState(() => _saving = true);
    try {
      final saved = _normalise(await _service.adminUpdateSettings(toSave));
      if (!mounted) return;
      setState(() {
        _base = saved;
        _draft = _copy(saved);
        _saving = false;
        _epoch++;
      });
      SnackBarUtils.showSnackBar(context, '$_title saved.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      SnackBarUtils.showSnackBar(context, ErrorMessageUtils.toUserFriendlyMessage(e), isError: true);
    }
  }

  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text('Your unsaved settings will be lost.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep editing')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Discard')),
        ],
      ),
    );
    return ok == true;
  }

  // ── Field helpers ──

  Widget _section(String title, List<Widget> children, {String? subtitle}) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFECEEF1)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(subtitle, style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
            ],
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      );

  Widget _switch(String label, bool value, ValueChanged<bool> onChanged, {String? subtitle}) => SwitchListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        title: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.textPrimary)),
        subtitle: subtitle == null
            ? null
            : Text(subtitle, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        value: value,
        onChanged: (v) => _edit(() => onChanged(v)),
      );

  Widget _number(String id, String label, num value, ValueChanged<num> onChanged,
          {String? suffix, bool decimal = false, String? helper}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(
          key: ValueKey('$_epoch-$id'),
          initialValue: decimal ? '$value' : value.round().toString(),
          keyboardType: TextInputType.numberWithOptions(decimal: decimal),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(decimal ? r'[0-9.]' : r'[0-9]'))],
          decoration: InputDecoration(labelText: label, suffixText: suffix, helperText: helper),
          onChanged: (v) => _edit(() => onChanged(num.tryParse(v) ?? 0)),
        ),
      );

  Widget _text(String id, String label, String value, ValueChanged<String> onChanged, {int maxLines = 1}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(
          key: ValueKey('$_epoch-$id'),
          initialValue: value,
          maxLines: maxLines,
          decoration: InputDecoration(labelText: label, alignLabelWithHint: maxLines > 1),
          onChanged: (v) => _edit(() => onChanged(v)),
        ),
      );

  Widget _levels(List<String> flow, ValueChanged<List<String>> onChanged) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final l in _approvalLevels)
            FilterChip(
              label: Text(l,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: flow.contains(l) ? FontWeight.w600 : FontWeight.w500,
                      color: AppColors.textPrimary)),
              selected: flow.contains(l),
              onSelected: (on) => _edit(() {
                final next = {...flow};
                on ? next.add(l) : next.remove(l);
                onChanged(_approvalLevels.where(next.contains).toList());
              }),
            ),
        ],
      );

  // ── Tabs ──

  Widget _generalTab() {
    final g = _general;
    return ListView(padding: const EdgeInsets.all(16), children: [
      _section('Module', [
        _switch('Enable loan module', g['loanModuleEnabled'] == true, (v) => g['loanModuleEnabled'] = v),
        _switch('Enable salary advance', g['salaryAdvanceEnabled'] == true, (v) => g['salaryAdvanceEnabled'] = v),
      ]),
      _section('Eligibility', [
        _number('g-maxActive', 'Maximum active loans', _num(g['maxActiveLoans']), (v) => g['maxActiveLoans'] = v),
        _number('g-minService', 'Minimum service period', _num(g['minServiceMonths']), (v) => g['minServiceMonths'] = v,
            suffix: 'months'),
        _number('g-minSalary', 'Minimum monthly salary', _num(g['minMonthlySalary']), (v) => g['minMonthlySalary'] = v,
            suffix: '₹'),
        _switch('Probation employees allowed', g['allowProbation'] == true, (v) => g['allowProbation'] = v),
        _switch('Notice period employees allowed', g['allowNoticePeriod'] == true, (v) => g['allowNoticePeriod'] = v),
      ]),
      _section('Company loan policy', [
        _text('g-policy', 'Policy text shown to employees', '${g['policyText'] ?? ''}', (v) => g['policyText'] = v,
            maxLines: 8),
      ]),
    ]);
  }

  Widget _loanPolicyTab() {
    final types = _types;
    if (types.isEmpty) {
      return adminLoanEmptyView(Icons.category_outlined,
          'No loan types yet. Add one under Configuration → Loan Types.');
    }
    final t = types.firstWhere((x) => x['id'] == _policyTypeId, orElse: () => types.first);
    final id = '${t['id']}';
    final method = '${t['interestMethod'] ?? 'None'}';
    return ListView(padding: const EdgeInsets.all(16), children: [
      DropdownButtonFormField<String>(
        initialValue: id,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Loan type'),
        items: [
          for (final x in types)
            DropdownMenuItem(
              value: '${x['id']}',
              child: Text('${(x['name'] ?? '').toString().isEmpty ? 'Untitled' : x['name']}${x['enabled'] == true ? '' : ' (disabled)'}'),
            ),
        ],
        onChanged: (v) => setState(() => _policyTypeId = v),
      ),
      const SizedBox(height: 12),
      _section('Limits', [
        _number('$id-maxAmount', 'Maximum amount', _num(t['maxAmount']), (v) => t['maxAmount'] = v, suffix: '₹'),
        _number('$id-minService', 'Minimum service', _num(t['minServiceMonths']), (v) => t['minServiceMonths'] = v,
            suffix: 'months'),
        _number('$id-minTenure', 'Minimum EMI', _num(t['minTenure']), (v) => t['minTenure'] = v, suffix: 'months'),
        _number('$id-maxTenure', 'Maximum EMI', _num(t['maxTenure']), (v) => t['maxTenure'] = v, suffix: 'months'),
      ]),
      _section('Interest', [
        DropdownButtonFormField<String>(
          key: ValueKey('$_epoch-$id-method'),
          initialValue: _interestLabels.containsKey(method) ? method : 'None',
          decoration: const InputDecoration(labelText: 'Interest type'),
          items: [for (final e in _interestLabels.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
          onChanged: (v) => _edit(() {
            t['interestMethod'] = v ?? 'None';
            if (v == 'None') t['interestRate'] = 0;
          }),
        ),
        if (method != 'None')
          _number('$id-rate', 'Interest % per year', _num(t['interestRate']), (v) => t['interestRate'] = v,
              decimal: true, suffix: '%'),
      ]),
      _section('Rules', [
        _switch('Allow foreclosure', t['allowForeclosure'] == true, (v) => t['allowForeclosure'] = v),
        _switch('Require documents', t['requiresDocuments'] == true, (v) => t['requiresDocuments'] = v),
        _switch('Allow during probation', t['allowProbation'] == true, (v) => t['allowProbation'] = v),
      ]),
      _section('Approval workflow', [
        _levels(_strings(t['approvalFlow']), (v) => t['approvalFlow'] = v),
      ]),
    ]);
  }

  Widget _advanceTab() {
    final a = _advance;
    final split = a['allowSplitRecovery'] == true;
    final recoveries = ['Next Salary', '2 Months', '3 Months'];
    final def = recoveries.contains(a['defaultRecovery']) ? '${a['defaultRecovery']}' : 'Next Salary';
    return ListView(padding: const EdgeInsets.all(16), children: [
      if (_general['salaryAdvanceEnabled'] != true)
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(color: AppColors.errorBg, borderRadius: BorderRadius.circular(12)),
          child: const Row(
            children: [
              Icon(Icons.info_outline_rounded, size: 18, color: AppColors.error),
              SizedBox(width: 8),
              Expanded(
                child: Text('Salary advance is switched off under General.',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.error)),
              ),
            ],
          ),
        ),
      _section('Amount', [
        _number('sa-pct', 'Maximum advance', _num(a['maxPctOfNet']), (v) => a['maxPctOfNet'] = v, suffix: '% of net'),
        _number('sa-cap', 'Maximum amount cap', _num(a['maxAmountCap']), (v) => a['maxAmountCap'] = v,
            suffix: '₹', helper: '0 = no cap'),
        _number('sa-rate', 'Interest', _num(a['interestRate']), (v) => a['interestRate'] = v, decimal: true, suffix: '% p.a.'),
        _number('sa-peryear', 'Advances per year', _num(a['maxAdvancesPerYear']), (v) => a['maxAdvancesPerYear'] = v),
        _number('sa-service', 'Minimum service', _num(a['minServiceMonths']), (v) => a['minServiceMonths'] = v,
            suffix: 'months'),
        _number('sa-cutoff', 'Payroll cut-off day', _num(a['cutoffDay']), (v) => a['cutoffDay'] = v),
      ]),
      _section('Recovery', [
        DropdownButtonFormField<String>(
          key: ValueKey('$_epoch-sa-def'),
          initialValue: def,
          decoration: const InputDecoration(labelText: 'Default recovery'),
          items: [for (final r in recoveries) DropdownMenuItem(value: r, child: Text(r))],
          onChanged: (v) => _edit(() => a['defaultRecovery'] = v ?? def),
        ),
        _switch('Allow split recovery', split, (v) => a['allowSplitRecovery'] = v),
        if (split)
          _number('sa-split', 'Maximum split', _num(a['maxSplitMonths']), (v) => a['maxSplitMonths'] = v,
              suffix: 'months (1–3)'),
      ]),
      _section('Approval', [
        _levels(_strings(a['approvalFlow']), (v) => a['approvalFlow'] = v),
      ]),
    ]);
  }

  String _codeFor(String name, List<Map<String, dynamic>> others) {
    final taken = others.map((o) => '${o['code'] ?? ''}'.toUpperCase()).toSet();
    var base = name.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    base = (base.length > 3 ? base.substring(0, 3) : base).toUpperCase();
    if (base.isEmpty) base = 'LT';
    if (base.length < 2) base = base.padRight(2, 'X');
    var code = base;
    for (var i = 2; taken.contains(code); i++) {
      code = '$base$i';
      if (code.length > 6) code = code.substring(0, 6);
    }
    return code;
  }

  Future<void> _addOrRenameType([Map<String, dynamic>? existing]) async {
    final ctrl = TextEditingController(text: existing?['name']?.toString() ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing == null ? 'Add loan type' : 'Rename loan type'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Name', hintText: 'e.g. Marriage Loan'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    ctrl.dispose();
    if (name == null || name.isEmpty) return;
    final others = _types.where((t) => !identical(t, existing)).toList();
    if (others.any((o) => '${o['name']}'.trim().toLowerCase() == name.toLowerCase())) {
      if (mounted) SnackBarUtils.showSnackBar(context, 'Another loan type already uses this name.', isError: true);
      return;
    }
    _edit(() {
      if (existing != null) {
        existing['name'] = name;
        return;
      }
      // Starts disabled with zero limits (web blankLoanType): nobody can apply until its policy is set.
      (_draft!['loanTypes'] as List).add(<String, dynamic>{
        'id': 'lt-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}',
        'name': name,
        'code': _codeFor(name, others),
        'enabled': false,
        'description': '',
        'maxAmount': 0,
        'maxAmountBasis': 'Fixed',
        'maxAmountMultiple': 2,
        'minServiceMonths': _num(_general['minServiceMonths']),
        'interestMethod': 'None',
        'interestRate': 0,
        'minTenure': 0,
        'maxTenure': 0,
        'tenureOptions': <int>[],
        'requiresDocuments': false,
        'documentTypes': <String>[],
        'allowProbation': false,
        'allowForeclosure': true,
        'approvalFlow': ['Manager', 'HR'],
      });
    });
  }

  Widget _loanTypesTab() {
    final types = _types;
    return ListView(padding: const EdgeInsets.all(16), children: [
      _section('Loan types', [
        if (types.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('No loan types yet.', style: TextStyle(color: AppColors.textSecondary)),
          ),
        for (final t in types)
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.account_balance_wallet_outlined, size: 20, color: AppColors.primaryText),
            ),
            title: Text('${(t['name'] ?? '').toString().isEmpty ? 'Untitled' : t['name']}',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            subtitle: Text('${t['code'] ?? ''}', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            onTap: () => _addOrRenameType(t),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Switch(
                  value: t['enabled'] == true,
                  onChanged: (v) => _edit(() => t['enabled'] = v),
                ),
                IconButton(
                  tooltip: 'Delete',
                  icon: const Icon(Icons.delete_outline_rounded, size: 20, color: AppColors.error),
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Delete loan type?'),
                        content: Text('"${t['name']}" will be removed when you save. Existing loans keep their type.'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
                        ],
                      ),
                    );
                    if (ok == true) _edit(() => (_draft!['loanTypes'] as List).remove(t));
                  },
                ),
              ],
            ),
          ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => _addOrRenameType(),
          icon: const Icon(Icons.add_rounded, size: 20),
          label: const Text('Add loan type'),
        ),
        const SizedBox(height: 12),
        const Text('A new type starts disabled. Set its limits under Loan Policies → Loan Policy, then enable it here.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.4)),
      ]),
    ]);
  }

  Widget _interestTab() {
    final enabled = _strings(_general['enabledInterestMethods']);
    return ListView(padding: const EdgeInsets.all(16), children: [
      _section('Interest types', subtitle: 'Methods an approver can choose when approving a loan.', [
        for (final e in _interestLabels.entries)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(e.value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.textPrimary)),
            value: enabled.contains(e.key),
            onChanged: (on) => _edit(() {
              final next = {...enabled};
              on == true ? next.add(e.key) : next.remove(e.key);
              _general['enabledInterestMethods'] = _interestLabels.keys.where(next.contains).toList();
            }),
          ),
      ]),
    ]);
  }

  Widget _approvalTab() {
    final w = _draft!['workflow'] as Map<String, dynamic>;
    final levels = (w['levels'] as List).whereType<Map>().toList();
    return ListView(padding: const EdgeInsets.all(16), children: [
      _section('Approval levels', subtitle: 'Levels available in loan and advance approval flows.', [
        for (final l in levels)
          _switch('${l['level']}', l['enabled'] == true, (v) => l['enabled'] = v),
      ]),
      _section('Director approval', [
        _number('wf-threshold', 'Director approval above', _num(w['directorThreshold']), (v) => w['directorThreshold'] = v,
            suffix: '₹'),
      ]),
    ]);
  }

  Widget _notificationsTab() {
    final n = _draft!['notifications'] as Map<String, dynamic>;
    final channels = n['channels'] as Map<String, dynamic>;
    final emp = n['employeeEvents'] as Map<String, dynamic>;
    final adm = n['adminEvents'] as Map<String, dynamic>;
    return ListView(padding: const EdgeInsets.all(16), children: [
      _section('Channels', [
        for (final (k, label) in const [('email', 'Email'), ('sms', 'SMS'), ('whatsapp', 'WhatsApp')])
          _switch(label, channels[k] == true, (v) => channels[k] = v),
      ]),
      _section('Employee notifications', [
        for (final e in _employeeEvents) _switch(e, emp[e] == true, (v) => v ? emp[e] = true : emp.remove(e)),
      ]),
      _section('Admin notifications', [
        for (final e in _adminEvents) _switch(e, adm[e] == true, (v) => v ? adm[e] = true : adm.remove(e)),
      ]),
    ]);
  }

  Widget _tabBody(String key) => switch (key) {
        'general' => _generalTab(),
        'loan-policy' => _loanPolicyTab(),
        'salary-advance' => _advanceTab(),
        'loan-types' => _loanTypesTab(),
        'interest' => _interestTab(),
        'approval-levels' => _approvalTab(),
        _ => _notificationsTab(),
      };

  @override
  Widget build(BuildContext context) {
    final tabs = _myTabs;
    final initial = tabs.indexWhere((t) => t.$1 == widget.initialTab);
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        if (await _confirmDiscard()) {
          setState(() => _draft = _copy(_base!));
          nav.pop();
        }
      },
      child: DefaultTabController(
        length: tabs.length,
        initialIndex: initial < 0 ? 0 : initial,
        child: Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            title: Text(_title),
            bottom: TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [for (final t in tabs) Tab(text: t.$2)],
            ),
          ),
          body: _error != null && _draft == null
              ? adminLoanErrorView(_error!, _load)
              : _draft == null
                  ? const Center(child: AppTabLoader())
                  : TabBarView(children: [for (final t in tabs) _tabBody(t.$1)]),
          bottomNavigationBar: _draft == null
              ? null
              : Container(
                  decoration: const BoxDecoration(
                    color: AppColors.surface,
                    border: Border(top: BorderSide(color: Color(0xFFECEEF1))),
                  ),
                  child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    child: Row(
                      children: [
                        if (_dirty)
                          TextButton(
                            onPressed: _saving
                                ? null
                                : () => setState(() {
                                      _draft = _copy(_base!);
                                      _epoch++;
                                    }),
                            child: const Text('Discard'),
                          ),
                        const Spacer(),
                        ElevatedButton(
                          onPressed: _saving || !_dirty ? null : _save,
                          style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 24)),
                          child: _saving
                              ? SizedBox(
                                  width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onPrimary))
                              : Text(widget.group == LoanSettingsGroup.policies ? 'Save policy' : 'Save configuration'),
                        ),
                      ],
                    ),
                  ),
                  ),
                ),
        ),
      ),
    );
  }
}
