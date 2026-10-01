// Loan detail - summary, EMI schedule, ledger, approvals, documents (and activity for
// admins). Staff: GET /staff/loans/:id. Admin: GET /admin/loans/:id plus Disburse,
// Record payment / Foreclose and status change (POST …/disburse, …/payments,
// PATCH …/status), like the web loan detail.

import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../models/loan_models.dart';
import '../../services/loan_service.dart';
import '../../utils/error_message_utils.dart';
import '../../utils/snackbar_utils.dart';
import '../../widgets/app_tab_loader.dart';
import 'loan_widgets.dart';

class LoanDetailScreen extends StatefulWidget {
  const LoanDetailScreen({super.key, required this.loanId, this.admin = false});
  final String loanId;
  final bool admin;

  @override
  State<LoanDetailScreen> createState() => _LoanDetailScreenState();
}

class _LoanDetailScreenState extends State<LoanDetailScreen> {
  final _service = LoanService();
  Loan? _loan;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final l = widget.admin ? await _service.adminLoan(widget.loanId) : await _service.getMyLoan(widget.loanId);
      if (mounted) setState(() => _loan = l);
    } catch (e) {
      if (mounted) setState(() => _error = ErrorMessageUtils.toUserFriendlyMessage(e));
    }
  }

  Future<void> _run(Future<Loan> Function() action, String done) async {
    setState(() => _busy = true);
    try {
      final l = await action();
      if (!mounted) return;
      setState(() {
        _loan = l;
        _busy = false;
      });
      SnackBarUtils.showSnackBar(context, done);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      SnackBarUtils.showSnackBar(context, ErrorMessageUtils.toUserFriendlyMessage(e), isError: true);
    }
  }

  // ── Admin actions ──

  Future<void> _disburse() async {
    var mode = 'Bank Transfer';
    final ref = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Disburse loan'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: mode,
                decoration: const InputDecoration(labelText: 'Mode'),
                items: const [
                  DropdownMenuItem(value: 'Bank Transfer', child: Text('Bank Transfer')),
                  DropdownMenuItem(value: 'Cash', child: Text('Cash')),
                ],
                onChanged: (v) => setD(() => mode = v ?? mode),
              ),
              TextField(controller: ref, decoration: const InputDecoration(labelText: 'Reference (optional)')),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Disburse')),
          ],
        ),
      ),
    );
    final reference = ref.text.trim();
    ref.dispose();
    if (ok != true) return;
    await _run(() => _service.adminDisburse(widget.loanId, mode: mode, reference: reference), 'Disbursement recorded.');
  }

  Future<void> _payment({required bool foreclose}) async {
    final loan = _loan!;
    final amount = TextEditingController(
        text: foreclose ? loan.outstanding.toStringAsFixed(0) : loan.emiAmount.toStringAsFixed(0));
    final ref = TextEditingController();
    var mode = 'Bank';
    const modes = ['Bank', 'Cash', 'Cheque', 'UPI', 'Manual', 'Adjustment'];
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(foreclose ? 'Foreclose loan' : 'Record EMI payment'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amount,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: 'Amount', helperText: 'Outstanding ${loanMoney(loan.outstanding)}'),
              ),
              DropdownButtonFormField<String>(
                initialValue: mode,
                decoration: const InputDecoration(labelText: 'Mode'),
                items: [for (final m in modes) DropdownMenuItem(value: m, child: Text(m))],
                onChanged: (v) => setD(() => mode = v ?? mode),
              ),
              TextField(controller: ref, decoration: const InputDecoration(labelText: 'Reference (optional)')),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    final value = double.tryParse(amount.text.trim()) ?? 0;
    final reference = ref.text.trim();
    amount.dispose();
    ref.dispose();
    if (ok != true) return;
    if (value <= 0 || value > loan.outstanding) {
      if (mounted) SnackBarUtils.showSnackBar(context, 'Enter an amount up to the outstanding balance.', isError: true);
      return;
    }
    await _run(
      () => _service.adminRecordPayment(widget.loanId,
          kind: foreclose ? 'Foreclosure' : 'Manual EMI', amount: value, mode: mode, reference: reference),
      foreclose ? 'Loan foreclosed.' : 'Payment recorded.',
    );
  }

  Future<void> _changeStatus(String status) async {
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Mark as $status?'),
        content: TextField(controller: reason, decoration: const InputDecoration(labelText: 'Reason *')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Mark $status')),
        ],
      ),
    );
    final text = reason.text.trim();
    reason.dispose();
    if (ok != true) return;
    if (text.length < 3) {
      if (mounted) SnackBarUtils.showSnackBar(context, 'Give a reason (at least 3 characters).', isError: true);
      return;
    }
    await _run(() => _service.adminSetStatus(widget.loanId, status, text), 'Loan marked $status.');
  }

  List<PopupMenuEntry<String>> _adminMenu(Loan l) => [
        if (l.status == 'Approved') const PopupMenuItem(value: 'disburse', child: Text('Disburse')),
        if (l.isLive && l.outstanding > 0) ...[
          const PopupMenuItem(value: 'payment', child: Text('Record EMI payment')),
          const PopupMenuItem(value: 'foreclose', child: Text('Foreclose')),
        ],
        if (l.isLive) ...[
          const PopupMenuItem(value: 'Closed', child: Text('Close loan')),
          if (l.disbursedOn == null) const PopupMenuItem(value: 'Cancelled', child: Text('Cancel loan')),
          if (l.status != 'Defaulted') const PopupMenuItem(value: 'Defaulted', child: Text('Mark defaulted')),
        ],
      ];

  void _onMenu(String v) {
    switch (v) {
      case 'disburse':
        _disburse();
      case 'payment':
        _payment(foreclose: false);
      case 'foreclose':
        _payment(foreclose: true);
      default:
        _changeStatus(v);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = _loan;
    final menu = (l != null && widget.admin) ? _adminMenu(l) : const <PopupMenuEntry<String>>[];
    final tabs = <String>['EMI Schedule', 'Ledger', 'Approvals', 'Documents', if (widget.admin) 'Activity'];
    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: Text(l?.loanNo ?? 'Loan', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
          backgroundColor: Colors.white,
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          actions: [
            if (menu.isNotEmpty)
              PopupMenuButton<String>(
                enabled: !_busy,
                itemBuilder: (_) => menu,
                onSelected: _onMenu,
              ),
          ],
        ),
        body: l == null
            ? Center(
                child: _error == null
                    ? const AppTabLoader()
                    : Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)),
              )
            : NestedScrollView(
                headerSliverBuilder: (_, __) => [
                  SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.all(16), child: _summary(l))),
                  SliverToBoxAdapter(
                    child: TabBar(
                      isScrollable: true,
                      labelColor: AppColors.brandDark,
                      unselectedLabelColor: AppColors.textSecondary,
                      indicatorColor: AppColors.brand,
                      tabs: [for (final t in tabs) Tab(text: t)],
                    ),
                  ),
                ],
                body: TabBarView(
                  children: [
                    _tabBody(LoanScheduleList(l.schedule)),
                    _tabBody(LoanLedgerList(l.ledger)),
                    _tabBody(LoanApprovalTracker(l.approvals)),
                    _tabBody(LoanDocumentList(l.documents)),
                    if (widget.admin) _tabBody(_activity(l)),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _tabBody(Widget child) => ListView(
        padding: const EdgeInsets.all(16),
        children: [LoanCard(child: child)],
      );

  Widget _summary(Loan l) => LoanCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(l.isAdvance ? 'Salary Advance' : l.loanType,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                ),
                LoanStatusChip(l.status),
              ],
            ),
            if (widget.admin && l.employee.name.isNotEmpty)
              Text('${l.employee.name} · ${l.employee.employeeId}',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: LoanStat('Principal', loanMoney(l.principal))),
                Expanded(child: LoanStat('EMI', loanMoney(l.emiAmount))),
                Expanded(child: LoanStat('Outstanding', loanMoney(l.outstanding))),
              ],
            ),
            const SizedBox(height: 10),
            LoanInfoRow(
              'Interest',
              l.interestMethod == 'None' || l.interestRate == 0
                  ? 'No interest'
                  : '${l.interestRate.toStringAsFixed(l.interestRate % 1 == 0 ? 0 : 2)}% p.a. (${l.interestMethod})',
            ),
            LoanInfoRow('Tenure', '${l.paidEmis} of ${l.tenure} EMIs paid'),
            LoanInfoRow('Total payable', loanMoney(l.totalPayable)),
            LoanInfoRow('Recovered', loanMoney(l.recovered), valueColor: AppColors.success),
            if (l.overdueAmount > 0) LoanInfoRow('Overdue', loanMoney(l.overdueAmount), valueColor: AppColors.error),
            LoanInfoRow('Next due', loanDate(l.nextDueDate)),
            LoanInfoRow('Recovery', l.recoveryMode),
            if (l.disbursedOn != null)
              LoanInfoRow('Disbursed', [loanDate(l.disbursedOn), if (l.disbursementMode.isNotEmpty) l.disbursementMode].join(' · ')),
          ],
        ),
      );

  Widget _activity(Loan l) {
    if (l.activity.isEmpty) {
      return const Text('No activity yet.', style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary));
    }
    return Column(
      children: [
        for (final a in l.activity.reversed)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(a.action, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            subtitle: Text(
              [if (a.detail.isNotEmpty) a.detail, [loanDate(a.at), if (a.actor.isNotEmpty) a.actor].join(' · ')].join('\n'),
              style: const TextStyle(fontSize: 11.5),
            ),
          ),
      ],
    );
  }
}
