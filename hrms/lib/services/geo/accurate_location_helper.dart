import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// Best-effort high-accuracy GPS for the **same** lat/lng sent to the API.
///
/// 1. [LocationAccuracy.bestForNavigation] with Android/iOS-tuned settings.
/// 2. Samples the position stream (faster updates on Android via [intervalDuration]).
/// 3. If several fixes cluster tightly and speed is low, returns a **weighted mean**
///    (1/σ²) to reduce jitter; otherwise returns the single best accuracy reading.
Future<Position> getPositionForTrackings({
  Duration primaryTimeout = const Duration(seconds: 32),
  Duration sampleWindow = const Duration(seconds: 18),
  double stopEarlyWhenAccuracyMeters = 10,
  int maxSamples = 24,
}) async {
  if (!await Geolocator.isLocationServiceEnabled()) {
    throw Exception('Location services disabled');
  }

  Position initial;
  try {
    initial = await Geolocator.getCurrentPosition(
      locationSettings: _primarySettings(primaryTimeout),
    );
  } catch (_) {
    initial = await Geolocator.getCurrentPosition(
      locationSettings: _fallbackSettings(primaryTimeout),
    );
  }

  final samples = <Position>[initial];
  StreamSubscription<Position>? sub;

  try {
    final better = Completer<void>();
    sub = Geolocator.getPositionStream(
      locationSettings: _streamSettings(),
    ).listen((p) {
      final a = p.accuracy;
      if (!a.isFinite || a <= 0 || a > 120) return;
      samples.add(p);
      if (samples.length > maxSamples) {
        samples.removeAt(0);
      }
      if (a <= stopEarlyWhenAccuracyMeters && !better.isCompleted) {
        better.complete();
      }
    });

    await Future.any<void>([
      better.future,
      Future<void>.delayed(sampleWindow),
    ]);
  } catch (_) {
    // use samples so far
  } finally {
    await sub?.cancel();
  }

  final usable = samples
      .where((p) => p.accuracy.isFinite && p.accuracy > 0 && p.accuracy <= 55)
      .toList();
  if (usable.length < 3) {
    return _bestByAccuracy(samples.isEmpty ? [initial] : samples);
  }

  if (_isStationaryCluster(usable)) {
    return _weightedMeanPosition(usable);
  }

  return _bestByAccuracy(usable);
}

/// Slightly faster sampling for dashboard / check-in UI (still uses navigation
/// accuracy + optional weighted mean when stationary).
Future<Position> getAccuratePositionForUi() => getPositionForTrackings(
      primaryTimeout: const Duration(seconds: 26),
      sampleWindow: const Duration(seconds: 12),
      stopEarlyWhenAccuracyMeters: 12,
      maxSamples: 18,
    );

/// Attendance/check-in needs a responsive fix more than a heavily sampled one.
Future<Position> getQuickPositionForUi() => getPositionForTrackings(
      primaryTimeout: const Duration(seconds: 10),
      sampleWindow: const Duration(seconds: 4),
      stopEarlyWhenAccuracyMeters: 15,
      maxSamples: 8,
    );

LocationSettings _primarySettings(Duration timeout) {
  if (kIsWeb) {
    return LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      timeLimit: timeout,
    );
  }
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
      return AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        timeLimit: timeout,
      );
    case TargetPlatform.iOS:
      return AppleSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        timeLimit: timeout,
        activityType: ActivityType.otherNavigation,
        pauseLocationUpdatesAutomatically: false,
      );
    default:
      return LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        timeLimit: timeout,
      );
  }
}

LocationSettings _fallbackSettings(Duration timeout) {
  if (kIsWeb) {
    return LocationSettings(
      accuracy: LocationAccuracy.high,
      timeLimit: timeout,
    );
  }
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: timeout,
      );
    case TargetPlatform.iOS:
      return AppleSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: timeout,
        activityType: ActivityType.fitness,
      );
    default:
      return LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: timeout,
      );
  }
}

LocationSettings _streamSettings() {
  if (kIsWeb) {
    return const LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 0,
    );
  }
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
      return AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
        intervalDuration: const Duration(milliseconds: 400),
      );
    case TargetPlatform.iOS:
      return AppleSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
        activityType: ActivityType.otherNavigation,
        pauseLocationUpdatesAutomatically: false,
      );
    default:
      return const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
      );
  }
}

Position _bestByAccuracy(List<Position> list) {
  return list.reduce(
    (a, b) => a.accuracy <= b.accuracy ? a : b,
  );
}

/// Tight cluster + low speed → safe to average (reduces multipath / drift).
bool _isStationaryCluster(List<Position> usable) {
  if (usable.length < 3) return false;
  for (final p in usable) {
    final s = p.speed;
    if (s.isFinite && s > 1.8) return false;
  }
  double maxSpread = 0;
  for (var i = 0; i < usable.length; i++) {
    for (var j = i + 1; j < usable.length; j++) {
      final d = Geolocator.distanceBetween(
        usable[i].latitude,
        usable[i].longitude,
        usable[j].latitude,
        usable[j].longitude,
      );
      if (d > maxSpread) maxSpread = d;
    }
  }
  return maxSpread <= 30;
}

Position _weightedMeanPosition(List<Position> usable) {
  final ref = _bestByAccuracy(usable);
  double wSum = 0;
  double latW = 0;
  double lngW = 0;
  const floorM = 2.5;
  for (final p in usable) {
    final sigma = math.max(p.accuracy, floorM);
    final w = 1.0 / (sigma * sigma);
    wSum += w;
    latW += p.latitude * w;
    lngW += p.longitude * w;
  }
  final minAcc = usable.map((p) => p.accuracy).reduce(math.min);
  return Position(
    latitude: latW / wSum,
    longitude: lngW / wSum,
    timestamp: DateTime.now(),
    accuracy: minAcc.clamp(3, 100),
    altitude: ref.altitude,
    altitudeAccuracy: ref.altitudeAccuracy,
    heading: ref.heading,
    headingAccuracy: ref.headingAccuracy,
    speed: ref.speed,
    speedAccuracy: ref.speedAccuracy,
    floor: ref.floor,
    isMocked: ref.isMocked,
  );
}
