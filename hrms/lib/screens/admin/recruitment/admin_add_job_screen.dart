// lib/screens/admin/recruitment/admin_add_job_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../config/app_colors.dart';
import '../../../services/admin_staff_service.dart';
import '../../../services/api_client.dart';
import '../../../utils/snackbar_utils.dart';

class AdminAddJobScreen extends StatefulWidget {
  const AdminAddJobScreen({super.key});

  @override
  State<AdminAddJobScreen> createState() => _AdminAddJobScreenState();
}

class _AdminAddJobScreenState extends State<AdminAddJobScreen> {
  final AdminStaffService _staffService = AdminStaffService();
  final ApiClient _api = ApiClient();
  final _formKey = GlobalKey<FormState>();

  // Text Controllers
  final _titleController = TextEditingController();
  final _positionsController = TextEditingController(text: '1');
  final _minExpController = TextEditingController();
  final _maxExpController = TextEditingController();
  final _minSalaryController = TextEditingController();
  final _maxSalaryController = TextEditingController();
  final _skillsInputController = TextEditingController();
  final _benefitsController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _responsibilitiesController = TextEditingController();

  // Dropdown & Selection States
  String _department = 'Engineering';
  String _branch = 'Mumbai Head Office';
  String _workplaceType = 'On-site'; // 'On-site' | 'Remote' | 'Hybrid'
  String _employmentType = 'Full-time'; // 'Full-time' | 'Part-time' | 'Contract' | 'Internship'
  String _education = "Bachelor's Degree";
  String _salaryType = 'Annual'; // 'Annual' | 'Monthly'
  String _status = 'DRAFT'; // 'ACTIVE' | 'DRAFT' | 'CLOSED' | 'INACTIVE'
  DateTime? _closingDate;
  bool _isPublic = false;
  final List<String> _skillsList = [];

  bool _isGeneratingAI = false;
  bool _isSubmitting = false;

  // Dynamic dropdown lists fetched from backend
  List<String> _departments = [
    'Engineering',
    'Design',
    'Product',
    'Sales',
    'HR & Admin',
    'Marketing',
  ];

  List<String> _branches = [
    'Mumbai Head Office',
    'Bangalore Tech Hub',
    'Delhi Office',
    'Remote - India',
  ];

  @override
  void initState() {
    super.initState();
    _fetchBackendSetup();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _positionsController.dispose();
    _minExpController.dispose();
    _maxExpController.dispose();
    _minSalaryController.dispose();
    _maxSalaryController.dispose();
    _skillsInputController.dispose();
    _benefitsController.dispose();
    _descriptionController.dispose();
    _responsibilitiesController.dispose();
    super.dispose();
  }

  Future<void> _fetchBackendSetup() async {
    try {
      final dynamicDepts = <String>{};
      final dynamicBranches = <String>{};

      // 1. Fetch live backend setup for dynamic departments & branches
      try {
        final setupRes = await _staffService.getStaffSetup();
        if (setupRes['success'] == true && setupRes['data'] != null) {
          final branches = setupRes['data']['branches'] as List? ?? [];
          for (final b in branches) {
            final bName = (b['name'] ?? b['branchName'])?.toString().trim();
            if (bName != null && bName.isNotEmpty) dynamicBranches.add(bName);
            final d = (b['department'] ?? b['dept'])?.toString().trim();
            if (d != null && d.isNotEmpty) dynamicDepts.add(d);
          }

          final deptsList = setupRes['data']['departments'] as List? ?? [];
          for (final d in deptsList) {
            final name = (d is Map ? (d['name'] ?? d['department']) : d)?.toString().trim();
            if (name != null && name.isNotEmpty) dynamicDepts.add(name);
          }
        }
      } catch (_) {}

      // 2. Also fetch existing staff departments from GET /admin/staff
      try {
        final staffRes = await _staffService.getStaffList();
        if (staffRes['success'] == true && staffRes['data'] != null) {
          final staffList = (staffRes['data']['staff'] as List?) ?? [];
          for (final s in staffList) {
            final d = s['department']?.toString().trim();
            if (d != null && d.isNotEmpty) dynamicDepts.add(d);
          }
        }
      } catch (_) {}

      if (mounted) {
        setState(() {
          if (dynamicDepts.isNotEmpty) {
            _departments = {..._departments, ...dynamicDepts}.toList();
          }
          if (dynamicBranches.isNotEmpty) {
            _branches = {..._branches, ...dynamicBranches}.toList();
          }
          if (!_departments.contains(_department) && _departments.isNotEmpty) {
            _department = _departments.first;
          }
          if (!_branches.contains(_branch) && _branches.isNotEmpty) {
            _branch = _branches.first;
          }
        });
      }
    } catch (_) {}
  }

  void _addSkill() {
    final text = _skillsInputController.text.trim();
    if (text.isNotEmpty && !_skillsList.contains(text)) {
      setState(() {
        _skillsList.add(text);
        _skillsInputController.clear();
      });
    }
  }

  void _generateWithAI() {
    if (_titleController.text.trim().isEmpty) {
      SnackBarUtils.showSnackBar(context, 'Please enter a Job Title first so AI can generate the description', isError: true);
      return;
    }

    setState(() => _isGeneratingAI = true);

    Future.delayed(const Duration(milliseconds: 1000), () {
      if (!mounted) return;
      final title = _titleController.text.trim();
      final dept = _department;
      final type = _employmentType;
      final workplace = _workplaceType;
      final skills = _skillsList.isNotEmpty ? _skillsList.join(', ') : 'relevant modern technologies';

      final desc = 'We are seeking a skilled and enthusiastic $title to join our growing $dept team. In this role, you will be responsible for building high-quality, scalable solutions and collaborating closely with product managers and cross-functional teams. This is a $type position based on a $workplace work setup.\n\nOur ideal candidate is a self-starter who enjoys solving complex challenges, is passionate about delivering exceptional user experiences, and has hands-on experience working with $skills.';

      final resp = '• Design, develop, and deploy scalable features for our core platforms.\n• Collaborate with cross-functional teams to translate product requirements into technical specifications.\n• Maintain high standards of code quality through testing, code reviews, and active documentation.\n• Optimize application performance and ensure a seamless, responsive user interface.\n${_skillsList.map((s) => '• Leverage expert knowledge of $s to solve daily technical engineering challenges.').join('\n')}\n• Troubleshooting, debugging, and improving existing software workflows.';

      setState(() {
        _descriptionController.text = desc;
        _responsibilitiesController.text = resp;
        _isGeneratingAI = false;
      });

      SnackBarUtils.showSnackBar(context, 'AI generated description & responsibilities!');
    });
  }

  Future<void> _submitJob() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    final expMin = _minExpController.text.trim();
    final expMax = _maxExpController.text.trim();
    final expStr = (expMin.isNotEmpty && expMax.isNotEmpty)
        ? '$expMin-$expMax Years'
        : expMin.isNotEmpty
            ? '$expMin+ Years'
            : 'Any Experience';

    final sMin = _minSalaryController.text.trim();
    final sMax = _maxSalaryController.text.trim();
    final salaryStr = (sMin.isNotEmpty && sMax.isNotEmpty)
        ? '₹$sMin - ₹$sMax'
        : sMin.isNotEmpty
            ? 'From ₹$sMin'
            : 'Not Disclosed';

    final jobPayload = {
      'title': _titleController.text.trim(),
      'department': _department,
      'branch': _branch,
      'workplaceType': _workplaceType,
      'employmentType': _employmentType,
      'positions': int.tryParse(_positionsController.text) ?? 1,
      'status': _status,
      'experience': expStr,
      'education': _education,
      'salary': salaryStr,
      'description': _descriptionController.text.trim(),
      'responsibilities': _responsibilitiesController.text.trim(),
      'skills': _skillsList,
      'benefits': _benefitsController.text.trim(),
      'isPublic': _isPublic,
      'closeDate': _closingDate != null ? DateFormat('yyyy-MM-dd').format(_closingDate!) : '',
    };

    try {
      await _api.request('/admin/recruitment/job-openings', method: 'POST', data: jobPayload);
    } catch (_) {}

    if (mounted) {
      setState(() => _isSubmitting = false);
      SnackBarUtils.showSnackBar(context, 'Job Opening created successfully!');
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF0F172A)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Add New Job Opening',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
        ),
        centerTitle: false,
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── Section 1: Job Information ──
            _buildCard(
              title: 'Job Information',
              children: [
                _buildFieldLabel('JOB CODE'),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: const Text(
                    'JOB-YYYY-XXX (Auto)',
                    style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8), fontFamily: 'monospace', fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 14),

                _buildFieldLabel('JOB TITLE *'),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _titleController,
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Job Title is required' : null,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  decoration: _inputDecoration('e.g. Senior Frontend Developer'),
                ),
                const SizedBox(height: 14),

                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildFieldLabel('DEPARTMENT'),
                          const SizedBox(height: 6),
                          _buildDropdown(
                            value: _department,
                            items: _departments,
                            onChanged: (v) {
                              if (v != null) setState(() => _department = v);
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildFieldLabel('BRANCH'),
                          const SizedBox(height: 6),
                          _buildDropdown(
                            value: _branch,
                            items: _branches,
                            onChanged: (v) {
                              if (v != null) setState(() => _branch = v);
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildFieldLabel('WORKPLACE TYPE'),
                          const SizedBox(height: 6),
                          _buildDropdown(
                            value: _workplaceType,
                            items: const ['On-site', 'Remote', 'Hybrid'],
                            onChanged: (v) {
                              if (v != null) setState(() => _workplaceType = v);
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildFieldLabel('EMPLOYMENT TYPE'),
                          const SizedBox(height: 6),
                          _buildDropdown(
                            value: _employmentType,
                            items: const ['Full-time', 'Part-time', 'Contract', 'Internship'],
                            onChanged: (v) {
                              if (v != null) setState(() => _employmentType = v);
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                _buildFieldLabel('NO. OF POSITIONS'),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _positionsController,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  decoration: _inputDecoration('1'),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ── Section 2: Qualifications & Skills ──
            _buildCard(
              title: 'Qualifications & Skills',
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildFieldLabel('MIN EXPERIENCE (YEARS)'),
                          const SizedBox(height: 6),
                          TextFormField(
                            controller: _minExpController,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(fontSize: 13),
                            decoration: _inputDecoration('e.g. 3'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildFieldLabel('MAX EXPERIENCE (YEARS)'),
                          const SizedBox(height: 6),
                          TextFormField(
                            controller: _maxExpController,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(fontSize: 13),
                            decoration: _inputDecoration('e.g. 6'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                _buildFieldLabel('EDUCATIONAL QUALIFICATION'),
                const SizedBox(height: 6),
                _buildDropdown(
                  value: _education,
                  items: const ["Any Degree", "Bachelor's Degree", "Master's Degree", "Diploma", "PhD"],
                  onChanged: (v) {
                    if (v != null) setState(() => _education = v);
                  },
                ),
                const SizedBox(height: 14),

                _buildFieldLabel('KEY SKILLS (PRESS ENTER TO ADD)'),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _skillsInputController,
                        onSubmitted: (_) => _addSkill(),
                        style: const TextStyle(fontSize: 13),
                        decoration: _inputDecoration('Type a skill (e.g. React)'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _addSkill,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFEFAA1F),
                        foregroundColor: const Color(0xFF0F172A),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        elevation: 0,
                      ),
                      child: const Text('Add', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                    ),
                  ],
                ),
                if (_skillsList.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _skillsList.map((skill) {
                      return Chip(
                        label: Text(skill, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFFD97706))),
                        backgroundColor: const Color(0xFFFFFBEB),
                        deleteIcon: const Icon(Icons.close_rounded, size: 14, color: Color(0xFFD97706)),
                        onDeleted: () => setState(() => _skillsList.remove(skill)),
                        side: const BorderSide(color: Color(0xFFFDE68A)),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),

            // ── Section 3: Compensation & Status ──
            _buildCard(
              title: 'Compensation & Status',
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildFieldLabel('MIN SALARY (INR)'),
                          const SizedBox(height: 6),
                          TextFormField(
                            controller: _minSalaryController,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(fontSize: 13),
                            decoration: _inputDecoration('e.g. 800000'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildFieldLabel('MAX SALARY (INR)'),
                          const SizedBox(height: 6),
                          TextFormField(
                            controller: _maxSalaryController,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(fontSize: 13),
                            decoration: _inputDecoration('e.g. 1500000'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildFieldLabel('SALARY FREQUENCY'),
                          const SizedBox(height: 6),
                          _buildDropdown(
                            value: _salaryType,
                            items: const ['Annual', 'Monthly'],
                            itemLabels: const {'Annual': 'Annual (LPA)', 'Monthly': 'Monthly'},
                            onChanged: (v) {
                              if (v != null) setState(() => _salaryType = v);
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildFieldLabel('STATUS'),
                          const SizedBox(height: 6),
                          _buildDropdown(
                            value: _status,
                            items: const ['ACTIVE', 'INACTIVE', 'CLOSED', 'CANCELLED', 'DRAFT'],
                            itemLabels: const {
                              'ACTIVE': 'Active',
                              'INACTIVE': 'Inactive',
                              'CLOSED': 'Closed',
                              'CANCELLED': 'Cancelled',
                              'DRAFT': 'Draft',
                            },
                            onChanged: (v) {
                              if (v != null) setState(() => _status = v);
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                _buildFieldLabel('CLOSING DATE'),
                const SizedBox(height: 6),
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _closingDate ?? DateTime.now().add(const Duration(days: 30)),
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (picked != null) setState(() => _closingDate = picked);
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _closingDate != null ? DateFormat('MM/dd/yyyy').format(_closingDate!) : 'mm/dd/yyyy',
                          style: TextStyle(
                            fontSize: 13,
                            color: _closingDate != null ? const Color(0xFF0F172A) : const Color(0xFF94A3B8),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Icon(Icons.calendar_month_outlined, size: 18, color: Color(0xFF64748B)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Public Job Board', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF0F172A))),
                  subtitle: const Text('Make this job visible on your public careers page embed', style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
                  value: _isPublic,
                  activeColor: const Color(0xFFEFAA1F),
                  onChanged: (val) => setState(() => _isPublic = val),
                ),
                const SizedBox(height: 14),

                _buildFieldLabel('PERKS & BENEFITS'),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _benefitsController,
                  maxLines: 3,
                  style: const TextStyle(fontSize: 13),
                  decoration: _inputDecoration('Medical insurance, flexible working hours, gym membership...'),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ── Section 4: Description & Responsibilities (with AI) ──
            _buildCard(
              title: 'Job Description & Responsibilities',
              headerAction: ElevatedButton.icon(
                onPressed: _isGeneratingAI ? null : _generateWithAI,
                icon: _isGeneratingAI
                    ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.auto_awesome_rounded, size: 14, color: Colors.white),
                label: Text(
                  _isGeneratingAI ? 'Generating...' : 'Generate with AI',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFD97706),
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              children: [
                _buildFieldLabel('JOB DESCRIPTION'),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _descriptionController,
                  maxLines: 5,
                  style: const TextStyle(fontSize: 13),
                  decoration: _inputDecoration('Detail the role, team, goals, and who you are looking for...'),
                ),
                const SizedBox(height: 14),

                _buildFieldLabel('KEY RESPONSIBILITIES'),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _responsibilitiesController,
                  maxLines: 4,
                  style: const TextStyle(fontSize: 13),
                  decoration: _inputDecoration('List the key responsibilities (e.g. Design components, coordinate with QA)...'),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // ── Action Buttons ──
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: const BorderSide(color: Color(0xFFE2E8F0)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Cancel', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF475569))),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: _isSubmitting ? null : _submitJob,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFEFAA1F),
                      foregroundColor: const Color(0xFF0F172A),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _isSubmitting
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF0F172A)))
                        : const Text('Post Job Opening', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildCard({required String title, required List<Widget> children, Widget? headerAction}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF1F5F9)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
              ),
              if (headerAction != null) headerAction,
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }

  Widget _buildFieldLabel(String label) {
    return Text(
      label,
      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF64748B), letterSpacing: 0.5),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFEFAA1F))),
    );
  }

  Widget _buildDropdown({
    required String value,
    required List<String> items,
    Map<String, String>? itemLabels,
    required void Function(String?) onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: items.contains(value) ? value : (items.isNotEmpty ? items.first : null),
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: Color(0xFF64748B)),
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
          items: items.map((item) {
            final label = itemLabels?[item] ?? item;
            return DropdownMenuItem(value: item, child: Text(label, overflow: TextOverflow.ellipsis));
          }).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}
