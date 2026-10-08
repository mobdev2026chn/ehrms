import 'package:dio/dio.dart';

import '../utils/error_message_utils.dart';
import 'api_client.dart';

/// A failed HRMS GEO admin call, carrying the backend's message (or a readable fallback).
class GeoApiException implements Exception {
  GeoApiException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Admin GEO APIs (HRMSbackend /api/admin/hrms-geo/*): tracking, travel allowance, tasks,
/// customers and GEO settings. Admins only.
///
/// Every method returns the parsed payload and throws [GeoApiException] on failure, so the
/// screens can show the backend's message and change their state only after success.
class AdminGeoService {
  AdminGeoService._();
  static final AdminGeoService instance = AdminGeoService._();
  final ApiClient _api = ApiClient();

  static const _base = '/admin/hrms-geo';

  /// yyyy-MM-dd of a local calendar day.
  static String dayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // ── plumbing ──────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _call(
    String path, {
    String method = 'GET',
    dynamic data,
    Map<String, dynamic>? query,
    String fallback = 'Request failed',
  }) async {
    try {
      final res = await _api.request<dynamic>(path, method: method, data: data, queryParameters: query);
      final body = res.data;
      if (body is Map) {
        final map = Map<String, dynamic>.from(body);
        if (map['success'] == false) {
          throw GeoApiException(ErrorMessageUtils.messageFromResponseData(map) ?? fallback);
        }
        return map;
      }
      throw GeoApiException(fallback);
    } on DioException catch (e) {
      throw GeoApiException(ErrorMessageUtils.messageFromDioException(e, fallback: fallback));
    }
  }

  static Map<String, dynamic> _map(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

  static List<Map<String, dynamic>> _list(dynamic v) =>
      v is List ? [for (final e in v) if (e is Map) Map<String, dynamic>.from(e)] : <Map<String, dynamic>>[];

  // ── tracking ──────────────────────────────────────────────────────────────────

  /// Today's figures: totals, tasks by status, per-staff totals and recent activities.
  /// GET /tracking/dashboard
  Future<Map<String, dynamic>> getDashboard() async =>
      _map((await _call('$_base/tracking/dashboard', fallback: 'Could not load the GEO dashboard.'))['data']);

  /// Staff punched in right now with their latest position. GET /tracking/live
  Future<({List<Map<String, dynamic>> items, int? liveWindowSeconds})> getLive() async {
    final r = await _call('$_base/tracking/live', fallback: 'Could not load live staff.');
    final w = r['liveWindowSeconds'];
    return (items: _list(r['data']), liveWindowSeconds: w is num ? w.toInt() : null);
  }

  /// Every staff member with completed-task distance and visit count. GET /tracking/summary
  Future<List<Map<String, dynamic>>> getTrackingSummary() async =>
      _list((await _call('$_base/tracking/summary', fallback: 'Could not load tracking summary.'))['data']);

  /// One staff member's tracking record for a date range (tasks, visits, route, transport,
  /// travel-allowance claims, payout details). GET /tracking/:id?startDate&endDate
  Future<Map<String, dynamic>> getTrackingDetails(String staffId, {required String startDate, required String endDate}) async =>
      _map((await _call(
        '$_base/tracking/$staffId',
        query: {'startDate': startDate, 'endDate': endDate},
        fallback: 'Could not load tracking details.',
      ))['data']);

  /// One staff member's day timeline (active task, tasks, activity events and segments).
  /// GET /tracking/timeline/:staffId?date=
  Future<Map<String, dynamic>> getTimeline(String staffId, String date) async =>
      _map((await _call(
        '$_base/tracking/timeline/$staffId',
        query: {'date': date},
        fallback: 'Could not load the timeline.',
      ))['data']);

  /// Location records between two instants (at most a day).
  /// GET /tracking/timeline/:staffId/locations?from=ISO&to=ISO
  Future<List<Map<String, dynamic>>> getTimelineLocations(String staffId, {required String from, required String to}) async =>
      _list((await _call(
        '$_base/tracking/timeline/$staffId/locations',
        query: {'from': from, 'to': to},
        fallback: 'Could not load location records.',
      ))['data']);

  /// One staff member's field day route (flags + legs + trail), same shape as the staff
  /// day-route. GET /day-route/:staffId?date=YYYY-MM-DD
  Future<Map<String, dynamic>> getStaffDayRoute(String staffId, DateTime day) async {
    final r = await _call('$_base/day-route/$staffId',
        query: {'date': dayKey(day)}, fallback: 'Could not load this employee\'s route.');
    final data = r['data'];
    if (data is Map) return Map<String, dynamic>.from(data);
    throw GeoApiException('Could not load this employee\'s route.');
  }

  // ── travel allowance ──────────────────────────────────────────────────────────

  /// Claims, newest first (optionally one day / one staff). GET /travel-allowance?date&staffId
  Future<List<Map<String, dynamic>>> getTravelAllowances({String? date, String? staffId}) async {
    final q = <String, dynamic>{};
    if (date != null) q['date'] = date;
    if (staffId != null) q['staffId'] = staffId;
    return _list((await _call('$_base/travel-allowance',
            query: q.isEmpty ? null : q, fallback: 'Could not load claims.'))['data']);
  }

  /// One claim document. GET /travel-allowance/:id
  Future<Map<String, dynamic>> getTravelAllowance(String id) async =>
      _map((await _call('$_base/travel-allowance/$id', fallback: 'Could not load the claim.'))['data']);

  /// Completed tasks of a staff day with distance per task. GET /task/travel-allowance?staffId&date
  Future<Map<String, dynamic>> getTaskTravelBreakdown(String staffId, String date) async =>
      _call('$_base/task/travel-allowance',
          query: {'staffId': staffId, 'date': date}, fallback: 'Could not load the task breakdown.');

  /// Months ("October 2026") whose payroll is already paid for this staff member.
  /// GET /travel-allowance/paid-payroll-months?staffId=
  Future<List<String>> getPaidPayrollMonths(String staffId) async {
    final r = await _call('$_base/travel-allowance/paid-payroll-months',
        query: {'staffId': staffId}, fallback: 'Could not load paid payroll months.');
    final d = r['data'];
    return d is List ? [for (final m in d) m.toString()] : <String>[];
  }

  /// Approve a claim. [paymentRoute] is 'Payroll' (with [payrollMonth] "October 2026") or
  /// 'Immediate' (with UPI / bank details and an optional proof image data URL).
  /// POST /travel-allowance/approve?staffId&date
  Future<Map<String, dynamic>> approveTravelAllowance({
    required String staffId,
    required String date,
    required String paymentRoute,
    String? payrollMonth,
    String? upiId,
    String? accountNo,
    String? ifscCode,
    String? proofImg,
  }) async =>
      _call(
        '$_base/travel-allowance/approve',
        method: 'POST',
        query: {'staffId': staffId, 'date': date},
        data: {
          'paymentRoute': paymentRoute,
          'payrollMonth': payrollMonth,
          'upiId': upiId,
          'accountNo': accountNo,
          'ifscCode': ifscCode,
          'proofImg': proofImg,
        },
        fallback: 'Could not approve the claim.',
      );

  /// Revise a claim's figures. POST /travel-allowance/revise
  Future<Map<String, dynamic>> reviseTravelAllowance({
    required String staffId,
    required String date,
    required double ratePerKm,
    required double totalDistanceKm,
    required double revisedAmount,
    String? description,
  }) async =>
      _call(
        '$_base/travel-allowance/revise',
        method: 'POST',
        data: {
          'staffId': staffId,
          'date': date,
          'ratePerKm': ratePerKm,
          'totalDistanceKm': totalDistanceKm,
          'revisedAmount': revisedAmount,
          'description': description ?? '',
        },
        fallback: 'Could not revise the claim.',
      );

  /// Reject a claim with a reason. POST /travel-allowance { status: 'Rejected' }
  Future<Map<String, dynamic>> rejectTravelAllowance({
    required String staffId,
    required String date,
    required String reason,
  }) async =>
      _call(
        '$_base/travel-allowance',
        method: 'POST',
        data: {'staffId': staffId, 'date': date, 'status': 'Rejected', 'description': reason},
        fallback: 'Could not reject the claim.',
      );

  // ── tasks ─────────────────────────────────────────────────────────────────────

  /// GET /task?status&type&search
  Future<List<Map<String, dynamic>>> getTasks({String? status, String? type, String? search}) async {
    final q = <String, dynamic>{};
    if (status != null && status != 'All') q['status'] = status;
    if (type != null && type != 'All') q['type'] = type;
    if (search != null && search.trim().isNotEmpty) q['search'] = search.trim();
    return _list((await _call('$_base/task', query: q.isEmpty ? null : q, fallback: 'Could not load tasks.'))['data']);
  }

  /// GET /task/:id (Mongo id or task number)
  Future<Map<String, dynamic>> getTask(String id) async =>
      _map((await _call('$_base/task/$id', fallback: 'Could not load the task.'))['data']);

  /// POST /task
  Future<Map<String, dynamic>> createTask(Map<String, dynamic> body) async =>
      _call('$_base/task', method: 'POST', data: body, fallback: 'Could not create the task.');

  /// PUT /task/:id
  Future<Map<String, dynamic>> updateTask(String id, Map<String, dynamic> body) async =>
      _call('$_base/task/$id', method: 'PUT', data: body, fallback: 'Could not update the task.');

  /// DELETE /task/:id
  Future<Map<String, dynamic>> deleteTask(String id) async =>
      _call('$_base/task/$id', method: 'DELETE', fallback: 'Could not delete the task.');

  // ── customers ─────────────────────────────────────────────────────────────────

  /// GET /customer
  Future<List<Map<String, dynamic>>> getCustomers() async =>
      _list((await _call('$_base/customer', fallback: 'Could not load customers.'))['data']);

  /// GET /customer/:id
  Future<Map<String, dynamic>> getCustomer(String id) async =>
      _map((await _call('$_base/customer/$id', fallback: 'Could not load the customer.'))['data']);

  /// POST /customer
  Future<Map<String, dynamic>> createCustomer(Map<String, dynamic> body) async =>
      _call('$_base/customer', method: 'POST', data: body, fallback: 'Could not create the customer.');

  /// PUT /customer/:id
  Future<Map<String, dynamic>> updateCustomer(String id, Map<String, dynamic> body) async =>
      _call('$_base/customer/$id', method: 'PUT', data: body, fallback: 'Could not update the customer.');

  /// DELETE /customer/:id
  Future<Map<String, dynamic>> deleteCustomer(String id) async =>
      _call('$_base/customer/$id', method: 'DELETE', fallback: 'Could not delete the customer.');

  // ── lookups ───────────────────────────────────────────────────────────────────

  /// Company branches (for internal tasks / employee access). GET /admin/settings/attendance/branches
  Future<List<Map<String, dynamic>>> getBranches() async =>
      _list((await _call('/admin/settings/attendance/branches', fallback: 'Could not load branches.'))['data']);

  // ── settings: general ─────────────────────────────────────────────────────────

  /// GET /settings/general-settings
  Future<Map<String, dynamic>> getGeneralSettings() async =>
      _map((await _call('$_base/settings/general-settings', fallback: 'Could not load settings.'))['data']);

  /// PUT /settings/general-settings (only the keys passed are changed)
  Future<Map<String, dynamic>> updateGeneralSettings({
    bool? autoTaskApproval,
    bool? liveTracking,
    bool? timelineTracking,
    int? liveTrackingInterval,
    int? dataStoreDays,
  }) async {
    final body = <String, dynamic>{};
    if (autoTaskApproval != null) body['autoTaskApproval'] = autoTaskApproval;
    if (liveTracking != null) body['liveTracking'] = liveTracking;
    if (timelineTracking != null) body['timelineTracking'] = timelineTracking;
    if (liveTrackingInterval != null) body['liveTrackingInterval'] = liveTrackingInterval;
    if (dataStoreDays != null) body['dataStoreDays'] = dataStoreDays;
    return _map((await _call('$_base/settings/general-settings',
            method: 'PUT', data: body, fallback: 'Could not save settings.'))['data']);
  }

  /// Every staff member with their auto-approval / timeline / live switches.
  /// GET /settings/general-settings/external-employees
  Future<List<Map<String, dynamic>>> getExternalEmployees() async =>
      _list((await _call('$_base/settings/general-settings/external-employees',
          fallback: 'Could not load employees.'))['data']);

  /// PUT /settings/general-settings/staff/:id/{auto-approval|timeline-tracking|live-tracking}
  /// [kind] is 'auto-approval', 'timeline-tracking' or 'live-tracking'.
  Future<Map<String, dynamic>> updateStaffGeoSwitch(String staffId, String kind, bool value) async {
    final key = switch (kind) {
      'auto-approval' => 'autoApproval',
      'timeline-tracking' => 'timelineTracking',
      _ => 'liveTracking',
    };
    return _call('$_base/settings/general-settings/staff/$staffId/$kind',
        method: 'PUT', data: {key: value}, fallback: 'Could not update the employee.');
  }

  /// Turn a switch off for every employee (and globally).
  /// PUT /settings/general-settings/global-{auto-approval|timeline-tracking|live-tracking}
  Future<Map<String, dynamic>> disableForAll(String kind) async =>
      _call('$_base/settings/general-settings/global-$kind', method: 'PUT', fallback: 'Could not update employees.');

  // ── settings: custom fields ───────────────────────────────────────────────────

  /// Customer and task fields (each carries `category`). GET /settings/custom-fields
  Future<List<Map<String, dynamic>>> getCustomFields() async =>
      _list((await _call('$_base/settings/custom-fields', fallback: 'Could not load custom fields.'))['data']);

  /// POST /settings/custom-fields
  Future<Map<String, dynamic>> createCustomField({
    required String category,
    required String label,
    required String type,
    required bool required,
    List<String> options = const [],
  }) async =>
      _call('$_base/settings/custom-fields',
          method: 'POST',
          data: {'category': category, 'label': label, 'type': type, 'required': required, 'options': options},
          fallback: 'Could not add the field.');

  /// PUT /settings/custom-fields/:id
  Future<Map<String, dynamic>> updateCustomField(
    String id, {
    required String label,
    required String type,
    required bool required,
    List<String> options = const [],
  }) async =>
      _call('$_base/settings/custom-fields/$id',
          method: 'PUT',
          data: {'label': label, 'type': type, 'required': required, 'options': options},
          fallback: 'Could not update the field.');

  /// DELETE /settings/custom-fields/:id
  Future<Map<String, dynamic>> deleteCustomField(String id) async =>
      _call('$_base/settings/custom-fields/$id', method: 'DELETE', fallback: 'Could not delete the field.');

  // ── settings: form templates ──────────────────────────────────────────────────

  /// The internal and external templates. GET /settings/form-templates
  Future<List<Map<String, dynamic>>> getFormTemplates() async =>
      _list((await _call('$_base/settings/form-templates', fallback: 'Could not load form templates.'))['data']);

  /// Replace a template's fields. PUT /settings/form-templates/:id
  Future<Map<String, dynamic>> updateFormTemplate(String id, List<Map<String, dynamic>> fields) async =>
      _map((await _call('$_base/settings/form-templates/$id',
              method: 'PUT', data: {'fields': fields}, fallback: 'Could not save the template.'))['data']);

  // ── settings: employee access ─────────────────────────────────────────────────

  /// GET /settings/employee-access
  Future<List<Map<String, dynamic>>> getEmployeeAccess() async =>
      _list((await _call('$_base/settings/employee-access', fallback: 'Could not load employee access.'))['data']);

  /// PUT /settings/employee-access/:id { type, transport, HRMSbranches }
  Future<Map<String, dynamic>> updateEmployeeAccess(String staffId, Map<String, dynamic> body) async =>
      _map((await _call('$_base/settings/employee-access/$staffId',
              method: 'PUT', data: body, fallback: 'Could not update employee access.'))['data']);

  // ── settings: travel allowance ────────────────────────────────────────────────

  /// GET /settings/travel-allowance → { _id, transports: [{_id,name,rate}], globalKmRate }
  Future<Map<String, dynamic>> getTaSettings() async =>
      _map((await _call('$_base/settings/travel-allowance', fallback: 'Could not load transport settings.'))['data']);

  /// PUT /settings/travel-allowance
  Future<Map<String, dynamic>> updateTaSettings({required List<Map<String, dynamic>> transports, num? globalKmRate}) async =>
      _map((await _call('$_base/settings/travel-allowance',
              method: 'PUT',
              data: {'transports': transports, if (globalKmRate != null) 'globalKmRate': globalKmRate},
              fallback: 'Could not save transport settings.'))['data']);
}
