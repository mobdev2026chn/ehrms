// hrms/lib/screens/interaction/interaction_shell_screen.dart
// Employee Interaction: Chats + Polls (parity with web /interaction/chat and /interaction/polls).

import 'dart:async';

import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../utils/snackbar_utils.dart';
import '../../services/interaction_service.dart';
import '../../services/interaction_socket_service.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/bottom_navigation_bar.dart';
import 'interaction_chat_list_screen.dart';
import 'interaction_polls_list_screen.dart';

class InteractionShellScreen extends StatefulWidget {
  const InteractionShellScreen({super.key});

  @override
  State<InteractionShellScreen> createState() => _InteractionShellScreenState();
}

class _InteractionShellScreenState extends State<InteractionShellScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String? _role;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureTermsAndSocket();
    });
  }

  Future<void> _ensureTermsAndSocket() async {
    if (!mounted) return;
    try {
      _role = await InteractionService.currentUserRole();
      final isAdminLike = InteractionService.isInteractionAdminLikeRole(_role);
      final status = await InteractionService.instance.getChatTermsStatus();
      final data = status['data'];
      final approved = data is Map && data['chatTermsApproved'] == true;
      if (!approved && !isAdminLike && mounted) {
        final accept = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('Chat guidelines'),
            content: const SingleChildScrollView(
              child: Text(
                'By using Interaction chat you agree to use it professionally. '
                'Harassment, sharing confidential data, or misuse may violate company policy. '
                'Continue only if you agree to these terms.',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('I agree'),
              ),
            ],
          ),
        );
        if (accept == true) {
          await InteractionService.instance.approveChatTerms();
        } else if (mounted) {
          Navigator.of(context).pop();
          return;
        }
      }
      await InteractionSocketService.instance.connect();
      unawaited(InteractionService.instance.getLmsMyAccess());
    } catch (_) {
      if (mounted) {
        SnackBarUtils.showSnackBar(
          context,
          'Could not start chat connection. Pull to refresh.',
        );
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      drawer: const AppDrawer(),
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        foregroundColor: const Color(0xFF0F172A),
        title: const Text('Interaction', style: TextStyle(fontWeight: FontWeight.w600)),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.primary,
          unselectedLabelColor: Colors.grey,
          indicatorColor: AppColors.primary,
          tabs: const [
            Tab(icon: Icon(Icons.chat_bubble_outline), text: 'Messages'),
            Tab(icon: Icon(Icons.poll_outlined), text: 'Polls & Surveys'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          InteractionChatListScreen(),
          InteractionPollsListScreen(),
        ],
      ),
      bottomNavigationBar: const AppBottomNavigationBar(currentIndex: -1),
    );
  }
}
