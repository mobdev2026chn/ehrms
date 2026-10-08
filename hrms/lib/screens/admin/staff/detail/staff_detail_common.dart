// Shared helpers and small widgets for the admin Staff Detail tabs.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../config/app_colors.dart';
import '../../../../config/app_text_styles.dart';
import '../../../../services/admin_staff_detail_service.dart';
import '../../../../utils/snackbar_utils.dart';
import '../../../../widgets/app_tab_loader.dart';

// Staff-detail palette, aliased to the EktaHR design tokens.
const Color kSdInk = AppColors.textPrimary;
const Color kSdMuted = AppColors.textSecondary;
const Color kSdSubtle = AppColors.textCaption;
const Color kSdLine = Color(0xFFE2E5EA);
const Color kSdSoft = AppColors.inputFill;
const Color kSdBg = Color(0xFFF7F8FA);

/// Hairline border used on detail cards.
const Color kSdHairline = Color(0xFFECEEF1);

/// Message to show for any error thrown by the detail service (or anything else).
String sdErrorText(Object e) {
  if (e is StaffDetailApiException) return e.message;
  return 'Something went wrong. Please try again.';
}

void sdShowError(BuildContext context, Object e) {
  SnackBarUtils.showSnackBar(context, sdErrorText(e), isError: true);
}

void sdShowSuccess(BuildContext context, String message) {
  SnackBarUtils.showSnackBar(context, message);
}

String sdStr(dynamic v, [String fallback = '']) {
  if (v == null) return fallback;
  final s = v.toString().trim();
  return s.isEmpty ? fallback : s;
}

double sdNum(dynamic v) {
  if (v is num) return v.toDouble();
  return double.tryParse(v?.toString() ?? '') ?? 0;
}

String sdId(dynamic v) {
  if (v is Map) return sdStr(v['_id'] ?? v['id']);
  return sdStr(v);
}

DateTime? sdDate(dynamic v) {
  final s = sdStr(v);
  if (s.isEmpty) return null;
  return DateTime.tryParse(s)?.toLocal();
}

String sdFmtDate(dynamic v, [String pattern = 'dd MMM yyyy']) {
  final d = v is DateTime ? v : sdDate(v);
  if (d == null) return '-';
  return DateFormat(pattern).format(d);
}

/// YYYY-MM-DD for a calendar date (no timezone shift).
String sdKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// YYYY-MM-DD from a stored ISO date: the date part as written, so a UTC midnight
/// does not slide to the previous day.
String sdIsoKey(dynamic v) {
  final s = sdStr(v);
  if (s.length >= 10 && RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(s)) return s.substring(0, 10);
  final d = sdDate(v);
  return d == null ? '' : sdKey(d);
}

final NumberFormat _inr = NumberFormat.currency(locale: 'en_IN', symbol: '₹ ', decimalDigits: 2);
String sdMoney(dynamic v) => _inr.format(sdNum(v));

String sdStaffName(Map<String, dynamic> s) {
  final n = sdStr(s['name']);
  if (n.isNotEmpty) return n;
  return '${sdStr(s['firstName'])} ${sdStr(s['lastName'])}'.trim();
}

class SdLoading extends StatelessWidget {
  const SdLoading({super.key});
  @override
  Widget build(BuildContext context) =>
      const Padding(padding: EdgeInsets.symmetric(vertical: 48), child: Center(child: AppTabLoader()));
}

class SdErrorView extends StatelessWidget {
  const SdErrorView({super.key, required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
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
          Text(message, textAlign: TextAlign.center, style: AppTextStyles.bodySmall),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

class SdEmptyView extends StatelessWidget {
  const SdEmptyView({super.key, required this.message, this.icon = Icons.inbox_outlined, this.detail});
  final String message;
  final String? detail;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
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
          Text(message, textAlign: TextAlign.center, style: AppTextStyles.headingSmall),
          if (detail != null) ...[
            const SizedBox(height: 4),
            Text(detail!, textAlign: TextAlign.center, style: AppTextStyles.bodySmall),
          ],
        ],
      ),
    );
  }
}

class SdCard extends StatelessWidget {
  const SdCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.margin});
  final Widget child;
  final EdgeInsets padding;
  final EdgeInsets? margin;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin ?? const EdgeInsets.only(bottom: 12),
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kSdHairline),
        boxShadow: const [BoxShadow(color: Color(0x08000000), blurRadius: 10, offset: Offset(0, 3))],
      ),
      child: child,
    );
  }
}

class SdSectionTitle extends StatelessWidget {
  const SdSectionTitle(this.title, {super.key, this.trailing, this.icon});
  final String title;
  final Widget? trailing;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          if (icon != null) ...[
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: AppColors.primaryText),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Text(title, style: AppTextStyles.headingSmall),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class SdKeyValue extends StatelessWidget {
  const SdKeyValue(this.label, this.value, {super.key});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(label, style: AppTextStyles.bodySmall),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(value.isEmpty ? '-' : value,
                style: AppTextStyles.bodyMedium.copyWith(fontSize: 13.5, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}

class SdPill extends StatelessWidget {
  const SdPill(this.text, {super.key, this.color = kSdMuted, this.bg = kSdSoft});
  final String text;
  final Color color;
  final Color bg;

  factory SdPill.status(String status) {
    final s = status.toLowerCase();
    if (s == 'approved' || s == 'paid' || s == 'active' || s == 'present') {
      return SdPill(status, color: AppColors.success, bg: AppColors.successBg);
    }
    if (s == 'rejected' || s == 'absent' || s == 'cancelled') {
      return SdPill(status, color: AppColors.error, bg: AppColors.errorBg);
    }
    if (s == 'pending' || s == 'half day') {
      return SdPill(status, color: AppColors.warning, bg: AppColors.warningBg);
    }
    return SdPill(status);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
    );
  }
}

/// Decoration for text fields / dropdowns in the detail forms.
InputDecoration sdInput(String label, {String? hint}) {
  return InputDecoration(
    labelText: label,
    hintText: hint,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
  );
}

ButtonStyle sdPrimaryButton() => ElevatedButton.styleFrom(
      backgroundColor: AppColors.primary,
      foregroundColor: AppColors.onPrimary,
      elevation: 0,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );

/// Month navigator used by attendance, shifts and salary tabs.
class SdMonthBar extends StatelessWidget {
  const SdMonthBar({super.key, required this.month, required this.onChanged, this.canGoNext = true});
  final DateTime month;
  final ValueChanged<DateTime> onChanged;
  final bool canGoNext;

  @override
  Widget build(BuildContext context) {
    return SdCard(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Previous month',
            icon: const Icon(Icons.chevron_left_rounded, color: kSdInk),
            onPressed: () => onChanged(DateTime(month.year, month.month - 1)),
          ),
          Expanded(
            child: Text(DateFormat('MMMM yyyy').format(month),
                textAlign: TextAlign.center,
                style: AppTextStyles.headingSmall.copyWith(fontSize: 15)),
          ),
          IconButton(
            tooltip: 'Next month',
            icon: Icon(Icons.chevron_right_rounded, color: canGoNext ? kSdInk : AppColors.textHint),
            onPressed: canGoNext ? () => onChanged(DateTime(month.year, month.month + 1)) : null,
          ),
        ],
      ),
    );
  }
}

/// Asks for a free-text reason; returns null when cancelled.
Future<String?> sdAskText(
  BuildContext context, {
  required String title,
  required String label,
  String initial = '',
  bool required = true,
  String confirmText = 'Submit',
  int maxLines = 3,
}) async {
  final ctrl = TextEditingController(text: initial);
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) {
      String? error;
      return StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(title, style: AppTextStyles.headingMedium),
          content: TextField(
            controller: ctrl,
            maxLines: maxLines,
            decoration: sdInput(label).copyWith(errorText: error),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              style: sdPrimaryButton(),
              onPressed: () {
                final v = ctrl.text.trim();
                if (required && v.isEmpty) {
                  setD(() => error = '$label is required');
                  return;
                }
                Navigator.pop(ctx, v);
              },
              child: Text(confirmText),
            ),
          ],
        ),
      );
    },
  );
  ctrl.dispose();
  return result;
}

Future<bool> sdConfirm(BuildContext context,
    {required String title, required String message, String confirmText = 'Confirm', bool danger = false}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title, style: AppTextStyles.headingMedium),
      content: Text(message, style: AppTextStyles.bodyMedium.copyWith(color: kSdMuted)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        ElevatedButton(
          style: danger
              ? ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)))
              : sdPrimaryButton(),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmText),
        ),
      ],
    ),
  );
  return ok == true;
}

/// "hh:mm AM" — the time format the attendance endpoints parse.
String sdTimeOfDay(TimeOfDay t) {
  final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
  final p = t.period == DayPeriod.am ? 'AM' : 'PM';
  return '${h.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')} $p';
}
