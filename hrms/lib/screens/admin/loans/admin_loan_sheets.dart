// Shared admin loan pieces: the Disburse sheet (POST /admin/loans/:id/disburse with
// mode / date / reference / remarks, like the web DisburseModal), the list filter sheet
// (category / loan type / department / branch / date range - the backend's ListQuery) and
// YYYY-MM month helpers.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../config/app_colors.dart';
import '../../../models/loan_models.dart';
import '../../../services/loan_service.dart';
import '../../../utils/error_message_utils.dart';
import '../../../utils/snackbar_utils.dart';
import '../../loans/loan_widgets.dart';

// ── Presentation helpers shared by the admin loan screens ──

/// Centered empty state (64 tinted circle + title + optional message), scrollable so it
/// works inside a RefreshIndicator.
Widget adminLoanEmptyView(IconData icon, String title, {String? message}) => ListView(
      padding: const EdgeInsets.fromLTRB(32, 64, 32, 32),
      children: [
        Center(
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: Icon(icon, size: 30, color: AppColors.primaryText),
          ),
        ),
        const SizedBox(height: 16),
        Text(title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        if (message != null) ...[
          const SizedBox(height: 6),
          Text(message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.45)),
        ],
      ],
    );

/// Error state with a Retry action.
Widget adminLoanErrorView(String message, VoidCallback retry) => ListView(
      padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
      children: [
        Center(
          child: Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(color: AppColors.errorBg, shape: BoxShape.circle),
            child: const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 30),
          ),
        ),
        const SizedBox(height: 16),
        Text(message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, color: AppColors.textSecondary, height: 1.4)),
        const SizedBox(height: 8),
        Center(child: TextButton(onPressed: retry, child: const Text('Retry'))),
      ],
    );

/// White strip under the app bar that holds a search box / filters.
const BoxDecoration adminLoanToolbarDecoration = BoxDecoration(
  color: AppColors.surface,
  border: Border(bottom: BorderSide(color: Color(0xFFECEEF1))),
);

/// Bottom-sheet header: drag handle, title and an optional subtitle.
Widget adminLoanSheetHeader(String title, {String? subtitle}) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(color: const Color(0xFFE2E5EA), borderRadius: BorderRadius.circular(999)),
          ),
        ),
        Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
        ],
        const SizedBox(height: 20),
      ],
    );

// ── Months ──

/// "2026-10"
String loanMonthKey(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}';

/// "Oct 2026"
String loanMonthLabel(String key) {
  final p = key.split('-');
  if (p.length != 2) return key;
  final y = int.tryParse(p[0]), m = int.tryParse(p[1]);
  if (y == null || m == null) return key;
  return DateFormat('MMM yyyy').format(DateTime(y, m));
}

/// Shift a YYYY-MM key by [delta] months.
String loanShiftMonth(String key, int delta) {
  final p = key.split('-');
  final d = DateTime(int.parse(p[0]), int.parse(p[1]) + delta);
  return loanMonthKey(d);
}

/// First payroll month an advance approved today can be recovered from (web defaultRecoveryMonth).
String loanDefaultRecoveryMonth(int cutoffDay) {
  final now = DateTime.now();
  final bump = cutoffDay <= 0 || now.day > cutoffDay ? 1 : 0;
  return loanMonthKey(DateTime(now.year, now.month + bump));
}

/// Dropdown of payroll months from the current month forward (recovery start picker).
class LoanMonthDropdown extends StatelessWidget {
  const LoanMonthDropdown({super.key, required this.value, required this.onChanged, this.label = 'Recovery starts'});
  final String value;
  final ValueChanged<String> onChanged;
  final String label;

  @override
  Widget build(BuildContext context) {
    final start = loanMonthKey(DateTime.now());
    final months = [for (var i = 0; i < 13; i++) loanShiftMonth(start, i)];
    if (!months.contains(value)) months.insert(0, value);
    return DropdownButtonFormField<String>(
      initialValue: value,
      decoration: InputDecoration(labelText: label),
      items: [for (final m in months) DropdownMenuItem(value: m, child: Text(loanMonthLabel(m)))],
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }
}

// ── Disburse ──

/// Opens the disburse sheet for an Approved loan. Records the disbursement and returns the
/// updated loan, or null when cancelled / failed (failures show the backend message).
Future<Loan?> showLoanDisburseSheet(BuildContext context, Loan loan) => showModalBottomSheet<Loan>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      builder: (_) => _DisburseSheet(loan: loan),
    );

class _DisburseSheet extends StatefulWidget {
  const _DisburseSheet({required this.loan});
  final Loan loan;
  @override
  State<_DisburseSheet> createState() => _DisburseSheetState();
}

class _DisburseSheetState extends State<_DisburseSheet> {
  String _mode = 'Bank Transfer';
  DateTime _date = DateTime.now();
  final _ref = TextEditingController();
  final _remarks = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _ref.dispose();
    _remarks.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );
    if (d != null) setState(() => _date = d);
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      final now = DateTime.now();
      final when = DateTime(_date.year, _date.month, _date.day, now.hour, now.minute);
      final l = await LoanService().adminDisburse(
        widget.loan.id,
        mode: _mode,
        date: when,
        reference: _ref.text.trim(),
        remarks: _remarks.text.trim(),
      );
      if (!mounted) return;
      SnackBarUtils.showSnackBar(context, 'Disbursement recorded for ${l.loanNo}.');
      Navigator.of(context).pop(l);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      SnackBarUtils.showSnackBar(context, ErrorMessageUtils.toUserFriendlyMessage(e), isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.loan;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 12, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            adminLoanSheetHeader('Disburse', subtitle: '${l.employee.name} · ${l.loanNo} · ${loanMoney(l.principal)}'),
            DropdownButtonFormField<String>(
              initialValue: _mode,
              decoration: const InputDecoration(labelText: 'Mode'),
              items: const [
                DropdownMenuItem(value: 'Bank Transfer', child: Text('Bank Transfer')),
                DropdownMenuItem(value: 'Cash', child: Text('Cash')),
              ],
              onChanged: (v) => setState(() => _mode = v ?? _mode),
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: _pickDate,
              borderRadius: BorderRadius.circular(12),
              child: InputDecorator(
                decoration: const InputDecoration(labelText: 'Disbursement date', suffixIcon: Icon(Icons.event_outlined, size: 20)),
                child: Text(loanDate(_date)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _ref,
              decoration: InputDecoration(labelText: _mode == 'Cash' ? 'Receipt no. (optional)' : 'Transaction reference (optional)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _remarks,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Remarks (optional)'),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _busy ? null : _submit,
              style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              child: _busy
                  ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onPrimary))
                  : Text('Disburse ${loanMoney(l.principal)}'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── List filters ──

/// The admin list filters the backend's ListQuery understands (besides status and search).
class LoanListFilters {
  const LoanListFilters({this.category, this.loanType, this.department, this.branch, this.from, this.to});
  final String? category; // 'Loan' | 'SalaryAdvance'
  final String? loanType, department, branch;
  final DateTime? from, to;

  int get count => [category, loanType, department, branch, from, to].where((v) => v != null).length;
}

/// Options for the filter sheet: loan types from settings, departments / branches from the
/// dashboard breakdowns. Loaded once per app session.
class _FilterOptions {
  static Future<({List<String> types, List<String> departments, List<String> branches})>? _cache;

  static Future<({List<String> types, List<String> departments, List<String> branches})> load() =>
      _cache ??= _fetch().catchError((Object e) {
        // Do not keep a failed load around.
        _cache = null;
        throw e;
      });

  static Future<({List<String> types, List<String> departments, List<String> branches})> _fetch() async {
    final service = LoanService();
    final results = await Future.wait([service.adminSettings(), service.adminDashboard()]);
    final settings = results[0], dash = results[1];
    List<String> labels(dynamic v) => v is List
        ? v
            .whereType<Map>()
            .map((e) => e['label']?.toString() ?? '')
            .where((s) => s.isNotEmpty && s != 'Unassigned')
            .toSet()
            .toList()
        : <String>[];
    final types = settings['loanTypes'] is List
        ? (settings['loanTypes'] as List)
            .whereType<Map>()
            .map((t) => t['name']?.toString() ?? '')
            .where((s) => s.isNotEmpty)
            .toList()
        : <String>[];
    return (
      types: {...types, 'Salary Advance'}.toList(),
      departments: labels(dash['byDepartment'])..sort(),
      branches: labels(dash['byBranch'])..sort(),
    );
  }
}

Future<LoanListFilters?> showLoanFiltersSheet(BuildContext context, LoanListFilters current, {bool showCategory = true}) =>
    showModalBottomSheet<LoanListFilters>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      builder: (_) => _FiltersSheet(current: current, showCategory: showCategory),
    );

class _FiltersSheet extends StatefulWidget {
  const _FiltersSheet({required this.current, required this.showCategory});
  final LoanListFilters current;
  final bool showCategory;
  @override
  State<_FiltersSheet> createState() => _FiltersSheetState();
}

class _FiltersSheetState extends State<_FiltersSheet> {
  late String? _category = widget.current.category,
      _type = widget.current.loanType,
      _dept = widget.current.department,
      _branch = widget.current.branch;
  late DateTime? _from = widget.current.from, _to = widget.current.to;
  late Future<({List<String> types, List<String> departments, List<String> branches})> _options = _FilterOptions.load();

  Widget _drop(String label, String? value, List<String> options, ValueChanged<String?> onChanged,
      {Map<String, String> labels = const {}}) {
    final opts = [...options];
    if (value != null && !opts.contains(value)) opts.add(value);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String?>(
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        items: [
          const DropdownMenuItem<String?>(value: null, child: Text('All')),
          for (final o in opts) DropdownMenuItem<String?>(value: o, child: Text(labels[o] ?? o)),
        ],
        onChanged: onChanged,
      ),
    );
  }

  Future<void> _pick(bool from) async {
    final d = await showDatePicker(
      context: context,
      initialDate: (from ? _from : _to) ?? DateTime.now(),
      firstDate: DateTime(2018),
      lastDate: DateTime.now().add(const Duration(days: 366)),
    );
    if (d != null) setState(() => from ? _from = d : _to = d);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 12, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: FutureBuilder<({List<String> types, List<String> departments, List<String> branches})>(
        future: _options,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const SizedBox(height: 160, child: Center(child: CircularProgressIndicator()));
          }
          if (snap.hasError) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 16),
                const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 28),
                const SizedBox(height: 8),
                Text(ErrorMessageUtils.toUserFriendlyMessage(snap.error),
                    textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary)),
                TextButton(onPressed: () => setState(() => _options = _FilterOptions.load()), child: const Text('Retry')),
              ],
            );
          }
          final o = snap.data!;
          return SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                adminLoanSheetHeader('Filters'),
                if (widget.showCategory)
                  _drop('Category', _category, const ['Loan', 'SalaryAdvance'], (v) => setState(() => _category = v),
                      labels: const {'SalaryAdvance': 'Salary Advance'}),
                _drop('Loan type', _type, o.types, (v) => setState(() => _type = v)),
                _drop('Department', _dept, o.departments, (v) => setState(() => _dept = v)),
                _drop('Branch', _branch, o.branches, (v) => setState(() => _branch = v)),
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () => _pick(true),
                        borderRadius: BorderRadius.circular(12),
                        child: InputDecorator(
                          decoration: const InputDecoration(labelText: 'From'),
                          child: Text(_from == null ? 'Any' : loanDate(_from)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: InkWell(
                        onTap: () => _pick(false),
                        borderRadius: BorderRadius.circular(12),
                        child: InputDecorator(
                          decoration: const InputDecoration(labelText: 'To'),
                          child: Text(_to == null ? 'Any' : loanDate(_to)),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(const LoanListFilters()),
                        child: const Text('Clear'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: (_from != null && _to != null && _to!.isBefore(_from!))
                            ? null
                            : () => Navigator.of(context).pop(LoanListFilters(
                                  category: _category,
                                  loanType: _type,
                                  department: _dept,
                                  branch: _branch,
                                  from: _from,
                                  to: _to,
                                )),
                        child: const Text('Apply'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
