// hrms/lib/screens/lms/lms_ai_quiz_attempt_screen.dart
// AI Practice Quiz attempt - mirrors web /lms/ai-quiz/attempt/:quizId

import 'package:flutter/material.dart';
import '../../config/app_colors.dart';
import '../../config/app_text_styles.dart';
import '../../widgets/app_card.dart';
import '../../services/lms_service.dart';
import '../../utils/snackbar_utils.dart' show SnackBarUtils;
import '../../utils/error_message_utils.dart';
import 'lms_course_detail_screen.dart';
import 'lms_dashboard_screen.dart';
import '../../widgets/app_tab_loader.dart';

class LmsAiQuizAttemptScreen extends StatefulWidget {
  final String quizId;

  const LmsAiQuizAttemptScreen({super.key, required this.quizId});

  @override
  State<LmsAiQuizAttemptScreen> createState() => _LmsAiQuizAttemptScreenState();
}

class _LmsAiQuizAttemptScreenState extends State<LmsAiQuizAttemptScreen> {
  final LmsService _lmsService = LmsService();
  dynamic _quiz;
  bool _loading = true;
  int _currentIndex = 0;
  final Map<int, String> _answers = {};
  bool _isFinished = false;
  Map<String, dynamic>? _results;
  final DateTime _startTime = DateTime.now();

  @override
  void initState() {
    super.initState();
    _loadQuiz();
  }

  Future<void> _loadQuiz() async {
    setState(() => _loading = true);
    final res = await _lmsService.getAIQuiz(widget.quizId);
    if (mounted) {
      setState(() {
        _loading = false;
        _quiz = res['data'];
      });
    }
  }

  Future<void> _submit() async {
    final questions = (_quiz?['questions'] as List?) ?? [];
    if (_answers.length < questions.length) {
      SnackBarUtils.showSnackBar(
        context,
        'Please answer all questions before submitting.',
        isError: true,
      );
      return;
    }

    final responses = <Map<String, dynamic>>[];
    for (var i = 0; i < questions.length; i++) {
      responses.add({'questionIndex': i, 'answer': _answers[i] ?? ''});
    }

    final completionTime = DateTime.now().difference(_startTime).inSeconds;
    final res = await _lmsService.submitAIQuiz(
      widget.quizId,
      responses: responses,
      completionTime: completionTime,
    );

    if (mounted) {
      if (res['success'] == true && res['data'] != null) {
        setState(() {
          _isFinished = true;
          _results = res['data'] as Map<String, dynamic>;
        });
        SnackBarUtils.showSnackBar(context, 'Practice complete!');
      } else {
        SnackBarUtils.showSnackBar(
          context,
          ErrorMessageUtils.sanitizeForDisplay(res['message']?.toString(), fallback: 'Failed to submit'),
          isError: true,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            tooltip: 'Back',
            onPressed: () => Navigator.pop(context),
          ),
          title: const Text('Practice Quiz'),
        ),
        body: const Center(child: AppTabLoader()),
      );
    }

    if (_quiz == null) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            tooltip: 'Back',
            onPressed: () => Navigator.pop(context),
          ),
          title: const Text('Quiz'),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Quiz not found', style: AppTextStyles.headingSmall),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Back'),
              ),
            ],
          ),
        ),
      );
    }

    if (_isFinished && _results != null) {
      return _buildResultsView();
    }

    final questions = (_quiz['questions'] as List?) ?? [];
    if (questions.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            tooltip: 'Back',
            onPressed: () => Navigator.pop(context),
          ),
          title: const Text('Quiz'),
        ),
        body: const Center(
          child: Text('No questions available', style: AppTextStyles.bodySmall),
        ),
      );
    }

    final current = questions[_currentIndex] as Map<String, dynamic>?;
    if (current == null) return const SizedBox();

    final progress = ((_currentIndex + 1) / questions.length) * 100;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Back',
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Practice Quiz'),
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: progress / 100,
                minHeight: 8,
                backgroundColor: const Color(0xFFECEEF1),
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Question ${_currentIndex + 1} of ${questions.length}',
              style: AppTextStyles.sectionLabel.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 20),
            Text(
              current['question'] ?? 'Question',
              style: AppTextStyles.headingMedium.copyWith(height: 1.35),
            ),
            const SizedBox(height: 24),
            ..._buildOptions(current),
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (_currentIndex > 0)
                  Material(
                    color: AppColors.surface,
                    shape: const CircleBorder(
                      side: BorderSide(color: Color(0xFFE2E5EA), width: 1.2),
                    ),
                    child: IconButton(
                      onPressed: () => setState(() => _currentIndex--),
                      icon: const Icon(Icons.arrow_back_rounded),
                      tooltip: 'Previous',
                      color: AppColors.textPrimary,
                      iconSize: 22,
                    ),
                  )
                else
                  const SizedBox(width: 48),
                Material(
                  color: AppColors.primary,
                  shape: const CircleBorder(),
                  child: IconButton(
                    onPressed: () {
                      if (_currentIndex < questions.length - 1) {
                        setState(() => _currentIndex++);
                      } else {
                        _submit();
                      }
                    },
                    icon: Icon(
                      _currentIndex < questions.length - 1
                          ? Icons.arrow_forward_rounded
                          : Icons.check_rounded,
                      size: 22,
                    ),
                    tooltip: _currentIndex < questions.length - 1 ? 'Next' : 'Submit',
                    color: AppColors.onPrimary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildOptions(Map<String, dynamic> question) {
    final options = question['options'] as List? ?? [];
    final selected = _answers[_currentIndex];

    if (options.isEmpty) {
      return [
        TextField(
          decoration: const InputDecoration(
            labelText: 'Your answer',
          ),
          onChanged: (v) => _answers[_currentIndex] = v,
        ),
      ];
    }

    return options.map<Widget>((opt) {
      final val = opt.toString();
      final isSelected = selected == val;
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: InkWell(
          onTap: () => setState(() => _answers[_currentIndex] = val),
          borderRadius: BorderRadius.circular(14),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppColors.primary.withValues(alpha: 0.10)
                  : AppColors.surface,
              border: Border.all(
                color: isSelected ? AppColors.primary : const Color(0xFFE2E5EA),
                width: isSelected ? 1.6 : 1.2,
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Icon(
                  isSelected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: isSelected ? AppColors.primaryText : AppColors.textCaption,
                  size: 22,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    val,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }).toList();
  }

  Widget _buildResultsView() {
    final score = _results!['score'] ?? _results!['earnedPoints'] ?? 0;
    final totalPoints = _results!['totalPoints'] ?? 0;
    final passed = _results!['passed'] ?? false;
    final percentage =
        _results!['proficiency'] as int? ??
        (totalPoints > 0 ? ((score / totalPoints) * 100).round() : 0);
    final c = _quiz?['courseId'];
    final courseId = c is Map ? c['_id']?.toString() : c?.toString();

    List<Map<String, dynamic>> questionResults = [];
    if (_results!['questionResults'] is List) {
      questionResults = List<Map<String, dynamic>>.from(
        (_results!['questionResults'] as List).map(
          (e) => Map<String, dynamic>.from(e as Map),
        ),
      );
    } else {
      final questions = (_quiz?['questions'] as List?) ?? [];
      for (var i = 0; i < questions.length; i++) {
        final q = questions[i] as Map<String, dynamic>? ?? {};
        final userAnswer = _answers[i] ?? '';
        final correctAnswer = q['correctAnswer']?.toString() ?? '';
        final correct = userAnswer == correctAnswer;
        questionResults.add({
          'questionIndex': i,
          'question': q['question'] ?? 'Question ${i + 1}',
          'userAnswer': userAnswer,
          'correct': correct,
          'correctAnswer': correctAnswer,
          'rationale':
              q['rationale'] ??
              (correctAnswer.isNotEmpty
                  ? 'The correct answer is $correctAnswer.'
                  : null),
        });
      }
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Back',
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Quiz Complete'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            Center(
              child: Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: passed
                      ? AppColors.brand.withValues(alpha: 0.14)
                      : AppColors.inputFill,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.emoji_events_rounded,
                  size: 52,
                  color: passed ? AppColors.brand : AppColors.textCaption,
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Knowledge Review Complete',
              style: AppTextStyles.headingLarge,
              textAlign: TextAlign.center,
            ),
            if ((_quiz?['lessonTitles'] as List?)?.isNotEmpty == true)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Focused practice for ${(_quiz!['lessonTitles'] as List).length}',
                  style: AppTextStyles.bodySmall.copyWith(fontSize: 14),
                  textAlign: TextAlign.center,
                ),
              ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(
                  child: _resultCard(
                    'Proficiency',
                    '$percentage%',
                    passed ? AppColors.success : AppColors.brandDark,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _resultCard('Score', '$score/$totalPoints', AppColors.primaryText),
                ),
              ],
            ),
            const SizedBox(height: 32),
            Wrap(
              alignment: WrapAlignment.center,
              runSpacing: 8,
              children: [
                if (courseId != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(
                          builder: (_) =>
                              LmsCourseDetailScreen(courseId: courseId),
                        ),
                        (r) => r.isFirst,
                      ),
                      child: const Text('Back to Course'),
                    ),
                  ),
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(
                      builder: (_) => const LmsDashboardScreen(),
                    ),
                    (r) => r.isFirst,
                  ),
                  child: const Text('Dashboard'),
                ),
              ],
            ),
            if (questionResults.isNotEmpty) ...[
              const SizedBox(height: 32),
              const Divider(),
              const SizedBox(height: 16),
              ...questionResults.map((r) => _buildQuestionResultCard(r)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildQuestionResultCard(Map<String, dynamic> r) {
    final correct = r['correct'] == true;
    final questionNum = (r['questionIndex'] as int? ?? 0) + 1;
    final question = (r['question'] ?? '').toString();
    final userAnswer = (r['userAnswer'] ?? '').toString();
    final rationale = (r['rationale'] ?? '').toString();

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: correct ? AppColors.successBg : AppColors.errorBg,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    correct ? 'Correct' : 'Incorrect',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: correct ? AppColors.success : AppColors.error,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'QUESTION $questionNum',
                  style: AppTextStyles.sectionLabel.copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              question,
              style: const TextStyle(
                fontSize: 15,
                height: 1.4,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'YOUR RESPONSE',
              style: AppTextStyles.sectionLabel.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 4),
            Text(
              userAnswer.isEmpty ? '(No answer)' : userAnswer,
              style: TextStyle(
                fontSize: 14,
                color: correct ? AppColors.success : AppColors.error,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (rationale.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.indigoBg.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AI Tutor Rationale',
                      style: AppTextStyles.sectionLabel.copyWith(
                        color: AppColors.indigo,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      rationale,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.45,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _resultCard(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFECEEF1)),
        boxShadow: kSoftCardShadow,
      ),
      child: Column(
        children: [
          Text(
            label.toUpperCase(),
            style: AppTextStyles.sectionLabel.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: AppTextStyles.displayLarge.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}
