import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../config/app_colors.dart';
import '../../config/app_text_styles.dart';
import '../../widgets/app_card.dart';
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
    final fillPrimaryLight = AppColors.primary.withValues(alpha: 0.10);
    final fillWhite = AppColors.surface;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('CTC Details'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
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
            const SizedBox(height: 16),
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
            const SizedBox(height: 16),
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
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFECEEF1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTextStyles.label.copyWith(
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _col('Monthly', currency.format(monthly)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _col('Yearly', currency.format(yearly)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 1),
                child: Icon(Icons.functions_rounded,
                    size: 14, color: AppColors.textCaption),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Calculation: $note',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
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
          style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w600),
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFECEEF1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTextStyles.headingSmall,
          ),
          const SizedBox(height: 12),
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
          style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            maxLines: 1,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 16,
              color: AppColors.textPrimary,
            ),
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.brandLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.brandBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline_rounded,
                  color: AppColors.brandDark, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  text,
                  style: AppTextStyles.bodyMedium.copyWith(fontSize: 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 28),
            child: GestureDetector(
              onTap: onLink,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'View Revision History',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primaryText,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(Icons.chevron_right_rounded,
                      size: 18, color: AppColors.primaryText),
                ],
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
        color: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFECEEF1)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: AppTextStyles.headingSmall,
                  ),
                ),
                Text(
                  trailingAmount,
                  style: AppTextStyles.bodyMedium.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedRotation(
                  turns: expanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: const Icon(
                    Icons.expand_more_rounded,
                    color: AppColors.textSecondary,
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
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFECEEF1)),
        boxShadow: kSoftCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: AppTextStyles.headingSmall,
                ),
              ),
              const Icon(Icons.info_outline_rounded,
                  size: 18, color: AppColors.textSecondary),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Monthly',
                      style: AppTextStyles.caption
                          .copyWith(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        currency.format(monthly),
                        maxLines: 1,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 18,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Annually',
                      style: AppTextStyles.caption
                          .copyWith(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        currency.format(annually),
                        maxLines: 1,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 18,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (footnote != null) ...[
            const SizedBox(height: 12),
            Text(
              footnote!,
              style: AppTextStyles.caption.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
