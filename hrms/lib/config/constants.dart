// hrms/lib/config/constants.dart
class AppConstants {
  /// General app API (attendance, geo, profile, …).
  /// DEV SERVER ONLY — both the HRMS app and the face kiosk punch against this
  /// same dev host. Do NOT point at production (app.ektahr.com / my.ektahr.com).
  // Local-dev alt: `adb reverse tcp:2001 tcp:2001`, then 'http://127.0.0.1:2001/api'
  // (EHRMS backend PORT=2001 in app_backend/.env).
  static const String baseUrl = 'https://ehrms.askeva.net/api';

  /// Web/Interaction HRMS API — dev web companion of [baseUrl] (chat, polls, LMS).
  static const String webBaseUrl = 'https://hrms.askeva.net/api';

  /// When **true** (default): Interaction REST + Socket use [webBaseUrl] like the web.
  /// With a different [baseUrl], [AuthService] performs a second `/auth/login` against [webBaseUrl]
  /// and stores `interaction_access_token` so chat works without changing geo login.
  /// When **false**: Interaction uses [baseUrl] (needs TypeScript `backend` with `/api/interaction` on that host).
  static const bool interactionUseWebHost = true;

  /// When true, login uses only one network call (`POST /auth/login`) and
  /// skips post-login network side-effects for troubleshooting rate-limits.
  static const bool singleApiLoginMode = false;

  /// Prefs key: JWT for [webBaseUrl] when [baseUrl] is another server (set after web login sync).
  static const String interactionAccessTokenPrefsKey =
      'interaction_access_token';

  /// Prefs key: long-lived refresh JWT for `POST /auth/refresh` (main API host).
  static const String refreshTokenPrefsKey = 'refresh_token';

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
  static const bool logTrackingsToConsole = true;
  // static const bool logTrackingsToConsole = false;

  /// Task live-tracking capture interval (used by ride screen periodic upload timer).
  /// TESTING now: 5 minutes. Set to 900 for 15 minutes in production.
  static const int taskTrackingCaptureIntervalSeconds = 300;

  /// Presence (non-task) tracking interval in seconds.
  /// TESTING now: 5 minutes. Set to 900 for 15 minutes in production.
  static const int presenceTrackingCaptureIntervalSeconds = 300;

  /// EHRMS's OWN face engine on the API host (9001), in-process via /auth/verify-face
  /// (faceEngine.js spawns the dlib worker — no extra port). ENABLED: the EHRMS app
  /// gets its own engine that validates the punch selfie 1-to-1 against the EHRMS
  /// single-click enrollment. Runs alongside the same-domain face app engine
  /// ([enableCrossUserFaceCheck]). Requires the dlib deps on the 9001 host
  /// (face_verify/venv, or FACE_PYTHON_BIN) — see face_verify/setup_engine.sh.
  static const bool enableAttendanceFaceMatching = true;

  /// Cross-user face check (anti buddy-punch): before a punch/break the app asks
  /// the Face backend whether the captured face is the logged-in user and NOT a
  /// different enrolled employee. EHRMS's own verify-face is 1-to-1 (self only);
  /// this adds 1-to-many identity confirmation. Requires the Face backend running
  /// Face validation via the FACE APP's engine, reached on the SAME DOMAIN
  /// ([faceVerifyBaseUrl] → https://ehrms.askeva.net/face/api). ENABLED so EHRMS uses
  /// the already-working face engine instead of running Python on the EHRMS API host.
  /// It does 1-to-1 + 1-to-many against the face app's enrolled faces. Requires: the
  /// /face reverse-proxy live on the EHRMS domain, and the employee enrolled in the
  /// face app. Fail-open (never bricks attendance if the engine is unreachable).
  static const bool enableCrossUserFaceCheck = true;

  /// Face backend base — SAME DOMAIN as EHRMS. The face app's engine is reverse-
  /// proxied under /face on the EHRMS domain, so EHRMS reaches the (already working)
  /// face recognition engine without a separate IP/port and without installing the
  /// Python engine on the EHRMS API host. (LAN-IP dev value kept below for reference.)
  static const String faceVerifyBaseUrl = 'https://ehrms.askeva.net/face/api';
  // Local dev (machine LAN IP): 'http://192.168.0.26:8000/api'

  /// Punch/break/permission selfies captured BEFORE this instant were stored
  /// upside-down: the front camera (camerawesome) wrote pixels rotated 180° with
  /// EXIF orientation = 1, so the upload-time orientation bake was a no-op and the
  /// saved pixels stayed rotated 180°. Those legacy images are rotated 180° on
  /// display to look correct. Selfies captured at/after this instant are baked
  /// upright at capture time (SelfieCameraScreen.bakeSelfieUpright180) and stored
  /// upright everywhere — server, profile avatar, face match — so they render as-is.
  ///
  /// SET THIS to the UTC instant the build containing the capture-time rotation fix
  /// goes live. Any selfie taken before it is treated as a legacy (flipped) image.
  static final DateTime selfieOrientationFixCutoffUtc = DateTime.utc(
    2026,
    6,
    17,
  );

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

  /// Base URL (no `/api`) for Interaction/chat uploads. These files live on the
  /// same host the chat REST/Socket talks to ([interactionApiBaseUrl]), which is
  /// the web host when [interactionUseWebHost] is true — NOT [baseUrl]. Using
  /// [fileBaseUrl] here would point chat media at the geo backend host (e.g.
  /// 127.0.0.1:9001 in dev), which doesn't hold those uploads and just times out.
  static String get interactionFileBaseUrl {
    final u = interactionApiBaseUrl;
    if (u.endsWith('/api')) return u.substring(0, u.length - 4);
    return u.replaceAll(RegExp(r'/+$'), '');
  }

  /// Resolve an Interaction/chat file path (image, document, voice, avatar) to a
  /// full URL against the interaction host. Full URLs/data URIs pass through.
  static String getInteractionFileUrl(String? path) {
    if (path == null || path.isEmpty) return '';
    if (path.startsWith('http://') ||
        path.startsWith('https://') ||
        path.startsWith('data:')) {
      return path;
    }
    final p = path.startsWith('/') ? path : '/$path';
    return '$interactionFileBaseUrl$p';
  }
}
