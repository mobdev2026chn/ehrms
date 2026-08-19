// Builds the "exact" travelled route from raw GPS tracking points.
//
// Raw tracking points, drawn as straight segments, cut corners and show GPS
// jitter as zig-zags. This service (1) cleans the points (drops invalid/zero
// coordinates, near-duplicates and physically-impossible jumps) and then
// (2) snaps them to the road network via the Google Roads API
// (snapToRoads, interpolate=true) so the polyline follows the actual roads the
// person travelled. On any failure it falls back to the cleaned raw points so
// the map always shows something sensible.

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart' as gl;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import 'package:hrms/config/constants.dart';
import 'package:hrms/models/task.dart';

class RouteSnappingService {
  RouteSnappingService._();

  /// Roads API accepts at most 100 points per snapToRoads request.
  static const int _maxPointsPerRequest = 100;

  /// Drop a point if it is closer than this to the previous kept point.
  static const double _minSeparationMeters = 5;

  /// Reject a point as an outlier if reaching it would require this speed.
  static const double _maxPlausibleSpeedKmh = 200;

  /// Reject a jump this large when timestamps are missing (likely GPS glitch).
  static const double _maxJumpWithoutTimeMeters = 3000;

  /// Clean raw tracking points: drop invalid coordinates, near-duplicates and
  /// physically-impossible jumps, preserving chronological order.
  static List<LatLng> cleanPoints(List<RoutePoint> raw) {
    final cleaned = <LatLng>[];
    RoutePoint? lastKept;

    for (final p in raw) {
      if (!_isValidCoordinate(p.lat, p.lng)) continue;

      if (lastKept != null) {
        final distanceM = gl.Geolocator.distanceBetween(
          lastKept.lat,
          lastKept.lng,
          p.lat,
          p.lng,
        );
        if (distanceM < _minSeparationMeters) continue;

        final lastTime = lastKept.timestamp;
        final time = p.timestamp;
        if (lastTime != null && time != null) {
          final seconds = time.difference(lastTime).inMilliseconds / 1000.0;
          if (seconds > 0) {
            final speedKmh = (distanceM / seconds) * 3.6;
            if (speedKmh > _maxPlausibleSpeedKmh) continue;
          }
        } else if (distanceM > _maxJumpWithoutTimeMeters) {
          continue;
        }
      }

      cleaned.add(LatLng(p.lat, p.lng));
      lastKept = p;
    }
    return cleaned;
  }

  /// Clean an already-projected list of coordinates (no timestamps available).
  static List<LatLng> cleanLatLng(List<LatLng> raw) {
    final cleaned = <LatLng>[];
    LatLng? lastKept;
    for (final p in raw) {
      if (!_isValidCoordinate(p.latitude, p.longitude)) continue;
      if (lastKept != null) {
        final distanceM = gl.Geolocator.distanceBetween(
          lastKept.latitude,
          lastKept.longitude,
          p.latitude,
          p.longitude,
        );
        if (distanceM < _minSeparationMeters) continue;
        if (distanceM > _maxJumpWithoutTimeMeters) continue;
      }
      cleaned.add(p);
      lastKept = p;
    }
    return cleaned;
  }

  /// Build the exact, road-snapped route from already-projected coordinates.
  static Future<List<LatLng>> buildExactRouteFromLatLng(
    List<LatLng> raw,
  ) async {
    final cleaned = cleanLatLng(raw);
    if (cleaned.length < 2) return cleaned;
    try {
      final snapped = await _snapToRoads(cleaned);
      if (snapped.length >= cleaned.length) return snapped;
      return cleaned;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[RouteSnapping] snapToRoads failed, using raw points: $e');
      }
      return cleaned;
    }
  }

  /// Build the exact, road-snapped route from raw tracking points.
  /// Falls back to cleaned raw points if snapping is unavailable.
  static Future<List<LatLng>> buildExactRoute(List<RoutePoint> raw) async {
    final cleaned = cleanPoints(raw);
    if (cleaned.length < 2) return cleaned;

    try {
      final snapped = await _snapToRoads(cleaned);
      // Only trust the snapped result if it is at least as detailed as input.
      if (snapped.length >= cleaned.length) return snapped;
      return cleaned;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[RouteSnapping] snapToRoads failed, using raw points: $e');
      }
      return cleaned;
    }
  }

  static Future<List<LatLng>> _snapToRoads(List<LatLng> points) async {
    final key = AppConstants.googleMapsApiKey.trim();
    if (key.isEmpty) return points;

    final result = <LatLng>[];
    // Batch in chunks of 100 with a 1-point overlap so consecutive batches stitch
    // together without a visible gap at the seam.
    var start = 0;
    while (start < points.length) {
      final end = (start + _maxPointsPerRequest).clamp(0, points.length);
      final batch = points.sublist(start, end);
      final snapped = await _snapBatch(batch, key);

      if (result.isNotEmpty && snapped.isNotEmpty) {
        // Drop the first snapped point of subsequent batches (overlap point).
        result.addAll(snapped.skip(1));
      } else {
        result.addAll(snapped);
      }

      if (end >= points.length) break;
      start = end - 1; // overlap last point of this batch into the next
    }
    return result.isEmpty ? points : result;
  }

  static Future<List<LatLng>> _snapBatch(
    List<LatLng> batch,
    String key,
  ) async {
    final path = batch
        .map((p) => '${p.latitude},${p.longitude}')
        .join('|');
    final uri = Uri.parse(
      'https://roads.googleapis.com/v1/snapToRoads'
      '?interpolate=true'
      '&path=${Uri.encodeQueryComponent(path)}'
      '&key=$key',
    );

    final response = await http
        .get(uri)
        .timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) {
      throw Exception('Roads API HTTP ${response.statusCode}: ${response.body}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final snappedPoints = data['snappedPoints'] as List<dynamic>?;
    if (snappedPoints == null || snappedPoints.isEmpty) {
      // No snapped result (e.g. off-road); keep the original batch.
      return batch;
    }

    return snappedPoints
        .whereType<Map<String, dynamic>>()
        .map((sp) {
          final loc = sp['location'] as Map<String, dynamic>?;
          final lat = (loc?['latitude'] as num?)?.toDouble();
          final lng = (loc?['longitude'] as num?)?.toDouble();
          if (lat == null || lng == null) return null;
          return LatLng(lat, lng);
        })
        .whereType<LatLng>()
        .toList();
  }

  static bool _isValidCoordinate(double lat, double lng) {
    if (lat == 0 && lng == 0) return false;
    if (lat.isNaN || lng.isNaN || !lat.isFinite || !lng.isFinite) return false;
    if (lat < -90 || lat > 90) return false;
    if (lng < -180 || lng > 180) return false;
    return true;
  }
}
