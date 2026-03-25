// presence_tracking_service.dart
// Staff location tracking based on attendance presence status.
// Stores a point every 1 minute in trackings (POST /tracking/presence/store) while checked in.
// Timer runs regardless of which screen is visible (singleton). When app is in background,
// the OS may pause the isolate so the timer does not fire; on resume we send one record and restart the timer.
// Failed periodic sends (e.g. offline) are queued locally and POSTed when the app opens again.

import 'dart:async';
import 'dart:convert';
import 'package:battery_plus/battery_plus.dart';
import 'package:background_location_tracker/background_location_tracker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart' as gl;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dio/dio.dart';
import 'package:hrms/config/constants.dart';
import 'package:hrms/services/geo/address_resolution_service.dart';
import 'package:hrms/services/geo/accurate_location_helper.dart';
import 'package:hrms/services/geo/live_tracking_service.dart';
import 'package:hrms/services/geo/movement_classification_service.dart';
import 'package:hrms/services/geo/tracking_outlier_filter_service.dart';
import 'api_client.dart';

/// SharedPref key: stores today's date when checked in (YYYY-MM-DD). Cleared on checkout.
const String _kPresenceTrackingDate = 'presence_tracking_date';
const String _kPresenceBackgroundEnabled = 'presence_background_enabled';
const String _kPresenceAppLifecycleState = 'presence_app_lifecycle_state';

const String _kPresencePendingQueue = 'presence_pending_queue';
const String _kPresenceLastSentLat = 'presence_last_sent_lat';
const String _kPresenceLastSentLng = 'presence_last_sent_lng';
const String _kPresenceLastSentTime = 'presence_last_sent_time';
const String _kPresenceLastBackgroundAttemptTime =
    'presence_last_background_attempt_time';
const String _kPresenceLastMovementType = 'presence_last_movement_type';
const String _kPresenceConsecutiveLowSpeed = 'presence_consecutive_low_speed';
const int _maxPendingPresence = 80;

enum _PresenceSendResult { sent, skipped, failed }

typedef _PresenceSendOutcome = ({
  _PresenceSendResult result,
  String movementType,
});

class PresenceTrackingService {
  static bool _looksLikeMissingPlugin(Object error) {
    return error is MissingPluginException ||
        error.toString().contains('No implementation found for method initialized');
  }

  static final PresenceTrackingService _instance =
      PresenceTrackingService._internal();
  factory PresenceTrackingService() => _instance;

  PresenceTrackingService._internal();

  final ApiClient _api = ApiClient();

  Timer? _trackingTimer;
  bool _isTracking = false;
  bool _taskInProgress = false;
  bool _sendingAppClosed = false;
  bool _periodicTickInProgress = false;

  /// Interval for inserting presence tracking into DB (trackings collection).
  /// Applied to both foreground timer and native Android background tracker.
  static const Duration trackingInterval = Duration(minutes: 1);
  static const double _duplicateLocationThresholdMeters = 10;

  static const double defaultOfficeRadiusMeters = 200;
  static const AndroidConfig _presenceBackgroundConfig = AndroidConfig(
    notificationIcon: 'explore',
    notificationBody: 'Attendance presence tracking active. Tap to open.',
    channelName: 'Presence Tracking',
    cancelTrackingActionText: 'Stop tracking',
    enableCancelTrackingAction: true,
    trackingInterval: trackingInterval,
    distanceFilterMeters: null,
  );

  Future<gl.Position> _capturePresencePosition() {
    // Use the same stabilized GPS sampling as attendance check-in so
    // the reverse-geocoded address comes from the same style of fix.
    return getAccuratePositionForUi();
  }

  Future<void> _setToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token != null) _api.setAuthToken(token);
  }

  Future<bool> _shouldSkipPresenceSend(
    double lat,
    double lng, {
    String logLabel = 'presence_store',
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final lastLat = prefs.getDouble(_kPresenceLastSentLat);
    final lastLng = prefs.getDouble(_kPresenceLastSentLng);
    if (lastLat == null || lastLng == null) return false;
    final distanceM = gl.Geolocator.distanceBetween(lastLat, lastLng, lat, lng);
    final shouldSkip = distanceM < _duplicateLocationThresholdMeters;
    if (shouldSkip && kDebugMode && AppConstants.logTrackingsToConsole) {
      debugPrint(
        '[Trackings] $logLabel duplicate_check '
        'lastLat=${lastLat.toStringAsFixed(6)} lastLng=${lastLng.toStringAsFixed(6)} '
        'currentLat=${lat.toStringAsFixed(6)} currentLng=${lng.toStringAsFixed(6)} '
        'distance=${distanceM.toStringAsFixed(2)}m '
        'threshold=${_duplicateLocationThresholdMeters.toStringAsFixed(1)}m '
        'decision=skip',
      );
    }
    return shouldSkip;
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

  Future<void> setTrackingAllowed() async {
    final prefs = await SharedPreferences.getInstance();
    final previousDate = prefs.getString(_kPresenceTrackingDate);
    final today = DateTime.now().toIso8601String().split('T')[0];
    await prefs.setString(_kPresenceTrackingDate, today);
    await prefs.setBool(_kPresenceBackgroundEnabled, true);
    await prefs.setString(_kPresenceAppLifecycleState, 'foreground');
    if (previousDate != today) {
      await TrackingOutlierFilterService.clearScope(
        TrackingOutlierFilterService.presenceScope,
      );
      await prefs.remove(_kPresenceLastSentLat);
      await prefs.remove(_kPresenceLastSentLng);
      await prefs.remove(_kPresenceLastSentTime);
      await prefs.remove(_kPresenceLastBackgroundAttemptTime);
      await prefs.remove(_kPresenceLastMovementType);
      await prefs.remove(_kPresenceConsecutiveLowSpeed);
    }
  }

  Future<void> clearTrackingAllowed() async {
    final prefs = await SharedPreferences.getInstance();
    await TrackingOutlierFilterService.clearScope(
      TrackingOutlierFilterService.presenceScope,
    );
    await prefs.remove(_kPresenceTrackingDate);
    await prefs.remove(_kPresenceBackgroundEnabled);
    await prefs.remove(_kPresenceAppLifecycleState);
    await prefs.remove(_kPresencePendingQueue);
    await prefs.remove(_kPresenceLastSentLat);
    await prefs.remove(_kPresenceLastSentLng);
    await prefs.remove(_kPresenceLastSentTime);
    await prefs.remove(_kPresenceLastBackgroundAttemptTime);
    await prefs.remove(_kPresenceLastMovementType);
    await prefs.remove(_kPresenceConsecutiveLowSpeed);
  }

  Future<void> markAppForeground() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPresenceAppLifecycleState, 'foreground');
  }

  Future<void> markAppBackground() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPresenceAppLifecycleState, 'background');
  }

  Future<void> markAppClosed() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPresenceAppLifecycleState, 'closed');
  }

  static Future<String> _getLifecycleAppStatusForBackgroundInsert() async {
    final prefs = await SharedPreferences.getInstance();
    final state = prefs.getString(_kPresenceAppLifecycleState);
    if (state == 'closed') return 'app_closed';
    if (state == 'foreground') return 'active';
    return 'app_background';
  }

  Future<String> _getAppStatusForCurrentLifecycle() async {
    final prefs = await SharedPreferences.getInstance();
    final state = prefs.getString(_kPresenceAppLifecycleState);
    if (state == 'closed') return 'app_closed';
    if (state == 'background') return 'app_background';
    return 'active';
  }

  static Future<bool> isBackgroundPresenceEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kPresenceBackgroundEnabled) == true;
  }

  Future<void> _ensureBackgroundPresenceTracking() async {
    if (_taskInProgress) return;
    if (!await isTrackingAllowed()) return;
    if (await LiveTrackingService().isActive()) return;
    try {
      await BackgroundLocationTrackerManager.startTracking(
        config: _presenceBackgroundConfig,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[PresenceTracking] background tracker start failed: $e');
      }
    }
  }

  Future<void> _stopBackgroundPresenceTrackingIfIdle() async {
    if (await LiveTrackingService().isActive()) return;
    if (await isTrackingAllowed()) return;
    try {
      bool isTracking = false;
      try {
        isTracking = await BackgroundLocationTrackerManager.isTracking();
      } catch (e) {
        if (_looksLikeMissingPlugin(e)) {
          isTracking = false;
        } else {
          rethrow;
        }
      }
      if (isTracking) {
        await BackgroundLocationTrackerManager.stopTracking();
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[PresenceTracking] background tracker stop failed: $e');
      }
    }
  }

  static Future<void> sendPresenceFromBackground(
    double lat,
    double lng, {
    int? batteryPercent,
    double? accuracyM,
    double? speedMps,
  }) async {
    if (await LiveTrackingService().isActive()) return;
    if (!await isBackgroundPresenceEnabled()) return;

    final self = PresenceTrackingService();
    if (!await self.isTrackingAllowed()) return;

    final prefs = await SharedPreferences.getInstance();
    final token = _sanitizeStoredToken(prefs.getString('token'));
    if (token == null || token.isEmpty) return;
    final lifecycleState = prefs.getString(_kPresenceAppLifecycleState);
    if (lifecycleState == 'foreground') {
      return;
    }

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final lastAttemptMs = prefs.getInt(_kPresenceLastBackgroundAttemptTime);
    if (lastAttemptMs != null &&
        lastAttemptMs > 0 &&
        (nowMs - lastAttemptMs) < trackingInterval.inMilliseconds) {
      return;
    }
    await prefs.setInt(_kPresenceLastBackgroundAttemptTime, nowMs);
    if (await self._shouldSkipPresenceSend(lat, lng, logLabel: 'presence_store_bg')) {
      if (kDebugMode && AppConstants.logTrackingsToConsole) {
        debugPrint(
          '[Trackings] presence_store_bg SKIP duplicate '
          'lat=${lat.toStringAsFixed(6)} lng=${lng.toStringAsFixed(6)}',
        );
      }
      return;
    }

    final baseUrl = AppConstants.baseUrl.replaceAll(RegExp(r'/$'), '');
    final uri = Uri.parse('$baseUrl/tracking/presence/store');
    final capturedAt = DateTime.now().toUtc();
    final body = <String, dynamic>{
      'lat': lat,
      'lng': lng,
      'status': 'active',
      'appStatus': await _getLifecycleAppStatusForBackgroundInsert(),
      'timestamp': capturedAt.toIso8601String(),
    };
    if (batteryPercent != null) body['batteryPercent'] = batteryPercent;
    if (accuracyM != null) body['accuracy'] = accuracyM;
    final movement = await _classifyBackgroundMovement(
      prefs,
      lat,
      lng,
      speedMps: speedMps,
      accuracyM: accuracyM,
    );
    final outlierDecision = await TrackingOutlierFilterService.evaluate(
      scope: TrackingOutlierFilterService.presenceScope,
      lat: lat,
      lng: lng,
      timestamp: capturedAt,
      movementType: movement.movementType,
      accuracyM: accuracyM,
      sensorSpeedMps: speedMps,
    );
    if (outlierDecision.shouldSkip) {
      if (kDebugMode && AppConstants.logTrackingsToConsole) {
        debugPrint(
          '[Trackings] presence_store_bg SKIP outlier '
          'reason=${outlierDecision.reason} '
          'distance=${outlierDecision.distanceM?.toStringAsFixed(2) ?? "—"}m '
          'speed=${outlierDecision.speedKmh?.toStringAsFixed(2) ?? "—"}kmh '
          'appStatus=${body['appStatus']}',
        );
      }
      return;
    }
    final resolvedMovementType = outlierDecision.movementType;
    final nextConsecutiveLowSpeed = resolvedMovementType == kMovementStop
        ? movement.consecutiveLowSpeed
        : 0;
    body['movementType'] = resolvedMovementType;

    try {
      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(body),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        if (kDebugMode && AppConstants.logTrackingsToConsole) {
          debugPrint(
            '[Trackings] presence_store_bg FAIL ${response.statusCode} '
            'lat=$lat lng=$lng status=${body['status']} '
            'appStatus=${body['appStatus']} movement=${body['movementType']} '
            'body=${response.body}',
          );
        }
      } else if (kDebugMode && AppConstants.logTrackingsToConsole) {
        debugPrint(
          '[Trackings] presence_store_bg OK '
          'lat=${lat.toStringAsFixed(6)} lng=${lng.toStringAsFixed(6)} '
          'status=${body['status']} appStatus=${body['appStatus']} '
          'movement=${body['movementType']}',
        );
      }
      if (response.statusCode >= 200 && response.statusCode < 300) {
        await self._persistPresenceMovementState(
          lat,
          lng,
          movementType: resolvedMovementType,
          consecutiveLowSpeed: nextConsecutiveLowSpeed,
          recordedAt: capturedAt,
        );
        await TrackingOutlierFilterService.rememberValidRecord(
          scope: TrackingOutlierFilterService.presenceScope,
          lat: lat,
          lng: lng,
          timestamp: capturedAt,
          movementType: resolvedMovementType,
          accuracyM: accuracyM,
        );
      }
    } catch (e) {
      if (kDebugMode && AppConstants.logTrackingsToConsole) {
        debugPrint(
          '[Trackings] presence_store_bg error status=${body['status']} '
          'appStatus=${body['appStatus']} movement=${body['movementType']}: $e',
        );
      }
    }
  }

  Future<bool> isTrackingAllowed() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_kPresenceTrackingDate);
    if (stored == null || stored.isEmpty) return false;

    final parts = stored.split('-');
    if (parts.length != 3) return false;
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (year == null || month == null || day == null) return false;

    // TESTING ONLY:
    // Keep presence tracking alive after midnight so overnight/background
    // tracking can be verified. Re-enable the block below after testing.
    //
    // final now = DateTime.now();
    // final endOfCheckInDay = DateTime(year, month, day, 23, 59, 59, 999);
    //
    // if (now.isAfter(endOfCheckInDay)) {
    //   await prefs.remove(_kPresenceTrackingDate);
    //   return false;
    // }
    return true;
  }

  /// Call when API / prefs show user is punched in today (e.g. after app restart or dashboard load).
  Future<void> ensureTrackingIfPunchedIn(bool isPunchedInToday) async {
    if (!isPunchedInToday) {
      await stopTracking();
      return;
    }
    await setTrackingAllowed();
    await _schedulePresenceSends();
  }

  Future<Map<String, dynamic>> getPresenceStatus() async {
    await _setToken();
    try {
      final response = await _api.dio.get<Map<String, dynamic>>(
        '/tracking/presence/status',
      );
      final data = response.data;
      if (data == null) return {'canTrack': false, 'reason': 'unknown'};
      final d = data['data'];
      if (d is! Map) return {'canTrack': false, 'reason': 'invalid_response'};
      return {
        'canTrack': d['canTrack'] == true,
        'reason': d['reason'] as String?,
        'branchGeofence': d['branchGeofence'] as Map<String, dynamic>?,
      };
    } catch (e) {
      return {'canTrack': false, 'reason': 'error'};
    }
  }

  Future<void> _persistPresenceMovementState(
    double lat,
    double lng, {
    required String movementType,
    required int consecutiveLowSpeed,
    DateTime? recordedAt,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kPresenceLastSentLat, lat);
    await prefs.setDouble(_kPresenceLastSentLng, lng);
    await prefs.setInt(
      _kPresenceLastSentTime,
      (recordedAt ?? DateTime.now()).millisecondsSinceEpoch,
    );
    await prefs.setString(_kPresenceLastMovementType, movementType);
    await prefs.setInt(_kPresenceConsecutiveLowSpeed, consecutiveLowSpeed);
  }

  Future<String> _classifyForegroundMovement(gl.Position position) async {
    final prefs = await SharedPreferences.getInstance();
    final lastMovement =
        prefs.getString(_kPresenceLastMovementType) ?? kMovementStop;
    final lastLat = prefs.getDouble(_kPresenceLastSentLat);
    final lastLng = prefs.getDouble(_kPresenceLastSentLng);
    final lastTimeMs = prefs.getInt(_kPresenceLastSentTime);
    final accuracyM = position.accuracy;

    if (accuracyM > kMaxAccuracyM) {
      if (kDebugMode && AppConstants.logTrackingsToConsole) {
        debugPrint(
          '[MovementDetection][foreground_guard] '
          'time=${DateTime.now().toIso8601String()} '
          'lat=${position.latitude.toStringAsFixed(6)} '
          'lng=${position.longitude.toStringAsFixed(6)} '
          'acc=${accuracyM.toStringAsFixed(1)}m '
          'result=$lastMovement reason=ignored_accuracy',
        );
      }
      return lastMovement;
    }

    if (lastLat == null || lastLng == null || lastTimeMs == null || lastTimeMs <= 0) {
      return MovementClassificationService().classifyFromPosition(position);
    }

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final elapsedSec = (nowMs - lastTimeMs) / 1000.0;
    if (elapsedSec < kMovementHoldDuration.inSeconds) {
      if (kDebugMode && AppConstants.logTrackingsToConsole) {
        debugPrint(
          '[MovementDetection][foreground_guard] '
          'time=${DateTime.now().toIso8601String()} '
          'lat=${position.latitude.toStringAsFixed(6)} '
          'lng=${position.longitude.toStringAsFixed(6)} '
          'acc=${accuracyM.toStringAsFixed(1)}m '
          'elapsed=${elapsedSec.toStringAsFixed(1)}s '
          'result=$lastMovement reason=hold_not_met',
        );
      }
      return lastMovement;
    }

    final distanceM = gl.Geolocator.distanceBetween(
      lastLat,
      lastLng,
      position.latitude,
      position.longitude,
    );
    final speedKmh = MovementClassificationService.speedKmhFromDistance(
      distanceM: distanceM,
      elapsedSeconds: elapsedSec,
    );
    final result = MovementClassificationService.classifyFromTrackingSignals(
      distanceM: distanceM,
      elapsedSeconds: elapsedSec,
      lastMovementType: lastMovement,
      sensorSpeedKmh:
          (position.speed.isFinite && position.speed >= 0)
              ? position.speed * 3.6
              : null,
    );

    if (kDebugMode && AppConstants.logTrackingsToConsole) {
      debugPrint(
        '[MovementDetection][foreground_guard] '
        'time=${DateTime.now().toIso8601String()} '
        'lat=${position.latitude.toStringAsFixed(6)} '
        'lng=${position.longitude.toStringAsFixed(6)} '
        'acc=${accuracyM.toStringAsFixed(1)}m '
        'distance=${distanceM.toStringAsFixed(1)}m '
        'speed=${speedKmh.toStringAsFixed(2)}kmh '
        'last=$lastMovement result=$result',
      );
    }

    return result;
  }

  static Future<({String movementType, int consecutiveLowSpeed})>
  _classifyBackgroundMovement(
    SharedPreferences prefs,
    double lat,
    double lng, {
    double? speedMps,
    double? accuracyM,
  }) async {
    final lastMovement =
        prefs.getString(_kPresenceLastMovementType) ?? kMovementStop;
    final consecutiveLow =
        prefs.getInt(_kPresenceConsecutiveLowSpeed) ?? 0;
    final lastLat = prefs.getDouble(_kPresenceLastSentLat);
    final lastLng = prefs.getDouble(_kPresenceLastSentLng);
    final lastTimeMs = prefs.getInt(_kPresenceLastSentTime);

    double distanceM = 0.0;
    double elapsedSec = 0.0;
    if (lastLat != null &&
        lastLng != null &&
        lastTimeMs != null &&
        lastTimeMs > 0) {
      distanceM = gl.Geolocator.distanceBetween(lastLat, lastLng, lat, lng);
      elapsedSec = (DateTime.now().millisecondsSinceEpoch - lastTimeMs) / 1000.0;
    }

    final speedKmhFromSensor =
        (speedMps != null && speedMps.isFinite && speedMps >= 0)
            ? speedMps * 3.6
            : 0.0;

    if (accuracyM != null && accuracyM > kMaxAccuracyM) {
      return (
        movementType: lastMovement,
        consecutiveLowSpeed:
            lastMovement == kMovementStop ? (consecutiveLow + 1) : 0,
      );
    }

    if (lastLat == null ||
        lastLng == null ||
        lastTimeMs == null ||
        lastTimeMs <= 0 ||
        elapsedSec < kMovementHoldDuration.inSeconds) {
      return (
        movementType: lastMovement,
        consecutiveLowSpeed:
            lastMovement == kMovementStop ? (consecutiveLow + 1) : 0,
      );
    }

    final speedKmh = MovementClassificationService.speedKmhFromDistance(
      distanceM: distanceM,
      elapsedSeconds: elapsedSec,
    );
    final movementType = MovementClassificationService.classifyFromTrackingSignals(
      distanceM: distanceM,
      elapsedSeconds: elapsedSec,
      lastMovementType: lastMovement,
      sensorSpeedKmh:
          (speedMps != null && speedMps.isFinite && speedMps >= 0)
              ? speedMps * 3.6
              : null,
    );
    final nextConsecutive =
        movementType == kMovementStop ? (consecutiveLow + 1) : 0;

    if (kDebugMode && AppConstants.logTrackingsToConsole) {
      debugPrint(
        '[MovementDetection][background] '
        'time=${DateTime.now().toIso8601String()} '
        'lat=${lat.toStringAsFixed(6)} lng=${lng.toStringAsFixed(6)} '
        'acc=${accuracyM?.toStringAsFixed(1) ?? "—"}m '
        'distance=${distanceM.toStringAsFixed(1)}m '
        'elapsed=${elapsedSec.toStringAsFixed(1)}s '
        'speed=${speedKmh.toStringAsFixed(2)}kmh '
        'sensor=${speedKmhFromSensor.toStringAsFixed(2)}kmh '
        'last=$lastMovement result=$movementType',
      );
    }

    return (
      movementType: movementType,
      consecutiveLowSpeed: nextConsecutive,
    );
  }

  Future<_PresenceSendOutcome> _sendPresence({
    required double lat,
    required double lng,
    required String presenceStatus,
    String? status,
    String? appStatus,
    String? movementType,
    double? accuracy,
    int? batteryPercent,
    String? address,
    String? fullAddress,
    String? city,
    String? area,
    String? pincode,
    DateTime? timestampUtc,
  }) async {
    await _setToken();
    final capturedAt = (timestampUtc ?? DateTime.now().toUtc()).toUtc();
    final outlierDecision = await TrackingOutlierFilterService.evaluate(
      scope: TrackingOutlierFilterService.presenceScope,
      lat: lat,
      lng: lng,
      timestamp: capturedAt,
      movementType: movementType ?? kMovementStop,
      accuracyM: accuracy,
      sensorSpeedMps: null,
    );
    if (outlierDecision.shouldSkip) {
      if (kDebugMode && AppConstants.logTrackingsToConsole) {
        debugPrint(
          '[Trackings] presence_store SKIP outlier '
          'presence=$presenceStatus reason=${outlierDecision.reason} '
          'distance=${outlierDecision.distanceM?.toStringAsFixed(2) ?? "—"}m '
          'speed=${outlierDecision.speedKmh?.toStringAsFixed(2) ?? "—"}kmh '
          'appStatus=${appStatus ?? "—"}',
        );
      }
      return (
        result: _PresenceSendResult.skipped,
        movementType: outlierDecision.movementType,
      );
    }
    final resolvedMovementType = outlierDecision.movementType;
    if (await _shouldSkipPresenceSend(lat, lng, logLabel: 'presence_store')) {
      if (kDebugMode && AppConstants.logTrackingsToConsole) {
        debugPrint(
          '[Trackings] presence_store SKIP duplicate '
          'lat=${lat.toStringAsFixed(6)} lng=${lng.toStringAsFixed(6)} '
          'presence=$presenceStatus',
        );
      }
      return (
        result: _PresenceSendResult.skipped,
        movementType: resolvedMovementType,
      );
    }
    try {
      final body = <String, dynamic>{
        'lat': lat,
        'lng': lng,
        'presenceStatus': presenceStatus,
        'timestamp': capturedAt.toIso8601String(),
      };
      if (status == 'active' || status == 'inactive') {
        body['status'] = status;
      }
      if (appStatus == 'app_closed' ||
          appStatus == 'app_background' ||
          appStatus == 'active' ||
          appStatus == 'inactive' ||
          appStatus == 'offline') {
        body['appStatus'] = appStatus;
      }
      body['movementType'] = resolvedMovementType;
      if (accuracy != null) body['accuracy'] = accuracy;
      if (batteryPercent != null) body['batteryPercent'] = batteryPercent;
      if (address != null && address.isNotEmpty) body['address'] = address;
      if (fullAddress != null && fullAddress.isNotEmpty) {
        body['fullAddress'] = fullAddress;
      }
      if (city != null && city.isNotEmpty) body['city'] = city;
      if (area != null && area.isNotEmpty) body['area'] = area;
      if (pincode != null && pincode.isNotEmpty) body['pincode'] = pincode;

      await _api.dio.post<dynamic>('/tracking/presence/store', data: body);
      await TrackingOutlierFilterService.rememberValidRecord(
        scope: TrackingOutlierFilterService.presenceScope,
        lat: lat,
        lng: lng,
        timestamp: capturedAt,
        movementType: resolvedMovementType,
        accuracyM: accuracy,
      );
      if (kDebugMode && AppConstants.logTrackingsToConsole) {
        debugPrint(
          '[Trackings] presence_store OK lat=${lat.toStringAsFixed(6)} '
          'lng=${lng.toStringAsFixed(6)} presence=$presenceStatus '
          'status=${status ?? "—"} appStatus=${appStatus ?? "—"} '
          'movement=$resolvedMovementType '
          'acc=${accuracy?.toStringAsFixed(1) ?? "—"}m',
        );
      }
      return (result: _PresenceSendResult.sent, movementType: resolvedMovementType);
    } on DioException catch (e) {
      if (kDebugMode && AppConstants.logTrackingsToConsole) {
        debugPrint(
          '[Trackings] presence_store FAIL ${e.response?.statusCode} '
          'presence=$presenceStatus status=${status ?? "—"} '
          'appStatus=${appStatus ?? "—"} '
          'movement=$resolvedMovementType '
          'lat=$lat lng=$lng → ${e.response?.data}',
        );
      }
      if (kDebugMode) {
        debugPrint(
          '[PresenceTracking] store ${e.response?.statusCode}: ${e.response?.data}',
        );
      }
      return (result: _PresenceSendResult.failed, movementType: resolvedMovementType);
    } catch (e) {
      if (kDebugMode) debugPrint('[PresenceTracking] store error: $e');
      return (result: _PresenceSendResult.failed, movementType: resolvedMovementType);
    }
  }

  Future<List<Map<String, dynamic>>> _loadPendingQueue() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kPresencePendingQueue);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      final out = <Map<String, dynamic>>[];
      for (final e in decoded) {
        if (e is Map) {
          out.add(Map<String, dynamic>.from(
            e.map((k, v) => MapEntry(k.toString(), v)),
          ));
        }
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  Future<void> _savePendingQueue(List<Map<String, dynamic>> list) async {
    final prefs = await SharedPreferences.getInstance();
    if (list.isEmpty) {
      await prefs.remove(_kPresencePendingQueue);
    } else {
      await prefs.setString(_kPresencePendingQueue, jsonEncode(list));
    }
  }

  Future<void> _enqueueFailedPeriodicPresence({
    required double lat,
    required double lng,
    required String presenceStatus,
    String? status,
    String? appStatus,
    String? movementType,
    double? accuracy,
    int? batteryPercent,
    String? address,
    String? fullAddress,
    String? city,
    String? area,
    String? pincode,
    required DateTime capturedAtUtc,
  }) async {
    var list = await _loadPendingQueue();
    list.add({
      'lat': lat,
      'lng': lng,
      'presenceStatus': presenceStatus,
      if (status != null && status.isNotEmpty) 'status': status,
      if (appStatus != null && appStatus.isNotEmpty) 'appStatus': appStatus,
      if (movementType != null && movementType.isNotEmpty)
        'movementType': movementType,
      if (accuracy != null) 'accuracy': accuracy,
      if (batteryPercent != null) 'batteryPercent': batteryPercent,
      if (address != null && address.isNotEmpty) 'address': address,
      if (fullAddress != null && fullAddress.isNotEmpty) 'fullAddress': fullAddress,
      if (city != null && city.isNotEmpty) 'city': city,
      if (area != null && area.isNotEmpty) 'area': area,
      if (pincode != null && pincode.isNotEmpty) 'pincode': pincode,
      'timestamp': capturedAtUtc.toIso8601String(),
    });
    while (list.length > _maxPendingPresence) {
      list = list.sublist(list.length - _maxPendingPresence);
    }
    await _savePendingQueue(list);
    if (kDebugMode) {
      debugPrint(
        '[PresenceTracking] queued failed send (queue size=${list.length})',
      );
    }
  }

  /// Replay locally stored periodic presence points (e.g. after offline). Call on app resume.
  Future<void> flushPendingPresenceQueue() async {
    if (_taskInProgress) return;
    if (!await isTrackingAllowed()) return;

    var list = await _loadPendingQueue();
    if (list.isEmpty) return;

    final remaining = <Map<String, dynamic>>[];
    for (final m in list) {
      final lat = (m['lat'] as num?)?.toDouble();
      final lng = (m['lng'] as num?)?.toDouble();
      final ps = m['presenceStatus'] as String?;
      final ts = m['timestamp'] as String?;
      if (lat == null || lng == null || ps == null || ts == null) {
        continue;
      }
      DateTime? t;
      try {
        t = DateTime.parse(ts).toUtc();
      } catch (_) {
        continue;
      }
      final outcome = await _sendPresence(
        lat: lat,
        lng: lng,
        presenceStatus: ps,
        status: m['status'] as String?,
        appStatus: m['appStatus'] as String?,
        movementType: m['movementType'] as String?,
        accuracy: (m['accuracy'] as num?)?.toDouble(),
        batteryPercent: (m['batteryPercent'] as num?)?.toInt(),
        address: m['address'] as String?,
        fullAddress: m['fullAddress'] as String?,
        city: m['city'] as String?,
        area: m['area'] as String?,
        pincode: m['pincode'] as String?,
        timestampUtc: t,
      );
      if (outcome.result == _PresenceSendResult.failed) remaining.add(m);
    }
    await _savePendingQueue(remaining);
    if (kDebugMode && AppConstants.logTrackingsToConsole && list.isNotEmpty) {
      debugPrint(
        '[Trackings] flush_pending sent=${list.length - remaining.length}/${list.length} remaining=${remaining.length}',
      );
    }
  }

  bool _isInsideOffice(
    double lat,
    double lng,
    Map<String, dynamic>? branchGeofence,
  ) {
    if (branchGeofence == null) return false;
    final officeLat = (branchGeofence['latitude'] as num?)?.toDouble();
    final officeLng = (branchGeofence['longitude'] as num?)?.toDouble();
    final radius =
        (branchGeofence['radius'] as num?)?.toDouble() ??
        defaultOfficeRadiusMeters;

    if (officeLat == null || officeLng == null) return false;

    final distM = gl.Geolocator.distanceBetween(lat, lng, officeLat, officeLng);
    return distM <= radius;
  }

  Future<void> _tick(Map<String, dynamic>? branchGeofence) async {
    if (!_isTracking) return;
    if (_taskInProgress) return;

    if (!await isTrackingAllowed()) {
      stopTracking();
      return;
    }

    final gf = branchGeofence;

    gl.Position? position;
    try {
      position = await _capturePresencePosition();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[PresenceTracking] accurate position failed: $e');
      }
      return;
    }

    final lat = position.latitude;
    final lng = position.longitude;
    final accuracy = position.accuracy;
    int? batteryPercent;
    try {
      batteryPercent = await Battery().batteryLevel;
    } catch (_) {}
    final resolvedAddress = await AddressResolutionService.reverseGeocode(
      lat,
      lng,
    );
    final movementType = await _classifyForegroundMovement(position);

    final presenceStatus = _isInsideOffice(lat, lng, gf)
        ? 'in_office'
        : 'out_of_office';
    final appStatus = await _getAppStatusForCurrentLifecycle();

    final capturedAt = DateTime.now().toUtc();
    final outcome = await _sendPresence(
      lat: lat,
      lng: lng,
      presenceStatus: presenceStatus,
      status: 'active',
      appStatus: appStatus,
      movementType: movementType,
      accuracy: accuracy,
      batteryPercent: batteryPercent,
      address: resolvedAddress?.formattedAddress,
      fullAddress: resolvedAddress?.formattedAddress,
      city: resolvedAddress?.city ?? resolvedAddress?.state,
      area: resolvedAddress?.area,
      pincode: resolvedAddress?.pincode,
      timestampUtc: capturedAt,
    );
    if (outcome.result == _PresenceSendResult.failed) {
      await _enqueueFailedPeriodicPresence(
        lat: lat,
        lng: lng,
        presenceStatus: presenceStatus,
        status: 'active',
        appStatus: appStatus,
        movementType: outcome.movementType,
        accuracy: accuracy,
        batteryPercent: batteryPercent,
        address: resolvedAddress?.formattedAddress,
        fullAddress: resolvedAddress?.formattedAddress,
        city: resolvedAddress?.city ?? resolvedAddress?.state,
        area: resolvedAddress?.area,
        pincode: resolvedAddress?.pincode,
        capturedAtUtc: capturedAt,
      );
    }
    if (kDebugMode) {
      debugPrint(
        '[PresenceTracking] tick presence=$presenceStatus movement=${outcome.movementType} '
        'result=${outcome.result == _PresenceSendResult.sent ? "ok" : outcome.result == _PresenceSendResult.skipped ? "skip" : "fail"}',
      );
    }
    if (outcome.result == _PresenceSendResult.sent) {
      await _persistPresenceMovementState(
        lat,
        lng,
        movementType: outcome.movementType,
        consecutiveLowSpeed:
            outcome.movementType == kMovementStop
                ? MovementClassificationService().consecutiveLowSpeedCount
                : 0,
        recordedAt: capturedAt,
      );
    }
  }

  Future<void> _periodicTick() async {
    if (!_isTracking || _taskInProgress) return;
    if (_periodicTickInProgress) return;
    if (!await isTrackingAllowed()) {
      stopTracking();
      return;
    }
    _periodicTickInProgress = true;
    try {
      final status = await getPresenceStatus();
      final gf = status['branchGeofence'] as Map<String, dynamic>?;
      await _tick(gf);
    } finally {
      _periodicTickInProgress = false;
    }
  }

  /// First send + periodic uploads. Ensures a tracking record is inserted every 1 minute while checked in.
  Future<void> _schedulePresenceSends() async {
    if (_taskInProgress) return;
    if (!await isTrackingAllowed()) return;

    _isTracking = true;
    await MovementClassificationService().start();
    await flushPendingPresenceQueue();
    await _ensureBackgroundPresenceTracking();
    try {
      final status = await getPresenceStatus();
      final gf = status['branchGeofence'] as Map<String, dynamic>?;
      await _tick(gf);
    } catch (e) {
      if (kDebugMode) debugPrint('[PresenceTracking] initial tick failed: $e');
    }
    _trackingTimer?.cancel();
    _trackingTimer = Timer.periodic(trackingInterval, (_) {
      _periodicTick();
    });
    if (kDebugMode) {
      debugPrint('[PresenceTracking] timer started (interval: ${trackingInterval.inMinutes} min)');
    }
  }

  /// Insert one tracking record immediately when app is opened: status "active", presenceStatus "in_office", full address details.
  Future<void> recordAppOpened() async {
    if (_taskInProgress) return;
    if (!await isTrackingAllowed()) return;
    await markAppForeground();

    try {
      final position = await _capturePresencePosition();
      int? batteryPercent;
      try {
        batteryPercent = await Battery().batteryLevel;
      } catch (_) {}
      final resolvedAddress = await AddressResolutionService.reverseGeocode(
        position.latitude,
        position.longitude,
      );
      final movementType = await _classifyForegroundMovement(position);

      final outcome = await _sendPresence(
        lat: position.latitude,
        lng: position.longitude,
        presenceStatus: 'in_office',
        status: 'active',
        appStatus: 'active',
        movementType: movementType,
        accuracy: position.accuracy,
        batteryPercent: batteryPercent,
        address: resolvedAddress?.formattedAddress,
        fullAddress: resolvedAddress?.formattedAddress,
        city: resolvedAddress?.city ?? resolvedAddress?.state,
        area: resolvedAddress?.area,
        pincode: resolvedAddress?.pincode,
      );
      if (kDebugMode) {
        debugPrint(
          '[PresenceTracking] recordAppOpened: active, in_office '
          'result=${outcome.result == _PresenceSendResult.sent ? "ok" : outcome.result == _PresenceSendResult.skipped ? "skip" : "fail"} '
          'movement=${outcome.movementType}',
        );
      }
      if (outcome.result == _PresenceSendResult.sent) {
        await _persistPresenceMovementState(
          position.latitude,
          position.longitude,
          movementType: outcome.movementType,
          consecutiveLowSpeed:
              outcome.movementType == kMovementStop
                  ? MovementClassificationService().consecutiveLowSpeedCount
                  : 0,
        );
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[PresenceTracking] recordAppOpened failed: $e');
    }
  }

  Future<void> recordAppClosed() async {
    if (_sendingAppClosed) return;
    if (_taskInProgress) return;
    if (!await isTrackingAllowed()) return;

    _sendingAppClosed = true;
    await markAppClosed();
    try {
      final status = await getPresenceStatus();
      final branchGeofence = status['branchGeofence'] as Map<String, dynamic>?;
      final position = await _capturePresencePosition();
      int? batteryPercent;
      try {
        batteryPercent = await Battery().batteryLevel;
      } catch (_) {}
      final resolvedAddress = await AddressResolutionService.reverseGeocode(
        position.latitude,
        position.longitude,
      );
      final presenceStatus = _isInsideOffice(
        position.latitude,
        position.longitude,
        branchGeofence,
      )
          ? 'in_office'
          : 'out_of_office';
      final movementType = await _classifyForegroundMovement(position);

      final outcome = await _sendPresence(
        lat: position.latitude,
        lng: position.longitude,
        presenceStatus: presenceStatus,
        status: 'active',
        appStatus: 'app_closed',
        movementType: movementType,
        accuracy: position.accuracy,
        batteryPercent: batteryPercent,
        address: resolvedAddress?.formattedAddress,
        fullAddress: resolvedAddress?.formattedAddress,
        city: resolvedAddress?.city ?? resolvedAddress?.state,
        area: resolvedAddress?.area,
        pincode: resolvedAddress?.pincode,
      );

      _isInsideOffice(position.latitude, position.longitude, branchGeofence);
      if (outcome.result == _PresenceSendResult.sent) {
        await _persistPresenceMovementState(
          position.latitude,
          position.longitude,
          movementType: outcome.movementType,
          consecutiveLowSpeed:
              outcome.movementType == kMovementStop
                  ? MovementClassificationService().consecutiveLowSpeedCount
                  : 0,
        );
      }
    } catch (_) {
    } finally {
      _sendingAppClosed = false;
    }
  }

  /// Start or refresh 1-minute presence uploads (after check-in).
  Future<void> startTracking() async {
    await _schedulePresenceSends();
  }

  /// After app returns to foreground — timer often pauses in background; send now and restart interval.
  Future<void> onAppLifecycleResumed() async {
    if (_taskInProgress) return;
    if (!await isTrackingAllowed()) return;
    _isTracking = true;
    await flushPendingPresenceQueue();
    await _periodicTick();
    _trackingTimer?.cancel();
    _trackingTimer = Timer.periodic(trackingInterval, (_) {
      _periodicTick();
    });
  }

  Future<void> stopTracking() async {
    _isTracking = false;
    _taskInProgress = false;
    _trackingTimer?.cancel();
    _trackingTimer = null;
    await MovementClassificationService().stop();
    await clearTrackingAllowed();
    await _stopBackgroundPresenceTrackingIfIdle();
  }

  void pausePresenceTracking() {
    _taskInProgress = true;
    _trackingTimer?.cancel();
    _trackingTimer = null;
  }

  Future<void> resumePresenceTracking() async {
    _taskInProgress = false;
    if (!await isTrackingAllowed()) return;
    await _schedulePresenceSends();
  }

  bool get isTracking => _isTracking;
}
