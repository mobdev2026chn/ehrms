import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_colors.dart';

class ThemeProvider with ChangeNotifier {
  static const String _themeKey = 'theme_color';
  static const String _themeModeKey =
      'theme_mode'; // 'light' | 'dark' | 'system'

  Color _primaryColor = const Color(0xFFEFAA1F);
  ThemeMode _themeMode = ThemeMode.system;

  Color get primaryColor => _primaryColor;
  ThemeMode get themeMode => _themeMode;
  bool get isDarkMode => _themeMode == ThemeMode.dark;

  final List<Color> themeColors = [
    const Color(0xFFEFAA1F),
    const Color(0xFF43A047),
    const Color(0xFF1E88E5),
    const Color(0xFFE53935),
    const Color(0xFF8E24AA),
    const Color(0xFFFB8C00),
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
    final colorScheme = ColorScheme.light(
      primary: _primaryColor,
      onPrimary: Colors.white,
      primaryContainer: _primaryColor.withOpacity(0.2),
      onPrimaryContainer: const Color(0xFF263238),
      secondary: _primaryColor.withOpacity(0.8),
      onSecondary: Colors.white,
      surface: Colors.white,
      onSurface: const Color(0xFF263238),
      onSurfaceVariant: const Color(0xFF78909C),
      surfaceContainerHighest: const Color(0xFFF5F7FA),
      error: AppColors.error,
      onError: Colors.white,
      errorContainer: AppColors.error.withOpacity(0.15),
      onErrorContainer: const Color(0xFF263238),
      outline: const Color(0xFFECEFF1),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: const Color(0xFFF5F7FA),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: _primaryColor),
        titleTextStyle: TextStyle(
          color: colorScheme.onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: _primaryColor,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      cardTheme: CardThemeData(
        color: colorScheme.surface,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: colorScheme.surface,
        scrimColor: Colors.black54,
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: Colors.white,
        selectedItemColor: _primaryColor,
        unselectedItemColor: colorScheme.onSurfaceVariant,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold),
        unselectedLabelStyle: TextStyle(color: colorScheme.onSurfaceVariant),
      ),
      listTileTheme: ListTileThemeData(
        textColor: colorScheme.onSurface,
        iconColor: colorScheme.onSurfaceVariant,
      ),
      iconTheme: IconThemeData(color: colorScheme.onSurface),
      dividerTheme: DividerThemeData(color: colorScheme.outline),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.grey.shade50,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        labelStyle: TextStyle(color: colorScheme.onSurfaceVariant),
        hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
      ),
      textTheme: TextTheme(
        bodyLarge: TextStyle(color: colorScheme.onSurface),
        bodyMedium: TextStyle(color: colorScheme.onSurface),
        bodySmall: TextStyle(color: colorScheme.onSurfaceVariant),
        titleLarge: TextStyle(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
        titleMedium: TextStyle(color: colorScheme.onSurface),
        titleSmall: TextStyle(color: colorScheme.onSurfaceVariant),
        labelLarge: TextStyle(color: colorScheme.onSurface),
      ),
    );
  }

  ThemeData getThemeData() => _buildTheme();
  ThemeData getDarkThemeData() => _buildTheme();
}
