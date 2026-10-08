// One employee's salary for one month: attendance summary, earnings and deductions breakdown.
// GET/PUT /admin/staff/overview/detail/:staffId?month. Editing works on a draft of the rows;
// Gross / Deductions / Net are re-derived from the rows, and loan EMI lines stay locked because
// the server recomputes them on every save. Generate Payslip posts /admin/staff/payroll/generate.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../config/app_colors.dart';
import '../../../services/admin_salary_service.dart';
import '../../../utils/snackbar_utils.dart';
import 'admin_salary_ui.dart';

class AdminSalaryOverviewDetailScreen extends StatefulWidget {
  final String staffId;
  final String staffName;

  /// "August 2026"; defaults to the current month.
  final String? initialMonth;

  const AdminSalaryOverviewDetailScreen({
    super.key,
    required this.staffId,
    required this.staffName,
    this.initialMonth,
  });

  @override
  State<AdminSalaryOverviewDetailScreen> createState() => _AdminSalaryOverviewDetailScreenState();
}

class _EarningRow {
  final TextEditingController label;
  final TextEditingController fixed;
  final TextEditingController earned;
  _EarningRow(String l, num f, num e)
      : label = TextEditingController(text: l),
        fixed = TextEditingController(text: _num(f)),
        earned = TextEditingController(text: _num(e));
  void dispose() {
    label.dispose();
    fixed.dispose();
    earned.dispose();
  }
}

class _DeductionRow {
  final TextEditingController label;
  final TextEditingController value;
  final bool locked;
  _DeductionRow(String l, num v, this.locked)
      : label = TextEditingController(text: l),
        value = TextEditingController(text: _num(v));
  void dispose() {
    label.dispose();
    value.dispose();
  }
}

String _num(num v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

/// Loan EMI lines belong to the loan; the server drops and recomputes them on every save.
bool _isLoanLine(String label) => RegExp(r'^(Loan EMI|Advance Recovery) - ').hasMatch(label);

class _AdminSalaryOverviewDetailScreenState extends State<AdminSalaryOverviewDetailScreen> {
  late DateTime _month;
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _detail;
  bool _editing = false;
  bool _saving = false;
  bool _generating = false;
  List<_EarningRow> _earnings = [];
  List<_DeductionRow> _deductions = [];
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = AdminUi.parseMonthLabel(widget.initialMonth) ?? DateTime(now.year, now.month, 1);
    _load();
  }

  @override
  void dispose() {
    _disposeDraft();
    super.dispose();
  }

  void _disposeDraft() {
    for (final r in _earnings) {
      r.dispose();
    }
    for (final r in _deductions) {
      r.dispose();
    }
    _earnings = [];
    _deductions = [];
  }

  String get _monthLabel => AdminUi.monthLabel(_month);

  Future<void> _load() async {
    final req = ++_requestId;
    setState(() {
      _loading = true;
      _error = null;
    });
    final r = await AdminSalaryService.instance.getOverviewDetail(widget.staffId, _monthLabel);
    if (!mounted || req != _requestId) return;
    setState(() {
      _loading = false;
      if (r['success'] == true) {
        _detail = Map<String, dynamic>.from(r['data'] as Map);
        _cancelEdit();
      } else {
        _detail = null;
        _error = r['message']?.toString() ?? 'Could not load the salary overview.';
      }
    });
  }

  List<Map<String, dynamic>> _list(String key) => (_detail?[key] is List)
      ? (_detail![key] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
      : <Map<String, dynamic>>[];

  void _startEdit() {
    _disposeDraft();
    _earnings = _list('earningsBreakdown')
        .map((e) => _EarningRow((e['label'] ?? '').toString(), AdminUi.toDouble(e['fixed']), AdminUi.toDouble(e['earned'])))
        .toList();
    _deductions = _list('deductionsBreakdown').map((d) {
      final label = (d['label'] ?? '').toString();
      return _DeductionRow(label, AdminUi.toDouble(d['value']), _isLoanLine(label));
    }).toList();
    setState(() => _editing = true);
  }

  void _cancelEdit() {
    _disposeDraft();
    _editing = false;
  }

  double _amount(TextEditingController c) => (double.tryParse(c.text.trim()) ?? 0).clamp(0, double.infinity).toDouble();

  double get _draftGross => _earnings.fold(0, (s, r) => s + _amount(r.earned));
  double get _draftDeductions => _deductions.fold(0, (s, r) => s + _amount(r.value));

  Future<void> _save() async {
    if (_detail == null) return;
    if (_earnings.any((r) => r.label.text.trim().isEmpty) || _deductions.any((r) => r.label.text.trim().isEmpty)) {
      SnackBarUtils.showSnackBar(context, 'Every row needs a label.', isError: true);
      return;
    }
    final gross = _draftGross;
    final deductions = _draftDeductions;
    final net = (gross - deductions) < 0 ? 0.0 : gross - deductions;
    final body = <String, dynamic>{
      'earningsBreakdown': _earnings
          .map((r) => {'label': r.label.text.trim(), 'fixed': _amount(r.fixed), 'earned': _amount(r.earned)})
          .toList(),
      'deductionsBreakdown':
          _deductions.map((r) => {'label': r.label.text.trim(), 'value': _amount(r.value)}).toList(),
      'gross': gross,
      'deductions': deductions,
      'net': net,
      'dueAmount': net,
      for (final k in ['payableDays', 'presentDays', 'absentDays', 'halfDays', 'leaves', 'hoursWorked', 'otHours', 'totalFineHours'])
        if (_detail![k] != null) k: _detail![k],
    };
    setState(() => _saving = true);
    final r = await AdminSalaryService.instance.updateOverviewDetail(widget.staffId, _monthLabel, body);
    if (!mounted) return;
    setState(() => _saving = false);
    if (r['success'] == true) {
      setState(() {
        final saved = Map<String, dynamic>.from(r['data'] as Map);
        // The PUT answers with the stored record, which does not carry isGenerated.
        saved['isGenerated'] = _detail?['isGenerated'];
        _detail = saved;
        _cancelEdit();
      });
      SnackBarUtils.showSnackBar(context, 'Salary overview for $_monthLabel updated successfully.');
    } else {
      SnackBarUtils.showSnackBar(context, r['message']?.toString() ?? 'Could not update the salary overview.', isError: true);
    }
  }

  Future<void> _generate() async {
    final ok = await adminConfirm(
      context,
      title: 'Generate payslip',
      message: 'Generate the $_monthLabel payslip for ${widget.staffName}? Loan EMIs shown here are recovered when it is generated.',
      confirmLabel: 'Generate',
    );
    if (!ok || !mounted) return;
    setState(() => _generating = true);
    final r = await AdminSalaryService.instance.generatePayslip(widget.staffId, _monthLabel);
    if (!mounted) return;
    setState(() => _generating = false);
    if (r['success'] == true) {
      SnackBarUtils.showSnackBar(context, 'Payslip generated for $_monthLabel.');
      _load();
    } else {
      SnackBarUtils.showSnackBar(context, r['message']?.toString() ?? 'Could not generate the payslip.', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_editing,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final discard = await adminConfirm(context,
            title: 'Discard changes?', message: 'Your edits to this breakdown have not been saved.', confirmLabel: 'Discard', destructive: true);
        if (!discard || !mounted) return;
        setState(_cancelEdit);
        Navigator.of(this.context).pop();
      },
      child: Scaffold(
        backgroundColor: AdminUi.bg,
        appBar: AdminUi.appBar(widget.staffName, actions: [
          if (_detail != null && !_editing && !_loading)
            IconButton(onPressed: _startEdit, icon: const Icon(Icons.edit_outlined), tooltip: 'Edit breakdown'),
        ]),
        bottomNavigationBar: _editing ? _editBar() : null,
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            Center(
              child: AdminMonthSwitcher(
                month: _month,
                onChanged: (m) {
                  if (_editing) {
                    SnackBarUtils.showSnackBar(context, 'Save or cancel your edits first.', isError: true);
                    return;
                  }
                  setState(() => _month = m);
                  _load();
                },
              ),
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Padding(padding: EdgeInsets.only(top: 80), child: AdminLoading())
            else if (_error != null)
              Padding(padding: const EdgeInsets.only(top: 60), child: AdminErrorView(message: _error!, onRetry: _load))
            else if (_detail != null)
              ..._content(),
          ],
        ),
      ),
    );
  }

  Widget _editBar() => SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: const BoxDecoration(color: AppColors.surface, border: Border(top: BorderSide(color: AdminUi.border))),
          child: Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _saving ? null : () => setState(_cancelEdit),
                child: const Text('Cancel'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                style: AdminUi.primaryButton(),
                onPressed: _saving ? null : _save,
                child: _saving
                    ? SizedBox(
                        width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onPrimary))
                    : const Text('Save'),
              ),
            ),
          ]),
        ),
      );

  List<Widget> _content() {
    final d = _detail!;
    final gross = _editing ? _draftGross : AdminUi.toDouble(d['gross']);
    final deductions = _editing ? _draftDeductions : AdminUi.toDouble(d['deductions']);
    final net = _editing ? ((gross - deductions) < 0 ? 0.0 : gross - deductions) : AdminUi.toDouble(d['net']);
    final generated = d['isGenerated'] == true;

    return [
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: AppColors.surfaceDark, borderRadius: BorderRadius.circular(20)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text((d['duration'] ?? _monthLabel).toString(),
                  style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500)),
            ),
            if (d['isManuallyEdited'] == true) const AdminPill('Edited', fg: AppColors.ink, bg: AdminUi.accent),
            const SizedBox(width: 6),
            AdminPill(generated ? 'Payslip generated' : 'Not generated',
                fg: generated ? AdminUi.green : AdminUi.amber, bg: generated ? AdminUi.greenBg : AdminUi.amberBg),
          ]),
          const SizedBox(height: 16),
          const Text('Net Pay', style: TextStyle(color: Colors.white70, fontSize: 12.5)),
          const SizedBox(height: 2),
          Text(AdminUi.money(net, decimals: true),
              style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          Container(height: 1, color: Colors.white12),
          const SizedBox(height: 14),
          Row(children: [
            _darkFigure('Gross', AdminUi.money(gross, decimals: true)),
            _darkFigure('Deductions', AdminUi.money(deductions, decimals: true)),
          ]),
        ]),
      ),
      const SizedBox(height: 16),
      _attendanceCard(d),
      const SizedBox(height: 12),
      _earningsCard(),
      const SizedBox(height: 12),
      _deductionsCard(),
      if (!_editing && !generated) ...[
        const SizedBox(height: 24),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          onPressed: _generating ? null : _generate,
          icon: _generating
              ? SizedBox(
                  width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onPrimary))
              : const Icon(Icons.receipt_long_outlined, size: 20),
          label: const Text('Generate Payslip'),
        ),
      ],
    ];
  }

  Widget _darkFigure(String label, String value) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: Colors.white60, fontSize: 11.5)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14.5)),
        ]),
      );

  Widget _attendanceCard(Map<String, dynamic> d) {
    final items = <(String, String)>[
      ('Payable days', '${d['payableDays'] ?? 0}'),
      ('Present', '${d['presentDays'] ?? 0}'),
      ('Absent', '${d['absentDays'] ?? 0}'),
      ('Half days', '${d['halfDays'] ?? 0}'),
      ('Leaves', '${d['leaves'] ?? 0}'),
      ('Hours worked', '${d['hoursWorked'] ?? '-'}'),
      ('OT hours', '${d['otHours'] ?? '-'}'),
      ('Fine hours', '${d['totalFineHours'] ?? '-'}'),
    ];
    return AdminCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.event_note_outlined, size: 20, color: AdminUi.muted),
          SizedBox(width: 8),
          Text('Attendance', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: AdminUi.ink)),
        ]),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: items
              .map((i) => Container(
                    width: 100,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(color: AdminUi.bg, borderRadius: BorderRadius.circular(12)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(i.$1, style: const TextStyle(fontSize: 11.5, color: AdminUi.muted)),
                      const SizedBox(height: 4),
                      Text(i.$2, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AdminUi.ink)),
                    ]),
                  ))
              .toList(),
        ),
      ]),
    );
  }

  Widget _sectionHeader(String title, {VoidCallback? onAdd}) => Row(children: [
        Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: AdminUi.ink))),
        if (_editing && onAdd != null)
          TextButton.icon(onPressed: onAdd, icon: const Icon(Icons.add_rounded, size: 18), label: const Text('Add row')),
      ]);

  static final _amountFormatters = [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))];

  Widget _amountField(TextEditingController c, String label) => TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: _amountFormatters,
        onChanged: (_) => setState(() {}),
        decoration: AdminUi.input(label, prefix: '₹ '),
      );

  Widget _earningsCard() {
    final rows = _list('earningsBreakdown');
    return AdminCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _sectionHeader('Earnings',
            onAdd: () => setState(() => _earnings.add(_EarningRow('New Earning', 0, 0)))),
        const SizedBox(height: 8),
        if (_editing)
          ..._earnings.asMap().entries.map((e) => Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(children: [
                  Row(children: [
                    Expanded(child: TextField(controller: e.value.label, decoration: AdminUi.input('Label'))),
                    IconButton(
                      tooltip: 'Remove row',
                      icon: const Icon(Icons.delete_outline_rounded, size: 20, color: AdminUi.red),
                      onPressed: () => setState(() => _earnings.removeAt(e.key).dispose()),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(child: _amountField(e.value.fixed, 'Fixed')),
                    const SizedBox(width: 8),
                    Expanded(child: _amountField(e.value.earned, 'Earned')),
                  ]),
                ]),
              ))
        else if (rows.isEmpty)
          const Text('No earnings for this month.', style: TextStyle(color: AdminUi.muted, fontSize: 13))
        else ...[
          const Row(children: [
            Expanded(
                flex: 5,
                child: Text('Component', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AdminUi.muted))),
            Expanded(
                flex: 3,
                child: Text('Fixed',
                    textAlign: TextAlign.right,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AdminUi.muted))),
            Expanded(
                flex: 3,
                child: Text('Earned',
                    textAlign: TextAlign.right,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AdminUi.muted))),
          ]),
          const Divider(height: 20),
          ...rows.map((e) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(children: [
                  Expanded(
                      flex: 5,
                      child: Text((e['label'] ?? '').toString(), style: const TextStyle(fontSize: 13.5, color: AdminUi.ink))),
                  Expanded(
                      flex: 3,
                      child: Text(AdminUi.money(AdminUi.toDouble(e['fixed'])),
                          textAlign: TextAlign.right, style: const TextStyle(fontSize: 13, color: AdminUi.muted))),
                  Expanded(
                      flex: 3,
                      child: Text(AdminUi.money(AdminUi.toDouble(e['earned'])),
                          textAlign: TextAlign.right,
                          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AdminUi.ink))),
                ]),
              )),
        ],
      ]),
    );
  }

  Widget _deductionsCard() {
    final rows = _list('deductionsBreakdown');
    return AdminCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _sectionHeader('Deductions',
            onAdd: () => setState(() => _deductions.add(_DeductionRow('New Deduction', 0, false)))),
        const SizedBox(height: 8),
        if (_editing)
          ..._deductions.asMap().entries.map((e) {
            final row = e.value;
            if (row.locked) {
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(color: AdminUi.bg, borderRadius: BorderRadius.circular(12)),
                child: Row(children: [
                  const Icon(Icons.lock_outline_rounded, size: 16, color: AdminUi.muted),
                  const SizedBox(width: 8),
                  Expanded(child: Text(row.label.text, style: const TextStyle(fontSize: 13.5, color: AdminUi.ink))),
                  Text(AdminUi.money(_amount(row.value)),
                      style: const TextStyle(fontWeight: FontWeight.w600, color: AdminUi.ink)),
                ]),
              );
            }
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(children: [
                Expanded(flex: 3, child: TextField(controller: row.label, decoration: AdminUi.input('Label'))),
                const SizedBox(width: 8),
                Expanded(flex: 2, child: _amountField(row.value, 'Amount')),
                IconButton(
                  tooltip: 'Remove row',
                  icon: const Icon(Icons.delete_outline_rounded, size: 20, color: AdminUi.red),
                  onPressed: () => setState(() => _deductions.removeAt(e.key).dispose()),
                ),
              ]),
            );
          })
        else if (rows.isEmpty)
          const Text('No deductions for this month.', style: TextStyle(color: AdminUi.muted, fontSize: 13))
        else
          ...rows.map((d) {
            final label = (d['label'] ?? '').toString();
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(children: [
                if (_isLoanLine(label)) ...[
                  const Icon(Icons.lock_outline_rounded, size: 14, color: AdminUi.muted),
                  const SizedBox(width: 6),
                ],
                Expanded(child: Text(label, style: const TextStyle(fontSize: 13.5, color: AdminUi.ink))),
                Text(AdminUi.money(AdminUi.toDouble(d['value'])),
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AdminUi.red)),
              ]),
            );
          }),
        if (_editing && _deductions.any((r) => r.locked))
          const Text('Loan EMI lines come from the employee’s loans and are recalculated when you save.',
              style: TextStyle(fontSize: 12, color: AdminUi.muted, height: 1.4)),
      ]),
    );
  }
}
