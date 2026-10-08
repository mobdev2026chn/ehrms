// When app is open and user is logged in, check every 5s if staff is still active.
// If deactivated, logout silently (no notification) and navigate to login.
// The same poll also notices when the account signed in on another phone (the backend
// then answers SESSION_REPLACED) and signs this phone out with a message.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../bloc/auth/auth_bloc.dart';
import '../core/network/dio_client.dart' show onSessionReplaced;
import 'app_drawer.dart';
import '../screens/auth/login_screen.dart';
import '../services/auth_service.dart';
import '../services/fcm_service.dart';
import '../services/geo/live_tracking_service.dart';
import '../services/geo/location_service.dart';
import '../services/presence_tracking_service.dart';

class DeactivationCheckWrapper extends StatefulWidget {
  const DeactivationCheckWrapper({
    super.key,
    required this.child,
    required this.navigatorKey,
  });

  final Widget child;
  final GlobalKey<NavigatorState> navigatorKey;

  @override
  State<DeactivationCheckWrapper> createState() => _DeactivationCheckWrapperState();
}

class _DeactivationCheckWrapperState extends State<DeactivationCheckWrapper> with WidgetsBindingObserver {
  Timer? _timer;
  static const Duration _checkInterval = Duration(seconds: 5);
  bool _hadLoggedInSession = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    onSessionReplaced = _signOutReplacedSession;
    _scheduleNextCheck();
    unawaited(_handleResumeForLoggedInUser());
  }

  @override
  void dispose() {
    if (onSessionReplaced == _signOutReplacedSession) onSessionReplaced = null;
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  /// The account signed in on another phone (only one mobile session is allowed):
  /// stop this phone's tracking, sign out, go to login and say why.
  Future<void> _signOutReplacedSession(String message) async {
    // Stops the token==null branch of [_checkActive] racing us to the login screen.
    _hadLoggedInSession = false;
    _timer?.cancel();
    _timer = null;
    AppDrawer.resetMenuMemory();
    try {
      await AuthService().logout();
    } catch (e) {
      debugPrint('[DeactivationCheckWrapper] logout after session replaced failed: $e');
    }
    if (!mounted) return;
    context.read<AuthBloc>().add(const AuthLogoutRequested());
    final nav = widget.navigatorKey.currentState;
    if (nav == null) return;
    nav.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
    final dialogContext = widget.navigatorKey.currentContext;
    if (dialogContext == null || !dialogContext.mounted) return;
    await showDialog<void>(
      context: dialogContext,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.devices_other_rounded, size: 36),
        title: const Text('Signed in on another device'),
        content: Text(message),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_handleResumeForLoggedInUser());
    } else if (state == AppLifecycleState.detached) {
      PresenceTrackingService().recordAppClosed();
      LiveTrackingService().markAppClosed();
      _timer?.cancel();
      _timer = null;
    } else {
      PresenceTrackingService().markAppBackground();
      LiveTrackingService().markAppBackground();
      _timer?.cancel();
      _timer = null;
    }
  }

  Future<void> _handleResumeForLoggedInUser() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token == null || token.isEmpty || !mounted) return;
    _hadLoggedInSession = true;

    PresenceTrackingService().markAppForeground();
    LiveTrackingService().markAppForeground();
    _scheduleNextCheck();
    FcmService.sendTokenToBackend();
    LocationService.syncLocationPermissionStatusToBackend();
    // Resume presence tracking timer and insert one "active" record.
    PresenceTrackingService().recordAppOpened();
    PresenceTrackingService().onAppLifecycleResumed();
  }

  void _scheduleNextCheck() {
    _timer?.cancel();
    _timer = Timer.periodic(_checkInterval, (_) => _checkActive());
  }

  Future<void> _checkActive() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token == null || token.isEmpty) {
      // Global session-expiry interceptor clears token immediately on 401/jwt-expired.
      // If this app runtime had a logged-in session, force back to login.
      if (_hadLoggedInSession && mounted) {
        // Drawer (or other) logout may already have cleared the stack to [LoginScreen].
        // A second pushAndRemoveUntil remounts Login and replays entrance animations.
        context.read<AuthBloc>().add(const AuthLogoutRequested());
        final nav = widget.navigatorKey.currentState;
        if (nav != null && nav.canPop()) {
          _timer?.cancel();
          _timer = null;
          nav.pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const LoginScreen()),
            (_) => false,
          );
        }
        _hadLoggedInSession = false;
      }
      return;
    }
    _hadLoggedInSession = true;
    final active = await AuthService().checkStaffActive();
    if (active == false && mounted) {
      _timer?.cancel();
      _timer = null;
      context.read<AuthBloc>().add(AuthLogoutRequested());
      widget.navigatorKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (_) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
