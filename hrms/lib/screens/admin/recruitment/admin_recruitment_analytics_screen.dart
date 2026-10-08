// lib/screens/admin/recruitment/admin_recruitment_analytics_screen.dart
// Recruitment Analytics, computed from the module's list endpoints (candidates, interview
// rounds, job openings, sent offers) - the same model as the web analytics page.

import 'package:flutter/material.dart';

import '../../../config/app_colors.dart';
import '../../../models/admin_recruitment_models.dart';
import '../../../services/admin_recruitment_service.dart';
import 'rec_widgets.dart';

const List<String> _ranges = ['Today', 'This Week', 'This Month', 'This Quarter', 'All Time'];
const List<String> _funnelStages = [
  'Applied',
  'Interviewing',
  'Selected',
  'Offer sent',
  'Offer accepted',
  'Documents verified',
  'Joined as staff',
];

class AdminRecruitmentAnalyticsScreen extends StatefulWidget {
  const AdminRecruitmentAnalyticsScreen({super.key});

  @override
  State<AdminRecruitmentAnalyticsScreen> createState() => _AdminRecruitmentAnalyticsScreenState();
}

class _AdminRecruitmentAnalyticsScreenState extends State<AdminRecruitmentAnalyticsScreen> {
  final AdminRecruitmentService _service = AdminRecruitmentService();
  bool _loading = true;
  String? _error;
  List<RecCandidate> _candidates = [];
  List<RecInterviewRound> _rounds = [];
  List<RecJobOpening> _jobs = [];
  Map<String, String> _sentAt = {};

  String _range = 'All Time';
  String _jobId = 'All';
  String _source = 'All';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool showLoader = true}) async {
    if (showLoader) setState(() => _loading = true);
    try {
      final cF = _service.getCandidates();
      final rF = _service.getInterviewRounds();
      final jF = _service.getJobOpenings();
      final sF = _service.getSentOfferCandidates();
      final c = await cF;
      final r = await rF;
      final j = await jF;
      final s = await sF;
      if (!mounted) return;
      setState(() {
        _candidates = c;
        _rounds = r;
        _jobs = j;
        _sentAt = {for (final x in s) x.candidateId: x.lastSentAt};
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

  (String?, String?) _bounds() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (_range) {
      case 'Today':
        return (recDateKeyOf(today), recDateKeyOf(today));
      case 'This Week':
        final start = today.subtract(Duration(days: today.weekday - 1));
        return (recDateKeyOf(start), recDateKeyOf(start.add(const Duration(days: 6))));
      case 'This Month':
        return (recDateKeyOf(DateTime(now.year, now.month, 1)), recDateKeyOf(DateTime(now.year, now.month + 1, 0)));
      case 'This Quarter':
        final q = (now.month - 1) ~/ 3;
        return (recDateKeyOf(DateTime(now.year, q * 3 + 1, 1)), recDateKeyOf(DateTime(now.year, q * 3 + 4, 0)));
      default:
        return (null, null);
    }
  }

  bool _inBounds(String day, (String?, String?) b) {
    if (b.$1 == null) return true;
    if (day.isEmpty) return false;
    return day.compareTo(b.$1!) >= 0 && day.compareTo(b.$2!) <= 0;
  }

  bool _converted(RecCandidate c) =>
      c.verificationStage == 'converted' || (c.staffId.isNotEmpty && c.status == 'Hired');

  bool _inVerification(RecCandidate c) =>
      c.status == 'Offer Accepted' ||
      c.status == 'Hired' ||
      c.verificationStage == 'verificationReject' ||
      c.verificationStage == 'verificationBlacklist';

  int _stageReached(RecCandidate c, bool hadRound, bool selectedInRound, bool offerSent) {
    if (_converted(c) || c.status == 'Hired') return 6;
    if (c.documentsSavedAt.isNotEmpty) return 5;
    if (_inVerification(c) || c.verificationStage == 'verificationHold') return 4;
    if (offerSent || ['Offered', 'Offer Rejected', 'Offer Expired'].contains(c.status)) return 3;
    if (selectedInRound || c.status == 'Selected') return 2;
    if (hadRound || c.status == 'Interviewing' || c.status == 'Passed') return 1;
    return 0;
  }

  int _pct(int a, int b) => b == 0 ? 0 : ((a / b) * 100).round();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kRecBg,
      appBar: recAppBar(context, 'Recruitment Analytics', onRefresh: () => _load()),
      body: RecAsyncBody(
        loading: _loading,
        error: _error,
        isEmpty: false,
        onRetry: _load,
        builder: _content,
      ),
    );
  }

  Widget _content() {
    final bounds = _bounds();
    final today = recTodayKey();
    final jobsById = {for (final j in _jobs) j.id: j};
    final scoped = _candidates.where((c) {
      if (_jobId != 'All' && c.jobOpeningId != _jobId) return false;
      if (_source != 'All' && c.source != _source) return false;
      return true;
    }).toList();
    final scopedIds = scoped.map((c) => c.id).toSet();
    final cohort = scoped.where((c) => _inBounds(c.appliedDate, bounds)).toList();

    final roundsBy = <String, List<RecInterviewRound>>{};
    for (final r in _rounds) {
      roundsBy.putIfAbsent(r.candidateId, () => []).add(r);
    }
    final reached = <String, int>{};
    for (final c in scoped) {
      final rs = roundsBy[c.id] ?? [];
      reached[c.id] = _stageReached(c, rs.isNotEmpty, rs.any((r) => r.evaluation?.recommendation == 'FinalRound'), _sentAt.containsKey(c.id));
    }
    List<RecCandidate> atLeast(int s) => cohort.where((c) => (reached[c.id] ?? 0) >= s).toList();
    int withStatus(List<String> st) => cohort.where((c) => st.contains(c.status)).length;

    final activeJobs = _jobs.where((j) => j.status == 'ACTIVE' && (_jobId == 'All' || j.id == _jobId)).toList();
    final vacancies = activeJobs.fold<int>(0, (s, j) => s + j.positions);
    final interviewedEver = atLeast(1).length;
    final selectedEver = atLeast(2).length;
    final joined = cohort.where(_converted).length;
    final verificationOpen = cohort.where((c) => _inVerification(c) && !_converted(c) && c.verificationStage == 'pending').toList();
    const closed = ['Hired', 'Rejected', 'Withdrawn', 'Offer Rejected', 'Offer Expired'];

    final periodRounds = _rounds.where((r) => scopedIds.contains(r.candidateId) && _inBounds(r.interviewDate, bounds)).toList();
    final evaluated = periodRounds.where((r) => r.status == 'Evaluated').toList();
    final todayRounds = _rounds.where((r) => scopedIds.contains(r.candidateId) && r.interviewDate == today).toList();

    final funnel = List.generate(_funnelStages.length, (i) => atLeast(i).length);
    final sources = <String, int>{};
    for (final c in cohort) {
      sources[c.source] = (sources[c.source] ?? 0) + 1;
    }

    return RefreshIndicator(
      onRefresh: () => _load(showLoader: false),
      color: AppColors.primary,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          RecFilterChips(options: _ranges, selected: _range, onSelected: (r) => setState(() => _range = r)),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: RecDropdown<String>(
                label: 'Job opening',
                value: _jobId,
                items: ['All', ..._jobs.map((j) => j.id)],
                labelOf: (id) => id == 'All' ? 'All jobs' : (jobsById[id]?.title ?? id),
                onChanged: (v) => setState(() => _jobId = v ?? 'All'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: RecDropdown<String>(
                label: 'Source',
                value: _source,
                items: const ['All', ...kCandidateSources],
                labelOf: (s) => s == 'All' ? 'All sources' : s,
                onChanged: (v) => setState(() => _source = v ?? 'All'),
              ),
            ),
          ]),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.75,
            children: [
              RecStatTile(label: 'Open positions\n$vacancies vacancies', value: '${activeJobs.length}', icon: Icons.work_outline_rounded),
              RecStatTile(
                  label: 'Applications\n${cohort.where((c) => !closed.contains(c.status)).length} in process',
                  value: '${cohort.length}',
                  icon: Icons.inbox_outlined,
                  color: AppColors.info),
              RecStatTile(
                  label: 'Interviewing\n${_pct(interviewedEver, cohort.length)}% reached',
                  value: '${withStatus(['Interviewing', 'Passed'])}',
                  icon: Icons.record_voice_over_outlined,
                  color: AppColors.indigo),
              RecStatTile(
                  label: 'Selected\n${_pct(selectedEver, interviewedEver)}% of interviewed',
                  value: '$selectedEver',
                  icon: Icons.emoji_events_outlined,
                  color: AppColors.brandDark),
              RecStatTile(
                  label: 'Rejected\n${withStatus(['Withdrawn'])} withdrew',
                  value: '${withStatus(['Rejected'])}',
                  icon: Icons.cancel_outlined,
                  color: AppColors.error),
              RecStatTile(
                  label: 'Offers awaiting reply\n${atLeast(3).length} sent',
                  value: '${cohort.where((c) => c.status == 'Offered' && (reached[c.id] ?? 0) < 4).length}',
                  icon: Icons.mail_outline_rounded,
                  color: AppColors.brandDark),
              RecStatTile(
                  label: 'In verification\n${verificationOpen.where((c) => c.documentsSavedAt.isNotEmpty).length} ready to convert',
                  value: '${verificationOpen.length}',
                  icon: Icons.verified_user_outlined,
                  color: AppColors.info),
              RecStatTile(
                  label: 'Joined as staff\n${_pct(joined, cohort.length)}% of applications',
                  value: '$joined',
                  icon: Icons.badge_outlined,
                  color: AppColors.success),
            ],
          ),
          const SizedBox(height: 16),
          _barsCard('Hiring funnel', [
            for (var i = 0; i < _funnelStages.length; i++) (_funnelStages[i], funnel[i], i >= 2 ? kRecInk : AppColors.brand),
          ], max: funnel.first),
          _barsCard('Today', [
            ('Applications received', scoped.where((c) => c.appliedDate == today).length, AppColors.info),
            ('Interviews today', todayRounds.length, AppColors.brand),
            ('Interviews still to hold', todayRounds.where((r) => r.status == 'Scheduled').length, AppColors.brandDark),
            ('Offers sent', scoped.where((c) => recDateKey(_sentAt[c.id]) == today).length, AppColors.success),
          ]),
          _barsCard('Interviews in period', [
            ('Interviews', periodRounds.length, AppColors.brand),
            ('Evaluated', evaluated.length, AppColors.success),
            ('Awaiting evaluation', periodRounds.where((r) => r.status == 'Scheduled' && r.interviewDate.compareTo(today) <= 0).length, AppColors.brandDark),
            ('Upcoming', periodRounds.where((r) => r.status == 'Scheduled' && r.interviewDate.compareTo(today) > 0).length, AppColors.info),
            ('Passed', evaluated.where((r) => ['Pass', 'Schedule', 'FinalRound'].contains(r.evaluation?.recommendation)).length, AppColors.success),
            ('Failed', evaluated.where((r) => r.evaluation?.recommendation == 'Fail').length, AppColors.error),
          ]),
          _barsCard('Outcomes', [
            ('Selected', selectedEver, AppColors.brandDark),
            ('Rejected', withStatus(['Rejected']), kRecInk),
            ('On hold', withStatus(['On Hold']), AppColors.brand),
            ('Withdrawn', withStatus(['Withdrawn']), kRecHint),
          ]),
          _barsCard('Applications by source', [
            for (final e in (sources.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))) (e.key, e.value, AppColors.indigo),
          ]),
          _vacancies(activeJobs),
        ],
      ),
    );
  }

  Widget _barsCard(String title, List<(String, int, Color)> rows, {int? max}) {
    final top = max ?? rows.fold<int>(0, (m, r) => r.$2 > m ? r.$2 : m);
    return RecCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RecSectionTitle(title),
          if (rows.isEmpty) const Text('No data for this period', style: TextStyle(fontSize: 12.5, color: kRecMuted)),
          ...rows.map((r) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(
                          child: Text(r.$1, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: kRecInk))),
                      Text('${r.$2}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: kRecInk)),
                    ]),
                    const SizedBox(height: 6),
                    LinearProgressIndicator(
                      value: top == 0 ? 0 : r.$2 / top,
                      minHeight: 8,
                      color: r.$3,
                      backgroundColor: AppColors.inputFill,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  Widget _vacancies(List<RecJobOpening> active) {
    return RecCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const RecSectionTitle('Active openings'),
          if (active.isEmpty) const Text('No active job openings', style: TextStyle(fontSize: 12.5, color: kRecMuted)),
          ...active.map((j) {
            final applicants = _candidates.where((c) => c.jobOpeningId == j.id).toList();
            final hired = applicants.where((c) => c.status == 'Hired' || _converted(c)).length;
            return ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const RecIconTile(Icons.work_outline_rounded, size: 36),
              title: Text(j.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: kRecInk)),
              subtitle: Text('${j.department} • ${j.branch} • ${applicants.length} applicant(s)',
                  style: const TextStyle(fontSize: 12, color: kRecMuted)),
              trailing: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: AppColors.successBg, borderRadius: BorderRadius.circular(999)),
                child: Text('$hired/${j.positions} filled',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.success)),
              ),
            );
          }),
        ],
      ),
    );
  }
}
