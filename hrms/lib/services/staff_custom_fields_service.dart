import 'package:dio/dio.dart';

import '../config/constants.dart';
import 'api_client.dart';
import 'web_hrms_api_dio.dart';

/// Loads `/settings/staff-custom-fields` (same contract as web HRMS profile).
/// When [AppConstants.baseUrl] and [AppConstants.webBaseUrl] differ, tries web first
/// (JWT via [webHrmsApiDio]), then the main app API — same idea as payroll/salary.
class StaffCustomFieldsService {
  StaffCustomFieldsService({ApiClient? apiClient})
      : _api = apiClient ?? ApiClient();

  final ApiClient _api;

  static bool _hostsSame() {
    final a = AppConstants.baseUrl.replaceAll(RegExp(r'/+$'), '');
    final b = AppConstants.webBaseUrl.replaceAll(RegExp(r'/+$'), '');
    return a == b;
  }

  /// Treats a field as active only when its flag is an affirmative value.
  /// Accepts bool `true`, `"true"`, `1`, `"1"` (different JSON sources serialize
  /// the toggle differently); everything else (false/0/null/missing) is inactive
  /// so deactivated fields never reach the profile UI.
  static bool _isFieldActive(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value == 1;
    if (value is String) {
      final v = value.trim().toLowerCase();
      return v == 'true' || v == '1';
    }
    return false;
  }

  static String _normalizeToken(String? token) {
    if (token == null) return '';
    var t = token.trim();
    if (t.startsWith('"') && t.endsWith('"')) {
      t = t.replaceAll('"', '');
    }
    return t;
  }

  /// Active fields only (`isActive == true`), sorted by `order` then `label`.
  Future<List<Map<String, dynamic>>> fetchActiveStaffCustomFields({
    required String token,
  }) async {
    final t = _normalizeToken(token);
    if (t.isEmpty) return [];

    Future<List<Map<String, dynamic>>> fromDio(Dio dio) async {
      try {
        final response = await dio.get<Map<String, dynamic>>(
          '/settings/staff-custom-fields',
        );
        final body = response.data;
        if (body == null || body['success'] != true) return [];
        final data = body['data'];
        if (data is! Map) return [];
        final raw = data['fields'];
        if (raw is! List) return [];
        final out = <Map<String, dynamic>>[];
        for (final e in raw) {
          if (e is! Map) continue;
          final m = Map<String, dynamic>.from(e);
          if (!_isFieldActive(m['isActive'])) continue;
          out.add(m);
        }
        out.sort((a, b) {
          final ao = (a['order'] as num?)?.toInt() ?? 0;
          final bo = (b['order'] as num?)?.toInt() ?? 0;
          final c = ao.compareTo(bo);
          if (c != 0) return c;
          final al = (a['label'] ?? a['name'] ?? '').toString();
          final bl = (b['label'] ?? b['name'] ?? '').toString();
          return al.compareTo(bl);
        });
        return out;
      } on DioException {
        return [];
      } catch (_) {
        return [];
      }
    }

    _api.setAuthToken(t);
    if (_hostsSame()) {
      return fromDio(_api.dio);
    }
    final web = await fromDio(webHrmsApiDio());
    if (web.isNotEmpty) return web;
    return fromDio(_api.dio);
  }
}
