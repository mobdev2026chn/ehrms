import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TrackingIncident {
  final String id;
  /// Types: 'gps_off', 'gps_on', 'no_network', 'network_on', 'permission_blocked',
  /// 'permission_ok', 'battery_restricted', 'battery_ok', 'gap', 'sync', 'offline_queue'
  final String type;
  final String title;
  final String description;
  final DateTime at;
  /// 'critical', 'warning', 'info'
  final String severity;

  TrackingIncident({
    required this.id,
    required this.type,
    required this.title,
    required this.description,
    required this.at,
    this.severity = 'warning',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'title': title,
        'description': description,
        'at': at.toIso8601String(),
        'severity': severity,
      };

  factory TrackingIncident.fromJson(Map<String, dynamic> json) => TrackingIncident(
        id: json['id']?.toString() ?? '',
        type: json['type']?.toString() ?? 'warning',
        title: json['title']?.toString() ?? '',
        description: json['description']?.toString() ?? '',
        at: DateTime.tryParse(json['at']?.toString() ?? '') ?? DateTime.now(),
        severity: json['severity']?.toString() ?? 'warning',
      );

  bool get isGps => type == 'gps_off' || type == 'gps_on' || type == 'gap';
  bool get isNetwork =>
      type == 'no_network' ||
      type == 'network_on' ||
      type == 'offline_queue' ||
      type == 'sync';
  bool get isPermission =>
      type == 'permission_blocked' ||
      type == 'permission_ok' ||
      type == 'battery_restricted' ||
      type == 'battery_ok';
}

/// Service that persists tracking incident logs (GPS disconnections, network issues,
/// permission blocks, offline buffers) per day in phone storage.
class TrackingIncidentLogService {
  TrackingIncidentLogService._();

  static const String _prefPrefix = 'tracking_incidents_v1_';
  static const int _maxPerDay = 250;

  static String _keyForDay(DateTime day) =>
      '$_prefPrefix${DateFormat('yyyy-MM-dd').format(day)}';

  /// Records an incident to disk for today (or [at] date), skipping identical repeats within 2 minutes.
  static Future<void> record({
    required String type,
    required String title,
    required String description,
    String severity = 'warning',
    DateTime? at,
  }) async {
    try {
      final now = at ?? DateTime.now();
      final key = _keyForDay(now);
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      final list = <TrackingIncident>[];
      if (raw != null && raw.isNotEmpty) {
        try {
          final decoded = jsonDecode(raw) as List;
          list.addAll(decoded.whereType<Map>().map((m) =>
              TrackingIncident.fromJson(Map<String, dynamic>.from(m))));
        } catch (_) {}
      }

      // Deduplicate if identical type occurred within 2 minutes
      if (list.isNotEmpty) {
        final last = list.last;
        if (last.type == type &&
            now.difference(last.at).inSeconds.abs() < 120) {
          return;
        }
      }

      final incident = TrackingIncident(
        id: '${type}_${now.millisecondsSinceEpoch}',
        type: type,
        title: title,
        description: description,
        at: now,
        severity: severity,
      );
      list.add(incident);

      // Keep up to [_maxPerDay]
      while (list.length > _maxPerDay) {
        list.removeAt(0);
      }

      await prefs.setString(
          key, jsonEncode(list.map((i) => i.toJson()).toList()));
    } catch (_) {}
  }

  /// Returns all stored incidents for [day].
  static Future<List<TrackingIncident>> getIncidentsForDay(DateTime day) async {
    try {
      final key = _keyForDay(day);
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      if (raw == null || raw.isEmpty) return const [];
      final decoded = jsonDecode(raw) as List;
      final list = decoded
          .whereType<Map>()
          .map((m) => TrackingIncident.fromJson(Map<String, dynamic>.from(m)))
          .toList();
      list.sort((a, b) => a.at.compareTo(b.at));
      return list;
    } catch (_) {
      return const [];
    }
  }

  // ── Convenience helpers for system sensors ──

  static Future<void> logGpsStatus(bool enabled) async {
    if (!enabled) {
      await record(
        type: 'gps_off',
        title: 'GPS Disconnected',
        description:
            'Location (GPS) was turned off on device. Tracking coordinates could not be collected.',
        severity: 'critical',
      );
    } else {
      await record(
        type: 'gps_on',
        title: 'GPS Reconnected',
        description: 'Location services turned back on. GPS fixes resumed.',
        severity: 'info',
      );
    }
  }

  static Future<void> logNetworkStatus(bool connected) async {
    if (!connected) {
      await record(
        type: 'no_network',
        title: 'Network Issue (Offline)',
        description:
            'Internet connection lost. Live coordinates could not upload in real time and were queued in offline storage.',
        severity: 'warning',
      );
    } else {
      await record(
        type: 'network_on',
        title: 'Network Restored (Online)',
        description: 'Internet connection re-established. Offline sync enabled.',
        severity: 'info',
      );
    }
  }

  static Future<void> logPermissionStatus(bool isAlways, {String? detail}) async {
    if (!isAlways) {
      await record(
        type: 'permission_blocked',
        title: 'Permission Block / Limited',
        description: detail ??
            'Location permission is not set to "Allow all the time". Background route tracking is restricted by Android when the screen is locked.',
        severity: 'critical',
      );
    } else {
      await record(
        type: 'permission_ok',
        title: 'Permission Granted (All The Time)',
        description:
            'Background location permission is set to "Allow all the time". Background route tracking is permitted.',
        severity: 'info',
      );
    }
  }

  static Future<void> logBatteryOptimization(bool isUnrestricted) async {
    if (!isUnrestricted) {
      await record(
        type: 'battery_restricted',
        title: 'Battery Saver / Optimization Active',
        description:
            'EktaHR battery usage is restricted. Android Doze Mode will pause background location when phone is in pocket.',
        severity: 'warning',
      );
    } else {
      await record(
        type: 'battery_ok',
        title: 'Battery Usage Unrestricted',
        description: 'Battery optimization disabled for EktaHR.',
        severity: 'info',
      );
    }
  }

  static Future<void> logOfflineQueue(int count, {String source = 'Presence'}) async {
    await record(
      type: 'offline_queue',
      title: 'GPS Coordinates Queued Offline',
      description:
          'Network connection lost or server unreachable. $source coordinate buffered locally (queue depth: $count).',
      severity: 'warning',
    );
  }

  static Future<void> logSync(int count, {String source = 'Presence'}) async {
    await record(
      type: 'sync',
      title: 'Offline Queue Synchronized',
      description:
          'Network connection restored. Successfully synchronized $count $source coordinate(s) with the server.',
      severity: 'info',
    );
  }
}

