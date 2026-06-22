// hrms/lib/services/interaction_service.dart
// Employee Interaction APIs — uses [AppConstants.interactionApiBaseUrl] (see interactionUseWebHost).

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:mime/mime.dart';
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
          var interactionToken = normalizeAccessToken(
            prefs.getString(AppConstants.interactionAccessTokenPrefsKey),
          );
          var t = interactionToken;
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
            options.extra['auth_source'] = (interactionToken != null)
                ? 'interaction_token'
                : 'primary_token';
          }
          handler.next(options);
        },
        onError: (err, handler) async {
          final status = err.response?.statusCode ?? 0;
          final retried =
              err.requestOptions.extra['_retried_with_primary'] == true;
          final source =
              err.requestOptions.extra['auth_source']?.toString() ?? '';
          if (status == 401 && !retried && source == 'interaction_token') {
            try {
              final prefs = await SharedPreferences.getInstance();
              var primary = normalizeAccessToken(prefs.getString('token'));
              if (primary == null) {
                final auth = ApiClient().dio.options.headers['Authorization'];
                if (auth is String) {
                  primary = normalizeAccessToken(
                    auth.startsWith('Bearer ') ? auth.substring(7) : auth,
                  );
                }
              }
              if (primary != null) {
                final retryHeaders = Map<String, dynamic>.from(
                  err.requestOptions.headers,
                );
                retryHeaders['Authorization'] = 'Bearer $primary';
                final retryExtra = Map<String, dynamic>.from(
                  err.requestOptions.extra,
                );
                retryExtra['_retried_with_primary'] = true;
                retryExtra['auth_source'] = 'primary_token_retry';

                final retryOptions = err.requestOptions.copyWith(
                  headers: retryHeaders,
                  extra: retryExtra,
                );
                final retryResponse = await _dio!.fetch<dynamic>(retryOptions);
                await prefs.setString(
                  AppConstants.interactionAccessTokenPrefsKey,
                  primary,
                );
                if (kDebugMode) {
                  debugPrint(
                    '[InteractionService] 401 recovered using primary token; refreshed interaction token.',
                  );
                }
                handler.resolve(retryResponse);
                return;
              }
            } catch (_) {
              // Fall through to original error if retry also fails.
            }
          }
          handler.next(err);
        },
      ),
    );
    _dio!.interceptors.add(RetryOnRateLimitInterceptor(_dio!));
    if (kDebugMode) {
      _dio!.interceptors.add(
        LogInterceptor(
          requestBody: true,
          responseBody: true,
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
  /// Tries web-compatible POST paths and body shapes; does not throw — returns `success: false` + `message`.
  Future<Map<String, dynamic>> sendAnnouncementEngagementMessage(
    String announcementId, {
    required String message,
  }) async {
    final id = announcementId.trim();
    if (id.isEmpty) {
      return {'success': false, 'message': 'Missing announcement id.'};
    }
    final attempts = <(String, Map<String, dynamic>)>[
      ('/interaction/announcements/$id/reply', {'replyText': message}),
      ('/interaction/announcements/$id/reply', {'message': message}),
      ('/interaction/announcements/$id/engagement', {'replyText': message}),
      ('/interaction/announcements/$id/engagement', {'message': message}),
      ('/interaction/announcements/$id/engagement', {'text': message}),
    ];
    DioException? lastError;
    for (final attempt in attempts) {
      final path = attempt.$1;
      final body = attempt.$2;
      try {
        final res = await _client().post<Map<String, dynamic>>(
          path,
          data: body,
        );
        final raw = res.data;
        if (raw is Map) {
          final map = Map<String, dynamic>.from(raw as Map);
          if (map['success'] == false) {
            final msg = map['message']?.toString().trim();
            return {
              'success': false,
              'message': (msg != null && msg.isNotEmpty)
                  ? msg
                  : 'Unable to send this message.',
            };
          }
          return map;
        }
        return {'success': true};
      } on DioException catch (e) {
        lastError = e;
        final code = e.response?.statusCode ?? 0;
        if (code == 400 || code == 422 || code == 404 || code == 405) {
          continue;
        }
        if (code == 401 || code == 403) {
          final main = AppConstants.baseUrl.replaceAll(RegExp(r'/+$'), '');
          final web = AppConstants.webBaseUrl.replaceAll(RegExp(r'/+$'), '');
          if (AppConstants.interactionUseWebHost && main != web) {
            return {
              'success': false,
              'message':
                  'Announcement messages use the main HRMS server. Log out and log in again so your session syncs, then try sending.',
            };
          }
          return {
            'success': false,
            'message': ErrorMessageUtils.messageFromDioException(
              e,
              fallback: 'Unable to send engagement message',
            ),
          };
        }
        return {
          'success': false,
          'message': ErrorMessageUtils.messageFromDioException(
            e,
            fallback: 'Unable to send engagement message',
          ),
        };
      }
    }
    if (lastError != null) {
      final code = lastError.response?.statusCode ?? 0;
      if (code == 404 || code == 405) {
        return {
          'success': false,
          'message':
              'Sending replies is not available on this HRMS server version. Ask your admin or try again later.',
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
    required String type, // image | video | file | voice
    String? receiverId,
  }) async {
    final endpoint = '/interaction/chats/$chatId/upload';
    final receiver = receiverId?.trim();
    final hasReceiver = receiver != null && receiver.isNotEmpty;

    // The server rejects an upload as "Invalid file type" when the message-type
    // value it receives isn't in its accepted set — this is unrelated to the
    // actual file bytes (which carry a correct Content-Type below). Different
    // HRMS server versions name the field (`messageType` vs `type`), the value
    // (`file` vs `document`), and the file part (`file` vs `audio`/`media`)
    // differently, so we try the most-likely shape first and fall back through
    // the known conventions. Every attempt fails fast on 400/422, so the chain
    // stays quick. Order is dedup'd to avoid redundant round-trips.
    final payloads = <({Map<String, dynamic> fields, String fileField})>[];
    final seen = <String>{};
    void add(String typeKey, String typeValue, String fileField) {
      final sig = '$typeKey=$typeValue:$fileField';
      if (!seen.add(sig)) return;
      payloads.add((
        fields: {typeKey: typeValue, if (hasReceiver) 'receiverId': receiver},
        fileField: fileField,
      ));
    }

    // 1) The intended type, both field-name conventions.
    add('messageType', type, 'file');
    add('type', type, 'file');
    // 2) Generic attachment fallbacks so ANY file still posts even when the
    //    server doesn't accept the specific type value. `file` and `document`
    //    are the two values HRMS backends use for arbitrary uploads.
    add('messageType', 'file', 'file');
    add('messageType', 'document', 'file');
    add('type', 'document', 'file');
    // 3) Voice/audio-specific shapes (web records voice as audio).
    if (type == 'voice') {
      add('messageType', 'audio', 'file');
      add('messageType', 'voice', 'audio');
      add('messageType', 'audio', 'audio');
    }

    // Resolve a real MIME type from the filename/path. Without this Dio sends
    // `application/octet-stream`, which the server's upload filter rejects as
    // "Invalid Format" (notably for videos picked from the gallery).
    final contentType = _resolveMediaType(filename, filePath, type);

    // Guarantee the multipart filename carries an extension matching the MIME
    // type. Android's image_picker often returns gallery videos with an
    // extension-less cache name (e.g. `.../cache/REC0001`), so a server filter
    // that validates by file extension rejects the upload as "Invalid file
    // type" even though the Content-Type header is a correct `video/mp4`.
    final uploadFilename = _filenameForUpload(filename, contentType, type);

    DioException? lastError;
    for (final candidate in payloads) {
      try {
        final form = FormData.fromMap({
          ...candidate.fields,
          candidate.fileField: await MultipartFile.fromFile(
            filePath,
            filename: uploadFilename,
            contentType: contentType,
          ),
        });
        final res = await _client().post<Map<String, dynamic>>(
          endpoint,
          data: form,
        );
        return res.data ?? {};
      } on DioException catch (e) {
        lastError = e;
        final code = e.response?.statusCode ?? 0;
        // A wrong message-type value or a rejected MIME shows up across server
        // versions as 400/422 (validation), 415 (unsupported media type), or
        // 500 (a multer `fileFilter` error surfaces as a generic 500). Advance
        // to the next known field-name/value shape for all of these so the
        // `file`→`document` and audio fallbacks are actually exercised instead
        // of bailing on the first attempt. The final lastError is still thrown
        // on exhaustion, so a genuine failure is never swallowed.
        if (code == 400 || code == 415 || code == 422 || code == 500) {
          continue;
        }
        rethrow;
      }
    }
    if (lastError != null) throw lastError;
    return {'success': false, 'message': 'Unable to upload media'};
  }

  /// Resolve the HTTP `Content-Type` for an outgoing multipart file from its
  /// name/path. Defaults to `application/octet-stream` only when the type is
  /// genuinely unknown so the server filter has a real MIME type to validate.
  DioMediaType? _resolveMediaType(String filename, String filePath, String type) {
    // Gallery-picked videos sometimes arrive with an extension-less name/path,
    // so the lookup returns null and Dio falls back to octet-stream — which the
    // server rejects. Use a sensible default per message type in that case.
    var mime =
        lookupMimeType(filename) ?? lookupMimeType(filePath) ?? _fallbackMimeForType(type);
    // The `mime` package maps `.m4a` → `audio/mp4`, but the interaction server's
    // upload filter rejects anything it reads as MP4 ("OGG, MP4, and WEBM file
    // formats are not supported"). A browser uploads the same `.m4a` as
    // `audio/x-m4a`, which is on the server allowlist — so voice works from web
    // but not the app. Mirror the browser's Content-Type for voice/audio so the
    // recorded AAC/m4a clip (and picked `.m4a` files) pass the filter.
    if (type == 'voice' && mime == 'audio/mp4') {
      mime = 'audio/x-m4a';
    }
    if (mime == null) return null;
    try {
      return DioMediaType.parse(mime);
    } catch (_) {
      return null;
    }
  }

  /// Best-effort MIME type when the filename/path carries no usable extension.
  String? _fallbackMimeForType(String type) {
    switch (type) {
      case 'video':
        return 'video/mp4';
      case 'image':
        return 'image/jpeg';
      case 'voice':
        // Browser-compatible audio type the server allowlist accepts; never
        // `audio/mp4`, which the upload filter rejects as an MP4 format.
        return 'audio/x-m4a';
      default:
        return null;
    }
  }

  /// Ensure the multipart filename ends with an extension consistent with
  /// [contentType]. Servers that validate uploads by file extension (rather than
  /// the multipart Content-Type header) reject extension-less names as "Invalid
  /// file type". Leaves names that already carry a recognised media extension
  /// untouched.
  String _filenameForUpload(
    String filename,
    DioMediaType? contentType,
    String type,
  ) {
    final name = filename.trim().isEmpty ? 'upload' : filename.trim();
    if (lookupMimeType(name) != null) return name;
    final ext =
        _extensionForMime(contentType?.mimeType) ?? _fallbackExtensionForType(type);
    if (ext == null) return name;
    return '$name.$ext';
  }

  /// Map a resolved MIME type back to a common file extension (no leading dot).
  String? _extensionForMime(String? mime) {
    switch (mime) {
      case 'video/mp4':
        return 'mp4';
      case 'video/quicktime':
        return 'mov';
      case 'video/x-matroska':
        return 'mkv';
      case 'video/webm':
        return 'webm';
      case 'video/3gpp':
        return '3gp';
      case 'image/jpeg':
        return 'jpg';
      case 'image/png':
        return 'png';
      case 'image/gif':
        return 'gif';
      case 'image/webp':
        return 'webp';
      case 'audio/mpeg':
        return 'mp3';
      case 'audio/mp4':
      case 'audio/aac':
        return 'm4a';
      case 'audio/wav':
      case 'audio/x-wav':
        return 'wav';
      case 'audio/ogg':
        return 'ogg';
      default:
        return null;
    }
  }

  /// Sensible default extension per message type when the MIME is unknown.
  String? _fallbackExtensionForType(String type) {
    switch (type) {
      case 'video':
        return 'mp4';
      case 'image':
        return 'jpg';
      case 'voice':
        return 'm4a';
      default:
        return null;
    }
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
      'file': await MultipartFile.fromFile(
        filePath,
        filename: filename,
        contentType: _resolveMediaType(filename, filePath, 'image'),
      ),
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
