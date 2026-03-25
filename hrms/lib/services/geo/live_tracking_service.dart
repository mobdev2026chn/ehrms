import 'dart:convert';
import 'package:background_location_tracker/background_location_tracker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart' as gl;
import '../../config/constants.dart';
import 'address_resolution_service.dart';
import 'movement_classification_service.dart';
import 'tracking_outlier_filter_service.dart';

/// Persists active live tracking state and sends tracking in background.
/// Used so tracking continues when app is closed or in background.
class LiveTrackingService {
  static const _keyActive = 'live_tracking_active';
  static const _keyTaskMongoId = 'live_tracking_task_mongo_id';
  static const _keyTaskId = 'live_tracking_task_id';
  static const _keyPickupLat = 'live_tracking_pickup_lat';
  static const _keyPickupLng = 'live_tracking_pickup_lng';
  static const _keyDropoffLat = 'live_tracking_dropoff_lat';
  static const _keyDropoffLng = 'live_tracking_dropoff_lng';
  static const _keyTaskJson = 'live_tracking_task_json';
  static const _keyBaseUrl = 'live_tracking_base_url';
  static const _keyToken = 'live_tracking_token';
  static const _keyAppLifecycleState = 'live_tracking_app_lifecycle_state';
  static const _keyLastSentLat = 'live_tracking_last_sent_lat';
  static const _keyLastSentLng = 'live_tracking_last_sent_lng';
  static const _keyLastSentTime = 'live_tracking_last_sent_time';
  static const _keyLastMovementType = 'live_tracking_last_movement_type';
  static const _keyConsecutiveLowSpeed = 'live_tracking_consecutive_low_speed';
  static const _keyLastStoredTaskMongoId =
      'live_tracking_last_stored_task_mongo_id';
  static const _keyLastStoredLat = 'live_tracking_last_stored_lat';
  static const _keyLastStoredLng = 'live_tracking_last_stored_lng';
  static const _keyLastResolvedAddressLat =
      'live_tracking_last_resolved_address_lat';
  static const _keyLastResolvedAddressLng =
      'live_tracking_last_resolved_address_lng';
  static const _keyLastResolvedAddress = 'live_tracking_last_resolved_address';
  static const _keyLastResolvedFullAddress =
      'live_tracking_last_resolved_full_address';
  static const _keyLastResolvedCity = 'live_tracking_last_resolved_city';
  static const _keyLastResolvedArea = 'live_tracking_last_resolved_area';
  static const _keyLastResolvedPincode =
      'live_tracking_last_resolved_pincode';
  /// Wall-clock start of the current live trip (for UI "Elapsed"; survives sleep / restart).
  static const _keyTripStartMs = 'live_tracking_trip_start_ms';
  static const double duplicateLocationThresholdMeters = 10;

  static final LiveTrackingService _instance = LiveTrackingService._internal();
  factory LiveTrackingService() => _instance;
  LiveTrackingService._internal();

  static String? _sanitizeStoredToken(String? token) {
    if (token == null) return null;
    final trimmed = token.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.startsWith('"') || trimmed.endsWith('"')) {
      return trimmed.replaceAll('"', '');
    }
    return trimmed;
  }

  /// Start live tracking - persist state for background sending.
  Future<void> startTracking({
    required String taskMongoId,
    required String taskId,
    required double pickupLat,
    required double pickupLng,
    required double dropoffLat,
    required double dropoffLng,
    String? taskJson,
  }) async {
    await TrackingOutlierFilterService.clearScope(
      TrackingOutlierFilterService.taskScope(taskMongoId),
    );
    final prefs = await SharedPreferences.getInstance();
    final previousTaskId = prefs.getString(_keyTaskMongoId);
    final existingTripStartMs = prefs.getInt(_keyTripStartMs);
    final previousLastSentTime = prefs.getInt(_keyLastSentTime);

    await prefs.setBool(_keyActive, true);
    await prefs.setString(_keyTaskMongoId, taskMongoId);
    await prefs.setString(_keyTaskId, taskId);
    await prefs.setDouble(_keyPickupLat, pickupLat);
    await prefs.setDouble(_keyPickupLng, pickupLng);
    await prefs.setDouble(_keyDropoffLat, dropoffLat);
    await prefs.setDouble(_keyDropoffLng, dropoffLng);
    await prefs.setString(_keyAppLifecycleState, 'foreground');
    if (taskJson != null) await prefs.setString(_keyTaskJson, taskJson);
    await prefs.setString(_keyBaseUrl, AppConstants.baseUrl);
    await prefs.setDouble(_keyLastSentLat, pickupLat);
    await prefs.setDouble(_keyLastSentLng, pickupLng);
    await prefs.setInt(_keyLastSentTime, DateTime.now().millisecondsSinceEpoch);

    // Persist trip start once per task; reuse after app sleep / cold start so "Elapsed" stays correct.
    if (previousTaskId == taskMongoId && existingTripStartMs != null) {
      // keep existingTripStartMs
    } else if (previousTaskId == taskMongoId && existingTripStartMs == null) {
      await prefs.setInt(
        _keyTripStartMs,
        previousLastSentTime ?? DateTime.now().millisecondsSinceEpoch,
      );
    } else {
      await prefs.setInt(_keyTripStartMs, DateTime.now().millisecondsSinceEpoch);
    }
    final token = prefs.getString('token');
    if (token != null) {
      await prefs.setString(_keyToken, token);
    }
  }

  /// Update persisted destination so app resume/background tracking uses the latest pin.
  Future<void> updateDestination({
    required double dropoffLat,
    required double dropoffLng,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_keyActive) != true) return;
    await prefs.setDouble(_keyDropoffLat, dropoffLat);
    await prefs.setDouble(_keyDropoffLng, dropoffLng);
  }

  /// Stop live tracking - clear persisted state.
  Future<void> stopTracking() async {
    final prefs = await SharedPreferences.getInstance();
    final taskMongoId = prefs.getString(_keyTaskMongoId);
    await prefs.remove(_keyActive);
    await prefs.remove(_keyTaskMongoId);
    await prefs.remove(_keyTaskId);
    await prefs.remove(_keyPickupLat);
    await prefs.remove(_keyPickupLng);
    await prefs.remove(_keyDropoffLat);
    await prefs.remove(_keyDropoffLng);
    await prefs.remove(_keyTaskJson);
    await prefs.remove(_keyBaseUrl);
    await prefs.remove(_keyToken);
    await prefs.remove(_keyAppLifecycleState);
    await prefs.remove(_keyLastSentLat);
    await prefs.remove(_keyLastSentLng);
    await prefs.remove(_keyLastSentTime);
    await prefs.remove(_keyLastMovementType);
    await prefs.remove(_keyConsecutiveLowSpeed);
    await prefs.remove(_keyLastStoredTaskMongoId);
    await prefs.remove(_keyLastStoredLat);
    await prefs.remove(_keyLastStoredLng);
    await prefs.remove(_keyLastResolvedAddressLat);
    await prefs.remove(_keyLastResolvedAddressLng);
    await prefs.remove(_keyLastResolvedAddress);
    await prefs.remove(_keyLastResolvedFullAddress);
    await prefs.remove(_keyLastResolvedCity);
    await prefs.remove(_keyLastResolvedArea);
    await prefs.remove(_keyLastResolvedPincode);
    await prefs.remove(_keyTripStartMs);
    if (taskMongoId != null && taskMongoId.isNotEmpty) {
      await TrackingOutlierFilterService.clearScope(
        TrackingOutlierFilterService.taskScope(taskMongoId),
      );
    }
  }

  /// Persist last sent position and movement state for background hysteresis.
  static Future<void> persistLastSentPosition(
    double lat,
    double lng, {
    String? movementType,
    int consecutiveLowSpeed = 0,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_keyActive) != true) return;
      await prefs.setDouble(_keyLastSentLat, lat);
      await prefs.setDouble(_keyLastSentLng, lng);
      await prefs.setInt(
        _keyLastSentTime,
        DateTime.now().millisecondsSinceEpoch,
      );
      if (movementType != null) {
        await prefs.setString(_keyLastMovementType, movementType);
        await prefs.setInt(_keyConsecutiveLowSpeed, consecutiveLowSpeed);
      }
    } catch (_) {}
  }

  static Future<({
    bool shouldSkip,
    double? distanceM,
    double? lastLat,
    double? lastLng,
  })> getDuplicateTrackingDecision(
    String taskMongoId,
    double lat,
    double lng, {
    double thresholdMeters = duplicateLocationThresholdMeters,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastTaskMongoId = prefs.getString(_keyLastStoredTaskMongoId);
      if (lastTaskMongoId != taskMongoId) {
        return (
          shouldSkip: false,
          distanceM: null,
          lastLat: null,
          lastLng: null,
        );
      }
      final lastLat = prefs.getDouble(_keyLastStoredLat);
      final lastLng = prefs.getDouble(_keyLastStoredLng);
      if (lastLat == null || lastLng == null) {
        return (
          shouldSkip: false,
          distanceM: null,
          lastLat: null,
          lastLng: null,
        );
      }
      final distanceM = gl.Geolocator.distanceBetween(
        lastLat,
        lastLng,
        lat,
        lng,
      );
      return (
        shouldSkip: distanceM < thresholdMeters,
        distanceM: distanceM,
        lastLat: lastLat,
        lastLng: lastLng,
      );
    } catch (_) {
      return (
        shouldSkip: false,
        distanceM: null,
        lastLat: null,
        lastLng: null,
      );
    }
  }

  Future<void> markAppForeground() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyAppLifecycleState, 'foreground');
  }

  Future<void> markAppBackground() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyAppLifecycleState, 'background');
  }

  Future<void> markAppClosed() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyAppLifecycleState, 'closed');
  }

  static Future<String> _getLifecycleAppStatusForBackgroundLogs() async {
    final prefs = await SharedPreferences.getInstance();
    final state = prefs.getString(_keyAppLifecycleState);
    if (state == 'closed') return 'app_closed';
    if (state == 'foreground') return 'active';
    return 'app_background';
  }

  static Future<bool> shouldSkipDuplicateTrackingSend(
    String taskMongoId,
    double lat,
    double lng, {
    double thresholdMeters = duplicateLocationThresholdMeters,
  }) async {
    final decision = await getDuplicateTrackingDecision(
      taskMongoId,
      lat,
      lng,
      thresholdMeters: thresholdMeters,
    );
    return decision.shouldSkip;
  }

  static Future<void> persistStoredTrackingPoint(
    String taskMongoId,
    double lat,
    double lng,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyLastStoredTaskMongoId, taskMongoId);
      await prefs.setDouble(_keyLastStoredLat, lat);
      await prefs.setDouble(_keyLastStoredLng, lng);
    } catch (_) {}
  }

  static Future<void> persistResolvedAddress(
    double lat,
    double lng, {
    String? address,
    String? fullAddress,
    String? city,
    String? area,
    String? pincode,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_keyActive) != true) return;
      await prefs.setDouble(_keyLastResolvedAddressLat, lat);
      await prefs.setDouble(_keyLastResolvedAddressLng, lng);
      if (address != null && address.isNotEmpty) {
        await prefs.setString(_keyLastResolvedAddress, address);
      }
      if (fullAddress != null && fullAddress.isNotEmpty) {
        await prefs.setString(_keyLastResolvedFullAddress, fullAddress);
      }
      if (city != null && city.isNotEmpty) {
        await prefs.setString(_keyLastResolvedCity, city);
      }
      if (area != null && area.isNotEmpty) {
        await prefs.setString(_keyLastResolvedArea, area);
      }
      if (pincode != null && pincode.isNotEmpty) {
        await prefs.setString(_keyLastResolvedPincode, pincode);
      }
    } catch (_) {}
  }

  static int _addressDetailScore(Map<String, String?> address) {
    final formatted =
        (address['fullAddress'] ?? address['address'] ?? '').trim();
    if (formatted.isEmpty) return -1;

    var score = 0;
    if ((address['area'] ?? '').trim().isNotEmpty) score += 2;
    if ((address['city'] ?? '').trim().isNotEmpty) score += 1;
    if ((address['pincode'] ?? '').trim().isNotEmpty) score += 1;
    if (RegExp(r'\d').hasMatch(formatted)) score += 2;
    if (RegExp(r'\b(road|rd|street|st|lane|ln|nagar|main)\b', caseSensitive: false)
        .hasMatch(formatted)) {
      score += 2;
    }
    score += ','.allMatches(formatted).length.clamp(0, 3);
    return score;
  }

  static bool _hasDetailedAddress(Map<String, String?> address) {
    return _addressDetailScore(address) >= 5;
  }

  /// Check if live tracking is active.
  Future<bool> isActive() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyActive) == true;
  }

  /// Milliseconds since epoch when the current live trip started (for UI elapsed time).
  Future<int?> getTripStartMs() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyTripStartMs);
  }

  /// Writes trip start (e.g. from server [Task.startTime]) when local prefs were reset incorrectly.
  Future<void> persistTripStartMs(int millisecondsSinceEpoch) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_keyActive) != true) return;
    await prefs.setInt(_keyTripStartMs, millisecondsSinceEpoch);
  }

  static bool _looksLikeMissingPlugin(Object e) {
    return e is MissingPluginException ||
        e.toString().contains('No implementation found for method initialized');
  }

  /// Cold start: native plugin often reports `false` briefly; retry before treating as stopped.
  Future<bool> isBackgroundLocationTrackingRunningWithRetry({
    int maxAttempts = 8,
    Duration delayBetweenAttempts = const Duration(milliseconds: 350),
  }) async {
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        if (await BackgroundLocationTrackerManager.isTracking()) {
          return true;
        }
      } catch (e) {
        if (_looksLikeMissingPlugin(e)) {
          return true;
        }
        rethrow;
      }
      if (attempt < maxAttempts - 1) {
        await Future.delayed(delayBetweenAttempts);
      }
    }
    return false;
  }

  /// Get active task info for restoring LiveTrackingScreen.
  Future<Map<String, dynamic>?> getActiveTaskInfo() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_keyActive) != true) return null;
    final taskMongoId = prefs.getString(_keyTaskMongoId);
    if (taskMongoId == null || taskMongoId.isEmpty) return null;
    return {
      'taskMongoId': taskMongoId,
      'taskId': prefs.getString(_keyTaskId) ?? '',
      'pickupLat': prefs.getDouble(_keyPickupLat) ?? 0.0,
      'pickupLng': prefs.getDouble(_keyPickupLng) ?? 0.0,
      'dropoffLat': prefs.getDouble(_keyDropoffLat) ?? 0.0,
      'dropoffLng': prefs.getDouble(_keyDropoffLng) ?? 0.0,
      'taskJson': prefs.getString(_keyTaskJson),
    };
  }

  /// Send tracking from background isolate.
  /// Ignores points with accuracy > 50m before movement classification.
  static Future<void> sendTrackingFromBackground(
    double lat,
    double lng, {
    int? batteryPercent,
    String? movementType,
    double? speedMps,
    double? accuracyM,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final active = prefs.getBool(_keyActive);
      if (active != true) return;
      final taskMongoId = prefs.getString(_keyTaskMongoId);
      final baseUrl = prefs.getString(_keyBaseUrl);
      final token = _sanitizeStoredToken(prefs.getString(_keyToken));
      if (taskMongoId == null || taskMongoId.isEmpty) return;
      if (baseUrl == null || baseUrl.isEmpty) return;
      if (token == null || token.isEmpty) return;
      if (accuracyM != null && accuracyM > kMaxAccuracyM) return;
      final capturedAt = DateTime.now().toUtc();
      final appStatus = await _getLifecycleAppStatusForBackgroundLogs();
      if (kDebugMode && AppConstants.logTrackingsToConsole) {
        debugPrint(
          '[Trackings] task_detected_bg taskId=$taskMongoId '
          'lat=${lat.toStringAsFixed(6)} lng=${lng.toStringAsFixed(6)} '
          'appStatus=$appStatus acc=${accuracyM?.toStringAsFixed(1) ?? "—"}m',
        );
      }
      final lastLat = prefs.getDouble(_keyLastSentLat);
      final lastLng = prefs.getDouble(_keyLastSentLng);
      final lastTimeMs = prefs.getInt(_keyLastSentTime);
      final lastMovement = prefs.getString(_keyLastMovementType) ?? 'stop';
      final consecutiveLow = prefs.getInt(_keyConsecutiveLowSpeed) ?? 0;

      double avgSpeedKmh = 0.0;
      if (lastLat != null &&
          lastLng != null &&
          lastTimeMs != null &&
          lastTimeMs > 0) {
        final distanceM = gl.Geolocator.distanceBetween(
          lastLat,
          lastLng,
          lat,
          lng,
        );
        final nowMs = DateTime.now().millisecondsSinceEpoch;
        final elapsedSec = (nowMs - lastTimeMs) / 1000.0;
        if (elapsedSec > 0.1) {
          final speedMpsCalc = distanceM / elapsedSec;
          avgSpeedKmh = speedMpsCalc * 3.6;
        }
      }

      String resolvedMovementType =
          MovementClassificationService.classifyFromTrackingSignals(
            distanceM: (lastLat != null && lastLng != null) ? gl.Geolocator.distanceBetween(
              lastLat,
              lastLng,
              lat,
              lng,
            ) : 0.0,
            elapsedSeconds: (lastTimeMs != null && lastTimeMs > 0)
                ? (DateTime.now().millisecondsSinceEpoch - lastTimeMs) / 1000.0
                : 0.0,
            lastMovementType: lastMovement,
            sensorSpeedKmh:
                (speedMps != null && speedMps.isFinite && speedMps >= 0)
                    ? speedMps * 3.6
                    : null,
          );
      int nextConsecutive = avgSpeedKmh <= 1.0 ? (consecutiveLow + 1) : 0;

      final outlierDecision = await TrackingOutlierFilterService.evaluate(
        scope: TrackingOutlierFilterService.taskScope(taskMongoId),
        lat: lat,
        lng: lng,
        timestamp: capturedAt,
        movementType: resolvedMovementType,
        accuracyM: accuracyM,
        sensorSpeedMps: speedMps,
      );
      if (outlierDecision.shouldSkip) {
        if (kDebugMode && AppConstants.logTrackingsToConsole) {
          debugPrint(
            '[Trackings] task_store SKIP outlier taskId=$taskMongoId '
            'appStatus=$appStatus reason=${outlierDecision.reason} '
            'distance=${outlierDecision.distanceM?.toStringAsFixed(2) ?? "—"}m '
            'speed=${outlierDecision.speedKmh?.toStringAsFixed(2) ?? "—"}kmh',
          );
        }
        return;
      }
      resolvedMovementType = outlierDecision.movementType;
      nextConsecutive = resolvedMovementType == kMovementStop
          ? (consecutiveLow + 1)
          : 0;

      final destinationLat = prefs.getDouble(_keyDropoffLat);
      final destinationLng = prefs.getDouble(_keyDropoffLng);
      final resolvedAddress = await _resolveTrackingAddressForBackground(
        prefs,
        lat,
        lng,
      );

      final url = baseUrl.replaceAll(RegExp(r'/$'), '');
      final uri = Uri.parse('$url/tracking/store');
      final body = <String, dynamic>{
        'taskId': taskMongoId,
        'lat': lat,
        'lng': lng,
        'timestamp': capturedAt.toIso8601String(),
      };
      if (batteryPercent != null) body['batteryPercent'] = batteryPercent;
      body['movementType'] = resolvedMovementType;
      if (destinationLat != null) body['destinationLat'] = destinationLat;
      if (destinationLng != null) body['destinationLng'] = destinationLng;
      if ((resolvedAddress['address'] ?? '').toString().isNotEmpty) {
        body['address'] = resolvedAddress['address'];
      }
      if ((resolvedAddress['fullAddress'] ?? '').toString().isNotEmpty) {
        body['fullAddress'] = resolvedAddress['fullAddress'];
      }
      if ((resolvedAddress['city'] ?? '').toString().isNotEmpty) {
        body['city'] = resolvedAddress['city'];
      }
      if ((resolvedAddress['area'] ?? '').toString().isNotEmpty) {
        body['area'] = resolvedAddress['area'];
      }
      if ((resolvedAddress['pincode'] ?? '').toString().isNotEmpty) {
        body['pincode'] = resolvedAddress['pincode'];
      }

      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(body),
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (kDebugMode && AppConstants.logTrackingsToConsole) {
          debugPrint(
            '[Trackings] task_store OK taskId=$taskMongoId '
            'lat=${lat.toStringAsFixed(6)} lng=${lng.toStringAsFixed(6)} '
            'appStatus=$appStatus movement=$resolvedMovementType '
            'acc=${accuracyM?.toStringAsFixed(1) ?? "—"}m',
          );
        }
        await prefs.setDouble(_keyLastSentLat, lat);
        await prefs.setDouble(_keyLastSentLng, lng);
        await prefs.setInt(
          _keyLastSentTime,
          DateTime.now().millisecondsSinceEpoch,
        );
        await prefs.setString(_keyLastMovementType, resolvedMovementType);
        await prefs.setInt(_keyConsecutiveLowSpeed, nextConsecutive);
        await persistStoredTrackingPoint(taskMongoId, lat, lng);
        await TrackingOutlierFilterService.rememberValidRecord(
          scope: TrackingOutlierFilterService.taskScope(taskMongoId),
          lat: lat,
          lng: lng,
          timestamp: capturedAt,
          movementType: resolvedMovementType,
          accuracyM: accuracyM,
        );
      } else if (kDebugMode && AppConstants.logTrackingsToConsole) {
        debugPrint(
          '[Trackings] task_store FAIL ${response.statusCode} taskId=$taskMongoId '
          'appStatus=$appStatus body=${response.body.length > 200 ? "${response.body.substring(0, 200)}..." : response.body}',
        );
      }
    } catch (e) {
      if (kDebugMode && AppConstants.logTrackingsToConsole) {
        debugPrint('[Trackings] task_store error appStatus=app_background: $e');
      }
    }
  }

  static Future<Map<String, String?>> _resolveTrackingAddressForBackground(
    SharedPreferences prefs,
    double lat,
    double lng,
  ) async {
    final cachedLat = prefs.getDouble(_keyLastResolvedAddressLat);
    final cachedLng = prefs.getDouble(_keyLastResolvedAddressLng);
    final cachedAddress = prefs.getString(_keyLastResolvedAddress);
    final cachedFullAddress = prefs.getString(_keyLastResolvedFullAddress);
    final cachedCity = prefs.getString(_keyLastResolvedCity);
    final cachedArea = prefs.getString(_keyLastResolvedArea);
    final cachedPincode = prefs.getString(_keyLastResolvedPincode);

    final cached = <String, String?>{
      'address': cachedAddress,
      'fullAddress': cachedFullAddress,
      'city': cachedCity,
      'area': cachedArea,
      'pincode': cachedPincode,
    };

    if (cachedLat != null &&
        cachedLng != null &&
        ((cachedAddress ?? '').isNotEmpty || (cachedFullAddress ?? '').isNotEmpty)) {
      final distance = gl.Geolocator.distanceBetween(
        cachedLat,
        cachedLng,
        lat,
        lng,
      );
      if (distance <= 30 && _hasDetailedAddress(cached)) {
        return cached;
      }
    }

    final resolved = await AddressResolutionService.reverseGeocodeWithGoogle(
      lat,
      lng,
    );
    if (resolved != null && resolved.formattedAddress.isNotEmpty) {
      final fresh = <String, String?>{
        'address': resolved.formattedAddress,
        'fullAddress': resolved.formattedAddress,
        'city': resolved.city ?? resolved.state,
        'area': resolved.area,
        'pincode': resolved.pincode,
      };
      if (_addressDetailScore(cached) > _addressDetailScore(fresh)) {
        return cached;
      }
      await persistResolvedAddress(
        lat,
        lng,
        address: fresh['address'],
        fullAddress: fresh['fullAddress'],
        city: fresh['city'],
        area: fresh['area'],
        pincode: fresh['pincode'],
      );
      return fresh;
    }

    return cached;
  }

}
