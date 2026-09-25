import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// One look for "the route the staff member actually travelled" on every map:
/// a bold dashed green line, which stays readable over Google's yellow/orange
/// roads (the old solid amber line blended into them).
class TravelledRouteStyle {
  TravelledRouteStyle._();

  static const Color color = Color(0xFF2E7D32);
  static const int width = 5;
  static final List<PatternItem> patterns = [
    PatternItem.dash(20),
    PatternItem.gap(10),
  ];

  static Polyline polyline(String id, List<LatLng> points) => Polyline(
        polylineId: PolylineId(id),
        points: points,
        color: color,
        width: width,
        patterns: patterns,
        jointType: JointType.round,
        zIndex: 2,
      );
}
