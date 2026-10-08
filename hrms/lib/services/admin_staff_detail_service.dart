// lib/services/admin_staff_detail_service.dart
//
// API calls behind the admin Staff Detail screen (profile, attendance, salary,
// approvals, shifts and documents of one staff member). Every method returns
// the backend's JSON body on success and throws [StaffDetailApiException]
// carrying the backend's message on failure, so screens only update state
// after a call actually succeeded.
import 'package:dio/dio.dart';

import '../utils/error_message_utils.dart';
import 'api_client.dart';

class StaffDetailApiException implements Exception {
  StaffDetailApiException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

/// The four approval queues that can be filtered by staff member.
enum StaffRequestKind { leave, permission, expense, payslip }

extension StaffRequestKindPath on StaffRequestKind {
  String get path {
    switch (this) {
      case StaffRequestKind.leave:
        return 'leave';
      case StaffRequestKind.permission:
        return 'permission';
      case StaffRequestKind.expense:
        return 'expense';
      case StaffRequestKind.payslip:
        return 'payslip';
    }
  }
}

class AdminStaffDetailService {
  static final AdminStaffDetailService _instance = AdminStaffDetailService._internal();
  factory AdminStaffDetailService() => _instance;
  AdminStaffDetailService._internal();

  final ApiClient _api = ApiClient();

  Future<Map<String, dynamic>> _call(
    String path, {
    String method = 'GET',
    dynamic data,
    Map<String, dynamic>? query,
    String fallback = 'Request failed. Please try again.',
  }) async {
    try {
      final res = await _api.request(path, method: method, data: data, queryParameters: query);
      final body = res.data;
      if (body is Map) {
        final map = Map<String, dynamic>.from(body);
        if (map['success'] == false) {
          throw StaffDetailApiException(map['message']?.toString() ?? fallback, statusCode: res.statusCode);
        }
        return map;
      }
      return {'success': true, 'data': body};
    } on DioException catch (e) {
      final msg = ErrorMessageUtils.messageFromResponseData(e.response?.data) ??
          ErrorMessageUtils.messageFromDioException(e, fallback: fallback);
      throw StaffDetailApiException(msg, statusCode: e.response?.statusCode);
    }
  }

  static Map<String, dynamic> _dataMap(Map<String, dynamic> body) {
    final d = body['data'];
    return d is Map ? Map<String, dynamic>.from(d) : <String, dynamic>{};
  }

  static List<Map<String, dynamic>> _list(dynamic raw) {
    if (raw is! List) return [];
    return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  // ───────────────────────── Staff record ─────────────────────────

  /// GET /admin/staff → data.staff (scope-filtered; the backend takes no search / paging params).
  Future<List<Map<String, dynamic>>> getStaffList() async {
    final body = await _call('/admin/staff', fallback: 'Failed to load staff list');
    return _list(_dataMap(body)['staff']);
  }

  /// GET /admin/staff/:id → data.staff
  Future<Map<String, dynamic>> getStaff(String staffId) async {
    final body = await _call('/admin/staff/$staffId', fallback: 'Could not load staff details.');
    final staff = _dataMap(body)['staff'];
    if (staff is! Map) throw StaffDetailApiException('Staff member not found');
    return Map<String, dynamic>.from(staff);
  }

  /// PUT /admin/staff/:id → data.staff (only the fields present are written).
  Future<Map<String, dynamic>> updateStaff(String staffId, Map<String, dynamic> payload) async {
    final body = await _call('/admin/staff/$staffId',
        method: 'PUT', data: payload, fallback: 'Could not save profile changes.');
    final staff = _dataMap(body)['staff'];
    return staff is Map ? Map<String, dynamic>.from(staff) : <String, dynamic>{};
  }

  /// PUT /admin/staff/:id/activate | deactivate → data.staff
  Future<Map<String, dynamic>> setActive(String staffId, bool active) async {
    final body = await _call('/admin/staff/$staffId/${active ? 'activate' : 'deactivate'}',
        method: 'PUT', fallback: 'Failed to change status.');
    final staff = _dataMap(body)['staff'];
    return staff is Map ? Map<String, dynamic>.from(staff) : <String, dynamic>{};
  }

  /// GET /admin/staff/subscription → data (active SubscriptionHistory or null).
  Future<Map<String, dynamic>?> getSubscription() async {
    final body = await _call('/admin/staff/subscription', fallback: 'Could not read subscription.');
    final d = body['data'];
    return d is Map ? Map<String, dynamic>.from(d) : null;
  }

  /// GET /admin/staff/setup → template lists for the profile pickers.
  Future<Map<String, dynamic>> getSetup() async {
    final body = await _call('/admin/staff/setup', fallback: 'Could not load templates.');
    return _dataMap(body);
  }

  /// GET /admin/settings/attendance/branches → data: [ {_id, branchName} ]
  Future<List<Map<String, dynamic>>> getBranches() async {
    final body = await _call('/admin/settings/attendance/branches', fallback: 'Could not load branches.');
    return _list(body['data']);
  }

  /// GET /admin/staff/reporting-managers?designation&excludeId → data.{options, reportsTo, defaultOption}
  Future<Map<String, dynamic>> getReportingManagers({required String designation, String? excludeId}) async {
    final body = await _call('/admin/staff/reporting-managers',
        query: {
          'designation': designation,
          if (excludeId != null && excludeId.isNotEmpty) 'excludeId': excludeId,
        },
        fallback: 'Could not load reporting managers.');
    return _dataMap(body);
  }

  // ───────────────────────── Shift roster ─────────────────────────

  /// GET /admin/settings/shift-roster/active/:staffId → data.{source, assignment}
  Future<Map<String, dynamic>> getActiveShift(String staffId) async {
    final body = await _call('/admin/settings/shift-roster/active/$staffId', fallback: 'Could not load active shift.');
    return _dataMap(body);
  }

  /// GET /admin/settings/shift-roster/schedule/:staffId?year&month → data.{days, todayShift}
  Future<Map<String, dynamic>> getSchedule(String staffId, int year, int month) async {
    final body = await _call('/admin/settings/shift-roster/schedule/$staffId',
        query: {'year': year, 'month': month}, fallback: 'Could not load shift schedule.');
    return _dataMap(body);
  }

  /// POST /admin/settings/shift-roster/override
  Future<Map<String, dynamic>> saveShiftOverride({
    required String staffId,
    required String date,
    required String overrideType,
    String? shiftTemplateId,
    required String reason,
  }) {
    return _call('/admin/settings/shift-roster/override',
        method: 'POST',
        data: {
          'staffId': staffId,
          'date': date,
          'overrideType': overrideType,
          if (shiftTemplateId != null) 'shiftTemplateId': shiftTemplateId,
          'reason': reason,
        },
        fallback: 'Failed to save override.');
  }

  /// GET /admin/settings/attendance/shifts → data.templates
  Future<List<Map<String, dynamic>>> getShiftTemplates() async {
    final body = await _call('/admin/settings/attendance/shifts', fallback: 'Could not load shift templates.');
    return _list(_dataMap(body)['templates']);
  }

  // ───────────────────────── Attendance ─────────────────────────

  /// GET /admin/staff/attendance/staff/:staffId?year&month
  Future<Map<String, dynamic>> getMonthlyAttendance(String staffId, int year, int month) async {
    final body = await _call('/admin/staff/attendance/staff/$staffId',
        query: {'year': year, 'month': month}, fallback: 'Could not load attendance.');
    return _dataMap(body);
  }

  /// POST /admin/staff/attendance/present
  Future<Map<String, dynamic>> markPresent({
    required String staffId,
    required String date,
    required String shiftId,
    required String checkInTime,
    String? checkOutTime,
  }) {
    return _call('/admin/staff/attendance/present',
        method: 'POST',
        data: {
          'staffId': staffId,
          'date': date,
          'shiftId': shiftId,
          'checkInTime': checkInTime,
          if (checkOutTime != null) 'checkOutTime': checkOutTime,
          'approved': true,
        },
        fallback: 'Failed to mark present.');
  }

  /// POST /admin/staff/attendance/half-day
  Future<Map<String, dynamic>> markHalfDay({
    required String staffId,
    required String date,
    String? shiftId,
    required String checkInTime,
    required String checkOutTime,
    required String leaveType,
    String? remarks,
  }) {
    return _call('/admin/staff/attendance/half-day',
        method: 'POST',
        data: {
          'staffId': staffId,
          'date': date,
          if (shiftId != null && shiftId.isNotEmpty) 'shiftId': shiftId,
          'checkInTime': checkInTime,
          'checkOutTime': checkOutTime,
          'leaveType': leaveType,
          'approved': true,
          if (remarks != null && remarks.isNotEmpty) 'remarks': remarks,
        },
        fallback: 'Failed to mark half day.');
  }

  /// POST /admin/staff/attendance/absent
  Future<Map<String, dynamic>> markAbsent({required String staffId, required String date, String? remarks}) {
    return _call('/admin/staff/attendance/absent',
        method: 'POST',
        data: {
          'staffId': staffId,
          'date': date,
          'remarks': (remarks == null || remarks.isEmpty) ? 'Marked absent by admin.' : remarks,
          'deductionStatus': 'Deducted',
        },
        fallback: 'Failed to mark absent.');
  }

  /// POST /admin/staff/attendance/leave
  Future<Map<String, dynamic>> markLeave({
    required String staffId,
    required String date,
    required String leaveType,
    String? remarks,
  }) {
    return _call('/admin/staff/attendance/leave',
        method: 'POST',
        data: {
          'staffId': staffId,
          'date': date,
          'leaveType': leaveType,
          if (remarks != null && remarks.isNotEmpty) 'remarks': remarks,
        },
        fallback: 'Failed to mark leave.');
  }

  /// PUT /admin/staff/attendance/all-staff { staffId, date, note }
  Future<Map<String, dynamic>> saveAttendanceNote({required String staffId, required String date, required String note}) {
    return _call('/admin/staff/attendance/all-staff',
        method: 'PUT', data: {'staffId': staffId, 'date': date, 'note': note}, fallback: 'Failed to save note.');
  }

  /// POST /admin/staff/attendance/week-off/convert
  Future<Map<String, dynamic>> convertWeekOff({
    required String staffId,
    required String date,
    required String leaveType,
    String? alternateWorkDate,
    String? policyName,
  }) {
    return _call('/admin/staff/attendance/week-off/convert',
        method: 'POST',
        data: {
          'staffId': staffId,
          'date': date,
          'leaveType': leaveType,
          if (alternateWorkDate != null) 'alternateWorkDate': alternateWorkDate,
          if (policyName != null) 'policyName': policyName,
        },
        fallback: 'Failed to update week off.');
  }

  /// GET /admin/settings/attendance/leave-templates/staff-balances/:staffId → data.balances
  Future<List<Map<String, dynamic>>> getLeaveBalances(String staffId) async {
    final body = await _call('/admin/settings/attendance/leave-templates/staff-balances/$staffId',
        fallback: 'Could not load leave balances.');
    return _list(_dataMap(body)['balances']);
  }

  // ───────────────────────── Salary ─────────────────────────

  /// GET /admin/staff/overview/detail/:staffId?month=October 2026
  Future<Map<String, dynamic>> getSalaryOverview(String staffId, String month) async {
    final body = await _call('/admin/staff/overview/detail/$staffId',
        query: {'month': month}, fallback: 'Could not load salary overview.');
    return _dataMap(body);
  }

  /// PUT /admin/staff/overview/detail/:staffId?month
  Future<Map<String, dynamic>> updateSalaryOverview(String staffId, String month, Map<String, dynamic> payload) async {
    final body = await _call('/admin/staff/overview/detail/$staffId',
        method: 'PUT', query: {'month': month}, data: payload, fallback: 'Failed to save salary overview.');
    return _dataMap(body);
  }

  /// POST /admin/staff/payroll/generate { staffId, month }
  Future<Map<String, dynamic>> generatePayroll(String staffId, String month) {
    return _call('/admin/staff/payroll/generate',
        method: 'POST', data: {'staffId': staffId, 'month': month}, fallback: 'Failed to generate payroll.');
  }

  /// GET /admin/staff/salary-structures/staff/:staffId → data.{structure, history}
  Future<Map<String, dynamic>> getSalaryStructure(String staffId) async {
    final body = await _call('/admin/staff/salary-structures/staff/$staffId',
        fallback: 'Could not load salary structure.');
    return _dataMap(body);
  }

  /// POST /admin/staff/salary-structures
  Future<Map<String, dynamic>> saveSalaryStructure(Map<String, dynamic> payload) {
    return _call('/admin/staff/salary-structures',
        method: 'POST', data: payload, fallback: 'Failed to save salary structure.');
  }

  /// GET /admin/staff/salary-templates → data.templates
  Future<List<Map<String, dynamic>>> getSalaryTemplates() async {
    final body = await _call('/admin/staff/salary-templates', fallback: 'Could not load salary templates.');
    return _list(_dataMap(body)['templates']);
  }

  // ───────────────────────── Approvals (per staff) ─────────────────────────

  /// GET /admin/approvals/{kind}?staffId&status → data.{requests, summary}
  Future<List<Map<String, dynamic>>> getRequests(StaffRequestKind kind, String staffId, {String? status}) async {
    final body = await _call('/admin/approvals/${kind.path}',
        query: {
          'staffId': staffId,
          if (status != null && status != 'All') 'status': status,
        },
        fallback: 'Could not load requests.');
    return _list(_dataMap(body)['requests']);
  }

  /// POST /admin/approvals/{kind}/:id/approve
  Future<Map<String, dynamic>> approveRequest(StaffRequestKind kind, String id, Map<String, dynamic> payload) {
    return _call('/admin/approvals/${kind.path}/$id/approve',
        method: 'POST', data: payload, fallback: 'Failed to approve request.');
  }

  /// POST /admin/approvals/{kind}/:id/reject
  Future<Map<String, dynamic>> rejectRequest(StaffRequestKind kind, String id, String reason) {
    final payload = <String, dynamic>{'reason': reason, 'remarks': reason};
    if (kind == StaffRequestKind.leave || kind == StaffRequestKind.permission) {
      payload['rejectionReason'] = reason;
    }
    return _call('/admin/approvals/${kind.path}/$id/reject',
        method: 'POST', data: payload, fallback: 'Failed to reject request.');
  }

  /// POST /admin/approvals/leave/:id/cancel { reason }
  Future<Map<String, dynamic>> cancelLeave(String id, String reason) {
    return _call('/admin/approvals/leave/$id/cancel',
        method: 'POST', data: {'reason': reason}, fallback: 'Failed to cancel leave.');
  }

  // ───────────────────────── Documents ─────────────────────────

  /// GET /admin/staff/:staffId/documents → data.documents
  Future<List<Map<String, dynamic>>> getDocuments(String staffId) async {
    final body = await _call('/admin/staff/$staffId/documents', fallback: 'Could not load documents.');
    return _list(_dataMap(body)['documents']);
  }

  /// POST /admin/staff/:staffId/documents { name, category, type, size, proofFile(base64 data URL) }
  Future<Map<String, dynamic>> addDocument({
    required String staffId,
    required String name,
    required String category,
    required String type,
    required String size,
    required String proofFile,
  }) {
    return _call('/admin/staff/$staffId/documents',
        method: 'POST',
        data: {'name': name, 'category': category, 'type': type, 'size': size, 'proofFile': proofFile},
        fallback: 'Failed to upload document.');
  }

  /// DELETE /admin/staff/:staffId/documents/:documentId
  Future<Map<String, dynamic>> deleteDocument(String staffId, String documentId) {
    return _call('/admin/staff/$staffId/documents/$documentId',
        method: 'DELETE', fallback: 'Failed to delete document.');
  }
}
