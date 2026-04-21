import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import '../../config/app_colors.dart';
import '../../widgets/walking_turtle_emoji.dart';
import '../../config/constants.dart';
import '../../utils/break_datetime_util.dart';
import '../../utils/error_message_utils.dart';
import '../../utils/punch_flow_log.dart';
import '../../utils/snackbar_utils.dart';
import '../../widgets/attendance_success_overlay.dart';
import '../../widgets/notification_reaction_overlay.dart';
import '../../widgets/bottom_navigation_bar.dart';
import '../../services/attendance_service.dart';
import '../../services/break_service.dart';
import '../../services/attendance_template_store.dart';
import '../../services/auth_service.dart';
import '../../services/request_service.dart';
import '../../services/geo/address_resolution_service.dart';
import '../../services/geo/accurate_location_helper.dart';
import '../../services/geo/location_service.dart';
import '../../services/presence_tracking_service.dart';
import '../../services/salary_service.dart';
import '../../bloc/attendance/attendance_bloc.dart';
import '../../utils/face_detection_helper.dart';
import '../../utils/attendance_template_util.dart';
import '../../utils/absent_alert_helper.dart';
import '../../utils/fine_calculation_util.dart';
import '../../utils/rotational_shift_util.dart';
import 'home_dashboard_screen.dart';
import '../attendance/attendance_screen.dart';
import '../attendance/selfie_camera_screen.dart';
import '../holidays/holidays_screen.dart';
import '../requests/my_requests_screen.dart';
import '../salary/salary_overview_screen.dart' hide debugPrint;

typedef _ResolvedLocation = ({
  Position? position,
  String address,
  String? area,
  String? city,
  String? pincode,
});

class DashboardScreen extends StatefulWidget {
  /// 0=Dashboard, 1=Requests, 2=Salary overview (IndexedStack only; not in bottom bar), 3=Holidays, 4=Attendance, 5=punch flow, 6=break flow.
  /// Tab 2 opens from quick actions when [staffData.salaryDetailsAccessEnabled] is true (staffs collection / profile).
  final int? initialIndex;
  const DashboardScreen({super.key, this.initialIndex});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with WidgetsBindingObserver {
  static const String _dashboardLocationPromptLastShownKey =
      'dashboard_location_prompt_last_shown_ms';
  late int _currentIndex;
  int _requestsSubTabIndex = 0;
  int _attendanceSubTabIndex = 0;
  bool _isSubmittingFromFingerprint = false;
  bool _isPunchActionInProgress = false;
  bool _isBreakActionInProgress = false;

  /// Starts false so the bottom bar matches the today card (no stale prefs via null).
  bool _isPunchedInToday = false;
  bool _isPunchCompletedToday = false;

  /// From company shift [breakPolicy.enabled] for today's [appliedShiftId] (tea-break icon).
  bool _showBreakNavForShiftPolicy = true;
  Map<String, dynamic>? _activeBreak;
  bool _openBreakAfterBuild = false;
  Map<String, dynamic>? _fineCalculation;

  /// Staffs collection `salaryDetailsAccessEnabled` on profile [staffData] — must be explicitly true for Salary Overview quick action (tab 2).
  bool _hasSalaryOverviewAccess = false;

  /// When true, [initialIndex] was 2; apply tab 2 only after access is confirmed.
  bool _deferSalaryInitialTab = false;

  static void _logSalaryAccessTest(String message) {
    if (kDebugMode) {
      debugPrint('[SalaryAccess][TEST] $message');
    }
  }

  final AttendanceService _attendanceService = AttendanceService();
  final BreakService _breakService = BreakService();
  final AuthService _authService = AuthService();
  final RequestService _requestService = RequestService();
  final ValueNotifier<int> _dashboardRefreshTrigger = ValueNotifier<int>(0);

  static bool _hasPunchValue(dynamic value) =>
      value != null && value.toString().trim().isNotEmpty;

  static Map<String, dynamic>? _extractAttendanceRecord(
    Map<String, dynamic>? data,
  ) {
    if (data == null) return null;
    final nested = data['data'];
    if (nested is Map<String, dynamic>) return nested;
    return data;
  }

  static bool _isAttendancePunchedIn(Map<String, dynamic>? attendance) {
    return isAwaitingPunchOutFromTodayAttendance(attendance);
  }

  static bool _isAttendanceCompleted(Map<String, dynamic>? attendance) {
    final hasIn = _hasPunchValue(attendance?['punchIn']);
    final hasOut = _hasPunchValue(attendance?['punchOut']);
    return hasIn && hasOut;
  }

  void _setPunchActionInProgress(bool value) {
    if (!mounted || _isPunchActionInProgress == value) return;
    setState(() => _isPunchActionInProgress = value);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final rawInitial = widget.initialIndex ?? 0;
    if (rawInitial == 2) {
      _deferSalaryInitialTab = true;
      _currentIndex = _normalizeTabIndex(0);
    } else {
      _currentIndex = _normalizeTabIndex(rawInitial);
    }
    _openBreakAfterBuild = widget.initialIndex == 6;
    unawaited(_refreshSalaryOverviewAccess());
    _attendanceService.clearCachesForRefresh();
    _fetchPunchStatusForNavBar();
    _fetchActiveBreak();
    unawaited(_fetchFineCalculation());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showLocationCardsAfterDelay();
      if (_openBreakAfterBuild) {
        _openBreakAfterBuild = false;
        _openRequestedBreakFlow();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _dashboardRefreshTrigger.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_fetchPunchStatusForNavBar());
    }
  }

  Future<void> _showLocationCardsAfterDelay() async {
    await Future.delayed(const Duration(seconds: 4));
    if (!mounted) return;
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now().millisecondsSinceEpoch;
    final lastShownMs = prefs.getInt(_dashboardLocationPromptLastShownKey) ?? 0;
    final throttleDurationMs = const Duration(hours: 24).inMilliseconds;
    final shouldShowPrompt = (now - lastShownMs) >= throttleDurationMs;
    if (!shouldShowPrompt) return;
    await prefs.setInt(_dashboardLocationPromptLastShownKey, now);
    await LocationService.ensureAppLocationAccess(context);
  }

  /// When GET /today fails (throttle, offline), keep nav label aligned with last known prefs
  /// instead of forcing "Punch In" and clearing cache.
  Future<void> _applyPunchNavFromPrefsIfAny() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final punchIn = prefs.getString('today_punch_in') ?? '';
      final punchOut = prefs.getString('today_punch_out') ?? '';
      final today = DateTime.now();
      final todayKey = '${today.year}-${today.month}-${today.day}';
      final cacheDay = prefs.getString('today_punch_date');
      final isIn =
          cacheDay == todayKey &&
          isAwaitingPunchOutFromCachedPunchStrings(
            punchIn: punchIn,
            punchOut: punchOut,
          );
      final isCompleted =
          cacheDay == todayKey &&
          hasParsablePunchDateTime(punchIn) &&
          hasParsablePunchDateTime(punchOut);
      if (mounted) {
        setState(() {
          _isPunchedInToday = isIn;
          _isPunchCompletedToday = isCompleted;
        });
      }
    } catch (_) {}
  }

  Future<void> _optimisticPunchInPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final today = DateTime.now();
      final todayKey = '${today.year}-${today.month}-${today.day}';
      await prefs.setString('today_punch_date', todayKey);
      await prefs.setString('today_punch_in', today.toIso8601String());
      await prefs.setString('today_punch_out', '');
    } catch (_) {}
  }

  Future<void> _optimisticPunchOutPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final today = DateTime.now();
      final todayKey = '${today.year}-${today.month}-${today.day}';
      await prefs.setString('today_punch_date', todayKey);
      final existingIn = prefs.getString('today_punch_in') ?? '';
      if (existingIn.trim().isEmpty) {
        await prefs.setString('today_punch_in', today.toIso8601String());
      }
      await prefs.setString('today_punch_out', today.toIso8601String());
    } catch (_) {}
  }

  Future<void> _fetchPunchStatusForNavBar() async {
    final res = await _attendanceService.getTodayAttendance(forceRefresh: true);
    if (!mounted) return;
    final data = res['data'] as Map<String, dynamic>?;
    if (res['success'] == true && data != null) {
      // Same merge as home dashboard today card (nested `data` + root flags).
      final attendance =
          flattenTodayAttendancePayload(data) ??
          _extractAttendanceRecord(data) ??
          data;
      // Some server responses can be "success" but still have no attendance document
      // (timezone/date mismatch). In that case, don't wipe a known punch-in state:
      // fall back to today's cached punch strings in prefs.
      final hasPunchSignal =
          (attendance['checkedIn'] is bool) ||
          attendance['hasPunchIn'] == true ||
          attendance['hasPunchOut'] == true ||
          hasParsablePunchDateTime(attendance['punchIn']) ||
          hasParsablePunchDateTime(attendance['punchOut']);
      if (!hasPunchSignal) {
        if (kDebugMode) {
          debugPrint(
            '[Dashboard] _fetchPunchStatusForNavBar: success but no punch fields; using prefs fallback',
          );
        }
        await _applyPunchNavFromPrefsIfAny();
        await PresenceTrackingService().ensureTrackingIfPunchedIn(
          _isPunchedInToday,
        );
        return;
      }

      final isPunchedIn = _isAttendancePunchedIn(attendance);
      final hasIn = _hasPunchValue(attendance['punchIn']);
      final hasOut = _hasPunchValue(attendance['punchOut']);
      // Always start from visible; only hide when current shift explicitly disables breaks.
      // This avoids stale false state when appliedShiftId is temporarily unavailable.
      var showBreakNav = true;
      var breakPolicyLogSource = 'default-visible';
      final appliedId = attendance['appliedShiftId'];
      String? resolvedShiftName;
      bool? resolvedShiftBreakEnabled;
      try {
        // Full shift rows (incl. breakPolicy) live on today API root [businessShifts], not in SharedPrefs template.
        Map<String, dynamic>? companyDoc =
            companyDocForBreakPolicyFromTodayApiRoot(data);
        if (companyDoc == null) {
          final stored = await AttendanceTemplateStore.loadTemplateDetails();
          final rawT = stored?['template'];
          if (rawT is Map<String, dynamic>) {
            companyDoc = rawT;
          } else if (rawT is Map) {
            companyDoc = Map<String, dynamic>.from(rawT);
          }
        }
        if (companyDoc != null && companyDoc.isNotEmpty && appliedId != null) {
          final shiftRow = shiftRowForAppliedShiftId(
            companyDoc: companyDoc,
            appliedShiftId: appliedId,
          );
          resolvedShiftName = shiftRow?['name']?.toString();
          resolvedShiftBreakEnabled = breakPolicyEnabledForShiftRow(shiftRow);
          showBreakNav = shouldShowBreakNavForAppliedShift(
            companyDoc: companyDoc,
            appliedShiftId: appliedId,
          );
          breakPolicyLogSource = 'appliedShiftId';
        } else {
          // Before first punch-in there may be no attendance row / appliedShiftId.
          // Fallback to resolved template breakPolicy from today payload.
          final templateBreakEnabled = readBreakPolicyEnabledFromMap(
            data['template'] is Map
                ? (data['template'] as Map)['breakPolicy']
                : null,
          );
          if (templateBreakEnabled != null) {
            showBreakNav = templateBreakEnabled;
            final t = data['template'];
            if (t is Map) {
              resolvedShiftName = t['name']?.toString();
            }
            resolvedShiftBreakEnabled = templateBreakEnabled;
            breakPolicyLogSource = 'today.template.breakPolicy';
          } else {
            breakPolicyLogSource = 'no-appliedShiftId-no-templateBreakPolicy';
          }
        }
      } catch (_) {}
      if (kDebugMode) {
        final rawIn = attendance['punchIn']?.toString();
        final rawOut = attendance['punchOut']?.toString();
        final checkedIn = attendance['checkedIn'];
        final hasInFlag = attendance['hasPunchIn'];
        final hasOutFlag = attendance['hasPunchOut'];
        final awaiting = isAwaitingPunchOutFromTodayAttendance(attendance);
        final label = awaiting ? 'Punch Out' : 'Punch In';
        debugPrint(
          '[Dashboard] _fetchPunchStatusForNavBar: '
          'hasIn=$hasIn hasOut=$hasOut => isPunchedInToday=$isPunchedIn',
        );
        debugPrint(
          '[PunchButton][Dashboard][today-from-api] '
          'checkedIn=$checkedIn hasPunchIn=$hasInFlag hasPunchOut=$hasOutFlag '
          'punchIn="$rawIn" punchOut="$rawOut" awaitingPunchOut=$awaiting => label="$label"',
        );
        debugPrint(
          '[BreakPolicy][Dashboard] appliedShiftId=${appliedId?.toString() ?? 'null'} '
          'shift="${resolvedShiftName ?? 'unknown'}" breakEnabled=${resolvedShiftBreakEnabled?.toString() ?? 'unknown'} '
          'source=$breakPolicyLogSource showBreakNav=$showBreakNav',
        );
      }
      setState(() {
        _isPunchedInToday = isPunchedIn;
        _isPunchCompletedToday = hasIn && hasOut;
        _showBreakNavForShiftPolicy = showBreakNav;
      });
      await _savePunchStateToPrefs(attendance);
      if (isPunchedIn) {
        PresenceTrackingService().recordAppOpened();
      }
      await PresenceTrackingService().ensureTrackingIfPunchedIn(isPunchedIn);
    } else {
      if (kDebugMode) {
        debugPrint(
          '[Dashboard] _fetchPunchStatusForNavBar: fetch failed '
          '${res['message'] ?? ''} — keeping prefs-backed punch nav state',
        );
      }
      await _applyPunchNavFromPrefsIfAny();
      await PresenceTrackingService().ensureTrackingIfPunchedIn(
        _isPunchedInToday,
      );
    }
  }

  Future<void> _savePunchStateToPrefs(Map<String, dynamic> attendance) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final today = DateTime.now();
      final todayKey = '${today.year}-${today.month}-${today.day}';
      final punchIn = attendance['punchIn']?.toString().trim() ?? '';
      final punchOut = attendance['punchOut']?.toString().trim() ?? '';
      // Only overwrite cached times when server actually returned valid punch timestamps.
      // This prevents a "success" response with null attendance from wiping a real punch-in.
      await prefs.setString('today_punch_date', todayKey);
      if (hasParsablePunchDateTime(punchIn)) {
        await prefs.setString('today_punch_in', punchIn);
      }
      if (hasParsablePunchDateTime(punchOut)) {
        await prefs.setString('today_punch_out', punchOut);
      }
    } catch (_) {}
  }

  Future<void> _fetchFineCalculation() async {
    try {
      final result = await _attendanceService.getFineCalculation();
      if (!mounted) return;
      if (result['success'] == true && result['data'] is Map<String, dynamic>) {
        setState(
          () => _fineCalculation = result['data'] as Map<String, dynamic>,
        );
      } else {
        setState(() => _fineCalculation = null);
      }
    } catch (_) {
      if (mounted) setState(() => _fineCalculation = null);
    }
  }

  Map<String, String> _resolveFineLogForAction(String actionApplyToType) {
    try {
      final fc = _fineCalculation;
      final rulesRaw = fc?['fineRules'];
      final rules = rulesRaw is List ? rulesRaw.cast<Map>() : const <Map>[];

      final rawCalcType =
          fc?['calculationType'] ?? fc?['calculationMethod'] ?? 'shiftBased';
      final normalizedCalcType = rawCalcType == 'fixedPerHour'
          ? 'fixedPerHour'
          : 'shiftBased';

      final match = rules.firstWhere((r) {
        final applyTo = r['applyTo'];
        if (applyTo == null) return true;
        final s = applyTo.toString();
        return s == actionApplyToType || s == 'both';
      }, orElse: () => <String, dynamic>{});

      if (match.isNotEmpty && match['type'] != null) {
        return {
          'fineType': 'ruleBased',
          'ruleType': match['type'].toString(),
          'ruleApplyTo': match['applyTo']?.toString() ?? 'both',
        };
      }

      return {
        'fineType': normalizedCalcType,
        'ruleType': 'default',
        'ruleApplyTo': 'none',
      };
    } catch (_) {
      return {
        'fineType': 'shiftBased',
        'ruleType': 'default',
        'ruleApplyTo': 'none',
      };
    }
  }

  bool _hasFineRules() {
    final fc = _fineCalculation;
    final rulesRaw = fc?['fineRules'];
    return rulesRaw is List && rulesRaw.isNotEmpty;
  }

  Map<String, dynamic>? _matchFineRuleForAction(String actionApplyToType) {
    if (!_hasFineRules()) return null;
    final fc = _fineCalculation;
    final rulesRaw = fc?['fineRules'];
    if (rulesRaw is! List) return null;
    final rules = rulesRaw.cast<Map>();
    final match = rules.cast<Map>().cast<dynamic>().firstWhere((dynamic r) {
      if (r is! Map) return false;
      final applyTo = r['applyTo'];
      if (applyTo == null) return true;
      final s = applyTo.toString().trim();
      if (s.isEmpty) return true;
      return s == actionApplyToType || s == 'both';
    }, orElse: () => <String, dynamic>{});
    if (match is Map<String, dynamic> && match.isNotEmpty) {
      return match;
    }
    return null;
  }

  double _computeFineFromRule({
    required Map<String, dynamic> rule,
    required int minutes,
    required double netPerDaySalary,
    required double shiftHours,
  }) {
    final type = (rule['type']?.toString() ?? '').toLowerCase();
    if (minutes <= 0) return 0.0;

    debugPrint(
      '[Fine] _computeFineFromRule: type=$type, minutes=$minutes, netPerDaySalary=$netPerDaySalary, shiftHours=$shiftHours',
    );

    if (type == 'custom') {
      final customAmount = (rule['customAmount'] as num?)?.toDouble() ?? 0.0;
      final unit = (rule['customAmountUnit']?.toString() ?? 'perHour')
          .toLowerCase();
      if (unit == 'perminute') return customAmount * minutes;
      if (unit == 'perhour') return customAmount * (minutes / 60.0);
      if (unit == 'fixed') return customAmount;
      // Default to perHour when unit is missing/unrecognized.
      return customAmount * (minutes / 60.0);
    }

    if (type == 'halfday') {
      return (netPerDaySalary / 2.0);
    }
    if (type == 'fullday') {
      return netPerDaySalary;
    }

    // Salary-multiple style rules (1xSalary / 2xSalary / 3xSalary).
    int multiplier = 1;
    if (type == '2xsalary') multiplier = 2;
    if (type == '3xsalary') multiplier = 3;

    final hourlyRate = (shiftHours > 0) ? (netPerDaySalary / shiftHours) : 0.0;
    final hours = minutes / 60.0;
    // Example: 1xSalary => hourlyRate * (minutes/60)
    final amount = (hourlyRate * hours * multiplier);
    debugPrint(
      '[Fine] Rule Result: hourlyRate=$hourlyRate, hours=$hours, multiplier=$multiplier => amount=$amount',
    );
    return amount;
  }

  Future<double?> _loadPerDaySalaryFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final grossDirect = prefs.getDouble(kAppGrossPerDaySalaryPrefsKey);
      if (grossDirect != null && grossDirect > 0) return grossDirect;
      final grossAsString = prefs.getString(kAppGrossPerDaySalaryPrefsKey);
      final grossParsed = grossAsString == null
          ? null
          : double.tryParse(grossAsString);
      if (grossParsed != null && grossParsed > 0) return grossParsed;
      final direct = prefs.getDouble(kAppNetPerDaySalaryPrefsKey);
      if (direct != null && direct > 0) return direct;
      final asString = prefs.getString(kAppNetPerDaySalaryPrefsKey);
      final parsed = asString == null ? null : double.tryParse(asString);
      if (parsed != null && parsed > 0) return parsed;
      final legacyDirect = prefs.getDouble(kAppLegacyPerDaySalaryPrefsKey);
      if (legacyDirect != null && legacyDirect > 0) return legacyDirect;
    } catch (_) {}
    return null;
  }

  String _buildLateAlertMessage({
    required String baseMessage,
    required int lateMinutes,
    required double fineAmount,
  }) {
    return '$baseMessage\n'
        'LateMinutes: $lateMinutes\n'
        'Fine: ₹${fineAmount.toStringAsFixed(2)}';
  }

  String _buildEarlyAlertMessage({
    required String baseMessage,
    required int earlyMinutes,
    required double fineAmount,
  }) {
    return '$baseMessage\n'
        'EarlyMinutes: $earlyMinutes\n'
        'Fine: ₹${fineAmount.toStringAsFixed(2)}';
  }

  Future<Map<String, int>> _getPermissionAdjustment({
    required DateTime day,
    required int lateMinutes,
    required int earlyMinutes,
    required bool isOpenShift,
    required bool isCheckout,
    String? applyTo,
  }) async {
    try {
      final reqRes = await _requestService.getPermissionRequests(
        status: 'Approved',
        month: day.month,
        year: day.year,
      );
      final balRes = await _requestService.getPermissionBalance(
        month: day.month,
        year: day.year,
      );
      final remainingFromApi =
          ((balRes['data']?['remainingMinutes'] as num?)?.toInt() ?? 0).clamp(
            0,
            1000000,
          );
      final data = reqRes['data'];
      final listRaw = (data is Map) ? data['permissions'] : data;
      int approvedLate = 0;
      int approvedEarly = 0;
      if (listRaw is List) {
        for (final item in listRaw) {
          if (item is! Map) continue;
          final dateRaw = item['date'];
          if (dateRaw == null) continue;
          DateTime? d;
          try {
            d = DateTime.parse(dateRaw.toString()).toLocal();
          } catch (_) {
            d = null;
          }
          if (d == null ||
              d.year != day.year ||
              d.month != day.month ||
              d.day != day.day) {
            continue;
          }
          final mins = ((item['requestedMinutes'] as num?)?.toInt() ?? 0).clamp(
            0,
            1000000,
          );
          if (mins <= 0) continue;
          final type = (item['type'] ?? 'both').toString().trim();
          if (type == 'lateArrival') {
            approvedLate += mins;
          } else if (type == 'earlyExit') {
            approvedEarly += mins;
          } else {
            approvedLate += mins;
            approvedEarly += mins;
          }
        }
      }

      final applyToLower = (applyTo ?? 'both').toLowerCase().trim();
      if (applyToLower == 'latearrival') {
        approvedEarly = 0;
      } else if (applyToLower == 'earlyexit') {
        approvedLate = 0;
      }
      if (isOpenShift) {
        approvedLate = 0;
        if (!isCheckout) approvedEarly = 0;
      }

      final eligibleLate = lateMinutes.clamp(0, approvedLate);
      final eligibleEarly = earlyMinutes.clamp(0, approvedEarly);
      final totalEligible = (eligibleLate + eligibleEarly).clamp(0, 1000000);
      final totalConsume = totalEligible.clamp(0, remainingFromApi);
      var consumeLate = eligibleLate.clamp(0, totalConsume);
      final consumeEarly = (totalConsume - consumeLate).clamp(0, eligibleEarly);
      return {'consumeLate': consumeLate, 'consumeEarly': consumeEarly};
    } catch (_) {
      return {'consumeLate': 0, 'consumeEarly': 0};
    }
  }

  Future<Map<String, dynamic>> _buildFinePayloadForPunch({
    required bool isCheckedIn,
    required Map<String, dynamic>? attendanceData,
    required Map<String, dynamic>? halfDayLeave,
    required Map<String, dynamic> tmpl,
  }) async {
    // Always compute with the latest backend fine config.
    await _fetchFineCalculation();
    int lateMinutes = 0;
    int earlyMinutes = 0;
    double fineAmount = 0;
    double shiftHoursForFinalFine = 0;
    final now = DateTime.now();
    final netPerDaySalary = await _loadPerDaySalaryFromPrefs();
    final sessionTimings = _getWorkingSessionTimings(
      attendanceData,
      halfDayLeave,
      tmpl,
    );

    if (!isCheckedIn) {
      if (_templateIsOpenShift(tmpl)) {
        lateMinutes = 0;
        fineAmount = 0;
        shiftHoursForFinalFine = _templateOpenRequiredHours(tmpl);
      } else {
        final shiftStartStr =
            sessionTimings?['startTime'] ?? _getShiftStartTimeFromDb(tmpl);
        if (shiftStartStr != null && shiftStartStr.isNotEmpty) {
          try {
            final parts = shiftStartStr.split(':').map(int.parse).toList();
            final gracePeriod = _getGracePeriodMinutesForLateCheckIn(
              attendanceData,
              halfDayLeave,
              tmpl,
            );
            final shiftStartOnly = DateTime(
              now.year,
              now.month,
              now.day,
              parts[0],
              parts.length > 1 ? parts[1] : 0,
            );
            final graceEnd = shiftStartOnly.add(Duration(minutes: gracePeriod));
            if (now.isAfter(graceEnd)) {
              final shiftEndForFine =
                  sessionTimings?['endTime'] ??
                  _getShiftEndTimeFromDb(tmpl) ??
                  '18:30';
              final fineResult = calculateFine(
                punchInTime: now,
                attendanceDate: DateTime(now.year, now.month, now.day),
                shiftTiming: ShiftTiming(
                  name: 'Current Shift',
                  startTime: shiftStartStr,
                  endTime: shiftEndForFine,
                  graceTime: GraceTime(value: gracePeriod, unit: 'minutes'),
                ),
                fineSettings: FineSettings(
                  enabled: true,
                  graceTimeMinutes: gracePeriod,
                  calculationType: 'shiftBased',
                ),
                dailySalary: netPerDaySalary,
              );
              lateMinutes = fineResult.lateMinutes;
              fineAmount = fineResult.fineAmount;
              shiftHoursForFinalFine = calculateShiftHours(
                shiftStartStr,
                shiftEndForFine,
              );
              final hasRules = _hasFineRules();
              final lateRule = _matchFineRuleForAction('lateArrival');
              if (hasRules) {
                if (lateRule == null) {
                  fineAmount = 0.0;
                } else {
                  fineAmount = _computeFineFromRule(
                    rule: lateRule,
                    minutes: lateMinutes,
                    netPerDaySalary: netPerDaySalary ?? 0.0,
                    shiftHours: shiftHoursForFinalFine,
                  );
                }
              }
            }
          } catch (_) {}
        }
      }
    } else {
      lateMinutes = (attendanceData?['lateMinutes'] as num?)?.toInt() ?? 0;
      final existingFineAmount =
          (attendanceData?['fineAmount'] as num?)?.toDouble() ?? 0.0;
      if (_templateIsOpenShift(tmpl)) {
        final punchInRaw = attendanceData?['punchIn'];
        if (punchInRaw != null) {
          try {
            final punchIn = DateTime.parse(punchInRaw.toString()).toLocal();
            final reqH = _templateOpenRequiredHours(tmpl);
            final requiredMin = (reqH * 60).round();
            final workedMin = now.difference(punchIn).inMinutes;
            shiftHoursForFinalFine = reqH;
            earlyMinutes = workedMin >= requiredMin
                ? 0
                : (requiredMin - workedMin);
            final shiftHours = reqH;
            double earlyFine = 0.0;
            if (netPerDaySalary != null &&
                netPerDaySalary > 0 &&
                earlyMinutes > 0 &&
                shiftHours > 0) {
              earlyFine =
                  ((netPerDaySalary / shiftHours) * (earlyMinutes / 60) * 100)
                      .round() /
                  100;
            }
            final hasRules = _hasFineRules();
            final earlyRule = _matchFineRuleForAction('earlyExit');
            if (hasRules) {
              if (earlyRule == null) {
                earlyFine = 0.0;
              } else {
                earlyFine = _computeFineFromRule(
                  rule: earlyRule,
                  minutes: earlyMinutes,
                  netPerDaySalary: netPerDaySalary ?? 0.0,
                  shiftHours: shiftHours,
                );
              }
            }
            fineAmount = existingFineAmount + earlyFine;
          } catch (_) {}
        }
      } else {
        final shiftEndStr =
            sessionTimings?['endTime'] ?? _getShiftEndTimeFromDb(tmpl);
        if (shiftEndStr != null && shiftEndStr.isNotEmpty) {
          try {
            final parts = shiftEndStr.split(':').map(int.parse).toList();
            final shiftEnd = DateTime(
              now.year,
              now.month,
              now.day,
              parts[0],
              parts.length > 1 ? parts[1] : 0,
            );
            if (now.isBefore(shiftEnd)) {
              earlyMinutes = shiftEnd.difference(now).inMinutes;
              final shiftStartForFine =
                  sessionTimings?['startTime'] ??
                  _getShiftStartTimeFromDb(tmpl) ??
                  '09:30';
              final shiftHours = calculateShiftHours(
                shiftStartForFine,
                shiftEndStr,
              );
              shiftHoursForFinalFine = shiftHours;
              double earlyFine = 0.0;
              if (netPerDaySalary != null &&
                  netPerDaySalary > 0 &&
                  earlyMinutes > 0 &&
                  shiftHours > 0) {
                earlyFine =
                    ((netPerDaySalary / shiftHours) * (earlyMinutes / 60) * 100)
                        .round() /
                    100;
              }
              final hasRules = _hasFineRules();
              final earlyRule = _matchFineRuleForAction('earlyExit');
              if (hasRules) {
                if (earlyRule == null) {
                  earlyFine = 0.0;
                } else {
                  earlyFine = _computeFineFromRule(
                    rule: earlyRule,
                    minutes: earlyMinutes,
                    netPerDaySalary: netPerDaySalary ?? 0.0,
                    shiftHours: shiftHours,
                  );
                }
              }
              fineAmount = existingFineAmount + earlyFine;
            }
          } catch (_) {}
        }
      }
    }

    final isOpenShift = _templateIsOpenShift(tmpl);
    final permissionApplyTo = (tmpl['permissionPolicy'] is Map<String, dynamic>)
        ? (tmpl['permissionPolicy']['applyTo']?.toString())
        : null;
    // At checkout, do not pass stored [lateMinutes] into permission splitting: that
    // value was already settled at check-in and would steal the whole permission
    // balance as "eligible late", zeroing early exit minutes and checkout fine.
    final permissionAdjustment = await _getPermissionAdjustment(
      day: DateTime(now.year, now.month, now.day),
      lateMinutes: isCheckedIn ? 0 : lateMinutes,
      earlyMinutes: earlyMinutes,
      isOpenShift: isOpenShift,
      isCheckout: isCheckedIn,
      applyTo: permissionApplyTo,
    );
    lateMinutes = (lateMinutes - (permissionAdjustment['consumeLate'] ?? 0))
        .clamp(0, 1000000);
    earlyMinutes = (earlyMinutes - (permissionAdjustment['consumeEarly'] ?? 0))
        .clamp(0, 1000000);

    if (shiftHoursForFinalFine <= 0) {
      if (isOpenShift) {
        shiftHoursForFinalFine = _templateOpenRequiredHours(tmpl);
      } else {
        final shiftStartStr = _getShiftStartTimeFromDb(tmpl) ?? '09:30';
        final shiftEndStr = _getShiftEndTimeFromDb(tmpl) ?? '18:30';
        shiftHoursForFinalFine = calculateShiftHours(
          shiftStartStr,
          shiftEndStr,
        );
      }
    }
    double computeLegFine(String action, int minutes) {
      if (minutes <= 0 ||
          netPerDaySalary == null ||
          netPerDaySalary <= 0 ||
          shiftHoursForFinalFine <= 0) {
        return 0.0;
      }
      final hasRules = _hasFineRules();
      final rule = _matchFineRuleForAction(action);
      if (hasRules) {
        if (rule == null) return 0.0;
        return _computeFineFromRule(
          rule: rule,
          minutes: minutes,
          netPerDaySalary: netPerDaySalary,
          shiftHours: shiftHoursForFinalFine,
        );
      }
      return ((netPerDaySalary / shiftHoursForFinalFine) * (minutes / 60) * 100)
              .round() /
          100;
    }

    final lateFine = isOpenShift
        ? 0.0
        : computeLegFine('lateArrival', lateMinutes);
    final earlyFine = computeLegFine('earlyExit', earlyMinutes);
    fineAmount = lateFine + earlyFine;

    if (kDebugMode) {
      debugPrint(
        '[Fine TEST][Dashboard Punch][Payload] isCheckout=$isCheckedIn '
        'lateMinutes=$lateMinutes earlyMinutes=$earlyMinutes '
        'fineAmount=${fineAmount.toStringAsFixed(2)}',
      );
    }

    return {
      'lateMinutes': lateMinutes,
      'earlyMinutes': earlyMinutes,
      'fineAmount': fineAmount,
    };
  }

  Future<Map<String, dynamic>?> _fetchActiveBreak() async {
    final result = await _breakService.getCurrentBreak();
    if (!mounted) return null;
    Map<String, dynamic>? activeBreak;
    final data = result['data'];
    if (result['success'] == true && data is Map<String, dynamic>) {
      activeBreak = data;
    } else if (result['success'] == true && data is Map) {
      activeBreak = Map<String, dynamic>.from(data);
    }
    setState(() {
      _activeBreak = activeBreak;
    });
    return activeBreak;
  }

  String _formatLocationText(_ResolvedLocation location) {
    if (location.address.trim().isNotEmpty) {
      return location.address;
    }
    final parts = <String>[
      if ((location.area ?? '').trim().isNotEmpty) location.area!.trim(),
      if ((location.city ?? '').trim().isNotEmpty) location.city!.trim(),
    ];
    var text = parts.join(', ');
    if ((location.pincode ?? '').trim().isNotEmpty) {
      text = text.isEmpty
          ? location.pincode!.trim()
          : '$text ${location.pincode!.trim()}';
    }
    return text;
  }

  DateTime? _activeBreakStartTime() {
    return parseApiDateTimeToLocal(_activeBreak?['startTime']);
  }

  int _normalizeTabIndex(int index) {
    if (index == 5) return 4;
    return index.clamp(0, 4);
  }

  /// Bottom bar: Dashboard (0), Requests (1), and Attendance (2). Punch/break use 5 and 6.
  int _bottomBarSelectedIndex() {
    if (_currentIndex >= 0 && _currentIndex <= 1) return _currentIndex;
    if (_currentIndex == 4) return 2;
    return -1;
  }

  int _mapBottomNavIndexToScreenIndex(int index) {
    // Bottom bar third icon is Attendance, which lives at screen index 4.
    if (index == 2) return 4;
    return _normalizeTabIndex(index);
  }

  List<NavItem> _buildBottomNavItems() {
    return const <NavItem>[
      NavItem(
        icon: Icons.dashboard_outlined,
        activeIcon: Icons.dashboard_rounded,
        label: 'Dashboard',
      ),
      NavItem(
        icon: Icons.description_outlined,
        activeIcon: Icons.description_rounded,
        label: 'Requests',
      ),
      NavItem(
        icon: Icons.fact_check_outlined,
        activeIcon: Icons.fact_check,
        label: 'Attendance',
      ),
    ];
  }

  Future<void> _refreshSalaryOverviewAccess({bool preferServer = false}) async {
    final hasAccessBefore = _hasSalaryOverviewAccess;
    final tabBefore = _currentIndex;
    final enabled = await _loadSalaryDetailsAccessEnabled(
      preferServer: preferServer,
    );
    if (!mounted) return;
    setState(() {
      _hasSalaryOverviewAccess = enabled;
      if (_deferSalaryInitialTab) {
        _deferSalaryInitialTab = false;
        if (enabled) {
          _currentIndex = 2;
        }
      } else if (!enabled && _currentIndex == 2) {
        _currentIndex = 0;
      }
    });
    _logSalaryAccessTest(
      '_refreshSalaryOverviewAccess | '
      'hasAccessBefore=$hasAccessBefore hasAccessAfter=$enabled | '
      'tabIndexBefore=$tabBefore tabIndexAfter=$_currentIndex',
    );
  }

  /// Runs when the home dashboard finishes a load: open tab, pull-to-refresh, or [refreshTrigger].
  Future<void> _onHomeDashboardDataRefreshed() async {
    await _refreshSalaryOverviewAccess(preferServer: true);
    await _fetchPunchStatusForNavBar();
  }

  /// Same rule as [SalaryOverviewScreen]: `salaryDetailsAccessEnabled == true` only.
  ///
  /// When [preferServer] is true, skips prefs short-circuit so GET /auth/profile always runs
  /// (dashboard refresh / tab focus reflects HR toggles without re-login).
  Future<bool> _loadSalaryDetailsAccessEnabled({bool preferServer = false}) async {
    bool result(bool value, String reason) {
      _logSalaryAccessTest(
        '_loadSalaryDetailsAccessEnabled -> salaryOverviewEnabled=$value ($reason)',
      );
      return value;
    }

    if (!preferServer) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final userStr = prefs.getString('user');
        if (userStr != null) {
          final user = jsonDecode(userStr) as Map<String, dynamic>;
          final staffRaw = user['staffData'] ?? user['staff'];
          Map<String, dynamic>? staffMap;
          if (staffRaw is Map) {
            staffMap = Map<String, dynamic>.from(staffRaw);
            final s = staffMap['salaryDetailsAccessEnabled'];
            _logSalaryAccessTest(
              '_loadSalaryDetailsAccessEnabled prefs | '
              'staffData.salaryDetailsAccessEnabled raw=$s (${s.runtimeType})',
            );
            if (s == true) {
              return result(true, 'prefs:staffData==true');
            }
          }
          final flat = user['salaryDetailsAccessEnabled'];
          _logSalaryAccessTest(
            '_loadSalaryDetailsAccessEnabled prefs | '
            'user.salaryDetailsAccessEnabled raw=$flat (${flat.runtimeType})',
          );
          if (flat == true) {
            return result(true, 'prefs:user_root==true');
          }
          if (staffMap != null && staffMap['salaryDetailsAccessEnabled'] == false) {
            return result(false, 'prefs:staffData==false');
          }
          if (flat == false) {
            return result(false, 'prefs:user_root==false');
          }
        } else {
          _logSalaryAccessTest(
            '_loadSalaryDetailsAccessEnabled prefs | no user json in SharedPreferences',
          );
        }
      } catch (e) {
        _logSalaryAccessTest('_loadSalaryDetailsAccessEnabled prefs | error=$e');
      }
    } else {
      _logSalaryAccessTest(
        '_loadSalaryDetailsAccessEnabled | preferServer=true (skip prefs, use GET /auth/profile)',
      );
    }
    try {
      final res = await _authService.getProfile();
      final ok = res['success'] == true;
      _logSalaryAccessTest(
        '_loadSalaryDetailsAccessEnabled profile | success=$ok',
      );
      if (res['success'] == true && res['data'] is Map) {
        final data = Map<String, dynamic>.from(res['data'] as Map);
        final staffRaw = data['staffData'];
        if (staffRaw is Map) {
          final staff = Map<String, dynamic>.from(staffRaw);
          final raw = staff['salaryDetailsAccessEnabled'];
          final enabled = raw == true;
          _logSalaryAccessTest(
            '_loadSalaryDetailsAccessEnabled profile | '
            'staffData.salaryDetailsAccessEnabled raw=$raw (${raw.runtimeType}) '
            '=> strictTrue=$enabled',
          );
          await _persistSalaryAccessOnUser(raw);
          return result(enabled, 'profile:staffData strict equality == true');
        }
        _logSalaryAccessTest(
          '_loadSalaryDetailsAccessEnabled profile | staffData missing or not a Map',
        );
      }
    } catch (e) {
      _logSalaryAccessTest('_loadSalaryDetailsAccessEnabled profile | error=$e');
    }
    return result(false, 'fallback:no_decisive_prefs_and_no_staff_true');
  }

  Future<void> _persistSalaryAccessOnUser(
    dynamic salaryDetailsAccessEnabled,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userStr = prefs.getString('user');
      if (userStr == null) {
        _logSalaryAccessTest(
          '_persistSalaryAccessOnUser skipped | no user string in prefs '
          '(would have written salaryDetailsAccessEnabled=$salaryDetailsAccessEnabled)',
        );
        return;
      }
      final user = jsonDecode(userStr) as Map<String, dynamic>;
      user['salaryDetailsAccessEnabled'] = salaryDetailsAccessEnabled;
      if (user['staffData'] is Map) {
        final st = Map<String, dynamic>.from(user['staffData'] as Map);
        st['salaryDetailsAccessEnabled'] = salaryDetailsAccessEnabled;
        user['staffData'] = st;
      } else if (user['staff'] is Map) {
        final st = Map<String, dynamic>.from(user['staff'] as Map);
        st['salaryDetailsAccessEnabled'] = salaryDetailsAccessEnabled;
        user['staff'] = st;
      }
      await prefs.setString('user', jsonEncode(user));
      _logSalaryAccessTest(
        '_persistSalaryAccessOnUser | wrote user+staffData salaryDetailsAccessEnabled='
        '$salaryDetailsAccessEnabled (${salaryDetailsAccessEnabled.runtimeType})',
      );
    } catch (e) {
      _logSalaryAccessTest('_persistSalaryAccessOnUser error=$e');
    }
  }

  void _onDrawerNavigateToIndex(int index) {
    if (index == 2 && !_hasSalaryOverviewAccess) return;
    final normalized = _normalizeTabIndex(index);
    if (index >= 0 && (index <= 4 || index == 5)) {
      setState(() => _currentIndex = normalized);
      unawaited(_fetchPunchStatusForNavBar());
    }
  }

  void _onDashboardNavigate(int index, {int subTabIndex = 0}) {
    if (index == 2 && !_hasSalaryOverviewAccess) return;
    final normalized = _normalizeTabIndex(index);
    if (index < 0 || index > 5) return;
    if (!mounted) return;
    setState(() {
      _currentIndex = normalized;
      if (index == 1) _requestsSubTabIndex = subTabIndex;
      if (normalized == 4) _attendanceSubTabIndex = subTabIndex;
    });
    unawaited(_fetchPunchStatusForNavBar());
  }

  void _onRequestsTabIndexChanged(int index) {
    if (!mounted) return;
    setState(() => _requestsSubTabIndex = index.clamp(0, 4));
  }

  /// Fetches current position and address. Returns null position on failure.
  Future<_ResolvedLocation> _getCurrentLocation() async {
    String address = '';
    String? area;
    String? city;
    String? pincode;
    Position? position;
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled)
        return (
          position: null,
          address: '',
          area: null,
          city: null,
          pincode: null,
        );
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return (
          position: null,
          address: '',
          area: null,
          city: null,
          pincode: null,
        );
      }
      position = await getQuickPositionForUi();
      final resolved = await AddressResolutionService.reverseGeocodeForUi(
        position.latitude,
        position.longitude,
      );
      if (resolved != null) {
        area = resolved.area;
        city = resolved.city ?? resolved.state;
        pincode = resolved.pincode;
        address = resolved.formattedAddress;
      } else {
        address = 'Lat: ${position.latitude}, Lng: ${position.longitude}';
      }
    } catch (_) {
      address = 'Location found (Address unavailable)';
    }
    return (
      position: position,
      address: address,
      area: area,
      city: city,
      pincode: pincode,
    );
  }

  Future<void> _submitBreakFromFile(
    File file, {
    required bool isEnding,
    required Map<String, dynamic>? activeBreak,
    _ResolvedLocation? prefetchedLocation,
  }) async {
    final detection = await FaceDetectionHelper.detectFromFile(file);
    if (!mounted) return;
    if (!detection.valid) {
      SnackBarUtils.showSnackBar(
        context,
        detection.message ??
            'Please take a selfie with exactly one face visible.',
        isError: true,
      );
      return;
    }

    final location = prefetchedLocation ?? await _getCurrentLocation();
    if (!mounted) return;
    final position = location.position;
    if (position == null) {
      SnackBarUtils.showSnackBar(
        context,
        'Location is required for breaks.',
        isError: true,
      );
      return;
    }

    final selfieBytes = await file.readAsBytes();
    if (!mounted) return;
    final selfie = 'data:image/jpeg;base64,${base64Encode(selfieBytes)}';
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        content: Row(
          children: [
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 16),
            Text(isEnding ? 'Ending break…' : 'Starting break…'),
          ],
        ),
      ),
    );

    Map<String, dynamic> result;
    try {
      result = isEnding
          ? await _breakService.endBreak(
              breakId: activeBreak?['id']?.toString() ?? '',
              lat: position.latitude,
              lng: position.longitude,
              address: location.address,
              area: location.area,
              city: location.city,
              pincode: location.pincode,
              selfie: selfie,
            )
          : await _breakService.startBreak(
              lat: position.latitude,
              lng: position.longitude,
              address: location.address,
              area: location.area,
              city: location.city,
              pincode: location.pincode,
              selfie: selfie,
            );
    } finally {
      if (mounted) {
        Navigator.of(context).pop();
      }
    }

    if (!mounted) return;
    if (result['success'] == true) {
      await _fetchActiveBreak();
      if (!mounted) return;
      SnackBarUtils.showSnackBar(
        context,
        isEnding ? 'Break ended successfully' : 'Break started successfully',
      );
      _dashboardRefreshTrigger.value++;
      return;
    }

    final serverBreak = result['data'];
    if (serverBreak is Map) {
      setState(() {
        _activeBreak = Map<String, dynamic>.from(serverBreak);
      });
    }
    SnackBarUtils.showSnackBar(
      context,
      ErrorMessageUtils.sanitizeForDisplay(result['message']?.toString()),
      isError: true,
    );
  }

  Future<void> _captureBreakSelfieAndSubmit({
    required bool isEnding,
    required Map<String, dynamic>? activeBreak,
  }) async {
    _ResolvedLocation? latestLocation;
    final result = await SelfieCameraScreen.captureSelfie(
      context,
      title: isEnding ? 'End Break' : 'Start Break',
      loadLocationOnOpen: true,
      onRefreshLocation: () async {
        final location = await _getCurrentLocation();
        latestLocation = location;
        final formatted = _formatLocationText(location);
        return formatted.isEmpty ? null : formatted;
      },
    );
    if (!mounted) return;

    File? file;
    if (result is File) {
      file = result;
    } else if (identical(result, useImagePickerFallback)) {
      final pickedFile = await ImagePicker().pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
        imageQuality: 85,
        maxWidth: 1024,
      );
      if (!mounted) return;
      if (pickedFile != null) {
        file = File(pickedFile.path);
      }
    }
    if (file == null) return;

    await _submitBreakFromFile(
      file,
      isEnding: isEnding,
      activeBreak: activeBreak,
      prefetchedLocation: latestLocation,
    );
  }

  Future<void> _startBreakFlow() async {
    if (_isBreakActionInProgress) return;
    setState(() => _isBreakActionInProgress = true);
    try {
      final activeBreak = await _fetchActiveBreak();
      if (!mounted) return;
      if (activeBreak != null) {
        SnackBarUtils.showSnackBar(
          context,
          'You are already on break. End that break to start a new one.',
          isError: true,
        );
        return;
      }
      await _captureBreakSelfieAndSubmit(isEnding: false, activeBreak: null);
    } finally {
      if (mounted) {
        setState(() => _isBreakActionInProgress = false);
      }
    }
  }

  Future<void> _endBreakFlow() async {
    if (_isBreakActionInProgress) return;
    setState(() => _isBreakActionInProgress = true);
    try {
      final activeBreak = await _fetchActiveBreak();
      if (!mounted) return;
      if (activeBreak == null) {
        SnackBarUtils.showSnackBar(
          context,
          'No active break found.',
          isError: true,
        );
        return;
      }
      await _captureBreakSelfieAndSubmit(
        isEnding: true,
        activeBreak: activeBreak,
      );
    } finally {
      if (mounted) {
        setState(() => _isBreakActionInProgress = false);
      }
    }
  }

  Future<void> _openRequestedBreakFlow() async {
    final activeBreak = await _fetchActiveBreak();
    if (!mounted) return;
    if (activeBreak != null) {
      await _endBreakFlow();
      return;
    }
    await _startBreakFlow();
  }

  /// Fetches profile + today attendance for fingerprint validation (same data as attendance screen).
  Future<Map<String, dynamic>?> _fetchAttendanceValidationData() async {
    try {
      const validationTimeout = Duration(seconds: 12);
      final sw = Stopwatch()..start();
      _attendanceService.clearCachesForRefresh();
      final todayStr =
          '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')}';
      final settled = await Future.wait<dynamic>([
        _authService.getProfile().timeout(
          validationTimeout,
          onTimeout: () => {'success': false, 'message': 'profile timeout'},
        ),
        _attendanceService
            .getTodayAttendance(forceRefresh: true, date: todayStr)
            .timeout(
              validationTimeout,
              onTimeout: () => {'success': false, 'message': 'today timeout'},
            ),
      ]);
      if (!mounted) return null;
      final profileResult = settled[0] as Map<String, dynamic>;
      final result = settled[1] as Map<String, dynamic>;
      final staffData =
          profileResult['data']?['staffData'] as Map<String, dynamic>?;
      final templateId = staffData?['attendanceTemplateId'];
      punchFlowLog(
        '[PunchFlow] validation data settled in ${sw.elapsedMilliseconds}ms | '
        'profileSuccess=${profileResult['success']} | todaySuccess=${result['success']}',
      );
      Map<String, dynamic> effectiveResult = Map<String, dynamic>.from(result);
      if (effectiveResult['success'] != true || effectiveResult['data'] == null) {
        punchFlowLog(
          '[PunchFlow] primary today fetch failed; trying getAttendanceByDate fallback | '
          'message=${effectiveResult['message'] ?? '(none)'}',
        );
        try {
          final fallback = await _attendanceService
              .getAttendanceByDate(todayStr)
              .timeout(
                validationTimeout,
                onTimeout: () => {'success': false, 'message': 'today fallback timeout'},
              );
          if (fallback['success'] == true && fallback['data'] != null) {
            effectiveResult = Map<String, dynamic>.from(fallback);
            punchFlowLog(
              '[PunchFlow] getAttendanceByDate fallback succeeded in '
              '${sw.elapsedMilliseconds}ms',
            );
          } else {
            punchFlowLog(
              '[PunchFlow] getAttendanceByDate fallback failed | '
              'message=${fallback['message'] ?? '(none)'}',
            );
          }
        } catch (e) {
          punchFlowLog('[PunchFlow] getAttendanceByDate fallback error: $e');
        }
      }
      if (effectiveResult['success'] != true || effectiveResult['data'] == null) {
        // One final short retry helps when backend is momentarily busy.
        await Future.delayed(const Duration(milliseconds: 450));
        final retry = await _attendanceService
            .getTodayAttendance(forceRefresh: true, date: todayStr)
            .timeout(
              validationTimeout,
              onTimeout: () => {'success': false, 'message': 'today retry timeout'},
            );
        if (retry['success'] == true && retry['data'] != null) {
          effectiveResult = Map<String, dynamic>.from(retry);
          punchFlowLog(
            '[PunchFlow] getTodayAttendance retry succeeded in '
            '${sw.elapsedMilliseconds}ms',
          );
        } else {
          punchFlowLog(
            '[PunchFlow] getTodayAttendance retry failed | '
            'message=${retry['message'] ?? '(none)'}',
          );
        }
      }
      if (effectiveResult['success'] != true || effectiveResult['data'] == null) {
        punchFlowLog(
          '[PunchFlow] validation data unavailable after retries in '
          '${sw.elapsedMilliseconds}ms',
        );
        return null;
      }

      final body = effectiveResult['data'] as Map<String, dynamic>;
      final template = asAttendanceTemplateMap(body['template']);
      if (kDebugMode) {
        _logTodayShiftTimingsFromDb(template);
      }
      final staffHasTemplate = staffHasAssignedAttendanceTemplate(
        profileAttendanceTemplateRef: templateId,
        todayAttendanceTemplate: template,
      );
      final branch = body['branch'];
      final branchData = branch is Map<String, dynamic> ? branch : null;
      final shiftAssigned = body['shiftAssigned'] as bool? ?? true;
      final data = body['data'] ?? body;
      final attendanceData = data is Map<String, dynamic> ? data : null;

      // Keep SharedPrefs in sync so late/early warning dialogs can show template flags.
      await AttendanceTemplateStore.saveTemplateDetails(<String, dynamic>{
        'template': template,
        'branch': branchData,
        'shiftAssigned': shiftAssigned,
        'isHoliday': body['isHoliday'] ?? false,
        'isWeeklyOff': body['isWeeklyOff'] ?? false,
        'holidayInfo': body['holidayInfo'],
        'checkInAllowed': body['checkInAllowed'] ?? true,
        'checkOutAllowed': body['checkOutAllowed'] ?? true,
      });

      final companyDocForShift = companyDocForBreakPolicyFromTodayApiRoot(body);

      return {
        'staffHasTemplate': staffHasTemplate,
        'template': template,
        'companyDocForShift': companyDocForShift,
        'staffData': staffData != null
            ? Map<String, dynamic>.from(staffData)
            : null,
        'branchData': branchData,
        'shiftAssigned': shiftAssigned,
        'attendanceData': attendanceData,
        'halfDayLeave': body['halfDayLeave'],
        'checkInAllowed': body['checkInAllowed'] ?? true,
        'checkOutAllowed': body['checkOutAllowed'] ?? true,
        'leaveMessage': body['leaveMessage'],
        'isHoliday': body['isHoliday'] ?? false,
        'isWeeklyOff': body['isWeeklyOff'] ?? false,
        'isAlternateWorkDate': body['isAlternateWorkDate'] ?? false,
        'isCompensationWeekOff': body['isCompensationWeekOff'] ?? false,
        'isCompensationCompOff': body['isCompensationCompOff'] ?? false,
        'isPaidLeaveToday': body['isPaidLeaveToday'] ?? false,
        'isOnLeave': body['isOnLeave'] ?? false,
      };
    } catch (e) {
      punchFlowLog('[PunchFlow] validation fetch error: $e');
      return null;
    }
  }

  /// Same UI as attendance screen "Cannot mark attendance" alert.
  Future<void> _showValidationAlertDialog(String message) async {
    if (!mounted) return;
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        const String title = 'Cannot mark attendance';
        const IconData iconData = Icons.warning_amber_rounded;
        final Color iconColor = AppColors.primary;
        final colorScheme = Theme.of(context).colorScheme;
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Material(
            color: Colors.transparent,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 340),
              decoration: BoxDecoration(
                color: const Color(0xFF2A2A2A).withOpacity(0.85),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFF0D0D0D), width: 2),
                boxShadow: [
                  BoxShadow(
                    color: colorScheme.shadow.withOpacity(0.2),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: iconColor.withOpacity(0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(iconData, size: 48, color: iconColor),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white.withOpacity(0.9),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.4,
                      color: Colors.white.withOpacity(0.8),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: Material(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        onTap: () => Navigator.of(context).pop(),
                        borderRadius: BorderRadius.circular(12),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(vertical: 14),
                          child: Text(
                            'OK',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Same UI as attendance screen "You are Late" / "You are Early" alert.
  /// Late login: turtle emoji 🐢 shown standing on top of the card.
  Future<bool> _showWarningAlertDialog(
    String message, {
    bool isLate = false,
    bool isEarly = false,
    String? shiftTimingLine,
  }) async {
    final fullMessage = (isLate || isEarly)
        ? message
        : await AttendanceTemplateStore.appendRequireSelfieGeolocationToMessage(
            message,
          );
    if (!mounted) return false;
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        final String title = isLate
            ? 'Late Login'
            : isEarly
            ? 'You are Early'
            : 'Notice';
        final IconData iconData = isLate
            ? Icons.access_time_rounded
            : isEarly
            ? Icons.schedule_rounded
            : Icons.info_outline_rounded;
        final Color iconColor = AppColors.primary;
        final colorScheme = Theme.of(context).colorScheme;
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24),
          child: Material(
            color: Colors.transparent,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                // Card
                Container(
                  constraints: const BoxConstraints(maxWidth: 340),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A2A2A).withOpacity(0.85),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: const Color(0xFF0D0D0D),
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: colorScheme.shadow.withOpacity(0.2),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  padding: EdgeInsets.only(
                    left: 24,
                    right: 24,
                    top: (isLate || isEarly) ? 48 : 28,
                    bottom: 28,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!isLate && !isEarly)
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: iconColor.withOpacity(0.12),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(iconData, size: 48, color: iconColor),
                        ),
                      if (!isLate && !isEarly) const SizedBox(height: 20),
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white.withOpacity(0.9),
                        ),
                      ),
                      if ((isLate || isEarly) &&
                          shiftTimingLine != null &&
                          shiftTimingLine.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        Text(
                          'shift $shiftTimingLine',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.35,
                            color: Colors.white.withOpacity(0.88),
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Text(
                        fullMessage,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.4,
                          color: Colors.white.withOpacity(0.8),
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: Material(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(12),
                          child: InkWell(
                            onTap: () => Navigator.of(context).pop(true),
                            borderRadius: BorderRadius.circular(12),
                            child: const Padding(
                              padding: EdgeInsets.symmetric(vertical: 14),
                              child: Text(
                                'OK',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Single turtle walking left→right above the card only (not inside)
                if (isLate || isEarly)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: -82,
                    child: RepaintBoundary(
                      child: Center(
                        child: WalkingTurtleEmoji(
                          fontSize: 64,
                          playOnlyOncePerApp: isLate,
                          animationKey: 'late-login-card-turtle',
                          emoji: isLate ? '🐢' : '😐',
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
    // Back button / route pop returns null -> treat as cancelled.
    return result == true;
  }

  /// Template helpers (mirror attendance screen for validation only).
  static String? _getShiftStartTimeFromDb(Map<String, dynamic>? template) {
    final v = template?['shiftStartTime']?.toString().trim();
    return (v != null && v.isNotEmpty) ? v : null;
  }

  static String? _getShiftEndTimeFromDb(Map<String, dynamic>? template) {
    final v = template?['shiftEndTime']?.toString().trim();
    return (v != null && v.isNotEmpty) ? v : null;
  }

  /// Logs merged today template shift window from DB (`shiftStartTime` / `shiftEndTime`; falls back to `startTime` / `endTime`).
  static void _logTodayShiftTimingsFromDb(Map<String, dynamic>? template) {
    final fromShiftKeysStart = _getShiftStartTimeFromDb(template);
    final fromShiftKeysEnd = _getShiftEndTimeFromDb(template);
    final startFallback = template?['startTime']?.toString().trim();
    final endFallback = template?['endTime']?.toString().trim();
    final startOut =
        fromShiftKeysStart ??
        (startFallback?.isNotEmpty == true ? startFallback : null);
    final endOut =
        fromShiftKeysEnd ??
        (endFallback?.isNotEmpty == true ? endFallback : null);
    debugPrint('shift start time****** ${startOut ?? '(none)'}');
    debugPrint('shift end time****** ${endOut ?? '(none)'}');
  }

  /// Parity with app_backend getShiftTimings: open / open shift, or shift name "OPEN".
  static bool _templateIsOpenShift(Map<String, dynamic>? template) {
    if (template == null) return false;
    final st = (template['shiftType'] ?? '').toString().toLowerCase().trim();
    if (st == 'open' || st == 'open shift') return true;
    final name = (template['shiftName'] ?? template['name'] ?? '')
        .toString()
        .toLowerCase()
        .trim();
    if (name == 'open' || name == 'open shift') return true;
    return false;
  }

  static bool _templateIsRotationalWrapper(Map<String, dynamic>? template) {
    if (template == null) return false;
    final st = (template['shiftType'] ?? '').toString().toLowerCase().trim();
    if (st == 'rotational') return true;
    final rc = template['rotationalConfig'];
    if (rc is Map) {
      final ids = rc['shiftIdsInCycle'];
      if (ids is List && ids.isNotEmpty) return true;
      final names = rc['shiftNamesInCycle'];
      if (names is List && names.isNotEmpty) return true;
      final byWd = rc['shiftIdsByWeekday'];
      if (byWd is List && byWd.isNotEmpty) return true;
      final byCal = rc['weeklyDateAssignments'];
      if (byCal is List && byCal.isNotEmpty) return true;
    }
    return false;
  }

  static bool _templateHasTodayByWeekCalendarWeekOff(
    Map<String, dynamic>? template,
  ) {
    if (template == null) return false;
    final st = (template['shiftType'] ?? '').toString().toLowerCase().trim();
    if (st != 'rotational') return false;
    final rc = template['rotationalConfig'];
    if (rc is! Map) return false;
    final rotType = (rc['rotationType'] ?? '').toString().toLowerCase().trim();
    if (rotType != 'byweekcalendar' && rotType != 'by_week_calendar') {
      return false;
    }
    final rows = rc['weeklyDateAssignments'];
    if (rows is! List || rows.isEmpty) return false;
    final now = DateTime.now();
    final todayYmd =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    for (final row in rows) {
      if (row is! Map) continue;
      final dateRaw = row['date']?.toString().trim() ?? '';
      if (dateRaw.isEmpty) continue;
      final m = RegExp(r'^(\d{4}-\d{2}-\d{2})').firstMatch(dateRaw);
      final ymd = m?.group(1);
      if (ymd != todayYmd) continue;
      final weekOffRaw = row['isWeekOff'];
      final isWeekOff =
          weekOffRaw == true ||
          weekOffRaw == 1 ||
          weekOffRaw?.toString().trim().toLowerCase() == 'true';
      if (isWeekOff) return true;
    }
    return false;
  }

  static double _templateOpenRequiredHours(Map<String, dynamic>? template) {
    if (template == null || !_templateIsOpenShift(template)) return 8;
    for (final key in ['openWorkHours', 'workHours']) {
      final v = template[key];
      if (v is num) {
        final d = v.toDouble();
        if (d > 0) return d;
      } else if (v != null) {
        final p = double.tryParse(v.toString().trim());
        if (p != null && p > 0) return p;
      }
    }
    return 8;
  }

  static int _getGracePeriodMinutes(Map<String, dynamic>? template) {
    if (template == null) return 15;
    final flat = template['gracePeriodMinutes'];
    if (flat != null) {
      if (flat is int) return flat;
      final parsed = int.tryParse(flat.toString());
      if (parsed != null) return parsed;
    }
    try {
      final shifts = template['settings']?['attendance']?['shifts'] as List?;
      if (shifts != null && shifts.isNotEmpty) {
        final shift = shifts[0] as Map<String, dynamic>?;
        final graceTime = shift?['graceTime'];
        if (graceTime is Map) {
          final value = graceTime['value'];
          final unit = graceTime['unit']?.toString().toLowerCase();
          final v = value is int
              ? value
              : int.tryParse(value?.toString() ?? '');
          if (v != null) {
            if (unit == 'hours') return v * 60;
            return v;
          }
        }
      }
    } catch (_) {}
    return 15;
  }

  static Map<String, String>? _getHalfDaySessionBoundaries(
    Map<String, dynamic>? template,
  ) {
    final shiftStartStr = _getShiftStartTimeFromDb(template);
    final shiftEndStr = _getShiftEndTimeFromDb(template);
    if (shiftStartStr == null || shiftEndStr == null) return null;
    try {
      final startParts = shiftStartStr.split(':').map(int.parse).toList();
      final endParts = shiftEndStr.split(':').map(int.parse).toList();
      int startTotalMinutes =
          startParts[0] * 60 + (startParts.length > 1 ? startParts[1] : 0);
      int endTotalMinutes =
          endParts[0] * 60 + (endParts.length > 1 ? endParts[1] : 0);
      if (endTotalMinutes <= startTotalMinutes) endTotalMinutes += 24 * 60;
      final halfMinutes = (endTotalMinutes - startTotalMinutes) ~/ 2;
      final session1EndMinutes = startTotalMinutes + halfMinutes;
      final session1EndHours = (session1EndMinutes ~/ 60) % 24;
      final session1EndMins = session1EndMinutes % 60;
      final session1End =
          '${session1EndHours.toString().padLeft(2, '0')}:${session1EndMins.toString().padLeft(2, '0')}';
      return {
        'session1Start': shiftStartStr,
        'session1End': session1End,
        'session2Start': session1End,
        'session2End': shiftEndStr,
      };
    } catch (_) {
      return null;
    }
  }

  static String? _shiftTimingSummaryForWarningDialog(
    Map<String, dynamic>? attendanceData,
    Map<String, dynamic>? halfDayLeave,
    Map<String, dynamic>? template,
  ) {
    if (template == null || _templateIsOpenShift(template)) return null;
    final session = _getWorkingSessionTimings(
      attendanceData,
      halfDayLeave,
      template,
    );
    final startRaw =
        session?['startTime'] ?? _getShiftStartTimeFromDb(template);
    final endRaw = session?['endTime'] ?? _getShiftEndTimeFromDb(template);
    if (startRaw == null ||
        endRaw == null ||
        startRaw.isEmpty ||
        endRaw.isEmpty) {
      return null;
    }
    return '$startRaw-$endRaw';
  }

  static Map<String, String>? _getWorkingSessionTimings(
    Map<String, dynamic>? attendanceData,
    Map<String, dynamic>? halfDayLeave,
    Map<String, dynamic>? template,
  ) {
    final isHalfDay =
        (attendanceData?['status'] == 'Half Day') || (halfDayLeave != null);
    if (!isHalfDay) return null;
    final session =
        halfDayLeave?['session']?.toString().trim() ??
        attendanceData?['session']?.toString().trim();
    if (session != '1' && session != '2') return null;
    final b = _getHalfDaySessionBoundaries(template);
    if (b == null) return null;
    if (session == '1') {
      return {'startTime': b['session2Start']!, 'endTime': b['session2End']!};
    }
    return {'startTime': b['session1Start']!, 'endTime': b['session1End']!};
  }

  static int _getGracePeriodMinutesForLateCheckIn(
    Map<String, dynamic>? attendanceData,
    Map<String, dynamic>? halfDayLeave,
    Map<String, dynamic>? template,
  ) {
    final session =
        halfDayLeave?['session']?.toString().trim() ??
        attendanceData?['session']?.toString().trim();
    if (session == '1') return 0;
    return _getGracePeriodMinutes(template);
  }

  /// Runs same validations as attendance screen _openMarkAttendanceScreen. Returns true if OK to open camera, false if blocked (alert already shown).
  Future<bool> _runFingerprintAttendanceValidations(
    Map<String, dynamic> data,
  ) async {
    final staffHasTemplate = data['staffHasTemplate'] as bool? ?? false;
    final template = data['template'] as Map<String, dynamic>?;
    final branchData = data['branchData'] as Map<String, dynamic>?;
    final shiftAssigned = data['shiftAssigned'] as bool? ?? true;
    final attendanceData = data['attendanceData'] as Map<String, dynamic>?;
    final halfDayLeave = data['halfDayLeave'] as Map<String, dynamic>?;
    final checkInAllowed = data['checkInAllowed'] as bool? ?? true;
    final leaveMessage = data['leaveMessage']?.toString();
    final isHoliday = data['isHoliday'] as bool? ?? false;
    final isWeeklyOff = data['isWeeklyOff'] as bool? ?? false;
    final isAlternateWorkDate = data['isAlternateWorkDate'] as bool? ?? false;
    final isCompensationWeekOff =
        data['isCompensationWeekOff'] as bool? ?? false;
    final isCompensationCompOff =
        data['isCompensationCompOff'] as bool? ?? false;
    final isPaidLeaveToday = data['isPaidLeaveToday'] as bool? ?? false;
    final isPaidLeaveOnTodayRow = attendanceData?['isPaidLeave'] == true;
    final isPaidLeaveContext = isPaidLeaveToday || isPaidLeaveOnTodayRow;
    final isCheckedIn = _isAttendancePunchedIn(attendanceData);
    final isCompleted = _isAttendanceCompleted(attendanceData);
    final status = attendanceData?['status'] ?? '';
    final isAdminMarked =
        !_hasPunchValue(attendanceData?['punchIn']) &&
        !_hasPunchValue(attendanceData?['punchOut']) &&
        (status == 'Present' || status == 'Approved');

    if (isCompleted) {
      SnackBarUtils.showSnackBar(
        context,
        'You have already punched out today',
        isError: true,
      );
      return false;
    }
    if (isAdminMarked) return false;

    if (staffHasTemplate != true) {
      await _showValidationAlertDialog(
        'Attendance template is not assigned. Contact HR.',
      );
      return false;
    }
    if (!isValidAttendanceTemplateMap(template)) {
      await _showValidationAlertDialog('Template not mapped. Contact HR.');
      return false;
    }
    final Map<String, dynamic> tmpl = template!;
    final staffData = data['staffData'] as Map<String, dynamic>?;
    final companyDocRaw = data['companyDocForShift'] as Map<String, dynamic>?;
    EffectiveShiftDay? todayEffectiveShift;
    if (staffData != null && shiftsListFromCompany(companyDocRaw) != null) {
      final templateLabel =
          (tmpl['name'] ?? tmpl['shiftName'] ?? '').toString().trim();
      final shiftKey = staffShiftKeyFromProfileMap(
        staffData,
        attendanceTemplateName: templateLabel.isEmpty ? null : templateLabel,
      );
      todayEffectiveShift = effectiveShiftForCalendarDay(
        companyDoc: companyDocRaw,
        staffShiftKey: shiftKey,
        dayLocal: DateTime.now(),
        joiningDate: null,
        attendanceTodayTemplate: tmpl,
      );
    }
    final staffShiftIdLog =
        objectIdHexLoose(staffData?['shiftId']) ?? '(none)';
    final effWin = todayEffectiveShift != null &&
            !todayEffectiveShift.isWeekOff &&
            !todayEffectiveShift.isOpen
        ? '${todayEffectiveShift.startTime ?? ''}-${todayEffectiveShift.endTime ?? ''}'
        : '';
    punchFlowLog(
      '[PunchFlow][todayShift] staffShiftId=$staffShiftIdLog '
      'template=${(tmpl['name'] ?? tmpl['shiftName'] ?? '(unnamed)').toString()} '
      'type=${(tmpl['shiftType'] ?? '').toString()} '
      'effectiveName=${todayEffectiveShift?.displayName ?? '(n/a)'} '
      'effectiveIsWeekOff=${todayEffectiveShift?.isWeekOff == true} '
      'effectiveWindow=${effWin.isEmpty ? '(n/a)' : effWin}',
    );
    if (shiftAssigned != true) {
      await _showValidationAlertDialog('Shift not assigned. Contact HR.');
      return false;
    }
    if (branchData == null) {
      await _showValidationAlertDialog('Branch not assigned.');
      return false;
    }
    final branchStatus =
        (branchData['status']?.toString().trim().toUpperCase()) ?? '';
    if (branchStatus != 'ACTIVE') {
      await _showValidationAlertDialog('Your branch is not active.');
      return false;
    }
    final geofence = branchData['geofence'] as Map<String, dynamic>?;
    final requireTemplateGeolocation = tmpl['requireGeolocation'] ?? true;
    if (requireTemplateGeolocation == true) {
      final geofenceEnabled = geofence?['enabled'] == true;
      if (!geofenceEnabled) {
        await _showValidationAlertDialog('Geo fence is not set for your branch.');
        return false;
      }
      final branchLat = geofence?['latitude'];
      final branchLng = geofence?['longitude'];
      final latLngSet =
          branchLat != null &&
          branchLng != null &&
          (branchLat is num ||
              (branchLat is String && branchLat.toString().trim().isNotEmpty)) &&
          (branchLng is num ||
              (branchLng is String && branchLng.toString().trim().isNotEmpty));
      if (!latLngSet) {
        await _showValidationAlertDialog(
          'Lat and long is not set for the branch.',
        );
        return false;
      }
    }
    if (tmpl['isActive'] == false) {
      await _showValidationAlertDialog(
        'Attendance template is not active. Contact HR.',
      );
      return false;
    }
    if (!_templateIsOpenShift(tmpl)) {
      final shiftStart = _getShiftStartTimeFromDb(tmpl);
      final shiftEnd = _getShiftEndTimeFromDb(tmpl);
      final fromEffective = todayEffectiveShift != null &&
          !todayEffectiveShift.isWeekOff &&
          (todayEffectiveShift.isOpen ||
              ((todayEffectiveShift.startTime ?? '').isNotEmpty &&
                  (todayEffectiveShift.endTime ?? '').isNotEmpty));
      if (shiftStart == null ||
          shiftStart.isEmpty ||
          shiftEnd == null ||
          shiftEnd.isEmpty) {
        // Rotational wrappers intentionally do not carry direct start/end in template;
        // effective shift window is resolved server-side per date.
        if (!_templateIsRotationalWrapper(tmpl) && !fromEffective) {
          await _showValidationAlertDialog(
            shiftAssigned == true
                ? 'Shift timings not set. Contact HR.'
                : 'Shift not assigned. Contact HR.',
          );
          return false;
        }
      }
    }

    final isSecondHalfLeave =
        halfDayLeave != null &&
        (halfDayLeave['halfDayType'] == 'Second Half Day' ||
            halfDayLeave['halfDaySession'] == 'Second Half Day' ||
            halfDayLeave['session'] == '2');
    final isFirstHalfLeave =
        halfDayLeave != null &&
        (halfDayLeave['halfDayType'] == 'First Half Day' ||
            halfDayLeave['halfDaySession'] == 'First Half Day' ||
            halfDayLeave['session'] == '1');
    final isOnLeaveFromApi = data['isOnLeave'] as bool? ?? false;
    final isOnLeave = isOnLeaveFromApi || halfDayLeave != null;
    punchFlowLog(
      '[PunchFlow][validate] isCheckedIn=$isCheckedIn isOnLeave=$isOnLeave '
      '(api=$isOnLeaveFromApi halfDay=${halfDayLeave != null}) '
      'checkInAllowed=$checkInAllowed isPaidLeaveContext=$isPaidLeaveContext '
      'leaveMessage=${leaveMessage ?? "(null)"}',
    );
    if (!isCheckedIn && isOnLeave && !checkInAllowed) {
      SnackBarUtils.showSnackBar(
        context,
        ErrorMessageUtils.sanitizeForDisplay(
          isSecondHalfLeave
              ? 'Not allowed check-in. You are on leave on second half.'
              : isFirstHalfLeave
              ? 'Not allowed check-in. You are on leave on first half.'
              : (leaveMessage ?? 'Check-in is not allowed at this time.'),
        ),
        isError: true,
        debugSource:
            'Dashboard._runFingerprintAttendanceValidations.blockCheckInOnLeave',
      );
      await NotificationReactionOverlay.show(context, emoji: '😊');
      return false;
    }
    // Do not block check-out client-side when already punched in (e.g. web + app selfie); server decides.
    if (isHoliday && tmpl['allowAttendanceOnHolidays'] == false) {
      SnackBarUtils.showSnackBar(context, 'Today is a holiday', isError: true);
      return false;
    }
    if (isCompensationWeekOff) {
      SnackBarUtils.showSnackBar(
        context,
        'Today is compensation week off',
        isError: true,
      );
      return false;
    }
    if (isCompensationCompOff) {
      SnackBarUtils.showSnackBar(context, 'Today is comp off', isError: true);
      return false;
    }
    if (isPaidLeaveContext && !isCheckedIn) {
      SnackBarUtils.showSnackBar(context, 'Today is paid leave', isError: true);
      return false;
    }
    if (todayEffectiveShift?.isWeekOff == true ||
        (todayEffectiveShift == null &&
            _templateHasTodayByWeekCalendarWeekOff(tmpl))) {
      SnackBarUtils.showSnackBar(context, 'Today is weekoff', isError: true);
      return false;
    }
    if (isWeeklyOff &&
        tmpl['allowAttendanceOnWeeklyOff'] == false &&
        !isAlternateWorkDate) {
      SnackBarUtils.showSnackBar(context, 'Today is a holiday', isError: true);
      return false;
    }

    final now = DateTime.now();
    if (!isCheckedIn) {
      final sessionTimings = _getWorkingSessionTimings(
        attendanceData,
        halfDayLeave,
        tmpl,
      );
      final shiftEndStrForBlock =
          sessionTimings?['endTime'] ?? _getShiftEndTimeFromDb(tmpl);
      if (shiftEndStrForBlock != null && shiftEndStrForBlock.isNotEmpty) {
        try {
          final parts = shiftEndStrForBlock.split(':').map(int.parse).toList();
          final shiftEndForBlock = DateTime(
            now.year,
            now.month,
            now.day,
            parts[0],
            parts.length > 1 ? parts[1] : 0,
          );
          if (now.isAfter(shiftEndForBlock)) {
            SnackBarUtils.showSnackBar(
              context,
              'Check-in not allowed after shift end time ($shiftEndStrForBlock).',
              isError: true,
            );
            return false;
          }
        } catch (_) {}
      }
    }

    String? alertMessage;
    bool shouldBlock = false;
    await _fetchFineCalculation();
    final netPerDaySalary = await _loadPerDaySalaryFromPrefs();
    if (kDebugMode) {
      debugPrint(
        '[Fine TEST][Dashboard Punch] Refreshed fine rules before alert/fine evaluation',
      );
      debugPrint(
        '[Fine TEST][Dashboard Punch] Loaded netPerDaySalary='
        '${netPerDaySalary?.toStringAsFixed(2) ?? "null"}',
      );
    }
    final allowLateEntry =
        tmpl['allowLateEntry'] ?? tmpl['lateEntryAllowed'] ?? true;
    final allowEarlyExit =
        tmpl['allowEarlyExit'] ?? tmpl['earlyExitAllowed'] ?? true;
    if (!isCheckedIn) {
      if (_templateIsOpenShift(tmpl)) {
        // Flexible clock-in: no late-entry alert or block.
      } else {
        final sessionTimings = _getWorkingSessionTimings(
          attendanceData,
          halfDayLeave,
          tmpl,
        );
        final shiftStartStr =
            sessionTimings?['startTime'] ?? _getShiftStartTimeFromDb(tmpl);
        if (shiftStartStr == null && allowLateEntry == false) {
          alertMessage = 'Shift start time not set. Contact HR.';
          shouldBlock = true;
        } else if (shiftStartStr != null) {
          try {
            final parts = shiftStartStr.split(':').map(int.parse).toList();
            final gracePeriod = _getGracePeriodMinutesForLateCheckIn(
              attendanceData,
              halfDayLeave,
              tmpl,
            );
            final shiftStartOnly = DateTime(
              now.year,
              now.month,
              now.day,
              parts[0],
              parts.length > 1 ? parts[1] : 0,
            );
            final graceEnd = shiftStartOnly.add(Duration(minutes: gracePeriod));
            if (now.isAfter(graceEnd)) {
              final shiftEndForFine =
                  sessionTimings?['endTime'] ??
                  _getShiftEndTimeFromDb(tmpl) ??
                  '18:30';
              final fineResult = calculateFine(
                punchInTime: now,
                attendanceDate: DateTime(now.year, now.month, now.day),
                shiftTiming: ShiftTiming(
                  name: 'Current Shift',
                  startTime: shiftStartStr,
                  endTime: shiftEndForFine,
                  graceTime: GraceTime(value: gracePeriod, unit: 'minutes'),
                ),
                fineSettings: FineSettings(
                  enabled: true,
                  graceTimeMinutes: gracePeriod,
                  calculationType: 'shiftBased',
                ),
                dailySalary: netPerDaySalary,
              );
              final shiftHoursForFormula = calculateShiftHours(
                shiftStartStr,
                shiftEndForFine,
              );
              final permissionApplyTo =
                  (tmpl['permissionPolicy'] is Map<String, dynamic>)
                  ? (tmpl['permissionPolicy']['applyTo']?.toString())
                  : null;
              final permissionAdjustment = await _getPermissionAdjustment(
                day: DateTime(now.year, now.month, now.day),
                lateMinutes: fineResult.lateMinutes,
                earlyMinutes: 0,
                isOpenShift: false,
                isCheckout: false,
                applyTo: permissionApplyTo,
              );
              final adjustedLateMinutes =
                  (fineResult.lateMinutes -
                          (permissionAdjustment['consumeLate'] ?? 0))
                      .clamp(0, 1000000);
              final lateRule = _matchFineRuleForAction('lateArrival');
              double lateFineAmount = fineResult.fineAmount;
              if (_hasFineRules()) {
                if (lateRule == null) {
                  lateFineAmount = 0.0;
                } else {
                  lateFineAmount = _computeFineFromRule(
                    rule: lateRule,
                    minutes: adjustedLateMinutes,
                    netPerDaySalary: netPerDaySalary ?? 0.0,
                    shiftHours: shiftHoursForFormula,
                  );
                }
              } else {
                lateFineAmount =
                    ((netPerDaySalary ?? 0) > 0 && shiftHoursForFormula > 0)
                    ? (((netPerDaySalary! / shiftHoursForFormula) *
                                  (adjustedLateMinutes / 60) *
                                  100)
                              .round() /
                          100)
                    : 0.0;
              }
              if (kDebugMode) {
                final fineLog = _resolveFineLogForAction('lateArrival');
                debugPrint(
                  '[Fine TEST][Dashboard Punch][LateIn] start=$shiftStartStr '
                  'graceMin=$gracePeriod lateMin=$adjustedLateMinutes '
                  'netPerDay=${netPerDaySalary?.toStringAsFixed(2) ?? "null"} '
                  'fineType=${fineLog['fineType']} '
                  'ruleType=${fineLog['ruleType']} '
                  'ruleApplyTo=${fineLog['ruleApplyTo']} '
                  'fine=${lateFineAmount.toStringAsFixed(2)} '
                  'allowLate=$allowLateEntry',
                );
                String fineFormula;
                String fineFormulaWords;
                final ruleTypeLower = (lateRule?['type']?.toString() ?? '')
                    .toLowerCase();
                if (_hasFineRules() &&
                    lateRule != null &&
                    ruleTypeLower == 'custom') {
                  final customAmount =
                      (lateRule['customAmount'] as num?)?.toDouble() ?? 0.0;
                  final unitLower =
                      (lateRule['customAmountUnit']?.toString() ?? 'perHour')
                          .toLowerCase();
                  if (unitLower == 'perminute') {
                    fineFormula =
                        '${customAmount.toStringAsFixed(2)} × ${fineResult.lateMinutes}';
                    fineFormulaWords =
                        'perDaySalary=${netPerDaySalary?.toStringAsFixed(2) ?? "0.00"}; '
                        'customAmount perMinute × lateMinutes';
                  } else if (unitLower == 'perhour') {
                    fineFormula =
                        '${customAmount.toStringAsFixed(2)} × (${fineResult.lateMinutes} / 60)';
                    fineFormulaWords =
                        'perDaySalary=${netPerDaySalary?.toStringAsFixed(2) ?? "0.00"}; '
                        'customAmount perHour × (lateMinutes/60)';
                  } else {
                    fineFormula = '${customAmount.toStringAsFixed(2)} (fixed)';
                    fineFormulaWords =
                        'perDaySalary=${netPerDaySalary?.toStringAsFixed(2) ?? "0.00"}; '
                        'customAmount fixed';
                  }
                } else {
                  fineFormula =
                      '(${netPerDaySalary?.toStringAsFixed(2) ?? "0.00"} / ${shiftHoursForFormula.toStringAsFixed(2)}) '
                      '* (${fineResult.lateMinutes} / 60)';
                  fineFormulaWords =
                      'perDaySalary/shiftHours × (lateMinutes/60)';
                }
                debugPrint(
                  '[Fine FORMULA][Dashboard Punch][LateIn] '
                  'fineType=${fineLog['fineType']} '
                  'ruleType=${fineLog['ruleType']} '
                  'ruleApplyTo=${fineLog['ruleApplyTo']} '
                  'fineFormula=$fineFormula '
                  '= fineAmount:${lateFineAmount.toStringAsFixed(2)} '
                  'fineFormulaWords=$fineFormulaWords',
                );
              }
              final baseMessage = allowLateEntry == false
                  ? 'Late entry is not allowed for your shift.'
                  : 'You are checking in late.';
              alertMessage = _buildLateAlertMessage(
                baseMessage: baseMessage,
                lateMinutes: adjustedLateMinutes,
                fineAmount: lateFineAmount,
              );
              shouldBlock = allowLateEntry == false;
            }
          } catch (_) {}
        }
      }
    }
    if (isCheckedIn && alertMessage == null) {
      if (_templateIsOpenShift(tmpl)) {
        final punchInRaw = attendanceData?['punchIn'];
        if (punchInRaw != null) {
          try {
            final punchIn = DateTime.parse(punchInRaw.toString()).toLocal();
            final reqH = _templateOpenRequiredHours(tmpl);
            final requiredMin = (reqH * 60).round();
            final workedMin = now.difference(punchIn).inMinutes;
            final earlyMinutes = workedMin >= requiredMin
                ? 0
                : (requiredMin - workedMin);
            if (earlyMinutes > 0) {
              final permissionApplyTo =
                  (tmpl['permissionPolicy'] is Map<String, dynamic>)
                  ? (tmpl['permissionPolicy']['applyTo']?.toString())
                  : null;
              final permissionAdjustment = await _getPermissionAdjustment(
                day: DateTime(now.year, now.month, now.day),
                lateMinutes: 0,
                earlyMinutes: earlyMinutes,
                isOpenShift: true,
                isCheckout: true,
                applyTo: permissionApplyTo,
              );
              final adjustedEarlyMinutes =
                  (earlyMinutes - (permissionAdjustment['consumeEarly'] ?? 0))
                      .clamp(0, 1000000);
              double estimatedFine = 0;
              if (netPerDaySalary != null && netPerDaySalary > 0 && reqH > 0) {
                estimatedFine =
                    ((netPerDaySalary / reqH) *
                            (adjustedEarlyMinutes / 60) *
                            100)
                        .round() /
                    100;
              }
              final earlyRule = _matchFineRuleForAction('earlyExit');
              double earlyFineAmount = estimatedFine;
              if (_hasFineRules()) {
                if (earlyRule == null) {
                  earlyFineAmount = 0.0;
                } else {
                  earlyFineAmount = _computeFineFromRule(
                    rule: earlyRule,
                    minutes: adjustedEarlyMinutes,
                    netPerDaySalary: netPerDaySalary ?? 0.0,
                    shiftHours: reqH,
                  );
                }
              }
              if (kDebugMode) {
                debugPrint(
                  '[Fine TEST][Dashboard Punch][EarlyOut][open] '
                  'requiredH=$reqH earlyMin=$adjustedEarlyMinutes '
                  'fine=${earlyFineAmount.toStringAsFixed(2)}',
                );
              }
              final baseMessage = allowEarlyExit == false
                  ? 'Early check-out: you have not completed your required ${reqH == reqH.roundToDouble() ? reqH.toInt() : reqH} hour(s) for today.'
                  : 'You are checking out before completing your required hours.';
              alertMessage = _buildEarlyAlertMessage(
                baseMessage: baseMessage,
                earlyMinutes: adjustedEarlyMinutes,
                fineAmount: earlyFineAmount,
              );
              shouldBlock = allowEarlyExit == false;
            }
          } catch (_) {}
        }
      } else {
        final sessionTimings = _getWorkingSessionTimings(
          attendanceData,
          halfDayLeave,
          tmpl,
        );
        final shiftEndStr =
            sessionTimings?['endTime'] ?? _getShiftEndTimeFromDb(tmpl);
        if (shiftEndStr == null && allowEarlyExit == false) {
          alertMessage = 'Shift end time not set. Contact HR.';
          shouldBlock = true;
        } else if (shiftEndStr != null) {
          try {
            final parts = shiftEndStr.split(':').map(int.parse).toList();
            final shiftEnd = DateTime(
              now.year,
              now.month,
              now.day,
              parts[0],
              parts.length > 1 ? parts[1] : 0,
            );
            if (now.isBefore(shiftEnd)) {
              final shiftStartForFine =
                  sessionTimings?['startTime'] ??
                  _getShiftStartTimeFromDb(tmpl) ??
                  '09:30';
              final rawEarlyMinutes = shiftEnd.difference(now).inMinutes;
              final earlyMinutes = rawEarlyMinutes;
              double estimatedFine = 0;
              if (netPerDaySalary != null &&
                  netPerDaySalary > 0 &&
                  earlyMinutes > 0) {
                final shiftHours = calculateShiftHours(
                  shiftStartForFine,
                  shiftEndStr,
                );
                if (shiftHours > 0) {
                  estimatedFine =
                      ((netPerDaySalary / shiftHours) *
                              (earlyMinutes / 60) *
                              100)
                          .round() /
                      100;
                }
              }
              final shiftHoursForFormula = calculateShiftHours(
                shiftStartForFine,
                shiftEndStr,
              );
              final earlyRule = _matchFineRuleForAction('earlyExit');
              final permissionApplyTo =
                  (tmpl['permissionPolicy'] is Map<String, dynamic>)
                  ? (tmpl['permissionPolicy']['applyTo']?.toString())
                  : null;
              final permissionAdjustment = await _getPermissionAdjustment(
                day: DateTime(now.year, now.month, now.day),
                lateMinutes: 0,
                earlyMinutes: earlyMinutes,
                isOpenShift: false,
                isCheckout: true,
                applyTo: permissionApplyTo,
              );
              final adjustedEarlyMinutes =
                  (earlyMinutes - (permissionAdjustment['consumeEarly'] ?? 0))
                      .clamp(0, 1000000);
              double earlyFineAmount = estimatedFine;
              if (_hasFineRules()) {
                if (earlyRule == null) {
                  earlyFineAmount = 0.0;
                } else {
                  earlyFineAmount = _computeFineFromRule(
                    rule: earlyRule,
                    minutes: adjustedEarlyMinutes,
                    netPerDaySalary: netPerDaySalary ?? 0.0,
                    shiftHours: shiftHoursForFormula,
                  );
                }
              } else {
                earlyFineAmount =
                    ((netPerDaySalary ?? 0) > 0 && shiftHoursForFormula > 0)
                    ? (((netPerDaySalary! / shiftHoursForFormula) *
                                  (adjustedEarlyMinutes / 60) *
                                  100)
                              .round() /
                          100)
                    : 0.0;
              }
              if (kDebugMode) {
                final fineLog = _resolveFineLogForAction('earlyExit');
                debugPrint(
                  '[Fine TEST][Dashboard Punch][EarlyOut] start=$shiftStartForFine '
                  'end=$shiftEndStr earlyMin=$adjustedEarlyMinutes '
                  'rawEarlyMin=$rawEarlyMinutes '
                  'consumeEarly=${permissionAdjustment['consumeEarly'] ?? 0} '
                  'now=${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')} '
                  'netPerDay=${netPerDaySalary?.toStringAsFixed(2) ?? "null"} '
                  'fineType=${fineLog['fineType']} '
                  'ruleType=${fineLog['ruleType']} '
                  'ruleApplyTo=${fineLog['ruleApplyTo']} '
                  'fine=${earlyFineAmount.toStringAsFixed(2)} '
                  'allowEarly=$allowEarlyExit',
                );
                String fineFormula;
                String fineFormulaWords;
                final ruleTypeLower = (earlyRule?['type']?.toString() ?? '')
                    .toLowerCase();
                if (_hasFineRules() &&
                    earlyRule != null &&
                    ruleTypeLower == 'custom') {
                  final customAmount =
                      (earlyRule['customAmount'] as num?)?.toDouble() ?? 0.0;
                  final unitLower =
                      (earlyRule['customAmountUnit']?.toString() ?? 'perHour')
                          .toLowerCase();
                  if (unitLower == 'perminute') {
                    fineFormula =
                        '${customAmount.toStringAsFixed(2)} × $adjustedEarlyMinutes';
                    fineFormulaWords =
                        'perDaySalary=${netPerDaySalary?.toStringAsFixed(2) ?? "0.00"}; '
                        'customAmount perMinute × earlyMinutes';
                  } else if (unitLower == 'perhour') {
                    fineFormula =
                        '${customAmount.toStringAsFixed(2)} × ($adjustedEarlyMinutes / 60)';
                    fineFormulaWords =
                        'perDaySalary=${netPerDaySalary?.toStringAsFixed(2) ?? "0.00"}; '
                        'customAmount perHour × (earlyMinutes/60)';
                  } else {
                    fineFormula = '${customAmount.toStringAsFixed(2)} (fixed)';
                    fineFormulaWords =
                        'perDaySalary=${netPerDaySalary?.toStringAsFixed(2) ?? "0.00"}; '
                        'customAmount fixed';
                  }
                } else {
                  fineFormula =
                      '(${netPerDaySalary?.toStringAsFixed(2) ?? "0.00"} / ${shiftHoursForFormula.toStringAsFixed(2)}) '
                      '* ($adjustedEarlyMinutes / 60)';
                  fineFormulaWords =
                      'perDaySalary/shiftHours × (earlyMinutes/60)';
                }
                debugPrint(
                  '[Fine FORMULA][Dashboard Punch][EarlyOut] '
                  'fineType=${fineLog['fineType']} '
                  'ruleType=${fineLog['ruleType']} '
                  'ruleApplyTo=${fineLog['ruleApplyTo']} '
                  'fineFormula=$fineFormula '
                  'fineFormulaWords=$fineFormulaWords '
                  '= fineAmount:${earlyFineAmount.toStringAsFixed(2)}',
                );
              }
              final baseMessage = allowEarlyExit == false
                  ? 'Early check-out is not allowed before shift end.'
                  : 'You are checking out early.';
              alertMessage = _buildEarlyAlertMessage(
                baseMessage: baseMessage,
                earlyMinutes: adjustedEarlyMinutes,
                fineAmount: earlyFineAmount,
              );
              shouldBlock = allowEarlyExit == false;
            }
          } catch (_) {}
        }
      }
    }
    if (alertMessage != null) {
      final lower = alertMessage.toLowerCase();
      final isLate = lower.contains('late');
      final isEarly = lower.contains('early');
      String? punchWarningShiftTiming;
      if (isLate || isEarly) {
        punchWarningShiftTiming = _shiftTimingSummaryForWarningDialog(
          attendanceData,
          halfDayLeave,
          tmpl,
        );
      }
      final proceedAfterWarning = await _showWarningAlertDialog(
        alertMessage,
        isLate: isLate,
        isEarly: isEarly,
        shiftTimingLine: punchWarningShiftTiming,
      );
      if (!mounted) return false;
      if (!proceedAfterWarning) return false;
      if (shouldBlock) return false;
    }
    return true;
  }

  Future<void> _submitAttendanceFromFile(
    BuildContext context,
    File file, {
    Position? position,
    String? address,
    String? area,
    String? city,
    String? pincode,

    /// When set (e.g. from pre-camera validation), skips an extra GET /attendance/today
    /// inside submit — faster and avoids redundant network during face/API steps.
    bool? precomputedIsCheckedIn,
  }) async {
    final result = await FaceDetectionHelper.detectFromFile(file);
    if (!mounted) return;
    if (!result.valid) {
      _isSubmittingFromFingerprint = false;
      _setPunchActionInProgress(false);
      Navigator.of(context).pop();
      SnackBarUtils.showSnackBar(
        context,
        result.message ?? 'Please take a selfie with exactly one face visible.',
        isError: true,
      );
      return;
    }

    // Use pre-fetched location if provided; otherwise fetch now
    Position? usePosition = position;
    String useAddress = address ?? '';
    String? useArea = area;
    String? useCity = city;
    String? usePincode = pincode;
    if (usePosition == null && address == null) {
      final loc = await _getCurrentLocation();
      usePosition = loc.position;
      useAddress = loc.address;
      useArea = loc.area;
      useCity = loc.city;
      usePincode = loc.pincode;
    }

    final stored = await AttendanceTemplateStore.loadTemplateDetails();
    final template = stored != null && stored['template'] != null
        ? (stored['template'] is Map<String, dynamic>
              ? stored['template'] as Map<String, dynamic>
              : Map<String, dynamic>.from(stored['template'] as Map))
        : null;
    final requireSelfie = template?['requireSelfie'] ?? true;
    final requireGeolocation = template?['requireGeolocation'] ?? true;
    punchFlowLog(
      '[Dashboard][TemplateFlags][submit-from-file] requireSelfie=$requireSelfie requireGeolocation=$requireGeolocation templateName=${template?['name'] ?? template?['title'] ?? 'unknown'}',
    );
    if (requireGeolocation && usePosition == null) {
      if (mounted) {
        _isSubmittingFromFingerprint = false;
        _setPunchActionInProgress(false);
        Navigator.of(context).pop();
        SnackBarUtils.showSnackBar(
          context,
          'Could not get location.',
          isError: true,
        );
      }
      return;
    }

    final bool isCheckedIn;
    if (precomputedIsCheckedIn != null) {
      isCheckedIn = precomputedIsCheckedIn;
    } else {
      final todayRes = await _attendanceService.getTodayAttendance(
        forceRefresh: true,
      );
      final todayData = todayRes['data'] as Map<String, dynamic>?;
      isCheckedIn = _isAttendancePunchedIn(_extractAttendanceRecord(todayData));
    }

    List<int> imageBytes = await file.readAsBytes();
    String base64Image = base64Encode(imageBytes);
    final selfiePayload = 'data:image/jpeg;base64,$base64Image';

    if (AppConstants.enableAttendanceFaceMatching &&
        requireSelfie &&
        selfiePayload.isNotEmpty) {
      try {
        final verify = await _authService.verifyFace(selfiePayload);
        if (!mounted) return;
        if (verify['success'] != true || verify['match'] != true) {
          _isSubmittingFromFingerprint = false;
          _setPunchActionInProgress(false);
          Navigator.of(context).pop();
          SnackBarUtils.showSnackBar(
            context,
            ErrorMessageUtils.sanitizeForDisplay(
              verify['message']?.toString() ?? 'Face not matching.',
            ),
            isError: true,
          );
          return;
        }
      } catch (_) {
        if (mounted) {
          _isSubmittingFromFingerprint = false;
          _setPunchActionInProgress(false);
          Navigator.of(context).pop();
          SnackBarUtils.showSnackBar(
            context,
            'Face verification failed. Please try again.',
            isError: true,
          );
        }
        return;
      }
    }

    if (!mounted) return;
    final lat = usePosition?.latitude ?? 0.0;
    final lng = usePosition?.longitude ?? 0.0;
    final todayRes = await _attendanceService.getTodayAttendance(
      forceRefresh: true,
    );
    final todayData = todayRes['data'] as Map<String, dynamic>?;
    final attendanceData =
        flattenTodayAttendancePayload(todayData) ??
        _extractAttendanceRecord(todayData) ??
        todayData;
    final halfDayLeaveRaw = todayData?['halfDayLeave'];
    final Map<String, dynamic>? halfDayLeave = halfDayLeaveRaw is Map
        ? Map<String, dynamic>.from(halfDayLeaveRaw)
        : null;
    final Map<String, dynamic> effectiveTemplate;
    if (template != null) {
      effectiveTemplate = template;
    } else if (todayData?['template'] is Map) {
      effectiveTemplate = Map<String, dynamic>.from(
        todayData!['template'] as Map,
      );
    } else {
      effectiveTemplate = <String, dynamic>{};
    }
    final finePayload = await _buildFinePayloadForPunch(
      isCheckedIn: isCheckedIn,
      attendanceData: attendanceData,
      halfDayLeave: halfDayLeave,
      tmpl: effectiveTemplate,
    );
    if (isCheckedIn) {
      punchFlowLog(
        '[PunchFlow][submit] dispatch AttendanceCheckOutRequested '
        'late=${finePayload['lateMinutes']} early=${finePayload['earlyMinutes']} '
        'fine=${finePayload['fineAmount']}',
      );
      context.read<AttendanceBloc>().add(
        AttendanceCheckOutRequested(
          lat: lat,
          lng: lng,
          address: useAddress,
          area: useArea,
          city: useCity,
          pincode: usePincode,
          selfie: selfiePayload,
          lateMinutes: finePayload['lateMinutes'] as int?,
          earlyMinutes: finePayload['earlyMinutes'] as int?,
          fineAmount: finePayload['fineAmount'] as double?,
        ),
      );
    } else {
      punchFlowLog(
        '[PunchFlow][submit] dispatch AttendanceCheckInRequested '
        'late=${finePayload['lateMinutes']} early=${finePayload['earlyMinutes']}',
      );
      context.read<AttendanceBloc>().add(
        AttendanceCheckInRequested(
          lat: lat,
          lng: lng,
          address: useAddress,
          area: useArea,
          city: useCity,
          pincode: usePincode,
          selfie: selfiePayload,
          lateMinutes: finePayload['lateMinutes'] as int?,
          earlyMinutes: finePayload['earlyMinutes'] as int?,
          fineAmount: finePayload['fineAmount'] as double?,
        ),
      );
    }
  }

  /// Submits attendance without selfie (when template says `requireSelfie: false`).
  Future<void> _submitAttendanceWithoutSelfie(
    BuildContext context, {
    Position? position,
    String? address,
    String? area,
    String? city,
    String? pincode,

    /// When set, skips an extra GET /attendance/today inside submit.
    bool? precomputedIsCheckedIn,
  }) async {
    // Use pre-fetched location if provided; otherwise fetch now (only when needed).
    Position? usePosition = position;
    String useAddress = address ?? '';
    String? useArea = area;
    String? useCity = city;
    String? usePincode = pincode;

    final stored = await AttendanceTemplateStore.loadTemplateDetails();
    final template = stored != null && stored['template'] != null
        ? (stored['template'] is Map<String, dynamic>
              ? stored['template'] as Map<String, dynamic>
              : Map<String, dynamic>.from(stored['template'] as Map))
        : null;
    final requireSelfie = template?['requireSelfie'] ?? true;
    final requireGeolocation = template?['requireGeolocation'] ?? true;
    punchFlowLog(
      '[Dashboard][TemplateFlags][submit-no-selfie] requireSelfie=$requireSelfie requireGeolocation=$requireGeolocation templateName=${template?['name'] ?? template?['title'] ?? 'unknown'} precomputedPosition=${usePosition != null}',
    );

    if (requireGeolocation && usePosition == null && address == null) {
      final loc = await _getCurrentLocation();
      usePosition = loc.position;
      useAddress = loc.address;
      useArea = loc.area;
      useCity = loc.city;
      usePincode = loc.pincode;
    }

    if (requireGeolocation && usePosition == null) {
      if (mounted) {
        _isSubmittingFromFingerprint = false;
        _setPunchActionInProgress(false);
        Navigator.of(context).pop(); // Dismiss "Submitting attendance..."
        SnackBarUtils.showSnackBar(
          context,
          'Could not get location.',
          isError: true,
        );
      }
      return;
    }

    final bool isCheckedIn;
    if (precomputedIsCheckedIn != null) {
      isCheckedIn = precomputedIsCheckedIn;
    } else {
      final todayRes = await _attendanceService.getTodayAttendance(
        forceRefresh: true,
      );
      final todayData = todayRes['data'] as Map<String, dynamic>?;
      isCheckedIn = _isAttendancePunchedIn(_extractAttendanceRecord(todayData));
    }

    final lat = usePosition?.latitude ?? 0.0;
    final lng = usePosition?.longitude ?? 0.0;

    final todayRes = await _attendanceService.getTodayAttendance(
      forceRefresh: true,
    );
    final todayData = todayRes['data'] as Map<String, dynamic>?;
    final attendanceData =
        flattenTodayAttendancePayload(todayData) ??
        _extractAttendanceRecord(todayData) ??
        todayData;

    final halfDayLeaveRaw = todayData?['halfDayLeave'];
    final Map<String, dynamic>? halfDayLeave = halfDayLeaveRaw is Map
        ? Map<String, dynamic>.from(halfDayLeaveRaw)
        : null;

    final Map<String, dynamic> effectiveTemplate;
    if (template != null) {
      effectiveTemplate = template;
    } else if (todayData?['template'] is Map) {
      effectiveTemplate = Map<String, dynamic>.from(
        todayData!['template'] as Map,
      );
    } else {
      effectiveTemplate = <String, dynamic>{};
    }

    final finePayload = await _buildFinePayloadForPunch(
      isCheckedIn: isCheckedIn,
      attendanceData: attendanceData,
      halfDayLeave: halfDayLeave,
      tmpl: effectiveTemplate,
    );

    if (isCheckedIn) {
      context.read<AttendanceBloc>().add(
        AttendanceCheckOutRequested(
          lat: lat,
          lng: lng,
          address: useAddress,
          area: useArea,
          city: useCity,
          pincode: usePincode,
          selfie: null,
          lateMinutes: finePayload['lateMinutes'] as int?,
          earlyMinutes: finePayload['earlyMinutes'] as int?,
          fineAmount: finePayload['fineAmount'] as double?,
        ),
      );
    } else {
      context.read<AttendanceBloc>().add(
        AttendanceCheckInRequested(
          lat: lat,
          lng: lng,
          address: useAddress,
          area: useArea,
          city: useCity,
          pincode: usePincode,
          selfie: null,
          lateMinutes: finePayload['lateMinutes'] as int?,
          earlyMinutes: finePayload['earlyMinutes'] as int?,
          fineAmount: finePayload['fineAmount'] as double?,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> screens = [
      HomeDashboardScreen(
        onNavigate: _onDashboardNavigate,
        embeddedInDashboard: true,
        onNavigateToIndex: _onDrawerNavigateToIndex,
        dashboardTabIndex: _currentIndex,
        isActiveTab: _currentIndex == 0,
        refreshTrigger: _dashboardRefreshTrigger,
        onDashboardDataRefreshed: _onHomeDashboardDataRefreshed,
        hasSalaryOverviewAccess: _hasSalaryOverviewAccess,
      ),
      MyRequestsScreen(
        key: ValueKey('Requests_$_requestsSubTabIndex'),
        initialTabIndex: _requestsSubTabIndex,
        dashboardTabIndex: _currentIndex,
        onNavigateToIndex: _onDrawerNavigateToIndex,
        onTabIndexChanged: _onRequestsTabIndexChanged,
        isActiveTab: _currentIndex == 1,
      ),
      SalaryOverviewScreen(
        dashboardTabIndex: _currentIndex,
        onNavigateToIndex: _onDrawerNavigateToIndex,
        isActiveTab: _currentIndex == 2,
      ),
      HolidaysScreen(
        dashboardTabIndex: _currentIndex,
        onNavigateToIndex: _onDrawerNavigateToIndex,
      ),
      AttendanceScreen(
        key: ValueKey('Attendance_$_attendanceSubTabIndex'),
        initialTabIndex: _attendanceSubTabIndex,
        dashboardTabIndex: _currentIndex,
        onNavigateToIndex: _onDrawerNavigateToIndex,
        isActiveTab: _currentIndex == 4,
      ),
    ];

    return BlocListener<AttendanceBloc, AttendanceState>(
      listener: (context, state) async {
        punchFlowLog(
          '[PunchFlow][BlocListener] state=${state.runtimeType} '
          'fingerprintSubmit=$_isSubmittingFromFingerprint index=$_currentIndex',
        );
        if (state is AttendanceCheckInSuccess) {
          // Only bottom-nav punch uses this flag; Attendance tab / SelfieCheckIn show their own overlay.
          final showNavPunchSuccessOverlay =
              _isSubmittingFromFingerprint && _currentIndex != 4;
          // Dismiss loading immediately; presence + nav refresh run in background (they were blocking the dialog for several seconds).
          if (mounted) {
            if (_isSubmittingFromFingerprint) {
              _isSubmittingFromFingerprint = false;
              Navigator.of(context).pop();
            }
            _setPunchActionInProgress(false);
            setState(() {
              _isPunchedInToday = true;
              _isPunchCompletedToday = false;
            });
          }
          await _optimisticPunchInPrefs();
          _attendanceService.clearCachesForRefresh();
          unawaited(_fetchPunchStatusForNavBar());
          _dashboardRefreshTrigger.value++;
          final pinLat = state.checkInLat;
          final pinLng = state.checkInLng;
          unawaited(() async {
            try {
              if (pinLat != null && pinLng != null) {
                await PresenceTrackingService().pinOfficeZoneAtCheckIn(
                  pinLat,
                  pinLng,
                );
              }
              await PresenceTrackingService().ensureTrackingIfPunchedIn(true);
            } catch (e, st) {
              if (kDebugMode) {
                debugPrint('[Dashboard] presence after check-in: $e $st');
              }
            }
          }());
          if (mounted && showNavPunchSuccessOverlay) {
            final userName = await _authService.getCurrentUserName();
            if (!mounted) return;
            await AttendanceSuccessOverlay.show(
              context,
              isCheckIn: true,
              userName: userName,
            );
          }
        } else if (state is AttendanceCheckOutSuccess) {
          final showNavPunchSuccessOverlay =
              _isSubmittingFromFingerprint && _currentIndex != 4;
          if (mounted) {
            if (_isSubmittingFromFingerprint) {
              _isSubmittingFromFingerprint = false;
              Navigator.of(context).pop();
            }
            _setPunchActionInProgress(false);
            setState(() {
              _isPunchedInToday = false;
              _isPunchCompletedToday = true;
            });
          }
          await _optimisticPunchOutPrefs();
          _attendanceService.clearCachesForRefresh();
          unawaited(_fetchPunchStatusForNavBar());
          _dashboardRefreshTrigger.value++;
          unawaited(
            PresenceTrackingService().stopTracking().catchError((
              Object e,
              StackTrace st,
            ) {
              if (kDebugMode) {
                debugPrint('[Dashboard] stopTracking after check-out: $e');
              }
            }),
          );
          if (mounted && showNavPunchSuccessOverlay) {
            final userName = await _authService.getCurrentUserName();
            if (!mounted) return;
            await AttendanceSuccessOverlay.show(
              context,
              isCheckIn: false,
              userName: userName,
            );
          }
        } else if (state is AttendanceFailure && _isSubmittingFromFingerprint) {
          punchFlowLog(
            '[PunchFlow][BlocListener] AttendanceFailure (nav punch) msg=${state.message}',
          );
          _setPunchActionInProgress(false);
          _isSubmittingFromFingerprint = false;
          if (mounted) Navigator.of(context).pop();
          if (mounted) {
            SnackBarUtils.showSnackBar(
              context,
              ErrorMessageUtils.sanitizeForDisplay(state.message),
              isError: true,
              debugSource: 'Dashboard.BlocListener.AttendanceFailure.navPunch',
            );
          }
        }
      },
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          if (_currentIndex != 0) {
            setState(() => _currentIndex = 0);
          } else {
            // Dashboard is the root route (pushReplacement from splash/login).
            // Popping would leave empty stack = black screen. Exit app instead.
            SystemNavigator.pop();
          }
        },
        child: Scaffold(
          body: IndexedStack(
            index: _currentIndex.clamp(0, screens.length - 1),
            children: screens,
          ),
          bottomNavigationBar: AppBottomNavigationBar(
            currentIndex: _bottomBarSelectedIndex(),
            items: _buildBottomNavItems(),
            isPunchedInToday: _isPunchedInToday,
            isPunchCompletedToday: _isPunchCompletedToday,
            isPunchActionInProgress: _isPunchActionInProgress,
            isBreakActive: _activeBreak != null,
            isBreakActionInProgress: _isBreakActionInProgress,
            activeBreakStartTime: _activeBreakStartTime(),
            onEndBreakTap: _endBreakFlow,
            showBreakNavButton: _showBreakNavForShiftPolicy,
            onTap: (index) async {
              if (index == 6) {
                if (_activeBreak != null) {
                  SnackBarUtils.showSnackBar(
                    context,
                    'You are already on break. Use End Break above the bottom bar.',
                    isError: true,
                  );
                  return;
                }
                await _startBreakFlow();
                return;
              }
              if (index == 5) {
                if (_isPunchActionInProgress) return;
                final punchFlowSw = Stopwatch()..start();
                punchFlowLog('[PunchFlow] tap received');
                _setPunchActionInProgress(true);
                // Same validations as attendance screen before check-in/check-out
                final validationData = await _fetchAttendanceValidationData();
                punchFlowLog(
                  '[PunchFlow] validation finished in ${punchFlowSw.elapsedMilliseconds}ms | '
                  'ok=${validationData != null}',
                );
                if (!mounted) return;
                if (validationData == null) {
                  _setPunchActionInProgress(false);
                  SnackBarUtils.showSnackBar(
                    context,
                    'Unable to load attendance details. Try again.',
                    isError: true,
                  );
                  return;
                }
                final canProceed = await _runFingerprintAttendanceValidations(
                  validationData,
                );
                punchFlowLog(
                  '[PunchFlow] business validations finished in ${punchFlowSw.elapsedMilliseconds}ms | '
                  'canProceed=$canProceed',
                );
                if (!mounted) return;
                if (!canProceed) {
                  _setPunchActionInProgress(false);
                  return;
                }

                final stored =
                    await AttendanceTemplateStore.loadTemplateDetails();
                final template = stored != null && stored['template'] != null
                    ? (stored['template'] is Map<String, dynamic>
                          ? stored['template'] as Map<String, dynamic>
                          : Map<String, dynamic>.from(
                              stored['template'] as Map,
                            ))
                    : null;
                final requireSelfie = template?['requireSelfie'] ?? true;
                final requireGeolocation =
                    template?['requireGeolocation'] ?? true;
                punchFlowLog(
                  '[Dashboard][TemplateFlags][punch] requireSelfie=$requireSelfie requireGeolocation=$requireGeolocation templateName=${template?['name'] ?? template?['title'] ?? 'unknown'}',
                );

                Position? position;
                String useAddress = '';
                String? useArea;
                String? useCity;
                String? usePincode;

                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (ctx) => const AlertDialog(
                    content: Row(
                      children: [
                        SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 16),
                        Text('Getting location…'),
                      ],
                    ),
                  ),
                );
                final location = await _getCurrentLocation();
                punchFlowLog(
                  '[PunchFlow] location resolved in ${punchFlowSw.elapsedMilliseconds}ms | '
                  'hasPosition=${location.position != null}',
                );
                if (!mounted) return;
                Navigator.of(context).pop(); // Dismiss "Getting location..."

                if (location.position == null) {
                  _setPunchActionInProgress(false);
                  SnackBarUtils.showSnackBar(
                    context,
                    'Location is required. Please enable location and try again.',
                    isError: true,
                  );
                  return;
                }

                position = location.position;
                useAddress = location.address;
                useArea = location.area;
                useCity = location.city;
                usePincode = location.pincode;

                final locationStr = useAddress.isNotEmpty
                    ? useAddress
                    : (useArea != null
                          ? '$useArea, ${useCity ?? ''}${usePincode != null ? ' $usePincode' : ''}'
                          : null);

                File? file;
                if (requireSelfie) {
                  final result = await SelfieCameraScreen.captureSelfie(
                    context,
                    location: locationStr,
                    onRefreshLocation: () async {
                      final loc = await _getCurrentLocation();
                      return loc.address.isNotEmpty
                          ? loc.address
                          : (loc.area != null
                                ? '${loc.area}, ${loc.city ?? ''}${loc.pincode != null ? ' ${loc.pincode}' : ''}'
                                : null);
                    },
                  );
                  if (!mounted) return;
                  punchFlowLog(
                    '[PunchFlow] selfie capture finished in ${punchFlowSw.elapsedMilliseconds}ms | '
                    'hasFile=${result is File}',
                  );

                  if (result is File) {
                    file = result;
                  } else if (identical(result, useImagePickerFallback)) {
                    _setPunchActionInProgress(false);
                    SnackBarUtils.showSnackBar(
                      context,
                      'Camera unavailable. Try again from Attendance.',
                      isError: true,
                    );
                    return;
                  }

                  if (file == null) {
                    _setPunchActionInProgress(false);
                    return; // Cancelled
                  }
                }

                _isSubmittingFromFingerprint = true;
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (ctx) => const AlertDialog(
                    content: Row(
                      children: [
                        SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 16),
                        Text('Submitting attendance…'),
                      ],
                    ),
                  ),
                );
                final attendanceMap =
                    validationData['attendanceData'] as Map<String, dynamic>?;
                final precomputedIsCheckedIn = _isAttendancePunchedIn(
                  attendanceMap,
                );

                if (requireSelfie) {
                  await _submitAttendanceFromFile(
                    context,
                    file!,
                    position: position,
                    address: useAddress,
                    area: useArea,
                    city: useCity,
                    pincode: usePincode,
                    precomputedIsCheckedIn: precomputedIsCheckedIn,
                  );
                } else {
                  await _submitAttendanceWithoutSelfie(
                    context,
                    position: position,
                    address: useAddress,
                    area: useArea,
                    city: useCity,
                    pincode: usePincode,
                    precomputedIsCheckedIn: precomputedIsCheckedIn,
                  );
                }
                punchFlowLog(
                  '[PunchFlow] submit finished in ${punchFlowSw.elapsedMilliseconds}ms',
                );
                return;
              }
              final normalized = _mapBottomNavIndexToScreenIndex(index);
              setState(() => _currentIndex = normalized);
              unawaited(_fetchPunchStatusForNavBar());
            },
          ),
        ),
      ),
    );
  }
}
