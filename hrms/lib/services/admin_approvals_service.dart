// lib/services/admin_approvals_service.dart
import 'api_client.dart';

class AdminApprovalsService {
  static final AdminApprovalsService _instance = AdminApprovalsService._internal();
  factory AdminApprovalsService() => _instance;
  AdminApprovalsService._internal();

  final ApiClient _api = ApiClient();

  /// Generic helper to fetch approvals list for any type
  /// types: 'leave', 'permission', 'punch', 'fine', 'expense', 'payslip'
  Future<Map<String, dynamic>> getApprovalsList({
    required String type,
    String? status,
    String? search,
    String? startDate,
    String? endDate,
  }) async {
    try {
      final queryParams = <String, dynamic>{};
      if (status != null && status != 'All') queryParams['status'] = status;
      if (search != null && search.isNotEmpty) queryParams['search'] = search;
      if (startDate != null && startDate.isNotEmpty) queryParams['startDate'] = startDate;
      if (endDate != null && endDate.isNotEmpty) queryParams['endDate'] = endDate;

      final res = await _api.request(
        '/admin/approvals/$type',
        method: 'GET',
        queryParameters: queryParams,
      );

      final data = res.data;
      if (data is Map<String, dynamic>) {
        return data;
      }
      return {'success': true, 'data': {'requests': []}};
    } catch (e) {
      return {'success': false, 'message': e.toString(), 'data': {'requests': []}};
    }
  }

  /// Approve request (POST /admin/approvals/:type/:id/approve)
  Future<Map<String, dynamic>> approveRequest({
    required String type,
    required String requestId,
    String? remarks,
  }) async {
    try {
      final res = await _api.request(
        '/admin/approvals/$type/$requestId/approve',
        method: 'POST',
        data: {'remarks': remarks ?? 'Approved by admin'},
      );
      final data = res.data;
      if (data is Map<String, dynamic>) {
        return data;
      }
      return {'success': true};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  /// Reject request (POST /admin/approvals/:type/:id/reject)
  Future<Map<String, dynamic>> rejectRequest({
    required String type,
    required String requestId,
    required String reason,
    String? remarks,
  }) async {
    try {
      final res = await _api.request(
        '/admin/approvals/$type/$requestId/reject',
        method: 'POST',
        data: {
          'reason': reason,
          'rejectionReason': reason,
          'remarks': remarks ?? reason,
        },
      );
      final data = res.data;
      if (data is Map<String, dynamic>) {
        return data;
      }
      return {'success': true};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }
}
