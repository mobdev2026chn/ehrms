// Shared building blocks for the loan screens (staff and admin): money / date
// formatting, status chips, the approval tracker, EMI schedule and ledger lists.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/app_colors.dart';
import '../../config/app_text_styles.dart';
import '../../models/loan_models.dart';
import '../../widgets/app_card.dart';

final _money = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
final _money2 = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);

String loanMoney(num v, {bool paise = false}) => (paise ? _money2 : _money).format(v);
String loanDate(DateTime? d) => d == null ? '—' : DateFormat('d MMM yyyy').format(d);

/// 'SalaryAdvance' → 'Salary Advance'.
String loanCategoryLabel(String category) => category == 'SalaryAdvance' ? 'Salary Advance' : 'Loan';

/// Hairline border for loan cards and list rows.
const Color kLoanHairline = Color(0xFFECEEF1);

/// Status colours: green done/approved, gold in progress, red refused/overdue, grey closed.
({Color fg, Color bg}) loanStatusColors(String status) {
  // The app-wide pill colours for the shared statuses (Approved / Pending /
  // Rejected / Under Review); loan-specific statuses fall through to the switch.
  final shared = AppColors.statusStyle(status);
  if (shared.fg != AppColors.textSecondary) return (fg: shared.fg, bg: shared.bg);
  switch (status) {
    case 'Approved':
    case 'Disbursed':
    case 'Active':
    case 'Paid':
    case 'Completed':
      return (fg: AppColors.success, bg: AppColors.successBg);
    case 'Rejected':
    case 'Defaulted':
    case 'Overdue':
      return (fg: AppColors.error, bg: AppColors.errorBg);
    case 'Cancelled':
    case 'Closed':
    case 'Skipped':
      return (fg: AppColors.textSecondary, bg: AppColors.inputFill);
    case 'Need Clarification':
    case 'Clarification':
    case 'Partial':
    case 'Due':
      return (fg: AppColors.info, bg: AppColors.infoBg);
    default: // Pending, Manager/HR/Finance Approved, Upcoming
      return (fg: AppColors.brandDark, bg: AppColors.brandLight);
  }
}

class LoanStatusChip extends StatelessWidget {
  const LoanStatusChip(this.status, {super.key});
  final String status;

  @override
  Widget build(BuildContext context) {
    final c = loanStatusColors(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: BorderRadius.circular(999),
      ),
      // Upper-case pill like the web ("● PENDING").
      child: Text('● ${status.toUpperCase()}',
          style: AppTextStyles.caption.copyWith(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.4, color: c.fg)),
    );
  }
}

/// White rounded card used across the loan screens.
class LoanCard extends StatelessWidget {
  const LoanCard({super.key, required this.child, this.onTap, this.padding = const EdgeInsets.all(16)});
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(16);
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: radius, boxShadow: kSoftCardShadow),
      child: Material(
        color: AppColors.surface,
        borderRadius: radius,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(color: kLoanHairline),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class LoanSectionTitle extends StatelessWidget {
  const LoanSectionTitle(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 24, 4, 12),
        child: Text(text, style: AppTextStyles.headingSmall),
      );
}

/// Centered empty state: a tinted icon circle above a short title.
class LoanEmptyState extends StatelessWidget {
  const LoanEmptyState(this.icon, this.title, {super.key});
  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.primaryText;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.12), shape: BoxShape.circle),
              child: Icon(icon, size: 28, color: c),
            ),
            const SizedBox(height: 12),
            Text(title, textAlign: TextAlign.center, style: AppTextStyles.headingSmall),
          ],
        ),
      ),
    );
  }
}

/// Label / value pair on one line.
class LoanInfoRow extends StatelessWidget {
  const LoanInfoRow(this.label, this.value, {super.key, this.valueColor});
  final String label, value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 4, child: Text(label, style: AppTextStyles.bodySmall)),
            const SizedBox(width: 12),
            Expanded(
              flex: 6,
              child: Text(
                value.isEmpty ? '—' : value,
                textAlign: TextAlign.right,
                style: AppTextStyles.label.copyWith(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: valueColor ?? AppColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      );
}

/// Each approval level and its decision, in order.
class LoanApprovalTracker extends StatelessWidget {
  const LoanApprovalTracker(this.approvals, {super.key, this.currentLevel = ''});
  final List<LoanApproval> approvals;
  final String currentLevel;

  @override
  Widget build(BuildContext context) {
    if (approvals.isEmpty) {
      return const Text('No approval levels.', style: AppTextStyles.bodySmall);
    }
    return Column(
      children: [
        for (var i = 0; i < approvals.length; i++) _step(approvals[i], i == approvals.length - 1),
      ],
    );
  }

  Widget _step(LoanApproval a, bool last) {
    final c = loanStatusColors(a.decision == 'Approved' ? 'Approved' : a.decision);
    final icon = switch (a.decision) {
      'Approved' => Icons.check_circle_rounded,
      'Rejected' => Icons.cancel_rounded,
      'Clarification' => Icons.help_rounded,
      'Skipped' => Icons.remove_circle_outline_rounded,
      _ => a.level == currentLevel ? Icons.timelapse_rounded : Icons.radio_button_unchecked_rounded,
    };
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(color: c.bg, shape: BoxShape.circle),
                child: Icon(icon, size: 18, color: c.fg),
              ),
              if (!last)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    decoration: BoxDecoration(color: kLoanHairline, borderRadius: BorderRadius.circular(1)),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(a.level, style: AppTextStyles.label.copyWith(fontWeight: FontWeight.w600)),
                      ),
                      const SizedBox(width: 8),
                      LoanStatusChip(a.decision),
                    ],
                  ),
                  if (a.approverName.isNotEmpty || a.decidedAt != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        [if (a.approverName.isNotEmpty) a.approverName, if (a.decidedAt != null) loanDate(a.decidedAt)].join(' · '),
                        style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
                      ),
                    ),
                  if (a.approvedAmount != null)
                    Text('Approved amount: ${loanMoney(a.approvedAmount!)}',
                        style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary)),
                  if (a.remarks.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(10)),
                      child: Text('“${a.remarks}”', style: AppTextStyles.bodySmall.copyWith(color: AppColors.textPrimary)),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// EMI schedule rows (used for the live schedule and the pre-apply estimate).
class LoanScheduleList extends StatelessWidget {
  const LoanScheduleList(this.schedule, {super.key, this.showStatus = true});
  final List<EmiInstallment> schedule;
  final bool showStatus;

  @override
  Widget build(BuildContext context) {
    if (schedule.isEmpty) {
      return const Text('No schedule yet.', style: AppTextStyles.bodySmall);
    }
    return Column(
      children: [
        for (final e in schedule)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: kLoanHairline))),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  margin: const EdgeInsets.only(right: 12),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(10)),
                  child: Text('#${e.no}',
                      style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(loanDate(e.dueDate), style: AppTextStyles.label.copyWith(fontSize: 13.5, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(
                        'Principal ${loanMoney(e.principal)} · Interest ${loanMoney(e.interest)}',
                        style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
                      ),
                      if (e.paid > 0 && e.paid < e.total)
                        Text('Paid ${loanMoney(e.paid)}',
                            style: AppTextStyles.caption.copyWith(color: AppColors.success, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(loanMoney(e.total), style: AppTextStyles.label.copyWith(fontWeight: FontWeight.w700)),
                    if (showStatus) ...[const SizedBox(height: 4), LoanStatusChip(e.status)],
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Ledger lines: debits (disbursed) and credits (recovered) with the running balance.
class LoanLedgerList extends StatelessWidget {
  const LoanLedgerList(this.ledger, {super.key});
  final List<LedgerEntry> ledger;

  @override
  Widget build(BuildContext context) {
    if (ledger.isEmpty) {
      return const Text('No ledger entries yet.', style: AppTextStyles.bodySmall);
    }
    return Column(
      children: [
        for (final l in ledger)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: kLoanHairline))),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l.description.isEmpty ? l.mode : l.description,
                          style: AppTextStyles.label.copyWith(fontSize: 13.5, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(
                        [loanDate(l.date), if (l.mode.isNotEmpty) l.mode, if (l.reference.isNotEmpty) l.reference].join(' · '),
                        style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      l.credit > 0 ? '− ${loanMoney(l.credit)}' : '+ ${loanMoney(l.debit)}',
                      style: AppTextStyles.label.copyWith(
                        fontWeight: FontWeight.w700,
                        color: l.credit > 0 ? AppColors.success : AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text('Bal ${loanMoney(l.balance)}', style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary)),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Attached documents; tap opens the file (browser / viewer).
class LoanDocumentList extends StatelessWidget {
  const LoanDocumentList(this.documents, {super.key});
  final List<LoanDocument> documents;

  @override
  Widget build(BuildContext context) {
    if (documents.isEmpty) {
      return const Text('No documents.', style: AppTextStyles.bodySmall);
    }
    return Column(
      children: [
        for (final d in documents)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(12)),
              child: Icon(
                d.name.toLowerCase().endsWith('.pdf') ? Icons.picture_as_pdf_outlined : Icons.image_outlined,
                size: 20,
                color: AppColors.textSecondary,
              ),
            ),
            title: Text(
              d.name,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.label.copyWith(fontSize: 13.5, fontWeight: FontWeight.w600),
            ),
            subtitle: Text([if (d.type.isNotEmpty) d.type, if (d.uploadedAt != null) loanDate(d.uploadedAt)].join(' · '),
                style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary)),
            trailing: const Icon(Icons.open_in_new_rounded, size: 18, color: AppColors.textSecondary),
            onTap: d.url.isEmpty
                ? null
                : () => launchUrl(Uri.parse(d.url), mode: LaunchMode.externalApplication),
          ),
      ],
    );
  }
}

/// Small summary tile: label above a bold value.
class LoanStat extends StatelessWidget {
  const LoanStat(this.label, this.value, {super.key, this.color});
  final String label, value;
  final Color? color;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: 4),
          Text(
            value,
            style: AppTextStyles.headingSmall.copyWith(fontWeight: FontWeight.w700, color: color ?? AppColors.textPrimary),
          ),
        ],
      );
}
