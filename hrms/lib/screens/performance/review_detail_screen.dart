// hrms/lib/screens/performance/review_detail_screen.dart
// Review detail - View full performance review (matches web: Performance Review Details)

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../config/app_colors.dart';
import '../../widgets/bottom_navigation_bar.dart';
import '../../services/performance_service.dart';
import 'self_assessment_form_screen.dart';
import '../../widgets/app_tab_loader.dart';

class ReviewDetailScreen extends StatefulWidget {
  final String reviewId;

  const ReviewDetailScreen({super.key, required this.reviewId});

  @override
  State<ReviewDetailScreen> createState() => _ReviewDetailScreenState();
}

class _ReviewDetailScreenState extends State<ReviewDetailScreen> {
  final PerformanceService _performanceService = PerformanceService();
  Map<String, dynamic>? _review;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchReview();
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
        setState(() {
          _review = result['data']?['review'];
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
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Performance Review Details',
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
              child: _buildReviewContent(),
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
              label: const Text('Retry'),
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

  Widget _buildReviewContent() {
    final r = _review!;
    final period = r['reviewPeriod'] as Map<String, dynamic>?;
    final status = (r['status'] ?? '').toString();
    final managerId = r['managerId'] as Map<String, dynamic>?;
    final canSubmitSelfReview =
        status == 'self-review-pending' || status == 'draft';

    String periodStr = '';
    if (period != null) {
      try {
        final start = DateTime.tryParse(period['startDate']?.toString() ?? '');
        final end = DateTime.tryParse(period['endDate']?.toString() ?? '');
        if (start != null && end != null) {
          periodStr =
              '${DateFormat.yMMMd().format(start)} to ${DateFormat.yMMMd().format(end)}';
        }
      } catch (_) {}
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header: cycle • type, status badge
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${r['reviewCycle'] ?? 'Review'} • ${r['reviewType'] ?? ''}',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _getStatusColor(status).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _formatStatus(status),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _getStatusColor(status),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        // Review Period card
        _buildInfoCard(
          icon: Icons.calendar_today_rounded,
          title: 'Review Period',
          child: Text(
            periodStr,
            style: TextStyle(fontSize: 14, color: AppColors.textPrimary),
          ),
        ),
        if (r['finalRating'] != null) ...[
          const SizedBox(height: 16),
          _buildInfoCard(
            icon: Icons.emoji_events_rounded,
            title: 'Final Rating',
            child: Row(
              children: [
                Icon(Icons.star_rounded, size: 28, color: AppColors.warning),
                const SizedBox(width: 8),
                Text(
                  '${(r['finalRating'] as num).toStringAsFixed(1)}/5.0',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
        if (r['selfReview'] != null) ...[
          const SizedBox(height: 16),
          _buildReviewSectionCard(
            icon: Icons.person_rounded,
            title: 'Your Self Review',
            child: _buildSelfReviewContent(
              r['selfReview'] as Map<String, dynamic>,
            ),
          ),
        ],
        if (r['managerReview'] != null) ...[
          const SizedBox(height: 16),
          _buildReviewSectionCard(
            icon: Icons.groups_rounded,
            title: 'Manager Review',
            subtitle: managerId != null
                ? 'by ${managerId['name'] ?? ''}'
                : null,
            child: _buildManagerReviewContent(
              r['managerReview'] as Map<String, dynamic>,
            ),
          ),
        ],
        if (r['hrReview'] != null) ...[
          const SizedBox(height: 16),
          _buildReviewSectionCard(
            icon: Icons.workspace_premium_rounded,
            title: 'HR Review',
            child: _buildHrReviewContent(r['hrReview'] as Map<String, dynamic>),
          ),
        ],
        if (r['finalComments'] != null &&
            (r['finalComments'] as String).isNotEmpty) ...[
          const SizedBox(height: 16),
          _buildInfoCard(
            icon: Icons.comment_rounded,
            title: 'Final Comments',
            child: Text(
              r['finalComments'] as String,
              style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
            ),
          ),
        ],
        const SizedBox(height: 24),
        // Action buttons
        Row(
          children: [
            OutlinedButton(
              onPressed: () => Navigator.pop(context),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: BorderSide(color: AppColors.primary),
              ),
              child: const Text('Back to Reviews'),
            ),
            if (canSubmitSelfReview) ...[
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          SelfAssessmentFormScreen(reviewId: widget.reviewId),
                    ),
                  ).then((_) => _fetchReview());
                },
                icon: const Icon(Icons.edit_document, size: 18),
                label: const Text('Submit Self Review'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String title,
    required Widget child,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 0,
      color: AppColors.surface,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildReviewSectionCard({
    required IconData icon,
    required String title,
    String? subtitle,
    required Widget child,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 0,
      color: AppColors.surface,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildSelfReviewContent(Map<String, dynamic> sr) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildRatingRow('Overall Rating', sr['overallRating']),
        if (sr['strengths'] != null && (sr['strengths'] as List).isNotEmpty)
          _buildListBlock('Strengths', sr['strengths'] as List),
        if (sr['areasForImprovement'] != null &&
            (sr['areasForImprovement'] as List).isNotEmpty)
          _buildListBlock(
            'Areas for Improvement',
            sr['areasForImprovement'] as List,
          ),
        if (sr['achievements'] != null &&
            (sr['achievements'] as List).isNotEmpty)
          _buildListBlock('Achievements', sr['achievements'] as List),
        if (sr['challenges'] != null && (sr['challenges'] as List).isNotEmpty)
          _buildListBlock('Challenges', sr['challenges'] as List),
        if (sr['goalsAchieved'] != null &&
            (sr['goalsAchieved'] as List).isNotEmpty)
          _buildListBlock('Goals Achieved', sr['goalsAchieved'] as List),
        if (sr['comments'] != null && sr['comments'].toString().isNotEmpty)
          _buildFeedbackBlock('Comments', sr['comments'].toString()),
      ],
    );
  }

  Widget _buildManagerReviewContent(Map<String, dynamic> mr) {
    final categories = [
      ('Overall', mr['overallRating']),
      ('Technical Skills', mr['technicalSkills']),
      ('Communication', mr['communication']),
      ('Teamwork', mr['teamwork']),
      ('Leadership', mr['leadership']),
      ('Problem Solving', mr['problemSolving']),
      ('Punctuality', mr['punctuality']),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...categories
            .where((c) => c.$2 != null)
            .map((c) => _buildRatingRow(c.$1, c.$2)),
        if (mr['feedback'] != null && mr['feedback'].toString().isNotEmpty)
          _buildFeedbackBlock('Feedback', mr['feedback'].toString()),
        if (mr['recommendations'] != null &&
            mr['recommendations'].toString().isNotEmpty)
          _buildFeedbackBlock(
            'Recommendations',
            mr['recommendations'].toString(),
          ),
      ],
    );
  }

  Widget _buildHrReviewContent(Map<String, dynamic> hr) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildRatingRow('Overall', hr['overallRating']),
        _buildRatingRow(
          'Company Values Alignment',
          hr['alignmentWithCompanyValues'],
        ),
        _buildRatingRow('Growth Potential', hr['growthPotential']),
        if (hr['feedback'] != null && hr['feedback'].toString().isNotEmpty)
          _buildFeedbackBlock('Feedback', hr['feedback'].toString()),
        if (hr['recommendations'] != null &&
            hr['recommendations'].toString().isNotEmpty)
          _buildFeedbackBlock(
            'Recommendations',
            hr['recommendations'].toString(),
          ),
      ],
    );
  }

  Widget _buildRatingRow(String label, dynamic value) {
    final v = value is num ? value.toDouble() : 0.0;
    final pct = (v / 5.0 * 100).clamp(0.0, 100.0);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: LinearProgressIndicator(
                  value: pct / 100,
                  backgroundColor: AppColors.divider,
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$v/5.0',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildListBlock(String label, List list) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          ...list
              .where((e) => e != null && e.toString().trim().isNotEmpty)
              .map(
                (e) => Padding(
                  padding: const EdgeInsets.only(left: 8, bottom: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '• ',
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          e.toString(),
                          style: TextStyle(
                            fontSize: 14,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }

  Widget _buildFeedbackBlock(String label, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            text,
            style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}
