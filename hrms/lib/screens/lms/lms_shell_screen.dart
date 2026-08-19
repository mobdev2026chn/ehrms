// hrms/lib/screens/lms/lms_shell_screen.dart
// LMS module shell: single My Learning screen with sub-tabs (My Courses, Learning Engine, Library, Live Sessions).
// No top-level My Learning / Live Sessions switcher; back exits LMS.

import 'package:flutter/material.dart';
import '../../config/app_colors.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/bottom_navigation_bar.dart';
import '../../widgets/menu_icon_button.dart';
import '../dashboard/dashboard_screen.dart';
import 'lms_dashboard_screen.dart';

class LmsShellScreen extends StatelessWidget {
  /// Initial sub-tab index (0 = My Courses, 1 = Learning Engine, 2 = Library, 3 = Live Sessions)
  final int initialIndex;

  const LmsShellScreen({super.key, this.initialIndex = 0});

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
            'My Learning',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
        ),
        drawer: const AppDrawer(),
        body: LmsDashboardScreen(
          embeddedInShell: true,
          initialIndex: initialIndex,
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

