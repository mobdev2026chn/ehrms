// hrms/lib/widgets/profile_app_bar_actions.dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_colors.dart';
import '../screens/notifications/notifications_screen.dart';

/// Figma top-right AppBar cluster: a notification bell that opens the
/// notifications screen and the signed-in user's avatar (photo or initial),
/// read from the cached `user` blob in [SharedPreferences].
///
/// Drop into an [AppBar.actions] list. Purely presentational — it does not
/// fetch from the network, so it is cheap to embed on any screen.
class ProfileAppBarActions extends StatefulWidget {
  const ProfileAppBarActions({super.key});

  @override
  State<ProfileAppBarActions> createState() => _ProfileAppBarActionsState();
}

class _ProfileAppBarActionsState extends State<ProfileAppBarActions> {
  String? _avatarUrl;
  String _initial = 'U';

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userStr = prefs.getString('user');
      if (userStr == null) return;
      final user = jsonDecode(userStr);
      if (user is! Map) return;
      final url = (user['avatar'] ?? user['photoUrl'])?.toString().trim();
      final name = (user['name'] ?? '').toString().trim();
      if (!mounted) return;
      setState(() {
        if (url != null && url.startsWith('http')) _avatarUrl = url;
        if (name.isNotEmpty) _initial = name[0].toUpperCase();
      });
    } catch (_) {
      // Cached user missing/corrupt — keep the default initial.
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasPhoto = _avatarUrl != null;
    return Padding(
      padding: const EdgeInsets.only(right: 16),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const NotificationsScreen()),
            ),
            child: const Icon(
              Icons.notifications_none_rounded,
              size: 26,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(width: 14),
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.primary, width: 2),
            ),
            child: CircleAvatar(
              radius: 17,
              backgroundColor: AppColors.primary.withValues(alpha: 0.15),
              backgroundImage: hasPhoto ? NetworkImage(_avatarUrl!) : null,
              child: hasPhoto
                  ? null
                  : Text(
                      _initial,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
