// Admin "Celebration" against HRMSbackend's celebration module - the same APIs the web uses:
//   /admin/celebration/*  (routes/admin/celebrationRoute.ts,
//                          controllers/admin/celebration/celebrationController.ts)
// Every call throws an Exception carrying the server's message on failure.

import 'package:dio/dio.dart';

import 'api_client.dart';

/// 'birthday' | 'anniversary'
typedef CelebrationKind = String;

/// 'today' | 'week' | 'month' | 'all'
typedef CelebrationRange = String;

const List<String> kCelebrationKinds = ['birthday', 'anniversary'];
const List<String> kCelebrationRanges = ['today', 'week', 'month', 'all'];

String _str(dynamic v) => v == null ? '' : v.toString();
int _int(dynamic v) => v is num ? v.toInt() : int.tryParse(_str(v)) ?? 0;

class CelebrationTemplate {
  CelebrationTemplate({
    required this.id,
    required this.name,
    required this.kind,
    required this.subject,
    required this.message,
    required this.isDefault,
    required this.isSystem,
  });

  final String id;
  final String name;
  final CelebrationKind kind;
  final String subject;
  final String message;
  final bool isDefault;
  final bool isSystem;

  factory CelebrationTemplate.fromJson(Map<String, dynamic> j) => CelebrationTemplate(
        id: _str(j['_id']),
        name: _str(j['name']),
        kind: _str(j['kind']),
        subject: _str(j['subject']),
        message: _str(j['message']),
        isDefault: j['isDefault'] == true,
        isSystem: j['isSystem'] == true,
      );
}

/// One person's next occasion, derived server-side from the staff record.
class CelebrationEntry {
  CelebrationEntry({
    required this.id,
    required this.staffId,
    required this.staffName,
    required this.employeeId,
    required this.department,
    required this.designation,
    required this.kind,
    required this.date,
    required this.daysAway,
    required this.status,
    this.yearsOfService,
    this.profilePic,
  });

  final String id;
  final String staffId;
  final String staffName;
  final String employeeId;
  final String department;
  final String designation;
  final CelebrationKind kind;

  /// Next occurrence at midnight UTC.
  final DateTime? date;
  final int daysAway;
  final int? yearsOfService;

  /// 'not-sent' | 'scheduled' | 'sent'
  final String status;
  final String? profilePic;

  factory CelebrationEntry.fromJson(Map<String, dynamic> j) => CelebrationEntry(
        id: _str(j['id']),
        staffId: _str(j['staffId']),
        staffName: _str(j['staffName']),
        employeeId: _str(j['employeeId']),
        department: _str(j['department']),
        designation: _str(j['designation']),
        kind: _str(j['kind']),
        date: DateTime.tryParse(_str(j['date']))?.toUtc(),
        daysAway: _int(j['daysAway']),
        yearsOfService: j['yearsOfService'] == null ? null : _int(j['yearsOfService']),
        status: _str(j['status']).isEmpty ? 'not-sent' : _str(j['status']),
        profilePic: j['profilePic'] == null || _str(j['profilePic']).isEmpty ? null : _str(j['profilePic']),
      );
}

class CelebrationPage {
  CelebrationPage({
    required this.items,
    required this.total,
    required this.page,
    required this.limit,
    required this.pages,
    required this.counts,
  });

  final List<CelebrationEntry> items;
  final int total;
  final int page;
  final int limit;
  final int pages;

  /// Count per range ('today' | 'week' | 'month' | 'all'), ignoring the selected range.
  final Map<String, int> counts;
}

class CelebrationSummary {
  CelebrationSummary({
    required this.todayCount,
    required this.birthdaysThisMonth,
    required this.anniversariesThisMonth,
    required this.templateCount,
    required this.defaultCount,
    required this.companyName,
  });

  final int todayCount;
  final int birthdaysThisMonth;
  final int anniversariesThisMonth;
  final int templateCount;
  final int defaultCount;

  /// What {{company_name}} resolves to.
  final String companyName;

  factory CelebrationSummary.fromJson(Map<String, dynamic> j) => CelebrationSummary(
        todayCount: _int(j['todayCount']),
        birthdaysThisMonth: _int(j['birthdaysThisMonth']),
        anniversariesThisMonth: _int(j['anniversariesThisMonth']),
        templateCount: _int(j['templateCount']),
        defaultCount: _int(j['defaultCount']),
        companyName: _str(j['companyName']),
      );
}

class AutomationSetting {
  const AutomationSetting({
    required this.enabled,
    required this.templateId,
    required this.sendTime,
    required this.notifyTeam,
  });

  final bool enabled;

  /// Null means "whichever template is default".
  final String? templateId;

  /// 24h "HH:MM".
  final String sendTime;
  final bool notifyTeam;

  factory AutomationSetting.fromJson(dynamic raw, String fallbackTime) {
    final j = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    final t = _str(j['templateId']);
    return AutomationSetting(
      enabled: j['enabled'] == true,
      templateId: t.isEmpty ? null : t,
      sendTime: _str(j['sendTime']).isEmpty ? fallbackTime : _str(j['sendTime']),
      notifyTeam: j['notifyTeam'] != false,
    );
  }
}

class CelebrationSettings {
  CelebrationSettings({required this.birthday, required this.anniversary});

  final AutomationSetting birthday;
  final AutomationSetting anniversary;

  AutomationSetting of(CelebrationKind kind) => kind == 'anniversary' ? anniversary : birthday;

  factory CelebrationSettings.fromJson(Map<String, dynamic> j) => CelebrationSettings(
        birthday: AutomationSetting.fromJson(j['birthday'], '09:00'),
        anniversary: AutomationSetting.fromJson(j['anniversary'], '09:30'),
      );
}

class AdminCelebrationService {
  final ApiClient _api = ApiClient();

  static const String _base = '/admin/celebration';

  /// Unwraps `{success, data, message}` and returns the whole body.
  static Map<String, dynamic> _body(Response<dynamic> res) {
    final body = res.data;
    if (body is Map && body['success'] == true) return Map<String, dynamic>.from(body);
    throw Exception(body is Map ? (body['message'] ?? 'Request failed') : 'Request failed');
  }

  static Exception _error(Object e, String fallback) {
    if (e is DioException) {
      final body = e.response?.data;
      final msg = body is Map ? body['message']?.toString() : null;
      if (msg != null && msg.isNotEmpty) return Exception(msg);
      if (e.response == null) return Exception('$fallback. Please check your connection.');
      return Exception(fallback);
    }
    if (e is Exception) return e;
    return Exception(fallback);
  }

  Future<Map<String, dynamic>> _call(
    String method,
    String path,
    String fallback, {
    Map<String, dynamic>? body,
    Map<String, dynamic>? query,
  }) async {
    try {
      return _body(await _api.request<dynamic>(
        '$_base$path',
        method: method,
        data: body,
        queryParameters: query,
      ));
    } catch (e) {
      throw _error(e, fallback);
    }
  }

  static Map<String, dynamic> _map(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

  static List<Map<String, dynamic>> _list(dynamic v) =>
      v is List ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : <Map<String, dynamic>>[];

  /// GET /list?kind=&range=&search=&page=&limit=
  Future<CelebrationPage> list({
    required CelebrationKind kind,
    required CelebrationRange range,
    String search = '',
    int page = 1,
    int limit = 24,
  }) async {
    final b = await _call('GET', '/list', 'Could not load celebrations', query: {
      'kind': kind,
      'range': range,
      if (search.trim().isNotEmpty) 'search': search.trim(),
      'page': page,
      'limit': limit,
    });
    final meta = _map(b['meta']);
    final counts = _map(meta['counts']);
    final items = _list(b['data']).map(CelebrationEntry.fromJson).toList();
    return CelebrationPage(
      items: items,
      total: _int(meta['total']),
      page: _int(meta['page']) == 0 ? page : _int(meta['page']),
      limit: _int(meta['limit']) == 0 ? limit : _int(meta['limit']),
      pages: _int(meta['pages']) < 1 ? 1 : _int(meta['pages']),
      counts: {for (final r in kCelebrationRanges) r: _int(counts[r])},
    );
  }

  /// GET /summary
  Future<CelebrationSummary> summary() async =>
      CelebrationSummary.fromJson(_map((await _call('GET', '/summary', 'Could not load the summary'))['data']));

  /// GET /templates (optionally ?kind=)
  Future<List<CelebrationTemplate>> templates({CelebrationKind? kind}) async {
    final b = await _call('GET', '/templates', 'Could not load templates', query: {if (kind != null) 'kind': kind});
    return _list(b['data']).map(CelebrationTemplate.fromJson).toList();
  }

  /// POST /templates. Returns the server's message.
  Future<String> createTemplate({
    required String name,
    required CelebrationKind kind,
    required String subject,
    required String message,
    required bool isDefault,
  }) async {
    final b = await _call('POST', '/templates', 'Could not save the template', body: {
      'name': name,
      'kind': kind,
      'subject': subject,
      'message': message,
      'isDefault': isDefault,
    });
    return _str(b['message']).isEmpty ? 'Template created' : _str(b['message']);
  }

  /// PUT /templates/:id. `kind` is not updatable server-side.
  Future<String> updateTemplate(
    String id, {
    required String name,
    required String subject,
    required String message,
    required bool isDefault,
  }) async {
    final b = await _call('PUT', '/templates/$id', 'Could not save the template', body: {
      'name': name,
      'subject': subject,
      'message': message,
      'isDefault': isDefault,
    });
    return _str(b['message']).isEmpty ? 'Template updated' : _str(b['message']);
  }

  /// POST /templates/:id/duplicate
  Future<String> duplicateTemplate(String id) async {
    final b = await _call('POST', '/templates/$id/duplicate', 'Could not duplicate the template');
    return _str(b['message']).isEmpty ? 'Template duplicated' : _str(b['message']);
  }

  /// PATCH /templates/:id/default
  Future<String> setDefaultTemplate(String id) async {
    final b = await _call('PATCH', '/templates/$id/default', 'Could not set the default');
    return _str(b['message']).isEmpty ? 'Default updated' : _str(b['message']);
  }

  /// DELETE /templates/:id
  Future<String> deleteTemplate(String id) async {
    final b = await _call('DELETE', '/templates/$id', 'Could not delete the template');
    return _str(b['message']).isEmpty ? 'Template deleted' : _str(b['message']);
  }

  /// GET /settings (upserted server-side, never empty).
  Future<CelebrationSettings> settings() async =>
      CelebrationSettings.fromJson(_map((await _call('GET', '/settings', 'Could not load automation settings'))['data']));

  /// PUT /settings with `{ <kind>: { enabled?, templateId?, sendTime?, notifyTeam? } }`.
  Future<CelebrationSettings> updateSettings(CelebrationKind kind, Map<String, dynamic> patch) async {
    final b = await _call('PUT', '/settings', 'Could not save the setting', body: {kind: patch});
    return CelebrationSettings.fromJson(_map(b['data']));
  }

  /// POST /send with `{ kind, templateId?, staffIds }`. Returns the server's message.
  Future<String> sendWishes({
    required CelebrationKind kind,
    required List<String> staffIds,
    String? templateId,
  }) async {
    final b = await _call('POST', '/send', 'Could not send the wishes', body: {
      'kind': kind,
      'staffIds': staffIds,
      if (templateId != null && templateId.isNotEmpty) 'templateId': templateId,
    });
    return _str(b['message']).isEmpty ? 'Wishes sent' : _str(b['message']);
  }
}
