// lib/screens/admin/recruitment/admin_offer_letter_screen.dart
// Offer Letter: candidates at the offer stage (Offered / Accepted / Rejected / Expired / Hired /
// Revoked) with view, accept/reject marking, new offer; plus the letter templates tab.

import 'package:flutter/material.dart';

import '../../../config/app_colors.dart';
import '../../../models/admin_recruitment_models.dart';
import '../../../services/admin_recruitment_service.dart';
import '../../../widgets/app_drawer.dart';
import 'admin_offer_templates_screen.dart';
import 'admin_offer_view_screen.dart';
import 'admin_send_offer_screen.dart';
import 'rec_widgets.dart';

const List<String> _offerStatuses = ['Offered', 'Offer Accepted', 'Offer Rejected', 'Offer Expired', 'Hired', 'Revoked'];
const Map<String, String> _offerLabels = {
  'Offered': 'Offered',
  'Offer Accepted': 'Accepted',
  'Offer Rejected': 'Rejected',
  'Offer Expired': 'Expired',
  'Hired': 'Hired',
  'Revoked': 'Revoked',
};

class AdminOfferLetterScreen extends StatefulWidget {
  const AdminOfferLetterScreen({super.key});

  @override
  State<AdminOfferLetterScreen> createState() => _AdminOfferLetterScreenState();
}

class _AdminOfferLetterScreenState extends State<AdminOfferLetterScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: kRecBg,
        drawer: const AppDrawer(),
        appBar: recAppBar(
          context,
          'Offer Letters',
          drawerKey: _scaffoldKey,
          bottom: const TabBar(
            tabs: [Tab(text: 'Offers'), Tab(text: 'Templates')],
          ),
        ),
        body: const TabBarView(children: [_OffersTab(), AdminOfferTemplatesView()]),
      ),
    );
  }
}

class _OffersTab extends StatefulWidget {
  const _OffersTab();
  @override
  State<_OffersTab> createState() => _OffersTabState();
}

class _OffersTabState extends State<_OffersTab> with AutomaticKeepAliveClientMixin {
  final AdminRecruitmentService _service = AdminRecruitmentService();

  bool _loading = true;
  String? _error;
  List<RecCandidate> _all = [];
  Set<String> _revoked = {};
  Set<String> _sent = {};
  String _filter = 'All';
  String _search = '';

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool showLoader = true}) async {
    if (showLoader) setState(() => _loading = true);
    try {
      final cF = _service.getCandidates();
      final sF = _service.getSentOfferCandidates();
      final candidates = await cF;
      final sent = await sF;
      if (!mounted) return;
      setState(() {
        _all = candidates;
        _revoked = sent.where((s) => s.latestStatus == 'Revoked').map((s) => s.candidateId).toSet();
        _sent = sent.map((s) => s.candidateId).toSet();
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

  String _rowStatus(RecCandidate c) => _revoked.contains(c.id) ? 'Revoked' : c.status;

  List<RecCandidate> get _offerRows => _all
      .where((c) => _offerStatuses.contains(c.status) || (_revoked.contains(c.id) && c.status == 'Selected'))
      .toList()
    ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  bool _matches(String rowStatus, String filter) =>
      rowStatus == filter || (filter == 'Offer Accepted' && rowStatus == 'Hired');

  Future<void> _newOffer() async {
    final ready = _all.where((c) => c.status == 'Selected' && !_sent.contains(c.id)).toList();
    if (ready.isEmpty) {
      recShowError(context, 'No selected candidates are waiting for an offer.');
      return;
    }
    final id = await recShowActions(
      context,
      title: 'Send offer to',
      actions: ready.map((c) => RecAction(c.id, '${c.fullName} - ${c.displayJob}', Icons.person_outline_rounded)).toList(),
    );
    if (id == null || !mounted) return;
    final sent = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => AdminSendOfferScreen(candidateId: id)));
    if (sent == true) _load(showLoader: false);
  }

  Future<void> _actions(RecCandidate c) async {
    final status = _rowStatus(c);
    final a = await recShowActions(context, title: c.fullName, actions: [
      const RecAction('view', 'View offer letters', Icons.description_outlined),
      if (status == 'Offered') const RecAction('accept', 'Mark offer accepted', Icons.thumb_up_alt_outlined),
      if (status == 'Offered') const RecAction('reject', 'Mark offer rejected', Icons.thumb_down_alt_outlined, destructive: true),
      if (status == 'Revoked' || status == 'Offer Expired' || status == 'Offer Rejected')
        const RecAction('send', 'Send a new offer', Icons.send_rounded),
    ]);
    if (!mounted || a == null) return;
    switch (a) {
      case 'view':
        await Navigator.push(
            context, MaterialPageRoute(builder: (_) => AdminOfferViewScreen(candidateId: c.id, candidateName: c.fullName)));
        _load(showLoader: false);
        break;
      case 'send':
        final sent = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => AdminSendOfferScreen(candidateId: c.id)));
        if (sent == true) _load(showLoader: false);
        break;
      case 'accept':
      case 'reject':
        final newStatus = a == 'accept' ? 'Offer Accepted' : 'Offer Rejected';
        final ok = await recConfirm(context,
            title: a == 'accept' ? 'Mark offer accepted?' : 'Mark offer rejected?',
            message: 'Record that ${c.fullName} ${a == 'accept' ? 'accepted' : 'rejected'} the offer.',
            confirmLabel: a == 'accept' ? 'Yes, accepted' : 'Yes, rejected',
            destructive: a == 'reject');
        if (!ok) return;
        try {
          final msg = await _service.updateCandidateStatus(c.id, newStatus);
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
    super.build(context);
    final rows = _offerRows;
    final counts = <String, int>{'All': rows.length};
    for (final s in _offerStatuses) {
      counts[s] = rows.where((c) => _matches(_rowStatus(c), s)).length;
    }
    final q = _search.toLowerCase();
    final visible = rows.where((c) {
      if (_filter != 'All' && !_matches(_rowStatus(c), _filter)) return false;
      return q.isEmpty || c.fullName.toLowerCase().contains(q) || c.email.toLowerCase().contains(q) || c.displayJob.toLowerCase().contains(q);
    }).toList();

    return Scaffold(
      backgroundColor: kRecBg,
      floatingActionButton: _loading || _error != null
          ? null
          : FloatingActionButton.extended(
              heroTag: 'offer_send',
              onPressed: _newOffer,
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.onPrimary,
              icon: const Icon(Icons.send_rounded),
              label: const Text('Send Offer', style: TextStyle(fontWeight: FontWeight.w700)),
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
              RecSearchField(hint: 'Search name, email or job', onChanged: (v) => setState(() => _search = v)),
              const SizedBox(height: 12),
              RecFilterChips(
                options: const ['All', ..._offerStatuses],
                selected: _filter,
                counts: counts,
                labelOf: (s) => s == 'All' ? 'All' : _offerLabels[s]!,
                onSelected: (s) => setState(() => _filter = s),
              ),
              const SizedBox(height: 12),
              if (visible.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 60),
                  child: RecEmptyState(text: 'No offers yet.\nSend one to a selected candidate.', icon: Icons.mail_outline_rounded),
                )
              else
                ...visible.map((c) {
                  final status = _rowStatus(c);
                  return RecCard(
                    onTap: () => _actions(c),
                    child: Row(children: [
                      RecAvatar(c.fullName),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(c.fullName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: kRecInk)),
                            const SizedBox(height: 2),
                            Text(c.displayJob, style: const TextStyle(fontSize: 13, color: kRecMuted, fontWeight: FontWeight.w500)),
                            const SizedBox(height: 2),
                            Text('${c.email} • Updated ${recFormatDate(c.updatedAt)}',
                                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: kRecMuted)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      RecBadge(_offerLabels[status] ?? status, colorKey: status),
                    ]),
                  );
                }),
            ],
          ),
        ),
      ),
    );
  }
}
