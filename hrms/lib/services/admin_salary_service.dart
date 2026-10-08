// Admin salary APIs: Salary Overview, Salary Structure and Incentive Management.
// HRMSbackend src/routes/admin/salaryRoute.ts, mounted under /api/admin/staff.
//
// Every method answers { success, data?, message?, code? } and never throws, so a screen can
// show the backend's own message when a call fails.

import 'package:dio/dio.dart';

import 'api_client.dart';

class AdminSalaryService {
  AdminSalaryService._();
  static final AdminSalaryService instance = AdminSalaryService._();
  final ApiClient _api = ApiClient();

  static String messageOf(Object e) {
    if (e is DioException) {
      final data = e.response?.data;
      if (data is Map && data['message'] != null) return data['message'].toString();
      if (e.type == DioExceptionType.connectionError || e.type == DioExceptionType.connectionTimeout) {
        return 'Could not reach the server. Check your connection.';
      }
      return e.message ?? 'Request failed.';
    }
    return e.toString();
  }

  /// Runs one request. [pick] turns the response body into the `data` the screen wants.
  Future<Map<String, dynamic>> _run(
    Future<Response<dynamic>> Function() call, {
    dynamic Function(Map<String, dynamic> body)? pick,
  }) async {
    try {
      final res = await call();
      final body = res.data is Map ? Map<String, dynamic>.from(res.data as Map) : <String, dynamic>{};
      if (body['success'] == false) {
        return {'success': false, 'message': body['message']?.toString() ?? 'Request failed.'};
      }
      return {
        'success': true,
        'data': pick != null ? pick(body) : body['data'],
        'message': body['message']?.toString(),
      };
    } catch (e) {
      final out = <String, dynamic>{'success': false, 'message': messageOf(e)};
      if (e is DioException && e.response?.data is Map) {
        final body = e.response!.data as Map;
        if (body['code'] != null) out['code'] = body['code'].toString();
        if (body['data'] != null) out['data'] = body['data'];
      }
      return out;
    }
  }

  static List<Map<String, dynamic>> _maps(dynamic v) =>
      v is List ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : <Map<String, dynamic>>[];

  static Map<String, dynamic> _map(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

  // ── Staff (shared lookups) ────────────────────────────────────────────

  /// GET /admin/staff → data.staff
  Future<Map<String, dynamic>> getStaffList() =>
      _run(() => _api.request('/admin/staff'), pick: (b) => _maps(_map(b['data'])['staff']));

  /// GET /admin/staff/:id → data.staff
  Future<Map<String, dynamic>> getStaffDetail(String staffId) =>
      _run(() => _api.request('/admin/staff/$staffId'), pick: (b) => _map(_map(b['data'])['staff']));

  // ── Salary Overview ───────────────────────────────────────────────────

  /// GET /admin/staff/overview?month="August 2026" → data: [{ id, staffId, name, role, baseSalary,
  /// allowances, deductions, netPay, status, month }]
  Future<Map<String, dynamic>> getOverviewList(String month) => _run(
        () => _api.request('/admin/staff/overview', queryParameters: {'month': month}),
        pick: (b) => _maps(b['data']),
      );

  /// GET /admin/staff/overview/detail/:staffId?month → the month's breakdown plus isGenerated.
  Future<Map<String, dynamic>> getOverviewDetail(String staffId, String month) => _run(
        () => _api.request('/admin/staff/overview/detail/$staffId', queryParameters: {'month': month}),
        pick: (b) => _map(b['data']),
      );

  /// PUT /admin/staff/overview/detail/:staffId?month — saves a hand-edited breakdown.
  Future<Map<String, dynamic>> updateOverviewDetail(String staffId, String month, Map<String, dynamic> body) => _run(
        () => _api.request(
          '/admin/staff/overview/detail/$staffId',
          method: 'PUT',
          queryParameters: {'month': month},
          data: body,
        ),
        pick: (b) => _map(b['data']),
      );

  /// POST /admin/staff/payroll/generate { staffId, month } — generates the payslip for the month.
  Future<Map<String, dynamic>> generatePayslip(String staffId, String month) => _run(
        () => _api.request('/admin/staff/payroll/generate', method: 'POST', data: {'staffId': staffId, 'month': month}),
        pick: (b) => b,
      );

  // ── Salary Structure ──────────────────────────────────────────────────

  /// GET /admin/staff/salary-structures/staff/:staffId → data { structure, history }
  Future<Map<String, dynamic>> getSalaryStructure(String staffId) => _run(
        () => _api.request('/admin/staff/salary-structures/staff/$staffId'),
        pick: (b) => _map(b['data']),
      );

  /// POST /admin/staff/salary-structures — creates the new (revised) structure.
  Future<Map<String, dynamic>> saveSalaryStructure(Map<String, dynamic> body) => _run(
        () => _api.request('/admin/staff/salary-structures', method: 'POST', data: body),
        pick: (b) => _map(_map(b['data'])['structure']),
      );

  /// GET /admin/staff/salary-templates → data.templates (components populated).
  Future<Map<String, dynamic>> getSalaryTemplates() => _run(
        () => _api.request('/admin/staff/salary-templates'),
        pick: (b) => _maps(_map(b['data'])['templates']),
      );

  // ── Incentive ─────────────────────────────────────────────────────────

  /// GET /admin/staff/incentive?month&department&status →
  /// data { month, eligible[], notEligible[], departments[], monthLocked }
  Future<Map<String, dynamic>> getIncentiveList(String month, {String? department, String? status}) {
    final q = <String, dynamic>{'month': month};
    if (department != null && department != 'All') q['department'] = department;
    if (status != null && status != 'All') q['status'] = status;
    return _run(() => _api.request('/admin/staff/incentive', queryParameters: q), pick: (b) => _map(b['data']));
  }

  /// GET /admin/staff/incentive/locked-months → data: ["August 2026", ...]
  Future<Map<String, dynamic>> getIncentiveLockedMonths() => _run(
        () => _api.request('/admin/staff/incentive/locked-months'),
        pick: (b) => (b['data'] is List) ? (b['data'] as List).map((e) => e.toString()).toList() : <String>[],
      );

  /// GET /admin/staff/incentive/payroll-months?id → the runs an approval may pay this record into.
  Future<Map<String, dynamic>> getIncentivePayrollMonths(String id) => _run(
        () => _api.request('/admin/staff/incentive/payroll-months', queryParameters: {'id': id}),
        pick: (b) => (b['data'] is List) ? (b['data'] as List).map((e) => e.toString()).toList() : <String>[],
      );

  /// GET /admin/staff/incentive/eligibility?month → data { month, rows[] }
  Future<Map<String, dynamic>> getIncentiveEligibility(String month) => _run(
        () => _api.request('/admin/staff/incentive/eligibility', queryParameters: {'month': month}),
        pick: (b) => _map(b['data']),
      );

  /// PUT /admin/staff/incentive/eligibility/:staffId { eligible, month }
  Future<Map<String, dynamic>> updateIncentiveEligibility(String staffId, bool eligible, String month) => _run(
        () => _api.request(
          '/admin/staff/incentive/eligibility/$staffId',
          method: 'PUT',
          data: {'eligible': eligible, 'month': month},
        ),
      );

  /// GET /admin/staff/incentive/template?month → data { month, rows: [{ employeeId, name, department, branch }] }
  Future<Map<String, dynamic>> getIncentiveTemplate(String month) => _run(
        () => _api.request('/admin/staff/incentive/template', queryParameters: {'month': month}),
        pick: (b) => _map(b['data']),
      );

  /// POST /admin/staff/incentive/import { month, rows: [{ employeeId, target, achieved, incentiveAmount }] }
  /// → data { imported, replaced, failures[] }
  Future<Map<String, dynamic>> importIncentives(String month, List<Map<String, dynamic>> rows) => _run(
        () => _api.request('/admin/staff/incentive/import', method: 'POST', data: {'month': month, 'rows': rows}),
        pick: (b) => _map(b['data']),
      );

  /// PUT /admin/staff/incentive/:id { target, achieved, incentiveAmount }
  Future<Map<String, dynamic>> updateIncentive(String id, num target, num achieved, num incentiveAmount) => _run(
        () => _api.request(
          '/admin/staff/incentive/$id',
          method: 'PUT',
          data: {'target': target, 'achieved': achieved, 'incentiveAmount': incentiveAmount},
        ),
      );

  /// PUT /admin/staff/incentive/:id/approve { payrollMonth? }. A refusal with
  /// code PAYROLL_MONTH_REQUIRED carries data.openMonths.
  Future<Map<String, dynamic>> approveIncentive(String id, {String? payrollMonth}) => _run(
        () => _api.request(
          '/admin/staff/incentive/$id/approve',
          method: 'PUT',
          data: payrollMonth != null && payrollMonth.isNotEmpty ? {'payrollMonth': payrollMonth} : <String, dynamic>{},
        ),
      );

  /// PUT /admin/staff/incentive/:id/reject { rejectionReason }
  Future<Map<String, dynamic>> rejectIncentive(String id, String rejectionReason) => _run(
        () => _api.request(
          '/admin/staff/incentive/$id/reject',
          method: 'PUT',
          data: {'rejectionReason': rejectionReason},
        ),
      );
}
