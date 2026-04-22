// hrms/lib/config/constants.dart
class AppConstants {
  /// General app API (attendance, geo, profile, …).
  static const String baseUrl = 'http://192.168.1.33:9001/api';
 //static const String baseUrl = 'https://app.ektahr.com/api';
 //static const String baseUrl = 'https://ehrms.askeva.net/api';
  /// Production / web HRMS API — same host the web app uses for `GET /api/interaction/chats`, etc.
  static const String webBaseUrl = 'https://hrms.askeva.net/api';
 //static const String webBaseUrl = 'https://my.ektahr.com/api';

  /// When **true** (default): Interaction REST + Socket use [webBaseUrl] like the web.
  /// With a different [baseUrl], [AuthService] performs a second `/auth/login` against [webBaseUrl]
  /// and stores `interaction_access_token` so chat works without changing geo login.
  /// When **false**: Interaction uses [baseUrl] (needs TypeScript `backend` with `/api/interaction` on that host).
  static const bool interactionUseWebHost = true;
  /// When true, login uses only one network call (`POST /auth/login`) and
  /// skips post-login network side-effects for troubleshooting rate-limits.
  static const bool singleApiLoginMode = false;

  /// Prefs key: JWT for [webBaseUrl] when [baseUrl] is another server (set after web login sync).
  static const String interactionAccessTokenPrefsKey = 'interaction_access_token';

  /// REST base for `/interaction/*` and LMS routes on the same host as the web app.
  static String get interactionApiBaseUrl =>
      interactionUseWebHost ? webBaseUrl : baseUrl;

  /// WhatsApp-style background for Interaction message threads (`pubspec`: `assets/images/`).
  static const String interactionChatBackgroundAsset =
      'assets/images/chat-bg.jpeg';

  /// Socket.IO origin for Interaction (no `/api`, no trailing slash).
  static String get interactionSocketOrigin {
    final u = interactionApiBaseUrl;
    if (u.endsWith('/api')) return u.substring(0, u.length - 4);
    return u.replaceAll(RegExp(r'/+$'), '');
  }

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

  /// Explicit environment hint sent to backend for storage routing.
  /// This avoids relying only on proxy/origin headers for Spaces folder selection.
  static String get storageEnvironment {
    final host = Uri.tryParse(baseUrl)?.host.toLowerCase() ?? '';
    const productionHosts = {'app.ektahr.com', 'my.ektahr.com', 'ektahr.com'};
    return productionHosts.contains(host) ? 'production' : 'development';
  }

  /// Origin for Socket.IO (same server as REST; no trailing slash).
  static String get socketOrigin {
    final u = baseUrl;
    if (u.endsWith('/api')) return u.substring(0, u.length - 4);
    return u.replaceAll(RegExp(r'/+$'), '');
  }

  /// Debug console: presence + live task tracking POSTs (flutter run / debug only).
  // static const bool logTrackingsToConsole = true;
  static const bool logTrackingsToConsole = false;

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
        path.startsWith('data:')) {
      return path;
    }
    final p = path.startsWith('/') ? path : '/$path';
    return '$fileBaseUrl$p';
  }
}
