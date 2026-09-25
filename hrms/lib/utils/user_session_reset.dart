import '../services/attendance_service.dart';
import '../services/auth_service.dart';
import '../services/break_service.dart';
import '../services/request_service.dart';
import 'swr_cache.dart';

/// Clears everything the app keeps IN MEMORY about the signed-in user.
///
/// Logout already clears SharedPreferences, but several services keep static
/// caches for the whole app lifetime (today/month attendance, break state,
/// profile, reviewer names). Without this, a second user logging in on the same
/// phone saw the first user's data — e.g. "On Break" with their break time.
///
/// Called on logout, when the session is force-cleared (token invalid), and at
/// the start of every login.
void resetUserScopedState() {
  AttendanceService.resetForNewUser();
  BreakService.resetForNewUser();
  RequestService.resetForNewUser();
  AuthService.invalidateProfileCache();
  AuthService.clearFaceEnrollCache();
  SwrCache.clearAll();
}
