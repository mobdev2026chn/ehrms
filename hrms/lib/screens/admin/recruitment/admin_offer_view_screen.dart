// lib/screens/admin/recruitment/admin_offer_view_screen.dart
// A candidate's offer letters: details, compensation, PDF and attachments, revoke.

import 'package:flutter/material.dart';

import '../../../config/app_colors.dart';
import '../../../models/admin_recruitment_models.dart';
import '../../../services/admin_recruitment_service.dart';
import 'admin_send_offer_screen.dart';
import 'rec_widgets.dart';

class AdminOfferViewScreen extends StatefulWidget {
  final String candidateId;
  final String candidateName;
  const AdminOfferViewScreen({super.key, required this.candidateId, this.candidateName = ''});

  @override
  State<AdminOfferViewScreen> createState() => _AdminOfferViewScreenState();
}

class _AdminOfferViewScreenState extends State<AdminOfferViewScreen> {
  final AdminRecruitmentService _service = AdminRecruitmentService();
  bool _loading = true;
  String? _error;
  List<RecIssuedOffer> _offers = [];
  String? _busyId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool showLoader = true}) async {
    if (showLoader) setState(() => _loading = true);
    try {
      final o = await _service.getCandidateOfferLetters(widget.candidateId);
      o.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      if (!mounted) return;
      setState(() {
        _offers = o;
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

  Future<void> _openPdf(RecIssuedOffer o) async {
    setState(() => _busyId = o.id);
    try {
      final path = await _service.downloadOfferLetterPdf(o.id, widget.candidateName.isEmpty ? 'candidate' : widget.candidateName);
      if (mounted) await recOpenLocalFile(context, path);
    } catch (e) {
      if (mounted) recShowError(context, e);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _openAttachment(RecIssuedOffer o, RecOfferAttachment a) async {
    try {
      final url = await _service.getOfferAttachmentUrl(o.id, a.index);
      if (mounted) await recOpenUrl(context, url);
    } catch (e) {
      if (mounted) recShowError(context, e);
    }
  }

  Future<void> _revoke(RecIssuedOffer o) async {
    final ok = await recConfirm(context,
        title: 'Revoke this offer?',
        message: 'The offer is withdrawn. An Offered candidate goes back to Selected, so a new offer can be sent.',
        confirmLabel: 'Revoke',
        destructive: true);
    if (!ok) return;
    setState(() => _busyId = o.id);
    try {
      final msg = await _service.revokeOfferLetter(o.id);
      if (!mounted) return;
      recShowSuccess(context, msg);
      _load(showLoader: false);
    } catch (e) {
      if (mounted) recShowError(context, e);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kRecBg,
      appBar: recAppBar(context, widget.candidateName.isEmpty ? 'Offer Letters' : widget.candidateName,
          onRefresh: () => _load(),
          actions: [
            IconButton(
              tooltip: 'Send new offer',
              icon: const Icon(Icons.send_outlined, size: 22),
              onPressed: () async {
                final sent = await Navigator.push<bool>(
                    context, MaterialPageRoute(builder: (_) => AdminSendOfferScreen(candidateId: widget.candidateId)));
                if (sent == true) _load(showLoader: false);
              },
            ),
          ]),
      body: RecAsyncBody(
        loading: _loading,
        error: _error,
        isEmpty: _offers.isEmpty,
        emptyText: 'No offer letters for this candidate yet.',
        emptyIcon: Icons.mail_outline_rounded,
        onRetry: _load,
        builder: () => RefreshIndicator(
          onRefresh: () => _load(showLoader: false),
          color: AppColors.primary,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: List.generate(_offers.length, (i) => _offerCard(_offers[i], isLatest: i == 0)),
          ),
        ),
      ),
    );
  }

  Widget _offerCard(RecIssuedOffer o, {required bool isLatest}) {
    final busy = _busyId == o.id;
    return RecCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const RecIconTile(Icons.mail_outline_rounded),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(o.designation.isEmpty ? 'Offer letter' : o.designation,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: kRecInk)),
                  const SizedBox(height: 2),
                  Text(o.templateName, style: const TextStyle(fontSize: 12.5, color: kRecMuted)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            RecBadge(o.status),
          ]),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 8),
          RecInfoRow('Annual CTC', recMoney(o.annualCTC)),
          RecInfoRow('Basic salary', recMoney(o.basicSalary)),
          if (o.salaryTemplateTitle.isNotEmpty) RecInfoRow('Salary template', o.salaryTemplateTitle),
          RecInfoRow('Offer date', recFormatDate(o.offerDate)),
          RecInfoRow('Joining date', recFormatDate(o.joiningDate)),
          RecInfoRow('Valid till', recFormatDate(o.validTill)),
          if (o.sentAt.isNotEmpty) RecInfoRow('Sent', '${recFormatDateTime(o.sentAt)}${o.sentTo.isNotEmpty ? ' to ${o.sentTo}' : ''}'),
          if (o.respondedAt.isNotEmpty) RecInfoRow('Answered', recFormatDateTime(o.respondedAt)),
          if (o.responseReason.isNotEmpty) RecInfoRow('Reason', o.responseReason),
          if (o.revokedAt.isNotEmpty) RecInfoRow('Revoked', recFormatDateTime(o.revokedAt)),
          if (o.compensation.isNotEmpty)
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('Compensation breakdown', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: kRecInk)),
                children: [OfferCompensationTable(rows: o.compensation)],
              ),
            ),
          if (o.attachments.where((a) => !a.isLetter).isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text('Attachments', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: kRecInk)),
            ...o.attachments.where((a) => !a.isLetter).map((a) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.attach_file_rounded, size: 20, color: kRecMuted),
                  title: Text(a.fileName, style: const TextStyle(fontSize: 13, color: kRecInk)),
                  trailing: const Icon(Icons.chevron_right_rounded, color: kRecHint),
                  onTap: () => _openAttachment(o, a),
                )),
          ],
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: RecPrimaryButton(
                label: 'Open letter (PDF)',
                icon: Icons.picture_as_pdf_outlined,
                outlined: true,
                busy: busy,
                onPressed: () => _openPdf(o),
              ),
            ),
            if (isLatest && o.status == 'Sent') ...[
              const SizedBox(width: 12),
              Expanded(
                child: RecPrimaryButton(
                  label: 'Revoke',
                  icon: Icons.undo_rounded,
                  outlined: true,
                  destructive: true,
                  onPressed: busy ? null : () => _revoke(o),
                ),
              ),
            ],
          ]),
        ],
      ),
    );
  }
}

/// Compensation rows (section / item / total / net / ctc / spacer) as a compact table.
class OfferCompensationTable extends StatelessWidget {
  final List<RecCompensationRow> rows;
  const OfferCompensationTable({super.key, required this.rows});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 4, left: 6, right: 6),
          child: Row(children: [
            Expanded(flex: 5, child: Text('Component', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: kRecMuted))),
            Expanded(flex: 3, child: Text('Monthly', textAlign: TextAlign.right, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: kRecMuted))),
            Expanded(flex: 3, child: Text('Annual', textAlign: TextAlign.right, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: kRecMuted))),
          ]),
        ),
        ...rows.where((r) => r.kind != 'spacer').map((r) {
          final bold = r.kind == 'section' || r.kind == 'total' || r.kind == 'net' || r.kind == 'ctc';
          final style = TextStyle(fontSize: 12.5, fontWeight: bold ? FontWeight.w600 : FontWeight.w400, color: kRecInk);
          return Container(
            decoration: r.kind == 'ctc'
                ? BoxDecoration(color: AppColors.brandLight, borderRadius: BorderRadius.circular(8))
                : null,
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
            child: Row(children: [
              Expanded(flex: 5, child: Text(r.label, style: style)),
              Expanded(flex: 3, child: Text(r.monthly == null ? '' : recMoney(r.monthly), textAlign: TextAlign.right, style: style)),
              Expanded(flex: 3, child: Text(r.annual == null ? '' : recMoney(r.annual), textAlign: TextAlign.right, style: style)),
            ]),
          );
        }),
      ],
    );
  }
}
