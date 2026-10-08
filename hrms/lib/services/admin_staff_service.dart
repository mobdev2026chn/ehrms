// lib/services/admin_staff_service.dart
import 'package:dio/dio.dart';
import 'api_client.dart';

class AdminStaffService {
  static final AdminStaffService _instance = AdminStaffService._internal();
  factory AdminStaffService() => _instance;
  AdminStaffService._internal();

  final ApiClient _api = ApiClient();

  /// Fetches the staff list for admin.
  Future<Map<String, dynamic>> getStaffList({
    String? search,
    String? status,
    String? department,
    String? branch,
  }) async {
    try {
      final response = await _api.request(
        '/admin/staff',
        method: 'GET',
      );

      final data = response.data;
      if (data is Map<String, dynamic>) {
        return data;
      }
      return {'success': true, 'data': {'staff': []}};
    } catch (e) {
      return {'success': false, 'message': _errorMessage(e, 'Request failed. Please try again.'), 'data': {'staff': []}};
    }
  }

  /// Fetches template setup configuration (branches, templates).
  Future<Map<String, dynamic>> getStaffSetup() async {
    try {
      final response = await _api.request(
        '/admin/staff/setup',
        method: 'GET',
      );
      final data = response.data;
      if (data is Map<String, dynamic>) {
        return data;
      }
      return {'success': true, 'data': {}};
    } catch (e) {
      return {'success': false, 'message': _errorMessage(e, 'Request failed. Please try again.'), 'data': {}};
    }
  }

  /// Fetches subscription plan and seat limit info.
  Future<Map<String, dynamic>> getAdminSubscription() async {
    try {
      final response = await _api.request(
        '/admin/staff/subscription',
        method: 'GET',
      );
      final data = response.data;
      if (data is Map<String, dynamic>) {
        return data;
      }
      return {'success': true, 'data': {}};
    } catch (e) {
      return {'success': false, 'message': _errorMessage(e, 'Request failed. Please try again.'), 'data': {}};
    }
  }

  /// Activates a staff member.
  Future<Map<String, dynamic>> activateStaff(String staffId) async {
    try {
      final response = await _api.request(
        '/admin/staff/$staffId/activate',
        method: 'PUT',
      );
      final data = response.data;
      if (data is Map<String, dynamic>) {
        return data;
      }
      return {'success': true};
    } catch (e) {
      return {'success': false, 'message': _errorMessage(e, 'Request failed. Please try again.')};
    }
  }

  /// Deactivates a staff member.
  Future<Map<String, dynamic>> deactivateStaff(String staffId) async {
    try {
      final response = await _api.request(
        '/admin/staff/$staffId/deactivate',
        method: 'PUT',
      );
      final data = response.data;
      if (data is Map<String, dynamic>) {
        return data;
      }
      return {'success': true};
    } catch (e) {
      return {'success': false, 'message': _errorMessage(e, 'Request failed. Please try again.')};
    }
  }

  /// Gets single staff detail.
  Future<Map<String, dynamic>> getStaffDetail(String staffId) async {
    try {
      final response = await _api.request(
        '/admin/staff/$staffId',
        method: 'GET',
      );
      final data = response.data;
      if (data is Map<String, dynamic>) {
        return data;
      }
      return {'success': true, 'data': {'staff': {}}};
    } catch (e) {
      return {'success': false, 'message': _errorMessage(e, 'Request failed. Please try again.'), 'data': {'staff': {}}};
    }
  }

  /// Creates a new staff member (POST /admin/staff)
  Future<Map<String, dynamic>> createStaff(Map<String, dynamic> staffData) async {
    try {
      final response = await _api.request(
        '/admin/staff',
        method: 'POST',
        data: staffData,
      );
      final data = response.data;
      if (data is Map<String, dynamic>) {
        return data;
      }
      return {'success': true, 'data': data};
    } catch (e) {
      return {'success': false, 'message': _errorMessage(e, 'Failed to create staff member.')};
    }
  }

  /// Updates existing staff member (PUT /admin/staff/:id)
  Future<Map<String, dynamic>> updateStaff(String staffId, Map<String, dynamic> staffData) async {
    try {
      final response = await _api.request(
        '/admin/staff/$staffId',
        method: 'PUT',
        data: staffData,
      );
      final data = response.data;
      if (data is Map<String, dynamic>) {
        return data;
      }
      return {'success': true, 'data': data};
    } catch (e) {
      return {'success': false, 'message': _errorMessage(e, 'Request failed. Please try again.')};
    }
  }

  /// Deletes a staff member (DELETE /admin/staff/:id)
  Future<Map<String, dynamic>> deleteStaff(String staffId) async {
    try {
      final response = await _api.request(
        '/admin/staff/$staffId',
        method: 'DELETE',
      );
      final data = response.data;
      if (data is Map<String, dynamic>) {
        return data;
      }
      return {'success': true};
    } catch (e) {
      return {'success': false, 'message': _errorMessage(e, 'Request failed. Please try again.')};
    }
  }

  /// Face registration of a staff member
  /// (GET /admin/face-recognition/:staffId → { enrolled, samples, enrolledAt }).
  Future<Map<String, dynamic>> getStaffFaceStatus(String staffId) async {
    try {
      final response = await _api.request(
        '/admin/face-recognition/$staffId',
        method: 'GET',
      );
      final data = response.data;
      if (data is Map) return Map<String, dynamic>.from(data);
      return {'success': false, 'message': 'Unexpected response'};
    } catch (e) {
      return {'success': false, 'message': _errorMessage(e, 'Could not read face registration.')};
    }
  }

  /// Removes a staff member's registered face so they register again on their
  /// next punch (DELETE /admin/face-recognition/:staffId → { reset, message }).
  Future<Map<String, dynamic>> resetStaffFace(String staffId) async {
    try {
      final response = await _api.request(
        '/admin/face-recognition/$staffId',
        method: 'DELETE',
      );
      final data = response.data;
      if (data is Map) return Map<String, dynamic>.from(data);
      return {'success': true};
    } catch (e) {
      return {'success': false, 'message': _errorMessage(e, 'Could not remove face registration.')};
    }
  }

  static String _errorMessage(Object e, String fallback) {
    if (e is DioException) {
      final body = e.response?.data;
      if (body is Map) {
        final msg = body['message'] ?? body['error'];
        if (msg != null && msg.toString().trim().isNotEmpty) return msg.toString();
      }
      if (body is String && body.trim().isNotEmpty && body.length < 300) return body;
      switch (e.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          return 'The server took too long to respond. Please try again.';
        case DioExceptionType.connectionError:
          return 'Could not reach the server. Check your connection and try again.';
        default:
          break;
      }
    }
    return fallback;
  }

  /// Branches of the company (GET /admin/settings/attendance/branches →
  /// { success, data: Branch[] }). Each branch carries `_id` and `branchName`.
  Future<Map<String, dynamic>> getBranches() async {
    try {
      final response = await _api.request(
        '/admin/settings/attendance/branches',
        method: 'GET',
      );
      final data = response.data;
      if (data is Map) {
        final map = Map<String, dynamic>.from(data);
        final list = map['data'];
        map['data'] = list is List ? list : <dynamic>[];
        return map;
      }
      return {'success': false, 'message': 'Unexpected response while loading branches.', 'data': <dynamic>[]};
    } catch (e) {
      return {
        'success': false,
        'message': _errorMessage(e, 'Could not load branches.'),
        'data': <dynamic>[],
      };
    }
  }

  /// Reporting managers offerable for a designation
  /// (GET /admin/staff/reporting-managers?designation=&excludeId= →
  /// { success, data: { designation, reportsTo: string[], defaultOption, options: string[] } }).
  /// `options` are the literal strings to store on `reportingManager`.
  Future<Map<String, dynamic>> getReportingManagers({String? designation, String? excludeId}) async {
    try {
      final query = <String, dynamic>{};
      if (designation != null && designation.isNotEmpty) query['designation'] = designation;
      if (excludeId != null && excludeId.isNotEmpty) query['excludeId'] = excludeId;
      final response = await _api.request(
        '/admin/staff/reporting-managers',
        method: 'GET',
        queryParameters: query.isEmpty ? null : query,
      );
      final data = response.data;
      if (data is Map) return Map<String, dynamic>.from(data);
      return {'success': false, 'message': 'Unexpected response while loading reporting managers.'};
    } catch (e) {
      return {'success': false, 'message': _errorMessage(e, 'Could not load reporting managers.')};
    }
  }

  /// Bulk import of staff parsed from a spreadsheet (POST /admin/staff/import).
  /// Body: { rows: [...], defaultBranch?: branchId }.
  /// Response data: { totalRows, imported, failed, weekOffAssigned, seatsRemaining,
  /// importedStaffIds, failures: [{row, employeeId, reason}], warnings: [{row, employeeId, staffId, reason}] }.
  Future<Map<String, dynamic>> importStaff({
    required List<Map<String, dynamic>> rows,
    String? defaultBranch,
  }) async {
    try {
      final body = <String, dynamic>{'rows': rows};
      if (defaultBranch != null && defaultBranch.isNotEmpty) body['defaultBranch'] = defaultBranch;
      final response = await _api.request(
        '/admin/staff/import',
        method: 'POST',
        data: body,
      );
      final data = response.data;
      if (data is Map) return Map<String, dynamic>.from(data);
      return {'success': false, 'message': 'Unexpected response from the import.'};
    } catch (e) {
      return {'success': false, 'message': _errorMessage(e, 'Failed to import staff members.')};
    }
  }

  /// Fetches next available employee ID (GET /admin/staff/next-employee-id)
  Future<String?> getNextEmployeeId() async {
    try {
      final response = await _api.request(
        '/admin/staff/next-employee-id',
        method: 'GET',
      );
      final data = response.data;
      if (data is Map && data['success'] == true) {
        return (data['data']?['employeeId'] ?? data['employeeId'])?.toString();
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
