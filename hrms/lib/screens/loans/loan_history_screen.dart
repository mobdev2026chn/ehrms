// "Loan History" (web /staff/loans/history): finished loans (completed, closed,
// cancelled, defaulted) and requests that never became a loan (rejected, cancelled).

import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../config/app_text_styles.dart';
import '../../models/loan_models.dart';
import 'loan_detail_screen.dart';
import 'loan_request_detail_screen.dart';
import 'loan_widgets.dart';

class LoanHistoryScreen extends StatelessWidget {
  const LoanHistoryScreen({super.key, required this.loans, required this.requests});
  final List<Loan> loans;
  final List<LoanRequest> requests;

  @override
  Widget build(BuildContext context) {
    final finished = loans.where((l) => !l.isLive).toList();
    final closedRequests = requests.where((r) => !r.isOpen && r.loanId.isEmpty).toList();
    // One list, newest first.
    final rows = <(DateTime?, Widget)>[
      for (final l in finished)
        (
          l.disbursedOn ?? l.recoveryEnd,
          _row(
            context,
            title: l.isAdvance ? 'Salary Advance' : l.loanType,
            sub: '${l.loanNo} · ${loanMoney(l.principal)}',
            status: l.status,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => LoanDetailScreen(loanId: l.id))),
          )
        ),
      for (final r in closedRequests)
        (
          r.appliedOn,
          _row(
            context,
            title: r.isAdvance ? 'Salary Advance' : r.loanType,
            sub: '${r.requestNo} · ${loanMoney(r.requestedAmount)} · Applied ${loanDate(r.appliedOn)}',
            status: r.status,
            onTap: () =>
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => LoanRequestDetailScreen(requestId: r.id))),
          )
        ),
    ]..sort((a, b) => (b.$1 ?? DateTime(1970)).compareTo(a.$1 ?? DateTime(1970)));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Loan History'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: rows.isEmpty
            ? [
                const LoanCard(
                  padding: EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                  child: LoanEmptyState(Icons.history_rounded, 'No loan history yet'),
                ),
              ]
            : [for (final r in rows) Padding(padding: const EdgeInsets.only(bottom: 12), child: r.$2)],
      ),
    );
  }

  Widget _row(BuildContext context,
          {required String title, required String sub, required String status, required VoidCallback onTap}) =>
      LoanCard(
        onTap: onTap,
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.label.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(sub, style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary)),
            ]),
          ),
          const SizedBox(width: 8),
          LoanStatusChip(status),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right_rounded, color: AppColors.textCaption),
        ]),
      );
}
