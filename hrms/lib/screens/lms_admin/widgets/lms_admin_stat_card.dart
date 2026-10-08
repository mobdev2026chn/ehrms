// hrms/lib/screens/lms_admin/widgets/lms_admin_stat_card.dart
// Shared stat tile used across the admin LMS screens — white card with a
// tinted icon tile, a soft watermark icon bleeding into the corner,
// value-first hierarchy, and an optional trend pill.

import 'package:flutter/material.dart';
import '../../../config/app_colors.dart';
import '../../../config/app_text_styles.dart';
import '../../../widgets/app_card.dart';

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
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFECEEF1)),
        boxShadow: kSoftCardShadow,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            // ── Watermark icon bleeding into the bottom-right corner ────────
            Positioned(
              right: -14,
              bottom: -16,
              child: Icon(icon, size: 84, color: fg.withValues(alpha: 0.05)),
            ),

            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // ── Tinted icon tile + optional trend pill ───────────────
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Color.alphaBlend(fg.withValues(alpha: 0.12), bg),
                          borderRadius: BorderRadius.circular(12),
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
                        style: AppTextStyles.displayLarge.copyWith(
                          fontSize: 26,
                          height: 1.0,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        label.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.sectionLabel.copyWith(
                          fontSize: 10.5,
                          letterSpacing: 0.6,
                          color: AppColors.textSecondary,
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
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
