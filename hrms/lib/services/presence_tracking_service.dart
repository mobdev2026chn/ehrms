// presence_tracking_service.dart
// Day-long "timeline" location tracking that starts at PUNCH IN (not at a task's Field In).
//
// Flow: punch in -> ensureTrackingIfPunchedIn(true) -> refresh GET /staff/profile and read the
// admin-controlled `Staff.tracking` flag -> if true, store a point every
// [AppConstants.presenceTrackingCaptureIntervalSeconds] via
// POST /staff/geo-task/live-tracking/record (no taskId; staffId comes from the JWT) until
// PUNCH OUT (ensureTrackingIfPunchedIn(false) / stopTracking()). If the flag is false/absent,
// nothing is tracked and any running presence tracking is stopped.
//
// While a GEO task ride is live, presence is paused and LiveTrackingService (task tracking)
// takes over; it resumes after the ride.
// Timer runs regardless of which screen is visible (singleton). When app is in background,
// the OS may pause the isolate so the timer does not fire; the native background tracker
// (see main.dart backgroundCallback -> sendPresenceFromBackground) keeps sending points.
// Failed sends (e.g. offline) are queued locally and replayed via
// POST /staff/geo-task/live-tracking/batch.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:battery_plus/battery_plus.dart';
import 'package:background_location_tracker/background_location_tracker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart' as gl;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dio/dio.dart';
import 'package:hrms/config/constants.dart';
import 'package:hrms/services/attendance_template_store.dart';
import 'package:hrms/services/geo/address_resolution_service.dart';
import 'package:hrms/services/geo/accurate_location_helper.dart';
import 'package:hrms/services/geo/live_tracking_service.dart';
import 'package:hrms/services/geo/movement_classification_service.dart';
import 'package:hrms/services/geo/tracking_health_service.dart';
import 'package:hrms/services/geo/tracking_outlier_filter_service.dart';
import 'api_client.dart';
import 'auth_service.dart';

/// HRMSbackend endpoints (mounted under /api/staff/geo-task). A point without taskId is
/// stored as a staff-level (presence) point in the LiveTracking collection.
const String _kPresenceRecordPath = '/staff/geo-task/live-tracking/record';
const String _kPresenceBatchPath = '/staff/geo-task/live-tracking/batch';

/// Last known value of the staff profile's admin-controlled `tracking` flag.
const String _kPresenceTrackingFlag = 'presence_staff_tracking_flag';
const String _kPresenceTrackingFlagCheckedAt =
    'presence_staff_tracking_flag_checked_at_ms';

/// Throttled reverse-geocode cache for presence points (phone geocoder only).
const String _kPresenceAddrLat = 'presence_addr_lat';
const String _kPresenceAddrLng = 'presence_addr_lng';
const String _kPresenceAddrJson = 'presence_addr_json';
const String _kPresenceAddrAtMs = 'presence_addr_at_ms';

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

/// JSON: { id, latitude, longitude, radius } — sub-zone from branch.geofence.locations hit at check-in.
const String _kPresencePinnedGeofenceLocation =
    'presence_pinned_geofence_location_json';
/// Offline presence points kept on the phone. Stationary points are not queued, so this
/// covers well over a working day of real movement; beyond it the oldest are dropped.
const int _maxPendingPresence = 3000;

/// A queued point must be this far from the last queued one (same movement) to be kept.
const double _minQueueMoveM = 15;

/// Offline points are replayed in requests of this many.
const int _flushBatchSize = 200;

enum _PresenceSendResult { sent, skipped, failed }

typedef _PresenceSendOutcome = ({
  _PresenceSendResult result,
  String movementType,
});

class PresenceTrackingService {
  static bool _looksLikeMissingPlugin(Object error) {
    return error is MissingPluginException ||
        error.toString().contains(
          'No implementation found for method initialized',
        );
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
  bool _flushInProgress = false;
  Future<void>? _ensureInFlight;
  static int _offlineSendingCount = 0;

  /// A punch-in (or dashboard reload) re-reads the staff profile unless the flag was
  /// fetched within this window (dedupes the concurrent punch-in + nav refresh calls).
  static const Duration _flagMaxAgeOnEnsure = Duration(seconds: 60);

  /// While tracking, the flag is re-checked this often so an admin turning tracking
  /// off stops the device without waiting for punch out.
  static const Duration _flagMaxAgeWhileTracking = Duration(minutes: 30);
  static int _localOfflineInsertCount = 0;

  /// Seconds between captured points. Comes from the admin's HRMS Geo setting
  /// (GET /staff/geo-task/live-tracking/config `intervalSeconds`, default 30),
  /// cached in prefs so the background isolate uses it too. Dense enough that the
  /// day route's leg km (backend) follows the road instead of 5-minute chords.
  static int _intervalSeconds = _kDefaultIntervalSeconds;
  static const int _kDefaultIntervalSeconds = 30;
  static const String _kPresenceIntervalSec = 'presence_capture_interval_sec';

  /// Interval for inserting presence tracking into DB (trackings collection).
  /// Applied to both foreground timer and native Android background tracker.
  ///
  /// Live tracking checks the position every 30 s (never less often), however
  /// long the admin's save interval is; points within [_duplicateLocationThresholdMeters]
  /// of the last sent one are not sent at all (idle = no new points).
  static Duration get trackingInterval =>
      Duration(seconds: _intervalSeconds < _kLiveCheckSeconds ? _intervalSeconds : _kLiveCheckSeconds);
  static const int _kLiveCheckSeconds = 30;

  static Future<void> _loadIntervalFromPrefs([SharedPreferences? p]) async {
    final prefs = p ?? await SharedPreferences.getInstance();
    final v = prefs.getInt(_kPresenceIntervalSec);
    if (v != null && v >= 10 && v <= 300) _intervalSeconds = v;
  }
  /// A fix within this distance of the last sent point is "same place" and is
  /// never sent — not even periodically — so an idle employee adds no points.
  static const double _duplicateLocationThresholdMeters = 15;

  static const double defaultOfficeRadiusMeters = 200;
  static const double _maxAccuracyBufferM = 80;
  static AndroidConfig get _presenceBackgroundConfig => AndroidConfig(
        notificationIcon: 'ic_stat_ektahr',
        notificationBody: 'Attendance presence tracking active. Tap to open.',
        channelName: 'Presence Tracking',
        cancelTrackingActionText: 'Stop tracking',
        // Tracking runs from punch-in to punch-out; the employee cannot switch it off here.
        enableCancelTrackingAction: false,
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

  Future<bool> _hasInternetConnection() async {
    try {
      final probe = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 5),
        ),
      );
      final url = AppConstants.baseUrl.replaceAll(RegExp(r'/$'), '');
      await probe.get<dynamic>(url);
      return true;
    } on DioException catch (e) {
      final type = e.type;
      if (type == DioExceptionType.connectionError ||
          type == DioExceptionType.connectionTimeout ||
          type == DioExceptionType.receiveTimeout ||
          type == DioExceptionType.sendTimeout) {
        return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Suppresses bursty duplicate uploads when the fix is almost the same, but still allows
  /// one row per [trackingInterval] while checked in (otherwise background/foreground never
  /// writes when you stay near the last point — typical at a desk or small GPS drift).
  /// Walking pace (~5 km/h). At or above this the employee is genuinely moving,
  /// so the point is kept to draw the trip — only a near-stationary fix is "same place".
  static const double _movingSpeedMps = 1.4;

  /// Whether a movement type means the employee is in motion (keep the point).
  static bool _isMovingMovementType(String? mt) {
    if (mt == null) return false;
    final m = mt.toLowerCase();
    return m.contains('driv') || m.contains('walk') || m.contains('moving');
  }

  Future<bool> _shouldSkipPresenceSend(
    double lat,
    double lng, {
    String logLabel = 'presence_store',
    bool moving = false,
  }) async {
    // Genuinely moving (driving/walking): keep every point so the route draws the real
    // path, even when two fixes land within 15 m of each other. Idle is still neglected.
    if (moving) return false;

    final prefs = await SharedPreferences.getInstance();
    await _loadIntervalFromPrefs(prefs);
    final lastLat = prefs.getDouble(_kPresenceLastSentLat);
    final lastLng = prefs.getDouble(_kPresenceLastSentLng);
    if (lastLat == null || lastLng == null) return false;

    final distanceM = gl.Geolocator.distanceBetween(lastLat, lastLng, lat, lng);
    if (distanceM >= _duplicateLocationThresholdMeters) return false;

    // Same place (within 15 m): neglect it, however long since the last point.
    final lastSentMs = prefs.getInt(_kPresenceLastSentTime) ?? 0;
    final elapsedMs = DateTime.now().millisecondsSinceEpoch - lastSentMs;
    if (kDebugMode && AppConstants.logTrackingsToConsole) {
      debugPrint(
        '[Trackings] $logLabel duplicate_check '
        'lastLat=${lastLat.toStringAsFixed(6)} lastLng=${lastLng.toStringAsFixed(6)} '
        'currentLat=${lat.toStringAsFixed(6)} currentLng=${lng.toStringAsFixed(6)} '
        'distance=${distanceM.toStringAsFixed(2)}m '
        'threshold=${_duplicateLocationThresholdMeters.toStringAsFixed(1)}m '
        'elapsedSinceSuccess=${(elapsedMs / 1000).toStringAsFixed(0)}s '
        'decision=skip',
      );
    }
    return true;
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
      await prefs.remove(_kPresencePinnedGeofenceLocation);
      await _clearPresenceAddressCache(prefs);
    }
  }

  static Future<void> _clearPresenceAddressCache(SharedPreferences prefs) async {
    await prefs.remove(_kPresenceAddrLat);
    await prefs.remove(_kPresenceAddrLng);
    await prefs.remove(_kPresenceAddrJson);
    await prefs.remove(_kPresenceAddrAtMs);
  }

  /// Address label for a presence point. Reuses the last resolved address until the staff
  /// member has moved [LiveTrackingService.trackingAddressMinMoveM] and
  /// [LiveTrackingService.trackingAddressMinInterval] has passed. Uses the phone's own
  /// geocoder ([AddressResolutionService.reverseGeocodeForTracking]) — never Google per point.
  /// Prefs-only, so it also works in the background isolate.
  static Future<Map<String, String?>> _resolvePresenceAddress(
    SharedPreferences prefs,
    double lat,
    double lng,
  ) async {
    Map<String, String?> cached = const {};
    final raw = prefs.getString(_kPresenceAddrJson);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          cached = decoded.map(
            (k, v) => MapEntry(k.toString(), v?.toString()),
          );
        }
      } catch (_) {}
    }
    final cachedLat = prefs.getDouble(_kPresenceAddrLat);
    final cachedLng = prefs.getDouble(_kPresenceAddrLng);
    if (cachedLat != null &&
        cachedLng != null &&
        (cached['fullAddress'] ?? '').isNotEmpty) {
      final moved = gl.Geolocator.distanceBetween(cachedLat, cachedLng, lat, lng);
      final sinceMs = DateTime.now().millisecondsSinceEpoch -
          (prefs.getInt(_kPresenceAddrAtMs) ?? 0);
      if (moved < LiveTrackingService.trackingAddressMinMoveM ||
          sinceMs < LiveTrackingService.trackingAddressMinInterval.inMilliseconds) {
        return cached;
      }
    }
    final resolved =
        await AddressResolutionService.reverseGeocodeForTracking(lat, lng);
    if (resolved == null || resolved.formattedAddress.isEmpty) return cached;
    final fresh = <String, String?>{
      'address': resolved.formattedAddress,
      'fullAddress': resolved.formattedAddress,
      'city': resolved.city ?? resolved.state,
      'area': resolved.area,
      'pincode': resolved.pincode,
    };
    await prefs.setDouble(_kPresenceAddrLat, lat);
    await prefs.setDouble(_kPresenceAddrLng, lng);
    await prefs.setString(_kPresenceAddrJson, jsonEncode(fresh));
    await prefs.setInt(
      _kPresenceAddrAtMs,
      DateTime.now().millisecondsSinceEpoch,
    );
    return fresh;
  }

  /// [discardOfflineQueue]: also delete points not yet uploaded. Only on logout - after a
  /// punch-out they are still this user's shift and upload when the app is next online.
  Future<void> clearTrackingAllowed({bool discardOfflineQueue = false}) async {
    final prefs = await SharedPreferences.getInstance();
    await TrackingOutlierFilterService.clearScope(
      TrackingOutlierFilterService.presenceScope,
    );
    await prefs.remove(_kPresenceTrackingDate);
    await prefs.remove(_kPresenceBackgroundEnabled);
    await prefs.remove(_kPresenceAppLifecycleState);
    if (discardOfflineQueue) await _savePendingQueue(const []);
    await prefs.remove(_kPresenceLastSentLat);
    await prefs.remove(_kPresenceLastSentLng);
    await prefs.remove(_kPresenceLastSentTime);
    await prefs.remove(_kPresenceLastBackgroundAttemptTime);
    await prefs.remove(_kPresenceLastMovementType);
    await prefs.remove(_kPresenceConsecutiveLowSpeed);
    await prefs.remove(_kPresencePinnedGeofenceLocation);
    await _clearPresenceAddressCache(prefs);
  }

  Future<void> _clearPinnedOfficeZone() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPresencePinnedGeofenceLocation);
  }

  /// Pins one geofence zone from [AttendanceTemplateStore] branch data using check-in coordinates.
  /// Later presence pings compare only this zone (not every location every time).
  Future<void> pinOfficeZoneAtCheckIn(
    double checkInLat,
    double checkInLng,
  ) async {
    if (checkInLat == 0 && checkInLng == 0) {
      await _clearPinnedOfficeZone();
      return;
    }
    final details = await AttendanceTemplateStore.loadTemplateDetails();
    final branchRaw = details?['branch'];
    if (branchRaw is! Map) {
      await _clearPinnedOfficeZone();
      return;
    }
    final branch = Map<String, dynamic>.from(branchRaw);
    final geofenceRaw = branch['geofence'];
    if (geofenceRaw is! Map) {
      await _clearPinnedOfficeZone();
      return;
    }
    final geofence = Map<String, dynamic>.from(geofenceRaw);
    if (geofence['enabled'] != true) {
      await _clearPinnedOfficeZone();
      return;
    }

    String? extractLocId(Map<String, dynamic> loc) {
      final idObj = loc['_id'];
      if (idObj is Map) {
        final im = Map<String, dynamic>.from(idObj);
        if (im[r'$oid'] != null) return im[r'$oid'].toString();
      }
      if (idObj != null) return idObj.toString();
      return null;
    }

    final locations = geofence['locations'];
    if (locations is List && locations.isNotEmpty) {
      for (final item in locations) {
        if (item is! Map) continue;
        final loc = Map<String, dynamic>.from(item);
        final plat = (loc['latitude'] as num?)?.toDouble();
        final plng = (loc['longitude'] as num?)?.toDouble();
        final radius =
            (loc['radius'] as num?)?.toDouble() ?? defaultOfficeRadiusMeters;
        if (plat == null || plng == null) continue;
        final distM = gl.Geolocator.distanceBetween(
          checkInLat,
          checkInLng,
          plat,
          plng,
        );
        if (distM <= radius) {
          final id = extractLocId(loc) ?? '';
          final payload = <String, dynamic>{
            'id': id,
            'latitude': plat,
            'longitude': plng,
            'radius': radius,
          };
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(
            _kPresencePinnedGeofenceLocation,
            jsonEncode(payload),
          );
          return;
        }
      }
    }

    final mainLat = (geofence['latitude'] as num?)?.toDouble();
    final mainLng = (geofence['longitude'] as num?)?.toDouble();
    final mainR =
        (geofence['radius'] as num?)?.toDouble() ?? defaultOfficeRadiusMeters;
    if (mainLat != null && mainLng != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _kPresencePinnedGeofenceLocation,
        jsonEncode(<String, dynamic>{
          'id': '__main__',
          'latitude': mainLat,
          'longitude': mainLng,
          'radius': mainR,
        }),
      );
    } else {
      await _clearPinnedOfficeZone();
    }
  }

  Future<Map<String, dynamic>?> _effectiveOfficeGeofence(
    Map<String, dynamic>? apiGeofence,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kPresencePinnedGeofenceLocation);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          final m = Map<String, dynamic>.from(decoded);
          final lat = (m['latitude'] as num?)?.toDouble();
          final lng = (m['longitude'] as num?)?.toDouble();
          final r = (m['radius'] as num?)?.toDouble();
          if (lat != null && lng != null && r != null) {
            return {'latitude': lat, 'longitude': lng, 'radius': r};
          }
        }
      } catch (_) {}
    }
    return apiGeofence;
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

  static String? _presenceStatusFromPinnedJson(
    String raw,
    double lat,
    double lng,
  ) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final m = Map<String, dynamic>.from(decoded);
      final plat = (m['latitude'] as num?)?.toDouble();
      final plng = (m['longitude'] as num?)?.toDouble();
      final r = (m['radius'] as num?)?.toDouble() ?? defaultOfficeRadiusMeters;
      if (plat == null || plng == null) return null;
      final distM = gl.Geolocator.distanceBetween(lat, lng, plat, plng);
      return distM <= r ? 'in_office' : 'out_of_office';
    } catch (_) {
      return null;
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
    // Background isolate: refresh the prefs cache so an active task is seen (see
    // LiveTrackingService.sendTrackingFromBackground).
    try {
      await (await SharedPreferences.getInstance()).reload();
    } catch (_) {}
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

    await _loadIntervalFromPrefs(prefs);
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final lastAttemptMs = prefs.getInt(_kPresenceLastBackgroundAttemptTime);
    if (lastAttemptMs != null &&
        lastAttemptMs > 0 &&
        (nowMs - lastAttemptMs) < trackingInterval.inMilliseconds) {
      return;
    }
    await prefs.setInt(_kPresenceLastBackgroundAttemptTime, nowMs);
    if (await self._shouldSkipPresenceSend(
      lat,
      lng,
      logLabel: 'presence_store_bg',
      moving: speedMps != null && speedMps.isFinite && speedMps >= _movingSpeedMps,
    )) {
      if (kDebugMode && AppConstants.logTrackingsToConsole) {
        debugPrint(
          '[Trackings] presence_store_bg SKIP duplicate '
          'lat=${lat.toStringAsFixed(6)} lng=${lng.toStringAsFixed(6)}',
        );
      }
      return;
    }

    // baseUrl is a compile-time constant and the token was read after prefs.reload(), so
    // this works in the background isolate without the foreground ApiClient.
    final baseUrl = AppConstants.baseUrl.replaceAll(RegExp(r'/$'), '');
    final uri = Uri.parse('$baseUrl$_kPresenceRecordPath');
    final capturedAt = DateTime.now().toUtc();
    final body = <String, dynamic>{
      'lat': lat,
      'lng': lng,
      'latitude': lat,
      'longitude': lng,
      'status': 'active',
      'appStatus': await _getLifecycleAppStatusForBackgroundInsert(),
      'timestamp': capturedAt.toIso8601String(),
    };
    String? presenceStatus;
    final pinnedRaw = prefs.getString(_kPresencePinnedGeofenceLocation);
    if (pinnedRaw != null && pinnedRaw.isNotEmpty) {
      presenceStatus = _presenceStatusFromPinnedJson(pinnedRaw, lat, lng);
    }
    if (presenceStatus == null) {
      final gf = await self._branchGeofenceFromTemplate();
      presenceStatus = self._isInsideOffice(lat, lng, gf, accuracyM: accuracyM ?? 0)
          ? 'in_office'
          : 'out_of_office';
    }
    // Always explicit: without a taskId the backend defaults to 'in_office'.
    body['presenceStatus'] = presenceStatus;
    if (batteryPercent != null) body['batteryPercent'] = batteryPercent;
    if (speedMps != null && speedMps.isFinite && speedMps >= 0) {
      body['speed'] = speedMps;
    }
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
    final addr = await _resolvePresenceAddress(prefs, lat, lng);
    for (final k in const ['address', 'fullAddress', 'city', 'area', 'pincode']) {
      final v = addr[k];
      if (v != null && v.isNotEmpty) body[k] = v;
    }
    Future<void> enqueueBackgroundFailure() async {
      await self._enqueueFailedPeriodicPresence(
        lat: lat,
        lng: lng,
        presenceStatus: (body['presenceStatus'] as String?) ?? 'out_of_office',
        status: 'offline',
        appStatus: 'offline',
        movementType: resolvedMovementType,
        accuracy: accuracyM,
        batteryPercent: batteryPercent,
        address: addr['address'],
        fullAddress: addr['fullAddress'],
        city: addr['city'],
        area: addr['area'],
        pincode: addr['pincode'],
        capturedAtUtc: capturedAt,
      );
    }

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
        await enqueueBackgroundFailure();
        if (kDebugMode && AppConstants.logTrackingsToConsole) {
          debugPrint(
            '[Trackings] presence_store_bg FAIL ${response.statusCode} '
            'lat=$lat lng=$lng status=${body['status']} '
            'appStatus=${body['appStatus']} movement=${body['movementType']} '
            'body=${response.body}',
          );
          debugPrint(
            '[Trackings] presence_store_bg queued_offline '
            'lat=${lat.toStringAsFixed(6)} lng=${lng.toStringAsFixed(6)}',
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
        // Internet just recovered in background: immediately flush older queued rows.
        await self.flushPendingPresenceQueue();
      }
    } catch (e) {
      await enqueueBackgroundFailure();
      if (kDebugMode && AppConstants.logTrackingsToConsole) {
        debugPrint(
          '[Trackings] presence_store_bg error status=${body['status']} '
          'appStatus=${body['appStatus']} movement=${body['movementType']}: $e',
        );
        debugPrint(
          '[Trackings] presence_store_bg queued_offline '
          'lat=${lat.toStringAsFixed(6)} lng=${lng.toStringAsFixed(6)}',
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

    // Tracking started on the punch-in day ends at noon the next day: an overnight
    // shift is still tracked past midnight, but a shift left open (no punch-out) no
    // longer keeps tracking for days. (Was disabled "for testing", so open shifts
    // tracked indefinitely.)
    final trackingEndsAt = DateTime(year, month, day + 1, 12);
    if (DateTime.now().isAfter(trackingEndsAt)) {
      await prefs.remove(_kPresenceTrackingDate);
      return false;
    }
    return true;
  }

  /// Call after PUNCH IN / PUNCH OUT and whenever API / prefs show the punch state
  /// (dashboard load, app restart). Punched in + staff `tracking` flag on => day tracking
  /// runs; otherwise it is stopped. Calls are serialized so the concurrent punch-in and
  /// nav-refresh calls don't both start timers / fetch the profile.
  Future<void> ensureTrackingIfPunchedIn(bool isPunchedInToday) async {
    while (_ensureInFlight != null) {
      try {
        await _ensureInFlight;
      } catch (_) {}
    }
    final run = _ensureTrackingImpl(isPunchedInToday);
    _ensureInFlight = run;
    try {
      await run;
    } finally {
      if (identical(_ensureInFlight, run)) _ensureInFlight = null;
    }
  }

  Future<void> _ensureTrackingImpl(bool isPunchedInToday) async {
    if (!isPunchedInToday) {
      await stopTracking();
      return;
    }

    final enabled = await isTimelineTrackingEnabled(maxAge: _flagMaxAgeOnEnsure);
    if (!enabled) {
      if (kDebugMode) {
        debugPrint(
          '[PresenceTracking] not tracking: timeline tracking disabled for this staff',
        );
      }
      await stopTracking();
      return;
    }

    await setTrackingAllowed();
    await _schedulePresenceSends();
  }

  /// Reads the admin-controlled `Staff.tracking` flag from GET /staff/profile (raw Staff
  /// document). Refetches the profile unless the flag was read within [maxAge]; when the
  /// profile cannot be fetched (offline) the last known value is used. Absent => false.
  Future<bool> isTimelineTrackingEnabled({
    Duration maxAge = _flagMaxAgeOnEnsure,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await _loadIntervalFromPrefs(prefs);
    final cached = prefs.getBool(_kPresenceTrackingFlag);
    final checkedAt = prefs.getInt(_kPresenceTrackingFlagCheckedAt) ?? 0;
    final ageMs = DateTime.now().millisecondsSinceEpoch - checkedAt;
    if (cached != null &&
        checkedAt > 0 &&
        ageMs >= 0 &&
        ageMs < maxAge.inMilliseconds) {
      return cached;
    }
    try {
      final res = await AuthService().getProfile(forceRefresh: true);
      if (res['success'] == true) {
        // Timeline Tracking (Staff.tracking) OR Live Tracking (HRMS Geo config:
        // global switch AND this employee), plus the admin's capture interval.
        var enabled = _trackingFlagFromProfile(res['data']) ?? false;
        try {
          await _setToken();
          final cfgRes = await _api.dio.get<dynamic>('/staff/geo-task/live-tracking/config');
          final cfg = cfgRes.data is Map ? (cfgRes.data as Map)['data'] : null;
          if (cfg is Map) {
            if (cfg['liveTracking'] == true) enabled = true;
            final iv = (cfg['intervalSeconds'] as num?)?.toInt();
            if (iv != null && iv >= 10 && iv <= 300) {
              _intervalSeconds = iv;
              await prefs.setInt(_kPresenceIntervalSec, iv);
            }
          }
        } catch (_) {
          // Older backend without the config route: keep the profile flag.
        }
        await prefs.setBool(_kPresenceTrackingFlag, enabled);
        await prefs.setInt(
          _kPresenceTrackingFlagCheckedAt,
          DateTime.now().millisecondsSinceEpoch,
        );
        return enabled;
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[PresenceTracking] profile fetch for tracking flag failed: $e');
      }
    }
    return cached ?? false;
  }

  static bool? _trackingFlagFromProfile(dynamic data) {
    bool? read(dynamic m) {
      if (m is! Map) return null;
      // HRMSbackend renamed Staff.tracking -> Staff.timelineTracking; older
      // records may still carry only the old field.
      final v = m['timelineTracking'] ?? m['tracking'];
      if (v is bool) return v;
      if (v is String) return v.toLowerCase() == 'true';
      if (v is num) return v != 0;
      return null;
    }

    if (data is! Map) return null;
    return read(data) ?? read(data['staff']) ?? read(data['staffData']);
  }

  /// canTrack = staff `tracking` flag; branchGeofence from the cached attendance template
  /// (used only to label points in_office / out_of_office).
  Future<Map<String, dynamic>> getPresenceStatus({
    Duration flagMaxAge = _flagMaxAgeWhileTracking,
  }) async {
    final enabled = await isTimelineTrackingEnabled(maxAge: flagMaxAge);
    if (!enabled) {
      return {
        'canTrack': false,
        'reason': 'tracking_disabled_for_staff',
        'branchGeofence': null,
      };
    }
    return {
      'canTrack': true,
      'reason': null,
      'branchGeofence': await _branchGeofenceFromTemplate(),
    };
  }

  /// Builds the branch geofence targets from [AttendanceTemplateStore].
  Future<Map<String, dynamic>?> _branchGeofenceFromTemplate() async {
    final details = await AttendanceTemplateStore.loadTemplateDetails();
    final branchRaw = details?['branch'];
    if (branchRaw is! Map) return null;
    return _geofencePayloadFromBranchMap(Map<String, dynamic>.from(branchRaw));
  }

  /// Mirrors server `getBranchGeofenceTargets`: `locations[]`, single circle, or legacy branch lat/lng.
  Map<String, dynamic>? _geofencePayloadFromBranchMap(
    Map<String, dynamic> branch,
  ) {
    final geofenceRaw = branch['geofence'];
    Map<String, dynamic>? legacyFromTopLevel() {
      final legacyLat = (branch['latitude'] as num?)?.toDouble();
      final legacyLng = (branch['longitude'] as num?)?.toDouble();
      final legacyR =
          (branch['radius'] as num?)?.toDouble() ?? defaultOfficeRadiusMeters;
      if (legacyLat == null || legacyLng == null) return null;
      return {
        'enabled': true,
        'targets': [
          {'latitude': legacyLat, 'longitude': legacyLng, 'radius': legacyR},
        ],
        'latitude': legacyLat,
        'longitude': legacyLng,
        'radius': legacyR,
      };
    }

    if (geofenceRaw is! Map) {
      return legacyFromTopLevel();
    }
    final geofence = Map<String, dynamic>.from(geofenceRaw);
    if (geofence['enabled'] != true) {
      return legacyFromTopLevel();
    }

    final locations = geofence['locations'];
    if (locations is List && locations.isNotEmpty) {
      final targets = <Map<String, dynamic>>[];
      final fallbackR =
          (geofence['radius'] as num?)?.toDouble() ?? defaultOfficeRadiusMeters;
      for (final item in locations) {
        if (item is! Map) continue;
        final loc = Map<String, dynamic>.from(item);
        final plat = (loc['latitude'] as num?)?.toDouble();
        final plng = (loc['longitude'] as num?)?.toDouble();
        final r = (loc['radius'] as num?)?.toDouble() ?? fallbackR;
        if (plat == null || plng == null) continue;
        targets.add({'latitude': plat, 'longitude': plng, 'radius': r});
      }
      if (targets.isEmpty) return null;
      final t0 = targets.first;
      return {
        'enabled': true,
        'targets': targets,
        'latitude': t0['latitude'],
        'longitude': t0['longitude'],
        'radius': t0['radius'],
      };
    }

    final mainLat = (geofence['latitude'] as num?)?.toDouble();
    final mainLng = (geofence['longitude'] as num?)?.toDouble();
    final mainR =
        (geofence['radius'] as num?)?.toDouble() ?? defaultOfficeRadiusMeters;
    if (mainLat != null && mainLng != null) {
      return {
        'enabled': true,
        'targets': [
          {'latitude': mainLat, 'longitude': mainLng, 'radius': mainR},
        ],
        'latitude': mainLat,
        'longitude': mainLng,
        'radius': mainR,
      };
    }
    return legacyFromTopLevel();
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

    if (lastLat == null ||
        lastLng == null ||
        lastTimeMs == null ||
        lastTimeMs <= 0) {
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
      sensorSpeedKmh: (position.speed.isFinite && position.speed >= 0)
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
    final consecutiveLow = prefs.getInt(_kPresenceConsecutiveLowSpeed) ?? 0;
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
      elapsedSec =
          (DateTime.now().millisecondsSinceEpoch - lastTimeMs) / 1000.0;
    }

    final speedKmhFromSensor =
        (speedMps != null && speedMps.isFinite && speedMps >= 0)
        ? speedMps * 3.6
        : 0.0;

    if (accuracyM != null && accuracyM > kMaxAccuracyM) {
      return (
        movementType: lastMovement,
        consecutiveLowSpeed: lastMovement == kMovementStop
            ? (consecutiveLow + 1)
            : 0,
      );
    }

    if (lastLat == null ||
        lastLng == null ||
        lastTimeMs == null ||
        lastTimeMs <= 0 ||
        elapsedSec < kMovementHoldDuration.inSeconds) {
      return (
        movementType: lastMovement,
        consecutiveLowSpeed: lastMovement == kMovementStop
            ? (consecutiveLow + 1)
            : 0,
      );
    }

    final speedKmh = MovementClassificationService.speedKmhFromDistance(
      distanceM: distanceM,
      elapsedSeconds: elapsedSec,
    );
    final movementType =
        MovementClassificationService.classifyFromTrackingSignals(
          distanceM: distanceM,
          elapsedSeconds: elapsedSec,
          lastMovementType: lastMovement,
          sensorSpeedKmh:
              (speedMps != null && speedMps.isFinite && speedMps >= 0)
              ? speedMps * 3.6
              : null,
        );
    final nextConsecutive = movementType == kMovementStop
        ? (consecutiveLow + 1)
        : 0;

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

    return (movementType: movementType, consecutiveLowSpeed: nextConsecutive);
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
    final hasInternet = await _hasInternetConnection();
    final shouldBypassDuplicateCheck =
        !hasInternet || status == 'offline' || appStatus == 'offline';
    final movingNow = _isMovingMovementType(resolvedMovementType) ||
        _isMovingMovementType(movementType);
    if (!shouldBypassDuplicateCheck &&
        await _shouldSkipPresenceSend(lat, lng, logLabel: 'presence_store', moving: movingNow)) {
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
    if (shouldBypassDuplicateCheck &&
        kDebugMode &&
        AppConstants.logTrackingsToConsole) {
      debugPrint(
        '[Trackings] presence_store duplicate_check bypassed '
        'internet=${hasInternet ? "on" : "off"} '
        'status=${status ?? "-"} appStatus=${appStatus ?? "-"}',
      );
    }
    try {
      // No taskId: stored as a staff-level point; staffId/adminId come from the JWT.
      final body = <String, dynamic>{
        'lat': lat,
        'lng': lng,
        'latitude': lat,
        'longitude': lng,
        'presenceStatus': presenceStatus,
        'timestamp': capturedAt.toIso8601String(),
      };
      body['status'] =
          (status == 'active' || status == 'inactive' || status == 'offline')
          ? status
          : 'active';
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

      final response = await _api.dio.post<dynamic>(
        _kPresenceRecordPath,
        data: body,
      );
      final savedId = response.data is Map
          ? ((response.data as Map)['data'] is Map
                ? ((response.data as Map)['data'] as Map)['_id']
                : null)
          : null;
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
          'acc=${accuracy?.toStringAsFixed(1) ?? "—"}m '
          'savedId=${savedId ?? "-"}',
        );
      }
      return (
        result: _PresenceSendResult.sent,
        movementType: resolvedMovementType,
      );
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
      return (
        result: _PresenceSendResult.failed,
        movementType: resolvedMovementType,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[PresenceTracking] store error: $e');
      return (
        result: _PresenceSendResult.failed,
        movementType: resolvedMovementType,
      );
    }
  }

  /// Offline points live in a file, not SharedPreferences: the queue can hold a full day
  /// (thousands of rows), and the background isolate and the app both read/write it.
  static Future<File> _pendingQueueFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$_kPresencePendingQueue.json');
  }

  Future<List<Map<String, dynamic>>> _loadPendingQueue() async {
    String? raw;
    try {
      final file = await _pendingQueueFile();
      if (await file.exists()) raw = await file.readAsString();
    } catch (_) {}
    if (raw == null) {
      // Rows queued by an older build, before the file existed.
      final prefs = await SharedPreferences.getInstance();
      raw = prefs.getString(_kPresencePendingQueue);
    }
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      final out = <Map<String, dynamic>>[];
      for (final e in decoded) {
        if (e is Map) {
          out.add(
            Map<String, dynamic>.from(
              e.map((k, v) => MapEntry(k.toString(), v)),
            ),
          );
        }
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  Future<void> _savePendingQueue(List<Map<String, dynamic>> list) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPresencePendingQueue); // migrated to the file
    try {
      final file = await _pendingQueueFile();
      if (list.isEmpty) {
        if (await file.exists()) await file.delete();
        return;
      }
      // Write-then-rename, so a kill mid-write never leaves a half-written queue.
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(jsonEncode(list), flush: true);
      await tmp.rename(file.path);
    } catch (e) {
      if (kDebugMode) debugPrint('[PresenceTracking] save offline queue failed: $e');
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
    final queueBefore = list.length;
    // Standing still adds nothing new: skip a point within _minQueueMoveM of the last queued
    // one with the same movement (the server would not save it either). A status change is
    // always kept, so idle start/end survive offline.
    if (list.isNotEmpty) {
      final last = list.last;
      final lastLat = (last['lat'] as num?)?.toDouble();
      final lastLng = (last['lng'] as num?)?.toDouble();
      if (lastLat != null &&
          lastLng != null &&
          last['movementType'] == movementType &&
          gl.Geolocator.distanceBetween(lastLat, lastLng, lat, lng) < _minQueueMoveM) {
        return;
      }
    }
    if (kDebugMode && AppConstants.logTrackingsToConsole) {
      debugPrint(
        '[Trackings] presence_offline local_insert_prepare '
        'lat=${lat.toStringAsFixed(6)} lng=${lng.toStringAsFixed(6)} '
        'presence=$presenceStatus appStatus=${appStatus ?? "-"} '
        'queue_before=$queueBefore',
      );
    }
    list.add({
      'lat': lat,
      'lng': lng,
      'presenceStatus': presenceStatus,
      'status': 'offline',
      if (appStatus != null && appStatus.isNotEmpty) 'appStatus': appStatus,
      if (movementType != null && movementType.isNotEmpty)
        'movementType': movementType,
      if (accuracy != null) 'accuracy': accuracy,
      if (batteryPercent != null) 'batteryPercent': batteryPercent,
      if (address != null && address.isNotEmpty) 'address': address,
      if (fullAddress != null && fullAddress.isNotEmpty)
        'fullAddress': fullAddress,
      if (city != null && city.isNotEmpty) 'city': city,
      if (area != null && area.isNotEmpty) 'area': area,
      if (pincode != null && pincode.isNotEmpty) 'pincode': pincode,
      'timestamp': capturedAtUtc.toIso8601String(),
    });
    while (list.length > _maxPendingPresence) {
      list = list.sublist(list.length - _maxPendingPresence);
    }
    await _savePendingQueue(list);
    if (kDebugMode && AppConstants.logTrackingsToConsole) {
      debugPrint(
        '[Trackings] presence_offline local_insert_done '
        'queue_after=${list.length}',
      );
      _localOfflineInsertCount += 1;
      debugPrint('****LOCAL-OFFLINE INSERT $_localOfflineInsertCount');
    }
  }

  /// Replay locally stored periodic presence points (e.g. after offline). Call on app resume.
  /// Not gated on being punched in: points from a shift that ended while offline still
  /// belong to it - the server accepts each one by its own time (inside the shift).
  Future<void> flushPendingPresenceQueue() async {
    if (_taskInProgress) return;

    var list = await _loadPendingQueue();
    if (list.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token == null || token.isEmpty) return; // logged out: wait for this user's login
    if (kDebugMode && AppConstants.logTrackingsToConsole) {
      debugPrint(
        '[Trackings] presence_offline flush_start pending=${list.length}',
      );
    }

    if (_flushInProgress) return;
    _flushInProgress = true;
    try {
      // Queued rows were already outlier-filtered before being queued; replay them in
      // one request (POST /staff/geo-task/live-tracking/batch, no taskId).
      String keyOf(Map<String, dynamic> m) =>
          '${m['timestamp']}|${m['lat']}|${m['lng']}';
      final sentKeys = <String>{};
      final rows = <(String, Map<String, dynamic>)>[];
      for (final m in list) {
        final lat = (m['lat'] as num?)?.toDouble();
        final lng = (m['lng'] as num?)?.toDouble();
        final ts = m['timestamp'] as String?;
        if (lat == null || lng == null || ts == null) {
          sentKeys.add(keyOf(m)); // unusable row: drop it
          continue;
        }
        rows.add((
          keyOf(m),
          {
            ...m,
            'latitude': lat,
            'longitude': lng,
            'presenceStatus':
                (m['presenceStatus'] as String?) ?? 'out_of_office',
            'status': (m['status'] as String?) ?? 'offline',
          },
        ));
      }

      // Oldest first, _flushBatchSize per request; stop at the first failure so the rest
      // stays queued for the next attempt.
      if (rows.isNotEmpty) await _setToken();
      for (var i = 0; i < rows.length; i += _flushBatchSize) {
        final chunk = rows.sublist(i, (i + _flushBatchSize).clamp(0, rows.length));
        try {
          await _api.dio.post<dynamic>(
            _kPresenceBatchPath,
            data: {'points': chunk.map((r) => r.$2).toList()},
          );
          sentKeys.addAll(chunk.map((r) => r.$1));
          if (kDebugMode && AppConstants.logTrackingsToConsole) {
            _offlineSendingCount += chunk.length;
            debugPrint(
              '[Trackings] presence_offline flush_batch OK sent=${chunk.length} '
              'total=$_offlineSendingCount',
            );
          }
        } on DioException catch (e) {
          // 400 = nothing valid in the payload; retrying would never succeed.
          if (e.response?.statusCode == 400) {
            sentKeys.addAll(chunk.map((r) => r.$1));
            continue;
          }
          if (kDebugMode && AppConstants.logTrackingsToConsole) {
            debugPrint(
              '[Trackings] presence_offline flush_batch FAIL '
              '${e.response?.statusCode} → ${e.response?.data}',
            );
          }
          break;
        } catch (e) {
          if (kDebugMode) debugPrint('[PresenceTracking] flush error: $e');
          break;
        }
      }
      if (sentKeys.isNotEmpty) {
        // Re-read: rows queued while the request was in flight must survive.
        final current = await _loadPendingQueue();
        final remaining = current
            .where(
              (m) =>
                  !sentKeys.contains(keyOf(m)) &&
                  m['timestamp'] != null &&
                  m['lat'] is num &&
                  m['lng'] is num,
            )
            .toList();
        await _savePendingQueue(remaining);
      }
    } finally {
      _flushInProgress = false;
    }
  }

  bool _isInsideOffice(
    double lat,
    double lng,
    Map<String, dynamic>? branchGeofence, {
    double accuracyM = 0,
  }) {
    if (branchGeofence == null) return false;
    final buffer = accuracyM > 0
        ? (accuracyM > _maxAccuracyBufferM ? _maxAccuracyBufferM : accuracyM)
        : 0.0;

    final targetsRaw = branchGeofence['targets'];
    if (targetsRaw is List && targetsRaw.isNotEmpty) {
      for (final item in targetsRaw) {
        if (item is! Map) continue;
        final m = Map<String, dynamic>.from(item);
        final plat = (m['latitude'] as num?)?.toDouble();
        final plng = (m['longitude'] as num?)?.toDouble();
        final radius =
            (m['radius'] as num?)?.toDouble() ?? defaultOfficeRadiusMeters;
        if (plat == null || plng == null) continue;
        final distM = gl.Geolocator.distanceBetween(lat, lng, plat, plng);
        if (distM <= radius + buffer) return true;
      }
      return false;
    }

    final officeLat = (branchGeofence['latitude'] as num?)?.toDouble();
    final officeLng = (branchGeofence['longitude'] as num?)?.toDouble();
    final radius =
        (branchGeofence['radius'] as num?)?.toDouble() ??
        defaultOfficeRadiusMeters;

    if (officeLat == null || officeLng == null) return false;

    final distM = gl.Geolocator.distanceBetween(lat, lng, officeLat, officeLng);
    return distM <= radius + buffer;
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
    final addr = await _resolvePresenceAddress(
      await SharedPreferences.getInstance(),
      lat,
      lng,
    );
    final movementType = await _classifyForegroundMovement(position);

    final effectiveGf = await _effectiveOfficeGeofence(gf);
    final presenceStatus =
        _isInsideOffice(lat, lng, effectiveGf, accuracyM: accuracy)
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
      address: addr['address'],
      fullAddress: addr['fullAddress'],
      city: addr['city'],
      area: addr['area'],
      pincode: addr['pincode'],
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
        address: addr['address'],
        fullAddress: addr['fullAddress'],
        city: addr['city'],
        area: addr['area'],
        pincode: addr['pincode'],
        capturedAtUtc: capturedAt,
      );
    }
    if (kDebugMode) {
      debugPrint(
        '[PresenceTracking] tick presence=$presenceStatus movement=${outcome.movementType} '
        'result=${outcome.result == _PresenceSendResult.sent
            ? "ok"
            : outcome.result == _PresenceSendResult.skipped
            ? "skip"
            : "fail"}',
      );
    }
    if (outcome.result == _PresenceSendResult.sent) {
      await _persistPresenceMovementState(
        lat,
        lng,
        movementType: outcome.movementType,
        consecutiveLowSpeed: outcome.movementType == kMovementStop
            ? MovementClassificationService().consecutiveLowSpeedCount
            : 0,
        recordedAt: capturedAt,
      );
      // If internet just recovered, flush older offline rows immediately.
      await flushPendingPresenceQueue();
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
      // Keep replaying pending offline rows every minute while tracking is active.
      await flushPendingPresenceQueue();
      final status = await getPresenceStatus();
      if (status['canTrack'] != true) {
        if (kDebugMode) {
          debugPrint('[PresenceTracking] periodic check cannot track: ${status['reason']}');
        }
        await stopTracking();
        return;
      }
      final gf = status['branchGeofence'] as Map<String, dynamic>?;
      await _tick(gf);
    } finally {
      _periodicTickInProgress = false;
    }
  }

  /// First send + periodic uploads: one point every [trackingInterval] while checked in.
  Future<void> _schedulePresenceSends() async {
    if (_taskInProgress) return;
    if (!await isTrackingAllowed()) return;

    if (_isTracking && _trackingTimer != null) {
      // Already running (e.g. dashboard reload after punch in): keep the current timer
      // instead of forcing an extra GPS fix + upload.
      await _ensureBackgroundPresenceTracking();
      unawaited(TrackingHealthService.instance.start());
      return;
    }

    _isTracking = true;
    // From punch-in on, alert the employee if the phone blocks tracking.
    unawaited(TrackingHealthService.instance.start());
    await MovementClassificationService().start();
    await flushPendingPresenceQueue();
    await _ensureBackgroundPresenceTracking();
    try {
      final status = await getPresenceStatus();
      if (status['canTrack'] != true) {
        if (kDebugMode) debugPrint('[PresenceTracking] initial status cannot track: ${status['reason']}');
        await stopTracking();
        return;
      }
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
      debugPrint(
        '[PresenceTracking] timer started (interval: ${trackingInterval.inSeconds} s)',
      );
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
      final addr = await _resolvePresenceAddress(
        await SharedPreferences.getInstance(),
        position.latitude,
        position.longitude,
      );
      final movementType = await _classifyForegroundMovement(position);
      final effectiveGf = await _effectiveOfficeGeofence(
        await _branchGeofenceFromTemplate(),
      );
      final presenceStatus =
          _isInsideOffice(
            position.latitude,
            position.longitude,
            effectiveGf,
            accuracyM: position.accuracy,
          )
          ? 'in_office'
          : 'out_of_office';

      final outcome = await _sendPresence(
        lat: position.latitude,
        lng: position.longitude,
        presenceStatus: presenceStatus,
        status: 'active',
        appStatus: 'active',
        movementType: movementType,
        accuracy: position.accuracy,
        batteryPercent: batteryPercent,
        address: addr['address'],
        fullAddress: addr['fullAddress'],
        city: addr['city'],
        area: addr['area'],
        pincode: addr['pincode'],
      );
      if (kDebugMode) {
        debugPrint(
          '[PresenceTracking] recordAppOpened: active, presence=$presenceStatus '
          'result=${outcome.result == _PresenceSendResult.sent
              ? "ok"
              : outcome.result == _PresenceSendResult.skipped
              ? "skip"
              : "fail"} '
          'movement=${outcome.movementType}',
        );
      }
      if (outcome.result == _PresenceSendResult.sent) {
        await _persistPresenceMovementState(
          position.latitude,
          position.longitude,
          movementType: outcome.movementType,
          consecutiveLowSpeed: outcome.movementType == kMovementStop
              ? MovementClassificationService().consecutiveLowSpeedCount
              : 0,
        );
      }
    } catch (e) {
      if (kDebugMode)
        debugPrint('[PresenceTracking] recordAppOpened failed: $e');
    }
  }

  Future<void> recordAppClosed() async {
    if (_sendingAppClosed) return;
    if (_taskInProgress) return;
    if (!await isTrackingAllowed()) return;

    _sendingAppClosed = true;
    await markAppClosed();
    try {
      final effectiveGf = await _effectiveOfficeGeofence(
        await _branchGeofenceFromTemplate(),
      );
      final position = await _capturePresencePosition();
      int? batteryPercent;
      try {
        batteryPercent = await Battery().batteryLevel;
      } catch (_) {}
      final addr = await _resolvePresenceAddress(
        await SharedPreferences.getInstance(),
        position.latitude,
        position.longitude,
      );
      final presenceStatus =
          _isInsideOffice(
            position.latitude,
            position.longitude,
            effectiveGf,
            accuracyM: position.accuracy,
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
        address: addr['address'],
        fullAddress: addr['fullAddress'],
        city: addr['city'],
        area: addr['area'],
        pincode: addr['pincode'],
      );

      if (outcome.result == _PresenceSendResult.sent) {
        await _persistPresenceMovementState(
          position.latitude,
          position.longitude,
          movementType: outcome.movementType,
          consecutiveLowSpeed: outcome.movementType == kMovementStop
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
    // Points left over from a shift that ended while offline upload here too.
    if (!await isTrackingAllowed()) {
      await flushPendingPresenceQueue();
      return;
    }
    _isTracking = true;
    // Back from settings: clear or re-raise the tracking alert right away.
    unawaited(TrackingHealthService.instance.start());
    await flushPendingPresenceQueue();
    await _periodicTick();
    _trackingTimer?.cancel();
    _trackingTimer = Timer.periodic(trackingInterval, (_) {
      _periodicTick();
    });
  }

  /// Punch out / tracking disabled / logout: stop the timer and the native presence tracker
  /// (unless a task ride owns it) and clear the day's presence state.
  ///
  /// Points not yet uploaded are kept (they upload on the next app resume) unless
  /// [discardOfflineQueue] - pass it on logout, so they never go out under another login.
  Future<void> stopTracking({bool discardOfflineQueue = false}) async {
    // Best effort: upload offline-queued points now.
    try {
      await flushPendingPresenceQueue();
    } catch (_) {}
    _isTracking = false;
    _taskInProgress = false;
    _trackingTimer?.cancel();
    _trackingTimer = null;
    await TrackingHealthService.instance.stop();
    await MovementClassificationService().stop();
    await clearTrackingAllowed(discardOfflineQueue: discardOfflineQueue);
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
