// lib/services/admin_settings_service.dart
//
// Admin "Staff > Settings" APIs (HRMSbackend). Mirrors the web admin:
//   /admin/settings/attendance/*     attendance, holiday, leave, shift, weekly-off,
//                                    break, overtime, permission templates + branches
//   /admin/staff/payable-days        salary settings (payable days, components,
//   /admin/staff/salary-components   templates, salary details access)
//   /admin/staff/salary-templates
//   /admin/staff/salary-access
//   /admin/company                   company master (business settings)
//   /admin/settings/module-access    module access (admin only)
//   /admin/settings/shift-roster/*   shift roster
//   /admin/settings/reports/*        Excel report downloads
//
// Every method throws [SettingsApiException] carrying the backend's message on
// failure, so screens only update state after a call succeeds.

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../utils/error_message_utils.dart';
import 'api_client.dart';

class SettingsApiException implements Exception {
  SettingsApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// User-facing text for any error thrown by [AdminSettingsService].
String settingsErrorText(Object e) {
  if (e is SettingsApiException) return e.message;
  return ErrorMessageUtils.toUserFriendlyMessage(e);
}

/// One kind of attendance template under `/admin/settings/attendance/<segment>`.
class AttendanceTemplateKind {
  const AttendanceTemplateKind(this.segment, this.title, this.singular);
  final String segment;
  final String title;
  final String singular;

  String get basePath => '/admin/settings/attendance/$segment';

  static const attendance = AttendanceTemplateKind('attendance-templates', 'Attendance Templates', 'Attendance Template');
  static const holiday = AttendanceTemplateKind('holiday-templates', 'Holiday Templates', 'Holiday Template');
  static const leave = AttendanceTemplateKind('leave-templates', 'Leave Templates', 'Leave Template');
  static const shift = AttendanceTemplateKind('shifts', 'Shift Templates', 'Shift Template');
  static const weeklyOff = AttendanceTemplateKind('weekly-off-templates', 'Weekly Off Templates', 'Weekly Off Template');
  static const breaks = AttendanceTemplateKind('break-templates', 'Break Templates', 'Break Template');
  static const overtime = AttendanceTemplateKind('overtime-templates', 'Overtime Templates', 'Overtime Template');
  static const permission = AttendanceTemplateKind('permission-templates', 'Permission Templates', 'Permission Template');

  static const all = [attendance, holiday, leave, shift, weeklyOff, breaks, overtime, permission];
}

/// A downloaded report file.
class ReportFile {
  ReportFile(this.bytes, this.fileName);
  final Uint8List bytes;
  final String fileName;
}

class AdminSettingsService {
  AdminSettingsService._();
  static final AdminSettingsService instance = AdminSettingsService._();
  factory AdminSettingsService() => instance;

  final ApiClient _api = ApiClient();

  static const salaryTemplatesPath = '/admin/staff/salary-templates';

  // ---------------------------------------------------------------- helpers

  String _messageOf(Object e) {
    if (e is DioException) {
      dynamic d = e.response?.data;
      if (d is List<int>) {
        try {
          d = jsonDecode(utf8.decode(d));
        } on FormatException {
          d = null; // Non-JSON body (binary); fall through to the generic message.
        }
      } else if (d is String) {
        try {
          d = jsonDecode(d);
        } on FormatException {
          d = null; // Plain-text body; fall through to the generic message.
        }
      }
      if (d is Map && d['message'] != null && d['message'].toString().trim().isNotEmpty) {
        return d['message'].toString();
      }
      return ErrorMessageUtils.toUserFriendlyMessage(e);
    }
    return ErrorMessageUtils.toUserFriendlyMessage(e);
  }

  Future<Map<String, dynamic>> _call(
    String path, {
    String method = 'GET',
    dynamic data,
    Map<String, dynamic>? query,
  }) async {
    try {
      final res = await _api.request<dynamic>(path, method: method, data: data, queryParameters: query);
      final body = res.data;
      if (body is Map) {
        final map = Map<String, dynamic>.from(body);
        if (map['success'] == false) {
          throw SettingsApiException((map['message'] ?? 'Request failed').toString());
        }
        return map;
      }
      return <String, dynamic>{'success': true, 'data': body};
    } on SettingsApiException {
      rethrow;
    } catch (e) {
      throw SettingsApiException(_messageOf(e));
    }
  }

  static Map<String, dynamic> asMap(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

  static List<Map<String, dynamic>> asList(dynamic v) =>
      v is List ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : <Map<String, dynamic>>[];

  static String idOf(dynamic v) {
    if (v is Map) return (v['_id'] ?? v['id'] ?? '').toString();
    return v?.toString() ?? '';
  }

  /// Display name for a staff record (firstName/lastName or name).
  static String staffName(Map<String, dynamic> s) {
    final n = (s['name'] ?? '').toString().trim();
    if (n.isNotEmpty) return n;
    final full = '${s['firstName'] ?? ''} ${s['lastName'] ?? ''}'.trim();
    return full.isEmpty ? 'Unnamed' : full;
  }

  // ---------------------------------------------------- generic templates
  // Shared by every attendance template kind and by salary templates.

  Future<List<Map<String, dynamic>>> listTemplates(String basePath) async {
    final r = await _call(basePath);
    return asList(asMap(r['data'])['templates']);
  }

  Future<Map<String, dynamic>> getTemplate(String basePath, String id) async {
    final r = await _call('$basePath/$id');
    return asMap(asMap(r['data'])['template']);
  }

  Future<Map<String, dynamic>> createTemplate(String basePath, Map<String, dynamic> body) async {
    final r = await _call(basePath, method: 'POST', data: body);
    return asMap(asMap(r['data'])['template']);
  }

  Future<Map<String, dynamic>> updateTemplate(String basePath, String id, Map<String, dynamic> body) async {
    final r = await _call('$basePath/$id', method: 'PUT', data: body);
    return asMap(asMap(r['data'])['template']);
  }

  Future<void> deleteTemplate(String basePath, String id) async {
    await _call('$basePath/$id', method: 'DELETE');
  }

  /// Assigned and unassigned staff for a template: { assigned: [...], unassigned: [...] }.
  Future<({List<Map<String, dynamic>> assigned, List<Map<String, dynamic>> unassigned})> templateStaff(
      String basePath, String id) async {
    final r = await _call('$basePath/$id/staff');
    final d = asMap(r['data']);
    return (assigned: asList(d['assigned']), unassigned: asList(d['unassigned']));
  }

  Future<String?> assignStaff(String basePath, String id, List<String> staffIds) async {
    final r = await _call('$basePath/$id/assign', method: 'POST', data: {'staffIds': staffIds});
    return r['message']?.toString();
  }

  Future<String?> unassignStaff(String basePath, String id, List<String> staffIds) async {
    final r = await _call('$basePath/$id/unassign', method: 'POST', data: {'staffIds': staffIds});
    return r['message']?.toString();
  }

  // -------------------------------------------------------------- branches

  static const _branches = '/admin/settings/attendance/branches';

  Future<List<Map<String, dynamic>>> listBranches() async {
    final r = await _call(_branches);
    return asList(r['data']);
  }

  Future<Map<String, dynamic>> createBranch(Map<String, dynamic> body) async {
    final r = await _call(_branches, method: 'POST', data: body);
    return asMap(asMap(r['data'])['branch']);
  }

  Future<Map<String, dynamic>> updateBranch(String id, Map<String, dynamic> body) async {
    final r = await _call('$_branches/$id', method: 'PUT', data: body);
    return asMap(asMap(r['data'])['branch']);
  }

  Future<void> deleteBranch(String id) async {
    await _call('$_branches/$id', method: 'DELETE');
  }

  Future<Map<String, dynamic>> getBranchGeofence(String id) async {
    final r = await _call('$_branches/$id/geofence');
    return asMap(asMap(r['data'])['branch']);
  }

  Future<Map<String, dynamic>> updateBranchGeofence(
    String id, {
    required bool enabled,
    double? latitude,
    double? longitude,
    double? radius,
    List<Map<String, dynamic>>? locations,
  }) async {
    final r = await _call('$_branches/$id/geofence', method: 'PUT', data: {
      'geofence': {
        'enabled': enabled,
        'latitude': ?latitude,
        'longitude': ?longitude,
        'radius': ?radius,
        'locations': ?locations,
      },
      'geofenceStatus': enabled ? 'enable' : 'disable',
    });
    return asMap(asMap(r['data'])['branch']);
  }

  // ------------------------------------------------------- salary settings

  Future<List<Map<String, dynamic>>> listPayableDays() async {
    final r = await _call('/admin/staff/payable-days');
    return asList(asMap(r['data'])['templates']);
  }

  Future<void> createPayableDays({
    required String name,
    required String type,
    int? fixedDays,
    String status = 'Active',
  }) async {
    await _call('/admin/staff/payable-days', method: 'POST', data: {
      'name': name,
      'type': type,
      if (type == 'Fixed days') 'fixedDays': fixedDays,
      'status': status,
    });
  }

  Future<void> deletePayableDays(String id) async {
    await _call('/admin/staff/payable-days/$id', method: 'DELETE');
  }

  Future<List<Map<String, dynamic>>> listSalaryComponents() async {
    final r = await _call('/admin/staff/salary-components');
    return asList(asMap(r['data'])['components']);
  }

  Future<void> saveSalaryComponent({
    String? id,
    required String name,
    required String category,
    required String type,
    required num amount,
  }) async {
    final body = {'name': name, 'category': category, 'type': type, 'amount': amount};
    if (id == null) {
      await _call('/admin/staff/salary-components', method: 'POST', data: body);
    } else {
      await _call('/admin/staff/salary-components/$id', method: 'PUT', data: body);
    }
  }

  Future<void> deleteSalaryComponent(String id) async {
    await _call('/admin/staff/salary-components/$id', method: 'DELETE');
  }

  /// GET /admin/staff/salary-access?search=&department=
  Future<({List<Map<String, dynamic>> staff, int total, int granted})> listSalaryAccess({
    String? search,
    String? department,
  }) async {
    final r = await _call('/admin/staff/salary-access', query: {
      if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
      if (department != null && department.isNotEmpty && department != 'All') 'department': department,
    });
    final list = asList(r['data']);
    return (
      staff: list,
      total: (r['total'] as num?)?.toInt() ?? list.length,
      granted: (r['grantedCount'] as num?)?.toInt() ?? list.where((s) => s['salaryDetailsAccess'] == true).length,
    );
  }

  Future<String?> updateSalaryAccess(String staffId, bool access) async {
    final r = await _call('/admin/staff/salary-access/$staffId', method: 'PUT', data: {'salaryDetailsAccess': access});
    return r['message']?.toString();
  }

  // -------------------------------------------------------- company master

  Future<Map<String, dynamic>> getCompany() async {
    final r = await _call('/admin/company');
    return asMap(r['data']);
  }

  Future<Map<String, dynamic>> updateCompany(Map<String, dynamic> body) async {
    final r = await _call('/admin/company', method: 'PUT', data: body);
    return asMap(r['data']);
  }

  // --------------------------------------------------------- module access

  static const _moduleAccess = '/admin/settings/module-access';

  Future<List<Map<String, dynamic>>> listModuleAccessStaff() async {
    final r = await _call(_moduleAccess);
    return asList(asMap(r['data'])['staff']);
  }

  Future<Map<String, dynamic>> getStaffModuleAccess(String staffId) async {
    final r = await _call('$_moduleAccess/$staffId');
    return asMap(asMap(r['data'])['moduleAccess']);
  }

  Future<Map<String, dynamic>> saveStaffModuleAccess(
    String staffId, {
    required bool enabled,
    required List<Map<String, dynamic>> permissions,
  }) async {
    final r = await _call('$_moduleAccess/$staffId', method: 'PUT', data: {
      'enabled': enabled,
      'permissions': permissions,
    });
    return asMap(asMap(r['data'])['moduleAccess']);
  }

  Future<List<Map<String, dynamic>>> getModuleAccessTeam(String staffId) async {
    final r = await _call('$_moduleAccess/$staffId/team');
    return asList(asMap(r['data'])['team']);
  }

  Future<String?> updateModuleAccessProfile(String staffId, {String? designation, String? password}) async {
    final r = await _call('$_moduleAccess/$staffId/profile', method: 'PUT', data: {
      if (designation != null && designation.trim().isNotEmpty) 'designation': designation.trim(),
      if (password != null && password.isNotEmpty) 'password': password,
    });
    return r['message']?.toString();
  }

  // ---------------------------------------------------------- shift roster

  static const _roster = '/admin/settings/shift-roster';

  /// Every staff member of the company (GET /admin/staff -> data.staff).
  Future<List<Map<String, dynamic>>> listStaff() async {
    final r = await _call('/admin/staff');
    return asList(asMap(r['data'])['staff']);
  }

  Future<({List<Map<String, dynamic>> assignments, List<Map<String, dynamic>> overrides})> rosterData() async {
    final r = await _call('$_roster/data');
    final d = asMap(r['data']);
    return (assignments: asList(d['assignments']), overrides: asList(d['overrides']));
  }

  Future<String?> assignPermanentShift({
    required List<String> staffIds,
    required String shiftTemplateId,
    required String effectiveFrom,
  }) async {
    final r = await _call('$_roster/permanent', method: 'POST', data: {
      'employeeIds': staffIds,
      'shiftTemplateId': shiftTemplateId,
      'effectiveFrom': effectiveFrom,
    });
    return r['message']?.toString();
  }

  Future<String?> assignTemporaryShift({
    required List<String> staffIds,
    required String shiftTemplateId,
    String? weekOffTemplateId,
    required String effectiveFrom,
    required String effectiveTo,
    String? reason,
  }) async {
    final r = await _call('$_roster/temporary', method: 'POST', data: {
      'employeeIds': staffIds,
      'shiftTemplateId': shiftTemplateId,
      'weekOffTemplateId': ?weekOffTemplateId,
      'effectiveFrom': effectiveFrom,
      'effectiveTo': effectiveTo,
      if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
    });
    return r['message']?.toString();
  }

  /// overrideType: work_shift | weekly_off | holiday | leave | delete
  Future<String?> saveDailyOverride({
    required String staffId,
    required String date,
    required String overrideType,
    String? shiftTemplateId,
    String? reason,
  }) async {
    final r = await _call('$_roster/override', method: 'POST', data: {
      'staffId': staffId,
      'date': date,
      'overrideType': overrideType,
      'shiftTemplateId': ?shiftTemplateId,
      'reason': (reason == null || reason.trim().isEmpty) ? 'Manual adjustment' : reason.trim(),
    });
    return r['message']?.toString();
  }

  /// Resolved month for several staff: [{staffId, days: [CalendarDay]}].
  Future<List<Map<String, dynamic>>> monthSchedule({
    required List<String> staffIds,
    required int year,
    required int month,
  }) async {
    final r = await _call('$_roster/month-schedule', query: {
      'staffIds': staffIds.join(','),
      'year': year,
      'month': month,
    });
    return asList(asMap(r['data'])['staff']);
  }

  /// { weekOffDates: {staffId: [yyyy-MM-dd]}, weeklyOffDays: {...}, holidayDates: {...} }
  Future<Map<String, dynamic>> monthlyWeekOffs({required int year, required int month}) async {
    final r = await _call('$_roster/week-offs', query: {'year': year, 'month': month});
    return asMap(r['data']);
  }

  /// Read-only preview of a template for staff: { template: {...}, staff: [{staffId, name, employeeId, days}] }.
  Future<Map<String, dynamic>> shiftPreview({
    required List<String> staffIds,
    required String templateId,
    required String effectiveFrom,
    required int year,
    required int month,
  }) async {
    final r = await _call('$_roster/preview', query: {
      'staffIds': staffIds.join(','),
      'templateId': templateId,
      'effectiveFrom': effectiveFrom,
      'year': year,
      'month': month,
    });
    return asMap(r['data']);
  }

  // --------------------------------------------------------------- reports

  /// `GET /admin/settings/reports/<type>` returning an .xlsx file.
  Future<ReportFile> downloadReport(String type, Map<String, dynamic> params, {required String fallbackName}) async {
    try {
      final res = await _api.request<List<int>>(
        '/admin/settings/reports/$type',
        queryParameters: params,
        options: Options(responseType: ResponseType.bytes),
      );
      final bytes = Uint8List.fromList(res.data ?? const <int>[]);
      if (bytes.isEmpty) throw SettingsApiException('The report came back empty.');
      final contentType = res.headers.value('content-type') ?? '';
      if (contentType.contains('application/json')) {
        String msg = 'Could not generate the report.';
        try {
          final d = jsonDecode(utf8.decode(bytes));
          if (d is Map && d['message'] != null) msg = d['message'].toString();
        } on FormatException {
          // Keep the generic message when the JSON body cannot be parsed.
        }
        throw SettingsApiException(msg);
      }
      var name = fallbackName;
      final disp = res.headers.value('content-disposition') ?? '';
      final m = RegExp(r'filename="?([^";]+)"?').firstMatch(disp);
      if (m != null && m.group(1)!.trim().isNotEmpty) name = m.group(1)!.trim();
      return ReportFile(bytes, name);
    } on SettingsApiException {
      rethrow;
    } catch (e) {
      throw SettingsApiException(_messageOf(e));
    }
  }
}
