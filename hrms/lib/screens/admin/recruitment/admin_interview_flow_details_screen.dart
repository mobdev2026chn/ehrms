// lib/screens/admin/recruitment/admin_interview_flow_details_screen.dart
// One interview flow: rounds (add / edit / delete / reorder) and each round's questions (CRUD).

import 'package:flutter/material.dart';

import '../../../config/app_colors.dart';
import '../../../models/admin_recruitment_models.dart';
import '../../../services/admin_recruitment_service.dart';
import 'rec_question_editor.dart';
import 'rec_widgets.dart';

class AdminInterviewFlowDetailsScreen extends StatefulWidget {
  final String flowId;
  const AdminInterviewFlowDetailsScreen({super.key, required this.flowId});

  @override
  State<AdminInterviewFlowDetailsScreen> createState() => _AdminInterviewFlowDetailsScreenState();
}

class _AdminInterviewFlowDetailsScreenState extends State<AdminInterviewFlowDetailsScreen> {
  final AdminRecruitmentService _service = AdminRecruitmentService();

  RecInterviewFlow? _flow;
  List<RecStaffOption> _staff = [];
  bool _loading = true;
  String? _error;
  bool _busy = false;
  final Set<String> _expanded = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool showLoader = true}) async {
    if (showLoader) setState(() => _loading = true);
    try {
      final flow = await _service.getInterviewFlow(widget.flowId);
      if (!mounted) return;
      setState(() {
        _flow = flow;
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

  Future<List<RecStaffOption>> _ensureStaff() async {
    if (_staff.isNotEmpty) return _staff;
    _staff = await _service.getStaffOptions();
    return _staff;
  }

  /// Runs a flow mutation; the response is the updated flow.
  Future<void> _mutate(Future<RecInterviewFlow> Function() op, String success) async {
    setState(() => _busy = true);
    try {
      final flow = await op();
      if (!mounted) return;
      setState(() => _flow = flow);
      recShowSuccess(context, success);
    } catch (e) {
      if (mounted) recShowError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _roundForm([RecFlowRound? round]) async {
    List<RecStaffOption> staff;
    try {
      staff = await _ensureStaff();
    } catch (e) {
      if (mounted) recShowError(context, e);
      return;
    }
    if (!mounted) return;
    final name = TextEditingController(text: round?.name ?? '');
    final otherName = TextEditingController(
        text: round != null && round.interviewerId.isEmpty ? round.interviewer : '');
    String? evaluator = round == null ? null : (round.interviewerId.isNotEmpty ? round.interviewerId : '__other');
    String duration = round?.duration ?? '45 mins';
    final key = GlobalKey<FormState>();

    final result = await recShowSheet<Map<String, String?>>(
      context,
      title: round == null ? 'Add round' : 'Edit round',
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Form(
          key: key,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              RecTextField(controller: name, label: 'Round name * (e.g. Technical)', validator: recRequired),
              RecDropdown<String>(
                label: 'Evaluator *',
                value: evaluator,
                items: [
                  ...staff.map((s) => s.id),
                  if (round != null && round.interviewerId.isNotEmpty && !staff.any((s) => s.id == round.interviewerId))
                    round.interviewerId,
                  '__other',
                ],
                labelOf: (id) {
                  if (id == '__other') return 'Someone else (type a name)';
                  final s = staff.where((x) => x.id == id).firstOrNull;
                  return s?.label ?? round?.interviewer ?? 'Evaluator';
                },
                validator: (v) => v == null ? 'Required' : null,
                onChanged: (v) => setS(() => evaluator = v),
              ),
              if (evaluator == '__other') RecTextField(controller: otherName, label: 'Evaluator name *', validator: recRequired),
              RecDropdown<String>(
                label: 'Duration',
                value: duration,
                items: kRoundDurations,
                labelOf: (s) => s,
                onChanged: (v) => setS(() => duration = v ?? duration),
              ),
              const SizedBox(height: 4),
              RecPrimaryButton(
                label: 'Save',
                icon: Icons.check_rounded,
                onPressed: () {
                  if (!(key.currentState?.validate() ?? false)) return;
                  Navigator.pop(ctx, {
                    'name': name.text.trim(),
                    'interviewerId': evaluator == '__other' ? null : evaluator,
                    'interviewerName': evaluator == '__other' ? otherName.text.trim() : null,
                    'duration': duration,
                  });
                },
              ),
            ],
          ),
        ),
      ),
    );


    if (result == null) return;
    final flow = _flow!;
    if (round == null) {
      await _mutate(
          () => _service.addFlowRound(flow.id,
              name: result['name']!,
              interviewerId: result['interviewerId'],
              interviewerName: result['interviewerName'],
              duration: result['duration']!),
          'Round added');
    } else {
      await _mutate(
          () => _service.updateFlowRound(flow.id, round.id,
              name: result['name'],
              interviewerId: result['interviewerId'],
              interviewerName: result['interviewerName'],
              duration: result['duration']),
          'Round updated');
    }
  }

  Future<void> _deleteRound(RecFlowRound r) async {
    final ok = await recConfirm(context,
        title: 'Delete round?',
        message: 'Round ${r.roundNumber}: ${r.name} and its ${r.questions.length} question(s) will be removed from this flow.',
        confirmLabel: 'Delete',
        destructive: true);
    if (ok) await _mutate(() => _service.deleteFlowRound(_flow!.id, r.id), 'Round deleted');
  }

  Future<void> _reorder(int oldIndex, int newIndex) async {
    final rounds = [..._flow!.rounds];

    final moved = rounds.removeAt(oldIndex);
    rounds.insert(newIndex, moved);
    await _mutate(() => _service.reorderFlowRounds(_flow!.id, rounds.map((r) => r.id).toList()), 'Rounds reordered');
  }

  Future<void> _questionForm(RecFlowRound round, [RecQuestion? q]) async {
    final input = await showQuestionEditor(context, initial: q);
    if (input == null) return;
    final flow = _flow!;
    if (q == null) {
      await _mutate(() => _service.addFlowQuestion(flow.id, round.id, input), 'Question added');
    } else {
      await _mutate(() => _service.updateFlowQuestion(flow.id, round.id, q.id, input), 'Question updated');
    }
  }

  Future<void> _deleteQuestion(RecFlowRound round, RecQuestion q) async {
    final ok = await recConfirm(context,
        title: 'Delete question?', message: q.text, confirmLabel: 'Delete', destructive: true);
    if (ok) await _mutate(() => _service.deleteFlowQuestion(_flow!.id, round.id, q.id), 'Question deleted');
  }

  @override
  Widget build(BuildContext context) {
    final f = _flow;
    return Scaffold(
      backgroundColor: kRecBg,
      appBar: recAppBar(context, f?.jobTitle ?? 'Interview Flow', onRefresh: () => _load()),
      floatingActionButton: f == null
          ? null
          : FloatingActionButton.extended(
              onPressed: _busy ? null : () => _roundForm(),
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.onPrimary,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add Round', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
      body: RecAsyncBody(
        loading: _loading,
        error: _error,
        isEmpty: f == null,
        emptyText: 'Interview flow not found',
        onRetry: _load,
        builder: () => Column(
          children: [
            if (_busy) const LinearProgressIndicator(minHeight: 2),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: RecCard(
                margin: EdgeInsets.zero,
                child: Row(children: [
                  const RecIconTile(Icons.account_tree_outlined, size: 44),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(f!.jobTitle, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: kRecInk)),
                        const SizedBox(height: 2),
                        Text('${f.jobCode} • ${f.department} • ${f.rounds.length} round(s)',
                            style: const TextStyle(fontSize: 12.5, color: kRecMuted, fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (f.jobStatus.isNotEmpty) RecBadge(f.jobStatus),
                ]),
              ),
            ),
            if (f.rounds.length > 1)
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 10, 16, 0),
                child: Row(children: [
                  Icon(Icons.drag_indicator_rounded, size: 16, color: kRecMuted),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text('Long-press and drag a round to change the order.',
                        style: TextStyle(fontSize: 12.5, color: kRecMuted)),
                  ),
                ]),
              ),
            Expanded(
              child: f.rounds.isEmpty
                  ? const RecEmptyState(text: 'No rounds yet. Add the first round.', icon: Icons.layers_outlined)
                  : ReorderableListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
                      itemCount: f.rounds.length,
                      onReorderItem: _busy ? (_, __) {} : _reorder,
                      itemBuilder: (ctx, i) => _roundCard(f.rounds[i], key: ValueKey(f.rounds[i].id)),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _roundCard(RecFlowRound r, {required Key key}) {
    final open = _expanded.contains(r.id);
    return Container(
      key: key,
      child: RecCard(
        onTap: () => setState(() => open ? _expanded.remove(r.id) : _expanded.add(r.id)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: AppColors.brandLight, borderRadius: BorderRadius.circular(12)),
                child: Text('${r.roundNumber}',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.brandDark)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: kRecInk)),
                    const SizedBox(height: 2),
                    Text('${r.interviewer} • ${r.duration} • ${r.questions.length} question(s)',
                        style: const TextStyle(fontSize: 12.5, color: kRecMuted)),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Round actions',
                icon: const Icon(Icons.more_vert_rounded, size: 20, color: kRecMuted),
                onSelected: (v) {
                  if (v == 'edit') _roundForm(r);
                  if (v == 'delete') _deleteRound(r);
                  if (v == 'question') _questionForm(r);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Edit round')),
                  PopupMenuItem(value: 'question', child: Text('Add question')),
                  PopupMenuItem(value: 'delete', child: Text('Delete round', style: TextStyle(color: AppColors.error))),
                ],
              ),
              Icon(open ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: kRecMuted),
            ]),
            if (open) ...[
              const Divider(height: 24),
              if (r.questions.isEmpty)
                const Text('No questions yet.', style: TextStyle(fontSize: 12.5, color: kRecMuted)),
              ...List.generate(r.questions.length, (i) {
                final q = r.questions[i];
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text('${i + 1}. ${q.text}', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: kRecInk)),
                  subtitle: Text(
                    '${answerTypeLabel(q.answerType)} • ${q.maxScore} marks'
                    '${q.answerType == 'multichoice' ? '\n${q.options.join(' / ')}' : ''}'
                    '${q.answerType == 'scenario' && q.options.isNotEmpty ? '\nExpected: ${q.options.first}' : ''}',
                    style: const TextStyle(fontSize: 12, color: kRecMuted),
                  ),
                  onTap: () => _questionForm(r, q),
                  trailing: IconButton(
                    tooltip: 'Delete question',
                    icon: const Icon(Icons.delete_outline_rounded, size: 20, color: AppColors.error),
                    onPressed: () => _deleteQuestion(r, q),
                  ),
                );
              }),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => _questionForm(r),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Add question'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
