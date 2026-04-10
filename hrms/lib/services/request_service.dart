import 'dart:io';
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/error_message_utils.dart';
import 'api_client.dart';

class RequestService {
  final ApiClient _api = ApiClient();

  Future<void> _setToken() async {
    final prefs = await SharedPreferences.getInstance();
    String? token = prefs.getString('token');
    if (token != null && (token.startsWith('"') || token.endsWith('"'))) {
      token = token.replaceAll('"', '');
    }
    if (token != null && token.isNotEmpty) _api.setAuthToken(token);
  }

  // --- DASHBOARD ---

  Future<Map<String, dynamic>> getDashboardData() async {
    try {
      await _setToken();
      final response = await _api.dio.get<Map<String, dynamic>>(
        '/dashboard/employee',
      );
      final body = response.data;
      if (body != null && body['success'] == true) {
        return {'success': true, 'data': body['data']};
      }
      return {
        'success': false,
        'message': body?['message'] ?? 'Error fetching data',
      };
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return {
          'success': true,
          'data': {
            'attendance': {
              'present': 0,
              'absent': 0,
              'late': 0,
              'totalWorkingDays': 0,
            },
            'leaves': {'pending': 0, 'approved': 0, 'rejected': 0},
            'loans': {'active': 0, 'pending': 0, 'total': 0},
            'reimbursements': {'pending': 0, 'approved': 0},
            'payslips': [],
          },
        };
      }
      return {'success': false, 'message': _dioMessage(e)};
    } catch (e) {
      return {'success': false, 'message': _handleException(e)};
    }
  }

  String _dioMessage(DioException e) {
    return ErrorMessageUtils.messageFromDioException(e);
  }

  // --- ANNOUNCEMENTS ---

  /// All announcements for the logged-in employee (assigned to them or company-wide).
  Future<Map<String, dynamic>> getAnnouncementsForEmployee() async {
    try {
      await _setToken();
      final response = await _api.dio.get<Map<String, dynamic>>(
        '/announcements/for-employee',
      );
      final body = response.data;
      if (body != null && body['success'] == true) {
        return {'success': true, 'data': body['data'] ?? []};
      }
      return {
        'success': false,
        'message': body?['message'] ?? 'Error fetching announcements',
      };
    } on DioException catch (e) {
      return {'success': false, 'message': _dioMessage(e)};
    } catch (e) {
      return {'success': false, 'message': _handleException(e)};
    }
  }

  // --- LEAVE ---

  Future<Map<String, dynamic>> getLeaveTypes({
    int? month,
    int? year,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      await _setToken();
      final q = <String, dynamic>{};
      if (startDate != null && endDate != null) {
        q['startDate'] = startDate.toIso8601String();
        q['endDate'] = endDate.toIso8601String();
      } else if (month != null && year != null) {
        q['month'] = month;
        q['year'] = year;
      }
      final response = await _api.dio.get<Map<String, dynamic>>(
        '/requests/leave-types',
        queryParameters: q,
      );
      final body = response.data;
      return {'success': true, 'data': body?['data'] ?? body};
    } on DioException catch (e) {
      return {'success': false, 'message': _dioMessage(e)};
    } catch (e) {
      return {'success': false, 'message': _handleException(e)};
    }
  }

  /// Fetches leave types for Apply Leave dropdown: from staff's leave template + Half Day (static) + Unpaid Leave.
  /// Returns list of { type, days } where days is the limit (null for Unpaid Leave, 0.5 for Half Day).
  Future<Map<String, dynamic>> getLeaveTypesForApply() async {
    try {
      await _setToken();
      final response = await _api.dio.get<Map<String, dynamic>>(
        '/requests/leave-types/for-apply',
      );
      final body = response.data;
      return {'success': true, 'data': body?['data'] ?? body};
    } on DioException catch (e) {
      return {'success': false, 'message': _dioMessage(e)};
    } catch (e) {
      return {'success': false, 'message': _handleException(e)};
    }
  }

  /// Checks leave dates for conflict. Pass [startDate] and [endDate] (range), and optionally [selectedDates] for calendar selection.
  /// When [selectedDates] is provided, backend uses it for conflict check; otherwise uses range.
  /// Returns { success, hasConflict, effectiveDays }.
  Future<Map<String, dynamic>> checkLeaveDates(
    DateTime startDate,
    DateTime endDate, {
    List<DateTime>? selectedDates,
  }) async {
    try {
      await _setToken();
      final Map<String, dynamic> data;
      if (selectedDates != null && selectedDates.isNotEmpty) {
        data = {
          'selectedDates': selectedDates
              .map(
                (d) =>
                    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}',
              )
              .toList(),
        };
      } else {
        data = {
          'startDate': startDate.toIso8601String(),
          'endDate': endDate.toIso8601String(),
        };
      }
      final response = await _api.dio.post<Map<String, dynamic>>(
        '/requests/leave/check-dates',
        data: data,
      );
      final body = response.data;
      if (body == null || body['success'] != true) {
        return {'success': false, 'hasConflict': false};
      }
      final resData = body['data'] as Map<String, dynamic>?;
      List<String> list(dynamic value) => value is List
          ? List<String>.from(value.map((e) => e.toString()))
          : <String>[];
      return {
        'success': true,
        'hasConflict': resData?['hasConflict'] == true,
        'effectiveDays': (resData?['effectiveDays'] is int)
            ? resData!['effectiveDays'] as int
            : null,
        'paidLeaveDates': list(resData?['paidLeaveDates']),
        'pendingLeaveDates': list(resData?['pendingLeaveDates']),
        'approvedLeaveDates': list(resData?['approvedLeaveDates']),
        'weekOffDates': list(resData?['weekOffDates']),
        'holidayDates': list(resData?['holidayDates']),
      };
    } on DioException catch (e) {
      return {
        'success': false,
        'hasConflict': false,
        'message': _dioMessage(e),
      };
    } catch (e) {
      return {
        'success': false,
        'hasConflict': false,
        'message': _handleException(e),
      };
    }
  }

  /// Fetches leave balance: availableCasualLeaves from attendances, totalAllowed from leave template.
  Future<Map<String, dynamic>> getLeaveBalance() async {
    try {
      await _setToken();
      final response = await _api.dio.get<Map<String, dynamic>>(
        '/requests/leave-balance',
      );
      final body = response.data;
      if (body == null || body['success'] != true) {
        return {
          'success': false,
          'message':
              ErrorMessageUtils.messageFromResponseData(body) ??
              'Failed to load balance',
        };
      }
      final data = body['data'] as Map<String, dynamic>?;
      return {
        'success': true,
        'availableCasualLeaves': (data?['availableCasualLeaves'] is num)
            ? (data!['availableCasualLeaves'] as num).toDouble()
            : 0.0,
        'totalAllowed': (data?['totalAllowed'] is num)
            ? (data!['totalAllowed'] as num).toDouble()
            : 0.0,
      };
    } on DioException catch (e) {
      return {'success': false, 'message': _dioMessage(e)};
    } catch (e) {
      return {'success': false, 'message': _handleException(e)};
    }
  }

  Future<Map<String, dynamic>> applyLeave(Map<String, dynamic> data) async {
    try {
      await _setToken();
      final response = await _api.dio.post<Map<String, dynamic>>(
        '/requests/leave',
        data: data,
      );
      final body = response.data;
      if (body == null) {
        return {'success': false, 'message': 'Invalid response'};
      }
      var responseData = body;
      if (body.containsKey('data') && body['data'] is Map) {
        final d = body['data'] as Map;
        if (d.containsKey('leave')) {
          responseData = d['leave'] as Map<String, dynamic>;
        } else {
          responseData = Map<String, dynamic>.from(d);
        }
      }
      return {'success': true, 'data': responseData};
    } on DioException catch (e) {
      return {'success': false, 'message': _dioMessage(e)};
    } catch (e) {
      return {'success': false, 'message': _handleException(e)};
    }
  }

  Future<Map<String, dynamic>> getLeaveRequests({
    String? status,
    String? search,
    DateTime? startDate,
    DateTime? endDate,
    int page = 1,
    int limit = 10,
  }) async {
    try {
      await _setToken();
      final q = <String, dynamic>{
        'page': page,
        'limit': limit,
        if (status != null && status != 'All Status') 'status': status,
        if (search != null && search.isNotEmpty) 'search': search,
        if (startDate != null) 'startDate': startDate.toIso8601String(),
        if (endDate != null) 'endDate': endDate.toIso8601String(),
      };
      final response = await _api.dio.get<dynamic>(
        '/requests/leave',
        queryParameters: q,
      );
      final body = response.data;
      if (body is List) return {'success': true, 'data': body};
      if (body is Map && body['success'] == true) {
        return {'success': true, 'data': body['data'] ?? body};
      }
      return {'success': true, 'data': body};
    } on DioException catch (e) {
      return {'success': false, 'message': _dioMessage(e)};
    } catch (e) {
      return {'success': false, 'message': _handleException(e)};
    }
  }

  // --- LOAN ---

  Future<Map<String, dynamic>> applyLoan(Map<String, dynamic> data) async {
    try {
      await _setToken();
      final response = await _api.dio.post<Map<String, dynamic>>(
        '/requests/loan',
        data: data,
      );
      final body = response.data;
      final responseData = body != null && body.containsKey('data')
          ? body['data']!
          : body;
      return {'success': true, 'data': responseData};
    } on DioException catch (e) {
      return {'success': false, 'message': _dioMessage(e)};
    } catch (e) {
      return {'success': false, 'message': _handleException(e)};
    }
  }

  Future<Map<String, dynamic>> getLoanRequests({
    String? status,
    String? search,
    DateTime? startDate,
    DateTime? endDate,
    int page = 1,
    int limit = 10,
  }) async {
    try {
      await _setToken();
      final q = <String, dynamic>{
        'page': page,
        'limit': limit,
        if (status != null && status != 'All Status') 'status': status,
        if (search != null && search.isNotEmpty) 'search': search,
        if (startDate != null) 'startDate': startDate.toIso8601String(),
        if (endDate != null) 'endDate': endDate.toIso8601String(),
      };
      final response = await _api.dio.get<Map<String, dynamic>>(
        '/requests/loan',
        queryParameters: q,
      );
      final body = response.data;
      if (body != null && body['success'] == true) {
        return {'success': true, 'data': body['data'] ?? body};
      }
      return {'success': true, 'data': body};
    } on DioException catch (e) {
      return {'success': false, 'message': _dioMessage(e)};
    } catch (e) {
      return {'success': false, 'message': _handleException(e)};
    }
  }

  // --- EXPENSE ---

  Future<Map<String, dynamic>> applyExpense(Map<String, dynamic> data) async {
    try {
      await _setToken();
      final response = await _api.dio.post<Map<String, dynamic>>(
        '/requests/expense',
        data: data,
      );
      final body = response.data;
      if (body == null) {
        return {'success': false, 'message': 'Invalid response'};
      }
      var responseData = body;
      if (body.containsKey('data') && body['data'] is Map) {
        final d = body['data'] as Map;
        responseData = d['reimbursement'] ?? d;
      }
      return {'success': true, 'data': responseData};
    } on DioException catch (e) {
      return {'success': false, 'message': _dioMessage(e)};
    } catch (e) {
      return {'success': false, 'message': _handleException(e)};
    }
  }

  Future<Map<String, dynamic>> getExpenseRequests({
    String? status,
    String? search,
    DateTime? startDate,
    DateTime? endDate,
    int page = 1,
    int limit = 10,
  }) async {
    try {
      await _setToken();
      final q = <String, dynamic>{
        'page': page,
        'limit': limit,
        if (status != null && status != 'All Status') 'status': status,
        if (search != null && search.isNotEmpty) 'search': search,
        if (startDate != null) 'startDate': startDate.toIso8601String(),
        if (endDate != null) 'endDate': endDate.toIso8601String(),
      };
      final response = await _api.dio.get<Map<String, dynamic>>(
        '/requests/expense',
        queryParameters: q,
      );
      final body = response.data;
      if (body != null && body['success'] == true) {
        return {'success': true, 'data': body['data'] ?? body};
      }
      return {'success': true, 'data': body};
    } on DioException catch (e) {
      return {'success': false, 'message': _dioMessage(e)};
    } catch (e) {
      return {'success': false, 'message': _handleException(e)};
    }
  }

  // --- PAYSLIP ---

  Future<Map<String, dynamic>> requestPayslip(Map<String, dynamic> data) async {
    try {
      await _setToken();
      final response = await _api.dio.post<Map<String, dynamic>>(
        '/requests/payslip',
        data: data,
      );
      final body = response.data;
      if (body != null &&
          (body['success'] == true || response.statusCode == 201)) {
        return {
          'success': true,
          'data': body['data'],
          'message': body['message'],
        };
      }
      return {'success': true, 'data': body};
    } on DioException catch (e) {
      return {'success': false, 'message': _dioMessage(e)};
    } catch (e) {
      return {'success': false, 'message': _handleException(e)};
    }
  }

  Future<Map<String, dynamic>> getPayslipRequests({
    String? status,
    String? search,
    DateTime? startDate,
    DateTime? endDate,
    int page = 1,
    int limit = 10,
  }) async {
    try {
      await _setToken();
      final q = <String, dynamic>{
        'page': page,
        'limit': limit,
        if (status != null && status != 'All Status') 'status': status,
        if (search != null && search.isNotEmpty) 'search': search,
        if (startDate != null) 'startDate': startDate.toIso8601String(),
        if (endDate != null) 'endDate': endDate.toIso8601String(),
      };
      final response = await _api.dio.get<Map<String, dynamic>>(
        '/requests/payslip',
        queryParameters: q,
      );
      final body = response.data;
      if (body != null && body['success'] == true) {
        return {'success': true, 'data': body['data'] ?? body};
      }
      return {'success': true, 'data': body};
    } on DioException catch (e) {
      return {'success': false, 'message': _dioMessage(e)};
    } catch (e) {
      return {'success': false, 'message': _handleException(e)};
    }
  }

  Future<Map<String, dynamic>> viewPayslipRequest(String requestId) async {
    try {
      await _setToken();
      final response = await _api.dio.get<Map<String, dynamic>>(
        '/requests/payslip/$requestId/view',
      );
      final body = response.data;
      if (body != null &&
          body['success'] == true &&
          body['payslipUrl'] != null) {
        return {'success': true, 'payslipUrl': body['payslipUrl']};
      }
      return {
        'success': false,
        'message': body != null && body['error'] is Map
            ? (body['error']['message'] ?? 'Payslip not available yet')
            : 'Failed to view payslip',
      };
    } on DioException catch (e) {
      final msg = e.response?.data is Map
          ? (e.response?.data as Map)['error'] is Map
                ? ((e.response?.data as Map)['error'] as Map)['message']
                      ?.toString()
                : null
          : null;
      return {'success': false, 'message': msg ?? _dioMessage(e)};
    } catch (e) {
      return {'success': false, 'message': _handleException(e)};
    }
  }

  Future<Map<String, dynamic>> downloadPayslipRequest(String requestId) async {
    try {
      await _setToken();
      final response = await _api.dio.get<Map<String, dynamic>>(
        '/requests/payslip/$requestId/download',
      );
      final body = response.data;
      if (body != null &&
          body['success'] == true &&
          body['payslipUrl'] != null) {
        return {'success': true, 'payslipUrl': body['payslipUrl']};
      }
      return {
        'success': false,
        'message': body != null && body['error'] is Map
            ? (body['error']['message'] ?? 'Payslip not available yet')
            : 'Failed to download payslip',
      };
    } on DioException catch (e) {
      final msg = e.response?.data is Map
          ? (e.response?.data as Map)['error'] is Map
                ? ((e.response?.data as Map)['error'] as Map)['message']
                      ?.toString()
                : null
          : null;
      return {'success': false, 'message': msg ?? _dioMessage(e)};
    } catch (e) {
      return {'success': false, 'message': _handleException(e)};
    }
  }

  // --- PERMISSION ---

  Future<Map<String, dynamic>> getPermissionRequests({
    String? status,
    int? month,
    int? year,
  }) async {
    try {
      await _setToken();
      final now = DateTime.now();
      final q = <String, dynamic>{
        'month': month ?? now.month,
        'year': year ?? now.year,
        if (status != null && status != 'All Status') 'status': status,
      };
      final response = await _api.dio.get<Map<String, dynamic>>(
        '/requests/permission',
        queryParameters: q,
      );
      final body = response.data;
      if (body != null && body['success'] == true) {
        return {'success': true, 'data': body['data'] ?? body};
      }
      return {'success': true, 'data': body};
    } on DioException catch (e) {
      return {'success': false, 'message': _dioMessage(e)};
    } catch (e) {
      return {'success': false, 'message': _handleException(e)};
    }
  }

  Future<Map<String, dynamic>> createPermissionRequest({
    required DateTime date,
    required String type,
    required int requestedMinutes,
    required String reason,
  }) async {
    try {
      await _setToken();
      final response = await _api.dio.post<Map<String, dynamic>>(
        '/requests/permission',
        data: {
          'date': DateTime(date.year, date.month, date.day).toIso8601String(),
          'type': type,
          'requestedMinutes': requestedMinutes,
          'reason': reason,
        },
      );
      final body = response.data;
      if (body != null && body['success'] == true) {
        return {'success': true, 'data': body['data'] ?? body};
      }
      return {
        'success': false,
        'message': 'Failed to submit permission request',
      };
    } on DioException catch (e) {
      return {'success': false, 'message': _dioMessage(e)};
    } catch (e) {
      return {'success': false, 'message': _handleException(e)};
    }
  }

  Future<Map<String, dynamic>> cancelPermissionRequest(String requestId) async {
    try {
      await _setToken();
      final response = await _api.dio.patch<Map<String, dynamic>>(
        '/requests/permission/$requestId/cancel',
      );
      final body = response.data;
      if (body != null && body['success'] == true) {
        return {'success': true, 'data': body['data'] ?? body};
      }
      return {
        'success': false,
        'message': 'Failed to cancel permission request',
      };
    } on DioException catch (e) {
      return {'success': false, 'message': _dioMessage(e)};
    } catch (e) {
      return {'success': false, 'message': _handleException(e)};
    }
  }

  Future<Map<String, dynamic>> getPermissionBalance({
    int? month,
    int? year,
  }) async {
    try {
      await _setToken();
      final now = DateTime.now();
      final response = await _api.dio.get<Map<String, dynamic>>(
        '/requests/permission/balance',
        queryParameters: {
          'month': month ?? now.month,
          'year': year ?? now.year,
        },
      );
      final body = response.data;
      if (body != null && body['success'] == true) {
        return {'success': true, 'data': body['data'] ?? body};
      }
      return {'success': false, 'message': 'Failed to load permission balance'};
    } on DioException catch (e) {
      return {'success': false, 'message': _dioMessage(e)};
    } catch (e) {
      return {'success': false, 'message': _handleException(e)};
    }
  }

  /// Fetches PDF bytes from a full URL (e.g. Cloudinary payslipUrl). No auth.
  Future<Map<String, dynamic>> getPdfBytesFromUrl(String url) async {
    try {
      final uri = Uri.tryParse(url);
      if (uri == null || !uri.hasScheme) {
        return {'success': false, 'message': 'Invalid file URL'};
      }

      // Use a dedicated Dio (no baseUrl / auth interceptors) for absolute URLs.
      final dio = Dio(
        BaseOptions(
          responseType: ResponseType.bytes,
          followRedirects: true,
          receiveTimeout: const Duration(seconds: 30),
          sendTimeout: const Duration(seconds: 30),
          connectTimeout: const Duration(seconds: 30),
          validateStatus: (status) =>
              status != null && status >= 200 && status < 400,
          headers: {'Accept': '*/*'},
        ),
      );

      final response = await dio.get<List<int>>(url);
      final bytes = response.data;
      if (bytes != null && bytes.isNotEmpty) {
        return {'success': true, 'data': bytes};
      }
      return {'success': false, 'message': 'No data received'};
    } on DioException catch (e) {
      return {'success': false, 'message': _dioMessage(e)};
    } catch (e) {
      return {'success': false, 'message': _handleException(e)};
    }
  }

  String _handleException(dynamic error) {
    if (error is SocketException) {
      // SocketException can occur even with internet if server is unreachable
      String errorMsg = error.message.toLowerCase();
      if (errorMsg.contains('failed host lookup') ||
          errorMsg.contains('name resolution') ||
          errorMsg.contains('nodename nor servname provided')) {
        return 'Unable to reach server. Please check your internet connection or contact support if the problem persists.';
      } else if (errorMsg.contains('connection refused') ||
          errorMsg.contains('connection reset')) {
        return 'Server is not responding. Please try again in a moment or contact support.';
      } else {
        return 'Connection error. Please check your internet connection and try again.';
      }
    } else if (error is TimeoutException) {
      return 'Connection timed out. Please try again.';
    } else if (error is FormatException) {
      return 'Invalid response format from server.';
    }

    String msg = error.toString();
    if (msg.startsWith('Exception: ')) {
      msg = msg.substring(11);
    }
    return msg;
  }
}
