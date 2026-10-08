// "EMI Schedule": the repayment schedule of every active loan / advance.

import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../models/loan_models.dart';
import 'loan_widgets.dart';

class LoanEmiScheduleScreen extends StatelessWidget {
  const LoanEmiScheduleScreen({super.key, required this.loans});
  final List<Loan> loans;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('EMI Schedule'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          if (loans.isEmpty) ...[
            const SizedBox(height: 16),
            const LoanCard(
              padding: EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              child: LoanEmptyState(Icons.event_note_outlined, 'No active loans.'),
            ),
          ],
          for (final l in loans) ...[
            LoanSectionTitle('${l.isAdvance ? 'Salary Advance' : l.loanType} · ${l.loanNo}'),
            LoanCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(12)),
                    child: Row(children: [
                      Expanded(child: LoanStat('EMI', loanMoney(l.emiAmount))),
                      Expanded(child: LoanStat('Paid', '${l.paidEmis} / ${l.tenure}')),
                      Expanded(child: LoanStat('Outstanding', loanMoney(l.outstanding))),
                    ]),
                  ),
                  const SizedBox(height: 4),
                  LoanScheduleList(l.schedule),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
