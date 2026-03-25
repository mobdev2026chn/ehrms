// When app is open and user is logged in, check every 5s if staff is still active.
// If deactivated, logout silently (no notification) and navigate to login.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../bloc/auth/auth_bloc.dart';
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scheduleNextCheck();
    unawaited(_handleResumeForLoggedInUser());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
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
    if (prefs.getString('token') == null || prefs.getString('token')!.isEmpty) return;
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
