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
/// The 1-to-many check now runs on HRMSbackend inside the same live verification
/// call as the 1-to-1 check (POST /staff/face/verify, see AuthService.verifyFace):
/// a selfie that matches a different employee better than the logged-in one is
/// rejected there with that employee's name. This guard therefore has nothing
/// extra to check and always allows; the punch is gated by verifyFace, which
/// fails closed.
///
/// The old path called the separate face app (eface) and auto-enrolled unknown
/// users there; it could never recognise app users and let every punch through.
class FaceIdentityGuard {
  static Future<FaceIdentityVerdict> verify(String selfieDataUrl) async {
    return const FaceIdentityVerdict(true);
  }
}
