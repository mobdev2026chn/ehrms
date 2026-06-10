import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'fcm_service.dart';

/// Reminds the user every 10 minutes while a break is open, in every app state:
///
///  - **Foreground:** a live [Timer] writes each reminder into the in-app
///    Notifications screen but shows NO tray notification — the on-screen break
///    bar is already visible, so a tray pop-up would be redundant noise.
///  - **Background (app alive):** the live [Timer] still writes to the in-app
///    list, and an OS-scheduled repeat ([periodicallyShowWithDuration], armed on
///    background-entry) surfaces the tray notification.
///  - **App closed / deep background (isolate paused):** the OS-scheduled repeat
///    keeps the tray notification appearing. Those fire in a background isolate
///    with no chance to write to the in-app list, so on the next app resume /
///    break-status poll the service *catches up* — storing any reminder
///    boundaries crossed while away.
///
/// The OS repeat fires from the OS regardless of app state, so it is armed only
/// while backgrounded (see [setAppInForeground]); returning to the foreground
/// disarms it and clears any reminder it left in the tray.
///
/// Reminders are keyed off the real break start time, so elapsed minutes stay
/// correct across app restarts and the catch-up never double-counts.
///
/// The reminder carries an **End Break** action button. Tapping the action (or
/// the body) opens the in-app break screen so the user ends the break through
/// the SAME selfie + location flow as the on-screen End Break button — it never
/// ends silently, because ending requires a fresh selfie and live location.
class BreakReminderService {
  BreakReminderService._();

  /// Stable id for the reminder. Sits in its own range, away from FCM ids
  /// (`% 100000`) and AlarmService ids (`900000+`), so cancels never collide.
  static const int _reminderId = 870001;

  static const String channelId = 'hrms_break_reminder_channel';
  static const String _channelName = 'Break Reminders';
  static const String _channelDescription =
      'Reminds you every 10 minutes while a break is ongoing';

  /// Action id reported by the plugin when the user taps "End Break" on the
  /// reminder. [FcmService] watches for this to route to the break screen.
  static const String endBreakActionId = 'break_reminder_end';

  /// Payload so a plain tap on the reminder routes through the existing
  /// notification handler to the break screen.
  static const String reminderPayload =
      '{"module":"break","type":"break_reminder"}';

  /// Data mirrored into the in-app Notifications screen (same routing as a tap).
  static const Map<String, dynamic> _reminderData = {
    'module': 'break',
    'type': 'break_reminder',
  };

  static const Duration _interval = Duration(minutes: 10);
  static const String _title = 'Break ongoing';

  /// Guards against re-scheduling on every break-status poll. Process-local; a
  /// fresh launch re-syncs via [BreakService].
  static bool _scheduled = false;

  /// Whether the app is currently in the foreground. When true, the tray
  /// notification is suppressed (the in-app break bar is already visible).
  /// Defaults to true because the app is in the foreground on launch.
  static bool _appInForeground = true;

  /// Called by the app lifecycle observer when the app enters or leaves the
  /// foreground, so tray notifications are only shown when backgrounded.
  ///
  /// The OS-scheduled repeat fires from the OS regardless of app state, so it is
  /// only armed while backgrounded — otherwise its 10-minute fire would surface
  /// a tray notification in the foreground, where the in-app break bar is
  /// already visible. Entering the foreground disarms it and clears any reminder
  /// it left in the tray.
  static void setAppInForeground(bool inForeground) {
    final wasInForeground = _appInForeground;
    _appInForeground = inForeground;
    if (!_scheduled || wasInForeground == inForeground) return;
    if (inForeground) {
      unawaited(_disarmOsRepeat());
    } else {
      unawaited(_scheduleOsRepeat());
    }
  }

  /// Live ticker that fires while the app process is alive. Null when no break.
  static Timer? _timer;

  /// Epoch ms of the current break's start (server time when known, else now).
  static int? _startMs;

  /// Highest 10-minute boundary already written to the in-app list, so a
  /// catch-up after background delivery never stores the same reminder twice.
  static int _storedThroughTick = 0;

  static FlutterLocalNotificationsPlugin get _plugin =>
      FcmService.localNotifications;

  static Future<void> _ensureChannel() async {
    if (!Platform.isAndroid) return;
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            channelId,
            _channelName,
            description: _channelDescription,
            importance: Importance.high,
            playSound: true,
          ),
        );
  }

  static NotificationDetails _details() {
    final androidDetails = AndroidNotificationDetails(
      channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.high,
      priority: Priority.high,
      icon: '@drawable/ic_notification',
      category: AndroidNotificationCategory.reminder,
      actions: const [
        AndroidNotificationAction(
          endBreakActionId,
          'End Break',
          showsUserInterface: true,
        ),
      ],
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      categoryIdentifier: 'break_reminder',
    );
    return NotificationDetails(android: androidDetails, iOS: iosDetails);
  }

  static String _recurringBody(int ticks) =>
      'You\'ve been on break for about ${ticks * _interval.inMinutes} minutes. '
      'Tap "End Break" to end it.';

  /// Starts the reminder. Idempotent: a second call while already running is a
  /// no-op, so it is safe to invoke from break start and from every break-status
  /// refresh that reports an open break. [startedAt] anchors elapsed time to the
  /// real break start so reminders stay correct across restarts.
  static Future<void> schedule({DateTime? startedAt}) async {
    if (_scheduled) return;
    _scheduled = true;
    _startMs = (startedAt ?? DateTime.now()).millisecondsSinceEpoch;
    _storedThroughTick = 0;
    try {
      await _ensureChannel();
    } catch (_) {}
    // Live ticker while the app is alive — first fires at the 10-minute mark and
    // every 10 minutes after, showing the tray notification and storing each in
    // the in-app list. (No reminder at break start — only after 10 minutes.)
    _timer?.cancel();
    _timer = Timer.periodic(_interval, (_) => unawaited(_emitDueReminders()));
    // OS-scheduled repeat (first fire at +10 min) for when the app is fully
    // closed / backgrounded — keeps the local notification appearing in the
    // tray. Only armed while NOT in the foreground: in the foreground its OS
    // fire would pop a tray notification the in-app break bar makes redundant.
    // Lifecycle transitions ([setAppInForeground]) arm/disarm it from here on.
    if (!_appInForeground) {
      await _scheduleOsRepeat();
    }
    if (kDebugMode) {
      debugPrint('[BreakReminder] scheduled every ${_interval.inMinutes}min');
    }
  }

  /// Stores any 10-minute reminder boundary that has been crossed but not yet
  /// written to the in-app list (one entry, reflecting current elapsed time),
  /// and refreshes the tray notification. Driven by the live timer, by app
  /// resume, and by break-status polls — so the in-app list stays complete even
  /// when reminders were delivered by the OS while the isolate was paused.
  static Future<void> _emitDueReminders() async {
    if (!_scheduled || _startMs == null) return;
    final elapsedMin =
        (DateTime.now().millisecondsSinceEpoch - _startMs!) ~/ 60000;
    final dueTick = elapsedMin ~/ _interval.inMinutes;
    if (dueTick <= _storedThroughTick) return;
    _storedThroughTick = dueTick;
    await _showAndStore(_recurringBody(dueTick));
  }

  /// Catch-up entry point for app resume — surfaces reminders that the OS
  /// delivered to the tray while the app was backgrounded/closed into the
  /// in-app Notifications list.
  static Future<void> onAppResumed() => _emitDueReminders();

  /// Shows the reminder in the tray (replacing the previous one via the stable
  /// id) and mirrors it into the in-app Notifications screen. The tray
  /// notification is suppressed when the app is in the foreground — the
  /// break bar is already visible so a tray pop-up is unnecessary.
  static Future<void> _showAndStore(String body) async {
    if (!_appInForeground) {
      try {
        await _plugin.show(
          _reminderId,
          _title,
          body,
          _details(),
          payload: reminderPayload,
        );
      } catch (e) {
        if (kDebugMode) debugPrint('[BreakReminder] show failed: $e');
      }
    }
    try {
      await FcmService.storeNotification(
        title: _title,
        body: body,
        data: Map<String, dynamic>.from(_reminderData),
      );
    } catch (_) {}
  }

  static Future<void> _scheduleOsRepeat() async {
    try {
      await _periodicShow(AndroidScheduleMode.exactAllowWhileIdle);
    } on PlatformException catch (e) {
      // Exact alarms blocked (Android 12+ without permission) — fall back to an
      // inexact schedule so the reminder still fires, just not to the second.
      if (kDebugMode) {
        debugPrint('[BreakReminder] exact failed (${e.code}); retry inexact');
      }
      try {
        await _periodicShow(AndroidScheduleMode.inexactAllowWhileIdle);
      } catch (_) {}
    } catch (e) {
      if (kDebugMode) debugPrint('[BreakReminder] os repeat failed: $e');
    }
  }

  /// Cancels the OS-scheduled repeat and clears any reminder it left in the
  /// tray. Called when the app returns to the foreground so no break reminder
  /// lingers on screen while the in-app break bar is visible. Does not touch the
  /// live timer or in-app list — only the tray.
  static Future<void> _disarmOsRepeat() async {
    try {
      await _plugin.cancel(_reminderId);
    } catch (e) {
      if (kDebugMode) debugPrint('[BreakReminder] disarm failed: $e');
    }
  }

  static Future<void> _periodicShow(AndroidScheduleMode mode) {
    return _plugin.periodicallyShowWithDuration(
      _reminderId,
      _title,
      _recurringBody(1),
      _interval,
      _details(),
      androidScheduleMode: mode,
      payload: reminderPayload,
    );
  }

  /// Stops the reminder. Safe to call when none is scheduled.
  static Future<void> cancel() async {
    _scheduled = false;
    _startMs = null;
    _storedThroughTick = 0;
    _timer?.cancel();
    _timer = null;
    try {
      await _plugin.cancel(_reminderId);
      if (kDebugMode) debugPrint('[BreakReminder] cancelled');
    } catch (_) {}
  }

  /// Whether we have reconciled reminder state at least once this process. Lets
  /// the first status check after launch clear a reminder left running by a
  /// previous session that was killed mid-break.
  static bool _reconciledSinceLaunch = false;

  /// Syncs the reminder to the current break state: schedule (and catch up) when
  /// a break is open, cancel otherwise. Lets a single source of truth (the
  /// break-status fetch) keep reminders correct across app restarts and
  /// auto-end-on-checkout. [startedAt] is the open break's real start time.
  static Future<void> sync({
    required bool hasOpenBreak,
    DateTime? startedAt,
  }) async {
    if (hasOpenBreak) {
      _reconciledSinceLaunch = true;
      await schedule(startedAt: startedAt);
      // Already scheduled earlier this session? Still surface any reminders the
      // OS delivered while the app was away.
      await _emitDueReminders();
    } else if (_scheduled || !_reconciledSinceLaunch) {
      // Cancel when one is running, or on the first reconciliation after launch
      // to clear any reminder a killed session left scheduled in the OS.
      _reconciledSinceLaunch = true;
      await cancel();
    }
  }
}
