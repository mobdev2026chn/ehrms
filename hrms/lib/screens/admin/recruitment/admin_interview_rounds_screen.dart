// lib/screens/admin/recruitment/admin_interview_rounds_screen.dart
// Interview Rounds: one row per candidate (their latest ongoing round), filters by the round's
// status and number; tap opens the scorecard.

import 'package:flutter/material.dart';

import '../../../config/app_colors.dart';
import '../../../models/admin_recruitment_models.dart';
import '../../../services/admin_recruitment_service.dart';
import '../../../widgets/app_drawer.dart';
import 'admin_candidate_scorecard_screen.dart';
import 'rec_widgets.dart';

const List<String> kRoundStatusOptions = ['Scheduled', 'Passed', 'Selected', 'On Hold', 'Reassigned', 'Rejected'];

int byRoundSequence(RecInterviewRound a, RecInterviewRound b) {
  final n = a.roundNumber.compareTo(b.roundNumber);
  if (n != 0) return n;
  final d = '${a.interviewDate}T${a.interviewTime}'.compareTo('${b.interviewDate}T${b.interviewTime}');
  if (d != 0) return d;
  return a.createdAt.compareTo(b.createdAt);
}

class _CandidateRow {
  final String candidateId;
  final List<RecInterviewRound> rounds;
  final RecInterviewRound current;
  _CandidateRow(this.candidateId, this.rounds, this.current);
}

class AdminInterviewRoundsScreen extends StatefulWidget {
  const AdminInterviewRoundsScreen({super.key});

  @override
  State<AdminInterviewRoundsScreen> createState() => _AdminInterviewRoundsScreenState();
}

class _AdminInterviewRoundsScreenState extends State<AdminInterviewRoundsScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final AdminRecruitmentService _service = AdminRecruitmentService();

  bool _loading = true;
  String? _error;
  List<_CandidateRow> _rows = [];
  String _search = '';
  String _status = 'All';
  String _round = 'All';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool showLoader = true}) async {
    if (showLoader) setState(() => _loading = true);
    try {
      final rounds = await _service.getInterviewRounds();
      final by = <String, List<RecInterviewRound>>{};
      for (final r in rounds) {
        by.putIfAbsent(r.candidateId, () => []).add(r);
      }
      final rows = by.entries.map((e) {
        final sorted = [...e.value]..sort(byRoundSequence);
        final ongoing = sorted.where((r) => r.status == 'Scheduled').toList();
        return _CandidateRow(e.key, sorted, ongoing.isNotEmpty ? ongoing.last : sorted.last);
      }).toList()
        ..sort((a, b) => '${b.current.interviewDate}T${b.current.interviewTime}'
            .compareTo('${a.current.interviewDate}T${a.current.interviewTime}'));
      if (!mounted) return;
      setState(() {
        _rows = rows;
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

  @override
  Widget build(BuildContext context) {
    final roundNumbers = _rows.map((r) => r.current.roundNumber).toSet().toList()..sort();
    final q = _search.toLowerCase();
    final visible = _rows.where((row) {
      final c = row.current;
      if (_status != 'All' && c.displayStatus != _status) return false;
      if (_round != 'All' && '${c.roundNumber}' != _round) return false;
      return q.isEmpty ||
          c.candidateName.toLowerCase().contains(q) ||
          c.position.toLowerCase().contains(q) ||
          c.interviewerName.toLowerCase().contains(q) ||
          row.rounds.any((r) => r.roundName.toLowerCase().contains(q));
    }).toList();

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: kRecBg,
      drawer: const AppDrawer(),
      appBar: recAppBar(context, 'Interview Rounds', drawerKey: _scaffoldKey, onRefresh: () => _load()),
      body: RecAsyncBody(
        loading: _loading,
        error: _error,
        isEmpty: _rows.isEmpty,
        emptyText: 'No interviews scheduled yet.\nSchedule one from a candidate\'s profile.',
        emptyIcon: Icons.event_busy_outlined,
        onRetry: _load,
        builder: () => RefreshIndicator(
          onRefresh: () => _load(showLoader: false),
          color: AppColors.primary,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              RecSearchField(hint: 'Search candidate, position, round or evaluator', onChanged: (v) => setState(() => _search = v)),
              const SizedBox(height: 12),
              RecFilterChips(
                options: const ['All', ...kRoundStatusOptions],
                selected: _status,
                onSelected: (s) => setState(() => _status = s),
              ),
              const SizedBox(height: 8),
              RecFilterChips(
                options: ['All', ...roundNumbers.map((n) => '$n')],
                selected: _round,
                labelOf: (s) => s == 'All' ? 'All rounds' : 'Round $s',
                onSelected: (s) => setState(() => _round = s),
              ),
              const SizedBox(height: 16),
              if (visible.isEmpty)
                const Padding(padding: EdgeInsets.only(top: 60), child: RecEmptyState(text: 'No rounds match the filters'))
              else
                ...visible.map(_card),
            ],
          ),
        ),
      ),
    );
  }

  Widget _card(_CandidateRow row) {
    final c = row.current;
    return RecCard(
      onTap: () async {
        await Navigator.push(context, MaterialPageRoute(builder: (_) => AdminCandidateScorecardScreen(roundId: c.id)));
        _load(showLoader: false);
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            RecAvatar(c.candidateName, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c.candidateName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: kRecInk)),
                  const SizedBox(height: 2),
                  Text(c.position, style: const TextStyle(fontSize: 13, color: kRecMuted, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            RecBadge(c.displayStatus),
          ]),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),
          Text('Round ${c.roundNumber}: ${c.roundName}',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: kRecInk)),
          const SizedBox(height: 4),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Padding(
              padding: EdgeInsets.only(top: 1),
              child: Icon(Icons.event_outlined, size: 15, color: kRecMuted),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                  '${recFormatDate(c.interviewDate)} • ${recFormatTime(c.interviewTime)} • ${c.mode} • ${c.interviewerName}',
                  style: const TextStyle(fontSize: 12.5, color: kRecMuted)),
            ),
          ]),
          if (row.rounds.length > 1) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: row.rounds.map((r) => RecBadge('R${r.roundNumber} ${r.displayStatus}', colorKey: r.displayStatus)).toList(),
            ),
          ],
        ],
      ),
    );
  }
}
