import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../utils/error_message_utils.dart';
import 'api_client.dart';

/// Admin announcements (HRMSbackend /api/admin/announcements). Admins only.
///
/// Routes (announcementRoute.ts):
///   GET    /admin/announcements                     ?status&audience&search&page&limit
///   POST   /admin/announcements                     create (no update route exists)
///   GET    /admin/announcements/:id
///   DELETE /admin/announcements/:id
///   POST   /admin/announcements/:id/engagements/:engagementId/reply   { message }
/// Staff for "Individual Staff" targeting come from GET /admin/staff (data.staff).
///
/// Every method returns `{success, message, ...}` and never throws.
class AdminAnnouncementService {
  AdminAnnouncementService._();
  static final AdminAnnouncementService instance = AdminAnnouncementService._();
  final ApiClient _api = ApiClient();

  /// Audiences offered when creating (same as the web form).
  static const audiences = ['All Staff', 'Individual Staff'];

  /// Status values the backend stores and filters on.
  static const statuses = ['Published', 'Scheduled', 'Draft', 'Expired'];

  String _msg(Object e, String fallback) {
    if (e is DioException) {
      return ErrorMessageUtils.messageFromDioException(e, fallback: fallback);
    }
    return ErrorMessageUtils.toUserFriendlyMessage(e);
  }

  static Map<String, dynamic> _map(dynamic v) =>
      v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

  static List<Map<String, dynamic>> _maps(dynamic v) =>
      v is List ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : <Map<String, dynamic>>[];

  /// One page of announcements with the backend's filters.
  /// Returns `{success, data: List<Map>, totalItems, totalPages, currentPage, message}`.
  Future<Map<String, dynamic>> fetchPage({
    String? status,
    String? audience,
    String? search,
    int page = 1,
    int limit = 10,
  }) async {
    try {
      final q = <String, dynamic>{'page': page, 'limit': limit};
      if (status != null && status.isNotEmpty && status != 'All') q['status'] = status;
      if (audience != null && audience.isNotEmpty) q['audience'] = audience;
      if (search != null && search.trim().isNotEmpty) q['search'] = search.trim();
      final res = await _api.request<dynamic>('/admin/announcements', queryParameters: q);
      final body = _map(res.data);
      if (body['success'] == false) {
        return {'success': false, 'message': body['message']?.toString() ?? 'Could not load announcements.', 'data': <Map<String, dynamic>>[]};
      }
      final data = _map(body['data']);
      final pg = _map(data['pagination']);
      return {
        'success': true,
        'data': _maps(data['announcements']),
        'totalItems': (pg['totalItems'] as num?)?.toInt() ?? 0,
        'totalPages': (pg['totalPages'] as num?)?.toInt() ?? 1,
        'currentPage': (pg['currentPage'] as num?)?.toInt() ?? page,
      };
    } catch (e) {
      return {'success': false, 'message': _msg(e, 'Could not load announcements.'), 'data': <Map<String, dynamic>>[]};
    }
  }

  /// First 100 announcements (every status). Kept for older callers.
  Future<Map<String, dynamic>> list() => fetchPage(limit: 100);

  /// One announcement with its engagements. GET /admin/announcements/:id
  Future<Map<String, dynamic>> getById(String id) async {
    try {
      final res = await _api.request<dynamic>('/admin/announcements/$id');
      final body = _map(res.data);
      final a = _map(_map(body['data'])['announcement']);
      if (body['success'] == false || a.isEmpty) {
        return {'success': false, 'message': body['message']?.toString() ?? 'Announcement not found.'};
      }
      return {'success': true, 'data': a};
    } catch (e) {
      return {'success': false, 'message': _msg(e, 'Could not load the announcement.')};
    }
  }

  /// Create an announcement. POST /admin/announcements
  ///
  /// [targetStaff] items are `{id, name, designation}` (backend maps `id` to `staffId`).
  /// [coverUrl] and subsection `image.url` may be `data:image/...;base64,` URLs - the backend
  /// uploads those to storage. [attachments] items are `{id, name, size, url}` with url a file data URL.
  Future<Map<String, dynamic>> create({
    required String title,
    required String subject,
    required String description,
    String from = '',
    String audience = 'All Staff',
    List<Map<String, dynamic>> targetStaff = const [],
    String? coverUrl,
    List<Map<String, dynamic>> attachments = const [],
    List<Map<String, dynamic>> subsections = const [],
    DateTime? publishDate,
    DateTime? expiryDate,
    bool isDraft = false,
  }) async {
    try {
      final res = await _api.request<dynamic>(
        '/admin/announcements',
        method: 'POST',
        data: {
          'title': title,
          'subject': subject,
          'description': description,
          'from': from,
          'audience': audience,
          'targetStaff': audience == 'Individual Staff' ? targetStaff : <Map<String, dynamic>>[],
          'coverUrl': coverUrl,
          'attachments': attachments,
          'subsections': subsections,
          'publishDate': publishDate == null ? null : _ymd(publishDate),
          'expiryDate': expiryDate == null ? null : _ymd(expiryDate),
          'isDraft': isDraft,
        },
      );
      final body = _map(res.data);
      return {
        'success': body['success'] != false,
        'message': body['message']?.toString(),
        'data': _map(_map(body['data'])['announcement']),
      };
    } catch (e) {
      return {'success': false, 'message': _msg(e, 'Could not save the announcement.')};
    }
  }

  /// Delete an announcement. DELETE /admin/announcements/:id
  Future<Map<String, dynamic>> delete(String id) async {
    try {
      final res = await _api.request<dynamic>('/admin/announcements/$id', method: 'DELETE');
      final body = _map(res.data);
      return {'success': body['success'] != false, 'message': body['message']?.toString()};
    } catch (e) {
      return {'success': false, 'message': _msg(e, 'Could not delete the announcement.')};
    }
  }

  /// HR / admin reply to a staff comment.
  /// POST /admin/announcements/:id/engagements/:engagementId/reply  { message }
  /// Returns the updated announcement in `data`.
  Future<Map<String, dynamic>> reply(String id, String engagementId, String message) async {
    try {
      final res = await _api.request<dynamic>(
        '/admin/announcements/$id/engagements/$engagementId/reply',
        method: 'POST',
        data: {'message': message},
      );
      final body = _map(res.data);
      return {
        'success': body['success'] != false,
        'message': body['message']?.toString(),
        'data': _map(_map(body['data'])['announcement']),
      };
    } catch (e) {
      return {'success': false, 'message': _msg(e, 'Could not send the response.')};
    }
  }

  /// Staff the admin can target. GET /admin/staff -> data.staff
  /// Returns `data` as `[{id, name, designation}]`, the shape the create payload takes.
  Future<Map<String, dynamic>> staffOptions() async {
    try {
      final res = await _api.request<dynamic>('/admin/staff');
      final body = _map(res.data);
      if (body['success'] == false) {
        return {'success': false, 'message': body['message']?.toString() ?? 'Could not load staff.', 'data': <Map<String, dynamic>>[]};
      }
      final staff = _maps(_map(body['data'])['staff']);
      final out = <Map<String, dynamic>>[];
      for (final s in staff) {
        final id = (s['_id'] ?? s['id'] ?? '').toString();
        if (id.isEmpty) continue;
        final full = '${s['firstName'] ?? ''} ${s['lastName'] ?? ''}'.trim();
        final name = (s['name']?.toString().trim().isNotEmpty == true) ? s['name'].toString().trim() : (full.isNotEmpty ? full : 'Staff Member');
        final designation = (s['designation'] ?? s['department'] ?? '').toString();
        out.add({'id': id, 'name': name, 'designation': designation, 'employeeId': (s['employeeId'] ?? '').toString()});
      }
      return {'success': true, 'data': out};
    } catch (e) {
      return {'success': false, 'message': _msg(e, 'Could not load staff.'), 'data': <Map<String, dynamic>>[]};
    }
  }

  /// `data:image/<ext>;base64,...` - the form the backend uploads for covers / subsection images.
  static String imageDataUrl(Uint8List bytes, String fileName) {
    final ext = fileName.contains('.') ? fileName.split('.').last.toLowerCase() : 'jpeg';
    final mime = switch (ext) {
      'png' => 'png',
      'gif' => 'gif',
      'webp' => 'webp',
      _ => 'jpeg',
    };
    return 'data:image/$mime;base64,${base64Encode(bytes)}';
  }

  /// Attachment file as a `data:<mime>;base64,` URL; the backend uploads it to storage.
  static String fileDataUrl(Uint8List bytes, String fileName) {
    final ext = fileName.contains('.') ? fileName.split('.').last.toLowerCase() : '';
    final mime = switch (ext) {
      'pdf' => 'application/pdf',
      'png' => 'image/png',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      'jpg' || 'jpeg' => 'image/jpeg',
      _ => 'application/octet-stream',
    };
    return 'data:$mime;base64,${base64Encode(bytes)}';
  }

  static String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
