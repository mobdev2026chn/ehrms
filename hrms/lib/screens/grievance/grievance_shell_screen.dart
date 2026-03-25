import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/bottom_navigation_bar.dart';
import '../../widgets/menu_icon_button.dart';
import '../dashboard/dashboard_screen.dart';
import 'my_grievances_screen.dart';
import 'raise_grievance_screen.dart';

class GrievanceShellScreen extends StatefulWidget {
  const GrievanceShellScreen({super.key});

  @override
  State<GrievanceShellScreen> createState() => _GrievanceShellScreenState();
}

class _GrievanceShellScreenState extends State<GrievanceShellScreen> {
  final GlobalKey<MyGrievancesScreenState> _myGrievancesKey = GlobalKey();

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
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        appBar: AppBar(
          leading: const MenuIconButton(),
          title: const Text(
            'My Grievances',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
        ),
        drawer: const AppDrawer(),
        body: MyGrievancesScreen(
          key: _myGrievancesKey,
          embeddedInShell: true,
        ),
        floatingActionButton: _buildFab(),
        bottomNavigationBar: const AppBottomNavigationBar(currentIndex: -1),
      ),
    );
  }

  Widget _buildFab() {
    const style = TextStyle(fontSize: 13, fontWeight: FontWeight.bold);
    return SizedBox(
      height: 40,
      child: FloatingActionButton.extended(
        foregroundColor: Colors.white,
        onPressed: () async {
          final result = await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (_) => const RaiseGrievanceScreen(),
            ),
          );
          if (result == true && mounted) {
            _myGrievancesKey.currentState?.refresh();
          }
        },
        label: const Text('Raise Grievance', style: style),
        icon: const Icon(Icons.add, size: 18),
        backgroundColor: AppColors.primary,
      ),
    );
  }
}
