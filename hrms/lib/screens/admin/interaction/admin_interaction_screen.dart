// Admin "Interaction": Groups, Broadcasts and Polls & Surveys, matching the web admin
// (src/features/admin/interaction/**). APIs: /admin/interaction/chat/* and
// /admin/interaction/polls/* (company 'interaction' module, admin role).

import 'package:flutter/material.dart';

import '../../../config/app_colors.dart';
import 'admin_broadcasts.dart';
import 'admin_groups.dart';
import 'admin_polls.dart';

class AdminInteractionScreen extends StatelessWidget {
  const AdminInteractionScreen({super.key, this.initialTab = 0});
  final int initialTab; // 0 groups, 1 broadcasts, 2 polls

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      initialIndex: initialTab.clamp(0, 2),
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('Interaction'),
          bottom: const TabBar(
            tabs: [Tab(text: 'Groups'), Tab(text: 'Broadcasts'), Tab(text: 'Polls')],
          ),
        ),
        body: const TabBarView(children: [AdminGroupsTab(), AdminBroadcastsTab(), AdminPollsTab()]),
      ),
    );
  }
}
