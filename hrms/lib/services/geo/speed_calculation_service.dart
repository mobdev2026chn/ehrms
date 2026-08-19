import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart' as gl;
import 'package:activity_recognition_flutter/activity_recognition_flutter.dart';
import 'package:permission_handler/permission_handler.dart';

/// Output model for each speed calculation update.
class SpeedUpdate {
  /// Final speed in km/h (after smoothing and activity validation).
  final double speedKmh;

  /// Current detected activity (e.g. STILL, WALKING, IN_VEHICLE).
  final String activity;

  /// Raw GPS speed in m/s (from position.speed).
  final double? gpsSpeedMps;

  /// Manually calculated speed in m/s (distance/time).
  final double? calculatedSpeedMps;

  /// Which source was used: 'gps', 'calculated', or 'activity_override'.
  final String selectedSource;

  final DateTime timestamp;

  const SpeedUpdate({
    required this.speedKmh,
    required this.activity,
    this.gpsSpeedMps,
    this.calculatedSpeedMps,
    required this.selectedSource,
    required this.timestamp,
  });
}

/// Service for accurate real-time speed calculation using:
/// - activity_recognition_flutter: activity detection (IN_VEHICLE, WALKING, etc.)
/// - geolocator: GPS position (lat, lng, speed m/s)
///
/// Uses dual speed methods (GPS + calculated) with smoothing and activity-based validation.
class SpeedCalculationService {
  static final SpeedCalculationService _instance = SpeedCalculationService._internal();
  factory SpeedCalculationService() => _instance;

  SpeedCalculationService._internal();

  final StreamController<SpeedUpdate> _controller =
      StreamController<SpeedUpdate>.broadcast();
  Stream<SpeedUpdate> get speedStream => _controller.stream;

  StreamSubscription<gl.Position>? _gpsSubscription;
  StreamSubscription<ActivityEvent>? _activitySubscription;

  // Last position for calculated speed (distance/time).
  gl.Position? _lastPosition;
  DateTime? _lastPositionTime;

  // Activity state (STILL, WALKING, etc.).
  ActivityType _currentActivity = ActivityType.still;

  // Moving average buffer for smoothing (3–5 values).
  static const int _smoothWindowSize = 5;
  final List<double> _speedBufferMps = [];

  // Validity thresholds (all in m/s).
  static const double _minValidGpsSpeedMps = 0.1; // Ignore near-zero GPS noise.
  static const double _maxValidGpsSpeedMps = 200 / 3.6; // 200 km/h cap.
  static const double _humanMaxSpeedMps = 4.5; // ~16 km/h (fast run).
  static const double _walkRunMaxSpeedMps = 5.0; // Slight buffer for edge cases.

  bool _isRunning = false;

  /// Check and request required permissions.
  /// On iOS: do NOT request activity recognition (crashes).
  Future<bool> checkPermissions() async {
    // Location (required).
    gl.LocationPermission locPerm = await gl.Geolocator.checkPermission();
    if (locPerm == gl.LocationPermission.denied) {
      locPerm = await gl.Geolocator.requestPermission();
    }
    if (locPerm == gl.LocationPermission.deniedForever ||
        locPerm == gl.LocationPermission.denied) {
      return false;
    }

    // Activity recognition: Android only. iOS does not need runtime request.
    if (defaultTargetPlatform == TargetPlatform.android) {
      final status = await Permission.activityRecognition.status;
      if (!status.isGranted) {
        final result = await Permission.activityRecognition.request();
        if (!result.isGranted) {
          // Continue anyway; we can still use GPS speed.
        }
      }
    }

    return true;
  }

  /// Start listening to GPS and activity. Call when screen becomes visible.
  Future<void> start() async {
    if (_isRunning) return;

    final ok = await checkPermissions();
    if (!ok) return;

    _isRunning = true;
    _speedBufferMps.clear();
    _lastPosition = null;
    _lastPositionTime = null;

    // Start activity recognition (if available).
    try {
      final available = await ActivityRecognition().isAvailable();
      if (available) {
        _activitySubscription = ActivityRecognition()
            .activityStream(runForegroundService: false)
            .listen(_onActivityUpdate);
      }
    } catch (_) {}

    // GPS stream: reasonable interval to balance accuracy and battery.
    // distanceFilter: 3m, update every ~2–5 seconds when moving.
    _gpsSubscription = gl.Geolocator.getPositionStream(
      locationSettings: gl.LocationSettings(
        accuracy: gl.LocationAccuracy.high,
        distanceFilter: 3,
      ),
    ).listen(_onPositionUpdate);
  }

  /// Stop all subscriptions. Call when screen is disposed or app goes to background.
  Future<void> stop() async {
    if (!_isRunning) return;
    _isRunning = false;

    await _gpsSubscription?.cancel();
    _gpsSubscription = null;

    await _activitySubscription?.cancel();
    _activitySubscription = null;

    try {
      await ActivityRecognition().stopActivityUpdates();
    } catch (_) {}
  }

  /// Dispose the stream controller. Call when the service is no longer needed.
  void dispose() {
    stop();
    _controller.close();
  }

  void _onActivityUpdate(ActivityEvent event) {
    _currentActivity = event.type;
  }

  void _onPositionUpdate(gl.Position position) {
    final now = DateTime.now();

    // --- Method 1: GPS-provided speed (m/s) ---
    final gpsSpeedMps = _getValidGpsSpeed(position.speed);

    // --- Method 2: Calculated speed from last two points ---
    double? calculatedSpeedMps;
    if (_lastPosition != null && _lastPositionTime != null) {
      final distM = gl.Geolocator.distanceBetween(
        _lastPosition!.latitude,
        _lastPosition!.longitude,
        position.latitude,
        position.longitude,
      );
      final secs = now.difference(_lastPositionTime!).inMilliseconds / 1000.0;
      if (secs > 0.1) {
        // Avoid division by tiny values.
        calculatedSpeedMps = distM / secs;
      }
    }
    _lastPosition = position;
    _lastPositionTime = now;

    // --- Accuracy logic: prefer GPS if valid, else use calculated ---
    double rawSpeedMps;
    String selectedSource;

    if (gpsSpeedMps != null && gpsSpeedMps > _minValidGpsSpeedMps) {
      rawSpeedMps = gpsSpeedMps;
      selectedSource = 'gps';
    } else if (calculatedSpeedMps != null && calculatedSpeedMps >= 0) {
      rawSpeedMps = calculatedSpeedMps;
      selectedSource = 'calculated';
    } else {
      rawSpeedMps = 0;
      selectedSource = 'activity_override';
    }

    // --- Activity-based validation ---
    rawSpeedMps = _applyActivityValidation(rawSpeedMps);

    // --- Smoothing: moving average of last N values ---
    final smoothedMps = _smoothSpeed(rawSpeedMps);

    // --- Output ---
    final speedKmh = smoothedMps * 3.6;

    _controller.add(SpeedUpdate(
      speedKmh: speedKmh,
      activity: _currentActivity.name,
      gpsSpeedMps: position.speed >= 0 ? position.speed : null,
      calculatedSpeedMps: calculatedSpeedMps,
      selectedSource: selectedSource,
      timestamp: now,
    ));
  }

  /// Returns GPS speed if valid (>0 and <200 km/h). Negative/invalid → null.
  double? _getValidGpsSpeed(double speed) {
    if (speed < 0) return null;
    if (speed < _minValidGpsSpeedMps) return null; // Noise floor.
    if (speed > _maxValidGpsSpeedMps) return null; // Unrealistic.
    return speed;
  }

  /// Apply activity-based speed constraints.
  double _applyActivityValidation(double speedMps) {
    switch (_currentActivity) {
      case ActivityType.still:
      case ActivityType.tilting:
        // Force 0 when still; ignore GPS drift.
        return 0;
      case ActivityType.walking:
      case ActivityType.onFoot:
      case ActivityType.running:
        // Cap at human limits (~16 km/h).
        return speedMps.clamp(0, _humanMaxSpeedMps);
      case ActivityType.inVehicle:
      case ActivityType.onBicycle:
        // Allow higher speeds.
        return speedMps.clamp(0, _maxValidGpsSpeedMps);
      case ActivityType.unknown:
      case ActivityType.invalid:
        return speedMps;
    }
  }

  /// Moving average of last N speed values.
  double _smoothSpeed(double newSpeedMps) {
    _speedBufferMps.add(newSpeedMps);
    if (_speedBufferMps.length > _smoothWindowSize) {
      _speedBufferMps.removeAt(0);
    }
    if (_speedBufferMps.isEmpty) return 0;
    final sum = _speedBufferMps.reduce((a, b) => a + b);
    return sum / _speedBufferMps.length;
  }

  /// Current activity name (for display).
  String get currentActivityName => _currentActivity.name;
}
