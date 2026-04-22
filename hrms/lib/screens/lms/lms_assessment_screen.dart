// hrms/lib/screens/lms/lms_assessment_screen.dart
// Final Assessment - mirrors web /lms/assessment/:courseId

import 'dart:async';
import 'package:flutter/material.dart';
import '../../config/app_colors.dart';
import '../../services/lms_service.dart';
import '../../utils/snackbar_utils.dart' show SnackBarUtils;
import '../../utils/error_message_utils.dart';
import '../dashboard/dashboard_screen.dart';
import 'lms_course_detail_screen.dart';
import '../../widgets/app_tab_loader.dart';

class LmsAssessmentScreen extends StatefulWidget {
  final String courseId;

  const LmsAssessmentScreen({super.key, required this.courseId});

  @override
  State<LmsAssessmentScreen> createState() => _LmsAssessmentScreenState();
}

class _LmsAssessmentScreenState extends State<LmsAssessmentScreen> {
  final LmsService _lmsService = LmsService();
  dynamic _course;
  List<Map<String, dynamic>> _flatQuestions = [];
  bool _loading = true;
  int _currentIndex = 0;
  final Map<String, List<String>> _selectedAnswers = {};
  int _timeRemaining = 1800; // 30 min
  Timer? _timer;
  bool _isFinished = false;
  Map<String, dynamic>? _results;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _loadCourse();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        if (_timeRemaining <= 1) {
          _timer?.cancel();
          _submit();
        } else {
          _timeRemaining--;
        }
      });
    });
  }

  Future<void> _loadCourse() async {
    setState(() => _loading = true);
    final res = await _lmsService.getCourseDetails(widget.courseId);
    if (mounted) {
      setState(() {
        _loading = false;
        _course = res['data']?['course'];
        _flatQuestions = _buildFlatQuestions();
        if (_flatQuestions.isNotEmpty && !_isFinished) {
          _startTimer();
        }
      });
    }
  }

  List<Map<String, dynamic>> _buildFlatQuestions() {
    final groups = _course?['assessmentQuestions'] as List? ?? [];
    final list = <Map<String, dynamic>>[];
    for (final g in groups) {
      final group = g is Map ? Map<String, dynamic>.from(g) : {};
      final questions = group['questions'] as List? ?? [];
      final lessonTitle = group['lessonTitle']?.toString() ?? 'Course';
      for (final q in questions) {
        final qMap = q is Map
            ? Map<String, dynamic>.from(q)
            : <String, dynamic>{};
        qMap['lessonTitle'] = lessonTitle;
        final id = qMap['id']?.toString() ?? qMap['_id']?.toString();
        if (id != null) qMap['id'] = id;
        list.add(Map<String, dynamic>.from(qMap));
      }
    }
    return list;
  }

  void _selectAnswer(
    String questionId,
    String answer, {
    bool isMultiple = false,
  }) {
    setState(() {
      final current = _selectedAnswers[questionId] ?? [];
      if (isMultiple) {
        if (current.contains(answer)) {
          _selectedAnswers[questionId] = current
              .where((a) => a != answer)
              .toList();
        } else {
          _selectedAnswers[questionId] = [...current, answer];
        }
      } else {
        _selectedAnswers[questionId] = [answer];
      }
    });
  }

  void _setShortAnswer(String questionId, String value) {
    setState(() => _selectedAnswers[questionId] = [value]);
  }

  Future<void> _submit() async {
    if (_isSubmitting || _isFinished) return;
    setState(() => _isSubmitting = true);
    _timer?.cancel();

    final answers = _selectedAnswers.entries
        .map((e) => {'questionId': e.key, 'answers': e.value})
        .toList();

    final res = await _lmsService.submitCourseAssessment(
      widget.courseId,
      answers: answers,
    );
    if (mounted) {
      setState(() {
        _isSubmitting = false;
        if (res['success'] == true && res['data'] != null) {
          _isFinished = true;
          _results = res['data'] as Map<String, dynamic>;
          SnackBarUtils.showSnackBar(
            context,
            'Assessment submitted. Score: ${_results!['score']}%',
          );
        } else {
          SnackBarUtils.showSnackBar(
            context,
            ErrorMessageUtils.sanitizeForDisplay(res['message']?.toString(), fallback: 'Submission failed'),
            isError: true,
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context),
          ),
          title: const Text('Final Assessment'),
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.textPrimary,
        ),
        body: const Center(child: AppTabLoader()),
      );
    }

    if (_course == null || _flatQuestions.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context),
          ),
          title: const Text('Final Assessment'),
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.textPrimary,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.quiz_outlined, size: 64, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(
                'No assessment questions for this course.',
                style: TextStyle(color: Colors.grey[600]),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Back to Course'),
              ),
            ],
          ),
        ),
      );
    }

    if (_isFinished && _results != null) {
      return _buildResultsView();
    }

    return _buildQuizView();
  }

  Widget _buildResultsView() {
    final passed = _results!['passed'] == true;
    final score = _results!['score'] ?? 0;
    final questionResults = _results!['questionResults'] as List? ?? [];
    final passingScore = _course?['qualificationScore'] ?? 80;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Assessment Complete'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Icon(
                      passed ? Icons.emoji_events : Icons.cancel,
                      size: 64,
                      color: passed ? Colors.green : Colors.red,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      passed ? 'Assessment Passed' : 'Assessment Failed',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Performance report for ${_course?['title'] ?? 'Course'}',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildScoreChip(
                          'Your Score',
                          '$score%',
                          passed ? Colors.green : Colors.red,
                        ),
                        const SizedBox(width: 24),
                        _buildScoreChip(
                          'Passing Mark',
                          '$passingScore%',
                          Colors.grey,
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ElevatedButton.icon(
                          onPressed: () {
                            Navigator.of(context).pushReplacement(
                              MaterialPageRoute(
                                builder: (_) => LmsCourseDetailScreen(
                                  courseId: widget.courseId,
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.book),
                          label: const Text('Go to Course'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 12),
                        OutlinedButton(
                          onPressed: () {
                            Navigator.of(context).pushAndRemoveUntil(
                              MaterialPageRoute(
                                builder: (_) =>
                                    DashboardScreen(initialIndex: 2),
                              ),
                              (r) => r.isFirst,
                            );
                          },
                          child: const Text('Dashboard'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (questionResults.isNotEmpty) ...[
              const SizedBox(height: 24),
              const Text(
                'Answer breakdown',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              ...questionResults.asMap().entries.map((entry) {
                final idx = entry.key;
                final r = entry.value as Map<String, dynamic>;
                final q = _flatQuestions.firstWhere(
                  (q) =>
                      (q['id']?.toString() ?? q['_id']?.toString()) ==
                      r['questionId']?.toString(),
                  orElse: () => <String, dynamic>{'questionText': 'Question'},
                );
                final isCorrect = r['isCorrect'] == true;
                String fmt(a) =>
                    a is List ? (a).join(', ') : a?.toString() ?? '—';
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  color: isCorrect
                      ? Colors.green.withOpacity(0.05)
                      : Colors.red.withOpacity(0.05),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Q${idx + 1}. ${q['questionText'] ?? 'Question'}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: isCorrect
                                    ? Colors.green.withOpacity(0.2)
                                    : Colors.red.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '${r['marksAwarded'] ?? 0}/${r['marksTotal'] ?? 1}',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: isCorrect
                                      ? Colors.green.shade800
                                      : Colors.red.shade800,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Your answer: ${fmt(r['userAnswer'])}',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[700],
                          ),
                        ),
                        if (!isCorrect)
                          Text(
                            'Correct: ${fmt(r['correctAnswer'])}',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.green.shade700,
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildScoreChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey[600],
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuizView() {
    final question = _flatQuestions[_currentIndex];
    final id = question['id']?.toString() ?? question['_id']?.toString() ?? '';
    final qType = (question['type'] ?? 'MCQ').toString();
    final options =
        question['options'] as List? ??
        (qType == 'True / False' ? ['True', 'False'] : []);
    final answers = _selectedAnswers[id] ?? [];
    final progress = ((_currentIndex + 1) / _flatQuestions.length) * 100;
    final minutes = _timeRemaining ~/ 60;
    final seconds = _timeRemaining % 60;
    final canNext =
        (answers.isNotEmpty || qType == 'Short Answer') && !_isSubmitting;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Final Assessment'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: _timeRemaining < 300
                  ? Colors.red.withOpacity(0.1)
                  : Colors.grey.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.timer,
                  size: 18,
                  color: _timeRemaining < 300 ? Colors.red : Colors.grey[700],
                ),
                const SizedBox(width: 6),
                Text(
                  '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _timeRemaining < 300 ? Colors.red : Colors.grey[800],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Question ${_currentIndex + 1} of ${_flatQuestions.length}',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          question['lessonTitle']?.toString() ?? '',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: progress / 100,
                    backgroundColor: Colors.grey[200],
                    valueColor: AlwaysStoppedAnimation<Color>(
                      AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      question['questionText']?.toString() ?? 'Question',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (qType == 'Short Answer')
                      TextFormField(
                        key: ValueKey(id),
                        initialValue: answers.isNotEmpty ? answers[0] : '',
                        maxLines: 4,
                        decoration: const InputDecoration(
                          hintText: 'Type your answer...',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (v) => _setShortAnswer(id, v),
                      )
                    else if (qType == 'Multiple Correct')
                      ...options.map((opt) {
                        final optStr = opt.toString();
                        final isSelected = answers.contains(optStr);
                        return CheckboxListTile(
                          value: isSelected,
                          onChanged: (_) =>
                              _selectAnswer(id, optStr, isMultiple: true),
                          title: Text(optStr),
                          controlAffinity: ListTileControlAffinity.leading,
                        );
                      })
                    else
                      ...options.map((opt) {
                        final optStr = opt.toString();
                        final isSelected =
                            answers.isNotEmpty && answers[0] == optStr;
                        return RadioListTile<String>(
                          value: optStr,
                          groupValue: answers.isNotEmpty ? answers[0] : null,
                          onChanged: (_) => _selectAnswer(id, optStr),
                          title: Text(optStr),
                        );
                      }),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton.icon(
                  onPressed: _currentIndex > 0
                      ? () => setState(() => _currentIndex--)
                      : null,
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Previous'),
                ),
                ElevatedButton.icon(
                  onPressed: canNext
                      ? () {
                          if (_currentIndex < _flatQuestions.length - 1) {
                            setState(() => _currentIndex++);
                          } else {
                            _submit();
                          }
                        }
                      : null,
                  icon: const Icon(Icons.arrow_forward),
                  label: Text(
                    _currentIndex == _flatQuestions.length - 1
                        ? 'Finish Assessment'
                        : 'Next',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
