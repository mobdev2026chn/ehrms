// Staff request status / approval tracker (GET /staff/loans/requests/:id) with Cancel
// (POST …/cancel) and the clarification reply (POST …/clarification), like the web.

import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../models/loan_models.dart';
import '../../services/loan_service.dart';
import '../../utils/error_message_utils.dart';
import '../../utils/snackbar_utils.dart';
import '../../widgets/app_tab_loader.dart';
import 'loan_detail_screen.dart';
import 'loan_widgets.dart';

class LoanRequestDetailScreen extends StatefulWidget {
  const LoanRequestDetailScreen({super.key, required this.requestId});
  final String requestId;

  @override
  State<LoanRequestDetailScreen> createState() => _LoanRequestDetailScreenState();
}

class _LoanRequestDetailScreenState extends State<LoanRequestDetailScreen> {
  final _service = LoanService();
  final _reply = TextEditingController();
  LoanRequest? _request;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await _service.getMyRequest(widget.requestId);
      if (mounted) setState(() => _request = r);
    } catch (e) {
      if (mounted) setState(() => _error = ErrorMessageUtils.toUserFriendlyMessage(e));
    }
  }

  Future<void> _cancel() async {
    final reasonCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel this request?'),
        content: TextField(
          controller: reasonCtrl,
          decoration: const InputDecoration(labelText: 'Reason (optional)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Cancel request'),
          ),
        ],
      ),
    );
    final reason = reasonCtrl.text.trim();
    reasonCtrl.dispose();
    if (ok != true) return;
    await _run(() => _service.cancelRequest(widget.requestId, reason: reason), 'Request cancelled.');
  }

  Future<void> _sendReply() async {
    final msg = _reply.text.trim();
    if (msg.isEmpty) {
      SnackBarUtils.showSnackBar(context, 'Write your reply first.', isError: true);
      return;
    }
    await _run(() => _service.replyClarification(widget.requestId, msg), 'Reply sent to the approver.');
    _reply.clear();
  }

  Future<void> _run(Future<LoanRequest> Function() action, String done) async {
    setState(() => _busy = true);
    try {
      final r = await action();
      if (!mounted) return;
      setState(() {
        _request = r;
        _busy = false;
      });
      SnackBarUtils.showSnackBar(context, done);
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
        title: Text(r?.requestNo ?? 'Request', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
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
          : RefreshIndicator(
              color: AppColors.primary,
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  LoanCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(r.isAdvance ? 'Salary Advance' : r.loanType,
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                            ),
                            LoanStatusChip(r.status),
                          ],
                        ),
                        const SizedBox(height: 8),
                        LoanInfoRow('Amount requested', loanMoney(r.requestedAmount)),
                        if (r.isAdvance)
                          LoanInfoRow('Recovery', r.advanceRecovery)
                        else
                          LoanInfoRow('Preferred tenure', r.preferredTenure > 0 ? '${r.preferredTenure} months' : ''),
                        LoanInfoRow('Purpose', r.purpose),
                        LoanInfoRow('Reason', r.reason),
                        LoanInfoRow('Applied on', loanDate(r.appliedOn)),
                        if (r.requiredBy != null) LoanInfoRow('Required by', loanDate(r.requiredBy)),
                        if (r.loanStatus.isNotEmpty) LoanInfoRow('Loan status', r.loanStatus),
                        if (r.disbursedOn != null) LoanInfoRow('Disbursed on', loanDate(r.disbursedOn)),
                      ],
                    ),
                  ),
                  if (r.needsClarification) _clarificationCard(r),
                  const LoanSectionTitle('Approval progress'),
                  LoanCard(child: LoanApprovalTracker(r.approvals, currentLevel: r.currentLevel)),
                  if (r.documents.isNotEmpty) ...[
                    const LoanSectionTitle('Documents'),
                    LoanCard(child: LoanDocumentList(r.documents)),
                  ],
                  const SizedBox(height: 18),
                  if (r.loanId.isNotEmpty)
                    ElevatedButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => LoanDetailScreen(loanId: r.loanId)),
                      ),
                      icon: const Icon(Icons.receipt_long_outlined, size: 18),
                      label: const Text('View loan & EMI schedule'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  if (r.canCancel)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: OutlinedButton(
                        onPressed: _busy ? null : _cancel,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.error,
                          side: const BorderSide(color: AppColors.errorBg),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Cancel request'),
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _clarificationCard(LoanRequest r) => Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: AppColors.infoBg, borderRadius: BorderRadius.circular(14)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(children: [
                Icon(Icons.help_outline_rounded, size: 18, color: AppColors.info),
                SizedBox(width: 6),
                Text('The approver needs more information',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.info)),
              ]),
              if (r.clarificationQuestion.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text('“${r.clarificationQuestion}”', style: const TextStyle(fontSize: 13)),
              ],
              const SizedBox(height: 10),
              TextField(
                controller: _reply,
                minLines: 2,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: 'Your reply',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton(
                  onPressed: _busy ? null : _sendReply,
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.info, foregroundColor: Colors.white),
                  child: const Text('Send reply'),
                ),
              ),
            ],
          ),
        ),
      );
}
