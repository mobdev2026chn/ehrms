// Loans & salary advances against HRMSbackend's loan module - the same APIs the web uses:
//   staff  /staff/loans/*  (controllers/staff/loans/staffLoanController.ts)
//   admin  /admin/loans/*  (controllers/admin/loans/*, admin role only)
// Every call throws an Exception carrying the server's message on failure.

import 'package:dio/dio.dart';

import '../models/loan_models.dart';
import 'api_client.dart';

class LoanService {
  final ApiClient _api = ApiClient();

  static Map<String, dynamic> _data(Response<dynamic> res) {
    final body = res.data;
    if (body is Map && body['success'] == true) {
      final d = body['data'];
      return d is Map ? Map<String, dynamic>.from(d) : <String, dynamic>{};
    }
    throw Exception(body is Map ? (body['message'] ?? 'Request failed') : 'Request failed');
  }

  static Exception _error(Object e, String fallback) {
    if (e is DioException) {
      final body = e.response?.data;
      final msg = body is Map ? body['message']?.toString() : null;
      if (msg != null && msg.isNotEmpty) return Exception(msg);
      if (e.response == null) return Exception('$fallback. Please check your connection.');
    }
    if (e is Exception) return e;
    return Exception(fallback);
  }

  Future<Map<String, dynamic>> _get(String path, String fallback, {Map<String, dynamic>? query}) async {
    try {
      return _data(await _api.dio.get<dynamic>(path, queryParameters: query));
    } catch (e) {
      throw _error(e, fallback);
    }
  }

  Future<Map<String, dynamic>> _send(String method, String path, Map<String, dynamic> body, String fallback) async {
    try {
      return _data(await _api.dio.request<dynamic>(path, data: body, options: Options(method: method)));
    } catch (e) {
      throw _error(e, fallback);
    }
  }

  // ── Staff ─────────────────────────────────────────────────────────────

  /// Loan types, salary-advance rules and this employee's eligibility.
  Future<LoanPolicyView> getPolicy() async =>
      LoanPolicyView.fromJson(await _get('/staff/loans/policy', 'Could not load the loan policy'));

  /// All of this employee's loans and requests, newest first.
  Future<({List<Loan> loans, List<LoanRequest> requests})> getMyLoans() async {
    final d = await _get('/staff/loans', 'Could not load your loans');
    List<T> list<T>(dynamic v, T Function(Map<String, dynamic>) f) =>
        v is List ? v.whereType<Map>().map((e) => f(Map<String, dynamic>.from(e))).toList() : <T>[];
    return (loans: list(d['loans'], Loan.fromJson), requests: list(d['requests'], LoanRequest.fromJson));
  }

  Future<Loan> getMyLoan(String id) async {
    final d = await _get('/staff/loans/$id', 'Could not load the loan');
    return Loan.fromJson(Map<String, dynamic>.from(d['loan'] as Map));
  }

  Future<LoanRequest> getMyRequest(String id) async {
    final d = await _get('/staff/loans/requests/$id', 'Could not load the request');
    return LoanRequest.fromJson(Map<String, dynamic>.from(d['request'] as Map));
  }

  /// [documents]: `{name, type: <document label>, data: 'data:<mime>;base64,...'}`.
  Future<LoanRequest> submitRequest({
    required String category, // 'Loan' | 'SalaryAdvance'
    required double amount,
    required String reason,
    String? loanType,
    String? purpose,
    int? preferredTenure,
    String? advanceRecovery,
    DateTime? requiredBy,
    List<Map<String, String>> documents = const [],
  }) async {
    final d = await _send('POST', '/staff/loans/requests', {
      'category': category,
      'amount': amount,
      'reason': reason,
      if (loanType != null) 'loanType': loanType,
      if (purpose != null && purpose.isNotEmpty) 'purpose': purpose,
      if (preferredTenure != null) 'preferredTenure': preferredTenure,
      if (advanceRecovery != null) 'advanceRecovery': advanceRecovery,
      if (requiredBy != null) 'requiredBy': requiredBy.toUtc().toIso8601String(),
      if (documents.isNotEmpty) 'documents': documents,
    }, 'Could not submit the request');
    return LoanRequest.fromJson(d);
  }

  Future<LoanRequest> cancelRequest(String id, {String? reason}) async => LoanRequest.fromJson(await _send(
        'POST',
        '/staff/loans/requests/$id/cancel',
        {if (reason != null && reason.isNotEmpty) 'reason': reason},
        'Could not cancel the request',
      ));

  Future<LoanRequest> replyClarification(String id, String message, {List<Map<String, String>> documents = const []}) async =>
      LoanRequest.fromJson(await _send(
        'POST',
        '/staff/loans/requests/$id/clarification',
        {'message': message, if (documents.isNotEmpty) 'documents': documents},
        'Could not send your reply',
      ));

  // ── Admin ─────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> adminDashboard() => _get('/admin/loans/dashboard', 'Could not load the loan dashboard');

  /// Query for the admin list endpoints (adminLoan.service.ts `ListQuery`): status, category,
  /// loanType, department, branch, search, from/to (YYYY-MM-DD). 'All' / empty are dropped.
  static Map<String, dynamic> _listQuery({
    String? status,
    String? category,
    String? search,
    String? loanType,
    String? department,
    String? branch,
    DateTime? from,
    DateTime? to,
  }) {
    String day(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    bool set(String? v) => v != null && v.trim().isNotEmpty && v != 'All';
    return {
      if (set(status)) 'status': status,
      if (set(category)) 'category': category,
      if (set(loanType)) 'loanType': loanType,
      if (set(department)) 'department': department,
      if (set(branch)) 'branch': branch,
      if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
      if (from != null) 'from': day(from),
      if (to != null) 'to': day(to),
    };
  }

  /// Filters: status, category, search, loanType, department, branch, from/to (applied date).
  Future<List<LoanRequest>> adminRequests({
    String? status,
    String? category,
    String? search,
    String? loanType,
    String? department,
    String? branch,
    DateTime? from,
    DateTime? to,
  }) async {
    final d = await _get('/admin/loans/requests', 'Could not load loan requests',
        query: _listQuery(
            status: status,
            category: category,
            search: search,
            loanType: loanType,
            department: department,
            branch: branch,
            from: from,
            to: to));
    final list = d['requests'];
    return list is List ? list.whereType<Map>().map((e) => LoanRequest.fromJson(Map<String, dynamic>.from(e))).toList() : [];
  }

  /// The request plus the employee's active loans, loan history and the type's policy.
  Future<({LoanRequest request, List<Loan> activeLoans, List<Loan> loanHistory, Map<String, dynamic>? policy})>
      adminRequest(String id) async {
    final d = await _get('/admin/loans/requests/$id', 'Could not load the request');
    List<Loan> loans(dynamic v) =>
        v is List ? v.whereType<Map>().map((e) => Loan.fromJson(Map<String, dynamic>.from(e))).toList() : [];
    return (
      request: LoanRequest.fromJson(Map<String, dynamic>.from(d['request'] as Map)),
      activeLoans: loans(d['activeLoans']),
      loanHistory: loans(d['loanHistory']),
      policy: d['policy'] is Map ? Map<String, dynamic>.from(d['policy']) : null,
    );
  }

  Future<Loan> adminApprove(String id, Map<String, dynamic> terms) async =>
      Loan.fromJson(await _send('POST', '/admin/loans/requests/$id/approve', terms, 'Could not approve the request'));

  Future<void> adminReject(String id, String reason) =>
      _send('POST', '/admin/loans/requests/$id/reject', {'reason': reason}, 'Could not reject the request');

  Future<void> adminAskClarification(String id, String question) =>
      _send('POST', '/admin/loans/requests/$id/clarification', {'question': question}, 'Could not send the question');

  /// Filters as [adminRequests]; from/to apply to the loan's creation date.
  Future<List<Loan>> adminLoans({
    String? status,
    String? category,
    String? search,
    String? loanType,
    String? department,
    String? branch,
    DateTime? from,
    DateTime? to,
  }) async {
    final d = await _get('/admin/loans', 'Could not load loans',
        query: _listQuery(
            status: status,
            category: category,
            search: search,
            loanType: loanType,
            department: department,
            branch: branch,
            from: from,
            to: to));
    final list = d['loans'];
    return list is List ? list.whereType<Map>().map((e) => Loan.fromJson(Map<String, dynamic>.from(e))).toList() : [];
  }

  Future<Loan> adminLoan(String id) async {
    final d = await _get('/admin/loans/$id', 'Could not load the loan');
    return Loan.fromJson(Map<String, dynamic>.from(d['loan'] as Map));
  }

  /// mode: 'Bank Transfer' | 'Cash'
  Future<Loan> adminDisburse(String id, {required String mode, DateTime? date, String? reference, String? remarks}) async =>
      Loan.fromJson(await _send('POST', '/admin/loans/$id/disburse', {
        'mode': mode,
        if (date != null) 'date': date.toUtc().toIso8601String(),
        if (reference != null && reference.isNotEmpty) 'reference': reference,
        if (remarks != null && remarks.isNotEmpty) 'remarks': remarks,
      }, 'Could not record the disbursement'));

  /// kind: 'Manual EMI' | 'Foreclosure'; mode: Payroll, Manual, Bank, Cash, Cheque, UPI, F&F, Adjustment.
  Future<Loan> adminRecordPayment(String id,
          {required String kind, required double amount, required String mode, DateTime? date, String? reference, String? remarks}) async =>
      Loan.fromJson(await _send('POST', '/admin/loans/$id/payments', {
        'kind': kind,
        'amount': amount,
        'mode': mode,
        if (date != null) 'date': date.toUtc().toIso8601String(),
        if (reference != null && reference.isNotEmpty) 'reference': reference,
        if (remarks != null && remarks.isNotEmpty) 'remarks': remarks,
      }, 'Could not record the payment'));

  /// status: 'Closed' | 'Cancelled' | 'Defaulted'
  Future<Loan> adminSetStatus(String id, String status, String reason) async =>
      Loan.fromJson(await _send('PATCH', '/admin/loans/$id/status', {'status': status, 'reason': reason},
          'Could not change the loan status'));

  // ── Payroll recovery & settings ──

  /// GET /admin/loans/payroll-recovery?month=YYYY-MM -> {month, payrollStatus, rows}.
  Future<Map<String, dynamic>> adminPayrollRecovery(String month) =>
      _get('/admin/loans/payroll-recovery', 'Could not load payroll recovery', query: {'month': month});

  /// POST /admin/loans/payroll-recovery/run. [rowIds] limits the run to those rows; null runs all.
  /// Returns how many EMIs were recovered.
  Future<int> adminRunPayrollRecovery(String month, {List<String>? rowIds}) async {
    final d = await _send('POST', '/admin/loans/payroll-recovery/run', {
      'month': month,
      if (rowIds != null) 'rowIds': rowIds,
    }, 'Could not run the payroll recovery');
    return (d['processed'] as num?)?.toInt() ?? 0;
  }

  /// GET /admin/loans/settings -> {general, loanTypes, salaryAdvance, payroll, workflow, notifications}.
  Future<Map<String, dynamic>> adminSettings() => _get('/admin/loans/settings', 'Could not load the loan settings');

  /// PUT /admin/loans/settings with whole sections; returns the saved settings.
  Future<Map<String, dynamic>> adminUpdateSettings(Map<String, dynamic> sections) =>
      _send('PUT', '/admin/loans/settings', sections, 'Could not save the loan settings');
}
