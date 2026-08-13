// hrms/lib/screens/lms_admin/widgets/lms_admin_stat_card.dart
// Shared stat tile used across the admin LMS screens — premium card with a
// glowing gradient icon chip, a soft watermark icon bleeding into the corner,
// value-first hierarchy, and an optional trend pill.

import 'package:flutter/material.dart';
import '../../../config/app_colors.dart';

class LmsAdminStatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color? iconColor;
  final Color? iconBg;

  /// Optional trend, e.g. "+12%". Renders a small pill in the top-right.
  final String? delta;

  /// Whether the [delta] is positive (green) or negative (red).
  final bool deltaPositive;

  const LmsAdminStatCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.iconColor,
    this.iconBg,
    this.delta,
    this.deltaPositive = true,
  });

  @override
  Widget build(BuildContext context) {
    final fg = iconColor ?? AppColors.primary;
    final bg = iconBg ?? AppColors.primaryLight;

    return Container(
      width: 176,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.surface, Color.alphaBlend(fg.withValues(alpha: 0.07), AppColors.surface)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: fg.withValues(alpha: 0.16)),
        boxShadow: [
          BoxShadow(
            color: fg.withValues(alpha: 0.14),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          children: [
            // ── Watermark icon bleeding into the bottom-right corner ────────
            Positioned(
              right: -14,
              bottom: -16,
              child: Icon(icon, size: 84, color: fg.withValues(alpha: 0.06)),
            ),

            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // ── Glowing icon chip + optional trend pill ──────────────
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Color.alphaBlend(fg.withValues(alpha: 0.10), bg),
                              Color.alphaBlend(fg.withValues(alpha: 0.28), bg),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: fg.withValues(alpha: 0.22),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Icon(icon, size: 20, color: fg),
                      ),
                      const Spacer(),
                      if (delta != null) _DeltaPill(text: delta!, positive: deltaPositive),
                    ],
                  ),

                  // ── Value + label ────────────────────────────────────────
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 28,
                          height: 1.0,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.6,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        label.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.6,
                          color: AppColors.textCaption,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small trend pill — green for positive, red for negative.
class _DeltaPill extends StatelessWidget {
  final String text;
  final bool positive;
  const _DeltaPill({required this.text, required this.positive});

  @override
  Widget build(BuildContext context) {
    final fg = positive ? AppColors.success : AppColors.error;
    final bg = positive ? AppColors.successBg : AppColors.errorBg;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(positive ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded, size: 11, color: fg),
          const SizedBox(width: 2),
          Text(
            text,
            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: fg),
          ),
        ],
      ),
    );
  }
}

/// Horizontally scrollable row of stat cards (mobile-friendly).
class LmsAdminStatRow extends StatelessWidget {
  final List<LmsAdminStatCard> cards;
  const LmsAdminStatRow({super.key, required this.cards});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 130,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: cards.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, i) => cards[i],
      ),
    );
  }
}
