import 'package:dio/dio.dart';
import 'api_client.dart';

/// Admin GEO / field-tracking APIs (HRMSbackend /api/admin/hrms-geo/*).
/// Same backend as staff login; admins only.
class AdminGeoService {
  AdminGeoService._();
  static final AdminGeoService instance = AdminGeoService._();
  final ApiClient _api = ApiClient();

  String _dayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String? _msg(Object e) {
    if (e is DioException) {
      final data = e.response?.data;
      if (data is Map && data['message'] != null) return data['message'].toString();
      return e.message;
    }
    return e.toString();
  }

  /// Field-tracking dashboard for the day: totals, per-staff task counts, pending claims.
  /// GET /admin/hrms-geo/tracking/dashboard
  Future<Map<String, dynamic>> getDashboard({DateTime? day}) async {
    try {
      final res = await _api.request<Map<String, dynamic>>(
        '/admin/hrms-geo/tracking/dashboard',
        queryParameters: day != null ? {'date': _dayKey(day)} : null,
      );
      final data = res.data?['data'];
      return {'success': true, 'data': data is Map ? Map<String, dynamic>.from(data) : {}};
    } catch (e) {
      return {'success': false, 'message': _msg(e), 'data': {}};
    }
  }

  /// Field employees out right now (last live point or punch-in), with task and status.
  /// GET /admin/hrms-geo/tracking/live
  Future<Map<String, dynamic>> getLive() async {
    try {
      final res = await _api.request<Map<String, dynamic>>('/admin/hrms-geo/tracking/live');
      final list = res.data?['data'];
      return {
        'success': true,
        'data': list is List ? List<Map<String, dynamic>>.from(list.map((e) => Map<String, dynamic>.from(e as Map))) : <Map<String, dynamic>>[],
        'liveWindowSeconds': res.data?['liveWindowSeconds'],
      };
    } catch (e) {
      return {'success': false, 'message': _msg(e), 'data': <Map<String, dynamic>>[]};
    }
  }

  /// GEO general settings (tracking on/off, interval, retention).
  /// GET /admin/hrms-geo/settings/general-settings
  Future<Map<String, dynamic>> getGeneralSettings() async {
    try {
      final res = await _api.request<Map<String, dynamic>>('/admin/hrms-geo/settings/general-settings');
      final data = res.data?['data'];
      return {'success': true, 'data': data is Map ? Map<String, dynamic>.from(data) : {}};
    } catch (e) {
      return {'success': false, 'message': _msg(e), 'data': {}};
    }
  }

  /// Update GEO general settings. Only the keys passed are changed.
  /// PUT /admin/hrms-geo/settings/general-settings
  Future<Map<String, dynamic>> updateGeneralSettings({
    bool? liveTracking,
    bool? timelineTracking,
    int? liveTrackingInterval,
    int? dataStoreDays,
  }) async {
    try {
      final body = <String, dynamic>{};
      if (liveTracking != null) body['liveTracking'] = liveTracking;
      if (timelineTracking != null) body['timelineTracking'] = timelineTracking;
      if (liveTrackingInterval != null) body['liveTrackingInterval'] = liveTrackingInterval;
      if (dataStoreDays != null) body['dataStoreDays'] = dataStoreDays;
      final res = await _api.request<Map<String, dynamic>>(
        '/admin/hrms-geo/settings/general-settings',
        method: 'PUT',
        data: body,
      );
      final data = res.data?['data'];
      return {'success': res.data?['success'] != false, 'data': data is Map ? Map<String, dynamic>.from(data) : {}, 'message': res.data?['message']};
    } catch (e) {
      return {'success': false, 'message': _msg(e)};
    }
  }

  /// Travel-allowance claims (optionally a day / one staff).
  /// GET /admin/hrms-geo/travel-allowance?date=&staffId=
  Future<Map<String, dynamic>> getTravelAllowances({DateTime? day, String? staffId}) async {
    try {
      final q = <String, dynamic>{};
      if (day != null) q['date'] = _dayKey(day);
      if (staffId != null) q['staffId'] = staffId;
      final res = await _api.request<Map<String, dynamic>>(
        '/admin/hrms-geo/travel-allowance',
        queryParameters: q.isEmpty ? null : q,
      );
      final list = res.data?['data'];
      return {
        'success': true,
        'data': list is List ? List<Map<String, dynamic>>.from(list.map((e) => Map<String, dynamic>.from(e as Map))) : <Map<String, dynamic>>[],
      };
    } catch (e) {
      return {'success': false, 'message': _msg(e), 'data': <Map<String, dynamic>>[]};
    }
  }

  /// Approve a travel-allowance claim, paid through payroll in [payrollMonth] (e.g. "2026-10").
  /// POST /admin/hrms-geo/travel-allowance/approve
  Future<Map<String, dynamic>> approveTravelAllowance({
    required String staffId,
    required String date, // yyyy-MM-dd as returned by the list
    required String payrollMonth,
  }) async {
    try {
      final res = await _api.request<Map<String, dynamic>>(
        '/admin/hrms-geo/travel-allowance/approve',
        method: 'POST',
        queryParameters: {'staffId': staffId, 'date': date},
        data: {'paymentRoute': 'Payroll', 'payrollMonth': payrollMonth},
      );
      return {'success': res.data?['success'] != false, 'message': res.data?['message']};
    } catch (e) {
      return {'success': false, 'message': _msg(e)};
    }
  }

  /// One staff member's field day route (flags + legs + trail), same shape as the staff
  /// day-route. GET /admin/hrms-geo/day-route/:staffId?date=YYYY-MM-DD
  Future<Map<String, dynamic>> getStaffDayRoute(String staffId, DateTime day) async {
    final res = await _api.request<Map<String, dynamic>>(
      '/admin/hrms-geo/day-route/$staffId',
      queryParameters: {'date': _dayKey(day)},
    );
    final data = res.data?['data'];
    if (data is Map) return Map<String, dynamic>.from(data);
    throw Exception('Could not load this employee\'s route.');
  }
}
