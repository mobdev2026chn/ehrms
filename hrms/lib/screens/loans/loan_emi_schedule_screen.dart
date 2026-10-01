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
        title: const Text('EMI Schedule', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (loans.isEmpty)
            const LoanCard(
              child: Center(child: Text('No active loans.', style: TextStyle(color: AppColors.textSecondary))),
            ),
          for (final l in loans) ...[
            LoanSectionTitle('${l.isAdvance ? 'Salary Advance' : l.loanType} · ${l.loanNo}'),
            LoanCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(child: LoanStat('EMI', loanMoney(l.emiAmount))),
                    Expanded(child: LoanStat('Paid', '${l.paidEmis} / ${l.tenure}')),
                    Expanded(child: LoanStat('Outstanding', loanMoney(l.outstanding))),
                  ]),
                  const SizedBox(height: 8),
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
