// lib/screens/admin/recruitment/admin_interview_flow_details_screen.dart
import 'package:flutter/material.dart';
import '../../../services/api_client.dart';
import '../../../utils/snackbar_utils.dart';
import 'admin_interview_flow_screen.dart';

class AdminInterviewFlowDetailsScreen extends StatefulWidget {
  final AdminJobFlow flow;

  const AdminInterviewFlowDetailsScreen({super.key, required this.flow});

  @override
  State<AdminInterviewFlowDetailsScreen> createState() => _AdminInterviewFlowDetailsScreenState();
}

class _AdminInterviewFlowDetailsScreenState extends State<AdminInterviewFlowDetailsScreen> {
  final ApiClient _api = ApiClient();
  final Map<String, TextEditingController> _newQuestionControllers = {};
  final Map<String, String> _newQuestionTypes = {};

  final List<String> _durations = ['30 mins', '45 mins', '60 mins', '90 mins', '120 mins'];
  final List<String> _evaluators = [
    'Sanjay Patel (Tech Lead)',
    'Animesh Roy (Principal Architect)',
    'Meera Sen (HR Director)',
    'Vikram Malhotra (UX Director)',
    'Pooja Hegde (Senior Product Designer)',
    'Karan Singh (DevOps Lead)',
    'Neha Gupta (QA Manager)',
  ];

  @override
  void dispose() {
    for (final ctrl in _newQuestionControllers.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  TextEditingController _getControllerForRound(String roundId) {
    if (!_newQuestionControllers.containsKey(roundId)) {
      _newQuestionControllers[roundId] = TextEditingController();
      _newQuestionTypes[roundId] = 'TEXT';
    }
    return _newQuestionControllers[roundId]!;
  }

  String _getTypeForRound(String roundId) {
    return _newQuestionTypes[roundId] ?? 'TEXT';
  }

  void _addQuestionToRound(AdminInterviewRound round) {
    final ctrl = _getControllerForRound(round.id);
    final text = ctrl.text.trim();
    if (text.isEmpty) return;

    final type = _getTypeForRound(round.id);
    setState(() {
      round.questions.add({'text': text, 'type': type});
      ctrl.clear();
    });
    _saveFlowToBackend();
    SnackBarUtils.showSnackBar(context, 'Question added');
  }

  void _removeQuestionFromRound(AdminInterviewRound round, int index) {
    setState(() {
      round.questions.removeAt(index);
    });
    _saveFlowToBackend();
  }

  void _moveRoundUp(int index) {
    if (index <= 0) return;
    setState(() {
      final item = widget.flow.rounds.removeAt(index);
      widget.flow.rounds.insert(index - 1, item);
      _reindexRounds();
    });
    _saveFlowToBackend();
  }

  void _moveRoundDown(int index) {
    if (index >= widget.flow.rounds.length - 1) return;
    setState(() {
      final item = widget.flow.rounds.removeAt(index);
      widget.flow.rounds.insert(index + 1, item);
      _reindexRounds();
    });
    _saveFlowToBackend();
  }

  void _reindexRounds() {
    for (int i = 0; i < widget.flow.rounds.length; i++) {
      widget.flow.rounds[i].roundNumber = i + 1;
    }
  }

  void _deleteRound(int index) {
    setState(() {
      widget.flow.rounds.removeAt(index);
      _reindexRounds();
    });
    _saveFlowToBackend();
    SnackBarUtils.showSnackBar(context, 'Round deleted');
  }

  void _showAddRoundModal() {
    final nameCtrl = TextEditingController();
    String duration = '45 mins';
    String evaluator = _evaluators.first;
    final initialQuestionCtrl = TextEditingController();
    String questionType = 'TEXT';

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: const [
                  Icon(Icons.account_tree_outlined, color: Color(0xFFEFAA1F), size: 20),
                  SizedBox(width: 8),
                  Text('Add Interview Round Stage', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('ROUND STAGE NAME *', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: Color(0xFF64748B))),
                    const SizedBox(height: 6),
                    TextField(
                      controller: nameCtrl,
                      style: const TextStyle(fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'e.g. System Design Interview',
                        hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFEFAA1F))),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                    ),
                    const SizedBox(height: 12),

                    const Text('DURATION *', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: Color(0xFF64748B))),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: duration,
                          isExpanded: true,
                          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: Color(0xFF64748B)),
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
                          items: _durations.map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
                          onChanged: (v) {
                            if (v != null) setModalState(() => duration = v);
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    const Text('ASSIGNED EVALUATOR *', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: Color(0xFF64748B))),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: evaluator,
                          isExpanded: true,
                          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: Color(0xFF64748B)),
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
                          items: _evaluators.map((e) => DropdownMenuItem(value: e, child: Text(e, overflow: TextOverflow.ellipsis))).toList(),
                          onChanged: (v) {
                            if (v != null) setModalState(() => evaluator = v);
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    const Text('INITIAL ASSESSMENT QUESTIONS (OPTIONAL)', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: Color(0xFF64748B))),
                    const SizedBox(height: 6),
                    TextField(
                      controller: initialQuestionCtrl,
                      style: const TextStyle(fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Type an assessment question...',
                        hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFEFAA1F))),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (nameCtrl.text.trim().isEmpty) {
                      SnackBarUtils.showSnackBar(context, 'Please enter round name', isError: true);
                      return;
                    }
                    Navigator.pop(ctx);
                    final newQuestions = <Map<String, String>>[];
                    if (initialQuestionCtrl.text.trim().isNotEmpty) {
                      newQuestions.add({'text': initialQuestionCtrl.text.trim(), 'type': questionType});
                    }

                    final newRound = AdminInterviewRound(
                      id: 'R-${widget.flow.rounds.length + 1}',
                      roundNumber: widget.flow.rounds.length + 1,
                      name: nameCtrl.text.trim(),
                      interviewer: evaluator,
                      duration: duration,
                      questions: newQuestions,
                    );

                    setState(() {
                      widget.flow.rounds.add(newRound);
                    });
                    _saveFlowToBackend();
                    SnackBarUtils.showSnackBar(context, 'Round stage added');
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFEFAA1F),
                    foregroundColor: const Color(0xFF0F172A),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    elevation: 0,
                  ),
                  child: const Text('Add Round', style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _saveFlowToBackend() async {
    try {
      await _api.request(
        '/admin/recruitment/interview-process/flow/${widget.flow.jobId}',
        method: 'PUT',
        data: widget.flow.toJson(),
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF0F172A)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          '${widget.flow.jobTitle} Pipeline',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
        ),
        centerTitle: false,
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Banner & Add Stage Button
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFF1F5F9)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        '${widget.flow.jobTitle} Pipeline',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: _showAddRoundModal,
                      icon: const Icon(Icons.add_rounded, size: 16),
                      label: const Text('+ Add Round Stage', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFEFAA1F),
                        foregroundColor: const Color(0xFF0F172A),
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Configure and reorder interview stages, evaluators, and question templates for this position.',
                  style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Round Cards
          if (widget.flow.rounds.isEmpty)
            Container(
              padding: const EdgeInsets.all(32),
              alignment: Alignment.center,
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
              child: const Text('No round stages added. Tap + Add Round Stage to begin.', style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
            )
          else
            ...widget.flow.rounds.asMap().entries.map((entry) => _buildRoundCard(entry.key, entry.value)),
        ],
      ),
    );
  }

  Widget _buildRoundCard(int index, AdminInterviewRound round) {
    final ctrl = _getControllerForRound(round.id);
    final selectedType = _getTypeForRound(round.id);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF1F5F9)),
        boxShadow: const [BoxShadow(color: Color(0x04000000), blurRadius: 6, offset: Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Round Number & Duration + Reorder/Delete
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: const Color(0xFFFFFBEB), borderRadius: BorderRadius.circular(6), border: Border.all(color: const Color(0xFFFDE68A))),
                child: Text('ROUND ${round.roundNumber}', style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900, color: Color(0xFFD97706))),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(6), border: Border.all(color: const Color(0xFFE2E8F0))),
                child: Row(
                  children: [
                    const Icon(Icons.access_time_rounded, size: 12, color: Color(0xFF64748B)),
                    const SizedBox(width: 4),
                    Text(round.duration, style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: Color(0xFF475569))),
                  ],
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.arrow_upward_rounded, size: 17, color: Color(0xFF64748B)),
                onPressed: index > 0 ? () => _moveRoundUp(index) : null,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.arrow_downward_rounded, size: 17, color: Color(0xFF64748B)),
                onPressed: index < widget.flow.rounds.length - 1 ? () => _moveRoundDown(index) : null,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, size: 17, color: Color(0xFFEF4444)),
                onPressed: () => _deleteRound(index),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 10),

          Text(round.name, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: Color(0xFF0F172A))),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.person_outline_rounded, size: 14, color: Color(0xFFD97706)),
              const SizedBox(width: 4),
              Text('Evaluator: ${round.interviewer}', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFF64748B))),
            ],
          ),
          const SizedBox(height: 14),

          // Questions Template Section
          Text(
            'EVALUATION QUESTIONS TEMPLATE (${round.questions.length})',
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF94A3B8)),
          ),
          const SizedBox(height: 8),

          ...round.questions.asMap().entries.map((qEntry) {
            final qIdx = qEntry.key;
            final q = qEntry.value;
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${qIdx + 1}. ', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(q['text'] ?? '', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF1E293B))),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                          decoration: BoxDecoration(color: const Color(0xFFE2E8F0), borderRadius: BorderRadius.circular(4)),
                          child: Text(q['type'] ?? 'TEXT', style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.w800, color: Color(0xFF475569))),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 15, color: Color(0xFF94A3B8)),
                    onPressed: () => _removeQuestionFromRound(round, qIdx),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            );
          }),

          const SizedBox(height: 8),

          // Add Question Input Bar
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: ctrl,
                    onSubmitted: (_) => _addQuestionToRound(round),
                    style: const TextStyle(fontSize: 12),
                    decoration: const InputDecoration(
                      hintText: 'Type a predefined assessment question/topic...',
                      hintStyle: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    ),
                  ),
                ),
                // Type Dropdown (Text, Rating, Scenario, Multichoice)
                Container(
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: selectedType,
                      icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 14, color: Color(0xFF64748B)),
                      style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                      items: const [
                        DropdownMenuItem(value: 'TEXT', child: Text('Text')),
                        DropdownMenuItem(value: 'RATING', child: Text('Rating')),
                        DropdownMenuItem(value: 'SCENARIO', child: Text('Scenario')),
                        DropdownMenuItem(value: 'MULTICHOICE', child: Text('Multichoice')),
                      ],
                      onChanged: (v) {
                        if (v != null) setState(() => _newQuestionTypes[round.id] = v);
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.add_circle_rounded, color: Color(0xFFEFAA1F), size: 22),
                  onPressed: () => _addQuestionToRound(round),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
