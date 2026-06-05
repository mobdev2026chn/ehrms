import 'package:flutter/material.dart';
import '../config/app_colors.dart';

/// Soft drop shadow used by EktaHR surface cards (Figma): subtle black,
/// blur 10, 3px down. `0x0F000000` ≈ black @ 6% alpha.
const List<BoxShadow> kSoftCardShadow = [
  BoxShadow(color: Color(0x0F000000), blurRadius: 10, offset: Offset(0, 3)),
];

/// Standard EktaHR surface card: white, 16-radius, soft shadow.
///
/// Consolidates the card container repeated across the app (dashboard,
/// requests, salary, …). Override [color]/[boxShadow]/[padding] for the
/// accent variants (dark celebration card, amber leaves card, etc.). Pass
/// [onTap] to make the whole card tappable (no ripple, matching the existing
/// `GestureDetector` cards).
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.color = AppColors.surface,
    this.radius = 16,
    this.boxShadow = kSoftCardShadow,
    this.border,
    this.onTap,
    this.clipBehavior = Clip.none,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final Color color;
  final double radius;
  final List<BoxShadow> boxShadow;
  final BoxBorder? border;
  final VoidCallback? onTap;
  final Clip clipBehavior;

  @override
  Widget build(BuildContext context) {
    final Widget card = Container(
      padding: padding,
      margin: margin,
      clipBehavior: clipBehavior,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: boxShadow,
        border: border,
      ),
      child: child,
    );
    if (onTap == null) return card;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: card,
    );
  }
}
