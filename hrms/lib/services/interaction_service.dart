// hrms/lib/services/interaction_service.dart
// Employee Interaction APIs — uses [AppConstants.interactionApiBaseUrl] (see interactionUseWebHost).

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/constants.dart';
import '../core/network/dio_client.dart';
import '../utils/error_message_utils.dart';
import 'api_client.dart';

class InteractionService {
  InteractionService._();
  static final InteractionService instance = InteractionService._();

  Dio? _dio;
  String? _dioBaseUsed;

  /// Raw stored token → value safe for `Authorization: Bearer …` (no duplicate "Bearer").
  /// Geo/LAN `app_backend` has no `/api/interaction`. The TypeScript `backend` does (`server.ts`).
  static const String kInteractionMissingOnServerMessage =
      'Chat and polls need the HRMS API that exposes /api/interaction (the TypeScript '
      'backend in this project). Your current baseUrl points at the geo server only, '
      'which has no Interaction routes.\n\n'
      'Options: (1) Run `npm run dev` from the `backend` folder and set baseUrl to that '
      'host/port, or (2) set interactionUseWebHost = true and webBaseUrl to production, '
      'then log in against that same host so your token is valid.';

  /// Whether this error means the server does not implement Interaction at all.
  static bool isInteractionApiUnavailable(Object error) {
    if (error is! DioException) return false;
    final path = error.requestOptions.path;
    if (!path.contains('/interaction')) return false;
    final code = error.response?.statusCode;
    final raw = ErrorMessageUtils.messageFromResponseData(error.response?.data);
    final msg = (raw ?? '').toLowerCase();
    if (code == 404) return true;
    if (msg.contains('route not found') && msg.contains('interaction'))
      return true;
    return false;
  }

  static String? normalizeAccessToken(String? raw) {
    if (raw == null) return null;
    var t = raw.trim();
    if (t.isEmpty) return null;
    if (t.length > 1 && t.startsWith('"') && t.endsWith('"')) {
      t = t.substring(1, t.length - 1).trim();
    }
    if (t.toLowerCase().startsWith('bearer ')) {
      t = t.substring(7).trim();
    }
    return t.isEmpty ? null : t;
  }

  Dio _client() {
    final wantedBase = AppConstants.interactionApiBaseUrl.replaceAll(
      RegExp(r'/+$'),
      '',
    );
    if (_dio != null && _dioBaseUsed == wantedBase) return _dio!;
    _dio = null;
    _dioBaseUsed = wantedBase;
    var base = wantedBase;
    if (base.endsWith('/')) base = base.substring(0, base.length - 1);
    _dio = Dio(
      BaseOptions(
        baseUrl: base,
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 45),
        sendTimeout: const Duration(seconds: 45),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );
    _dio!.interceptors.add(FormDataContentTypeInterceptor());
    _dio!.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final prefs = await SharedPreferences.getInstance();
          var t = normalizeAccessToken(
            prefs.getString(AppConstants.interactionAccessTokenPrefsKey),
          );
          t ??= normalizeAccessToken(prefs.getString('token'));
          if (t == null) {
            final auth = ApiClient().dio.options.headers['Authorization'];
            if (auth is String) {
              t = normalizeAccessToken(
                auth.startsWith('Bearer ') ? auth.substring(7) : auth,
              );
            }
          }
          if (t != null) {
            options.headers['Authorization'] = 'Bearer $t';
          }
          handler.next(options);
        },
      ),
    );
    _dio!.interceptors.add(RetryOnRateLimitInterceptor(_dio!));
    if (kDebugMode) {
      _dio!.interceptors.add(
        LogInterceptor(
          requestBody: true,
          responseBody: false,
          requestHeader: false,
          responseHeader: false,
          error: true,
          logPrint: (obj) => debugPrint('[Dio Interaction] $obj'),
        ),
      );
    }
    if (kDebugMode) {
      debugPrint(
        '[InteractionService] interaction API: ${_dio!.options.baseUrl}',
      );
    }
    return _dio!;
  }

  static Future<String?> currentUserId() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('user');
    if (raw == null || raw.isEmpty) return null;
    try {
      final u = jsonDecode(raw) as Map<String, dynamic>;
      return u['_id']?.toString() ?? u['id']?.toString();
    } catch (_) {
      return null;
    }
  }

  static Future<String?> currentUserRole() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('user');
    if (raw == null || raw.isEmpty) return null;
    try {
      final u = jsonDecode(raw) as Map<String, dynamic>;
      return u['role']?.toString();
    } catch (_) {
      return null;
    }
  }

  static bool roleCannotVote(String? role) {
    final r = (role ?? '').trim();
    return interactionAdminLikeRoles.contains(r);
  }

  /// Web ChatPage `isAdminUser` parity.
  static const Set<String> interactionAdminLikeRoles = {
    'Admin',
    'Super Admin',
    'HR',
    'Senior HR',
    'Manager',
    'EmployeeAdmin',
  };

  /// Web canManageGroups parity.
  static const Set<String> interactionGroupManagerRoles = {
    'Super Admin',
    'Admin',
    'HR',
  };

  static bool isInteractionAdminLikeRole(String? role) {
    final r = (role ?? '').trim();
    return interactionAdminLikeRoles.contains(r);
  }

  /// Same as web: `GET {api}/interaction/chats` with Bearer token (web: https://hrms.askeva.net/api/interaction/chats).
  Future<Map<String, dynamic>> getChats() async {
    final res = await _client().get<Map<String, dynamic>>('/interaction/chats');
    return res.data ?? {};
  }

  /// Web parity: announcements feed from interaction service.
  Future<Map<String, dynamic>> getAnnouncements() async {
    final res = await _client().get<Map<String, dynamic>>(
      '/interaction/announcements',
    );
    return res.data ?? {};
  }

  /// Web parity: unseen HR engagement count for announcement badge.
  Future<Map<String, dynamic>> getAnnouncementsUnseenHrTotal() async {
    final res = await _client().get<Map<String, dynamic>>(
      '/interaction/announcements/engagement/unseen-hr-total',
    );
    return res.data ?? {};
  }

  Future<Map<String, dynamic>> markAnnouncementRead(
    String announcementId,
  ) async {
    final path = '/interaction/announcements/$announcementId/read';
    try {
      final res = await _client().patch<Map<String, dynamic>>(path);
      return res.data ?? {};
    } on DioException catch (e) {
      final code = e.response?.statusCode ?? 0;
      if (code == 404 || code == 405) {
        final res = await _client().get<Map<String, dynamic>>(path);
        return res.data ?? {};
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> markAnnouncementHrSeen(
    String announcementId,
  ) async {
    final path =
        '/interaction/announcements/$announcementId/engagement/mark-hr-seen';
    try {
      final res = await _client().patch<Map<String, dynamic>>(path);
      return res.data ?? {};
    } on DioException catch (e) {
      final code = e.response?.statusCode ?? 0;
      if (code == 404 || code == 405) {
        final res = await _client().get<Map<String, dynamic>>(path);
        return res.data ?? {};
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> getAnnouncementMyReplies(
    String announcementId,
  ) async {
    final res = await _client().get<Map<String, dynamic>>(
      '/interaction/announcements/$announcementId/my-replies',
    );
    return res.data ?? {};
  }

  Future<Map<String, dynamic>> getAnnouncementById(
    String announcementId,
  ) async {
    final res = await _client().get<Map<String, dynamic>>(
      '/interaction/announcements/$announcementId',
    );
    return res.data ?? {};
  }

  /// Fetch engagement messages/threads for one announcement.
  /// Tries web-compatible variants and returns first successful payload.
  Future<Map<String, dynamic>> getAnnouncementEngagement(
    String announcementId,
  ) async {
    final paths = <String>[
      '/interaction/announcements/$announcementId/engagement',
      '/interaction/announcements/$announcementId/my-replies',
    ];
    DioException? lastError;
    for (final path in paths) {
      try {
        final res = await _client().get<Map<String, dynamic>>(path);
        return res.data ?? {};
      } on DioException catch (e) {
        lastError = e;
        final code = e.response?.statusCode ?? 0;
        if (code == 404 || code == 405) continue;
        rethrow;
      }
    }
    if (lastError != null) throw lastError;
    return {};
  }

  /// Web-style announcement engagement message send.
  /// Uses same route as web: POST /interaction/announcements/:id/reply
  Future<Map<String, dynamic>> sendAnnouncementEngagementMessage(
    String announcementId, {
    required String message,
  }) async {
    const pathSuffix = '/reply';
    final payloads = <Map<String, dynamic>>[
      {'replyText': message},
      {'message': message},
      {'reply': message},
    ];
    DioException? lastError;
    for (final payload in payloads) {
      try {
        final res = await _client().post<Map<String, dynamic>>(
          '/interaction/announcements/$announcementId$pathSuffix',
          data: payload,
        );
        return res.data ?? {'success': true};
      } on DioException catch (e) {
        final code = e.response?.statusCode ?? 0;
        lastError = e;
        if (code == 400 || code == 422) continue;
        rethrow;
      }
    }
    if (lastError != null) {
      final code = lastError.response?.statusCode ?? 0;
      if (code == 404) {
        return {
          'success': false,
          'message':
              'Engagement send API is not available on this server route yet. Please try again later.',
        };
      }
      return {
        'success': false,
        'message': ErrorMessageUtils.messageFromDioException(
          lastError,
          fallback: 'Unable to send engagement message',
        ),
      };
    }
    return {'success': false, 'message': 'Unable to send engagement message'};
  }

  Future<Map<String, dynamic>> getChatMessages({
    required String chatId,
    int page = 1,
    String? receiverId,
  }) async {
    final res = await _client().get<Map<String, dynamic>>(
      '/interaction/chats/$chatId/messages',
      queryParameters: {
        'page': page,
        if (receiverId != null && receiverId.isNotEmpty)
          'receiverId': receiverId,
      },
    );
    return res.data ?? {};
  }

  Future<Map<String, dynamic>> sendTextMessage({
    required String chatId,
    required String messageContent,
    String? receiverId,
  }) async {
    final body = <String, dynamic>{
      'messageType': 'text',
      'messageContent': messageContent,
      if (receiverId != null) 'receiverId': receiverId,
    };
    final res = await _client().post<Map<String, dynamic>>(
      '/interaction/chats/$chatId/messages',
      data: body,
    );
    return res.data ?? {};
  }

  Future<Map<String, dynamic>> uploadChatMedia({
    required String chatId,
    required String filePath,
    required String filename,
    required String type, // image | file | voice
    String? receiverId,
  }) async {
    final form = FormData.fromMap({
      'type': type,
      if (receiverId != null) 'receiverId': receiverId,
      'file': await MultipartFile.fromFile(filePath, filename: filename),
    });
    final res = await _client().post<Map<String, dynamic>>(
      '/interaction/chats/$chatId/upload',
      data: form,
    );
    return res.data ?? {};
  }

  Future<Map<String, dynamic>> markMessageRead(String messageId) async {
    final res = await _client().patch<Map<String, dynamic>>(
      '/interaction/messages/$messageId/read',
    );
    return res.data ?? {};
  }

  Future<Map<String, dynamic>> getChatSuggestions({String? query}) async {
    final res = await _client().get<Map<String, dynamic>>(
      '/interaction/chats/suggestions',
      queryParameters: {
        if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
      },
    );
    return res.data ?? {};
  }

  Future<Map<String, dynamic>> getChatTermsStatus() async {
    final res = await _client().get<Map<String, dynamic>>(
      '/interaction/chats/terms/status',
    );
    return res.data ?? {};
  }

  Future<Map<String, dynamic>> approveChatTerms() async {
    final res = await _client().patch<Map<String, dynamic>>(
      '/interaction/chats/terms/approve',
    );
    return res.data ?? {};
  }

  Future<Map<String, dynamic>> getGroups() async {
    final res = await _client().get<Map<String, dynamic>>(
      '/interaction/groups',
    );
    return res.data ?? {};
  }

  Future<Map<String, dynamic>> getGroupMembers(String groupId) async {
    final res = await _client().get<Map<String, dynamic>>(
      '/interaction/groups/$groupId/members',
    );
    return res.data ?? {};
  }

  Future<Map<String, dynamic>> updateGroup(
    String groupId, {
    String? groupName,
    String? description,
    List<String>? allowedSenderIds,
  }) async {
    final body = <String, dynamic>{
      if (groupName != null) 'groupName': groupName,
      if (description != null) 'description': description,
      if (allowedSenderIds != null) 'allowedSenderIds': allowedSenderIds,
    };
    final res = await _client().patch<Map<String, dynamic>>(
      '/interaction/groups/$groupId',
      data: body,
    );
    return res.data ?? {};
  }

  Future<Map<String, dynamic>> uploadGroupAvatar({
    required String groupId,
    required String filePath,
    required String filename,
  }) async {
    final form = FormData.fromMap({
      'file': await MultipartFile.fromFile(filePath, filename: filename),
    });
    final res = await _client().post<Map<String, dynamic>>(
      '/interaction/groups/$groupId/avatar',
      data: form,
    );
    return res.data ?? {};
  }

  Future<Map<String, dynamic>> addGroupMembers(
    String groupId, {
    required List<String> userIds,
  }) async {
    final res = await _client().post<Map<String, dynamic>>(
      '/interaction/groups/$groupId/members',
      data: {'userIds': userIds},
    );
    return res.data ?? {};
  }

  Future<Map<String, dynamic>> removeGroupMember(
    String groupId, {
    required String userId,
  }) async {
    final res = await _client().delete<Map<String, dynamic>>(
      '/interaction/groups/$groupId/members/$userId',
    );
    return res.data ?? {};
  }

  Future<Map<String, dynamic>> updateGroupMemberRole(
    String groupId, {
    required String userId,
    required String role, // member | admin
  }) async {
    final res = await _client().patch<Map<String, dynamic>>(
      '/interaction/groups/$groupId/members/$userId/role',
      data: {'role': role},
    );
    return res.data ?? {};
  }

  Future<Map<String, dynamic>> deleteGroup(String groupId) async {
    final res = await _client().delete<Map<String, dynamic>>(
      '/interaction/groups/$groupId',
    );
    return res.data ?? {};
  }

  Future<Map<String, dynamic>> getPolls() async {
    final res = await _client().get<Map<String, dynamic>>('/interaction/polls');
    return res.data ?? {};
  }

  Future<Map<String, dynamic>> getPoll(String pollId) async {
    final res = await _client().get<Map<String, dynamic>>(
      '/interaction/polls/$pollId',
    );
    return res.data ?? {};
  }

  Future<Map<String, dynamic>> votePoll(
    String pollId, {
    required List<String> optionIds,
    bool anonymous = false,
  }) async {
    try {
      final res = await _client().post<Map<String, dynamic>>(
        '/interaction/polls/$pollId/vote',
        data: {'optionIds': optionIds, 'anonymous': anonymous},
      );
      return res.data ?? {'success': true};
    } on DioException catch (e) {
      final msg = ErrorMessageUtils.messageFromDioException(
        e,
        fallback: 'Vote failed',
      );
      if (kDebugMode) debugPrint('[InteractionService] votePoll: $msg');
      return {'success': false, 'message': msg};
    }
  }

  Future<Map<String, dynamic>> getPollResults(String pollId) async {
    final res = await _client().get<Map<String, dynamic>>(
      '/interaction/polls/$pollId/results',
    );
    return res.data ?? {};
  }

  /// Same as web: `GET /api/lms/me/access` on the HRMS API host.
  Future<Map<String, dynamic>> getLmsMyAccess() async {
    final res = await _client().get<Map<String, dynamic>>('/lms/me/access');
    return res.data ?? {};
  }
}
