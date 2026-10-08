// Shared pieces for the admin Celebration screens: template variables (mirrors the web's
// templateVariables.ts), the cross-tab data store, and small widgets.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../config/app_colors.dart';
import '../../../services/admin_celebration_service.dart';
import '../../../utils/error_message_utils.dart';

class TemplateVariable {
  const TemplateVariable(this.token, this.label, this.hint, this.sample, {this.kinds});
  final String token;
  final String label;
  final String hint;
  final String sample;

  /// Null means every kind.
  final List<String>? kinds;
}

const List<TemplateVariable> kTemplateVariables = [
  TemplateVariable('{{staff_name}}', 'Staff Name', "The employee's full name", 'Ananya Krishnan'),
  TemplateVariable('{{date}}', 'Date', 'The date of the occasion', '12 March 2026'),
  TemplateVariable('{{years_of_service}}', 'Years of Service', 'Completed years - anniversaries only', '5',
      kinds: ['anniversary']),
  TemplateVariable('{{company_name}}', 'Company Name', "Your organisation's name", 'Ekta Software'),
  TemplateVariable('{{department}}', 'Department', "The employee's department", 'Engineering'),
];

List<TemplateVariable> variablesFor(String kind) =>
    kTemplateVariables.where((v) => v.kinds == null || v.kinds!.contains(kind)).toList();

/// Substitutes sample values - editor preview only.
String renderWithSamples(String text, String kind) {
  final allowed = variablesFor(kind);
  var out = text;
  for (final v in kTemplateVariables) {
    out = out.split(v.token).join(allowed.contains(v) ? v.sample : '');
  }
  return out;
}

/// "12 March 2026", read in UTC like the server renders it.
String formatOccasionDate(DateTime? d) => d == null ? '' : DateFormat('d MMMM yyyy').format(d.toUtc());

/// Substitutes a real staff record - send preview.
String renderForEntry(String text, CelebrationEntry e, String companyName) {
  final values = <String, String>{
    '{{staff_name}}': e.staffName,
    '{{date}}': formatOccasionDate(e.date),
    '{{years_of_service}}': e.yearsOfService != null && e.yearsOfService! > 0 ? '${e.yearsOfService}' : '',
    '{{company_name}}': companyName,
    '{{department}}': e.department,
  };
  var out = text;
  values.forEach((k, v) => out = out.split(k).join(v));
  return out;
}

String kindLabel(String kind) => kind == 'anniversary' ? 'Work Anniversary' : 'Birthday';

/// Data shared by every tab: summary tiles, templates and automation settings. Any tab that
/// changes one of them refreshes it here so the others stay in step (like the web's tags).
class CelebrationStore extends ChangeNotifier {
  final AdminCelebrationService api = AdminCelebrationService();

  CelebrationSummary? summary;
  String? summaryError;

  List<CelebrationTemplate>? templates;
  String? templatesError;

  CelebrationSettings? settings;
  String? settingsError;

  bool _disposed = false;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> loadSummary() async {
    try {
      summary = await api.summary();
      summaryError = null;
    } catch (e) {
      summaryError = ErrorMessageUtils.toUserFriendlyMessage(e);
    }
    _notify();
  }

  Future<void> loadTemplates() async {
    try {
      templates = await api.templates();
      templatesError = null;
    } catch (e) {
      templatesError = ErrorMessageUtils.toUserFriendlyMessage(e);
    }
    _notify();
  }

  Future<void> loadSettings() async {
    try {
      settings = await api.settings();
      settingsError = null;
    } catch (e) {
      settingsError = ErrorMessageUtils.toUserFriendlyMessage(e);
    }
    _notify();
  }

  void setSettings(CelebrationSettings s) {
    settings = s;
    _notify();
  }

  Future<void> loadAll() => Future.wait([loadSummary(), loadTemplates(), loadSettings()]);

  List<CelebrationTemplate> templatesOf(String kind) =>
      (templates ?? const <CelebrationTemplate>[]).where((t) => t.kind == kind).toList();

  CelebrationTemplate? defaultOf(String kind) {
    for (final t in templatesOf(kind)) {
      if (t.isDefault) return t;
    }
    return null;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

void showCelebrationSnack(BuildContext context, String message, {bool error = false}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  messenger
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: error ? AppColors.error : AppColors.success,
      behavior: SnackBarBehavior.floating,
    ));
}

void showCelebrationError(BuildContext context, Object e) =>
    showCelebrationSnack(context, ErrorMessageUtils.toUserFriendlyMessage(e), error: true);

class CelebrationErrorView extends StatelessWidget {
  const CelebrationErrorView({super.key, required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 24),
          Center(
            child: Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(color: AppColors.errorBg, shape: BoxShape.circle),
              child: const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 30),
            ),
          ),
          const SizedBox(height: 16),
          Text(message,
              textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary, fontSize: 14, height: 1.4)),
          const SizedBox(height: 8),
          Center(child: TextButton(onPressed: onRetry, child: const Text('Retry'))),
        ],
      );
}

class CelebrationEmptyView extends StatelessWidget {
  const CelebrationEmptyView({super.key, required this.icon, required this.title, required this.subtitle});
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: Column(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.12), shape: BoxShape.circle),
              child: Icon(icon, size: 30, color: AppColors.primaryText),
            ),
            const SizedBox(height: 16),
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            const SizedBox(height: 6),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.45)),
          ],
        ),
      );
}

class CelebrationCard extends StatelessWidget {
  const CelebrationCard({super.key, required this.child, this.highlighted = false, this.padding = const EdgeInsets.all(16)});
  final Widget child;
  final bool highlighted;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: highlighted ? AppColors.primary : const Color(0xFFECEEF1), width: highlighted ? 1.4 : 1),
          boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 10, offset: Offset(0, 3))],
        ),
        child: child,
      );
}
