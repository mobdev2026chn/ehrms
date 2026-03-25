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
        '[SalaryOverview] GET /payroll/stats month=$month year=$year',
      );
      final response = await _api.dio.get<Map<String, dynamic>>(
        '/payroll/stats',
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
        '[SalaryOverview] GET /payroll query=$q',
      );
      final response = await _api.dio.get<Map<String, dynamic>>(
        '/payroll',
        queryParameters: q,
      );
      final data = response.data;
      if (data != null) return data;
      return {
        'success': true,
        'data': {
          'payrolls': <dynamic>[],
          'pagination': {
            'page': page ?? 1,
            'limit': limit ?? 10,
            'total': 0,
            'pages': 0,
          },
        },
      };
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return {
          'success': true,
          'data': {
            'payrolls': <dynamic>[],
            'pagination': {
              'page': page ?? 1,
              'limit': limit ?? 10,
              'total': 0,
              'pages': 0,
            },
          },
        };
      }
      throw Exception('Error fetching payrolls: ${e.message}');
    }
  }

  /// Web RTK `viewPayslip` / `downloadPayslip` — GET PDF bytes by payroll id.
  /// Returns null if the route is missing (404) or the body is not usable; callers fall back to [payslipUrl].
  Future<List<int>?> getPayslipPdfBytes(
    String payrollId, {
    required bool download,
  }) async {
    final token = await _authService.getToken();
    if (token == null) return null;
    try {
      _api.setAuthToken(token);
      final path = download
          ? '/payroll/$payrollId/payslip/download'
          : '/payroll/$payrollId/payslip/view';
      debugPrint('[SalaryOverview] GET $path');
      final response = await _api.dio.get<dynamic>(
        path,
        options: Options(responseType: ResponseType.bytes),
      );
      final data = response.data;
      if (data is List<int>) return List<int>.from(data);
      return null;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      debugPrint('[SalaryOverview] getPayslipPdfBytes: ${e.message}');
      return null;
    }
  }

  /// Web RTK `previewPayroll` / EmployeeSalaryOverview: tier 2 MTD (after processed payroll).
  /// Only valid when there is no payroll row for that month; uses
  /// (presentDays + paidLeaveDays) / fullMonthWorkingDays — see app_backend `previewPayrollEmployee`.
  Future<Map<String, dynamic>> previewPayroll({
    required String employeeId,
    required int month,
    required int year,
  }) async {
    final token = await _authService.getToken();
    if (token == null) {
      return {'success': false, 'data': null};
    }
    try {
      _api.setAuthToken(token);
      debugPrint(
        '[SalaryOverview] POST /payroll/preview month=$month year=$year employeeId=$employeeId',
      );
      final response = await _api.dio.post<Map<String, dynamic>>(
        '/payroll/preview',
        data: {
          'employeeId': employeeId,
          'month': month,
          'year': year,
        },
      );
      final data = response.data;
      if (data != null) return Map<String, dynamic>.from(data);
      return {'success': false, 'data': null};
    } on DioException catch (e) {
      debugPrint('[SalaryOverview] previewPayroll error: ${e.message}');
      return {'success': false, 'data': null};
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
