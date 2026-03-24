import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../services/auth_service.dart';
import 'api_client.dart';

class SalaryService {
  final AuthService _authService = AuthService();
  final ApiClient _api = ApiClient();

  Future<Map<String, dynamic>> getSalaryStats({int? month, int? year}) async {
    final token = await _authService.getToken();
    if (token == null) return _getEmptySalaryData();
    try {
      _api.setAuthToken(token);
      debugPrint(
        '[SalaryOverview] GET /payrolls/stats month=$month year=$year',
      );
      final response = await _api.dio.get<Map<String, dynamic>>(
        '/payrolls/stats',
        queryParameters: {
          if (month != null) 'month': month,
          if (year != null) 'year': year,
        },
      );
      final data = response.data;
      if (data != null && data['success'] == true) {
        final result = data['data'];
        return result is Map ? Map<String, dynamic>.from(result) : _getEmptySalaryData();
      }
      return _getEmptySalaryData();
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return _getEmptySalaryData();
      return _getEmptySalaryData();
    }
  }

  Map<String, dynamic> _getEmptySalaryData() {
    return {
      'netPay': 0,
      'grossSalary': 0,
      'deductions': 0,
      'workingDays': 0,
      'presentDays': 0,
      'lopDays': 0,
      'earnings': [],
      'deductionsList': [],
    };
  }

  /// POST `/payrolls/preview` — MTD estimate (same backend as web-style preview).
  Future<Map<String, dynamic>> previewPayroll({
    required String employeeId,
    required int month,
    required int year,
  }) async {
    final token = await _authService.getToken();
    if (token == null) {
      return {'success': false, 'error': 'No token found'};
    }
    try {
      _api.setAuthToken(token);
      debugPrint(
        '[SalaryOverview] POST /payrolls/preview month=$month year=$year employeeId=$employeeId',
      );
      final response = await _api.dio.post<Map<String, dynamic>>(
        '/payrolls/preview',
        data: {
          'employeeId': employeeId,
          'month': month,
          'year': year,
        },
      );
      final data = response.data;
      if (data != null) return Map<String, dynamic>.from(data);
      return {'success': false};
    } on DioException catch (e) {
      debugPrint('[SalaryOverview] previewPayroll DioException: ${e.message}');
      return {
        'success': false,
        'error': e.response?.data ?? e.message,
      };
    }
  }

  Future<Map<String, dynamic>> getPayrolls({
    int? page,
    int? limit,
    int? month,
    int? year,
  }) async {
    final token = await _authService.getToken();
    if (token == null) throw Exception('No token found');
    try {
      _api.setAuthToken(token);
      final q = <String, dynamic>{
        'page': page ?? 1,
        'limit': limit ?? 10,
      };
      if (month != null) q['month'] = month;
      if (year != null) q['year'] = year;
      debugPrint(
        '[SalaryOverview] GET /payrolls query=$q',
      );
      final response = await _api.dio.get<Map<String, dynamic>>(
        '/payrolls',
        queryParameters: q,
      );
      final data = response.data;
      if (data != null) return data;
      return {'success': true, 'data': []};
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return {'success': true, 'data': []};
      throw Exception('Error fetching payrolls: ${e.message}');
    }
  }

  Future<Map<String, dynamic>?> getStaffSalaryDetails() async {
    try {
      final profileResult = await _authService.getProfile();
      if (profileResult['success'] == true) {
        final staffData = profileResult['data']?['staffData'];
        if (staffData != null && staffData['salary'] != null) {
          return staffData['salary'] as Map<String, dynamic>;
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }
}
