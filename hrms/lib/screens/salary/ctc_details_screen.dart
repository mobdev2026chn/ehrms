import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../config/app_colors.dart';
import '../../utils/salary_structure_calculator.dart';

/// CTC / template breakdown aligned with web HRMS "Template earnings" + deductions + gross + net + full CTC.
class CtcDetailsScreen extends StatefulWidget {
  const CtcDetailsScreen({
    super.key,
    required this.salary,
    this.onViewRevisionHistory,
    this.nextEffectiveDate,
  });

  final Map<String, dynamic> salary;
  final VoidCallback? onViewRevisionHistory;
  final DateTime? nextEffectiveDate;

  @override
  State<CtcDetailsScreen> createState() => _CtcDetailsScreenState();
}

class _CtcDetailsScreenState extends State<CtcDetailsScreen> {
  bool _templateOpen = false;
  bool _dedOpen = false;

  @override
  Widget build(BuildContext context) {
    final inputs = SalaryStructureInputs.fromMap(widget.salary);
    final calc = calculateSalaryStructure(inputs);
    final m = calc.monthly;
    final currency = NumberFormat.currency(locale: 'en_IN', symbol: '₹');
    final basic = m.basicSalary;
    final basicPlusDa = m.basicSalary + m.dearnessAllowance;
    final employeePfStatutory = basicPlusDa < 15000;

    final templateEarningsAnnual = m.grossSalary * 12;
    final deductionsAnnual = m.totalMonthlyDeductions * 12;
    final fillPrimaryLight = AppColors.primary.withOpacity(0.12);
    final fillWhite = AppColors.surface;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'CTC Details',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.nextEffectiveDate != null &&
              widget.onViewRevisionHistory != null) ...[
            _Banner(
              text:
                  'Salary is revised and will be effective from ${DateFormat('d MMM, y').format(widget.nextEffectiveDate!)}.',
              onLink: widget.onViewRevisionHistory!,
            ),
            const SizedBox(height: 12),
          ],
          _AccordionHeader(
            title: 'Template earnings',
            trailingAmount: currency.format(templateEarningsAnnual),
            expanded: _templateOpen,
            onTap: () => setState(() => _templateOpen = !_templateOpen),
          ),
          if (_templateOpen) ...[
            _componentBlock(
              'BASIC',
              m.basicSalary,
              basic,
              currency,
            ),
            _componentBlock(
              'DA (Dearness Allowance)',
              m.dearnessAllowance,
              basic,
              currency,
            ),
            _componentBlock(
              'HRA (House Rent Allowance)',
              m.houseRentAllowance,
              basic,
              currency,
            ),
            if (m.specialAllowance > 0)
              _componentBlock(
                'SPECIAL ALLOWANCE',
                m.specialAllowance,
                basic,
                currency,
              ),
            if ((inputs.mobileAllowanceType == 'monthly'
                    ? inputs.mobileAllowance
                    : inputs.mobileAllowance / 12) >
                0)
              _componentBlock(
                'MOBILE ALLOWANCE',
                inputs.mobileAllowanceType == 'monthly'
                    ? inputs.mobileAllowance
                    : inputs.mobileAllowance / 12,
                basic,
                currency,
              ),
            _componentBlock(
              'Employer PF (${kWebStatutoryPfPercentOnBasic.toStringAsFixed(0)}%)',
              m.employerPF,
              basic,
              currency,
              calculationNote:
                  '${kWebStatutoryPfPercentOnBasic.toStringAsFixed(0)}% of Basic (same statutory line as web template)',
            ),
            _componentBlock(
              'Employer ESI (${inputs.employerESIRate.toStringAsFixed(2)}%)',
              m.employerESI,
              basic,
              currency,
              calculationNote:
                  '${inputs.employerESIRate.toStringAsFixed(2)}% of (Basic+DA+HRA)',
            ),
            if (m.pfStaticAmount > 0)
              _componentBlock(
                'PF (static in gross)',
                m.pfStaticAmount,
                basic,
                currency,
                calculationNote: 'When employer PF % does not apply',
              ),
            const SizedBox(height: 8),
            _HighlightTotalRow(
              label: 'Gross Salary',
              monthly: m.grossSalary,
              yearly: m.grossSalary * 12,
              currency: currency,
              background: fillPrimaryLight,
            ),
            const Divider(height: 24),
          ],
          _AccordionHeader(
            title: 'Deductions',
            trailingAmount: currency.format(deductionsAnnual),
            expanded: _dedOpen,
            onTap: () => setState(() => _dedOpen = !_dedOpen),
          ),
          if (_dedOpen) ...[
            _componentBlock(
              employeePfStatutory
                  ? 'Employee PF (${kWebStatutoryPfPercentOnBasic.toStringAsFixed(0)}%)'
                  : 'Employee PF (fixed)',
              m.employeePF,
              basic,
              currency,
              calculationNote: employeePfStatutory
                  ? '${kWebStatutoryPfPercentOnBasic.toStringAsFixed(0)}% of Basic'
                  : 'Statutory ₹1,800 when Basic+DA ≥ ₹15,000',
            ),
            _componentBlock(
              'Employee ESI (${inputs.employeeESIRate.toStringAsFixed(2)}%)',
              m.employeeESI,
              basic,
              currency,
              calculationNote:
                  '${inputs.employeeESIRate.toStringAsFixed(2)}% of (Basic+DA+HRA)',
            ),
            const SizedBox(height: 8),
            _HighlightTotalRow(
              label: 'Total Deductions',
              monthly: m.totalMonthlyDeductions,
              yearly: m.totalMonthlyDeductions * 12,
              currency: currency,
              background: fillWhite,
            ),
            const Divider(height: 24),
          ],
          const SizedBox(height: 8),
          _SummaryCard(
            title: 'Gross Salary',
            monthly: m.grossSalary,
            annually: m.grossSalary * 12,
            currency: currency,
            background: fillPrimaryLight,
          ),
          const SizedBox(height: 12),
          _SummaryCard(
            title: 'Net Salary',
            monthly: m.netMonthlySalary,
            annually: calc.yearly.annualNetSalary,
            currency: currency,
            background: fillWhite,
          ),
          const SizedBox(height: 12),
          _SummaryCard(
            title: 'Total CTC (incl. benefits)',
            monthly: calc.totalCTC / 12,
            annually: calc.totalCTC,
            currency: currency,
            background: fillPrimaryLight,
            footnote:
                'Gratuity, statutory bonus, allowances and incentives included where applicable.',
          ),
        ],
      ),
    );
  }

  Widget _componentBlock(
    String title,
    double monthly,
    double basic,
    NumberFormat currency, {
    String? calculationNote,
  }) {
    final yearly = monthly * 12;
    final note = calculationNote ?? _calculationLabel(title, monthly, basic);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _col('Monthly', currency.format(monthly)),
              ),
              Expanded(
                child: _col('Yearly', currency.format(yearly)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Calculation: $note',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
        ],
      ),
    );
  }

  Widget _col(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
        ),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
      ],
    );
  }

  String _calculationLabel(String title, double monthly, double basic) {
    if (monthly == 0) {
      if (title.contains('MOBILE')) return 'Variable';
      return 'Fixed Amount';
    }
    if (basic > 0) {
      final r = monthly / basic;
      if ((r - 0.2).abs() < 0.02) return '20% of Basic';
      if ((r - 0.5).abs() < 0.02) return '50% of Basic';
    }
    return 'Fixed Amount';
  }
}

class _HighlightTotalRow extends StatelessWidget {
  const _HighlightTotalRow({
    required this.label,
    required this.monthly,
    required this.yearly,
    required this.currency,
    required this.background,
  });

  final String label;
  final double monthly;
  final double yearly;
  final NumberFormat currency;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _amount('Monthly', currency.format(monthly)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _amount('Yearly', currency.format(yearly)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _amount(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            maxLines: 1,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
          ),
        ),
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.text, required this.onLink});

  final String text;
  final VoidCallback onLink;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF9E6),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFFE082)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, color: Colors.amber.shade800, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  text,
                  style: const TextStyle(fontSize: 13, height: 1.35),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 28),
            child: GestureDetector(
              onTap: onLink,
              child: Text(
                'View Revision History',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.secondary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AccordionHeader extends StatelessWidget {
  const _AccordionHeader({
    required this.title,
    required this.trailingAmount,
    required this.expanded,
    required this.onTap,
  });

  final String title;
  final String trailingAmount;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
                Text(
                  trailingAmount,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  expanded ? Icons.expand_less : Icons.expand_more,
                  color: Colors.grey.shade600,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.title,
    required this.monthly,
    required this.annually,
    required this.currency,
    required this.background,
    this.footnote,
  });

  final String title;
  final double monthly;
  final double annually;
  final NumberFormat currency;
  final Color background;
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
              ),
              Icon(Icons.info_outline, size: 16, color: Colors.grey.shade700),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Monthly',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                    ),
                    Text(
                      currency.format(monthly),
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Annually',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                    ),
                    Text(
                      currency.format(annually),
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (footnote != null) ...[
            const SizedBox(height: 10),
            Text(
              footnote!,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade700, height: 1.3),
            ),
          ],
        ],
      ),
    );
  }
}
