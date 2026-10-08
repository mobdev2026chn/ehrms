// Create / edit a celebration template (web: TemplateEditorModal). Variables insert at the
// caret of whichever field was last focused; a live preview renders sample values.
// Pops with the server's message on a successful save.

import 'package:flutter/material.dart';

import '../../../config/app_colors.dart';
import '../../../services/admin_celebration_service.dart';
import 'celebration_shared.dart';

class CelebrationTemplateEditorScreen extends StatefulWidget {
  const CelebrationTemplateEditorScreen({
    super.key,
    required this.api,
    required this.kind,
    this.template,
    this.isOnlyOfKind = false,
  });

  final AdminCelebrationService api;

  /// Fixed for the editor: the backend never moves a template between kinds.
  final String kind;
  final CelebrationTemplate? template;

  /// The only template of its kind stays default whatever the checkbox says.
  final bool isOnlyOfKind;

  @override
  State<CelebrationTemplateEditorScreen> createState() => _CelebrationTemplateEditorScreenState();
}

class _CelebrationTemplateEditorScreenState extends State<CelebrationTemplateEditorScreen> {
  late final TextEditingController _name = TextEditingController(text: widget.template?.name ?? '');
  late final TextEditingController _subject = TextEditingController(text: widget.template?.subject ?? '');
  late final TextEditingController _message = TextEditingController(text: widget.template?.message ?? '');
  final FocusNode _subjectFocus = FocusNode();
  final FocusNode _messageFocus = FocusNode();
  late bool _makeDefault = widget.template?.isDefault ?? false;

  /// Field a variable lands in, tracked on focus (tapping a chip steals focus first).
  bool _subjectActive = false;
  bool _saving = false;

  String get _kind => widget.template?.kind ?? widget.kind;

  @override
  void initState() {
    super.initState();
    _subjectFocus.addListener(() {
      if (_subjectFocus.hasFocus && !_subjectActive) setState(() => _subjectActive = true);
    });
    _messageFocus.addListener(() {
      if (_messageFocus.hasFocus && _subjectActive) setState(() => _subjectActive = false);
    });
    for (final c in [_name, _subject, _message]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _subject.dispose();
    _message.dispose();
    _subjectFocus.dispose();
    _messageFocus.dispose();
    super.dispose();
  }

  void _insert(String token) {
    final ctrl = _subjectActive ? _subject : _message;
    final focus = _subjectActive ? _subjectFocus : _messageFocus;
    final text = ctrl.text;
    final sel = ctrl.selection;
    final start = sel.isValid ? sel.start : text.length;
    final end = sel.isValid ? sel.end : text.length;
    ctrl.value = TextEditingValue(
      text: text.replaceRange(start, end, token),
      selection: TextSelection.collapsed(offset: start + token.length),
    );
    focus.requestFocus();
  }

  bool get _canSave => _name.text.trim().isNotEmpty && _message.text.trim().isNotEmpty;

  Future<void> _save() async {
    if (!_canSave || _saving) return;
    setState(() => _saving = true);
    final makeDefault = _makeDefault || widget.isOnlyOfKind;
    try {
      final t = widget.template;
      final msg = t != null
          ? await widget.api.updateTemplate(
              t.id,
              name: _name.text.trim(),
              subject: _subject.text.trim(),
              message: _message.text,
              isDefault: makeDefault,
            )
          : await widget.api.createTemplate(
              name: _name.text.trim(),
              kind: _kind,
              subject: _subject.text.trim(),
              message: _message.text,
              isDefault: makeDefault,
            );
      if (mounted) Navigator.of(context).pop(msg);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showCelebrationError(context, e);
    }
  }

  InputDecoration _decoration(String hint) => InputDecoration(hintText: hint);

  @override
  Widget build(BuildContext context) {
    final kindText = _kind == 'birthday' ? 'birthday' : 'anniversary';
    final previewSubject = renderWithSamples(_subject.text, _kind);
    final previewMessage = renderWithSamples(_message.text, _kind);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(widget.template == null ? 'New Template' : 'Edit Template'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: AppColors.warningBg, borderRadius: BorderRadius.circular(999)),
                child: Text(kindLabel(_kind),
                    style: const TextStyle(color: AppColors.warning, fontWeight: FontWeight.w600, fontSize: 12)),
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        children: [
          const Text("Write the message once - variables fill in each person's details at send time",
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13.5, height: 1.45)),
          const SizedBox(height: 20),
          const _FieldLabel('Template Name'),
          TextField(controller: _name, maxLength: 120, enabled: !_saving, decoration: _decoration('e.g. Warm birthday wish')),
          const _FieldLabel('Subject / Title'),
          TextField(
            controller: _subject,
            focusNode: _subjectFocus,
            maxLength: 200,
            enabled: !_saving,
            decoration: _decoration('e.g. Happy Birthday, {{staff_name}}!'),
          ),
          const _FieldLabel('Message'),
          TextField(
            controller: _message,
            focusNode: _messageFocus,
            maxLength: 5000,
            minLines: 6,
            maxLines: 14,
            enabled: !_saving,
            keyboardType: TextInputType.multiline,
            decoration: _decoration('Write the wish...'),
          ),
          const _FieldLabel('Insert Variables'),
          Text('Tap to insert into the ${_subjectActive ? 'subject' : 'message'} at the cursor.',
              style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final v in variablesFor(_kind))
                Tooltip(
                  message: v.hint,
                  child: ActionChip(
                    avatar: Icon(Icons.add_rounded, size: 16, color: AppColors.primaryText),
                    label: Text(v.label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                    backgroundColor: AppColors.primary.withValues(alpha: 0.10),
                    side: BorderSide(color: AppColors.primary.withValues(alpha: 0.35)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                    onPressed: _saving ? null : () => _insert(v.token),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
          CelebrationCard(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: CheckboxListTile(
              value: _makeDefault || widget.isOnlyOfKind,
              onChanged: widget.isOnlyOfKind || _saving ? null : (v) => setState(() => _makeDefault = v ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              activeColor: AppColors.surfaceDark,
              title: Text('Set as the default $kindText template',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AppColors.textPrimary)),
              subtitle: Text(
                widget.isOnlyOfKind
                    ? 'This is the only template of its kind, so it stays the default.'
                    : 'Auto-sent wishes use the default, and it is preselected when you send one by hand. The template it replaces stays available.',
                style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.4),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const _FieldLabel('Preview'),
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: AppColors.surfaceDark,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: Text(previewSubject.trim().isEmpty ? 'No subject' : previewSubject,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: previewSubject.trim().isEmpty ? Colors.white38 : AppColors.primary,
                    )),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
                child: Text(previewMessage.trim().isEmpty ? 'Your message will appear here.' : previewMessage,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.5,
                      color: previewMessage.trim().isEmpty ? Colors.white38 : Colors.white,
                    )),
              ),
            ]),
          ),
          const SizedBox(height: 6),
          const Text('Preview uses sample values. Real sends use each person\'s details.',
              style: TextStyle(fontSize: 11.5, color: AppColors.textCaption)),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: Color(0xFFECEEF1))),
        ),
        child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.surfaceDark,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(52),
            ),
            onPressed: _canSave && !_saving ? _save : null,
            child: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(widget.template == null ? 'Create Template' : 'Save Changes'),
          ),
        ),
      ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 6),
        child: Text(text.toUpperCase(),
            style: const TextStyle(fontSize: 11, letterSpacing: 1, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
      );
}
