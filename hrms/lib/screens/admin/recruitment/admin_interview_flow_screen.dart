// lib/screens/admin/recruitment/admin_interview_flow_screen.dart
// Interview Flow: one interview pipeline per job opening. Create, open, delete.

import 'package:flutter/material.dart';

import '../../../config/app_colors.dart';
import '../../../models/admin_recruitment_models.dart';
import '../../../services/admin_recruitment_service.dart';
import '../../../widgets/app_drawer.dart';
import 'admin_interview_flow_details_screen.dart';
import 'rec_widgets.dart';

class AdminInterviewFlowScreen extends StatefulWidget {
  const AdminInterviewFlowScreen({super.key});

  @override
  State<AdminInterviewFlowScreen> createState() => _AdminInterviewFlowScreenState();
}

class _AdminInterviewFlowScreenState extends State<AdminInterviewFlowScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final AdminRecruitmentService _service = AdminRecruitmentService();

  bool _loading = true;
  String? _error;
  List<RecInterviewFlow> _flows = [];
  String _search = '';
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool showLoader = true}) async {
    if (showLoader) setState(() => _loading = true);
    try {
      final flows = await _service.getInterviewFlows();
      if (!mounted) return;
      setState(() {
        _flows = flows;
        _error = null;
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

  Future<void> _create() async {
    setState(() => _creating = true);
    List<RecJobOpening> jobs;
    try {
      jobs = await _service.getJobOpenings();
    } catch (e) {
      if (mounted) {
        recShowError(context, e);
        setState(() => _creating = false);
      }
      return;
    }
    if (!mounted) return;
    setState(() => _creating = false);
    final taken = _flows.map((f) => f.jobOpeningId).toSet();
    final available = jobs.where((j) => !taken.contains(j.id)).toList();
    if (available.isEmpty) {
      recShowError(context, 'Every job opening already has an interview flow.');
      return;
    }
    final jobId = await recShowActions(
      context,
      title: 'Create flow for job opening',
      actions: available.map((j) => RecAction(j.id, '${j.title} (${j.code}) - ${j.status}', Icons.work_outline_rounded)).toList(),
    );
    if (jobId == null || !mounted) return;
    try {
      final flow = await _service.createInterviewFlow(jobId);
      if (!mounted) return;
      recShowSuccess(context, 'Interview flow created - add its rounds');
      await Navigator.push(context, MaterialPageRoute(builder: (_) => AdminInterviewFlowDetailsScreen(flowId: flow.id)));
      _load(showLoader: false);
    } catch (e) {
      if (mounted) recShowError(context, e);
    }
  }

  Future<void> _delete(RecInterviewFlow f) async {
    final ok = await recConfirm(context,
        title: 'Delete interview flow?',
        message: 'The pipeline for "${f.jobTitle}" and its ${f.rounds.length} round(s) will be removed. '
            'Rounds already scheduled for candidates stay as they are.',
        confirmLabel: 'Delete',
        destructive: true);
    if (!ok) return;
    try {
      final msg = await _service.deleteInterviewFlow(f.id);
      if (!mounted) return;
      recShowSuccess(context, msg);
      _load(showLoader: false);
    } catch (e) {
      if (mounted) recShowError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _search.toLowerCase();
    final visible = _flows
        .where((f) => q.isEmpty || f.jobTitle.toLowerCase().contains(q) || f.jobCode.toLowerCase().contains(q) || f.department.toLowerCase().contains(q))
        .toList();

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: kRecBg,
      drawer: const AppDrawer(),
      appBar: recAppBar(context, 'Interview Flow', drawerKey: _scaffoldKey, onRefresh: () => _load()),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _creating ? null : _create,
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        icon: _creating
            ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onPrimary))
            : const Icon(Icons.add_rounded),
        label: const Text('New Flow', style: TextStyle(fontWeight: FontWeight.w600)),
      ),
      body: RecAsyncBody(
        loading: _loading,
        error: _error,
        isEmpty: _flows.isEmpty,
        emptyText: 'No interview flows yet.\nCreate one for a job opening.',
        emptyIcon: Icons.account_tree_outlined,
        onRetry: _load,
        builder: () => RefreshIndicator(
          onRefresh: () => _load(showLoader: false),
          color: AppColors.primary,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
            children: [
              RecSearchField(hint: 'Search job title, code or department', onChanged: (v) => setState(() => _search = v)),
              const SizedBox(height: 12),
              ...visible.map((f) => RecCard(
                    onTap: () async {
                      await Navigator.push(
                          context, MaterialPageRoute(builder: (_) => AdminInterviewFlowDetailsScreen(flowId: f.id)));
                      _load(showLoader: false);
                    },
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          const RecIconTile(Icons.account_tree_outlined),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(f.jobTitle, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: kRecInk)),
                                const SizedBox(height: 2),
                                Text('${f.jobCode} • ${f.department}',
                                    style: const TextStyle(fontSize: 12.5, color: kRecMuted, fontWeight: FontWeight.w500)),
                              ],
                            ),
                          ),
                          if (f.jobStatus.isNotEmpty) RecBadge(f.jobStatus[0] + f.jobStatus.substring(1).toLowerCase(), colorKey: f.jobStatus),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            tooltip: 'Delete',
                            icon: const Icon(Icons.delete_outline_rounded, color: AppColors.error, size: 20),
                            onPressed: () => _delete(f),
                          ),
                        ]),
                        const SizedBox(height: 12),
                        if (f.rounds.isEmpty)
                          const Text('No rounds yet', style: TextStyle(fontSize: 12.5, color: kRecMuted))
                        else
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: f.rounds
                                .map((r) => Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                      decoration: BoxDecoration(color: kRecBg, borderRadius: BorderRadius.circular(999), border: Border.all(color: kRecSoftBorder)),
                                      child: Text('${r.roundNumber}. ${r.name}',
                                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: kRecInk)),
                                    ))
                                .toList(),
                          ),
                      ],
                    ),
                  )),
            ],
          ),
        ),
      ),
    );
  }
}
