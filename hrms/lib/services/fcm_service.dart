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
import '../config/app_colors.dart';
import '../screens/requests/my_requests_screen.dart';
import '../screens/attendance/attendance_screen.dart';
import '../screens/performance/performance_module_screen.dart';
import '../widgets/notification_reaction_overlay.dart';

/// Channel ID for FCM notifications. Must match Android default channel when using data-only messages.
const String kFcmNotificationChannelId = 'hrms_fcm_channel';

/// Top-level handler for FCM messages received in background or when app is closed.
/// Stores every message so it appears in the in-app Notifications screen even if the user never taps the notification.
/// IMPORTANT: This handler is only invoked for DATA-ONLY messages (no top-level "notification" payload).
/// If the backend sends notification+data, the OS shows the notification but does NOT call this handler,
/// so it will not be stored. Backend must send data-only with title/body inside the "data" payload.
@pragma('vm:entry-point')
Future<void> firebaseBackgroundMessageHandler(RemoteMessage message) async {
  debugPrint('[FCM] backgroundHandler: ENTERED (app closed/background – this runs only for DATA-ONLY messages)');
  debugPrint('[FCM] backgroundHandler: messageId=${message.messageId} hasNotification=${message.notification != null} dataKeys=${message.data.keys.toList()}');
  if (message.notification != null) {
    debugPrint('[FCM] backgroundHandler: WARNING message has notification payload – on Android this handler may not have been invoked; backend should send data-only');
  }
  try {
    await Firebase.initializeApp();
    debugPrint('[FCM] backgroundHandler: Firebase.initializeApp OK');
  } catch (e) {
    debugPrint('[FCM] backgroundHandler: Firebase.initializeApp FAILED $e');
  }
  final data = Map<String, dynamic>.from(message.data);
  String title =
      message.notification?.title ??
      data['title']?.toString() ??
      'Notification';
  String body =
      message.notification?.body ??
      data['body']?.toString() ??
      data['message']?.toString() ??
      '';
  debugPrint(
    '[FCM] backgroundHandler: title="$title" body=${body.length > 40 ? "${body.substring(0, 40)}..." : body}',
  );
  try {
    await FcmService.storeNotification(title: title, body: body, data: data);
    debugPrint('[FCM] backgroundHandler: storeNotification completed – notification should appear in app list');
  } catch (e, st) {
    debugPrint('[FCM] backgroundHandler: storeNotification FAILED $e');
    debugPrint('[FCM] backgroundHandler: stack $st');
  }
  try {
    await _showBackgroundNotification(title: title, body: body, data: data);
    debugPrint('[FCM] backgroundHandler: local notification shown in tray');
  } catch (e) {
    debugPrint('[FCM] backgroundHandler: _showBackgroundNotification FAILED $e');
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
  const androidSettings = AndroidInitializationSettings('@drawable/ic_notification');
  const iosSettings = DarwinInitializationSettings(
    requestAlertPermission: false,
    requestBadgePermission: false,
  );
  await plugin.initialize(
    const InitializationSettings(android: androidSettings, iOS: iosSettings),
  );
  if (Platform.isAndroid) {
    await plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()?.createNotificationChannel(
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

  /// Key to dedupe the same notification (module+type+entityId). Used for storage dedupe and Android notification tag.
  static String dedupeKeyFromData(Map<String, dynamic> data) {
    final type = data['type']?.toString() ?? '';
    final module = data['module']?.toString() ?? '';
    final id = data['leaveId'] ?? data['loanId'] ?? data['expenseId'] ?? data['payslipId'] ?? data['attendanceId'] ?? data['reviewId'] ?? data['messageId'] ?? '';
    if (type.isEmpty && module.isEmpty && id.toString().isEmpty) return '';
    return '${module}_${type}_$id';
  }

  static GlobalKey<NavigatorState>? navigatorKey;
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  /// Exposed for AlarmService (scheduled alarms).
  static FlutterLocalNotificationsPlugin get localNotifications => _localNotifications;

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
      _logAlways('getInitialMessage: app opened from terminated via notification tap – storing and navigating');
      final data = Map<String, dynamic>.from(initialMessage.data);
      final title =
          initialMessage.notification?.title ??
          data['title']?.toString() ??
          'Notification';
      final body =
          initialMessage.notification?.body ??
          data['body']?.toString() ??
          data['message']?.toString() ??
          '';
      await storeNotification(title: title, body: body, data: data);
      _handleNotificationData(initialMessage.data);
    } else {
      _log('getInitialMessage: none (normal launch)');
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
      onDidReceiveNotificationResponse: (response) {
        if (response.payload != null && response.payload!.isNotEmpty) {
          try {
            final data = jsonDecode(response.payload!) as Map<String, dynamic>?;
            if (data != null) _handleNotificationData(data);
          } catch (_) {}
        }
      },
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
    _logAlways('sendTokenToBackendAfterLogin: first attempt skipped/failed, retrying in 2s');
    await Future<void>.delayed(const Duration(seconds: 2));
    await sendTokenToBackend();
  }

  static Future<void> _onForegroundMessage(RemoteMessage message) async {
    _logAlways('[FCM] FOREGROUND message received – storing (app was in foreground)');
    final data = Map<String, dynamic>.from(message.data);
    final title =
        message.notification?.title ??
        data['title']?.toString() ??
        'Notification';
    final body =
        message.notification?.body ??
        data['body']?.toString() ??
        data['message']?.toString() ??
        '';

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
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
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
                      icon: const Icon(Icons.close, size: 20, color: Colors.white),
                      onPressed: () {
                        remove();
                      },
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
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
    final reaction = _getNotificationReaction(title: title, body: body, data: data);
    if (reaction == null) return;

    await NotificationReactionOverlay.show(
      context,
      emoji: reaction.emoji,
    );
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
    final isBirthday =
        type == 'birthday' ||
        combinedText.contains('birthday');
    final isAnniversary =
        type == 'anniversary' ||
        combinedText.contains('anniversary');

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
      return _NotificationReaction(
        emoji: '📢',
      );
    }

    if (isBirthday) {
      return _NotificationReaction(
        emoji: '🎂',
      );
    }

    if (isAnniversary) {
      return _NotificationReaction(
        emoji: '🥳',
      );
    }

    if (!isApproval && !isRejection) return null;

    if (isApproval) {
      return _NotificationReaction(
        emoji: '🤩',
      );
    }

    return _NotificationReaction(
      emoji: '😔',
    );
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
      if (kDebugMode)
        debugPrint('$_logTag _showForegroundSystemNotification: $e');
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
    debugPrint('$_logTag storeNotification: called title="$title" bodyLength=${body.length}');
    try {
      final now = DateTime.now();
      final cutoff = now.subtract(_kFcmNotificationRetention);
      final list = await _loadRawListFromFile();
      final pruned = list.where((e) {
        final receivedAt = e['receivedAt']?.toString();
        if (receivedAt == null) return false;
        final dt = DateTime.tryParse(receivedAt);
        return dt != null && dt.isAfter(cutoff);
      }).toList();
      debugPrint('$_logTag storeNotification: current list size=${pruned.length} (after 24h prune)');
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
          return dedupeKeyFromData(Map<String, dynamic>.from(existingData)) == incomingKey;
        });
        if (isDuplicate) {
          debugPrint('$_logTag storeNotification: SKIP duplicate (same key within 2min) key=$incomingKey');
          return;
        }
      }
      pruned.insert(0, {
        'title': title,
        'body': body,
        'data': data,
        'receivedAt': now.toUtc().toIso8601String(),
      });
      await _saveRawListToFile(pruned);
      debugPrint('$_logTag storeNotification: STORED OK – list size now ${pruned.length}');
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
      debugPrint('$_logTag migrated ${list.length} notifications from SharedPreferences to file');
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
    if (pruned.length != list.length) {
      await _saveRawListToFile(pruned);
    }
    debugPrint('$_logTag getStoredNotifications: returning ${pruned.length} item(s)');
    return pruned;
  }

  static Future<void> _onNotificationOpened(RemoteMessage message) async {
    _logAlways('onMessageOpenedApp: notification tap (app was background) – storing and navigating');
    _log('notification opened (background/terminated): data=${message.data}');
    final data = Map<String, dynamic>.from(message.data);
    final title =
        message.notification?.title ??
        data['title']?.toString() ??
        'Notification';
    final body =
        message.notification?.body ??
        data['body']?.toString() ??
        data['message']?.toString() ??
        '';
    await storeNotification(title: title, body: body, data: data);
    _handleNotificationData(message.data);
  }

  static Future<void> _handleNotificationData(Map<String, dynamic> data) async {
    _log(
      'handleNotificationData: module=${data['module']} type=${data['type']} data=$data',
    );
    if (navigatorKey?.currentContext == null) {
      _log('handleNotificationData: no navigator context, skip navigation');
      return;
    }

    final module = data['module']?.toString() ?? data['type']?.toString() ?? '';
    final type = data['type']?.toString() ?? '';

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
        return;
      }
    }

    if (!navigatorKey!.currentContext!.mounted) return;

    // Leave: My Requests, tab 0
    if (module == 'leave' ||
        type == 'leave_approved' ||
        type == 'leave_rejected' ||
        module == 'requests' &&
            (type == 'leave_approved' || type == 'leave_rejected')) {
      _log(
        'handleNotificationData: navigating to MyRequestsScreen tab 0 (leave)',
      );
      navigatorKey?.currentState?.push(
        MaterialPageRoute<void>(
          builder: (_) => MyRequestsScreen(initialTabIndex: 0),
        ),
      );
      return;
    }
    // Loan: My Requests, tab 1
    if (module == 'loan' ||
        type == 'loan_approved' ||
        type == 'loan_rejected') {
      _log(
        'handleNotificationData: navigating to MyRequestsScreen tab 1 (loan)',
      );
      navigatorKey?.currentState?.push(
        MaterialPageRoute<void>(
          builder: (_) => MyRequestsScreen(initialTabIndex: 1),
        ),
      );
      return;
    }
    // Expense: My Requests, tab 2
    if (module == 'expense' ||
        type == 'expense_approved' ||
        type == 'expense_rejected') {
      _log(
        'handleNotificationData: navigating to MyRequestsScreen tab 2 (expense)',
      );
      navigatorKey?.currentState?.push(
        MaterialPageRoute<void>(
          builder: (_) => MyRequestsScreen(initialTabIndex: 2),
        ),
      );
      return;
    }
    // Payslip: My Requests, tab 3
    if (module == 'payslip' ||
        type == 'payslip_approved' ||
        type == 'payslip_rejected') {
      _log(
        'handleNotificationData: navigating to MyRequestsScreen tab 3 (payslip)',
      );
      navigatorKey?.currentState?.push(
        MaterialPageRoute<void>(
          builder: (_) => MyRequestsScreen(initialTabIndex: 3),
        ),
      );
      return;
    }
    // Attendance: Attendance screen
    if (module == 'attendance' ||
        type == 'attendance_approved' ||
        type == 'attendance_rejected') {
      _log('handleNotificationData: navigating to AttendanceScreen');
      navigatorKey?.currentState?.push(
        MaterialPageRoute<void>(builder: (_) => AttendanceScreen()),
      );
      return;
    }
    // Performance: Performance module
    if (module == 'performance' ||
        type.startsWith('self_review') ||
        type.startsWith('manager_review') ||
        type.startsWith('hr_review')) {
      _log('handleNotificationData: navigating to PerformanceModuleScreen');
      navigatorKey?.currentState?.push(
        MaterialPageRoute<void>(builder: (_) => PerformanceModuleScreen()),
      );
      return;
    }
    _log('handleNotificationData: no route matched module=$module type=$type');
  }

  /// Call when user taps a stored notification (e.g. from NotificationsScreen). Navigates by module/type.
  static Future<void> handleNotificationTap(Map<String, dynamic> data) async {
    await _handleNotificationData(data);
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

  const _NotificationReaction({
    required this.emoji,
  });
}
