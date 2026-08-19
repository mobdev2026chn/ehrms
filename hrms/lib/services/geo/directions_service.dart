// Directions service – fetches road route from Google Directions API.
import 'dart:math' show cos, sqrt, asin;

import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:hrms/config/constants.dart';

/// Result of fetching directions between two points.
class DirectionsResult {
  final List<LatLng> points;
  final double distanceKm;
  final String? durationText;

  const DirectionsResult({
    required this.points,
    required this.distanceKm,
    this.durationText,
  });
}

class DirectionsService {
  static final PolylinePoints _polylinePoints = PolylinePoints(
    apiKey: AppConstants.googleMapsApiKey,
  );

  /// Fetch road route between origin and destination. Returns polyline points,
  /// distance in km, and duration text (e.g. "15 mins").
  static Future<DirectionsResult> getRouteBetweenCoordinates({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
  }) async {
    try {
      final result = await _polylinePoints.getRouteBetweenCoordinates(
        request: PolylineRequest(
          origin: PointLatLng(originLat, originLng),
          destination: PointLatLng(destLat, destLng),
          mode: TravelMode.driving,
        ),
      );

      if (result.points.isEmpty) {
        return _fallbackStraightLine(originLat, originLng, destLat, destLng);
      }

      final points = result.points
          .map((p) => LatLng(p.latitude, p.longitude))
          .toList();

      double distanceKm = 0;
      String? durationText;

      if (result.totalDistanceValue != null && result.totalDistanceValue! > 0) {
        distanceKm = result.totalDistanceValue! / 1000;
      } else {
        distanceKm = _haversineKm(originLat, originLng, destLat, destLng);
      }

      if (result.totalDurationValue != null && result.totalDurationValue! > 0) {
        final secs = result.totalDurationValue!.round();
        if (secs >= 3600) {
          durationText = '~${secs ~/ 3600} h ${(secs % 3600) ~/ 60} min';
        } else if (secs >= 60) {
          durationText = '~${secs ~/ 60} min';
        } else {
          durationText = '~$secs sec';
        }
      }

      return DirectionsResult(
        points: points,
        distanceKm: distanceKm,
        durationText: durationText,
      );
    } catch (e) {
      return _fallbackStraightLine(originLat, originLng, destLat, destLng);
    }
  }

  static DirectionsResult _fallbackStraightLine(
    double originLat,
    double originLng,
    double destLat,
    double destLng,
  ) {
    final points = [
      LatLng(originLat, originLng),
      LatLng(destLat, destLng),
    ];
    final km = _haversineKm(originLat, originLng, destLat, destLng);
    final min = (km / 30 * 60).round().clamp(0, 999);
    final durationText = min > 60 ? '~${min ~/ 60} h' : '~$min min';
    return DirectionsResult(
      points: points,
      distanceKm: km,
      durationText: durationText,
    );
  }

  static double _haversineKm(double lat1, double lng1, double lat2, double lng2) {
    const p = 0.017453292519943295;
    final a = 0.5 -
        cos((lat2 - lat1) * p) / 2 +
        cos(lat1 * p) * cos(lat2 * p) * (1 - cos((lng2 - lng1) * p)) / 2;
    return 12742 * asin(sqrt(a));
  }
}
