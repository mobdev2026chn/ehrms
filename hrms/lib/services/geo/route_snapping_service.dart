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
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:math' as math;

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
    for (var i = 0; i < raw.length; i++) {
      final p = raw[i];
      if (!_isValidCoordinate(p.latitude, p.longitude)) continue;
      if (lastKept != null) {
        final distanceM = gl.Geolocator.distanceBetween(
          lastKept.latitude,
          lastKept.longitude,
          p.latitude,
          p.longitude,
        );
        if (distanceM < _minSeparationMeters) continue;
        // The last point is the route's end (e.g. a leg's Stop): never drop it as a
        // glitch, or a long Start → Stop leg would lose its end and not be drawn.
        if (distanceM > _maxJumpWithoutTimeMeters && i != raw.length - 1) continue;
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

  // ── Route for DISPLAY (task detail / completed task maps) ───────────────────
  // Roads API is billed per request (100 points each), and a dense recorded
  // route has ~100 points per km, so snapping on every screen open was costly.
  // For display: a dense route (points every <= 60 m) already follows the
  // streets and is drawn as-is; a sparse one is snapped ONCE and the result is
  // kept on the phone per task. The allowance distance at arrival
  // (travelledDistanceKm) still snaps, exactly as before.

  static const double _denseSpacingMeters = 60;
  // v3: road snapping / gap routing is only kept when it fits the recorded GPS
  // (metro, train, footpaths stay as recorded), so routes cached by v2 are rebuilt once.
  static const String _snapCachePrefix = 'route_snap_v3:';
  static const String _snapCacheIndex = 'route_snap_v3_index';

  /// A gap longer than this is a GPS blackout (underground metro, tunnel) or a
  /// tracking pause, not a road the person was seen on: it stays straight.
  static const double _maxRoutableGapMeters = 1500;

  /// The road route for a gap is used only if it is at most this much longer than
  /// the straight line between its ends; a bigger detour means the person went
  /// another way (metro / rail line, footpath) and the gap stays straight.
  static const double _maxGapDetourRatio = 1.35;

  /// A snapped route is rejected (raw GPS drawn instead) when it is this much
  /// longer than the recorded path …
  static const double _maxSnapLengthRatio = 1.3;

  /// … or when more than [_maxOffRoadShare] of the recorded points are farther than
  /// this from it (they were not on a road: metro, train, open ground).
  static const double _maxOffRoadMeters = 60;
  static const double _maxOffRoadShare = 0.3;
  static const int _snapCacheMax = 80;

  /// Consecutive points farther apart than this are too sparse for snapToRoads to
  /// follow the streets (it interpolates only short gaps); the road route between them
  /// comes from the Directions API instead.
  static const double _gapMeters = 250;

  /// Directions requests per route at most (each is billed); further gaps stay straight.
  static const int _maxDirectionsPerRoute = 10;

  /// Display route for [raw] tracking points of task [cacheKey].
  static Future<List<LatLng>> buildDisplayRoute(
    String cacheKey,
    List<RoutePoint> raw,
  ) =>
      _displayRoute(cacheKey, cleanPoints(raw));

  /// Display route for already-projected coordinates of task [cacheKey].
  static Future<List<LatLng>> buildDisplayRouteFromLatLng(
    String cacheKey,
    List<LatLng> raw,
  ) =>
      _displayRoute(cacheKey, cleanLatLng(raw));

  static Future<List<LatLng>> _displayRoute(
    String cacheKey,
    List<LatLng> cleaned,
  ) async {
    if (cleaned.length < 2) return cleaned;
    final spacing = _pathLengthMeters(cleaned) / (cleaned.length - 1);
    // A dense recording already follows the streets - unless it has a gap somewhere
    // (tracking paused, few points saved), which would still be drawn straight.
    if (spacing <= _denseSpacingMeters && !_hasGap(cleaned)) return cleaned;

    // Same task + same number of points = same route; reuse the snapped copy.
    final key = '$_snapCachePrefix$cacheKey:${cleaned.length}';
    try {
      final prefs = await SharedPreferences.getInstance();
      final hit = prefs.getString(key);
      if (hit != null && hit.isNotEmpty) {
        final pts = hit.split(';').map((s) {
          final ll = s.split(',');
          return LatLng(double.parse(ll[0]), double.parse(ll[1]));
        }).toList();
        if (pts.length >= 2) return pts;
      }
      // 1) snapToRoads for the parts with nearby points; 2) the road route for every gap
      //    it could not follow.
      List<LatLng> snapped;
      try {
        snapped = await _snapToRoads(cleaned);
        if (snapped.length < cleaned.length) snapped = cleaned;
        // Keep the road version only if it fits the recorded GPS (else: metro, train,
        // footpath — draw what was actually recorded).
        if (!identical(snapped, cleaned) && !_fitsRecorded(cleaned, snapped)) {
          if (kDebugMode) debugPrint('[RouteSnapping] snapped route does not fit the GPS - using raw points');
          snapped = cleaned;
        }
      } catch (_) {
        snapped = cleaned;
      }
      snapped = await _routeGaps(snapped);
      if (snapped.length < 2) return cleaned;
      await prefs.setString(
        key,
        snapped
            .map((p) =>
                '${p.latitude.toStringAsFixed(6)},${p.longitude.toStringAsFixed(6)}')
            .join(';'),
      );
      final index = prefs.getStringList(_snapCacheIndex) ?? <String>[];
      index.remove(key);
      index.add(key);
      while (index.length > _snapCacheMax) {
        await prefs.remove(index.removeAt(0));
      }
      await prefs.setStringList(_snapCacheIndex, index);
      return snapped;
    } catch (_) {
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

  static double _metersBetween(LatLng a, LatLng b) =>
      gl.Geolocator.distanceBetween(a.latitude, a.longitude, b.latitude, b.longitude);

  /// Whether a road-snapped route is believable for the recorded points: not much
  /// longer than the recorded path, and most recorded points lie close to it.
  static bool _fitsRecorded(List<LatLng> recorded, List<LatLng> snapped) {
    if (snapped.length < 2 || recorded.length < 2) return true;
    final recLen = _pathLengthMeters(recorded);
    final snapLen = _pathLengthMeters(snapped);
    if (snapLen > recLen * _maxSnapLengthRatio + 100) return false;
    var offRoad = 0;
    for (final p in recorded) {
      var best = double.infinity;
      for (var i = 1; i < snapped.length; i++) {
        final d = _distanceToSegment(p, snapped[i - 1], snapped[i]);
        if (d < best) best = d;
        if (best <= _maxOffRoadMeters) break;
      }
      if (best > _maxOffRoadMeters) offRoad++;
    }
    return offRoad <= recorded.length * _maxOffRoadShare;
  }

  /// Metres from [p] to segment [a]-[b] (flat-earth approximation; fine at city scale).
  static double _distanceToSegment(LatLng p, LatLng a, LatLng b) {
    const mPerDegLat = 111320.0;
    final mPerDegLng = 111320.0 * math.cos(p.latitude * math.pi / 180);
    final ax = (a.longitude - p.longitude) * mPerDegLng, ay = (a.latitude - p.latitude) * mPerDegLat;
    final bx = (b.longitude - p.longitude) * mPerDegLng, by = (b.latitude - p.latitude) * mPerDegLat;
    final dx = bx - ax, dy = by - ay;
    final len2 = dx * dx + dy * dy;
    var t = len2 == 0 ? 0.0 : -(ax * dx + ay * dy) / len2;
    t = t.clamp(0.0, 1.0);
    final cx = ax + t * dx, cy = ay + t * dy;
    return math.sqrt(cx * cx + cy * cy);
  }

  static bool _hasGap(List<LatLng> path) {
    for (var i = 1; i < path.length; i++) {
      if (_metersBetween(path[i - 1], path[i]) > _gapMeters) return true;
    }
    return false;
  }

  /// Replaces each straight jump longer than [_gapMeters] with the road route between
  /// its two ends (Directions API). Any request that fails leaves that gap straight.
  static Future<List<LatLng>> _routeGaps(List<LatLng> path) async {
    final key = AppConstants.googleMapsApiKey.trim();
    if (key.isEmpty || path.length < 2) return path;
    final out = <LatLng>[path.first];
    var requests = 0;
    for (var i = 1; i < path.length; i++) {
      final a = path[i - 1];
      final b = path[i];
      final gap = _metersBetween(a, b);
      // Only short gaps are routed along the roads; a long one is a GPS blackout
      // (underground metro, tunnel) or a pause and stays straight.
      if (gap > _gapMeters && gap <= _maxRoutableGapMeters && requests < _maxDirectionsPerRoute) {
        requests++;
        try {
          final road = await _directions(a, b, key);
          // Keep the recorded ends; take the road geometry in between - but only when the
          // road roughly follows the straight line (a big detour = metro / rail / footpath).
          if (road.length > 2 && _pathLengthMeters(road) <= gap * _maxGapDetourRatio) {
            out.addAll(road.sublist(1, road.length - 1));
          }
        } catch (e) {
          if (kDebugMode) debugPrint('[RouteSnapping] directions failed, gap stays straight: $e');
        }
      }
      out.add(b);
    }
    return out;
  }

  /// Driving route geometry from [a] to [b] (Directions API, overview polyline).
  static Future<List<LatLng>> _directions(LatLng a, LatLng b, String key) async {
    final uri = Uri.parse(
      'https://maps.googleapis.com/maps/api/directions/json'
      '?origin=${a.latitude},${a.longitude}'
      '&destination=${b.latitude},${b.longitude}'
      '&mode=driving'
      '&key=$key',
    );
    final response = await http.get(uri).timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) {
      throw Exception('Directions HTTP ${response.statusCode}');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (data['status'] != 'OK') throw Exception('Directions ${data['status']}');
    final routes = data['routes'] as List<dynamic>?;
    if (routes == null || routes.isEmpty) return const [];
    final overview = (routes.first as Map)['overview_polyline'];
    final encoded = overview is Map ? overview['points']?.toString() : null;
    if (encoded == null || encoded.isEmpty) return const [];
    return _decodePolyline(encoded);
  }

  /// Google encoded-polyline decoder.
  static List<LatLng> _decodePolyline(String encoded) {
    final points = <LatLng>[];
    var index = 0, lat = 0, lng = 0;
    while (index < encoded.length) {
      for (var coord = 0; coord < 2; coord++) {
        var shift = 0, result = 0, b = 0;
        do {
          b = encoded.codeUnitAt(index++) - 63;
          result |= (b & 0x1f) << shift;
          shift += 5;
        } while (b >= 0x20 && index < encoded.length);
        final delta = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
        if (coord == 0) {
          lat += delta;
        } else {
          lng += delta;
        }
      }
      points.add(LatLng(lat / 1e5, lng / 1e5));
    }
    return points;
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
