// hrms/lib/services/api_client.dart
// Delegates to core/network/dio_client.dart. Single Dio instance for the app.
// Existing services keep using ApiClient; new data layer uses DioClient directly.

import 'package:dio/dio.dart';
import '../core/network/dio_client.dart';

export '../core/network/dio_client.dart' show RetryOnRateLimitInterceptor;
typedef RetryOn429Interceptor = RetryOnRateLimitInterceptor;

/// Singleton facade. Dio lives in [DioClient]; this keeps existing service code working.
class ApiClient {
  static final ApiClient _instance = ApiClient._internal();
  factory ApiClient() => _instance;

  final DioClient _client = DioClient();

  ApiClient._internal();

  Dio get dio => _client.dio;

  void setAuthToken(String? token) => _client.setAuthToken(token);
  void clearAuthToken() => _client.clearAuthToken();

  Future<Response<T>> request<T>(
    String path, {
    String method = 'GET',
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic>? headers,
    Options? options,
  }) {
    return dio.request<T>(
      path.startsWith('/') ? path : '/$path',
      data: data,
      queryParameters: queryParameters,
      options: (options ?? Options()).copyWith(method: method, headers: headers),
    );
  }
}
