// lib/screens/admin/recruitment/admin_job_detail_screen.dart
// View one job opening, with edit / status / delete. Pops `true` when something changed.

import 'package:flutter/material.dart';

import '../../../config/app_colors.dart';
import '../../../models/admin_recruitment_models.dart';
import '../../../services/admin_recruitment_service.dart';
import 'admin_add_job_screen.dart';
import 'admin_job_openings_screen.dart' show changeJobStatus, deleteJob, jobStatusLabel;
import 'rec_widgets.dart';

class AdminJobDetailScreen extends StatefulWidget {
  final String jobId;
  const AdminJobDetailScreen({super.key, required this.jobId});

  @override
  State<AdminJobDetailScreen> createState() => _AdminJobDetailScreenState();
}

class _AdminJobDetailScreenState extends State<AdminJobDetailScreen> {
  final AdminRecruitmentService _service = AdminRecruitmentService();
  RecJobOpening? _job;
  bool _loading = true;
  String? _error;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final j = await _service.getJobOpening(widget.jobId);
      if (!mounted) return;
      setState(() {
        _job = j;
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

  Future<void> _edit() async {
    final saved = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => AdminAddJobScreen(job: _job)));
    if (saved == true) {
      _changed = true;
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final j = _job;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _changed);
      },
      child: Scaffold(
        backgroundColor: kRecBg,
        appBar: recAppBar(context, 'Job Opening', onRefresh: _load, actions: [
          if (j != null)
            IconButton(icon: const Icon(Icons.edit_outlined, size: 22), onPressed: _edit, tooltip: 'Edit'),
        ]),
        body: RecAsyncBody(
          loading: _loading,
          error: _error,
          isEmpty: j == null,
          emptyText: 'Job opening not found',
          onRetry: _load,
          builder: () => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              RecCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const RecIconTile(Icons.work_outline_rounded, size: 44),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(j!.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: kRecInk)),
                          const SizedBox(height: 2),
                          Text(j.code, style: const TextStyle(fontSize: 12.5, color: kRecMuted, fontWeight: FontWeight.w500)),
                        ]),
                      ),
                      const SizedBox(width: 8),
                      RecBadge(jobStatusLabel(j.status), colorKey: j.status),
                    ]),
                    const SizedBox(height: 16),
                    Row(children: [
                      Expanded(
                        child: RecPrimaryButton(
                          label: 'Change status',
                          icon: Icons.flag_outlined,
                          outlined: true,
                          onPressed: () async {
                            if (await changeJobStatus(context, j)) {
                              _changed = true;
                              _load();
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: RecPrimaryButton(
                          label: 'Delete',
                          icon: Icons.delete_outline_rounded,
                          outlined: true,
                          destructive: true,
                          onPressed: () async {
                            if (await deleteJob(context, j) && context.mounted) Navigator.pop(context, true);
                          },
                        ),
                      ),
                    ]),
                  ],
                ),
              ),
              RecCard(
                child: Column(children: [
                  const RecSectionTitle('Overview'),
                  RecInfoRow('Department', j.department),
                  RecInfoRow('Branch', j.branch),
                  RecInfoRow('Workplace', j.workplaceType),
                  RecInfoRow('Employment', j.employmentType),
                  RecInfoRow('Positions', '${j.positions}'),
                  RecInfoRow('Experience', j.experience),
                  RecInfoRow('Education', j.education),
                  RecInfoRow('Salary', j.salary),
                  RecInfoRow('Salary type', j.salaryType),
                  RecInfoRow('Opened', recFormatDate(j.openDate)),
                  RecInfoRow('Closes', recFormatDate(j.closeDate)),
                  RecInfoRow('Job board', j.isPublic ? 'Shown' : 'Hidden'),
                ]),
              ),
              if (j.skills.isNotEmpty)
                RecCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const RecSectionTitle('Skills'),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: j.skills
                            .map((s) => Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(color: AppColors.brandLight, borderRadius: BorderRadius.circular(999)),
                                  child: Text(s,
                                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.brandDark)),
                                ))
                            .toList(),
                      ),
                    ],
                  ),
                ),
              _text('Description', j.description),
              _text('Key responsibilities', j.responsibilities),
              if (j.requirements.isNotEmpty) _text('Requirements', j.requirements),
              _text('Benefits', j.benefits),
            ],
          ),
        ),
      ),
    );
  }

  Widget _text(String title, String body) => RecCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RecSectionTitle(title),
            Text(body.isEmpty ? '-' : body, style: const TextStyle(fontSize: 14, height: 1.5, color: kRecInk)),
          ],
        ),
      );
}
