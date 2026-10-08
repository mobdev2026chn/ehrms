// Payroll Loan Recovery (web loans/pages/PayrollRecovery.tsx): EMIs and advance recoveries due
// in a payroll month (GET /admin/loans/payroll-recovery?month=YYYY-MM) and running the deduction
// for every row or only the selected ones (POST /admin/loans/payroll-recovery/run
// {month, rowIds?}). Loans set to manual payment are not listed by the backend.

import 'package:flutter/material.dart';

import '../../../config/app_colors.dart';
import '../../../models/loan_models.dart';
import '../../../services/loan_service.dart';
import '../../../utils/error_message_utils.dart';
import '../../../utils/snackbar_utils.dart';
import '../../../widgets/app_tab_loader.dart';
import '../../loans/loan_detail_screen.dart';
import '../../loans/loan_widgets.dart';
import 'admin_loan_sheets.dart';

class _Row {
  _Row(Map<String, dynamic> j)
      : id = j['id']?.toString() ?? '',
        loanId = j['loanId']?.toString() ?? '',
        loanNo = j['loanNo']?.toString() ?? '',
        loanType = j['loanType']?.toString() ?? '',
        category = j['category']?.toString() ?? '',
        employee = LoanEmployee.fromJson(j['employee'] is Map ? Map<String, dynamic>.from(j['employee']) : {}),
        emiDue = _n(j['emiDue']),
        grossSalary = _n(j['grossSalary']),
        netBefore = _n(j['netBeforeRecovery']),
        recovered = _n(j['recovered']),
        carryForward = _n(j['carryForward']),
        netAfter = _n(j['netAfterRecovery']),
        status = j['status']?.toString() ?? '',
        remarks = j['remarks']?.toString() ?? '';

  static double _n(dynamic v) => (v as num?)?.toDouble() ?? 0;

  final String id, loanId, loanNo, loanType, category, status, remarks;
  final LoanEmployee employee;
  final double emiDue, grossSalary, netBefore, recovered, carryForward, netAfter;

  /// A run can still take something for this row (backend skips rows with nothing recoverable).
  bool get runnable => recovered <= 0 && (status == 'Pending' || status == 'Partial');
}

Color _statusColor(String s) => switch (s) {
      'Success' => AppColors.success,
      'Partial' => AppColors.warning,
      'Failed' => AppColors.error,
      _ => AppColors.info,
    };

class AdminPayrollRecoveryScreen extends StatefulWidget {
  const AdminPayrollRecoveryScreen({super.key});
  @override
  State<AdminPayrollRecoveryScreen> createState() => _AdminPayrollRecoveryScreenState();
}

class _AdminPayrollRecoveryScreenState extends State<AdminPayrollRecoveryScreen> {
  final _service = LoanService();
  String _month = loanMonthKey(DateTime.now());
  List<_Row>? _rows;
  String _payrollStatus = 'Draft';
  String? _error;
  String _search = '';
  final Set<String> _selected = {};
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final month = _month;
    try {
      final d = await _service.adminPayrollRecovery(month);
      if (!mounted || month != _month) return;
      setState(() {
        _rows = d['rows'] is List
            ? (d['rows'] as List).whereType<Map>().map((e) => _Row(Map<String, dynamic>.from(e))).toList()
            : <_Row>[];
        _payrollStatus = d['payrollStatus']?.toString() ?? 'Draft';
        _selected.retainWhere((id) => _rows!.any((r) => r.id == id && r.runnable));
        _error = null;
      });
    } catch (e) {
      if (mounted && month == _month) setState(() => _error = ErrorMessageUtils.toUserFriendlyMessage(e));
    }
  }

  void _changeMonth(int delta) {
    setState(() {
      _month = loanShiftMonth(_month, delta);
      _rows = null;
      _error = null;
      _selected.clear();
    });
    _load();
  }

  Future<void> _run({required bool selectedOnly}) async {
    final rows = _rows ?? [];
    final ids = selectedOnly ? _selected.toList() : rows.map((r) => r.id).toList();
    final target = selectedOnly ? '${ids.length} selected row${ids.length == 1 ? '' : 's'}' : 'all rows';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Recover EMI'),
        content: Text(
            'Deduct the ${loanMonthLabel(_month)} EMIs for $target? Each recovery is posted to the loan ledger. '
            'An employee is never left below the minimum take-home set in the loan settings.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Recover')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _running = true);
    try {
      final processed = await _service.adminRunPayrollRecovery(_month, rowIds: ids);
      if (!mounted) return;
      setState(() {
        _running = false;
        _selected.clear();
      });
      SnackBarUtils.showSnackBar(
          context, processed == 0 ? 'Nothing could be recovered.' : 'EMI recovered for $processed loan${processed == 1 ? '' : 's'}.');
      _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _running = false);
      SnackBarUtils.showSnackBar(context, ErrorMessageUtils.toUserFriendlyMessage(e), isError: true);
    }
  }

  Widget _header() {
    final rows = _rows ?? [];
    double sum(double Function(_Row) f) => rows.fold(0, (a, r) => a + f(r));
    final locked = _payrollStatus == 'Processed';
    return Container(
      decoration: adminLoanToolbarDecoration,
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                  tooltip: 'Previous month',
                  onPressed: () => _changeMonth(-1),
                  icon: const Icon(Icons.chevron_left_rounded)),
              Text(loanMonthLabel(_month),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              IconButton(
                  tooltip: 'Next month',
                  onPressed: () => _changeMonth(1),
                  icon: const Icon(Icons.chevron_right_rounded)),
              const Spacer(),
              if (_rows != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: locked ? AppColors.successBg : AppColors.warningBg,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(_payrollStatus,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: locked ? AppColors.success : AppColors.warning)),
                ),
            ],
          ),
          if (_rows != null && rows.isNotEmpty)
            Container(
              margin: const EdgeInsets.fromLTRB(8, 4, 0, 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  Expanded(child: LoanStat('EMIs due', loanMoney(sum((r) => r.emiDue)))),
                  Expanded(child: LoanStat('Recovered', loanMoney(sum((r) => r.recovered)), color: AppColors.success)),
                  Expanded(child: LoanStat('Carry forward', loanMoney(sum((r) => r.carryForward)))),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: TextField(
              onChanged: (v) => setState(() => _search = v),
              decoration: const InputDecoration(
                isDense: true,
                hintText: 'Search employee or loan number',
                prefixIcon: Icon(Icons.search_rounded, size: 20),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    final locked = _payrollStatus == 'Processed';
    final term = _search.trim().toLowerCase();
    final visible = rows == null
        ? <_Row>[]
        : rows
            .where((r) => term.isEmpty || '${r.employee.name} ${r.employee.employeeId} ${r.loanNo}'.toLowerCase().contains(term))
            .toList();
    final canRunAll = rows != null && rows.any((r) => r.runnable) && !locked;

    Widget body;
    if (_error != null && rows == null) {
      body = adminLoanErrorView(_error!, _load);
    } else if (rows == null) {
      body = const Center(child: AppTabLoader());
    } else if (visible.isEmpty) {
      body = adminLoanEmptyView(
        rows.isEmpty ? Icons.event_available_outlined : Icons.search_off_rounded,
        rows.isEmpty ? 'No EMIs fall due in ${loanMonthLabel(_month)}.' : 'No matching rows.',
      );
    } else {
      body = ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
        itemCount: visible.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, i) {
          final r = visible[i];
          final selectable = r.runnable && !locked;
          return LoanCard(
            onTap: r.loanId.isEmpty
                ? null
                : () async {
                    await Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => LoanDetailScreen(loanId: r.loanId, admin: true)));
                    _load();
                  },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (selectable)
                      SizedBox(
                        width: 32,
                        height: 24,
                        child: Checkbox(
                          value: _selected.contains(r.id),
                          onChanged: (v) => setState(() => v == true ? _selected.add(r.id) : _selected.remove(r.id)),
                        ),
                      ),
                    Expanded(
                      child: Text(r.employee.name,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _statusColor(r.status).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(r.status,
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _statusColor(r.status))),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${r.category == 'SalaryAdvance' ? 'Salary Advance' : r.loanType} · ${r.loanNo}'
                  '${r.employee.employeeId.isNotEmpty ? ' · ${r.employee.employeeId}' : ''}',
                  style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Divider(height: 1),
                ),
                Row(
                  children: [
                    Expanded(child: LoanStat('EMI due', loanMoney(r.emiDue))),
                    Expanded(child: LoanStat('Net salary', loanMoney(r.netBefore))),
                    Expanded(child: LoanStat('Recovered', loanMoney(r.recovered), color: r.recovered > 0 ? AppColors.success : null)),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: LoanStat('Net after', loanMoney(r.netAfter))),
                    Expanded(
                      child: LoanStat('Carry forward', loanMoney(r.carryForward),
                          color: r.carryForward > 0 ? AppColors.warning : null),
                    ),
                    const Expanded(child: SizedBox()),
                  ],
                ),
                if (r.remarks.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(r.remarks, style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                  ),
              ],
            ),
          );
        },
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Payroll Recovery'),
      ),
      body: Column(
        children: [
          _header(),
          Expanded(child: RefreshIndicator(color: AppColors.primary, onRefresh: _load, child: body)),
        ],
      ),
      bottomNavigationBar: rows == null || rows.isEmpty
          ? null
          : Container(
              decoration: const BoxDecoration(
                color: AppColors.surface,
                border: Border(top: BorderSide(color: Color(0xFFECEEF1))),
              ),
              child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: locked
                    ? const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.lock_outline_rounded, size: 16, color: AppColors.textSecondary),
                          SizedBox(width: 6),
                          Flexible(
                            child: Text('Payroll for this month is already processed.',
                                textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                          ),
                        ],
                      )
                    : Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _running || _selected.isEmpty ? null : () => _run(selectedOnly: true),
                              child: Text('Recover selected (${_selected.length})'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: _running || !canRunAll ? null : () => _run(selectedOnly: false),
                              child: _running
                                  ? SizedBox(
                                      width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onPrimary))
                                  : const Text('Recover all'),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
            ),
    );
  }
}
