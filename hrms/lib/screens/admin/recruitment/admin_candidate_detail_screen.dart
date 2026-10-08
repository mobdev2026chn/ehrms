// lib/screens/admin/recruitment/admin_candidate_detail_screen.dart
// Candidate profile: details, resume, interview rounds, offer letters and activity log, with
// edit / status / schedule interview / send offer / delete.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../../config/app_colors.dart';
import '../../../models/admin_recruitment_models.dart';
import '../../../services/admin_recruitment_service.dart';
import 'admin_candidate_form_screen.dart';
import 'admin_candidate_scorecard_screen.dart';
import 'admin_candidates_screen.dart' show changeCandidateStatus, deleteCandidateWithConfirm;
import 'admin_offer_view_screen.dart';
import 'admin_schedule_interview_sheet.dart';
import 'admin_send_offer_screen.dart';
import 'rec_widgets.dart';

class AdminCandidateDetailScreen extends StatefulWidget {
  final String candidateId;
  const AdminCandidateDetailScreen({super.key, required this.candidateId});

  @override
  State<AdminCandidateDetailScreen> createState() => _AdminCandidateDetailScreenState();
}

class _AdminCandidateDetailScreenState extends State<AdminCandidateDetailScreen> {
  final AdminRecruitmentService _service = AdminRecruitmentService();

  RecCandidate? _c;
  List<RecInterviewRound> _rounds = [];
  List<RecIssuedOffer> _offers = [];
  String? _roundsError;
  String? _offersError;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool showLoader = true}) async {
    if (showLoader) setState(() => _loading = true);
    try {
      final c = await _service.getCandidate(widget.candidateId);
      if (!mounted) return;
      setState(() {
        _c = c;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
      return;
    }
    _loadRounds();
    _loadOffers();
  }

  Future<void> _loadRounds() async {
    try {
      final r = await _service.getInterviewRounds(candidateId: widget.candidateId);
      r.sort((a, b) => a.roundNumber.compareTo(b.roundNumber));
      if (!mounted) return;
      setState(() {
        _rounds = r;
        _roundsError = null;
      });
    } catch (e) {
      if (mounted) setState(() => _roundsError = e.toString());
    }
  }

  Future<void> _loadOffers() async {
    try {
      final o = await _service.getCandidateOfferLetters(widget.candidateId);
      if (!mounted) return;
      setState(() {
        _offers = o;
        _offersError = null;
      });
    } catch (e) {
      if (mounted) setState(() => _offersError = e.toString());
    }
  }

  Future<void> _openResume(RecCandidate c) async {
    final url = c.resumeUrl;
    if (url.startsWith('data:')) {
      try {
        final comma = url.indexOf(',');
        final bytes = base64Decode(url.substring(comma + 1));
        final dir = await getTemporaryDirectory();
        final name = c.resumeName.isEmpty ? 'resume_${c.id}.pdf' : c.resumeName.replaceAll(RegExp(r'[\\/]'), '_');
        final file = File('${dir.path}/$name');
        await file.writeAsBytes(bytes, flush: true);
        if (mounted) await recOpenLocalFile(context, file.path);
      } catch (e) {
        if (mounted) recShowError(context, 'Could not open the resume');
      }
    } else {
      await recOpenUrl(context, url);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    return Scaffold(
      backgroundColor: kRecBg,
      appBar: recAppBar(context, 'Candidate', onRefresh: () => _load(), actions: [
        if (c != null)
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 22),
            tooltip: 'Edit',
            onPressed: () async {
              final saved = await Navigator.push<bool>(
                  context, MaterialPageRoute(builder: (_) => AdminCandidateFormScreen(candidate: c)));
              if (saved == true) _load(showLoader: false);
            },
          ),
      ]),
      body: RecAsyncBody(
        loading: _loading,
        error: _error,
        isEmpty: c == null,
        emptyText: 'Candidate not found',
        onRetry: _load,
        builder: () => RefreshIndicator(
          onRefresh: () => _load(showLoader: false),
          color: AppColors.primary,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _header(c!),
              _profile(c),
              if (c.education.isNotEmpty) _education(c),
              if (c.experience.isNotEmpty) _experience(c),
              _roundsCard(c),
              _offersCard(c),
              _logs(c),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(RecCandidate c) {
    final canOffer = c.status == 'Selected';
    return RecCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            RecAvatar(c.fullName, size: 48),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c.fullName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: kRecInk)),
                  const SizedBox(height: 2),
                  Text(c.displayJob, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: kRecMuted)),
                  const SizedBox(height: 8),
                  Wrap(spacing: 6, runSpacing: 4, children: [
                    RecBadge(c.status),
                    if (c.verificationStage != 'pending')
                      RecBadge(kVerificationStageLabels[c.verificationStage] ?? c.verificationStage),
                  ]),
                ],
              ),
            ),
          ]),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _chipButton('Status', Icons.label_outline_rounded, () async {
                if (await changeCandidateStatus(context, c)) _load(showLoader: false);
              }),
              _chipButton('Schedule interview', Icons.event_available_outlined, () async {
                if (await showScheduleInterviewSheet(context, candidate: c)) _load(showLoader: false);
              }),
              if (canOffer)
                _chipButton('Send offer', Icons.mail_outline_rounded, () async {
                  final sent = await Navigator.push<bool>(
                      context, MaterialPageRoute(builder: (_) => AdminSendOfferScreen(candidateId: c.id)));
                  if (sent == true) _load(showLoader: false);
                }),
              if (c.resumeUrl.isNotEmpty) _chipButton('Resume', Icons.description_outlined, () => _openResume(c)),
              _chipButton('Delete', Icons.delete_outline_rounded, () async {
                if (await deleteCandidateWithConfirm(context, c) && mounted) Navigator.pop(context, true);
              }, destructive: true),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chipButton(String label, IconData icon, VoidCallback onTap, {bool destructive = false}) {
    return ActionChip(
      avatar: Icon(icon, size: 18, color: destructive ? AppColors.error : kRecInk),
      label: Text(label,
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: destructive ? AppColors.error : kRecInk)),
      onPressed: onTap,
      backgroundColor: destructive ? AppColors.errorBg : AppColors.surface,
      side: BorderSide(color: destructive ? AppColors.errorBg : kRecBorder),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
    );
  }

  Widget _profile(RecCandidate c) => RecCard(
        child: Column(children: [
          const RecSectionTitle('Profile'),
          RecInfoRow('Candidate ID', c.candidateId),
          RecInfoRow('Email', c.email),
          RecInfoRow('Phone', c.phone),
          RecInfoRow('Date of birth', recFormatDate(c.dob)),
          RecInfoRow('Gender', c.gender),
          RecInfoRow('Current city', c.currentCity),
          RecInfoRow('Preferred location', c.preferredJobLocation),
          RecInfoRow('Primary skill', c.primarySkill),
          RecInfoRow('Experience', '${c.experienceYears} years'),
          RecInfoRow('Source', c.source),
          RecInfoRow('Applied', recFormatDate(c.appliedDate)),
          if (c.verificationStageReason.isNotEmpty) RecInfoRow('Verification note', c.verificationStageReason),
        ]),
      );

  Widget _education(RecCandidate c) => RecCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const RecSectionTitle('Education'),
            ...c.education.map((e) => _bullet(
                  '${e['qualification'] ?? ''} ${e['courseName'] ?? ''}'.trim(),
                  [e['institution'], e['university'], e['yearOfPassing'],
                    (e['cgpa'] ?? '').toString().isNotEmpty ? 'CGPA ${e['cgpa']}' : ((e['percentage'] ?? '').toString().isNotEmpty ? '${e['percentage']}%' : null)]
                      .where((x) => x != null && x.toString().isNotEmpty)
                      .join(' • '),
                )),
          ],
        ),
      );

  Widget _experience(RecCandidate c) => RecCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const RecSectionTitle('Work experience'),
            ...c.experience.map((e) => _bullet(
                  '${e['role'] ?? ''} at ${e['company'] ?? ''}',
                  '${e['durationFrom'] ?? ''} - ${(e['durationTo'] ?? '').toString().isEmpty ? 'Present' : e['durationTo']}'
                  '${(e['keyResponsibilities'] ?? '').toString().isNotEmpty ? '\n${e['keyResponsibilities']}' : ''}',
                )),
          ],
        ),
      );

  Widget _bullet(String title, String sub) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: kRecInk)),
            const SizedBox(height: 2),
            Text(sub, style: const TextStyle(fontSize: 12.5, color: kRecMuted, height: 1.4)),
          ],
        ),
      );

  Widget _roundsCard(RecCandidate c) => RecCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const RecSectionTitle('Interview rounds'),
            if (_roundsError != null)
              Row(children: [
                Expanded(child: Text(_roundsError!, style: const TextStyle(fontSize: 12, color: AppColors.error))),
                TextButton(onPressed: _loadRounds, child: const Text('Retry')),
              ])
            else if (_rounds.isEmpty)
              const Text('No interviews scheduled yet.', style: TextStyle(fontSize: 12.5, color: kRecMuted))
            else
              ..._rounds.map((r) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text('Round ${r.roundNumber}: ${r.roundName}',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: kRecInk)),
                    subtitle: Text('${recFormatDate(r.interviewDate)} ${recFormatTime(r.interviewTime)} • ${r.mode} • ${r.interviewerName}',
                        style: const TextStyle(fontSize: 12, color: kRecMuted)),
                    trailing: RecBadge(r.displayStatus),
                    onTap: () async {
                      await Navigator.push(
                          context, MaterialPageRoute(builder: (_) => AdminCandidateScorecardScreen(roundId: r.id)));
                      _load(showLoader: false);
                    },
                  )),
          ],
        ),
      );

  Widget _offersCard(RecCandidate c) => RecCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RecSectionTitle('Offer letters',
                trailing: _offers.isEmpty
                    ? null
                    : TextButton(
                        onPressed: () async {
                          await Navigator.push(context,
                              MaterialPageRoute(builder: (_) => AdminOfferViewScreen(candidateId: c.id, candidateName: c.fullName)));
                          _load(showLoader: false);
                        },
                        child: const Text('Manage')),
            ),
            if (_offersError != null)
              Row(children: [
                Expanded(child: Text(_offersError!, style: const TextStyle(fontSize: 12, color: AppColors.error))),
                TextButton(onPressed: _loadOffers, child: const Text('Retry')),
              ])
            else if (_offers.isEmpty)
              const Text('No offer letters yet.', style: TextStyle(fontSize: 12.5, color: kRecMuted))
            else
              ..._offers.map((o) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(o.designation.isEmpty ? o.templateName : o.designation,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: kRecInk)),
                    subtitle: Text('CTC ${recMoney(o.annualCTC)} • ${recFormatDate(o.sentAt.isEmpty ? o.createdAt : o.sentAt)}',
                        style: const TextStyle(fontSize: 12, color: kRecMuted)),
                    trailing: RecBadge(o.status),
                  )),
          ],
        ),
      );

  Widget _logs(RecCandidate c) => RecCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const RecSectionTitle('Activity log'),
            if (c.logs.isEmpty)
              const Text('No activity recorded.', style: TextStyle(fontSize: 12.5, color: kRecMuted))
            else
              ...c.logs.map((l) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          margin: const EdgeInsets.only(top: 5),
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(color: AppColors.brand, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(l.message, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: kRecInk)),
                              const SizedBox(height: 2),
                              Text('${recFormatDateTime(l.at)}${l.actorName.isNotEmpty ? ' • ${l.actorName}' : ''}',
                                  style: const TextStyle(fontSize: 12, color: kRecMuted)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  )),
          ],
        ),
      );
}
