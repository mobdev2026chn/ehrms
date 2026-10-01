// Admin review of one loan / advance request (GET /admin/loans/requests/:id): request,
// the employee's active loans and history, then Approve (with final terms), Reject or
// Ask clarification - POST …/approve | …/reject | …/clarification, like the web.

import 'package:flutter/material.dart';

import '../../../config/app_colors.dart';
import '../../../models/loan_models.dart';
import '../../../services/loan_service.dart';
import '../../../utils/error_message_utils.dart';
import '../../../utils/loan_math.dart';
import '../../../utils/snackbar_utils.dart';
import '../../../widgets/app_tab_loader.dart';
import '../../loans/loan_detail_screen.dart';
import '../../loans/loan_widgets.dart';

class AdminLoanRequestScreen extends StatefulWidget {
  const AdminLoanRequestScreen({super.key, required this.requestId});
  final String requestId;

  @override
  State<AdminLoanRequestScreen> createState() => _AdminLoanRequestScreenState();
}

class _AdminLoanRequestScreenState extends State<AdminLoanRequestScreen> {
  final _service = LoanService();
  LoanRequest? _request;
  List<Loan> _activeLoans = [], _history = [];
  Map<String, dynamic>? _policy;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await _service.adminRequest(widget.requestId);
      if (!mounted) return;
      setState(() {
        _request = d.request;
        _activeLoans = d.activeLoans;
        _history = d.loanHistory;
        _policy = d.policy;
      });
    } catch (e) {
      if (mounted) setState(() => _error = ErrorMessageUtils.toUserFriendlyMessage(e));
    }
  }

  /// Pending-type statuses an approver can still act on.
  bool get _actionable => _request != null && _request!.isOpen;

  Future<void> _textAction({
    required String title,
    required String label,
    required String button,
    required Future<void> Function(String text) action,
    required String done,
  }) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(controller: ctrl, minLines: 2, maxLines: 4, decoration: InputDecoration(labelText: label)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(button)),
        ],
      ),
    );
    final text = ctrl.text.trim();
    ctrl.dispose();
    if (ok != true) return;
    if (text.length < 5) {
      if (mounted) SnackBarUtils.showSnackBar(context, 'Please write at least 5 characters.', isError: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await action(text);
      if (!mounted) return;
      SnackBarUtils.showSnackBar(context, done);
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      SnackBarUtils.showSnackBar(context, ErrorMessageUtils.toUserFriendlyMessage(e), isError: true);
    }
  }

  Future<void> _approve() async {
    final r = _request!;
    final terms = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (_) => _ApproveSheet(request: r, policy: _policy),
    );
    if (terms == null) return;
    setState(() => _busy = true);
    try {
      final loan = await _service.adminApprove(r.id, terms);
      if (!mounted) return;
      SnackBarUtils.showSnackBar(context, 'Approved - loan ${loan.loanNo} created.');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      SnackBarUtils.showSnackBar(context, ErrorMessageUtils.toUserFriendlyMessage(e), isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _request;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(r?.requestNo ?? 'Loan request', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: r == null
          ? Center(
              child: _error == null
                  ? const AppTabLoader()
                  : Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                LoanCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(r.employee.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                          ),
                          LoanStatusChip(r.status),
                        ],
                      ),
                      Text(
                        [r.employee.employeeId, r.employee.designation, r.employee.department]
                            .where((s) => s.isNotEmpty)
                            .join(' · '),
                        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                      ),
                      const Divider(height: 20),
                      LoanInfoRow('Type', r.isAdvance ? 'Salary Advance' : r.loanType),
                      LoanInfoRow('Amount requested', loanMoney(r.requestedAmount)),
                      if (r.isAdvance)
                        LoanInfoRow('Recovery', r.advanceRecovery)
                      else
                        LoanInfoRow('Preferred tenure', r.preferredTenure > 0 ? '${r.preferredTenure} months' : ''),
                      LoanInfoRow('Purpose', r.purpose),
                      LoanInfoRow('Reason', r.reason),
                      LoanInfoRow('Applied on', loanDate(r.appliedOn)),
                      if (r.requiredBy != null) LoanInfoRow('Required by', loanDate(r.requiredBy)),
                      if (r.employee.monthlyGross > 0) LoanInfoRow('Monthly gross', loanMoney(r.employee.monthlyGross)),
                      if (r.employee.monthlyNet > 0) LoanInfoRow('Monthly net', loanMoney(r.employee.monthlyNet)),
                    ],
                  ),
                ),
                const LoanSectionTitle('Approval progress'),
                LoanCard(child: LoanApprovalTracker(r.approvals, currentLevel: r.currentLevel)),
                if (r.documents.isNotEmpty) ...[
                  const LoanSectionTitle('Documents'),
                  LoanCard(child: LoanDocumentList(r.documents)),
                ],
                LoanSectionTitle('Active loans (${_activeLoans.length})'),
                ..._loanTiles(_activeLoans, 'No active loans.'),
                LoanSectionTitle('Loan history (${_history.length})'),
                ..._loanTiles(_history, 'No previous loans.'),
                const SizedBox(height: 18),
                if (_actionable) ...[
                  ElevatedButton(
                    onPressed: _busy ? null : _approve,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Approve', style: TextStyle(fontWeight: FontWeight.w800)),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _busy
                              ? null
                              : () => _textAction(
                                    title: 'Ask for clarification',
                                    label: 'Question for the employee',
                                    button: 'Send',
                                    action: (q) => _service.adminAskClarification(r.id, q),
                                    done: 'Clarification requested.',
                                  ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.info,
                            padding: const EdgeInsets.symmetric(vertical: 13),
                          ),
                          child: const Text('Ask clarification'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _busy
                              ? null
                              : () => _textAction(
                                    title: 'Reject request',
                                    label: 'Reason',
                                    button: 'Reject',
                                    action: (reason) => _service.adminReject(r.id, reason),
                                    done: 'Request rejected.',
                                  ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.error,
                            padding: const EdgeInsets.symmetric(vertical: 13),
                          ),
                          child: const Text('Reject'),
                        ),
                      ),
                    ],
                  ),
                ],
                if (r.loanId.isNotEmpty)
                  TextButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => LoanDetailScreen(loanId: r.loanId, admin: true)),
                    ),
                    icon: const Icon(Icons.receipt_long_outlined),
                    label: const Text('Open the loan'),
                  ),
              ],
            ),
    );
  }

  List<Widget> _loanTiles(List<Loan> loans, String empty) {
    if (loans.isEmpty) {
      return [LoanCard(child: Text(empty, style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)))];
    }
    return [
      for (final l in loans)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: LoanCard(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => LoanDetailScreen(loanId: l.id, admin: true)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${l.isAdvance ? 'Salary Advance' : l.loanType} · ${l.loanNo}',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                      Text('EMI ${loanMoney(l.emiAmount)} · outstanding ${loanMoney(l.outstanding)}',
                          style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
                    ],
                  ),
                ),
                LoanStatusChip(l.status),
              ],
            ),
          ),
        ),
    ];
  }
}

/// Final terms for approval, prefilled from the request and the loan type's policy.
class _ApproveSheet extends StatefulWidget {
  const _ApproveSheet({required this.request, required this.policy});
  final LoanRequest request;
  final Map<String, dynamic>? policy;

  @override
  State<_ApproveSheet> createState() => _ApproveSheetState();
}

class _ApproveSheetState extends State<_ApproveSheet> {
  late final TextEditingController _amount, _rate, _tenure, _remarks;
  late String _method;
  late String _recovery;
  String _recoveryMode = 'Salary Deduction';

  LoanRequest get _r => widget.request;

  @override
  void initState() {
    super.initState();
    final p = widget.policy ?? const {};
    _amount = TextEditingController(text: _r.requestedAmount.toStringAsFixed(0));
    _method = _r.isAdvance ? 'None' : (p['interestMethod']?.toString() ?? 'None');
    _rate = TextEditingController(text: _r.isAdvance ? '0' : '${(p['interestRate'] as num?) ?? 0}');
    _tenure = TextEditingController(
        text: '${_r.preferredTenure > 0 ? _r.preferredTenure : ((p['minTenure'] as num?)?.toInt() ?? 6)}');
    _recovery = _r.advanceRecovery.isNotEmpty ? _r.advanceRecovery : 'Next Salary';
    _remarks = TextEditingController();
    for (final c in [_amount, _rate, _tenure]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    for (final c in [_amount, _rate, _tenure, _remarks]) {
      c.dispose();
    }
    super.dispose();
  }

  double get _amountV => double.tryParse(_amount.text.trim()) ?? 0;
  double get _rateV => double.tryParse(_rate.text.trim()) ?? 0;
  int get _tenureV => int.tryParse(_tenure.text.trim()) ?? 0;

  String? _problem() {
    if (_amountV <= 0) return 'Enter the approved amount.';
    if (_rateV < 0 || _rateV > 50) return 'Interest rate must be between 0 and 50%.';
    if (!_r.isAdvance && (_tenureV < 1 || _tenureV > 120)) return 'Tenure must be 1–120 months.';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final quote = (!_r.isAdvance && _amountV > 0 && _tenureV > 0) ? buildSchedule(_amountV, _rateV, _tenureV, _method) : null;
    final problem = _problem();
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Approve with terms', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            TextField(
              controller: _amount,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Approved amount (₹)'),
            ),
            if (!_r.isAdvance) ...[
              DropdownButtonFormField<String>(
                initialValue: _method,
                decoration: const InputDecoration(labelText: 'Interest method'),
                items: const [
                  DropdownMenuItem(value: 'None', child: Text('None')),
                  DropdownMenuItem(value: 'Flat', child: Text('Flat')),
                  DropdownMenuItem(value: 'Reducing', child: Text('Reducing')),
                ],
                onChanged: (v) => setState(() => _method = v ?? _method),
              ),
              TextField(
                controller: _rate,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Interest rate (% per year)'),
              ),
              TextField(
                controller: _tenure,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Tenure (months)'),
              ),
              DropdownButtonFormField<String>(
                initialValue: _recoveryMode,
                decoration: const InputDecoration(labelText: 'Recovery mode'),
                items: const [
                  DropdownMenuItem(value: 'Salary Deduction', child: Text('Salary Deduction')),
                  DropdownMenuItem(value: 'Manual Payment', child: Text('Manual Payment')),
                ],
                onChanged: (v) => setState(() => _recoveryMode = v ?? _recoveryMode),
              ),
            ] else
              DropdownButtonFormField<String>(
                initialValue: _recovery,
                decoration: const InputDecoration(labelText: 'Recovery'),
                items: const [
                  DropdownMenuItem(value: 'Next Salary', child: Text('Next Salary')),
                  DropdownMenuItem(value: '2 Months', child: Text('2 Months')),
                  DropdownMenuItem(value: '3 Months', child: Text('3 Months')),
                ],
                onChanged: (v) => setState(() => _recovery = v ?? _recovery),
              ),
            TextField(controller: _remarks, decoration: const InputDecoration(labelText: 'Remarks (optional)')),
            if (quote != null) ...[
              const SizedBox(height: 12),
              LoanCard(
                child: Column(
                  children: [
                    LoanInfoRow('EMI', loanMoney(quote.emi), valueColor: AppColors.brandDark),
                    LoanInfoRow('Total interest', loanMoney(quote.totalInterest)),
                    LoanInfoRow('Total payable', loanMoney(quote.totalPayable)),
                  ],
                ),
              ),
            ],
            if (problem != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(problem, style: const TextStyle(fontSize: 12.5, color: AppColors.error)),
              ),
            const SizedBox(height: 14),
            ElevatedButton(
              onPressed: problem != null
                  ? null
                  : () => Navigator.of(context).pop(<String, dynamic>{
                        'approvedAmount': _amountV,
                        'interestMethod': _r.isAdvance ? 'None' : _method,
                        'interestRate': _r.isAdvance ? 0 : _rateV,
                        if (!_r.isAdvance) 'tenure': _tenureV,
                        if (!_r.isAdvance) 'recoveryMode': _recoveryMode,
                        if (_r.isAdvance) 'advanceRecovery': _recovery,
                        if (_remarks.text.trim().isNotEmpty) 'remarks': _remarks.text.trim(),
                      }),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 13),
              ),
              child: const Text('Approve', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      ),
    );
  }
}
