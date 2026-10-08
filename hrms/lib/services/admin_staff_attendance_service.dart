// lib/services/admin_staff_attendance_service.dart
//
// Admin "Employee Attendance" register - mirrors the web admin Attendance page
// (HRMSfrontend features/admin/staff/Attendance) and the backend routes in
// HRMSbackend src/routes/admin/staffRoute.ts (mounted at /api/admin/staff).
//
// Every method throws on failure; use [AdminStaffAttendanceService.errorMessage]
// to turn the error into the backend's message for display.
import 'package:dio/dio.dart';

import 'api_client.dart';

class AdminStaffAttendanceService {
  static final AdminStaffAttendanceService _instance = AdminStaffAttendanceService._internal();
  factory AdminStaffAttendanceService() => _instance;
  AdminStaffAttendanceService._internal();

  final ApiClient _api = ApiClient();

  static const String _base = '/admin/staff/attendance';

  /// Backend message from a failed call, or a readable fallback.
  static String errorMessage(Object error, [String fallback = 'Something went wrong. Please try again.']) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map && data['message'] != null && data['message'].toString().trim().isNotEmpty) {
        return data['message'].toString();
      }
      if (error.type == DioExceptionType.connectionError ||
          error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.receiveTimeout) {
        return 'Unable to reach the server. Please check your connection.';
      }
      return fallback;
    }
    if (error is AdminAttendanceException) return error.message;
    return fallback;
  }

  Map<String, dynamic> _unwrap(Response res) {
    final body = res.data;
    if (body is Map) {
      if (body['success'] == false) {
        throw AdminAttendanceException((body['message'] ?? 'Request failed').toString());
      }
      return Map<String, dynamic>.from(body);
    }
    throw AdminAttendanceException('Invalid response from server');
  }

  /// GET /admin/staff/attendance/all-staff?date=YYYY-MM-DD
  /// -> { records: [...], weekOffStaffIds: [...] }
  Future<Map<String, dynamic>> getAllStaffAttendance(String date) async {
    final res = await _api.request('$_base/all-staff', queryParameters: {'date': date});
    final body = _unwrap(res);
    final data = body['data'];
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  /// POST /admin/staff/attendance/all-staff  { status: 'present', ... }
  Future<String?> markPresent({
    required String staffId,
    required String date,
    required String shiftId,
    required String checkInTime,
    String? checkOutTime,
    bool approved = true,
  }) async {
    final res = await _api.request('$_base/all-staff', method: 'POST', data: {
      'staffId': staffId,
      'date': date,
      'status': 'present',
      'shiftId': shiftId,
      'checkInTime': checkInTime,
      if (checkOutTime != null) 'checkOutTime': checkOutTime,
      'approved': approved,
    });
    return _unwrap(res)['message']?.toString();
  }

  /// POST /admin/staff/attendance/all-staff  { status: 'half_day', leaveType, ... }
  Future<String?> markHalfDay({
    required String staffId,
    required String date,
    String? shiftId,
    required String checkInTime,
    required String checkOutTime,
    required String leaveType,
    bool approved = true,
  }) async {
    final res = await _api.request('$_base/all-staff', method: 'POST', data: {
      'staffId': staffId,
      'date': date,
      'status': 'half_day',
      if (shiftId != null && shiftId.isNotEmpty) 'shiftId': shiftId,
      'checkInTime': checkInTime,
      'checkOutTime': checkOutTime,
      'approved': approved,
      'leaveType': leaveType,
    });
    return _unwrap(res)['message']?.toString();
  }

  /// POST /admin/staff/attendance/absent
  Future<String?> markAbsent({
    required String staffId,
    required String date,
    String? remarks,
    String? deductionStatus,
  }) async {
    final res = await _api.request('$_base/absent', method: 'POST', data: {
      'staffId': staffId,
      'date': date,
      if (remarks != null && remarks.isNotEmpty) 'remarks': remarks,
      if (deductionStatus != null) 'deductionStatus': deductionStatus,
    });
    return _unwrap(res)['message']?.toString();
  }

  /// POST /admin/staff/attendance/leave
  Future<String?> markLeave({
    required String staffId,
    required String date,
    required String leaveType,
    String? remarks,
  }) async {
    final res = await _api.request('$_base/leave', method: 'POST', data: {
      'staffId': staffId,
      'date': date,
      'leaveType': leaveType,
      if (remarks != null && remarks.isNotEmpty) 'remarks': remarks,
    });
    return _unwrap(res)['message']?.toString();
  }

  /// POST /admin/staff/attendance/all-staff  { status: 'week_off', leaveType: 'Week Off'|'Comp Off' }
  Future<String?> markWeekOff({
    required String staffId,
    required String date,
    required String leaveType,
    String? alternateWorkDate,
    String? policyName,
  }) async {
    final res = await _api.request('$_base/all-staff', method: 'POST', data: {
      'staffId': staffId,
      'date': date,
      'status': 'week_off',
      'leaveType': leaveType,
      if (alternateWorkDate != null && alternateWorkDate.isNotEmpty) 'alternateWorkDate': alternateWorkDate,
      if (policyName != null && policyName.isNotEmpty) 'policyName': policyName,
    });
    return _unwrap(res)['message']?.toString();
  }

  /// PUT /admin/staff/attendance/all-staff  { staffId, date, note }
  Future<String?> saveNote({
    required String staffId,
    required String date,
    required String note,
  }) async {
    final res = await _api.request('$_base/all-staff', method: 'PUT', data: {
      'staffId': staffId,
      'date': date,
      'note': note,
    });
    return _unwrap(res)['message']?.toString();
  }

  /// GET /admin/staff/attendance/fine?staffId=&date=
  Future<Map<String, dynamic>> getFineDetails({required String staffId, required String date}) async {
    final res = await _api.request('$_base/fine', queryParameters: {'staffId': staffId, 'date': date});
    final data = _unwrap(res)['data'];
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  /// PUT /admin/staff/attendance/fine  { staffId, date, lateFine, earlyExitFine }
  Future<String?> updateFine({
    required String staffId,
    required String date,
    required Map<String, dynamic> lateFine,
    required Map<String, dynamic> earlyExitFine,
  }) async {
    final res = await _api.request('$_base/fine', method: 'PUT', data: {
      'staffId': staffId,
      'date': date,
      'lateFine': lateFine,
      'earlyExitFine': earlyExitFine,
    });
    return _unwrap(res)['message']?.toString();
  }

  /// GET /admin/staff/attendance/overtime?staffId=&date=
  Future<Map<String, dynamic>> getOvertimeDetails({required String staffId, required String date}) async {
    final res = await _api.request('$_base/overtime', queryParameters: {'staffId': staffId, 'date': date});
    final data = _unwrap(res)['data'];
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  /// PUT /admin/staff/attendance/overtime
  Future<String?> updateOvertime({
    required String staffId,
    required String date,
    required String actualOvertime,
    required int hours,
    required int minutes,
    required String option,
    required double amount,
  }) async {
    final res = await _api.request('$_base/overtime', method: 'PUT', data: {
      'staffId': staffId,
      'date': date,
      'actualOvertime': actualOvertime,
      'updatedOvertime': {'hours': hours, 'minutes': minutes},
      'option': option,
      'amount': amount,
    });
    return _unwrap(res)['message']?.toString();
  }

  /// GET /admin/settings/attendance/leave-templates/staff-balances/:staffId
  /// -> list of { leaveTypeName, balance, ... }
  Future<List<Map<String, dynamic>>> getStaffLeaveBalances(String staffId) async {
    final res = await _api.request('/admin/settings/attendance/leave-templates/staff-balances/$staffId');
    final data = _unwrap(res)['data'];
    final list = data is Map ? data['balances'] : null;
    if (list is List) {
      return list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    }
    return <Map<String, dynamic>>[];
  }
}

class AdminAttendanceException implements Exception {
  final String message;
  AdminAttendanceException(this.message);

  @override
  String toString() => message;
}
