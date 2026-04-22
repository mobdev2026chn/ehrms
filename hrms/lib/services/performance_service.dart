// hrms/lib/services/performance_service.dart
// Performance module API service
// Backend: app_backend routes - /api/performance/* (performanceRoutes), /api/pms (pmsRoutes)
// - GET /api/performance/cycles -> reviewCycleController.getReviewCycles
// - GET /api/performance/kra -> reviewCycleController.getKRAs
// - GET /api/pms -> pmsController.getGoals (params: myGoals, status, cycle)
// - POST /api/pms -> pmsController.createGoal

import 'package:dio/dio.dart';
import '../services/auth_service.dart';
import 'api_client.dart';

class PerformanceService {
  final AuthService _authService = AuthService();
  final ApiClient _api = ApiClient();

  /// Get employee performance summary (overview, average rating, total reviews, etc.)
  Future<Map<String, dynamic>> getEmployeeSummary() async {
    final token = await _authService.getToken();
    if (token == null) return _emptySummary();
    try {
      _api.setAuthToken(token);
      final response = await _api.dio.get<Map<String, dynamic>>(
        '/performance/reviews/employee/summary',
      );
      final data = response.data;
      if (data != null && data['success'] == true) {
        return data;
      }
      return _emptySummary();
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return _emptySummary();
      rethrow;
    }
  }

  Map<String, dynamic> _emptySummary() {
    return {
      'success': true,
      'data': {
        'employee': {
          'name': '',
          'designation': '',
          'department': '',
          'employeeId': '',
        },
        'averageRating': 0.0,
        'totalReviews': 0,
        'completedReviews': 0,
        'currentGoals': 0,
        'latestReview': null,
        'recentReviews': [],
      },
    };
  }

  /// Get performance reviews (my reviews)
  Future<Map<String, dynamic>> getPerformanceReviews({
    int page = 1,
    int limit = 20,
    String? status,
  }) async {
    final token = await _authService.getToken();
    if (token == null) {
      return {
        'success': true,
        'data': {'reviews': [], 'pagination': _emptyPagination()},
      };
    }
    try {
      _api.setAuthToken(token);
      final response = await _api.dio.get<Map<String, dynamic>>(
        '/performance/reviews',
        queryParameters: {
          'page': page,
          'limit': limit,
          'myReviews': true,
          if (status != null) 'status': status,
        },
      );
      final data = response.data;
      if (data != null) return data;
      return {
        'success': true,
        'data': {'reviews': [], 'pagination': _emptyPagination()},
      };
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return {
          'success': true,
          'data': {'reviews': [], 'pagination': _emptyPagination()},
        };
      }
      rethrow;
    }
  }

  Map<String, dynamic> _emptyPagination() {
    return {'page': 1, 'limit': 20, 'total': 0, 'pages': 0};
  }

  /// Get performance review by ID
  Future<Map<String, dynamic>> getPerformanceReviewById(String id) async {
    final token = await _authService.getToken();
    if (token == null) throw Exception('Not authenticated');
    _api.setAuthToken(token);
    final response = await _api.dio.get<Map<String, dynamic>>(
      '/performance/reviews/$id',
    );
    final data = response.data;
    if (data != null && data['success'] == true) return data;
    throw Exception('Review not found');
  }

  /// Submit self-review
  Future<Map<String, dynamic>> submitSelfReview({
    required String reviewId,
    required int overallRating,
    required List<String> strengths,
    required List<String> areasForImprovement,
    required List<String> achievements,
    required List<String> challenges,
    required List<String> goalsAchieved,
    required String comments,
  }) async {
    final token = await _authService.getToken();
    if (token == null) throw Exception('Not authenticated');
    _api.setAuthToken(token);
    final response = await _api.dio.patch<Map<String, dynamic>>(
      '/performance/reviews/$reviewId/self-review',
      data: {
        'overallRating': overallRating,
        'strengths': strengths,
        'areasForImprovement': areasForImprovement,
        'achievements': achievements,
        'challenges': challenges,
        'goalsAchieved': goalsAchieved,
        'comments': comments,
      },
    );
    final data = response.data;
    if (data != null && data['success'] == true) return data;
    throw Exception('Failed to submit review');
  }

  /// Get performance goals (my goals)
  Future<Map<String, dynamic>> getGoals({
    int page = 1,
    int limit = 20,
    String? status,
    String? cycle,
  }) async {
    final token = await _authService.getToken();
    if (token == null) {
      return {
        'success': true,
        'data': {'goals': [], 'pagination': _emptyPagination()},
      };
    }
    try {
      _api.setAuthToken(token);
      final response = await _api.dio.get<Map<String, dynamic>>(
        '/pms',
        queryParameters: {
          'page': page,
          'limit': limit,
          'myGoals': true,
          if (status != null) 'status': status,
          if (cycle != null) 'cycle': cycle,
        },
      );
      final data = response.data;
      if (data != null) return data;
      return {
        'success': true,
        'data': {'goals': [], 'pagination': _emptyPagination()},
      };
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return {
          'success': true,
          'data': {'goals': [], 'pagination': _emptyPagination()},
        };
      }
      rethrow;
    }
  }

  /// Create a new goal (submitted for manager approval when created by employee).
  Future<Map<String, dynamic>> createGoal({
    required String title,
    required String type,
    required String kpi,
    required String target,
    required int weightage,
    required String startDate,
    required String endDate,
    required String cycle,
    String? kraId,
  }) async {
    final token = await _authService.getToken();
    if (token == null) throw Exception('Not authenticated');
    _api.setAuthToken(token);
    final body = <String, dynamic>{
      'title': title,
      'type': type,
      'kpi': kpi,
      'target': target,
      'weightage': weightage,
      'startDate': startDate,
      'endDate': endDate,
      'cycle': cycle,
    };
    if (kraId != null && kraId.isNotEmpty) body['kraId'] = kraId;
    final response = await _api.dio.post<Map<String, dynamic>>(
      '/pms',
      data: body,
    );
    final data = response.data;
    if (data != null && data['success'] == true) return data;
    throw Exception(data?['error']?['message'] ?? 'Failed to create goal');
  }

  /// Update goal progress.
  Future<Map<String, dynamic>> updateGoalProgress(
    String goalId, {
    required int progress,
    String? achievements,
    String? challenges,
  }) async {
    final token = await _authService.getToken();
    if (token == null) throw Exception('Not authenticated');
    _api.setAuthToken(token);
    final body = <String, dynamic>{
      'progress': progress.clamp(0, 100),
      if (achievements != null) 'achievements': achievements,
      if (challenges != null) 'challenges': challenges,
    };
    final response = await _api.dio.patch<Map<String, dynamic>>(
      '/pms/$goalId/progress',
      data: body,
    );
    final data = response.data;
    if (data != null && data['success'] == true) return data;
    throw Exception(data?['error']?['message'] ?? 'Failed to update progress');
  }

  /// Mark goal as completed (requires 100% progress and approved status).
  Future<Map<String, dynamic>> completeGoal(
    String goalId, {
    String? completionNotes,
  }) async {
    final token = await _authService.getToken();
    if (token == null) throw Exception('Not authenticated');
    _api.setAuthToken(token);
    final body = <String, dynamic>{};
    if (completionNotes != null && completionNotes.isNotEmpty) {
      body['completionNotes'] = completionNotes;
    }
    final response = await _api.dio.patch<Map<String, dynamic>>(
      '/pms/$goalId/complete',
      data: body.isNotEmpty ? body : null,
    );
    final data = response.data;
    if (data != null && data['success'] == true) return data;
    throw Exception(data?['error']?['message'] ?? 'Failed to complete goal');
  }

  /// Get KRAs for Link to KRA dropdown.
  Future<Map<String, dynamic>> getKRAs({int page = 1, int limit = 1000}) async {
    final token = await _authService.getToken();
    if (token == null) {
      return {
        'success': true,
        'data': {'kras': [], 'pagination': _emptyPagination()},
      };
    }
    try {
      _api.setAuthToken(token);
      final response = await _api.dio.get<Map<String, dynamic>>(
        '/performance/kra',
        queryParameters: {'page': page, 'limit': limit},
      );
      final data = response.data;
      if (data != null) return data;
      return {
        'success': true,
        'data': {'kras': [], 'pagination': _emptyPagination()},
      };
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return {
          'success': true,
          'data': {'kras': [], 'pagination': _emptyPagination()},
        };
      }
      rethrow;
    }
  }

  /// Get review cycles (from /api/performance/cycles - app_backend performanceRoutes)
  Future<Map<String, dynamic>> getReviewCycles({
    int page = 1,
    int limit = 100,
    String? status,
    String? type,
  }) async {
    final token = await _authService.getToken();
    if (token == null) {
      return {
        'success': true,
        'data': {'cycles': [], 'pagination': _emptyPagination()},
      };
    }
    try {
      _api.setAuthToken(token);
      final response = await _api.dio.get<Map<String, dynamic>>(
        '/performance/cycles',
        queryParameters: {
          'page': page,
          'limit': limit,
          if (status != null) 'status': status,
          if (type != null) 'type': type,
        },
      );
      final data = response.data;
      if (data != null) return data;
      return {
        'success': true,
        'data': {'cycles': [], 'pagination': _emptyPagination()},
      };
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return {
          'success': true,
          'data': {'cycles': [], 'pagination': _emptyPagination()},
        };
      }
      rethrow;
    }
  }
}
