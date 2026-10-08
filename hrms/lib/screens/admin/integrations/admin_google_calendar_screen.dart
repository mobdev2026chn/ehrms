// Admin "Google Calendar & Meet": the company's Google connection used for interview Meet links,
// like the web (features/admin/integrations/pages/GoogleCalendarConfig.tsx).
//   GET    /admin/integrations/google-calendar/status
//   GET    /admin/integrations/google-calendar/connect-url  -> opened in the external browser
//   DELETE /admin/integrations/google-calendar              (disconnect)
// The web's OAuth-credentials card is not here: the backend has no /credentials routes (the
// client ID/secret come from the server .env), and the web's sync switches are UI only.

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../widgets/app_card.dart';
import '../../../config/app_colors.dart';
import '../../../services/admin_integrations_service.dart';
import '../../../utils/error_message_utils.dart';
import '../../../widgets/app_tab_loader.dart';

class AdminGoogleCalendarScreen extends StatefulWidget {
  const AdminGoogleCalendarScreen({super.key});

  @override
  State<AdminGoogleCalendarScreen> createState() => _AdminGoogleCalendarScreenState();
}

class _AdminGoogleCalendarScreenState extends State<AdminGoogleCalendarScreen> with WidgetsBindingObserver {
  final _service = AdminIntegrationsService();
  GoogleCalendarStatus? _status;
  String? _error;
  bool _connecting = false;
  bool _disconnecting = false;

  /// Set while the Google sign-in is open in the browser, so coming back refreshes the status.
  bool _awaitingReturn = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _awaitingReturn) {
      _awaitingReturn = false;
      _refreshAfterConnect();
    }
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final s = await _service.getGoogleCalendarStatus();
      if (mounted) setState(() => _status = s);
    } catch (e) {
      if (mounted) setState(() => _error = ErrorMessageUtils.toUserFriendlyMessage(e));
    }
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? AppColors.error : AppColors.success,
    ));
  }

  Future<void> _refreshAfterConnect() async {
    final wasConnected = _status?.connected ?? false;
    try {
      final s = await _service.getGoogleCalendarStatus();
      if (!mounted) return;
      setState(() => _status = s);
      if (s.connected && !wasConnected) _snack('Google account connected');
    } catch (e) {
      _snack(ErrorMessageUtils.toUserFriendlyMessage(e), error: true);
    }
  }

  Future<void> _connect() async {
    setState(() => _connecting = true);
    try {
      final url = await _service.getGoogleCalendarConnectUrl();
      final uri = Uri.tryParse(url);
      if (uri == null) throw Exception('The Google sign-in link is not valid');
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened) throw Exception('Could not open the browser for Google sign-in');
      _awaitingReturn = true;
      _snack('Finish signing in with Google in the browser, then come back to the app.');
    } catch (e) {
      _snack(ErrorMessageUtils.toUserFriendlyMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  Future<void> _disconnect() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Disconnect Google account?'),
        content: const Text(
            'New interviews will no longer get Google Meet links. Existing Meet links stay as they are.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _disconnecting = true);
    try {
      final s = await _service.disconnectGoogleCalendar();
      if (!mounted) return;
      setState(() => _status = s);
      _snack('Google account disconnected');
    } catch (e) {
      _snack(ErrorMessageUtils.toUserFriendlyMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _disconnecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Google Calendar & Meet')),
      body: _body(),
    );
  }

  Widget _body() {
    final s = _status;
    if (s == null) {
      if (_error != null) {
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
      return const Center(child: AppTabLoader());
    }

    final (String pillLabel, Color pillColor, Color pillBg) = s.connected
        ? ('Connected', AppColors.success, AppColors.successBg)
        : s.configured
            ? ('Configured', AppColors.brandDark, AppColors.brandLight)
            : ('Not Connected', AppColors.textSecondary, AppColors.inputFill);

    final String title;
    final String subtitle;
    if (s.connected) {
      title = 'Google Account Connected';
      subtitle = 'Meet links will be created with ${s.googleEmail.isNotEmpty ? s.googleEmail : 'this account'}.';
    } else if (s.needsReconnect) {
      title = 'Reconnect Required';
      subtitle = 'Google access expired or was revoked. Connect again to keep creating Meet links.';
    } else if (s.configured) {
      title = 'Ready to Connect';
      subtitle = 'Sign in with the Google account that should create interview Meet links.';
    } else {
      title = 'Not Set Up on the Server';
      subtitle = 'Google sign-in is not configured on the server (GOOGLE_CLIENT_ID / GOOGLE_CLIENT_SECRET). '
          'Ask your administrator to set it up.';
    }

    final details = <(String, String)>[
      if (s.googleEmail.isNotEmpty) ('Google account', s.googleEmail),
      if (s.connectedByName.isNotEmpty) ('Connected by', s.connectedByName),
      if (s.connectedAt != null) ('Last updated', _fmtDate(s.connectedAt!)),
    ];

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Connect your Google Calendar to create Meet links for interviews',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 13.5, height: 1.4)),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: pillBg, borderRadius: BorderRadius.circular(999)),
                child: Text(pillLabel, style: TextStyle(color: pillColor, fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          AppCard(
            padding: const EdgeInsets.all(20),
            border: Border.all(color: const Color(0xFFECEEF1)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: s.connected ? AppColors.successBg : AppColors.infoBg,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(s.connected ? Icons.check_circle_outline_rounded : Icons.calendar_month_outlined,
                          color: s.connected ? AppColors.success : AppColors.info),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 16, color: AppColors.textPrimary)),
                          const SizedBox(height: 4),
                          Text(subtitle, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4)),
                        ],
                      ),
                    ),
                  ],
                ),
                if (details.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Divider(height: 1),
                  const SizedBox(height: 8),
                  for (final (k, v) in details)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 120,
                            child: Text(k, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                          ),
                          Expanded(
                            child: Text(v,
                                style: const TextStyle(
                                    color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w500)),
                          ),
                        ],
                      ),
                    ),
                ],
                const SizedBox(height: 20),
                SizedBox(width: double.infinity, height: 48, child: _action(s)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Google sign-in opens in your browser. When it finishes, return to the app - the status refreshes '
            'automatically (or pull down to refresh).',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _action(GoogleCalendarStatus s) {
    if (s.connected) {
      return OutlinedButton.icon(
        onPressed: _disconnecting ? null : _disconnect,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.error,
          side: const BorderSide(color: AppColors.error, width: 1.2),
        ),
        icon: _disconnecting ? _spinner(AppColors.error) : const Icon(Icons.link_off_rounded, size: 18),
        label: const Text('Disconnect'),
      );
    }
    return ElevatedButton.icon(
      onPressed: (!s.configured || _connecting) ? null : _connect,
      icon: _connecting ? _spinner(AppColors.onPrimary) : const Icon(Icons.link_rounded, size: 18),
      label: Text(s.needsReconnect ? 'Reconnect Google Account' : 'Connect Google Account'),
    );
  }

  static Widget _spinner(Color c) =>
      SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: c));

  static String _fmtDate(DateTime d) {
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.day} ${m[d.month - 1]} ${d.year}, ${two(d.hour)}:${two(d.minute)}';
  }
}
