// lib/services/admin_approvals_service.dart
//
// Admin approvals API. Every path here is mounted by the HRMS backend at
// `/api/admin/approvals` (routes/admin/approvalsRoute.ts), the same paths the web admin uses.
//
//   leave       GET  /admin/approvals/leave             -> data: { requests, summary }
//               GET  /admin/approvals/leave/:id         -> data: { request }
//               POST /admin/approvals/leave/:id/approve { remarks }
//               POST /admin/approvals/leave/:id/reject  { reason, rejectionReason, remarks }
//               POST /admin/approvals/leave/:id/cancel  { reason }   (Approved leave only)
//   permission  GET  /admin/approvals/permission        -> data: { requests, summary }
//               GET  /admin/approvals/permission/:id    -> data: { request }
//               POST /admin/approvals/permission/:id/approve { remarks }
//               POST /admin/approvals/permission/:id/reject  { reason, remarks }
//   punch       GET  /admin/approvals/punch?date=        -> data: [records]
//               POST /admin/approvals/punch/approve      { ids: [] }
//               POST /admin/approvals/punch/reject       { ids: [] }
//   fine        GET  /admin/approvals/fine?date=         -> data: [records]
//               POST /admin/approvals/fine/approve       { ids: [] }
//               POST /admin/approvals/fine/reject        { ids: [] }
//   expense     GET  /admin/approvals/expense            -> data: { requests, summary }
//               GET  /admin/approvals/expense/:id        -> data: { request }
//               POST /admin/approvals/expense/:id/approve
//                    { paymentRoute, payrollMonth, upiId, accountNo, ifscCode, proofImg, remarks }
//               POST /admin/approvals/expense/:id/reject { reason, remarks }
//   payslip     GET  /admin/approvals/payslip            -> data: { requests, summary }
//               POST /admin/approvals/payslip/:id/approve { remarks }
//               POST /admin/approvals/payslip/:id/reject  { reason, remarks }
//
// Every method throws [AdminApprovalsException] carrying the backend's `message` on failure,
// so screens can show it and only change local state after a successful call.
import 'package:dio/dio.dart';

import '../utils/error_message_utils.dart';
import 'api_client.dart';

class AdminApprovalsException implements Exception {
  final String message;
  AdminApprovalsException(this.message);

  @override
  String toString() => message;
}

class AdminApprovalsService {
  static final AdminApprovalsService _instance = AdminApprovalsService._internal();
  factory AdminApprovalsService() => _instance;
  AdminApprovalsService._internal();

  final ApiClient _api = ApiClient();

  static const String _base = '/admin/approvals';

  /// Types served by the hub: 'leave', 'permission', 'punch', 'fine', 'expense', 'payslip'.
  static const List<String> batchTypes = ['punch', 'fine'];

  /// The user-facing message for any error thrown by this service (or by Dio directly).
  static String messageOf(Object error, {String fallback = 'Something went wrong. Please try again.'}) {
    if (error is AdminApprovalsException) return error.message;
    if (error is DioException) {
      return ErrorMessageUtils.messageFromDioException(error, fallback: fallback);
    }
    return fallback;
  }

  // ── Core ──────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _call(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? query,
    dynamic data,
    String fallback = 'Request failed',
  }) async {
    try {
      final cleanQuery = <String, dynamic>{};
      query?.forEach((k, v) {
        if (v == null) return;
        if (v is String && v.trim().isEmpty) return;
        cleanQuery[k] = v;
      });
      final res = await _api.request(
        path,
        method: method,
        queryParameters: cleanQuery.isEmpty ? null : cleanQuery,
        data: data,
      );
      final body = res.data;
      if (body is Map) {
        final map = Map<String, dynamic>.from(body);
        if (map['success'] == false) {
          throw AdminApprovalsException(
            ErrorMessageUtils.messageFromResponseData(map) ?? fallback,
          );
        }
        return map;
      }
      throw AdminApprovalsException(fallback);
    } on DioException catch (e) {
      throw AdminApprovalsException(ErrorMessageUtils.messageFromDioException(e, fallback: fallback));
    }
  }

  List<Map<String, dynamic>> _asMapList(dynamic raw) {
    if (raw is! List) return [];
    return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  /// `data: { requests, summary }` lists (leave, permission, expense, payslip).
  Future<ApprovalsPage> _getPaged(String type, Map<String, dynamic> query) async {
    final body = await _call('$_base/$type', query: query, fallback: 'Failed to load $type requests');
    final data = body['data'];
    if (data is Map) {
      final summary = data['summary'] is Map ? Map<String, dynamic>.from(data['summary'] as Map) : <String, dynamic>{};
      return ApprovalsPage(_asMapList(data['requests']), summary);
    }
    return ApprovalsPage(_asMapList(data), const {});
  }

  /// `data: { request }` detail lookups (leave, permission, expense).
  Future<Map<String, dynamic>> _getDetail(String type, String id) async {
    final body = await _call('$_base/$type/$id', fallback: 'Failed to load request details');
    final data = body['data'];
    if (data is Map && data['request'] is Map) {
      return Map<String, dynamic>.from(data['request'] as Map);
    }
    throw AdminApprovalsException('Request details not found');
  }

  String _messageOf(Map<String, dynamic> body, String fallback) {
    final m = body['message'];
    return (m is String && m.trim().isNotEmpty) ? m : fallback;
  }

  // ── Leave ─────────────────────────────────────────────────────────────────

  Future<ApprovalsPage> getLeaveRequests({
    String? status,
    String? search,
    String? leaveType,
    String? startDate,
    String? endDate,
    String? tab,
    String? sort,
    String? staffId,
  }) {
    return _getPaged('leave', {
      'status': status,
      'search': search,
      'leaveType': leaveType,
      'startDate': startDate,
      'endDate': endDate,
      'tab': tab,
      'sort': sort,
      'staffId': staffId,
    });
  }

  Future<Map<String, dynamic>> getLeaveDetail(String id) => _getDetail('leave', id);

  Future<String> approveLeave(String id, {String? remarks}) async {
    final body = await _call('$_base/leave/$id/approve',
        method: 'POST', data: {'remarks': remarks}, fallback: 'Failed to approve leave');
    return _messageOf(body, 'Leave request approved');
  }

  Future<String> rejectLeave(String id, {required String reason, String? remarks}) async {
    final body = await _call('$_base/leave/$id/reject',
        method: 'POST',
        data: {'reason': reason, 'rejectionReason': reason, 'remarks': remarks},
        fallback: 'Failed to reject leave');
    return _messageOf(body, 'Leave request rejected');
  }

  /// Withdraws an APPROVED leave: days return to the balance and attendance is cleared.
  Future<String> cancelLeave(String id, {String? reason}) async {
    final body = await _call('$_base/leave/$id/cancel',
        method: 'POST', data: {'reason': reason}, fallback: 'Failed to cancel leave');
    return _messageOf(body, 'Approved leave cancelled');
  }

  // ── Permission ────────────────────────────────────────────────────────────

  Future<ApprovalsPage> getPermissionRequests({
    String? status,
    String? search,
    String? type,
    String? startDate,
    String? endDate,
    String? tab,
    String? sort,
    String? staffId,
  }) {
    return _getPaged('permission', {
      'status': status,
      'search': search,
      'type': type,
      'startDate': startDate,
      'endDate': endDate,
      'tab': tab,
      'sort': sort,
      'staffId': staffId,
    });
  }

  Future<Map<String, dynamic>> getPermissionDetail(String id) => _getDetail('permission', id);

  Future<String> approvePermission(String id, {String? remarks}) async {
    final body = await _call('$_base/permission/$id/approve',
        method: 'POST', data: {'remarks': remarks}, fallback: 'Failed to approve permission');
    return _messageOf(body, 'Permission request approved');
  }

  Future<String> rejectPermission(String id, {required String reason, String? remarks}) async {
    final body = await _call('$_base/permission/$id/reject',
        method: 'POST', data: {'reason': reason, 'remarks': remarks}, fallback: 'Failed to reject permission');
    return _messageOf(body, 'Permission request rejected');
  }

  // ── Punch (batch) ─────────────────────────────────────────────────────────

  /// [date] is `yyyy-MM-dd`; omitted returns every present/half-day record in scope.
  Future<List<Map<String, dynamic>>> getPunchApprovals({String? date}) async {
    final body = await _call('$_base/punch', query: {'date': date}, fallback: 'Failed to load punch approvals');
    return _asMapList(body['data']);
  }

  Future<String> approvePunches(List<String> ids) async {
    final body = await _call('$_base/punch/approve',
        method: 'POST', data: {'ids': ids}, fallback: 'Failed to approve punches');
    return _messageOf(body, 'Attendances approved successfully');
  }

  Future<String> rejectPunches(List<String> ids) async {
    final body = await _call('$_base/punch/reject',
        method: 'POST', data: {'ids': ids}, fallback: 'Failed to reject punches');
    return _messageOf(body, 'Attendances rejected successfully');
  }

  // ── Fine (batch) ──────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getFineApprovals({String? date}) async {
    final body = await _call('$_base/fine', query: {'date': date}, fallback: 'Failed to load fine approvals');
    return _asMapList(body['data']);
  }

  Future<String> approveFines(List<String> ids) async {
    final body = await _call('$_base/fine/approve',
        method: 'POST', data: {'ids': ids}, fallback: 'Failed to approve fines');
    return _messageOf(body, 'Fines approved successfully');
  }

  Future<String> rejectFines(List<String> ids) async {
    final body = await _call('$_base/fine/reject',
        method: 'POST', data: {'ids': ids}, fallback: 'Failed to reject fines');
    return _messageOf(body, 'Fines rejected successfully');
  }

  // ── Expense / Reimbursement ───────────────────────────────────────────────

  Future<ApprovalsPage> getExpenseRequests({
    String? status,
    String? search,
    String? type,
    String? startDate,
    String? endDate,
    String? sort,
    String? staffId,
  }) {
    return _getPaged('expense', {
      'status': status,
      'search': search,
      'type': type,
      'startDate': startDate,
      'endDate': endDate,
      'sort': sort,
      'staffId': staffId,
    });
  }

  Future<Map<String, dynamic>> getExpenseDetail(String id) => _getDetail('expense', id);

  /// Mirrors the web payout modal: [paymentRoute] is 'Payroll' (with [payrollMonth], e.g.
  /// "October 2026") or 'Immediate' (with account fields and an optional [proofImg] data URL,
  /// `data:<mime>;base64,...`, which the backend uploads). Unused fields are sent as null.
  Future<String> approveExpense(
    String id, {
    required String paymentRoute,
    String? payrollMonth,
    String? upiId,
    String? accountNo,
    String? ifscCode,
    String? proofImg,
    String remarks = 'Approved',
  }) async {
    final body = await _call('$_base/expense/$id/approve',
        method: 'POST',
        data: {
          'paymentRoute': paymentRoute,
          'payrollMonth': payrollMonth,
          'upiId': upiId,
          'accountNo': accountNo,
          'ifscCode': ifscCode,
          'proofImg': proofImg,
          'remarks': remarks,
        },
        fallback: 'Failed to approve claim');
    return _messageOf(body, 'Expense request approved');
  }

  Future<String> rejectExpense(String id, {required String reason, String? remarks}) async {
    final body = await _call('$_base/expense/$id/reject',
        method: 'POST', data: {'reason': reason, 'remarks': remarks ?? reason}, fallback: 'Failed to reject claim');
    return _messageOf(body, 'Expense request rejected');
  }

  /// Staff profile (GET /admin/staff/:id -> data.staff), read for the payout account details.
  Future<Map<String, dynamic>> getStaffProfile(String staffId) async {
    final body = await _call('/admin/staff/$staffId', fallback: 'Failed to load staff profile');
    final data = body['data'];
    if (data is Map && data['staff'] is Map) {
      return Map<String, dynamic>.from(data['staff'] as Map);
    }
    throw AdminApprovalsException('Staff profile not found');
  }

  // ── Payslip ───────────────────────────────────────────────────────────────

  Future<ApprovalsPage> getPayslipRequests({
    String? status,
    String? search,
    String? sort,
    String? staffId,
    String? startDate,
    String? endDate,
  }) {
    return _getPaged('payslip', {
      'status': status,
      'search': search,
      'sort': sort,
      'staffId': staffId,
      'startDate': startDate,
      'endDate': endDate,
    });
  }

  Future<String> approvePayslip(String id, {String? remarks}) async {
    final body = await _call('$_base/payslip/$id/approve',
        method: 'POST', data: {'remarks': remarks}, fallback: 'Failed to approve payslip request');
    return _messageOf(body, 'Payslip request approved');
  }

  Future<String> rejectPayslip(String id, {required String reason, String? remarks}) async {
    final body = await _call('$_base/payslip/$id/reject',
        method: 'POST', data: {'reason': reason, 'remarks': remarks ?? reason}, fallback: 'Failed to reject payslip request');
    return _messageOf(body, 'Payslip request rejected');
  }

  // ── Generic hub helpers ───────────────────────────────────────────────────

  /// List for the hub. Punch/fine return a bare list with no summary.
  Future<ApprovalsPage> getApprovalsList({
    required String type,
    String? status,
    String? search,
  }) async {
    final st = (status == null || status == 'All') ? null : status;
    switch (type) {
      case 'leave':
        return getLeaveRequests(status: st, search: search);
      case 'permission':
        return getPermissionRequests(status: st, search: search);
      case 'expense':
        return getExpenseRequests(status: st, search: search);
      case 'payslip':
        return getPayslipRequests(status: st, search: search);
      case 'punch':
        return ApprovalsPage(await getPunchApprovals(), const {});
      case 'fine':
        return ApprovalsPage(await getFineApprovals(), const {});
    }
    throw AdminApprovalsException('Unknown approval type: $type');
  }

  /// Approve one request of any type except expense (which needs the payout details,
  /// see [approveExpense]). Punch and fine go through the batch endpoints.
  Future<String> approveRequest({required String type, required String requestId, String? remarks}) {
    switch (type) {
      case 'leave':
        return approveLeave(requestId, remarks: remarks);
      case 'permission':
        return approvePermission(requestId, remarks: remarks);
      case 'payslip':
        return approvePayslip(requestId, remarks: remarks);
      case 'punch':
        return approvePunches([requestId]);
      case 'fine':
        return approveFines([requestId]);
    }
    throw AdminApprovalsException('Use the payout flow to approve a reimbursement');
  }

  Future<String> rejectRequest({required String type, required String requestId, required String reason}) {
    switch (type) {
      case 'leave':
        return rejectLeave(requestId, reason: reason);
      case 'permission':
        return rejectPermission(requestId, reason: reason);
      case 'expense':
        return rejectExpense(requestId, reason: reason);
      case 'payslip':
        return rejectPayslip(requestId, reason: reason);
      case 'punch':
        return rejectPunches([requestId]);
      case 'fine':
        return rejectFines([requestId]);
    }
    throw AdminApprovalsException('Unknown approval type: $type');
  }
}

class ApprovalsPage {
  final List<Map<String, dynamic>> requests;
  final Map<String, dynamic> summary;
  const ApprovalsPage(this.requests, this.summary);
}
