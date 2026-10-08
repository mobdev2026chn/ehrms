// Admin Exit Process APIs. HRMSbackend src/routes/admin/exitProcessRoute.ts, mounted at
// /api/admin/exit-process (company admin only), plus GET /api/admin/company for the
// acknowledgement template's letterhead.
//
// Every method answers { success, data?, message? } and never throws.

import 'package:dio/dio.dart';

import 'admin_salary_service.dart';
import 'api_client.dart';

class AdminExitProcessService {
  AdminExitProcessService._();
  static final AdminExitProcessService instance = AdminExitProcessService._();
  final ApiClient _api = ApiClient();

  static const _base = '/admin/exit-process';

  Future<Map<String, dynamic>> _run(
    Future<Response<dynamic>> Function() call, {
    dynamic Function(Map<String, dynamic> data)? pick,
  }) async {
    try {
      final res = await call();
      final body = res.data is Map ? Map<String, dynamic>.from(res.data as Map) : <String, dynamic>{};
      if (body['success'] == false) {
        return {'success': false, 'message': body['message']?.toString() ?? 'Request failed.'};
      }
      final data = body['data'] is Map ? Map<String, dynamic>.from(body['data'] as Map) : <String, dynamic>{};
      return {'success': true, 'data': pick != null ? pick(data) : data, 'message': body['message']?.toString()};
    } catch (e) {
      return {'success': false, 'message': AdminSalaryService.messageOf(e)};
    }
  }

  static List<Map<String, dynamic>> _maps(dynamic v) =>
      v is List ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : <Map<String, dynamic>>[];

  static Map<String, dynamic> _case(Map<String, dynamic> d) =>
      d['case'] is Map ? Map<String, dynamic>.from(d['case'] as Map) : <String, dynamic>{};

  // ── Pipeline ──────────────────────────────────────────────────────────

  /// GET /cases → data.cases
  Future<Map<String, dynamic>> getCases() => _run(() => _api.request('$_base/cases'), pick: (d) => _maps(d['cases']));

  /// GET /cases/candidates → data.candidates [{ staffId, employeeId, name, designation, department, inPipeline }]
  Future<Map<String, dynamic>> getCandidates() =>
      _run(() => _api.request('$_base/cases/candidates'), pick: (d) => _maps(d['candidates']));

  /// POST /cases { staffIds } → data.cases (the new ones)
  Future<Map<String, dynamic>> addCases(List<String> staffIds) => _run(
        () => _api.request('$_base/cases', method: 'POST', data: {'staffIds': staffIds}),
        pick: (d) => _maps(d['cases']),
      );

  /// PATCH /cases/:id/status { status: in_progress | completed | cancelled, cancelReason? } → data.case
  Future<Map<String, dynamic>> updateStatus(String id, String status, {String? cancelReason}) => _run(
        () => _api.request(
          '$_base/cases/$id/status',
          method: 'PATCH',
          data: {'status': status, if (cancelReason != null && cancelReason.trim().isNotEmpty) 'cancelReason': cancelReason.trim()},
        ),
        pick: _case,
      );

  /// DELETE /cases/:id
  Future<Map<String, dynamic>> deleteCase(String id) => _run(() => _api.request('$_base/cases/$id', method: 'DELETE'));

  // ── Settings ──────────────────────────────────────────────────────────

  /// GET /settings → data (the settings, with chosen people expanded)
  Future<Map<String, dynamic>> getSettings() => _run(() => _api.request('$_base/settings'));

  /// PUT /settings — people go as { userId, userType }, questions keep their fieldId.
  Future<Map<String, dynamic>> updateSettings(Map<String, dynamic> payload) =>
      _run(() => _api.request('$_base/settings', method: 'PUT', data: payload));

  /// POST /settings/reset
  Future<Map<String, dynamic>> resetSettings() => _run(() => _api.request('$_base/settings/reset', method: 'POST'));

  /// GET /settings/people → data.people [{ userId, userType, name, email, role, deactivated }]
  Future<Map<String, dynamic>> getSettingsPeople() =>
      _run(() => _api.request('$_base/settings/people'), pick: (d) => _maps(d['people']));

  // ── One exit ──────────────────────────────────────────────────────────

  /// GET /cases/:id → data.case
  Future<Map<String, dynamic>> getCase(String id) => _run(() => _api.request('$_base/cases/$id'), pick: _case);

  /// GET /cases/:id/credentials → data.credentials { laptopPasswordCollected, mobilePasswordCollected, accounts[] }
  Future<Map<String, dynamic>> getCredentials(String id) => _run(
        () => _api.request('$_base/cases/$id/credentials'),
        pick: (d) => d['credentials'] is Map ? Map<String, dynamic>.from(d['credentials'] as Map) : <String, dynamic>{},
      );

  /// PUT /cases/:id/credentials → data { case, credentials }
  Future<Map<String, dynamic>> saveCredentials(String id, Map<String, dynamic> body) =>
      _run(() => _api.request('$_base/cases/$id/credentials', method: 'PUT', data: body));

  Future<Map<String, dynamic>> _put(String id, String section, Map<String, dynamic> body) =>
      _run(() => _api.request('$_base/cases/$id/$section', method: 'PUT', data: body), pick: _case);

  /// PUT /cases/:id/timeline { exitType, ...timeline }
  Future<Map<String, dynamic>> saveTimeline(String id, Map<String, dynamic> timeline) => _put(id, 'timeline', timeline);

  /// PUT /cases/:id/assets { assets }
  Future<Map<String, dynamic>> saveAssets(String id, List<Map<String, dynamic>> assets) =>
      _put(id, 'assets', {'assets': assets});

  /// PUT /cases/:id/kt { projects }
  Future<Map<String, dynamic>> saveKT(String id, List<Map<String, dynamic>> projects) =>
      _put(id, 'kt', {'projects': projects});

  /// PUT /cases/:id/sops { sops }
  Future<Map<String, dynamic>> saveSOPs(String id, List<Map<String, dynamic>> sops) => _put(id, 'sops', {'sops': sops});

  /// PUT /cases/:id/documents { originalDocumentsCollected, acknowledgementSigned }
  Future<Map<String, dynamic>> saveDocuments(String id, {required bool originals, required bool signed}) =>
      _put(id, 'documents', {'originalDocumentsCollected': originals, 'acknowledgementSigned': signed});

  /// POST /cases/:id/documents/acknowledgement { fileName, mimeType, dataBase64 }
  Future<Map<String, dynamic>> uploadAcknowledgement(String id, String fileName, String mimeType, String dataBase64) =>
      _run(
        () => _api.request(
          '$_base/cases/$id/documents/acknowledgement',
          method: 'POST',
          data: {'fileName': fileName, 'mimeType': mimeType, 'dataBase64': dataBase64},
          options: Options(sendTimeout: const Duration(minutes: 2), receiveTimeout: const Duration(minutes: 2)),
        ),
        pick: _case,
      );

  /// DELETE /cases/:id/documents/acknowledgement
  Future<Map<String, dynamic>> removeAcknowledgement(String id) =>
      _run(() => _api.request('$_base/cases/$id/documents/acknowledgement', method: 'DELETE'), pick: _case);

  /// PUT /cases/:id/review { reviewLink, reviewConfirmed }
  Future<Map<String, dynamic>> saveReview(String id, Map<String, dynamic> review) => _put(id, 'review', review);

  /// PUT /cases/:id/full-final { salaryProcessed, salaryNotes, relievingLetterStatus, relievingLetterDate, reason }
  Future<Map<String, dynamic>> saveFullFinal(String id, Map<String, dynamic> body) => _put(id, 'full-final', body);

  // ── Company ───────────────────────────────────────────────────────────

  /// GET /admin/company → data (name, address, city, state, pincode, logo, ...)
  Future<Map<String, dynamic>> getCompany() => _run(() => _api.request('/admin/company'));
}
