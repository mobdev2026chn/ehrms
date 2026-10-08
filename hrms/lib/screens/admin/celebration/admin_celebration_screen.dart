// Admin "Celebration": birthdays and work anniversaries (GET /admin/celebration/list +
// /summary), the wish templates (/admin/celebration/templates) and the auto-send settings
// (/admin/celebration/settings) - the same four tabs as the web's Celebration page.

import 'package:flutter/material.dart';

import '../../../config/app_colors.dart';
import 'celebration_automation_tab.dart';
import 'celebration_list_tab.dart';
import 'celebration_shared.dart';
import 'celebration_templates_tab.dart';

class AdminCelebrationScreen extends StatefulWidget {
  const AdminCelebrationScreen({super.key, this.initialTab = 0});

  /// 0 birthdays, 1 anniversaries, 2 templates, 3 automation
  final int initialTab;

  @override
  State<AdminCelebrationScreen> createState() => _AdminCelebrationScreenState();
}

class _AdminCelebrationScreenState extends State<AdminCelebrationScreen> {
  final CelebrationStore _store = CelebrationStore();

  @override
  void initState() {
    super.initState();
    _store.loadAll();
  }

  @override
  void dispose() {
    _store.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      initialIndex: widget.initialTab.clamp(0, 3),
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('Celebration'),
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(icon: Icon(Icons.cake_outlined, size: 18), text: 'Birthdays'),
              Tab(icon: Icon(Icons.celebration_outlined, size: 18), text: 'Anniversaries'),
              Tab(icon: Icon(Icons.dashboard_customize_outlined, size: 18), text: 'Templates'),
              Tab(icon: Icon(Icons.bolt_outlined, size: 18), text: 'Automation'),
            ],
          ),
        ),
        body: TabBarView(children: [
          CelebrationListTab(kind: 'birthday', store: _store),
          CelebrationListTab(kind: 'anniversary', store: _store),
          CelebrationTemplatesTab(store: _store),
          CelebrationAutomationTab(store: _store),
        ]),
      ),
    );
  }
}
