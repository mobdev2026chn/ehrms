// Watches, from punch-in to punch-out, for anything on the phone that stops GPS tracking
// (GPS off, location not "Allow all the time", precise location off, battery restriction)
// and alerts the employee straight away: a phone notification (repeated until fixed) and
// [issues] for the in-app banner. Started/stopped by PresenceTrackingService.

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart' as gl;
import 'package:permission_handler/permission_handler.dart';

import 'location_service.dart';

enum TrackingIssue {
  gpsOff(
    'GPS is turned off',
    'Turn on Location (GPS) so your route can be tracked.',
  ),
  locationNotAlways(
    'Location is not "Allow all the time"',
    'Set ektaHr location permission to "Allow all the time".',
  ),
  preciseOff(
    'Precise location is off',
    'Turn on "Use precise location" for ektaHr.',
  ),
  batteryRestricted(
    'Battery saver is limiting ektaHr',
    'Set ektaHr battery usage to "Unrestricted" so tracking keeps running.',
  );

  const TrackingIssue(this.title, this.fix);
  final String title;
  final String fix;
}

class TrackingHealthService {
  TrackingHealthService._();
  static final TrackingHealthService instance = TrackingHealthService._();

  static const _channelId = 'hrms_tracking_health';
  static const _notificationId = 7301;
  static const _realertEvery = Duration(minutes: 10);
  // Own timer: presence ticks pause during task rides, the watch must not.
  static const _checkEvery = Duration(minutes: 1);

  /// Current problems; empty when tracking is healthy or not running. Drives the banner.
  final ValueNotifier<List<TrackingIssue>> issues = ValueNotifier(const []);

  bool _active = false;
  bool _checking = false;
  DateTime? _lastAlertAt;
  Set<TrackingIssue> _lastAlerted = {};
  StreamSubscription<gl.ServiceStatus>? _gpsSub;
  Timer? _timer;

  /// Punch-in: start watching. Safe to call repeatedly.
  Future<void> start() async {
    if (!_active) {
      _active = true;
      // GPS switched off/on reaches us immediately, not only on the next tick.
      _gpsSub ??= gl.Geolocator.getServiceStatusStream().listen(
        (_) => check(),
        onError: (_) {},
      );
      _timer ??= Timer.periodic(_checkEvery, (_) => check());
    }
    await check();
  }

  /// Punch-out / tracking stopped: stop watching and clear any alert.
  Future<void> stop() async {
    _active = false;
    _timer?.cancel();
    _timer = null;
    await _gpsSub?.cancel();
    _gpsSub = null;
    _lastAlerted = {};
    _lastAlertAt = null;
    issues.value = const [];
    await _cancelNotification();
  }

  /// Re-checks the phone; alerts on a new problem at once, and repeats every
  /// [_realertEvery] while any problem is still there.
  Future<void> check() async {
    if (!_active || _checking) return;
    _checking = true;
    try {
      final found = await _detect();
      if (!_active) return;
      final changed = !setEquals(found.toSet(), issues.value.toSet());
      issues.value = found;
      if (changed) unawaited(LocationService.syncLocationPermissionStatusToBackend());

      if (found.isEmpty) {
        if (_lastAlerted.isNotEmpty) await _cancelNotification();
        _lastAlerted = {};
        _lastAlertAt = null;
        return;
      }
      final hasNew = found.any((i) => !_lastAlerted.contains(i));
      final due = _lastAlertAt == null || DateTime.now().difference(_lastAlertAt!) >= _realertEvery;
      if (hasNew || due) {
        await _notify(found);
        _lastAlerted = found.toSet();
        _lastAlertAt = DateTime.now();
      }
    } catch (e) {
      debugPrint('[TrackingHealth] check failed: $e');
    } finally {
      _checking = false;
    }
  }

  /// Opens the screen that fixes [issue].
  static Future<void> fix(TrackingIssue issue) async {
    switch (issue) {
      case TrackingIssue.gpsOff:
        await gl.Geolocator.openLocationSettings();
      case TrackingIssue.batteryRestricted:
        final status = await Permission.ignoreBatteryOptimizations.request();
        if (!status.isGranted) await openAppSettings();
      case TrackingIssue.locationNotAlways:
      case TrackingIssue.preciseOff:
        await openAppSettings();
    }
  }

  static Future<List<TrackingIssue>> _detect() async {
    if (kIsWeb) return const [];
    final found = <TrackingIssue>[];
    if (!await gl.Geolocator.isLocationServiceEnabled()) found.add(TrackingIssue.gpsOff);

    final permission = await gl.Geolocator.checkPermission();
    if (permission != gl.LocationPermission.always) {
      found.add(TrackingIssue.locationNotAlways);
    } else {
      try {
        if (await gl.Geolocator.getLocationAccuracy() != gl.LocationAccuracyStatus.precise) {
          found.add(TrackingIssue.preciseOff);
        }
      } catch (_) {}
    }

    if (Platform.isAndroid && !await Permission.ignoreBatteryOptimizations.isGranted) {
      found.add(TrackingIssue.batteryRestricted);
    }
    return found;
  }

  static Future<void> _notify(List<TrackingIssue> found) async {
    final title = found.length == 1 ? 'Tracking stopped: ${found.first.title}' : 'Tracking stopped: ${found.length} problems';
    final body = found.map((i) => i.fix).join('\n');
    try {
      await FlutterLocalNotificationsPlugin().show(
        _notificationId,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            'Tracking alerts',
            channelDescription: 'Alerts when your phone settings stop attendance tracking',
            importance: Importance.max,
            priority: Priority.high,
            icon: 'ic_stat_ektahr',
            styleInformation: BigTextStyleInformation(body),
            ongoing: true,
            autoCancel: false,
          ),
          iOS: const DarwinNotificationDetails(presentAlert: true, presentSound: true),
        ),
      );
    } catch (e) {
      debugPrint('[TrackingHealth] notify failed: $e');
    }
  }

  static Future<void> _cancelNotification() async {
    try {
      await FlutterLocalNotificationsPlugin().cancel(_notificationId);
    } catch (_) {}
  }
}
