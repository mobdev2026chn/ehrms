// hrms/lib/screens/performance/performance_module_screen.dart
// Performance module with bottom nav: Overview | Goals | Reviews | Self Assessment
// Add Goal FAB above bottom nav (on Goals tab)

import 'package:flutter/material.dart';
import '../../config/app_colors.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/bottom_navigation_bar.dart';
import '../../widgets/menu_icon_button.dart';
import 'my_performance_screen.dart';
import 'my_goals_screen.dart';
import 'my_reviews_screen.dart';
import 'self_assessment_screen.dart';

class PerformanceModuleScreen extends StatefulWidget {
  final int initialTabIndex;

  const PerformanceModuleScreen({super.key, this.initialTabIndex = 0});

  @override
  State<PerformanceModuleScreen> createState() =>
      _PerformanceModuleScreenState();
}

class _PerformanceModuleScreenState extends State<PerformanceModuleScreen> {
  late int _currentIndex;
  int _refreshTrigger = 0;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialTabIndex.clamp(0, 3);
  }

  void _onTabTap(int index) {
    setState(() {
      _currentIndex = index;
      _refreshTrigger++;
    });
  }

  void _onAddGoal() {
    _goalsKey.currentState?.showCreateGoalSheet();
  }

  final GlobalKey<MyGoalsScreenState> _goalsKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      drawer: const AppDrawer(),
      appBar: AppBar(
        leading: const MenuIconButton(),
        title: const Text('Performance'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Container(
            decoration: const BoxDecoration(
              color: AppColors.surface,
              border: Border(
                top: BorderSide(color: Color(0xFFECEEF1)),
                bottom: BorderSide(color: Color(0xFFECEEF1)),
              ),
            ),
            child: Row(
              children: [
                _buildNavItem(0, Icons.grid_view_rounded,      'Overview'),
                _buildNavItem(1, Icons.flag_outlined,          'Goals'),
                _buildNavItem(2, Icons.description_outlined,   'Reviews'),
                _buildNavItem(3, Icons.person_outline_rounded, 'Self'),
              ],
            ),
          ),
        ),
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: [
          MyPerformanceScreen(
            embeddedInModule: true,
            refreshTrigger: _refreshTrigger,
            currentTabIndex: _currentIndex,
            performanceTabIndex: 0,
            onNavigateToTab: _onTabTap,
          ),
          MyGoalsScreen(
            key: _goalsKey,
            embeddedInModule: true,
            hideAppBar: true,
            refreshTrigger: _refreshTrigger,
            currentTabIndex: _currentIndex,
            performanceTabIndex: 1,
          ),
          MyReviewsScreen(
            embeddedInModule: true,
            refreshTrigger: _refreshTrigger,
            currentTabIndex: _currentIndex,
            performanceTabIndex: 2,
          ),
          SelfAssessmentScreen(
            embeddedInModule: true,
            refreshTrigger: _refreshTrigger,
            currentTabIndex: _currentIndex,
            performanceTabIndex: 3,
          ),
        ],
      ),
      bottomNavigationBar: const AppBottomNavigationBar(currentIndex: -1),
      floatingActionButton: _currentIndex == 1 ? _buildFab() : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    final isSelected = _currentIndex == index;
    return Expanded(
      child: InkWell(
        onTap: () => _onTabTap(index),
        child: SizedBox(
          height: 58,
          child: Column(
            children: [
              const Spacer(),
              Icon(
                icon,
                size: 22,
                color: isSelected ? AppColors.primaryText : AppColors.textSecondary,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: isSelected
                      ? AppColors.textPrimary
                      : AppColors.textSecondary,
                ),
              ),
              const Spacer(),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                height: 3,
                width: isSelected ? 32 : 0,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(3)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget? _buildFab() {
    return SizedBox(
      height: 44,
      child: FloatingActionButton.extended(
        foregroundColor: AppColors.onPrimary,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        onPressed: _onAddGoal,
        label: const Text(
          'Add Goal',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        icon: const Icon(Icons.add_rounded, size: 20),
        backgroundColor: AppColors.primary,
      ),
    );
  }

}
