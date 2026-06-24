import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_colors.dart';
import '../utils/avatar_orientation.dart';

/// Small circular avatar for app-bar actions that shows the signed-in user's
/// real profile photo (read from the cached `user` blob in SharedPreferences,
/// matching the Profile screen's source), falling back to a person icon when
/// there's no usable photo. Mirrors the Profile header's 180° flip handling so
/// upside-down selfies display upright here too.
class AppBarProfileAvatar extends StatefulWidget {
  final double radius;
  final VoidCallback? onTap;

  const AppBarProfileAvatar({super.key, this.radius = 18, this.onTap});

  @override
  State<AppBarProfileAvatar> createState() => _AppBarProfileAvatarState();
}

class _AppBarProfileAvatarState extends State<AppBarProfileAvatar> {
  String? _photoUrl;
  bool _needsFlip = false;
  bool _imageError = false;

  @override
  void initState() {
    super.initState();
    _loadAvatar();
  }

  Future<void> _loadAvatar() async {
    String? url;
    try {
      final prefs = await SharedPreferences.getInstance();
      final userStr = prefs.getString('user');
      if (userStr != null) {
        final user = jsonDecode(userStr) as Map<String, dynamic>?;
        if (user != null) {
          url = (user['avatar'] ?? user['photoUrl'])?.toString().trim();
        }
      }
    } catch (_) {}

    if (url == null ||
        url.isEmpty ||
        !(url.startsWith('http://') || url.startsWith('https://'))) {
      url = null;
    }
    if (!mounted) return;
    setState(() => _photoUrl = url);

    if (url != null) {
      AvatarOrientation.resolveNeedsFlip(url).then((resolved) {
        if (!mounted || resolved == null || resolved == _needsFlip) return;
        setState(() => _needsFlip = resolved);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final showPhoto = _photoUrl != null && !_imageError;

    final avatar = RotatedBox(
      quarterTurns: (showPhoto && _needsFlip) ? 2 : 0,
      child: CircleAvatar(
        radius: widget.radius,
        backgroundColor: AppColors.primary.withValues(alpha: 0.15),
        backgroundImage:
            showPhoto ? CachedNetworkImageProvider(_photoUrl!) : null,
        onBackgroundImageError: showPhoto
            ? (_, __) {
                if (mounted) setState(() => _imageError = true);
              }
            : null,
        child: showPhoto
            ? null
            : Icon(Icons.person_rounded,
                color: AppColors.primary, size: widget.radius * 1.22),
      ),
    );

    if (widget.onTap == null) return avatar;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      child: avatar,
    );
  }
}
