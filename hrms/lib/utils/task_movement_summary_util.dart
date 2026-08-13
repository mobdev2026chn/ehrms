import 'dart:math' as math;

import 'package:hrms/models/task.dart';

class TaskMovementSummary {
  final Duration drivingDuration;
  final Duration walkingDuration;
  final Duration stopDuration;
  final bool hasData;

  const TaskMovementSummary({
    required this.drivingDuration,
    required this.walkingDuration,
    required this.stopDuration,
    required this.hasData,
  });

  factory TaskMovementSummary.fromDurations({
    Duration? drivingDuration,
    Duration? walkingDuration,
    Duration? stopDuration,
  }) {
    final drive = drivingDuration ?? Duration.zero;
    final walk = walkingDuration ?? Duration.zero;
    final stop = stopDuration ?? Duration.zero;
    return TaskMovementSummary(
      drivingDuration: drive,
      walkingDuration: walk,
      stopDuration: stop,
      hasData:
          drive.inSeconds > 0 ||
          walk.inSeconds > 0 ||
          stop.inSeconds > 0 ||
          drivingDuration != null ||
          walkingDuration != null ||
          stopDuration != null,
    );
  }

  factory TaskMovementSummary.fromRoutePoints(
    List<RoutePoint> routePoints, {
    DateTime? endTime,
  }) {
    final points = routePoints.where((p) => p.timestamp != null).toList()
      ..sort((a, b) => a.timestamp!.compareTo(b.timestamp!));

    if (points.isEmpty) {
      return const TaskMovementSummary(
        drivingDuration: Duration.zero,
        walkingDuration: Duration.zero,
        stopDuration: Duration.zero,
        hasData: false,
      );
    }

    Duration driving = Duration.zero;
    Duration walking = Duration.zero;
    Duration stop = Duration.zero;

    for (var i = 0; i < points.length; i++) {
      final start = points[i].timestamp!;
      if (endTime != null && start.isAfter(endTime)) break;

      DateTime? segmentEnd;
      if (i + 1 < points.length) {
        segmentEnd = points[i + 1].timestamp!;
      } else if (endTime != null) {
        segmentEnd = endTime;
      }

      if (segmentEnd == null) continue;
      if (endTime != null && segmentEnd.isAfter(endTime)) {
        segmentEnd = endTime;
      }
      if (!segmentEnd.isAfter(start)) continue;

      final duration = segmentEnd.difference(start);
      switch (_normalizeMovement(points[i].movementType)) {
        case _MovementKind.driving:
          driving += duration;
          break;
        case _MovementKind.walking:
          walking += duration;
          break;
        case _MovementKind.stop:
          stop += duration;
          break;
      }
    }

    return TaskMovementSummary(
      drivingDuration: driving,
      walkingDuration: walking,
      stopDuration: stop,
      hasData: true,
    );
  }
}

double computeRouteDistanceKm(
  List<RoutePoint> routePoints, {
  DateTime? endTime,
}) {
  final points = routePoints.where((p) => p.timestamp != null).toList()
    ..sort((a, b) => a.timestamp!.compareTo(b.timestamp!));

  if (points.length < 2) return 0;

  var totalKm = 0.0;
  for (var i = 0; i < points.length - 1; i++) {
    final start = points[i];
    final end = points[i + 1];
    final startTime = start.timestamp!;
    if (endTime != null && startTime.isAfter(endTime)) break;
    final endPointTime = end.timestamp!;
    if (endTime != null && endPointTime.isAfter(endTime)) break;
    totalKm += _haversineKm(start.lat, start.lng, end.lat, end.lng);
  }
  return totalKm;
}

enum _MovementKind { driving, walking, stop }

_MovementKind _normalizeMovement(String? movementType) {
  switch (movementType?.trim().toLowerCase()) {
    case 'drive':
    case 'driving':
      return _MovementKind.driving;
    case 'walk':
    case 'walking':
      return _MovementKind.walking;
    case 'stop':
    default:
      return _MovementKind.stop;
  }
}

double _haversineKm(double lat1, double lng1, double lat2, double lng2) {
  const p = 0.017453292519943295;
  final a = 0.5 -
      math.cos((lat2 - lat1) * p) / 2 +
      math.cos(lat1 * p) *
          math.cos(lat2 * p) *
          (1 - math.cos((lng2 - lng1) * p)) /
          2;
  return 12742 * math.asin(math.sqrt(a));
}
