// hrms/lib/screens/lms_admin/lms_admin_shell_screen.dart
// Admin LMS module shell — a single "LMS Admin" screen with horizontally
// scrollable sub-tabs: Course Library, Learners, Live Sessions, Assessment,
// Scores & Analytics. Isolated from the employee LMS module.

import 'package:flutter/material.dart';
import '../../config/app_colors.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/bottom_navigation_bar.dart';
import '../../widgets/menu_icon_button.dart';
import '../dashboard/dashboard_screen.dart';
import 'lms_admin_assessment_screen.dart';
import 'lms_admin_course_library_screen.dart';
import 'lms_admin_learners_screen.dart';
import 'lms_admin_live_sessions_screen.dart';
import 'lms_admin_scores_screen.dart';

class LmsAdminShellScreen extends StatefulWidget {
  final int initialIndex;
  const LmsAdminShellScreen({super.key, this.initialIndex = 0});

  @override
  State<LmsAdminShellScreen> createState() => _LmsAdminShellScreenState();
}

class _LmsAdminShellScreenState extends State<LmsAdminShellScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  static const _tabs = <({String label, IconData icon})>[
    (label: 'Course Library', icon: Icons.menu_book_outlined),
    (label: 'Learners', icon: Icons.people_alt_outlined),
    (label: 'Live Sessions', icon: Icons.video_call_outlined),
    (label: 'Assessment', icon: Icons.fact_check_outlined),
    (label: 'Scores & Analytics', icon: Icons.bar_chart_outlined),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: _tabs.length,
      vsync: this,
      initialIndex: widget.initialIndex.clamp(0, _tabs.length - 1),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const DashboardScreen()),
          (route) => route.isFirst,
        );
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          leading: const MenuIconButton(),
          title: const Text(
            'LMS Admin',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(46),
            child: Container(
              color: AppColors.surface,
              alignment: Alignment.centerLeft,
              child: TabBar(
                controller: _tabController,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                labelColor: AppColors.primary,
                unselectedLabelColor: AppColors.textSecondary,
                indicatorColor: AppColors.primary,
                indicatorWeight: 2.5,
                labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                unselectedLabelStyle: const TextStyle(fontSize: 13),
                tabs: _tabs
                    .map((t) => Tab(
                          height: 44,
                          icon: null,
                          iconMargin: EdgeInsets.zero,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(t.icon, size: 16),
                              const SizedBox(width: 6),
                              Text(t.label),
                            ],
                          ),
                        ))
                    .toList(),
              ),
            ),
          ),
        ),
        drawer: const AppDrawer(),
        body: TabBarView(
          controller: _tabController,
          children: const [
            LmsAdminCourseLibraryScreen(),
            LmsAdminLearnersScreen(),
            LmsAdminLiveSessionsScreen(),
            LmsAdminAssessmentScreen(),
            LmsAdminScoresScreen(),
          ],
        ),
        bottomNavigationBar: AppBottomNavigationBar(
          currentIndex: -1,
          onTap: (index) {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(
                  builder: (_) => DashboardScreen(initialIndex: index)),
              (route) => route.isFirst,
            );
          },
        ),
      ),
    );
  }
}
