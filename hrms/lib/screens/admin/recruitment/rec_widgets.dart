// lib/screens/admin/recruitment/rec_widgets.dart
// Shared building blocks for the admin Recruitment screens: app bar, async states,
// badges, search, chips, cards, dialogs and form fields.

import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../config/app_colors.dart';
import '../../../config/app_text_styles.dart';
import '../../../utils/snackbar_utils.dart';
import '../../../widgets/app_card.dart';
import '../../../widgets/app_tab_loader.dart';

const Color kRecInk = AppColors.textPrimary;
const Color kRecMuted = AppColors.textSecondary;
const Color kRecHint = AppColors.textCaption;
const Color kRecBorder = Color(0xFFE2E5EA);
const Color kRecSoftBorder = Color(0xFFECEEF1);
const Color kRecBg = AppColors.background;

// ───────────────────────── Messages ─────────────────────────

void recShowError(BuildContext context, Object error) {
  if (!context.mounted) return;
  SnackBarUtils.showSnackBar(context, error.toString(), isError: true);
}

void recShowSuccess(BuildContext context, String message) {
  if (!context.mounted) return;
  SnackBarUtils.showSnackBar(context, message, backgroundColor: AppColors.success);
}

Future<void> recOpenUrl(BuildContext context, String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null || url.isEmpty) {
    recShowError(context, 'No link available');
    return;
  }
  final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) recShowError(context, 'Could not open the link');
}

/// A file chosen by the user, read into memory.
class RecPickedFile {
  final String name;
  final Uint8List bytes;
  final String mimeType;
  RecPickedFile(this.name, this.bytes, this.mimeType);
}

String recMimeFor(String fileName) {
  final ext = fileName.split('.').last.toLowerCase();
  switch (ext) {
    case 'pdf':
      return 'application/pdf';
    case 'doc':
      return 'application/msword';
    case 'docx':
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    case 'png':
      return 'image/png';
    case 'jpg':
    case 'jpeg':
      return 'image/jpeg';
    default:
      return 'application/octet-stream';
  }
}

/// Picks one file with the given extensions. Returns null when cancelled; shows an error
/// when the file cannot be read or is larger than [maxMb].
Future<RecPickedFile?> recPickFile(BuildContext context, List<String> extensions, {int maxMb = 10}) async {
  try {
    final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: extensions, withData: true);
    if (r == null || r.files.isEmpty) return null;
    final f = r.files.first;
    final bytes = f.bytes;
    if (bytes == null) {
      if (context.mounted) recShowError(context, 'Could not read the selected file');
      return null;
    }
    if (bytes.length > maxMb * 1024 * 1024) {
      if (context.mounted) recShowError(context, 'The file is larger than $maxMb MB');
      return null;
    }
    return RecPickedFile(f.name, bytes, recMimeFor(f.name));
  } catch (e) {
    if (context.mounted) recShowError(context, 'Could not open the file picker');
    return null;
  }
}

Future<void> recOpenLocalFile(BuildContext context, String path) async {
  final result = await OpenFilex.open(path);
  if (result.type != ResultType.done && context.mounted) {
    recShowError(context, result.message.isEmpty ? 'No app found to open this file' : result.message);
  }
}

// ───────────────────────── Formatting ─────────────────────────

String recFormatDate(String? value) {
  if (value == null || value.isEmpty || value == '-') return '-';
  final d = DateTime.tryParse(value);
  if (d == null) return value;
  return DateFormat('dd MMM yyyy').format(d.toLocal());
}

String recFormatDateTime(String? value) {
  if (value == null || value.isEmpty) return '-';
  final d = DateTime.tryParse(value);
  if (d == null) return value;
  return DateFormat('dd MMM yyyy, hh:mm a').format(d.toLocal());
}

String recFormatTime(String hhmm) {
  final parts = hhmm.split(':');
  if (parts.length < 2) return hhmm;
  final h = int.tryParse(parts[0]) ?? 0;
  final m = int.tryParse(parts[1]) ?? 0;
  return DateFormat('hh:mm a').format(DateTime(2000, 1, 1, h, m));
}

String recDateKeyOf(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
String recTodayKey() => recDateKeyOf(DateTime.now());

String recMoney(num? v) {
  if (v == null) return '-';
  return NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0).format(v);
}

String recInitials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).take(2);
  final s = parts.map((p) => p[0]).join().toUpperCase();
  return s.isEmpty ? '?' : s;
}

// ───────────────────────── Status colours ─────────────────────────

({Color fg, Color bg}) recStatusColors(String status) {
  switch (status.toLowerCase()) {
    case 'active':
    case 'selected':
    case 'hired':
    case 'offer accepted':
    case 'accepted':
    case 'passed':
    case 'verified':
    case 'converted':
    case 'completed':
    case 'delivered':
    case 'joined':
    case 'sent':
      return (fg: AppColors.success, bg: AppColors.successBg);
    case 'rejected':
    case 'offer rejected':
    case 'closed':
    case 'canceled':
    case 'failed':
    case 'blacklisted':
    case 'revoked':
    case 'withdrawn':
    case 'expired':
      return (fg: AppColors.error, bg: AppColors.errorBg);
    case 'interviewing':
    case 'on hold':
    case 'offered':
    case 'pending review':
    case 'pending':
    case 'awaiting decision':
    case 'draft':
    case 'skipped':
    case 'reassigned':
      return (fg: AppColors.warning, bg: AppColors.warningBg);
    case 'scheduled':
    case 'shortlisted':
      return (fg: AppColors.info, bg: AppColors.infoBg);
    case 'inactive':
    case 'offer expired':
    case 'not submitted':
      return (fg: AppColors.textSecondary, bg: AppColors.inputFill);
    default:
      return (fg: AppColors.indigo, bg: AppColors.indigoBg);
  }
}

class RecBadge extends StatelessWidget {
  final String text;
  final String? colorKey;
  const RecBadge(this.text, {super.key, this.colorKey});

  @override
  Widget build(BuildContext context) {
    final c = recStatusColors(colorKey ?? text);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: c.bg, borderRadius: BorderRadius.circular(999)),
      child: Text(text, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: c.fg)),
    );
  }
}

// ───────────────────────── Scaffold pieces ─────────────────────────

PreferredSizeWidget recAppBar(
  BuildContext context,
  String title, {
  GlobalKey<ScaffoldState>? drawerKey,
  List<Widget>? actions,
  VoidCallback? onRefresh,
  PreferredSizeWidget? bottom,
}) {
  return AppBar(
    leading: drawerKey != null
        ? IconButton(
            icon: const Icon(Icons.menu_rounded),
            tooltip: 'Menu',
            onPressed: () => drawerKey.currentState?.openDrawer(),
          )
        : IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            tooltip: 'Back',
            onPressed: () => Navigator.of(context).maybePop(),
          ),
    title: Text(title),
    bottom: bottom,
    actions: [
      ...?actions,
      if (onRefresh != null)
        IconButton(
          icon: const Icon(Icons.refresh_rounded, size: 22),
          onPressed: onRefresh,
          tooltip: 'Refresh',
        ),
      const SizedBox(width: 4),
    ],
  );
}

/// Loading / error-with-retry / empty / content switch.
class RecAsyncBody extends StatelessWidget {
  final bool loading;
  final String? error;
  final bool isEmpty;
  final String emptyText;
  final IconData emptyIcon;
  final VoidCallback onRetry;
  final Widget Function() builder;

  const RecAsyncBody({
    super.key,
    required this.loading,
    required this.error,
    required this.isEmpty,
    required this.onRetry,
    required this.builder,
    this.emptyText = 'Nothing here yet',
    this.emptyIcon = Icons.inbox_outlined,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: AppTabLoader());
    if (error != null) return RecErrorState(message: error!, onRetry: onRetry);
    if (isEmpty) return RecEmptyState(text: emptyText, icon: emptyIcon, onRefresh: onRetry);
    return builder();
  }
}

class RecErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const RecErrorState({super.key, required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const RecStateIcon(Icons.error_outline_rounded, color: AppColors.error),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center, style: AppTextStyles.bodySmall),
            const SizedBox(height: 16),
            RecPrimaryButton(label: 'Retry', icon: Icons.refresh_rounded, onPressed: onRetry),
          ],
        ),
      ),
    );
  }
}

class RecEmptyState extends StatelessWidget {
  final String text;
  final IconData icon;
  final VoidCallback? onRefresh;
  const RecEmptyState({super.key, required this.text, this.icon = Icons.inbox_outlined, this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        RecStateIcon(icon),
        const SizedBox(height: 16),
        Text(text, textAlign: TextAlign.center, style: AppTextStyles.headingSmall.copyWith(fontSize: 15)),
      ],
    );
    if (onRefresh == null) return Center(child: Padding(padding: const EdgeInsets.all(32), child: content));
    return RefreshIndicator(
      onRefresh: () async => onRefresh!(),
      color: AppColors.primary,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(height: MediaQuery.of(context).size.height * 0.22),
          Padding(padding: const EdgeInsets.all(32), child: content),
        ],
      ),
    );
  }
}

/// 64px tinted circle with an icon, used by empty / error states.
class RecStateIcon extends StatelessWidget {
  final IconData icon;
  final Color color;
  const RecStateIcon(this.icon, {super.key, this.color = AppColors.brandDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
      child: Icon(icon, size: 28, color: color),
    );
  }
}

/// White bottom action bar with a hairline top border (for `bottomNavigationBar`).
class RecBottomBar extends StatelessWidget {
  final Widget child;
  const RecBottomBar({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: kRecSoftBorder)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: SizedBox(height: 52, child: child),
        ),
      ),
    );
  }
}

/// Tinted inline notice (info / warning / error) with a leading icon.
class RecNotice extends StatelessWidget {
  final String text;
  final Color color;
  final Color background;
  final IconData icon;
  final EdgeInsetsGeometry margin;
  const RecNotice(
    this.text, {
    super.key,
    this.color = AppColors.brandDark,
    this.background = AppColors.warningBg,
    this.icon = Icons.info_outline_rounded,
    this.margin = const EdgeInsets.only(bottom: 12),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(12)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(fontSize: 13, height: 1.4, fontWeight: FontWeight.w500, color: color))),
        ],
      ),
    );
  }
}

/// Square tinted icon tile (radius 12) for list rows and headers.
class RecIconTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  const RecIconTile(this.icon, {super.key, this.color = AppColors.brandDark, this.size = 40});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
      child: Icon(icon, size: 20, color: color),
    );
  }
}

class RecCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  const RecCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
    this.margin = const EdgeInsets.only(bottom: 12),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kRecSoftBorder),
        boxShadow: kSoftCardShadow,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

class RecSectionTitle extends StatelessWidget {
  final String title;
  final Widget? trailing;
  const RecSectionTitle(this.title, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: AppTextStyles.headingSmall.copyWith(fontSize: 15)),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class RecInfoRow extends StatelessWidget {
  final String label;
  final String value;
  const RecInfoRow(this.label, this.value, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: AppTextStyles.bodySmall.copyWith(fontSize: 12.5)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(value.isEmpty ? '-' : value,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: kRecInk)),
          ),
        ],
      ),
    );
  }
}

class RecSearchField extends StatelessWidget {
  final String hint;
  final ValueChanged<String> onChanged;
  final TextEditingController? controller;
  const RecSearchField({super.key, required this.hint, required this.onChanged, this.controller});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: const TextStyle(fontSize: 14, color: kRecInk),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(fontSize: 13.5, color: kRecHint),
          prefixIcon: const Icon(Icons.search_rounded, size: 20),
          filled: true,
          fillColor: AppColors.surface,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }
}

class RecFilterChips extends StatelessWidget {
  final List<String> options;
  final String selected;
  final ValueChanged<String> onSelected;
  final String Function(String)? labelOf;
  final Map<String, int>? counts;
  const RecFilterChips({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
    this.labelOf,
    this.counts,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: options.map((o) {
          final isSel = o == selected;
          final count = counts?[o];
          final label = (labelOf?.call(o) ?? o) + (count != null ? ' ($count)' : '');
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(label),
              selected: isSel,
              onSelected: (_) => onSelected(o),
              selectedColor: AppColors.primary,
              backgroundColor: AppColors.surface,
              labelStyle: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: isSel ? AppColors.onPrimary : kRecMuted,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
                side: BorderSide(color: isSel ? AppColors.primary : kRecBorder),
              ),
              showCheckmark: false,
            ),
          );
        }).toList(),
      ),
    );
  }
}

class RecStatTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color? color;
  final VoidCallback? onTap;
  const RecStatTile({super.key, required this.label, required this.value, required this.icon, this.color, this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.brandDark;
    return RecCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(12),
      onTap: onTap,
      child: Row(
        children: [
          RecIconTile(icon, color: c),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: kRecInk, height: 1.2)),
                const SizedBox(height: 2),
                Text(label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: kRecMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class RecAvatar extends StatelessWidget {
  final String name;
  final double size;
  const RecAvatar(this.name, {super.key, this.size = 40});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: AppColors.brandLight, borderRadius: BorderRadius.circular(size / 3)),
      child: Text(recInitials(name),
          style: TextStyle(fontSize: size * 0.34, fontWeight: FontWeight.w700, color: AppColors.brandDark)),
    );
  }
}

class RecPrimaryButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool busy;
  final bool destructive;
  final bool outlined;
  const RecPrimaryButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.busy = false,
    this.destructive = false,
    this.outlined = false,
  });

  @override
  Widget build(BuildContext context) {
    final bg = destructive ? AppColors.error : AppColors.primary;
    final fg = destructive ? Colors.white : AppColors.onPrimary;
    final child = busy
        ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: outlined ? bg : fg))
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[Icon(icon, size: 18), const SizedBox(width: 8)],
              Flexible(child: Text(label, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600))),
            ],
          );
    if (outlined) {
      return OutlinedButton(
        onPressed: busy ? null : onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: destructive ? AppColors.error : kRecInk,
          side: BorderSide(color: destructive ? AppColors.error : kRecBorder, width: 1.2),
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        ),
        child: child,
      );
    }
    return ElevatedButton(
      onPressed: busy ? null : onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: bg,
        foregroundColor: fg,
        disabledBackgroundColor: bg.withValues(alpha: 0.5),
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      ),
      child: child,
    );
  }
}

// ───────────────────────── Form fields ─────────────────────────

// Inherits the app-wide input theme (filled, radius 12, hairline border, gold focus).
InputDecoration recInputDecoration(String label, {String? hint, Widget? suffix}) {
  return InputDecoration(
    labelText: label,
    hintText: hint,
    suffixIcon: suffix,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
  );
}

class RecTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final int maxLines;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final bool obscure;
  final Widget? suffix;
  final bool readOnly;
  final VoidCallback? onTap;
  const RecTextField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.maxLines = 1,
    this.keyboardType,
    this.validator,
    this.obscure = false,
    this.suffix,
    this.readOnly = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        maxLines: obscure ? 1 : maxLines,
        minLines: 1,
        keyboardType: keyboardType,
        validator: validator,
        obscureText: obscure,
        readOnly: readOnly,
        onTap: onTap,
        style: const TextStyle(fontSize: 14, color: kRecInk),
        decoration: recInputDecoration(label, hint: hint, suffix: suffix),
      ),
    );
  }
}

class RecDropdown<T> extends StatelessWidget {
  final String label;
  final T? value;
  final List<T> items;
  final String Function(T) labelOf;
  final ValueChanged<T?>? onChanged;
  final String? Function(T?)? validator;
  const RecDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.labelOf,
    this.onChanged,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<T>(
        // Keyed by the value so a value changed from outside (prefill, reset) is shown
        key: ValueKey<Object?>('$label|$value|${items.length}'),
        initialValue: items.contains(value) ? value : null,
        isExpanded: true,
        validator: validator,
        decoration: recInputDecoration(label),
        style: const TextStyle(fontSize: 14, color: kRecInk),
        items: items
            .map((e) => DropdownMenuItem<T>(value: e, child: Text(labelOf(e), overflow: TextOverflow.ellipsis)))
            .toList(),
        onChanged: onChanged,
      ),
    );
  }
}

/// A tappable read-only field (dates, times, pickers).
class RecPickerField extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final VoidCallback? onTap;
  final VoidCallback? onClear;
  const RecPickerField({
    super.key,
    required this.label,
    required this.value,
    this.icon = Icons.event_outlined,
    this.onTap,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: InputDecorator(
          decoration: recInputDecoration(
            label,
            suffix: value.isNotEmpty && onClear != null
                ? IconButton(icon: const Icon(Icons.clear_rounded, size: 20), tooltip: 'Clear', onPressed: onClear)
                : Icon(icon, size: 20, color: kRecMuted),
          ),
          child: Text(value.isEmpty ? 'Select' : value,
              style: TextStyle(fontSize: 14, color: value.isEmpty ? kRecHint : kRecInk)),
        ),
      ),
    );
  }
}

String? recRequired(String? v) => (v == null || v.trim().isEmpty) ? 'Required' : null;

// ───────────────────────── Dialogs & sheets ─────────────────────────

Future<bool> recConfirm(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  bool destructive = false,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message, style: AppTextStyles.bodyMedium.copyWith(color: kRecMuted)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel,
              style: TextStyle(fontWeight: FontWeight.w600, color: destructive ? AppColors.error : AppColors.primaryText)),
        ),
      ],
    ),
  );
  return ok == true;
}

/// Asks for one line (or paragraph) of text. Returns null when cancelled.
Future<String?> recPromptText(
  BuildContext context, {
  required String title,
  required String label,
  String initial = '',
  bool required = true,
  int maxLines = 1,
  String confirmLabel = 'Save',
  String? message,
}) async {
  final ctrl = TextEditingController(text: initial);
  final formKey = GlobalKey<FormState>();
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Form(
        key: formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message != null) ...[
              Text(message, style: AppTextStyles.bodySmall),
              const SizedBox(height: 12),
            ],
            RecTextField(controller: ctrl, label: label, maxLines: maxLines, validator: required ? recRequired : null),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        TextButton(
          onPressed: () {
            if (formKey.currentState?.validate() ?? false) Navigator.pop(ctx, ctrl.text.trim());
          },
          child: Text(confirmLabel, style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.primaryText)),
        ),
      ],
    ),
  );
  return result;
}

Future<String?> recPickDate(BuildContext context, {String? initial, DateTime? firstDate, DateTime? lastDate}) async {
  final now = DateTime.now();
  final init = DateTime.tryParse(initial ?? '') ?? now;
  final first = firstDate ?? DateTime(now.year - 60);
  final last = lastDate ?? DateTime(now.year + 5);
  final picked = await showDatePicker(
    context: context,
    initialDate: init.isBefore(first) ? first : (init.isAfter(last) ? last : init),
    firstDate: first,
    lastDate: last,
  );
  return picked == null ? null : recDateKeyOf(picked);
}

Future<String?> recPickTime(BuildContext context, {String? initial}) async {
  final parts = (initial ?? '').split(':');
  final init = parts.length >= 2
      ? TimeOfDay(hour: int.tryParse(parts[0]) ?? 10, minute: int.tryParse(parts[1]) ?? 0)
      : const TimeOfDay(hour: 10, minute: 0);
  final picked = await showTimePicker(context: context, initialTime: init);
  if (picked == null) return null;
  return '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
}

/// A scrollable bottom sheet with a title; [builder] gets the sheet's context.
Future<T?> recShowSheet<T>(BuildContext context, {required String title, required Widget Function(BuildContext) builder}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.9),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: kRecBorder, borderRadius: BorderRadius.circular(2))),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(title, style: AppTextStyles.headingMedium),
                  ),
                  IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      tooltip: 'Close',
                      icon: const Icon(Icons.close_rounded, color: kRecMuted)),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                child: builder(ctx),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Action list bottom sheet. Returns the chosen value.
Future<String?> recShowActions(BuildContext context, {required String title, required List<RecAction> actions}) {
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(width: 40, height: 4, decoration: BoxDecoration(color: kRecBorder, borderRadius: BorderRadius.circular(2))),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(title, style: AppTextStyles.headingSmall),
            ),
          ),
          ...actions.map((a) => ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                leading: RecIconTile(a.icon, color: a.destructive ? AppColors.error : kRecInk, size: 36),
                title: Text(a.label,
                    style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600, color: a.destructive ? AppColors.error : kRecInk)),
                onTap: () => Navigator.pop(ctx, a.value),
              )),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

class RecAction {
  final String value;
  final String label;
  final IconData icon;
  final bool destructive;
  const RecAction(this.value, this.label, this.icon, {this.destructive = false});
}
