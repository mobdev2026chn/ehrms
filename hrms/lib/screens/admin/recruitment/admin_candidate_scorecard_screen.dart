// lib/screens/admin/recruitment/admin_candidate_scorecard_screen.dart
import 'package:flutter/material.dart';
import '../../../config/app_colors.dart';
import '../../../services/api_client.dart';
import '../../../utils/snackbar_utils.dart';
import 'admin_interview_rounds_screen.dart';

class AdminCandidateScorecardScreen extends StatefulWidget {
  final AdminEvaluationRoundItem item;

  const AdminCandidateScorecardScreen({super.key, required this.item});

  @override
  State<AdminCandidateScorecardScreen> createState() => _AdminCandidateScorecardScreenState();
}

class _AdminCandidateScorecardScreenState extends State<AdminCandidateScorecardScreen> {
  final ApiClient _api = ApiClient();
  int _selectedRoundIndex = 0;

  final Map<int, String> _textAnswers = {
    1: 'Candidate demonstrated clear structured approach starting from problem statement, user empathy mapping, and wireframing.',
    2: 'Uses Hotjar heatmaps, Figma user testing recordings, and direct user interviews.',
    3: 'Relies on data points, usability testing metrics, and design system consistency guidelines.',
    7: 'Demonstrated iterative improvements after A/B testing checkout CTA button contrast.',
  };

  final Map<int, int> _ratings = {
    4: 5,
    5: 4,
    6: 4,
  };

  late TextEditingController _generalFeedbackCtrl;
  late String _recommendation;
  late int _overallScore;

  @override
  void initState() {
    super.initState();
    _generalFeedbackCtrl = TextEditingController(text: widget.item.generalFeedback);
    _recommendation = widget.item.recommendation;
    _overallScore = widget.item.overallScore;
  }

  @override
  void dispose() {
    _generalFeedbackCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveScorecard() async {
    try {
      await _api.request(
        '/admin/recruitment/interview-process/rounds/${widget.item.id}/evaluation',
        method: 'POST',
        data: {
          'textAnswers': _textAnswers,
          'ratings': _ratings,
          'overallScore': _overallScore,
          'generalFeedback': _generalFeedbackCtrl.text.trim(),
          'recommendation': _recommendation,
        },
      );
    } catch (_) {}
    setState(() {
      widget.item.generalFeedback = _generalFeedbackCtrl.text.trim();
      widget.item.recommendation = _recommendation;
      widget.item.overallScore = _overallScore;
      if (_recommendation == 'Pass' || _recommendation == 'Selected') {
        widget.item.status = 'Evaluated - Pass';
      } else if (_recommendation == 'Reject') {
        widget.item.status = 'Evaluated - Rejected';
      } else if (_recommendation == 'Hold') {
        widget.item.status = 'Evaluated - Hold';
      }
    });
    if (mounted) SnackBarUtils.showSnackBar(context, 'Scorecard saved successfully!');
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF0F172A)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Candidate Interview Flow',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
        ),
        centerTitle: false,
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Subtitle
          const Text(
            'Review scorecards, evaluator remarks, and round recommendations across the interview loop.',
            style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 14),

          // Round Tabs
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildRoundTab(0, 'Round 1', 'PASSED', isPassed: true),
                const SizedBox(width: 8),
                _buildRoundTab(1, 'Round 2', 'PENDING'),
                const SizedBox(width: 8),
                _buildRoundTab(2, 'Round 3', 'PENDING'),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── ROUND METADATA CARD ──
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
                  children: const [
                    Icon(Icons.assignment_ind_outlined, size: 16, color: Color(0xFFEFAA1F)),
                    SizedBox(width: 6),
                    Text('ROUND METADATA', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Color(0xFF0F172A), letterSpacing: 0.5)),
                  ],
                ),
                const SizedBox(height: 12),
                _metadataRow('CANDIDATE', item.candidateName),
                _metadataRow('ROLE POSITION', item.position),
                _metadataRow('STAGE ROUND', item.round.toUpperCase(), isAmber: true),
                _metadataRow('ASSIGNED EVALUATOR', item.interviewerName),
                _metadataRow('SCHEDULED DATE', item.interviewDate),
                _metadataRow('SCHEDULED TIME', item.interviewTime),
                _metadataRow('INTERVIEW MODE', item.mode),
                _metadataRow('STATUS', item.status, isPass: item.status.contains('Pass')),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── SCORECARD SECTION ──
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
                    Row(
                      children: const [
                        Icon(Icons.rate_review_outlined, size: 16, color: Color(0xFFEFAA1F)),
                        SizedBox(width: 6),
                        Text('SCORECARD', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Color(0xFF0F172A), letterSpacing: 0.5)),
                      ],
                    ),
                    ElevatedButton.icon(
                      onPressed: _saveScorecard,
                      icon: const Icon(Icons.check_rounded, size: 14),
                      label: const Text('Save Scorecard', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFEFAA1F),
                        foregroundColor: const Color(0xFF0F172A),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        elevation: 0,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Q1
                _buildTextQuestion(1, 'Walk us through your design process for your favorite portfolio project.'),
                const SizedBox(height: 16),

                // Q2
                _buildTextQuestion(2, 'How do you gather user research insights and implement them into mockups?'),
                const SizedBox(height: 16),

                // Q3
                _buildTextQuestion(3, 'How do you handle disagreement from product managers on design patterns?'),
                const SizedBox(height: 16),

                // Q4 Rating
                _buildRatingQuestion(4, "Rate the candidate's visual layout, modern typography, and spacing."),
                const SizedBox(height: 16),

                // Q5 Rating
                _buildRatingQuestion(5, "Rate the candidate's responsive designs across desktop and mobile formats."),
                const SizedBox(height: 16),

                // Q6 Rating
                _buildRatingQuestion(6, "Evaluate candidate's Figma/design tool competency on custom components and design systems."),
                const SizedBox(height: 16),

                // Q7 Scenario
                _buildScenarioQuestion(
                  7,
                  'Explain a scenario where design choices had to be modified based on testing feedback.',
                  'Expected to show how feedback was captured, analyzed, and implemented into iterative designs.',
                ),
                const SizedBox(height: 18),

                // Overall Score
                const Text('OVERALL SCORE *', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: Color(0xFF64748B))),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFE2E8F0))),
                      child: Text('$_overallScore / 100', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Color(0xFF0F172A))),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: _overallScore / 100,
                          backgroundColor: const Color(0xFFF1F5F9),
                          valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFEFAA1F)),
                          minHeight: 8,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Overall Remarks
                const Text('OVERALL SCORE NOTE & REMARKS *', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: Color(0xFF64748B))),
                const SizedBox(height: 6),
                TextField(
                  controller: _generalFeedbackCtrl,
                  maxLines: 3,
                  style: const TextStyle(fontSize: 12),
                  decoration: InputDecoration(
                    hintText: 'Enter general evaluator feedback...',
                    hintStyle: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFEFAA1F))),
                    contentPadding: const EdgeInsets.all(10),
                  ),
                ),
                const SizedBox(height: 18),

                // Recommendation Decision Buttons
                const Text('RECOMMENDATION DECISION', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: Color(0xFF64748B))),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _decisionBtn('Pass Round', 'Pass', Icons.check_circle_outline_rounded, const Color(0xFF16A34A)),
                    _decisionBtn('Hold Candidate', 'Hold', Icons.pause_circle_outline_rounded, const Color(0xFFD97706)),
                    _decisionBtn('Reject Candidate', 'Reject', Icons.cancel_outlined, const Color(0xFFDC2626)),
                    _decisionBtn('Schedule Next', 'Schedule', Icons.calendar_today_outlined, const Color(0xFF2563EB)),
                    _decisionBtn('Selected', 'Selected', Icons.verified_rounded, const Color(0xFF059669)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoundTab(int index, String title, String badge, {bool isPassed = false}) {
    final isSelected = _selectedRoundIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedRoundIndex = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isSelected ? const Color(0xFFEFAA1F) : Colors.transparent),
        ),
        child: Row(
          children: [
            Text(
              title,
              style: TextStyle(fontSize: 12, fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600, color: isSelected ? const Color(0xFF0F172A) : const Color(0xFF64748B)),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isPassed ? const Color(0xFFDCFCE7) : const Color(0xFFE2E8F0),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                badge,
                style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w900, color: isPassed ? const Color(0xFF16A34A) : const Color(0xFF64748B)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metadataRow(String label, String value, {bool isAmber = false, bool isPass = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(label, style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: Color(0xFF94A3B8))),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: isPass
                    ? const Color(0xFF16A34A)
                    : isAmber
                        ? const Color(0xFFD97706)
                        : const Color(0xFF0F172A),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextQuestion(int qNum, String question) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Q$qNum: $question', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF0F172A))),
        const SizedBox(height: 6),
        const Text("CANDIDATE'S ANSWER / RESPONSE *", style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w800, color: Color(0xFF94A3B8))),
        const SizedBox(height: 4),
        TextFormField(
          initialValue: _textAnswers[qNum] ?? '',
          maxLines: 2,
          style: const TextStyle(fontSize: 11.5),
          onChanged: (v) => _textAnswers[qNum] = v,
          decoration: InputDecoration(
            hintText: 'No answer recorded.',
            hintStyle: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
            contentPadding: const EdgeInsets.all(8),
          ),
        ),
      ],
    );
  }

  Widget _buildRatingQuestion(int qNum, String question) {
    final rating = _ratings[qNum] ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Q$qNum: $question', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF0F172A))),
        const SizedBox(height: 6),
        Row(
          children: List.generate(5, (idx) {
            final star = idx + 1;
            return GestureDetector(
              onTap: () => setState(() => _ratings[qNum] = star),
              child: Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Icon(
                  star <= rating ? Icons.star_rounded : Icons.star_outline_rounded,
                  color: star <= rating ? const Color(0xFFEFAA1F) : const Color(0xFFCBD5E1),
                  size: 22,
                ),
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildScenarioQuestion(int qNum, String question, String expected) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Q$qNum: $question', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF0F172A))),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: const Color(0xFFFFFBEB), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFFDE68A))),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('EXPECTED SCENARIO ANSWER:', style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w900, color: Color(0xFFD97706))),
              const SizedBox(height: 2),
              Text(expected, style: const TextStyle(fontSize: 10.5, color: Color(0xFF78350F))),
            ],
          ),
        ),
        const SizedBox(height: 6),
        const Text("CANDIDATE'S RESPONSE NOTES *", style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w800, color: Color(0xFF94A3B8))),
        const SizedBox(height: 4),
        TextFormField(
          initialValue: _textAnswers[qNum] ?? '',
          maxLines: 2,
          style: const TextStyle(fontSize: 11.5),
          onChanged: (v) => _textAnswers[qNum] = v,
          decoration: InputDecoration(
            hintText: 'No response notes recorded.',
            hintStyle: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
            contentPadding: const EdgeInsets.all(8),
          ),
        ),
      ],
    );
  }

  Widget _decisionBtn(String label, String value, IconData icon, Color color) {
    final isSelected = _recommendation == value;
    return GestureDetector(
      onTap: () => setState(() => _recommendation = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? color.withAlpha(20) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isSelected ? color : const Color(0xFFE2E8F0)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: isSelected ? color : const Color(0xFF64748B)),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(fontSize: 10.5, fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600, color: isSelected ? color : const Color(0xFF475569)),
            ),
          ],
        ),
      ),
    );
  }
}
