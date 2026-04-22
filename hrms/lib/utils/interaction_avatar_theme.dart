import 'package:flutter/material.dart';

/// Letter avatars for Interaction (web-style colored circles + white initial).
class InteractionAvatarTheme {
  InteractionAvatarTheme._();

  static const List<Color> _palette = [
    Color(0xFFE53935),
    Color(0xFF00897B),
    Color(0xFF3949AB),
    Color(0xFF5E35B1),
    Color(0xFF43A047),
    Color(0xFF8E24AA),
    Color(0xFFD81B60),
    Color(0xFF6D4C41),
    Color(0xFF039BE5),
    Color(0xFF00695C),
  ];

  static Color backgroundForTitle(String title, {String? groupType}) {
    final t = groupType?.trim().toLowerCase();
    if (t == 'broadcast') return const Color(0xFF3949AB);
    if (t == 'department') return const Color(0xFF00897B);
    var h = 0;
    final s = title.trim();
    for (var i = 0; i < s.length; i++) {
      h = 0x1fffffff & (31 * h + s.codeUnitAt(i));
    }
    return _palette[h.abs() % _palette.length];
  }

  static Color letterColor(Color bg) => Colors.white;
}
