import 'dart:async';
import 'package:flutter/material.dart';
import '../config/app_colors.dart';

/// Shows the request-submitted confirmation: a transient full-screen hero
/// (Figma "…confirmation" screens) with an amber check circle, a success
/// heading and a message. It auto-dismisses after a short delay, so the
/// post-submit navigation flow is unchanged.
///
/// Earlier this also fired a top snackbar alongside the hero. That snackbar was
/// redundant (the hero already confirms the submission) and lingered on screen,
/// so it was removed — the hero is now the single, self-dismissing confirmation.
///
/// The Figma confirmation screens also show per-request detail cards (Claim ID,
/// status, reimbursement time) and a "View My …" button + bottom nav. Those
/// require a full navigable screen with the submitted record's data; this
/// keeps the lightweight transient confirmation to avoid changing the flow.
Future<void> showRequestSubmittedSuccessDialog(
  BuildContext context, {
  String message = 'Your request has been received and is being processed.',
}) async {
  final overlay = Navigator.of(context, rootNavigator: true).overlay;
  if (overlay == null) return;

  OverlayEntry? entry;
  void remove() {
    entry?.remove();
    entry = null;
  }

  entry = OverlayEntry(
    builder: (ctx) => _RequestSuccessHero(message: message, onDismiss: remove),
  );
  overlay.insert(entry!);

  await Future<void>.delayed(const Duration(milliseconds: 2200));
  remove();
}

class _RequestSuccessHero extends StatelessWidget {
  const _RequestSuccessHero({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.background.withValues(alpha: 0.98),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onDismiss,
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primary,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.30),
                        blurRadius: 24,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: const Icon(Icons.check_rounded,
                      color: Colors.white, size: 48),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Submitted Successfully!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 48),
                  child: Text(
                    message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
