// hrms/lib/screens/performance/my_reviews_screen.dart
// My Reviews - View performance reviews with View Details and Submit Review actions

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../config/app_colors.dart';
import '../../config/app_text_styles.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/bottom_navigation_bar.dart';
import '../../widgets/menu_icon_button.dart';
import '../../services/performance_service.dart';
import 'review_detail_screen.dart';
import 'self_assessment_form_screen.dart';
import '../../widgets/app_tab_loader.dart';

class MyReviewsScreen extends StatefulWidget {
  final bool embeddedInModule;
  final int refreshTrigger;
  final int currentTabIndex;
  final int performanceTabIndex;

  const MyReviewsScreen({
    super.key,
    this.embeddedInModule = false,
    this.refreshTrigger = 0,
    this.currentTabIndex = 0,
    this.performanceTabIndex = 2,
  });

  @override
  State<MyReviewsScreen> createState() => _MyReviewsScreenState();
}

class _MyReviewsScreenState extends State<MyReviewsScreen> {
  final PerformanceService _performanceService = PerformanceService();
  List<dynamic> _reviews = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchReviews();
  }

  @override
  void didUpdateWidget(MyReviewsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshTrigger != widget.refreshTrigger &&
        widget.currentTabIndex == widget.performanceTabIndex) {
      _fetchReviews();
    }
  }

  Future<void> _fetchReviews() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final result = await _performanceService.getPerformanceReviews(
        page: 1,
        limit: 50,
      );
      if (mounted) {
        final data = result['data'];
        setState(() {
          _reviews = data?['reviews'] ?? [];
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

  Color _getStatusColor(String status) {
    if (status == 'completed') return AppColors.success;
    if (status.contains('submitted')) return AppColors.info;
    if (status.contains('pending') || status == 'draft') {
      return AppColors.warning;
    }
    return AppColors.textSecondary;
  }

  String _formatStatus(String status) {
    return status
        .replaceAll('-', ' ')
        .split(' ')
        .map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final body = _isLoading
        ? const Center(child: AppTabLoader())
        : _error != null
        ? _buildErrorState()
        : RefreshIndicator(
            onRefresh: _fetchReviews,
            color: AppColors.primary,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(),
                  const SizedBox(height: 20),
                  if (_reviews.isEmpty)
                    _buildEmptyCard()
                  else
                    for (final review in _reviews)
                      _buildReviewCard(review as Map<String, dynamic>),
                ],
              ),
            ),
          );

    if (widget.embeddedInModule) return body;
    return Scaffold(
      backgroundColor: AppColors.background,
      drawer: const AppDrawer(),
      appBar: AppBar(
        leading: const MenuIconButton(),
        title: const Text('My Performance Reviews'),
      ),
      body: body,
      bottomNavigationBar: const AppBottomNavigationBar(currentIndex: -1),
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
              _error ?? 'Failed to load reviews',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodySmall,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _fetchReviews,
              icon: const Icon(Icons.refresh_rounded, size: 20),
              label: Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('My Reviews', style: AppTextStyles.headingLarge),
        const SizedBox(height: 4),
        Text(
          'Manage your performance track and feedback.',
          style: AppTextStyles.bodySmall,
        ),
      ],
    );
  }

  Widget _buildEmptyCard() {
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      border: Border.all(color: const Color(0xFFECEEF1)),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.description_outlined,
              size: 30,
              color: AppColors.primaryText,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'No performance reviews found',
            textAlign: TextAlign.center,
            style: AppTextStyles.headingSmall,
          ),
          const SizedBox(height: 8),
          Text(
            "Your performance journey hasn't started yet. "
            'Once your manager initiates a review cycle, it will appear here.',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _buildMetaRow(IconData icon, String text, {Color? iconColor}) {
    return Row(
      children: [
        Icon(icon, size: 14, color: iconColor ?? AppColors.textSecondary),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: AppTextStyles.bodySmall,
          ),
        ),
      ],
    );
  }

  Widget _buildRatingRow(IconData icon, Color color, String text) {
    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: AppTextStyles.bodySmall.copyWith(
              fontWeight: FontWeight.w500,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildReviewCard(Map<String, dynamic> review) {
    final id = review['_id'] as String? ?? '';
    final reviewCycle = review['reviewCycle'] ?? 'N/A';
    final reviewType = review['reviewType'] ?? '';
    final status = (review['status'] ?? '').toString();
    final period = review['reviewPeriod'] as Map<String, dynamic>?;
    final managerId = review['managerId'] as Map<String, dynamic>?;
    final finalRating = review['finalRating'];
    final selfReview = review['selfReview'] as Map<String, dynamic>?;
    final managerReview = review['managerReview'] as Map<String, dynamic>?;
    final hrReview = review['hrReview'] as Map<String, dynamic>?;

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

    final canSubmitSelfReview =
        status == 'self-review-pending' || status == 'draft';

    final statusColor = _getStatusColor(status);
    final hasRatings = selfReview != null ||
        managerReview != null ||
        hrReview != null ||
        finalRating != null;

    return AppCard(
      margin: const EdgeInsets.only(bottom: 12),
      border: Border.all(color: const Color(0xFFECEEF1)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.description_outlined,
                    size: 20, color: AppColors.primaryText),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    reviewCycle,
                    style: AppTextStyles.headingSmall,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  _formatStatus(status),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          if (periodStr.isNotEmpty) ...[
            const SizedBox(height: 12),
            _buildMetaRow(Icons.calendar_today_outlined, periodStr),
          ],
          if (reviewType.isNotEmpty) ...[
            const SizedBox(height: 6),
            _buildMetaRow(Icons.category_outlined, 'Type: $reviewType'),
          ],
          if (managerId != null) ...[
            const SizedBox(height: 6),
            _buildMetaRow(
              Icons.person_outline_rounded,
              'Reviewer: ${managerId['name'] ?? ''} (${managerId['designation'] ?? ''})',
            ),
          ],
          if (hasRatings) ...[
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
          ],
          if (selfReview != null) ...[
            _buildRatingRow(
              Icons.star_rounded,
              AppColors.warning,
              'Self Review: ${selfReview['overallRating'] ?? 'N/A'}/5.0',
            ),
            const SizedBox(height: 6),
          ],
          if (managerReview != null) ...[
            _buildRatingRow(
              Icons.supervisor_account_outlined,
              AppColors.info,
              'Manager Review: ${managerReview['overallRating'] ?? 'N/A'}/5.0',
            ),
            const SizedBox(height: 6),
          ],
          if (hrReview != null) ...[
            _buildRatingRow(
              Icons.badge_outlined,
              AppColors.primaryText,
              'HR Review: ${hrReview['overallRating'] ?? 'N/A'}/5.0',
            ),
            const SizedBox(height: 6),
          ],
          if (finalRating != null) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.warningBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.star_rounded, size: 18, color: AppColors.warning),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      '${(finalRating as num).toStringAsFixed(1)}/5.0 Final Rating',
                      style: AppTextStyles.label.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ReviewDetailScreen(reviewId: id),
                      ),
                    ).then((_) => _fetchReviews());
                  },
                  child: const Text('View Details'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SelfAssessmentFormScreen(reviewId: id),
                      ),
                    ).then((_) => _fetchReviews());
                  },
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Submit'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
