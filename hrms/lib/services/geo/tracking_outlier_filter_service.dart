import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart' as gl;
import 'package:hrms/config/constants.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'movement_classification_service.dart';

class TrackingOutlierFilterDecision {
  const TrackingOutlierFilterDecision({
    required this.shouldSkip,
    required this.movementType,
    required this.reason,
    this.distanceM,
    this.elapsedSeconds,
    this.speedKmh,
    this.sensorSpeedKmh,
    this.windowDistanceM,
    this.windowSpeedKmh,
  });

  final bool shouldSkip;
  final String movementType;
  final String reason;
  final double? distanceM;
  final double? elapsedSeconds;
  final double? speedKmh;
  final double? sensorSpeedKmh;
  final double? windowDistanceM;
  final double? windowSpeedKmh;
}

class _TrackingFilterRecord {
  const _TrackingFilterRecord({
    required this.lat,
    required this.lng,
    required this.timestamp,
    required this.movementType,
    this.accuracyM,
  });

  final double lat;
  final double lng;
  final DateTime timestamp;
  final String movementType;
  final double? accuracyM;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'lat': lat,
    'lng': lng,
    'timestamp': timestamp.toUtc().toIso8601String(),
    'movementType': movementType,
    if (accuracyM != null) 'accuracyM': accuracyM,
  };

  static _TrackingFilterRecord? fromJson(Map<String, dynamic> json) {
    final lat = (json['lat'] as num?)?.toDouble();
    final lng = (json['lng'] as num?)?.toDouble();
    final movementType = json['movementType'] as String?;
    final timestampRaw = json['timestamp'] as String?;
    if (lat == null ||
        lng == null ||
        movementType == null ||
        timestampRaw == null ||
        movementType.isEmpty) {
      return null;
    }

    try {
      return _TrackingFilterRecord(
        lat: lat,
        lng: lng,
        timestamp: DateTime.parse(timestampRaw).toUtc(),
        movementType: movementType,
        accuracyM: (json['accuracyM'] as num?)?.toDouble(),
      );
    } catch (_) {
      return null;
    }
  }
}

class _PendingMovementState {
  const _PendingMovementState({
    required this.movementType,
    required this.since,
  });

  final String movementType;
  final DateTime since;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'movementType': movementType,
    'since': since.toUtc().toIso8601String(),
  };

  static _PendingMovementState? fromJson(Map<String, dynamic> json) {
    final movementType = json['movementType'] as String?;
    final sinceRaw = json['since'] as String?;
    if (movementType == null || movementType.isEmpty || sinceRaw == null) {
      return null;
    }
    try {
      return _PendingMovementState(
        movementType: movementType,
        since: DateTime.parse(sinceRaw).toUtc(),
      );
    } catch (_) {
      return null;
    }
  }
}

class TrackingOutlierFilterService {
  static const String _prefsPrefix = 'tracking_outlier_history_';
  static const String _pendingPrefix = 'tracking_outlier_pending_';
  static const int _maxHistoryRecords = 2;
  static const double _maxAccuracyM = 50.0;
  static const double _lowMovementDistanceM = 10.0;
  static const double _lowMovementSpeedKmh = 1.0;
  static const double _suddenSpikeDistanceM = 8.0;
  static const double _suddenSpikeSpeedKmh = 1.2;

  static final Map<String, List<_TrackingFilterRecord>> _memoryHistory =
      <String, List<_TrackingFilterRecord>>{};
  static final Map<String, _PendingMovementState?> _memoryPending =
      <String, _PendingMovementState?>{};

  static const String presenceScope = 'presence';

  static String taskScope(String taskId) => 'task:$taskId';

  static Future<TrackingOutlierFilterDecision> evaluate({
    required String scope,
    required double lat,
    required double lng,
    required DateTime timestamp,
    required String movementType,
    double? accuracyM,
    double? sensorSpeedMps,
  }) async {
    final normalizedMovement = _normalizeMovement(movementType);
    final history = await _loadHistory(scope);
    final last = history.isNotEmpty ? history.last : null;
    final previous = history.length >= 2 ? history[history.length - 2] : null;

    double? distanceM;
    double? elapsedSeconds;
    double? speedKmh;
    final sensorSpeedKmh =
        (sensorSpeedMps != null && sensorSpeedMps.isFinite && sensorSpeedMps >= 0)
            ? sensorSpeedMps * 3.6
            : null;
    if (last != null) {
      distanceM = gl.Geolocator.distanceBetween(last.lat, last.lng, lat, lng);
      elapsedSeconds =
          timestamp.difference(last.timestamp).inMilliseconds / 1000.0;
      if (elapsedSeconds > 0) {
        speedKmh = MovementClassificationService.speedKmhFromDistance(
          distanceM: distanceM,
          elapsedSeconds: elapsedSeconds,
        );
      }
    }
    final effectiveSpeedKmh = _effectiveSpeedKmh(
      calculatedSpeedKmh: speedKmh,
      sensorSpeedKmh: sensorSpeedKmh,
    );

    if (accuracyM != null && accuracyM > _maxAccuracyM) {
      _logDecision(
        scope: scope,
        lat: lat,
        lng: lng,
        accuracyM: accuracyM,
        movementType: normalizedMovement,
        distanceM: distanceM,
        elapsedSeconds: elapsedSeconds,
        speedKmh: speedKmh,
        sensorSpeedKmh: sensorSpeedKmh,
        decision: 'skip',
        reason: 'ignored_accuracy',
      );
      return TrackingOutlierFilterDecision(
        shouldSkip: true,
        movementType: normalizedMovement,
        reason: 'ignored_accuracy',
        distanceM: distanceM,
        elapsedSeconds: elapsedSeconds,
        speedKmh: speedKmh,
        sensorSpeedKmh: sensorSpeedKmh,
      );
    }

    var resolvedMovement = normalizedMovement;
    var reason = 'accepted';

    if (last != null &&
        distanceM != null &&
        elapsedSeconds != null &&
        elapsedSeconds > 0 &&
        speedKmh != null) {
      if (resolvedMovement == kMovementStop &&
          distanceM < _lowMovementDistanceM &&
          effectiveSpeedKmh < _lowMovementSpeedKmh) {
        resolvedMovement = kMovementStop;
        reason = 'low_movement_stop';
      }

      if (resolvedMovement == kMovementWalk &&
          previous != null &&
          previous.movementType == kMovementStop &&
          last.movementType == kMovementStop &&
          distanceM < _suddenSpikeDistanceM &&
          effectiveSpeedKmh < _suddenSpikeSpeedKmh) {
        _logDecision(
          scope: scope,
          lat: lat,
          lng: lng,
          accuracyM: accuracyM,
          movementType: normalizedMovement,
          correctedMovementType: kMovementStop,
          distanceM: distanceM,
          elapsedSeconds: elapsedSeconds,
          speedKmh: speedKmh,
          sensorSpeedKmh: sensorSpeedKmh,
          decision: 'skip',
          reason: 'sudden_spike_between_stops',
        );
        return TrackingOutlierFilterDecision(
          shouldSkip: true,
          movementType: kMovementStop,
          reason: 'sudden_spike_between_stops',
          distanceM: distanceM,
          elapsedSeconds: elapsedSeconds,
          speedKmh: speedKmh,
          sensorSpeedKmh: sensorSpeedKmh,
        );
      }
    }

    if (reason != 'accepted') {
      _logDecision(
        scope: scope,
        lat: lat,
        lng: lng,
        accuracyM: accuracyM,
        movementType: normalizedMovement,
        correctedMovementType: resolvedMovement,
        distanceM: distanceM,
        elapsedSeconds: elapsedSeconds,
        speedKmh: speedKmh,
        sensorSpeedKmh: sensorSpeedKmh,
        decision: 'send',
        reason: reason,
      );
    }

    return TrackingOutlierFilterDecision(
      shouldSkip: false,
      movementType: resolvedMovement,
      reason: reason,
      distanceM: distanceM,
      elapsedSeconds: elapsedSeconds,
      speedKmh: speedKmh,
      sensorSpeedKmh: sensorSpeedKmh,
    );
  }

  static Future<void> rememberValidRecord({
    required String scope,
    required double lat,
    required double lng,
    required DateTime timestamp,
    required String movementType,
    double? accuracyM,
  }) async {
    final history = await _loadHistory(scope);
    history.add(
      _TrackingFilterRecord(
        lat: lat,
        lng: lng,
        timestamp: timestamp.toUtc(),
        movementType: _normalizeMovement(movementType),
        accuracyM: accuracyM,
      ),
    );
    while (history.length > _maxHistoryRecords) {
      history.removeAt(0);
    }
    _memoryHistory[scope] = history;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '$_prefsPrefix$scope',
      jsonEncode(history.map((item) => item.toJson()).toList()),
    );
  }

  static Future<void> clearScope(String scope) async {
    _memoryHistory.remove(scope);
    _memoryPending.remove(scope);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_prefsPrefix$scope');
    await prefs.remove('$_pendingPrefix$scope');
  }

  static Future<List<_TrackingFilterRecord>> _loadHistory(String scope) async {
    final cached = _memoryHistory[scope];
    if (cached != null) return List<_TrackingFilterRecord>.from(cached);

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_prefsPrefix$scope');
    if (raw == null || raw.isEmpty) {
      final empty = <_TrackingFilterRecord>[];
      _memoryHistory[scope] = empty;
      return List<_TrackingFilterRecord>.from(empty);
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        _memoryHistory[scope] = <_TrackingFilterRecord>[];
        return <_TrackingFilterRecord>[];
      }
      final history = decoded
          .whereType<Map>()
          .map(
            (item) => _TrackingFilterRecord.fromJson(
              Map<String, dynamic>.from(
                item.map((key, value) => MapEntry(key.toString(), value)),
              ),
            ),
          )
          .whereType<_TrackingFilterRecord>()
          .toList();
      while (history.length > _maxHistoryRecords) {
        history.removeAt(0);
      }
      _memoryHistory[scope] = history;
      return List<_TrackingFilterRecord>.from(history);
    } catch (_) {
      _memoryHistory[scope] = <_TrackingFilterRecord>[];
      return <_TrackingFilterRecord>[];
    }
  }

  static Future<_PendingMovementState?> _loadPending(String scope) async {
    if (_memoryPending.containsKey(scope)) {
      return _memoryPending[scope];
    }

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_pendingPrefix$scope');
    if (raw == null || raw.isEmpty) {
      _memoryPending[scope] = null;
      return null;
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        _memoryPending[scope] = null;
        return null;
      }
      final pending = _PendingMovementState.fromJson(
        Map<String, dynamic>.from(
          decoded.map((key, value) => MapEntry(key.toString(), value)),
        ),
      );
      _memoryPending[scope] = pending;
      return pending;
    } catch (_) {
      _memoryPending[scope] = null;
      return null;
    }
  }

  static Future<void> _savePending(
    String scope,
    _PendingMovementState? pending,
  ) async {
    _memoryPending[scope] = pending;
    final prefs = await SharedPreferences.getInstance();
    if (pending == null) {
      await prefs.remove('$_pendingPrefix$scope');
      return;
    }
    await prefs.setString(
      '$_pendingPrefix$scope',
      jsonEncode(pending.toJson()),
    );
  }

  static double _effectiveSpeedKmh({
    double? calculatedSpeedKmh,
    double? sensorSpeedKmh,
  }) {
    final safeCalculated =
        calculatedSpeedKmh != null &&
                calculatedSpeedKmh.isFinite &&
                calculatedSpeedKmh > 0
            ? calculatedSpeedKmh
            : 0.0;
    final safeSensor =
        sensorSpeedKmh != null && sensorSpeedKmh.isFinite && sensorSpeedKmh > 0
            ? sensorSpeedKmh
            : 0.0;
    return safeCalculated > safeSensor ? safeCalculated : safeSensor;
  }

  static String _normalizeMovement(String movementType) {
    if (movementType == kMovementDrive ||
        movementType == kMovementWalk ||
        movementType == kMovementStop) {
      return movementType;
    }
    return kMovementStop;
  }

  static void _logDecision({
    required String scope,
    required double lat,
    required double lng,
    required String movementType,
    required String decision,
    required String reason,
    String? correctedMovementType,
    double? accuracyM,
    double? distanceM,
    double? elapsedSeconds,
    double? speedKmh,
    double? sensorSpeedKmh,
  }) {
    if (!kDebugMode || !AppConstants.logTrackingsToConsole) return;
    debugPrint(
      '[TrackingOutlierFilter] '
      'scope=$scope '
      'lat=${lat.toStringAsFixed(6)} lng=${lng.toStringAsFixed(6)} '
      'acc=${accuracyM?.toStringAsFixed(1) ?? "—"}m '
      'distance=${distanceM?.toStringAsFixed(2) ?? "—"}m '
      'elapsed=${elapsedSeconds?.toStringAsFixed(1) ?? "—"}s '
      'speed=${speedKmh?.toStringAsFixed(2) ?? "—"}kmh '
      'sensor=${sensorSpeedKmh?.toStringAsFixed(2) ?? "—"}kmh '
      'movement=$movementType corrected=${correctedMovementType ?? movementType} '
      'decision=$decision reason=$reason',
    );
  }
}
