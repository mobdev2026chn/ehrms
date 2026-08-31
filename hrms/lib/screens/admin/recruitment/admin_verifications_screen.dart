// lib/screens/admin/recruitment/admin_verifications_screen.dart
import 'package:flutter/material.dart';
import '../../../config/app_colors.dart';
import '../../../services/api_client.dart';
import '../../../utils/snackbar_utils.dart';
import '../../../widgets/app_drawer.dart';
import '../../../widgets/app_tab_loader.dart';
import 'admin_verification_detail_screen.dart';

class VerificationDoc {
  final String title;
  final String fileName;
  String status; // 'Verified' | 'Pending Review' | 'Missing'

  VerificationDoc({required this.title, required this.fileName, required this.status});
}

class AdminCandidateVerification {
  final String id;
  final String firstName;
  final String lastName;
  final String email;
  final String phone;
  final String position;
  final String appliedDate;
  List<VerificationDoc> documents;

  AdminCandidateVerification({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.phone,
    required this.position,
    required this.appliedDate,
    required this.documents,
  });

  String get fullName => '$firstName $lastName'.trim();
  String get initials => '${firstName.isNotEmpty ? firstName[0] : ""}${lastName.isNotEmpty ? lastName[0] : ""}'.toUpperCase();

  int get verifiedCount => documents.where((d) => d.status == 'Verified').length;
  bool get isCompleted => verifiedCount == documents.length && documents.isNotEmpty;

  factory AdminCandidateVerification.fromJson(Map<String, dynamic> json) {
    final nameParts = (json['name']?.toString() ?? '').split(' ');
    final fn = (json['firstName'] ?? (nameParts.isNotEmpty && nameParts.first.isNotEmpty ? nameParts.first : 'Candidate')).toString();
    final ln = (json['lastName'] ?? (nameParts.length > 1 ? nameParts.sublist(1).join(' ') : '')).toString();

    final rawDocs = json['documents'] as List? ?? [];
    List<VerificationDoc> docs = [];
    if (rawDocs.isNotEmpty) {
      docs = rawDocs
          .map((d) => VerificationDoc(
                title: (d['title'] ?? 'Document').toString(),
                fileName: (d['fileName'] ?? 'document.pdf').toString(),
                status: (d['status'] ?? 'Pending Review').toString(),
              ))
          .toList();
    } else {
      docs = [
        VerificationDoc(title: 'Government ID (Aadhaar / Passport)', fileName: 'aadhaar_card.pdf', status: 'Verified'),
        VerificationDoc(title: 'Highest Educational Certificate', fileName: 'degree_certificate.pdf', status: 'Verified'),
        VerificationDoc(title: 'Relieving / Experience Letter', fileName: 'relieving_letter.pdf', status: 'Pending Review'),
        VerificationDoc(title: 'Bank Passbook / Cancelled Cheque', fileName: 'bank_cheque.pdf', status: 'Pending Review'),
      ];
    }

    return AdminCandidateVerification(
      id: (json['id'] ?? 'C-001').toString(),
      firstName: fn,
      lastName: ln,
      email: (json['email'] ?? '').toString(),
      phone: (json['phone'] ?? '').toString(),
      position: (json['position'] ?? 'Software Engineer').toString(),
      appliedDate: (json['appliedDate'] ?? '2026-07-02').toString(),
      documents: docs,
    );
  }
}

class AdminVerificationsScreen extends StatefulWidget {
  const AdminVerificationsScreen({super.key});

  @override
  State<AdminVerificationsScreen> createState() => _AdminVerificationsScreenState();
}

class _AdminVerificationsScreenState extends State<AdminVerificationsScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final ApiClient _api = ApiClient();

  bool _isLoading = true;
  String _searchQuery = '';
  String _statusFilter = 'All Statuses'; // 'All Statuses' | 'Pending' | 'Completed'

  List<AdminCandidateVerification> _candidates = [];

  @override
  void initState() {
    super.initState();
    _fetchVerifications();
  }

  Future<void> _fetchVerifications({bool showLoader = true}) async {
    if (showLoader && mounted) setState(() => _isLoading = true);

    try {
      final res = await _api.request('/admin/recruitment/verifications');
      if (res.data is Map && res.data['success'] == true) {
        final list = (res.data['data']?['candidates'] as List?) ?? (res.data['data'] as List?) ?? [];
        if (list.isNotEmpty && mounted) {
          setState(() {
            _candidates = list.map((e) => AdminCandidateVerification.fromJson(Map<String, dynamic>.from(e as Map))).toList();
          });
        } else {
          _setMockVerifications();
        }
      } else {
        _setMockVerifications();
      }
    } catch (_) {
      _setMockVerifications();
    }

    if (showLoader && mounted) setState(() => _isLoading = false);
  }

  void _setMockVerifications() {
    _candidates = [
      AdminCandidateVerification(
        id: 'C-004',
        firstName: 'Anjali',
        lastName: 'Rao',
        email: 'anjali.rao@example.com',
        phone: '+91 65432 10987',
        position: 'HR Manager',
        appliedDate: '2026-06-15',
        documents: [
          VerificationDoc(title: 'Government ID (Aadhaar / Passport)', fileName: 'aadhaar_anjali.pdf', status: 'Verified'),
          VerificationDoc(title: 'Highest Educational Certificate', fileName: 'mba_degree.pdf', status: 'Verified'),
          VerificationDoc(title: 'Relieving / Experience Letter', fileName: 'relieving_letter.pdf', status: 'Verified'),
          VerificationDoc(title: 'Bank Passbook / Cancelled Cheque', fileName: 'cancelled_cheque.pdf', status: 'Verified'),
        ],
      ),
      AdminCandidateVerification(
        id: 'C-006',
        firstName: 'Sunita',
        lastName: 'Rao',
        email: 'sunita.rao@example.com',
        phone: '+91 99887 76655',
        position: 'Senior Frontend Developer',
        appliedDate: '2026-06-25',
        documents: [
          VerificationDoc(title: 'Government ID (Aadhaar / Passport)', fileName: 'aadhaar_sunita.pdf', status: 'Verified'),
          VerificationDoc(title: 'Highest Educational Certificate', fileName: 'btech_degree.pdf', status: 'Verified'),
          VerificationDoc(title: 'Relieving / Experience Letter', fileName: 'exp_letter.pdf', status: 'Pending Review'),
          VerificationDoc(title: 'Bank Passbook / Cancelled Cheque', fileName: 'bank_statement.pdf', status: 'Pending Review'),
        ],
      ),
      AdminCandidateVerification(
        id: 'C-001',
        firstName: 'Amit',
        lastName: 'Sharma',
        email: 'amit.sharma@example.com',
        phone: '+91 98765 43210',
        position: 'Senior Full-Stack Engineer',
        appliedDate: '2026-07-02',
        documents: [
          VerificationDoc(title: 'Government ID (Aadhaar / Passport)', fileName: 'passport_amit.pdf', status: 'Verified'),
          VerificationDoc(title: 'Highest Educational Certificate', fileName: 'degree_certificate.pdf', status: 'Pending Review'),
          VerificationDoc(title: 'Relieving / Experience Letter', fileName: 'relieving_tech.pdf', status: 'Pending Review'),
          VerificationDoc(title: 'Bank Passbook / Cancelled Cheque', fileName: 'cheque_amit.pdf', status: 'Pending Review'),
        ],
      ),
    ];
  }

  List<AdminCandidateVerification> get _filteredCandidates {
    return _candidates.where((c) {
      final matchesSearch = _searchQuery.isEmpty ||
          c.fullName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          c.email.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          c.position.toLowerCase().contains(_searchQuery.toLowerCase());

      bool matchesStatus = true;
      if (_statusFilter == 'Pending') {
        matchesStatus = !c.isCompleted;
      } else if (_statusFilter == 'Completed') {
        matchesStatus = c.isCompleted;
      }

      return matchesSearch && matchesStatus;
    }).toList();
  }

  // ── Action: Review Documents Modal ──
  void _showReviewDocumentsModal(AdminCandidateVerification c) {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                const Icon(Icons.folder_shared_outlined, color: Color(0xFFEFAA1F), size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${c.fullName} Verifications', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                      Text(c.position, style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                    ],
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ...c.documents.asMap().entries.map((entry) {
                      final doc = entry.value;
                      final isVerified = doc.status == 'Verified';

                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(doc.title, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: isVerified ? const Color(0xFFDCFCE7) : const Color(0xFFFEF3C7),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    doc.status,
                                    style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: isVerified ? const Color(0xFF16A34A) : const Color(0xFFD97706)),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                const Icon(Icons.picture_as_pdf_outlined, color: Color(0xFFEF4444), size: 16),
                                const SizedBox(width: 6),
                                Expanded(child: Text(doc.fileName, style: const TextStyle(fontSize: 10.5, color: Color(0xFF64748B)))),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                if (!isVerified)
                                  ElevatedButton.icon(
                                    onPressed: () {
                                      setModalState(() => doc.status = 'Verified');
                                      setState(() {});
                                      try {
                                        _api.request('/admin/recruitment/verifications/${c.id}/verify', method: 'POST', data: {'document': doc.title});
                                      } catch (_) {}
                                      SnackBarUtils.showSnackBar(context, '${doc.title} marked as Verified');
                                    },
                                    icon: const Icon(Icons.check_rounded, size: 14),
                                    label: const Text('Approve', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800)),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF16A34A),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                      elevation: 0,
                                    ),
                                  )
                                else
                                  TextButton(
                                    onPressed: () {
                                      setModalState(() => doc.status = 'Pending Review');
                                      setState(() {});
                                    },
                                    child: const Text('Mark Pending', style: TextStyle(fontSize: 10.5, color: Color(0xFF64748B))),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close', style: TextStyle(color: Color(0xFF64748B)))),
              if (c.isCompleted)
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    SnackBarUtils.showSnackBar(context, 'All documents verified! ${c.fullName} ready for onboarding.');
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEFAA1F), foregroundColor: const Color(0xFF0F172A)),
                  child: const Text('Onboard Candidate', style: TextStyle(fontWeight: FontWeight.w800)),
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
          'Onboarding Verifications',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
        ),
        centerTitle: false,
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Color(0xFF64748B), size: 22),
            onPressed: () => _fetchVerifications(),
            tooltip: 'Refresh',
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _isLoading
          ? const Center(child: AppTabLoader())
          : RefreshIndicator(
              onRefresh: () => _fetchVerifications(showLoader: false),
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
                          'Review, request, and verify onboarding document submissions for hired or offered candidates.',
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
                              hintText: 'Search candidates name or email...',
                              hintStyle: TextStyle(fontSize: 11.5, color: Color(0xFF94A3B8)),
                              prefixIcon: Icon(Icons.search_rounded, size: 18, color: Color(0xFF94A3B8)),
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(vertical: 11),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),

                        // Status Filter Dropdown matching Web UI
                        Row(
                          children: [
                            const Icon(Icons.filter_list_rounded, size: 16, color: Color(0xFF64748B)),
                            const SizedBox(width: 6),
                            const Text('Status:', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF475569))),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Container(
                                height: 38,
                                padding: const EdgeInsets.symmetric(horizontal: 10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: const Color(0xFFE2E8F0)),
                                ),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    value: _statusFilter,
                                    isExpanded: true,
                                    icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: Color(0xFF64748B)),
                                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                                    items: const ['All Statuses', 'Completed', 'Pending']
                                        .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                                        .toList(),
                                    onChanged: (v) {
                                      if (v != null) setState(() => _statusFilter = v);
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
                      child: const Text('No candidates with pending document verifications', style: TextStyle(fontSize: 13, color: Color(0xFF94A3B8))),
                    )
                  else
                    ..._filteredCandidates.map((c) => _buildVerificationCard(c)),
                ],
              ),
            ),
    );
  }

  Widget _buildVerificationCard(AdminCandidateVerification c) {
    final progress = c.documents.isNotEmpty ? c.verifiedCount / c.documents.length : 0.0;
    final isCompleted = c.isCompleted;

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
                decoration: BoxDecoration(
                  color: isCompleted ? const Color(0xFFDCFCE7) : const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  isCompleted ? 'COMPLETED' : 'PENDING',
                  style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900, color: isCompleted ? const Color(0xFF16A34A) : const Color(0xFFD97706)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Role & Progress
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.work_outline_rounded, size: 14, color: Color(0xFFEFAA1F)),
                    const SizedBox(width: 6),
                    Text(c.position, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Verification: ${c.verifiedCount}/${c.documents.length} Verified', style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Color(0xFF64748B))),
                    Text('${(progress * 100).toInt()}%', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: isCompleted ? const Color(0xFF16A34A) : const Color(0xFFD97706))),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: const Color(0xFFE2E8F0),
                    valueColor: AlwaysStoppedAnimation<Color>(isCompleted ? const Color(0xFF16A34A) : const Color(0xFFEFAA1F)),
                    minHeight: 6,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Verify Checklist Action matching Web UI
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              ElevatedButton.icon(
                onPressed: () async {
                  final res = await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => AdminVerificationDetailScreen(candidate: c)),
                  );
                  if (res == true) {
                    _fetchVerifications();
                  } else {
                    setState(() {});
                  }
                },
                icon: const Icon(Icons.remove_red_eye_outlined, size: 14),
                label: const Text('Verify Checklist', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFFBEB),
                  foregroundColor: const Color(0xFFD97706),
                  elevation: 0,
                  side: const BorderSide(color: Color(0xFFFDE68A)),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
