// hrms/lib/services/lms_service.dart
// LMS API service - mirrors web frontend lmsService for staff employee routes.
// Uses app_backend /api/lms/* endpoints.

import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/error_message_utils.dart';
import 'api_client.dart';

class LmsService {
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

  /// Fetches PDF bytes from a full URL (e.g. from getLmsFileUrl). Uses auth token. For in-app PDF viewer.
  /// [onProgress] receives (received, total); total may be -1 if server omits Content-Length.
  /// Uses longer timeout (60s) for large PDFs.
  Future<Uint8List?> fetchPdfBytes(
    String fullUrl, {
    void Function(int received, int total)? onProgress,
  }) async {
    if (fullUrl.isEmpty) return null;
    await _setToken();
    try {
      final res = await _api.dio.get<Uint8List>(
        fullUrl,
        options: Options(
          responseType: ResponseType.bytes,
          receiveTimeout: const Duration(seconds: 60),
          sendTimeout: const Duration(seconds: 30),
        ),
        onReceiveProgress: onProgress,
      );
      return res.data;
    } on DioException catch (_) {
      return null;
    }
  }

  // --- Courses ---
  /// GET /lms/courses - List all published courses (for library). Ref: lmsController.getAllCourses
  Future<Map<String, dynamic>> getAllCourses() async {
    await _setToken();
    try {
      final res = await _api.dio.get<Map<String, dynamic>>('/lms/courses');
      final body = res.data ?? {};
      return {'success': body['success'] == true, 'data': body['data'] ?? []};
    } on DioException catch (e) {
      return {'success': false, 'message': _dioMessage(e)};
    }
  }

  /// POST /lms/courses/:id/enroll - Self-enroll in course. Ref: lmsController.enrollCourse
  Future<Map<String, dynamic>> enrollCourse(String courseId) async {
    await _setToken();
    try {
      final res = await _api.dio.post<Map<String, dynamic>>(
        '/lms/courses/$courseId/enroll',
      );
      final body = res.data ?? {};
      return {'success': body['success'] == true, 'data': body['data']};
    } on DioException catch (e) {
      return {'success': false, 'message': _dioMessage(e)};
    }
  }

  Future<Map<String, dynamic>> getMyCourses() async {
    await _setToken();
    try {
      final res = await _api.dio.get<Map<String, dynamic>>('/lms/my-courses');
      final body = res.data ?? {};
      return {'success': body['success'] == true, 'data': body['data'] ?? []};
    } on DioException catch (e) {
      return {'success': false, 'message': _dioMessage(e)};
    }
  }

  Future<Map<String, dynamic>> getCourseDetails(String courseId) async {
    await _setToken();
    try {
      final res = await _api.dio.get<Map<String, dynamic>>(
        '/lms/courses/$courseId/details',
      );
      final body = res.data ?? {};
      return {'success': body['success'] == true, 'data': body['data']};
    } on DioException catch (e) {
      return {'success': false, 'message': _dioMessage(e)};
    }
  }

  Future<Map<String, dynamic>> getMyProgress(String courseId) async {
    await _setToken();
    try {
      final res = await _api.dio.get<Map<String, dynamic>>(
        '/lms/courses/$courseId/my-progress',
      );
      final body = res.data ?? {};
      return {'success': body['success'] == true, 'data': body['data'] ?? {}};
    } on DioException catch (e) {
      return {'success': false, 'message': _dioMessage(e)};
    }
  }

  Future<Map<String, dynamic>> completeLesson(
    String courseId,
    String lessonTitle,
  ) async {
    await _setToken();
    try {
      final res = await _api.dio.post<Map<String, dynamic>>(
        '/lms/courses/$courseId/complete-lesson',
        data: {'lessonTitle': lessonTitle},
      );
      final body = res.data ?? {};
      return {'success': body['success'] == true, 'data': body['data']};
    } on DioException catch (e) {
      return {'success': false, 'message': _dioMessage(e)};
    }
  }

  Future<Map<String, dynamic>> updateProgress(
    String courseId,
    String contentId, {
    bool? completed,
    int? watchTime,
  }) async {
    await _setToken();
    try {
      final data = <String, dynamic>{'contentId': contentId};
      if (completed != null) data['completed'] = completed;
      if (watchTime != null) data['watchTime'] = watchTime;
      final res = await _api.dio.post<Map<String, dynamic>>(
        '/lms/courses/$courseId/progress',
        data: data,
      );
      final body = res.data ?? {};
      return {'success': body['success'] == true, 'data': body['data']};
    } on DioException catch (e) {
      return {'success': false, 'message': _dioMessage(e)};
    }
  }

  Future<Map<String, dynamic>> getCategories() async {
    await _setToken();
    try {
      final res = await _api.dio.get<Map<String, dynamic>>('/lms/categories');
      final body = res.data ?? {};
      return {'success': body['success'] == true, 'data': body['data'] ?? []};
    } on DioException catch (e) {
      return {'success': false, 'message': _dioMessage(e)};
    }
  }

  // --- Live Sessions ---
  Future<Map<String, dynamic>> getMySessions({String? search}) async {
    await _setToken();
    try {
      final params = <String, dynamic>{};
      if (search != null && search.isNotEmpty) params['search'] = search;
      final res = await _api.dio.get<Map<String, dynamic>>(
        '/lms/my-sessions',
        queryParameters: params,
      );
      final body = res.data ?? {};
      return {'success': body['success'] == true, 'data': body['data'] ?? []};
    } on DioException catch (e) {
      return {'success': false, 'message': _dioMessage(e)};
    }
  }

  Future<Map<String, dynamic>> createSession(
    Map<String, dynamic> payload,
  ) async {
    await _setToken();
    try {
      final res = await _api.dio.post<Map<String, dynamic>>(
        '/lms/sessions',
        data: payload,
      );
      final body = res.data ?? {};
      return {'success': body['success'] == true, 'data': body['data']};
    } on DioException catch (e) {
      return {'success': false, 'message': _dioMessage(e)};
    }
  }

  Future<Map<String, dynamic>> updateSession(
    String sessionId,
    Map<String, dynamic> payload,
  ) async {
    await _setToken();
    try {
      final res = await _api.dio.put<Map<String, dynamic>>(
        '/lms/sessions/$sessionId',
        data: payload,
      );
      final body = res.data ?? {};
      return {'success': body['success'] == true, 'data': body['data']};
    } on DioException catch (e) {
      return {'success': false, 'message': _dioMessage(e)};
    }
  }

  Future<Map<String, dynamic>> deleteSession(String sessionId) async {
    await _setToken();
    try {
      await _api.dio.delete('/lms/sessions/$sessionId');
      return {'success': true};
    } on DioException catch (e) {
      return {'success': false, 'message': _dioMessage(e)};
    }
  }

  Future<Map<String, dynamic>> joinSession(String sessionId) async {
    await _setToken();
    try {
      await _api.dio.post('/lms/my-sessions/$sessionId/join');
      return {'success': true};
    } on DioException catch (e) {
      return {'success': false, 'message': _dioMessage(e)};
    }
  }

  Future<Map<String, dynamic>> leaveSession(
    String sessionId, {
    String? feedbackSummary,
    String? issues,
    int? rating,
  }) async {
    await _setToken();
    try {
      final data = <String, dynamic>{};
      if (feedbackSummary != null) data['feedbackSummary'] = feedbackSummary;
      if (issues != null) data['issues'] = issues;
      if (rating != null) data['rating'] = rating;
      await _api.dio.post('/lms/my-sessions/$sessionId/leave', data: data);
      return {'success': true};
    } on DioException catch (e) {
      return {'success': false, 'message': _dioMessage(e)};
    }
  }

  // --- Learning Engine ---
  /// GET /lms/learning-engine — same as web (hrms.askeva.net). Returns heatmap; supports both
  /// { success, heatmap } and raw { dailyGoal, skills, heatmap, ... } response shapes.
  Future<Map<String, dynamic>> getLearningEngine() async {
    await _setToken();
    try {
      final res = await _api.dio.get<Map<String, dynamic>>(
        '/lms/learning-engine',
      );
      final body = res.data ?? {};
      final heatmap = body['heatmap'] ?? body['data']?['heatmap'] ?? [];
      final heatmapList = heatmap is List ? heatmap : [];
      return {
        'success': body['success'] == true || body['heatmap'] != null,
        'heatmap': heatmapList,
        if (body['dailyGoal'] != null) 'dailyGoal': body['dailyGoal'],
        if (body['skills'] != null) 'skills': body['skills'],
        if (body['readiness'] != null) 'readiness': body['readiness'],
      };
    } on DioException catch (e) {
      return {'success': false, 'message': _dioMessage(e)};
    }
  }

  /// Log learning activity for heatmap (same as web logLearningActivity).
  Future<void> logLearningActivity({
    int totalMinutes = 0,
    int lessonsCompleted = 0,
    int quizzesAttempted = 0,
    int assessmentsAttempted = 0,
    int liveSessionsAttended = 0,
  }) async {
    await _setToken();
    try {
      await _api.dio.post<Map<String, dynamic>>(
        '/lms/learning-engine/activity',
        data: {
          'totalMinutes': totalMinutes,
          'lessonsCompleted': lessonsCompleted,
          'quizzesAttempted': quizzesAttempted,
          'assessmentsAttempted': assessmentsAttempted,
          'liveSessionsAttended': liveSessionsAttended,
        },
      );
    } on DioException catch (_) {
      // Non-blocking; heatmap still gets data from progress/viewedAt
    }
  }

  Future<Map<String, dynamic>> getMyScores() async {
    await _setToken();
    try {
      final res = await _api.dio.get<Map<String, dynamic>>(
        '/lms/analytics/my-scores',
      );
      final body = res.data ?? {};
      final result = {'success': body['success'] == true, 'data': body['data']};
      return result;
    } on DioException catch (e) {
      return {'success': false, 'message': _dioMessage(e)};
    }
  }

  // --- AI Quiz ---
  Future<Map<String, dynamic>> generateAIQuiz({
    required String courseId,
    required List<String> lessonTitles,
    int questionCount = 5,
    String difficulty = 'Medium',
    String? materialId,
    List<String>? materialIds,
  }) async {
    await _setToken();
    try {
      final data = <String, dynamic>{
        'courseId': courseId,
        'lessonTitles': lessonTitles,
        'questionCount': questionCount,
        'difficulty': difficulty,
      };
      if (materialId != null) data['materialId'] = materialId;
      if (materialIds != null && materialIds.isNotEmpty) {
        data['materialIds'] = materialIds;
      }
      final res = await _api.dio.post<Map<String, dynamic>>(
        '/lms/ai-quiz/generate',
        data: data,
        options: Options(
          receiveTimeout: const Duration(seconds: 90),
          sendTimeout: const Duration(seconds: 30),
        ),
      );
      final body = res.data ?? {};
      return {'success': body['success'] == true, 'data': body['data']};
    } on DioException catch (e) {
      return {'success': false, 'message': _dioMessage(e)};
    }
  }

  Future<Map<String, dynamic>> getAIQuiz(String quizId) async {
    await _setToken();
    try {
      final res = await _api.dio.get<Map<String, dynamic>>(
        '/lms/ai-quiz/$quizId',
      );
      final body = res.data ?? {};
      return {'success': body['success'] == true, 'data': body['data']};
    } on DioException catch (e) {
      return {'success': false, 'message': _dioMessage(e)};
    }
  }

  Future<Map<String, dynamic>> submitAIQuiz(
    String quizId, {
    required List<Map<String, dynamic>> responses,
    int? completionTime,
  }) async {
    await _setToken();
    try {
      final data = <String, dynamic>{'responses': responses};
      if (completionTime != null) data['completionTime'] = completionTime;
      final res = await _api.dio.post<Map<String, dynamic>>(
        '/lms/ai-quiz/$quizId/submit',
        data: data,
      );
      final body = res.data ?? {};
      return {'success': body['success'] == true, 'data': body['data']};
    } on DioException catch (e) {
      return {'success': false, 'message': _dioMessage(e)};
    }
  }

  // --- Final Assessment ---
  Future<Map<String, dynamic>> submitCourseAssessment(
    String courseId, {
    required List<Map<String, dynamic>> answers,
  }) async {
    await _setToken();
    try {
      final res = await _api.dio.post<Map<String, dynamic>>(
        '/lms/courses/$courseId/assessment/submit',
        data: {'answers': answers},
      );
      final body = res.data ?? {};
      return {'success': body['success'] == true, 'data': body['data']};
    } on DioException catch (e) {
      return {'success': false, 'message': _dioMessage(e)};
    }
  }

  // --- Meta (for schedule modal) ---
  Future<Map<String, dynamic>> getDepartments() async {
    await _setToken();
    try {
      final res = await _api.dio.get<Map<String, dynamic>>('/lms/departments');
      final body = res.data ?? {};
      return {'success': body['success'] == true, 'data': body['data'] ?? {}};
    } on DioException catch (e) {
      return {'success': false, 'message': _dioMessage(e)};
    }
  }

  Future<Map<String, dynamic>> getEmployees() async {
    await _setToken();
    try {
      final res = await _api.dio.get<Map<String, dynamic>>('/lms/employees');
      final body = res.data ?? {};
      return {'success': body['success'] == true, 'data': body['data'] ?? {}};
    } on DioException catch (e) {
      return {'success': false, 'message': _dioMessage(e)};
    }
  }
}
