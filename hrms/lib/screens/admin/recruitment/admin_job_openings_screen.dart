// lib/screens/admin/recruitment/admin_job_openings_screen.dart
// Job Openings: list with search, status/department filters, view, edit, status change, delete.

import 'package:flutter/material.dart';

import '../../../config/app_colors.dart';
import '../../../models/admin_recruitment_models.dart';
import '../../../services/admin_recruitment_service.dart';
import '../../../widgets/app_drawer.dart';
import 'admin_add_job_screen.dart';
import 'admin_job_detail_screen.dart';
import 'rec_widgets.dart';

const List<String> kJobStatuses = ['ACTIVE', 'DRAFT', 'CLOSED', 'INACTIVE', 'CANCELED'];
const List<String> kJobDepartments = ['IT', 'Marketing', 'HR', 'Sales'];

String jobStatusLabel(String s) => s.isEmpty ? s : s[0] + s.substring(1).toLowerCase();

/// Lets the user pick a new status for [job] and saves it. Returns true when changed.
Future<bool> changeJobStatus(BuildContext context, RecJobOpening job) async {
  final picked = await recShowActions(
    context,
    title: 'Change status',
    actions: kJobStatuses
        .where((s) => s != job.status)
        .map((s) => RecAction(s, jobStatusLabel(s), Icons.flag_outlined))
        .toList(),
  );
  if (picked == null || !context.mounted) return false;
  try {
    final msg = await AdminRecruitmentService().updateJobOpeningStatus(job.id, picked);
    if (context.mounted) recShowSuccess(context, msg);
    return true;
  } catch (e) {
    if (context.mounted) recShowError(context, e);
    return false;
  }
}

/// Confirms and deletes [job]. Returns true when deleted.
Future<bool> deleteJob(BuildContext context, RecJobOpening job) async {
  final ok = await recConfirm(
    context,
    title: 'Delete job opening?',
    message: '"${job.title}" (${job.code}) will be removed permanently.',
    confirmLabel: 'Delete',
    destructive: true,
  );
  if (!ok || !context.mounted) return false;
  try {
    final msg = await AdminRecruitmentService().deleteJobOpening(job.id);
    if (context.mounted) recShowSuccess(context, msg);
    return true;
  } catch (e) {
    if (context.mounted) recShowError(context, e);
    return false;
  }
}

class AdminJobOpeningsScreen extends StatefulWidget {
  const AdminJobOpeningsScreen({super.key});

  @override
  State<AdminJobOpeningsScreen> createState() => _AdminJobOpeningsScreenState();
}

class _AdminJobOpeningsScreenState extends State<AdminJobOpeningsScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final AdminRecruitmentService _service = AdminRecruitmentService();

  bool _loading = true;
  String? _error;
  List<RecJobOpening> _jobs = [];
  String _search = '';
  String _status = 'All';
  String _department = 'All';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool showLoader = true}) async {
    if (showLoader) setState(() => _loading = true);
    try {
      final jobs = await _service.getJobOpenings();
      if (!mounted) return;
      setState(() {
        _jobs = jobs;
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

  List<RecJobOpening> get _filtered {
    final q = _search.toLowerCase();
    return _jobs.where((j) {
      if (_status != 'All' && j.status != _status) return false;
      if (_department != 'All' && j.department != _department) return false;
      if (q.isEmpty) return true;
      return j.title.toLowerCase().contains(q) ||
          j.code.toLowerCase().contains(q) ||
          j.branch.toLowerCase().contains(q) ||
          j.skills.any((s) => s.toLowerCase().contains(q));
    }).toList();
  }

  Future<void> _openForm([RecJobOpening? job]) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => AdminAddJobScreen(job: job)),
    );
    if (saved == true) _load(showLoader: false);
  }

  Future<void> _openDetail(RecJobOpening job) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => AdminJobDetailScreen(jobId: job.id)),
    );
    if (changed == true) _load(showLoader: false);
  }

  Future<void> _showActions(RecJobOpening job) async {
    final action = await recShowActions(context, title: job.title, actions: const [
      RecAction('view', 'View details', Icons.visibility_outlined),
      RecAction('edit', 'Edit', Icons.edit_outlined),
      RecAction('status', 'Change status', Icons.flag_outlined),
      RecAction('delete', 'Delete', Icons.delete_outline_rounded, destructive: true),
    ]);
    if (!mounted || action == null) return;
    switch (action) {
      case 'view':
        _openDetail(job);
        break;
      case 'edit':
        _openForm(job);
        break;
      case 'status':
        if (await changeJobStatus(context, job)) _load(showLoader: false);
        break;
      case 'delete':
        if (await deleteJob(context, job)) _load(showLoader: false);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final counts = <String, int>{'All': _jobs.length};
    for (final s in kJobStatuses) {
      counts[s] = _jobs.where((j) => j.status == s).length;
    }
    final filtered = _filtered;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: kRecBg,
      drawer: const AppDrawer(),
      appBar: recAppBar(context, 'Job Openings', drawerKey: _scaffoldKey, onRefresh: () => _load()),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Job', style: TextStyle(fontWeight: FontWeight.w600)),
      ),
      body: RecAsyncBody(
        loading: _loading,
        error: _error,
        isEmpty: false,
        onRetry: _load,
        builder: () => RefreshIndicator(
          onRefresh: () => _load(showLoader: false),
          color: AppColors.primary,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
            children: [
              RecSearchField(hint: 'Search title, code, branch or skill', onChanged: (v) => setState(() => _search = v)),
              const SizedBox(height: 12),
              RecFilterChips(
                options: ['All', ...kJobStatuses],
                selected: _status,
                counts: counts,
                labelOf: (s) => s == 'All' ? 'All' : jobStatusLabel(s),
                onSelected: (s) => setState(() => _status = s),
              ),
              const SizedBox(height: 8),
              RecFilterChips(
                options: const ['All', ...kJobDepartments],
                selected: _department,
                labelOf: (s) => s == 'All' ? 'All departments' : s,
                onSelected: (s) => setState(() => _department = s),
              ),
              const SizedBox(height: 12),
              if (filtered.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 60),
                  child: RecEmptyState(text: 'No job openings match the current filters', icon: Icons.work_off_outlined),
                )
              else
                ...filtered.map(_jobCard),
            ],
          ),
        ),
      ),
    );
  }

  Widget _jobCard(RecJobOpening j) {
    return RecCard(
      onTap: () => _openDetail(j),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(j.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: kRecInk)),
                    const SizedBox(height: 2),
                    Text('${j.code} • ${j.department} • ${j.branch}',
                        style: const TextStyle(fontSize: 12.5, color: kRecMuted, fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              RecBadge(jobStatusLabel(j.status), colorKey: j.status),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'More actions',
                icon: const Icon(Icons.more_vert_rounded, color: kRecMuted, size: 20),
                onPressed: () => _showActions(j),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 14,
            runSpacing: 8,
            children: [
              _meta(Icons.business_center_outlined, j.employmentType),
              _meta(Icons.place_outlined, j.workplaceType),
              _meta(Icons.people_alt_outlined, '${j.positions} position${j.positions == 1 ? '' : 's'}'),
              _meta(Icons.timeline_outlined, j.experience),
              _meta(Icons.payments_outlined, j.salary),
              if (j.closeDate.isNotEmpty) _meta(Icons.event_outlined, 'Closes ${recFormatDate(j.closeDate)}'),
              if (j.isPublic) _meta(Icons.public_rounded, 'On job board'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _meta(IconData icon, String text) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: kRecMuted),
          const SizedBox(width: 4),
          Text(text, style: const TextStyle(fontSize: 12.5, color: kRecMuted, fontWeight: FontWeight.w500)),
        ],
      );
}
