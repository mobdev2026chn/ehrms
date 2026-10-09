// Watches, from punch-in to punch-out, for anything on the phone that stops GPS tracking
// (GPS off, location not "Allow all the time", precise location off, battery restriction)
// and alerts the employee straight away: a phone notification (repeated until fixed) and
// [issues] for the in-app banner. Started/stopped by PresenceTrackingService.

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart' as gl;
import 'package:hrms/services/api_client.dart';
import 'package:permission_handler/permission_handler.dart';

import 'location_service.dart';
import 'tracking_incident_log_service.dart';

enum TrackingIssue {
  gpsOff(
    'GPS is turned off',
    'Turn on Location (GPS) so your route can be tracked.',
    'Location is turned off. Your route is not being tracked. Please turn on G P S.',
    critical: true,
  ),
  locationNotAlways(
    'Location is not "Allow all the time"',
    'Set ektaHr location permission to "Allow all the time".',
    'Location permission is limited. Please allow EktaHR to use location all the time.',
    critical: true,
  ),
  preciseOff(
    'Precise location is off',
    'Turn on "Use precise location" for ektaHr.',
    'Precise location is off. Please turn it on for EktaHR.',
    critical: false,
  ),
  batteryRestricted(
    'Battery saver is limiting ektaHr',
    'Set ektaHr battery usage to "Unrestricted" so tracking keeps running.',
    'Battery saver is stopping tracking. Please set EktaHR battery usage to unrestricted.',
    critical: true,
  ),
  noNetwork(
    'No internet connection',
    'Your phone is offline. Location is still being recorded and will sync once you are back online.',
    'No internet connection. Your location is saved and will sync when you are back online.',
    // Not critical: GPS still records; points are buffered and replayed when online, so this
    // informs (notification + banner) without the voice/vibration alarm.
    critical: false,
  );

  const TrackingIssue(this.title, this.fix, this.spoken, {required this.critical});
  final String title;
  final String fix;

  /// Short line read aloud (text-to-speech).
  final String spoken;

  /// High-priority issues (cause location to stop) get voice + strong vibration;
  /// a minor one gets the notification only.
  final bool critical;
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
  // True while the last check saw no internet. Used to tell the admin, once the connection
  // is back, about the outage we could not report while it was happening.
  bool _wasOffline = false;
  StreamSubscription<gl.ServiceStatus>? _gpsSub;
  Timer? _timer;

  /// Callbacks to execute as soon as network is restored from an offline state.
  final List<Future<void> Function()> onNetworkRestored = [];

  /// Punch-in: start watching. Safe to call repeatedly.
  Future<void> start() async {
    if (!_active) {
      _active = true;
      // GPS switched off/on reaches us immediately, not only on the next tick.
      _gpsSub ??= gl.Geolocator.getServiceStatusStream().listen(
        (status) {
          unawaited(TrackingIncidentLogService.logGpsStatus(status == gl.ServiceStatus.enabled));
          check();
        },
        onError: (_) {},
      );
      _timer ??= Timer.periodic(_checkEvery, (_) => check());
    }
    await check();
  }

  bool? _lastGpsOff;
  bool? _lastPermIssue;
  bool? _lastOffline;
  bool? _lastBatteryIssue;

  /// Punch-out / tracking stopped: stop watching and clear any alert.
  Future<void> stop() async {
    _active = false;
    _timer?.cancel();
    _timer = null;
    await _gpsSub?.cancel();
    _gpsSub = null;
    _lastAlerted = {};
    _lastAlertAt = null;
    _wasOffline = false;
    _lastGpsOff = null;
    _lastPermIssue = null;
    _lastOffline = null;
    _lastBatteryIssue = null;
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

      // Log transitions into TrackingIncidentLogService
      final gpsOff = found.contains(TrackingIssue.gpsOff);
      if (gpsOff != _lastGpsOff) {
        if (_lastGpsOff != null || gpsOff) {
          unawaited(TrackingIncidentLogService.logGpsStatus(!gpsOff));
        }
        _lastGpsOff = gpsOff;
      }

      final permIssue = found.contains(TrackingIssue.locationNotAlways);
      if (permIssue != _lastPermIssue) {
        if (_lastPermIssue != null || permIssue) {
          unawaited(TrackingIncidentLogService.logPermissionStatus(!permIssue));
        }
        _lastPermIssue = permIssue;
      }

      final offlineNow = found.contains(TrackingIssue.noNetwork);
      if (offlineNow != _lastOffline) {
        if (_lastOffline != null || offlineNow) {
          unawaited(TrackingIncidentLogService.logNetworkStatus(!offlineNow));
        }
        _lastOffline = offlineNow;
      }

      final batteryIssue = found.contains(TrackingIssue.batteryRestricted);
      if (batteryIssue != _lastBatteryIssue) {
        if (_lastBatteryIssue != null || batteryIssue) {
          unawaited(TrackingIncidentLogService.logBatteryOptimization(!batteryIssue));
        }
        _lastBatteryIssue = batteryIssue;
      }

      // The connection just came back: we could not reach the server while offline, so tell the
      // admin now about the interruption that just ended, and trigger immediate sync of all offline data!
      if (_wasOffline && !offlineNow) {
        unawaited(_reportReasonToAdmin('no_network'));
        // The incident log recorded the outage while offline; ship it now.
        unawaited(TrackingIncidentLogService.syncToServer(force: true));
        for (final callback in onNetworkRestored) {
          try {
            unawaited(callback());
          } catch (_) {}
        }
      }
      _wasOffline = offlineNow;

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
        // Priority: a critical issue (location actually stopped) also vibrates and speaks;
        // a minor one gets just the notification.
        unawaited(_alertVoiceAndVibrate(found));
        // Tell the admin too (backend throttles to one alert per ~20 min per employee).
        unawaited(_reportToAdmin(found.first));
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
      case TrackingIssue.noNetwork:
        // Nothing to open — the phone just needs to regain signal/data.
        break;
    }
  }

  static FlutterTts? _tts;

  /// On a critical issue: strong vibration + a spoken voice alert, so the employee notices
  /// even with the phone in a pocket. The notification covers the non-critical case already.
  static Future<void> _alertVoiceAndVibrate(List<TrackingIssue> found) async {
    if (kIsWeb) return;
    final critical = found.firstWhere((i) => i.critical, orElse: () => found.first);
    if (!critical.critical) return;

    // Vibration: a few strong buzzes (no extra plugin needed).
    try {
      for (var i = 0; i < 3; i++) {
        await HapticFeedback.heavyImpact();
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    } catch (_) {}

    // Voice: speak the fix once.
    try {
      final tts = _tts ??= FlutterTts();
      await tts.setLanguage('en-US');
      await tts.setSpeechRate(0.45);
      await tts.setVolume(1.0);
      await tts.stop();
      await tts.speak(critical.spoken);
    } catch (_) {
      // TTS not available on this device; the notification + vibration still fired.
    }
  }

  /// Notifies the employee's admin that tracking is interrupted. The server records an
  /// admin notification and throttles repeats, so this is safe to call on every alert.
  static Future<void> _reportToAdmin(TrackingIssue issue) async {
    final reason = switch (issue) {
      TrackingIssue.gpsOff => 'gps_off',
      TrackingIssue.locationNotAlways => 'permission',
      TrackingIssue.preciseOff => 'permission',
      TrackingIssue.batteryRestricted => 'service_stopped',
      TrackingIssue.noNetwork => 'no_network',
    };
    await _reportReasonToAdmin(reason);
  }

  /// Posts a tracking interruption to the employee's admin. The server records an admin
  /// notification and throttles repeats, so this is safe to call on every alert.
  static Future<void> _reportReasonToAdmin(String reason) async {
    try {
      await ApiClient().dio.post<dynamic>(
        '/staff/geo-task/tracking-alert',
        data: {'reason': reason},
      );
    } catch (_) {
      // Best-effort: the employee is already warned on their phone.
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

    if (!await _hasNetwork()) found.add(TrackingIssue.noNetwork);
    return found;
  }

  /// A quick reachability probe (no extra plugin): a DNS lookup needs a working connection.
  /// Unknown or unexpected errors are treated as "online" so tracking never false-alarms.
  static Future<bool> _hasNetwork() async {
    try {
      final r = await InternetAddress.lookup('one.one.one.one')
          .timeout(const Duration(seconds: 4));
      return r.isNotEmpty && r.first.rawAddress.isNotEmpty;
    } on SocketException {
      return false;
    } on TimeoutException {
      return false;
    } catch (_) {
      return true;
    }
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
            // Priority alert: ring + buzz, not a silent notification.
            playSound: true,
            enableVibration: true,
            enableLights: true,
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
