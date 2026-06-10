import '../models/holiday_model.dart';
import '../services/holiday_service.dart';

/// Resolves which calendar dates are non-working (holidays + weekly offs) so date
/// pickers in Request Leave / Request Permission can disable them.
///
/// Weekday numbering follows the backend (JS getDay): 0 = Sunday ... 6 = Saturday.
class HolidayOffConfig {
  /// Holiday calendar days as 'yyyy-MM-dd' keys.
  final Set<String> holidayKeys;

  /// 'standard' or 'oddEvenSaturday'.
  final String weeklyOffPattern;

  /// Weekly-off weekdays (0=Sun..6=Sat) for the 'standard' pattern.
  final Set<int> weeklyOffDays;

  const HolidayOffConfig({
    required this.holidayKeys,
    required this.weeklyOffPattern,
    required this.weeklyOffDays,
  });

  static const HolidayOffConfig empty = HolidayOffConfig(
    holidayKeys: <String>{},
    weeklyOffPattern: 'standard',
    weeklyOffDays: <int>{},
  );

  static String keyFor(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// JS getDay() value for a Dart [DateTime] (Dart: Mon=1..Sun=7 → JS: Sun=0..Sat=6).
  static int _jsDay(DateTime d) => d.weekday % 7;

  bool isHoliday(DateTime d) => holidayKeys.contains(keyFor(d));

  bool isWeeklyOff(DateTime d) {
    if (weeklyOffPattern == 'oddEvenSaturday') {
      final jsDay = _jsDay(d);
      if (jsDay == 0) return true; // Sunday always off
      if (jsDay == 6) return _isEvenOrdinalSaturday(d); // 2nd/4th/6th Saturday off
      return false;
    }
    return weeklyOffDays.contains(_jsDay(d));
  }

  bool isDisabled(DateTime d) => isHoliday(d) || isWeeklyOff(d);

  /// True if [d] is a Saturday whose ordinal in the month is even (2nd, 4th, 6th).
  bool _isEvenOrdinalSaturday(DateTime d) {
    int ordinal = 0;
    for (int day = 1; day <= d.day; day++) {
      if (DateTime(d.year, d.month, day).weekday == DateTime.saturday) ordinal++;
    }
    return ordinal % 2 == 0;
  }

  /// Returns the first selectable (non-disabled) date on or after [start], scanning
  /// up to [maxScan] days. Falls back to [start] if none found (keeps the picker usable).
  DateTime firstSelectableOnOrAfter(DateTime start, {int maxScan = 366}) {
    var candidate = DateTime(start.year, start.month, start.day);
    for (int i = 0; i < maxScan; i++) {
      if (!isDisabled(candidate)) return candidate;
      candidate = candidate.add(const Duration(days: 1));
    }
    return DateTime(start.year, start.month, start.day);
  }
}

/// Loads holidays (all configured years) + the weekly-off config and combines them
/// into a [HolidayOffConfig]. Returns [HolidayOffConfig.empty] on failure so callers
/// degrade gracefully (no dates disabled) rather than blocking the picker.
Future<HolidayOffConfig> loadHolidayOffConfig() async {
  final service = HolidayService();
  Set<String> holidayKeys = <String>{};
  String pattern = 'standard';
  Set<int> offDays = <int>{};

  try {
    final results = await Future.wait([
      service.getHolidays(limit: 1000),
      service.getWeekOffConfig(),
    ]);

    final holidayRes = results[0];
    if (holidayRes['success'] == true) {
      final list = holidayRes['data'];
      if (list is List<Holiday>) {
        holidayKeys = list.map((h) => HolidayOffConfig.keyFor(h.date)).toSet();
      }
    }

    final weekRes = results[1];
    if (weekRes['success'] == true) {
      pattern = (weekRes['weeklyOffPattern'] as String?) ?? 'standard';
      final days = weekRes['weeklyOffDays'];
      if (days is List) {
        offDays = days.whereType<int>().toSet();
      }
    }
  } catch (_) {
    return HolidayOffConfig.empty;
  }

  return HolidayOffConfig(
    holidayKeys: holidayKeys,
    weeklyOffPattern: pattern,
    weeklyOffDays: offDays,
  );
}
