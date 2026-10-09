import 'package:flutter/material.dart';

/// Figma design tokens — EktaHR design system.
/// Primary amber/gold palette with clean white surface.
class AppColors {
  // ── Brand ──────────────────────────────────────────────────────────────
  static Color primary      = const Color(0xFFF9B824); // Amber gold
  static Color primaryDark  = const Color(0xFFF9B824); // Darker gold
  static Color primaryLight = const Color(0xFFF9B824); // Tinted amber bg
  static const Color accent = brand;

  // Constant brand shades, usable inside `const` widgets. Every orange/amber in the
  // app uses these, so the app has one gold instead of assorted oranges:
  //   brand       - fills, icons, accents (the primary colour)
  //   brandDark   - text / icons on light backgrounds (readable gold)
  //   brandLight  - tinted backgrounds
  //   brandBorder - borders on tinted backgrounds
  static const Color brand       = Color(0xFFF9B824);
  static const Color brandDark   = Color(0xFFF9B824);
  static const Color brandLight  = Color(0xFFFFF3D6);
  static const Color brandBorder = Color(0xFFF7D58A);

  /// Near-black from the EktaHR logo (wordmark, dark surfaces).
  static const Color ink = Color(0xFF111113);

  /// Readable text/icon colour on a [primary] fill: ink on light picks
  /// (the default gold), white on dark picks (blue, purple, black, ...).
  static Color get onPrimary =>
      ThemeData.estimateBrightnessForColor(primary) == Brightness.dark
          ? Colors.white
          : ink;

  /// Readable icon / text primary shade on light backgrounds.
  static Color primaryText = const Color(0xFFF9B824); // Amber gold


  // ── Secondary accent (Figma indigo) ─────────────────────────────────────
  // Highlight values like Performance score and "This Month Net" (₹ amount).
  static const Color indigo   = Color(0xFF6366F1);
  static const Color indigoBg = Color(0xFFEEF0FF);

  // ── Backgrounds ────────────────────────────────────────────────────────
  static const Color background     = Color(0xFFF5F7FA); // App background
  static const Color surface        = Color(0xFFFFFFFF); // Card / sheet
  static const Color surfaceDark    = Color(0xFF1C1C1E); // Dark card (celebrations, net pay, bottom nav)
  static const Color inputFill      = Color(0xFFF3F4F6); // Form field bg
  static const Color divider        = Color(0xFFE5E7EB);

  // ── Text ───────────────────────────────────────────────────────────────
  static const Color textPrimary    = Color(0xFF111827); // Near-black
  static const Color textSecondary  = Color(0xFF6B7280); // Medium grey
  static const Color textCaption    = Color(0xFF9CA3AF); // Section labels
  static const Color textHint       = Color(0xFFD1D5DB); // Placeholder

  // ── Semantic ───────────────────────────────────────────────────────────
  static const Color success        = Color(0xFF059669);
  static const Color successBg      = Color(0xFFD1FAE5);
  static const Color warning        = brandDark;
  static const Color warningBg      = brandLight;
  static const Color error          = Color(0xFFDC2626);
  static const Color errorBg        = Color(0xFFFEE2E2);
  static const Color info           = Color(0xFF2563EB);
  static const Color infoBg         = Color(0xFFDBEAFE);

  // ── Legacy aliases (kept for compatibility) ────────────────────────────
  static Color secondary    = const Color(0xFF2196F3);
  static Color text         = const Color(0xFF111827);
  static Color textPrimaryM = const Color(0xFF111827);
  static Color textSecondaryM = const Color(0xFF6B7280);

  // ── Theme helpers ──────────────────────────────────────────────────────
  static void updateTheme(Color color) {
    primary      = color;
    primaryDark  = color;
    primaryLight = color.withValues(alpha: 0.12);
    primaryText  = color;
  }

  static void updateForBrightness(bool isDark) {}


  // ── Utility ────────────────────────────────────────────────────────────
  /// Returns status badge foreground + background for a status string.
  static ({Color fg, Color bg, String label}) statusStyle(String status) {
    switch (status.toLowerCase()) {
      case 'approved':   return (fg: success,  bg: successBg, label: 'Approved');
      case 'present':    return (fg: success,  bg: successBg, label: 'Present');
      case 'rejected':   return (fg: error,    bg: errorBg,   label: 'Rejected');
      case 'absent':     return (fg: error,    bg: errorBg,   label: 'Absent');
      case 'pending':    return (fg: warning,  bg: warningBg, label: 'Pending');
      case 'under review': return (fg: warning, bg: warningBg, label: 'Under Review');
      case 'on leave':   return (fg: info,     bg: infoBg,    label: 'On Leave');
      case 'holiday':    return (fg: warning,  bg: warningBg, label: 'Holiday');
      case 'weekend':    return (fg: const Color(0xFF7C3AED), bg: const Color(0xFFEDE9FE), label: 'Weekend');
      default:           return (fg: textSecondary, bg: inputFill, label: status);
    }
  }
}

extension ThemeColors on BuildContext {
  ColorScheme get colorScheme => Theme.of(this).colorScheme;
  ThemeData   get theme       => Theme.of(this);
}
