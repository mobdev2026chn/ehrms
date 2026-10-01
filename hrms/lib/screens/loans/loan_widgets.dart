// Shared building blocks for the loan screens (staff and admin): money / date
// formatting, status chips, the approval tracker, EMI schedule and ledger lists.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/app_colors.dart';
import '../../models/loan_models.dart';

final _money = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
final _money2 = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);

String loanMoney(num v, {bool paise = false}) => (paise ? _money2 : _money).format(v);
String loanDate(DateTime? d) => d == null ? '—' : DateFormat('d MMM yyyy').format(d);

/// 'SalaryAdvance' → 'Salary Advance'.
String loanCategoryLabel(String category) => category == 'SalaryAdvance' ? 'Salary Advance' : 'Loan';

/// Status colours: green done/approved, gold in progress, red refused/overdue, grey closed.
({Color fg, Color bg}) loanStatusColors(String status) {
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.fg.withValues(alpha: 0.35)),
      ),
      // Upper-case pill like the web ("● PENDING").
      child: Text('● ${status.toUpperCase()}',
          style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.4, color: c.fg)),
    );
  }
}

/// White rounded card used across the loan screens.
class LoanCard extends StatelessWidget {
  const LoanCard({super.key, required this.child, this.onTap, this.padding = const EdgeInsets.all(14)});
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.divider),
          ),
          child: child,
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
        padding: const EdgeInsets.fromLTRB(2, 18, 2, 8),
        child: Text(text, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
      );
}

/// Label / value pair on one line.
class LoanInfoRow extends StatelessWidget {
  const LoanInfoRow(this.label, this.value, {super.key, this.valueColor});
  final String label, value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 4, child: Text(label, style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary))),
            Expanded(
              flex: 6,
              child: Text(
                value.isEmpty ? '—' : value,
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: valueColor ?? AppColors.textPrimary),
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
      return const Text('No approval levels.', style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary));
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
              Icon(icon, size: 20, color: c.fg),
              if (!last) Expanded(child: Container(width: 2, color: AppColors.divider)),
            ],
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(a.level,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                      ),
                      LoanStatusChip(a.decision),
                    ],
                  ),
                  if (a.approverName.isNotEmpty || a.decidedAt != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        [if (a.approverName.isNotEmpty) a.approverName, if (a.decidedAt != null) loanDate(a.decidedAt)].join(' · '),
                        style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
                      ),
                    ),
                  if (a.approvedAmount != null)
                    Text('Approved amount: ${loanMoney(a.approvedAmount!)}',
                        style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
                  if (a.remarks.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text('“${a.remarks}”', style: const TextStyle(fontSize: 12, color: AppColors.textPrimary)),
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
      return const Text('No schedule yet.', style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary));
    }
    return Column(
      children: [
        for (final e in schedule)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.divider))),
            child: Row(
              children: [
                SizedBox(
                  width: 28,
                  child: Text('#${e.no}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(loanDate(e.dueDate), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                      Text(
                        'Principal ${loanMoney(e.principal)} · Interest ${loanMoney(e.interest)}',
                        style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                      ),
                      if (e.paid > 0 && e.paid < e.total)
                        Text('Paid ${loanMoney(e.paid)}', style: const TextStyle(fontSize: 11, color: AppColors.success)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(loanMoney(e.total), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                    if (showStatus) ...[const SizedBox(height: 3), LoanStatusChip(e.status)],
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
      return const Text('No ledger entries yet.', style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary));
    }
    return Column(
      children: [
        for (final l in ledger)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.divider))),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l.description.isEmpty ? l.mode : l.description,
                          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                      Text(
                        [loanDate(l.date), if (l.mode.isNotEmpty) l.mode, if (l.reference.isNotEmpty) l.reference].join(' · '),
                        style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      l.credit > 0 ? '− ${loanMoney(l.credit)}' : '+ ${loanMoney(l.debit)}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: l.credit > 0 ? AppColors.success : AppColors.textPrimary,
                      ),
                    ),
                    Text('Bal ${loanMoney(l.balance)}', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
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
      return const Text('No documents.', style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary));
    }
    return Column(
      children: [
        for (final d in documents)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              d.name.toLowerCase().endsWith('.pdf') ? Icons.picture_as_pdf_outlined : Icons.image_outlined,
              color: AppColors.textSecondary,
            ),
            title: Text(d.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
            subtitle: Text([if (d.type.isNotEmpty) d.type, if (d.uploadedAt != null) loanDate(d.uploadedAt)].join(' · '),
                style: const TextStyle(fontSize: 11.5)),
            trailing: const Icon(Icons.open_in_new_rounded, size: 18),
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
          Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
          const SizedBox(height: 3),
          Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: color ?? AppColors.textPrimary)),
        ],
      );
}
