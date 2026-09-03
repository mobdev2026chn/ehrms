import 'package:intl/intl.dart';

/// A single break taken today, as returned by GET /api/breaks/today or /staff/attendance/break-status.
class BreakEntry {
  final String? id;
  final DateTime? startTime;
  final DateTime? endTime;
  final String? rawStartTime;
  final String? rawEndTime;
  final bool ongoing;
  final int durationSeconds;
  final int durationMin;

  const BreakEntry({
    this.id,
    this.startTime,
    this.endTime,
    this.rawStartTime,
    this.rawEndTime,
    this.ongoing = false,
    this.durationSeconds = 0,
    this.durationMin = 0,
  });

  static DateTime? _parseTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value.isUtc ? value.toLocal() : value;
    final s = value.toString().trim();
    if (s.isEmpty || s == 'null') return null;
    final dt = DateTime.tryParse(s);
    if (dt != null) return dt.toLocal();

    // Try parsing 12-hour or 24-hour time strings e.g. "11:57 AM", "11:57:00"
    final now = DateTime.now();
    for (final pattern in [
      'hh:mm a',
      'h:mm a',
      'hh:mma',
      'h:mma',
      'HH:mm:ss',
      'HH:mm',
      'H:mm',
    ]) {
      try {
        final d = DateFormat(pattern).parseLoose(s);
        return DateTime(now.year, now.month, now.day, d.hour, d.minute, d.second);
      } catch (_) {}
    }
    return null;
  }

  static int _asInt(dynamic value) {
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  factory BreakEntry.fromJson(Map<String, dynamic> json) {
    final rawS = (json['startTime'] ??
            json['startAt'] ??
            json['start_time'] ??
            json['start'] ??
            json['from'])
        ?.toString();
    final rawE = (json['endTime'] ??
            json['endAt'] ??
            json['end_time'] ??
            json['end'] ??
            json['to'])
        ?.toString();
    final parsedStart = _parseTime(rawS);
    final parsedEnd = _parseTime(rawE);
    final isOngoing = json['ongoing'] == true ||
        (parsedStart != null &&
            (rawE == null ||
                rawE.isEmpty ||
                rawE == 'null'));
    final dMin = _asInt(json['durationMin'] ??
        json['durationMinutes'] ??
        json['breakMin'] ??
        json['duration']);
    final dSec = _asInt(json['durationSeconds'] ??
        json['totalSeconds']);
    return BreakEntry(
      id: (json['id'] ?? json['_id'] ?? json['breakId'])?.toString(),
      startTime: parsedStart,
      endTime: parsedEnd,
      rawStartTime: rawS,
      rawEndTime: rawE,
      ongoing: isOngoing,
      durationSeconds: dSec != 0 ? dSec : (dMin * 60),
      durationMin: dMin != 0 ? dMin : (dSec > 0 ? (dSec / 60).round() : 0),
    );
  }
}

/// Daily break summary for the logged-in employee (GET /api/breaks/today).
///
/// Single source of truth for: today's break list (ascending), total break
/// time used, the allowed break quota and the remaining balance.
class BreakSummary {
  final List<BreakEntry> breaks;
  final int totalBreakSeconds;
  final int totalBreakMin;
  final int totalBreakCount;
  final bool policyEnabled;

  /// True only when the shift explicitly disabled breaks (server tri-state).
  /// Legacy shifts without a configured policy report `false` here, so the
  /// Start Break action stays available for them.
  final bool policyDisabled;

  /// True when breaks are enabled AND a real allowance (allowedMinutes > 0) was
  /// configured for the shift. False means "enabled but not configured" — the app
  /// blocks starting a break and asks the employee to contact HR. Defaults to
  /// `true` so older backends that omit the flag are never falsely blocked.
  final bool policyConfigured;
  final bool isUnlimited;
  final int allowedMinutes;

  /// Allowed break quota in seconds. `null` when breaks are unlimited.
  final int? allowedSeconds;

  /// Minutes of break left for today. `null` when breaks are unlimited
  /// (policy disabled or no quota configured).
  final int? remainingMin;

  /// Seconds of break left for today (second precision). `null` when unlimited.
  final int? remainingSeconds;

  final bool hasActiveBreak;

  /// Raw allowance from the shift template (before the default-60-min fallback).
  /// 0 when not configured. Used to differentiate "disabled with quota" from
  /// "disabled with no quota" so the correct message is shown.
  final int configuredAllowedMinutes;

  /// True when the shift explicitly disabled breaks but a quota > 0 was configured.
  /// In this state breaks are ALLOWED and all break time is added to Fine.
  final bool policyIsDisabledWithQuota;

  /// Canonical, server-authored policy notice (exact tooltip wording) for the
  /// current break state — set for the disabled / no-allowance scenarios where the
  /// break time is processed with Fine. Empty/null when breaks are normally
  /// configured. Breaks are ALWAYS allowed; this is informational only.
  final String? breakNotice;

  const BreakSummary({
    this.breaks = const [],
    this.totalBreakSeconds = 0,
    this.totalBreakMin = 0,
    this.totalBreakCount = 0,
    this.policyEnabled = false,
    this.policyDisabled = false,
    this.policyConfigured = true,
    this.isUnlimited = true,
    this.allowedMinutes = 0,
    this.allowedSeconds,
    this.remainingMin,
    this.remainingSeconds,
    this.hasActiveBreak = false,
    this.configuredAllowedMinutes = 0,
    this.policyIsDisabledWithQuota = false,
    this.breakNotice,
  });

  bool get isEmpty => breaks.isEmpty && totalBreakSeconds == 0;

  /// Total seconds of COMPLETED breaks today (excludes any ongoing break).
  /// Used as the running base for the live "taken today" counter on the break
  /// status card, where the ongoing break's elapsed is added on top each tick.
  int get completedBreakSeconds => breaks
      .where((b) => !b.ongoing)
      .fold(0, (sum, b) => sum + b.durationSeconds);

  static int _asInt(dynamic value) {
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  factory BreakSummary.fromJson(Map<String, dynamic> json) {
    final rawBreaks = json['breaks'] ?? json['sessions'];
    final list = <BreakEntry>[];
    if (rawBreaks is List) {
      for (final item in rawBreaks) {
        if (item is Map) {
          list.add(BreakEntry.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }
    if (json['activeBreak'] is Map) {
      final ab = json['activeBreak'] as Map;
      final st = BreakEntry._parseTime(ab['startTime'] ?? ab['startAt']);
      if (st != null && !list.any((b) => b.ongoing)) {
        list.add(BreakEntry(
          id: (ab['id'] ?? ab['_id'] ?? ab['breakId'])?.toString(),
          startTime: st,
          ongoing: true,
        ));
      }
    }
    // Defensive: keep ascending by startTime even if the server order changes.
    list.sort((a, b) {
      final at = a.startTime;
      final bt = b.startTime;
      if (at == null && bt == null) return 0;
      if (at == null) return -1;
      if (bt == null) return 1;
      return at.compareTo(bt);
    });
    final remainingRaw = json['remainingMin'] ?? json['remainingMinutes'];
    final remainingSecRaw = json['remainingSeconds'];
    final allowedSecRaw = json['allowedSeconds'];
    final usedMin = _asInt(json['totalBreakMin'] ?? json['usedMinutes'] ?? json['totalBreakMinutes']);
    final totalSeconds = _asInt(json['totalBreakSeconds']) != 0
        ? _asInt(json['totalBreakSeconds'])
        : (usedMin * 60);
    return BreakSummary(
      breaks: list,
      totalBreakSeconds: totalSeconds,
      totalBreakMin: usedMin,
      totalBreakCount: _asInt(json['totalBreakCount']) != 0 ? _asInt(json['totalBreakCount']) : list.length,
      policyEnabled: json['policyEnabled'] == true || json['breakTemplateAssigned'] == true,
      policyDisabled: json['policyDisabled'] == true,
      // Default to configured=true when the backend omits the flag (older builds)
      // so the break flow is never blocked on a missing field.
      policyConfigured: json.containsKey('policyConfigured')
          ? json['policyConfigured'] == true
          : true,
      isUnlimited: json['isUnlimited'] == true || (_asInt(json['allowedMinutes']) == 0 && json['breakTemplateAssigned'] != true),
      allowedMinutes: _asInt(json['allowedMinutes']),
      allowedSeconds: allowedSecRaw == null ? null : _asInt(allowedSecRaw),
      remainingMin: remainingRaw == null ? null : _asInt(remainingRaw),
      remainingSeconds: remainingSecRaw == null
          ? (remainingRaw != null ? _asInt(remainingRaw) * 60 : null)
          : _asInt(remainingSecRaw),
      hasActiveBreak: json['hasActiveBreak'] == true ||
          json['isOnBreak'] == true ||
          list.any((b) => b.ongoing),
      configuredAllowedMinutes: _asInt(json['configuredAllowedMinutes'] ?? json['allowedMinutes']),
      policyIsDisabledWithQuota: json['policyIsDisabledWithQuota'] == true,
      breakNotice: (json['breakNotice'] is String &&
              (json['breakNotice'] as String).trim().isNotEmpty)
          ? json['breakNotice'] as String
          : null,
    );
  }

  /// Formats a second count as "1h 05m 30s" / "5m 30s" / "45s".
  static String formatDuration(int seconds) {
    if (seconds <= 0) return '0s';
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) {
      return '${h}h ${m.toString().padLeft(2, '0')}m ${s.toString().padLeft(2, '0')}s';
    }
    if (m > 0) return '${m}m ${s.toString().padLeft(2, '0')}s';
    return '${s}s';
  }
}
