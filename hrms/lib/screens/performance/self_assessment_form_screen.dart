// hrms/lib/screens/performance/self_assessment_form_screen.dart
// Self assessment form - Submit self review for a specific performance review

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../config/app_colors.dart';
import '../../config/app_text_styles.dart';
import '../../widgets/app_card.dart';
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
    for (final c in _strengthsControllers) {
      c.dispose();
    }
    for (final c in _areasControllers) {
      c.dispose();
    }
    for (final c in _achievementsControllers) {
      c.dispose();
    }
    for (final c in _challengesControllers) {
      c.dispose();
    }
    for (final c in _goalsAchievedControllers) {
      c.dispose();
    }
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
            for (final c in _strengthsControllers) {
              c.dispose();
            }
            for (final c in _areasControllers) {
              c.dispose();
            }
            for (final c in _achievementsControllers) {
              c.dispose();
            }
            for (final c in _challengesControllers) {
              c.dispose();
            }
            for (final c in _goalsAchievedControllers) {
              c.dispose();
            }
            setState(() {
              _overallRating = (sr['overallRating'] as num?)?.toInt() ?? 0;
              _strengthsControllers.clear();
              for (final s in (sr['strengths'] as List?) ?? ['']) {
                _strengthsControllers.add(
                  TextEditingController(text: s?.toString() ?? ''),
                );
              }
              if (_strengthsControllers.isEmpty) {
                _strengthsControllers.add(TextEditingController());
              }
              _areasControllers.clear();
              for (final a in (sr['areasForImprovement'] as List?) ?? ['']) {
                _areasControllers.add(
                  TextEditingController(text: a?.toString() ?? ''),
                );
              }
              if (_areasControllers.isEmpty) {
                _areasControllers.add(TextEditingController());
              }
              _achievementsControllers.clear();
              for (final a in (sr['achievements'] as List?) ?? ['']) {
                _achievementsControllers.add(
                  TextEditingController(text: a?.toString() ?? ''),
                );
              }
              if (_achievementsControllers.isEmpty) {
                _achievementsControllers.add(TextEditingController());
              }
              _challengesControllers.clear();
              for (final c in (sr['challenges'] as List?) ?? ['']) {
                _challengesControllers.add(
                  TextEditingController(text: c?.toString() ?? ''),
                );
              }
              if (_challengesControllers.isEmpty) {
                _challengesControllers.add(TextEditingController());
              }
              _goalsAchievedControllers.clear();
              for (final g in (sr['goalsAchieved'] as List?) ?? ['']) {
                _goalsAchievedControllers.add(
                  TextEditingController(text: g?.toString() ?? ''),
                );
              }
              if (_goalsAchievedControllers.isEmpty) {
                _goalsAchievedControllers.add(TextEditingController());
              }
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
          tooltip: 'Back',
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Self Assessment'),
      ),
      bottomNavigationBar: const AppBottomNavigationBar(currentIndex: -1),
      body: _isLoading
          ? const Center(child: AppTabLoader())
          : _error != null
          ? _buildErrorState()
          : _review == null
          ? const Center(
              child: Text('Review not found', style: AppTextStyles.bodySmall))
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildReviewHeader(),
                    const SizedBox(height: 16),
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
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isSubmitting ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(0, 52),
                        ),
                        child: _isSubmitting
                            ? SizedBox(
                                height: 22,
                                width: 22,
                                child: CircularProgressIndicator(
                                  color: AppColors.onPrimary,
                                  strokeWidth: 2,
                                ),
                              )
                            : Text('Submit'),
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
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: AppColors.errorBg,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.error_outline_rounded,
                  size: 32, color: AppColors.error),
            ),
            const SizedBox(height: 16),
            Text(
              _error ?? 'Failed to load review',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodySmall,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _fetchReview,
              icon: const Icon(Icons.refresh_rounded, size: 20),
              label: Text('Retry'),
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.assignment_ind_outlined,
                size: 22, color: AppColors.primaryText),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r['reviewCycle'] ?? 'Review',
                  style: AppTextStyles.headingMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  '${r['reviewType'] ?? ''} · $periodStr',
                  style: AppTextStyles.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionCard({required String title, required Widget child}) {
    return AppCard(
      margin: const EdgeInsets.only(bottom: 12),
      border: Border.all(color: const Color(0xFFECEEF1)),
      child: SizedBox(
        width: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 4,
                  height: 16,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(title, style: AppTextStyles.headingSmall),
                ),
              ],
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildRatingSection() {
    return _sectionCard(
      title: 'Overall Rating',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: List.generate(5, (i) {
              final rating = i + 1;
              return Padding(
                padding: const EdgeInsets.only(right: 4),
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
          const SizedBox(height: 4),
          Text(
            '$_overallRating/5',
            style: AppTextStyles.bodySmall
                .copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildListSection(
    String title,
    List<TextEditingController> controllers,
  ) {
    return _sectionCard(
      title: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                      ),
                    ),
                  ),
                  if (controllers.length > 1)
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline_rounded,
                          size: 20),
                      tooltip: 'Remove',
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
          ),
        ],
      ),
    );
  }

  Widget _buildCommentsSection() {
    return _sectionCard(
      title: 'Additional Comments',
      child: TextFormField(
        controller: _commentsController,
        maxLines: 5,
        decoration: InputDecoration(
          hintText:
              'Add any additional comments about your performance...',
          contentPadding: const EdgeInsets.all(16),
        ),
      ),
    );
  }
}
