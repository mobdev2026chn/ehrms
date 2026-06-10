import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_client.dart';
import 'alarm_service.dart';
import 'break_reminder_service.dart';
import '../config/app_colors.dart';
import '../screens/requests/my_requests_screen.dart';
import '../screens/attendance/attendance_screen.dart';
import '../screens/attendance/break_screen.dart';
import '../screens/performance/performance_module_screen.dart';
import '../screens/announcements/announcements_screen.dart';
import '../screens/announcements/announcement_detail_screen.dart';
import '../screens/salary/all_payslips_screen.dart';
import '../screens/grievance/grievance_shell_screen.dart';
import '../screens/interaction/interaction_shell_screen.dart';
import '../screens/assets/assets_listing_screen.dart';
import '../screens/lms/lms_shell_screen.dart';
import '../screens/geo/my_tasks_screen.dart';
import '../widgets/notification_reaction_overlay.dart';
import 'interaction_service.dart';

/// Channel ID for FCM notifications. Must match Android default channel when using data-only messages.
const String kFcmNotificationChannelId = 'hrms_fcm_channel';

/// Non-null, non-blank string; otherwise null (FCM often sends [RemoteNotification] with empty strings — `??` would not fall through to [data]).
String? _fcmNonBlank(String? s) {
  final t = s?.trim();
  if (t == null || t.isEmpty) return null;
  return t;
}

/// Top-level handler for FCM messages received in background or when app is closed.
/// When the payload has no title and no body, nothing is stored or shown. Otherwise stores and shows a tray notification.
/// IMPORTANT: This handler is only invoked for DATA-ONLY messages (no top-level "notification" payload).
/// If the backend sends notification+data, the OS shows the notification but does NOT call this handler,
/// so it will not be stored. Backend must send data-only with title/body inside the "data" payload.
@pragma('vm:entry-point')
Future<void> firebaseBackgroundMessageHandler(RemoteMessage message) async {
  debugPrint(
    '[FCM] backgroundHandler: ENTERED (app closed/background – this runs only for DATA-ONLY messages)',
  );
  debugPrint(
    '[FCM] backgroundHandler: messageId=${message.messageId} hasNotification=${message.notification != null} dataKeys=${message.data.keys.toList()}',
  );
  if (message.notification != null) {
    debugPrint(
      '[FCM] backgroundHandler: WARNING message has notification payload – on Android this handler may not have been invoked; backend should send data-only',
    );
  }
  try {
    await Firebase.initializeApp();
    debugPrint('[FCM] backgroundHandler: Firebase.initializeApp OK');
  } catch (e) {
    debugPrint('[FCM] backgroundHandler: Firebase.initializeApp FAILED $e');
  }
  final data = Map<String, dynamic>.from(message.data);
  if (!FcmService.hasDisplayableRemoteNotification(message)) {
    debugPrint(
      '[FCM] backgroundHandler: skip — no title or body in notification or data',
    );
    return;
  }
  final (:title, :body) = FcmService.displayStringsFromRemoteMessage(message);
  debugPrint(
    '[FCM] backgroundHandler: title="$title" body=${body.length > 40 ? "${body.substring(0, 40)}..." : body}',
  );
  try {
    await FcmService.storeNotification(title: title, body: body, data: data);
    debugPrint(
      '[FCM] backgroundHandler: storeNotification completed – notification should appear in app list',
    );
  } catch (e, st) {
    debugPrint('[FCM] backgroundHandler: storeNotification FAILED $e');
    debugPrint('[FCM] backgroundHandler: stack $st');
  }
  try {
    await _showBackgroundNotification(title: title, body: body, data: data);
    debugPrint('[FCM] backgroundHandler: local notification shown in tray');
  } catch (e) {
    debugPrint(
      '[FCM] backgroundHandler: _showBackgroundNotification FAILED $e',
    );
  }
  debugPrint('[FCM] backgroundHandler: DONE');
}

/// Shows a local notification from the background isolate (so user sees it when message is data-only).
/// Uses a stable id from [data] so duplicate messages for the same event replace the previous notification in the tray.
@pragma('vm:entry-point')
Future<void> _showBackgroundNotification({
  required String title,
  required String body,
  required Map<String, dynamic> data,
}) async {
  final id = FcmService.notificationIdFromData(data);
  final plugin = FlutterLocalNotificationsPlugin();
  const androidSettings = AndroidInitializationSettings(
    '@drawable/ic_notification',
  );
  const iosSettings = DarwinInitializationSettings(
    requestAlertPermission: false,
    requestBadgePermission: false,
  );
  await plugin.initialize(
    const InitializationSettings(android: androidSettings, iOS: iosSettings),
  );
  if (Platform.isAndroid) {
    await plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(
          AndroidNotificationChannel(
            kFcmNotificationChannelId,
            'HRMS Notifications',
            description: 'Notifications for leave, attendance, requests, etc.',
            importance: Importance.high,
            playSound: true,
          ),
        );
  }
  final tag = FcmService.dedupeKeyFromData(data);
  final androidDetails = AndroidNotificationDetails(
    kFcmNotificationChannelId,
    'HRMS Notifications',
    channelDescription: 'Notifications for leave, attendance, requests, etc.',
    importance: Importance.high,
    priority: Priority.high,
    icon: '@drawable/ic_notification',
    tag: tag.isNotEmpty ? tag : null,
  );
  const iosDetails = DarwinNotificationDetails(
    presentAlert: true,
    presentBadge: true,
    presentSound: true,
  );
  await plugin.show(
    id,
    title,
    body,
    NotificationDetails(android: androidDetails, iOS: iosDetails),
    payload: jsonEncode(data),
  );
}

/// Background-isolate handler for taps on locally-shown notification actions
/// (e.g. the break reminder's "End Break" while the app is not in the
/// foreground). The plugin invokes this from its own isolate, where there is no
/// UI to navigate; with `showsUserInterface: true` the OS brings the app
/// forward, and the foreground response / launch-details path then opens the
/// break screen. Must be a top-level vm:entry-point.
@pragma('vm:entry-point')
void fcmLocalNotificationBackgroundResponse(NotificationResponse response) {
  // Intentionally no navigation here — handled on resume/launch.
}

/// Handles FCM: permission, token, foreground/background/terminated messages.
/// Receives notifications sent from web backend (leave/expense/payslip/loan/attendance approve/reject).
///
/// **Background/terminated capture**: The Dart background handler runs only for DATA-ONLY messages.
/// Backend should send FCM with title/body inside the "data" map (e.g. data["title"], data["body"] or data["message"]),
/// and must NOT include a top-level "notification" payload. Otherwise the OS shows the notification but the handler
/// is not invoked and the notification is not stored in the app.
/// Call [init] from main() after Firebase.initializeApp().
/// Set [navigatorKey] so notification taps can open screens (e.g. by module).
class FcmService {
  FcmService._();

  static const String _logTag = '[FCM]';
  static const String _kFcmNotificationsKey = 'fcm_notifications';
  static const String _kFcmNotificationsFileName = 'fcm_notifications.json';
  static const Duration _kFcmNotificationRetention = Duration(hours: 24);
  static const String _kLocalNotificationChannelId = kFcmNotificationChannelId;
  static const Duration _kDedupeWindow = Duration(minutes: 2);

  /// Stable id for system notification so the same event replaces the previous (avoids duplicate tray notifications).
  static int notificationIdFromData(Map<String, dynamic> data) {
    final key = dedupeKeyFromData(data);
    if (key.isEmpty) return DateTime.now().millisecondsSinceEpoch % 100000;
    return key.hashCode.abs() % 100000;
  }

  /// The current logged-in user's stable id. Stored notifications are stamped
  /// with this as their `owner` so personal items (break/leave/permission/etc.)
  /// only surface for the user they belong to — never for whoever logs in next
  /// on the same device. Null when no one is logged in.
  static Future<String?> currentOwnerId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userStr = prefs.getString('user');
      if (userStr != null) {
        final user = jsonDecode(userStr) as Map<String, dynamic>?;
        if (user != null) {
          final id =
              user['staffId']?.toString() ??
              user['_id']?.toString() ??
              user['id']?.toString();
          if (id != null && id.trim().isNotEmpty) return id.trim();
        }
      }
      final staffId = prefs.getString('staffId');
      if (staffId != null && staffId.trim().isNotEmpty) return staffId.trim();
    } catch (_) {}
    return null;
  }

  /// True when a stored notification (stamped with [owner]) should be visible to
  /// the user identified by [currentOwner]. Owner-less entries (legacy items
  /// stored before scoping, or company-wide broadcasts) stay visible to all;
  /// an owned entry shows only for its owner, so personal notifications never
  /// leak to a different user on the same device.
  static bool _isVisibleToOwner(String? owner, String? currentOwner) {
    if (owner == null || owner.isEmpty) return true;
    if (currentOwner == null || currentOwner.isEmpty) return false;
    return owner == currentOwner;
  }

  /// Key to dedupe the same notification (module+type+entityId). Used for storage dedupe and Android notification tag.
  static String dedupeKeyFromData(Map<String, dynamic> data) {
    final type = data['type']?.toString() ?? '';
    final module = data['module']?.toString() ?? '';
    final id =
        data['leaveId'] ??
        data['loanId'] ??
        data['expenseId'] ??
        data['payslipId'] ??
        data['attendanceId'] ??
        data['reviewId'] ??
        data['messageId'] ??
        '';
    if (type.isEmpty && module.isEmpty && id.toString().isEmpty) return '';
    return '${module}_${type}_$id';
  }

  /// Raw title from notification or [data] keys only (no default). Null if absent/blank.
  static String? rawTitleFromRemoteMessage(RemoteMessage message) {
    final data = message.data;
    final fromN = _fcmNonBlank(message.notification?.title);
    if (fromN != null) return fromN;
    for (final key in ['title', 'Title', 'subject', 'Subject']) {
      final v = _fcmNonBlank(data[key]?.toString());
      if (v != null) return v;
    }
    return null;
  }

  /// Raw body from notification or [data] keys only (no default). Null if absent/blank.
  static String? rawBodyFromRemoteMessage(RemoteMessage message) {
    final data = message.data;
    final fromN = _fcmNonBlank(message.notification?.body);
    if (fromN != null) return fromN;
    for (final key in ['body', 'Body', 'message', 'Message', 'text', 'alert']) {
      final v = _fcmNonBlank(data[key]?.toString());
      if (v != null) return v;
    }
    return null;
  }

  static bool hasDisplayableRemoteNotification(RemoteMessage message) {
    return rawTitleFromRemoteMessage(message) != null ||
        rawBodyFromRemoteMessage(message) != null;
  }

  /// Title/body for tray and storage when [hasDisplayableRemoteNotification] is true.
  static ({String title, String body}) displayStringsFromRemoteMessage(
    RemoteMessage message,
  ) {
    final rt = rawTitleFromRemoteMessage(message);
    final rb = rawBodyFromRemoteMessage(message);
    if (rt != null && rb != null) return (title: rt, body: rb);
    if (rt != null) return (title: rt, body: rt);
    return (title: 'HRMS', body: rb!);
  }

  /// Prefer non-blank [RemoteMessage.notification] fields; otherwise read common [data] keys.
  /// Avoids empty `notification.title` blocking real title in `data` (Dart `??` does not skip `''`).
  static String visibleTitleFromRemoteMessage(RemoteMessage message) {
    return rawTitleFromRemoteMessage(message) ?? 'HRMS';
  }

  static String visibleBodyFromRemoteMessage(RemoteMessage message) {
    return rawBodyFromRemoteMessage(message) ?? '';
  }

  static GlobalKey<NavigatorState>? navigatorKey;
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  /// Exposed for AlarmService (scheduled alarms).
  static FlutterLocalNotificationsPlugin get localNotifications =>
      _localNotifications;

  static FirebaseMessaging get _messaging => FirebaseMessaging.instance;

  /// Log for notification debugging – always prints in debug; use for tracing delivery issues.
  static void _log(String message) {
    if (kDebugMode) {
      debugPrint('$_logTag $message');
    }
  }

  /// Log that shows in release too – for critical notification flow checks.
  static void _logAlways(String message) {
    debugPrint('$_logTag $message');
  }

  /// Gets FCM token with retries. Often getToken fails on first try (network/Play Services cold start).
  static Future<String?> _getTokenWithRetry({
    int maxAttempts = 3,
    Duration delayBetween = const Duration(seconds: 2),
  }) async {
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final token = await _messaging.getToken();
        if (token != null && token.isNotEmpty) return token;
      } catch (e) {
        _logAlways('getToken attempt $attempt/$maxAttempts failed: $e');
        if (attempt < maxAttempts) {
          _logAlways('getToken retrying in ${delayBetween.inSeconds}s...');
          await Future<void>.delayed(delayBetween);
        }
      }
    }
    return null;
  }

  /// Initialize FCM: permission, token, handlers. Call once after Firebase.initializeApp().
  static Future<void> init() async {
    _logAlways('init started');
    // Required for showing notifications in tray when app is in foreground
    try {
      await _initLocalNotifications();
      _log('local notifications initialized');
    } catch (e) {
      _logAlways('_initLocalNotifications failed (continuing): $e');
    }
    try {
      await _requestPermission();
    } catch (e) {
      _logAlways('_requestPermission failed (continuing): $e');
    }

    final token = await _getTokenWithRetry();
    _logAlways(
      'getToken: token=${token != null ? "ok(len=${token.length})" : "NULL after retries"}',
    );
    if (token != null) {
      _log('token obtained (length=${token.length}), sending to backend...');
      await sendTokenToBackend();
    } else {
      _logAlways(
        'token is NULL – check Firebase config / google-services.json or network',
      );
    }

    _messaging.onTokenRefresh.listen((newToken) {
      _logAlways(
        'onTokenRefresh: token changed (len=${newToken.length}) – sending to backend',
      );
      sendTokenToBackend();
    });

    FirebaseMessaging.onMessage.listen(_onForegroundMessage);
    _log('foreground listener attached');

    FirebaseMessaging.onMessageOpenedApp.listen(_onNotificationOpened);
    _log('messageOpenedApp listener attached');

    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      if (!hasDisplayableRemoteNotification(initialMessage)) {
        _logAlways(
          'getInitialMessage: skip — no title or body in payload',
        );
      } else {
        _logAlways(
          'getInitialMessage: app opened from terminated via notification tap – storing and navigating',
        );
        final data = Map<String, dynamic>.from(initialMessage.data);
        final (:title, :body) = displayStringsFromRemoteMessage(initialMessage);
        await storeNotification(title: title, body: body, data: data);
        await _handleNotificationData(
          initialMessage.data,
          notificationTitle: title,
          notificationBody: body,
        );
      }
    } else {
      _log('getInitialMessage: none (normal launch)');
    }
    // App launched from a tap on a local notification (e.g. the break reminder's
    // "End Break" action while terminated): route once the navigator is ready.
    try {
      final launchDetails = await _localNotifications
          .getNotificationAppLaunchDetails();
      if (launchDetails?.didNotificationLaunchApp == true) {
        final resp = launchDetails!.notificationResponse;
        if (resp != null) {
          _logAlways(
            'getNotificationAppLaunchDetails: launched via local notification '
            'action=${resp.actionId}',
          );
          _onLocalNotificationResponse(resp);
        }
      }
    } catch (e) {
      _logAlways('getNotificationAppLaunchDetails failed (continuing): $e');
    }
    _logAlways(
      'init completed – foreground/background/terminated handlers attached. Background/closed notifications show in-app ONLY if server sends DATA-ONLY (no top-level notification payload).',
    );
  }

  static Future<void> _initLocalNotifications() async {
    const androidSettings = AndroidInitializationSettings(
      '@drawable/ic_notification',
    );
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
    );
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onLocalNotificationResponse,
      onDidReceiveBackgroundNotificationResponse:
          fcmLocalNotificationBackgroundResponse,
    );
    if (Platform.isAndroid) {
      await _localNotifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(
            AndroidNotificationChannel(
              _kLocalNotificationChannelId,
              'HRMS Notifications',
              importance: Importance.high,
              playSound: true,
            ),
          );
      // Alarm channel for scheduled reminders (works when app is closed)
      await AlarmService.ensureAlarmChannel(_localNotifications);
    }
  }

  /// Foreground/background-resumed handler for taps on locally-shown
  /// notifications (FCM tray copies and the break reminder). Routes the break
  /// reminder's "End Break" action to the break screen; otherwise decodes the
  /// JSON payload and navigates by module/type.
  static void _onLocalNotificationResponse(NotificationResponse response) {
    if (response.actionId == BreakReminderService.endBreakActionId) {
      unawaited(
        _handleNotificationData(const {
          'module': 'break',
          'type': 'break_reminder',
        }),
      );
      return;
    }
    if (response.payload != null && response.payload!.isNotEmpty) {
      try {
        final data = jsonDecode(response.payload!) as Map<String, dynamic>?;
        if (data != null) {
          unawaited(_handleNotificationData(data));
        }
      } catch (_) {}
    }
  }

  static Future<void> _requestPermission() async {
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    _logAlways(
      'permission: ${settings.authorizationStatus} (0=notDetermined,1=denied,2=authorized,3=provisional)',
    );
  }

  /// Sends the current FCM token to the backend so it can target this device for push.
  /// Backend should implement POST /notifications/fcm-token with body { "fcmToken": "..." }.
  /// Uses retry for getToken to handle transient IOException/ExecutionException. Never throws.
  /// Returns true if the token was sent successfully, false if skipped (no token / not logged in) or failed.
  static Future<bool> sendTokenToBackend() async {
    try {
      final fcmToken = await _getTokenWithRetry();
      if (fcmToken == null || fcmToken.isEmpty) {
        _logAlways('sendTokenToBackend: no FCM token, skip');
        return false;
      }
      final prefs = await SharedPreferences.getInstance();
      String? authToken = prefs.getString('token');
      if (authToken != null &&
          (authToken.startsWith('"') || authToken.endsWith('"'))) {
        authToken = authToken.replaceAll('"', '');
      }
      if (authToken == null || authToken.isEmpty) {
        _logAlways(
          'sendTokenToBackend: user not logged in (no auth token), skip – will retry after login',
        );
        return false;
      }
      _logAlways(
        'sendTokenToBackend: posting fcm-token (len=${fcmToken.length})',
      );
      final api = ApiClient();
      api.setAuthToken(authToken);
      final response = await api.dio.post<dynamic>(
        '/notifications/fcm-token',
        data: {'fcmToken': fcmToken},
      );
      final preview = fcmToken.length > 16
          ? '${fcmToken.substring(0, 8)}...${fcmToken.substring(fcmToken.length - 6)}'
          : 'short';
      _logAlways(
        'sendTokenToBackend: success status=${response.statusCode} tokenPreview=$preview',
      );
      return response.statusCode == 200;
    } catch (e, st) {
      _logAlways('sendTokenToBackend: FAILED (getToken or POST) – $e');
      if (kDebugMode) debugPrint('$_logTag sendTokenToBackend stack: $st');
      return false;
    }
  }

  /// Call after login to register FCM token. Sends immediately and retries once after
  /// a short delay so token is reliably registered even if FCM was not ready on first try.
  static Future<void> sendTokenToBackendAfterLogin() async {
    final sent = await sendTokenToBackend();
    if (sent) return;
    // Token may not be ready yet (e.g. first launch). Retry once after delay.
    _logAlways(
      'sendTokenToBackendAfterLogin: first attempt skipped/failed, retrying in 2s',
    );
    await Future<void>.delayed(const Duration(seconds: 2));
    await sendTokenToBackend();
  }

  static Future<void> _onForegroundMessage(RemoteMessage message) async {
    _logAlways(
      '[FCM] FOREGROUND message received – storing (app was in foreground)',
    );
    final data = Map<String, dynamic>.from(message.data);
    if (!hasDisplayableRemoteNotification(message)) {
      _logAlways(
        '[FCM] FOREGROUND message skipped — no title or body in payload',
      );
      return;
    }
    final (:title, :body) = displayStringsFromRemoteMessage(message);

    _logAlways(
      'foreground message: title=$title body=${body.length > 60 ? "${body.substring(0, 60)}..." : body}',
    );

    // Store in SharedPreferences immediately so it appears in Notifications screen
    await storeNotification(title: title, body: body, data: data);

    // Show system notification (outside app – in notification tray) when app is in foreground
    await _showForegroundSystemNotification(
      title: title,
      body: body,
      data: data,
    );

    // Show in-app notification at same position as app snackbars (top: padding.top + 12, left/right 16)
    final context = navigatorKey?.currentContext;
    if (context != null && context.mounted) {
      SystemSound.play(SystemSoundType.alert);
      await _showForegroundReactionIfNeeded(
        context,
        title: title,
        body: body,
        data: data,
      );
      final overlay = Navigator.of(context, rootNavigator: true).overlay;
      if (overlay != null) {
        OverlayEntry? entry;
        void remove() {
          entry?.remove();
          entry = null;
        }

        entry = OverlayEntry(
          builder: (ctx) => Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            left: 16,
            right: 16,
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.primary,
                      AppColors.primary.withOpacity(0.85),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withOpacity(0.4),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                  border: Border.all(
                    color: Colors.white.withOpacity(0.2),
                    width: 1.5,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.notifications_outlined,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        body.isNotEmpty ? body : title,
                        textAlign: TextAlign.left,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          letterSpacing: 0.1,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.close,
                        size: 20,
                        color: Colors.white,
                      ),
                      onPressed: () {
                        remove();
                      },
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                      style: IconButton.styleFrom(
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        overlay.insert(entry!);
        Future.delayed(const Duration(seconds: 4), () {
          if (entry != null) remove();
        });
      }
    }
  }

  static Future<void> _showForegroundReactionIfNeeded(
    BuildContext context, {
    required String title,
    required String body,
    required Map<String, dynamic> data,
  }) async {
    final reaction = _getNotificationReaction(
      title: title,
      body: body,
      data: data,
    );
    if (reaction == null) return;

    await NotificationReactionOverlay.show(context, emoji: reaction.emoji);
  }

  static _NotificationReaction? _getNotificationReaction({
    required String title,
    required String body,
    required Map<String, dynamic> data,
  }) {
    final type = data['type']?.toString().toLowerCase() ?? '';
    final module = data['module']?.toString().toLowerCase() ?? '';
    final combinedText = '$title $body'.toLowerCase();
    final isAnnouncement =
        type == 'announcement' ||
        module == 'announcement' ||
        module == 'announcements' ||
        combinedText.contains('announcement');
    final isBirthday = type == 'birthday' || combinedText.contains('birthday');
    final isAnniversary =
        type == 'anniversary' || combinedText.contains('anniversary');

    final isApproval =
        type.endsWith('_approved') ||
        combinedText.contains(' approved') ||
        combinedText.contains('has been approved') ||
        combinedText.contains('request approved');
    final isRejection =
        type.endsWith('_rejected') ||
        combinedText.contains(' rejected') ||
        combinedText.contains('has been rejected') ||
        combinedText.contains('was rejected') ||
        combinedText.contains('request rejected');

    if (isAnnouncement) {
      return _NotificationReaction(emoji: '📢');
    }

    if (isBirthday) {
      return _NotificationReaction(emoji: '🎂');
    }

    if (isAnniversary) {
      return _NotificationReaction(emoji: '🥳');
    }

    if (!isApproval && !isRejection) return null;

    if (isApproval) {
      return _NotificationReaction(emoji: '🤩');
    }

    return _NotificationReaction(emoji: '😔');
  }

  /// Shows a local tray notification + in-app overlay banner when the employee
  /// exceeds their leave or permission quota.
  /// [type] must be `'leave'` or `'permission'`.
  /// Tapping the notification navigates to [AttendanceScreen].
  static Future<void> showLimitExceededLocalNotification({
    required String type,
    required String message,
  }) async {
    final title = type == 'permission'
        ? 'Permission Quota Exceeded'
        : 'Leave Balance Exceeded';
    const data = <String, dynamic>{
      'module': 'attendance',
      'type': 'limit_exceeded',
    };
    try {
      final id = 'limit_$type'.hashCode.abs() % 100000;
      final androidDetails = AndroidNotificationDetails(
        _kLocalNotificationChannelId,
        'HRMS Notifications',
        channelDescription:
            'Notifications for leave, attendance, requests, etc.',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@drawable/ic_notification',
      );
      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );
      await _localNotifications.show(
        id,
        title,
        message,
        NotificationDetails(android: androidDetails, iOS: iosDetails),
        payload: jsonEncode(data),
      );
      await storeNotification(title: title, body: message, data: data);
      _logAlways('showLimitExceededLocalNotification: shown ($type)');
    } catch (e) {
      if (kDebugMode) {
        debugPrint('$_logTag showLimitExceededLocalNotification: $e');
      }
    }

    // In-app foreground overlay banner (orange warning theme)
    final context = navigatorKey?.currentContext;
    if (context != null && context.mounted) {
      SystemSound.play(SystemSoundType.alert);
      final overlay = Navigator.of(context, rootNavigator: true).overlay;
      if (overlay != null) {
        OverlayEntry? entry;
        void remove() {
          entry?.remove();
          entry = null;
        }

        entry = OverlayEntry(
          builder: (ctx) => Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            left: 16,
            right: 16,
            child: Material(
              color:AppColors.primary,
              child: GestureDetector(
                onTap: () {
                  remove();
                  unawaited(_handleNotificationData(data));
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 14,
                  ),
                  // decoration: BoxDecoration(
                  //   gradient: LinearGradient(
                  //     colors: [
                  //       Colors.orange.shade700,
                  //       Colors.orange.shade600,
                  //     ],
                  //     begin: Alignment.topLeft,
                  //     end: Alignment.bottomRight,
                  //   ),
                  //   borderRadius: BorderRadius.circular(20),
                  //   boxShadow: [
                  //     BoxShadow(
                  //       color: Colors.orange.withOpacity(0.4),
                  //       blurRadius: 20,
                  //       offset: const Offset(0, 10),
                  //     ),
                  //   ],
                  //   border: Border.all(
                  //     color: Colors.white.withOpacity(0.2),
                  //     width: 1.5,
                  //   ),
                  // ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.warning_amber_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              message,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w500,
                                fontSize: 12,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.close,
                          size: 20,
                          color: Colors.white,
                        ),
                        onPressed: remove,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                        style: IconButton.styleFrom(
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        overlay.insert(entry!);
        Future.delayed(const Duration(seconds: 6), () {
          if (entry != null) remove();
        });
      }
    }
  }

  static Future<void> _showForegroundSystemNotification({
    required String title,
    required String body,
    required Map<String, dynamic> data,
  }) async {
    try {
      final id = notificationIdFromData(data);
      final tag = dedupeKeyFromData(data);
      final androidDetails = AndroidNotificationDetails(
        _kLocalNotificationChannelId,
        'HRMS Notifications',
        channelDescription:
            'Notifications for leave, attendance, requests, etc.',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@drawable/ic_notification',
        tag: tag.isNotEmpty ? tag : null,
      );
      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );
      final details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );
      await _localNotifications.show(
        id,
        title,
        body,
        details,
        payload: jsonEncode(data),
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('$_logTag _showForegroundSystemNotification: $e');
      }
    }
  }

  /// Saves one notification (foreground or background) and prunes entries older than 24h.
  /// Skips storing if the same event (same dedupe key) was already stored within the last 2 minutes to avoid duplicates.
  /// Uses file storage so background isolate writes are visible when app is resumed (no per-isolate cache).
  /// Call from foreground handler, background handler, or when user opens app via notification tap.
  static Future<void> storeNotification({
    required String title,
    required String body,
    required Map<String, dynamic> data,
  }) async {
    debugPrint(
      '$_logTag storeNotification: called title="$title" bodyLength=${body.length}',
    );
    try {
      final owner = await currentOwnerId();
      // If the payload is explicitly addressed to a staff member who is NOT the
      // user currently logged in on this device, don't store it — a personal
      // notification (break/leave/permission/etc.) must never surface for
      // anyone but its recipient.
      final payloadStaffId = data['staffId']?.toString().trim();
      if (payloadStaffId != null &&
          payloadStaffId.isNotEmpty &&
          owner != null &&
          owner.isNotEmpty &&
          payloadStaffId != owner) {
        debugPrint(
          '$_logTag storeNotification: SKIP — addressed to staffId=$payloadStaffId, current owner=$owner',
        );
        return;
      }
      final now = DateTime.now();
      final cutoff = now.subtract(_kFcmNotificationRetention);
      final list = await _loadRawListFromFile();
      final pruned = list.where((e) {
        final receivedAt = e['receivedAt']?.toString();
        if (receivedAt == null) return false;
        final dt = DateTime.tryParse(receivedAt);
        return dt != null && dt.isAfter(cutoff);
      }).toList();
      debugPrint(
        '$_logTag storeNotification: current list size=${pruned.length} (after 24h prune)',
      );
      final incomingKey = dedupeKeyFromData(data);
      debugPrint('$_logTag storeNotification: dedupeKey="$incomingKey"');
      if (incomingKey.isNotEmpty) {
        final dedupeCutoff = now.subtract(_kDedupeWindow);
        final isDuplicate = pruned.any((e) {
          final receivedAt = e['receivedAt']?.toString();
          if (receivedAt == null) return false;
          final dt = DateTime.tryParse(receivedAt);
          if (dt == null || dt.isBefore(dedupeCutoff)) return false;
          final existingData = e['data'];
          if (existingData is! Map) return false;
          return dedupeKeyFromData(Map<String, dynamic>.from(existingData)) ==
              incomingKey;
        });
        if (isDuplicate) {
          debugPrint(
            '$_logTag storeNotification: SKIP duplicate (same key within 2min) key=$incomingKey',
          );
          return;
        }
      }
      pruned.insert(0, {
        'title': title,
        'body': body,
        'data': data,
        'owner': owner,
        'receivedAt': now.toUtc().toIso8601String(),
      });
      await _saveRawListToFile(pruned);
      debugPrint(
        '$_logTag storeNotification: STORED OK – list size now ${pruned.length}',
      );
    } catch (e, st) {
      debugPrint('$_logTag storeNotification ERROR: $e');
      debugPrint('$_logTag storeNotification stack: $st');
    }
  }

  /// File-based storage so background isolate writes are visible when app is resumed (SharedPreferences is cached per-isolate).
  static Future<String> _getNotificationsFilePath() async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/$_kFcmNotificationsFileName';
  }

  static Future<List<dynamic>> _loadRawListFromFile() async {
    try {
      final path = await _getNotificationsFilePath();
      final file = File(path);
      if (!await file.exists()) return _migrateFromSharedPreferencesIfAny();
      final raw = await file.readAsString();
      if (raw.isEmpty) return [];
      final decoded = jsonDecode(raw);
      if (decoded is List) return List<dynamic>.from(decoded);
      return [];
    } catch (e) {
      debugPrint('$_logTag _loadRawListFromFile: $e');
      return [];
    }
  }

  /// One-time migration: if file doesn't exist, try reading from SharedPreferences (old storage) and write to file.
  static Future<List<dynamic>> _migrateFromSharedPreferencesIfAny() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kFcmNotificationsKey);
      if (raw == null || raw.isEmpty) return [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      final list = List<dynamic>.from(decoded);
      final path = await _getNotificationsFilePath();
      await File(path).writeAsString(jsonEncode(list));
      await prefs.remove(_kFcmNotificationsKey);
      debugPrint(
        '$_logTag migrated ${list.length} notifications from SharedPreferences to file',
      );
      return list;
    } catch (_) {
      return [];
    }
  }

  static Future<void> _saveRawListToFile(List<dynamic> list) async {
    try {
      final path = await _getNotificationsFilePath();
      await File(path).writeAsString(jsonEncode(list));
    } catch (e) {
      debugPrint('$_logTag _saveRawListToFile: $e');
    }
  }

  /// Returns notifications received in foreground/background, kept for 24h from receipt. Prunes old entries.
  /// Reads from file so we always see latest (including what background isolate wrote when app was in recent apps).
  static Future<List<Map<String, dynamic>>> getStoredNotifications() async {
    final cutoff = DateTime.now().subtract(_kFcmNotificationRetention);
    final list = await _loadRawListFromFile();
    final pruned = <Map<String, dynamic>>[];
    for (final e in list) {
      if (e is! Map) continue;
      final map = Map<String, dynamic>.from(e);
      final receivedAt = map['receivedAt']?.toString();
      if (receivedAt == null) continue;
      final dt = DateTime.tryParse(receivedAt);
      if (dt == null || dt.isBefore(cutoff)) continue;
      pruned.add(map);
    }
    // Persist only the time-based prune — the file holds every user's items so a
    // different user's valid notifications are never dropped from the device.
    if (pruned.length != list.length) {
      await _saveRawListToFile(pruned);
    }
    // Scope to the current user: personal notifications stamped with another
    // user's `owner` are hidden, so break/leave/permission and other personal
    // items only show for the concerned user (and never on a shared device).
    final owner = await currentOwnerId();
    final visible = pruned
        .where((m) => _isVisibleToOwner(m['owner']?.toString(), owner))
        .toList();
    debugPrint(
      '$_logTag getStoredNotifications: returning ${visible.length} item(s) '
      'for owner=$owner (of ${pruned.length} stored)',
    );
    return visible;
  }

  /// Removes every stored notification from this device. Call on logout so a
  /// user's personal notifications never linger for the next person to sign in.
  static Future<void> clearStoredNotifications() async {
    try {
      final path = await _getNotificationsFilePath();
      final file = File(path);
      if (await file.exists()) await file.delete();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kFcmNotificationsKey);
      debugPrint('$_logTag clearStoredNotifications: cleared');
    } catch (e) {
      debugPrint('$_logTag clearStoredNotifications: $e');
    }
  }

  static Future<void> _onNotificationOpened(RemoteMessage message) async {
    _logAlways(
      'onMessageOpenedApp: notification tap (app was background) – storing and navigating',
    );
    _log('notification opened (background/terminated): data=${message.data}');
    if (!hasDisplayableRemoteNotification(message)) {
      _logAlways('onMessageOpenedApp: skip — no title or body in payload');
      return;
    }
    final data = Map<String, dynamic>.from(message.data);
    final (:title, :body) = displayStringsFromRemoteMessage(message);
    await storeNotification(title: title, body: body, data: data);
    await _handleNotificationData(
      message.data,
      notificationTitle: title,
      notificationBody: body,
    );
  }

  static String? _announcementIdFromData(Map<String, dynamic> data) {
    for (final key in [
      'announcementId',
      'announcement_id',
      'announcementMongoId',
      'mongoId',
      '_id',
      'id',
    ]) {
      final v = data[key]?.toString().trim();
      if (v != null && v.isNotEmpty) return v;
    }
    return null;
  }

  /// Infers the canonical module from notification title/body when FCM `data` omits
  /// `module`/`type`, so tapping a stored notification still routes to the right screen.
  /// Most-specific keywords first (e.g. "reimbursement" → expense before generic checks).
  static String _inferModuleFromText(String text) {
    if (text.contains('reimbursement') ||
        text.contains('expense') ||
        text.contains('claim')) {
      return 'expense';
    }
    if (text.contains('loan')) return 'loan';
    if (text.contains('payslip') ||
        text.contains('pay slip') ||
        text.contains('salary slip')) {
      return 'payslip';
    }
    if (text.contains('permission')) return 'permission';
    if (text.contains('leave')) return 'leave';
    if (text.contains('attendance')) return 'attendance';
    if (text.contains('grievance') || text.contains('complaint')) {
      return 'grievance';
    }
    if (text.contains('poll') ||
        text.contains('message') ||
        text.contains('chat')) {
      return 'chat';
    }
    if (text.contains('license') ||
        text.contains('asset')) {
      return 'asset';
    }
    if (text.contains('course') ||
        text.contains('quiz') ||
        text.contains('assessment') ||
        text.contains('learning') ||
        text.contains('lms')) {
      return 'lms';
    }
    if (text.contains('task')) return 'task';
    if (text.contains('performance') ||
        text.contains('appraisal') ||
        text.contains('review')) {
      return 'performance';
    }
    return '';
  }

  static bool _isAnnouncementNotification(
    Map<String, dynamic> data, {
    String? notificationTitle,
    String? notificationBody,
  }) {
    final module = (data['module'] ?? '').toString().toLowerCase();
    final type = (data['type'] ?? '').toString().toLowerCase();
    final screen = (data['screen'] ?? data['route'] ?? '').toString().toLowerCase();
    final text =
        '${notificationTitle ?? ''} ${notificationBody ?? ''}'.toLowerCase();
    if (screen == 'announcement' || screen == 'announcements') return true;
    if (type == 'announcement' ||
        module == 'announcement' ||
        module == 'announcements') {
      return true;
    }
    if (text.contains('announcement')) return true;
    for (final key in [
      'announcementId',
      'announcement_id',
      'announcementMongoId',
    ]) {
      final v = data[key]?.toString().trim();
      if (v != null && v.isNotEmpty) return true;
    }
    return false;
  }

  /// Maps an explicit `screen`/`route` value from the notification payload to a
  /// Flutter screen, so a notification can target a screen directly (independent
  /// of `module`). Returns null for unknown keys — the caller then falls back to
  /// module routing — and for announcements, which are handled separately so an
  /// id can open the detail view instead of the list.
  static Widget? _screenForKey(String key, Map<String, dynamic> data) {
    switch (key) {
      case 'attendance':
        return AttendanceScreen();
      case 'break':
        return const BreakScreen();
      case 'leave':
        return MyRequestsScreen(initialTabIndex: 0);
      case 'loan':
        return MyRequestsScreen(initialTabIndex: 1);
      case 'expense':
        return MyRequestsScreen(initialTabIndex: 2);
      case 'permission':
        return MyRequestsScreen(initialTabIndex: 3);
      case 'requests':
      case 'my_requests':
      case 'myrequests':
        {
          final tab =
              int.tryParse('${data['tab'] ?? data['tabIndex'] ?? 0}') ?? 0;
          return MyRequestsScreen(initialTabIndex: tab);
        }
      case 'payslip':
      case 'payslips':
      case 'salary':
        return const AllPayslipsScreen();
      case 'performance':
        return PerformanceModuleScreen();
      case 'grievance':
      case 'grievances':
        return const GrievanceShellScreen();
      case 'interaction':
      case 'chat':
      case 'chats':
      case 'message':
      case 'messages':
      case 'poll':
      case 'polls':
        return const InteractionShellScreen();
      case 'asset':
      case 'assets':
      case 'license':
      case 'licenses':
        return const AssetsListingScreen();
      case 'lms':
      case 'learning':
      case 'course':
      case 'courses':
        return const LmsShellScreen();
      case 'task':
      case 'tasks':
      case 'geo':
        return const MyTasksScreen();
      default:
        return null;
    }
  }

  /// Returns `true` if a route was pushed.
  ///
  /// [replaceCurrent]: when the tap originates from a screen that should be left
  /// behind (e.g. the NotificationsScreen), the target replaces the current top
  /// route instead of stacking on top of it. This avoids the push-then-pop race
  /// where popping the source screen would pop the freshly-pushed target right
  /// back off the shared root navigator.
  static Future<bool> _handleNotificationData(
    Map<String, dynamic> data, {
    String? notificationTitle,
    String? notificationBody,
    bool replaceCurrent = false,
  }) async {
    _log(
      'handleNotificationData: module=${data['module']} type=${data['type']} data=$data',
    );
    if (navigatorKey?.currentContext == null) {
      _log('handleNotificationData: no navigator context, skip navigation');
      return false;
    }

    final module = data['module']?.toString() ?? data['type']?.toString() ?? '';
    final type = data['type']?.toString() ?? '';

    // When the backend sends only a title/body (no module/type in data), infer the target
    // screen from the notification text so tapping still routes. Skip for announcements
    // (handled separately below) and whenever data already carries module/type.
    final combinedText =
        '${notificationTitle ?? ''} ${notificationBody ?? ''}'.toLowerCase();
    final isAnnouncement = _isAnnouncementNotification(
      data,
      notificationTitle: notificationTitle,
      notificationBody: notificationBody,
    );
    final inferred = (module.isEmpty && type.isEmpty && !isAnnouncement)
        ? _inferModuleFromText(combinedText)
        : '';
    final effModule = module.isNotEmpty ? module : inferred;

    // Check staffId match for user-specific notifications
    final payloadStaffId = data['staffId']?.toString();
    if (payloadStaffId != null && payloadStaffId.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      String? currentStaffId;
      final userStr = prefs.getString('user');
      if (userStr != null) {
        try {
          final user = jsonDecode(userStr) as Map<String, dynamic>?;
          if (user != null) {
            currentStaffId =
                user['staffId']?.toString() ??
                user['_id']?.toString() ??
                user['id']?.toString();
          }
        } catch (_) {}
      }
      currentStaffId ??= prefs.getString('staffId');
      if (currentStaffId != null && currentStaffId != payloadStaffId) {
        _log(
          'handleNotificationData: ignoring – notification is for staffId=$payloadStaffId, current staffId=$currentStaffId',
        );
        return false;
      }
    }

    if (!navigatorKey!.currentContext!.mounted) return false;

    // Single navigation entry point: replace the current route (e.g. the
    // NotificationsScreen) when [replaceCurrent] is set, otherwise stack on top.
    final nav = navigatorKey?.currentState;
    void navPush(MaterialPageRoute<void> route) {
      if (replaceCurrent) {
        nav?.pushReplacement(route);
      } else {
        nav?.push(route);
      }
    }

    // Screen-based routing (preferred): the payload may name a Flutter screen
    // directly via `screen`/`route`, so navigation is driven by the screen rather
    // than the `module`. Unknown keys fall through to module routing below.
    final screenKey =
        (data['screen'] ?? data['route'] ?? '').toString().trim().toLowerCase();
    if (screenKey.isNotEmpty) {
      final target = _screenForKey(screenKey, data);
      if (target != null) {
        _log('handleNotificationData: screen-routing to "$screenKey"');
        navPush(MaterialPageRoute<void>(builder: (_) => target));
        return true;
      }
    }

    // Break reminder ("End Break" action or a tap on the 10-min reminder):
    // open the break screen so the user ends the break with the same selfie +
    // location flow as the on-screen button. The screen loads the active break.
    if (effModule == 'break' || type == 'break_reminder') {
      _log('handleNotificationData: navigating to BreakScreen (break reminder)');
      navPush(
        MaterialPageRoute<void>(builder: (_) => const BreakScreen()),
      );
      return true;
    }
    // Leave: My Requests, tab 0
    if (effModule == 'leave' ||
        type == 'leave_approved' ||
        type == 'leave_rejected' ||
        effModule == 'requests' &&
            (type == 'leave_approved' || type == 'leave_rejected')) {
      _log(
        'handleNotificationData: navigating to MyRequestsScreen tab 0 (leave)',
      );
      navPush(
        MaterialPageRoute<void>(
          builder: (_) => MyRequestsScreen(initialTabIndex: 0),
        ),
      );
      return true;
    }
    // Loan: My Requests, tab 1
    if (effModule == 'loan' ||
        type == 'loan_approved' ||
        type == 'loan_rejected') {
      _log(
        'handleNotificationData: navigating to MyRequestsScreen tab 1 (loan)',
      );
      navPush(
        MaterialPageRoute<void>(
          builder: (_) => MyRequestsScreen(initialTabIndex: 1),
        ),
      );
      return true;
    }
    // Expense: My Requests, tab 2
    if (effModule == 'expense' ||
        type == 'expense_approved' ||
        type == 'expense_rejected') {
      _log(
        'handleNotificationData: navigating to MyRequestsScreen tab 2 (expense)',
      );
      navPush(
        MaterialPageRoute<void>(
          builder: (_) => MyRequestsScreen(initialTabIndex: 2),
        ),
      );
      return true;
    }
    // Payslip: lives under Salary, not in My Requests (which only has tabs 0–3:
    // Leave/Loan/Expense/Permission). Open the payslips list directly.
    if (effModule == 'payslip' ||
        type == 'payslip_approved' ||
        type == 'payslip_rejected' ||
        effModule == 'salary') {
      _log('handleNotificationData: navigating to AllPayslipsScreen (payslip)');
      navPush(
        MaterialPageRoute<void>(builder: (_) => const AllPayslipsScreen()),
      );
      return true;
    }
    // Permission: My Requests, tab 3
    if (effModule == 'permission' ||
        type == 'permission_approved' ||
        type == 'permission_rejected') {
      _log(
        'handleNotificationData: navigating to MyRequestsScreen tab 3 (permission)',
      );
      navPush(
        MaterialPageRoute<void>(
          builder: (_) => MyRequestsScreen(initialTabIndex: 3),
        ),
      );
      return true;
    }
    // Attendance: Attendance screen
    if (effModule == 'attendance' ||
        type == 'attendance_approved' ||
        type == 'attendance_rejected') {
      _log('handleNotificationData: navigating to AttendanceScreen');
      navPush(
        MaterialPageRoute<void>(builder: (_) => AttendanceScreen()),
      );
      return true;
    }
    // Performance: Performance module
    if (effModule == 'performance' ||
        type.startsWith('self_review') ||
        type.startsWith('manager_review') ||
        type.startsWith('hr_review')) {
      _log('handleNotificationData: navigating to PerformanceModuleScreen');
      navPush(
        MaterialPageRoute<void>(builder: (_) => PerformanceModuleScreen()),
      );
      return true;
    }
    // Grievance: grievance shell (My Grievances / Raise)
    if (effModule == 'grievance' ||
        type.startsWith('grievance')) {
      _log('handleNotificationData: navigating to GrievanceShellScreen');
      navPush(
        MaterialPageRoute<void>(builder: (_) => const GrievanceShellScreen()),
      );
      return true;
    }
    // Interaction: chat messages and polls live in the interaction shell.
    if (effModule == 'interaction' ||
        effModule == 'chat' ||
        effModule == 'message' ||
        effModule == 'poll' ||
        type.startsWith('chat') ||
        type.startsWith('message') ||
        type.startsWith('poll')) {
      _log('handleNotificationData: navigating to InteractionShellScreen');
      navPush(
        MaterialPageRoute<void>(builder: (_) => const InteractionShellScreen()),
      );
      return true;
    }
    // Assets / software licenses
    if (effModule == 'asset' ||
        effModule == 'assets' ||
        effModule == 'license' ||
        type.startsWith('asset') ||
        type.startsWith('license')) {
      _log('handleNotificationData: navigating to AssetsListingScreen');
      navPush(
        MaterialPageRoute<void>(builder: (_) => const AssetsListingScreen()),
      );
      return true;
    }
    // LMS: courses, assessments, live sessions
    if (effModule == 'lms' ||
        effModule == 'learning' ||
        effModule == 'course' ||
        type.startsWith('lms') ||
        type.startsWith('course') ||
        type.startsWith('assessment')) {
      _log('handleNotificationData: navigating to LmsShellScreen');
      navPush(
        MaterialPageRoute<void>(builder: (_) => const LmsShellScreen()),
      );
      return true;
    }
    // Geo / field tasks
    if (effModule == 'task' ||
        effModule == 'geo' ||
        type.startsWith('task')) {
      _log('handleNotificationData: navigating to MyTasksScreen');
      navPush(
        MaterialPageRoute<void>(builder: (_) => const MyTasksScreen()),
      );
      return true;
    }
    // Announcements (FCM data may be empty; use stored title/body from NotificationsScreen).
    if (_isAnnouncementNotification(
      data,
      notificationTitle: notificationTitle,
      notificationBody: notificationBody,
    )) {
      final announcementId = _announcementIdFromData(data);
      if (announcementId != null && announcementId.isNotEmpty) {
        try {
          final res =
              await InteractionService.instance.getAnnouncementById(announcementId);
          if (!navigatorKey!.currentContext!.mounted) return false;
          Map<String, dynamic>? ann;
          final raw = res['data'];
          if (raw is Map<String, dynamic>) {
            ann = Map<String, dynamic>.from(raw);
          } else if (raw is Map) {
            ann = Map<String, dynamic>.from(raw);
          }
          if (ann != null && ann.isNotEmpty) {
            final announcementMap = Map<String, dynamic>.from(ann);
            navPush(
              MaterialPageRoute<void>(
                builder: (_) => AnnouncementDetailScreen(
                  announcement: announcementMap,
                  accent: AppColors.primary,
                ),
              ),
            );
            _log(
              'handleNotificationData: navigating to AnnouncementDetailScreen id=$announcementId',
            );
            return true;
          }
        } catch (e) {
          _log('handleNotificationData: announcement detail fetch failed: $e');
        }
      }
      if (!navigatorKey!.currentContext!.mounted) return false;
      navPush(
        MaterialPageRoute<void>(builder: (_) => const AnnouncementsScreen()),
      );
      _log('handleNotificationData: navigating to AnnouncementsScreen');
      return true;
    }
    _log('handleNotificationData: no route matched module=$module effModule=$effModule type=$type');
    return false;
  }

  /// Call when user taps a stored notification (e.g. from NotificationsScreen). Navigates by module/type.
  ///
  /// [replaceCurrent]: pass `true` from a screen that should be left behind (the
  /// NotificationsScreen) so the target replaces it on the shared root navigator
  /// instead of stacking on top — the caller must then NOT pop afterwards.
  static Future<bool> handleNotificationTap(
    Map<String, dynamic> data, {
    String? title,
    String? body,
    bool replaceCurrent = false,
  }) {
    return _handleNotificationData(
      data,
      notificationTitle: title,
      notificationBody: body,
      replaceCurrent: replaceCurrent,
    );
  }

  /// Call this to get the current FCM token (e.g. after login, to send to backend).
  static Future<String?> getToken() => _messaging.getToken();

  /// Subscribe to a topic (e.g. 'attendance', 'leave') for server to send by topic.
  static Future<void> subscribeToTopic(String topic) =>
      _messaging.subscribeToTopic(topic);

  static Future<void> unsubscribeFromTopic(String topic) =>
      _messaging.unsubscribeFromTopic(topic);
}

class _NotificationReaction {
  final String emoji;

  const _NotificationReaction({required this.emoji});
}
