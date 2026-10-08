// Exit Process: the pipeline of employees on their way out, and the company's exit settings.
//   GET    /admin/exit-process/cases             - the pipeline
//   GET    /admin/exit-process/cases/candidates  - who can be added
//   POST   /admin/exit-process/cases             - add staff { staffIds }
//   PATCH  /admin/exit-process/cases/:id/status  - in_progress | completed | cancelled
//   DELETE /admin/exit-process/cases/:id
// Tapping an exit opens AdminExitCaseDetailScreen. Company admin only (backend restrictTo admin).

import 'package:flutter/material.dart';

import '../../../config/app_colors.dart';
import '../../../services/admin_exit_process_service.dart';
import '../../../utils/snackbar_utils.dart';
import '../salary/admin_salary_ui.dart';
import 'admin_exit_case_detail_screen.dart';
import 'admin_exit_settings_tab.dart';
import 'exit_process_common.dart';

class AdminExitProcessScreen extends StatelessWidget {
  /// 0 = pipeline, 1 = settings.
  final int initialTab;
  const AdminExitProcessScreen({super.key, this.initialTab = 0});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      initialIndex: initialTab.clamp(0, 1),
      child: Scaffold(
        backgroundColor: AdminUi.bg,
        appBar: AdminUi.appBar(
          'Exit Process',
          bottom: const TabBar(
            tabs: [Tab(text: 'Exit Pipeline'), Tab(text: 'Settings')],
          ),
        ),
        body: const TabBarView(children: [_PipelineTab(), AdminExitSettingsTab()]),
      ),
    );
  }
}

class _PipelineTab extends StatefulWidget {
  const _PipelineTab();
  @override
  State<_PipelineTab> createState() => _PipelineTabState();
}

class _PipelineTabState extends State<_PipelineTab> with AutomaticKeepAliveClientMixin {
  final _search = TextEditingController();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _cases = [];
  String _status = 'All';
  final Set<String> _busy = {};

  static const _filters = ['All', 'In Progress', 'Completed', 'Cancelled'];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool showLoader = true}) async {
    if (showLoader) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    final r = await AdminExitProcessService.instance.getCases();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r['success'] == true) {
        _cases = List<Map<String, dynamic>>.from(r['data'] as List);
        _error = null;
      } else {
        _error = r['message']?.toString() ?? 'Could not load the exit pipeline.';
      }
    });
  }

  List<Map<String, dynamic>> get _filtered {
    final q = _search.text.trim().toLowerCase();
    return _cases.where((c) {
      final label = ExitUi.statusLabel(c['status']);
      if (_status != 'All' && label != _status) return false;
      if (q.isEmpty) return true;
      return [c['name'], c['employeeId'], c['designation'], c['department'], c['exitType']]
          .any((v) => (v ?? '').toString().toLowerCase().contains(q));
    }).toList();
  }

  Future<void> _setStatus(Map<String, dynamic> c, String status) async {
    String? reason;
    if (status == 'cancelled') {
      reason = await _askCancelReason();
      if (reason == null) return;
    } else {
      final ok = await adminConfirm(
        context,
        title: status == 'completed' ? 'Mark exit completed?' : 'Reopen exit?',
        message: status == 'completed'
            ? '${c['name']}’s exit will be marked completed (100%).'
            : '${c['name']}’s exit will be moved back to In Progress.',
        confirmLabel: status == 'completed' ? 'Mark completed' : 'Reopen',
      );
      if (!ok) return;
    }
    final id = c['id'].toString();
    setState(() => _busy.add(id));
    final r = await AdminExitProcessService.instance.updateStatus(id, status, cancelReason: reason);
    if (!mounted) return;
    setState(() {
      _busy.remove(id);
      if (r['success'] == true) {
        final updated = Map<String, dynamic>.from(r['data'] as Map);
        final i = _cases.indexWhere((x) => x['id'] == id);
        if (i >= 0 && updated.isNotEmpty) _cases[i] = updated;
      }
    });
    if (r['success'] == true) {
      SnackBarUtils.showSnackBar(context, 'Exit moved to ${ExitUi.statusLabel(status)}.');
    } else {
      SnackBarUtils.showSnackBar(context, r['message']?.toString() ?? 'Could not change the status.', isError: true);
    }
  }

  Future<String?> _askCancelReason() async {
    final ctrl = TextEditingController();
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel exit', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18, color: AdminUi.ink)),
        content: TextField(
          controller: ctrl,
          maxLines: 3,
          maxLength: 500,
          decoration: AdminUi.input('Reason (optional)', hint: 'e.g. Employee withdrew the resignation'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Back')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AdminUi.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('Cancel exit'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    return r;
  }

  Future<void> _delete(Map<String, dynamic> c) async {
    final ok = await adminConfirm(
      context,
      title: 'Remove from pipeline?',
      message: 'This deletes ${c['name']}’s exit record and everything recorded in it. This cannot be undone.',
      confirmLabel: 'Remove',
      destructive: true,
    );
    if (!ok || !mounted) return;
    final id = c['id'].toString();
    setState(() => _busy.add(id));
    final r = await AdminExitProcessService.instance.deleteCase(id);
    if (!mounted) return;
    setState(() {
      _busy.remove(id);
      if (r['success'] == true) _cases.removeWhere((x) => x['id'] == id);
    });
    if (r['success'] == true) {
      SnackBarUtils.showSnackBar(context, '${c['name']} removed from the exit pipeline.');
    } else {
      SnackBarUtils.showSnackBar(context, r['message']?.toString() ?? 'Could not remove the exit.', isError: true);
    }
  }

  Future<void> _addStaff() async {
    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      builder: (_) => const _AddToPipelineSheet(),
    );
    if (added == true && mounted) _load(showLoader: false);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final list = _filtered;
    final inProgress = _cases.where((c) => c['status'] == 'in_progress').length;
    final completed = _cases.where((c) => c['status'] == 'completed').length;
    return Scaffold(
      backgroundColor: AdminUi.bg,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        onPressed: _addStaff,
        icon: const Icon(Icons.person_add_alt_1_outlined),
        label: const Text('Add staff', style: TextStyle(fontWeight: FontWeight.w600)),
      ),
      body: _loading
          ? const AdminLoading()
          : _error != null
              ? AdminErrorView(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  color: AppColors.primary,
                  onRefresh: () => _load(showLoader: false),
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                    children: [
                      Row(children: [
                        Expanded(child: _miniStat('Total', '${_cases.length}', Icons.groups_outlined, null)),
                        const SizedBox(width: 8),
                        Expanded(child: _miniStat('In progress', '$inProgress', Icons.timelapse_rounded, AdminUi.blue)),
                        const SizedBox(width: 8),
                        Expanded(child: _miniStat('Completed', '$completed', Icons.task_alt_rounded, AdminUi.green)),
                      ]),
                      const SizedBox(height: 16),
                      AdminSearchField(controller: _search, hint: 'Search name, ID, department', onChanged: (_) => setState(() {})),
                      const SizedBox(height: 12),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: _filters
                              .map((f) => Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: ChoiceChip(
                                      label: Text(f,
                                          style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: _status == f ? FontWeight.w600 : FontWeight.w500,
                                              color: _status == f ? AppColors.onPrimary : AdminUi.muted)),
                                      selected: _status == f,
                                      showCheckmark: false,
                                      selectedColor: AppColors.primary,
                                      backgroundColor: AppColors.surface,
                                      side: BorderSide(color: _status == f ? AppColors.primary : const Color(0xFFE2E5EA)),
                                      onSelected: (_) => setState(() => _status = f),
                                    ),
                                  ))
                              .toList(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (list.isEmpty)
                        AdminEmptyView(
                          icon: Icons.logout_rounded,
                          title: _cases.isEmpty ? 'No one is in the exit pipeline' : 'No matching exits',
                          subtitle: _cases.isEmpty ? 'Use Add staff to start an employee’s exit process.' : null,
                        )
                      else
                        ...list.map(_card),
                    ],
                  ),
                ),
    );
  }

  Widget _card(Map<String, dynamic> c) {
    final id = c['id'].toString();
    final name = (c['name'] ?? '').toString();
    final status = (c['status'] ?? 'in_progress').toString();
    final progress = ((c['progress'] as num?) ?? 0).clamp(0, 100).toDouble();
    final busy = _busy.contains(id);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AdminCard(
        onTap: () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => AdminExitCaseDetailScreen(caseId: id)));
          if (mounted) _load(showLoader: false);
        },
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            AdminAvatar(name),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AdminUi.ink)),
                const SizedBox(height: 2),
                Text(
                  [c['employeeId'], c['designation'], c['department']]
                      .where((v) => v != null && v.toString().isNotEmpty)
                      .join(' • '),
                  style: const TextStyle(fontSize: 12.5, color: AdminUi.muted),
                  overflow: TextOverflow.ellipsis,
                ),
              ]),
            ),
            if (busy)
              const Padding(
                  padding: EdgeInsets.all(10),
                  child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
            else
              PopupMenuButton<String>(
                tooltip: 'Actions',
                icon: const Icon(Icons.more_vert_rounded, color: AdminUi.muted),
                onSelected: (v) {
                  if (v == 'delete') {
                    _delete(c);
                  } else {
                    _setStatus(c, v);
                  }
                },
                itemBuilder: (_) => [
                  if (status != 'completed') const PopupMenuItem(value: 'completed', child: Text('Mark completed')),
                  if (status != 'in_progress') const PopupMenuItem(value: 'in_progress', child: Text('Reopen (In Progress)')),
                  if (status != 'cancelled') const PopupMenuItem(value: 'cancelled', child: Text('Cancel exit')),
                  const PopupMenuItem(
                      value: 'delete', child: Text('Remove from pipeline', style: TextStyle(color: AdminUi.red))),
                ],
              ),
          ]),
          const SizedBox(height: 12),
          Wrap(spacing: 6, runSpacing: 6, children: [
            ExitTypeBadge((c['exitType'] ?? '').toString()),
            AdminPill(ExitUi.statusLabel(status)),
          ]),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AdminUi.bg, borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              Expanded(child: _date('Exit date', c['resignationDate'])),
              Expanded(child: _date('Last working day', c['lastWorkingDay'])),
            ]),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: progress / 100,
                  minHeight: 6,
                  backgroundColor: AdminUi.greyBg,
                  color: status == 'cancelled'
                      ? AdminUi.faint
                      : progress >= 100
                          ? AdminUi.green
                          : AppColors.primary,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text('${progress.round()}%',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5, color: AdminUi.ink)),
          ]),
          if ((c['reason'] ?? '').toString().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(c['reason'].toString(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5, color: AdminUi.muted, height: 1.4)),
          ],
        ]),
      ),
    );
  }

  Widget _date(String label, dynamic v) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 12, color: AdminUi.muted)),
        const SizedBox(height: 2),
        Text(AdminUi.date(v), style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AdminUi.ink)),
      ]);

  /// Compact KPI tile for the three pipeline counts (three across fits a 360px phone).
  Widget _miniStat(String label, String value, IconData icon, Color? color) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AdminUi.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          AdminIconTile(icon, color: color, size: 32),
          const SizedBox(height: 10),
          Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AdminUi.ink)),
          const SizedBox(height: 2),
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AdminUi.muted)),
        ]),
      );
}

class _AddToPipelineSheet extends StatefulWidget {
  const _AddToPipelineSheet();
  @override
  State<_AddToPipelineSheet> createState() => _AddToPipelineSheetState();
}

class _AddToPipelineSheetState extends State<_AddToPipelineSheet> {
  final _search = TextEditingController();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _candidates = [];
  final Set<String> _selected = {};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final r = await AdminExitProcessService.instance.getCandidates();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r['success'] == true) {
        _candidates = List<Map<String, dynamic>>.from(r['data'] as List);
      } else {
        _error = r['message']?.toString() ?? 'Could not load staff.';
      }
    });
  }

  Future<void> _add() async {
    if (_selected.isEmpty) return;
    setState(() => _saving = true);
    final r = await AdminExitProcessService.instance.addCases(_selected.toList());
    if (!mounted) return;
    setState(() => _saving = false);
    if (r['success'] == true) {
      final n = (r['data'] as List).length;
      SnackBarUtils.showSnackBar(context, '$n staff added to the exit pipeline.');
      Navigator.pop(context, true);
    } else {
      SnackBarUtils.showSnackBar(context, r['message']?.toString() ?? 'Could not add staff.', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _search.text.trim().toLowerCase();
    final list = _candidates
        .where((c) =>
            q.isEmpty ||
            [c['name'], c['employeeId'], c['department'], c['designation']]
                .any((v) => (v ?? '').toString().toLowerCase().contains(q)))
        .toList();
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (ctx, controller) => Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 8, 12),
          child: Row(children: [
            const Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Add to exit pipeline', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18, color: AdminUi.ink)),
                SizedBox(height: 4),
                Text('Select the employees who are leaving.', style: TextStyle(fontSize: 13, color: AdminUi.muted)),
              ]),
            ),
            IconButton(
                tooltip: 'Close', onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: AdminSearchField(controller: _search, hint: 'Search staff', onChanged: (_) => setState(() {})),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _loading
              ? const AdminLoading()
              : _error != null
                  ? AdminErrorView(message: _error!, onRetry: _load)
                  : list.isEmpty
                      ? const AdminEmptyView(icon: Icons.people_outline_rounded, title: 'No staff to add')
                      : ListView.builder(
                          controller: controller,
                          itemCount: list.length,
                          itemBuilder: (_, i) {
                            final c = list[i];
                            final id = c['staffId'].toString();
                            final inPipeline = c['inPipeline'] == true;
                            return CheckboxListTile(
                              value: inPipeline || _selected.contains(id),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                              onChanged: inPipeline
                                  ? null
                                  : (v) => setState(() => v == true ? _selected.add(id) : _selected.remove(id)),
                              title: Text((c['name'] ?? '').toString(),
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AdminUi.ink)),
                              subtitle: Text(
                                inPipeline
                                    ? 'Already in the exit pipeline'
                                    : [c['employeeId'], c['designation'], c['department']]
                                        .where((v) => v != null && v.toString().isNotEmpty)
                                        .join(' • '),
                                style: const TextStyle(fontSize: 12.5, color: AdminUi.muted),
                              ),
                            );
                          },
                        ),
        ),
        Container(
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: AdminUi.border))),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  onPressed: _saving || _selected.isEmpty ? null : _add,
                  child: _saving
                      ? SizedBox(
                          width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onPrimary))
                      : Text(_selected.isEmpty ? 'Select staff' : 'Add ${_selected.length} to pipeline'),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
