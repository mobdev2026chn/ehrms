import 'package:intl/intl.dart';

/// Utilities for displaying dates in India IST / device local timezone.
/// API dates from MongoDB are stored in UTC; format them for display in local time.
class DateDisplayUtil {
  /// Converts [dateTime] to local timezone (IST when device is in India) and formats.
  /// Use for all task/timeline date displays to fix UTC vs IST mismatch.
  static String formatForDisplay(DateTime? dateTime, String pattern) {
    if (dateTime == null) return '—';
    final local = dateTime.isUtc ? dateTime.toLocal() : dateTime;
    return DateFormat(pattern).format(local);
  }

  /// Short time: "10:30 AM"
  static String formatTime(DateTime? dateTime) =>
      formatForDisplay(dateTime, 'h:mm a');

  /// Date + time: "06 Feb 2025, 10:30 AM"
  static String formatDateTime(DateTime? dateTime) =>
      formatForDisplay(dateTime, 'dd MMM yyyy, h:mm a');

  /// Full: "Thursday, 06 Feb 2025 at 10:30 AM"
  static String formatFull(DateTime? dateTime) =>
      formatForDisplay(dateTime, "EEEE, dd MMM yyyy 'at' h:mm a");

  /// Short date: "06 Feb 25"
  static String formatShortDate(DateTime? dateTime) =>
      formatForDisplay(dateTime, 'dd MMM yy');

  /// Date only: "06 Feb 2025"
  static String formatDateOnly(DateTime? dateTime) =>
      formatForDisplay(dateTime, 'dd MMM yyyy');

  /// Timeline style: "Feb 6, 10:30 AM"
  static String formatTimeline(DateTime? dateTime) =>
      formatForDisplay(dateTime, 'MMM d, h:mm a');
}
