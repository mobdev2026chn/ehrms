// lib/screens/admin/recruitment/admin_offer_templates_screen.dart
// Offer letter templates: list, preview, set default, duplicate, delete, and edit of the
// template settings (name, subject, salary template, salary columns). The letter body and
// letterhead are edited in the web template editor.

import 'package:flutter/material.dart';

import '../../../config/app_colors.dart';
import '../../../models/admin_recruitment_models.dart';
import '../../../services/admin_recruitment_service.dart';
import 'rec_widgets.dart';

String _plainText(String html) => html
    .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
    .replaceAll(RegExp(r'</(p|div|h\d|li|tr)>', caseSensitive: false), '\n')
    .replaceAll(RegExp(r'<[^>]+>'), '')
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll(RegExp(r'\n{3,}'), '\n\n')
    .trim();

/// Standalone screen wrapper (the Offer Letter screen embeds [AdminOfferTemplatesView] as a tab).
class AdminOfferTemplatesScreen extends StatelessWidget {
  const AdminOfferTemplatesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kRecBg,
      appBar: recAppBar(context, 'Offer Letter Templates'),
      body: const AdminOfferTemplatesView(),
    );
  }
}

class AdminOfferTemplatesView extends StatefulWidget {
  const AdminOfferTemplatesView({super.key});

  @override
  State<AdminOfferTemplatesView> createState() => _AdminOfferTemplatesViewState();
}

class _AdminOfferTemplatesViewState extends State<AdminOfferTemplatesView> with AutomaticKeepAliveClientMixin {
  final AdminRecruitmentService _service = AdminRecruitmentService();
  bool _loading = true;
  String? _error;
  List<RecOfferTemplate> _templates = [];

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
      final t = await _service.getOfferTemplates();
      if (!mounted) return;
      setState(() {
        _templates = t;
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

  Future<void> _run(Future<String> Function() op) async {
    try {
      final msg = await op();
      if (!mounted) return;
      recShowSuccess(context, msg);
      _load(showLoader: false);
    } catch (e) {
      if (mounted) recShowError(context, e);
    }
  }

  Future<void> _actions(RecOfferTemplate t) async {
    final a = await recShowActions(context, title: t.name, actions: [
      const RecAction('preview', 'Preview letter', Icons.visibility_outlined),
      const RecAction('edit', 'Edit settings', Icons.edit_outlined),
      if (!t.isDefault) const RecAction('default', 'Set as default', Icons.star_outline_rounded),
      const RecAction('duplicate', 'Duplicate', Icons.copy_all_outlined),
      if (!t.isSystem && !t.isDefault) const RecAction('delete', 'Delete', Icons.delete_outline_rounded, destructive: true),
    ]);
    if (!mounted || a == null) return;
    switch (a) {
      case 'preview':
        recShowSheet(context,
            title: t.name,
            builder: (_) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (t.subject.isNotEmpty) RecInfoRow('Subject', t.subject),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                          color: kRecBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: kRecSoftBorder)),
                      child: Text(_plainText(t.body), style: const TextStyle(fontSize: 13.5, height: 1.5, color: kRecInk)),
                    ),
                  ],
                ));
        break;
      case 'edit':
        _edit(t);
        break;
      case 'default':
        _run(() => _service.setDefaultOfferTemplate(t.id));
        break;
      case 'duplicate':
        _run(() => _service.duplicateOfferTemplate(t.id));
        break;
      case 'delete':
        final ok = await recConfirm(context,
            title: 'Delete template?', message: '"${t.name}" will be removed.', confirmLabel: 'Delete', destructive: true);
        if (ok) _run(() => _service.deleteOfferTemplate(t.id));
        break;
    }
  }

  Future<void> _edit(RecOfferTemplate t) async {
    List<RecSalaryTemplateOption> salaryTemplates;
    try {
      salaryTemplates = await _service.getSalaryTemplates();
    } catch (e) {
      if (mounted) recShowError(context, e);
      return;
    }
    if (!mounted) return;
    final name = TextEditingController(text: t.name);
    final subject = TextEditingController(text: t.subject);
    String salaryId = t.salaryTemplateId;
    bool monthly = t.showMonthlySalary;
    bool annual = t.showAnnualSalary;
    final key = GlobalKey<FormState>();
    final result = await recShowSheet<Map<String, dynamic>>(
      context,
      title: 'Edit template',
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Form(
          key: key,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              RecTextField(controller: name, label: 'Template name *', validator: recRequired),
              RecTextField(controller: subject, label: 'Email subject (may use {{variables}})'),
              RecDropdown<String>(
                label: 'Salary template',
                value: salaryId,
                items: ['', ...salaryTemplates.map((s) => s.id)],
                labelOf: (id) => id.isEmpty ? 'Chosen when the letter is generated' : salaryTemplates.firstWhere((s) => s.id == id).title,
                onChanged: (v) => setS(() => salaryId = v ?? ''),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: monthly,
                title: const Text('Show monthly salary column', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                onChanged: (v) => setS(() => monthly = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: annual,
                title: const Text('Show annual salary column', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                onChanged: (v) => setS(() => annual = v),
              ),
              const Padding(
                padding: EdgeInsets.only(top: 4, bottom: 16),
                child: Text('The letter text, letterhead and signature are edited in the web template editor.',
                    style: TextStyle(fontSize: 12.5, color: kRecMuted)),
              ),
              RecPrimaryButton(
                label: 'Save',
                icon: Icons.check_rounded,
                onPressed: () {
                  if (!(key.currentState?.validate() ?? false)) return;
                  if (!monthly && !annual) {
                    recShowError(ctx, 'Show at least one salary column');
                    return;
                  }
                  Navigator.pop(ctx, {
                    'name': name.text.trim(),
                    'subject': subject.text.trim(),
                    'salaryTemplateId': salaryId.isEmpty ? null : salaryId,
                    'showMonthlySalary': monthly,
                    'showAnnualSalary': annual,
                  });
                },
              ),
            ],
          ),
        ),
      ),
    );
    if (result != null) _run(() => _service.updateOfferTemplate(t.id, result));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return RecAsyncBody(
      loading: _loading,
      error: _error,
      isEmpty: _templates.isEmpty,
      emptyText: 'No offer letter templates yet.\nCreate one in the web app.',
      emptyIcon: Icons.description_outlined,
      onRetry: _load,
      builder: () => RefreshIndicator(
        onRefresh: () => _load(showLoader: false),
        color: AppColors.primary,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: _templates
              .map((t) => RecCard(
                    onTap: () => _actions(t),
                    child: Row(children: [
                      const RecIconTile(Icons.description_outlined, size: 44),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(t.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: kRecInk)),
                            const SizedBox(height: 2),
                            Text(t.subject.isEmpty ? 'No subject' : t.subject,
                                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: kRecMuted)),
                            const SizedBox(height: 2),
                            Text('Updated ${recFormatDate(t.updatedAt)}', style: const TextStyle(fontSize: 12, color: kRecMuted)),
                          ],
                        ),
                      ),
                      Column(children: [
                        if (t.isDefault) const RecBadge('Default', colorKey: 'active'),
                        if (t.isSystem) ...[const SizedBox(height: 4), const RecBadge('System', colorKey: 'inactive')],
                      ]),
                    ]),
                  ))
              .toList(),
        ),
      ),
    );
  }
}
