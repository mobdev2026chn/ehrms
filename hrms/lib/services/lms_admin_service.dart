// hrms/lib/services/lms_admin_service.dart
// Admin-side LMS API service. Isolated from the employee LmsService so the
// existing employee LMS flows remain untouched.
//
// IMPORTANT: this app_backend (see src/controllers/lmsController.js) only
// exposes the employee LMS routes — there are no admin-aggregate endpoints.
// So the admin screens are wired to the real existing routes and parse their
// actual response shapes:
//   GET /lms/courses            -> { data: Course[] }            (Published only)
//   GET /lms/categories         -> { data: string[] }
//   GET /lms/employees          -> { data: { staff: [{name,email}] } }
//   GET /lms/departments        -> { data: { departments: [{_id,name}] } }
//   GET /lms/my-sessions        -> { data: LiveSession[] }
//   GET /lms/analytics/my-scores-> { data: { summary, courses, quizStats } }

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/error_message_utils.dart';
import 'api_client.dart';

class LmsAdminService {
  final ApiClient _api = ApiClient();

  Future<void> _setToken() async {
    final prefs = await SharedPreferences.getInstance();
    String? token = prefs.getString('token');
    if (token != null && (token.startsWith('"') || token.endsWith('"'))) {
      token = token.replaceAll('"', '');
    }
    if (token != null && token.isNotEmpty) _api.setAuthToken(token);
  }

  static String _dioMessage(DioException e) {
    return ErrorMessageUtils.messageFromDioException(
      e,
      fallback: e.message ?? 'Request failed',
    );
  }

  /// GETs [path] and returns the raw body `data` (List or Map). On failure
  /// returns {success:false, data:[]} so the UI still renders gracefully.
  Future<Map<String, dynamic>> _get(String path) async {
    await _setToken();
    try {
      final res = await _api.dio.get<dynamic>(path);
      final body = res.data;
      if (body is Map) {
        return {
          'success': body['success'] != false,
          'data': body['data'] ?? body,
        };
      }
      if (body is List) return {'success': true, 'data': body};
      return {'success': true, 'data': body};
    } on DioException catch (e) {
      return {'success': false, 'message': _dioMessage(e), 'data': const []};
    }
  }

  // ── Course Library ────────────────────────────────────────────────────────
  /// GET /lms/courses — all published courses (lmsController.getAllCourses).
  Future<Map<String, dynamic>> getCourses() => _get('/lms/courses');

  /// GET /lms/categories — fixed category list (lmsController.getCategories).
  Future<Map<String, dynamic>> getCategories() => _get('/lms/categories');

  // ── Learners ──────────────────────────────────────────────────────────────
  /// GET /lms/employees — active staff {name,email} (lmsController.getEmployees).
  Future<Map<String, dynamic>> getLearners() => _get('/lms/employees');

  /// GET /lms/departments — distinct departments (lmsController.getDepartments).
  Future<Map<String, dynamic>> getDepartments() => _get('/lms/departments');

  // ── Live Sessions ─────────────────────────────────────────────────────────
  /// GET /lms/my-sessions — sessions visible to the user (lmsController.getMySessions).
  Future<Map<String, dynamic>> getSessions() => _get('/lms/my-sessions');

  // ── Assessment & Analytics ────────────────────────────────────────────────
  /// GET /lms/analytics/my-scores — summary + per-course progress + quizStats
  /// (lmsController.getMyScores). Used by both the Assessment and Scores tabs.
  Future<Map<String, dynamic>> getMyScores() => _get('/lms/analytics/my-scores');
}
