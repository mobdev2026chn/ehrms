// lib/screens/admin/recruitment/rec_question_editor.dart
// Bottom-sheet editor for an interview question (text, answer type, options, total marks).
// Mirrors the backend's normalizeQuestion rules: multichoice needs exactly 4 choices,
// scenario keeps one expected answer, marks are a whole number 1-100.

import 'package:flutter/material.dart';

import '../../../models/admin_recruitment_models.dart';
import 'rec_widgets.dart';

/// Returns the question as the API input map ({text, answerType, options, maxScore}), or null.
Future<Map<String, dynamic>?> showQuestionEditor(BuildContext context, {RecQuestion? initial, String title = 'Question'}) {
  return recShowSheet<Map<String, dynamic>>(
    context,
    title: initial == null ? 'Add $title' : 'Edit $title',
    builder: (ctx) => _QuestionEditor(initial: initial),
  );
}

class _QuestionEditor extends StatefulWidget {
  final RecQuestion? initial;
  const _QuestionEditor({this.initial});

  @override
  State<_QuestionEditor> createState() => _QuestionEditorState();
}

class _QuestionEditorState extends State<_QuestionEditor> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _text;
  late final TextEditingController _marks;
  late final List<TextEditingController> _options;
  late String _type;

  @override
  void initState() {
    super.initState();
    final q = widget.initial;
    _text = TextEditingController(text: q?.text ?? '');
    _marks = TextEditingController(text: '${q?.maxScore ?? 10}');
    _type = q?.answerType ?? 'text';
    _options = List.generate(4, (i) => TextEditingController(text: (q != null && i < q.options.length) ? q.options[i] : ''));
  }

  @override
  void dispose() {
    _text.dispose();
    _marks.dispose();
    for (final c in _options) {
      c.dispose();
    }
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    List<String> options = [];
    if (_type == 'multichoice') {
      options = _options.map((c) => c.text.trim()).toList();
    } else if (_type == 'scenario' && _options[0].text.trim().isNotEmpty) {
      options = [_options[0].text.trim()];
    }
    Navigator.pop(context, {
      'text': _text.text.trim(),
      'answerType': _type,
      'options': options,
      'maxScore': int.parse(_marks.text.trim()),
    });
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        children: [
          RecTextField(controller: _text, label: 'Question *', maxLines: 3, validator: recRequired),
          RecDropdown<String>(
            label: 'Answer type',
            value: _type,
            items: kAnswerTypes,
            labelOf: answerTypeLabel,
            onChanged: (v) => setState(() => _type = v ?? _type),
          ),
          if (_type == 'multichoice')
            ...List.generate(
                4,
                (i) => RecTextField(
                      controller: _options[i],
                      label: 'Choice ${i + 1} *',
                      validator: recRequired,
                    )),
          if (_type == 'scenario') RecTextField(controller: _options[0], label: 'Expected answer (optional)', maxLines: 3),
          RecTextField(
            controller: _marks,
            label: 'Total marks (1-100)',
            keyboardType: TextInputType.number,
            validator: (v) {
              final n = int.tryParse((v ?? '').trim());
              if (n == null || n < 1 || n > 100) return 'A whole number from 1 to 100';
              return null;
            },
          ),
          const SizedBox(height: 8),
          SizedBox(width: double.infinity, height: 52, child: RecPrimaryButton(label: 'Save', icon: Icons.check_rounded, onPressed: _submit)),
        ],
      ),
    );
  }
}
