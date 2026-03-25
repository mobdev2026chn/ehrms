import 'dart:async';
import 'package:activity_recognition_flutter/activity_recognition_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart' as gl;
import 'package:hrms/config/constants.dart';

class _LocationSample {
  final double lat;
  final double lng;
  final DateTime time;
  final double accuracyM;

  _LocationSample(this.lat, this.lng, this.time, this.accuracyM);
}

const String kMovementDrive = 'driving';
const String kMovementWalk = 'walking';
const String kMovementStop = 'stop';

const double kMaxAccuracyM = 50.0;
const double kSameLocationDistanceM = 10.0;
const double kSpeedWalkEnterKmh = 1.2;
const double kSpeedWalkExitKmh = 0.8;
const double kSpeedDriveEnterKmh = 15.0;
const double kSpeedDriveExitKmh = 10.0;
const double kMinWalkDistanceM = 3.0;
const double kMinDriveDistanceM = 12.0;
const double kSensorWalkSupportKmh = 1.5;
const double kSensorDriveSupportKmh = 18.0;
const double kMinCalculatedSupportForSensorWalkKmh = 0.4;
const double kMinCalculatedSupportForSensorDriveKmh = 4.0;
const double kStrongStopDistanceM = 1.5;
const double kStrongStopSpeedKmh = 0.5;
const double kMinSampleIntervalSeconds = 1.0;
const Duration kMovementHoldDuration = Duration(seconds: 5);
const int kLocationWindowSize = 5;
const int kMinActivityConfidence = 70;
const int kConsecutiveActivityRequired = 2;

/// Final production logic:
/// 1. Ignore low quality GPS fixes (> 50m accuracy) for movement changes.
/// 2. Treat movement under 10m as the same location.
/// 3. Speed > 15 km/h => driving, > 1.2 km/h => walking, else stop.
/// 4. Only switch movement type after the condition is held for at least 5s.
class MovementClassificationService {
  static final MovementClassificationService _instance =
      MovementClassificationService._internal();
  factory MovementClassificationService() => _instance;

  MovementClassificationService._internal();

  final List<_LocationSample> _locationWindow = [];
  static const int _maxSamples = kLocationWindowSize;

  ActivityType? _lastActivityType;
  int _lastActivityConsecutive = 0;
  String? _activitySuggestedMovement;

  String _currentMovementType = kMovementStop;
  String? _pendingMovementType;
  DateTime? _pendingMovementSince;
  int _consecutiveLowSpeedCount = 0;

  bool _activityAvailable = false;
  StreamSubscription<ActivityEvent>? _activitySubscription;

  void _logDetection({
    required String stage,
    required double lat,
    required double lng,
    required DateTime time,
    double? accuracyM,
    double? distanceM,
    double? speedKmh,
    double? sensorSpeedKmh,
    String? candidate,
    String? result,
  }) {
    if (!kDebugMode || !AppConstants.logTrackingsToConsole) return;
    debugPrint(
      '[MovementDetection] stage=$stage '
      'time=${time.toIso8601String()} '
      'lat=${lat.toStringAsFixed(6)} lng=${lng.toStringAsFixed(6)} '
      'acc=${accuracyM?.toStringAsFixed(1) ?? "—"}m '
      'distance=${distanceM?.toStringAsFixed(1) ?? "—"}m '
      'speed=${speedKmh?.toStringAsFixed(2) ?? "—"}kmh '
      'sensor=${sensorSpeedKmh?.toStringAsFixed(2) ?? "—"}kmh '
      'activity=${_activitySuggestedMovement ?? "—"} '
      'candidate=${candidate ?? "—"} '
      'pending=${_pendingMovementType ?? "—"} '
      'current=$_currentMovementType '
      'result=${result ?? _currentMovementType}',
    );
  }

  Future<void> start() async {
    _locationWindow.clear();
    _lastActivityType = null;
    _lastActivityConsecutive = 0;
    _activitySuggestedMovement = null;
    _currentMovementType = kMovementStop;
    _pendingMovementType = null;
    _pendingMovementSince = null;
    _consecutiveLowSpeedCount = 0;

    if (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS) {
      return;
    }

    try {
      final available = await ActivityRecognition().isAvailable();
      if (available) {
        _activityAvailable = true;
        await _activitySubscription?.cancel();
        _activitySubscription = ActivityRecognition()
            .activityStream(runForegroundService: false)
            .listen(_onActivityEvent);
      }
    } catch (_) {
      _activityAvailable = false;
    }
  }

  void _onActivityEvent(ActivityEvent event) {
    if (kDebugMode && AppConstants.logTrackingsToConsole) {
      debugPrint(
        '[MovementDetection] activity_event '
        'time=${DateTime.now().toIso8601String()} '
        'type=${event.type.name} confidence=${event.confidence}',
      );
    }

    if (event.type == ActivityType.unknown ||
        event.type == ActivityType.invalid ||
        event.confidence < kMinActivityConfidence) {
      _lastActivityType = null;
      _lastActivityConsecutive = 0;
      _activitySuggestedMovement = null;
      return;
    }

    if (event.type == _lastActivityType) {
      _lastActivityConsecutive++;
    } else {
      _lastActivityType = event.type;
      _lastActivityConsecutive = 1;
    }

    if (_lastActivityConsecutive >= kConsecutiveActivityRequired) {
      _activitySuggestedMovement = _activityToMovement(event.type);
    } else {
      _activitySuggestedMovement = null;
    }
  }

  static String? _activityToMovement(ActivityType type) {
    switch (type) {
      case ActivityType.inVehicle:
      case ActivityType.onBicycle:
        return kMovementDrive;
      case ActivityType.walking:
      case ActivityType.onFoot:
      case ActivityType.running:
        return kMovementWalk;
      case ActivityType.still:
      case ActivityType.tilting:
        return kMovementStop;
      default:
        return null;
    }
  }

  Future<void> stop() async {
    await _activitySubscription?.cancel();
    _activitySubscription = null;
    _activityAvailable = false;
  }

  String addLocationAndClassify({
    required double lat,
    required double lng,
    required DateTime time,
    double? accuracyM,
    bool inBackground = false,
  }) {
    final accuracy = accuracyM ?? 999.0;
    if (accuracy > kMaxAccuracyM) {
      _logDetection(
        stage: 'ignored_accuracy',
        lat: lat,
        lng: lng,
        time: time,
        accuracyM: accuracy,
        result: _currentMovementType,
      );
      return _currentMovementType;
    }

    final previous = _locationWindow.isNotEmpty ? _locationWindow.last : null;
    final current = _LocationSample(lat, lng, time, accuracy);
    _locationWindow.add(current);
    if (_locationWindow.length > _maxSamples) {
      _locationWindow.removeAt(0);
    }

    if (previous == null) {
      _clearPendingMovement();
      _updateConsecutiveStopCount(_currentMovementType);
      _logDetection(
        stage: 'first_accurate_sample',
        lat: lat,
        lng: lng,
        time: time,
        accuracyM: accuracy,
        result: _currentMovementType,
      );
      return _currentMovementType;
    }

    final elapsedSeconds =
        current.time.difference(previous.time).inMilliseconds / 1000.0;
    if (elapsedSeconds <= 0) {
      _locationWindow.removeLast();
      _logDetection(
        stage: 'invalid_elapsed',
        lat: lat,
        lng: lng,
        time: time,
        accuracyM: accuracy,
        result: _currentMovementType,
      );
      return _currentMovementType;
    }
    if (elapsedSeconds < kMinSampleIntervalSeconds) {
      _locationWindow.removeLast();
      _logDetection(
        stage: 'ignored_short_interval',
        lat: lat,
        lng: lng,
        time: time,
        accuracyM: accuracy,
        result: _currentMovementType,
      );
      return _currentMovementType;
    }

    final distanceM = gl.Geolocator.distanceBetween(
      previous.lat,
      previous.lng,
      current.lat,
      current.lng,
    );
    final speedKmh = speedKmhFromDistance(
      distanceM: distanceM,
      elapsedSeconds: elapsedSeconds,
    );
    var candidate = _resolveCandidateFromWindow(
      distanceM: distanceM,
      elapsedSeconds: elapsedSeconds,
      current: current,
    );
    final isStrongStopEvidence =
        distanceM <= kStrongStopDistanceM && speedKmh <= kStrongStopSpeedKmh;
    if (isStrongStopEvidence) {
      candidate = kMovementStop;
    }
    final result = isStrongStopEvidence && _currentMovementType != kMovementStop
        ? _forceStop()
        : _resolveMovementWithHold(
            candidate: candidate,
            now: current.time,
            evidenceStart: previous.time,
          );

    _updateConsecutiveStopCount(result);
    _logDetection(
      stage: result == _currentMovementType ? 'classified' : 'pending',
      lat: lat,
      lng: lng,
      time: time,
      accuracyM: accuracy,
      distanceM: distanceM,
      speedKmh: speedKmh,
      candidate: candidate,
      result: result,
    );
    return result;
  }

  String classifyFromPosition(gl.Position position, {bool inBackground = false}) {
    return addLocationAndClassify(
      lat: position.latitude,
      lng: position.longitude,
      time: DateTime.now(),
      accuracyM: position.accuracy,
      inBackground: inBackground,
    );
  }

  String _resolveMovementWithHold({
    required String candidate,
    required DateTime now,
    required DateTime evidenceStart,
  }) {
    if (candidate == _currentMovementType) {
      _clearPendingMovement();
      return _currentMovementType;
    }

    if (_pendingMovementType != candidate) {
      _pendingMovementType = candidate;
      _pendingMovementSince = evidenceStart;
      if (now.difference(evidenceStart) >= kMovementHoldDuration) {
        _currentMovementType = candidate;
        _clearPendingMovement();
      }
      return _currentMovementType;
    }

    final holdSince = _pendingMovementSince;
    if (holdSince == null || evidenceStart.isBefore(holdSince)) {
      _pendingMovementSince = evidenceStart;
    }

    if (now.difference(_pendingMovementSince!) >= kMovementHoldDuration) {
      _currentMovementType = candidate;
      _clearPendingMovement();
    }

    return _currentMovementType;
  }

  void _clearPendingMovement() {
    _pendingMovementType = null;
    _pendingMovementSince = null;
  }

  String _forceStop() {
    _currentMovementType = kMovementStop;
    _clearPendingMovement();
    return _currentMovementType;
  }

  void _updateConsecutiveStopCount(String movementType) {
    if (movementType == kMovementStop) {
      _consecutiveLowSpeedCount++;
    } else {
      _consecutiveLowSpeedCount = 0;
    }
  }

  static double speedKmhFromDistance({
    required double distanceM,
    required double elapsedSeconds,
  }) {
    if (!distanceM.isFinite || !elapsedSeconds.isFinite || elapsedSeconds <= 0) {
      return 0.0;
    }
    return (distanceM / elapsedSeconds) * 3.6;
  }

  static String classifyFromDistanceAndDuration({
    required double distanceM,
    required double elapsedSeconds,
    String lastMovementType = kMovementStop,
    double? sensorSpeedKmh,
  }) {
    return classifyFromTrackingSignals(
      distanceM: distanceM,
      elapsedSeconds: elapsedSeconds,
      lastMovementType: lastMovementType,
      sensorSpeedKmh: sensorSpeedKmh,
    );
  }

  static String classifyFromSpeedOnly({
    required double avgSpeedKmh,
    required String lastMovementType,
    double? sensorSpeedKmh,
    bool inBackground = false,
    int consecutiveLowSpeed = 0,
  }) {
    if (!avgSpeedKmh.isFinite || avgSpeedKmh < 0) return lastMovementType;
    final effectiveSpeedKmh = _effectiveSpeedKmh(
      calculatedSpeedKmh: avgSpeedKmh,
      sensorSpeedKmh: sensorSpeedKmh,
    );
    if ((lastMovementType == kMovementDrive &&
            effectiveSpeedKmh >= kSpeedDriveExitKmh) ||
        effectiveSpeedKmh >= kSpeedDriveEnterKmh) {
      return kMovementDrive;
    }
    if ((lastMovementType == kMovementWalk &&
            effectiveSpeedKmh >= kSpeedWalkExitKmh) ||
        effectiveSpeedKmh >= kSpeedWalkEnterKmh) {
      return kMovementWalk;
    }
    return kMovementStop;
  }

  String _resolveCandidateFromWindow({
    required double distanceM,
    required double elapsedSeconds,
    required _LocationSample current,
  }) {
    final pairCandidate = classifyFromTrackingSignals(
      distanceM: distanceM,
      elapsedSeconds: elapsedSeconds,
      lastMovementType: _currentMovementType,
    );
    if (pairCandidate == kMovementDrive) {
      return pairCandidate;
    }

    final windowStats = _windowMovementStats(current);
    if (windowStats != null) {
      return classifyFromTrackingSignals(
        distanceM: windowStats.distanceM,
        elapsedSeconds: windowStats.elapsedSeconds,
        lastMovementType: _currentMovementType,
      );
    }

    return pairCandidate;
  }

  ({double distanceM, double elapsedSeconds, double speedKmh})?
  _windowMovementStats(_LocationSample current) {
    if (_locationWindow.length < 3) return null;
    final first = _locationWindow.first;
    final elapsedSeconds =
        current.time.difference(first.time).inMilliseconds / 1000.0;
    if (elapsedSeconds <= 0) return null;

    double totalDistanceM = 0.0;
    for (var i = 1; i < _locationWindow.length; i++) {
      final previous = _locationWindow[i - 1];
      final next = _locationWindow[i];
      totalDistanceM += gl.Geolocator.distanceBetween(
        previous.lat,
        previous.lng,
        next.lat,
        next.lng,
      );
    }

    return (
      distanceM: totalDistanceM,
      elapsedSeconds: elapsedSeconds,
      speedKmh: speedKmhFromDistance(
        distanceM: totalDistanceM,
        elapsedSeconds: elapsedSeconds,
      ),
    );
  }

  static String classifyFromInstantSpeed({
    required double speedKmh,
    required String lastMovementType,
    bool inBackground = false,
    int consecutiveLowSpeed = 0,
  }) {
    if (!speedKmh.isFinite || speedKmh < 0) return lastMovementType;
    return classifyFromSpeedOnly(
      avgSpeedKmh: speedKmh,
      lastMovementType: lastMovementType,
    );
  }

  static String classifyFromTrackingSignals({
    required double distanceM,
    required double elapsedSeconds,
    required String lastMovementType,
    double? sensorSpeedKmh,
  }) {
    final calculatedSpeedKmh = speedKmhFromDistance(
      distanceM: distanceM,
      elapsedSeconds: elapsedSeconds,
    );
    final sanitizedSensorSpeedKmh = _sanitizeSensorSpeedKmh(sensorSpeedKmh);

    final driveSupportedByCalculated =
        calculatedSpeedKmh >= kSpeedDriveEnterKmh &&
        distanceM >= kMinDriveDistanceM;
    final driveSupportedBySensor =
        sanitizedSensorSpeedKmh != null &&
        sanitizedSensorSpeedKmh >= kSensorDriveSupportKmh &&
        calculatedSpeedKmh >= kMinCalculatedSupportForSensorDriveKmh &&
        distanceM >= kMinDriveDistanceM;
    if ((lastMovementType == kMovementDrive &&
            distanceM >= kMinDriveDistanceM &&
            (calculatedSpeedKmh >= kSpeedDriveExitKmh ||
                (sanitizedSensorSpeedKmh != null &&
                    sanitizedSensorSpeedKmh >= kSpeedDriveExitKmh &&
                    calculatedSpeedKmh >=
                        kMinCalculatedSupportForSensorDriveKmh))) ||
        driveSupportedByCalculated ||
        driveSupportedBySensor) {
      return kMovementDrive;
    }

    final hasWalkDistance = distanceM >= kMinWalkDistanceM;
    final walkSupportedByCalculated =
        hasWalkDistance && calculatedSpeedKmh >= kSpeedWalkEnterKmh;
    final walkSupportedBySensor =
        hasWalkDistance &&
        sanitizedSensorSpeedKmh != null &&
        sanitizedSensorSpeedKmh >= kSensorWalkSupportKmh &&
        calculatedSpeedKmh >= kMinCalculatedSupportForSensorWalkKmh;
    if (hasWalkDistance &&
        ((lastMovementType == kMovementWalk &&
                (calculatedSpeedKmh >= kSpeedWalkExitKmh ||
                    (sanitizedSensorSpeedKmh != null &&
                        sanitizedSensorSpeedKmh >= kSpeedWalkExitKmh &&
                        calculatedSpeedKmh >=
                            kMinCalculatedSupportForSensorWalkKmh))) ||
            walkSupportedByCalculated ||
            walkSupportedBySensor)) {
      return kMovementWalk;
    }

    return kMovementStop;
  }

  static double? _sanitizeSensorSpeedKmh(double? sensorSpeedKmh) {
    if (sensorSpeedKmh == null ||
        !sensorSpeedKmh.isFinite ||
        sensorSpeedKmh <= 0) {
      return null;
    }
    return sensorSpeedKmh;
  }

  static double _effectiveSpeedKmh({
    required double calculatedSpeedKmh,
    double? sensorSpeedKmh,
  }) {
    final safeCalculated =
        calculatedSpeedKmh.isFinite && calculatedSpeedKmh > 0
            ? calculatedSpeedKmh
            : 0.0;
    final safeSensor = _sanitizeSensorSpeedKmh(sensorSpeedKmh) ?? 0.0;
    return safeCalculated > safeSensor ? safeCalculated : safeSensor;
  }

  static String _classifyBySpeedKmh(double speedKmh) {
    if (!speedKmh.isFinite || speedKmh <= kSpeedWalkEnterKmh) {
      return kMovementStop;
    }
    if (speedKmh > kSpeedDriveEnterKmh) {
      return kMovementDrive;
    }
    return kMovementWalk;
  }

  String get currentMovementType => _currentMovementType;
  int get consecutiveLowSpeedCount => _consecutiveLowSpeedCount;
}
