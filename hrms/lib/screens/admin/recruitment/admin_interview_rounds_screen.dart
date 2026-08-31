// lib/screens/admin/recruitment/admin_interview_rounds_screen.dart
import 'package:flutter/material.dart';
import '../../../config/app_colors.dart';
import '../../../services/api_client.dart';
import '../../../utils/snackbar_utils.dart';
import '../../../widgets/app_drawer.dart';
import '../../../widgets/app_tab_loader.dart';
import 'admin_candidate_scorecard_screen.dart';

class AdminEvaluationRoundItem {
  final String id;
  final String candidateName;
  final String candidateEmail;
  final String position;
  final String round;
  final int roundNumber;
  final String interviewerName;
  final String interviewDate;
  final String interviewTime;
  final String mode;
  String status;
  int overallScore;
  String generalFeedback;
  String recommendation;

  AdminEvaluationRoundItem({
    required this.id,
    required this.candidateName,
    required this.candidateEmail,
    required this.position,
    required this.round,
    required this.roundNumber,
    required this.interviewerName,
    required this.interviewDate,
    required this.interviewTime,
    required this.mode,
    required this.status,
    this.overallScore = 9,
    this.generalFeedback = 'Exceptional visual layout skills and typography. Strong case studies in components systems.',
    this.recommendation = 'Pass',
  });

  factory AdminEvaluationRoundItem.fromJson(Map<String, dynamic> json) {
    return AdminEvaluationRoundItem(
      id: (json['id'] ?? 'INT-003').toString(),
      candidateName: (json['candidateName'] ?? 'Candidate').toString(),
      candidateEmail: (json['candidateEmail'] ?? '').toString(),
      position: (json['position'] ?? 'Product Designer').toString(),
      round: (json['round'] ?? 'Portfolio Review').toString(),
      roundNumber: int.tryParse(json['roundNumber']?.toString() ?? '1') ?? 1,
      interviewerName: (json['interviewerName'] ?? 'Interviewer').toString(),
      interviewDate: (json['interviewDate'] ?? '2026-08-26').toString(),
      interviewTime: (json['interviewTime'] ?? '11:00').toString(),
      mode: (json['mode'] ?? 'Zoom').toString(),
      status: (json['status'] ?? 'Evaluated - Pass').toString(),
      overallScore: int.tryParse(json['overallScore']?.toString() ?? '9') ?? 9,
      generalFeedback: (json['generalFeedback'] ?? '').toString(),
      recommendation: (json['recommendation'] ?? 'Pass').toString(),
    );
  }
}

class AdminInterviewRoundsScreen extends StatefulWidget {
  const AdminInterviewRoundsScreen({super.key});

  @override
  State<AdminInterviewRoundsScreen> createState() => _AdminInterviewRoundsScreenState();
}

class _AdminInterviewRoundsScreenState extends State<AdminInterviewRoundsScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final ApiClient _api = ApiClient();

  bool _isLoading = true;
  String _searchQuery = '';
  String _statusFilter = 'All';

  List<AdminEvaluationRoundItem> _items = [];

  @override
  void initState() {
    super.initState();
    _fetchRounds();
  }

  Future<void> _fetchRounds({bool showLoader = true}) async {
    if (showLoader && mounted) setState(() => _isLoading = true);

    try {
      final res = await _api.request('/admin/recruitment/interview-process/rounds');
      if (res.data is Map && res.data['success'] == true) {
        final list = (res.data['data']?['rounds'] as List?) ?? (res.data['data'] as List?) ?? [];
        if (list.isNotEmpty && mounted) {
          setState(() {
            _items = list.map((e) => AdminEvaluationRoundItem.fromJson(Map<String, dynamic>.from(e as Map))).toList();
          });
        } else {
          _setMockRounds();
        }
      } else {
        _setMockRounds();
      }
    } catch (_) {
      _setMockRounds();
    }

    if (showLoader && mounted) setState(() => _isLoading = false);
  }

  void _setMockRounds() {
    _items = [
      AdminEvaluationRoundItem(
        id: 'INT-003',
        candidateName: 'Rohan Mehta',
        candidateEmail: 'rohan.mehta@example.com',
        position: 'Product Designer',
        round: 'Portfolio Review',
        roundNumber: 1,
        interviewerName: 'Vikram Malhotra (UX Director)',
        interviewDate: '2026-08-26',
        interviewTime: '11:00',
        mode: 'ZOOM',
        status: 'Evaluated - Pass',
        overallScore: 9,
        generalFeedback: 'Exceptional visual layout skills and typography. Strong case studies in components systems. Needs minor improvement in responsive layout details.',
        recommendation: 'Pass',
      ),
      AdminEvaluationRoundItem(
        id: 'INT-001',
        candidateName: 'Amit Sharma',
        candidateEmail: 'amit.sharma@example.com',
        position: 'Senior Full-Stack Engineer',
        round: 'Initial Coding Assessment',
        roundNumber: 1,
        interviewerName: 'Sanjay Patel (Tech Lead)',
        interviewDate: '2026-08-28',
        interviewTime: '10:00',
        mode: 'GOOGLE MEET',
        status: 'Pending Evaluation',
        overallScore: 0,
        generalFeedback: '',
        recommendation: 'Pending',
      ),
      AdminEvaluationRoundItem(
        id: 'INT-004',
        candidateName: 'Sneha Reddy',
        candidateEmail: 'sneha.reddy@example.com',
        position: 'DevOps Engineer',
        round: 'Infrastructure Round',
        roundNumber: 1,
        interviewerName: 'Karan Singh (DevOps Lead)',
        interviewDate: '2026-08-29',
        interviewTime: '16:00',
        mode: 'GOOGLE MEET',
        status: 'Scheduled',
        overallScore: 0,
        generalFeedback: '',
        recommendation: 'Pending',
      ),
    ];
  }

  List<AdminEvaluationRoundItem> get _filteredItems {
    return _items.where((i) {
      final matchesSearch = _searchQuery.isEmpty ||
          i.candidateName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          i.position.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          i.interviewerName.toLowerCase().contains(_searchQuery.toLowerCase());

      final matchesStatus = _statusFilter == 'All' || i.status.toLowerCase().contains(_statusFilter.toLowerCase());

      return matchesSearch && matchesStatus;
    }).toList();
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
          'Interview Evaluation Rounds',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
        ),
        centerTitle: false,
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Color(0xFF64748B), size: 22),
            onPressed: () => _fetchRounds(),
            tooltip: 'Refresh',
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _isLoading
          ? const Center(child: AppTabLoader())
          : RefreshIndicator(
              onRefresh: () => _fetchRounds(showLoader: false),
              color: AppColors.primary,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Search & Filter Header
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
                          'Review active assessment queues, evaluate candidates, and read historical scorecard notes.',
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
                              hintText: 'Search candidate, role, or interviewer...',
                              hintStyle: TextStyle(fontSize: 11.5, color: Color(0xFF94A3B8)),
                              prefixIcon: Icon(Icons.search_rounded, size: 18, color: Color(0xFF94A3B8)),
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(vertical: 11),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  if (_filteredItems.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(36),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                      child: const Text('No interview evaluation rounds found', style: TextStyle(fontSize: 13, color: Color(0xFF94A3B8))),
                    )
                  else
                    ..._filteredItems.map((item) => _buildRoundCard(item)),
                ],
              ),
            ),
    );
  }

  Widget _buildRoundCard(AdminEvaluationRoundItem item) {
    Color stBg = const Color(0xFFFEF3C7);
    Color stFg = const Color(0xFFD97706);
    if (item.status.contains('Pass')) {
      stBg = const Color(0xFFDCFCE7);
      stFg = const Color(0xFF16A34A);
    } else if (item.status.contains('Fail') || item.status.contains('Reject')) {
      stBg = const Color(0xFFFEE2E2);
      stFg = const Color(0xFFDC2626);
    }

    return InkWell(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => AdminCandidateScorecardScreen(item: item)),
        );
        setState(() {});
      },
      child: Container(
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
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(item.candidateName, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: Color(0xFF0F172A))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: stBg, borderRadius: BorderRadius.circular(20)),
                  child: Text(
                    item.status,
                    style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900, color: stFg),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(item.candidateEmail, style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
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
                    children: [
                      const Icon(Icons.work_outline_rounded, size: 14, color: Color(0xFFEFAA1F)),
                      const SizedBox(width: 6),
                      Text(item.position, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: const Color(0xFFFFFBEB), borderRadius: BorderRadius.circular(4), border: Border.all(color: const Color(0xFFFDE68A))),
                        child: Text('ROUND ${item.roundNumber}', style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.w800, color: Color(0xFFD97706))),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text('Type: ${item.round}', style: const TextStyle(fontSize: 10.5, color: Color(0xFF64748B))),
                    ],
                  ),
                  const Divider(height: 14, color: Color(0xFFE2E8F0)),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.person_outline_rounded, size: 13, color: Color(0xFF64748B)),
                          const SizedBox(width: 4),
                          Text(item.interviewerName, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: Color(0xFF475569))),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(4)),
                        child: Text(item.mode, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Color(0xFF2563EB))),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            Row(
              children: [
                const Icon(Icons.calendar_today_outlined, size: 13, color: Color(0xFF64748B)),
                const SizedBox(width: 6),
                Text('${item.interviewDate} at ${item.interviewTime}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF64748B))),
                const Spacer(),
                const Text('View Scorecard ❯', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFFD97706))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
