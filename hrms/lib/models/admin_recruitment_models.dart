// lib/models/admin_recruitment_models.dart
// Data shapes for the admin Recruitment module, matching the HRMS backend
// (/api/admin/recruitment/*) responses.

String _s(dynamic v, [String fallback = '']) => v == null ? fallback : v.toString();
int _i(dynamic v, [int fallback = 0]) => v is int ? v : (v is num ? v.toInt() : int.tryParse(_s(v)) ?? fallback);
double? _d(dynamic v) => v is num ? v.toDouble() : double.tryParse(_s(v));
bool _b(dynamic v) => v == true || v == 'true';
List<String> _sl(dynamic v) => v is List ? v.map((e) => _s(e)).where((e) => e.isNotEmpty).toList() : <String>[];
Map<String, dynamic> _m(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
List<Map<String, dynamic>> _ml(dynamic v) => v is List ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : [];

/// 'YYYY-MM-DD' from an ISO date, or '' when missing.
String recDateKey(dynamic v) {
  final s = _s(v);
  if (s.isEmpty || s == 'null') return '';
  return s.length >= 10 ? s.substring(0, 10) : s;
}

// ───────────────────────────── Job openings ─────────────────────────────

class RecJobOpening {
  final String id;
  final String code;
  final String title;
  final String department;
  final String branchId;
  final String branch;
  final String workplaceType;
  final String employmentType;
  final int positions;
  final String status;
  final num? experienceMin;
  final num? experienceMax;
  final String experience;
  final String education;
  final List<String> skills;
  final num? salaryMin;
  final num? salaryMax;
  final String currency;
  final String salaryType;
  final String salary;
  final String description;
  final String responsibilities;
  final String requirements;
  final String benefits;
  final bool isPublic;
  final String openDate;
  final String closeDate;
  final String createdAt;

  RecJobOpening({
    required this.id,
    required this.code,
    required this.title,
    required this.department,
    required this.branchId,
    required this.branch,
    required this.workplaceType,
    required this.employmentType,
    required this.positions,
    required this.status,
    this.experienceMin,
    this.experienceMax,
    required this.experience,
    required this.education,
    required this.skills,
    this.salaryMin,
    this.salaryMax,
    required this.currency,
    required this.salaryType,
    required this.salary,
    required this.description,
    required this.responsibilities,
    required this.requirements,
    required this.benefits,
    required this.isPublic,
    required this.openDate,
    required this.closeDate,
    required this.createdAt,
  });

  factory RecJobOpening.fromJson(Map<String, dynamic> j) => RecJobOpening(
        id: _s(j['id'] ?? j['_id']),
        code: _s(j['code']),
        title: _s(j['title']),
        department: _s(j['department']),
        branchId: _s(j['branchId']),
        branch: _s(j['branch']),
        workplaceType: _s(j['workplaceType'], 'On-site'),
        employmentType: _s(j['employmentType'], 'Full-time'),
        positions: _i(j['positions'], 1),
        status: _s(j['status'], 'DRAFT').toUpperCase(),
        experienceMin: _d(j['experienceMin']),
        experienceMax: _d(j['experienceMax']),
        experience: _s(j['experience']),
        education: _s(j['education']),
        skills: _sl(j['skills']),
        salaryMin: _d(j['salaryMin']),
        salaryMax: _d(j['salaryMax']),
        currency: _s(j['currency'], 'INR'),
        salaryType: _s(j['salaryType'], 'Annual'),
        salary: _s(j['salary']),
        description: _s(j['description']),
        responsibilities: _s(j['responsibilities']),
        requirements: _s(j['requirements']),
        benefits: _s(j['benefits']),
        isPublic: _b(j['isPublic']),
        openDate: recDateKey(j['openDate']),
        closeDate: recDateKey(j['closeDate']),
        createdAt: _s(j['createdAt']),
      );
}

class RecGeneratedDescription {
  final String description;
  final String keyResponsibilities;
  final List<String> requirements;
  final List<String> skills;
  final String benefits;

  RecGeneratedDescription({
    required this.description,
    required this.keyResponsibilities,
    required this.requirements,
    required this.skills,
    required this.benefits,
  });

  static String _text(dynamic v) => v is List ? v.map((e) => e.toString()).join('\n') : _s(v);

  factory RecGeneratedDescription.fromJson(Map<String, dynamic> j) => RecGeneratedDescription(
        description: _text(j['description']),
        keyResponsibilities: _text(j['keyResponsibilities']),
        requirements: _sl(j['requirements']),
        skills: _sl(j['skills']),
        benefits: _text(j['benefits']),
      );
}

// ───────────────────────────── Candidates ─────────────────────────────

const List<String> kCandidateStatuses = [
  'Applied',
  'Shortlisted',
  'Interviewing',
  'Passed',
  'On Hold',
  'Reassigned',
  'Selected',
  'Offered',
  'Offer Accepted',
  'Offer Rejected',
  'Offer Expired',
  'Hired',
  'Rejected',
  'Withdrawn',
];

const List<String> kCandidateSources = ['LinkedIn', 'Career Page', 'Naukri', 'Referral', 'Manual'];

class RecCandidateLog {
  final String action;
  final String message;
  final String actorName;
  final String at;
  final String fromStatus;
  final String toStatus;

  RecCandidateLog({
    required this.action,
    required this.message,
    required this.actorName,
    required this.at,
    required this.fromStatus,
    required this.toStatus,
  });

  factory RecCandidateLog.fromJson(Map<String, dynamic> j) => RecCandidateLog(
        action: _s(j['action']),
        message: _s(j['message']),
        actorName: _s(j['actorName']),
        at: _s(j['at']),
        fromStatus: _s(j['fromStatus']),
        toStatus: _s(j['toStatus']),
      );
}

class RecCandidate {
  final String id;
  final String candidateId;
  final String jobOpeningId;
  final String jobTitle;
  final String jobDepartment;
  final String firstName;
  final String lastName;
  final String email;
  final String phone;
  final String dob;
  final String gender;
  final String currentCity;
  final String preferredJobLocation;
  final String position;
  final String primarySkill;
  final num experienceYears;
  final String status;
  final String source;
  final String appliedDate;
  final String resumeUrl;
  final String resumeName;
  final List<Map<String, dynamic>> education;
  final List<Map<String, dynamic>> experience;
  final List<Map<String, dynamic>> courses;
  final List<Map<String, dynamic>> internships;
  final String verificationStage;
  final String verificationStageReason;
  final String staffId;
  final String documentsSavedAt;
  final String documentsSubmittedAt;
  final String updatedAt;
  final List<RecCandidateLog> logs;

  RecCandidate({
    required this.id,
    required this.candidateId,
    required this.jobOpeningId,
    required this.jobTitle,
    required this.jobDepartment,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.phone,
    required this.dob,
    required this.gender,
    required this.currentCity,
    required this.preferredJobLocation,
    required this.position,
    required this.primarySkill,
    required this.experienceYears,
    required this.status,
    required this.source,
    required this.appliedDate,
    required this.resumeUrl,
    required this.resumeName,
    required this.education,
    required this.experience,
    required this.courses,
    required this.internships,
    required this.verificationStage,
    required this.verificationStageReason,
    required this.staffId,
    required this.documentsSavedAt,
    required this.documentsSubmittedAt,
    required this.updatedAt,
    required this.logs,
  });

  String get fullName => '$firstName $lastName'.trim();
  String get displayJob => jobTitle.isNotEmpty ? jobTitle : position;

  factory RecCandidate.fromJson(Map<String, dynamic> j) {
    final job = j['jobOpeningId'];
    final jobMap = job is Map ? Map<String, dynamic>.from(job) : null;
    return RecCandidate(
      id: _s(j['id'] ?? j['_id']),
      candidateId: _s(j['candidateId']),
      jobOpeningId: jobMap != null ? _s(jobMap['_id'] ?? jobMap['id']) : _s(job),
      jobTitle: jobMap != null ? _s(jobMap['title']) : '',
      jobDepartment: jobMap != null ? _s(jobMap['department']) : '',
      firstName: _s(j['firstName']),
      lastName: _s(j['lastName']),
      email: _s(j['email']),
      phone: _s(j['phone']),
      dob: recDateKey(j['dob']),
      gender: _s(j['gender']),
      currentCity: _s(j['currentCity']),
      preferredJobLocation: _s(j['preferredJobLocation']),
      position: _s(j['position']),
      primarySkill: _s(j['primarySkill']),
      experienceYears: _d(j['experienceYears']) ?? 0,
      status: _s(j['status'], 'Applied'),
      source: _s(j['source'], 'Manual'),
      appliedDate: recDateKey(j['appliedDate']),
      resumeUrl: _s(j['resumeUrl']),
      resumeName: _s(j['resumeName']),
      education: _ml(j['education']),
      experience: _ml(j['experience']),
      courses: _ml(j['courses']),
      internships: _ml(j['internships']),
      verificationStage: _s(j['verificationStage'], 'pending'),
      verificationStageReason: _s(j['verificationStageReason']),
      staffId: _s(j['staffId']),
      documentsSavedAt: _s(j['documentsSavedAt']),
      documentsSubmittedAt: _s(j['documentsSubmittedAt']),
      updatedAt: _s(j['updatedAt']),
      logs: _ml(j['logs']).map(RecCandidateLog.fromJson).toList(),
    );
  }
}

// ───────────────────────────── Interview flows ─────────────────────────────

const List<String> kAnswerTypes = ['text', 'rating', 'scenario', 'multichoice'];
const List<String> kRoundDurations = ['30 mins', '45 mins', '60 mins', '90 mins'];
const List<String> kInterviewModes = ['Virtual', 'In-Person', 'Telephonic'];

String answerTypeLabel(String t) {
  switch (t) {
    case 'rating':
      return 'Rating';
    case 'scenario':
      return 'Scenario';
    case 'multichoice':
      return 'Multiple choice';
    default:
      return 'Written';
  }
}

class RecQuestion {
  final String id;
  final String text;
  final String answerType;
  final List<String> options;
  final int maxScore;

  RecQuestion({required this.id, required this.text, required this.answerType, required this.options, required this.maxScore});

  factory RecQuestion.fromJson(Map<String, dynamic> j) => RecQuestion(
        id: _s(j['id'] ?? j['_id']),
        text: _s(j['text']),
        answerType: _s(j['answerType'], 'text'),
        options: _sl(j['options']),
        maxScore: _i(j['maxScore'], 10),
      );

  Map<String, dynamic> toInput() => {
        'text': text,
        'answerType': answerType,
        if (options.isNotEmpty) 'options': options,
        'maxScore': maxScore,
      };
}

class RecFlowRound {
  final String id;
  final int roundNumber;
  final String name;
  final String interviewerId;
  final String interviewer;
  final String duration;
  final List<RecQuestion> questions;

  RecFlowRound({
    required this.id,
    required this.roundNumber,
    required this.name,
    required this.interviewerId,
    required this.interviewer,
    required this.duration,
    required this.questions,
  });

  factory RecFlowRound.fromJson(Map<String, dynamic> j) => RecFlowRound(
        id: _s(j['id']),
        roundNumber: _i(j['roundNumber'], 1),
        name: _s(j['name']),
        interviewerId: _s(j['interviewerId']),
        interviewer: _s(j['interviewer']),
        duration: _s(j['duration'], '45 mins'),
        questions: _ml(j['questions']).map(RecQuestion.fromJson).toList(),
      );
}

class RecInterviewFlow {
  final String id;
  final String jobOpeningId;
  final String jobTitle;
  final String jobCode;
  final String department;
  final String jobStatus;
  final List<RecFlowRound> rounds;
  final String updatedAt;

  RecInterviewFlow({
    required this.id,
    required this.jobOpeningId,
    required this.jobTitle,
    required this.jobCode,
    required this.department,
    required this.jobStatus,
    required this.rounds,
    required this.updatedAt,
  });

  factory RecInterviewFlow.fromJson(Map<String, dynamic> j) => RecInterviewFlow(
        id: _s(j['id']),
        jobOpeningId: _s(j['jobOpeningId']),
        jobTitle: _s(j['jobTitle']),
        jobCode: _s(j['jobCode']),
        department: _s(j['department']),
        jobStatus: _s(j['jobStatus']),
        rounds: _ml(j['rounds']).map(RecFlowRound.fromJson).toList(),
        updatedAt: _s(j['updatedAt']),
      );
}

// ───────────────────────────── Interview rounds ─────────────────────────────

const List<String> kRecommendations = ['Pass', 'Fail', 'Hold', 'Schedule', 'Reassign', 'FinalRound'];

String recommendationLabel(String r) {
  switch (r) {
    case 'Pass':
      return 'Pass';
    case 'Fail':
      return 'Reject';
    case 'Hold':
      return 'Hold';
    case 'Schedule':
      return 'Pass & schedule next';
    case 'Reassign':
      return 'Reassign';
    case 'FinalRound':
      return 'Select (final round)';
    default:
      return r;
  }
}

class RecRoundEvaluation {
  final Map<String, dynamic> scores;
  final Map<String, dynamic> questionNotes;
  final Map<String, dynamic> questionScores;
  final String generalFeedback;
  final String recommendation;
  final num? overallScore;
  final String reassignedPosition;
  final String evaluatedAt;

  RecRoundEvaluation({
    required this.scores,
    required this.questionNotes,
    required this.questionScores,
    required this.generalFeedback,
    required this.recommendation,
    this.overallScore,
    required this.reassignedPosition,
    required this.evaluatedAt,
  });

  factory RecRoundEvaluation.fromJson(Map<String, dynamic> j) => RecRoundEvaluation(
        scores: _m(j['scores']),
        questionNotes: _m(j['questionNotes']),
        questionScores: _m(j['questionScores']),
        generalFeedback: _s(j['generalFeedback']),
        recommendation: _s(j['recommendation']),
        overallScore: _d(j['overallScore']),
        reassignedPosition: _s(j['reassignedPosition']),
        evaluatedAt: _s(j['evaluatedAt']),
      );
}

class RecInterviewRound {
  final String id;
  final String candidateId;
  final String jobOpeningId;
  final String flowId;
  final String flowRoundId;
  final String candidateName;
  final String candidateEmail;
  final String position;
  final int roundNumber;
  final String roundName;
  final String duration;
  final String interviewerId;
  final String interviewerName;
  final String interviewDate;
  final String interviewTime;
  final String mode;
  final String meetLink;
  final String calendarEventLink;
  final String calendarSyncStatus;
  final String calendarSyncError;
  final String status;
  final List<RecQuestion> questions;
  final RecRoundEvaluation? evaluation;
  final bool candidateWithdrawn;
  final String createdAt;

  RecInterviewRound({
    required this.id,
    required this.candidateId,
    required this.jobOpeningId,
    required this.flowId,
    required this.flowRoundId,
    required this.candidateName,
    required this.candidateEmail,
    required this.position,
    required this.roundNumber,
    required this.roundName,
    required this.duration,
    required this.interviewerId,
    required this.interviewerName,
    required this.interviewDate,
    required this.interviewTime,
    required this.mode,
    required this.meetLink,
    required this.calendarEventLink,
    required this.calendarSyncStatus,
    required this.calendarSyncError,
    required this.status,
    required this.questions,
    required this.evaluation,
    required this.candidateWithdrawn,
    required this.createdAt,
  });

  bool get isScheduled => status == 'Scheduled' || evaluation == null;

  /// "Scheduled" until evaluated, then the decision (matches the web's getRoundDisplayStatus).
  String get displayStatus {
    if (status == 'Scheduled' || evaluation == null) return 'Scheduled';
    switch (evaluation!.recommendation) {
      case 'Pass':
      case 'Schedule':
        return 'Passed';
      case 'Fail':
        return 'Rejected';
      case 'Hold':
        return 'On Hold';
      case 'Reassign':
        return 'Reassigned';
      case 'FinalRound':
        return 'Selected';
      default:
        return 'Evaluated';
    }
  }

  DateTime? get dateTime => DateTime.tryParse('${interviewDate}T${interviewTime.isEmpty ? '00:00' : interviewTime}');

  factory RecInterviewRound.fromJson(Map<String, dynamic> j) => RecInterviewRound(
        id: _s(j['id'] ?? j['_id']),
        candidateId: _s(j['candidateId']),
        jobOpeningId: _s(j['jobOpeningId']),
        flowId: _s(j['flowId']),
        flowRoundId: _s(j['flowRoundId']),
        candidateName: _s(j['candidateName']),
        candidateEmail: _s(j['candidateEmail']),
        position: _s(j['position']),
        roundNumber: _i(j['roundNumber'], 1),
        roundName: _s(j['roundName']),
        duration: _s(j['duration']),
        interviewerId: _s(j['interviewerId']),
        interviewerName: _s(j['interviewerName']),
        interviewDate: recDateKey(j['interviewDate']),
        interviewTime: _s(j['interviewTime']),
        mode: _s(j['mode'], 'Virtual'),
        meetLink: _s(j['meetLink']),
        calendarEventLink: _s(j['calendarEventLink']),
        calendarSyncStatus: _s(j['calendarSyncStatus']),
        calendarSyncError: _s(j['calendarSyncError']),
        status: _s(j['status'], 'Scheduled'),
        questions: _ml(j['questions']).map(RecQuestion.fromJson).toList(),
        evaluation: j['evaluation'] is Map ? RecRoundEvaluation.fromJson(_m(j['evaluation'])) : null,
        candidateWithdrawn: _b(j['candidateWithdrawn']),
        createdAt: _s(j['createdAt']),
      );
}

class RecStaffOption {
  final String id;
  final String name;
  final String designation;
  RecStaffOption({required this.id, required this.name, required this.designation});

  String get label => designation.isEmpty ? name : '$name ($designation)';

  factory RecStaffOption.fromJson(Map<String, dynamic> j) => RecStaffOption(
        id: _s(j['_id'] ?? j['id']),
        name: '${_s(j['firstName'])} ${_s(j['lastName'])}'.trim().isEmpty
            ? _s(j['name'])
            : '${_s(j['firstName'])} ${_s(j['lastName'])}'.trim(),
        designation: _s(j['designation']),
      );
}

class RecBranchOption {
  final String id;
  final String name;
  final String code;
  RecBranchOption({required this.id, required this.name, required this.code});

  factory RecBranchOption.fromJson(Map<String, dynamic> j) =>
      RecBranchOption(id: _s(j['_id'] ?? j['id']), name: _s(j['branchName'] ?? j['name']), code: _s(j['branchCode']));
}

class RecGoogleCalendarStatus {
  final bool configured;
  final bool connected;
  final bool needsReconnect;
  final String googleEmail;
  final String connectedByName;

  RecGoogleCalendarStatus({
    required this.configured,
    required this.connected,
    required this.needsReconnect,
    required this.googleEmail,
    required this.connectedByName,
  });

  factory RecGoogleCalendarStatus.fromJson(Map<String, dynamic> j) => RecGoogleCalendarStatus(
        configured: _b(j['configured']),
        connected: _b(j['connected']),
        needsReconnect: _b(j['needsReconnect']),
        googleEmail: _s(j['googleEmail']),
        connectedByName: _s(j['connectedByName']),
      );
}

// ───────────────────────────── Verification ─────────────────────────────

const Map<String, String> kVerificationStageLabels = {
  'pending': 'Awaiting Decision',
  'converted': 'Converted',
  'verificationHold': 'On Hold',
  'verificationReject': 'Rejected',
  'verificationBlacklist': 'Blacklisted',
};

class RecVerificationSummary {
  final int required;
  final int verified;
  final int pendingReview;
  final int rejected;
  final int notSubmitted;
  final int additional;
  final int additionalVerified;
  final String verificationStatus;
  final bool readyToSave;
  final bool allSubmitted;

  RecVerificationSummary({
    required this.required,
    required this.verified,
    required this.pendingReview,
    required this.rejected,
    required this.notSubmitted,
    required this.additional,
    required this.additionalVerified,
    required this.verificationStatus,
    required this.readyToSave,
    required this.allSubmitted,
  });

  factory RecVerificationSummary.fromJson(Map<String, dynamic> j) => RecVerificationSummary(
        required: _i(j['required']),
        verified: _i(j['verified']),
        pendingReview: _i(j['pendingReview']),
        rejected: _i(j['rejected']),
        notSubmitted: _i(j['notSubmitted']),
        additional: _i(j['additional']),
        additionalVerified: _i(j['additionalVerified']),
        verificationStatus: _s(j['verificationStatus'], 'Pending'),
        readyToSave: _b(j['readyToSave']),
        allSubmitted: _b(j['allSubmitted']),
      );
}

class RecVerificationCandidate {
  final String id;
  final String firstName;
  final String lastName;
  final String email;
  final String phone;
  final String position;
  final String department;
  final String status;
  final String staffId;
  final String verificationStage;
  final String verificationStageReason;
  final String documentsSavedAt;
  final String documentsSubmittedAt;
  final String documentsSkippedAt;
  final RecVerificationSummary summary;

  RecVerificationCandidate({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.phone,
    required this.position,
    required this.department,
    required this.status,
    required this.staffId,
    required this.verificationStage,
    required this.verificationStageReason,
    required this.documentsSavedAt,
    required this.documentsSubmittedAt,
    required this.documentsSkippedAt,
    required this.summary,
  });

  String get fullName => '$firstName $lastName'.trim();

  factory RecVerificationCandidate.fromJson(Map<String, dynamic> j) => RecVerificationCandidate(
        id: _s(j['id']),
        firstName: _s(j['firstName']),
        lastName: _s(j['lastName']),
        email: _s(j['email']),
        phone: _s(j['phone']),
        position: _s(j['position']),
        department: _s(j['department']),
        status: _s(j['status']),
        staffId: _s(j['staffId']),
        verificationStage: _s(j['verificationStage'], 'pending'),
        verificationStageReason: _s(j['verificationStageReason']),
        documentsSavedAt: _s(j['documentsSavedAt']),
        documentsSubmittedAt: _s(j['documentsSubmittedAt']),
        documentsSkippedAt: _s(j['documentsSkippedAt']),
        summary: RecVerificationSummary.fromJson(j),
      );
}

class RecDocument {
  final String id;
  final String documentType;
  final String documentName;
  final String fileName;
  final String mimeType;
  final int fileSize;
  final String status;
  final String rejectReason;
  final String uploadedAt;

  RecDocument({
    required this.id,
    required this.documentType,
    required this.documentName,
    required this.fileName,
    required this.mimeType,
    required this.fileSize,
    required this.status,
    required this.rejectReason,
    required this.uploadedAt,
  });

  factory RecDocument.fromJson(Map<String, dynamic> j) => RecDocument(
        id: _s(j['id'] ?? j['_id']),
        documentType: _s(j['documentType']),
        documentName: _s(j['documentName']),
        fileName: _s(j['fileName']),
        mimeType: _s(j['mimeType']),
        fileSize: _i(j['fileSize']),
        status: _s(j['status'], 'Pending Review'),
        rejectReason: _s(j['rejectReason']),
        uploadedAt: _s(j['uploadedAt']),
      );
}

class RecChecklistItem {
  final String documentType;
  final String name;
  final String description;
  final bool isAdditional;
  final bool isRequested;
  final RecDocument? document;

  RecChecklistItem({
    required this.documentType,
    required this.name,
    required this.description,
    required this.isAdditional,
    required this.isRequested,
    required this.document,
  });

  factory RecChecklistItem.fromJson(Map<String, dynamic> j) => RecChecklistItem(
        documentType: _s(j['documentType']),
        name: _s(j['name']),
        description: _s(j['description']),
        isAdditional: _b(j['isAdditional']),
        isRequested: _b(j['isRequested']),
        document: j['document'] is Map ? RecDocument.fromJson(_m(j['document'])) : null,
      );
}

class RecCandidateDocuments {
  final Map<String, dynamic> candidate;
  final List<RecChecklistItem> checklist;
  final RecVerificationSummary summary;

  RecCandidateDocuments({required this.candidate, required this.checklist, required this.summary});

  String c(String key) => _s(candidate[key]);
  String get fullName => '${c('firstName')} ${c('lastName')}'.trim();

  factory RecCandidateDocuments.fromJson(Map<String, dynamic> j) => RecCandidateDocuments(
        candidate: _m(j['candidate']),
        checklist: _ml(j['checklist']).map(RecChecklistItem.fromJson).toList(),
        summary: RecVerificationSummary.fromJson(_m(j['summary'])),
      );
}

// ───────────────────────────── Offer letters ─────────────────────────────

class RecOfferTemplate {
  final String id;
  final String name;
  final String subject;
  final String body;
  final String salaryTemplateId;
  final bool showMonthlySalary;
  final bool showAnnualSalary;
  final bool isDefault;
  final bool isSystem;
  final String updatedAt;

  RecOfferTemplate({
    required this.id,
    required this.name,
    required this.subject,
    required this.body,
    required this.salaryTemplateId,
    required this.showMonthlySalary,
    required this.showAnnualSalary,
    required this.isDefault,
    required this.isSystem,
    required this.updatedAt,
  });

  factory RecOfferTemplate.fromJson(Map<String, dynamic> j) => RecOfferTemplate(
        id: _s(j['_id'] ?? j['id']),
        name: _s(j['name']),
        subject: _s(j['subject']),
        body: _s(j['body']),
        salaryTemplateId: _s(j['salaryTemplateId']),
        showMonthlySalary: j['showMonthlySalary'] != false,
        showAnnualSalary: j['showAnnualSalary'] != false,
        isDefault: _b(j['isDefault']),
        isSystem: _b(j['isSystem']),
        updatedAt: _s(j['updatedAt']),
      );
}

class RecSalaryTemplateOption {
  final String id;
  final String title;
  RecSalaryTemplateOption({required this.id, required this.title});
  factory RecSalaryTemplateOption.fromJson(Map<String, dynamic> j) =>
      RecSalaryTemplateOption(id: _s(j['_id'] ?? j['id']), title: _s(j['title'] ?? j['name']));
}

class RecCompensationRow {
  final String kind;
  final String label;
  final double? monthly;
  final double? annual;
  RecCompensationRow({required this.kind, required this.label, this.monthly, this.annual});
  factory RecCompensationRow.fromJson(Map<String, dynamic> j) => RecCompensationRow(
        kind: _s(j['kind'], 'item'),
        label: _s(j['label']),
        monthly: _d(j['monthly']),
        annual: _d(j['annual']),
      );
}

class RecOfferAttachment {
  final int index;
  final String fileName;
  final String mimeType;
  final bool isLetter;
  RecOfferAttachment({required this.index, required this.fileName, required this.mimeType, required this.isLetter});
  factory RecOfferAttachment.fromJson(Map<String, dynamic> j) => RecOfferAttachment(
        index: _i(j['index']),
        fileName: _s(j['fileName']),
        mimeType: _s(j['mimeType']),
        isLetter: _b(j['isLetter']),
      );
}

class RecIssuedOffer {
  final String id;
  final String templateName;
  final String designation;
  final double annualCTC;
  final double basicSalary;
  final String salaryTemplateTitle;
  final String status;
  final String offerDate;
  final String joiningDate;
  final String validTill;
  final String sentAt;
  final String sentTo;
  final String subject;
  final String body;
  final List<RecCompensationRow> compensation;
  final String respondedAt;
  final String revokedAt;
  final String responseReason;
  final List<RecOfferAttachment> attachments;
  final String createdAt;

  RecIssuedOffer({
    required this.id,
    required this.templateName,
    required this.designation,
    required this.annualCTC,
    required this.basicSalary,
    required this.salaryTemplateTitle,
    required this.status,
    required this.offerDate,
    required this.joiningDate,
    required this.validTill,
    required this.sentAt,
    required this.sentTo,
    required this.subject,
    required this.body,
    required this.compensation,
    required this.respondedAt,
    required this.revokedAt,
    required this.responseReason,
    required this.attachments,
    required this.createdAt,
  });

  factory RecIssuedOffer.fromJson(Map<String, dynamic> j) => RecIssuedOffer(
        id: _s(j['_id'] ?? j['id']),
        templateName: _s(j['templateName']),
        designation: _s(j['designation']),
        annualCTC: _d(j['annualCTC']) ?? 0,
        basicSalary: _d(j['basicSalary']) ?? 0,
        salaryTemplateTitle: _s(j['salaryTemplateTitle']),
        status: _s(j['status'], 'Draft'),
        offerDate: recDateKey(j['offerDate']),
        joiningDate: recDateKey(j['joiningDate']),
        validTill: recDateKey(j['validTill']),
        sentAt: _s(j['sentAt']),
        sentTo: _s(j['sentTo']),
        subject: _s(j['subject']),
        body: _s(j['body']),
        compensation: _ml(j['compensation']).map(RecCompensationRow.fromJson).toList(),
        respondedAt: _s(j['respondedAt']),
        revokedAt: _s(j['revokedAt']),
        responseReason: _s(j['responseReason']),
        attachments: _ml(j['attachments']).map(RecOfferAttachment.fromJson).toList(),
        createdAt: _s(j['createdAt']),
      );
}

class RecSentOffer {
  final String candidateId;
  final String lastSentAt;
  final String latestStatus;
  RecSentOffer({required this.candidateId, required this.lastSentAt, required this.latestStatus});
  factory RecSentOffer.fromJson(Map<String, dynamic> j) => RecSentOffer(
        candidateId: _s(j['candidateId']),
        lastSentAt: _s(j['lastSentAt']),
        latestStatus: _s(j['latestStatus']),
      );
}

class RecOfferPreview {
  final String subject;
  final String body;
  final List<RecCompensationRow> compensation;
  final double annualCTC;
  final double monthlyGross;
  final double monthlyNet;

  RecOfferPreview({
    required this.subject,
    required this.body,
    required this.compensation,
    required this.annualCTC,
    required this.monthlyGross,
    required this.monthlyNet,
  });

  factory RecOfferPreview.fromJson(Map<String, dynamic> j) {
    final totals = _m(j['totals']);
    return RecOfferPreview(
      subject: _s(j['subject']),
      body: _s(j['body']),
      compensation: _ml(j['compensation']).map(RecCompensationRow.fromJson).toList(),
      annualCTC: _d(totals['annualCTC']) ?? 0,
      monthlyGross: _d(totals['monthlyGross']) ?? 0,
      monthlyNet: _d(totals['monthlyNet']) ?? 0,
    );
  }
}

// ───────────────────────────── Communications ─────────────────────────────

class RecCommChannel {
  final String channel;
  final String label;
  final String description;
  final bool available;
  final bool enabled;
  RecCommChannel({required this.channel, required this.label, required this.description, required this.available, required this.enabled});
  factory RecCommChannel.fromJson(Map<String, dynamic> j) => RecCommChannel(
        channel: _s(j['channel']),
        label: _s(j['label']),
        description: _s(j['description']),
        available: _b(j['available']),
        enabled: _b(j['enabled']),
      );
}

class RecCommCandidate {
  final String id;
  final String candidateCode;
  final String name;
  final String email;
  final String position;
  final String status;
  final int total;
  final int delivered;
  final int failed;
  final int skipped;
  final String lastAt;
  final String lastSubject;
  final String lastEventLabel;
  final String lastStatus;

  RecCommCandidate({
    required this.id,
    required this.candidateCode,
    required this.name,
    required this.email,
    required this.position,
    required this.status,
    required this.total,
    required this.delivered,
    required this.failed,
    required this.skipped,
    required this.lastAt,
    required this.lastSubject,
    required this.lastEventLabel,
    required this.lastStatus,
  });

  factory RecCommCandidate.fromJson(Map<String, dynamic> j) => RecCommCandidate(
        id: _s(j['id']),
        candidateCode: _s(j['candidateCode']),
        name: _s(j['name']),
        email: _s(j['email']),
        position: _s(j['position']),
        status: _s(j['status']),
        total: _i(j['total']),
        delivered: _i(j['delivered']),
        failed: _i(j['failed']),
        skipped: _i(j['skipped']),
        lastAt: _s(j['lastAt']),
        lastSubject: _s(j['lastSubject']),
        lastEventLabel: _s(j['lastEventLabel']),
        lastStatus: _s(j['lastStatus']),
      );
}

class RecCommLog {
  final String id;
  final String channel;
  final String eventLabel;
  final String reason;
  final String recipient;
  final String recipientName;
  final String recipientType;
  final String subject;
  final String preview;
  final List<String> attachments;
  final String status;
  final String error;
  final String triggeredBy;
  final String sentAt;

  RecCommLog({
    required this.id,
    required this.channel,
    required this.eventLabel,
    required this.reason,
    required this.recipient,
    required this.recipientName,
    required this.recipientType,
    required this.subject,
    required this.preview,
    required this.attachments,
    required this.status,
    required this.error,
    required this.triggeredBy,
    required this.sentAt,
  });

  factory RecCommLog.fromJson(Map<String, dynamic> j) => RecCommLog(
        id: _s(j['id']),
        channel: _s(j['channel']),
        eventLabel: _s(j['eventLabel'] ?? j['event']),
        reason: _s(j['reason']),
        recipient: _s(j['recipient']),
        recipientName: _s(j['recipientName']),
        recipientType: _s(j['recipientType']),
        subject: _s(j['subject']),
        preview: _s(j['preview']),
        attachments: _sl(j['attachments']),
        status: _s(j['status']),
        error: _s(j['error']),
        triggeredBy: _s(j['triggeredBy']),
        sentAt: _s(j['sentAt']),
      );
}

class RecPage<T> {
  final List<T> rows;
  final int total;
  final int page;
  final int limit;
  final Map<String, dynamic> extra;
  RecPage({required this.rows, required this.total, required this.page, required this.limit, this.extra = const {}});
}
