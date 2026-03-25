// hrms/lib/screens/performance/self_assessment_form_screen.dart
// Self assessment form - Submit self review for a specific performance review

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../config/app_colors.dart';
import '../../widgets/bottom_navigation_bar.dart';
import '../../services/performance_service.dart';
import '../../utils/snackbar_utils.dart';
import '../../utils/error_message_utils.dart';
import '../../widgets/app_tab_loader.dart';

class SelfAssessmentFormScreen extends StatefulWidget {
  final String reviewId;

  const SelfAssessmentFormScreen({super.key, required this.reviewId});

  @override
  State<SelfAssessmentFormScreen> createState() =>
      _SelfAssessmentFormScreenState();
}

class _SelfAssessmentFormScreenState extends State<SelfAssessmentFormScreen> {
  final PerformanceService _performanceService = PerformanceService();
  final _formKey = GlobalKey<FormState>();
  Map<String, dynamic>? _review;
  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _error;

  int _overallRating = 0;
  final List<TextEditingController> _strengthsControllers = [
    TextEditingController(),
  ];
  final List<TextEditingController> _areasControllers = [
    TextEditingController(),
  ];
  final List<TextEditingController> _achievementsControllers = [
    TextEditingController(),
  ];
  final List<TextEditingController> _challengesControllers = [
    TextEditingController(),
  ];
  final List<TextEditingController> _goalsAchievedControllers = [
    TextEditingController(),
  ];
  final TextEditingController _commentsController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchReview();
  }

  @override
  void dispose() {
    for (final c in _strengthsControllers) c.dispose();
    for (final c in _areasControllers) c.dispose();
    for (final c in _achievementsControllers) c.dispose();
    for (final c in _challengesControllers) c.dispose();
    for (final c in _goalsAchievedControllers) c.dispose();
    _commentsController.dispose();
    super.dispose();
  }

  Future<void> _fetchReview() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final result = await _performanceService.getPerformanceReviewById(
        widget.reviewId,
      );
      if (mounted) {
        final review = result['data']?['review'];
        if (review != null) {
          final sr = review['selfReview'] as Map<String, dynamic>?;
          if (sr != null) {
            for (final c in _strengthsControllers) c.dispose();
            for (final c in _areasControllers) c.dispose();
            for (final c in _achievementsControllers) c.dispose();
            for (final c in _challengesControllers) c.dispose();
            for (final c in _goalsAchievedControllers) c.dispose();
            setState(() {
              _overallRating = (sr['overallRating'] as num?)?.toInt() ?? 0;
              _strengthsControllers.clear();
              for (final s in (sr['strengths'] as List?) ?? ['']) {
                _strengthsControllers.add(
                  TextEditingController(text: s?.toString() ?? ''),
                );
              }
              if (_strengthsControllers.isEmpty)
                _strengthsControllers.add(TextEditingController());
              _areasControllers.clear();
              for (final a in (sr['areasForImprovement'] as List?) ?? ['']) {
                _areasControllers.add(
                  TextEditingController(text: a?.toString() ?? ''),
                );
              }
              if (_areasControllers.isEmpty)
                _areasControllers.add(TextEditingController());
              _achievementsControllers.clear();
              for (final a in (sr['achievements'] as List?) ?? ['']) {
                _achievementsControllers.add(
                  TextEditingController(text: a?.toString() ?? ''),
                );
              }
              if (_achievementsControllers.isEmpty)
                _achievementsControllers.add(TextEditingController());
              _challengesControllers.clear();
              for (final c in (sr['challenges'] as List?) ?? ['']) {
                _challengesControllers.add(
                  TextEditingController(text: c?.toString() ?? ''),
                );
              }
              if (_challengesControllers.isEmpty)
                _challengesControllers.add(TextEditingController());
              _goalsAchievedControllers.clear();
              for (final g in (sr['goalsAchieved'] as List?) ?? ['']) {
                _goalsAchievedControllers.add(
                  TextEditingController(text: g?.toString() ?? ''),
                );
              }
              if (_goalsAchievedControllers.isEmpty)
                _goalsAchievedControllers.add(TextEditingController());
              _commentsController.text = sr['comments']?.toString() ?? '';
            });
          }
        }
        setState(() {
          _review = review;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceAll('Exception: ', '');
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _submit() async {
    if (_overallRating == 0) {
      SnackBarUtils.showSnackBar(
        context,
        'Please provide an overall rating',
        isError: true,
      );
      return;
    }
    setState(() => _isSubmitting = true);
    try {
      await _performanceService.submitSelfReview(
        reviewId: widget.reviewId,
        overallRating: _overallRating,
        strengths: _strengthsControllers
            .map((c) => c.text.trim())
            .where((s) => s.isNotEmpty)
            .toList(),
        areasForImprovement: _areasControllers
            .map((c) => c.text.trim())
            .where((s) => s.isNotEmpty)
            .toList(),
        achievements: _achievementsControllers
            .map((c) => c.text.trim())
            .where((s) => s.isNotEmpty)
            .toList(),
        challenges: _challengesControllers
            .map((c) => c.text.trim())
            .where((s) => s.isNotEmpty)
            .toList(),
        goalsAchieved: _goalsAchievedControllers
            .map((c) => c.text.trim())
            .where((s) => s.isNotEmpty)
            .toList(),
        comments: _commentsController.text.trim(),
      );
      if (mounted) {
        SnackBarUtils.showSnackBar(
          context,
          'Self review submitted successfully',
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        SnackBarUtils.showSnackBar(
          context,
          ErrorMessageUtils.toUserFriendlyMessage(e),
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _addItem(List<TextEditingController> list) {
    setState(() => list.add(TextEditingController()));
  }

  void _removeItem(List<TextEditingController> list, int index) {
    if (list.length > 1) {
      setState(() {
        list[index].dispose();
        list.removeAt(index);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Self Assessment',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
        elevation: 0,
        centerTitle: true,
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
      ),
      bottomNavigationBar: const AppBottomNavigationBar(currentIndex: -1),
      body: _isLoading
          ? const Center(child: AppTabLoader())
          : _error != null
          ? _buildErrorState()
          : _review == null
          ? const Center(child: Text('Review not found'))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildReviewHeader(),
                    const SizedBox(height: 24),
                    _buildRatingSection(),
                    _buildListSection('Strengths', _strengthsControllers),
                    _buildListSection(
                      'Areas for Improvement',
                      _areasControllers,
                    ),
                    _buildListSection('Achievements', _achievementsControllers),
                    _buildListSection('Challenges', _challengesControllers),
                    _buildListSection(
                      'Goals Achieved',
                      _goalsAchievedControllers,
                    ),
                    _buildCommentsSection(),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isSubmitting ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _isSubmitting
                            ? const SizedBox(
                                height: 24,
                                width: 24,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : Text('Submit Review'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline_rounded, size: 64, color: AppColors.error),
            const SizedBox(height: 16),
            Text(
              _error ?? 'Failed to load review',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _fetchReview,
              icon: const Icon(Icons.refresh_rounded),
              label: Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReviewHeader() {
    final r = _review!;
    final period = r['reviewPeriod'] as Map<String, dynamic>?;
    String periodStr = '';
    if (period != null) {
      try {
        final start = DateTime.tryParse(period['startDate']?.toString() ?? '');
        final end = DateTime.tryParse(period['endDate']?.toString() ?? '');
        if (start != null && end != null) {
          periodStr =
              '${DateFormat.yMMMd().format(start)} - ${DateFormat.yMMMd().format(end)}';
        }
      } catch (_) {}
    }
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 0,
      color: AppColors.primary.withOpacity(0.08),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              r['reviewCycle'] ?? 'Review',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            Text(
              '${r['reviewType'] ?? ''} · $periodStr',
              style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRatingSection() {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 0,
      color: AppColors.surface,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Overall Rating',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: List.generate(5, (i) {
                final rating = i + 1;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => setState(() => _overallRating = rating),
                    child: Icon(
                      Icons.star_rounded,
                      size: 40,
                      color: rating <= _overallRating
                          ? AppColors.warning
                          : AppColors.divider,
                    ),
                  ),
                );
              }),
            ),
            Text(
              '$_overallRating/5',
              style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildListSection(
    String title,
    List<TextEditingController> controllers,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 0,
      color: AppColors.surface,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            ...List.generate(controllers.length, (i) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: controllers[i],
                        decoration: InputDecoration(
                          hintText: 'Enter $title.toLowerCase()',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                        ),
                      ),
                    ),
                    if (controllers.length > 1)
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline_rounded),
                        onPressed: () => _removeItem(controllers, i),
                        color: AppColors.error,
                      ),
                  ],
                ),
              );
            }),
            TextButton.icon(
              onPressed: () => _addItem(controllers),
              icon: const Icon(Icons.add_rounded, size: 20),
              label: Text('Add'),
              style: TextButton.styleFrom(foregroundColor: AppColors.primary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCommentsSection() {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 0,
      color: AppColors.surface,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Additional Comments',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _commentsController,
              maxLines: 5,
              decoration: InputDecoration(
                hintText:
                    'Add any additional comments about your performance...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.all(16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
