// lib/screens/admin/recruitment/admin_schedule_interview_sheet.dart
// Schedule an interview round for a candidate (POST /interview-rounds) or re-schedule a round
// still waiting for its interview (PUT /interview-rounds/:id/schedule).

import 'package:flutter/material.dart';

import '../../../config/app_colors.dart';
import '../../../models/admin_recruitment_models.dart';
import '../../../services/admin_recruitment_service.dart';
import 'rec_question_editor.dart';
import 'rec_widgets.dart';

/// Returns true when a round was scheduled.
Future<bool> showScheduleInterviewSheet(BuildContext context, {required RecCandidate candidate}) async {
  final r = await recShowSheet<bool>(
    context,
    title: 'Schedule interview - ${candidate.fullName}',
    builder: (_) => _ScheduleForm(candidate: candidate),
  );
  return r == true;
}

/// Returns true when the round was re-scheduled.
Future<bool> showRescheduleInterviewSheet(BuildContext context, {required RecInterviewRound round}) async {
  final r = await recShowSheet<bool>(
    context,
    title: 'Re-schedule Round ${round.roundNumber}: ${round.roundName}',
    builder: (_) => _ScheduleForm(reschedule: round),
  );
  return r == true;
}

class _ScheduleForm extends StatefulWidget {
  final RecCandidate? candidate;
  final RecInterviewRound? reschedule;
  const _ScheduleForm({this.candidate, this.reschedule});

  @override
  State<_ScheduleForm> createState() => _ScheduleFormState();
}

class _ScheduleFormState extends State<_ScheduleForm> {
  final AdminRecruitmentService _service = AdminRecruitmentService();

  bool _loading = true;
  String? _error;
  bool _saving = false;

  List<RecInterviewFlow> _flows = [];
  List<RecStaffOption> _staff = [];
  List<RecInterviewRound> _candidateRounds = [];

  String? _flowId;
  String? _roundId;
  // Staff id, or 'name:<free text>' for an evaluator who is not a staff member
  String? _evaluator;
  String _date = '';
  String _time = '10:00';
  String _mode = 'Virtual';
  List<Map<String, dynamic>> _questions = [];

  bool get _isReschedule => widget.reschedule != null;

  @override
  void initState() {
    super.initState();
    final r = widget.reschedule;
    if (r != null) {
      _date = r.interviewDate;
      _time = r.interviewTime.isEmpty ? '10:00' : r.interviewTime;
      _mode = kInterviewModes.contains(r.mode) ? r.mode : 'Virtual';
      _evaluator = r.interviewerId.isNotEmpty ? r.interviewerId : 'name:${r.interviewerName}';
    } else {
      _date = recDateKeyOf(DateTime.now().add(const Duration(days: 1)));
    }
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final staffF = _service.getStaffOptions();
      if (_isReschedule) {
        final staff = await staffF;
        if (!mounted) return;
        setState(() {
          _staff = staff;
          _loading = false;
        });
        return;
      }
      final flowsF = _service.getInterviewFlows();
      final roundsF = _service.getInterviewRounds(candidateId: widget.candidate!.id);
      final flows = await flowsF;
      final staff = await staffF;
      final rounds = await roundsF;
      if (!mounted) return;
      setState(() {
        _flows = flows;
        _staff = staff;
        _candidateRounds = rounds;
        _loading = false;
      });
      _pickDefaults();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _pickDefaults() {
    final c = widget.candidate!;
    final pos = c.displayJob.toLowerCase();
    RecInterviewFlow? flow;
    for (final f in _flows) {
      if (c.jobOpeningId.isNotEmpty && f.jobOpeningId == c.jobOpeningId) {
        flow = f;
        break;
      }
    }
    flow ??= _flows.where((f) => pos.isNotEmpty && (pos.contains(f.jobTitle.toLowerCase()) || f.jobTitle.toLowerCase().contains(pos))).firstOrNull;
    flow ??= _flows.firstOrNull;
    if (flow == null) return;
    final had = _candidateRounds.map((r) => r.flowRoundId).toSet();
    var lastIdx = -1;
    for (var i = 0; i < flow.rounds.length; i++) {
      if (had.contains(flow.rounds[i].id)) lastIdx = i;
    }
    final next = lastIdx + 1 < flow.rounds.length
        ? flow.rounds[lastIdx + 1]
        : (flow.rounds.where((r) => !had.contains(r.id)).firstOrNull ?? flow.rounds.firstOrNull);
    setState(() => _flowId = flow!.id);
    _selectRound(next?.id);
  }

  RecInterviewFlow? get _flow => _flows.where((f) => f.id == _flowId).firstOrNull;

  void _selectRound(String? roundId) {
    final round = _flow?.rounds.where((r) => r.id == roundId).firstOrNull;
    setState(() {
      _roundId = round?.id;
      _evaluator = round == null
          ? null
          : (round.interviewerId.isNotEmpty ? round.interviewerId : (round.interviewer.isEmpty ? null : 'name:${round.interviewer}'));
      _questions = round?.questions.map((q) => q.toInput()).toList() ?? [];
    });
  }

  List<String> get _evaluatorItems {
    final items = _staff.map((s) => s.id).toList();
    if (_evaluator != null && _evaluator!.startsWith('name:')) items.insert(0, _evaluator!);
    if (_evaluator != null && !_evaluator!.startsWith('name:') && !items.contains(_evaluator)) items.insert(0, _evaluator!);
    return items;
  }

  String _evaluatorLabel(String v) {
    if (v.startsWith('name:')) return v.substring(5);
    final s = _staff.where((x) => x.id == v).firstOrNull;
    if (s != null) return s.label;
    if (_isReschedule && v == widget.reschedule!.interviewerId) return widget.reschedule!.interviewerName;
    final round = _flow?.rounds.where((r) => r.id == _roundId).firstOrNull;
    return round?.interviewer ?? 'Evaluator';
  }

  Future<void> _submit() async {
    if (_evaluator == null || _evaluator!.isEmpty) {
      recShowError(context, 'Please choose an evaluator.');
      return;
    }
    if (_date.isEmpty || _time.isEmpty) {
      recShowError(context, 'Please choose the interview date and time.');
      return;
    }
    final isName = _evaluator!.startsWith('name:');
    final interviewerId = isName ? null : _evaluator;
    final interviewerName = isName ? _evaluator!.substring(5) : _evaluatorLabel(_evaluator!);
    setState(() => _saving = true);
    try {
      String msg;
      if (_isReschedule) {
        msg = await _service.rescheduleInterviewRound(
          widget.reschedule!.id,
          interviewerId: interviewerId,
          interviewerName: interviewerName,
          interviewDate: _date,
          interviewTime: _time,
          mode: _mode,
        );
      } else {
        if (_flowId == null || _roundId == null) {
          recShowError(context, 'Please choose the interview flow and round.');
          setState(() => _saving = false);
          return;
        }
        msg = await _service.scheduleInterviewRound(
          candidateId: widget.candidate!.id,
          flowId: _flowId!,
          flowRoundId: _roundId!,
          interviewerId: interviewerId,
          interviewerName: interviewerName,
          interviewDate: _date,
          interviewTime: _time,
          mode: _mode,
          questions: _questions,
        );
      }
      if (!mounted) return;
      recShowSuccess(context, msg);
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) recShowError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()));
    if (_error != null) return SizedBox(height: 260, child: RecErrorState(message: _error!, onRetry: _load));
    if (!_isReschedule && _flows.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Text('No interview flows yet. Create an interview flow for the job opening first (Interview Flow).',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: kRecMuted)),
      );
    }

    final pending = _candidateRounds.where((r) => r.status == 'Scheduled').toList();
    final flow = _flow;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!_isReschedule && pending.isNotEmpty)
          RecNotice(
            'Round ${pending.first.roundNumber}: ${pending.first.roundName} is still waiting for evaluation '
            '(${recFormatDate(pending.first.interviewDate)}).',
            icon: Icons.pending_actions_rounded,
          ),
        if (!_isReschedule) ...[
          RecDropdown<String>(
            label: 'Interview flow',
            value: _flowId,
            items: _flows.map((f) => f.id).toList(),
            labelOf: (id) {
              final f = _flows.firstWhere((x) => x.id == id);
              return '${f.jobTitle}${f.jobCode.isEmpty ? '' : ' (${f.jobCode})'}';
            },
            onChanged: (v) {
              setState(() => _flowId = v);
              _selectRound(_flow?.rounds.firstOrNull?.id);
            },
          ),
          if (flow != null && flow.rounds.isEmpty)
            const RecNotice('This flow has no rounds yet. Add rounds in Interview Flow.',
                color: AppColors.error, background: AppColors.errorBg, icon: Icons.error_outline_rounded)
          else if (flow != null)
            RecDropdown<String>(
              label: 'Round',
              value: _roundId,
              items: flow.rounds.map((r) => r.id).toList(),
              labelOf: (id) {
                final r = flow.rounds.firstWhere((x) => x.id == id);
                final had = _candidateRounds.where((x) => x.flowRoundId == id).firstOrNull;
                return 'Round ${r.roundNumber}: ${r.name} (${r.duration})${had != null ? ' - ${had.displayStatus}' : ''}';
              },
              onChanged: _selectRound,
            ),
        ],
        RecDropdown<String>(
          label: 'Evaluator',
          value: _evaluator,
          items: _evaluatorItems,
          labelOf: _evaluatorLabel,
          onChanged: (v) => setState(() => _evaluator = v),
        ),
        Row(children: [
          Expanded(
            child: RecPickerField(
              label: 'Date',
              value: _date.isEmpty ? '' : recFormatDate(_date),
              onTap: () async {
                final d = await recPickDate(context,
                    initial: _date, firstDate: DateTime.now().subtract(const Duration(days: 1)));
                if (d != null) setState(() => _date = d);
              },
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: RecPickerField(
              label: 'Time',
              value: _time.isEmpty ? '' : recFormatTime(_time),
              icon: Icons.schedule_rounded,
              onTap: () async {
                final t = await recPickTime(context, initial: _time);
                if (t != null) setState(() => _time = t);
              },
            ),
          ),
        ]),
        RecDropdown<String>(
          label: 'Mode',
          value: _mode,
          items: kInterviewModes,
          labelOf: (s) => s,
          onChanged: (v) => setState(() => _mode = v ?? _mode),
        ),
        if (!_isReschedule && _roundId != null) ...[
          RecSectionTitle('Questions (${_questions.length})',
              trailing: TextButton.icon(
                onPressed: () async {
                  final q = await showQuestionEditor(context);
                  if (q != null) setState(() => _questions.add(q));
                },
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add'),
              )),
          if (_questions.isEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('No questions for this round.', style: TextStyle(fontSize: 12.5, color: kRecMuted)),
            ),
          ...List.generate(_questions.length, (i) {
            final q = _questions[i];
            return ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text('${i + 1}. ${q['text']}', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: kRecInk)),
              subtitle: Text('${answerTypeLabel(q['answerType'].toString())} • ${q['maxScore']} marks',
                  style: const TextStyle(fontSize: 12, color: kRecMuted)),
              onTap: () async {
                final edited = await showQuestionEditor(context, initial: RecQuestion.fromJson(q));
                if (edited != null) setState(() => _questions[i] = edited);
              },
              trailing: IconButton(
                tooltip: 'Remove question',
                icon: const Icon(Icons.close_rounded, size: 20, color: AppColors.error),
                onPressed: () => setState(() => _questions.removeAt(i)),
              ),
            );
          }),
          const SizedBox(height: 4),
          const Text('Changes here apply to this candidate only - the interview flow is not changed.',
              style: TextStyle(fontSize: 12.5, color: kRecMuted)),
          const SizedBox(height: 16),
        ],
        SizedBox(
          height: 52,
          child: RecPrimaryButton(
            label: _isReschedule ? 'Re-schedule' : 'Schedule interview',
            icon: Icons.event_available_rounded,
            busy: _saving,
            onPressed: _submit,
          ),
        ),
      ],
    );
  }
}
