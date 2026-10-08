// lib/screens/admin/recruitment/admin_convert_to_staff_screen.dart
// Convert a candidate (offer accepted, documents verified or skipped) to staff:
// POST /documents/candidates/:id/convert-to-staff with joiningDate, onboardingDate,
// designation, department, branchId, employmentType, jobRole and subscriptionPlanName.

import 'package:flutter/material.dart';

import '../../../config/app_colors.dart';
import '../../../models/admin_recruitment_models.dart';
import '../../../services/admin_recruitment_service.dart';
import 'rec_widgets.dart';

// Same choices as Add Staff (backend STAFF_* lists)
const List<String> _designations = ['Junior', 'Senior', 'Team Lead', 'Manager'];
const Map<String, String> _departments = {'Engineering': 'IT', 'Design': 'Marketing', 'HR': 'HR', 'Sales': 'Sales'};
const List<String> _employmentTypes = ['Full Time', 'Part Time', 'Contract', 'Intern'];
const Map<String, String> _departmentFromJob = {'IT': 'Engineering', 'Marketing': 'Design', 'HR': 'HR', 'Sales': 'Sales'};
const Map<String, String> _employmentFromJob = {
  'Full-time': 'Full Time',
  'Part-time': 'Part Time',
  'Contract': 'Contract',
  'Internship': 'Intern',
};

class AdminConvertToStaffScreen extends StatefulWidget {
  final String candidateId;
  const AdminConvertToStaffScreen({super.key, required this.candidateId});

  @override
  State<AdminConvertToStaffScreen> createState() => _AdminConvertToStaffScreenState();
}

class _AdminConvertToStaffScreenState extends State<AdminConvertToStaffScreen> {
  final AdminRecruitmentService _service = AdminRecruitmentService();
  final _formKey = GlobalKey<FormState>();

  RecCandidateDocuments? _d;
  List<RecBranchOption> _branches = [];
  List<Map<String, dynamic>> _plans = [];
  bool _loading = true;
  String? _error;
  bool _saving = false;

  String _joining = recTodayKey();
  String _onboarding = recTodayKey();
  String? _designation;
  String? _department;
  String? _branchId;
  String _employmentType = 'Full Time';
  final _jobRole = TextEditingController();
  String? _plan;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _jobRole.dispose();
    super.dispose();
  }

  ({int used, int total, bool full}) _seats(Map<String, dynamic> p) {
    final used = p['activeUsers'] is List ? (p['activeUsers'] as List).length : 0;
    final total = num.tryParse('${p['totalSeat'] ?? 0}')?.toInt() ?? 0;
    return (used: used, total: total, full: total > 0 && used >= total);
  }

  String _planLabel(Map<String, dynamic> p) {
    final s = _seats(p);
    final name = '${p['planName']}';
    if (s.total <= 0) return '$name - unlimited seats';
    final left = (s.total - s.used).clamp(0, s.total);
    return '$name - $left seat${left == 1 ? '' : 's'} left (${s.used}/${s.total})';
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final dF = _service.getCandidateDocuments(widget.candidateId);
      final bF = _service.getBranches();
      final pF = _service.getSubscriptionPlans();
      final d = await dF;
      final b = await bF;
      final p = await pF;
      if (!mounted) return;
      setState(() {
        _d = d;
        _branches = b;
        _plans = p;
        _department = _departmentFromJob[d.c('department')];
        _employmentType = _employmentFromJob[d.c('jobEmploymentType')] ?? 'Full Time';
        _jobRole.text = d.c('position');
        _branchId = b.any((x) => x.id == d.c('jobBranchId')) ? d.c('jobBranchId') : b.firstOrNull?.id;
        _plan = p.where((x) => !_seats(x).full).map((x) => '${x['planName']}').firstOrNull;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  bool get _needsOnboarding => _employmentType == 'Full Time' || _employmentType == 'Part Time';

  Future<void> _submit({bool retry = false}) async {
    if (!retry) {
      if (!(_formKey.currentState?.validate() ?? false)) return;
      if (_branchId == null) {
        recShowError(context, 'Please select a branch.');
        return;
      }
      if (_plan == null) {
        recShowError(context, 'Every subscription plan is full - free a seat or upgrade the plan.');
        return;
      }
    }
    final ok = await recConfirm(context,
        title: retry ? 'Finish conversion?' : 'Convert to staff?',
        message: retry
            ? 'The staff record exists; the remaining documents are moved to it.'
            : 'A staff record is created for ${_d!.fullName}, their documents move to it and the candidate is marked Hired.',
        confirmLabel: 'Convert');
    if (!ok) return;
    setState(() => _saving = true);
    try {
      final msg = await _service.convertCandidateToStaff(
        widget.candidateId,
        retry
            ? {}
            : {
                'joiningDate': _joining,
                if (_needsOnboarding) 'onboardingDate': _onboarding,
                'designation': _designation,
                'department': _department,
                'branchId': _branchId,
                'employmentType': _employmentType,
                'jobRole': _jobRole.text.trim(),
                'subscriptionPlanName': _plan,
              },
      );
      if (!mounted) return;
      recShowSuccess(context, msg);
      await _load();
    } catch (e) {
      if (mounted) recShowError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    return Scaffold(
      backgroundColor: kRecBg,
      appBar: recAppBar(context, 'Convert to Staff', onRefresh: _load),
      body: RecAsyncBody(
        loading: _loading,
        error: _error,
        isEmpty: d == null,
        emptyText: 'Candidate not found',
        onRetry: _load,
        builder: () {
          final stage = d!.c('verificationStage').isEmpty ? 'pending' : d.c('verificationStage');
          final converted = stage == 'converted';
          final partial = !converted && d.c('staffId').isNotEmpty;
          final ready = d.c('status') == 'Offer Accepted' &&
              (d.c('documentsSkippedAt').isNotEmpty || (d.c('documentsSavedAt').isNotEmpty && d.summary.readyToSave));
          return Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                RecCard(
                  child: Row(children: [
                    RecAvatar(d.fullName, size: 44),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(d.fullName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: kRecInk)),
                          const SizedBox(height: 2),
                          Text('${d.c('position')} • ${d.c('email')}', style: const TextStyle(fontSize: 12.5, color: kRecMuted)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    RecBadge(stage == 'pending' ? 'Ready to Convert' : (kVerificationStageLabels[stage] ?? stage),
                        colorKey: stage == 'pending' ? 'scheduled' : kVerificationStageLabels[stage]),
                  ]),
                ),
                if (converted)
                  RecCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(children: [
                          Icon(Icons.check_circle_outline_rounded, size: 20, color: AppColors.success),
                          SizedBox(width: 8),
                          Text('Converted to staff', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.success)),
                        ]),
                        const SizedBox(height: 8),
                        Text('Staff record: ${d.c('staffId')}', style: const TextStyle(fontSize: 12.5, color: kRecMuted)),
                        const Text('Manage the employee from Staff.', style: TextStyle(fontSize: 12.5, color: kRecMuted)),
                      ],
                    ),
                  )
                else if (partial)
                  RecCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text('The staff record was created but some documents did not move.',
                            style: TextStyle(fontSize: 13.5, color: AppColors.brandDark, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 12),
                        RecPrimaryButton(
                            label: 'Move remaining documents', icon: Icons.drive_file_move_outline, busy: _saving, onPressed: () => _submit(retry: true)),
                      ],
                    ),
                  )
                else if (stage == 'verificationReject' || stage == 'verificationBlacklist')
                  const RecCard(
                    child: Text('This candidate was rejected during verification and cannot be converted.',
                        style: TextStyle(fontSize: 13.5, color: AppColors.error, fontWeight: FontWeight.w500)),
                  )
                else if (!ready)
                  RecCard(
                    child: Text(
                      d.c('status') != 'Offer Accepted'
                          ? 'Only a candidate who accepted the offer can be converted (current status: ${d.c('status')}).'
                          : 'Save the document verification (every document approved) or skip the documents before converting.',
                      style: const TextStyle(fontSize: 13.5, color: AppColors.brandDark, fontWeight: FontWeight.w500),
                    ),
                  )
                else
                  RecCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const RecSectionTitle('Staff details'),
                        Row(children: [
                          Expanded(
                            child: RecPickerField(
                              label: 'Joining date *',
                              value: recFormatDate(_joining),
                              onTap: () async {
                                final v = await recPickDate(context, initial: _joining);
                                if (v != null) setState(() => _joining = v);
                              },
                            ),
                          ),
                          if (_needsOnboarding) ...[
                            const SizedBox(width: 12),
                            Expanded(
                              child: RecPickerField(
                                label: 'Onboarding date *',
                                value: recFormatDate(_onboarding),
                                onTap: () async {
                                  final v = await recPickDate(context, initial: _onboarding);
                                  if (v != null) setState(() => _onboarding = v);
                                },
                              ),
                            ),
                          ],
                        ]),
                        RecDropdown<String>(
                          label: 'Employment type *',
                          value: _employmentType,
                          items: _employmentTypes,
                          labelOf: (s) => s,
                          onChanged: (v) => setState(() => _employmentType = v ?? _employmentType),
                        ),
                        RecDropdown<String>(
                          label: 'Designation *',
                          value: _designation,
                          items: _designations,
                          labelOf: (s) => s,
                          validator: (v) => v == null ? 'Required' : null,
                          onChanged: (v) => setState(() => _designation = v),
                        ),
                        RecDropdown<String>(
                          label: 'Department *',
                          value: _department,
                          items: _departments.keys.toList(),
                          labelOf: (k) => _departments[k]!,
                          validator: (v) => v == null ? 'Required' : null,
                          onChanged: (v) => setState(() => _department = v),
                        ),
                        RecTextField(controller: _jobRole, label: 'Job role *', validator: recRequired),
                        if (_branches.isEmpty)
                          const Padding(
                            padding: EdgeInsets.only(bottom: 12),
                            child: Text('No branches configured - create one in Settings.', style: TextStyle(fontSize: 12, color: AppColors.error)),
                          )
                        else
                          RecDropdown<String>(
                            label: 'Branch *',
                            value: _branchId,
                            items: _branches.map((b) => b.id).toList(),
                            labelOf: (id) {
                              final b = _branches.firstWhere((x) => x.id == id);
                              return b.code.isEmpty ? b.name : '${b.name} (${b.code})';
                            },
                            onChanged: (v) => setState(() => _branchId = v),
                          ),
                        if (_plans.isEmpty)
                          const Padding(
                            padding: EdgeInsets.only(bottom: 12),
                            child: Text('There is no active subscription plan with seats. Contact your SuperAdmin.',
                                style: TextStyle(fontSize: 12, color: AppColors.error)),
                          )
                        else
                          RecDropdown<String>(
                            label: 'Subscription plan (seat) *',
                            value: _plan,
                            items: _plans.where((p) => !_seats(p).full).map((p) => '${p['planName']}').toList(),
                            labelOf: (name) => _planLabel(_plans.firstWhere((p) => '${p['planName']}' == name)),
                            onChanged: (v) => setState(() => _plan = v),
                          ),
                        const SizedBox(height: 4),
                        SizedBox(
                          height: 52,
                          child: RecPrimaryButton(label: 'Convert to staff', icon: Icons.badge_outlined, busy: _saving, onPressed: _submit),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
