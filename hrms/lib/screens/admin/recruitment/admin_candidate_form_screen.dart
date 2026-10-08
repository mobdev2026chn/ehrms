// lib/screens/admin/recruitment/admin_candidate_form_screen.dart
// Add (POST /candidates, with jobOpeningId + portal password) or edit (PUT /candidates/:id)
// a candidate. Supports AI resume parsing (POST /candidates/parse-resume).

import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../config/app_colors.dart';
import '../../../models/admin_recruitment_models.dart';
import '../../../services/admin_recruitment_service.dart';
import 'rec_widgets.dart';

const List<String> kGenders = ['Male', 'Female', 'Non-binary', 'Prefer not to say'];

class AdminCandidateFormScreen extends StatefulWidget {
  /// Null to add a new candidate.
  final RecCandidate? candidate;
  const AdminCandidateFormScreen({super.key, this.candidate});

  @override
  State<AdminCandidateFormScreen> createState() => _AdminCandidateFormScreenState();
}

class _AdminCandidateFormScreenState extends State<AdminCandidateFormScreen> {
  final AdminRecruitmentService _service = AdminRecruitmentService();
  final _formKey = GlobalKey<FormState>();

  final _first = TextEditingController();
  final _last = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _city = TextEditingController();
  final _prefLocation = TextEditingController();
  final _skill = TextEditingController();
  final _experienceYears = TextEditingController(text: '0');
  final _position = TextEditingController();
  final _password = TextEditingController();

  String _dob = '';
  String _gender = 'Prefer not to say';
  String _source = 'Manual';
  String? _status;
  String? _jobId;
  bool _showPassword = false;

  List<Map<String, dynamic>> _education = [];
  List<Map<String, dynamic>> _experience = [];
  List<Map<String, dynamic>> _courses = [];
  List<Map<String, dynamic>> _internships = [];

  RecPickedFile? _resume;
  bool _parsing = false;
  bool _saving = false;

  List<RecJobOpening> _jobs = [];
  bool _loadingJobs = true;
  String? _jobsError;

  bool get _isEdit => widget.candidate != null;

  @override
  void initState() {
    super.initState();
    final c = widget.candidate;
    if (c != null) {
      _first.text = c.firstName;
      _last.text = c.lastName;
      _email.text = c.email;
      _phone.text = c.phone;
      _city.text = c.currentCity;
      _prefLocation.text = c.preferredJobLocation;
      _skill.text = c.primarySkill;
      _experienceYears.text = '${c.experienceYears}';
      _position.text = c.position;
      _dob = c.dob;
      _gender = kGenders.contains(c.gender) ? c.gender : 'Prefer not to say';
      _source = kCandidateSources.contains(c.source) ? c.source : 'Manual';
      _status = c.status;
      _jobId = c.jobOpeningId.isEmpty ? null : c.jobOpeningId;
      _education = c.education.map((e) => Map<String, dynamic>.from(e)).toList();
      _experience = c.experience.map((e) => Map<String, dynamic>.from(e)).toList();
      _courses = c.courses;
      _internships = c.internships;
      _loadingJobs = false;
    } else {
      _loadJobs();
    }
  }

  @override
  void dispose() {
    for (final c in [_first, _last, _email, _phone, _city, _prefLocation, _skill, _experienceYears, _position, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadJobs() async {
    setState(() {
      _loadingJobs = true;
      _jobsError = null;
    });
    try {
      final jobs = await _service.getJobOpenings(status: 'ACTIVE');
      if (!mounted) return;
      setState(() {
        _jobs = jobs;
        _loadingJobs = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _jobsError = e.toString();
        _loadingJobs = false;
      });
    }
  }

  Future<void> _pickResume() async {
    final file = await recPickFile(context, const ['pdf', 'doc', 'docx']);
    if (file == null || !mounted) return;
    setState(() {
      _resume = file;
      _parsing = true;
    });
    try {
      final data = await _service.parseResume(bytes: file.bytes, fileName: file.name, mimeType: file.mimeType);
      if (!mounted) return;
      final pd = data['personalDetails'] is Map ? Map<String, dynamic>.from(data['personalDetails']) : <String, dynamic>{};
      String v(dynamic x) => x == null ? '' : x.toString();
      setState(() {
        if (v(pd['firstName']).isNotEmpty) _first.text = v(pd['firstName']);
        if (v(pd['lastName']).isNotEmpty) _last.text = v(pd['lastName']);
        if (v(pd['email']).isNotEmpty) _email.text = v(pd['email']);
        if (v(pd['phone']).isNotEmpty) {
          final digits = v(pd['phone']).replaceAll(RegExp(r'\D'), '');
          _phone.text = digits.length > 10 ? digits.substring(digits.length - 10) : digits;
        }
        if (v(pd['dateOfBirth']).isNotEmpty && DateTime.tryParse(v(pd['dateOfBirth'])) != null) {
          _dob = recDateKey(v(pd['dateOfBirth']));
        }
        if (kGenders.contains(v(pd['gender']))) _gender = v(pd['gender']);
        if (v(pd['currentCity']).isNotEmpty) _city.text = v(pd['currentCity']);
        if (v(pd['preferredJobLocation']).isNotEmpty) _prefLocation.text = v(pd['preferredJobLocation']);
        final skills = data['skills'] is Map ? data['skills'] as Map : const {};
        if (v(skills['primarySkill']).isNotEmpty) _skill.text = v(skills['primarySkill']);
        List<Map<String, dynamic>> list(dynamic x) =>
            x is List ? x.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : [];
        if (list(data['education']).isNotEmpty) _education = list(data['education']);
        if (list(data['experience']).isNotEmpty) {
          _experience = list(data['experience']);
          _experienceYears.text = '${_experience.length}';
        }
        if (list(data['courses']).isNotEmpty) _courses = list(data['courses']);
        if (list(data['internships']).isNotEmpty) _internships = list(data['internships']);
      });
      recShowSuccess(context, 'Resume read - please review the details');
    } catch (e) {
      if (mounted) recShowError(context, e);
    } finally {
      if (mounted) setState(() => _parsing = false);
    }
  }

  String? _validateEducation() {
    final maxYear = DateTime.now().year + 5;
    for (var i = 0; i < _education.length; i++) {
      final y = (_education[i]['yearOfPassing'] ?? '').toString().trim();
      final n = int.tryParse(y);
      if (y.length != 4 || n == null || n < 1950 || n > maxYear) {
        return 'Education entry #${i + 1}: year of passing must be between 1950 and $maxYear.';
      }
    }
    return null;
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final eduError = _validateEducation();
    if (eduError != null) {
      recShowError(context, eduError);
      return;
    }
    if (!_isEdit && _jobId == null) {
      recShowError(context, 'Please select the job opening the candidate is applying for.');
      return;
    }

    final payload = <String, dynamic>{
      'firstName': _first.text.trim(),
      'lastName': _last.text.trim(),
      'email': _email.text.trim(),
      'phone': _phone.text.trim(),
      if (_dob.isNotEmpty) 'dob': _dob,
      'gender': _gender,
      'currentCity': _city.text.trim(),
      'preferredJobLocation': _prefLocation.text.trim(),
      'primarySkill': _skill.text.trim().isEmpty ? 'N/A' : _skill.text.trim(),
      'experienceYears': num.tryParse(_experienceYears.text.trim()) ?? 0,
      'source': _source,
      'education': _education,
      'experience': _experience,
      'courses': _courses,
      'internships': _internships,
    };

    setState(() => _saving = true);
    try {
      if (_isEdit) {
        final c = widget.candidate!;
        payload['position'] = _position.text.trim();
        // Only a status the admin changed here - re-sending the loaded one could undo an offer answer
        if (_status != null && _status != c.status) payload['status'] = _status;
        final msg = await _service.updateCandidate(c.id, payload);
        if (!mounted) return;
        recShowSuccess(context, msg);
        Navigator.pop(context, true);
      } else {
        payload['jobOpeningId'] = _jobId;
        payload['status'] = 'Applied';
        payload['password'] = _password.text;
        if (_resume != null) {
          payload['resumeName'] = _resume!.name;
          payload['resumeUrl'] = 'data:${_resume!.mimeType};base64,${base64Encode(_resume!.bytes)}';
        }
        final res = await _service.createCandidate(payload);
        if (!mounted) return;
        await _showCredentials(res);
        if (mounted) Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) recShowError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _showCredentials(Map<String, dynamic> res) async {
    final password = res['password'];
    final emailSent = res['emailSent'] == true;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Candidate added'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RecInfoRow('Username', _email.text.trim().toLowerCase()),
            RecInfoRow('Password', password == null ? "The candidate's existing portal password" : password.toString()),
            if ((res['loginUrl'] ?? '').toString().isNotEmpty) RecInfoRow('Login', res['loginUrl'].toString()),
            const SizedBox(height: 12),
            RecNotice(
              emailSent ? 'The login details were emailed to the candidate.' : 'The email could not be sent - share the login details yourself.',
              color: emailSent ? AppColors.success : AppColors.error,
              background: emailSent ? AppColors.successBg : AppColors.errorBg,
              icon: emailSent ? Icons.mark_email_read_outlined : Icons.error_outline_rounded,
              margin: EdgeInsets.zero,
            ),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kRecBg,
      appBar: recAppBar(context, _isEdit ? 'Edit Candidate' : 'Add Candidate'),
      bottomNavigationBar: RecBottomBar(
        child: RecPrimaryButton(
          label: _isEdit ? 'Save Changes' : 'Add Candidate',
          icon: Icons.check_rounded,
          busy: _saving,
          onPressed: _parsing ? null : _save,
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (!_isEdit) _resumeCard(),
            _section('Application', [
              if (_isEdit) ...[
                RecTextField(controller: _position, label: 'Position'),
                RecDropdown<String>(
                  label: 'Status',
                  value: _status,
                  items: kCandidateStatuses,
                  labelOf: (s) => s,
                  onChanged: (v) => setState(() => _status = v),
                ),
              ] else if (_loadingJobs)
                const Padding(padding: EdgeInsets.only(bottom: 12), child: LinearProgressIndicator())
              else if (_jobsError != null)
                Row(children: [
                  const Icon(Icons.error_outline_rounded, size: 18, color: AppColors.error),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_jobsError!, style: const TextStyle(fontSize: 13, color: AppColors.error))),
                  TextButton(onPressed: _loadJobs, child: const Text('Retry')),
                ])
              else if (_jobs.isEmpty)
                const RecNotice('There are no ACTIVE job openings. Activate a job opening first.',
                    color: AppColors.error, background: AppColors.errorBg, icon: Icons.error_outline_rounded)
              else
                RecDropdown<String>(
                  label: 'Job opening *',
                  value: _jobId,
                  items: _jobs.map((j) => j.id).toList(),
                  labelOf: (id) {
                    final j = _jobs.firstWhere((x) => x.id == id);
                    return '${j.title} (${j.code})';
                  },
                  validator: (v) => v == null ? 'Required' : null,
                  onChanged: (v) => setState(() => _jobId = v),
                ),
              RecDropdown<String>(
                label: 'Source',
                value: _source,
                items: kCandidateSources,
                labelOf: (s) => s,
                onChanged: (v) => setState(() => _source = v ?? _source),
              ),
            ]),
            _section('Personal details', [
              Row(children: [
                Expanded(child: RecTextField(controller: _first, label: 'First name *', validator: recRequired)),
                const SizedBox(width: 12),
                Expanded(child: RecTextField(controller: _last, label: 'Last name *', validator: recRequired)),
              ]),
              RecTextField(
                controller: _email,
                label: 'Email *',
                keyboardType: TextInputType.emailAddress,
                validator: (v) {
                  if (recRequired(v) != null) return 'Required';
                  return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v!.trim()) ? null : 'Enter a valid email';
                },
              ),
              RecTextField(controller: _phone, label: 'Phone *', keyboardType: TextInputType.phone, validator: recRequired),
              RecPickerField(
                label: 'Date of birth',
                value: _dob.isEmpty ? '' : recFormatDate(_dob),
                onTap: () async {
                  final d = await recPickDate(context, initial: _dob.isEmpty ? '2000-01-01' : _dob, lastDate: DateTime.now());
                  if (d != null) setState(() => _dob = d);
                },
                onClear: () => setState(() => _dob = ''),
              ),
              RecDropdown<String>(
                label: 'Gender',
                value: _gender,
                items: kGenders,
                labelOf: (s) => s,
                onChanged: (v) => setState(() => _gender = v ?? _gender),
              ),
              RecTextField(controller: _city, label: 'Current city'),
              RecTextField(controller: _prefLocation, label: 'Preferred job location'),
              RecTextField(controller: _skill, label: 'Primary skill'),
              RecTextField(controller: _experienceYears, label: 'Experience (years)', keyboardType: TextInputType.number),
            ]),
            if (!_isEdit)
              _section('Candidate portal login', [
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text(
                    'The candidate signs in to the candidate portal with their email and this password. '
                    'If the email already has a candidate account, its own password is kept.',
                    style: TextStyle(fontSize: 12.5, color: kRecMuted, height: 1.45),
                  ),
                ),
                RecTextField(
                  controller: _password,
                  label: 'Password * (8-64 characters)',
                  obscure: !_showPassword,
                  suffix: IconButton(
                    tooltip: _showPassword ? 'Hide password' : 'Show password',
                    icon: Icon(_showPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20),
                    onPressed: () => setState(() => _showPassword = !_showPassword),
                  ),
                  validator: (v) {
                    final s = v ?? '';
                    if (s.isEmpty) return 'Required';
                    if (s.length < 8) return 'At least 8 characters';
                    if (s.length > 64) return 'At most 64 characters';
                    return null;
                  },
                ),
              ]),
            _listSection(
              title: 'Education',
              items: _education,
              summary: (e) => '${e['qualification'] ?? ''} ${e['courseName'] ?? ''}'.trim(),
              detail: (e) => '${e['institution'] ?? ''} • ${e['yearOfPassing'] ?? ''}',
              onEdit: (i) => _editEducation(i),
              onAdd: () => _editEducation(null),
            ),
            _listSection(
              title: 'Work experience',
              items: _experience,
              summary: (e) => '${e['role'] ?? ''} at ${e['company'] ?? ''}',
              detail: (e) => '${e['durationFrom'] ?? ''} - ${(e['durationTo'] ?? '').toString().isEmpty ? 'Present' : e['durationTo']}',
              onEdit: (i) => _editExperience(i),
              onAdd: () => _editExperience(null),
            ),
            if (_courses.isNotEmpty || _internships.isNotEmpty)
              _section('Courses & internships', [
                Text('${_courses.length} course(s), ${_internships.length} internship(s) will be saved as read from the resume.',
                    style: const TextStyle(fontSize: 12.5, color: kRecMuted)),
              ]),
          ],
        ),
      ),
    );
  }

  Widget _resumeCard() {
    return RecCard(
      child: Row(
        children: [
          const RecIconTile(Icons.description_outlined, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_resume?.name ?? 'Upload resume',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: kRecInk)),
                const SizedBox(height: 2),
                Text(
                  _parsing ? 'Reading the resume with AI…' : 'PDF, DOC or DOCX up to 10 MB. Details are filled in automatically.',
                  style: const TextStyle(fontSize: 12.5, color: kRecMuted),
                ),
              ],
            ),
          ),
          if (_parsing)
            const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
          else ...[
            if (_resume != null)
              IconButton(
                  tooltip: 'Remove',
                  icon: const Icon(Icons.close_rounded, size: 20, color: kRecMuted),
                  onPressed: () => setState(() => _resume = null)),
            TextButton(onPressed: _pickResume, child: Text(_resume == null ? 'Choose' : 'Change')),
          ],
        ],
      ),
    );
  }

  Widget _section(String title, List<Widget> children) => RecCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [RecSectionTitle(title), ...children]),
      );

  Widget _listSection({
    required String title,
    required List<Map<String, dynamic>> items,
    required String Function(Map<String, dynamic>) summary,
    required String Function(Map<String, dynamic>) detail,
    required void Function(int) onEdit,
    required VoidCallback onAdd,
  }) {
    return RecCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RecSectionTitle(title,
              trailing: TextButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add', style: TextStyle(fontWeight: FontWeight.w600)),
              )),
          if (items.isEmpty)
            const Text('None added', style: TextStyle(fontSize: 12.5, color: kRecMuted))
          else
            ...List.generate(items.length, (i) {
              final e = items[i];
              return ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(summary(e), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: kRecInk)),
                subtitle: Text(detail(e), style: const TextStyle(fontSize: 12, color: kRecMuted)),
                onTap: () => onEdit(i),
                trailing: IconButton(
                  tooltip: 'Remove',
                  icon: const Icon(Icons.delete_outline_rounded, size: 20, color: AppColors.error),
                  onPressed: () => setState(() => items.removeAt(i)),
                ),
              );
            }),
        ],
      ),
    );
  }

  Future<void> _editEducation(int? index) async {
    final e = index == null ? <String, dynamic>{'gradingType': 'Percentage'} : Map<String, dynamic>.from(_education[index]);
    final result = await _editMapSheet('Education', e, const [
      ('qualification', 'Qualification * (e.g. B.Tech)', true),
      ('courseName', 'Course / specialisation', false),
      ('institution', 'Institution *', true),
      ('university', 'University', false),
      ('yearOfPassing', 'Year of passing * (YYYY)', true),
      ('percentage', 'Percentage', false),
      ('cgpa', 'CGPA', false),
    ]);
    if (result == null) return;
    result['gradingType'] = (result['cgpa'] ?? '').toString().isNotEmpty ? 'CGPA' : 'Percentage';
    setState(() {
      if (index == null) {
        _education.add(result);
      } else {
        _education[index] = result;
      }
    });
  }

  Future<void> _editExperience(int? index) async {
    final e = index == null ? <String, dynamic>{} : Map<String, dynamic>.from(_experience[index]);
    final result = await _editMapSheet('Work experience', e, const [
      ('company', 'Company *', true),
      ('role', 'Role *', true),
      ('durationFrom', 'From * (e.g. 2021-06)', true),
      ('durationTo', 'To (blank = present)', false),
      ('keyResponsibilities', 'Key responsibilities', false),
    ]);
    if (result == null) return;
    setState(() {
      if (index == null) {
        _experience.add(result);
      } else {
        _experience[index] = result;
      }
    });
  }

  Future<Map<String, dynamic>?> _editMapSheet(
      String title, Map<String, dynamic> initial, List<(String, String, bool)> fields) {
    final ctrls = {for (final f in fields) f.$1: TextEditingController(text: (initial[f.$1] ?? '').toString())};
    final key = GlobalKey<FormState>();
    return recShowSheet<Map<String, dynamic>>(
      context,
      title: title,
      builder: (ctx) => Form(
        key: key,
        child: Column(
          children: [
            ...fields.map((f) => RecTextField(
                  controller: ctrls[f.$1]!,
                  label: f.$2,
                  maxLines: f.$1 == 'keyResponsibilities' ? 4 : 1,
                  validator: f.$3 ? recRequired : null,
                )),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: RecPrimaryButton(
                label: 'Done',
                icon: Icons.check_rounded,
                onPressed: () {
                  if (!(key.currentState?.validate() ?? false)) return;
                  final out = Map<String, dynamic>.from(initial);
                  ctrls.forEach((k, c) => out[k] = c.text.trim());
                  Navigator.pop(ctx, out);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
