// core/network/dio_client.dart
// Single place for Dio configuration. Used by data layer only.
// No business logic — only auth header, retry, and logging.

import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/constants.dart';
import '../../utils/swr_cache.dart';

/// Clears persisted auth tokens + user snapshot and default Dio Authorization header.
Future<void> clearStoredAuthSession() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove('token');
  await prefs.remove(AppConstants.refreshTokenPrefsKey);
  await prefs.remove('user');
  await prefs.remove('taskSettings');
  await prefs.remove('businessId');
  await prefs.remove(AppConstants.interactionAccessTokenPrefsKey);
  // Drop any in-memory screen caches so one session's data can't leak into the next.
  SwrCache.clearAll();
  DioClient().clearAuthToken();
}

/// Verbose per-request Dio logs (options, URLs, bodies). Off by default — very chatty.
const _kLogDioTraffic = false;

/// Retries on 429 (rate limit) with exponential backoff. Respects Retry-After.
class RetryOnRateLimitInterceptor extends Interceptor {
  RetryOnRateLimitInterceptor(this.dio);
  final Dio dio;
  static const int maxRetries = 3;
  static const List<int> backoffDelaysSeconds = [2, 4, 6];

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (err.response?.statusCode != 429) {
      return handler.next(err);
    }
    // Some endpoints (e.g. login) should not silently back off/retry because it
    // feels like the UI is "stuck". Allow opt-out per request.
    final disableRetry = err.requestOptions.extra['disable_429_retry'] == true;
    if (disableRetry) {
      return handler.next(err);
    }
    final extra = err.requestOptions.extra;
    final retryCount = extra['retry_count'] as int? ?? 0;
    if (retryCount >= maxRetries) {
      return handler.next(err);
    }
    int waitSeconds =
        backoffDelaysSeconds[retryCount.clamp(
          0,
          backoffDelaysSeconds.length - 1,
        )];
    final retryAfter = err.response?.headers.value('retry-after');
    if (retryAfter != null && retryAfter.isNotEmpty) {
      final parsed = int.tryParse(retryAfter);
      if (parsed != null && parsed > 0) {
        waitSeconds = parsed > 120 ? 120 : parsed;
      }
    }
    await Future<void>.delayed(Duration(seconds: waitSeconds));
    final opts = err.requestOptions;
    opts.extra['retry_count'] = retryCount + 1;
    try {
      final response = await dio.fetch(opts);
      return handler.resolve(response);
    } catch (e) {
      return handler.next(err);
    }
  }
}

/// Ensures multipart uploads are not sent with Content-Type: application/json.
class FormDataContentTypeInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (options.data is FormData) {
      options.headers.remove('Content-Type');
      // Dio will set multipart/form-data with boundary when sending
    }
    handler.next(options);
  }
}

/// On 401, exchanges [AppConstants.refreshTokenPrefsKey] for new access token and retries once.
class TokenRefreshInterceptor extends Interceptor {
  TokenRefreshInterceptor(this._dio);
  final Dio _dio;
  static Future<String?>? _ongoingRefresh;

  bool _shouldAttemptRefresh(DioException err) {
    if (err.response?.statusCode != 401) return false;
    final ro = err.requestOptions;
    if (ro.extra['_skip_token_refresh'] == true) return false;
    if (ro.extra['_retried_after_refresh'] == true) return false;
    final p = ro.path;
    if (p.endsWith('/auth/login') || p.endsWith('/auth/refresh')) return false;
    return true;
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (!_shouldAttemptRefresh(err)) {
      return handler.next(err);
    }
    final prefs = await SharedPreferences.getInstance();
    var rt = prefs.getString(AppConstants.refreshTokenPrefsKey);
    if (rt == null || rt.isEmpty) {
      return handler.next(err);
    }
    if (rt.startsWith('"') || rt.endsWith('"')) {
      rt = rt.replaceAll('"', '');
    }
    try {
      final newAccess = await _refreshOrJoin(rt);
      if (newAccess == null || newAccess.isEmpty) {
        return handler.next(err);
      }
      DioClient().setAuthToken(newAccess);
      final opts = err.requestOptions;
      final newHeaders = Map<String, dynamic>.from(opts.headers);
      newHeaders['Authorization'] = 'Bearer $newAccess';
      final newExtra = Map<String, dynamic>.from(opts.extra);
      newExtra['_retried_after_refresh'] = true;
      final clone = opts.copyWith(headers: newHeaders, extra: newExtra);
      final response = await _dio.fetch(clone);
      return handler.resolve(response);
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[TokenRefreshInterceptor] retry failed: $e $st');
      }
      return handler.next(err);
    }
  }

  static Future<String?> _refreshOrJoin(String refreshToken) {
    _ongoingRefresh ??= _doRefresh(refreshToken).whenComplete(() {
      _ongoingRefresh = null;
    });
    return _ongoingRefresh!;
  }

  static Future<String?> _doRefresh(String refreshToken) async {
    final base = AppConstants.baseUrl;
    final baseUrl = base.endsWith('/')
        ? base.substring(0, base.length - 1)
        : base;
    final plain = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 20),
        sendTimeout: const Duration(seconds: 20),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'X-Storage-Environment': AppConstants.storageEnvironment,
        },
      ),
    );
    try {
      final res = await plain.post<Map<String, dynamic>>(
        '/auth/refresh',
        data: {'refreshToken': refreshToken},
      );
      final body = res.data;
      if (body == null || body['success'] != true) return null;
      final data = body['data'];
      if (data is! Map) return null;
      final access = data['accessToken']?.toString();
      final newRt = data['refreshToken']?.toString();
      final prefs = await SharedPreferences.getInstance();
      if (access != null && access.isNotEmpty) {
        await prefs.setString('token', access);
      }
      if (newRt != null && newRt.isNotEmpty) {
        await prefs.setString(AppConstants.refreshTokenPrefsKey, newRt);
      }
      return access;
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        await clearStoredAuthSession();
      }
      return null;
    }
  }
}

/// Handles expired sessions globally: clear stale auth and let UI redirect to login.
class SessionExpiryInterceptor extends Interceptor {
  SessionExpiryInterceptor(this.dio);
  final Dio dio;
  static bool _handlingExpiry = false;

  bool _isExpiredTokenError(DioException err) {
    if (err.response?.statusCode != 401) return false;
    final data = err.response?.data;
    final message = (data is Map<String, dynamic>)
        ? '${data['message'] ?? ''} ${data['error'] ?? ''}'.toLowerCase()
        : (data?.toString().toLowerCase() ?? '');
    return message.contains('jwt expired') ||
        message.contains('session expired') ||
        message.contains('token expired');
  }

  Future<void> _clearSession() async {
    await clearStoredAuthSession();
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (_isExpiredTokenError(err) && !_handlingExpiry) {
      _handlingExpiry = true;
      try {
        await _clearSession();
      } catch (_) {
        // Ignore local storage cleanup issues; still forward original error.
      } finally {
        _handlingExpiry = false;
      }
    }
    handler.next(err);
  }
}

/// Central Dio client for the app. Used only by data layer (datasources).
/// Auth token is set before authenticated requests; interceptors handle retry and logging.
class DioClient {
  static final DioClient _instance = DioClient._internal();
  factory DioClient() => _instance;

  late final Dio dio;

  DioClient._internal() {
    final base = AppConstants.baseUrl;
    final baseUrl = base.endsWith('/')
        ? base.substring(0, base.length - 1)
        : base;
    dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        // Production mobile networks can have short jitter spikes; keep
        // timeouts tolerant to avoid false "server timed out" UX.
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 45),
        sendTimeout: const Duration(seconds: 45),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'X-Storage-Environment': AppConstants.storageEnvironment,
        },
      ),
    );
    if (kDebugMode) {
      debugPrint('[DioClient] baseUrl: ${dio.options.baseUrl}');
    }
    dio.interceptors.addAll([
      FormDataContentTypeInterceptor(),
      TokenRefreshInterceptor(dio),
      SessionExpiryInterceptor(dio),
      RetryOnRateLimitInterceptor(dio),
      if (kDebugMode && _kLogDioTraffic)
        LogInterceptor(
          requestBody: true,
          responseBody: false,
          requestHeader: false,
          responseHeader: false,
          error: true,
          logPrint: (obj) => debugPrint('[Dio] $obj'),
        ),
    ]);
  }

  void setAuthToken(String? token) {
    if (token == null || token.isEmpty) {
      dio.options.headers.remove('Authorization');
    } else {
      dio.options.headers['Authorization'] = 'Bearer $token';
    }
  }

  void clearAuthToken() {
    dio.options.headers.remove('Authorization');
  }
}
