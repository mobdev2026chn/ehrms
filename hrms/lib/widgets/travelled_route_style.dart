import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// One look for "the route the staff member actually travelled" on every map:
/// a bold, continuous (solid) green line with rounded joints and ends, which
/// stays readable over Google's yellow/orange roads.
class TravelledRouteStyle {
  TravelledRouteStyle._();

  static const Color color = Color(0xFF2E7D32);
  static const int width = 5;

  /// Solid line — no dash/gap pattern.
  static final List<PatternItem> patterns = const [];

  static Polyline polyline(String id, List<LatLng> points) => Polyline(
        polylineId: PolylineId(id),
        points: points,
        color: color,
        width: width,
        patterns: patterns,
        jointType: JointType.round,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
        zIndex: 2,
      );
}
