// hrms/lib/config/constants.dart
class AppConstants {
  /// Production API – use for release builds.
 // static const String baseUrl = 'https://ehrms.askeva.net/api';
//static const String baseUrl = 'https://ehrms.askeva.net/api';

  /// Local dev – backend on port 9001. Use your machine's **current** LAN IP (USB does not
  /// carry API traffic; the phone uses Wi‑Fi). On Windows run `ipconfig` and match Wi‑Fi IPv4.
  /// Quick check: open `http://<that-ip>:9001/api` in the phone browser (same Wi‑Fi).
  /// For LMS (and all) data to match the web for the same user, point [baseUrl]
  /// to the same backend the web frontend uses (e.g. production or same dev server).
  static const String baseUrl = 'http://192.168.16.104:9001/api';

  // Android emulator: use 10.0.2.2 to reach host
  // stati


  /// Google Maps key — enable **Geocoding API** for reverse geocode (lat/lng → address in app).
  /// Also Maps SDK, Places, Directions as needed. Restrict by app + APIs in Google Cloud Console.
  static const String googleMapsApiKey =
      'AIzaSyBcoj_g5hxrsv3mEJCVF1Uev_JZRcFO0F8';

  /// Privacy policy URL (required for Play Store).
  static const String privacyPolicyUrl =
      'https://doc-hosting.flycricket.io/ektahr-privacy-policy/d4be535f-6a23-4ff6-a5b6-efd3a9977365/privacy';

  /// Base URL without /api for file/asset paths (e.g. thumbnails, uploads).
  static String get fileBaseUrl {
    final u = baseUrl;
    if (u.endsWith('/api')) return u.substring(0, u.length - 4);
    return u.replaceAll(RegExp(r'/+$'), '');
  }

  /// Debug console: presence + live task tracking POSTs (flutter run / debug only).
  static const bool logTrackingsToConsole = true;

  /// When true, attendance selfie is verified against profile photo (face matching).
  /// When false, only on-device face detection runs; no server-side face matching.
  static const bool enableAttendanceFaceMatching = false;

  /// When true, show the lead/form fill step on arrived screen after getting a call (task).
  /// When false, form step is hidden and task can be completed without filling the form (code remains, just not shown).
  static const bool showLeadFormAfterCall = false;

  /// Absent alert: show "Absent Notification" when user has not logged in by this time (hour, minute).
  /// E.g. 10 and 11 → show alert from 10:11 onwards if no punch-in today.
  static const int absentAlertAfterHour = 10;
  static const int absentAlertAfterMinute = 11;

  /// Resolve LMS file path to full URL (handles relative paths and full URLs).
  static String getLmsFileUrl(String? path) {
    if (path == null || path.isEmpty) return '';
    if (path.startsWith('http://') ||
        path.startsWith('https://') ||
        path.startsWith('data:'))
      return path;
    final p = path.startsWith('/') ? path : '/$path';
    return '$fileBaseUrl$p';
  }
}
