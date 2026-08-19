import 'package:flutter/material.dart';

enum TrackingEventType { punchIn, drive, walk, stop, arrived, trackingStopped }

class TrackingEvent {
  final TrackingEventType type;
  final DateTime timestamp;
  final double? distance;
  final Duration? duration;
  final String? locationDescription;

  TrackingEvent({
    required this.type,
    required this.timestamp,
    this.distance,
    this.duration,
    this.locationDescription,
  });

  IconData get icon {
    switch (type) {
      case TrackingEventType.punchIn:
        return Icons.access_time;
      case TrackingEventType.drive:
        return Icons.drive_eta;
      case TrackingEventType.walk:
        return Icons.directions_walk;
      case TrackingEventType.stop:
        return Icons.pause_circle_filled;
      case TrackingEventType.arrived:
        return Icons.location_on;
      case TrackingEventType.trackingStopped:
        return Icons.stop_circle;
    }
  }

  Color get color {
    switch (type) {
      case TrackingEventType.punchIn:
        return Colors.blueGrey;
      case TrackingEventType.drive:
        return Colors.blueAccent;
      case TrackingEventType.walk:
        return Colors.green;
      case TrackingEventType.stop:
        return Colors.orange;
      case TrackingEventType.arrived:
        return Colors.purple;
      case TrackingEventType.trackingStopped:
        return Colors.redAccent;
    }
  }

  String get title {
    switch (type) {
      case TrackingEventType.punchIn:
        return "Task Started";
      case TrackingEventType.drive:
        return "Driving";
      case TrackingEventType.walk:
        return "Walking";
      case TrackingEventType.stop:
        return "Standing";
      case TrackingEventType.arrived:
        return "Arrived at Location";
      case TrackingEventType.trackingStopped:
        return "Tracking Stopped";
    }
  }
}
