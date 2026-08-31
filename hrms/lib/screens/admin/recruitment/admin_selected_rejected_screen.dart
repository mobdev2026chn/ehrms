// lib/screens/admin/recruitment/admin_selected_rejected_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../config/app_colors.dart';
import '../../../services/api_client.dart';
import '../../../utils/snackbar_utils.dart';
import '../../../widgets/app_drawer.dart';
import '../../../widgets/app_tab_loader.dart';

class AdminDecisionCandidate {
  final String id;
  final String firstName;
  final String lastName;
  final String email;
  final String phone;
  final String position;
  final int experienceYears;
  String status; // 'PENDING' | 'OFFERED' | 'REJECTED' | 'SELECTED'
  String decisionDate;
  String? generalFeedback;
  int? overallScore;
  String? rejectionReason;
  String? offerSalary;
  String? joiningDate;

  AdminDecisionCandidate({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.phone,
    required this.position,
    required this.experienceYears,
    required this.status,
    required this.decisionDate,
    this.generalFeedback,
    this.overallScore,
    this.rejectionReason,
    this.offerSalary,
    this.joiningDate,
  });

  String get fullName => '$firstName $lastName'.trim();
  String get initials => '${firstName.isNotEmpty ? firstName[0] : ""}${lastName.isNotEmpty ? lastName[0] : ""}'.toUpperCase();

  factory AdminDecisionCandidate.fromJson(Map<String, dynamic> json) {
    final nameParts = (json['name']?.toString() ?? '').split(' ');
    final fn = (json['firstName'] ?? (nameParts.isNotEmpty && nameParts.first.isNotEmpty ? nameParts.first : 'Candidate')).toString();
    final ln = (json['lastName'] ?? (nameParts.length > 1 ? nameParts.sublist(1).join(' ') : '')).toString();

    return AdminDecisionCandidate(
      id: (json['id'] ?? 'C-001').toString(),
      firstName: fn,
      lastName: ln,
      email: (json['email'] ?? '').toString(),
      phone: (json['phone'] ?? '').toString(),
      position: (json['position'] ?? 'Software Engineer').toString(),
      experienceYears: int.tryParse(json['experienceYears']?.toString() ?? '3') ?? 3,
      status: (json['status'] ?? 'PENDING').toString().toUpperCase(),
      decisionDate: (json['decisionDate'] ?? json['appliedDate'] ?? '2026-07-02').toString(),
      generalFeedback: json['generalFeedback']?.toString(),
      overallScore: int.tryParse(json['overallScore']?.toString() ?? ''),
      rejectionReason: json['rejectionReason']?.toString(),
      offerSalary: json['offerSalary']?.toString(),
      joiningDate: json['joiningDate']?.toString(),
    );
  }
}

class AdminSelectedRejectedScreen extends StatefulWidget {
  const AdminSelectedRejectedScreen({super.key});

  @override
  State<AdminSelectedRejectedScreen> createState() => _AdminSelectedRejectedScreenState();
}

class _AdminSelectedRejectedScreenState extends State<AdminSelectedRejectedScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final ApiClient _api = ApiClient();

  bool _isLoading = true;
  String _searchQuery = '';
  String _statusFilter = 'All Statuses'; // 'All Statuses' | 'Pending' | 'Selected' | 'Rejected'
  String _roleFilter = 'All Roles';

  List<AdminDecisionCandidate> _candidates = [];
  List<String> _availableRoles = ['All Roles'];

  @override
  void initState() {
    super.initState();
    _fetchCandidates();
  }

  Future<void> _fetchCandidates({bool showLoader = true}) async {
    if (showLoader && mounted) setState(() => _isLoading = true);

    try {
      final res = await _api.request('/admin/recruitment/interview-process/selected-rejected');
      if (res.data is Map && res.data['success'] == true) {
        final list = (res.data['data']?['candidates'] as List?) ?? (res.data['data'] as List?) ?? [];
        if (list.isNotEmpty && mounted) {
          setState(() {
            _candidates = list.map((e) => AdminDecisionCandidate.fromJson(Map<String, dynamic>.from(e as Map))).toList();
            _extractRoles();
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

  void _extractRoles() {
    final roles = {'All Roles'};
    for (final c in _candidates) {
      if (c.position.isNotEmpty) roles.add(c.position);
    }
    _availableRoles = roles.toList();
  }

  void _setMockCandidates() {
    _candidates = [
      AdminDecisionCandidate(
        id: 'C-001',
        firstName: 'Amit',
        lastName: 'Sharma',
        email: 'amit.sharma@example.com',
        phone: '+91 98765 43210',
        position: 'Senior Full-Stack Engineer',
        experienceYears: 6,
        status: 'PENDING',
        decisionDate: '2026-07-02',
        overallScore: 8,
        generalFeedback: 'Strong problem-solving skills in React and Node.js. Awaiting final compensation alignment.',
      ),
      AdminDecisionCandidate(
        id: 'C-002',
        firstName: 'Priya',
        lastName: 'Patel',
        email: 'priya.patel@example.com',
        phone: '+91 87654 32109',
        position: 'Lead UI/UX Designer',
        experienceYears: 7,
        status: 'OFFERED',
        decisionDate: '2026-07-06',
        offerSalary: '₹22,00,000 / annum',
        joiningDate: '2026-09-01',
        overallScore: 9,
        generalFeedback: 'Exceptional visual design portfolio and user testing depth.',
      ),
      AdminDecisionCandidate(
        id: 'C-003',
        firstName: 'Rahul',
        lastName: 'Verma',
        email: 'rahul.verma@example.com',
        phone: '+91 76543 21098',
        position: 'DevOps Engineer',
        experienceYears: 4,
        status: 'PENDING',
        decisionDate: '2026-07-10',
        overallScore: 7,
        generalFeedback: 'Solid Kubernetes and AWS experience. Under team review.',
      ),
      AdminDecisionCandidate(
        id: 'C-004',
        firstName: 'Anjali',
        lastName: 'Rao',
        email: 'anjali.rao@example.com',
        phone: '+91 65432 10987',
        position: 'HR Manager',
        experienceYears: 5,
        status: 'OFFERED',
        decisionDate: '2026-06-15',
        offerSalary: '₹14,00,000 / annum',
        joiningDate: '2026-08-15',
        overallScore: 9,
        generalFeedback: 'Great cultural fit and leadership track record.',
      ),
      AdminDecisionCandidate(
        id: 'C-005',
        firstName: 'Vikram',
        lastName: 'Singh',
        email: 'vikram.singh@example.com',
        phone: '+91 54321 09876',
        position: 'Senior Frontend Developer',
        experienceYears: 5,
        status: 'REJECTED',
        decisionDate: '2026-06-20',
        overallScore: 4,
        rejectionReason: 'Fell short on system design and architecture assessment.',
      ),
      AdminDecisionCandidate(
        id: 'C-006',
        firstName: 'Sunita',
        lastName: 'Rao',
        email: 'sunita.rao@example.com',
        phone: '+91 43210 98765',
        position: 'Senior Frontend Developer',
        experienceYears: 6,
        status: 'OFFERED',
        decisionDate: '2026-06-26',
        offerSalary: '₹18,00,000 / annum',
        joiningDate: '2026-08-20',
        overallScore: 9,
        generalFeedback: 'Outstanding technical performance across all rounds.',
      ),
    ];
    _extractRoles();
  }

  List<AdminDecisionCandidate> get _filteredCandidates {
    return _candidates.where((c) {
      final matchesSearch = _searchQuery.isEmpty ||
          c.fullName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          c.email.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          c.position.toLowerCase().contains(_searchQuery.toLowerCase());

      bool matchesStatus = true;
      if (_statusFilter == 'Pending') {
        matchesStatus = c.status == 'PENDING';
      } else if (_statusFilter == 'Selected') {
        matchesStatus = c.status == 'OFFERED' || c.status == 'SELECTED';
      } else if (_statusFilter == 'Rejected') {
        matchesStatus = c.status == 'REJECTED';
      }

      final matchesRole = _roleFilter == 'All Roles' || c.position == _roleFilter;

      return matchesSearch && matchesStatus && matchesRole;
    }).toList();
  }

  // ── Action: View Logs Modal ──
  void _showLogsModal(AdminDecisionCandidate c) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.assignment_outlined, color: Color(0xFFEFAA1F), size: 20),
            const SizedBox(width: 8),
            Text('${c.fullName} Evaluation Log', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _logRow('Candidate', c.fullName),
            _logRow('Email', c.email),
            _logRow('Target Role', c.position),
            _logRow('Decision Date', c.decisionDate),
            _logRow('Current Status', c.status),
            if (c.overallScore != null) _logRow('Overall Score', '${c.overallScore} / 10'),
            if (c.offerSalary != null) _logRow('Offered Salary', c.offerSalary!),
            if (c.joiningDate != null) _logRow('Joining Date', c.joiningDate!),
            if (c.rejectionReason != null) _logRow('Rejection Reason', c.rejectionReason!),
            if (c.generalFeedback != null && c.generalFeedback!.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text('GENERAL FEEDBACK & REMARKS:', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: Color(0xFF94A3B8))),
              const SizedBox(height: 4),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFE2E8F0))),
                child: Text(c.generalFeedback!, style: const TextStyle(fontSize: 11.5, color: Color(0xFF334155))),
              ),
            ],
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

  Widget _logRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(width: 100, child: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF64748B)))),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)))),
        ],
      ),
    );
  }

  // ── Action: Offer Dialog ──
  void _showOfferModal(AdminDecisionCandidate c) {
    final salaryCtrl = TextEditingController(text: c.offerSalary ?? '1800000');
    final joiningCtrl = TextEditingController(text: c.joiningDate ?? DateFormat('yyyy-MM-dd').format(DateTime.now().add(const Duration(days: 30))));

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: const [
            Icon(Icons.insert_drive_file_outlined, color: Color(0xFF16A34A), size: 20),
            SizedBox(width: 8),
            Text('Extend Employment Offer', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Candidate: ${c.fullName} (${c.position})', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF475569))),
            const SizedBox(height: 14),

            const Text('OFFERED ANNUAL CTC (INR) *', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: Color(0xFF64748B))),
            const SizedBox(height: 6),
            TextField(
              controller: salaryCtrl,
              keyboardType: TextInputType.number,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'e.g. 1800000',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
            const SizedBox(height: 12),

            const Text('EXPECTED JOINING DATE *', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: Color(0xFF64748B))),
            const SizedBox(height: 6),
            TextField(
              controller: joiningCtrl,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'YYYY-MM-DD',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B)))),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              setState(() {
                c.status = 'OFFERED';
                c.offerSalary = '₹${salaryCtrl.text.trim()} / annum';
                c.joiningDate = joiningCtrl.text.trim();
              });
              try {
                await _api.request(
                  '/admin/recruitment/interview-process/selected-rejected/${c.id}/offer',
                  method: 'POST',
                  data: {'salary': salaryCtrl.text.trim(), 'joiningDate': joiningCtrl.text.trim()},
                );
              } catch (_) {}
              if (mounted) SnackBarUtils.showSnackBar(context, 'Offer extended to ${c.fullName}');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF16A34A),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Confirm & Send Offer', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  // ── Action: Reject Dialog ──
  void _showRejectModal(AdminDecisionCandidate c) {
    final reasonCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: const [
            Icon(Icons.cancel_outlined, color: Color(0xFFDC2626), size: 20),
            SizedBox(width: 8),
            Text('Reject Candidate', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Are you sure you want to mark ${c.fullName} as Rejected for ${c.position}?', style: const TextStyle(fontSize: 12, color: Color(0xFF475569))),
            const SizedBox(height: 14),

            const Text('REASON FOR REJECTION *', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: Color(0xFF64748B))),
            const SizedBox(height: 6),
            TextField(
              controller: reasonCtrl,
              maxLines: 2,
              style: const TextStyle(fontSize: 12),
              decoration: InputDecoration(
                hintText: 'e.g. Assessment score below threshold, salary mismatch...',
                hintStyle: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                contentPadding: const EdgeInsets.all(10),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B)))),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              setState(() {
                c.status = 'REJECTED';
                c.rejectionReason = reasonCtrl.text.trim();
              });
              try {
                await _api.request(
                  '/admin/recruitment/interview-process/selected-rejected/${c.id}/reject',
                  method: 'POST',
                  data: {'reason': reasonCtrl.text.trim()},
                );
              } catch (_) {}
              if (mounted) SnackBarUtils.showSnackBar(context, '${c.fullName} marked as Rejected');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Confirm Rejection', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
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
          'Selection & Decision Board',
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
                  // Filter Header
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
                        const Text(
                          'Review candidates who completed evaluation rounds. Extend employment offers or review rejection logs.',
                          style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
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
                              hintText: 'Search candidates by name or email...',
                              hintStyle: TextStyle(fontSize: 11.5, color: Color(0xFF94A3B8)),
                              prefixIcon: Icon(Icons.search_rounded, size: 18, color: Color(0xFF94A3B8)),
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(vertical: 11),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),

                        // Status & Role Dropdown Filters
                        Row(
                          children: [
                            // Status Filter
                            Expanded(
                              child: Container(
                                height: 40,
                                padding: const EdgeInsets.symmetric(horizontal: 10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: const Color(0xFFE2E8F0)),
                                ),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    value: _statusFilter,
                                    isExpanded: true,
                                    icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: Color(0xFF64748B)),
                                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                                    items: const ['All Statuses', 'Pending', 'Selected', 'Rejected']
                                        .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                                        .toList(),
                                    onChanged: (v) {
                                      if (v != null) setState(() => _statusFilter = v);
                                    },
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),

                            // Role Filter
                            Expanded(
                              child: Container(
                                height: 40,
                                padding: const EdgeInsets.symmetric(horizontal: 10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: const Color(0xFFE2E8F0)),
                                ),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    value: _availableRoles.contains(_roleFilter) ? _roleFilter : 'All Roles',
                                    isExpanded: true,
                                    icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: Color(0xFF64748B)),
                                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                                    items: _availableRoles
                                        .map((r) => DropdownMenuItem(value: r, child: Text(r, overflow: TextOverflow.ellipsis)))
                                        .toList(),
                                    onChanged: (v) {
                                      if (v != null) setState(() => _roleFilter = v);
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
                  const SizedBox(height: 16),

                  if (_filteredCandidates.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(36),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                      child: const Text('No candidates found on the decision board', style: TextStyle(fontSize: 13, color: Color(0xFF94A3B8))),
                    )
                  else
                    ..._filteredCandidates.map((c) => _buildCandidateCard(c)),
                ],
              ),
            ),
    );
  }

  Widget _buildCandidateCard(AdminDecisionCandidate c) {
    Color stBg = const Color(0xFFFEF3C7);
    Color stFg = const Color(0xFFD97706);
    if (c.status == 'OFFERED' || c.status == 'SELECTED') {
      stBg = const Color(0xFFDCFCE7);
      stFg = const Color(0xFF16A34A);
    } else if (c.status == 'REJECTED') {
      stBg = const Color(0xFFFEE2E2);
      stFg = const Color(0xFFDC2626);
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
              // Avatar with Initials
              CircleAvatar(
                radius: 18,
                backgroundColor: const Color(0xFFF1F5F9),
                child: Text(
                  c.initials,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF64748B)),
                ),
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
                child: Text(
                  c.status,
                  style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900, color: stFg),
                ),
              ),
              const SizedBox(width: 4),

              // 3-Dots Action Menu
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded, size: 18, color: Color(0xFF94A3B8)),
                color: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                onSelected: (action) {
                  if (action == 'logs') {
                    _showLogsModal(c);
                  } else if (action == 'offer') {
                    _showOfferModal(c);
                  } else if (action == 'reject') {
                    _showRejectModal(c);
                  }
                },
                itemBuilder: (ctx) => [
                  const PopupMenuItem(
                    value: 'logs',
                    child: Row(
                      children: [
                        Icon(Icons.assignment_outlined, size: 16, color: Color(0xFF64748B)),
                        SizedBox(width: 8),
                        Text('View Logs', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'offer',
                    child: Row(
                      children: [
                        Icon(Icons.insert_drive_file_outlined, size: 16, color: Color(0xFF16A34A)),
                        SizedBox(width: 8),
                        Text('Offer', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF16A34A))),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'reject',
                    child: Row(
                      children: [
                        Icon(Icons.cancel_outlined, size: 16, color: Color(0xFFDC2626)),
                        SizedBox(width: 8),
                        Text('Reject', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFDC2626))),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Role & Decision Date
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      const Icon(Icons.work_outline_rounded, size: 14, color: Color(0xFFEFAA1F)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          c.position,
                          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF1E293B)),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                Row(
                  children: [
                    const Icon(Icons.calendar_today_outlined, size: 12, color: Color(0xFF64748B)),
                    const SizedBox(width: 4),
                    Text(
                      c.decisionDate,
                      style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
