// lib/screens/admin/recruitment/admin_candidate_disposition_screen.dart
// Candidate Disposition: candidates selected but not yet offered, or not moving forward
// (rejected, on hold, blacklisted, offer declined / expired). View only.

import 'package:flutter/material.dart';

import '../../../config/app_colors.dart';
import '../../../models/admin_recruitment_models.dart';
import '../../../services/admin_recruitment_service.dart';
import 'admin_candidate_detail_screen.dart';
import 'rec_widgets.dart';

const Map<String, String> _labels = {
  'selected': 'Selected',
  'rejected': 'Rejected',
  'onHold': 'On Hold',
  'blacklisted': 'Blacklisted',
  'offerDeclined': 'Offer Declined',
  'offerExpired': 'Offer Expired',
};

const Map<String, String> _descriptions = {
  'selected': 'Selected in interview - offer letter not sent yet',
  'rejected': 'Rejected in interview or during verification',
  'onHold': 'Paused in interview or during verification',
  'blacklisted': 'Rejected and blocked from applying again',
  'offerDeclined': 'The candidate turned down the offer',
  'offerExpired': 'The offer lapsed without an answer',
};

String? dispositionOf(RecCandidate c) {
  if (c.verificationStage == 'verificationBlacklist') return 'blacklisted';
  if (c.status == 'Rejected') return 'rejected';
  if (c.status == 'On Hold' || c.verificationStage == 'verificationHold') return 'onHold';
  if (c.status == 'Offer Rejected') return 'offerDeclined';
  if (c.status == 'Offer Expired') return 'offerExpired';
  if (c.status == 'Selected') return 'selected';
  return null;
}

class AdminCandidateDispositionScreen extends StatefulWidget {
  const AdminCandidateDispositionScreen({super.key});

  @override
  State<AdminCandidateDispositionScreen> createState() => _AdminCandidateDispositionScreenState();
}

class _AdminCandidateDispositionScreenState extends State<AdminCandidateDispositionScreen> {
  final AdminRecruitmentService _service = AdminRecruitmentService();
  bool _loading = true;
  String? _error;
  List<RecCandidate> _rows = [];
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
      final list = await _service.getCandidates();
      final rows = list.where((c) => dispositionOf(c) != null).toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
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
    final counts = <String, int>{'All': _rows.length};
    for (final k in _labels.keys) {
      counts[k] = _rows.where((c) => dispositionOf(c) == k).length;
    }
    final q = _search.toLowerCase();
    final visible = _rows.where((c) {
      if (_filter != 'All' && dispositionOf(c) != _filter) return false;
      return q.isEmpty ||
          c.fullName.toLowerCase().contains(q) ||
          c.email.toLowerCase().contains(q) ||
          c.displayJob.toLowerCase().contains(q) ||
          c.primarySkill.toLowerCase().contains(q);
    }).toList();

    return Scaffold(
      backgroundColor: kRecBg,
      appBar: recAppBar(context, 'Candidate Disposition', onRefresh: () => _load()),
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
              RecSearchField(hint: 'Search name, email, job or skill', onChanged: (v) => setState(() => _search = v)),
              const SizedBox(height: 12),
              RecFilterChips(
                options: ['All', ..._labels.keys],
                selected: _filter,
                counts: counts,
                labelOf: (k) => k == 'All' ? 'All' : _labels[k]!,
                onSelected: (k) => setState(() => _filter = k),
              ),
              if (_filter != 'All')
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Row(children: [
                    const Icon(Icons.info_outline_rounded, size: 16, color: kRecMuted),
                    const SizedBox(width: 6),
                    Expanded(child: Text(_descriptions[_filter]!, style: const TextStyle(fontSize: 12.5, color: kRecMuted))),
                  ]),
                ),
              const SizedBox(height: 16),
              if (visible.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 60),
                  child: RecEmptyState(text: 'No candidates in this disposition'),
                )
              else
                ...visible.map((c) {
                  final d = dispositionOf(c)!;
                  return RecCard(
                    onTap: () => Navigator.push(
                        context, MaterialPageRoute(builder: (_) => AdminCandidateDetailScreen(candidateId: c.id))),
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
                                RecBadge(_labels[d]!, colorKey: d == 'selected' ? 'selected' : (d == 'onHold' ? 'on hold' : (d.startsWith('offer') ? 'offer expired' : 'rejected'))),
                              ]),
                              const SizedBox(height: 2),
                              Text(c.displayJob, style: const TextStyle(fontSize: 13, color: kRecMuted, fontWeight: FontWeight.w500)),
                              const SizedBox(height: 4),
                              Text('Status: ${c.status} • Updated ${recFormatDate(c.updatedAt)}',
                                  style: const TextStyle(fontSize: 12.5, color: kRecMuted)),
                              if (c.verificationStageReason.isNotEmpty)
                                Container(
                                  margin: const EdgeInsets.only(top: 8),
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  decoration: BoxDecoration(color: kRecBg, borderRadius: BorderRadius.circular(10)),
                                  child: Text('Reason: ${c.verificationStageReason}',
                                      style: const TextStyle(fontSize: 12.5, color: kRecInk)),
                                ),
                            ],
                          ),
                        ),
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
