// Salary Advance (web loans/pages/SalaryAdvance.tsx): the advance policy at a glance
// (GET /admin/loans/settings), advance requests (GET /admin/loans/requests?category=SalaryAdvance)
// with Quick approve (POST /admin/loans/requests/:id/approve), and active / recovered advances
// (GET /admin/loans?category=SalaryAdvance).

import 'package:flutter/material.dart';

import '../../../config/app_colors.dart';
import '../../../models/loan_models.dart';
import '../../../services/loan_service.dart';
import '../../../utils/error_message_utils.dart';
import '../../../utils/snackbar_utils.dart';
import '../../../widgets/app_tab_loader.dart';
import '../../loans/loan_detail_screen.dart';
import '../../loans/loan_widgets.dart';
import 'admin_loan_request_screen.dart';
import 'admin_loan_settings_screen.dart';
import 'admin_loan_sheets.dart';

const _activeStatuses = ['Approved', 'Disbursed', 'Active', 'Defaulted'];
const _recoveredStatuses = ['Completed', 'Closed'];
const _finalRequestStatuses = ['Approved', 'Rejected', 'Cancelled', 'Disbursed', 'Active', 'Completed', 'Closed', 'Defaulted'];

int _monthsOf(String r) => r == '3 Months' ? 3 : (r == '2 Months' ? 2 : 1);

/// Policy ceiling for one employee: maxPctOfNet of net salary, capped at maxAmountCap when set.
double _eligible(double net, SalaryAdvancePolicy p) {
  final byPct = net * p.maxPctOfNet / 100;
  final v = p.maxAmountCap > 0 && p.maxAmountCap < byPct ? p.maxAmountCap : byPct;
  return v < 0 ? 0 : v.floorToDouble();
}

List<String> _allowedRecoveries(SalaryAdvancePolicy p) => const ['Next Salary', '2 Months', '3 Months']
    .where((r) => r == 'Next Salary' || (p.allowSplitRecovery && _monthsOf(r) <= p.maxSplitMonths))
    .toList();

class AdminSalaryAdvanceScreen extends StatefulWidget {
  const AdminSalaryAdvanceScreen({super.key});
  @override
  State<AdminSalaryAdvanceScreen> createState() => _AdminSalaryAdvanceScreenState();
}

class _AdminSalaryAdvanceScreenState extends State<AdminSalaryAdvanceScreen> {
  final _service = LoanService();
  SalaryAdvancePolicy? _policy;
  List<LoanRequest>? _requests;
  List<Loan>? _advances;
  String? _error;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait<Object>([
        _service.adminSettings(),
        _service.adminRequests(category: 'SalaryAdvance'),
        _service.adminLoans(category: 'SalaryAdvance'),
      ]);
      final settings = results[0] as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _policy = SalaryAdvancePolicy.fromJson(
            settings['salaryAdvance'] is Map ? Map<String, dynamic>.from(settings['salaryAdvance']) : <String, dynamic>{});
        _requests = (results[1] as List<LoanRequest>).where((r) => r.isAdvance).toList();
        _advances = (results[2] as List<Loan>).where((l) => l.isAdvance).toList();
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = ErrorMessageUtils.toUserFriendlyMessage(e));
    }
  }

  bool _match(List<String> values) {
    final t = _search.trim().toLowerCase();
    return t.isEmpty || values.any((v) => v.toLowerCase().contains(t));
  }

  Future<void> _quickApprove(LoanRequest r) async {
    final policy = _policy!;
    final approved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      builder: (_) => _QuickApproveSheet(request: r, policy: policy),
    );
    if (approved == true) _load();
  }

  Future<void> _openRequest(LoanRequest r) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => AdminLoanRequestScreen(requestId: r.id)));
    _load();
  }

  Future<void> _openLoan(Loan l) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => LoanDetailScreen(loanId: l.id, admin: true)));
    _load();
  }

  Future<void> _editPolicy() async {
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => const AdminLoanSettingsScreen(group: LoanSettingsGroup.policies, initialTab: 'salary-advance')));
    _load();
  }

  Widget _empty(String text) => adminLoanEmptyView(Icons.payments_outlined, text);

  static const _nameStyle = TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary);
  static const _metaStyle = TextStyle(fontSize: 12.5, color: AppColors.textSecondary);
  static const _statsDivider = Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider(height: 1));

  Widget _requestsList() {
    final rows = _requests!.where((r) => _match([r.employee.name, r.employee.employeeId, r.requestNo])).toList();
    if (rows.isEmpty) return _empty('No salary advance requests.');
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: rows.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, i) {
        final r = rows[i];
        final canApprove = !_finalRequestStatuses.contains(r.status);
        final eligible = _eligible(r.employee.monthlyNet, _policy!);
        return LoanCard(
          onTap: () => _openRequest(r),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(r.employee.name, style: _nameStyle)),
                  const SizedBox(width: 8),
                  LoanStatusChip(r.status),
                ],
              ),
              const SizedBox(height: 2),
              Text('${r.requestNo} · ${loanDate(r.appliedOn)}${r.advanceRecovery.isNotEmpty ? ' · ${r.advanceRecovery}' : ''}',
                  style: _metaStyle),
              _statsDivider,
              Row(
                children: [
                  Expanded(child: LoanStat('Requested', loanMoney(r.requestedAmount))),
                  Expanded(child: LoanStat('Net salary', loanMoney(r.employee.monthlyNet))),
                  Expanded(
                    child: LoanStat('Eligible', loanMoney(eligible),
                        color: r.requestedAmount > eligible ? AppColors.error : AppColors.success),
                  ),
                ],
              ),
              if (canApprove) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(onPressed: () => _openRequest(r), child: const Text('Review')),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _quickApprove(r),
                        icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
                        label: const Text('Approve'),
                        style: ElevatedButton.styleFrom(backgroundColor: AppColors.success, foregroundColor: Colors.white),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _advanceList(List<String> statuses, String emptyText) {
    final rows = _advances!
        .where((l) => statuses.contains(l.status))
        .where((l) => _match([l.employee.name, l.employee.employeeId, l.loanNo]))
        .toList();
    if (rows.isEmpty) return _empty(emptyText);
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: rows.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, i) {
        final l = rows[i];
        return LoanCard(
          onTap: () => _openLoan(l),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(l.employee.name, style: _nameStyle)),
                  const SizedBox(width: 8),
                  LoanStatusChip(l.status),
                ],
              ),
              const SizedBox(height: 2),
              Text('${l.loanNo} · ${l.tenure <= 1 ? 'Next Salary' : '${l.tenure} Months'}', style: _metaStyle),
              _statsDivider,
              Row(
                children: [
                  Expanded(child: LoanStat('Amount', loanMoney(l.principal))),
                  Expanded(child: LoanStat('Recovered', loanMoney(l.recovered), color: AppColors.success)),
                  Expanded(
                    child: LoanStat('Outstanding', loanMoney(l.outstanding),
                        color: l.overdueAmount > 0 ? AppColors.error : null),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _policyCard() {
    final p = _policy!;
    return Container(
      decoration: adminLoanToolbarDecoration,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(p.enabled ? Icons.policy_outlined : Icons.block_rounded,
                  size: 18, color: p.enabled ? AppColors.primaryText : AppColors.error),
              const SizedBox(width: 8),
              Expanded(
                child: Text(p.enabled ? 'Policy' : 'Salary advances are switched off',
                    style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600, color: p.enabled ? AppColors.textPrimary : AppColors.error)),
              ),
              TextButton.icon(
                onPressed: _editPolicy,
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('Edit policy'),
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _kv('Max', '${p.maxPctOfNet.toStringAsFixed(0)}% of net${p.maxAmountCap > 0 ? ' (cap ${loanMoney(p.maxAmountCap)})' : ''}'),
              _kv('Recovery', p.allowSplitRecovery ? 'Up to ${p.maxSplitMonths} months' : 'Next salary'),
              _kv('Per year', '${p.maxAdvancesPerYear}'),
              _kv('Cut-off day', '${p.cutoffDay}'),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            onChanged: (v) => setState(() => _search = v),
            decoration: const InputDecoration(
              isDense: true,
              hintText: 'Search employee or number',
              prefixIcon: Icon(Icons.search_rounded, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(999)),
        child: Text.rich(TextSpan(children: [
          TextSpan(text: '$k: ', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          TextSpan(
              text: v, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        ])),
      );

  @override
  Widget build(BuildContext context) {
    final ready = _requests != null && _advances != null && _policy != null;
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('Salary Advance'),
          bottom: TabBar(
            tabs: [
              Tab(text: ready ? 'Requests (${_requests!.where((r) => !_finalRequestStatuses.contains(r.status)).length})' : 'Requests'),
              const Tab(text: 'Active'),
              const Tab(text: 'Recovered'),
            ],
          ),
        ),
        body: _error != null && !ready
            ? adminLoanErrorView(_error!, _load)
            : !ready
                ? const Center(child: AppTabLoader())
                : Column(
                    children: [
                      _policyCard(),
                      Expanded(
                        child: TabBarView(children: [
                          RefreshIndicator(color: AppColors.primary, onRefresh: _load, child: _requestsList()),
                          RefreshIndicator(
                              color: AppColors.primary,
                              onRefresh: _load,
                              child: _advanceList(_activeStatuses, 'No active advances.')),
                          RefreshIndicator(
                              color: AppColors.primary,
                              onRefresh: _load,
                              child: _advanceList(_recoveredStatuses, 'No recovered advances.')),
                        ]),
                      ),
                    ],
                  ),
      ),
    );
  }
}

/// Web QuickApproveAdvanceModal: amount (pre-filled with min(requested, eligible)), recovery
/// plan the policy allows, first recovery month (honouring the cut-off day) and remarks.
class _QuickApproveSheet extends StatefulWidget {
  const _QuickApproveSheet({required this.request, required this.policy});
  final LoanRequest request;
  final SalaryAdvancePolicy policy;
  @override
  State<_QuickApproveSheet> createState() => _QuickApproveSheetState();
}

class _QuickApproveSheetState extends State<_QuickApproveSheet> {
  late final double _eligibleAmt = _eligible(widget.request.employee.monthlyNet, widget.policy);
  late final List<String> _options = _allowedRecoveries(widget.policy);
  late final TextEditingController _amount = TextEditingController(
    text: (() {
      final r = widget.request.requestedAmount;
      final v = r < _eligibleAmt ? r : _eligibleAmt;
      return (v > 0 ? v : r).toStringAsFixed(0);
    })(),
  );
  late String _recovery = _options.contains(widget.request.advanceRecovery)
      ? widget.request.advanceRecovery
      : (_options.contains(widget.policy.defaultRecovery) ? widget.policy.defaultRecovery : 'Next Salary');
  late String _start = loanDefaultRecoveryMonth(widget.policy.cutoffDay);
  final _remarks = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _amount.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _amount.dispose();
    _remarks.dispose();
    super.dispose();
  }

  double get _value => double.tryParse(_amount.text.trim()) ?? 0;

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      await LoanService().adminApprove(widget.request.id, {
        'approvedAmount': _value.round(),
        'interestMethod': 'None',
        'interestRate': 0,
        'tenure': _monthsOf(_recovery),
        'advanceRecovery': _recovery,
        'recoveryStart': '$_start-01',
        if (_remarks.text.trim().isNotEmpty) 'remarks': _remarks.text.trim(),
      });
      if (!mounted) return;
      SnackBarUtils.showSnackBar(context, 'Salary advance of ${loanMoney(_value)} approved.');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      SnackBarUtils.showSnackBar(context, ErrorMessageUtils.toUserFriendlyMessage(e), isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.request;
    final months = _monthsOf(_recovery);
    final valid = _value > 0;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 12, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            adminLoanSheetHeader('Approve salary advance',
                subtitle: '${r.employee.name} · requested ${loanMoney(r.requestedAmount)}'),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  Expanded(child: LoanStat('Eligible', loanMoney(_eligibleAmt), color: AppColors.success)),
                  Expanded(child: LoanStat('Net salary', loanMoney(r.employee.monthlyNet))),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _amount,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Approved amount (₹)',
                errorText: _amount.text.isNotEmpty && !valid ? 'Amount must be greater than zero' : null,
                helperText: valid && _value > _eligibleAmt ? 'Above the policy limit of ${loanMoney(_eligibleAmt)}' : null,
                helperStyle: const TextStyle(color: AppColors.warning),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _recovery,
              decoration: const InputDecoration(labelText: 'Recovery'),
              items: [for (final o in _options) DropdownMenuItem(value: o, child: Text(o))],
              onChanged: (v) => setState(() => _recovery = v ?? _recovery),
            ),
            const SizedBox(height: 12),
            LoanMonthDropdown(value: _start, onChanged: (v) => setState(() => _start = v), label: 'First recovery month'),
            const SizedBox(height: 12),
            TextField(controller: _remarks, decoration: const InputDecoration(labelText: 'Remarks (optional)')),
            if (valid)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline_rounded, size: 16, color: AppColors.textSecondary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        months == 1
                            ? 'Recovered in full from the ${loanMonthLabel(_start)} salary.'
                            : 'About ${loanMoney(_value / months)} a month over $months months from ${loanMonthLabel(_start)}.',
                        style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _busy || !valid ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(52),
              ),
              child: _busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(valid ? 'Approve ${loanMoney(_value)}' : 'Approve'),
            ),
          ],
        ),
      ),
    );
  }
}
