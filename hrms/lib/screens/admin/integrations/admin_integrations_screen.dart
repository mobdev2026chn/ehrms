// Admin "Integrations": the services the HRMS can connect to, grouped by category, like the web
// (features/admin/integrations/pages/Integrations.tsx). Google Calendar & Meet reads its status
// from GET /admin/integrations/google-calendar/status and opens its own screen; the email
// services have no backend yet and are shown as "Coming soon".

import 'package:flutter/material.dart';

import '../../../widgets/app_card.dart';
import '../../../config/app_colors.dart';
import '../../../services/admin_integrations_service.dart';
import '../../../utils/error_message_utils.dart';
import '../../../widgets/app_tab_loader.dart';
import 'admin_google_calendar_screen.dart';
import 'integration_definitions.dart';

class AdminIntegrationsScreen extends StatefulWidget {
  const AdminIntegrationsScreen({super.key});

  @override
  State<AdminIntegrationsScreen> createState() => _AdminIntegrationsScreenState();
}

class _AdminIntegrationsScreenState extends State<AdminIntegrationsScreen> {
  IntegrationCategoryKey _category = IntegrationCategoryKey.email;
  GoogleCalendarStatus? _google;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _google == null;
      _error = null;
    });
    try {
      final s = await AdminIntegrationsService().getGoogleCalendarStatus();
      if (mounted) {
        setState(() {
          _google = s;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = ErrorMessageUtils.toUserFriendlyMessage(e);
          _loading = false;
        });
      }
    }
  }

  bool _isConnected(IntegrationDefinition i) => i.id == 'google-calendar' && (_google?.connected ?? false);

  Future<void> _open(IntegrationDefinition i) async {
    if (i.id != 'google-calendar') return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AdminGoogleCalendarScreen()));
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Integrations')),
      body: _body(),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: AppTabLoader());
    if (_error != null && _google == null) {
      return ListView(
        padding: const EdgeInsets.all(32),
        children: [
          const SizedBox(height: 56),
          Center(
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(color: AppColors.error.withValues(alpha: 0.12), shape: BoxShape.circle),
              child: const Icon(Icons.wifi_off_rounded, size: 28, color: AppColors.error),
            ),
          ),
          const SizedBox(height: 16),
          Text(_error!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          const SizedBox(height: 16),
          Center(child: OutlinedButton(onPressed: _load, child: const Text('Retry'))),
        ],
      );
    }
    final category = integrationCategories.firstWhere((c) => c.key == _category);
    final listed = integrationDefinitions.where((i) => i.category == _category).toList();
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Connect and configure third-party services to enhance your HRMS experience',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13.5, height: 1.4)),
          const SizedBox(height: 20),
          const _SectionTitle('Available Integrations'),
          const SizedBox(height: 12),
          Row(
            children: [
              for (final c in integrationCategories) ...[
                Expanded(child: _categoryTile(c)),
                if (c != integrationCategories.last) const SizedBox(width: 12),
              ],
            ],
          ),
          const SizedBox(height: 24),
          _SectionTitle('${category.label} Integrations'),
          const SizedBox(height: 12),
          if (listed.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: Text('No integrations.', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary))),
            ),
          for (final i in listed)
            Padding(padding: const EdgeInsets.only(bottom: 12), child: _integrationCard(i)),
        ],
      ),
    );
  }

  Widget _categoryTile(IntegrationCategory c) {
    final active = c.key == _category;
    final connected = integrationDefinitions.where((i) => i.category == c.key && _isConnected(i)).length;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => setState(() => _category = c.key),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: active ? AppColors.brandLight : AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: active ? AppColors.primary : const Color(0xFFECEEF1), width: active ? 1.5 : 1),
          boxShadow: active ? null : kSoftCardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(c.icon, size: 20, color: active ? AppColors.brandDark : AppColors.textPrimary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(c.label,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: AppColors.textPrimary)),
                ),
                if (connected > 0) _Pill('$connected connected', AppColors.success, AppColors.successBg),
              ],
            ),
            const SizedBox(height: 6),
            Text(c.description, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
          ],
        ),
      ),
    );
  }

  Widget _integrationCard(IntegrationDefinition i) {
    final _Pill pill;
    if (!i.available) {
      pill = const _Pill('Coming soon', AppColors.textSecondary, AppColors.inputFill);
    } else if (_google?.connected ?? false) {
      pill = const _Pill('Connected', AppColors.success, AppColors.successBg);
    } else if (_google?.needsReconnect ?? false) {
      pill = const _Pill('Reconnect required', AppColors.error, AppColors.errorBg);
    } else if (_google?.configured ?? false) {
      pill = const _Pill('Configured', AppColors.brandDark, AppColors.brandLight);
    } else {
      pill = const _Pill('Not Connected', AppColors.textSecondary, AppColors.inputFill);
    }

    return Opacity(
      opacity: i.available ? 1 : 0.6,
      child: AppCard(
        border: Border.all(color: const Color(0xFFECEEF1)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: i.toneBg, borderRadius: BorderRadius.circular(12)),
                  child: Icon(i.icon, color: i.tone, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(i.name,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: AppColors.textPrimary)),
                      const SizedBox(height: 2),
                      Text(i.subtitle, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                pill,
              ],
            ),
            const SizedBox(height: 12),
            Text(i.description, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4)),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: i.available ? () => _open(i) : null,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primaryText,
                  side: BorderSide(color: i.available ? AppColors.primary : const Color(0xFFE2E5EA), width: 1.2),
                ),
                child: Text(i.available ? 'Configure' : 'Coming soon'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) =>
      Text(text, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: AppColors.textPrimary));
}

class _Pill extends StatelessWidget {
  const _Pill(this.label, this.color, this.bg);
  final String label;
  final Color color;
  final Color bg;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
        child: Text(label, style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w600)),
      );
}
