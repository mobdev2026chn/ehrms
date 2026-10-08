// Exit detail tabs, part 2: SOPs, Documents (with the signed acknowledgement upload), Feedback
// (read-only answers and the employee's link), Review, and Full & Final settlement.

import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../config/constants.dart';
import '../../../services/admin_exit_process_service.dart';
import '../../../utils/snackbar_utils.dart';
import '../salary/admin_salary_ui.dart';
import 'exit_case_tabs.dart' show ExitCaseCallback;
import 'exit_process_common.dart';

Map<String, dynamic> _mapOf(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
List<Map<String, dynamic>> _listOf(dynamic v) =>
    v is List ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : <Map<String, dynamic>>[];
String _s(dynamic v) => v?.toString() ?? '';

Future<void> _openLink(BuildContext context, String url) async {
  final uri = Uri.tryParse(url.trim());
  final ok = uri != null && await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) SnackBarUtils.showSnackBar(context, 'Could not open the link.', isError: true);
}

// ═══════════════════════════════ SOPs ═══════════════════════════════

class _SOPRow {
  final String id;
  final TextEditingController project;
  final TextEditingController title;
  final TextEditingController proof;
  final TextEditingController notes;
  bool documented;
  _SOPRow(Map<String, dynamic> s)
      : id = _s(s['id']),
        project = TextEditingController(text: _s(s['projectName'])),
        title = TextEditingController(text: _s(s['title'])),
        proof = TextEditingController(text: _s(s['proofLink'])),
        notes = TextEditingController(text: _s(s['notes'])),
        documented = s['documented'] == true;
  bool get blank =>
      project.text.trim().isEmpty && title.text.trim().isEmpty && !documented && proof.text.trim().isEmpty && notes.text.trim().isEmpty;
  void dispose() {
    project.dispose();
    title.dispose();
    proof.dispose();
    notes.dispose();
  }
}

class ExitSOPsTab extends StatefulWidget {
  final Map<String, dynamic> exitCase;
  final String sectionStatus;
  final ExitCaseCallback onCaseUpdated;
  const ExitSOPsTab({super.key, required this.exitCase, required this.sectionStatus, required this.onCaseUpdated});

  @override
  State<ExitSOPsTab> createState() => _ExitSOPsTabState();
}

class _ExitSOPsTabState extends State<ExitSOPsTab> with AutomaticKeepAliveClientMixin {
  List<_SOPRow>? _draft;
  bool _saving = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _clear();
    super.dispose();
  }

  void _clear() {
    for (final r in _draft ?? const <_SOPRow>[]) {
      r.dispose();
    }
    _draft = null;
  }

  Future<void> _save() async {
    final rows = _draft!.where((r) => !r.blank).toList();
    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      if (r.project.text.trim().isEmpty || r.title.text.trim().isEmpty) {
        SnackBarUtils.showSnackBar(context, 'SOP ${i + 1} needs a project name and a title.', isError: true);
        return;
      }
      if (r.documented && r.proof.text.trim().isNotEmpty && !ExitUi.isLink(r.proof.text)) {
        SnackBarUtils.showSnackBar(context, 'The SOP link for "${r.title.text.trim()}" must start with http:// or https://.',
            isError: true);
        return;
      }
    }
    setState(() => _saving = true);
    final r = await AdminExitProcessService.instance.saveSOPs(
      _s(widget.exitCase['id']),
      rows
          .map((s) => {
                if (s.id.isNotEmpty) 'id': s.id,
                'projectName': s.project.text.trim(),
                'title': s.title.text.trim(),
                'documented': s.documented,
                'proofLink': s.documented ? s.proof.text.trim() : '',
                'notes': s.notes.text.trim(),
              })
          .toList(),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (r['success'] == true) {
      setState(_clear);
      widget.onCaseUpdated(_mapOf(r['data']));
      SnackBarUtils.showSnackBar(context, 'SOPs saved.');
    } else {
      SnackBarUtils.showSnackBar(context, r['message']?.toString() ?? 'Could not save SOPs.', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final saved = _listOf(widget.exitCase['sops']);
    final editing = _draft != null;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        ExitEditBar(
          title: 'SOPs',
          status: widget.sectionStatus,
          editing: editing,
          saving: _saving,
          onEdit: () => setState(() => _draft = saved.map(_SOPRow.new).toList()),
          onCancel: () => setState(_clear),
          onSave: _save,
        ),
        if (!editing && saved.isEmpty)
          const AdminEmptyView(icon: Icons.description_outlined, title: 'No SOPs recorded', subtitle: 'Use Edit to list the SOPs to document.'),
        if (!editing)
          ...saved.map((s) {
            final done = _s(s['projectName']).isNotEmpty && _s(s['title']).isNotEmpty && s['documented'] == true && _s(s['proofLink']).isNotEmpty;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: AdminCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(_s(s['title']), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AdminUi.ink))),
                    AdminPill(done ? 'Completed' : 'Pending'),
                  ]),
                  const SizedBox(height: 6),
                  ExitKv('Project', _s(s['projectName'])),
                  ExitKv('Documented', s['documented'] == true ? 'Yes' : 'No'),
                  if (_s(s['proofLink']).isNotEmpty)
                    InkWell(onTap: () => _openLink(context, _s(s['proofLink'])), child: ExitKv('SOP link', _s(s['proofLink']))),
                  if (_s(s['notes']).isNotEmpty) ExitKv('Notes', _s(s['notes'])),
                ]),
              ),
            );
          }),
        if (editing) ...[
          ..._draft!.asMap().entries.map((e) {
            final r = e.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: AdminCard(
                child: Column(children: [
                  Row(children: [
                    Expanded(child: TextField(controller: r.project, decoration: AdminUi.input('Project name'))),
                    IconButton(
                      tooltip: 'Remove',
                      icon: const Icon(Icons.delete_outline_rounded, size: 20, color: AdminUi.red),
                      onPressed: () => setState(() => _draft!.removeAt(e.key).dispose()),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  TextField(controller: r.title, decoration: AdminUi.input('SOP title')),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: r.documented,
                    title: const Text('Documented & shared', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AdminUi.ink)),
                    onChanged: (v) => setState(() => r.documented = v),
                  ),
                  if (r.documented) ...[
                    TextField(controller: r.proof, keyboardType: TextInputType.url, decoration: AdminUi.input('SOP link', hint: 'https://...')),
                    const SizedBox(height: 12),
                  ],
                  TextField(controller: r.notes, maxLines: 2, decoration: AdminUi.input('Notes')),
                ]),
              ),
            );
          }),
          OutlinedButton.icon(
            onPressed: () => setState(() => _draft!.add(_SOPRow(const {}))),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Add SOP'),
          ),
        ],
      ],
    );
  }
}

// ═══════════════════════════════ Documents ═══════════════════════════════

class ExitDocumentsTab extends StatefulWidget {
  final Map<String, dynamic> exitCase;
  final String sectionStatus;
  final ExitCaseCallback onCaseUpdated;
  const ExitDocumentsTab({super.key, required this.exitCase, required this.sectionStatus, required this.onCaseUpdated});

  @override
  State<ExitDocumentsTab> createState() => _ExitDocumentsTabState();
}

class _ExitDocumentsTabState extends State<ExitDocumentsTab> with AutomaticKeepAliveClientMixin {
  static const _maxBytes = 10 * 1024 * 1024;
  static const _mimes = {
    'pdf': 'application/pdf',
    'doc': 'application/msword',
    'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  };

  bool? _originals;
  bool? _signed;
  bool _saving = false;
  bool _uploading = false;
  bool _removing = false;
  bool _templating = false;

  @override
  bool get wantKeepAlive => true;

  Map<String, dynamic> get _docs => _mapOf(widget.exitCase['documents']);
  bool get _editing => _originals != null;
  String get _caseId => _s(widget.exitCase['id']);

  static String _size(num bytes) =>
      bytes >= 1024 * 1024 ? '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB' : '${(bytes / 1024).round().clamp(1, 1024)} KB';

  Future<void> _save() async {
    setState(() => _saving = true);
    final r = await AdminExitProcessService.instance.saveDocuments(_caseId, originals: _originals!, signed: _signed!);
    if (!mounted) return;
    setState(() => _saving = false);
    if (r['success'] == true) {
      setState(() => _originals = _signed = null);
      widget.onCaseUpdated(_mapOf(r['data']));
      SnackBarUtils.showSnackBar(context, 'Documents saved.');
    } else {
      SnackBarUtils.showSnackBar(context, r['message']?.toString() ?? 'Could not save documents.', isError: true);
    }
  }

  Future<void> _upload() async {
    final picked = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf', 'doc', 'docx'], withData: true);
    if (picked == null || picked.files.isEmpty || !mounted) return;
    final f = picked.files.single;
    final ext = f.name.split('.').last.toLowerCase();
    final mime = _mimes[ext];
    if (mime == null) {
      SnackBarUtils.showSnackBar(context, 'Upload a PDF or Word (.doc / .docx) file.', isError: true);
      return;
    }
    if (f.size > _maxBytes) {
      SnackBarUtils.showSnackBar(context, 'That file is ${_size(f.size)}. Please upload one under 10 MB.', isError: true);
      return;
    }
    setState(() => _uploading = true);
    List<int>? bytes;
    try {
      bytes = f.bytes ?? (f.path != null ? await File(f.path!).readAsBytes() : null);
    } on FileSystemException catch (e) {
      if (mounted) {
        setState(() => _uploading = false);
        SnackBarUtils.showSnackBar(context, 'The file could not be read: ${e.message}', isError: true);
      }
      return;
    }
    if (bytes == null || bytes.isEmpty) {
      if (mounted) {
        setState(() => _uploading = false);
        SnackBarUtils.showSnackBar(context, 'The file is empty.', isError: true);
      }
      return;
    }
    final r = await AdminExitProcessService.instance.uploadAcknowledgement(_caseId, f.name, mime, base64Encode(bytes));
    if (!mounted) return;
    setState(() => _uploading = false);
    if (r['success'] == true) {
      widget.onCaseUpdated(_mapOf(r['data']));
      SnackBarUtils.showSnackBar(context, 'Signed acknowledgement uploaded.');
    } else {
      SnackBarUtils.showSnackBar(context, r['message']?.toString() ?? 'Could not upload the file.', isError: true);
    }
  }

  Future<void> _remove() async {
    final ok = await adminConfirm(context,
        title: 'Remove signed copy?', message: 'The uploaded acknowledgement will be deleted.', confirmLabel: 'Remove', destructive: true);
    if (!ok || !mounted) return;
    setState(() => _removing = true);
    final r = await AdminExitProcessService.instance.removeAcknowledgement(_caseId);
    if (!mounted) return;
    setState(() => _removing = false);
    if (r['success'] == true) {
      widget.onCaseUpdated(_mapOf(r['data']));
      SnackBarUtils.showSnackBar(context, 'Signed acknowledgement removed.');
    } else {
      SnackBarUtils.showSnackBar(context, r['message']?.toString() ?? 'Could not remove the file.', isError: true);
    }
  }

  static String _esc(String v) => v
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');

  /// The relieving acknowledgement as a print-ready page, letterheaded from GET /admin/company.
  Future<void> _downloadTemplate() async {
    setState(() => _templating = true);
    final r = await AdminExitProcessService.instance.getCompany();
    if (!mounted) return;
    if (r['success'] != true) {
      setState(() => _templating = false);
      SnackBarUtils.showSnackBar(context, r['message']?.toString() ?? 'Could not load company details.', isError: true);
      return;
    }
    final c = _mapOf(r['data']);
    final staff = _mapOf(widget.exitCase['staff']);
    final ext = _mapOf(widget.exitCase['leaveExtension']);
    final lwd = _s(ext['lastWorkingDay']).isNotEmpty ? _s(ext['lastWorkingDay']) : _s(_mapOf(widget.exitCase['timeline'])['lastWorkingDay']);
    final company = _esc(_s(c['name']).isEmpty ? 'Your company' : _s(c['name']));
    final address = _esc([c['address'], c['city'], c['state'], c['pincode']].where((v) => _s(v).isNotEmpty).join(', '));
    final logo = _s(c['logo']);
    final safeLogo = RegExp(r'^https?://', caseSensitive: false).hasMatch(logo) ||
            RegExp(r'^data:image/[a-z+.-]+;base64,', caseSensitive: false).hasMatch(logo)
        ? _esc(logo)
        : '';
    final name = _esc(_s(staff['name']));
    final lwdText = _esc(lwd.isEmpty ? '-' : AdminUi.date(lwd));
    final html = '''<!doctype html>
<html lang="en"><head><meta charset="utf-8" /><meta name="viewport" content="width=device-width, initial-scale=1" />
<title>Relieving acknowledgement - $name</title>
<style>
@page { margin: 20mm; }
body { font-family: Arial, Helvetica, sans-serif; color: #0f172a; margin: 16px; font-size: 13px; line-height: 1.6; }
header { display: flex; align-items: center; gap: 16px; border-bottom: 2px solid #F9B824; padding-bottom: 16px; }
header img { max-height: 56px; max-width: 160px; object-fit: contain; }
.company { font-size: 18px; font-weight: 700; } .address { font-size: 11px; color: #475569; }
h1 { font-size: 18px; margin: 32px 0 4px; } .date { color: #475569; margin-bottom: 20px; }
td { padding: 5px 24px 5px 0; vertical-align: top; } td:first-child { color: #475569; }
.sign { display: flex; justify-content: space-between; margin-top: 96px; gap: 24px; }
.line { border-top: 1px solid #0f172a; width: 220px; padding-top: 6px; font-size: 11px; color: #475569; }
</style></head><body>
<header>${safeLogo.isNotEmpty ? '<img src="$safeLogo" alt="" />' : ''}<div><div class="company">$company</div>${address.isNotEmpty ? '<div class="address">$address</div>' : ''}</div></header>
<h1>Relieving Acknowledgement</h1><div class="date">Date: ____________________</div>
<table>
<tr><td>Employee name</td><td><strong>$name</strong></td></tr>
<tr><td>Employee ID</td><td>${_esc(_s(staff['employeeId']))}</td></tr>
<tr><td>Designation</td><td>${_esc(_s(staff['designation']))}</td></tr>
<tr><td>Department</td><td>${_esc(_s(staff['department']))}</td></tr>
<tr><td>Last working day</td><td>$lwdText</td></tr>
</table>
<p>I, <strong>$name</strong>, acknowledge that I am relieved from my duties at $company with effect from <strong>$lwdText</strong>.</p>
<p>I confirm that I have handed over all company property, documents, credentials and knowledge transfer assigned to me, and that I have no claims against the company other than my full and final settlement.</p>
<div class="sign"><div class="line">Employee signature</div><div class="line">Authorised signatory, $company</div></div>
<script>window.addEventListener("load", function () { if (window.print) window.print(); });</script>
</body></html>''';
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/relieving_acknowledgement_${_s(staff['employeeId']).isEmpty ? _caseId : _s(staff['employeeId'])}.html');
      await file.writeAsString(html, flush: true);
      final res = await OpenFilex.open(file.path, type: 'text/html');
      if (res.type != ResultType.done && mounted) {
        SnackBarUtils.showSnackBar(context, 'Saved the template, but no app could open it (${res.message}).', isError: true);
      }
    } on FileSystemException catch (e) {
      if (mounted) SnackBarUtils.showSnackBar(context, 'Could not write the template: ${e.message}', isError: true);
    } finally {
      if (mounted) setState(() => _templating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final docs = _docs;
    final file = _mapOf(docs['acknowledgementFile']);
    final originals = _originals ?? docs['originalDocumentsCollected'] == true;
    final signed = _signed ?? docs['acknowledgementSigned'] == true;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        AdminCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ExitEditBar(
              title: 'Documents',
              status: widget.sectionStatus,
              editing: _editing,
              saving: _saving,
              onEdit: () => setState(() {
                _originals = docs['originalDocumentsCollected'] == true;
                _signed = docs['acknowledgementSigned'] == true;
              }),
              onCancel: () => setState(() => _originals = _signed = null),
              onSave: _save,
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: originals,
              title: const Text('Original documents collected', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AdminUi.ink)),
              onChanged: _editing ? (v) => setState(() => _originals = v == true) : null,
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: signed,
              title: const Text('Relieving acknowledgement signed', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AdminUi.ink)),
              onChanged: _editing ? (v) => setState(() => _signed = v == true) : null,
            ),
          ]),
        ),
        const SizedBox(height: 12),
        AdminCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Signed acknowledgement', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: AdminUi.ink)),
            const SizedBox(height: 4),
            const Text('Download the template (company name and logo from Business settings), have it signed, then upload the signed copy (PDF or Word, under 10 MB).',
                style: TextStyle(fontSize: 12, color: AdminUi.muted)),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _templating ? null : _downloadTemplate,
              icon: _templating
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.download_rounded, size: 18),
              label: const Text('Download template'),
            ),
            const SizedBox(height: 12),
            if (file.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: AdminUi.bg, borderRadius: BorderRadius.circular(12)),
                child: Row(children: [
                  const Icon(Icons.insert_drive_file_rounded, color: AdminUi.amber),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_s(file['fileName']), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                      Text('${_size(AdminUi.toDouble(file['size']))} • uploaded ${AdminUi.date(file['uploadedAt'])}',
                          style: const TextStyle(fontSize: 12.5, color: AdminUi.muted)),
                    ]),
                  ),
                  if (_s(file['url']).isNotEmpty)
                    IconButton(
                      tooltip: 'View',
                      icon: const Icon(Icons.open_in_new_rounded, size: 20),
                      onPressed: () => _openLink(context, _s(file['url'])),
                    ),
                  _removing
                      ? const Padding(
                          padding: EdgeInsets.all(10),
                          child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
                      : IconButton(
                          tooltip: 'Remove',
                          icon: const Icon(Icons.delete_outline_rounded, color: AdminUi.red, size: 20),
                          onPressed: _uploading ? null : _remove,
                        ),
                ]),
              ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              style: AdminUi.primaryButton(),
              onPressed: _uploading || _removing ? null : _upload,
              icon: _uploading
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.upload_file_rounded, size: 18),
              label: Text(file.isEmpty ? 'Upload signed copy' : 'Replace signed copy'),
            ),
          ]),
        ),
      ],
    );
  }
}

// ═══════════════════════════════ Feedback ═══════════════════════════════

class ExitFeedbackTab extends StatelessWidget {
  final Map<String, dynamic> exitCase;
  final Map<String, dynamic> settings;
  final String sectionStatus;
  const ExitFeedbackTab({super.key, required this.exitCase, required this.settings, required this.sectionStatus});

  @override
  Widget build(BuildContext context) {
    final fb = _mapOf(exitCase['feedback']);
    final token = _s(fb['token']);
    final link = token.isEmpty ? '' : '${AppConstants.fileBaseUrl}/exit-feedback/$token';
    final enabled = settings['exitFeedbackForm'] == true;
    final fields = _listOf(settings['feedbackFields']);
    final answers = {for (final a in _listOf(fb['answers'])) _s(a['fieldId']): a};
    final submitted = fb['submittedAt'] != null;

    String answerText(dynamic v) {
      if (v is List) return v.map((e) => e.toString()).join(', ');
      final s = _s(v);
      return RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s) ? AdminUi.date(s) : s;
    }

    // Questions as configured now, then any answered question since removed from Settings.
    final rows = <(String, String)>[
      for (final f in fields) (_s(f['label']), answerText(answers[_s(f['fieldId'])]?['value'])),
      for (final a in answers.values.where((a) => !fields.any((f) => _s(f['fieldId']) == _s(a['fieldId']))))
        (_s(a['label']), answerText(a['value'])),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        AdminCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Expanded(child: Text('Exit feedback', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: AdminUi.ink))),
              AdminPill(sectionStatus),
            ]),
            const SizedBox(height: 8),
            if (!enabled)
              const Text('The exit feedback form is switched off in Exit Process → Settings.',
                  style: TextStyle(fontSize: 12.5, color: AdminUi.muted))
            else ...[
              Text(
                submitted ? 'Submitted ${AdminUi.date(fb['submittedAt'])}' : 'Waiting for the employee to submit the form.',
                style: TextStyle(fontSize: 12.5, color: submitted ? AdminUi.green : AdminUi.amber, fontWeight: FontWeight.w600),
              ),
              if (link.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text('Share this link with the employee:', style: TextStyle(fontSize: 12, color: AdminUi.muted)),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: AdminUi.bg, borderRadius: BorderRadius.circular(12)),
                  child: Row(children: [
                    Expanded(child: SelectableText(link, style: const TextStyle(fontSize: 12))),
                    IconButton(
                      tooltip: 'Copy link',
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: link));
                        if (context.mounted) SnackBarUtils.showSnackBar(context, 'Feedback link copied.');
                      },
                    ),
                  ]),
                ),
              ],
            ],
          ]),
        ),
        const SizedBox(height: 12),
        if (rows.isEmpty)
          const AdminEmptyView(icon: Icons.chat_bubble_outline_rounded, title: 'No feedback questions')
        else
          AdminCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Answers', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: AdminUi.ink)),
              const SizedBox(height: 6),
              ...rows.map((r) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(r.$1, style: const TextStyle(fontSize: 12.5, color: AdminUi.muted)),
                      const SizedBox(height: 2),
                      Text(r.$2.isEmpty ? '—' : r.$2, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                    ]),
                  )),
            ]),
          ),
      ],
    );
  }
}

// ═══════════════════════════════ Review ═══════════════════════════════

class ExitReviewTab extends StatefulWidget {
  final Map<String, dynamic> exitCase;
  final String sectionStatus;
  final ExitCaseCallback onCaseUpdated;
  const ExitReviewTab({super.key, required this.exitCase, required this.sectionStatus, required this.onCaseUpdated});

  @override
  State<ExitReviewTab> createState() => _ExitReviewTabState();
}

class _ExitReviewTabState extends State<ExitReviewTab> with AutomaticKeepAliveClientMixin {
  final _link = TextEditingController();
  bool? _confirmed;
  bool _saving = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _link.dispose();
    super.dispose();
  }

  Map<String, dynamic> get _review => _mapOf(widget.exitCase['review']);

  Future<void> _save() async {
    final link = _link.text.trim();
    if (link.isNotEmpty && !ExitUi.isLink(link)) {
      SnackBarUtils.showSnackBar(context, 'Review link must start with http:// or https://', isError: true);
      return;
    }
    setState(() => _saving = true);
    final r = await AdminExitProcessService.instance
        .saveReview(_s(widget.exitCase['id']), {'reviewLink': link, 'reviewConfirmed': _confirmed == true});
    if (!mounted) return;
    setState(() => _saving = false);
    if (r['success'] == true) {
      setState(() => _confirmed = null);
      widget.onCaseUpdated(_mapOf(r['data']));
      SnackBarUtils.showSnackBar(context, 'Review saved.');
    } else {
      SnackBarUtils.showSnackBar(context, r['message']?.toString() ?? 'Could not save the review.', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final review = _review;
    final editing = _confirmed != null;
    final link = _s(review['reviewLink']);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        AdminCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ExitEditBar(
              title: 'Company review',
              status: widget.sectionStatus,
              editing: editing,
              saving: _saving,
              onEdit: () => setState(() {
                _link.text = link;
                _confirmed = review['reviewConfirmed'] == true;
              }),
              onCancel: () => setState(() => _confirmed = null),
              onSave: _save,
            ),
            const Text('Record the company’s Google review link and confirm once the employee has left a review.',
                style: TextStyle(fontSize: 12, color: AdminUi.muted)),
            const SizedBox(height: 12),
            if (editing)
              TextField(
                controller: _link,
                keyboardType: TextInputType.url,
                decoration: AdminUi.input('Review link', hint: 'https://g.page/r/...'),
              )
            else if (link.isEmpty)
              const ExitKv('Review link', '')
            else
              InkWell(onTap: () => _openLink(context, link), child: ExitKv('Review link', link)),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: editing ? _confirmed : review['reviewConfirmed'] == true,
              title: const Text('Employee has left a review', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AdminUi.ink)),
              onChanged: editing ? (v) => setState(() => _confirmed = v == true) : null,
            ),
          ]),
        ),
      ],
    );
  }
}

// ═══════════════════════════════ Full & Final ═══════════════════════════════

class ExitFullFinalTab extends StatefulWidget {
  final Map<String, dynamic> exitCase;
  final Map<String, dynamic> settings;
  final String sectionStatus;
  final ExitCaseCallback onCaseUpdated;
  const ExitFullFinalTab({
    super.key,
    required this.exitCase,
    required this.settings,
    required this.sectionStatus,
    required this.onCaseUpdated,
  });

  @override
  State<ExitFullFinalTab> createState() => _ExitFullFinalTabState();
}

class _ExitFullFinalTabState extends State<ExitFullFinalTab> with AutomaticKeepAliveClientMixin {
  static const _letter = {'pending': 'Pending', 'issued': 'Yes - issued', 'withheld': 'No - withheld'};

  Map<String, dynamic>? _draft;
  final _notes = TextEditingController();
  final _reason = TextEditingController();
  bool _saving = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _notes.dispose();
    _reason.dispose();
    super.dispose();
  }

  Map<String, dynamic> get _saved => _mapOf(widget.exitCase['fullFinal']);

  /// The last working day with leave counted, which the relieving letter must follow.
  String get _lwd {
    final ext = _mapOf(widget.exitCase['leaveExtension']);
    final e = _s(ext['lastWorkingDay']);
    return e.isNotEmpty ? e : _s(_mapOf(widget.exitCase['timeline'])['lastWorkingDay']);
  }

  Future<void> _save() async {
    final d = _draft!;
    final status = _s(d['relievingLetterStatus']);
    final date = _s(d['relievingLetterDate']);
    if (status == 'issued' && date.isEmpty) {
      SnackBarUtils.showSnackBar(context, 'Pick the date the relieving letter was issued.', isError: true);
      return;
    }
    if (status == 'issued' && _lwd.isNotEmpty && date.compareTo(_lwd) <= 0) {
      SnackBarUtils.showSnackBar(context, 'The relieving letter date must be after the last working day (${AdminUi.date(_lwd)}).',
          isError: true);
      return;
    }
    setState(() => _saving = true);
    final r = await AdminExitProcessService.instance.saveFullFinal(_s(widget.exitCase['id']), {
      'salaryProcessed': d['salaryProcessed'] == true,
      'salaryNotes': _notes.text.trim(),
      'relievingLetterStatus': status,
      'relievingLetterDate': status == 'issued' ? date : '',
      'reason': _reason.text.trim(),
    });
    if (!mounted) return;
    setState(() => _saving = false);
    if (r['success'] == true) {
      setState(() => _draft = null);
      widget.onCaseUpdated(_mapOf(r['data']));
      SnackBarUtils.showSnackBar(context, 'Full & final saved.');
    } else {
      SnackBarUtils.showSnackBar(context, r['message']?.toString() ?? 'Could not save full & final.', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final f = _draft ?? _saved;
    final editing = _draft != null;
    final status = _letter.containsKey(f['relievingLetterStatus']) ? _s(f['relievingLetterStatus']) : 'pending';
    final processDays = (widget.settings['salaryProcessDaysAfterRelieving'] as num?)?.toInt() ?? 0;
    final reminderDays = (widget.settings['salaryReminderDaysBeforeProcess'] as num?)?.toInt() ?? 0;
    final dueBy = _lwd.isEmpty ? '' : ExitUi.addDays(_lwd, processDays);
    final remindFrom = dueBy.isEmpty ? '' : ExitUi.addDays(dueBy, -reminderDays);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        AdminCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ExitEditBar(
              title: 'Full & final settlement',
              status: widget.sectionStatus,
              editing: editing,
              saving: _saving,
              onEdit: () => setState(() {
                _notes.text = _s(_saved['salaryNotes']);
                _reason.text = _s(_saved['reason']);
                _draft = Map<String, dynamic>.from(_saved);
              }),
              onCancel: () => setState(() => _draft = null),
              onSave: _save,
            ),
            if (dueBy.isNotEmpty)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: AdminUi.blueBg, borderRadius: BorderRadius.circular(12)),
                child: Text(
                  'Final salary due by ${AdminUi.date(dueBy)} • reminders from ${AdminUi.date(remindFrom)} (per Settings)',
                  style: const TextStyle(fontSize: 12, color: AdminUi.blue, fontWeight: FontWeight.w600),
                ),
              ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: f['salaryProcessed'] == true,
              title: const Text('Final salary processed', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AdminUi.ink)),
              onChanged: editing ? (v) => setState(() => _draft!['salaryProcessed'] = v == true) : null,
            ),
            if (editing)
              TextField(controller: _notes, maxLength: 500, maxLines: 2, decoration: AdminUi.input('Salary notes'))
            else
              ExitKv('Salary notes', _s(f['salaryNotes'])),
            const SizedBox(height: 12),
            if (editing) ...[
              DropdownButtonFormField<String>(
                initialValue: status,
                decoration: AdminUi.input('Relieving letter'),
                items: _letter.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
                onChanged: (v) => setState(() => _draft!['relievingLetterStatus'] = v ?? 'pending'),
              ),
              if (status == 'issued') ...[
                const SizedBox(height: 12),
                ExitDateField(
                  label: 'Relieving letter date',
                  value: _s(f['relievingLetterDate']),
                  firstDate: _lwd.isEmpty ? null : ExitUi.addDays(_lwd, 1),
                  helper: _lwd.isEmpty ? null : 'After the last working day (${AdminUi.date(_lwd)}).',
                  onChanged: (v) => setState(() => _draft!['relievingLetterDate'] = v),
                ),
              ],
              const SizedBox(height: 12),
              TextField(controller: _reason, maxLength: 1000, maxLines: 3, decoration: AdminUi.input('Reason / remarks')),
            ] else ...[
              ExitKv('Relieving letter', _letter[status]!),
              if (status == 'issued') ExitKv('Letter date', AdminUi.date(f['relievingLetterDate'])),
              ExitKv('Reason / remarks', _s(f['reason'])),
            ],
          ]),
        ),
      ],
    );
  }
}
