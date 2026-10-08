// lib/screens/admin/recruitment/admin_selected_rejected_screen.dart
// Selected / Rejected: candidates selected in interview (and the offer stage that follows) or
// rejected, with their rounds; send offer to a selected candidate, or reject them.

import 'package:flutter/material.dart';

import '../../../config/app_colors.dart';
import '../../../models/admin_recruitment_models.dart';
import '../../../services/admin_recruitment_service.dart';
import '../../../widgets/app_drawer.dart';
import 'admin_candidate_detail_screen.dart';
import 'admin_candidate_scorecard_screen.dart';
import 'admin_interview_rounds_screen.dart' show byRoundSequence;
import 'admin_send_offer_screen.dart';
import 'rec_widgets.dart';

const List<String> _selectedStatuses = ['Selected', 'Offered', 'Offer Accepted', 'Offer Rejected', 'Offer Expired', 'Hired'];
const List<String> _preOfferStatuses = ['Applied', 'Shortlisted', 'Interviewing', 'Passed', 'On Hold', 'Reassigned', 'Selected'];

class _Row {
  final RecCandidate candidate;
  final List<RecInterviewRound> rounds;
  final bool selectedInRound;
  _Row(this.candidate, this.rounds, this.selectedInRound);
}

class AdminSelectedRejectedScreen extends StatefulWidget {
  const AdminSelectedRejectedScreen({super.key});

  @override
  State<AdminSelectedRejectedScreen> createState() => _AdminSelectedRejectedScreenState();
}

class _AdminSelectedRejectedScreenState extends State<AdminSelectedRejectedScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final AdminRecruitmentService _service = AdminRecruitmentService();

  bool _loading = true;
  String? _error;
  List<_Row> _rows = [];
  Set<String> _sentIds = {};
  String _filter = 'All';
  String _search = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool showLoader = true}) async {
    if (showLoader) setState(() => _loading = true);
    try {
      final candidatesF = _service.getCandidates();
      final roundsF = _service.getInterviewRounds();
      final sentF = _service.getSentOfferCandidates();
      final candidates = await candidatesF;
      final rounds = await roundsF;
      final sent = await sentF;
      final byCandidate = <String, List<RecInterviewRound>>{};
      for (final r in rounds) {
        byCandidate.putIfAbsent(r.candidateId, () => []).add(r);
      }
      final rows = <_Row>[];
      for (final c in candidates) {
        final rs = [...(byCandidate[c.id] ?? <RecInterviewRound>[])]..sort(byRoundSequence);
        final evaluated = rs.where((r) => r.evaluation != null && r.evaluation!.evaluatedAt.isNotEmpty).toList()
          ..sort((a, b) => b.evaluation!.evaluatedAt.compareTo(a.evaluation!.evaluatedAt));
        final selectedInRound = evaluated.isNotEmpty && evaluated.first.evaluation!.recommendation == 'FinalRound';
        final onBoard = _selectedStatuses.contains(c.status) || c.status == 'Rejected' ||
            (selectedInRound && _preOfferStatuses.contains(c.status));
        if (onBoard) rows.add(_Row(c, rs, selectedInRound));
      }
      rows.sort((a, b) => b.candidate.updatedAt.compareTo(a.candidate.updatedAt));
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _sentIds = sent.map((s) => s.candidateId).toSet();
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

  bool _canSendOffer(_Row row) {
    final c = row.candidate;
    if (_sentIds.contains(c.id)) return false;
    if (c.status == 'Selected') return true;
    return row.selectedInRound && _preOfferStatuses.contains(c.status);
  }

  String _boardStatus(_Row row) =>
      row.selectedInRound && _preOfferStatuses.contains(row.candidate.status) ? 'Selected' : row.candidate.status;

  Future<void> _actions(_Row row) async {
    final c = row.candidate;
    final a = await recShowActions(context, title: c.fullName, actions: [
      const RecAction('view', 'View profile & activity', Icons.visibility_outlined),
      if (row.rounds.isNotEmpty) const RecAction('rounds', 'Open latest scorecard', Icons.fact_check_outlined),
      if (_canSendOffer(row)) const RecAction('offer', 'Send offer letter', Icons.mail_outline_rounded),
      if (_boardStatus(row) == 'Selected') const RecAction('reject', 'Reject candidate', Icons.cancel_outlined, destructive: true),
    ]);
    if (!mounted || a == null) return;
    switch (a) {
      case 'view':
        await Navigator.push(context, MaterialPageRoute(builder: (_) => AdminCandidateDetailScreen(candidateId: c.id)));
        _load(showLoader: false);
        break;
      case 'rounds':
        await Navigator.push(
            context, MaterialPageRoute(builder: (_) => AdminCandidateScorecardScreen(roundId: row.rounds.last.id)));
        _load(showLoader: false);
        break;
      case 'offer':
        final sent = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => AdminSendOfferScreen(candidateId: c.id)));
        if (sent == true) _load(showLoader: false);
        break;
      case 'reject':
        final ok = await recConfirm(context,
            title: 'Reject ${c.fullName}?',
            message: 'They were selected in interview. Their status becomes Rejected and no offer will be sent.',
            confirmLabel: 'Reject',
            destructive: true);
        if (!ok) return;
        try {
          final msg = await _service.updateCandidateStatus(c.id, 'Rejected');
          if (!mounted) return;
          recShowSuccess(context, msg);
          _load(showLoader: false);
        } catch (e) {
          if (mounted) recShowError(context, e);
        }
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final options = ['All', ..._selectedStatuses, 'Rejected'];
    final counts = <String, int>{'All': _rows.length};
    for (final s in options.skip(1)) {
      counts[s] = _rows.where((r) => _boardStatus(r) == s).length;
    }
    final q = _search.toLowerCase();
    final visible = _rows.where((r) {
      if (_filter != 'All' && _boardStatus(r) != _filter) return false;
      final c = r.candidate;
      return q.isEmpty ||
          c.fullName.toLowerCase().contains(q) ||
          c.email.toLowerCase().contains(q) ||
          c.displayJob.toLowerCase().contains(q);
    }).toList();

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: kRecBg,
      drawer: const AppDrawer(),
      appBar: recAppBar(context, 'Selected / Rejected', drawerKey: _scaffoldKey, onRefresh: () => _load()),
      body: RecAsyncBody(
        loading: _loading,
        error: _error,
        isEmpty: false,
        onRetry: _load,
        builder: () => RefreshIndicator(
          onRefresh: () => _load(showLoader: false),
          color: AppColors.primary,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              RecSearchField(hint: 'Search name, email or job', onChanged: (v) => setState(() => _search = v)),
              const SizedBox(height: 12),
              RecFilterChips(options: options, selected: _filter, counts: counts, onSelected: (s) => setState(() => _filter = s)),
              const SizedBox(height: 12),
              if (visible.isEmpty)
                const Padding(padding: EdgeInsets.only(top: 60), child: RecEmptyState(text: 'No candidates here yet'))
              else
                ...visible.map((row) {
                  final c = row.candidate;
                  return RecCard(
                    onTap: () => _actions(row),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          RecAvatar(c.fullName, size: 40),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(c.fullName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: kRecInk)),
                                Text(c.displayJob, style: const TextStyle(fontSize: 13, color: kRecMuted, fontWeight: FontWeight.w500)),
                              ],
                            ),
                          ),
                          RecBadge(_boardStatus(row)),
                        ]),
                        if (row.rounds.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: row.rounds
                                .map((r) => RecBadge('R${r.roundNumber} ${r.roundName}: ${r.displayStatus}', colorKey: r.displayStatus))
                                .toList(),
                          ),
                        ],
                        if (_canSendOffer(row)) ...[
                          const SizedBox(height: 12),
                          Align(
                            alignment: Alignment.centerRight,
                            child: RecPrimaryButton(
                              label: 'Send offer',
                              icon: Icons.send_rounded,
                              onPressed: () async {
                                final sent = await Navigator.push<bool>(
                                    context, MaterialPageRoute(builder: (_) => AdminSendOfferScreen(candidateId: c.id)));
                                if (sent == true) _load(showLoader: false);
                              },
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                }),
            ],
          ),
        ),
      ),
    );
  }
}
