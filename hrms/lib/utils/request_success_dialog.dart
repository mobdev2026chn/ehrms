import 'package:flutter/material.dart';
import '../widgets/notification_reaction_overlay.dart';
import 'snackbar_utils.dart';

/// Shows request submitted feedback using snackbar plus centered emoji only.
Future<void> showRequestSubmittedSuccessDialog(BuildContext context) async {
  SnackBarUtils.showSnackBar(
    context,
    'Your request has been submitted successfully.',
  );

  await NotificationReactionOverlay.show(
    context,
    emoji: '👍',
  );
}
