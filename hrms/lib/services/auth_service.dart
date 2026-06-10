// hrms/lib/services/auth_service.dart
import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dio/dio.dart';
import '../config/constants.dart';
import '../utils/error_message_utils.dart';
import '../utils/swr_cache.dart';
import 'api_client.dart';
import 'web_hrms_api_dio.dart';
import 'fcm_service.dart';
import 'attendance_template_store.dart';
import 'geo/live_tracking_service.dart';
import 'interaction_socket_service.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  static const String _kAuthBaseUrl = 'auth_base_url';
  // Use the constant from config
  final String baseUrl = AppConstants.baseUrl;
  final FirebaseAuth _firebaseAuth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  final ApiClient _api = ApiClient();

  static const Duration _loginRequestTimeout = Duration(seconds: 20);
  static DateTime? _interactionSyncBlockedUntil;
  static void _authLog(String message) {
    if (kDebugMode) debugPrint('[AuthService] $message');
  }

  /// Second login to [AppConstants.webBaseUrl] so `/api/interaction/*` matches the web (same JWT host).
  Future<void> _syncInteractionAccessTokenFromWebHost({
    required String email,
    required String password,
    String? otp,
  }) async {
    if (!AppConstants.interactionUseWebHost) return;
    final now = DateTime.now();
    if (_interactionSyncBlockedUntil != null &&
        now.isBefore(_interactionSyncBlockedUntil!)) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final main = AppConstants.baseUrl.replaceAll(RegExp(r'/+$'), '');
    final web = AppConstants.webBaseUrl.replaceAll(RegExp(r'/+$'), '');
    if (main == web) {
      await prefs.remove(AppConstants.interactionAccessTokenPrefsKey);
      return;
    }
    try {
      final dio = Dio(
        BaseOptions(
          baseUrl: web,
          connectTimeout: const Duration(seconds: 20),
          receiveTimeout: const Duration(seconds: 20),
          sendTimeout: const Duration(seconds: 20),
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
        ),
      );
      final requestBody = <String, dynamic>{'email': email, 'password': password};
      if (otp != null && otp.isNotEmpty) requestBody['otp'] = otp;
      final response = await dio.post<Map<String, dynamic>>(
        '/auth/login',
        data: requestBody,
      );
      final body = response.data ?? {};
      if (body['requiresOTP'] == true) {
        await prefs.remove(AppConstants.interactionAccessTokenPrefsKey);
        if (kDebugMode) {
          debugPrint(
            '[AuthService] Web HRMS login requires OTP; sign in with OTP then open Interaction again or set interactionUseWebHost false.',
          );
        }
        return;
      }
      final data = body['data'];
      String? webToken;
      if (data != null && data['accessToken'] != null) {
        webToken = data['accessToken']?.toString();
      } else if (body['token'] != null) {
        webToken = body['token']?.toString();
      } else if (body['accessToken'] != null) {
        webToken = body['accessToken']?.toString();
      }
      if (webToken != null && webToken.isNotEmpty) {
        await prefs.setString(
          AppConstants.interactionAccessTokenPrefsKey,
          webToken,
        );
        if (kDebugMode) debugPrint('[AuthService] Web HRMS interaction token synced');
      } else {
        await prefs.remove(AppConstants.interactionAccessTokenPrefsKey);
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 429) {
        // Back off secondary host login to avoid increasing auth limiter pressure.
        _interactionSyncBlockedUntil = DateTime.now().add(
          const Duration(minutes: 15),
        );
      }
      if (kDebugMode) debugPrint('[AuthService] Web HRMS interaction sync failed: $e');
      await prefs.remove(AppConstants.interactionAccessTokenPrefsKey);
    } catch (e) {
      if (kDebugMode) debugPrint('[AuthService] Web HRMS interaction sync failed: $e');
      await prefs.remove(AppConstants.interactionAccessTokenPrefsKey);
    }
  }

  Future<Map<String, dynamic>> login(String email, String password, {String? otp}) async {
    try {
      final startedAt = DateTime.now();
      final requestBody = <String, dynamic>{'email': email, 'password': password};
      if (otp != null && otp.isNotEmpty) requestBody['otp'] = otp;
      _authLog(
        'login start email=${email.trim()} otp=${otp != null && otp.isNotEmpty} singleApi=${AppConstants.singleApiLoginMode}',
      );
      // Avoid "stuck" feeling: do not 429-retry login, and enforce tight timeouts.
      final response = await _api.dio
          .post<Map<String, dynamic>>(
            '/auth/login',
            data: requestBody,
            options: Options(
              sendTimeout: _loginRequestTimeout,
              receiveTimeout: _loginRequestTimeout,
              extra: const {'disable_429_retry': true},
            ),
          )
          .timeout(_loginRequestTimeout);
      final body = response.data ?? {};
      _authLog(
        'login response status=${response.statusCode} elapsed=${DateTime.now().difference(startedAt).inMilliseconds}ms',
      );

      // 2FA: backend asks for OTP before issuing token
      if (body['requiresOTP'] == true) {
        return {
          'success': true,
          'requiresOTP': true,
          'message': body['message'] as String? ?? 'OTP has been sent to your email.',
        };
      }

      final data = body['data'];

      final prefs = await SharedPreferences.getInstance();
      String? accessToken;
      if (data != null && data['accessToken'] != null) {
        accessToken = data['accessToken'];
      } else if (body['token'] != null) {
        accessToken = body['token'];
      } else if (body['accessToken'] != null) {
        accessToken = body['accessToken'];
      }
      if (accessToken != null) {
        await prefs.setString('token', accessToken);
      }
      if (data != null) {
        final rt = (data is Map) ? data['refreshToken']?.toString() : null;
        if (rt != null && rt.trim().isNotEmpty) {
          await prefs.setString(AppConstants.refreshTokenPrefsKey, rt.trim());
        } else {
          await prefs.remove(AppConstants.refreshTokenPrefsKey);
        }
      }
      dynamic userData;
      if (data != null && data['user'] != null) {
        userData = data['user'];
      } else if (body['_id'] != null) {
        userData = body;
      }
      if (userData != null) {
        await prefs.setString('user', jsonEncode(userData));
      }
      if (data != null && data['user'] != null) {
        final user = data['user'] as Map<String, dynamic>?;
        final taskSettings = user?['taskSettings'] as Map<String, dynamic>?;
        if (taskSettings != null) {
          await prefs.setString('taskSettings', jsonEncode(taskSettings));
        }
        // Store businessId from staff (staffs collection) for task creation etc.
        final businessId = user?['businessId'] ?? user?['companyId'];
        if (businessId != null) {
          final idStr = businessId is Map
              ? (businessId['\$oid'] ?? businessId['_id'] ?? businessId)
                    .toString()
              : businessId.toString();
          await prefs.setString('businessId', idStr);
        }
      }
      await _persistCurrentBaseUrl(prefs);
      _api.setAuthToken(accessToken);
      if (AppConstants.singleApiLoginMode) {
        _authLog(
          'singleApiLoginMode enabled: skipped interaction web-host sync + FCM post-login sync',
        );
      } else {
        // Keep post-login background work non-blocking so login UI can proceed quickly.
        unawaited(
          _syncInteractionAccessTokenFromWebHost(
            email: email.trim(),
            password: password,
            otp: otp,
          ),
        );
        _authLog('login success - registering FCM token');
        unawaited(FcmService.sendTokenToBackendAfterLogin());
      }
      _authLog(
        'login success completed elapsed=${DateTime.now().difference(startedAt).inMilliseconds}ms',
      );
      return {'success': true, 'data': data};
    } on TimeoutException {
      _authLog('login timeout after ${_loginRequestTimeout.inSeconds}s');
      return {
        'success': false,
        'message':
            'Login request timed out. Please check your internet and try again.',
      };
    } on DioException catch (e) {
      _authLog(
        'login DioException status=${e.response?.statusCode} path=${e.requestOptions.path}',
      );
      _authLog('login error body=${e.response?.data}');
      return _handleDioError(e, 'Login failed', (code, body) {
        if (code != null && code >= 500) {
          return 'Server error ($code). The backend server is not responding. Please try again later.';
        }
        return _messageFromBody(body) ?? 'Login failed';
      });
    } catch (e) {
      _authLog('login unexpected error: ${e.runtimeType}');
      return {'success': false, 'message': _handleException(e)};
    }
  }

  /// Shared Dio error handling: 429 message, JSON body parsing, HTML fallback.
  Map<String, dynamic> _handleDioError(
    DioException e,
    String defaultMessage,
    String Function(int? code, dynamic body)? messageFn,
  ) {
    final code = e.response?.statusCode;
    if (code == null) {
      return {
        'success': false,
        'message': ErrorMessageUtils.messageFromDioException(
          e,
          fallback: defaultMessage,
        ),
      };
    }
    final data = e.response?.data;
    String? bodyStr;
    Map<String, dynamic>? bodyMap;
    if (data is String) {
      bodyStr = data;
      if (bodyStr.trim().startsWith('<')) {
        return {
          'success': false,
          'message':
              'Server error ($code). The backend server is not responding. Please try again later.',
        };
      }
      try {
        bodyMap = jsonDecode(bodyStr) as Map<String, dynamic>?;
      } catch (_) {}
    } else if (data is Map) {
      bodyMap = Map<String, dynamic>.from(data);
    }
    if (code == 429) {
      _authLog('rate-limited: status=429 path=${e.requestOptions.path}');
      return {
        'success': false,
        'message': bodyMap != null
            ? (bodyMap['error']?['message'] ??
                  bodyMap['message'] ??
                  'Too many requests. Please try again later.')
            : 'Too many requests. Please try again later.',
      };
    }
    final message = messageFn != null
        ? messageFn(code, bodyMap ?? bodyStr)
        : _messageFromBody(bodyMap);
    return {'success': false, 'message': message ?? defaultMessage};
  }

  static String? _messageFromBody(dynamic body) {
    if (body is Map) {
      String? msg;
      final err = body['error'];
      if (err is Map && err['message'] != null) {
        msg = err['message']?.toString();
      } else if (err is String && err.isNotEmpty) {
        msg = err;
      } else {
        msg = body['message']?.toString();
      }
      if (msg != null && !ErrorMessageUtils.isTechnicalMessage(msg)) {
        return msg;
      }
      return null;
    }
    return null;
  }

  dynamic _normalizeJson(dynamic value) {
    if (value is Map) {
      return value.map(
        (key, nestedValue) =>
            MapEntry(key.toString(), _normalizeJson(nestedValue)),
      );
    }
    if (value is List) {
      return value.map(_normalizeJson).toList();
    }
    return value;
  }

  Map<String, dynamic>? _normalizeJsonMap(dynamic value) {
    final normalized = _normalizeJson(value);
    return normalized is Map<String, dynamic> ? normalized : null;
  }

  String _normalizedBaseUrl(String? value) {
    if (value == null) return '';
    return value.trim().replaceAll(RegExp(r'/+$'), '');
  }

  Future<void> _persistCurrentBaseUrl(SharedPreferences prefs) async {
    await prefs.setString(_kAuthBaseUrl, _normalizedBaseUrl(AppConstants.baseUrl));
  }

  Future<void> _clearStoredSession(SharedPreferences prefs) async {
    _api.clearAuthToken();
    await AttendanceTemplateStore.clear();
    await LiveTrackingService().stopTracking();
    await FcmService.clearStoredNotifications();
    await prefs.remove('token');
    await prefs.remove(AppConstants.refreshTokenPrefsKey);
    await prefs.remove('user');
    await prefs.remove('staff');
    await prefs.remove('taskSettings');
    await prefs.remove('businessId');
  }

  Future<bool> clearSessionIfBaseUrlChanged() async {
    final prefs = await SharedPreferences.getInstance();
    final currentBaseUrl = _normalizedBaseUrl(AppConstants.baseUrl);
    final storedBaseUrl = _normalizedBaseUrl(prefs.getString(_kAuthBaseUrl));

    if (storedBaseUrl.isEmpty) {
      await _persistCurrentBaseUrl(prefs);
      return false;
    }

    if (storedBaseUrl == currentBaseUrl) {
      return false;
    }

    final hadSession =
        (prefs.getString('token')?.trim().isNotEmpty ?? false) ||
        prefs.getString('user') != null;

    await _clearStoredSession(prefs);
    await _persistCurrentBaseUrl(prefs);
    return hadSession;
  }

  Future<UserCredential?> signInWithGoogle() async {
    try {
      // Trigger the authentication flow
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        // The user canceled the sign-in
        return null;
      }

      // Obtain the auth details from the request
      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      // Create a new credential
      final OAuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // Sign in to Firebase with the user credentials
      return await _firebaseAuth.signInWithCredential(credential);
    } catch (e) {
      return null;
    }
  }

  // Verify email with backend after Google Sign-In
  Future<Map<String, dynamic>> googleLoginBackend(String email) async {
    try {
      final response = await _api.dio.post<Map<String, dynamic>>(
        '/auth/google-login',
        data: {'email': email},
      );
      final body = response.data ?? {};
      final data = body['data'];
      final prefs = await SharedPreferences.getInstance();
      if (data != null && data['accessToken'] != null) {
        await prefs.setString('token', data['accessToken']);
      }
      if (data != null) {
        final rt = data['refreshToken']?.toString();
        if (rt != null && rt.trim().isNotEmpty) {
          await prefs.setString(AppConstants.refreshTokenPrefsKey, rt.trim());
        } else {
          await prefs.remove(AppConstants.refreshTokenPrefsKey);
        }
      }
      if (data != null && data['user'] != null) {
        await prefs.setString('user', jsonEncode(data['user']));
        final user = data['user'] as Map<String, dynamic>?;
        final taskSettings = user?['taskSettings'] as Map<String, dynamic>?;
        if (taskSettings != null) {
          await prefs.setString('taskSettings', jsonEncode(taskSettings));
        }
      }
      await _persistCurrentBaseUrl(prefs);
      _api.setAuthToken(data?['accessToken']);
      if (kDebugMode) debugPrint('[AuthService] login success – registering FCM token');
      await FcmService.sendTokenToBackendAfterLogin();
      return {'success': true, 'data': data};
    } on DioException catch (e) {
      return _handleDioError(e, 'Login failed', (code, body) {
        if (code != null && code >= 500) {
          return 'Server error ($code). The backend server is not responding. Please try again later.';
        }
        return _messageFromBody(body) ?? 'Login failed';
      });
    } catch (e) {
      return {'success': false, 'message': _handleException(e)};
    }
  }

  String _handleException(dynamic error) {
    return ErrorMessageUtils.toUserFriendlyMessage(error);
  }

  /// Returns the current user's display name from cached user data, or empty string if not found.
  Future<String> getCurrentUserName() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userStr = prefs.getString('user');
      if (userStr == null) return '';
      final user = jsonDecode(userStr) as Map<String, dynamic>?;
      final name = user?['name']?.toString().trim();
      return name ?? '';
    } catch (_) {
      return '';
    }
  }

  Future<Map<String, dynamic>> getProfile({bool useWebHrmsApi = false}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String? token = prefs.getString('token');

      // Sanitize token
      if (token != null && (token.startsWith('"') || token.endsWith('"'))) {
        token = token.replaceAll('"', '');
      }

      if (token == null) {
        return {'success': false, 'message': 'Not authenticated'};
      }
      if (!useWebHrmsApi) {
        _api.setAuthToken(token);
      }
      try {
        final response = useWebHrmsApi
            ? await webHrmsApiDio().get<Map<String, dynamic>>('/auth/profile')
            : await _api.dio.get<Map<String, dynamic>>(
          '/auth/profile',
        );
        final body = response.data ?? {};
        return {'success': true, 'data': _normalizeJsonMap(body['data'])};
      } on DioException catch (e) {
        if (e.response?.statusCode == 404) {
          final userStr = prefs.getString('user');
          if (userStr != null) {
            try {
              final userObj = _normalizeJsonMap(jsonDecode(userStr));
              final staffObj = _normalizeJsonMap(
                prefs.getString('staff') != null
                    ? jsonDecode(prefs.getString('staff')!)
                    : null,
              );
              return {
                'success': true,
                'data': {
                  'profile': userObj,
                  'staffData': staffObj ?? <String, dynamic>{},
                },
              };
            } catch (_) {}
          }
          return {'success': false, 'message': 'Profile not found (404).'};
        }
        return _handleDioError(e, 'Failed to fetch profile', null);
      }
    } catch (e) {
      return {'success': false, 'message': _handleException(e)};
    }
  }

  Future<Map<String, dynamic>> updateProfile(Map<String, dynamic> data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      if (token == null) {
        return {'success': false, 'message': 'Not authenticated'};
      }
      _api.setAuthToken(token);
      await _api.dio.put<Map<String, dynamic>>('/auth/profile', data: data);
      return {'success': true};
    } on DioException catch (e) {
      return _handleDioError(e, 'Failed to update profile', null);
    } catch (e) {
      return {'success': false, 'message': _handleException(e)};
    }
  }

  /// Update education details. [education] is a list of maps with keys:
  /// qualification, courseName, institution, university, yearOfPassing, percentage, cgpa
  Future<Map<String, dynamic>> updateEducation(
    List<Map<String, dynamic>> education,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      if (token == null) {
        return {'success': false, 'message': 'Not authenticated'};
      }

      _api.setAuthToken(token);
      final response = await _api.dio.patch<Map<String, dynamic>>(
        '/auth/profile/education',
        data: {'education': education},
      );
      final body = response.data;
      if (body != null && body['data'] != null) {
        return {'success': true, 'data': body['data']};
      }
      return {
        'success': false,
        'message': 'Invalid response format from server',
      };
    } on DioException catch (e) {
      return _handleDioError(e, 'Failed to update education', null);
    } catch (e) {
      return {'success': false, 'message': _handleException(e)};
    }
  }

  /// Update experience details. [experience] is a list of maps with keys:
  /// company, role, designation, durationFrom, durationTo, keyResponsibilities, reasonForLeaving
  Future<Map<String, dynamic>> updateExperience(
    List<Map<String, dynamic>> experience,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String? token = prefs.getString('token');
      if (token == null) {
        return {'success': false, 'message': 'Not authenticated'};
      }

      // Sanitize token
      if (token.startsWith('"') || token.endsWith('"')) {
        token = token.replaceAll('"', '');
      }

      _api.setAuthToken(token);
      final response = await _api.dio.patch<Map<String, dynamic>>(
        '/auth/profile/experience',
        data: {'experience': experience},
      );
      final body = response.data;
      if (body != null) {
        return {
          'success': true,
          'data': body['data'],
          'message': body['message'] ?? 'Experience updated successfully',
        };
      }
      return {
        'success': false,
        'message': 'Invalid response format from server',
      };
    } on DioException catch (e) {
      return _handleDioError(e, 'Failed to update experience', null);
    } catch (e) {
      return {'success': false, 'message': _handleException(e)};
    }
  }

  Future<void> logout() async {
    InteractionSocketService.instance.disconnect();
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token != null && token.isNotEmpty) {
      final t = token.startsWith('"') || token.endsWith('"') ? token.replaceAll('"', '') : token;
      _api.setAuthToken(t);
      try {
        await _api.dio.post<dynamic>('/notifications/fcm-token', data: {'fcmToken': ''});
      } catch (_) {
        // Ignore FCM token clear errors
      }
    }
    _api.clearAuthToken();
    SwrCache.clearAll();
    await AttendanceTemplateStore.clear();
    await LiveTrackingService().stopTracking();
    await FcmService.clearStoredNotifications();
    await prefs.clear();
    await _persistCurrentBaseUrl(prefs);
    await _googleSignIn.signOut();
    await _firebaseAuth.signOut();
  }

  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token');
  }

  /// Returns true if staff is active, false when deactivated or session expired, null on
  /// transient network errors.
  Future<bool?> checkStaffActive() async {
    final prefs = await SharedPreferences.getInstance();
    String? token = prefs.getString('token');
    if (token == null || token.isEmpty) return null;
    if (token.startsWith('"') || token.endsWith('"')) token = token.replaceAll('"', '');
    try {
      _api.setAuthToken(token);
      final response = await _api.dio.get<Map<String, dynamic>>('/auth/check-active');
      final data = response.data;
      if (data == null) return null;
      return data['active'] == true;
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;
      if (statusCode == 401) {
        // Only force logout when backend clearly indicates token expiry/invalidity.
        // Some environments may transiently return 401 for reasons unrelated to session.
        final bodyMessage = _messageFromBody(e.response?.data)?.toLowerCase() ?? '';
        final raw = e.response?.data?.toString().toLowerCase() ?? '';
        final combined = '$bodyMessage $raw';
        final sessionExpired =
            combined.contains('jwt expired') ||
            combined.contains('token expired') ||
            combined.contains('session expired') ||
            combined.contains('token failed') ||
            combined.contains('not authorized');
        if (sessionExpired) return false;
        return null;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Task settings (enableOtpVerification, autoApprove, etc.) stored on login.
  /// Used by arrived screen as fallback when task doesn't have isOtpRequired.
  static Future<bool> isOtpRequiredFromStoredSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final str = prefs.getString('taskSettings');
    if (str == null) return false;
    try {
      final map = jsonDecode(str) as Map<String, dynamic>?;
      return map?['enableOtpVerification'] == true;
    } catch (_) {
      return false;
    }
  }

  // -------------------------
  // Forgot password with OTP
  // -------------------------

  Future<Map<String, dynamic>> forgotPassword(
    String email, {
    int retryCount = 0,
  }) async {
    try {
      final response = await _api.dio.post<Map<String, dynamic>>(
        '/auth/forgot-password',
        data: {'email': email},
      );
      final body = response.data;
      final success = body?['success'] == true;
      return {
        'success': success,
        'message': body?['message'] as String? ?? (success ? 'OTP sent successfully' : 'Failed to send OTP'),
      };
    } on DioException catch (e) {
      return _handleDioError(e, 'Failed to send OTP', (code, body) {
        if (code == 404) {
          return _messageFromBody(body) ?? 'User not found.';
        }
        if (code != null && code >= 500) {
          return 'Server error ($code). The backend server is not responding. Please try again later.';
        }
        return 'Failed to send OTP';
      });
    } catch (e) {
      return {'success': false, 'message': _handleException(e)};
    }
  }

  Future<Map<String, dynamic>> verifyOtp({
    required String email,
    required String otp,
  }) async {
    try {
      final response = await _api.dio.post<Map<String, dynamic>>(
        '/auth/verify-otp',
        data: {'email': email, 'otp': otp},
      );
      final body = response.data;
      return {
        'success': true,
        'message': body?['message'] as String? ?? 'OTP verified successfully',
      };
    } on DioException catch (e) {
      return _handleDioError(e, 'Invalid or expired OTP', null);
    } catch (e) {
      return {'success': false, 'message': _handleException(e)};
    }
  }

  Future<Map<String, dynamic>> resetPassword({
    required String email,
    required String otp,
    required String newPassword,
  }) async {
    try {
      final response = await _api.dio.post<Map<String, dynamic>>(
        '/auth/reset-password',
        data: {'email': email, 'otp': otp, 'newPassword': newPassword},
      );
      final body = response.data;
      return {
        'success': true,
        'message': body?['message'] as String? ?? 'Password reset successfully',
      };
    } on DioException catch (e) {
      return _handleDioError(e, 'Failed to reset password', null);
    } catch (e) {
      return {'success': false, 'message': _handleException(e)};
    }
  }

  // -------------------------
  // Change password (old + new)
  // -------------------------

  Future<Map<String, dynamic>> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String? token = prefs.getString('token');

      if (token == null) {
        return {'success': false, 'message': 'Not authenticated'};
      }

      // Sanitize token
      if (token.startsWith('"') || token.endsWith('"')) {
        token = token.replaceAll('"', '');
      }

      _api.setAuthToken(token);
      final response = await _api.dio.post<Map<String, dynamic>>(
        '/auth/change-password',
        data: {'oldPassword': oldPassword, 'newPassword': newPassword},
      );
      final body = response.data;
      return {
        'success': true,
        'message':
            body?['message'] as String? ?? 'Password updated successfully',
      };
    } on DioException catch (e) {
      return _handleDioError(e, 'Failed to update password', null);
    } catch (e) {
      return {'success': false, 'message': _handleException(e)};
    }
  }

  // -------------------------
  // Update profile photo (Cloudinary via backend)
  // -------------------------

  Future<Map<String, dynamic>> updateProfilePhoto(File imageFile) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String? token = prefs.getString('token');

      if (token == null) {
        return {'success': false, 'message': 'Not authenticated'};
      }

      // Sanitize token
      if (token.startsWith('"') || token.endsWith('"')) {
        token = token.replaceAll('"', '');
      }

      _api.setAuthToken(token);
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(
          imageFile.path,
          filename: imageFile.path.split(RegExp(r'[/\\]')).last,
        ),
      });
      final response = await _api.dio.post<Map<String, dynamic>>(
        '/auth/profile-photo',
        data: formData,
        options: Options(
          sendTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 30),
        ),
      );
      final body = response.data;
      if (body != null &&
          body['data'] != null &&
          body['data']['photoUrl'] != null) {
        final userStr = prefs.getString('user');
        if (userStr != null) {
          try {
            final user = jsonDecode(userStr) as Map<String, dynamic>;
            final url = body['data']['photoUrl'] as String?;
            if (url != null) {
              user['photoUrl'] = url;
              user['avatar'] = url;
              await prefs.setString('user', jsonEncode(user));
            }
          } catch (_) {}
        }
      }
      return {
        'success': true,
        'message': body?['message'] ?? 'Profile photo updated successfully',
        'data': body?['data'],
      };
    } on DioException catch (e) {
      return _handleDioError(e, 'Failed to update profile photo', null);
    } catch (e) {
      return {'success': false, 'message': _handleException(e)};
    }
  }

  /// Verify selfie against profile photo. Returns { success, match, message }.
  /// [message] is always user-friendly (no raw errors or exceptions).
  Future<Map<String, dynamic>> verifyFace(String selfieDataUrl) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String? token = prefs.getString('token');
      if (token != null && (token.startsWith('"') || token.endsWith('"'))) {
        token = token.replaceAll('"', '');
      }
      if (token == null) {
        return {
          'success': false,
          'match': false,
          'message': 'Please sign in and try again.',
        };
      }

      _api.setAuthToken(token);
      final response = await _api.dio.post<Map<String, dynamic>>(
        '/auth/verify-face',
        data: {'selfie': selfieDataUrl},
        options: Options(receiveTimeout: const Duration(seconds: 90)),
      );
      final body = response.data;
      final match = body?['match'] == true;
      final rawMessage =
          body?['message']?.toString() ??
          body?['error']?['message']?.toString();
      final message = _userFriendlyVerifyMessage(rawMessage, match);
      return {'success': true, 'match': match, 'message': message};
    } on DioException catch (e) {
      final body = e.response?.data;
      final rawMessage = body is Map
          ? (body['message'] ?? body['error']?['message'])?.toString()
          : null;
      return {
        'success': false,
        'match': false,
        'message': _userFriendlyVerifyMessage(rawMessage, false),
      };
    } catch (e) {
      return {
        'success': false,
        'match': false,
        'message': _userFriendlyVerifyMessage(_handleException(e), false),
      };
    }
  }

  /// Maps backend/exception text to clear, short text for the user.
  String _userFriendlyVerifyMessage(String? raw, bool matched) {
    if (matched) return 'Photo matched';
    if (raw == null || raw.isEmpty) {
      return 'Face not matching. Please try again.';
    }
    final s = raw.toLowerCase();
    if (s.contains('timeout') || s.contains('timed out')) {
      return 'Verification took too long. Please try again.';
    }
    if (s.contains('network') ||
        s.contains('internet') ||
        s.contains('connection')) {
      return 'Check your internet connection and try again.';
    }
    if (s.contains('server') || s.contains('respond')) {
      return 'Server is busy. Please try again.';
    }
    if (s.contains('no face') || s.contains('face could not be detected')) {
      return 'No face detected. Ensure your face is clearly visible.';
    }
    if (s.contains('profile photo') || s.contains('upload a profile')) {
      return 'Please upload a profile photo first.';
    }
    if (s.contains('not authenticated') || s.contains('sign in')) {
      return 'Please sign in and try again.';
    }
    if (s.contains('exception') || s.contains('error') || s.length > 60) {
      return 'Face verification failed. Please try again.';
    }
    if (s.contains('not matching') || s.contains('no match')) {
      return 'Face not matching. Please try again.';
    }
    return 'Face not matching. Please try again.';
  }
}
