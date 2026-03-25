/// Utilities for displaying attendance status with leave type (CL/SL etc.)
class AttendanceDisplayUtil {
  /// Converts leave type name to abbreviation for display.
  /// Input is trimmed and lowercased. CL = Casual Leave, SL = Sick Leave (e.g. "Sick Leave", "sick").
  static String leaveTypeToAbbreviation(String? leaveType) {
    if (leaveType == null || leaveType.isEmpty) return '';
    final normalized = leaveType.trim().toLowerCase();
    if (normalized == 'casual' || normalized.contains('casual')) return 'CL';
    // "Sick Leave", "sick leave", "sick" -> SL
    if (normalized == 'sick' ||
        normalized == 'sick leave' ||
        normalized.contains('sick')) {
      return 'SL';
    }
    if (normalized == 'earned' || normalized.contains('earned')) return 'EL';
    // Fallback: first two letters uppercase (e.g. "Other" -> "OT")
    final trimmed = leaveType.trim();
    if (trimmed.length >= 2) {
      return trimmed.substring(0, 2).toUpperCase();
    }
    return trimmed.toUpperCase();
  }

  /// Returns the display status for Daily Breakdown (Salary Overview, Month Salary Details)
  /// based on record's status, leaveType, compensationType, isPaidLeave.
  /// Shows: Paid Leave, Working Day, Week Off, Comp Off per user requirements.
  static String getDailyBreakdownStatus(Map<String, dynamic> record) {
    final recordStatus =
        (record['status'] as String? ?? '').trim().toLowerCase();
    final leaveType =
        (record['leaveType'] as String? ?? '').trim().toLowerCase();
    final compensationType =
        (record['compensationType'] as String? ?? '').trim().toLowerCase();
    final isPaidLeave = record['isPaidLeave'] == true;

    if (recordStatus == 'present' || recordStatus == 'approved') {
      final isHalfDay =
          recordStatus == 'half day' || leaveType == 'half day';
      if (isHalfDay) return 'Half Day';
      return 'Working Day';
    }
    if (recordStatus == 'on leave') {
      if (compensationType == 'compoff' || leaveType == 'comp off') {
        return 'Comp Off';
      }
      if (compensationType == 'weekoff' || leaveType == 'week off') {
        return 'Week Off';
      }
      if (isPaidLeave) return 'Paid Leave';
      return 'On Leave';
    }
    if (recordStatus == 'absent' || recordStatus == 'rejected') {
      return 'Absent';
    }
    if (recordStatus == 'pending') return 'Pending';
    return 'Not Marked';
  }

  /// Returns display string for attendance history card.
  /// WF=Week Off, CF=Comp Off, PL=Paid Leave, HA=Half Day, Present, On Leave.
  static String getHistoryCardDisplayStatus(Map<String, dynamic> record) {
    final status =
        (record['status'] as String? ?? 'Present').toString().trim();
    final statusLower = status.toLowerCase();
    final leaveType =
        (record['leaveType'] as String? ?? '').toString().trim().toLowerCase();
    final compensationType =
        (record['compensationType'] as String? ?? '')
            .toString()
            .trim()
            .toLowerCase();
    final isPaidLeave = record['isPaidLeave'] == true;

    if (statusLower == 'present' || statusLower == 'approved') {
      return 'Present';
    }
    if (statusLower == 'half day') return 'HA';
    if (statusLower == 'on leave') {
      if (compensationType == 'compoff' || leaveType == 'comp off') {
        return 'CF';
      }
      if (compensationType == 'weekoff' || leaveType == 'week off') {
        return 'WF';
      }
      if (isPaidLeave) return 'PL';
      return 'On Leave';
    }
    if (statusLower == 'absent' || statusLower == 'rejected') return 'Absent';
    if (statusLower == 'pending') return 'Pending';
    return status;
  }

  /// Returns display string for attendance status.
  /// When status is Present (or Approved) and leaveType is set, appends (CL)/(SL) etc.
  /// For Half Day, appends session when provided (e.g. "Half Day (Session 1)").
  static String formatAttendanceDisplayStatus(
    String? status, [
    String? leaveType,
    String? session,
  ]) {
    final s = status ?? 'Present';
    if (s == 'Half Day' && session != null && session.isNotEmpty) {
      final sessionLabel = session == '1'
          ? 'Session 1'
          : (session == '2' ? 'Session 2' : session);
      return 'Half Day ($sessionLabel)';
    }
    final abbr = leaveTypeToAbbreviation(leaveType);
    if (abbr.isEmpty) return s;
    if (s == 'Present' || s == 'Approved') return 'Present ($abbr)';
    return s;
  }
}
