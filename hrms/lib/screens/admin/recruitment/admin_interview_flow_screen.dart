// lib/screens/admin/recruitment/admin_interview_flow_screen.dart
import 'package:flutter/material.dart';
import '../../../config/app_colors.dart';
import '../../../services/admin_staff_service.dart';
import '../../../services/api_client.dart';
import '../../../utils/snackbar_utils.dart';
import '../../../widgets/app_drawer.dart';
import '../../../widgets/app_tab_loader.dart';
import 'admin_interview_flow_details_screen.dart';

class AdminInterviewRound {
  final String id;
  int roundNumber;
  String name;
  String interviewer;
  String duration;
  List<Map<String, String>> questions; // {'text': '...', 'type': 'TEXT' | 'RATING' | 'SCENARIO' | 'MULTICHOICE'}

  AdminInterviewRound({
    required this.id,
    required this.roundNumber,
    required this.name,
    required this.interviewer,
    required this.duration,
    required this.questions,
  });

  factory AdminInterviewRound.fromJson(Map<String, dynamic> json) {
    final rawQs = json['questions'] as List? ?? [];
    return AdminInterviewRound(
      id: (json['id'] ?? 'R-1').toString(),
      roundNumber: int.tryParse(json['roundNumber']?.toString() ?? '1') ?? 1,
      name: (json['name'] ?? 'Interview Round').toString(),
      interviewer: (json['interviewer'] ?? 'Interviewer').toString(),
      duration: (json['duration'] ?? '60 mins').toString(),
      questions: rawQs.map((q) {
        if (q is Map) {
          return {
            'text': (q['text'] ?? q['question'] ?? '').toString(),
            'type': (q['type'] ?? 'TEXT').toString().toUpperCase(),
          };
        }
        return {'text': q.toString(), 'type': 'TEXT'};
      }).toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'roundNumber': roundNumber,
        'name': name,
        'interviewer': interviewer,
        'duration': duration,
        'questions': questions,
      };
}

class AdminJobFlow {
  final String jobId;
  String jobTitle;
  String department;
  List<AdminInterviewRound> rounds;

  AdminJobFlow({
    required this.jobId,
    required this.jobTitle,
    required this.department,
    required this.rounds,
  });

  factory AdminJobFlow.fromJson(Map<String, dynamic> json) {
    final rawRounds = json['rounds'] as List? ?? [];
    return AdminJobFlow(
      jobId: (json['jobId'] ?? 'JOB-001').toString(),
      jobTitle: (json['jobTitle'] ?? json['title'] ?? 'Job Position').toString(),
      department: (json['department'] ?? 'Engineering').toString(),
      rounds: rawRounds.map((r) => AdminInterviewRound.fromJson(Map<String, dynamic>.from(r as Map))).toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'jobId': jobId,
        'jobTitle': jobTitle,
        'department': department,
        'rounds': rounds.map((r) => r.toJson()).toList(),
      };
}

class AdminInterviewFlowScreen extends StatefulWidget {
  const AdminInterviewFlowScreen({super.key});

  @override
  State<AdminInterviewFlowScreen> createState() => _AdminInterviewFlowScreenState();
}

class _AdminInterviewFlowScreenState extends State<AdminInterviewFlowScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final AdminStaffService _staffService = AdminStaffService();
  final ApiClient _api = ApiClient();

  bool _isLoading = true;
  List<AdminJobFlow> _flows = [];

  List<String> _availableDepartments = ['Engineering', 'Design', 'Product', 'Sales', 'HR & Admin', 'Marketing'];

  @override
  void initState() {
    super.initState();
    _fetchFlowsAndSetup();
  }

  Future<void> _fetchFlowsAndSetup({bool showLoader = true}) async {
    if (showLoader && mounted) setState(() => _isLoading = true);

    try {
      // 1. Fetch backend departments setup
      try {
        final setupRes = await _staffService.getStaffSetup();
        if (setupRes['success'] == true && setupRes['data'] != null) {
          final branches = setupRes['data']['branches'] as List? ?? [];
          final depts = <String>{};
          for (final b in branches) {
            final d = (b['department'] ?? b['dept'])?.toString().trim();
            if (d != null && d.isNotEmpty) depts.add(d);
          }
          if (depts.isNotEmpty && mounted) {
            setState(() => _availableDepartments = {..._availableDepartments, ...depts}.toList());
          }
        }
      } catch (_) {}

      // 2. Fetch flows from backend API or load defaults
      final res = await _api.request('/admin/recruitment/interview-process/flow');
      if (res.data is Map && res.data['success'] == true) {
        final list = (res.data['data']?['flows'] as List?) ?? (res.data['data'] as List?) ?? [];
        if (list.isNotEmpty && mounted) {
          setState(() {
            _flows = list.map((e) => AdminJobFlow.fromJson(Map<String, dynamic>.from(e as Map))).toList();
          });
        } else {
          _setMockFlows();
        }
      } else {
        _setMockFlows();
      }
    } catch (_) {
      _setMockFlows();
    }

    if (showLoader && mounted) setState(() => _isLoading = false);
  }

  void _setMockFlows() {
    _flows = [
      AdminJobFlow(
        jobId: 'JOB-001',
        jobTitle: 'Senior Full-Stack Engineer',
        department: 'Engineering',
        rounds: [
          AdminInterviewRound(
            id: 'R-1',
            roundNumber: 1,
            name: 'Initial Coding Assessment',
            interviewer: 'Sanjay Patel (Tech Lead)',
            duration: '60 mins',
            questions: [
              {'text': 'Explain the difference between Virtual DOM and Real DOM in React.', 'type': 'TEXT'},
              {'text': 'Describe how you would optimize a slow Node.js API query.', 'type': 'TEXT'},
              {'text': 'Write a function to check if a binary tree is balanced.', 'type': 'TEXT'},
            ],
          ),
          AdminInterviewRound(
            id: 'R-2',
            roundNumber: 2,
            name: 'System Design & Architecture',
            interviewer: 'Animesh Roy (Principal Architect)',
            duration: '60 mins',
            questions: [
              {'text': 'How would you design a real-time notification service for 10M users?', 'type': 'TEXT'},
              {'text': 'Explain SQL vs NoSQL scaling constraints under high write volume.', 'type': 'TEXT'},
              {'text': 'Design a distributed rate limiter for REST APIs.', 'type': 'TEXT'},
            ],
          ),
          AdminInterviewRound(
            id: 'R-3',
            roundNumber: 3,
            name: 'HR & Culture Fit Assessment',
            interviewer: 'Meera Sen (HR Director)',
            duration: '30 mins',
            questions: [
              {'text': 'Describe a conflict you had with a team member and how you resolved it.', 'type': 'TEXT'},
              {'text': 'What motivates you to join our company and what are your long-term career goals?', 'type': 'TEXT'},
              {'text': 'How do you handle deadlines that seem unrealistic?', 'type': 'TEXT'},
            ],
          ),
        ],
      ),
      AdminJobFlow(
        jobId: 'JOB-002',
        jobTitle: 'Lead UI/UX Designer',
        department: 'Design',
        rounds: [
          AdminInterviewRound(
            id: 'R-4',
            roundNumber: 1,
            name: 'Portfolio Review & Discussion',
            interviewer: 'Vikram Malhotra (UX Director)',
            duration: '45 mins',
            questions: [
              {'text': 'Walk us through your design process for your favorite portfolio project.', 'type': 'TEXT'},
              {'text': 'How do you gather user research insights and implement them into mockups?', 'type': 'TEXT'},
              {'text': 'How do you handle disagreement from product managers on design patterns?', 'type': 'TEXT'},
            ],
          ),
          AdminInterviewRound(
            id: 'R-5',
            roundNumber: 2,
            name: 'Figma Interactive Whiteboarding',
            interviewer: 'Pooja Hegde (Senior Product Designer)',
            duration: '90 mins',
            questions: [
              {'text': 'Redesign the checkout experience for B2B SaaS platform in Figma.', 'type': 'TEXT'},
              {'text': 'Build a responsive navigation system with proper auto-layout constraints.', 'type': 'TEXT'},
              {'text': 'Show how you organize and structure components in a Figma design system.', 'type': 'TEXT'},
            ],
          ),
        ],
      ),
      AdminJobFlow(
        jobId: 'JOB-003',
        jobTitle: 'DevOps Engineer',
        department: 'Engineering',
        rounds: [
          AdminInterviewRound(
            id: 'R-6',
            roundNumber: 1,
            name: 'Infrastructure-as-Code Assessment',
            interviewer: 'Karan Singh (DevOps Lead)',
            duration: '60 mins',
            questions: [
              {'text': 'Explain best practices for Terraform state file locking and security.', 'type': 'TEXT'},
              {'text': 'How do you configure canary deployments in Kubernetes with Istio?', 'type': 'TEXT'},
              {'text': 'Describe automated rollbacks in CI/CD when health checks fail.', 'type': 'TEXT'},
            ],
          ),
        ],
      ),
    ];
  }

  void _showCreatePipelineModal() {
    final titleCtrl = TextEditingController();
    String dept = _availableDepartments.first;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: const [
                  Icon(Icons.account_tree_outlined, color: Color(0xFFEFAA1F), size: 22),
                  SizedBox(width: 8),
                  Text('Create Interview Pipeline', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('JOB TITLE / POSITION *', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: Color(0xFF64748B))),
                  const SizedBox(height: 6),
                  TextField(
                    controller: titleCtrl,
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'e.g. Backend Lead Engineer',
                      hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFEFAA1F))),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                  const SizedBox(height: 14),

                  const Text('DEPARTMENT', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: Color(0xFF64748B))),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: dept,
                        isExpanded: true,
                        icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: Color(0xFF64748B)),
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
                        items: _availableDepartments.map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
                        onChanged: (v) {
                          if (v != null) setModalState(() => dept = v);
                        },
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (titleCtrl.text.trim().isEmpty) {
                      SnackBarUtils.showSnackBar(context, 'Please enter a job title', isError: true);
                      return;
                    }
                    Navigator.pop(ctx);
                    final newJobId = 'JOB-${(_flows.length + 1).toString().padLeft(3, '0')}';
                    final newFlow = AdminJobFlow(
                      jobId: newJobId,
                      jobTitle: titleCtrl.text.trim(),
                      department: dept,
                      rounds: [
                        AdminInterviewRound(
                          id: 'R-1',
                          roundNumber: 1,
                          name: 'Initial Screening',
                          interviewer: 'HR Team',
                          duration: '30 mins',
                          questions: [
                            {'text': 'Briefly introduce yourself and recent work experience.', 'type': 'TEXT'},
                          ],
                        ),
                      ],
                    );
                    setState(() => _flows.insert(0, newFlow));
                    try {
                      await _api.request(
                        '/admin/recruitment/interview-process/flow',
                        method: 'POST',
                        data: newFlow.toJson(),
                      );
                    } catch (_) {}
                    if (mounted) {
                      SnackBarUtils.showSnackBar(context, 'Pipeline created! Opening configuration...');
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => AdminInterviewFlowDetailsScreen(flow: newFlow)),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFEFAA1F),
                    foregroundColor: const Color(0xFF0F172A),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    elevation: 0,
                  ),
                  child: const Text('Create Pipeline', style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _deleteFlow(AdminJobFlow flow) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Pipeline', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
        content: Text('Are you sure you want to delete the pipeline for ${flow.jobTitle}?', style: const TextStyle(fontSize: 13, color: Color(0xFF64748B))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B)))),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() => _flows.remove(flow));
              try {
                _api.request('/admin/recruitment/interview-process/flow/${flow.jobId}', method: 'DELETE');
              } catch (_) {}
              SnackBarUtils.showSnackBar(context, 'Pipeline deleted');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Delete'),
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
          'Interview Flow Pipelines',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
        ),
        centerTitle: false,
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Color(0xFF64748B), size: 22),
            onPressed: () => _fetchFlowsAndSetup(),
            tooltip: 'Refresh',
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _isLoading
          ? const Center(child: AppTabLoader())
          : RefreshIndicator(
              onRefresh: () => _fetchFlowsAndSetup(showLoader: false),
              color: AppColors.primary,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Top Banner with + Create Pipeline
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFF1F5F9)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: const [
                              Text(
                                'Interview Flow Pipelines',
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Manage, structure, and create custom multi-stage interview flows.',
                                style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        ElevatedButton.icon(
                          onPressed: _showCreatePipelineModal,
                          icon: const Icon(Icons.add_rounded, size: 16),
                          label: const Text('+ Create Pipeline', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800)),
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
                  ),
                  const SizedBox(height: 16),

                  if (_flows.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(36),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFF1F5F9)),
                      ),
                      child: Column(
                        children: const [
                          Icon(Icons.account_tree_outlined, size: 40, color: Color(0xFF94A3B8)),
                          SizedBox(height: 10),
                          Text('No interview pipelines configured', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF475569))),
                        ],
                      ),
                    )
                  else
                    ..._flows.map((flow) => _buildPipelineCard(flow)),
                ],
              ),
            ),
    );
  }

  Widget _buildPipelineCard(AdminJobFlow flow) {
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: const Color(0xFFFFFBEB), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFFDE68A))),
                child: const Icon(Icons.work_outline_rounded, size: 18, color: Color(0xFFD97706)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            flow.jobTitle,
                            style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                          decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(6)),
                          child: Text(
                            flow.department.toUpperCase(),
                            style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Color(0xFF64748B)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      flow.jobId,
                      style: const TextStyle(fontSize: 10.5, fontFamily: 'monospace', fontWeight: FontWeight.w700, color: Color(0xFF94A3B8)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Stage Sequence Pills
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: const Color(0xFFECFDF5), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFA7F3D0))),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_outline_rounded, size: 12, color: Color(0xFF059669)),
                    const SizedBox(width: 4),
                    Text(
                      '${flow.rounds.length} Stages',
                      style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Color(0xFF059669)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Sequence Chips
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: flow.rounds.asMap().entries.map((entry) {
              final idx = entry.key;
              final r = entry.value;
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Text(
                  '${idx + 1}. ${r.name}',
                  style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: Color(0xFF475569)),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 14),

          // Action Buttons: Configure & Delete
          Row(
            children: [
              IconButton(
                onPressed: () => _deleteFlow(flow),
                icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Color(0xFF94A3B8)),
                tooltip: 'Delete Pipeline',
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => AdminInterviewFlowDetailsScreen(flow: flow)),
                  );
                  setState(() {});
                },
                icon: const Icon(Icons.settings_suggest_rounded, size: 15),
                label: const Text('Configure ❯', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
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
