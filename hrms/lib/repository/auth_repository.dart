// repository/auth_repository.dart
// Single data source abstraction for auth. Delegates to AuthService (data layer).
// No HTTP or JSON here; same API contract as before.

import '../services/auth_service.dart';

class AuthRepository {
  AuthRepository({AuthService? authService}) : _auth = authService ?? AuthService();

  final AuthService _auth;

  /// Login with email/password. If [otp] is provided, it is a 2FA verification login.
  /// Returns { success, data?, requiresOTP?, message? }.
  Future<Map<String, dynamic>> login(String email, String password, {String? otp}) async {
    return _auth.login(email, password, otp: otp);
  }

  /// After Google Sign-In, verify with backend. Returns { success, data?, message? }.
  Future<Map<String, dynamic>> googleLoginBackend(String email) async {
    return _auth.googleLoginBackend(email);
  }

  /// Get current user profile. Returns { success, data?, message? }.
  Future<Map<String, dynamic>> getProfile() async {
    return _auth.getProfile();
  }

  /// Clear token and local data; sign out from Google/Firebase.
  Future<void> logout() async {
    return _auth.logout();
  }

  /// Get stored access token (for other layers that need it).
  Future<String?> getToken() async {
    return _auth.getToken();
  }

  /// Forgot password: send OTP. Returns { success, message? }.
  Future<Map<String, dynamic>> forgotPassword(String email, {int retryCount = 0}) async {
    return _auth.forgotPassword(email, retryCount: retryCount);
  }

  /// Verify OTP. Returns { success, message? }.
  Future<Map<String, dynamic>> verifyOtp({required String email, required String otp}) async {
    return _auth.verifyOtp(email: email, otp: otp);
  }

  /// Reset password with OTP. Returns { success, message? }.
  Future<Map<String, dynamic>> resetPassword({
    required String email,
    required String otp,
    required String newPassword,
  }) async {
    return _auth.resetPassword(email: email, otp: otp, newPassword: newPassword);
  }

  /// Update profile. Returns { success, message? }.
  Future<Map<String, dynamic>> updateProfile(Map<String, dynamic> data) async {
    return _auth.updateProfile(data);
  }

  /// Update education. Returns { success, data?, message? }.
  Future<Map<String, dynamic>> updateEducation(List<Map<String, dynamic>> education) async {
    return _auth.updateEducation(education);
  }

  /// Update experience. Returns { success, data?, message? }.
  Future<Map<String, dynamic>> updateExperience(List<Map<String, dynamic>> experience) async {
    return _auth.updateExperience(experience);
  }

  /// Change password (old + new). Returns { success, message? }.
  Future<Map<String, dynamic>> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    return _auth.changePassword(oldPassword: oldPassword, newPassword: newPassword);
  }

  /// Upload profile photo. Returns { success, message?, data? }.
  Future<Map<String, dynamic>> updateProfilePhoto(dynamic imageFile) async {
    return _auth.updateProfilePhoto(imageFile);
  }

  /// Verify selfie against profile. Returns { success, match, message }.
  Future<Map<String, dynamic>> verifyFace(String selfieDataUrl) async {
    return _auth.verifyFace(selfieDataUrl);
  }
}
