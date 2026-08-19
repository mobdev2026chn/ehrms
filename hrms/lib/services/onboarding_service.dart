import 'dart:io';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_client.dart';

class OnboardingService {
  final ApiClient _api = ApiClient();

  /// MIME type for backend multer fileFilter (PDF, DOC, DOCX, JPG, PNG).
  static String? _mimeTypeForPath(String path) {
    final ext = path.split(RegExp(r'[/\\]')).last.split('.').last.toLowerCase();
    switch (ext) {
      case 'pdf':
        return 'application/pdf';
      case 'doc':
        return 'application/msword';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      default:
        return null;
    }
  }

  Future<void> _setToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token != null) _api.setAuthToken(token);
  }

  Future<Map<String, dynamic>> getMyOnboarding() async {
    try {
      await _setToken();
      final response = await _api.dio.get<Map<String, dynamic>>(
        '/onboarding/my-onboarding',
      );
      final body = response.data;
      if (body != null && body['data'] != null) {
        return {'success': true, 'data': body['data']};
      }
      return {'success': true, 'data': body?['data']};
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return {'success': true, 'data': null};
      }
      final d = e.response?.data;
      String message = 'Failed to fetch onboarding data';
      if (d is Map) {
        message =
            (d['error']?['message'] ?? d['message']) as String? ?? message;
      }
      return {'success': false, 'message': message};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  Future<Map<String, dynamic>> uploadDocument(
    String onboardingId,
    String documentId,
    File file,
  ) async {
    try {
      await _setToken();
      final filename = file.path.split(RegExp(r'[/\\]')).last;
      final mimeType = _mimeTypeForPath(file.path);
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(
          file.path,
          filename: filename,
          contentType: mimeType != null ? DioMediaType.parse(mimeType) : null,
        ),
      });
      // Dio sets Content-Type to multipart/form-data with boundary when data is FormData
      final response = await _api.dio.post<Map<String, dynamic>>(
        '/onboarding/$onboardingId/documents/$documentId/upload',
        data: formData,
        options: Options(
          sendTimeout: const Duration(seconds: 60),
          receiveTimeout: const Duration(seconds: 60),
        ),
      );
      final body = response.data;
      if (body != null && (body['data'] != null || body['success'] == true)) {
        return {'success': true, 'data': body['data']};
      }
      String message = 'Failed to upload document';
      if (body != null) {
        final errMsg = body['error']?['message'] ?? body['message'];
        if (errMsg != null) message = errMsg.toString();
      }
      return {'success': false, 'message': message};
    } on DioException catch (e) {
      final d = e.response?.data;
      String message = 'Failed to upload document';
      if (d is Map) {
        final errMsg = d['error']?['message'] ?? d['message'];
        if (errMsg != null) message = errMsg.toString();
      } else if (e.message != null && e.message!.isNotEmpty) {
        message = e.message!;
      }
      return {'success': false, 'message': message};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }
}
