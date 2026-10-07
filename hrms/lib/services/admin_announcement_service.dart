import 'package:dio/dio.dart';
import 'api_client.dart';

/// Admin announcements (HRMSbackend /api/admin/announcements). Admins only.
/// Create / list / delete; staff see them through the staff announcements module.
class AdminAnnouncementService {
  AdminAnnouncementService._();
  static final AdminAnnouncementService instance = AdminAnnouncementService._();
  final ApiClient _api = ApiClient();

  static const audiences = ['All Staff', 'All Employees'];

  String? _msg(Object e) {
    if (e is DioException) {
      final d = e.response?.data;
      if (d is Map && d['message'] != null) return d['message'].toString();
      return e.message;
    }
    return e.toString();
  }

  /// All announcements for the company (every status). GET /admin/announcements
  Future<Map<String, dynamic>> list() async {
    try {
      final res = await _api.request<Map<String, dynamic>>(
        '/admin/announcements',
        queryParameters: {'limit': 100},
      );
      final data = res.data?['data'];
      final list = data is Map ? data['announcements'] : data;
      return {
        'success': true,
        'data': list is List ? List<Map<String, dynamic>>.from(list.map((e) => Map<String, dynamic>.from(e as Map))) : <Map<String, dynamic>>[],
      };
    } catch (e) {
      return {'success': false, 'message': _msg(e), 'data': <Map<String, dynamic>>[]};
    }
  }

  /// Create an announcement. POST /admin/announcements
  Future<Map<String, dynamic>> create({
    required String title,
    required String subject,
    required String description,
    String from = '',
    String audience = 'All Staff',
    DateTime? publishDate,
    DateTime? expiryDate,
    bool isDraft = false,
  }) async {
    try {
      final res = await _api.request<Map<String, dynamic>>(
        '/admin/announcements',
        method: 'POST',
        data: {
          'title': title,
          'subject': subject,
          'description': description,
          'from': from,
          'audience': audience,
          'targetStaff': [],
          'attachments': [],
          'subsections': [],
          'publishDate': publishDate?.toIso8601String(),
          'expiryDate': expiryDate?.toIso8601String(),
          'isDraft': isDraft,
        },
      );
      return {'success': res.data?['success'] != false, 'message': res.data?['message']};
    } catch (e) {
      return {'success': false, 'message': _msg(e)};
    }
  }

  /// Delete an announcement. DELETE /admin/announcements/:id
  Future<Map<String, dynamic>> delete(String id) async {
    try {
      final res = await _api.request<Map<String, dynamic>>('/admin/announcements/$id', method: 'DELETE');
      return {'success': res.data?['success'] != false, 'message': res.data?['message']};
    } catch (e) {
      return {'success': false, 'message': _msg(e)};
    }
  }
}
