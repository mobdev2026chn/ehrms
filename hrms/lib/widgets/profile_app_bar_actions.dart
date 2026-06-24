// hrms/lib/widgets/profile_app_bar_actions.dart
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_colors.dart';
import '../screens/notifications/notifications_screen.dart';
import '../screens/profile/profile_screen.dart';
import '../services/auth_service.dart';

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
  final AuthService _authService = AuthService();
  String? _avatarUrl;
  String _initial = 'U';

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  /// First valid http(s) avatar URL from a user/staff/profile map, checking the
  /// several keys the backend has used over time (and the nested `profile`).
  String? _extractAvatar(Map? map) {
    if (map == null) return null;
    for (final key in const ['avatar', 'photoUrl', 'profilePic', 'image']) {
      final v = map[key]?.toString().trim();
      if (v != null && v.startsWith('http')) return v;
    }
    final nested = map['profile'];
    if (nested is Map) return _extractAvatar(nested);
    return null;
  }

  Future<void> _loadUser() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // 1. Resolve from cached blobs first (instant, works offline). The avatar
      //    is sometimes only on the `staff` blob, not `user`.
      String? url;
      String name = '';
      final userStr = prefs.getString('user');
      if (userStr != null) {
        final user = jsonDecode(userStr);
        if (user is Map) {
          url ??= _extractAvatar(user);
          name = (user['name'] ?? '').toString().trim();
        }
      }
      if (url == null) {
        final staffStr = prefs.getString('staff');
        if (staffStr != null) {
          final staff = jsonDecode(staffStr);
          if (staff is Map) url ??= _extractAvatar(staff);
        }
      }
      if (mounted) {
        setState(() {
          if (url != null) _avatarUrl = url;
          if (name.isNotEmpty) _initial = name[0].toUpperCase();
        });
      }
      // 2. No cached photo → fetch the latest profile (the backend seeds the
      //    avatar from the first-punch selfie) and persist it for next time.
      if (url == null) await _refreshAvatarFromProfile();
    } catch (_) {
      // Cached user missing/corrupt — keep the default initial.
    }
  }

  Future<void> _refreshAvatarFromProfile() async {
    try {
      final res = await _authService.getProfile();
      if (res['success'] != true || res['data'] is! Map) return;
      final data = Map<String, dynamic>.from(res['data'] as Map);
      final url = _extractAvatar(data['staffData'] as Map?) ??
          _extractAvatar(data['profile'] as Map?) ??
          _extractAvatar(data);
      if (url == null) return;
      if (mounted) setState(() => _avatarUrl = url);
      // Persist into the cached user blob so other screens pick it up too.
      final prefs = await SharedPreferences.getInstance();
      final userStr = prefs.getString('user');
      if (userStr != null) {
        final user = jsonDecode(userStr);
        if (user is Map) {
          user['avatar'] = url;
          user['photoUrl'] = url;
          await prefs.setString('user', jsonEncode(user));
        }
      }
    } catch (_) {
      // Network/profile failure — keep the initial fallback.
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
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const ProfileScreen(dashboardTabIndex: 3),
              ),
            ),
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.primary, width: 2),
              ),
              child: CircleAvatar(
                radius: 17,
                backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                backgroundImage: hasPhoto ? CachedNetworkImageProvider(_avatarUrl!) : null,
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
          ),
        ],
      ),
    );
  }
}
