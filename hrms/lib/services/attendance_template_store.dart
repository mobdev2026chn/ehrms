/// Stores attendance template details in SharedPreferences.
/// Used so check-in alert, selfie check-in, and attendance validation
/// can use fresh template data without re-login when templates change.
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class AttendanceTemplateStore {
  static const String _kTemplateDetailsKey = 'attendance_template_details';
  static const String _kSavedAtKey = 'attendance_template_saved_at';

  /// Save template details from /attendance/today response.
  /// Call when opening attendance check-in screen after fetching fresh data.
  static Future<void> saveTemplateDetails(Map<String, dynamic> details) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kTemplateDetailsKey, jsonEncode(details));
      await prefs.setString(_kSavedAtKey, DateTime.now().toIso8601String());
    } catch (_) {}
  }

  /// Load stored template details. Returns null if none or invalid.
  static Future<Map<String, dynamic>?> loadTemplateDetails() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final str = prefs.getString(_kTemplateDetailsKey);
      if (str == null || str.isEmpty) return null;
      final decoded = jsonDecode(str);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Clear stored template (e.g. on logout).
  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kTemplateDetailsKey);
      await prefs.remove(_kSavedAtKey);
    } catch (_) {}
  }
}
