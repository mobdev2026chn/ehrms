// lib/services/admin_staff_service.dart
import 'dart:convert';
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
      return {'success': false, 'message': e.toString(), 'data': {'staff': []}};
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
      return {'success': false, 'message': e.toString(), 'data': {}};
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
      return {'success': false, 'message': e.toString(), 'data': {}};
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
      return {'success': false, 'message': e.toString()};
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
      return {'success': false, 'message': e.toString()};
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
      return {'success': false, 'message': e.toString(), 'data': {'staff': {}}};
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
      return {'success': false, 'message': e.toString()};
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
      return {'success': false, 'message': e.toString()};
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
      return {'success': false, 'message': e.toString()};
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
