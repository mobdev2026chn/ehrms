// Shared look and small helpers for the admin HRMS GEO screens (same palette as the other
// admin GEO screens: amber accent, slate ink, light slate background).

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../config/app_colors.dart';
import '../../../config/app_text_styles.dart';
import '../../../utils/snackbar_utils.dart';
import '../../../widgets/app_card.dart';

class GeoUi {
  GeoUi._();

  static const accent = AppColors.brand;
  static const ink = AppColors.textPrimary;
  static const muted = AppColors.textSecondary;
  static const bg = AppColors.background;
  static const line = Color(0xFFECEEF1);
  static const border = Color(0xFFE2E5EA);

  static num n(dynamic v) => v is num ? v : num.tryParse('${v ?? ''}') ?? 0;
  static String s(dynamic v, [String fallback = '']) {
    final t = v?.toString() ?? '';
    return t.isEmpty || t == 'null' ? fallback : t;
  }

  static String money(dynamic v) => '₹${n(v).toDouble().toStringAsFixed(2)}';

  /// "12 Oct 2026" from yyyy-MM-dd or ISO; the raw text when it does not parse.
  static String date(dynamic v) {
    final t = s(v);
    final d = DateTime.tryParse(t);
    if (d == null) return t;
    return DateFormat('d MMM yyyy').format(t.length > 10 ? d.toLocal() : d);
  }

  static String time(dynamic v) {
    final d = DateTime.tryParse(s(v));
    return d == null ? s(v) : DateFormat('h:mm a').format(d.toLocal());
  }

  static String dateTime(dynamic v) {
    final d = DateTime.tryParse(s(v));
    return d == null ? s(v) : DateFormat('d MMM, h:mm a').format(d.toLocal());
  }

  // Inherits the app-wide AppBar theme (white, hairline border, centred Inter 18/w600 title).
  static PreferredSizeWidget appBar(String title, {List<Widget>? actions, PreferredSizeWidget? bottom}) => AppBar(
        title: Text(title),
        actions: actions,
        bottom: bottom,
      );

  static Widget card({required Widget child, EdgeInsets padding = const EdgeInsets.all(16), EdgeInsets? margin, VoidCallback? onTap}) =>
      AppCard(
        margin: margin ?? const EdgeInsets.only(bottom: 12),
        padding: padding,
        border: Border.all(color: line),
        onTap: onTap,
        child: child,
      );

  static Widget sectionTitle(String t, {Widget? trailing}) => Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 8),
        child: Row(children: [
          Expanded(child: Text(t, style: AppTextStyles.headingSmall.copyWith(fontSize: 15, color: ink))),
          ?trailing,
        ]),
      );

  static Widget pill(String text, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
        child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.3, color: fg)),
      );

  /// Icon "tile": square, radius 12, tinted background + coloured icon.
  static Widget iconTile(IconData icon, {Color color = AppColors.brandDark, double size = 44}) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
        child: Icon(icon, size: 22, color: color),
      );

  /// Colours for task / claim / customer statuses.
  static (Color, Color) statusColors(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
      case 'approved':
      case 'revised-approved':
        return (AppColors.successBg, AppColors.success);
      case 'rejected':
      case 'exited':
        return (AppColors.errorBg, AppColors.error);
      case 'started':
      case 'in progress':
      case 'in_progress':
      case 'arrived':
        return (AppColors.infoBg, AppColors.info);
      case 'requested':
        return (AppColors.indigoBg, AppColors.indigo);
      case 'expired':
      case 'hold':
        return (AppColors.inputFill, AppColors.textSecondary);
      case 'assigned':
        return (const Color(0xFFE0F2FE), const Color(0xFF0369A1));
      default:
        return (AppColors.warningBg, AppColors.warning);
    }
  }

  static Widget statusPill(String status) {
    final (bg, fg) = statusColors(status);
    return pill(status.toUpperCase(), bg, fg);
  }

  /// Centered message (scrollable so pull-to-refresh still works), with an optional retry.
  static Widget message(IconData icon, String title, String msg, {VoidCallback? onRetry}) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 32),
        children: [
          const SizedBox(height: 96),
          Center(
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(color: AppColors.brand.withValues(alpha: 0.12), shape: BoxShape.circle),
              child: Icon(icon, size: 28, color: AppColors.brandDark),
            ),
          ),
          const SizedBox(height: 16),
          Text(title, textAlign: TextAlign.center, style: AppTextStyles.headingSmall.copyWith(color: ink)),
          const SizedBox(height: 4),
          Text(msg, textAlign: TextAlign.center, style: AppTextStyles.bodySmall),
          if (onRetry != null) ...[
            const SizedBox(height: 16),
            Center(child: OutlinedButton(onPressed: onRetry, child: const Text('Retry'))),
          ],
        ],
      );

  static Widget error(String msg, VoidCallback onRetry) =>
      message(Icons.wifi_off_rounded, 'Could not load', msg, onRetry: onRetry);

  static const Widget loading = Center(child: CircularProgressIndicator(strokeWidth: 2.5));

  static void ok(BuildContext context, String msg) => SnackBarUtils.showSnackBar(context, msg);
  static void fail(BuildContext context, Object e) =>
      SnackBarUtils.showSnackBar(context, e.toString(), isError: true);

  static Future<bool> confirm(BuildContext context, String title, String body,
      {String action = 'Confirm', bool destructive = false}) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: destructive
                ? ElevatedButton.styleFrom(backgroundColor: AppColors.error, foregroundColor: Colors.white)
                : null,
            child: Text(action),
          ),
        ],
      ),
    );
    return r == true;
  }

  // Inherits the app-wide input theme (filled, radius 12, hairline border, gold focus).
  static InputDecoration input(String label, {String? hint, Widget? suffix}) => InputDecoration(
        labelText: label,
        hintText: hint,
        suffixIcon: suffix,
        isDense: true,
      );

  static Widget primaryButton(String label, VoidCallback? onPressed, {bool busy = false, IconData? icon}) => SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton.icon(
          onPressed: busy ? null : onPressed,
          icon: busy
              ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onPrimary))
              : Icon(icon ?? Icons.check_rounded, size: 20),
          label: Text(label),
        ),
      );

  static Widget kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 120, child: Text(k, style: AppTextStyles.bodySmall)),
          const SizedBox(width: 8),
          Expanded(
              child: Text(v.isEmpty ? '—' : v,
                  style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w500, color: ink))),
        ]),
      );

  static Widget choiceChips<T>({
    required List<T> values,
    required T selected,
    required String Function(T) label,
    required ValueChanged<T> onSelected,
  }) =>
      SizedBox(
        height: 36,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: values.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (_, i) {
            final v = values[i];
            final sel = v == selected;
            return ChoiceChip(
              selected: sel,
              onSelected: (_) => onSelected(v),
              showCheckmark: false,
              selectedColor: AppColors.primary,
              backgroundColor: Colors.white,
              side: BorderSide(color: sel ? Colors.transparent : border),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
              label: Text(label(v),
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: sel ? AppColors.onPrimary : ink)),
            );
          },
        ),
      );
}

/// Admin custom-field inputs (HRMS GEO → Settings → Custom Fields), built from the definitions
/// returned by GET /admin/hrms-geo/settings/custom-fields for one category. Read with
/// [GeoCustomFieldsFormState.values] and check with [GeoCustomFieldsFormState.validate].
class GeoCustomFieldsForm extends StatefulWidget {
  const GeoCustomFieldsForm({super.key, required this.defs, this.initial = const {}});

  /// Field definitions: {_id, label, type: text|number|date|dropdown, required, options}.
  final List<Map<String, dynamic>> defs;

  /// Existing values by field id.
  final Map<String, String> initial;

  @override
  State<GeoCustomFieldsForm> createState() => GeoCustomFieldsFormState();
}

class GeoCustomFieldsFormState extends State<GeoCustomFieldsForm> {
  final Map<String, TextEditingController> _ctrls = {};

  String _id(Map<String, dynamic> d) => GeoUi.s(d['_id'] ?? d['id']);

  @override
  void initState() {
    super.initState();
    for (final d in widget.defs) {
      _ctrls[_id(d)] = TextEditingController(text: widget.initial[_id(d)] ?? '');
    }
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// `{ fieldId: value }` for every field (empty ones included, the backend skips them).
  Map<String, String> get values => {for (final e in _ctrls.entries) e.key: e.value.text.trim()};

  String? validate() {
    for (final d in widget.defs) {
      final v = _ctrls[_id(d)]?.text.trim() ?? '';
      final label = GeoUi.s(d['label'], 'Field');
      if (v.isEmpty) {
        if (d['required'] == true) return '$label is required.';
        continue;
      }
      if (d['type'] == 'number' && double.tryParse(v) == null) return '$label must be a number.';
    }
    return null;
  }

  Future<void> _pickDate(TextEditingController c) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(c.text) ?? now,
      firstDate: DateTime(now.year - 50),
      lastDate: DateTime(now.year + 10),
    );
    if (picked != null) setState(() => c.text = DateFormat('yyyy-MM-dd').format(picked));
  }

  @override
  Widget build(BuildContext context) {
    if (widget.defs.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 4, bottom: 10),
          child: Text('Additional details', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: GeoUi.ink)),
        ),
        for (final d in widget.defs) _field(d),
      ],
    );
  }

  Widget _field(Map<String, dynamic> d) {
    final c = _ctrls[_id(d)]!;
    final type = GeoUi.s(d['type'], 'text');
    final label = d['required'] == true ? '${GeoUi.s(d['label'])} *' : GeoUi.s(d['label']);
    final options = d['options'] is List ? [for (final o in d['options'] as List) o.toString()] : <String>[];
    Widget child;
    if (type == 'dropdown' && options.isNotEmpty) {
      child = DropdownButtonFormField<String>(
        initialValue: options.contains(c.text) ? c.text : null,
        isExpanded: true,
        decoration: GeoUi.input(label),
        items: [for (final o in options) DropdownMenuItem(value: o, child: Text(o))],
        onChanged: (v) => setState(() => c.text = v ?? ''),
      );
    } else {
      child = TextField(
        controller: c,
        readOnly: type == 'date',
        onTap: type == 'date' ? () => _pickDate(c) : null,
        keyboardType: type == 'number' ? const TextInputType.numberWithOptions(decimal: true, signed: true) : TextInputType.text,
        decoration: GeoUi.input(label,
            suffix: type == 'date' ? const Icon(Icons.calendar_today_rounded, size: 18) : null),
      );
    }
    return Padding(padding: const EdgeInsets.only(bottom: 12), child: child);
  }
}
