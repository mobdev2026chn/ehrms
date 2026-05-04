import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/constants.dart';
import '../core/network/dio_client.dart';
import 'api_client.dart';
import 'interaction_service.dart';

/// Dio client for [AppConstants.webBaseUrl] (HRMS web API).
/// Auth: `interaction_access_token` (web JWT) when present, else `token` / ApiClient header.
/// Used by Salary Overview and [SalaryService] payroll routes so data matches the web app.
Dio webHrmsApiDio() {
  var base = AppConstants.webBaseUrl.replaceAll(RegExp(r'/+$'), '');
  if (base.endsWith('/')) base = base.substring(0, base.length - 1);
  final dio = Dio(
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
  dio.interceptors.add(FormDataContentTypeInterceptor());
  dio.interceptors.add(SessionExpiryInterceptor(dio));
  dio.interceptors.add(RetryOnRateLimitInterceptor(dio));
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) async {
        final prefs = await SharedPreferences.getInstance();
        var t = InteractionService.normalizeAccessToken(
          prefs.getString(AppConstants.interactionAccessTokenPrefsKey),
        );
        t ??= InteractionService.normalizeAccessToken(prefs.getString('token'));
        if (t == null) {
          final auth = ApiClient().dio.options.headers['Authorization'];
          if (auth is String) {
            t = InteractionService.normalizeAccessToken(
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
  return dio;
}
