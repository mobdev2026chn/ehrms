// lib/screens/admin/recruitment/admin_job_openings_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../config/app_colors.dart';
import '../../../services/admin_staff_service.dart';
import '../../../services/api_client.dart';
import '../../../utils/snackbar_utils.dart';
import '../../../widgets/app_drawer.dart';
import '../../../widgets/app_tab_loader.dart';
import 'admin_add_job_screen.dart';

class AdminJobOpening {
  final String id;
  final String code;
  final String title;
  final String department;
  final String branch;
  final String workplaceType; // 'Remote' | 'On-site' | 'Hybrid'
  final String employmentType; // 'Full-time' | 'Part-time' | 'Contract' | 'Internship'
  final int positions;
  final String status; // 'ACTIVE' | 'DRAFT' | 'CLOSED' | 'INACTIVE' | 'CANCELED'
  final String experience;
  final String education;
  final String salary;
  final String description;
  final String responsibilities;
  final List<String> skills;
  final String benefits;
  final bool isPublic;
  final String openDate;
  final String closeDate;

  AdminJobOpening({
    required this.id,
    required this.code,
    required this.title,
    required this.department,
    required this.branch,
    required this.workplaceType,
    required this.employmentType,
    required this.positions,
    required this.status,
    required this.experience,
    required this.education,
    required this.salary,
    required this.description,
    required this.responsibilities,
    required this.skills,
    required this.benefits,
    required this.isPublic,
    required this.openDate,
    required this.closeDate,
  });

  factory AdminJobOpening.fromJson(Map<String, dynamic> json) {
    return AdminJobOpening(
      id: (json['id'] ?? json['_id'] ?? '').toString(),
      code: (json['code'] ?? json['jobCode'] ?? '').toString(),
      title: (json['title'] ?? json['jobTitle'] ?? '').toString(),
      department: (json['department'] ?? '').toString(),
      branch: (json['branch'] ?? '').toString(),
      workplaceType: (json['workplaceType'] ?? 'Hybrid').toString(),
      employmentType: (json['employmentType'] ?? 'Full-time').toString(),
      positions: int.tryParse(json['positions']?.toString() ?? '1') ?? 1,
      status: (json['status'] ?? 'ACTIVE').toString().toUpperCase(),
      experience: (json['experience'] ?? json['yearOfExp'] ?? '0-1 Years').toString(),
      education: (json['education'] ?? '').toString(),
      salary: (json['salary'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      responsibilities: (json['responsibilities'] ?? '').toString(),
      skills: (json['skills'] is List)
          ? (json['skills'] as List).map((e) => e.toString()).toList()
          : [],
      benefits: (json['benefits'] ?? '').toString(),
      isPublic: json['isPublic'] == true || json['posting'] == 'PUBLIC',
      openDate: (json['openDate'] ?? '').toString(),
      closeDate: (json['closeDate'] ?? '').toString(),
    );
  }
}

class AdminJobOpeningsScreen extends StatefulWidget {
  const AdminJobOpeningsScreen({super.key});

  @override
  State<AdminJobOpeningsScreen> createState() => _AdminJobOpeningsScreenState();
}

class _AdminJobOpeningsScreenState extends State<AdminJobOpeningsScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final AdminStaffService _staffService = AdminStaffService();
  final ApiClient _api = ApiClient();

  bool _isLoading = true;
  String _searchQuery = '';

  // Filter States (matching web filter drawer)
  String _selectedStatus = 'All'; // 'All' | 'ACTIVE' | 'DRAFT' | 'CLOSED' | 'INACTIVE' | 'CANCELED'
  String _selectedDepartment = 'All';
  String _selectedExperience = 'All'; // 'All' | '0-1' | '2-5' | '5-8' | '8+'

  // Dynamic dropdown list fetched from web backend setup
  List<String> _departments = [
    'Engineering',
    'Design',
    'Product',
    'Sales',
    'HR & Admin',
    'Marketing',
  ];

  List<AdminJobOpening> _allJobs = [];

  final List<AdminJobOpening> _initialMockJobs = [
    AdminJobOpening(
      id: '1',
      code: 'JOB-2026-001',
      title: 'Senior Full-Stack Engineer',
      department: 'Engineering',
      branch: 'Mumbai Head Office',
      workplaceType: 'Hybrid',
      employmentType: 'Full-time',
      positions: 3,
      status: 'ACTIVE',
      experience: '5-8 Years',
      education: "Bachelor's in Computer Science",
      salary: '₹18,00,000 - ₹24,00,000',
      description: 'We are looking for a Senior Full-Stack Engineer to lead development of our core web applications and platform services.',
      responsibilities: 'Write clean testable code, design system architectures, mentor junior engineers, collaborate with product managers.',
      skills: ['React', 'Node.js', 'TypeScript', 'PostgreSQL', 'AWS'],
      benefits: 'Health Insurance, Flexible Working Hours, Remote work options',
      isPublic: true,
      openDate: '2026-07-01',
      closeDate: '2026-08-01',
    ),
    AdminJobOpening(
      id: '2',
      code: 'JOB-2026-002',
      title: 'Lead UI/UX Designer',
      department: 'Design',
      branch: 'Bangalore Tech Hub',
      workplaceType: 'On-site',
      employmentType: 'Full-time',
      positions: 1,
      status: 'ACTIVE',
      experience: '6+ Years',
      education: 'Degree in Design, Fine Arts or equivalent',
      salary: '₹15,00,000 - ₹20,00,000',
      description: 'Seeking a creative Lead Designer to own the user experience and design systems of our enterprise software suite.',
      responsibilities: 'Conduct user research, design wireframes and high-fidelity mockups, maintain the design system, collaborate with frontend team.',
      skills: ['Figma', 'User Research', 'Wireframing', 'Design Systems', 'Prototyping'],
      benefits: 'Health Insurance, Medical Cover, Annual Bonus, Flexible Timings',
      isPublic: true,
      openDate: '2026-07-05',
      closeDate: '2026-08-15',
    ),
    AdminJobOpening(
      id: '3',
      code: 'JOB-2026-003',
      title: 'DevOps Engineer',
      department: 'Engineering',
      branch: 'Remote - India',
      workplaceType: 'Remote',
      employmentType: 'Contract',
      positions: 2,
      status: 'DRAFT',
      experience: '3-5 Years',
      education: 'Any Degree',
      salary: '₹12,00,000 - ₹16,00,000',
      description: 'Looking for a DevOps engineer with expertise in CI/CD pipelines, container orchestration, and cloud infrastructure management.',
      responsibilities: 'Manage AWS accounts, optimize CI/CD workflows, configure Kubernetes clusters, monitor system reliability.',
      skills: ['AWS', 'Docker', 'Kubernetes', 'GitHub Actions', 'Terraform'],
      benefits: 'Internet Reimbursement, Home Office Setup, Health Insurance',
      isPublic: false,
      openDate: '2026-07-10',
      closeDate: '2026-09-01',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _fetchJobOpeningsAndSetup();
  }

  Future<void> _fetchJobOpeningsAndSetup({bool showLoader = true}) async {
    if (showLoader && mounted) setState(() => _isLoading = true);

    try {
      final dynamicDepts = <String>{};

      // 1. Fetch live backend setup for dynamic departments & branches
      try {
        final setupRes = await _staffService.getStaffSetup();
        if (setupRes['success'] == true && setupRes['data'] != null) {
          final branches = setupRes['data']['branches'] as List? ?? [];
          for (final b in branches) {
            final d = (b['department'] ?? b['name'])?.toString().trim();
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
          _departments = {
            'Engineering',
            'Design',
            'Product',
            'Sales',
            'HR & Admin',
            'Marketing',
            ...dynamicDepts,
          }.toList();
        });
      }

      // 2. Fetch live job openings from backend API if available
      try {
        final jobRes = await _api.request('/admin/recruitment/job-openings');
        if (jobRes.data is Map && jobRes.data['success'] == true) {
          final list = (jobRes.data['data']?['jobs'] as List?) ?? (jobRes.data['data'] as List?) ?? [];
          if (list.isNotEmpty && mounted) {
            setState(() {
              _allJobs = list.map((e) => AdminJobOpening.fromJson(Map<String, dynamic>.from(e as Map))).toList();
            });
          } else {
            setState(() => _allJobs = _initialMockJobs);
          }
        } else {
          setState(() => _allJobs = _initialMockJobs);
        }
      } catch (_) {
        setState(() => _allJobs = _initialMockJobs);
      }
    } catch (_) {
      if (mounted) setState(() => _allJobs = _initialMockJobs);
    }

    if (showLoader && mounted) setState(() => _isLoading = false);
  }

  int get _activeFilterCount {
    int count = 0;
    if (_selectedStatus != 'All') count++;
    if (_selectedDepartment != 'All') count++;
    if (_selectedExperience != 'All') count++;
    return count;
  }

  List<AdminJobOpening> get _filteredJobs {
    return _allJobs.where((job) {
      // Search term match
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final matchTitle = job.title.toLowerCase().contains(q);
        final matchCode = job.code.toLowerCase().contains(q);
        final matchDept = job.department.toLowerCase().contains(q);
        final matchBranch = job.branch.toLowerCase().contains(q);
        if (!matchTitle && !matchCode && !matchDept && !matchBranch) {
          return false;
        }
      }

      // Status Filter
      if (_selectedStatus != 'All') {
        if (job.status.toUpperCase() != _selectedStatus.toUpperCase()) {
          return false;
        }
      }

      // Department Filter
      if (_selectedDepartment != 'All') {
        if (job.department.toLowerCase() != _selectedDepartment.toLowerCase()) {
          return false;
        }
      }

      // Experience Filter
      if (_selectedExperience != 'All') {
        final exp = job.experience.toLowerCase();
        if (_selectedExperience == '0-1' && !(exp.contains('0') || exp.contains('1'))) return false;
        if (_selectedExperience == '2-5' && !(exp.contains('2') || exp.contains('3') || exp.contains('4') || exp.contains('5'))) return false;
        if (_selectedExperience == '5-8' && !(exp.contains('5') || exp.contains('6') || exp.contains('7') || exp.contains('8'))) return false;
        if (_selectedExperience == '8+' && !(exp.contains('8') || exp.contains('9') || exp.contains('10') || exp.contains('+'))) return false;
      }

      return true;
    }).toList();
  }

  void _openFilterBottomSheet() {
    String tempStatus = _selectedStatus;
    String tempDept = _selectedDepartment;
    String tempExp = _selectedExperience;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            return Container(
              padding: EdgeInsets.only(
                top: 20,
                left: 20,
                right: 20,
                bottom: MediaQuery.of(modalCtx).viewInsets.bottom + 24,
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Modal Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEF3C7),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.filter_list_rounded, size: 18, color: Color(0xFFD97706)),
                          ),
                          const SizedBox(width: 10),
                          const Text(
                            'ADVANCED FILTERS',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF0F172A),
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, size: 20, color: Color(0xFF64748B)),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // ── Filter 1: JOB STATUS ──
                  _buildDropdownField(
                    label: 'JOB STATUS',
                    value: tempStatus,
                    items: const [
                      'All',
                      'ACTIVE',
                      'DRAFT',
                      'CLOSED',
                      'INACTIVE',
                      'CANCELED',
                    ],
                    itemLabels: const {
                      'All': 'All Statuses',
                      'ACTIVE': 'Active',
                      'DRAFT': 'Draft',
                      'CLOSED': 'Closed',
                      'INACTIVE': 'Inactive',
                      'CANCELED': 'Canceled',
                    },
                    onChanged: (val) {
                      if (val != null) setModalState(() => tempStatus = val);
                    },
                  ),
                  const SizedBox(height: 14),

                  // ── Filter 2: DEPARTMENT (API Dynamic) ──
                  _buildDropdownField(
                    label: 'DEPARTMENT',
                    value: tempDept,
                    items: ['All', ..._departments],
                    itemLabels: {
                      'All': 'All Departments',
                      for (final d in _departments) d: d,
                    },
                    onChanged: (val) {
                      if (val != null) setModalState(() => tempDept = val);
                    },
                  ),
                  const SizedBox(height: 14),

                  // ── Filter 3: REQUIRED EXPERIENCE ──
                  _buildDropdownField(
                    label: 'REQUIRED EXPERIENCE',
                    value: tempExp,
                    items: const ['All', '0-1', '2-5', '5-8', '8+'],
                    itemLabels: const {
                      'All': 'All Experience',
                      '0-1': '0-1 Years',
                      '2-5': '2-5 Years',
                      '5-8': '5-8 Years',
                      '8+': '8+ Years',
                    },
                    onChanged: (val) {
                      if (val != null) setModalState(() => tempExp = val);
                    },
                  ),
                  const SizedBox(height: 24),

                  // Modal Actions
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () {
                            setModalState(() {
                              tempStatus = 'All';
                              tempDept = 'All';
                              tempExp = 'All';
                            });
                          },
                          child: const Text(
                            'Clear All',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton(
                          onPressed: () {
                            setState(() {
                              _selectedStatus = tempStatus;
                              _selectedDepartment = tempDept;
                              _selectedExperience = tempExp;
                            });
                            Navigator.pop(ctx);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFEFAA1F),
                            foregroundColor: const Color(0xFF0F172A),
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text(
                            'Apply Filters',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildDropdownField({
    required String label,
    required String value,
    required List<String> items,
    required Map<String, String> itemLabels,
    required ValueChanged<String?> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: Color(0xFF94A3B8),
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: items.contains(value) ? value : items.first,
              isExpanded: true,
              icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF64748B)),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF0F172A),
              ),
              items: items.map((item) {
                return DropdownMenuItem<String>(
                  value: item,
                  child: Text(itemLabels[item] ?? item),
                );
              }).toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final jobs = _filteredJobs;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFFF8FAFC),
      drawer: const AppDrawer(),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu_rounded, color: Color(0xFF0F172A)),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        title: const Text(
          'Job Openings',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: Color(0xFF0F172A),
          ),
        ),
        centerTitle: false,
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Color(0xFF64748B), size: 22),
            onPressed: () => _fetchJobOpeningsAndSetup(),
            tooltip: 'Refresh',
          ),
          const SizedBox(width: 4),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: const Color(0xFFF1F5F9), height: 1),
        ),
      ),
      body: _isLoading
          ? const Center(child: AppTabLoader())
          : RefreshIndicator(
              onRefresh: () => _fetchJobOpeningsAndSetup(showLoader: false),
              color: AppColors.primary,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                children: [
                  // ── Header Banner Card ──
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFF1F5F9)),
                      boxShadow: const [
                        BoxShadow(color: Color(0x06000000), blurRadius: 8, offset: Offset(0, 2)),
                      ],
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: const [
                              Text(
                                'Manage Openings',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Publish & track job listings to attract applicants.',
                                style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                              ),
                            ],
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: () async {
                            final created = await Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const AdminAddJobScreen()),
                            );
                            if (created == true) {
                              _fetchJobOpeningsAndSetup();
                            }
                          },
                          icon: const Icon(Icons.add_rounded, size: 16),
                          label: const Text('+ Add Job', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFEFAA1F),
                            foregroundColor: const Color(0xFF0F172A),
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // ── Search & Filter Controls ──
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 44,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: TextField(
                            onChanged: (v) => setState(() => _searchQuery = v),
                            decoration: InputDecoration(
                              hintText: 'Search by title, code, dept...',
                              hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                              prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF94A3B8), size: 18),
                              suffixIcon: _searchQuery.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear_rounded, size: 16, color: Color(0xFF94A3B8)),
                                      onPressed: () => setState(() => _searchQuery = ''),
                                    )
                                  : null,
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      InkWell(
                        onTap: _openFilterBottomSheet,
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          height: 44,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          decoration: BoxDecoration(
                            color: _activeFilterCount > 0 ? const Color(0xFFFEF3C7) : Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _activeFilterCount > 0 ? const Color(0xFFFDE68A) : const Color(0xFFE2E8F0),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.filter_list_rounded,
                                size: 17,
                                color: _activeFilterCount > 0 ? const Color(0xFFD97706) : const Color(0xFF475569),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Filters',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: _activeFilterCount > 0 ? const Color(0xFFD97706) : const Color(0xFF334155),
                                ),
                              ),
                              if (_activeFilterCount > 0) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFD97706),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Text(
                                    '$_activeFilterCount',
                                    style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Colors.white),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // ── Job Opening Cards List ──
                  if (jobs.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(32),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFF1F5F9)),
                      ),
                      child: Column(
                        children: const [
                          Icon(Icons.search_off_rounded, size: 40, color: Color(0xFF94A3B8)),
                          SizedBox(height: 10),
                          Text(
                            'No job openings match your filters',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF475569)),
                          ),
                        ],
                      ),
                    )
                  else
                    ...jobs.map((job) => _buildJobCard(job)),
                ],
              ),
            ),
    );
  }

  Widget _buildJobCard(AdminJobOpening job) {
    Color statusBg;
    Color statusFg;
    if (job.status == 'ACTIVE') {
      statusBg = const Color(0xFFDCFCE7);
      statusFg = const Color(0xFF16A34A);
    } else if (job.status == 'DRAFT') {
      statusBg = const Color(0xFFFEF3C7);
      statusFg = const Color(0xFFD97706);
    } else {
      statusBg = const Color(0xFFFEE2E2);
      statusFg = const Color(0xFFDC2626);
    }

    final isPublic = job.isPublic;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF1F5F9)),
        boxShadow: const [
          BoxShadow(color: Color(0x04000000), blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Row: Code + Posting Pill + Status Pill
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  job.code,
                  style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Color(0xFF475569)),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                decoration: BoxDecoration(
                  color: isPublic ? const Color(0xFFEFF6FF) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isPublic ? const Color(0xFFBFDBFE) : const Color(0xFFE2E8F0),
                  ),
                ),
                child: Text(
                  isPublic ? 'PUBLIC' : 'PRIVATE',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    color: isPublic ? const Color(0xFF2563EB) : const Color(0xFF64748B),
                  ),
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusBg,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  job.status,
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: statusFg),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Job Title
          Text(
            job.title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 4),

          // Department & Branch
          Row(
            children: [
              const Icon(Icons.apartment_rounded, size: 14, color: Color(0xFF94A3B8)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${job.department} • ${job.branch}',
                  style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Grid Info: Workplace, Experience, Positions, Dates
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _metaCol('WORKPLACE & TYPE', '${job.workplaceType} • ${job.employmentType}'),
                    _metaCol('YEAR OF EXP', job.experience),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _metaCol('POSITIONS', '${job.positions} Open'),
                    _metaCol('DATES', '${job.openDate} → ${job.closeDate}'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _metaCol(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.w700, color: Color(0xFF94A3B8)),
        ),
        const SizedBox(height: 1),
        Text(
          value,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF1E293B)),
        ),
      ],
    );
  }
}
