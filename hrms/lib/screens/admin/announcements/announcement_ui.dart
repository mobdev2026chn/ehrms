// Shared bits for the admin Announcements screens: status rule, badge, date formatting.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../config/app_colors.dart';
import '../../../config/app_text_styles.dart';
import '../../../widgets/app_card.dart';

String announcementId(Map<String, dynamic> a) => (a['_id'] ?? a['id'] ?? '').toString();

DateTime? announcementDate(dynamic v) {
  if (v == null) return null;
  final d = DateTime.tryParse(v.toString());
  return d?.toLocal();
}

String announcementDateLabel(dynamic v, {String empty = '-'}) {
  final d = announcementDate(v);
  return d == null ? empty : DateFormat('d MMM yyyy').format(d);
}

String announcementDateTimeLabel(dynamic v) {
  final d = announcementDate(v);
  return d == null ? '' : DateFormat('d MMM yyyy, h:mm a').format(d);
}

/// Same rule as the backend's pre-save hook: Draft -> Expired -> Scheduled -> Published,
/// compared against the start of today. Derived here so a stored status that went stale
/// (a scheduled date that has since passed) still shows correctly.
String announcementStatus(Map<String, dynamic> a) {
  if (a['isDraft'] == true) return 'Draft';
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final expiry = announcementDate(a['expiryDate']);
  if (expiry != null && expiry.isBefore(today)) return 'Expired';
  final publish = announcementDate(a['publishDate']);
  if (publish != null && publish.isAfter(today)) return 'Scheduled';
  return 'Published';
}

({Color fg, Color bg}) announcementStatusColors(String status) {
  switch (status) {
    case 'Published':
      return (fg: AppColors.success, bg: AppColors.successBg);
    case 'Scheduled':
      return (fg: AppColors.info, bg: AppColors.infoBg);
    case 'Expired':
      return (fg: AppColors.error, bg: AppColors.errorBg);
    default:
      return (fg: AppColors.textSecondary, bg: AppColors.inputFill);
  }
}

class AnnouncementStatusBadge extends StatelessWidget {
  const AnnouncementStatusBadge(this.status, {super.key});
  final String status;

  @override
  Widget build(BuildContext context) {
    final c = announcementStatusColors(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: c.bg, borderRadius: BorderRadius.circular(999)),
      child: Text(status.toUpperCase(), style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, letterSpacing: 0.4, color: c.fg, height: 1.2)),
    );
  }
}

String announcementAudienceLabel(Map<String, dynamic> a) {
  final audience = (a['audience'] ?? '').toString();
  final targets = a['targetStaff'];
  if (audience == 'Individual Staff' && targets is List && targets.isNotEmpty) {
    return '${targets.length} staff member${targets.length == 1 ? '' : 's'}';
  }
  return audience.isEmpty ? 'All Staff' : audience;
}

String formatAnnouncementBytes(num bytes) {
  if (bytes >= 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  final kb = (bytes / 1024).round();
  return '${kb < 1 ? 1 : kb} KB';
}

/// Centered message with a Retry button, scrollable so pull-to-refresh still works.
Widget announcementMessageView({
  required IconData icon,
  required String title,
  required String message,
  VoidCallback? onRetry,
}) =>
    ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      children: [
        const SizedBox(height: 96),
        Center(
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppColors.textSecondary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 30, color: AppColors.textSecondary),
          ),
        ),
        const SizedBox(height: 16),
        Text(title, textAlign: TextAlign.center, style: AppTextStyles.headingSmall),
        const SizedBox(height: 4),
        Text(message, textAlign: TextAlign.center, style: AppTextStyles.bodySmall),
        if (onRetry != null) ...[
          const SizedBox(height: 16),
          Center(child: OutlinedButton(onPressed: onRetry, child: const Text('Retry'))),
        ],
      ],
    );

const announcementCardDecoration = BoxDecoration(
  color: AppColors.surface,
  borderRadius: BorderRadius.all(Radius.circular(16)),
  border: Border.fromBorderSide(BorderSide(color: Color(0xFFECEEF1))),
  boxShadow: kSoftCardShadow,
);

/// Confirm dialog shared by the list and the detail screen.
Future<bool?> confirmAnnouncementDelete(BuildContext context, String title) => showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete announcement'),
        content: Text('Delete "${title.isEmpty ? 'this announcement' : title}"? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error, foregroundColor: Colors.white),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
