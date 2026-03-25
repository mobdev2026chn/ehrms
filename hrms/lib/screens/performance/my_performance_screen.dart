// hrms/lib/screens/performance/my_performance_screen.dart
// My Performance - Landing page for Performance module

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../config/app_colors.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/bottom_navigation_bar.dart';
import '../../widgets/menu_icon_button.dart';
import '../../services/performance_service.dart';
import 'my_reviews_screen.dart';
import 'self_assessment_screen.dart';
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
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildOverviewSection(),
                  if (_summary?['latestReview'] != null) ...[
                    const SizedBox(height: 24),
                    _buildLatestReviewSection(),
                  ],
                  if (_summary?['recentReviews'] != null &&
                      (_summary!['recentReviews'] as List).isNotEmpty) ...[
                    const SizedBox(height: 24),
                    _buildRecentReviewsSection(),
                  ],
                  const SizedBox(height: 24),
                  _buildQuickAccessCards(),
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

  Widget _buildOverviewSection() {
    final emp = _summary?['employee'] as Map<String, dynamic>? ?? {};
    final avgRating = (_summary?['averageRating'] ?? 0.0) as num;
    final totalReviews = (_summary?['totalReviews'] ?? 0) as int;
    final completedReviews = (_summary?['completedReviews'] ?? 0) as int;
    final currentGoals = (_summary?['currentGoals'] ?? 0) as int;
    final latestReview = _summary?['latestReview'] as Map<String, dynamic>?;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'My Performance Overview',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${emp['name'] ?? ''} · ${emp['designation'] ?? ''} · ${emp['department'] ?? ''}',
          style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 16),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
          childAspectRatio: 1.5,
          children: [
            _buildOverviewCard(
              title: 'Average Rating',
              value: avgRating > 0 ? avgRating.toStringAsFixed(1) : 'N/A',
              subtitle: 'Out of 5.0',
              icon: Icons.star_rounded,
              iconColor: AppColors.warning,
            ),
            _buildOverviewCard(
              title: 'Total Reviews',
              value: totalReviews.toString(),
              subtitle: '$completedReviews completed',
              icon: Icons.description_rounded,
              iconColor: AppColors.textSecondary,
            ),
            _buildOverviewCard(
              title: 'Current Goals',
              value: currentGoals.toString(),
              subtitle: 'Active goals',
              icon: Icons.flag_rounded,
              iconColor: AppColors.textSecondary,
            ),
            _buildOverviewCard(
              title: 'Latest Review',
              value: latestReview?['reviewCycle'] ?? 'N/A',
              subtitle: latestReview?['reviewType'] ?? 'No reviews yet',
              icon: Icons.calendar_today_rounded,
              iconColor: AppColors.textSecondary,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildOverviewCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(icon, size: 14, color: iconColor),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            subtitle,
            style: TextStyle(fontSize: 9, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildLatestReviewSection() {
    final latestReview = _summary!['latestReview'] as Map<String, dynamic>;
    final period = latestReview['reviewPeriod'] as Map<String, dynamic>?;
    final status = (latestReview['status'] ?? '').toString();
    final finalRating = latestReview['finalRating'];
    final managerReview =
        latestReview['managerReview'] as Map<String, dynamic>?;
    final hrReview = latestReview['hrReview'] as Map<String, dynamic>?;
    final selfReview = latestReview['selfReview'] as Map<String, dynamic>?;
    final reviewId = latestReview['_id'] as String?;

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

    Color statusColor = AppColors.textSecondary;
    if (status == 'completed') statusColor = AppColors.success;
    if (status.contains('pending')) statusColor = AppColors.warning;
    if (status.contains('submitted')) statusColor = AppColors.info;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.emoji_events_rounded,
              size: 22,
              color: AppColors.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Latest Performance Review - ${latestReview['reviewCycle'] ?? 'Review'}',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Review Period',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      Text(
                        periodStr,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Final Rating',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      Row(
                        children: [
                          Text(
                            finalRating != null
                                ? (finalRating as num).toStringAsFixed(1)
                                : 'N/A',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.star_rounded,
                            size: 20,
                            color: AppColors.warning,
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  status.replaceAll('-', ' ').toUpperCase(),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: statusColor,
                  ),
                ),
              ),
              if (managerReview != null) ...[
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 12),
                Text(
                  'Manager Review',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                _buildRatingRow('Overall', managerReview['overallRating']),
                _buildRatingRow(
                  'Technical Skills',
                  managerReview['technicalSkills'],
                ),
                _buildRatingRow(
                  'Communication',
                  managerReview['communication'],
                ),
              ],
              if (hrReview != null) ...[
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 12),
                Text(
                  'HR Review',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                _buildRatingRow('Overall', hrReview['overallRating']),
                _buildRatingRow(
                  'Company Values',
                  hrReview['alignmentWithCompanyValues'],
                ),
                _buildRatingRow(
                  'Growth Potential',
                  hrReview['growthPotential'],
                ),
              ],
              if (selfReview != null) ...[
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 12),
                Text(
                  'Your Self Review',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                _buildRatingRow('Overall Rating', selfReview['overallRating']),
              ],
              if (reviewId != null) ...[
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              ReviewDetailScreen(reviewId: reviewId),
                        ),
                      ).then((_) => _fetchSummary());
                    },
                    icon: const Icon(Icons.visibility_rounded, size: 18),
                    label: Text('View Details'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: BorderSide(color: AppColors.primary),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRatingRow(String label, dynamic value) {
    final v = value is num ? value.toDouble() : 0.0;
    final pct = (v / 5.0 * 100).clamp(0.0, 100.0);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: pct / 100,
              backgroundColor: AppColors.divider,
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
              minHeight: 6,
            ),
          ),
          Text(
            '$v/5',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentReviewsSection() {
    final recentReviews = _summary!['recentReviews'] as List<dynamic>? ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Recent Reviews',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: [
              for (int i = 0; i < recentReviews.length; i++) ...[
                if (i > 0) const Divider(height: 24),
                _buildRecentReviewItem(
                  recentReviews[i] as Map<String, dynamic>,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRecentReviewItem(Map<String, dynamic> review) {
    final period = review['reviewPeriod'] as Map<String, dynamic>?;
    final reviewId = review['_id'] as String?;
    final status = (review['status'] ?? '').toString();
    final finalRating = review['finalRating'];

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

    Color statusColor = AppColors.textSecondary;
    if (status == 'completed') statusColor = AppColors.success;
    if (status.contains('pending')) statusColor = AppColors.warning;
    if (status.contains('submitted')) statusColor = AppColors.info;

    return InkWell(
      onTap: reviewId != null
          ? () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ReviewDetailScreen(reviewId: reviewId),
                ),
              ).then((_) => _fetchSummary());
            }
          : null,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    review['reviewCycle'] ?? 'Review',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    '${review['reviewType'] ?? ''} · $periodStr',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (finalRating != null)
              Row(
                children: [
                  Text(
                    (finalRating as num).toStringAsFixed(1),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.star_rounded, size: 18, color: AppColors.warning),
                ],
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  status.replaceAll('-', ' '),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: statusColor,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickAccessCards() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Quick Access',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth > 500;
            return isWide
                ? Row(
                    children: [
                      Expanded(
                        child: _buildQuickCard(
                          title: 'My Reviews',
                          subtitle: 'View your performance reviews',
                          icon: Icons.star_rounded,
                          onTap: () {
                            if (widget.onNavigateToTab != null) {
                              widget.onNavigateToTab!(2);
                            } else {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const MyReviewsScreen(),
                                ),
                              );
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildQuickCard(
                          title: 'Self Assessment',
                          subtitle: 'Complete your self assessment',
                          icon: Icons.checklist_rounded,
                          onTap: () {
                            if (widget.onNavigateToTab != null) {
                              widget.onNavigateToTab!(3);
                            } else {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const SelfAssessmentScreen(),
                                ),
                              );
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildQuickCard(
                          title: 'My Goals',
                          subtitle: 'Track and manage your goals',
                          icon: Icons.flag_rounded,
                          onTap: () => widget.onNavigateToTab != null
                              ? widget.onNavigateToTab!(1)
                              : Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const MyGoalsScreen(),
                                  ),
                                ),
                        ),
                      ),
                    ],
                  )
                : Column(
                    children: [
                      _buildQuickCard(
                        title: 'My Reviews',
                        subtitle: 'View your performance reviews',
                        icon: Icons.star_rounded,
                        onTap: () {
                          if (widget.onNavigateToTab != null) {
                            widget.onNavigateToTab!(2);
                          } else {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const MyReviewsScreen(),
                              ),
                            );
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      _buildQuickCard(
                        title: 'Self Assessment',
                        subtitle: 'Complete your self assessment',
                        icon: Icons.checklist_rounded,
                        onTap: () {
                          if (widget.onNavigateToTab != null) {
                            widget.onNavigateToTab!(3);
                          } else {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const SelfAssessmentScreen(),
                              ),
                            );
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      _buildQuickCard(
                        title: 'My Goals',
                        subtitle: 'Track and manage your goals',
                        icon: Icons.flag_rounded,
                        onTap: () {
                          if (widget.onNavigateToTab != null) {
                            widget.onNavigateToTab!(1);
                          } else {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const MyGoalsScreen(),
                              ),
                            );
                          }
                        },
                      ),
                    ],
                  );
          },
        ),
      ],
    );
  }

  Widget _buildQuickCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: AppColors.primary.withOpacity(0.2),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 10,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 16,
                color: AppColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
