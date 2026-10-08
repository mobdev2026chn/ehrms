// lib/screens/admin/recruitment/admin_candidates_screen.dart
// Candidates: list with search and status chips; add, view, edit, status, schedule interview,
// delete; share application form link.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../../config/app_colors.dart';
import '../../../config/constants.dart';
import '../../../models/admin_recruitment_models.dart';
import '../../../services/admin_recruitment_service.dart';
import '../../../widgets/app_drawer.dart';
import 'admin_candidate_detail_screen.dart';
import 'admin_candidate_disposition_screen.dart';
import 'admin_candidate_form_screen.dart';
import 'admin_schedule_interview_sheet.dart';
import 'rec_widgets.dart';

/// Lets the user pick a new status for [c] and saves it. Returns true when changed.
Future<bool> changeCandidateStatus(BuildContext context, RecCandidate c) async {
  final picked = await recShowActions(
    context,
    title: 'Change status of ${c.fullName}',
    actions: kCandidateStatuses
        .where((s) => s != c.status)
        .map((s) => RecAction(s, s, Icons.label_outline_rounded))
        .toList(),
  );
  if (picked == null || !context.mounted) return false;
  final ok = await recConfirm(context,
      title: 'Change status?', message: '${c.fullName}: ${c.status} → $picked', confirmLabel: 'Change');
  if (!ok || !context.mounted) return false;
  try {
    final msg = await AdminRecruitmentService().updateCandidateStatus(c.id, picked);
    if (context.mounted) recShowSuccess(context, msg);
    return true;
  } catch (e) {
    if (context.mounted) recShowError(context, e);
    return false;
  }
}

Future<bool> deleteCandidateWithConfirm(BuildContext context, RecCandidate c) async {
  final ok = await recConfirm(
    context,
    title: 'Delete candidate?',
    message: '${c.fullName} and their application will be removed permanently.',
    confirmLabel: 'Delete',
    destructive: true,
  );
  if (!ok || !context.mounted) return false;
  try {
    final msg = await AdminRecruitmentService().deleteCandidate(c.id);
    if (context.mounted) recShowSuccess(context, msg);
    return true;
  } catch (e) {
    if (context.mounted) recShowError(context, e);
    return false;
  }
}

/// The web app's origin, from the API base URL (…/api).
String recWebOrigin() {
  final base = AppConstants.baseUrl;
  return base.endsWith('/api') ? base.substring(0, base.length - 4) : base.replaceAll(RegExp(r'/+$'), '');
}

/// Generates a single-use application form link and offers copy / share.
Future<void> showShareFormLinkSheet(BuildContext context) async {
  await recShowSheet(context, title: 'Share application form', builder: (ctx) => const _ShareLinkBody());
}

class _ShareLinkBody extends StatefulWidget {
  const _ShareLinkBody();
  @override
  State<_ShareLinkBody> createState() => _ShareLinkBodyState();
}

class _ShareLinkBodyState extends State<_ShareLinkBody> {
  String? _link;
  bool _busy = false;

  Future<void> _generate() async {
    setState(() => _busy = true);
    try {
      final token = await AdminRecruitmentService().createCandidateFormLink();
      if (!mounted) return;
      setState(() => _link = '${recWebOrigin()}/candidate/apply/$token');
    } catch (e) {
      if (mounted) recShowError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Generate a single-use link. The candidate fills in the application form themselves; '
          'the link stops working after one application.',
          style: TextStyle(fontSize: 13, color: kRecMuted, height: 1.45),
        ),
        const SizedBox(height: 16),
        if (_link != null) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: kRecBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: kRecSoftBorder)),
            child: SelectableText(_link!, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: kRecInk)),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: RecPrimaryButton(
                label: 'Copy',
                icon: Icons.copy_rounded,
                outlined: true,
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: _link!));
                  if (context.mounted) recShowSuccess(context, 'Link copied');
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: RecPrimaryButton(
                label: 'Share',
                icon: Icons.share_rounded,
                onPressed: () => SharePlus.instance.share(ShareParams(text: _link!, subject: 'Job application form')),
              ),
            ),
          ]),
          const SizedBox(height: 12),
        ],
        RecPrimaryButton(
          label: _link == null ? 'Generate link' : 'Generate another link',
          icon: Icons.link_rounded,
          outlined: _link != null,
          busy: _busy,
          onPressed: _generate,
        ),
      ],
    );
  }
}

class AdminCandidatesScreen extends StatefulWidget {
  const AdminCandidatesScreen({super.key});

  @override
  State<AdminCandidatesScreen> createState() => _AdminCandidatesScreenState();
}

class _AdminCandidatesScreenState extends State<AdminCandidatesScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final AdminRecruitmentService _service = AdminRecruitmentService();

  bool _loading = true;
  String? _error;
  List<RecCandidate> _candidates = [];
  String _search = '';
  String _status = 'All';
  String _source = 'All';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool showLoader = true}) async {
    if (showLoader) setState(() => _loading = true);
    try {
      final list = await _service.getCandidates();
      if (!mounted) return;
      setState(() {
        _candidates = list;
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

  List<RecCandidate> get _filtered {
    final q = _search.toLowerCase();
    return _candidates.where((c) {
      if (_status != 'All' && c.status != _status) return false;
      if (_source != 'All' && c.source != _source) return false;
      if (q.isEmpty) return true;
      return c.fullName.toLowerCase().contains(q) ||
          c.email.toLowerCase().contains(q) ||
          c.phone.contains(q) ||
          c.displayJob.toLowerCase().contains(q) ||
          c.primarySkill.toLowerCase().contains(q) ||
          c.candidateId.toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _openForm([RecCandidate? c]) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => AdminCandidateFormScreen(candidate: c)),
    );
    if (saved == true) _load(showLoader: false);
  }

  Future<void> _openDetail(RecCandidate c) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => AdminCandidateDetailScreen(candidateId: c.id)));
    _load(showLoader: false);
  }

  Future<void> _showActions(RecCandidate c) async {
    final action = await recShowActions(context, title: c.fullName, actions: const [
      RecAction('view', 'View profile', Icons.visibility_outlined),
      RecAction('edit', 'Edit', Icons.edit_outlined),
      RecAction('status', 'Change status', Icons.label_outline_rounded),
      RecAction('schedule', 'Schedule interview', Icons.event_available_outlined),
      RecAction('delete', 'Delete', Icons.delete_outline_rounded, destructive: true),
    ]);
    if (!mounted || action == null) return;
    switch (action) {
      case 'view':
        _openDetail(c);
        break;
      case 'edit':
        _openForm(c);
        break;
      case 'status':
        if (await changeCandidateStatus(context, c)) _load(showLoader: false);
        break;
      case 'schedule':
        if (await showScheduleInterviewSheet(context, candidate: c)) _load(showLoader: false);
        break;
      case 'delete':
        if (await deleteCandidateWithConfirm(context, c)) _load(showLoader: false);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final counts = <String, int>{'All': _candidates.length};
    for (final s in kCandidateStatuses) {
      counts[s] = _candidates.where((c) => c.status == s).length;
    }
    final filtered = _filtered;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: kRecBg,
      drawer: const AppDrawer(),
      appBar: recAppBar(context, 'Candidates', drawerKey: _scaffoldKey, onRefresh: () => _load(), actions: [
        IconButton(
          tooltip: 'Candidate disposition',
          icon: const Icon(Icons.assignment_late_outlined, size: 22),
          onPressed: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => const AdminCandidateDispositionScreen())),
        ),
        IconButton(
          tooltip: 'Share form link',
          icon: const Icon(Icons.link_rounded, size: 22),
          onPressed: () => showShareFormLinkSheet(context),
        ),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('Add Candidate', style: TextStyle(fontWeight: FontWeight.w700)),
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
              RecSearchField(hint: 'Search name, email, phone, job or skill', onChanged: (v) => setState(() => _search = v)),
              const SizedBox(height: 12),
              RecFilterChips(
                options: ['All', ...kCandidateStatuses.where((s) => (counts[s] ?? 0) > 0 || s == _status)],
                selected: _status,
                counts: counts,
                onSelected: (s) => setState(() => _status = s),
              ),
              const SizedBox(height: 8),
              RecFilterChips(
                options: const ['All', ...kCandidateSources],
                selected: _source,
                labelOf: (s) => s == 'All' ? 'All sources' : s,
                onSelected: (s) => setState(() => _source = s),
              ),
              const SizedBox(height: 12),
              if (filtered.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 60),
                  child: RecEmptyState(text: 'No candidates match the current filters', icon: Icons.person_search_outlined),
                )
              else
                ...filtered.map(_card),
            ],
          ),
        ),
      ),
    );
  }

  Widget _card(RecCandidate c) {
    return RecCard(
      onTap: () => _openDetail(c),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RecAvatar(c.fullName),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                    child: Text(c.fullName,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: kRecInk)),
                  ),
                  const SizedBox(width: 8),
                  RecBadge(c.status),
                ]),
                const SizedBox(height: 2),
                Text(c.displayJob, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: kRecMuted)),
                const SizedBox(height: 4),
                Text('${c.email} • ${c.phone}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, color: kRecMuted)),
                const SizedBox(height: 4),
                Text(
                  '${c.candidateId} • ${c.source} • ${c.experienceYears} yrs • Applied ${recFormatDate(c.appliedDate)}',
                  style: const TextStyle(fontSize: 12, color: kRecMuted),
                ),
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'More actions',
            icon: const Icon(Icons.more_vert_rounded, color: kRecMuted, size: 20),
            onPressed: () => _showActions(c),
          ),
        ],
      ),
    );
  }
}
