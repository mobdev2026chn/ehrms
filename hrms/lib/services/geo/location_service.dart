import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart' as gl;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hrms/models/location_data.dart';
import 'package:hrms/services/api_client.dart';
import 'package:hrms/services/geo/live_tracking_service.dart';
import 'package:background_location_tracker/background_location_tracker.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Geofence stream events: ENTER=inside, EXIT=outside (accuracy OK), LOW_ACCURACY=can't validate
class GeofenceEvent {
  static const String enter = 'ENTER';
  static const String exit = 'EXIT';
  static const String lowAccuracy = 'LOW_ACCURACY';
}

class LocationService {
  static final LocationService _instance = LocationService._internal();
  static bool _ensureAppLocationAccessInProgress = false;
  static bool _ensurePersistentTaskTrackingAccessInProgress = false;
  static bool _syncLocationPermissionStatusInProgress = false;
  static final ApiClient _api = ApiClient();

  factory LocationService() {
    return _instance;
  }

  LocationService._internal();

  final StreamController<Location> _locationController =
      StreamController<Location>.broadcast();
  Stream<Location> get locationStream => _locationController.stream;

  final StreamController<String> _geofenceController =
      StreamController<String>.broadcast();
  Stream<String> get geofenceStream => _geofenceController.stream;

  LatLng? _geofenceCenter;

  /// Base geofence radius in meters (>= 100m per requirements).
  static const double baseRadius = 300;

  /// Accuracy threshold: above this, do NOT show "outside geofence" warning.
  static const double accuracyThresholdMeters = 40;

  StreamSubscription<gl.Position>? _geolocatorSubscription;

  /// Update geofence center when destination changes (single source of truth).
  void updateGeofenceCenter(LatLng center) {
    _geofenceCenter = center;
  }

  static bool _isMissingTrackerPluginError(Object error) {
    return error is MissingPluginException ||
        (error is PlatformException &&
            (error.code.toLowerCase().contains('missing_plugin') ||
                (error.message ?? '').toLowerCase().contains(
                  'no implementation found',
                )));
  }

  /// [context] optional: when provided on Android, shows Play-required in-app
  /// disclosure before requesting background location (required for live tracking when app is in background).
  Future<void> initLocationService({
    required LatLng customerLocation,
    BuildContext? context,
  }) async {
    _geofenceCenter = customerLocation;
    await _checkAndRequestPermissions();

    // Play policy: request background location only after in-app disclosure (Android).
    if (Platform.isAndroid) {
      final hasBackground = await Permission.locationAlways.isGranted;
      if (!hasBackground && context != null) {
        await showBackgroundLocationDisclosureAndRequest(context);
      }
      if (context != null) {
        await ensurePersistentTaskTrackingAccess(context);
      }
    }

    // Get initial position immediately so map and tracking start right away.
    try {
      final pos = await gl.Geolocator.getCurrentPosition(
        desiredAccuracy: gl.LocationAccuracy.high,
      );
      final loc = Location.fromPosition(pos);
      if (loc.latitude != null && loc.longitude != null) {
        _locationController.add(loc);
      }
    } catch (_) {}

    // Start Geolocator for frequent foreground updates (every 2m when moving).
    // This ensures lat/long update as you move and route refreshes like Google Maps.
    _geolocatorSubscription =
        gl.Geolocator.getPositionStream(
          locationSettings: gl.LocationSettings(
            accuracy: gl.LocationAccuracy.high,
            distanceFilter: 2, // Update every 2 meters for responsive tracking
          ),
        ).listen((gl.Position position) {
          final loc = Location.fromPosition(position);
          if (loc.latitude != null && loc.longitude != null) {
            _locationController.add(loc);
            _classifyMovement(loc.speed ?? 0);
            _checkGeofence(loc);
          }
        });

    // Keep background tracker for when app goes to background.
    // Uses foreground service with persistent notification; app can go background or be swiped away.
    const liveTrackingConfig = AndroidConfig(
      notificationIcon: 'explore',
      notificationBody: 'Live tracking in progress. Tap to open.',
      channelName: 'Live Tracking',
      cancelTrackingActionText: 'Stop tracking',
      enableCancelTrackingAction: true,
      trackingInterval: Duration(seconds: 5),
      // null = time-based updates every 5s even when stationary. Critical for background.
      distanceFilterMeters: null,
    );
    try {
      await BackgroundLocationTrackerManager.startTracking(
        config: liveTrackingConfig,
      );
      BackgroundLocationTrackerManager.handleBackgroundUpdated((data) async {
        final Location currentLocation = Location.fromBackgroundData(data);
        if (currentLocation.latitude != null &&
            currentLocation.longitude != null) {
          _locationController.add(currentLocation);
          _classifyMovement(currentLocation.speed ?? 0);
          _checkGeofence(currentLocation);
          // Send to backend when app is in background (main isolate still alive)
          await LiveTrackingService.sendTrackingFromBackground(
            currentLocation.latitude!,
            currentLocation.longitude!,
            speedMps: currentLocation.speed,
            accuracyM: currentLocation.accuracy,
          );
        }
      });
    } catch (e) {
      if (kDebugMode) {
        final prefix = _isMissingTrackerPluginError(e)
            ? '[LocationService] background tracker plugin unavailable'
            : '[LocationService] background tracker start failed';
        debugPrint('$prefix: $e');
      }
    }
  }

  void _checkGeofence(Location currentLocation) {
    if (_geofenceCenter == null) return;

    final currentLat = currentLocation.latitude ?? 0.0;
    final currentLng = currentLocation.longitude ?? 0.0;
    final destLat = _geofenceCenter!.latitude;
    final destLng = _geofenceCenter!.longitude;

    final distanceInMeters = gl.Geolocator.distanceBetween(
      currentLat,
      currentLng,
      destLat,
      destLng,
    );

    // Treat null/negative accuracy as poor (avoid false "outside" warnings).
    final accuracy =
        (currentLocation.accuracy != null && currentLocation.accuracy! >= 0)
        ? currentLocation.accuracy!
        : 999.0;

    // Adaptive radius: base + accuracy to absorb GPS drift.
    final effectiveRadius = baseRadius + accuracy;

    // Accuracy-aware validation: do NOT show "outside geofence" when accuracy > 40m.
    if (accuracy > accuracyThresholdMeters) {
      _geofenceController.add(GeofenceEvent.lowAccuracy);
      return;
    }

    final isInside = distanceInMeters <= effectiveRadius;
    final status = isInside ? GeofenceEvent.enter : GeofenceEvent.exit;
    _geofenceController.add(status);
  }

  Future<void> _checkAndRequestPermissions() async {
    gl.LocationPermission permission = await gl.Geolocator.checkPermission();
    if (permission == gl.LocationPermission.denied) {
      permission = await gl.Geolocator.requestPermission();
      if (permission == gl.LocationPermission.denied) {
        return Future.error('Location permissions are denied');
      }
    }
    if (permission == gl.LocationPermission.deniedForever) {
      return Future.error(
        'Location permissions are permanently denied, we cannot request permissions.',
      );
    }
  }

  /// Play Store requirement: prominent in-app disclosure before requesting
  /// background location. Explains use and then requests "Allow all the time".
  static Future<void> showBackgroundLocationDisclosureAndRequest(
    BuildContext context, {
    String title = 'Location access for live tracking',
    String? message,
  }) async {
    final shown = await _showLocationPermissionDialog(
      context,
      emoji: '📍',
      title: title,
      message:
          message ??
          'To show your live position to your organization while you are on a task (including when the app is in the background or the screen is off), this app needs "Allow all the time" location access.\n\n'
              'Your location is used only for task tracking and is sent to your organization\'s HRMS server. It is not shared with third parties for advertising.',
      confirmText: 'Continue',
    );
    if (shown == true) {
      await Permission.locationAlways.request();
    }
  }

  static Future<void> ensureAppLocationAccess(
    BuildContext context, {
    bool requestBackgroundAlways = true,
  }) async {
    if (_ensureAppLocationAccessInProgress) return;
    _ensureAppLocationAccessInProgress = true;
    try {
      final serviceEnabled = await gl.Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        final open = await _showLocationPermissionDialog(
          context,
          emoji: '📡',
          title: 'Enable GPS',
          message:
              'Location services are turned off. Please enable GPS/location services so the app can detect your location.',
          confirmText: 'Open settings',
        );
        if (open == true) {
          await gl.Geolocator.openLocationSettings();
        }
        return;
      }

      var permission = await gl.Geolocator.checkPermission();
      if (permission == gl.LocationPermission.denied) {
        permission = await gl.Geolocator.requestPermission();
      }

      if (permission == gl.LocationPermission.denied) {
        return;
      }

      if (permission == gl.LocationPermission.deniedForever) {
        final open = await _showLocationPermissionDialog(
          context,
          emoji: '📍',
          title: 'Allow location',
          message:
              'Location permission is permanently denied. Please allow location access from app settings.',
          confirmText: 'Open app settings',
        );
        if (open == true) {
          await openAppSettings();
        }
        return;
      }

      if (Platform.isAndroid && requestBackgroundAlways) {
        final hasBackground = await Permission.locationAlways.isGranted;
        if (!hasBackground && context.mounted) {
          final open = await _showLocationPermissionDialog(
            context,
            emoji: '📍',
            title: 'Allow location all the time',
            message:
                'Background location is not enabled for this app. Please open this app\'s location permission settings and choose "Allow all the time" so attendance and tracking can continue when the app is in the background or closed.',
            confirmText: 'Open app settings',
          );
          if (open == true) {
            await openAppSettings();
          }
        }
      }

      final preciseEnabled = await _isPreciseLocationEnabled();
      if (!preciseEnabled && context.mounted) {
        final open = await _showLocationPermissionDialog(
          context,
          emoji: '🛰️',
          title: 'Enable precise location',
          message:
              'Precise location is turned off for this app. Please open this app\'s location permission settings and enable precise location for more accurate attendance and tracking.',
          confirmText: 'Open app settings',
        );
        if (open == true) {
          await openAppSettings();
        }
      }
    } finally {
      await syncLocationPermissionStatusToBackend();
      _ensureAppLocationAccessInProgress = false;
    }
  }

  /// Best-effort Android hardening so live task tracking continues when the app
  /// is backgrounded, the screen is off, or the task is swiped away.
  static Future<void> ensurePersistentTaskTrackingAccess(
    BuildContext context,
  ) async {
    if (!Platform.isAndroid || _ensurePersistentTaskTrackingAccessInProgress) {
      return;
    }
    _ensurePersistentTaskTrackingAccessInProgress = true;
    try {
      final hasBackgroundAlways = await Permission.locationAlways.isGranted;
      if (!hasBackgroundAlways && context.mounted) {
        final allow = await _showLocationPermissionDialog(
          context,
          emoji: '📍',
          title: 'Allow location all the time',
          message:
              'To keep task tracking working when the app is in the background, the phone is sleeping, or the app is closed, this app needs "Allow all the time" location access.',
          cancelText: 'Not now',
          confirmText: 'Continue',
        );
        if (allow == true) {
          await Permission.locationAlways.request();
        }
      }

      final ignoreBatteryOptimizations =
          await Permission.ignoreBatteryOptimizations.isGranted;
      if (!ignoreBatteryOptimizations && context.mounted) {
        final allow = await _showLocationPermissionDialog(
          context,
          emoji: '🔋',
          title: 'Allow unrestricted battery usage',
          message:
              'To keep task tracking running while the phone is sleeping or the app is closed, allow this app to ignore battery optimization. This helps Android avoid stopping background location updates.',
          cancelText: 'Not now',
          confirmText: 'Allow',
        );
        if (allow == true) {
          final status = await Permission.ignoreBatteryOptimizations.request();
          if (!status.isGranted && context.mounted) {
            final openSettings = await _showLocationPermissionDialog(
              context,
              emoji: '🔋',
              title: 'Open app settings',
              message:
                  'Battery optimization is still enabled for this app. Open app settings and allow unrestricted battery/background usage for more reliable live task tracking.',
              cancelText: 'Later',
              confirmText: 'Open app settings',
            );
            if (openSettings == true) {
              await openAppSettings();
            }
          }
        }
      }
    } finally {
      _ensurePersistentTaskTrackingAccessInProgress = false;
    }
  }

  static Future<bool?> _showLocationPermissionDialog(
    BuildContext context, {
    required String emoji,
    required String title,
    required String message,
    String cancelText = 'Not now',
    String confirmText = 'Open app settings',
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final colorScheme = theme.colorScheme;

        return AlertDialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
          contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          title: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colorScheme.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  emoji,
                  style: const TextStyle(fontSize: 24),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    title,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                    ),
                  ),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Container(
              width: double.maxFinite,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withOpacity(0.45),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Text(
                message,
                style: theme.textTheme.bodyMedium?.copyWith(
                  height: 1.45,
                  color: colorScheme.onSurface.withOpacity(0.86),
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(cancelText),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(confirmText),
            ),
          ],
        );
      },
    );
  }

  static Future<bool> _isPreciseLocationEnabled() async {
    try {
      final permission = await gl.Geolocator.checkPermission();
      if (permission == gl.LocationPermission.denied ||
          permission == gl.LocationPermission.deniedForever) {
        return false;
      }
      final accuracy = await gl.Geolocator.getLocationAccuracy();
      return accuracy == gl.LocationAccuracyStatus.precise;
    } catch (_) {
      return false;
    }
  }

  static String _mapGpsAllowedLabel(
    gl.LocationPermission permission, {
    required bool hasBackgroundAlways,
  }) {
    if (permission == gl.LocationPermission.always || hasBackgroundAlways) {
      return 'Allow all the time';
    }
    if (permission == gl.LocationPermission.whileInUse) {
      return 'Allow only while using the app';
    }
    if (permission == gl.LocationPermission.unableToDetermine) {
      return 'Ask every time';
    }
    return "Don't allow";
  }

  static String? _sanitizeStoredToken(String? token) {
    if (token == null) return null;
    final trimmed = token.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.startsWith('"') || trimmed.endsWith('"')) {
      return trimmed.replaceAll('"', '');
    }
    return trimmed;
  }

  static Future<void> syncLocationPermissionStatusToBackend() async {
    if (_syncLocationPermissionStatusInProgress) return;
    _syncLocationPermissionStatusInProgress = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = _sanitizeStoredToken(prefs.getString('token'));
      if (token == null) return;

      final permission = await gl.Geolocator.checkPermission();
      final serviceEnabled = await gl.Geolocator.isLocationServiceEnabled();
      final hasBackgroundAlways = Platform.isAndroid
          ? await Permission.locationAlways.isGranted
          : permission == gl.LocationPermission.always;
      final preciseEnabled = await _isPreciseLocationEnabled();

      _api.setAuthToken(token);
      await _api.dio.put<dynamic>(
        '/auth/profile',
        data: <String, dynamic>{
          'isGpsEnabled': serviceEnabled,
          'isGpsAllowed': _mapGpsAllowedLabel(
            permission,
            hasBackgroundAlways: hasBackgroundAlways,
          ),
          'isEnabledPreciseLocation': preciseEnabled,
        },
      );
    } catch (error) {
      if (kDebugMode) {
        debugPrint('[LocationService] syncLocationPermissionStatus failed: $error');
      }
    } finally {
      _syncLocationPermissionStatusInProgress = false;
    }
  }

  String _classifyMovement(double speed) {
    if (speed > 10 / 3.6) {
      return "Driving";
    } else if (speed > 1 / 3.6) {
      return "Walking";
    } else {
      return "Standing";
    }
  }

  void dispose() {
    _geolocatorSubscription?.cancel();
    _geolocatorSubscription = null;
    _locationController.close();
    _geofenceController.close();
    unawaited(
      BackgroundLocationTrackerManager.stopTracking().catchError((_) {}),
    );
  }

  static double calculateDistance(LatLng start, LatLng end) {
    return gl.Geolocator.distanceBetween(
          start.latitude,
          start.longitude,
          end.latitude,
          end.longitude,
        ) /
        1000; // Convert to kilometers
  }
}
