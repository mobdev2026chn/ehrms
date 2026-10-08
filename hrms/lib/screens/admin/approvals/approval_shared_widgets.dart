// lib/screens/admin/approvals/approval_shared_widgets.dart
//
// Pieces shared by the admin approval screens: error/empty states, the reason prompt,
// a detail sheet that loads one request from the backend, and the reimbursement payout
// flow (the mobile counterpart of the web `approveAmountModal`).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../config/app_colors.dart';
import '../../../config/app_text_styles.dart';
import '../../../services/admin_approvals_service.dart';
import '../../../utils/snackbar_utils.dart';

/// Shows the backend message for [error] as an error SnackBar.
void showApprovalError(BuildContext context, Object error, {String fallback = 'Something went wrong. Please try again.'}) {
  SnackBarUtils.showSnackBar(context, AdminApprovalsService.messageOf(error, fallback: fallback), isError: true);
}

// ── Shared approval card look ───────────────────────────────────────────────
// Every admin approval screen builds its request cards from these pieces so the
// cards read the same everywhere: white, radius 16, hairline border, header row
// (avatar/icon tile + name + meta + status pill), detail rows, then an action row
// (Approve = success fill, Reject = error outline).

/// Hairline border used by approval cards.
const Color kApprovalBorder = Color(0xFFECEEF1);

/// Decoration for an approval request card.
BoxDecoration approvalCardDecoration({Color? borderColor}) => BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: borderColor ?? kApprovalBorder),
    );

/// Approve button style: success fill + white text.
ButtonStyle approvalApproveStyle() => ElevatedButton.styleFrom(
      backgroundColor: AppColors.success,
      foregroundColor: Colors.white,
      disabledBackgroundColor: AppColors.success.withValues(alpha: 0.4),
      disabledForegroundColor: Colors.white,
      elevation: 0,
      minimumSize: const Size(0, 44),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );

/// Reject button style: error outline + error text.
ButtonStyle approvalRejectStyle() => OutlinedButton.styleFrom(
      foregroundColor: AppColors.error,
      side: BorderSide(color: AppColors.error.withValues(alpha: 0.5), width: 1.2),
      minimumSize: const Size(0, 44),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );

/// Status pill coloured by [AppColors.statusStyle] ('Paid' uses the info pair).
/// [label] overrides the shown text.
class ApprovalStatusPill extends StatelessWidget {
  final String status;
  final String? label;
  const ApprovalStatusPill({super.key, required this.status, this.label});

  @override
  Widget build(BuildContext context) {
    final st = AppColors.statusStyle(status);
    final isPaid = status.toLowerCase() == 'paid';
    final fg = isPaid ? AppColors.info : st.fg;
    final bg = isPaid ? AppColors.infoBg : st.bg;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(
        label ?? st.label,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg),
      ),
    );
  }
}

/// 44px rounded tile with initials (or an icon) for the card header.
class ApprovalAvatar extends StatelessWidget {
  final String name;
  final String? initials;
  final IconData? icon;
  final Color? color;
  const ApprovalAvatar({super.key, required this.name, this.initials, this.icon, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.primaryText;
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    final shown = initials ??
        (parts.isEmpty
            ? '?'
            : (parts.length == 1 ? parts.first[0] : '${parts.first[0]}${parts.last[0]}').toUpperCase());
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
      child: icon != null
          ? Icon(icon, size: 22, color: c)
          : Text(shown, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c)),
    );
  }
}

/// Header row of an approval card: leading tile, name, meta line, trailing pill.
class ApprovalCardHeader extends StatelessWidget {
  final Widget leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  const ApprovalCardHeader({super.key, required this.leading, required this.title, this.subtitle, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        leading,
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.headingSmall),
              if (subtitle != null && subtitle!.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.bodySmall),
              ],
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 8),
          trailing!,
        ],
      ],
    );
  }
}

/// One label/value line inside an approval card.
class ApprovalDetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;
  final int? maxLines;
  const ApprovalDetailRow({super.key, required this.icon, required this.label, required this.value, this.valueColor, this.maxLines});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: AppColors.textCaption),
          const SizedBox(width: 8),
          Text('$label: ', style: AppTextStyles.bodySmall),
          Expanded(
            child: Text(
              value,
              maxLines: maxLines,
              overflow: maxLines == null ? null : TextOverflow.ellipsis,
              style: AppTextStyles.bodySmall.copyWith(
                color: valueColor ?? AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Centered empty state: 64 tinted circle + title + message.
class ApprovalEmptyView extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  const ApprovalEmptyView({super.key, required this.icon, required this.title, this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: Icon(icon, size: 30, color: AppColors.primaryText),
          ),
          const SizedBox(height: 16),
          Text(title, textAlign: TextAlign.center, style: AppTextStyles.headingSmall),
          if (message != null) ...[
            const SizedBox(height: 4),
            Text(message!, textAlign: TextAlign.center, style: AppTextStyles.bodySmall),
          ],
        ],
      ),
    );
  }
}

/// Full-width error block with a retry button, for a failed list load.
class ApprovalErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const ApprovalErrorView({super.key, required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      alignment: Alignment.center,
      decoration: approvalCardDecoration(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(color: AppColors.errorBg, shape: BoxShape.circle),
            child: const Icon(Icons.error_outline_rounded, size: 30, color: AppColors.error),
          ),
          const SizedBox(height: 16),
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Retry'),
            style: ElevatedButton.styleFrom(minimumSize: const Size(140, 44)),
          ),
        ],
      ),
    );
  }
}

/// Asks for a reason/remark. Returns the trimmed text, or null when dismissed.
Future<String?> showApprovalReasonDialog(
  BuildContext context, {
  required String title,
  String? subtitle,
  String actionLabel = 'Reject',
  Color actionColor = AppColors.error,
  String hint = 'Enter reason...',
  bool required = true,
  String initialText = '',
}) {
  final ctrl = TextEditingController(text: initialText);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(title, style: AppTextStyles.headingMedium),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (subtitle != null) ...[
            Text(subtitle, style: AppTextStyles.bodySmall),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: ctrl,
            maxLines: 3,
            autofocus: true,
            style: AppTextStyles.bodyMedium,
            decoration: InputDecoration(
              hintText: hint,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
        ),
        ElevatedButton(
          onPressed: () {
            final text = ctrl.text.trim();
            if (required && text.isEmpty) {
              SnackBarUtils.showSnackBar(ctx, 'Please enter a reason', isError: true);
              return;
            }
            Navigator.pop(ctx, text);
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: actionColor,
            foregroundColor: Colors.white,
            minimumSize: const Size(96, 44),
          ),
          child: Text(actionLabel),
        ),
      ],
    ),
  );
}

/// Formats an ISO date (or anything DateTime can parse) as `dd MMM yyyy`; passes others through.
String formatApprovalDate(dynamic raw) {
  if (raw == null) return '—';
  final s = raw.toString();
  if (s.isEmpty) return '—';
  final d = DateTime.tryParse(s);
  if (d == null) return s;
  return DateFormat('dd MMM yyyy').format(d.toLocal());
}

/// Name of a populated staff object (`staffId` on detail responses).
String approvalStaffName(dynamic staff, {String fallback = 'Staff Member'}) {
  if (staff is! Map) return fallback;
  final name = (staff['name'] ?? '').toString().trim();
  if (name.isNotEmpty) return name;
  final full = '${staff['firstName'] ?? ''} ${staff['lastName'] ?? ''}'.trim();
  return full.isNotEmpty ? full : fallback;
}

/// A bottom sheet that fetches one request with [loader] and renders the rows [buildRows]
/// returns. Loading, error (with retry) and the optional [actions] are handled here.
Future<void> showApprovalDetailSheet(
  BuildContext context, {
  required String title,
  required Future<Map<String, dynamic>> Function() loader,
  required List<MapEntry<String, String>> Function(Map<String, dynamic> data) buildRows,
  List<Widget> Function(BuildContext sheetCtx, Map<String, dynamic> data)? actions,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetCtx) => _ApprovalDetailSheet(title: title, loader: loader, buildRows: buildRows, actions: actions),
  );
}

class _ApprovalDetailSheet extends StatefulWidget {
  final String title;
  final Future<Map<String, dynamic>> Function() loader;
  final List<MapEntry<String, String>> Function(Map<String, dynamic> data) buildRows;
  final List<Widget> Function(BuildContext sheetCtx, Map<String, dynamic> data)? actions;

  const _ApprovalDetailSheet({required this.title, required this.loader, required this.buildRows, this.actions});

  @override
  State<_ApprovalDetailSheet> createState() => _ApprovalDetailSheetState();
}

class _ApprovalDetailSheetState extends State<_ApprovalDetailSheet> {
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.loader();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SheetHandle(),
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                  child: Icon(Icons.description_outlined, color: AppColors.primaryText, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(widget.title, style: AppTextStyles.headingMedium)),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 22, color: AppColors.textSecondary),
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 8),
            Flexible(
              child: FutureBuilder<Map<String, dynamic>>(
                future: _future,
                builder: (ctx, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return Padding(
                      padding: const EdgeInsets.all(32),
                      child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
                    );
                  }
                  if (snap.hasError) {
                    return ApprovalErrorView(
                      message: AdminApprovalsService.messageOf(snap.error!, fallback: 'Failed to load request details'),
                      onRetry: () => setState(() => _future = widget.loader()),
                    );
                  }
                  final data = snap.data ?? const <String, dynamic>{};
                  final rows = widget.buildRows(data);
                  final actionWidgets = widget.actions?.call(context, data) ?? const <Widget>[];
                  return SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ...rows.map((e) => _row(e.key, e.value)),
                        if (actionWidgets.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Row(children: actionWidgets),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 2, child: Text(label, style: AppTextStyles.bodySmall)),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: Text(
              value.isEmpty ? '—' : value,
              textAlign: TextAlign.end,
              style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// Small grab handle shown at the top of approval bottom sheets.
class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 40,
        height: 4,
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(999)),
      ),
    );
  }
}

// ── Reimbursement payout flow ───────────────────────────────────────────────

const List<String> _monthsFull = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

String _monthLabel(int year, int monthIndex) => '${_monthsFull[monthIndex]} $year';

String currentPayrollMonthLabel() {
  final now = DateTime.now();
  return _monthLabel(now.year, now.month - 1);
}

/// Payroll months from [joiningDate] through the current month, newest first (as the web
/// `monthLabelsFrom`). Always contains at least the current month.
List<String> payrollMonthOptions(dynamic joiningDate) {
  final now = DateTime.now();
  final endIndex = now.year * 12 + (now.month - 1);
  final from = joiningDate == null ? null : DateTime.tryParse(joiningDate.toString());
  final startIndex = from == null ? endIndex : from.year * 12 + (from.month - 1);
  if (startIndex > endIndex) return [currentPayrollMonthLabel()];
  final labels = <String>[];
  for (int i = endIndex; i >= startIndex; i--) {
    labels.add(_monthLabel(i ~/ 12, i % 12));
  }
  return labels.isEmpty ? [currentPayrollMonthLabel()] : labels;
}

/// Opens the payout workflow for an expense claim and, on confirm, calls
/// POST /admin/approvals/expense/:id/approve with the same body as the web modal.
/// Returns true when the backend accepted it.
Future<bool> showReimbursementPayoutSheet(
  BuildContext context, {
  required String expenseId,
  required String staffId,
  required String staffName,
  required double amount,
  String? claimUpiId,
  String? claimAccountNo,
  String? claimIfscCode,
}) async {
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ReimbursementPayoutSheet(
      expenseId: expenseId,
      staffId: staffId,
      staffName: staffName,
      amount: amount,
      claimUpiId: claimUpiId,
      claimAccountNo: claimAccountNo,
      claimIfscCode: claimIfscCode,
    ),
  );
  return ok == true;
}

class _ReimbursementPayoutSheet extends StatefulWidget {
  final String expenseId;
  final String staffId;
  final String staffName;
  final double amount;
  final String? claimUpiId;
  final String? claimAccountNo;
  final String? claimIfscCode;

  const _ReimbursementPayoutSheet({
    required this.expenseId,
    required this.staffId,
    required this.staffName,
    required this.amount,
    this.claimUpiId,
    this.claimAccountNo,
    this.claimIfscCode,
  });

  @override
  State<_ReimbursementPayoutSheet> createState() => _ReimbursementPayoutSheetState();
}

class _ReimbursementPayoutSheetState extends State<_ReimbursementPayoutSheet> {
  final AdminApprovalsService _service = AdminApprovalsService();
  static const int _maxProofBytes = 5 * 1024 * 1024;

  String _step = 'select'; // 'select' | 'payroll' | 'immediate'
  bool _loadingStaff = true;
  String? _staffLoadError;
  bool _submitting = false;

  List<String> _months = [currentPayrollMonthLabel()];
  String _payrollMonth = currentPayrollMonthLabel();
  String _upiId = '';
  String _accountNo = '';
  String _ifscCode = '';
  String? _proofDataUrl;
  String? _proofName;

  @override
  void initState() {
    super.initState();
    _upiId = widget.claimUpiId ?? '';
    _accountNo = widget.claimAccountNo ?? '';
    _ifscCode = widget.claimIfscCode ?? '';
    _loadStaff();
  }

  // Account details come from the staff profile (read-only) so the payout goes to the
  // account on record; the claim's stored values are the fallback, as on the web.
  Future<void> _loadStaff() async {
    if (widget.staffId.isEmpty) {
      setState(() => _loadingStaff = false);
      return;
    }
    try {
      final staff = await _service.getStaffProfile(widget.staffId);
      if (!mounted) return;
      final months = payrollMonthOptions(staff['joiningDate']);
      setState(() {
        _upiId = (staff['upiId'] ?? '').toString();
        _accountNo = (staff['accountNumber'] ?? '').toString();
        _ifscCode = (staff['ifscCode'] ?? '').toString();
        _months = months;
        if (!_months.contains(_payrollMonth)) _payrollMonth = _months.first;
        _loadingStaff = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingStaff = false;
        _staffLoadError = AdminApprovalsService.messageOf(e, fallback: 'Could not load the staff profile');
      });
    }
  }

  Future<void> _pickProof() async {
    try {
      final file = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 80);
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (bytes.length > _maxProofBytes) {
        if (mounted) SnackBarUtils.showSnackBar(context, 'File size exceeds 5MB limit.', isError: true);
        return;
      }
      final name = file.name;
      final ext = name.contains('.') ? name.split('.').last.toLowerCase() : 'jpeg';
      final mime = file.mimeType ?? (ext == 'png' ? 'image/png' : (ext == 'webp' ? 'image/webp' : 'image/jpeg'));
      if (!mounted) return;
      setState(() {
        _proofDataUrl = 'data:$mime;base64,${base64Encode(bytes)}';
        _proofName = name;
      });
    } catch (e) {
      if (mounted) SnackBarUtils.showSnackBar(context, 'Could not read the selected image', isError: true);
    }
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    final payroll = _step == 'payroll';
    try {
      final msg = await _service.approveExpense(
        widget.expenseId,
        paymentRoute: payroll ? 'Payroll' : 'Immediate',
        payrollMonth: payroll ? _payrollMonth : null,
        upiId: payroll ? null : _upiId,
        accountNo: payroll ? null : _accountNo,
        ifscCode: payroll ? null : _ifscCode,
        proofImg: payroll ? null : _proofDataUrl,
        remarks: 'Approved',
      );
      if (!mounted) return;
      SnackBarUtils.showSnackBar(context, msg);
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      showApprovalError(context, e, fallback: 'Failed to approve claim');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SheetHandle(),
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                      child: Icon(Icons.currency_rupee_rounded, size: 20, color: AppColors.primaryText),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text('Expense Claim Payout Workflow', style: AppTextStyles.headingMedium),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 22, color: AppColors.textSecondary),
                      tooltip: 'Close',
                      onPressed: _submitting ? null : () => Navigator.pop(context, false),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text('${widget.staffName} • ₹${widget.amount.toStringAsFixed(0)}',
                    style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 16),
                if (_step == 'select') _buildSelect(),
                if (_step == 'payroll') _buildPayroll(),
                if (_step == 'immediate') _buildImmediate(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _routeOption(IconData icon, String title, String sub, VoidCallback onTap) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: approvalCardDecoration(),
          child: Column(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, size: 24, color: AppColors.primaryText),
              ),
              const SizedBox(height: 12),
              Text(title, textAlign: TextAlign.center, style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(sub, textAlign: TextAlign.center, style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSelect() {
    return Row(
      children: [
        _routeOption(Icons.calendar_month_outlined, 'Add to Payroll', 'Disburse payout through the salary cycle',
            () => setState(() => _step = 'payroll')),
        const SizedBox(width: 12),
        _routeOption(Icons.account_balance_wallet_outlined, 'Immediate Payment', 'Pay now via bank transfer or UPI',
            () => setState(() => _step = 'immediate')),
      ],
    );
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t, style: AppTextStyles.sectionLabel.copyWith(color: AppColors.textSecondary)),
      );

  Widget _footer(String confirmLabel) {
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _submitting ? null : () => setState(() => _step = 'select'),
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
              child: const Text('Back'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton(
              onPressed: _submitting ? null : _submit,
              style: approvalApproveStyle().copyWith(minimumSize: const WidgetStatePropertyAll(Size(0, 48))),
              child: _submitting
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(confirmLabel),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPayroll() {
    final current = currentPayrollMonthLabel();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('SELECT PAYROLL MONTH'),
        Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(color: const Color(0xFFF7F8FA), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE2E5EA))),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _months.contains(_payrollMonth) ? _payrollMonth : _months.first,
              isExpanded: true,
              items: _months
                  .map((m) => DropdownMenuItem(
                        value: m,
                        child: Text(m == current ? '$m (Current Month)' : m, style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w500)),
                      ))
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => _payrollMonth = v);
              },
            ),
          ),
        ),
        if (_loadingStaff)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('Loading months from staff profile...', style: AppTextStyles.caption),
          ),
        _footer('Confirm & Add'),
      ],
    );
  }

  Widget _readOnly(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(label),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(color: AppColors.inputFill, borderRadius: BorderRadius.circular(12), border: Border.all(color: kApprovalBorder)),
          child: Text(
            value.isNotEmpty ? value : (_loadingStaff ? 'Loading...' : 'Not available'),
            style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w500, color: value.isNotEmpty ? AppColors.textPrimary : AppColors.textCaption),
          ),
        ),
      ],
    );
  }

  Widget _buildImmediate() {
    final noDetails = !_loadingStaff && _accountNo.isEmpty && _ifscCode.isEmpty && _upiId.isEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: approvalCardDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text('ACCOUNT DETAILS', style: AppTextStyles.sectionLabel.copyWith(color: AppColors.textSecondary))),
                  const Icon(Icons.lock_outline_rounded, size: 14, color: AppColors.textCaption),
                  const SizedBox(width: 4),
                  const Text('From staff profile', style: AppTextStyles.caption),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _readOnly('ACCOUNT NO.', _accountNo)),
                  const SizedBox(width: 12),
                  Expanded(child: _readOnly('IFSC CODE', _ifscCode)),
                ],
              ),
              const SizedBox(height: 12),
              _readOnly('UPI ID', _upiId),
              if (_staffLoadError != null) ...[
                const SizedBox(height: 8),
                Text('$_staffLoadError. Showing details stored on the claim.',
                    style: AppTextStyles.caption.copyWith(color: AppColors.warning, fontWeight: FontWeight.w600)),
              ],
              if (noDetails) ...[
                const SizedBox(height: 8),
                const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_amber_rounded, size: 16, color: AppColors.warning),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'No bank or UPI details on this staff profile. Add them to the staff profile before recording an immediate payment.',
                        style: TextStyle(fontSize: 12, height: 1.3, color: AppColors.warning, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        _label('PAYMENT PROOF RECEIPT'),
        InkWell(
          onTap: _submitting ? null : _pickProof,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _proofDataUrl != null ? AppColors.successBg.withValues(alpha: 0.5) : const Color(0xFFF7F8FA),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _proofDataUrl != null ? AppColors.success.withValues(alpha: 0.4) : const Color(0xFFE2E5EA)),
            ),
            child: _proofDataUrl == null
                ? const Column(
                    children: [
                      Icon(Icons.upload_rounded, size: 24, color: AppColors.textSecondary),
                      SizedBox(height: 8),
                      Text('Upload Transaction Proof', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                      SizedBox(height: 2),
                      Text('Images up to 5MB', style: AppTextStyles.bodySmall),
                    ],
                  )
                : Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.memory(
                          base64Decode(_proofDataUrl!.split(',').last),
                          width: 48,
                          height: 48,
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(_proofName ?? 'proof_attachment.jpg',
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.success)),
                      ),
                      TextButton(
                        onPressed: _submitting ? null : () => setState(() {
                          _proofDataUrl = null;
                          _proofName = null;
                        }),
                        child: const Text('Remove', style: TextStyle(fontSize: 13, color: AppColors.error, fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
          ),
        ),
        _footer('Confirm Payment'),
      ],
    );
  }
}
