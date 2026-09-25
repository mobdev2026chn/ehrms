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
  static const double _minSeparationMeters = 8;

  /// Drop points recorded with worse GPS accuracy than this.
  static const double _maxAccuracyMeters = 30;

  /// Reject a point as an outlier if reaching it would require this speed.
  static const double _maxPlausibleSpeedKmh = 200;

  /// Reject a jump this large when timestamps are missing (likely GPS glitch).
  static const double _maxJumpWithoutTimeMeters = 3000;

  /// Clean raw tracking points: drop invalid coordinates, near-duplicates and
  /// physically-impossible jumps, preserving chronological order.
  static List<LatLng> cleanPoints(List<RoutePoint> raw) {
    final cleaned = <LatLng>[];
    RoutePoint? lastKept;

    // The trail mixes the dense ride recording with periodic/background points;
    // draw them in the order they were recorded.
    final ordered = List<RoutePoint>.from(raw);
    if (ordered.every((p) => p.timestamp != null)) {
      ordered.sort((a, b) => a.timestamp!.compareTo(b.timestamp!));
    }

    for (final p in ordered) {
      if (!_isValidCoordinate(p.lat, p.lng)) continue;
      // A fix this imprecise lands on the wrong street; it only adds zig-zags.
      if (p.accuracy != null && p.accuracy! > _maxAccuracyMeters) continue;

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

  /// Tracking was not running across a gap this long (hold/resume, app killed),
  /// so the two sides are separate legs — the gap itself is not travel.
  static const Duration _legBreakGap = Duration(minutes: 5);

  /// Distance actually travelled along [raw] tracking points, in km.
  ///
  /// Same cleaning as the drawn route (accuracy, jitter, impossible jumps),
  /// split into legs where tracking paused, each leg snapped to the roads when
  /// the Roads API answers (straight segments between the dense points
  /// otherwise), then summed. This is what the travel allowance should use.
  static Future<double> travelledDistanceKm(List<RoutePoint> raw) async {
    final ordered = List<RoutePoint>.from(raw)
        .where((p) =>
            _isValidCoordinate(p.lat, p.lng) &&
            (p.accuracy == null || p.accuracy! <= _maxAccuracyMeters))
        .toList();
    if (ordered.every((p) => p.timestamp != null)) {
      ordered.sort((a, b) => a.timestamp!.compareTo(b.timestamp!));
    }

    final legs = <List<RoutePoint>>[];
    var leg = <RoutePoint>[];
    for (final p in ordered) {
      final last = leg.isNotEmpty ? leg.last : null;
      if (last != null &&
          last.timestamp != null &&
          p.timestamp != null &&
          p.timestamp!.difference(last.timestamp!) > _legBreakGap) {
        legs.add(leg);
        leg = <RoutePoint>[];
      }
      leg.add(p);
    }
    if (leg.isNotEmpty) legs.add(leg);

    var meters = 0.0;
    for (final l in legs) {
      final path = await buildExactRoute(l);
      meters += _pathLengthMeters(path);
    }
    return meters / 1000;
  }

  static double _pathLengthMeters(List<LatLng> path) {
    var m = 0.0;
    for (var i = 1; i < path.length; i++) {
      m += gl.Geolocator.distanceBetween(
        path[i - 1].latitude,
        path[i - 1].longitude,
        path[i].latitude,
        path[i].longitude,
      );
    }
    return m;
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
