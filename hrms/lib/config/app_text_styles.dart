import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Figma design tokens — EktaHR typography scale.
///
/// Single source of truth for text styles, mirroring the EktaHR Figma file
/// (`ektaHr`). Uses the bundled **Inter** family (see `pubspec.yaml`), which
/// ships weights 400/500/600/700 only — do NOT use w300/w800 here, they are
/// not bundled and will be synthesized inconsistently across platforms.
///
/// Prefer these named styles over inline `TextStyle(...)` in new/redesigned
/// screens. Colors come from [AppColors]; override per-use with `.copyWith`.
class AppTextStyles {
  AppTextStyles._();

  static const String fontFamily = 'Inter';

  // ── Display / hero numbers (net pay, big amounts) ───────────────────────
  static const TextStyle displayLarge = TextStyle(
    fontFamily: fontFamily,
    fontSize: 28,
    height: 1.15,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
  );

  // ── Headings ────────────────────────────────────────────────────────────
  /// Page / screen title (h1).
  static const TextStyle headingLarge = TextStyle(
    fontFamily: fontFamily,
    fontSize: 22,
    height: 1.2,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
  );

  /// Card / section heading (h2).
  static const TextStyle headingMedium = TextStyle(
    fontFamily: fontFamily,
    fontSize: 18,
    height: 1.25,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  /// Sub-heading / list-item title (h3).
  static const TextStyle headingSmall = TextStyle(
    fontFamily: fontFamily,
    fontSize: 16,
    height: 1.3,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  // ── Body ──────────────────────────────────────────────────────────────--
  static const TextStyle bodyLarge = TextStyle(
    fontFamily: fontFamily,
    fontSize: 15,
    height: 1.4,
    fontWeight: FontWeight.w400,
    color: AppColors.textPrimary,
  );

  static const TextStyle bodyMedium = TextStyle(
    fontFamily: fontFamily,
    fontSize: 14,
    height: 1.4,
    fontWeight: FontWeight.w400,
    color: AppColors.textPrimary,
  );

  static const TextStyle bodySmall = TextStyle(
    fontFamily: fontFamily,
    fontSize: 13,
    height: 1.4,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
  );

  // ── Labels / captions ────────────────────────────────────────────────────
  /// Medium-weight inline label (field labels, chips).
  static const TextStyle label = TextStyle(
    fontFamily: fontFamily,
    fontSize: 14,
    height: 1.3,
    fontWeight: FontWeight.w500,
    color: AppColors.textPrimary,
  );

  /// All-caps section label, e.g. "TODAY'S ATTENDANCE".
  static const TextStyle sectionLabel = TextStyle(
    fontFamily: fontFamily,
    fontSize: 11,
    height: 1.2,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.0,
    color: AppColors.textCaption,
  );

  /// Secondary caption / helper text.
  static const TextStyle caption = TextStyle(
    fontFamily: fontFamily,
    fontSize: 12,
    height: 1.3,
    fontWeight: FontWeight.w400,
    color: AppColors.textCaption,
  );

  // ── Interactive ───────────────────────────────────────────────────────--
  /// Button / actionable label. Color is set by the button theme/foreground,
  /// so this intentionally omits a color (defaults to the button's onColor).
  static const TextStyle button = TextStyle(
    fontFamily: fontFamily,
    fontSize: 15,
    height: 1.2,
    fontWeight: FontWeight.w600,
  );

  /// Builds the Material [TextTheme] from these tokens. Wired into
  /// `ThemeData` in `ThemeProvider`. Only ~8 call sites read from the global
  /// textTheme today, so this is intentionally close to Material defaults.
  static TextTheme textTheme(Color onSurface, Color onSurfaceVariant) {
    return TextTheme(
      displayLarge: displayLarge.copyWith(color: onSurface),
      displayMedium: headingLarge.copyWith(color: onSurface),
      displaySmall: headingMedium.copyWith(color: onSurface),
      headlineMedium: headingMedium.copyWith(color: onSurface),
      headlineSmall: headingSmall.copyWith(color: onSurface),
      titleLarge: headingMedium.copyWith(color: onSurface),
      titleMedium: headingSmall.copyWith(color: onSurface),
      titleSmall: label.copyWith(color: onSurfaceVariant),
      bodyLarge: bodyLarge.copyWith(color: onSurface),
      bodyMedium: bodyMedium.copyWith(color: onSurface),
      bodySmall: bodySmall.copyWith(color: onSurfaceVariant),
      labelLarge: button.copyWith(color: onSurface),
      labelMedium: label.copyWith(color: onSurfaceVariant),
      labelSmall: caption.copyWith(color: onSurfaceVariant),
    );
  }
}
