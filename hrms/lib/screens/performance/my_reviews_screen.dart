// hrms/lib/screens/performance/my_reviews_screen.dart
// My Reviews - View performance reviews with View Details and Submit Review actions

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../config/app_colors.dart';
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
        : _reviews.isEmpty
        ? _buildEmptyState()
        : RefreshIndicator(
            onRefresh: _fetchReviews,
            color: AppColors.primary,
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                    child: Text(
                      'View and track all your performance reviews',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final review = _reviews[index] as Map<String, dynamic>;
                      return _buildReviewCard(review);
                    }, childCount: _reviews.length),
                  ),
                ),
              ],
            ),
          );

    if (widget.embeddedInModule) return body;
    return Scaffold(
      backgroundColor: AppColors.background,
      drawer: const AppDrawer(),
      appBar: AppBar(
        leading: const MenuIconButton(),
        title: Text(
          'My Performance Reviews',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22),
        ),
        elevation: 0,
        centerTitle: true,
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
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
            Icon(Icons.error_outline_rounded, size: 64, color: AppColors.error),
            const SizedBox(height: 16),
            Text(
              _error ?? 'Failed to load reviews',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _fetchReviews,
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

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.description_outlined,
              size: 64,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 16),
            Text(
              'No performance reviews found',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
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

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      elevation: 0,
      color: AppColors.surface,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    reviewCycle,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: _getStatusColor(status).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    _formatStatus(status),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: _getStatusColor(status),
                    ),
                  ),
                ),
              ],
            ),
            if (periodStr.isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(
                    Icons.calendar_today_rounded,
                    size: 12,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    periodStr,
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
            if (reviewType.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                'Type: $reviewType',
                style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
              ),
            ],
            if (managerId != null) ...[
              const SizedBox(height: 4),
              Text(
                'Reviewer: ${managerId['name'] ?? ''} (${managerId['designation'] ?? ''})',
                style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
              ),
            ],
            if (selfReview != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.star_rounded, size: 12, color: AppColors.warning),
                  const SizedBox(width: 4),
                  Text(
                    'Self Review: ${selfReview['overallRating'] ?? 'N/A'}/5.0',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
            if (managerReview != null) ...[
              const SizedBox(height: 2),
              Row(
                children: [
                  Icon(Icons.star_rounded, size: 12, color: AppColors.warning),
                  const SizedBox(width: 4),
                  Text(
                    'Manager Review: ${managerReview['overallRating'] ?? 'N/A'}/5.0',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
            if (finalRating != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.star_rounded, size: 14, color: AppColors.warning),
                  const SizedBox(width: 4),
                  Text(
                    '${(finalRating as num).toStringAsFixed(1)}/5.0 Final Rating',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ReviewDetailScreen(reviewId: id),
                      ),
                    ).then((_) => _fetchReviews());
                  },
                  icon: const Icon(Icons.visibility_rounded, size: 14),
                  label: Text('View Details'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: BorderSide(color: AppColors.primary),
                  ),
                ),
                if (canSubmitSelfReview) ...[
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              SelfAssessmentFormScreen(reviewId: id),
                        ),
                      ).then((_) => _fetchReviews());
                    },
                    icon: const Icon(Icons.edit_rounded, size: 14),
                    label: Text('Submit Review'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
