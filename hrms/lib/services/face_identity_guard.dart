import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/constants.dart';

/// Verdict from the cross-user identity check.
class FaceIdentityVerdict {
  /// Whether the punch/break may proceed.
  final bool allow;

  /// User-facing reason when [allow] is false.
  final String? message;

  const FaceIdentityVerdict(this.allow, [this.message]);
}

/// Cross-user (1-to-many) identity guard — anti buddy-punching.
///
/// EHRMS's own `/auth/verify-face` is 1-to-1 (the selfie vs the logged-in user's
/// OWN reference). That can't catch a user with no reference, and doesn't say
/// "this is actually a different employee". This guard asks the Face backend's
/// `verify-identity` endpoint, which embeds the selfie and matches it against
/// ALL enrolled faces, then confirms the best match is the logged-in user.
///
/// Fail-open by design: it only BLOCKS on a confident wrong-person result
/// (a different enrolled employee, or a face that matches no enrolled profile).
/// Anything it can't determine — user not enrolled in the Face system, backend
/// unreachable, no face — returns allow=true so it never bricks attendance
/// (EHRMS's own 1-to-1 verify-face still applies on top of this).
class FaceIdentityGuard {
  /// [selfieDataUrl] is the same compressed `data:image/jpeg;base64,...` payload
  /// already built for the punch.
  static Future<FaceIdentityVerdict> verify(String selfieDataUrl) async {
    if (!AppConstants.enableCrossUserFaceCheck) {
      return const FaceIdentityVerdict(true);
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final userStr = prefs.getString('user');
      if (userStr == null) return const FaceIdentityVerdict(true);
      final user = jsonDecode(userStr) as Map<String, dynamic>;
      final email = (user['email'] ?? '').toString();
      final empId = (user['employeeId'] ?? '').toString();
      final uid = (user['id'] ?? user['_id'] ?? '').toString();

      final uri = Uri.parse(
        '${AppConstants.faceVerifyBaseUrl}/attendance/verify-identity',
      );
      final res = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'image_base64': selfieDataUrl,
              'claimed_email': email,
              'claimed_employee_id': empId,
              'claimed_user_id': uid,
            }),
          )
          .timeout(const Duration(seconds: 20));

      if (res.statusCode != 200) return const FaceIdentityVerdict(true);
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      if (j['verified'] == true) return const FaceIdentityVerdict(true);

      final reason = (j['reason'] ?? '').toString();
      if (reason == 'identity_mismatch') {
        final who = (j['matched_name'] ?? '').toString().trim();
        return FaceIdentityVerdict(
          false,
          who.isNotEmpty
              ? 'This face matches $who — not your account. Punch denied.'
              : 'This face matches another employee — not your account. Punch denied.',
        );
      }
      if (reason == 'not_recognized') {
        return const FaceIdentityVerdict(
          false,
          'Face does not match your enrolled profile. Please try again.',
        );
      }
      // claimer_not_enrolled / no_face / error / anything else → can't verify
      // cross-user → allow (EHRMS 1-to-1 verify-face still gates the punch).
      if (kDebugMode) {
        debugPrint('[FaceIdentityGuard] inconclusive ($reason) → allow');
      }
      return const FaceIdentityVerdict(true);
    } catch (e) {
      if (kDebugMode) debugPrint('[FaceIdentityGuard] error → allow: $e');
      return const FaceIdentityVerdict(true);
    }
  }
}
