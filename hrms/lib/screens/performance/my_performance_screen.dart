// hrms/lib/screens/performance/my_performance_screen.dart
// My Performance - Landing page for Performance module (Overview tab)

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../config/app_colors.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/bottom_navigation_bar.dart';
import '../../widgets/menu_icon_button.dart';
import '../../services/performance_service.dart';
import 'my_reviews_screen.dart';
import 'my_goals_screen.dart';
import 'review_detail_screen.dart';
import '../../widgets/app_tab_loader.dart';

class MyPerformanceScreen extends StatefulWidget {
  final bool embeddedInModule;
  final int refreshTrigger;
  final int currentTabIndex;
  final int performanceTabIndex;
  final void Function(int index)? onNavigateToTab;

  const MyPerformanceScreen({
    super.key,
    this.embeddedInModule = false,
    this.refreshTrigger = 0,
    this.currentTabIndex = 0,
    this.performanceTabIndex = 0,
    this.onNavigateToTab,
  });

  @override
  State<MyPerformanceScreen> createState() => _MyPerformanceScreenState();
}

class _MyPerformanceScreenState extends State<MyPerformanceScreen> {
  final PerformanceService _performanceService = PerformanceService();
  bool _isLoading = true;
  String? _error;
  Map<String, dynamic>? _summary;

  @override
  void initState() {
    super.initState();
    _fetchSummary();
  }

  @override
  void didUpdateWidget(MyPerformanceScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshTrigger != widget.refreshTrigger &&
        widget.currentTabIndex == widget.performanceTabIndex) {
      _fetchSummary();
    }
  }

  Future<void> _fetchSummary() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final result = await _performanceService.getEmployeeSummary();
      if (mounted) {
        setState(() {
          _summary = result['data'];
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

  @override
  Widget build(BuildContext context) {
    final body = _isLoading
        ? const Center(child: AppTabLoader())
        : _error != null
        ? _buildErrorState()
        : RefreshIndicator(
            onRefresh: _fetchSummary,
            color: AppColors.primary,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: _buildOverviewContent(),
            ),
          );

    if (widget.embeddedInModule) return body;
    return Scaffold(
      backgroundColor: AppColors.background,
      drawer: const AppDrawer(),
      appBar: AppBar(
        leading: const MenuIconButton(),
        title: Text(
          'My Performance',
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
              _error ?? 'Failed to load performance data',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _fetchSummary,
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

  Widget _buildOverviewContent() {
    final avgRating = ((_summary?['averageRating'] ?? 0.0) as num).toDouble();
    final totalReviews = (_summary?['totalReviews'] ?? 0) as int;
    final completedReviews = (_summary?['completedReviews'] ?? 0) as int;
    final currentGoals = (_summary?['currentGoals'] ?? 0) as int;
    final latestReview = _summary?['latestReview'] as Map<String, dynamic>?;
    final latestReviewId = latestReview?['_id'] as String?;

    // Latest review display value (e.g. "Oct 24") + subtitle.
    String latestValue = latestReview?['reviewCycle']?.toString() ?? 'N/A';
    final latestPeriod = latestReview?['reviewPeriod'] as Map<String, dynamic>?;
    final latestEnd = DateTime.tryParse(
      latestPeriod?['endDate']?.toString() ?? '',
    );
    if (latestEnd != null) {
      latestValue = DateFormat('MMM yy').format(latestEnd);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        _buildHeroRating(avgRating),
        const SizedBox(height: 20),
        _buildStatTile(
          icon: Icons.rate_review_rounded,
          title: 'Total Reviews',
          subtitle: completedReviews > 0
              ? '$completedReviews completed cycles'
              : 'Completed cycles',
          value: totalReviews.toString(),
          onTap: () => _navigate(2, const MyReviewsScreen()),
        ),
        const SizedBox(height: 12),
        _buildStatTile(
          icon: Icons.track_changes_rounded,
          title: 'Current Goals',
          subtitle: 'Active objectives',
          value: currentGoals.toString(),
          onTap: () => _navigate(1, const MyGoalsScreen()),
        ),
        const SizedBox(height: 12),
        _buildStatTile(
          icon: Icons.history_rounded,
          title: 'Latest Review',
          subtitle: 'Last assessment date',
          value: latestValue,
          onTap: latestReviewId != null
              ? () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ReviewDetailScreen(reviewId: latestReviewId),
                    ),
                  ).then((_) => _fetchSummary());
                }
              : null,
        ),
      ],
    );
  }

  /// Navigate to a sibling tab when embedded, otherwise push the screen.
  void _navigate(int tabIndex, Widget fallback) {
    if (widget.onNavigateToTab != null) {
      widget.onNavigateToTab!(tabIndex);
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => fallback),
      );
    }
  }

  Widget _buildHeroRating(double rating) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            'OVERALL RATING',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            rating > 0 ? rating.toStringAsFixed(1) : 'N/A',
            style: TextStyle(
              fontSize: 72,
              fontWeight: FontWeight.bold,
              height: 1.0,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: _buildStars(rating),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildStars(double rating) {
    return List.generate(5, (i) {
      IconData icon;
      Color color = AppColors.primary;
      if (rating >= i + 1) {
        icon = Icons.star_rounded;
      } else if (rating >= i + 0.5) {
        icon = Icons.star_half_rounded;
      } else {
        icon = Icons.star_rounded;
        color = AppColors.divider;
      }
      return Icon(icon, size: 32, color: color);
    });
  }

  Widget _buildStatTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required String value,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: AppColors.primary, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                value,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
