// lib/screens/admin/recruitment/admin_verification_detail_screen.dart
// One candidate's onboarding documents: checklist with upload / view / verify / reject /
// remove, request extra documents, submit for verification, save verification, skip,
// verification decision (hold / reject / blacklist), lift blacklist, convert to staff.

import 'package:flutter/material.dart';

import '../../../config/app_colors.dart';
import '../../../models/admin_recruitment_models.dart';
import '../../../services/admin_recruitment_service.dart';
import 'admin_convert_to_staff_screen.dart';
import 'rec_widgets.dart';

class AdminVerificationDetailScreen extends StatefulWidget {
  final String candidateId;
  const AdminVerificationDetailScreen({super.key, required this.candidateId});

  @override
  State<AdminVerificationDetailScreen> createState() => _AdminVerificationDetailScreenState();
}

class _AdminVerificationDetailScreenState extends State<AdminVerificationDetailScreen> {
  final AdminRecruitmentService _service = AdminRecruitmentService();
  RecCandidateDocuments? _d;
  bool _loading = true;
  String? _error;
  String? _busy;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool showLoader = true}) async {
    if (showLoader) setState(() => _loading = true);
    try {
      final d = await _service.getCandidateDocuments(widget.candidateId);
      if (!mounted) return;
      setState(() {
        _d = d;
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

  Future<void> _run(String key, Future<String> Function() op) async {
    setState(() => _busy = key);
    try {
      final msg = await op();
      if (!mounted) return;
      recShowSuccess(context, msg);
      await _load(showLoader: false);
    } catch (e) {
      if (mounted) recShowError(context, e);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  String get _stage => _d?.c('verificationStage').isNotEmpty == true ? _d!.c('verificationStage') : 'pending';
  bool get _converted => _stage == 'converted' || (_d?.c('staffId').isNotEmpty ?? false);
  bool get _closed => _stage == 'verificationReject' || _stage == 'verificationBlacklist';

  Future<void> _upload(RecChecklistItem? item) async {
    String? customName;
    if (item == null) {
      customName = await recPromptText(context,
          title: 'Add a document', label: 'Document name (e.g. Passport)', confirmLabel: 'Choose file');
      if (customName == null || !mounted) return;
    }
    final f = await recPickFile(context, const ['pdf', 'jpg', 'jpeg', 'png']);
    if (f == null || !mounted) return;
    await _run('upload:${item?.documentType ?? customName}', () => _service.uploadCandidateDocument(
          widget.candidateId,
          documentType: item?.documentType,
          documentName: item == null ? customName : null,
          fileName: f.name,
          bytes: f.bytes,
          mimeType: f.mimeType,
        ));
  }

  Future<void> _view(RecDocument doc) async {
    setState(() => _busy = 'view:${doc.id}');
    try {
      final url = await _service.getDocumentViewUrl(doc.id);
      if (mounted) await recOpenUrl(context, url);
    } catch (e) {
      if (mounted) recShowError(context, e);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _reject(RecDocument doc) async {
    final reason = await recPromptText(context,
        title: 'Reject document', label: 'Reason *', maxLines: 3, confirmLabel: 'Reject',
        message: 'The candidate is asked to upload it again.');
    if (reason == null) return;
    await _run('reject:${doc.id}', () => _service.rejectDocument(doc.id, reason));
  }

  Future<void> _remove(RecDocument doc) async {
    final ok = await recConfirm(context,
        title: 'Remove upload?',
        message: '${doc.fileName} is deleted and the item goes back to Not Submitted.',
        confirmLabel: 'Remove',
        destructive: true);
    if (ok) await _run('remove:${doc.id}', () => _service.deleteDocument(doc.id));
  }

  Future<void> _request() async {
    final name = TextEditingController();
    final note = TextEditingController();
    final key = GlobalKey<FormState>();
    final ok = await recShowSheet<bool>(
      context,
      title: 'Request a document',
      builder: (ctx) => Form(
        key: key,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text('The candidate uploads it from the candidate portal.', style: TextStyle(fontSize: 12.5, color: kRecMuted)),
            ),
            RecTextField(controller: name, label: 'Document name * (max 60)', validator: (v) {
              if (recRequired(v) != null) return 'Required';
              return v!.trim().length > 60 ? 'Too long' : null;
            }),
            RecTextField(controller: note, label: 'Note for the candidate (optional)', maxLines: 3),
            RecPrimaryButton(
              label: 'Request',
              icon: Icons.send_outlined,
              onPressed: () {
                if (key.currentState?.validate() ?? false) Navigator.pop(ctx, true);
              },
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      await _run('request', () => _service.requestCandidateDocument(widget.candidateId,
          documentName: name.text.trim(), note: note.text.trim()));
    }
  }

  Future<void> _decide(String stage) async {
    final needsReason = stage != 'verificationHold';
    final label = {'verificationHold': 'Put on hold', 'verificationReject': 'Reject', 'verificationBlacklist': 'Blacklist'}[stage]!;
    final reason = await recPromptText(
      context,
      title: label,
      label: needsReason ? 'Reason *' : 'Reason (optional)',
      required: needsReason,
      maxLines: 3,
      confirmLabel: label,
      message: stage == 'verificationBlacklist'
          ? 'The candidate is rejected and cannot be added or apply again until the blacklist is lifted.'
          : stage == 'verificationReject'
              ? 'The candidate is rejected and cannot be converted to staff.'
              : 'The candidate stays in verification, on hold.',
    );
    if (reason == null) return;
    await _run('stage', () => _service.setVerificationStage(widget.candidateId, stage, reason: reason));
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    return Scaffold(
      backgroundColor: kRecBg,
      appBar: recAppBar(context, 'Document Verification', onRefresh: () => _load()),
      body: RecAsyncBody(
        loading: _loading,
        error: _error,
        isEmpty: d == null,
        emptyText: 'Candidate not found',
        onRetry: _load,
        builder: () => RefreshIndicator(
          onRefresh: () => _load(showLoader: false),
          color: AppColors.primary,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_busy != null) const LinearProgressIndicator(minHeight: 2),
              _header(d!),
              _summary(d),
              RecSectionTitle('Documents (${d.checklist.length})',
                  trailing: _converted || _closed
                      ? null
                      : PopupMenuButton<String>(
                          tooltip: 'Add document',
                          icon: const Icon(Icons.add_circle_outline_rounded, color: AppColors.brandDark),
                          onSelected: (v) => v == 'add' ? _upload(null) : _request(),
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'add', child: Text('Upload an extra document')),
                            PopupMenuItem(value: 'request', child: Text('Request from candidate')),
                          ],
                        )),
              ...d.checklist.map(_item),
              _actions(d),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(RecCandidateDocuments d) {
    return RecCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            RecAvatar(d.fullName, size: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(d.fullName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: kRecInk)),
                  const SizedBox(height: 2),
                  Text('${d.c('position')}${d.c('department').isNotEmpty ? ' • ${d.c('department')}' : ''}',
                      style: const TextStyle(fontSize: 13, color: kRecMuted, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 2),
                  Text('${d.c('email')} • ${d.c('phone')}', style: const TextStyle(fontSize: 12.5, color: kRecMuted)),
                ],
              ),
            ),
          ]),
          const SizedBox(height: 12),
          Wrap(spacing: 6, runSpacing: 6, children: [
            RecBadge(d.c('status')),
            RecBadge(kVerificationStageLabels[_stage] ?? _stage),
            if (d.c('documentsSkippedAt').isNotEmpty) const RecBadge('Docs Skipped', colorKey: 'skipped'),
            if (d.c('documentsSavedAt').isNotEmpty) const RecBadge('Verification saved', colorKey: 'verified'),
          ]),
          if (d.c('verificationStageReason').isNotEmpty)
            RecNotice('Reason: ${d.c('verificationStageReason')}',
              margin: const EdgeInsets.only(top: 12)),
          if (d.c('documentsSkipReason').isNotEmpty)
            Text('Skip reason: ${d.c('documentsSkipReason')}', style: const TextStyle(fontSize: 12.5, color: kRecMuted)),
        ],
      ),
    );
  }

  Widget _summary(RecCandidateDocuments d) {
    final s = d.summary;
    Widget cell(String label, int v, Color c) => Expanded(
          child: Column(children: [
            Text('$v', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: c)),
            const SizedBox(height: 2),
            Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500, color: kRecMuted)),
          ]),
        );
    return RecCard(
      child: Row(children: [
        cell('Verified', s.verified, AppColors.success),
        cell('To review', s.pendingReview, AppColors.brandDark),
        cell('Rejected', s.rejected, AppColors.error),
        cell('Missing', s.notSubmitted, kRecMuted),
        cell('Extra', s.additional, AppColors.info),
      ]),
    );
  }

  Widget _item(RecChecklistItem item) {
    final doc = item.document;
    final status = doc?.status ?? 'Not Submitted';
    final locked = _converted || _closed;
    final busyHere = _busy != null && (_busy!.endsWith(item.documentType) || (doc != null && _busy!.endsWith(doc.id)));
    return RecCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.name, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: kRecInk)),
                  if (item.description.isNotEmpty)
                    Text(item.description, style: const TextStyle(fontSize: 12.5, color: kRecMuted)),
                  if (item.isRequested) const Text('Requested from the candidate', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.info)),
                  if (item.isAdditional && !item.isRequested)
                    const Text('Extra document', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.info)),
                ],
              ),
            ),
            busyHere
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : RecBadge(status),
          ]),
          if (doc != null) ...[
            const SizedBox(height: 8),
            Text('${doc.fileName} • ${(doc.fileSize / 1024).ceil()} KB • ${recFormatDate(doc.uploadedAt)}',
                style: const TextStyle(fontSize: 12.5, color: kRecMuted)),
            if (doc.rejectReason.isNotEmpty && doc.status == 'Rejected')
              Text('Rejected: ${doc.rejectReason}', style: const TextStyle(fontSize: 12.5, color: AppColors.error)),
          ],
          const SizedBox(height: 8),
          Wrap(spacing: 4, runSpacing: 4, children: [
            if (doc != null)
              TextButton.icon(
                onPressed: _busy != null ? null : () => _view(doc),
                icon: const Icon(Icons.visibility_outlined, size: 18),
                label: const Text('View'),
              ),
            if (doc != null && doc.status != 'Verified' && !locked)
              TextButton.icon(
                onPressed: _busy != null ? null : () => _run('verify:${doc.id}', () => _service.verifyDocument(doc.id)),
                icon: const Icon(Icons.check_circle_outline_rounded, size: 18, color: AppColors.success),
                label: const Text('Verify', style: TextStyle(color: AppColors.success)),
              ),
            if (doc != null && doc.status != 'Rejected' && !locked)
              TextButton.icon(
                onPressed: _busy != null ? null : () => _reject(doc),
                icon: const Icon(Icons.cancel_outlined, size: 18, color: AppColors.error),
                label: const Text('Reject', style: TextStyle(color: AppColors.error)),
              ),
            if ((doc == null || doc.status == 'Rejected') && !locked)
              TextButton.icon(
                onPressed: _busy != null ? null : () => _upload(item),
                icon: const Icon(Icons.upload_file_rounded, size: 18),
                label: Text(doc == null ? 'Upload' : 'Upload again'),
              ),
            if (doc != null && !locked)
              TextButton.icon(
                onPressed: _busy != null ? null : () => _remove(doc),
                icon: const Icon(Icons.delete_outline_rounded, size: 18, color: kRecMuted),
                label: const Text('Remove', style: TextStyle(color: kRecMuted)),
              ),
            if (item.isRequested && doc == null && !locked)
              TextButton.icon(
                onPressed: _busy != null
                    ? null
                    : () async {
                        final ok = await recConfirm(context,
                            title: 'Cancel request?', message: 'Stop asking the candidate for ${item.name}.', confirmLabel: 'Cancel request');
                        if (ok) await _run('cancel:${item.documentType}', () => _service.cancelDocumentRequest(widget.candidateId, item.documentType));
                      },
                icon: const Icon(Icons.block_rounded, size: 18, color: kRecMuted),
                label: const Text('Cancel request', style: TextStyle(color: kRecMuted)),
              ),
          ]),
        ],
      ),
    );
  }

  Widget _actions(RecCandidateDocuments d) {
    final s = d.summary;
    final skipped = d.c('documentsSkippedAt').isNotEmpty;
    final saved = d.c('documentsSavedAt').isNotEmpty;
    final submitted = d.c('documentsSubmittedAt').isNotEmpty;
    final busy = _busy != null;
    final canConvert = !_closed && (_converted || ((saved || skipped) && d.c('status') == 'Offer Accepted'));
    return RecCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const RecSectionTitle('Actions'),
          if (_converted)
            const RecNotice('This candidate has been converted to staff.',
                color: AppColors.success, background: AppColors.successBg, icon: Icons.check_circle_outline_rounded),
          if (!_converted && !_closed && !skipped && !submitted && !saved) ...[
            RecPrimaryButton(
              label: 'Next: send for verification',
              icon: Icons.arrow_forward_rounded,
              busy: _busy == 'submit',
              onPressed: busy || !s.allSubmitted
                  ? null
                  : () => _run('submit', () => _service.submitDocumentsForVerification(widget.candidateId)),
            ),
            if (!s.allSubmitted)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('Add every document (including requested or rejected ones) first.',
                    style: TextStyle(fontSize: 12.5, color: kRecMuted)),
              ),
            const SizedBox(height: 12),
          ],
          if (!_converted && !_closed && !skipped && !saved) ...[
            RecPrimaryButton(
              label: 'Save verification',
              icon: Icons.verified_outlined,
              outlined: !s.readyToSave,
              busy: _busy == 'save',
              onPressed: busy || !s.readyToSave
                  ? null
                  : () => _run('save', () => _service.saveDocumentVerification(widget.candidateId)),
            ),
            if (!s.readyToSave)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('Approve every document to save the verification.', style: TextStyle(fontSize: 12.5, color: kRecMuted)),
              ),
            const SizedBox(height: 12),
          ],
          if (canConvert)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: RecPrimaryButton(
                label: _converted ? 'View conversion' : 'Convert to staff',
                icon: Icons.badge_outlined,
                onPressed: () async {
                  await Navigator.push(
                      context, MaterialPageRoute(builder: (_) => AdminConvertToStaffScreen(candidateId: widget.candidateId)));
                  _load(showLoader: false);
                },
              ),
            ),
          if (!_converted && !_closed)
            RecPrimaryButton(
              label: skipped ? 'Undo skip - collect documents' : 'Skip documents',
              icon: skipped ? Icons.undo_rounded : Icons.skip_next_rounded,
              outlined: true,
              busy: _busy == 'skip',
              onPressed: busy
                  ? null
                  : () async {
                      if (skipped) {
                        await _run('skip', () => _service.undoSkipDocuments(widget.candidateId));
                        return;
                      }
                      final reason = await recPromptText(context,
                          title: 'Skip documents',
                          label: 'Reason (optional)',
                          required: false,
                          maxLines: 3,
                          confirmLabel: 'Skip',
                          message: 'Document collection and verification are skipped; the candidate can go straight to Convert to Staff.');
                      if (reason != null) await _run('skip', () => _service.skipDocuments(widget.candidateId, reason: reason));
                    },
            ),
          if (!_converted) ...[
            const Divider(height: 32),
            const Text('Verification decision', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: kRecInk)),
            const SizedBox(height: 12),
            if (_stage == 'verificationBlacklist')
              RecPrimaryButton(
                label: 'Lift blacklist',
                icon: Icons.lock_open_rounded,
                outlined: true,
                busy: _busy == 'lift',
                onPressed: busy
                    ? null
                    : () async {
                        final ok = await recConfirm(context,
                            title: 'Lift blacklist?',
                            message: 'The person may be added or apply again. This record stays rejected.',
                            confirmLabel: 'Lift');
                        if (ok) await _run('lift', () => _service.liftBlacklist(widget.candidateId));
                      },
              )
            else
              Wrap(spacing: 8, runSpacing: 8, children: [
                if (_stage != 'verificationHold' && _stage != 'verificationReject')
                  OutlinedButton.icon(
                    onPressed: busy ? null : () => _decide('verificationHold'),
                    icon: const Icon(Icons.pause_circle_outline_rounded, size: 18, color: AppColors.brandDark),
                    label: const Text('Hold'),
                  ),
                if (_stage != 'verificationReject')
                  OutlinedButton.icon(
                    onPressed: busy ? null : () => _decide('verificationReject'),
                    icon: const Icon(Icons.cancel_outlined, size: 18, color: AppColors.error),
                    label: const Text('Reject'),
                  ),
                OutlinedButton.icon(
                  onPressed: busy ? null : () => _decide('verificationBlacklist'),
                  icon: const Icon(Icons.block_rounded, size: 18, color: AppColors.error),
                  label: const Text('Blacklist'),
                ),
              ]),
          ],
        ],
      ),
    );
  }
}
