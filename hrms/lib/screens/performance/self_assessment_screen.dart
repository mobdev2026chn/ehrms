// hrms/lib/screens/performance/self_assessment_screen.dart
// Self Assessment - List available review cycles, show status, Start Assessment button

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../config/app_colors.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/bottom_navigation_bar.dart';
import '../../widgets/menu_icon_button.dart';
import '../../services/performance_service.dart';
import 'self_assessment_form_screen.dart';
import 'self_assessment_create_screen.dart';
import 'my_reviews_screen.dart';
import '../../widgets/app_tab_loader.dart';

class SelfAssessmentScreen extends StatefulWidget {
  final bool embeddedInModule;
  final int refreshTrigger;
  final int currentTabIndex;
  final int performanceTabIndex;

  const SelfAssessmentScreen({
    super.key,
    this.embeddedInModule = false,
    this.refreshTrigger = 0,
    this.currentTabIndex = 0,
    this.performanceTabIndex = 3,
  });

  @override
  State<SelfAssessmentScreen> createState() => _SelfAssessmentScreenState();
}

class _SelfAssessmentScreenState extends State<SelfAssessmentScreen> {
  final PerformanceService _performanceService = PerformanceService();
  List<dynamic> _pendingReviews = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchPendingReviews();
  }

  @override
  void didUpdateWidget(SelfAssessmentScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshTrigger != widget.refreshTrigger &&
        widget.currentTabIndex == widget.performanceTabIndex) {
      _fetchPendingReviews();
    }
  }

  Future<void> _fetchPendingReviews() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final result = await _performanceService.getPerformanceReviews(
        page: 1,
        limit: 50,
        status: 'self-review-pending',
      );
      if (mounted) {
        final data = result['data'];
        setState(() {
          _pendingReviews = data?['reviews'] ?? [];
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

  Future<void> _openCreateSelfAssessment() async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const SelfAssessmentCreateScreen()),
    );
    if (created == true) _fetchPendingReviews();
  }

  Widget _buildCreateBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: _openCreateSelfAssessment,
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Create Self Assessment'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primary,
            side: BorderSide(color: AppColors.primary),
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final content = _isLoading
        ? const Center(child: AppTabLoader())
        : _error != null
        ? _buildErrorState()
        : _pendingReviews.isEmpty
        ? _buildEmptyState()
        : RefreshIndicator(
            onRefresh: _fetchPendingReviews,
            color: AppColors.primary,
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              itemCount: _pendingReviews.length,
              itemBuilder: (context, index) {
                final review = _pendingReviews[index] as Map<String, dynamic>;
                return _buildReviewCard(review);
              },
            ),
          );

    final body = Column(
      children: [
        _buildCreateBar(),
        Expanded(child: content),
      ],
    );

    if (widget.embeddedInModule) return body;
    return Scaffold(
      backgroundColor: AppColors.background,
      drawer: const AppDrawer(),
      appBar: AppBar(
        leading: const MenuIconButton(),
        title: const Text(
          'Self Assessment',
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
              onPressed: _fetchPendingReviews,
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

  Widget _buildEmptyState() {
    return RefreshIndicator(
      onRefresh: _fetchPendingReviews,
      color: AppColors.primary,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
        child: Column(
          children: [
            const SizedBox(height: 12),
            _buildEmptyIllustration(),
            const SizedBox(height: 24),
            Text(
              'No Pending Reviews',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              "You don't have any pending self-assessments at the moment. "
              'Take a break and celebrate your progress!',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.4,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const MyReviewsScreen()),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Text(
                    'View All Reviews',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(width: 8),
                  Icon(Icons.arrow_forward_rounded, size: 18),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyIllustration() {
    return SizedBox(
      width: 120,
      height: 110,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Center(
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.coffee_rounded,
                  size: 28,
                  color: AppColors.primary,
                ),
              ),
            ),
          ),
          Positioned(
            right: 0,
            bottom: 6,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Icon(
                Icons.done_all_rounded,
                size: 20,
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewCard(Map<String, dynamic> review) {
    final id = review['_id'] as String? ?? '';
    final reviewCycle = review['reviewCycle'] ?? 'N/A';
    final reviewType = review['reviewType'] ?? '';
    final period = review['reviewPeriod'] as Map<String, dynamic>?;
    final goalIds = review['goalIds'] as List?;

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
                    color: AppColors.warning.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'Pending',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: AppColors.warning,
                    ),
                  ),
                ),
              ],
            ),
            if (periodStr.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.calendar_today_rounded,
                    size: 16,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    periodStr,
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
            if (reviewType.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Type: $reviewType',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
            ],
            if (goalIds != null && goalIds.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                '${goalIds.length} goal${goalIds.length != 1 ? 's' : ''} linked',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
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
                          builder: (_) => const MyReviewsScreen(),
                        ),
                      );
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: BorderSide(color: AppColors.primary),
                    ),
                    child: const Text('View Details'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => SelfAssessmentFormScreen(reviewId: id),
                        ),
                      ).then((_) => _fetchPendingReviews());
                    },
                    icon: const Icon(Icons.edit_rounded, size: 14),
                    label: const Text('Start Assessment'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                    ),
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
