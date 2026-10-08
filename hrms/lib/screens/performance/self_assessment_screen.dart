// hrms/lib/screens/performance/self_assessment_screen.dart
// Self Assessment - List available review cycles, show status, Start Assessment button

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../config/app_colors.dart';
import '../../config/app_text_styles.dart';
import '../../widgets/app_card.dart';
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
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: _openCreateSelfAssessment,
          icon: const Icon(Icons.add_rounded, size: 20),
          label: const Text('Create Self Assessment'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primaryText,
            backgroundColor: AppColors.surface,
            side: BorderSide(color: AppColors.primary, width: 1.2),
            minimumSize: const Size(0, 48),
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
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
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
        title: const Text('Self Assessment'),
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
              onPressed: _fetchPendingReviews,
              icon: const Icon(Icons.refresh_rounded, size: 20),
              label: const Text('Retry'),
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
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
        child: Column(
          children: [
            _buildEmptyIllustration(),
            const SizedBox(height: 20),
            Text(
              'No Pending Reviews',
              textAlign: TextAlign.center,
              style: AppTextStyles.headingMedium,
            ),
            const SizedBox(height: 8),
            Text(
              "You don't have any pending self-assessments at the moment. "
              'Take a break and celebrate your progress!',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodySmall,
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
                padding: const EdgeInsets.symmetric(horizontal: 24),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Text('View All Reviews'),
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
      width: 96,
      height: 88,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.coffee_outlined,
              size: 34,
              color: AppColors.primaryText,
            ),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.surface,
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFECEEF1)),
                boxShadow: kSoftCardShadow,
              ),
              child: const Icon(
                Icons.done_all_rounded,
                size: 18,
                color: AppColors.success,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetaRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 14, color: AppColors.textSecondary),
        const SizedBox(width: 6),
        Expanded(child: Text(text, style: AppTextStyles.bodySmall)),
      ],
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

    final pending = AppColors.statusStyle('pending');

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
                child: Icon(Icons.assignment_ind_outlined,
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
                  color: pending.bg,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'Pending',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: pending.fg,
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
          if (goalIds != null && goalIds.isNotEmpty) ...[
            const SizedBox(height: 6),
            _buildMetaRow(
              Icons.flag_outlined,
              '${goalIds.length} goal${goalIds.length != 1 ? 's' : ''} linked',
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
                    ).then((_) => _fetchPendingReviews());
                  },
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text(
                    'Start Assessment',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
