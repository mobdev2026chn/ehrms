// lib/screens/admin/recruitment/admin_candidate_scorecard_screen.dart
// One interview round: schedule details, round questions (add/edit while scheduled) and the
// evaluation scorecard (PUT /interview-rounds/:id/evaluation). Choosing a decision saves it.

import 'package:flutter/material.dart';

import '../../../config/app_colors.dart';
import '../../../models/admin_recruitment_models.dart';
import '../../../services/admin_recruitment_service.dart';
import 'admin_schedule_interview_sheet.dart';
import 'rec_question_editor.dart';
import 'rec_widgets.dart';

class AdminCandidateScorecardScreen extends StatefulWidget {
  final String roundId;
  const AdminCandidateScorecardScreen({super.key, required this.roundId});

  @override
  State<AdminCandidateScorecardScreen> createState() => _AdminCandidateScorecardScreenState();
}

class _AdminCandidateScorecardScreenState extends State<AdminCandidateScorecardScreen> {
  final AdminRecruitmentService _service = AdminRecruitmentService();

  RecInterviewRound? _round;
  List<RecInterviewRound> _candidateRounds = [];
  RecInterviewFlow? _flow;
  bool _loading = true;
  String? _error;

  // Scorecard state, keyed by question index
  Map<int, num> _scores = {};
  Map<int, TextEditingController> _notes = {};
  Map<int, TextEditingController> _marks = {};
  final TextEditingController _feedback = TextEditingController();
  double _overall = 50;
  bool _forceEdit = false;
  String? _saving;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _feedback.dispose();
    for (final c in [..._notes.values, ..._marks.values]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load({bool showLoader = true}) async {
    if (showLoader) setState(() => _loading = true);
    try {
      final round = await _service.getInterviewRound(widget.roundId);
      final others = await _service.getInterviewRounds(candidateId: round.candidateId);
      RecInterviewFlow? flow;
      if (round.flowId.isNotEmpty) {
        try {
          flow = await _service.getInterviewFlow(round.flowId);
        } on RecruitmentApiException {
          flow = null; // flow deleted - the round still stands on its own
        }
      }
      if (!mounted) return;
      setState(() {
        _round = round;
        _candidateRounds = others;
        _flow = flow;
        _error = null;
        _loading = false;
        _forceEdit = false;
      });
      _fillForm(round);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _fillForm(RecInterviewRound r) {
    for (final c in [..._notes.values, ..._marks.values]) {
      c.dispose();
    }
    final ev = r.evaluation;
    num? n(dynamic v) => v is num ? v : num.tryParse('${v ?? ''}');
    _scores = {};
    _notes = {};
    _marks = {};
    for (var i = 0; i < r.questions.length; i++) {
      final s = n(ev?.scores['$i']);
      if (s != null) _scores[i] = s;
      _notes[i] = TextEditingController(text: (ev?.questionNotes['$i'] ?? '').toString());
      final m = n(ev?.questionScores['$i']);
      _marks[i] = TextEditingController(text: m == null ? '' : '$m');
    }
    _feedback.text = ev?.generalFeedback ?? '';
    _overall = (ev?.overallScore ?? 50).toDouble().clamp(0, 100);
    setState(() {});
  }

  bool get _isPortfolio => (_round?.roundName.toLowerCase() ?? '').contains('portfolio');

  bool get _isFinalRound {
    final r = _round;
    final rounds = _flow?.rounds ?? [];
    if (r == null || rounds.isEmpty) return false;
    return rounds.last.id == r.flowRoundId || rounds.every((fr) => _candidateRounds.any((x) => x.flowRoundId == fr.id));
  }

  RecInterviewRound? get _pendingNext =>
      _candidateRounds.where((x) => x.status == 'Scheduled' && x.id != _round?.id).firstOrNull;

  bool _validate() {
    final r = _round!;
    for (var i = 0; i < r.questions.length; i++) {
      final q = r.questions[i];
      if ((q.answerType == 'text' || q.answerType == 'scenario') && _notes[i]!.text.trim().isEmpty) {
        recShowError(context, 'Write a response / notes for question ${i + 1}');
        return false;
      }
      final m = _marks[i]!.text.trim();
      if (m.isNotEmpty) {
        final v = num.tryParse(m);
        if (v == null || v < 0 || v > q.maxScore) {
          recShowError(context, 'Question ${i + 1} score must be between 0 and ${q.maxScore}');
          return false;
        }
      }
    }
    if (_feedback.text.trim().isEmpty) {
      recShowError(context, _isPortfolio ? 'Write the overall score note & remarks' : 'Write the overall assessment summary');
      return false;
    }
    return true;
  }

  Future<bool> _save(String recommendation, {String? reassignJobId, String? reassignReason}) async {
    final r = _round!;
    setState(() => _saving = recommendation);
    try {
      final notes = <String, String>{};
      final marks = <String, num>{};
      _notes.forEach((i, c) {
        if (c.text.trim().isNotEmpty) notes['$i'] = c.text.trim();
      });
      _marks.forEach((i, c) {
        final v = num.tryParse(c.text.trim());
        if (v != null) marks['$i'] = v;
      });
      final feedback = reassignReason != null && reassignReason.isNotEmpty
          ? '${_feedback.text.trim()}\n\nReassignment Reason: $reassignReason'
          : _feedback.text.trim();
      final msg = await _service.evaluateInterviewRound(
        r.id,
        scores: _scores.map((k, v) => MapEntry('$k', v)),
        questionNotes: notes,
        questionScores: marks,
        generalFeedback: feedback,
        recommendation: recommendation,
        overallScore: _isPortfolio ? _overall.round() : null,
        reassignedJobOpeningId: recommendation == 'Reassign' ? reassignJobId : null,
      );
      if (!mounted) return true;
      recShowSuccess(context, msg);
      await _load(showLoader: false);
      return true;
    } catch (e) {
      if (mounted) recShowError(context, e);
      return false;
    } finally {
      if (mounted) setState(() => _saving = null);
    }
  }

  Future<void> _decide(String rec) async {
    final r = _round!;
    if (rec == 'Reschedule') {
      if (await showRescheduleInterviewSheet(context, round: r)) _load(showLoader: false);
      return;
    }
    if (!_validate()) return;
    if (rec == 'Reassign') {
      await _reassign();
      return;
    }
    if (rec == 'Schedule') {
      if (_pendingNext != null) {
        recShowError(context,
            'Round ${_pendingNext!.roundNumber}: ${_pendingNext!.roundName} is already scheduled for ${recFormatDate(_pendingNext!.interviewDate)}.');
        return;
      }
      try {
        final candidate = await _service.getCandidate(r.candidateId);
        if (!mounted) return;
        // The scorecard is saved once the next round is scheduled
        if (await showScheduleInterviewSheet(context, candidate: candidate)) await _save('Schedule');
      } catch (e) {
        if (mounted) recShowError(context, e);
      }
      return;
    }
    final text = {
      'Pass': _isFinalRound
          ? 'Pass ${r.candidateName} in the final round? No rounds are left - mark them Selected to move them forward.'
          : 'Pass ${r.candidateName} in this round?',
      'Hold': 'Put ${r.candidateName} on hold?',
      'Fail': 'Reject ${r.candidateName}? Their status becomes Rejected.',
      'FinalRound': 'Select ${r.candidateName}? This decision is final and moves them to the offer stage.',
    }[rec]!;
    final ok = await recConfirm(context,
        title: recommendationLabel(rec), message: text, confirmLabel: 'Confirm', destructive: rec == 'Fail');
    if (ok) await _save(rec);
  }

  Future<void> _reassign() async {
    final r = _round!;
    List<RecJobOpening> jobs;
    try {
      jobs = (await _service.getJobOpenings(status: 'ACTIVE')).where((j) => j.id != r.jobOpeningId).toList();
    } catch (e) {
      if (mounted) recShowError(context, e);
      return;
    }
    if (!mounted) return;
    if (jobs.isEmpty) {
      recShowError(context, 'There is no other ACTIVE job opening to reassign to.');
      return;
    }
    String? jobId;
    final reason = TextEditingController();
    final result = await recShowSheet<bool>(
      context,
      title: 'Reassign ${r.candidateName}',
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Current role: ${r.position}', style: const TextStyle(fontSize: 12.5, color: kRecMuted)),
            const SizedBox(height: 12),
            RecDropdown<String>(
              label: 'Target role',
              value: jobId,
              items: jobs.map((j) => j.id).toList(),
              labelOf: (id) {
                final j = jobs.firstWhere((x) => x.id == id);
                return '${j.title} (${j.code})';
              },
              onChanged: (v) => setS(() => jobId = v),
            ),
            RecTextField(controller: reason, label: 'Reason', maxLines: 3),
            RecPrimaryButton(
              label: 'Reassign',
              icon: Icons.swap_horiz_rounded,
              onPressed: () {
                if (jobId == null) {
                  recShowError(ctx, 'Please select a target role');
                  return;
                }
                Navigator.pop(ctx, true);
              },
            ),
          ],
        ),
      ),
    );
    if (result == true && jobId != null) await _save('Reassign', reassignJobId: jobId, reassignReason: reason.text.trim());

  }

  Future<void> _editQuestion(int? index) async {
    final r = _round!;
    final initial = index == null ? null : r.questions[index];
    final q = await showQuestionEditor(context, initial: initial);
    if (q == null || !mounted) return;
    try {
      if (index == null) {
        await _service.addRoundQuestion(r.id, q);
      } else {
        await _service.updateRoundQuestion(r.id, initial!.id, q);
      }
      if (!mounted) return;
      recShowSuccess(context, index == null ? 'Question added to this round' : 'Question updated');
      // Keep what was typed: reload the round, then put the answers back
      final oldScores = Map<int, num>.from(_scores);
      final oldNotes = _notes.map((k, v) => MapEntry(k, v.text));
      final oldMarks = _marks.map((k, v) => MapEntry(k, v.text));
      final feedback = _feedback.text;
      await _load(showLoader: false);
      setState(() {
        _scores = oldScores;
        oldNotes.forEach((k, v) => _notes[k]?.text = v);
        oldMarks.forEach((k, v) => _marks[k]?.text = v);
        _feedback.text = feedback;
      });
    } catch (e) {
      if (mounted) recShowError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _round;
    return Scaffold(
      backgroundColor: kRecBg,
      appBar: recAppBar(context, 'Interview Scorecard', onRefresh: () => _load()),
      body: RecAsyncBody(
        loading: _loading,
        error: _error,
        isEmpty: r == null,
        emptyText: 'Interview round not found',
        onRetry: _load,
        builder: () {
          final round = r!;
          final withdrawn = round.candidateWithdrawn;
          final readOnly = (round.status != 'Scheduled' && !_forceEdit) || withdrawn;
          final canEditQuestions = round.status == 'Scheduled' && !withdrawn;
          final saved = round.evaluation?.recommendation;
          final selectedFinal = saved == 'FinalRound';
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _headerCard(round),
              if (_candidateRounds.length > 1) _otherRounds(round),
              if (withdrawn)
                _notice('The candidate withdrew their application - this round can no longer be evaluated or re-scheduled.',
                    AppColors.error, AppColors.errorBg),
              RecSectionTitle('Questions (${round.questions.length})',
                  trailing: canEditQuestions
                      ? TextButton.icon(
                          onPressed: () => _editQuestion(null),
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: const Text('Add question'),
                        )
                      : null),
              if (round.questions.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text('No questions on this round.', style: TextStyle(fontSize: 12.5, color: kRecMuted)),
                ),
              ...List.generate(round.questions.length, (i) => _questionCard(round, i, readOnly, canEditQuestions)),
              RecCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RecSectionTitle(_isPortfolio ? 'Overall score & remarks' : 'Overall assessment',
                        trailing: round.status != 'Scheduled' && !selectedFinal && !withdrawn
                            ? TextButton(
                                onPressed: () => setState(() {
                                  if (_forceEdit) _fillForm(round);
                                  _forceEdit = !_forceEdit;
                                }),
                                child: Text(_forceEdit ? 'Cancel edit' : 'Edit scorecard'),
                              )
                            : null),
                    if (_isPortfolio) ...[
                      Text('Overall score: ${_overall.round()} / 100',
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: kRecInk)),
                      Slider(
                        value: _overall,
                        min: 0,
                        max: 100,
                        divisions: 100,
                        activeColor: AppColors.primary,
                        onChanged: readOnly ? null : (v) => setState(() => _overall = v),
                      ),
                    ],
                    TextFormField(
                      controller: _feedback,
                      readOnly: readOnly,
                      maxLines: 5,
                      minLines: 3,
                      style: const TextStyle(fontSize: 14, color: kRecInk),
                      decoration: recInputDecoration('Summary *'),
                    ),
                  ],
                ),
              ),
              _decisions(round, readOnly, saved, selectedFinal, withdrawn),
            ],
          );
        },
      ),
    );
  }

  Widget _notice(String text, Color fg, Color bg) =>
      RecNotice(text, color: fg, background: bg, icon: Icons.info_outline_rounded);

  Widget _headerCard(RecInterviewRound r) {
    return RecCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            RecAvatar(r.candidateName),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r.candidateName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: kRecInk)),
                  const SizedBox(height: 2),
                  Text(r.position, style: const TextStyle(fontSize: 13, color: kRecMuted, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            RecBadge(r.displayStatus),
          ]),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 8),
          RecInfoRow('Round', 'Round ${r.roundNumber}: ${r.roundName}${_isFinalRound ? ' (final)' : ''}'),
          RecInfoRow('When', '${recFormatDate(r.interviewDate)}, ${recFormatTime(r.interviewTime)} (${r.duration})'),
          RecInfoRow('Mode', r.mode),
          RecInfoRow('Evaluator', r.interviewerName),
          if (r.calendarSyncStatus.isNotEmpty)
            RecInfoRow('Calendar', r.calendarSyncStatus == 'Failed' ? 'Failed: ${r.calendarSyncError}' : r.calendarSyncStatus),
          if (r.evaluation != null) RecInfoRow('Evaluated', recFormatDateTime(r.evaluation!.evaluatedAt)),
          if ((r.evaluation?.reassignedPosition ?? '').isNotEmpty) RecInfoRow('Reassigned to', r.evaluation!.reassignedPosition),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (r.meetLink.isNotEmpty)
              RecPrimaryButton(label: 'Join Meet', icon: Icons.video_call_outlined, onPressed: () => recOpenUrl(context, r.meetLink)),
            if (r.calendarEventLink.isNotEmpty)
              RecPrimaryButton(
                  label: 'Calendar event',
                  icon: Icons.calendar_month_outlined,
                  outlined: true,
                  onPressed: () => recOpenUrl(context, r.calendarEventLink)),
            if (r.status == 'Scheduled' && !r.candidateWithdrawn)
              RecPrimaryButton(
                label: 'Send invite again',
                icon: Icons.send_outlined,
                outlined: true,
                onPressed: () async {
                  try {
                    final msg = await _service.syncRoundCalendar(r.id);
                    if (!mounted) return;
                    recShowSuccess(context, msg);
                    _load(showLoader: false);
                  } catch (e) {
                    if (mounted) recShowError(context, e);
                  }
                },
              ),
          ]),
        ],
      ),
    );
  }

  Widget _otherRounds(RecInterviewRound current) {
    final rounds = [..._candidateRounds]..sort((a, b) => a.roundNumber.compareTo(b.roundNumber));
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(bottom: 12),
        children: rounds.map((x) {
          final sel = x.id == current.id;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text('R${x.roundNumber} ${x.roundName} • ${x.displayStatus}'),
              selected: sel,
              showCheckmark: false,
              selectedColor: AppColors.primary,
              backgroundColor: AppColors.surface,
              side: BorderSide(color: sel ? AppColors.primary : kRecBorder),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
              labelStyle: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: sel ? AppColors.onPrimary : kRecMuted),
              onSelected: sel
                  ? null
                  : (_) => Navigator.pushReplacement(
                      context, MaterialPageRoute(builder: (_) => AdminCandidateScorecardScreen(roundId: x.id))),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _questionCard(RecInterviewRound r, int i, bool readOnly, bool canEdit) {
    final q = r.questions[i];
    return RecCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text('${i + 1}. ${q.text}', style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: kRecInk)),
              ),
              if (canEdit)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Edit question',
                  icon: const Icon(Icons.edit_outlined, size: 20, color: kRecMuted),
                  onPressed: () => _editQuestion(i),
                ),
            ],
          ),
          Text('${answerTypeLabel(q.answerType)} • ${q.maxScore} marks', style: const TextStyle(fontSize: 12.5, color: kRecMuted)),
          const SizedBox(height: 8),
          if (q.answerType == 'rating')
            Row(
              children: List.generate(5, (s) {
                final filled = (_scores[i] ?? 0) >= s + 1;
                return IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: readOnly ? null : () => setState(() => _scores[i] = s + 1),
                  icon: Icon(filled ? Icons.star_rounded : Icons.star_border_rounded, color: AppColors.brand, size: 26),
                );
              }),
            ),
          if (q.answerType == 'multichoice')
            ...List.generate(q.options.length, (o) {
              final sel = _scores[i] == o;
              return InkWell(
                onTap: readOnly ? null : () => setState(() => _scores[i] = o),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(children: [
                    Icon(sel ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
                        size: 20, color: sel ? AppColors.brandDark : kRecHint),
                    const SizedBox(width: 8),
                    Expanded(child: Text(q.options[o], style: const TextStyle(fontSize: 13.5, color: kRecInk))),
                  ]),
                ),
              );
            }),
          if (q.answerType == 'scenario' && q.options.isNotEmpty)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColors.infoBg, borderRadius: BorderRadius.circular(12)),
              child: Text('Expected: ${q.options.first}', style: const TextStyle(fontSize: 13, color: AppColors.info)),
            ),
          const SizedBox(height: 6),
          TextFormField(
            controller: _notes[i],
            readOnly: readOnly,
            maxLines: 3,
            minLines: 1,
            style: const TextStyle(fontSize: 14, color: kRecInk),
            decoration: recInputDecoration(
                q.answerType == 'text' || q.answerType == 'scenario' ? 'Response / notes *' : 'Notes (optional)'),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: 160,
            child: TextFormField(
              controller: _marks[i],
              readOnly: readOnly,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(fontSize: 14, color: kRecInk),
              decoration: recInputDecoration('Score / ${q.maxScore}'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _decisions(RecInterviewRound r, bool readOnly, String? saved, bool selectedFinal, bool withdrawn) {
    final awaiting = r.status == 'Scheduled';
    final options = <(String, String, IconData, Color)>[
      ('Pass', 'Pass round', Icons.check_circle_outline_rounded, AppColors.success),
      ('Hold', 'Hold', Icons.pause_circle_outline_rounded, AppColors.brandDark),
      ('Fail', 'Reject', Icons.cancel_outlined, AppColors.error),
      if ((saved == null || saved == 'Pass' || saved == 'Schedule') && (awaiting || !_isFinalRound || _pendingNext != null))
        (awaiting ? 'Reschedule' : 'Schedule', awaiting ? 'Re-schedule' : (_pendingNext != null ? 'Next round scheduled' : 'Schedule next round'),
            Icons.event_repeat_rounded, AppColors.info),
      ('Reassign', (r.evaluation?.reassignedPosition ?? '').isNotEmpty ? 'Reassign: ${r.evaluation!.reassignedPosition}' : 'Reassign role',
          Icons.swap_horiz_rounded, AppColors.brandDark),
      ('FinalRound', 'Selected', Icons.emoji_events_outlined, AppColors.brandDark),
    ];
    return RecCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const RecSectionTitle('Decision'),
          Text(
            selectedFinal
                ? 'This candidate has been selected. The decision is final.'
                : saved != null
                    ? 'Choose a different decision to change it - the scorecard is saved again.'
                    : 'Choosing a decision saves the scorecard.',
            style: const TextStyle(fontSize: 12.5, color: kRecMuted),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: options.map((o) {
              final isSaved = saved == o.$1;
              final disabled = _saving != null ||
                  withdrawn ||
                  selectedFinal ||
                  (readOnly && isSaved && o.$1 != 'Schedule') ||
                  (o.$1 == 'Schedule' && _pendingNext != null);
              return OutlinedButton.icon(
                onPressed: disabled ? null : () => _decide(o.$1),
                icon: _saving == o.$1
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(o.$3, size: 18, color: disabled ? kRecHint : o.$4),
                label: Text(o.$2, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: kRecInk,
                  backgroundColor: isSaved ? o.$4.withValues(alpha: 0.12) : AppColors.surface,
                  side: BorderSide(color: isSaved ? o.$4 : kRecBorder, width: isSaved ? 1.4 : 1.2),
                  minimumSize: const Size(0, 44),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
