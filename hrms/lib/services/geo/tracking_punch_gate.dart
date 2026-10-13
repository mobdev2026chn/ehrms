// Punch-in gate: a FIELD employee cannot punch in while their phone is set up in a
// way that is guaranteed to break tracking (GPS off, location not "Allow all the
// time", battery saver restricting the app). Alerts inform; this enforces — the one
// thing every employee must do daily is punch in, so the settings get fixed there.
//
// Deliberately NOT blocking: no internet (an offline punch is legitimate and points
// queue locally), precise-location off (minor), office staff (no tracking at all),
// and any error inside the gate itself (never brick attendance over a check).

import 'package:hrms/services/task_service.dart';

import 'tracking_health_service.dart';

class TrackingPunchGate {
  TrackingPunchGate._();

  /// Issues that must be fixed before a field employee may punch in; empty when
  /// the punch may proceed.
  static Future<List<TrackingIssue>> criticalIssuesForPunch() async {
    try {
      final fieldType = await TaskService().getStaffFieldType();
      if (!(fieldType ?? '').toLowerCase().contains('field')) return const [];
      final issues = await TrackingHealthService.detectIssues();
      return issues
          .where((i) => i.critical && i != TrackingIssue.noNetwork)
          .toList();
    } catch (_) {
      // Profile unreachable / detection failed: let the punch through.
      return const [];
    }
  }
}
