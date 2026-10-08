// lib/screens/admin/recruitment/admin_send_offer_screen.dart
// Generate an offer letter for a candidate: template, salary template, basic salary, PF/ESI,
// designation, dates and attachments. Calculate (POST /offer-letters/preview), then save a
// draft or send (POST /offer-letters with send). Pops `true` when issued.

import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../config/app_colors.dart';
import '../../../models/admin_recruitment_models.dart';
import '../../../services/admin_recruitment_service.dart';
import 'admin_offer_view_screen.dart' show OfferCompensationTable;
import 'rec_widgets.dart';

class AdminSendOfferScreen extends StatefulWidget {
  final String candidateId;
  const AdminSendOfferScreen({super.key, required this.candidateId});

  @override
  State<AdminSendOfferScreen> createState() => _AdminSendOfferScreenState();
}

class _AdminSendOfferScreenState extends State<AdminSendOfferScreen> {
  final AdminRecruitmentService _service = AdminRecruitmentService();
  final _formKey = GlobalKey<FormState>();

  RecCandidate? _candidate;
  List<RecOfferTemplate> _templates = [];
  List<RecSalaryTemplateOption> _salaryTemplates = [];
  bool _loading = true;
  String? _error;

  String? _templateId;
  String? _salaryTemplateId;
  final _basic = TextEditingController();
  final _designation = TextEditingController();
  bool _pf = true;
  bool _esi = true;
  String _joiningDate = '';
  String _validTill = '';
  final List<RecPickedFile> _attachments = [];

  RecOfferPreview? _preview;
  bool _previewing = false;
  String? _issuing;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _basic.dispose();
    _designation.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final cF = _service.getCandidate(widget.candidateId);
      final tF = _service.getOfferTemplates();
      final sF = _service.getSalaryTemplates();
      final c = await cF;
      final t = await tF;
      final s = await sF;
      if (!mounted) return;
      final def = t.where((x) => x.isDefault).firstOrNull ?? t.firstOrNull;
      setState(() {
        _candidate = c;
        _templates = t;
        _salaryTemplates = s;
        _templateId = def?.id;
        _salaryTemplateId = (def != null && s.any((x) => x.id == def.salaryTemplateId)) ? def.salaryTemplateId : null;
        if (_designation.text.isEmpty) _designation.text = c.displayJob;
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

  Map<String, dynamic> _payload() => {
        'candidateId': widget.candidateId,
        if (_templateId != null) 'templateId': _templateId,
        if (_salaryTemplateId != null) 'salaryTemplateId': _salaryTemplateId,
        'basicSalary': num.parse(_basic.text.trim()),
        'hasPF': _pf,
        'hasESI': _esi,
        if (_designation.text.trim().isNotEmpty) 'designation': _designation.text.trim(),
        if (_joiningDate.isNotEmpty) 'joiningDate': _joiningDate,
        if (_validTill.isNotEmpty) 'validTill': _validTill,
      };

  bool _validate() {
    if (!(_formKey.currentState?.validate() ?? false)) return false;
    if (_templates.isEmpty) {
      recShowError(context, 'Create an offer letter template first.');
      return false;
    }
    if (_salaryTemplateId == null) {
      recShowError(context, 'Please select a salary template.');
      return false;
    }
    return true;
  }

  Future<void> _calculate() async {
    if (!_validate()) return;
    setState(() => _previewing = true);
    try {
      final p = await _service.previewOfferLetter(_payload());
      if (!mounted) return;
      setState(() => _preview = p);
    } catch (e) {
      if (mounted) recShowError(context, e);
    } finally {
      if (mounted) setState(() => _previewing = false);
    }
  }

  Future<void> _issue(bool send) async {
    if (!_validate()) return;
    if (send) {
      final ok = await recConfirm(context,
          title: 'Send offer letter?',
          message: 'The letter is emailed to ${_candidate?.email} and the candidate becomes Offered.',
          confirmLabel: 'Send');
      if (!ok) return;
    }
    setState(() => _issuing = send ? 'send' : 'draft');
    try {
      final payload = _payload();
      if (_attachments.isNotEmpty) {
        payload['attachments'] = _attachments
            .map((a) => {'fileName': a.name, 'fileData': 'data:${a.mimeType};base64,${base64Encode(a.bytes)}'})
            .toList();
      }
      final msg = await _service.issueOfferLetter(payload, send: send);
      if (!mounted) return;
      recShowSuccess(context, msg);
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) recShowError(context, e);
    } finally {
      if (mounted) setState(() => _issuing = null);
    }
  }

  Future<void> _addAttachment() async {
    if (_attachments.length >= 5) {
      recShowError(context, 'Up to 5 attachments');
      return;
    }
    final f = await recPickFile(context, const ['pdf', 'png', 'jpg', 'jpeg', 'doc', 'docx'], maxMb: 15);
    if (f == null || !mounted) return;
    final total = _attachments.fold<int>(0, (s, a) => s + a.bytes.length) + f.bytes.length;
    if (total > 15 * 1024 * 1024) {
      recShowError(context, 'Attachments can be 15 MB in total');
      return;
    }
    setState(() => _attachments.add(f));
  }

  @override
  Widget build(BuildContext context) {
    final c = _candidate;
    return Scaffold(
      backgroundColor: kRecBg,
      appBar: recAppBar(context, 'Send Offer Letter'),
      bottomNavigationBar: c == null
          ? null
          : Container(
              decoration: const BoxDecoration(
                color: AppColors.surface,
                border: Border(top: BorderSide(color: kRecSoftBorder)),
              ),
              child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Row(children: [
                  Expanded(
                    child: RecPrimaryButton(
                      label: 'Save draft',
                      icon: Icons.save_outlined,
                      outlined: true,
                      busy: _issuing == 'draft',
                      onPressed: _issuing != null ? null : () => _issue(false),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: RecPrimaryButton(
                      label: 'Send offer',
                      icon: Icons.send_rounded,
                      busy: _issuing == 'send',
                      onPressed: _issuing != null ? null : () => _issue(true),
                    ),
                  ),
                ]),
              ),
            ),
            ),
      body: RecAsyncBody(
        loading: _loading,
        error: _error,
        isEmpty: c == null,
        emptyText: 'Candidate not found',
        onRetry: _load,
        builder: () => Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              RecCard(
                child: Row(children: [
                  RecAvatar(c!.fullName),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(c.fullName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: kRecInk)),
                        const SizedBox(height: 2),
                        Text('${c.displayJob} • ${c.email}', style: const TextStyle(fontSize: 12.5, color: kRecMuted)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  RecBadge(c.status),
                ]),
              ),
              RecCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const RecSectionTitle('Letter'),
                    if (_templates.isEmpty)
                      const RecNotice('No offer letter templates yet - create one first.',
                          color: AppColors.error, background: AppColors.errorBg, icon: Icons.error_outline_rounded)
                    else
                      RecDropdown<String>(
                        label: 'Offer letter template',
                        value: _templateId,
                        items: _templates.map((t) => t.id).toList(),
                        labelOf: (id) {
                          final t = _templates.firstWhere((x) => x.id == id);
                          return t.isDefault ? '${t.name} (default)' : t.name;
                        },
                        onChanged: (v) => setState(() {
                          _templateId = v;
                          final t = _templates.where((x) => x.id == v).firstOrNull;
                          if (t != null && _salaryTemplates.any((s) => s.id == t.salaryTemplateId)) {
                            _salaryTemplateId = t.salaryTemplateId;
                          }
                          _preview = null;
                        }),
                      ),
                    RecDropdown<String>(
                      label: 'Salary template *',
                      value: _salaryTemplateId,
                      items: _salaryTemplates.map((s) => s.id).toList(),
                      labelOf: (id) => _salaryTemplates.firstWhere((s) => s.id == id).title,
                      validator: (v) => v == null ? 'Required' : null,
                      onChanged: (v) => setState(() {
                        _salaryTemplateId = v;
                        _preview = null;
                      }),
                    ),
                    RecTextField(controller: _designation, label: 'Designation'),
                  ],
                ),
              ),
              RecCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const RecSectionTitle('Compensation'),
                    RecTextField(
                      controller: _basic,
                      label: 'Basic salary (per month) *',
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      validator: (v) {
                        final n = num.tryParse((v ?? '').trim());
                        if ((v ?? '').trim().isEmpty) return 'Required';
                        if (n == null) return 'Enter a valid number';
                        if (n <= 0) return 'Must be greater than 0';
                        return null;
                      },
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _pf,
                      title: const Text('Provident Fund (PF)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                      onChanged: (v) => setState(() {
                        _pf = v;
                        _preview = null;
                      }),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _esi,
                      title: const Text('ESI', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                      onChanged: (v) => setState(() {
                        _esi = v;
                        _preview = null;
                      }),
                    ),
                    Row(children: [
                      Expanded(
                        child: RecPickerField(
                          label: 'Joining date',
                          value: _joiningDate.isEmpty ? '' : recFormatDate(_joiningDate),
                          onTap: () async {
                            final d = await recPickDate(context, initial: _joiningDate, firstDate: DateTime.now());
                            if (d != null) setState(() => _joiningDate = d);
                          },
                          onClear: () => setState(() => _joiningDate = ''),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: RecPickerField(
                          label: 'Valid till',
                          value: _validTill.isEmpty ? '' : recFormatDate(_validTill),
                          onTap: () async {
                            final d = await recPickDate(context, initial: _validTill, firstDate: DateTime.now());
                            if (d != null) setState(() => _validTill = d);
                          },
                          onClear: () => setState(() => _validTill = ''),
                        ),
                      ),
                    ]),
                    RecPrimaryButton(
                      label: 'Calculate & preview',
                      icon: Icons.calculate_outlined,
                      outlined: true,
                      busy: _previewing,
                      onPressed: _calculate,
                    ),
                  ],
                ),
              ),
              if (_preview != null)
                RecCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const RecSectionTitle('Preview'),
                      RecInfoRow('Annual CTC', recMoney(_preview!.annualCTC)),
                      RecInfoRow('Monthly gross', recMoney(_preview!.monthlyGross)),
                      RecInfoRow('Monthly net', recMoney(_preview!.monthlyNet)),
                      const SizedBox(height: 8),
                      OfferCompensationTable(rows: _preview!.compensation),
                      Theme(
                        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                        child: ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          title: const Text('Letter text', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: kRecInk)),
                          children: [
                            if (_preview!.subject.isNotEmpty) RecInfoRow('Subject', _preview!.subject),
                            Text(_preview!.body, style: const TextStyle(fontSize: 13.5, height: 1.5, color: kRecInk)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              RecCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RecSectionTitle('Attachments (${_attachments.length}/5)',
                        trailing: TextButton.icon(
                          onPressed: _addAttachment,
                          icon: const Icon(Icons.attach_file_rounded, size: 18),
                          label: const Text('Add'),
                        )),
                    if (_attachments.isEmpty)
                      const Text('Optional - sent with the letter. 15 MB total.', style: TextStyle(fontSize: 12.5, color: kRecMuted)),
                    ...List.generate(_attachments.length, (i) => ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const RecIconTile(Icons.insert_drive_file_outlined, size: 36),
                          title: Text(_attachments[i].name, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: kRecInk)),
                          subtitle: Text('${(_attachments[i].bytes.length / 1024).ceil()} KB',
                              style: const TextStyle(fontSize: 12, color: kRecMuted)),
                          trailing: IconButton(
                            tooltip: 'Remove',
                            icon: const Icon(Icons.close_rounded, size: 20, color: kRecMuted),
                            onPressed: () => setState(() => _attachments.removeAt(i)),
                          ),
                        )),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
