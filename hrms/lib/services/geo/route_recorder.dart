// Records the route a staff member actually travels during a GEO task, densely
// enough to redraw it accurately (a point about every 10-15 m of real movement),
// and uploads it to HRMSbackend in batches (POST /staff/geo-task/live-tracking/batch).
//
// Why: the periodic tracking upload (every 30 s) leaves 150-300 m gaps at city
// speeds, so the drawn route cut across corners and blocks. The live GPS stream
// already gives a fix every few metres; this keeps the good ones.
//
// Points are persisted per task in SharedPreferences before upload, so an app
// restart or a network outage never loses the route — pending points are sent
// on the next flush.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart' as gl;
import 'package:shared_preferences/shared_preferences.dart';

import '../api_client.dart';

class RouteRecorder {
  RouteRecorder._();

  /// Fixes worse than this are GPS guesses (inside buildings, under cover).
  static const double maxAccuracyM = 25;

  /// Minimum real movement between kept points (filters standing-still jitter).
  static const double minMoveM = 10;

  /// A jump needing more than this speed is a GPS glitch, not travel.
  static const double maxSpeedKmh = 160;

  static const int _batchSize = 100;
  static const String _pendingPrefix = 'route_rec_pending_v1:';
  static const String _lastPrefix = 'route_rec_last_v1:';

  static final ApiClient _api = ApiClient();
  static final Map<String, Future<void>> _flushing = {};

  /// Offer a GPS fix for [taskId]. Returns true when it was kept.
  static Future<bool> add({
    required String taskId,
    required double lat,
    required double lng,
    double? accuracyM,
    double? speedMps,
    double? heading,
    String? movementType,
    DateTime? at,
  }) async {
    if (taskId.isEmpty || !_valid(lat, lng)) return false;
    if (accuracyM != null && accuracyM > maxAccuracyM) return false;
    final now = (at ?? DateTime.now()).toUtc();
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastRaw = prefs.getString('$_lastPrefix$taskId');
      if (lastRaw != null) {
        final last = jsonDecode(lastRaw) as Map<String, dynamic>;
        final lLat = (last['lat'] as num).toDouble();
        final lLng = (last['lng'] as num).toDouble();
        final lTs = DateTime.tryParse(last['ts']?.toString() ?? '');
        final moved = gl.Geolocator.distanceBetween(lLat, lLng, lat, lng);
        if (moved < minMoveM) return false;
        if (lTs != null) {
          final secs = now.difference(lTs).inMilliseconds / 1000.0;
          if (secs > 0 && (moved / secs) * 3.6 > maxSpeedKmh) return false;
        }
      }
      final point = <String, dynamic>{
        'taskId': taskId,
        'latitude': lat,
        'longitude': lng,
        if (accuracyM != null) 'accuracy': accuracyM,
        if (speedMps != null && speedMps.isFinite && speedMps >= 0) 'speed': speedMps,
        if (heading != null && heading.isFinite) 'heading': heading,
        'movementType': movementType ?? 'moving',
        'status': 'in_progress',
        'presenceStatus': 'task',
        'appStatus': 'active',
        'timestamp': now.toIso8601String(),
      };
      final key = '$_pendingPrefix$taskId';
      final pending = prefs.getStringList(key) ?? <String>[];
      pending.add(jsonEncode(point));
      await prefs.setStringList(key, pending);
      await prefs.setString(
        '$_lastPrefix$taskId',
        jsonEncode({'lat': lat, 'lng': lng, 'ts': now.toIso8601String()}),
      );
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('[RouteRecorder] add failed: $e');
      return false;
    }
  }

  /// Upload pending points for [taskId]. Safe to call often; concurrent calls
  /// for the same task share one upload.
  static Future<void> flush(String taskId) {
    if (taskId.isEmpty) return Future.value();
    final running = _flushing[taskId];
    if (running != null) return running;
    final future = _flush(taskId);
    _flushing[taskId] = future;
    future.whenComplete(() => _flushing.remove(taskId)).ignore();
    return future;
  }

  /// Upload pending points for every task (e.g. after the app restarts).
  static Future<void> flushAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ids = prefs
          .getKeys()
          .where((k) => k.startsWith(_pendingPrefix))
          .map((k) => k.substring(_pendingPrefix.length))
          .toList();
      for (final id in ids) {
        await flush(id);
      }
    } catch (_) {}
  }

  /// Forget the "last kept point" for [taskId] (call when a ride ends), so a
  /// later resume doesn't compare against a stale position.
  static Future<void> resetAnchor(String taskId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_lastPrefix$taskId');
    } catch (_) {}
  }

  static Future<void> _flush(String taskId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_pendingPrefix$taskId';
      var pending = prefs.getStringList(key) ?? <String>[];
      while (pending.isNotEmpty) {
        final chunk = pending.take(_batchSize).toList();
        final points = chunk.map((s) => jsonDecode(s)).toList();
        final token = prefs.getString('token')?.replaceAll('"', '');
        if (token == null || token.isEmpty) return;
        _api.setAuthToken(token);
        await _api.dio.post<dynamic>(
          '/staff/geo-task/live-tracking/batch',
          data: {'points': points},
        );
        // Re-read: new points may have been added while uploading.
        final latest = prefs.getStringList(key) ?? <String>[];
        pending = latest.length >= chunk.length
            ? latest.sublist(chunk.length)
            : <String>[];
        if (pending.isEmpty) {
          await prefs.remove(key);
        } else {
          await prefs.setStringList(key, pending);
        }
      }
    } catch (e) {
      // Offline or server error: points stay queued for the next flush.
      if (kDebugMode) debugPrint('[RouteRecorder] flush($taskId) deferred: $e');
    }
  }

  static bool _valid(double lat, double lng) {
    if (lat == 0 && lng == 0) return false;
    if (!lat.isFinite || !lng.isFinite) return false;
    return lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180;
  }
}
