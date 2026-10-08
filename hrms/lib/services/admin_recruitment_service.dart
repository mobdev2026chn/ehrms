// lib/services/admin_recruitment_service.dart
// Admin Recruitment API: job openings, candidates, interview flows/rounds,
// onboarding documents, offer letters, communications and Google Calendar.
// Paths and payloads follow HRMSbackend src/routes/admin/* + controllers.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

import '../models/admin_recruitment_models.dart';
import '../utils/error_message_utils.dart';
import 'api_client.dart';

/// A failed recruitment call, carrying the backend's message.
class RecruitmentApiException implements Exception {
  final String message;
  final int? statusCode;
  RecruitmentApiException(this.message, [this.statusCode]);
  @override
  String toString() => message;
}

class AdminRecruitmentService {
  static final AdminRecruitmentService _instance = AdminRecruitmentService._internal();
  factory AdminRecruitmentService() => _instance;
  AdminRecruitmentService._internal();

  final ApiClient _api = ApiClient();

  static const String _base = '/admin/recruitment';
  static const String _jobs = '$_base/job-openings';
  static const String _candidates = '$_base/candidates';
  static const String _flows = '$_base/interview-flows';
  static const String _rounds = '$_base/interview-rounds';
  static const String _documents = '$_base/documents';
  static const String _offers = '$_base/offer-letters';
  static const String _offerTemplates = '$_base/offer-letter-templates';
  static const String _comms = '$_base/communications';
  static const String _gcal = '/admin/integrations/google-calendar';

  // ───────────────────────── core ─────────────────────────

  Future<Map<String, dynamic>> _call(
    String path, {
    String method = 'GET',
    dynamic data,
    Map<String, dynamic>? query,
    String fallback = 'Request failed',
  }) async {
    try {
      final res = await _api.request(path, method: method, data: data, queryParameters: query);
      final body = res.data;
      if (body is Map) {
        final map = Map<String, dynamic>.from(body);
        if (map['success'] == false) {
          throw RecruitmentApiException(
              ErrorMessageUtils.messageFromResponseData(map) ?? fallback, res.statusCode);
        }
        return map;
      }
      if (body is String && body.isNotEmpty) {
        final decoded = jsonDecode(body);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      }
      return <String, dynamic>{'success': true};
    } on DioException catch (e) {
      throw RecruitmentApiException(
        ErrorMessageUtils.messageFromDioException(e, fallback: fallback),
        e.response?.statusCode,
      );
    } on RecruitmentApiException {
      rethrow;
    } catch (e) {
      throw RecruitmentApiException(fallback);
    }
  }

  List<Map<String, dynamic>> _list(dynamic v) =>
      v is List ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : <Map<String, dynamic>>[];

  Map<String, dynamic> _map(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

  String _msg(Map<String, dynamic> res, String fallback) {
    final m = res['message'];
    return m is String && m.isNotEmpty ? m : fallback;
  }

  // ───────────────────────── Job openings ─────────────────────────

  Future<List<RecJobOpening>> getJobOpenings({String? search, String? status, String? department}) async {
    final res = await _call(_jobs,
        query: {
          if (search != null && search.isNotEmpty) 'search': search,
          if (status != null && status.isNotEmpty) 'status': status,
          if (department != null && department.isNotEmpty) 'department': department,
        },
        fallback: 'Could not load job openings');
    return _list(res['data']).map(RecJobOpening.fromJson).toList();
  }

  Future<RecJobOpening> getJobOpening(String id) async {
    final res = await _call('$_jobs/$id', fallback: 'Could not load the job opening');
    return RecJobOpening.fromJson(_map(res['data']));
  }

  /// [payload] keys: title, department, branchId, workplaceType, employmentType, positions,
  /// experienceMin, experienceMax, education, skills, salaryMin, salaryMax, currency, salaryType,
  /// description, responsibilities, benefits, status, isPublic, closeDate.
  Future<String> createJobOpening(Map<String, dynamic> payload) async {
    final res = await _call(_jobs, method: 'POST', data: payload, fallback: 'Could not create the job opening');
    return _msg(res, 'Job opening created');
  }

  Future<String> updateJobOpening(String id, Map<String, dynamic> payload) async {
    final res = await _call('$_jobs/$id', method: 'PUT', data: payload, fallback: 'Could not update the job opening');
    return _msg(res, 'Job opening updated');
  }

  Future<String> updateJobOpeningStatus(String id, String status) async {
    final res = await _call('$_jobs/$id/status',
        method: 'PATCH', data: {'status': status}, fallback: 'Could not change the status');
    return _msg(res, 'Status updated');
  }

  Future<String> deleteJobOpening(String id) async {
    final res = await _call('$_jobs/$id', method: 'DELETE', fallback: 'Could not delete the job opening');
    return _msg(res, 'Job opening deleted');
  }

  Future<RecGeneratedDescription> generateJobDescription(Map<String, dynamic> payload) async {
    final res = await _call('$_jobs/generate-description',
        method: 'POST', data: payload, fallback: 'Could not generate the description');
    return RecGeneratedDescription.fromJson(_map(res['data']));
  }

  // ───────────────────────── Candidates ─────────────────────────

  Future<List<RecCandidate>> getCandidates({String? search, String? status}) async {
    final res = await _call(_candidates,
        query: {
          if (search != null && search.isNotEmpty) 'search': search,
          if (status != null && status.isNotEmpty) 'status': status,
        },
        fallback: 'Could not load candidates');
    return _list(res['data']).map(RecCandidate.fromJson).toList();
  }

  Future<RecCandidate> getCandidate(String id) async {
    final res = await _call('$_candidates/$id', fallback: 'Could not load the candidate');
    return RecCandidate.fromJson(_map(res['data']));
  }

  /// Returns the created candidate data (includes loginUrl, emailSent, password).
  Future<Map<String, dynamic>> createCandidate(Map<String, dynamic> payload) async {
    final res = await _call(_candidates, method: 'POST', data: payload, fallback: 'Could not add the candidate');
    return {'message': _msg(res, 'Candidate created'), ..._map(res['data'])};
  }

  Future<String> updateCandidate(String id, Map<String, dynamic> payload) async {
    final res = await _call('$_candidates/$id', method: 'PUT', data: payload, fallback: 'Could not update the candidate');
    return _msg(res, 'Candidate updated');
  }

  Future<String> updateCandidateStatus(String id, String status) async {
    final res = await _call('$_candidates/$id/status',
        method: 'PATCH', data: {'status': status}, fallback: 'Could not change the status');
    return _msg(res, 'Status updated');
  }

  Future<String> deleteCandidate(String id) async {
    final res = await _call('$_candidates/$id', method: 'DELETE', fallback: 'Could not delete the candidate');
    return _msg(res, 'Candidate deleted');
  }

  /// Parses a resume (PDF/DOC/DOCX, max 10MB) with AI. Returns personalDetails, education,
  /// experience, courses, internships, skills, summary.
  Future<Map<String, dynamic>> parseResume({required Uint8List bytes, required String fileName, required String mimeType}) async {
    final dataUrl = 'data:$mimeType;base64,${base64Encode(bytes)}';
    final res = await _call('$_candidates/parse-resume',
        method: 'POST',
        data: {'fileData': dataUrl, 'fileName': fileName, 'mimeType': mimeType},
        fallback: 'Could not read the resume');
    return _map(res['data']);
  }

  /// Single-use application form link token.
  Future<String> createCandidateFormLink() async {
    final res = await _call('$_candidates/form-links', method: 'POST', fallback: 'Could not generate the link');
    return (_map(res['data'])['token'] ?? '').toString();
  }

  // ───────────────────────── Interview flows ─────────────────────────

  Future<List<RecInterviewFlow>> getInterviewFlows() async {
    final res = await _call(_flows, fallback: 'Could not load interview flows');
    return _list(res['data']).map(RecInterviewFlow.fromJson).toList();
  }

  Future<RecInterviewFlow> getInterviewFlow(String id) async {
    final res = await _call('$_flows/$id', fallback: 'Could not load the interview flow');
    return RecInterviewFlow.fromJson(_map(res['data']));
  }

  Future<RecInterviewFlow> createInterviewFlow(String jobOpeningId) async {
    final res = await _call(_flows,
        method: 'POST', data: {'jobOpeningId': jobOpeningId}, fallback: 'Could not create the interview flow');
    return RecInterviewFlow.fromJson(_map(res['data']));
  }

  Future<String> deleteInterviewFlow(String id) async {
    final res = await _call('$_flows/$id', method: 'DELETE', fallback: 'Could not delete the interview flow');
    return _msg(res, 'Interview flow deleted');
  }

  /// [interviewerId] (a staff id) wins over [interviewerName].
  Future<RecInterviewFlow> addFlowRound(
    String flowId, {
    required String name,
    String? interviewerId,
    String? interviewerName,
    required String duration,
    List<Map<String, dynamic>> questions = const [],
  }) async {
    final res = await _call('$_flows/$flowId/rounds',
        method: 'POST',
        data: {
          'name': name,
          if (interviewerId != null && interviewerId.isNotEmpty) 'interviewerId': interviewerId,
          if ((interviewerId == null || interviewerId.isEmpty) && interviewerName != null) 'interviewerName': interviewerName,
          'duration': duration,
          'questions': questions,
        },
        fallback: 'Could not add the round');
    return RecInterviewFlow.fromJson(_map(res['data']));
  }

  Future<RecInterviewFlow> updateFlowRound(
    String flowId,
    String roundId, {
    String? name,
    String? interviewerId,
    String? interviewerName,
    String? duration,
  }) async {
    final res = await _call('$_flows/$flowId/rounds/$roundId',
        method: 'PUT',
        data: {
          if (name != null) 'name': name,
          if (interviewerId != null && interviewerId.isNotEmpty) 'interviewerId': interviewerId,
          if ((interviewerId == null || interviewerId.isEmpty) && interviewerName != null) 'interviewerName': interviewerName,
          if (duration != null) 'duration': duration,
        },
        fallback: 'Could not update the round');
    return RecInterviewFlow.fromJson(_map(res['data']));
  }

  Future<RecInterviewFlow> deleteFlowRound(String flowId, String roundId) async {
    final res = await _call('$_flows/$flowId/rounds/$roundId', method: 'DELETE', fallback: 'Could not delete the round');
    return RecInterviewFlow.fromJson(_map(res['data']));
  }

  Future<RecInterviewFlow> reorderFlowRounds(String flowId, List<String> roundIds) async {
    final res = await _call('$_flows/$flowId/rounds/reorder',
        method: 'PUT', data: {'roundIds': roundIds}, fallback: 'Could not reorder the rounds');
    return RecInterviewFlow.fromJson(_map(res['data']));
  }

  Future<RecInterviewFlow> addFlowQuestion(String flowId, String roundId, Map<String, dynamic> question) async {
    final res = await _call('$_flows/$flowId/rounds/$roundId/questions',
        method: 'POST', data: question, fallback: 'Could not add the question');
    return RecInterviewFlow.fromJson(_map(res['data']));
  }

  Future<RecInterviewFlow> updateFlowQuestion(String flowId, String roundId, String questionId, Map<String, dynamic> question) async {
    final res = await _call('$_flows/$flowId/rounds/$roundId/questions/$questionId',
        method: 'PUT', data: question, fallback: 'Could not update the question');
    return RecInterviewFlow.fromJson(_map(res['data']));
  }

  Future<RecInterviewFlow> deleteFlowQuestion(String flowId, String roundId, String questionId) async {
    final res = await _call('$_flows/$flowId/rounds/$roundId/questions/$questionId',
        method: 'DELETE', fallback: 'Could not delete the question');
    return RecInterviewFlow.fromJson(_map(res['data']));
  }

  // ───────────────────────── Interview rounds ─────────────────────────

  Future<List<RecInterviewRound>> getInterviewRounds({String? candidateId, String? status}) async {
    final res = await _call(_rounds,
        query: {
          if (candidateId != null && candidateId.isNotEmpty) 'candidateId': candidateId,
          if (status != null && status.isNotEmpty) 'status': status,
        },
        fallback: 'Could not load interview rounds');
    return _list(res['data']).map(RecInterviewRound.fromJson).toList();
  }

  Future<RecInterviewRound> getInterviewRound(String id) async {
    final res = await _call('$_rounds/$id', fallback: 'Could not load the interview round');
    return RecInterviewRound.fromJson(_map(res['data']));
  }

  /// Schedules a round for a candidate (moves the candidate to Interviewing).
  /// interviewDate: YYYY-MM-DD, interviewTime: HH:mm.
  Future<String> scheduleInterviewRound({
    required String candidateId,
    required String flowId,
    required String flowRoundId,
    String? interviewerId,
    String? interviewerName,
    required String interviewDate,
    required String interviewTime,
    required String mode,
    required List<Map<String, dynamic>> questions,
  }) async {
    final res = await _call(_rounds,
        method: 'POST',
        data: {
          'candidateId': candidateId,
          'flowId': flowId,
          'flowRoundId': flowRoundId,
          if (interviewerId != null && interviewerId.isNotEmpty) 'interviewerId': interviewerId,
          if (interviewerId == null || interviewerId.isEmpty) 'interviewerName': interviewerName ?? '',
          'interviewDate': interviewDate,
          'interviewTime': interviewTime,
          'mode': mode,
          'questions': questions,
        },
        fallback: 'Could not schedule the interview');
    return _msg(res, 'Interview scheduled');
  }

  Future<String> rescheduleInterviewRound(
    String id, {
    String? interviewerId,
    String? interviewerName,
    required String interviewDate,
    required String interviewTime,
    required String mode,
  }) async {
    final res = await _call('$_rounds/$id/schedule',
        method: 'PUT',
        data: {
          if (interviewerId != null && interviewerId.isNotEmpty) 'interviewerId': interviewerId,
          if (interviewerId == null || interviewerId.isEmpty) 'interviewerName': interviewerName ?? '',
          'interviewDate': interviewDate,
          'interviewTime': interviewTime,
          'mode': mode,
        },
        fallback: 'Could not re-schedule the interview');
    return _msg(res, 'Interview re-scheduled');
  }

  /// Keys of the maps are question indexes.
  Future<String> evaluateInterviewRound(
    String id, {
    required Map<String, num> scores,
    required Map<String, String> questionNotes,
    required Map<String, num> questionScores,
    required String generalFeedback,
    required String recommendation,
    num? overallScore,
    String? reassignedJobOpeningId,
  }) async {
    final res = await _call('$_rounds/$id/evaluation',
        method: 'PUT',
        data: {
          'scores': scores,
          'questionNotes': questionNotes,
          'questionScores': questionScores,
          'generalFeedback': generalFeedback,
          'recommendation': recommendation,
          if (overallScore != null) 'overallScore': overallScore,
          if (reassignedJobOpeningId != null) 'reassignedJobOpeningId': reassignedJobOpeningId,
        },
        fallback: 'Could not save the evaluation');
    return _msg(res, 'Evaluation saved');
  }

  Future<String> syncRoundCalendar(String id) async {
    final res = await _call('$_rounds/$id/calendar-sync', method: 'POST', fallback: 'Could not send the invite');
    return _msg(res, 'Calendar invite sent');
  }

  Future<RecInterviewRound> addRoundQuestion(String roundId, Map<String, dynamic> question) async {
    final res = await _call('$_rounds/$roundId/questions', method: 'POST', data: question, fallback: 'Could not add the question');
    return RecInterviewRound.fromJson(_map(res['data']));
  }

  Future<RecInterviewRound> updateRoundQuestion(String roundId, String questionId, Map<String, dynamic> question) async {
    final res = await _call('$_rounds/$roundId/questions/$questionId',
        method: 'PUT', data: question, fallback: 'Could not update the question');
    return RecInterviewRound.fromJson(_map(res['data']));
  }

  // ───────────────────────── Google Calendar ─────────────────────────

  Future<RecGoogleCalendarStatus> getGoogleCalendarStatus() async {
    final res = await _call('$_gcal/status', fallback: 'Could not load Google Calendar status');
    return RecGoogleCalendarStatus.fromJson(_map(res['data']));
  }

  Future<String> getGoogleCalendarConnectUrl({String returnTo = '/admin/recruitment/appointments'}) async {
    final res = await _call('$_gcal/connect-url', query: {'returnTo': returnTo}, fallback: 'Could not start the Google connection');
    return (_map(res['data'])['url'] ?? '').toString();
  }

  Future<String> disconnectGoogleCalendar() async {
    final res = await _call(_gcal, method: 'DELETE', fallback: 'Could not disconnect Google Calendar');
    return _msg(res, 'Google account disconnected');
  }

  // ───────────────────────── Verification documents ─────────────────────────

  /// [scope]: 'verify' (collect & review) or 'convert' (decide / convert to staff).
  Future<List<RecVerificationCandidate>> getVerificationCandidates(String scope) async {
    final res = await _call(_documents, query: {'scope': scope}, fallback: 'Could not load verification candidates');
    return _list(res['data']).map(RecVerificationCandidate.fromJson).toList();
  }

  Future<RecCandidateDocuments> getCandidateDocuments(String candidateId) async {
    final res = await _call('$_documents/candidates/$candidateId', fallback: 'Could not load documents');
    return RecCandidateDocuments.fromJson(_map(res['data']));
  }

  /// Upload a file (PDF/JPG/PNG, max 10MB). Pass [documentType] for a checklist item or
  /// [documentName] for an extra document.
  Future<String> uploadCandidateDocument(
    String candidateId, {
    String? documentType,
    String? documentName,
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
  }) async {
    final res = await _call('$_documents/candidates/$candidateId',
        method: 'POST',
        data: {
          if (documentType != null) 'documentType': documentType,
          if (documentName != null) 'documentName': documentName,
          'fileName': fileName,
          'fileData': 'data:$mimeType;base64,${base64Encode(bytes)}',
        },
        fallback: 'Could not upload the document');
    return _msg(res, 'Document uploaded');
  }

  Future<String> getDocumentViewUrl(String documentId) async {
    final res = await _call('$_documents/$documentId/view', fallback: 'Could not open the document');
    return (_map(res['data'])['url'] ?? '').toString();
  }

  Future<String> verifyDocument(String documentId) async {
    final res = await _call('$_documents/$documentId/verify', method: 'PATCH', fallback: 'Could not verify the document');
    return _msg(res, 'Document verified');
  }

  Future<String> rejectDocument(String documentId, String reason) async {
    final res = await _call('$_documents/$documentId/reject',
        method: 'PATCH', data: {'reason': reason}, fallback: 'Could not reject the document');
    return _msg(res, 'Document rejected');
  }

  Future<String> deleteDocument(String documentId) async {
    final res = await _call('$_documents/$documentId', method: 'DELETE', fallback: 'Could not remove the document');
    return _msg(res, 'Document removed');
  }

  Future<String> requestCandidateDocument(String candidateId, {required String documentName, String? note}) async {
    final res = await _call('$_documents/candidates/$candidateId/requests',
        method: 'POST',
        data: {'documentName': documentName, if (note != null && note.isNotEmpty) 'note': note},
        fallback: 'Could not request the document');
    return _msg(res, 'Document requested');
  }

  Future<String> cancelDocumentRequest(String candidateId, String documentType) async {
    final res = await _call('$_documents/candidates/$candidateId/requests/${Uri.encodeComponent(documentType)}',
        method: 'DELETE', fallback: 'Could not cancel the request');
    return _msg(res, 'Request cancelled');
  }

  Future<String> submitDocumentsForVerification(String candidateId) async {
    final res = await _call('$_documents/candidates/$candidateId/submit-documents',
        method: 'POST', fallback: 'Could not submit the documents');
    return _msg(res, 'Documents submitted for verification');
  }

  Future<String> saveDocumentVerification(String candidateId) async {
    final res = await _call('$_documents/candidates/$candidateId/save-verification',
        method: 'POST', fallback: 'Could not save the verification');
    return _msg(res, 'Verification saved');
  }

  /// [stage]: verificationHold | verificationReject | verificationBlacklist.
  Future<String> setVerificationStage(String candidateId, String stage, {String? reason}) async {
    final res = await _call('$_documents/candidates/$candidateId/verification-stage',
        method: 'PATCH',
        data: {'stage': stage, if (reason != null && reason.isNotEmpty) 'reason': reason},
        fallback: 'Could not save the decision');
    return _msg(res, 'Decision saved');
  }

  Future<String> liftBlacklist(String candidateId) async {
    final res = await _call('$_documents/candidates/$candidateId/blacklist',
        method: 'DELETE', fallback: 'Could not lift the blacklist');
    return _msg(res, 'Blacklist lifted');
  }

  Future<String> skipDocuments(String candidateId, {String? reason}) async {
    final res = await _call('$_documents/candidates/$candidateId/skip-documents',
        method: 'POST', data: {'reason': reason ?? ''}, fallback: 'Could not skip the documents');
    return _msg(res, 'Documents skipped');
  }

  Future<String> undoSkipDocuments(String candidateId) async {
    final res = await _call('$_documents/candidates/$candidateId/skip-documents',
        method: 'DELETE', fallback: 'Could not undo the skip');
    return _msg(res, 'Documents will be collected again');
  }

  /// Body: joiningDate, onboardingDate, designation, department, branchId, employmentType,
  /// jobRole, subscriptionPlanName.
  Future<String> convertCandidateToStaff(String candidateId, Map<String, dynamic> payload) async {
    final res = await _call('$_documents/candidates/$candidateId/convert-to-staff',
        method: 'POST', data: payload, fallback: 'Could not convert the candidate to staff');
    return _msg(res, 'Candidate converted to staff');
  }

  // ───────────────────────── Offer letters ─────────────────────────

  Future<List<RecSentOffer>> getSentOfferCandidates() async {
    final res = await _call('$_offers/sent', fallback: 'Could not load sent offers');
    return _list(res['data']).map(RecSentOffer.fromJson).toList();
  }

  Future<List<RecIssuedOffer>> getCandidateOfferLetters(String candidateId) async {
    final res = await _call('$_offers/candidate/$candidateId', fallback: 'Could not load offer letters');
    return _list(res['data']).map(RecIssuedOffer.fromJson).toList();
  }

  /// Payload: candidateId, templateId, salaryTemplateId, basicSalary, hasPF, hasESI,
  /// designation, joiningDate, validTill, variables.
  Future<RecOfferPreview> previewOfferLetter(Map<String, dynamic> payload) async {
    final res = await _call('$_offers/preview', method: 'POST', data: payload, fallback: 'Could not prepare the preview');
    return RecOfferPreview.fromJson(_map(res['data']));
  }

  /// [send] true emails the letter (candidate becomes Offered); false saves a draft.
  Future<String> issueOfferLetter(Map<String, dynamic> payload, {required bool send}) async {
    final res = await _call(_offers,
        method: 'POST', data: {...payload, 'send': send}, fallback: 'Could not issue the offer letter');
    return _msg(res, send ? 'Offer letter sent' : 'Draft saved');
  }

  Future<String> revokeOfferLetter(String offerId) async {
    final res = await _call('$_offers/$offerId/revoke', method: 'POST', fallback: 'Could not revoke the offer');
    return _msg(res, 'Offer revoked');
  }

  /// Downloads the letter PDF to a temp file and returns its path.
  Future<String> downloadOfferLetterPdf(String offerId, String candidateName) async {
    try {
      final res = await _api.request<List<int>>('$_offers/$offerId/letter',
          options: Options(responseType: ResponseType.bytes));
      final bytes = res.data ?? <int>[];
      final dir = await getTemporaryDirectory();
      final safe = candidateName.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
      final file = File('${dir.path}/offer_letter_${safe}_$offerId.pdf');
      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    } on DioException catch (e) {
      dynamic data = e.response?.data;
      if (data is List<int>) {
        try {
          data = jsonDecode(utf8.decode(data));
        } on FormatException {
          data = null;
        }
      }
      throw RecruitmentApiException(
          ErrorMessageUtils.messageFromResponseData(data) ??
              ErrorMessageUtils.messageFromDioException(e, fallback: 'Could not open the letter'),
          e.response?.statusCode);
    }
  }

  Future<String> getOfferAttachmentUrl(String offerId, int index) async {
    final res = await _call('$_offers/$offerId/attachments/$index/file', fallback: 'Could not open the attachment');
    return (_map(res['data'])['url'] ?? '').toString();
  }

  Future<List<RecSalaryTemplateOption>> getSalaryTemplates() async {
    final res = await _call('/admin/staff/salary-templates', fallback: 'Could not load salary templates');
    final data = res['data'];
    final list = data is Map ? data['templates'] : data;
    return _list(list).map(RecSalaryTemplateOption.fromJson).toList();
  }

  // ───────────────────────── Offer letter templates ─────────────────────────

  Future<List<RecOfferTemplate>> getOfferTemplates() async {
    final res = await _call(_offerTemplates, fallback: 'Could not load templates');
    return _list(res['data']).map(RecOfferTemplate.fromJson).toList();
  }

  Future<String> updateOfferTemplate(String id, Map<String, dynamic> payload) async {
    final res = await _call('$_offerTemplates/$id', method: 'PUT', data: payload, fallback: 'Could not save the template');
    return _msg(res, 'Template saved');
  }

  Future<String> duplicateOfferTemplate(String id) async {
    final res = await _call('$_offerTemplates/$id/duplicate', method: 'POST', fallback: 'Could not duplicate the template');
    return _msg(res, 'Template duplicated');
  }

  Future<String> setDefaultOfferTemplate(String id) async {
    final res = await _call('$_offerTemplates/$id/default', method: 'PATCH', fallback: 'Could not set the default template');
    return _msg(res, 'Default template updated');
  }

  Future<String> deleteOfferTemplate(String id) async {
    final res = await _call('$_offerTemplates/$id', method: 'DELETE', fallback: 'Could not delete the template');
    return _msg(res, 'Template deleted');
  }

  // ───────────────────────── Communications ─────────────────────────

  Future<List<RecCommChannel>> getCommunicationChannels() async {
    final res = await _call('$_comms/channels', fallback: 'Could not load channels');
    return _list(res['data']).map(RecCommChannel.fromJson).toList();
  }

  Future<List<RecCommChannel>> updateCommunicationChannel(String channel, bool enabled) async {
    final res = await _call('$_comms/channels/$channel',
        method: 'PATCH', data: {'enabled': enabled}, fallback: 'Could not update the channel');
    return _list(res['data']).map(RecCommChannel.fromJson).toList();
  }

  Future<RecPage<RecCommCandidate>> getCommunicationCandidates({String? search, bool messaged = false, int page = 1, int limit = 25}) async {
    final res = await _call('$_comms/history/candidates',
        query: {
          if (search != null && search.isNotEmpty) 'search': search,
          if (messaged) 'messaged': 'true',
          'page': page,
          'limit': limit,
        },
        fallback: 'Could not load communication history');
    final data = _map(res['data']);
    return RecPage(
      rows: _list(data['rows']).map(RecCommCandidate.fromJson).toList(),
      total: (data['total'] as num?)?.toInt() ?? 0,
      page: (data['page'] as num?)?.toInt() ?? page,
      limit: (data['limit'] as num?)?.toInt() ?? limit,
    );
  }

  Future<RecPage<RecCommLog>> getCommunicationHistory({
    required String candidateId,
    String? status,
    String? search,
    int page = 1,
    int limit = 25,
  }) async {
    final res = await _call('$_comms/history',
        query: {
          'candidateId': candidateId,
          if (status != null && status.isNotEmpty) 'status': status,
          if (search != null && search.isNotEmpty) 'search': search,
          'page': page,
          'limit': limit,
        },
        fallback: 'Could not load messages');
    final data = _map(res['data']);
    return RecPage(
      rows: _list(data['rows']).map(RecCommLog.fromJson).toList(),
      total: (data['total'] as num?)?.toInt() ?? 0,
      page: (data['page'] as num?)?.toInt() ?? page,
      limit: (data['limit'] as num?)?.toInt() ?? limit,
      extra: {'counts': _map(data['counts'])},
    );
  }

  // ───────────────────────── Lookups (other modules) ─────────────────────────

  Future<List<RecBranchOption>> getBranches() async {
    final res = await _call('/admin/settings/attendance/branches', fallback: 'Could not load branches');
    return _list(res['data']).map(RecBranchOption.fromJson).toList();
  }

  Future<List<RecStaffOption>> getStaffOptions() async {
    final res = await _call('/admin/staff', fallback: 'Could not load staff');
    final data = res['data'];
    final list = data is Map ? data['staff'] : data;
    return _list(list).map(RecStaffOption.fromJson).where((s) => s.id.isNotEmpty).toList();
  }

  /// Raw staff records (for joining dates).
  Future<List<Map<String, dynamic>>> getStaffRecords() async {
    final res = await _call('/admin/staff', fallback: 'Could not load staff');
    final data = res['data'];
    return _list(data is Map ? data['staff'] : data);
  }

  /// Subscription plans (planName, totalSeat, activeUsers) for Convert to Staff.
  Future<List<Map<String, dynamic>>> getSubscriptionPlans() async {
    final res = await _call('/admin/staff/subscription', fallback: 'Could not load subscription plans');
    return _list(_map(res['data'])['planDetails']);
  }
}
