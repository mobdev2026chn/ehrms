import 'dart:async';
import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:background_location_tracker/background_location_tracker.dart';
import 'services/alarm_service.dart';
import 'services/auth_service.dart';
import 'services/fcm_service.dart';
import 'config/app_route_observer.dart';
import 'services/geo/live_tracking_service.dart';
import 'services/presence_tracking_service.dart';
import 'providers/theme_provider.dart';
import 'screens/splash/splash_screen.dart';
import 'widgets/deactivation_check_wrapper.dart';
import 'bloc/auth/auth_bloc.dart';
import 'bloc/task/task_bloc.dart';
import 'bloc/attendance/attendance_bloc.dart';

const Duration _defaultBackgroundLocationInterval = Duration(minutes: 1);

@pragma('vm:entry-point')
void backgroundCallback() {
  BackgroundLocationTrackerManager.handleBackgroundUpdated((data) async {
    final lat = data.lat;
    final lon = data.lon;
    final speedMps = data.speed;
    int? batteryPercent;
    try {
      batteryPercent = await Battery().batteryLevel;
    } catch (_) {}
    await LiveTrackingService.sendTrackingFromBackground(
      lat,
      lon,
      batteryPercent: batteryPercent,
      speedMps: speedMps,
      accuracyM: data.horizontalAccuracy,
    );
    await PresenceTrackingService.sendPresenceFromBackground(
      lat,
      lon,
      batteryPercent: batteryPercent,
      accuracyM: data.horizontalAccuracy,
      speedMps: speedMps,
    );
  });
}

void main() {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      debugPrint(
        '[FCM] main: registering onBackgroundMessage handler (required for app closed/background → in-app list)',
      );
      FirebaseMessaging.onBackgroundMessage(firebaseBackgroundMessageHandler);

      // Catch unhandled async errors (e.g. from plugins) so release build doesn't show black screen on some devices
      FlutterError.onError = (details) {
        FlutterError.presentError(details);
        if (kReleaseMode) {
          debugPrint('[FlutterError] ${details.exception} ${details.stack}');
        }
      };

      if (kReleaseMode) {
        ErrorWidget.builder = (details) => Material(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Text(
                'Something went wrong.\nPlease restart the app.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[700], fontSize: 14),
              ),
            ),
          ),
        );
      }

      try {
        await Firebase.initializeApp();
      } catch (e, st) {
        debugPrint('[main] Firebase.initializeApp failed: $e $st');
        runApp(
          _InitErrorApp(
            message:
                'App could not start. Please check your internet or reinstall.',
          ),
        );
        return;
      }

      try {
        final sessionReset = await AuthService().clearSessionIfBaseUrlChanged();
        if (sessionReset) {
          debugPrint(
            '[main] Cleared stale session because baseUrl changed before startup init',
          );
        }
      } catch (e, st) {
        debugPrint(
          '[main] clearSessionIfBaseUrlChanged failed (continuing): $e',
        );
        if (kDebugMode) debugPrint('[main] clearSessionIfBaseUrlChanged stack: $st');
      }

      try {
        await AlarmService.initializeTimezone();
      } catch (e) {
        debugPrint('[main] AlarmService timezone init failed (continuing): $e');
      }

      try {
        debugPrint('[main] FCM init starting...');
        await FcmService.init();
        debugPrint('[main] FCM init completed');
      } catch (e, st) {
        debugPrint('[main] FCM init FAILED (continuing): $e');
        if (kDebugMode) debugPrint('[main] FCM init stack: $st');
      }

      try {
        await BackgroundLocationTrackerManager.initialize(
          backgroundCallback,
          config: const BackgroundLocationTrackerConfig(
            loggingEnabled: true,
            androidConfig: AndroidConfig(
              notificationIcon: 'explore',
              notificationBody: 'Live tracking in progress. Tap to open.',
              channelName: 'Live Tracking',
              cancelTrackingActionText: 'Stop tracking',
              enableCancelTrackingAction: true,
              trackingInterval: _defaultBackgroundLocationInterval,
              distanceFilterMeters: null,
            ),
            iOSConfig: IOSConfig(
              activityType: ActivityType.FITNESS,
              distanceFilterMeters: 40,
              restartAfterKill: true,
            ),
          ),
        );
      } catch (e, st) {
        debugPrint(
          '[main] BackgroundLocationTracker init failed (continuing): $e $st',
        );
      }

      runApp(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => ThemeProvider()),
            BlocProvider(create: (_) => AuthBloc()),
            BlocProvider(create: (_) => TaskBloc()),
            BlocProvider(create: (_) => AttendanceBloc()),
          ],
          child: const MyApp(),
        ),
      );
    },
    (error, stack) {
      debugPrint('[runZonedGuarded] Unhandled error: $error $stack');
      if (kReleaseMode) {
        // Ensure we don't leave the app in a black screen; if runApp wasn't called yet, show error
        // (runApp may already have been called, so this only helps for pre-runApp errors)
      }
    },
  );
}

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Shown when Firebase (or critical init) fails so user sees a message instead of black screen.
class _InitErrorApp extends StatelessWidget {
  const _InitErrorApp({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline, size: 48, color: Colors.grey[600]),
                  const SizedBox(height: 16),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey[800], fontSize: 16),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    FcmService.navigatorKey = navigatorKey;
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        final lightTheme = themeProvider.getThemeData().copyWith(
          textTheme: themeProvider.getThemeData().textTheme.apply(
            fontFamily: 'Inter',
          ),
        );
        final darkTheme = themeProvider.getDarkThemeData().copyWith(
          textTheme: themeProvider.getDarkThemeData().textTheme.apply(
            fontFamily: 'Inter',
          ),
        );
        return MaterialApp(
          navigatorKey: navigatorKey,
          navigatorObservers: [appRouteObserver],
          title: 'ektaHr',
          debugShowCheckedModeBanner: false,
          theme: lightTheme,
          darkTheme: darkTheme,
          themeMode: themeProvider.themeMode,
          builder: (context, child) => DeactivationCheckWrapper(
            navigatorKey: navigatorKey,
            child: child ?? const SizedBox.shrink(),
          ),
          home: const SplashScreen(),
        );
      },
    );
  }
}
