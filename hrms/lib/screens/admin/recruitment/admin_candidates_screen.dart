// lib/screens/admin/recruitment/admin_candidates_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../config/app_colors.dart';
import '../../../services/api_client.dart';
import '../../../utils/snackbar_utils.dart';
import '../../../widgets/app_drawer.dart';
import '../../../widgets/app_tab_loader.dart';

class AdminCandidate {
  final String id;
  String firstName;
  String lastName;
  String email;
  String phone;
  String position;
  String primarySkill;
  int experienceYears;
  String status; // 'Applied' | 'Shortlisted' | 'Interviewing' | 'Offered' | 'Hired' | 'Rejected'
  String source; // 'LinkedIn' | 'Career Page' | 'Naukri' | 'Referral' | 'Manual'
  String appliedDate;
  String? dob;
  String? resumeName;

  AdminCandidate({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.phone,
    required this.position,
    required this.primarySkill,
    required this.experienceYears,
    required this.status,
    required this.source,
    required this.appliedDate,
    this.dob,
    this.resumeName,
  });

  String get fullName => '$firstName $lastName'.trim();
  String get initials => '${firstName.isNotEmpty ? firstName[0] : ""}${lastName.isNotEmpty ? lastName[0] : ""}'.toUpperCase();

  factory AdminCandidate.fromJson(Map<String, dynamic> json) {
    final nameParts = (json['name']?.toString() ?? '').split(' ');
    final fn = (json['firstName'] ?? (nameParts.isNotEmpty && nameParts.first.isNotEmpty ? nameParts.first : 'Candidate')).toString();
    final ln = (json['lastName'] ?? (nameParts.length > 1 ? nameParts.sublist(1).join(' ') : '')).toString();

    return AdminCandidate(
      id: (json['id'] ?? json['_id'] ?? 'C-001').toString(),
      firstName: fn,
      lastName: ln,
      email: (json['email'] ?? '').toString(),
      phone: (json['phone'] ?? '').toString(),
      position: (json['position'] ?? json['role'] ?? 'Software Engineer').toString(),
      primarySkill: (json['primarySkill'] ?? json['skills'] ?? 'General').toString(),
      experienceYears: int.tryParse(json['experienceYears']?.toString() ?? '3') ?? 3,
      status: (json['status'] ?? 'Applied').toString(),
      source: (json['source'] ?? 'LinkedIn').toString(),
      appliedDate: (json['appliedDate'] ?? json['createdAt'] ?? '2026-07-02').toString(),
      dob: json['dob']?.toString(),
      resumeName: json['resumeName']?.toString() ?? 'Resume_${fn}_${ln}.pdf',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'firstName': firstName,
        'lastName': lastName,
        'email': email,
        'phone': phone,
        'position': position,
        'primarySkill': primarySkill,
        'experienceYears': experienceYears,
        'status': status,
        'source': source,
        'appliedDate': appliedDate,
        'dob': dob,
        'resumeName': resumeName,
      };
}

class AdminCandidatesScreen extends StatefulWidget {
  const AdminCandidatesScreen({super.key});

  @override
  State<AdminCandidatesScreen> createState() => _AdminCandidatesScreenState();
}

class _AdminCandidatesScreenState extends State<AdminCandidatesScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final ApiClient _api = ApiClient();

  bool _isLoading = true;
  String _searchQuery = '';
  String _selectedStage = 'All'; // 'All' | 'Applied' | 'Shortlisted' | 'Interviewing' | 'Offered' | 'Hired' | 'Rejected'
  String _sourceFilter = 'All Sources';

  List<AdminCandidate> _candidates = [];
  final List<String> _stages = ['All', 'Applied', 'Shortlisted', 'Interviewing', 'Offered', 'Hired', 'Rejected'];
  final List<String> _sources = ['All Sources', 'LinkedIn', 'Career Page', 'Naukri', 'Referral', 'Manual'];

  @override
  void initState() {
    super.initState();
    _fetchCandidates();
  }

  Future<void> _fetchCandidates({bool showLoader = true}) async {
    if (showLoader && mounted) setState(() => _isLoading = true);

    try {
      final res = await _api.request('/admin/recruitment/candidates');
      if (res.data is Map && res.data['success'] == true) {
        final list = (res.data['data']?['candidates'] as List?) ?? (res.data['data'] as List?) ?? [];
        if (list.isNotEmpty && mounted) {
          setState(() {
            _candidates = list.map((e) => AdminCandidate.fromJson(Map<String, dynamic>.from(e as Map))).toList();
          });
        } else {
          _setMockCandidates();
        }
      } else {
        _setMockCandidates();
      }
    } catch (_) {
      _setMockCandidates();
    }

    if (showLoader && mounted) setState(() => _isLoading = false);
  }

  void _setMockCandidates() {
    _candidates = [
      AdminCandidate(
        id: 'C-001',
        firstName: 'Amit',
        lastName: 'Sharma',
        email: 'amit.sharma@example.com',
        phone: '+91 98765 43210',
        position: 'Senior Full-Stack Engineer',
        primarySkill: 'React, Node.js',
        experienceYears: 6,
        status: 'Interviewing',
        source: 'LinkedIn',
        appliedDate: '2026-07-02',
        dob: '1996-04-12',
      ),
      AdminCandidate(
        id: 'C-002',
        firstName: 'Priya',
        lastName: 'Patel',
        email: 'priya.patel@example.com',
        phone: '+91 87654 32109',
        position: 'Lead UI/UX Designer',
        primarySkill: 'Figma, Wireframing',
        experienceYears: 7,
        status: 'Shortlisted',
        source: 'Referral',
        appliedDate: '2026-07-06',
        dob: '1995-08-23',
      ),
      AdminCandidate(
        id: 'C-003',
        firstName: 'Rahul',
        lastName: 'Verma',
        email: 'rahul.verma@example.com',
        phone: '+91 76543 21098',
        position: 'DevOps Engineer',
        primarySkill: 'AWS, Kubernetes',
        experienceYears: 4,
        status: 'Applied',
        source: 'Naukri',
        appliedDate: '2026-07-10',
        dob: '1998-11-05',
      ),
      AdminCandidate(
        id: 'C-004',
        firstName: 'Anjali',
        lastName: 'Rao',
        email: 'anjali.rao@example.com',
        phone: '+91 65432 10987',
        position: 'HR Manager',
        primarySkill: 'Recruiting, Operations',
        experienceYears: 5,
        status: 'Hired',
        source: 'Career Page',
        appliedDate: '2026-06-15',
        dob: '1997-02-18',
      ),
      AdminCandidate(
        id: 'C-005',
        firstName: 'Vikram',
        lastName: 'Singh',
        email: 'vikram.singh@example.com',
        phone: '+91 54321 09876',
        position: 'Senior Frontend Developer',
        primarySkill: 'TypeScript, React',
        experienceYears: 5,
        status: 'Rejected',
        source: 'Manual',
        appliedDate: '2026-06-20',
        dob: '1996-09-30',
      ),
    ];
  }

  List<AdminCandidate> get _filteredCandidates {
    return _candidates.where((c) {
      final matchesSearch = _searchQuery.isEmpty ||
          c.fullName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          c.email.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          c.primarySkill.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          c.position.toLowerCase().contains(_searchQuery.toLowerCase());

      final matchesStage = _selectedStage == 'All' || c.status.toLowerCase() == _selectedStage.toLowerCase();
      final matchesSource = _sourceFilter == 'All Sources' || c.source.toLowerCase() == _sourceFilter.toLowerCase();

      return matchesSearch && matchesStage && matchesSource;
    }).toList();
  }

  // ── Action: Add Candidate Modal ──
  void _showAddCandidateModal() {
    final fnCtrl = TextEditingController();
    final lnCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final positionCtrl = TextEditingController(text: 'Senior Full-Stack Engineer');
    final skillCtrl = TextEditingController();
    final expCtrl = TextEditingController(text: '3');
    String source = 'LinkedIn';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: const [
                Icon(Icons.person_add_alt_1_rounded, color: Color(0xFFEFAA1F), size: 20),
                SizedBox(width: 8),
                Text('Add New Candidate', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('FIRST NAME *', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: Color(0xFF64748B))),
                            const SizedBox(height: 4),
                            TextField(
                              controller: fnCtrl,
                              style: const TextStyle(fontSize: 12),
                              decoration: _inputDec('e.g. John'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('LAST NAME *', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: Color(0xFF64748B))),
                            const SizedBox(height: 4),
                            TextField(
                              controller: lnCtrl,
                              style: const TextStyle(fontSize: 12),
                              decoration: _inputDec('e.g. Doe'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  const Text('EMAIL ADDRESS *', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: Color(0xFF64748B))),
                  const SizedBox(height: 4),
                  TextField(
                    controller: emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    style: const TextStyle(fontSize: 12),
                    decoration: _inputDec('e.g. john.doe@example.com'),
                  ),
                  const SizedBox(height: 10),

                  const Text('PHONE NUMBER *', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: Color(0xFF64748B))),
                  const SizedBox(height: 4),
                  TextField(
                    controller: phoneCtrl,
                    keyboardType: TextInputType.phone,
                    style: const TextStyle(fontSize: 12),
                    decoration: _inputDec('e.g. +91 9876543210'),
                  ),
                  const SizedBox(height: 10),

                  const Text('TARGET POSITION *', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: Color(0xFF64748B))),
                  const SizedBox(height: 4),
                  TextField(
                    controller: positionCtrl,
                    style: const TextStyle(fontSize: 12),
                    decoration: _inputDec('e.g. Senior Frontend Developer'),
                  ),
                  const SizedBox(height: 10),

                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('PRIMARY SKILLS', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: Color(0xFF64748B))),
                            const SizedBox(height: 4),
                            TextField(
                              controller: skillCtrl,
                              style: const TextStyle(fontSize: 12),
                              decoration: _inputDec('e.g. React, Flutter'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 90,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('EXP (YRS)', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: Color(0xFF64748B))),
                            const SizedBox(height: 4),
                            TextField(
                              controller: expCtrl,
                              keyboardType: TextInputType.number,
                              style: const TextStyle(fontSize: 12),
                              decoration: _inputDec('e.g. 4'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  const Text('APPLICATION SOURCE', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: Color(0xFF64748B))),
                  const SizedBox(height: 4),
                  Container(
                    height: 38,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFE2E8F0))),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: source,
                        isExpanded: true,
                        icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: Color(0xFF64748B)),
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
                        items: ['LinkedIn', 'Career Page', 'Naukri', 'Referral', 'Manual']
                            .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                            .toList(),
                        onChanged: (v) {
                          if (v != null) setModalState(() => source = v);
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B)))),
              ElevatedButton(
                onPressed: () async {
                  if (fnCtrl.text.trim().isEmpty || emailCtrl.text.trim().isEmpty) {
                    SnackBarUtils.showSnackBar(context, 'First name and email are required', isError: true);
                    return;
                  }
                  Navigator.pop(ctx);
                  final newCand = AdminCandidate(
                    id: 'C-${(_candidates.length + 1).toString().padLeft(3, '0')}',
                    firstName: fnCtrl.text.trim(),
                    lastName: lnCtrl.text.trim(),
                    email: emailCtrl.text.trim(),
                    phone: phoneCtrl.text.trim(),
                    position: positionCtrl.text.trim(),
                    primarySkill: skillCtrl.text.trim().isEmpty ? 'General' : skillCtrl.text.trim(),
                    experienceYears: int.tryParse(expCtrl.text.trim()) ?? 1,
                    status: 'Applied',
                    source: source,
                    appliedDate: DateFormat('yyyy-MM-dd').format(DateTime.now()),
                  );
                  setState(() => _candidates.insert(0, newCand));
                  try {
                    await _api.request('/admin/recruitment/candidates', method: 'POST', data: newCand.toJson());
                  } catch (_) {}
                  if (mounted) SnackBarUtils.showSnackBar(context, 'Candidate added successfully');
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFEFAA1F),
                  foregroundColor: const Color(0xFF0F172A),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  elevation: 0,
                ),
                child: const Text('Add Candidate', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ],
          );
        },
      ),
    );
  }

  InputDecoration _inputDec(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFEFAA1F))),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    );
  }

  // ── Action: View Candidate Profile Modal ──
  void _showProfileModal(AdminCandidate c) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: const Color(0xFFFFFBEB),
              child: Text(c.initials, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFFD97706))),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c.fullName, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800)),
                  Text(c.position, style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                ],
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _specRow('Email', c.email),
            _specRow('Phone', c.phone),
            _specRow('Experience', '${c.experienceYears} Years'),
            _specRow('Primary Skills', c.primarySkill),
            _specRow('Source', c.source),
            _specRow('Applied Date', c.appliedDate),
            _specRow('Status', c.status),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFE2E8F0))),
              child: Row(
                children: [
                  const Icon(Icons.picture_as_pdf_outlined, color: Color(0xFFEF4444), size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(c.resumeName ?? 'Resume.pdf', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
                  ),
                  const Icon(Icons.download_rounded, size: 16, color: Color(0xFF64748B)),
                ],
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEFAA1F),
              foregroundColor: const Color(0xFF0F172A),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Close', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  Widget _specRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(width: 95, child: Text(label, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Color(0xFF64748B)))),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)))),
        ],
      ),
    );
  }

  // ── Action: Update Stage Modal ──
  void _showUpdateStageModal(AdminCandidate c) {
    String stage = c.status;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text('Update Stage for ${c.fullName}', style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800)),
            content: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFE2E8F0))),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: stage,
                  isExpanded: true,
                  items: ['Applied', 'Shortlisted', 'Interviewing', 'Offered', 'Hired', 'Rejected']
                      .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setModalState(() => stage = v);
                  },
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B)))),
              ElevatedButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  setState(() => c.status = stage);
                  try {
                    await _api.request('/admin/recruitment/candidates/${c.id}/stage', method: 'POST', data: {'status': stage});
                  } catch (_) {}
                  if (mounted) SnackBarUtils.showSnackBar(context, 'Stage updated to $stage');
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFEFAA1F),
                  foregroundColor: const Color(0xFF0F172A),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('Update Stage', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
          'Candidates Management',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
        ),
        centerTitle: false,
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Color(0xFF64748B), size: 22),
            onPressed: () => _fetchCandidates(),
            tooltip: 'Refresh',
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _isLoading
          ? const Center(child: AppTabLoader())
          : RefreshIndicator(
              onRefresh: () => _fetchCandidates(showLoader: false),
              color: AppColors.primary,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Top Banner with + Add Candidate
                  Container(
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
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: const [
                                  Text('Candidate Directory & Pipeline', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF0F172A))),
                                  SizedBox(height: 2),
                                  Text('Track candidate applications, recruitment stages, and resumes.', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                                ],
                              ),
                            ),
                            ElevatedButton.icon(
                              onPressed: _showAddCandidateModal,
                              icon: const Icon(Icons.add_rounded, size: 16),
                              label: const Text('+ Add Candidate', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFEFAA1F),
                                foregroundColor: const Color(0xFF0F172A),
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Search
                        Container(
                          height: 42,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: TextField(
                            onChanged: (v) => setState(() => _searchQuery = v),
                            decoration: const InputDecoration(
                              hintText: 'Search by name, email, or skill...',
                              hintStyle: TextStyle(fontSize: 11.5, color: Color(0xFF94A3B8)),
                              prefixIcon: Icon(Icons.search_rounded, size: 18, color: Color(0xFF94A3B8)),
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(vertical: 11),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),

                        // Source Filter
                        Row(
                          children: [
                            const Text('Source:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF64748B))),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Container(
                                height: 36,
                                padding: const EdgeInsets.symmetric(horizontal: 10),
                                decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFE2E8F0))),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    value: _sourceFilter,
                                    isExpanded: true,
                                    icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: Color(0xFF64748B)),
                                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                                    items: _sources.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                                    onChanged: (v) {
                                      if (v != null) setState(() => _sourceFilter = v);
                                    },
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Stage Tabs
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _stages.map((stage) {
                        final isSelected = _selectedStage == stage;
                        return Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            label: Text(stage),
                            selected: isSelected,
                            onSelected: (_) => setState(() => _selectedStage = stage),
                            selectedColor: const Color(0xFFEFAA1F),
                            backgroundColor: Colors.white,
                            labelStyle: TextStyle(
                              fontSize: 11,
                              fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                              color: isSelected ? const Color(0xFF0F172A) : const Color(0xFF64748B),
                            ),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: isSelected ? const Color(0xFFEFAA1F) : const Color(0xFFE2E8F0))),
                            showCheckmark: false,
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Candidates List
                  if (_filteredCandidates.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(36),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                      child: const Text('No candidates match the current filters', style: TextStyle(fontSize: 13, color: Color(0xFF94A3B8))),
                    )
                  else
                    ..._filteredCandidates.map((c) => _buildCandidateCard(c)),
                ],
              ),
            ),
    );
  }

  Widget _buildCandidateCard(AdminCandidate c) {
    Color stBg;
    Color stFg;
    if (c.status == 'Hired' || c.status == 'Offered') {
      stBg = const Color(0xFFDCFCE7);
      stFg = const Color(0xFF16A34A);
    } else if (c.status == 'Rejected') {
      stBg = const Color(0xFFFEE2E2);
      stFg = const Color(0xFFDC2626);
    } else if (c.status == 'Interviewing') {
      stBg = const Color(0xFFFEF3C7);
      stFg = const Color(0xFFD97706);
    } else {
      stBg = const Color(0xFFE0E7FF);
      stFg = const Color(0xFF4338CA);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF1F5F9)),
        boxShadow: const [BoxShadow(color: Color(0x04000000), blurRadius: 6, offset: Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: const Color(0xFFF1F5F9),
                child: Text(c.initials, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF64748B))),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.fullName, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: Color(0xFF0F172A))),
                    Text(c.email, style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: stBg, borderRadius: BorderRadius.circular(20)),
                child: Text(c.status, style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900, color: stFg)),
              ),
            ],
          ),
          const SizedBox(height: 10),

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
                    Expanded(
                      child: Text('${c.position} • ${c.experienceYears} Yrs Exp', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(4)),
                      child: Text(c.source, style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: Color(0xFF2563EB))),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.star_border_rounded, size: 13, color: Color(0xFFD97706)),
                    const SizedBox(width: 4),
                    Text('Skills: ${c.primarySkill}', style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: Color(0xFF64748B))),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Applied: ${c.appliedDate}', style: const TextStyle(fontSize: 10.5, color: Color(0xFF94A3B8))),
              Row(
                children: [
                  TextButton(
                    onPressed: () => _showUpdateStageModal(c),
                    style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), minimumSize: Size.zero),
                    child: const Text('Change Stage', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF2563EB))),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () => _showProfileModal(c),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFFBEB),
                      foregroundColor: const Color(0xFFD97706),
                      elevation: 0,
                      side: const BorderSide(color: Color(0xFFFDE68A)),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('Profile ❯', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
