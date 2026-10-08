// Small shared pieces for the admin Salary and Exit Process screens: colours, money and month
// formatting, the loading / error / empty states, cards and pills. Styled like the other
// admin screens (GEO settings, Payroll).

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../config/app_colors.dart';
import '../../../widgets/app_tab_loader.dart';

/// Hairline used for card / field borders across the admin Salary and Exit screens.
const Color _hairline = Color(0xFFECEEF1);

class AdminUi {
  // Aliases of the EktaHR design tokens (AppColors) so every admin Salary / Exit screen
  // shares one palette with the rest of the app.
  static const accent = AppColors.brand;
  static const accentLight = AppColors.brandLight;
  static const ink = AppColors.textPrimary;
  static const muted = AppColors.textSecondary;
  static const faint = AppColors.textCaption;
  static const bg = AppColors.background;
  static const border = _hairline;
  static const green = AppColors.success;
  static const greenBg = AppColors.successBg;
  static const red = AppColors.error;
  static const redBg = AppColors.errorBg;
  static const blue = AppColors.info;
  static const blueBg = AppColors.infoBg;
  static const amber = AppColors.warning;
  static const amberBg = AppColors.warningBg;
  static const greyBg = AppColors.inputFill;

  static const months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  static final NumberFormat _inr = NumberFormat.decimalPattern('en_IN');

  /// "₹ 1,23,456" (rounded to rupees unless [decimals]).
  static String money(num? v, {bool decimals = false}) {
    if (v == null) return '—';
    if (decimals) return '₹ ${NumberFormat('#,##,##0.00', 'en_IN').format(v)}';
    return '₹ ${_inr.format(v.round())}';
  }

  static double toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0;
  }

  /// "August 2026" for a date.
  static String monthLabel(DateTime d) => '${months[d.month - 1]} ${d.year}';

  /// The 1st of the month a "Month YYYY" label names, or null.
  static DateTime? parseMonthLabel(String? label) {
    if (label == null) return null;
    final parts = label.trim().split(RegExp(r'\s+'));
    if (parts.length != 2) return null;
    final m = months.indexWhere((x) => x.toLowerCase() == parts[0].toLowerCase());
    final y = int.tryParse(parts[1]);
    if (m < 0 || y == null) return null;
    return DateTime(y, m + 1, 1);
  }

  /// "12 Aug 2026" from an ISO / "YYYY-MM-DD" string; "-" when empty.
  static String date(dynamic v) {
    final s = v?.toString() ?? '';
    if (s.isEmpty) return '-';
    final ymd = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(s);
    DateTime? d;
    if (ymd != null) {
      d = DateTime(int.parse(ymd.group(1)!), int.parse(ymd.group(2)!), int.parse(ymd.group(3)!));
    } else {
      d = DateTime.tryParse(s)?.toLocal();
    }
    return d == null ? '-' : DateFormat('dd MMM yyyy').format(d);
  }

  /// "YYYY-MM-DD" from local calendar parts (never via UTC).
  static String ymd(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static DateTime? parseYmd(String? s) {
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(s ?? '');
    if (m == null) return null;
    return DateTime(int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!));
  }

  /// App bar that inherits the global theme (white, hairline, centered Inter title).
  static PreferredSizeWidget appBar(String title, {List<Widget>? actions, PreferredSizeWidget? bottom}) => AppBar(
        scrolledUnderElevation: 0,
        title: Text(title),
        actions: actions,
        bottom: bottom,
      );

  static ({Color fg, Color bg}) statusColors(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
      case 'released':
      case 'completed':
      case 'returned':
        return (fg: green, bg: greenBg);
      case 'rejected':
      case 'on hold':
      case 'cancelled':
      case 'damaged':
      case 'lost':
        return (fg: red, bg: redBg);
      case 'pending':
        return (fg: amber, bg: amberBg);
      case 'in progress':
        return (fg: blue, bg: blueBg);
      case 'payroll processed':
        return (fg: Colors.white, bg: ink);
      default:
        return (fg: muted, bg: greyBg);
    }
  }

  /// Field decoration: fill, borders and focus colours come from the app-wide input theme.
  static InputDecoration input(String? label, {String? hint, String? prefix, String? helper}) => InputDecoration(
        labelText: label,
        hintText: hint,
        prefixText: prefix,
        helperText: helper,
        helperMaxLines: 3,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      );

  /// Primary action: the themed ElevatedButton (primary fill, onPrimary text, radius 12).
  static ButtonStyle primaryButton() => ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      );
}

class AdminLoading extends StatelessWidget {
  const AdminLoading({super.key});
  @override
  Widget build(BuildContext context) => const Center(child: AppTabLoader());
}

class AdminErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const AdminErrorView({super.key, required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(color: AdminUi.redBg, shape: BoxShape.circle),
              child: const Icon(Icons.error_outline_rounded, size: 30, color: AdminUi.red),
            ),
            const SizedBox(height: 16),
            Text(message,
                textAlign: TextAlign.center, style: const TextStyle(color: AdminUi.muted, fontSize: 14, height: 1.4)),
            const SizedBox(height: 16),
            OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh_rounded, size: 18), label: const Text('Retry')),
          ]),
        ),
      );
}

class AdminEmptyView extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  const AdminEmptyView({super.key, required this.icon, required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: Icon(icon, size: 30, color: AppColors.primaryText),
          ),
          const SizedBox(height: 16),
          Text(title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w600, color: AdminUi.ink, fontSize: 16)),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(subtitle!,
                textAlign: TextAlign.center, style: const TextStyle(color: AdminUi.muted, fontSize: 13, height: 1.45)),
          ],
        ]),
      );
}

class AdminCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  const AdminCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.onTap});

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 10, offset: Offset(0, 3))],
        ),
        child: Material(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: Container(
              padding: padding,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AdminUi.border),
              ),
              child: child,
            ),
          ),
        ),
      );
}

/// Section label above a group of cards ("EARNINGS", "DOCUMENTS"…): 11/w700 caps.
class AdminSectionLabel extends StatelessWidget {
  final String text;
  const AdminSectionLabel(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
        child: Text(text.toUpperCase(),
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1, color: AdminUi.muted)),
      );
}

/// 40×40 tinted icon tile (radius 12) used as a leading visual in rows and headers.
class AdminIconTile extends StatelessWidget {
  final IconData icon;
  final Color? color;
  final double size;
  const AdminIconTile(this.icon, {super.key, this.color, this.size = 40});
  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.primaryText;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: (color ?? AppColors.primary).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, size: size * 0.5, color: c),
    );
  }
}

class AdminPill extends StatelessWidget {
  final String label;
  final Color? fg;
  final Color? bg;
  const AdminPill(this.label, {super.key, this.fg, this.bg});

  @override
  Widget build(BuildContext context) {
    final c = AdminUi.statusColors(label);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg ?? c.bg, borderRadius: BorderRadius.circular(999)),
      child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg ?? c.fg, height: 1.2)),
    );
  }
}

class AdminStatTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  const AdminStatTile({super.key, required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AdminUi.border),
        ),
        child: Row(children: [
          AdminIconTile(icon),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(fontSize: 12, color: AdminUi.muted, fontWeight: FontWeight.w500)),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AdminUi.ink)),
              ),
            ]),
          ),
        ]),
      );
}

/// "‹ August 2026 ›" — steps a month at a time, tap the label to pick any month.
class AdminMonthSwitcher extends StatelessWidget {
  final DateTime month;
  final ValueChanged<DateTime> onChanged;
  final bool allowFuture;
  final Set<String> lockedMonths;
  const AdminMonthSwitcher({
    super.key,
    required this.month,
    required this.onChanged,
    this.allowFuture = false,
    this.lockedMonths = const {},
  });

  bool _canGoNext() {
    if (allowFuture) return true;
    final now = DateTime.now();
    return DateTime(month.year, month.month + 1, 1).isBefore(DateTime(now.year, now.month + 1, 1));
  }

  Future<void> _pick(BuildContext context) async {
    int year = month.year;
    final now = DateTime.now();
    final picked = await showDialog<DateTime>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Row(children: [
            IconButton(
                tooltip: 'Previous year',
                onPressed: () => setD(() => year--),
                icon: const Icon(Icons.chevron_left_rounded)),
            Expanded(
                child: Text('$year',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 18, color: AdminUi.ink))),
            IconButton(
              tooltip: 'Next year',
              onPressed: allowFuture || year < now.year ? () => setD(() => year++) : null,
              icon: const Icon(Icons.chevron_right_rounded),
            ),
          ]),
          content: SizedBox(
            width: 300,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List.generate(12, (i) {
                final d = DateTime(year, i + 1, 1);
                final disabled = !allowFuture && d.isAfter(DateTime(now.year, now.month, 1));
                final selected = d.year == month.year && d.month == month.month;
                final locked = lockedMonths.contains(AdminUi.monthLabel(d));
                return SizedBox(
                  width: 88,
                  child: ChoiceChip(
                    selected: selected,
                    showCheckmark: false,
                    selectedColor: AppColors.primary,
                    backgroundColor: AdminUi.greyBg,
                    side: BorderSide.none,
                    onSelected: disabled ? null : (_) => Navigator.pop(ctx, d),
                    label: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(AdminUi.months[i].substring(0, 3),
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: disabled
                                  ? AdminUi.faint
                                  : (selected ? AppColors.onPrimary : AdminUi.ink),
                              fontSize: 13)),
                      if (locked) ...[
                        const SizedBox(width: 3),
                        const Icon(Icons.lock_rounded, size: 11, color: AdminUi.muted),
                      ],
                    ]),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final locked = lockedMonths.contains(AdminUi.monthLabel(month));
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E5EA)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
          tooltip: 'Previous month',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.chevron_left_rounded, size: 20),
          onPressed: () => onChanged(DateTime(month.year, month.month - 1, 1)),
        ),
        InkWell(
          onTap: () => _pick(context),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.calendar_month_outlined, size: 16, color: AppColors.primaryText),
              const SizedBox(width: 6),
              Text(AdminUi.monthLabel(month),
                  style: const TextStyle(fontWeight: FontWeight.w600, color: AdminUi.ink, fontSize: 13.5)),
              if (locked) ...[
                const SizedBox(width: 4),
                const Icon(Icons.lock_rounded, size: 13, color: AdminUi.muted),
              ],
            ]),
          ),
        ),
        IconButton(
          tooltip: 'Next month',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.chevron_right_rounded, size: 20),
          onPressed: _canGoNext() ? () => onChanged(DateTime(month.year, month.month + 1, 1)) : null,
        ),
      ]),
    );
  }
}

class AdminSearchField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  const AdminSearchField({super.key, required this.controller, required this.hint, required this.onChanged});

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 44,
        child: TextField(
          controller: controller,
          onChanged: onChanged,
          style: const TextStyle(fontSize: 14, color: AdminUi.ink),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(fontSize: 13.5, color: AdminUi.faint),
            prefixIcon: const Icon(Icons.search_rounded, size: 20),
            suffixIcon: controller.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear',
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: () {
                      controller.clear();
                      onChanged('');
                    },
                  ),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      );
}

/// A yes/no confirmation; resolves true when confirmed.
Future<bool> adminConfirm(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  bool destructive = false,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 18, color: AdminUi.ink)),
      content: Text(message, style: const TextStyle(color: AdminUi.muted, fontSize: 14, height: 1.45)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: destructive
              ? ElevatedButton.styleFrom(backgroundColor: AdminUi.red, foregroundColor: Colors.white)
              : AdminUi.primaryButton(),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return ok == true;
}

String initialsOf(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts[0][0].toUpperCase();
  return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
}

class AdminAvatar extends StatelessWidget {
  final String name;
  final double size;
  const AdminAvatar(this.name, {super.key, this.size = 38});
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.14), shape: BoxShape.circle),
        child: Text(initialsOf(name),
            style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.primaryText, fontSize: size * 0.36)),
      );
}
