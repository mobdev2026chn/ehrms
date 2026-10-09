import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_colors.dart';
import '../config/app_text_styles.dart';
import '../widgets/animations.dart';

class ThemeProvider with ChangeNotifier {
  static const String _themeKey = 'theme_color';
  static const String _themeModeKey =
      'theme_mode'; // 'light' | 'dark' | 'system'

  Color _primaryColor = const Color(0xFFF9B824);
  ThemeMode _themeMode = ThemeMode.system;

  Color get primaryColor => _primaryColor;
  ThemeMode get themeMode => _themeMode;
  bool get isDarkMode => _themeMode == ThemeMode.dark;

  final List<Color> themeColors = [
    const Color(0xFFF9B824),
    const Color(0xFF43A047),
    const Color(0xFF1E88E5),
    const Color(0xFFE53935),
    const Color(0xFF8E24AA),
    // (the orange option was dropped: oranges now use the brand gold, listed first)
    const Color(0xFFE91E63),
    const Color(0xFF000000),
  ];

  ThemeProvider() {
    _loadTheme();
    final previous =
        WidgetsBinding.instance.platformDispatcher.onPlatformBrightnessChanged;
    WidgetsBinding.instance.platformDispatcher.onPlatformBrightnessChanged =
        () {
          previous?.call();
          if (_themeMode == ThemeMode.system) {
            _syncAppColorsToTheme();
            notifyListeners();
          }
        };
  }

  bool get _effectiveIsDark {
    if (_themeMode == ThemeMode.dark) return true;
    if (_themeMode == ThemeMode.light) return false;
    return WidgetsBinding.instance.platformDispatcher.platformBrightness ==
        Brightness.dark;
  }

  void _syncAppColorsToTheme() {
    AppColors.updateForBrightness(_effectiveIsDark);
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final colorValue = prefs.getInt(_themeKey);
    final modeStr = prefs.getString(_themeModeKey);
    if (colorValue != null) {
      _primaryColor = Color(colorValue);
      AppColors.updateTheme(_primaryColor);
    }
    if (modeStr != null) {
      switch (modeStr) {
        case 'dark':
          _themeMode = ThemeMode.dark;
          break;
        case 'light':
          _themeMode = ThemeMode.light;
          break;
        default:
          _themeMode = ThemeMode.system;
      }
    }
    _syncAppColorsToTheme();
    notifyListeners();
  }

  Future<void> setThemeColor(Color color) async {
    _primaryColor = color;
    AppColors.updateTheme(color);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_themeKey, color.value);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    _syncAppColorsToTheme();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    final value = mode == ThemeMode.dark
        ? 'dark'
        : mode == ThemeMode.light
        ? 'light'
        : 'system';
    await prefs.setString(_themeModeKey, value);
  }

  ThemeData _buildTheme() {
    // Always use light ColorScheme for visibility: white backgrounds, dark text.
    // This ensures all screens (request, profile, attendance, etc.) are readable
    // even when phone or app is in dark mode.
    final onPrimary =
        ThemeData.estimateBrightnessForColor(_primaryColor) == Brightness.dark
        ? Colors.white
        : AppColors.ink;
    // Use primary color directly for icons, accents, and theme elements.
    final primaryText = _primaryColor;
    const fieldFill = Color(0xFFF7F8FA);
    const fieldBorder = Color(0xFFE2E5EA);
    const hairline = Color(0xFFECEEF1);
    const font = AppTextStyles.fontFamily;

    final colorScheme = ColorScheme.light(
      primary: _primaryColor,
      onPrimary: onPrimary,
      primaryContainer: _primaryColor.withValues(alpha: 0.16),
      onPrimaryContainer: AppColors.textPrimary,
      secondary: _primaryColor.withValues(alpha: 0.8),
      onSecondary: onPrimary,
      surface: Colors.white,
      onSurface: AppColors.textPrimary,
      onSurfaceVariant: AppColors.textSecondary,
      surfaceContainerHighest: const Color(0xFFF5F7FA),
      surfaceTint: Colors.transparent,
      error: AppColors.error,
      onError: Colors.white,
      errorContainer: AppColors.error.withValues(alpha: 0.15),
      onErrorContainer: AppColors.textPrimary,
      outline: fieldBorder,
      outlineVariant: hairline,
    );

    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
    );
    const buttonText = TextStyle(
      fontFamily: font,
      fontSize: 15,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.1,
    );
    OutlineInputBorder outline(Color color, [double width = 1.2]) {
      return OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: color, width: width),
      );
    }

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: colorScheme,
      fontFamily: font,
      scaffoldBackgroundColor: AppColors.background,
      splashFactory: InkSparkle.splashFactory,
      // Smooth fade+slide transition for every MaterialPageRoute, app-wide.
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeThroughPageTransitionsBuilder(),
          TargetPlatform.iOS: FadeThroughPageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: colorScheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        shape: const Border(bottom: BorderSide(color: hairline)),
        iconTheme: IconThemeData(color: primaryText, size: 22),
        actionsIconTheme: IconThemeData(color: primaryText, size: 22),
        titleTextStyle: const TextStyle(
          fontFamily: font,
          color: AppColors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: _primaryColor,
          foregroundColor: onPrimary,
          disabledBackgroundColor: const Color(0xFFE5E7EB),
          disabledForegroundColor: AppColors.textCaption,
          elevation: 0,
          shadowColor: Colors.transparent,
          minimumSize: const Size(64, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: buttonShape,
          textStyle: buttonText,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: _primaryColor,
          foregroundColor: onPrimary,
          minimumSize: const Size(64, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: buttonShape,
          textStyle: buttonText,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          side: const BorderSide(color: fieldBorder, width: 1.2),
          minimumSize: const Size(64, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: buttonShape,
          textStyle: buttonText,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primaryText,
          shape: buttonShape,
          textStyle: buttonText.copyWith(fontSize: 14),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: _primaryColor,
        foregroundColor: onPrimary,
        elevation: 2,
        focusElevation: 3,
        hoverElevation: 3,
        highlightElevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        extendedTextStyle: buttonText,
      ),
      cardTheme: CardThemeData(
        color: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        shadowColor: const Color(0x140F172A),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: hairline),
        ),
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        scrimColor: Colors.black54,
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: Colors.white,
        selectedItemColor: primaryText,
        unselectedItemColor: AppColors.textCaption,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        selectedLabelStyle: const TextStyle(
          fontFamily: font,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: const TextStyle(
          fontFamily: font,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
      listTileTheme: ListTileThemeData(
        textColor: colorScheme.onSurface,
        iconColor: AppColors.textSecondary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        titleTextStyle: const TextStyle(
          fontFamily: font,
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: AppColors.textPrimary,
        ),
        subtitleTextStyle: const TextStyle(
          fontFamily: font,
          fontSize: 13,
          color: AppColors.textSecondary,
        ),
      ),
      iconTheme: IconThemeData(color: colorScheme.onSurface),
      dividerTheme: const DividerThemeData(
        color: hairline,
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: WidgetStateColor.resolveWith(
          (states) =>
              states.contains(WidgetState.focused) ? Colors.white : fieldFill,
        ),
        hoverColor: const Color(0xFFF1F3F6),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: outline(fieldBorder),
        enabledBorder: outline(fieldBorder),
        disabledBorder: outline(hairline),
        focusedBorder: outline(_primaryColor, 1.6),
        errorBorder: outline(AppColors.error.withValues(alpha: 0.7)),
        focusedErrorBorder: outline(AppColors.error, 1.6),
        labelStyle: const TextStyle(
          fontFamily: font,
          fontSize: 14,
          color: AppColors.textSecondary,
        ),
        floatingLabelStyle: WidgetStateTextStyle.resolveWith(
          (states) => TextStyle(
            fontFamily: font,
            fontWeight: FontWeight.w500,
            color: states.contains(WidgetState.error)
                ? AppColors.error
                : states.contains(WidgetState.focused)
                ? primaryText
                : AppColors.textSecondary,
          ),
        ),
        hintStyle: const TextStyle(
          fontFamily: font,
          fontSize: 14,
          color: AppColors.textCaption,
        ),
        errorStyle: const TextStyle(
          fontFamily: font,
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: AppColors.error,
        ),
        prefixIconColor: WidgetStateColor.resolveWith((states) {
          if (states.contains(WidgetState.error)) return AppColors.error;
          if (states.contains(WidgetState.focused)) return primaryText;
          return AppColors.textCaption;
        }),
        suffixIconColor: AppColors.textSecondary,
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: primaryText,
        selectionColor: _primaryColor.withValues(alpha: 0.3),
        selectionHandleColor: _primaryColor,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: const Color(0xFFF3F4F6),
        selectedColor: _primaryColor.withValues(alpha: 0.16),
        disabledColor: const Color(0xFFF3F4F6),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        labelStyle: const TextStyle(
          fontFamily: font,
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: AppColors.textPrimary,
        ),
        secondaryLabelStyle: TextStyle(
          fontFamily: font,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: primaryText,
        ),
        checkmarkColor: primaryText,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: AppColors.textPrimary,
        unselectedLabelColor: AppColors.textSecondary,
        indicatorColor: _primaryColor,
        indicatorSize: TabBarIndicatorSize.label,
        indicator: UnderlineTabIndicator(
          borderSide: BorderSide(color: _primaryColor, width: 3),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
        ),
        dividerColor: hairline,
        labelStyle: const TextStyle(
          fontFamily: font,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: const TextStyle(
          fontFamily: font,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titleTextStyle: const TextStyle(
          fontFamily: font,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
        contentTextStyle: const TextStyle(
          fontFamily: font,
          fontSize: 14,
          height: 1.45,
          color: AppColors.textSecondary,
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.white,
        modalBackgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 4,
        shadowColor: const Color(0x260F172A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: hairline),
        ),
        textStyle: const TextStyle(
          fontFamily: font,
          fontSize: 14,
          color: AppColors.textPrimary,
        ),
      ),
      menuTheme: const MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(Colors.white),
          surfaceTintColor: WidgetStatePropertyAll(Colors.transparent),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.ink,
        contentTextStyle: const TextStyle(
          fontFamily: font,
          fontSize: 14,
          color: Colors.white,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.ink.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: const TextStyle(
          fontFamily: font,
          fontSize: 12,
          color: Colors.white,
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: _primaryColor,
        linearTrackColor: _primaryColor.withValues(alpha: 0.15),
        circularTrackColor: Colors.transparent,
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
        side: const BorderSide(color: Color(0xFFC5CAD3), width: 1.5),
        fillColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? _primaryColor : null,
        ),
        checkColor: WidgetStatePropertyAll(onPrimary),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? _primaryColor
              : const Color(0xFFC5CAD3),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? Colors.white : null,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? _primaryColor : null,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.transparent
              : null,
        ),
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        headerBackgroundColor: _primaryColor,
        headerForegroundColor: onPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        todayForegroundColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? onPrimary : primaryText,
        ),
        todayBorder: BorderSide(color: _primaryColor),
        dayForegroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? onPrimary : null,
        ),
        yearForegroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? onPrimary : null,
        ),
      ),
      timePickerTheme: TimePickerThemeData(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        dialHandColor: _primaryColor,
        hourMinuteShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      // Typography is driven by AppTextStyles (Figma EktaHR scale). Only ~8
      // call sites read from the global textTheme today; screens otherwise use
      // explicit TextStyle / AppTextStyles, so this stays close to defaults.
      textTheme: AppTextStyles.textTheme(
        colorScheme.onSurface,
        colorScheme.onSurfaceVariant,
      ),
    );
  }

  ThemeData getThemeData() => _buildTheme();
  ThemeData getDarkThemeData() => _buildTheme();
}
