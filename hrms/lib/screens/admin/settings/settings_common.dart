// Shared widgets/helpers for the admin Staff > Settings screens.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../config/app_colors.dart';
import '../../../config/app_text_styles.dart';
import '../../../services/admin_settings_service.dart';
import '../../../utils/snackbar_utils.dart';
import '../../../widgets/app_card.dart';
import '../../../widgets/app_tab_loader.dart';

PreferredSizeWidget settingsAppBar(String title, {List<Widget>? actions, PreferredSizeWidget? bottom}) => AppBar(
      title: Text(title),
      actions: actions,
      bottom: bottom,
    );

TabBar settingsTabBar(List<String> tabs, {bool scrollable = false}) => TabBar(
      isScrollable: scrollable,
      tabAlignment: scrollable ? TabAlignment.start : null,
      tabs: [for (final t in tabs) Tab(text: t)],
    );

void showSettingsError(BuildContext context, Object e) {
  SnackBarUtils.showSnackBar(context, settingsErrorText(e), isError: true);
}

void showSettingsSuccess(BuildContext context, String message) {
  SnackBarUtils.showSnackBar(context, message);
}

class SettingsLoading extends StatelessWidget {
  const SettingsLoading({super.key});
  @override
  Widget build(BuildContext context) => const Center(child: AppTabLoader());
}

class SettingsErrorView extends StatelessWidget {
  const SettingsErrorView({super.key, required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(32),
        children: [
          const SizedBox(height: 56),
          Center(child: _settingsStateIcon(Icons.error_outline_rounded, AppColors.error)),
          const SizedBox(height: 16),
          Text(message, textAlign: TextAlign.center, style: AppTextStyles.bodySmall),
          const SizedBox(height: 16),
          Center(child: OutlinedButton(onPressed: onRetry, child: const Text('Retry'))),
        ],
      );
}

class SettingsEmptyView extends StatelessWidget {
  const SettingsEmptyView({super.key, required this.message, this.icon = Icons.inbox_outlined});
  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(32),
        children: [
          const SizedBox(height: 56),
          Center(child: _settingsStateIcon(icon, AppColors.brandDark)),
          const SizedBox(height: 16),
          Text(message, textAlign: TextAlign.center, style: AppTextStyles.headingSmall.copyWith(fontSize: 15)),
        ],
      );
}

/// White form-section card (16 radius, hairline) that groups related fields.
class SettingsFormCard extends StatelessWidget {
  const SettingsFormCard({super.key, required this.children, this.padding = const EdgeInsets.fromLTRB(16, 16, 16, 4)});
  final List<Widget> children;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => AppCard(
        padding: padding,
        border: Border.all(color: const Color(0xFFECEEF1)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      );
}

/// Square tinted icon tile (radius 12) for list rows and headers.
Widget settingsIconTile(IconData icon, {Color color = AppColors.brandDark, double size = 44}) => Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
      child: Icon(icon, size: 22, color: color),
    );

/// 64px tinted circle used by the empty / error states.
Widget _settingsStateIcon(IconData icon, Color color) => Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
      child: Icon(icon, size: 28, color: color),
    );

/// Loading / error / empty / content switch for a list loaded asynchronously.
Widget settingsAsyncBody<T>({
  required List<T>? items,
  required String? error,
  required Future<void> Function() onRefresh,
  required String emptyText,
  required Widget Function(List<T> items) builder,
}) {
  if (error != null && items == null) return SettingsErrorView(message: error, onRetry: onRefresh);
  if (items == null) return const SettingsLoading();
  return RefreshIndicator(
    color: AppColors.primary,
    onRefresh: onRefresh,
    child: items.isEmpty ? SettingsEmptyView(message: emptyText) : builder(items),
  );
}

Future<bool> confirmSettingsAction(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Delete',
  bool destructive = true,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel, style: TextStyle(color: destructive ? AppColors.error : AppColors.primaryText)),
        ),
      ],
    ),
  );
  return ok == true;
}

InputDecoration settingsInput(String label, {String? hint, String? suffix, Widget? suffixIcon}) => InputDecoration(
      labelText: label,
      hintText: hint,
      suffixText: suffix,
      suffixIcon: suffixIcon,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );

class SettingsSectionTitle extends StatelessWidget {
  const SettingsSectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(text.toUpperCase(),
                  style: AppTextStyles.sectionLabel.copyWith(color: AppColors.textSecondary)),
            ),
            ?trailing,
          ],
        ),
      );
}

class SettingsSwitchTile extends StatelessWidget {
  const SettingsSwitchTile({super.key, required this.title, this.subtitle, required this.value, required this.onChanged});
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        activeTrackColor: AppColors.primary,
        title: Text(title, style: AppTextStyles.label.copyWith(color: AppColors.textPrimary)),
        subtitle: subtitle == null
            ? null
            : Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(subtitle!, style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary)),
              ),
        value: value,
        onChanged: onChanged,
      );
}

class SettingsChip extends StatelessWidget {
  const SettingsChip(this.label, {super.key, this.color = AppColors.textSecondary, this.background = AppColors.inputFill});
  final String label;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(999)),
        child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
      );
}

SettingsChip activeChip(bool active) => active
    ? const SettingsChip('Active', color: AppColors.success, background: AppColors.successBg)
    : const SettingsChip('Inactive', color: AppColors.error, background: AppColors.errorBg);

/// Bottom "Save" bar used by every form.
class SettingsSaveBar extends StatelessWidget {
  const SettingsSaveBar({super.key, required this.saving, required this.onSave, this.label = 'Save'});
  final bool saving;
  final VoidCallback onSave;
  final String label;

  @override
  Widget build(BuildContext context) => SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(top: BorderSide(color: Color(0xFFECEEF1))),
          ),
          child: SizedBox(
            height: 52,
            child: FilledButton(
              onPressed: saving ? null : onSave,
              child: saving
                  ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onPrimary))
                  : Text(label),
            ),
          ),
        ),
      );
}

/// A tappable list card with title / subtitle / trailing.
class SettingsListCard extends StatelessWidget {
  const SettingsListCard({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.footer,
  });
  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Widget? footer;

  @override
  Widget build(BuildContext context) => AppCard(
        onTap: onTap,
        padding: const EdgeInsets.all(16),
        border: Border.all(color: const Color(0xFFECEEF1)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (leading != null) ...[leading!, const SizedBox(width: 12)],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: AppTextStyles.headingSmall.copyWith(fontSize: 15)),
                      if (subtitle != null && subtitle!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(subtitle!, style: AppTextStyles.bodySmall),
                      ],
                    ],
                  ),
                ),
                ?trailing,
              ],
            ),
            if (footer != null) ...[const SizedBox(height: 12), footer!],
          ],
        ),
      );
}

String fmtYmd(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
String fmtDisplayDate(dynamic v) {
  final d = v is DateTime ? v : DateTime.tryParse(v?.toString() ?? '');
  if (d == null) return '-';
  return DateFormat('dd MMM yyyy').format(d.toLocal());
}

Future<DateTime?> pickSettingsDate(BuildContext context, {DateTime? initial, DateTime? first, DateTime? last}) {
  final now = DateTime.now();
  return showDatePicker(
    context: context,
    initialDate: initial ?? now,
    firstDate: first ?? DateTime(now.year - 5),
    lastDate: last ?? DateTime(now.year + 5),
  );
}

/// "hh:mm AM" string from a TimeOfDay - the format the web shift form stores.
String fmtAmPm(TimeOfDay t) {
  final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
  final p = t.period == DayPeriod.am ? 'AM' : 'PM';
  return '${h.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')} $p';
}

/// Parses "hh:mm AM" or "HH:mm".
TimeOfDay? parseAmPm(String? s) {
  if (s == null) return null;
  final m = RegExp(r'^(\d{1,2}):(\d{2})\s*(AM|PM)?$', caseSensitive: false).firstMatch(s.trim());
  if (m == null) return null;
  var h = int.parse(m.group(1)!);
  final min = int.parse(m.group(2)!);
  final p = m.group(3)?.toUpperCase();
  if (p == 'PM' && h < 12) h += 12;
  if (p == 'AM' && h == 12) h = 0;
  if (h > 23 || min > 59) return null;
  return TimeOfDay(hour: h, minute: min);
}

/// Dropdown field with consistent styling.
class SettingsDropdown<T> extends StatelessWidget {
  const SettingsDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });
  final String label;
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;

  @override
  Widget build(BuildContext context) {
    final hasValue = value != null && items.any((i) => i.value == value);
    return DropdownButtonFormField<T>(
      key: ValueKey('$label-$value-${items.length}'),
      initialValue: hasValue ? value : null,
      isExpanded: true,
      decoration: settingsInput(label),
      items: items,
      onChanged: onChanged,
    );
  }
}

/// Simple int parsing helper for form values.
int? toInt(dynamic v) => v is num ? v.toInt() : int.tryParse(v?.toString() ?? '');
num? toNum(dynamic v) => v is num ? v : num.tryParse(v?.toString() ?? '');
