import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Service for scheduling alarms that ring and show notifications even when the app is closed.
/// Uses flutter_local_notifications zonedSchedule on Android (AlarmManager) and iOS.
class AlarmService {
  AlarmService._();

  static const String _kAlarmChannelId = 'hrms_alarm_channel';
  static const String _kAlarmsPrefsKey = 'hrms_scheduled_alarms';
  static const int _kAlarmNotificationIdBase = 900000; // Avoid collision with FCM ids

  static bool _timezoneInitialized = false;

  /// Initialize timezone data. Call from main() before runApp.
  static Future<void> initializeTimezone() async {
    if (_timezoneInitialized) return;
    tz_data.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.UTC);
    } catch (_) {}
    _timezoneInitialized = true;
  }

  /// Request permission to schedule exact alarms (Android 12+). Opens system settings.
  /// Call before scheduling so the alarm can ring at the exact time.
  static Future<void> requestExactAlarmPermission(FlutterLocalNotificationsPlugin plugin) async {
    if (!Platform.isAndroid) return;
    await plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()?.requestExactAlarmsPermission();
  }

  /// Create alarm notification channel. Call during app init.
  static Future<void> ensureAlarmChannel(FlutterLocalNotificationsPlugin plugin) async {
    if (!Platform.isAndroid) return;
    await plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()?.createNotificationChannel(
      const AndroidNotificationChannel(
        _kAlarmChannelId,
        'Alarms',
        description: 'Reminder alarms',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      ),
    );
  }

  /// Get next scheduled alarm time or null.
  static Future<DateTime?> getNextAlarm() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_kAlarmsPrefsKey);
    if (json == null || json.isEmpty) return null;
    try {
      final list = jsonDecode(json) as List<dynamic>?;
      if (list == null || list.isEmpty) return null;
      DateTime? nearest;
      final now = DateTime.now();
      for (final e in list) {
        final m = e is Map<String, dynamic> ? e : Map<String, dynamic>.from(e as Map);
        final ms = m['scheduledAt'] as int?;
        if (ms != null) {
          final dt = DateTime.fromMillisecondsSinceEpoch(ms);
          if (dt.isAfter(now) && (nearest == null || dt.isBefore(nearest))) {
            nearest = dt;
          }
        }
      }
      return nearest;
    } catch (_) {
      return null;
    }
  }

  /// Schedule an alarm at the given time. Replaces any existing alarm for the same id.
  static Future<bool> scheduleAlarm(
    DateTime scheduledTime, {
    required FlutterLocalNotificationsPlugin plugin,
    String title = 'Alarm',
    String body = 'Your alarm',
  }) async {
    await initializeTimezone();
    await ensureAlarmChannel(plugin);

    if (scheduledTime.isBefore(DateTime.now())) {
      return false;
    }

    final id = _kAlarmNotificationIdBase + scheduledTime.millisecondsSinceEpoch % 100000;
    final tzScheduled = tz.TZDateTime.from(scheduledTime, tz.local);

    const androidDetails = AndroidNotificationDetails(
      _kAlarmChannelId,
      'Alarms',
      channelDescription: 'Reminder alarms',
      importance: Importance.max,
      priority: Priority.max,
      icon: '@drawable/ic_notification',
      fullScreenIntent: true,
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    try {
      await cancelAllAlarms(plugin);
      await plugin.zonedSchedule(
        id,
        title,
        body,
        tzScheduled,
        const NotificationDetails(android: androidDetails, iOS: iosDetails),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );

      await _saveAlarm(id, scheduledTime);
      if (kDebugMode) {
        debugPrint('[AlarmService] Scheduled alarm at $scheduledTime id=$id');
      }
      return true;
    } on PlatformException catch (e) {
      if (e.code == 'exact_alarms_not_permitted') {
        try {
          await cancelAllAlarms(plugin);
          await plugin.zonedSchedule(
            id,
            title,
            body,
            tzScheduled,
            const NotificationDetails(android: androidDetails, iOS: iosDetails),
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            uiLocalNotificationDateInterpretation:
                UILocalNotificationDateInterpretation.absoluteTime,
          );
          await _saveAlarm(id, scheduledTime);
          if (kDebugMode) {
            debugPrint('[AlarmService] Scheduled (inexact) at $scheduledTime id=$id');
          }
          return true;
        } catch (_) {
          if (kDebugMode) debugPrint('[AlarmService] Inexact schedule also failed');
          return false;
        }
      }
      if (kDebugMode) debugPrint('[AlarmService] scheduleAlarm failed: $e');
      return false;
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[AlarmService] scheduleAlarm failed: $e $st');
      }
      return false;
    }
  }

  static Future<void> _saveAlarm(int id, DateTime scheduledAt) async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_kAlarmsPrefsKey);
    List<Map<String, dynamic>> list = [];
    if (json != null && json.isNotEmpty) {
      try {
        final decoded = jsonDecode(json) as List<dynamic>?;
        if (decoded != null) {
          list = decoded
              .map((e) => e is Map<String, dynamic> ? e : Map<String, dynamic>.from(e as Map))
              .toList();
        }
      } catch (_) {}
    }
    list.removeWhere((m) => m['id'] == id);
    list.add({'id': id, 'scheduledAt': scheduledAt.millisecondsSinceEpoch});
    await prefs.setString(_kAlarmsPrefsKey, jsonEncode(list));
  }

  /// Cancel all scheduled alarms.
  static Future<void> cancelAllAlarms(FlutterLocalNotificationsPlugin plugin) async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_kAlarmsPrefsKey);
    if (json == null || json.isEmpty) return;
    try {
      final list = jsonDecode(json) as List<dynamic>?;
      if (list != null) {
        for (final e in list) {
          final m = e is Map<String, dynamic> ? e : Map<String, dynamic>.from(e as Map);
          final id = m['id'] as int?;
          if (id != null) {
            await plugin.cancel(id);
          }
        }
      }
    } catch (_) {}
    await prefs.remove(_kAlarmsPrefsKey);
    if (kDebugMode) debugPrint('[AlarmService] Canceled all alarms');
  }
}
