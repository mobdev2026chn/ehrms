// lib/screens/admin/recruitment/admin_add_job_screen.dart
// Create / edit a job opening (POST/PUT /admin/recruitment/job-openings), with AI description.

import 'package:flutter/material.dart';

import '../../../config/app_colors.dart';
import '../../../models/admin_recruitment_models.dart';
import '../../../services/admin_recruitment_service.dart';
import 'admin_job_openings_screen.dart' show kJobStatuses, kJobDepartments, jobStatusLabel;
import 'rec_widgets.dart';

class AdminAddJobScreen extends StatefulWidget {
  /// Null to create a new job opening.
  final RecJobOpening? job;
  const AdminAddJobScreen({super.key, this.job});

  @override
  State<AdminAddJobScreen> createState() => _AdminAddJobScreenState();
}

class _AdminAddJobScreenState extends State<AdminAddJobScreen> {
  final AdminRecruitmentService _service = AdminRecruitmentService();
  final _formKey = GlobalKey<FormState>();

  final _title = TextEditingController();
  final _positions = TextEditingController(text: '1');
  final _expMin = TextEditingController();
  final _expMax = TextEditingController();
  final _education = TextEditingController(text: "Bachelor's Degree");
  final _salaryMin = TextEditingController();
  final _salaryMax = TextEditingController();
  final _description = TextEditingController();
  final _responsibilities = TextEditingController();
  final _benefits = TextEditingController();
  final _skillInput = TextEditingController();

  String? _department;
  String? _branchId;
  String _workplaceType = 'On-site';
  String _employmentType = 'Full-time';
  String _salaryType = 'Annual';
  String _status = 'DRAFT';
  bool _isPublic = false;
  String _closeDate = '';
  List<String> _skills = [];

  List<RecBranchOption> _branches = [];
  bool _loadingBranches = true;
  String? _branchError;
  bool _saving = false;
  bool _generating = false;

  bool get _isEdit => widget.job != null;

  @override
  void initState() {
    super.initState();
    final j = widget.job;
    if (j != null) {
      _title.text = j.title;
      _positions.text = '${j.positions}';
      _expMin.text = j.experienceMin == null ? '' : _num(j.experienceMin!);
      _expMax.text = j.experienceMax == null ? '' : _num(j.experienceMax!);
      _education.text = j.education;
      _salaryMin.text = j.salaryMin == null ? '' : _num(j.salaryMin!);
      _salaryMax.text = j.salaryMax == null ? '' : _num(j.salaryMax!);
      _description.text = j.description;
      _responsibilities.text = j.responsibilities;
      _benefits.text = j.benefits;
      _department = kJobDepartments.contains(j.department) ? j.department : null;
      _branchId = j.branchId.isEmpty ? null : j.branchId;
      _workplaceType = j.workplaceType;
      _employmentType = j.employmentType;
      _salaryType = j.salaryType;
      _status = j.status;
      _isPublic = j.isPublic;
      _closeDate = j.closeDate;
      _skills = [...j.skills];
    }
    _loadBranches();
  }

  String _num(num v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  @override
  void dispose() {
    for (final c in [
      _title, _positions, _expMin, _expMax, _education, _salaryMin, _salaryMax,
      _description, _responsibilities, _benefits, _skillInput,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadBranches() async {
    setState(() {
      _loadingBranches = true;
      _branchError = null;
    });
    try {
      final b = await _service.getBranches();
      if (!mounted) return;
      setState(() {
        _branches = b;
        _loadingBranches = false;
        if (_branchId == null && b.length == 1) _branchId = b.first.id;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _branchError = e.toString();
        _loadingBranches = false;
      });
    }
  }

  void _addSkill() {
    final s = _skillInput.text.trim();
    if (s.isEmpty) return;
    if (!_skills.any((e) => e.toLowerCase() == s.toLowerCase())) {
      setState(() => _skills.add(s));
    }
    _skillInput.clear();
  }

  Future<void> _generate() async {
    if (_title.text.trim().isEmpty) {
      recShowError(context, 'Fill in the Job Title first so AI can write the description.');
      return;
    }
    setState(() => _generating = true);
    try {
      final branch = _branches.where((b) => b.id == _branchId).toList();
      final g = await _service.generateJobDescription({
        'role': _title.text.trim(),
        'skills': _skills,
        if (_department != null) 'department': _department,
        if (_expMin.text.trim().isNotEmpty) 'minExperience': _expMin.text.trim(),
        if (_expMax.text.trim().isNotEmpty) 'maxExperience': _expMax.text.trim(),
        'employmentType': _employmentType,
        'workplaceType': _workplaceType,
        if (branch.isNotEmpty) 'location': branch.first.name,
        'educationalQualification': _education.text.trim(),
        'numberOfPositions': int.tryParse(_positions.text) ?? 1,
      });
      if (!mounted) return;
      setState(() {
        if (g.description.isNotEmpty) _description.text = g.description;
        if (g.keyResponsibilities.isNotEmpty) _responsibilities.text = g.keyResponsibilities;
        if (g.benefits.isNotEmpty) _benefits.text = g.benefits;
        for (final s in g.skills) {
          if (!_skills.any((e) => e.toLowerCase() == s.toLowerCase())) _skills.add(s);
        }
      });
      recShowSuccess(context, 'Description generated - review it before saving');
    } catch (e) {
      if (mounted) recShowError(context, e);
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _pickCloseDate() async {
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    final d = await recPickDate(context,
        initial: _closeDate.isEmpty ? recDateKeyOf(tomorrow) : _closeDate,
        firstDate: DateTime(tomorrow.year, tomorrow.month, tomorrow.day),
        lastDate: DateTime.now().add(const Duration(days: 730)));
    if (d != null) setState(() => _closeDate = d);
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_branchId == null) {
      recShowError(context, _branches.isEmpty ? 'No branches exist yet. Create a branch in Settings first.' : 'Please select a branch.');
      return;
    }
    final expMin = num.tryParse(_expMin.text.trim());
    final expMax = num.tryParse(_expMax.text.trim());
    if (expMin != null && expMax != null && expMax < expMin) {
      recShowError(context, 'Maximum experience must be at least the minimum.');
      return;
    }
    final salMin = num.tryParse(_salaryMin.text.trim());
    final salMax = num.tryParse(_salaryMax.text.trim());
    if (salMin != null && salMax != null && salMax < salMin) {
      recShowError(context, 'Maximum salary must be at least the minimum.');
      return;
    }

    final payload = <String, dynamic>{
      'title': _title.text.trim(),
      'department': _department,
      'branchId': _branchId,
      'workplaceType': _workplaceType,
      'employmentType': _employmentType,
      'positions': int.tryParse(_positions.text.trim()) ?? 1,
      'experienceMin': expMin ?? 0,
      if (expMax != null) 'experienceMax': expMax,
      'education': _education.text.trim(),
      'skills': _skills,
      if (salMin != null) 'salaryMin': salMin,
      if (salMax != null) 'salaryMax': salMax,
      'salaryType': _salaryType,
      'description': _description.text.trim(),
      'responsibilities': _responsibilities.text.trim(),
      'benefits': _benefits.text.trim(),
      'status': _status,
      'isPublic': _isPublic,
      if (_closeDate.isNotEmpty) 'closeDate': _closeDate,
    };

    setState(() => _saving = true);
    try {
      final msg = _isEdit
          ? await _service.updateJobOpening(widget.job!.id, payload)
          : await _service.createJobOpening(payload);
      if (!mounted) return;
      recShowSuccess(context, msg);
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) recShowError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kRecBg,
      appBar: recAppBar(context, _isEdit ? 'Edit Job Opening' : 'Add Job Opening'),
      bottomNavigationBar: RecBottomBar(
        child: RecPrimaryButton(
          label: _isEdit ? 'Save Changes' : 'Create Job Opening',
          icon: Icons.check_rounded,
          busy: _saving,
          onPressed: _save,
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _section('Basic details', [
              RecTextField(controller: _title, label: 'Job title *', validator: recRequired),
              RecDropdown<String>(
                label: 'Department *',
                value: _department,
                items: kJobDepartments,
                labelOf: (s) => s,
                validator: (v) => v == null ? 'Required' : null,
                onChanged: (v) => setState(() => _department = v),
              ),
              if (_loadingBranches)
                const Padding(padding: EdgeInsets.only(bottom: 12), child: LinearProgressIndicator())
              else if (_branchError != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(children: [
                    const Icon(Icons.error_outline_rounded, size: 18, color: AppColors.error),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_branchError!, style: const TextStyle(fontSize: 13, color: AppColors.error))),
                    TextButton(onPressed: _loadBranches, child: const Text('Retry')),
                  ]),
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
                  validator: (v) => v == null ? 'Required' : null,
                  onChanged: (v) => setState(() => _branchId = v),
                ),
              Row(children: [
                Expanded(
                  child: RecDropdown<String>(
                    label: 'Workplace',
                    value: _workplaceType,
                    items: const ['On-site', 'Remote', 'Hybrid'],
                    labelOf: (s) => s,
                    onChanged: (v) => setState(() => _workplaceType = v ?? _workplaceType),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: RecDropdown<String>(
                    label: 'Employment',
                    value: _employmentType,
                    items: const ['Full-time', 'Part-time', 'Contract', 'Internship'],
                    labelOf: (s) => s,
                    onChanged: (v) => setState(() => _employmentType = v ?? _employmentType),
                  ),
                ),
              ]),
              RecTextField(
                controller: _positions,
                label: 'Number of positions',
                keyboardType: TextInputType.number,
                validator: (v) => (int.tryParse(v ?? '') ?? 0) < 1 ? 'At least 1' : null,
              ),
            ]),
            _section('Qualifications & experience', [
              Row(children: [
                Expanded(child: RecTextField(controller: _expMin, label: 'Min exp (yrs)', keyboardType: TextInputType.number)),
                const SizedBox(width: 12),
                Expanded(child: RecTextField(controller: _expMax, label: 'Max exp (yrs)', keyboardType: TextInputType.number)),
              ]),
              RecTextField(controller: _education, label: 'Education'),
              Row(children: [
                Expanded(
                  child: RecTextField(
                    controller: _skillInput,
                    label: 'Add skill',
                    suffix: IconButton(
                        tooltip: 'Add skill',
                        icon: const Icon(Icons.add_circle_outline_rounded, color: AppColors.brandDark),
                        onPressed: _addSkill),
                  ),
                ),
              ]),
              if (_skills.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text('No skills added yet.', style: TextStyle(fontSize: 12.5, color: kRecMuted)),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _skills
                        .map((s) => Chip(
                              label: Text(s,
                                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.brandDark)),
                              onDeleted: () => setState(() => _skills.remove(s)),
                              deleteIconColor: AppColors.brandDark,
                              backgroundColor: AppColors.brandLight,
                              side: BorderSide.none,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                              visualDensity: VisualDensity.compact,
                            ))
                        .toList(),
                  ),
                ),
            ]),
            _section('Compensation', [
              Row(children: [
                Expanded(child: RecTextField(controller: _salaryMin, label: 'Min salary (₹)', keyboardType: TextInputType.number)),
                const SizedBox(width: 12),
                Expanded(child: RecTextField(controller: _salaryMax, label: 'Max salary (₹)', keyboardType: TextInputType.number)),
              ]),
              RecDropdown<String>(
                label: 'Salary frequency',
                value: _salaryType,
                items: const ['Annual', 'Monthly'],
                labelOf: (s) => s,
                onChanged: (v) => setState(() => _salaryType = v ?? _salaryType),
              ),
            ]),
            _section(
              'Description',
              [
                RecTextField(controller: _description, label: 'Job description', maxLines: 6),
                RecTextField(controller: _responsibilities, label: 'Key responsibilities', maxLines: 6),
                RecTextField(controller: _benefits, label: 'Benefits', maxLines: 4),
              ],
              trailing: TextButton.icon(
                onPressed: _generating ? null : _generate,
                icon: _generating
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.auto_awesome_rounded, size: 18),
                label: const Text('Generate with AI', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                style: TextButton.styleFrom(foregroundColor: AppColors.primaryText),
              ),
            ),
            _section('Settings', [
              RecDropdown<String>(
                label: 'Status',
                value: _status,
                items: kJobStatuses,
                labelOf: jobStatusLabel,
                onChanged: (v) => setState(() => _status = v ?? _status),
              ),
              RecPickerField(
                label: 'Closing date (optional)',
                value: _closeDate.isEmpty ? '' : recFormatDate(_closeDate),
                onTap: _pickCloseDate,
                onClear: () => setState(() => _closeDate = ''),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _isPublic,
                onChanged: (v) => setState(() => _isPublic = v),
                title: const Text('Show on public job board', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: kRecInk)),
                subtitle: const Text('Only ACTIVE openings appear on the board', style: TextStyle(fontSize: 12, color: kRecMuted)),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _section(String title, List<Widget> children, {Widget? trailing}) {
    return RecCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RecSectionTitle(title, trailing: trailing),
          ...children,
        ],
      ),
    );
  }
}
