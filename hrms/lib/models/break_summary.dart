/// A single break taken today, as returned by GET /api/breaks/today.
class BreakEntry {
  final String? id;
  final DateTime? startTime;
  final DateTime? endTime;
  final bool ongoing;
  final int durationSeconds;
  final int durationMin;

  const BreakEntry({
    this.id,
    this.startTime,
    this.endTime,
    this.ongoing = false,
    this.durationSeconds = 0,
    this.durationMin = 0,
  });

  static DateTime? _parseTime(dynamic value) {
    if (value == null) return null;
    final s = value.toString().trim();
    if (s.isEmpty) return null;
    final dt = DateTime.tryParse(s);
    return dt?.toLocal();
  }

  static int _asInt(dynamic value) {
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  factory BreakEntry.fromJson(Map<String, dynamic> json) {
    return BreakEntry(
      id: json['id']?.toString(),
      startTime: _parseTime(json['startTime']),
      endTime: _parseTime(json['endTime']),
      ongoing: json['ongoing'] == true,
      durationSeconds: _asInt(json['durationSeconds']),
      durationMin: _asInt(json['durationMin']),
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

  const BreakSummary({
    this.breaks = const [],
    this.totalBreakSeconds = 0,
    this.totalBreakMin = 0,
    this.totalBreakCount = 0,
    this.policyEnabled = false,
    this.policyDisabled = false,
    this.isUnlimited = true,
    this.allowedMinutes = 0,
    this.allowedSeconds,
    this.remainingMin,
    this.remainingSeconds,
    this.hasActiveBreak = false,
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
    final rawBreaks = json['breaks'];
    final list = <BreakEntry>[];
    if (rawBreaks is List) {
      for (final item in rawBreaks) {
        if (item is Map) {
          list.add(BreakEntry.fromJson(Map<String, dynamic>.from(item)));
        }
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
    final remainingRaw = json['remainingMin'];
    final remainingSecRaw = json['remainingSeconds'];
    final allowedSecRaw = json['allowedSeconds'];
    return BreakSummary(
      breaks: list,
      totalBreakSeconds: _asInt(json['totalBreakSeconds']),
      totalBreakMin: _asInt(json['totalBreakMin']),
      totalBreakCount: _asInt(json['totalBreakCount']),
      policyEnabled: json['policyEnabled'] == true,
      policyDisabled: json['policyDisabled'] == true,
      isUnlimited: json['isUnlimited'] == true,
      allowedMinutes: _asInt(json['allowedMinutes']),
      allowedSeconds: allowedSecRaw == null ? null : _asInt(allowedSecRaw),
      remainingMin: remainingRaw == null ? null : _asInt(remainingRaw),
      remainingSeconds: remainingSecRaw == null
          ? null
          : _asInt(remainingSecRaw),
      hasActiveBreak: json['hasActiveBreak'] == true,
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
