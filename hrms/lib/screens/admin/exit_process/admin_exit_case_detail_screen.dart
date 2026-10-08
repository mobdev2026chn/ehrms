// One employee's exit: header with progress, and a tab per clearance section.
//   GET /admin/exit-process/cases/:id   - the exit (issues the feedback link on first open)
//   GET /admin/exit-process/settings    - termination reasons, approvers, feedback questions, notice rules
// Each tab saves on its own and hands back the exit the server returns, so section statuses and
// progress shown here are always the server's.

import 'package:flutter/material.dart';

import '../../../config/app_colors.dart';
import '../../../services/admin_exit_process_service.dart';
import '../salary/admin_salary_ui.dart';
import 'exit_case_tabs.dart';
import 'exit_case_tabs_more.dart';
import 'exit_process_common.dart';

class AdminExitCaseDetailScreen extends StatefulWidget {
  final String caseId;
  const AdminExitCaseDetailScreen({super.key, required this.caseId});

  @override
  State<AdminExitCaseDetailScreen> createState() => _AdminExitCaseDetailScreenState();
}

class _AdminExitCaseDetailScreenState extends State<AdminExitCaseDetailScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _case = {};
  Map<String, dynamic> _settings = {};

  static const _tabs = <(String id, String label, IconData icon)>[
    ('employment', 'Employment', Icons.work_outline_rounded),
    ('credentials', 'Credentials', Icons.key_rounded),
    ('assets', 'Asset Handover', Icons.laptop_mac_rounded),
    ('kt', 'KT Handover', Icons.school_outlined),
    ('sops', 'SOPs', Icons.description_outlined),
    ('documents', 'Documents', Icons.folder_copy_outlined),
    ('feedback', 'Feedback', Icons.chat_bubble_outline_rounded),
    ('review', 'Review', Icons.star_outline_rounded),
    ('fnf', 'Full & Final', Icons.account_balance_wallet_outlined),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final svc = AdminExitProcessService.instance;
    final results = await Future.wait([svc.getCase(widget.caseId), svc.getSettings()]);
    if (!mounted) return;
    final failed = results.firstWhere((r) => r['success'] != true, orElse: () => const {});
    setState(() {
      _loading = false;
      if (failed.isNotEmpty) {
        _error = failed['message']?.toString() ?? 'Could not load this exit.';
        return;
      }
      _case = Map<String, dynamic>.from(results[0]['data'] as Map);
      _settings = Map<String, dynamic>.from(results[1]['data'] as Map);
    });
  }

  void _onCaseUpdated(Map<String, dynamic> updated) {
    if (updated.isEmpty || !mounted) return;
    setState(() => _case = updated);
  }

  String _sectionStatus(String id) {
    final s = _case['sectionStatus'];
    return ExitUi.sectionLabel(s is Map ? s[id] : null);
  }

  @override
  Widget build(BuildContext context) {
    final staff = _case['staff'] is Map ? Map<String, dynamic>.from(_case['staff'] as Map) : <String, dynamic>{};
    final name = (staff['name'] ?? 'Exit details').toString();
    if (_loading || _error != null) {
      return Scaffold(
        backgroundColor: AdminUi.bg,
        appBar: AdminUi.appBar('Exit details'),
        body: _loading ? const AdminLoading() : AdminErrorView(message: _error!, onRetry: _load),
      );
    }
    return DefaultTabController(
      length: _tabs.length,
      child: Scaffold(
        backgroundColor: AdminUi.bg,
        appBar: AdminUi.appBar(name, actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded), tooltip: 'Refresh'),
        ]),
        body: NestedScrollView(
          headerSliverBuilder: (context, _) => [
            SliverToBoxAdapter(child: _header(staff)),
            SliverPersistentHeader(
              pinned: true,
              delegate: _TabBarDelegate(
                TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
                  tabs: _tabs.map((t) {
                    final status = _sectionStatus(t.$1);
                    return Tab(
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(t.$3, size: 16),
                        const SizedBox(width: 6),
                        Text(t.$2),
                        const SizedBox(width: 6),
                        Icon(
                          status == 'Completed'
                              ? Icons.check_circle_rounded
                              : status == 'In Progress'
                                  ? Icons.timelapse_rounded
                                  : Icons.radio_button_unchecked_rounded,
                          size: 14,
                          color: status == 'Completed'
                              ? AdminUi.green
                              : status == 'In Progress'
                                  ? AdminUi.blue
                                  : AdminUi.faint,
                        ),
                      ]),
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
          body: TabBarView(children: [
            ExitEmploymentTab(exitCase: _case, settings: _settings, sectionStatus: _sectionStatus('employment'), onCaseUpdated: _onCaseUpdated),
            ExitCredentialsTab(caseId: widget.caseId, sectionStatus: _sectionStatus('credentials'), onCaseUpdated: _onCaseUpdated),
            ExitAssetsTab(exitCase: _case, sectionStatus: _sectionStatus('assets'), onCaseUpdated: _onCaseUpdated),
            ExitKTTab(exitCase: _case, sectionStatus: _sectionStatus('kt'), onCaseUpdated: _onCaseUpdated),
            ExitSOPsTab(exitCase: _case, sectionStatus: _sectionStatus('sops'), onCaseUpdated: _onCaseUpdated),
            ExitDocumentsTab(exitCase: _case, sectionStatus: _sectionStatus('documents'), onCaseUpdated: _onCaseUpdated),
            ExitFeedbackTab(exitCase: _case, settings: _settings, sectionStatus: _sectionStatus('feedback')),
            ExitReviewTab(exitCase: _case, sectionStatus: _sectionStatus('review'), onCaseUpdated: _onCaseUpdated),
            ExitFullFinalTab(exitCase: _case, settings: _settings, sectionStatus: _sectionStatus('fnf'), onCaseUpdated: _onCaseUpdated),
          ]),
        ),
      ),
    );
  }

  Widget _header(Map<String, dynamic> staff) {
    final name = (staff['name'] ?? '').toString();
    final progress = ((_case['progress'] as num?) ?? 0).clamp(0, 100).toDouble();
    final status = ExitUi.statusLabel(_case['status']);
    final statuses = _tabs.map((t) => _sectionStatus(t.$1)).toList();
    final done = statuses.where((s) => s == 'Completed').length;
    final timeline = _case['timeline'] is Map ? Map<String, dynamic>.from(_case['timeline'] as Map) : <String, dynamic>{};
    final ext = _case['leaveExtension'] is Map ? Map<String, dynamic>.from(_case['leaveExtension'] as Map) : null;
    final lwd = (ext?['lastWorkingDay'] ?? timeline['lastWorkingDay'] ?? '').toString();

    // How far into the notice period the employee is, extended for leave when it applies.
    final noticeFrom = (timeline['noticeFrom'] ?? '').toString();
    final noticeTo = (ext?['noticeTo'] ?? timeline['noticeTo'] ?? '').toString();
    final span = noticeFrom.isNotEmpty && noticeTo.isNotEmpty ? ExitUi.daysBetween(noticeFrom, noticeTo) : null;
    final total = (span ?? (ext?['noticePeriodDays'] as num?)?.toInt() ?? (timeline['noticePeriodDays'] as num?)?.toInt() ?? 0)
        .clamp(0, 100000);
    final elapsed = noticeFrom.isNotEmpty ? (ExitUi.daysBetween(noticeFrom, AdminUi.ymd(DateTime.now())) ?? 0) : 0;
    final served = elapsed.clamp(0, total);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: AdminCard(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            AdminAvatar(name, size: 48),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17, color: AdminUi.ink)),
                const SizedBox(height: 2),
                Text(
                  [staff['employeeId'], staff['designation'], staff['department']]
                      .where((v) => v != null && v.toString().isNotEmpty)
                      .join(' • '),
                  style: const TextStyle(fontSize: 12.5, color: AdminUi.muted),
                ),
              ]),
            ),
          ]),
          const SizedBox(height: 12),
          Wrap(spacing: 6, runSpacing: 6, children: [
            ExitTypeBadge((_case['exitType'] ?? '').toString()),
            AdminPill(status),
            if (lwd.isNotEmpty) AdminPill('LWD ${AdminUi.date(lwd)}', fg: AdminUi.ink, bg: AdminUi.greyBg),
          ]),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: progress / 100,
                  minHeight: 8,
                  backgroundColor: AdminUi.greyBg,
                  color: progress >= 100 ? AdminUi.green : AppColors.primary,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text('${progress.round()}%',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AdminUi.ink)),
          ]),
          const SizedBox(height: 8),
          Text('$done of ${statuses.length} sections completed',
              style: const TextStyle(fontSize: 12.5, color: AdminUi.muted)),
          if (total > 0) ...[
            const SizedBox(height: 4),
            Text('Notice: $served of $total days served • ${total - served} remaining',
                style: const TextStyle(fontSize: 12.5, color: AdminUi.muted)),
          ],
        ]),
      ),
    );
  }
}

class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  _TabBarDelegate(this.tabBar);

  @override
  double get minExtent => tabBar.preferredSize.height;
  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) =>
      // The themed TabBar draws its own hairline divider, so no border here (it would eat into
      // the fixed header extent).
      Container(color: AppColors.surface, child: tabBar);

  @override
  bool shouldRebuild(covariant _TabBarDelegate oldDelegate) => true;
}
