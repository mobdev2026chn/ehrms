import 'dart:async';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:table_calendar/table_calendar.dart';
import '../../config/app_colors.dart';
import '../../config/app_text_styles.dart';
import '../../config/constants.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/menu_icon_button.dart';
import '../../services/attendance_service.dart';
import '../../services/auth_service.dart';
import '../../services/break_service.dart';
import '../../services/attendance_template_store.dart';
import '../../services/geo/address_resolution_service.dart';
import '../../services/geo/accurate_location_helper.dart';
import '../../services/presence_tracking_service.dart';
import '../../utils/attendance_display_util.dart';
import '../../utils/attendance_selfie_compress.dart';
import '../../utils/attendance_template_util.dart';
import '../../utils/face_detection_helper.dart';
import '../../bloc/attendance/attendance_bloc.dart';
import 'selfie_camera_screen.dart';
import '../../utils/snackbar_utils.dart';
import '../../utils/error_message_utils.dart';
import '../../utils/absent_alert_helper.dart';
import '../../utils/fine_calculation_util.dart';
import '../../services/salary_service.dart';
import '../../services/settings_service.dart';
import '../../utils/rotational_shift_util.dart';
import '../../widgets/app_tab_loader.dart';
import '../../widgets/attendance_success_overlay.dart';
import '../../widgets/notification_reaction_overlay.dart';
import '../../widgets/walking_turtle_emoji.dart';

class AttendanceScreen extends StatefulWidget {
  final int initialTabIndex;
  final int? dashboardTabIndex;
  final void Function(int index)? onNavigateToIndex;

  /// When true, this screen is the active tab (e.g. user switched to Attendance). Used to refresh once on open.
  final bool? isActiveTab;

  const AttendanceScreen({
    super.key,
    this.initialTabIndex = 0,
    this.dashboardTabIndex,
    this.onNavigateToIndex,
    this.isActiveTab,
  });

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen>
    with SingleTickerProviderStateMixin {
  static const Duration _networkTimeout = Duration(seconds: 45);
  static const Duration _businessLookupCacheDuration = Duration(minutes: 5);
  Map<String, dynamic>? _attendanceData;

  /// Date we last fetched attendance status for (ensures selected-date card shows correct date)
  DateTime? _attendanceDataFetchedFor;
  final AttendanceService _attendanceService = AttendanceService();
  final AuthService _authService = AuthService();
  final BreakService _breakService = BreakService();
  final SettingsService _settingsService = SettingsService();

  /// Full business from `GET /settings/business` (fallback when API omits embedded list).
  Map<String, dynamic>? _businessDocForShifts;
  DateTime? _lastBusinessLookupAt;

  /// From `GET /attendance/today` or month payload [businessShifts] — full company shift rows for [appliedShiftId].
  List<dynamic>? _embeddedBusinessShiftsFromApi;

  // History State
  List<dynamic> _historyList = [];
  int _page = 1;
  int _totalPages = 1;
  int _totalRecords = 0;
  bool _isLoadingHistory = false;
  final int _limit = 10;

  /// Recent activity: always today + last 5 days. Not affected by History tab month change.
  List<dynamic> _recentActivityList = [];

  // Calendar State
  Map<String, dynamic>? _monthData;
  DateTime _selectedDay = DateTime.now();
  DateTime _focusedDay = DateTime.now();
  // TableCalendar's internal PageView controller (from onCalendarCreated). Used to
  // snap the visible page back to _focusedDay when TableCalendar drifts to an
  // adjacent month on first build — otherwise the grid shows an empty month under
  // the (correct) _focusedDay header while the loaded data sits on an off-screen page.
  PageController? _calendarPageController;
  bool _isLoadingMonthData =
      false; // True until month data for History is loaded
  bool _monthRetryScheduled =
      false; // Guards the one-shot auto-retry after a failed month fetch
  int _monthRetryAttempts =
      0; // Bounded auto-retry count for the currently-focused month
  String?
      _monthRetryKey; // 'year-month' the retry budget above belongs to (resets per month)
  String?
      _monthLoadError; // Last month-fetch failure reason, surfaced in the calendar strip for diagnosis

  // Precomputed maps/sets for calendar coloring (mirrors dashboard calendar)
  final Map<String, String> _dayStatusByDate = {};
  final Map<String, String?> _dayLeaveTypeByDate = {};
  final Map<String, bool> _dayIsPaidLeaveByDate = {};
  final Map<String, String> _dayCompensationTypeByDate = {};
  final Map<String, num?> _dayWorkHoursByDate = {};
  final Set<String> _holidayDateSet = {};
  // Holiday name (e.g. "Pongal", "Christmas") keyed by yyyy-MM-dd. Kept even when a
  // holiday overlaps a week-off so the holiday name can still be surfaced on that date.
  final Map<String, String> _holidayNameByDate = {};
  final Set<String> _weekOffDateSet = {};
  final Set<String> _alternateWorkDatesInMonth = {};
  final Set<String> _presentDateSet = {};
  final Set<String> _absentDateSet = {};
  final Set<String> _leaveDateSet = {};
  final Set<String> _pendingWithCheckInDateSet =
      {}; // Pending + has punchIn → WA

  String _activeFilter = 'All'; // Filter for history list
  bool _showHistoryView =
      false; // true = History screen, false = Mark Attendance

  // Template & Rule State
  Map<String, dynamic>? _attendanceTemplate;

  /// Branch data from /attendance/today (status, geofence) for check-in/out validation.
  Map<String, dynamic>? _branchData;
  bool _attendanceStatusFetched =
      false; // true only after first fetch completes (avoids flashing "not mapped")
  bool?
  _staffHasAttendanceTemplate; // from profile + /attendance/today (null = not yet checked)
  /// Latest `staffData.attendanceTemplateId` from profile (for merging with today's API template).
  dynamic _profileAttendanceTemplateId;

  String? _profileStaffShiftName;
  Map<String, dynamic>? _profileStaffDataSnapshot;
  bool _retryingTemplateFetch = false; // avoid infinite retry
  bool _isOnLeave = false;
  String? _leaveMessage;
  Map<String, dynamic>? _halfDayLeave;
  bool _checkInAllowed = true;
  bool _checkOutAllowed = true;
  bool _shiftAssigned = true;
  bool _isHoliday = false;
  bool _isWeeklyOff = false;
  bool _isAlternateWorkDate = false;
  bool _isCompensationWeekOff = false;
  bool _isCompensationCompOff = false;
  bool _isPaidLeaveToday = false;
  Map<String, dynamic>? _holidayInfo;
  String? _weeklyOffPattern;
  bool? _checkedInFromApi;

  /// True when submitting from camera-direct flow; used to pop dialog on bloc success.
  bool _isSubmittingFromAttendanceCamera = false;
  bool _isPunchActionInProgress = false;
  String? _punchActionStatusMessage;

  /// True while fetching template details on open.
  bool _isFetchingTemplateDetails = false;
  bool _hasInitializedActiveData = false;

  /// Company fine calculation (company.settings.payroll.fineCalculation) fetched by staff's businessId.
  Map<String, dynamic>? _fineCalculation;

  /// ScrollController for the horizontal date strip (strip hidden; kept for dispose).
  final ScrollController _dateStripScrollController = ScrollController();

  void _setPunchActionInProgress(bool value, {String? message}) {
    if (!mounted) return;
    final nextMessage = value ? (message ?? _punchActionStatusMessage) : null;
    if (_isPunchActionInProgress == value &&
        _punchActionStatusMessage == nextMessage) {
      return;
    }
    setState(() {
      _isPunchActionInProgress = value;
      _punchActionStatusMessage = nextMessage;
    });
  }

  Future<void> _runPostPunchSuccessTasks(
    bool isCheckedIn, {
    double? checkInLat,
    double? checkInLng,
  }) async {
    try {
      if (isCheckedIn && checkInLat != null && checkInLng != null) {
        await PresenceTrackingService().pinOfficeZoneAtCheckIn(
          checkInLat,
          checkInLng,
        );
      }
      await PresenceTrackingService().ensureTrackingIfPunchedIn(isCheckedIn);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[Attendance] post-punch tracking sync failed: $e');
      }
    }
    if (!mounted) return;
    _attendanceService.clearCachesForRefresh();
    unawaited(_refreshData(forceRefresh: true));
  }

  bool _hasPunchValue(Object? value) {
    final text = value?.toString().trim();
    return text != null && text.isNotEmpty && text.toLowerCase() != 'null';
  }

  /// Calendar flag and/or today's attendance row (e.g. web check-in with `isPaidLeave: true`, status Present).
  /// Half-day leave days are excluded: the web/admin backend stamps `isPaidLeave: true` on a
  /// half-day leave's attendance row, but the employee must still punch in/out for their working
  /// half. The dedicated half-day logic (checkInAllowed / checkOutAllowed + PRIORITY 1 card)
  /// governs those days, so this full-day paid-leave block must not pre-empt it.
  bool get _isPaidLeaveContext =>
      _halfDayLeave == null &&
      (_isPaidLeaveToday || _attendanceData?['isPaidLeave'] == true);

  @override
  void initState() {
    super.initState();
    debugPrint(
      '[Attendance][lifecycle] initState hashCode=$hashCode isActiveTab=${widget.isActiveTab}',
    );
    final now = DateTime.now();
    final todayOnly = DateTime(now.year, now.month, now.day);
    if (_focusedDay.isAfter(todayOnly)) {
      _focusedDay = todayOnly;
      _selectedDay = todayOnly;
    }
    if (_selectedDay.isAfter(todayOnly)) {
      _selectedDay = todayOnly;
    }
    // Attendance page should open directly in history view; punch in/out stays in bottom navbar.
    _showHistoryView = true;
    if (widget.isActiveTab == true) {
      _hasInitializedActiveData = true;
      _initData();
    }
  }

  @override
  void dispose() {
    debugPrint('[Attendance][lifecycle] dispose hashCode=$hashCode');
    _dateStripScrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(AttendanceScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // When user opens/switches to Attendance tab, load once. Do NOT force-refresh:
    // forcing bypassed the (now shared) month cache and re-fetched from scratch, so
    // the calendar sat blank for a few seconds on every open even though the
    // Dashboard had already loaded the same month. A non-forced load serves the
    // cached month instantly (5-min TTL); pull-to-refresh and post-punch still force
    // fresh data when it actually matters.
    if (widget.isActiveTab == true && oldWidget.isActiveTab != true) {
      if (_hasInitializedActiveData) {
        _refreshData();
      } else {
        _hasInitializedActiveData = true;
        _initData();
      }
    }
  }

  Future<void> _initData({bool forceRefresh = false}) async {
    if (!mounted) return;
    setState(() {
      // Do NOT wipe _monthData / _historyList here. The calendar coloring depends
      // only on month data (not template details), so we start its fetch in
      // parallel below and let it overwrite atomically when fresh data arrives.
      // Nulling up front used to blank the calendar behind a spinner for the
      // entire template round-trip.
      _isLoadingHistory = true;
      _isLoadingMonthData = true;
      _retryingTemplateFetch = false;
      _isFetchingTemplateDetails = true;
    });
    if (!mounted) return;

    // Calendar/history/fine data do not depend on the template details, so kick
    // them off immediately and run them concurrently with the template fetch.
    // Previously _fetchMonthData was gated behind _fetchAllTemplateDetails, so the
    // calendar couldn't start loading until profile + today-attendance + the
    // business-shift lookup all finished — first-open latency was the SUM of both.
    // Running them in parallel makes it the MAX instead, so the calendar paints
    // as soon as its own fetch returns.
    // Order matters: invoke the calendar/history fetches first so their
    // synchronous cache-check runs before _fetchAllTemplateDetails' top-of-body
    // clearCachesForRefresh(), preserving any instant cache hit.
    await Future.wait<void>([
      _fetchMonthData(
        _focusedDay.year,
        _focusedDay.month,
        forceRefresh: forceRefresh,
      ),
      _fetchHistory(refresh: true),
      _fetchFineCalculation(),
      // Fetch fresh template details on open (profile + today attendance).
      // No re-login needed when templates change; stored in SharedPrefs for
      // check-in alert/selfie.
      _fetchAllTemplateDetails().whenComplete(() {
        if (mounted) setState(() => _isFetchingTemplateDetails = false);
      }),
    ]);
  }

  Future<Map<String, dynamic>> _withTimeoutRetry(
    Future<Map<String, dynamic>> Function() action, {
    required String tag,
    int retries = 1,
  }) async {
    var attempt = 0;
    while (true) {
      attempt++;
      try {
        return await action().timeout(_networkTimeout);
      } on TimeoutException {
        if (attempt > retries) rethrow;
        if (kDebugMode) {
          debugPrint(
            '[Attendance] $tag timed out (attempt $attempt). Retrying...',
          );
        }
        await Future<void>.delayed(const Duration(milliseconds: 600));
      }
    }
  }

  /// Fetches profile + today attendance, saves template details to SharedPrefs.
  /// Ensures fresh shift, attendance template, branch, holiday info when templates change.
  Future<void> _fetchAllTemplateDetails() async {
    try {
      debugPrint('[Attendance] Fetching template details...');
      // Only the today/profile data needs to be fresh here. Preserve the month
      // cache (clearMonth: false) so the calendar can paint instantly from data
      // the Dashboard already loaded, instead of sitting blank while a fresh
      // month fetch runs on every tab open.
      _attendanceService.clearCachesForRefresh(clearMonth: false);
      // Profile and today attendance are independent network calls; fetch them
      // in parallel (was sequential) to save one round-trip on every open, then
      // process profile first since today's template flags depend on it.
      final todayStr =
          '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')}';
      debugPrint('[Attendance] Fetching profile + today attendance: $todayStr');
      final fetched = await Future.wait<Map<String, dynamic>>([
        // 1. Fresh profile (shift key snapshot for template reconciliation).
        _withTimeoutRetry(_authService.getProfile, tag: 'Profile fetch'),
        // 2. Fresh today attendance (template, branch, shift, holiday, etc.)
        _withTimeoutRetry(
          () => _attendanceService.getAttendanceByDate(todayStr),
          tag: 'Today attendance fetch',
        ),
      ]);
      if (!mounted) return;
      final profileResult = fetched[0];
      final result = fetched[1];
      final staffData =
          profileResult['data']?['staffData'] as Map<String, dynamic>?;
      _profileAttendanceTemplateId = staffData?['attendanceTemplateId'];
      _syncShiftCalendarContextFromStaff(staffData);
      debugPrint(
        '[Attendance] Profile fetched: profileTemplateRef=$_profileAttendanceTemplateId',
      );
      if (!mounted) return;

      if (result['success'] == true && result['data'] != null) {
        final responseBody = result['data'] as Map<String, dynamic>?;
        Map<String, dynamic>? template;
        if (responseBody != null) {
          template = asAttendanceTemplateMap(responseBody['template']);
          final branch = responseBody['branch'];
          if (mounted) {
            setState(() {
              _attendanceTemplate = template;
              _staffHasAttendanceTemplate = staffHasAssignedAttendanceTemplate(
                profileAttendanceTemplateRef: _profileAttendanceTemplateId,
                todayAttendanceTemplate: template,
              );
              _branchData = branch is Map<String, dynamic> ? branch : null;
              _isOnLeave = responseBody['isOnLeave'] ?? false;
              _leaveMessage = responseBody['leaveMessage'] as String?;
              _halfDayLeave =
                  responseBody['halfDayLeave'] as Map<String, dynamic>?;
              _checkInAllowed = responseBody['checkInAllowed'] ?? true;
              _checkOutAllowed = responseBody['checkOutAllowed'] ?? true;
              _shiftAssigned = responseBody['shiftAssigned'] as bool? ?? true;
              _isHoliday = responseBody['isHoliday'] ?? false;
              _isWeeklyOff = responseBody['isWeeklyOff'] ?? false;
              _isAlternateWorkDate =
                  responseBody['isAlternateWorkDate'] ?? false;
              _isCompensationWeekOff =
                  responseBody['isCompensationWeekOff'] ?? false;
              _isCompensationCompOff =
                  responseBody['isCompensationCompOff'] ?? false;
              _isPaidLeaveToday = responseBody['isPaidLeaveToday'] ?? false;
              _holidayInfo = responseBody['holidayInfo'];
              _weeklyOffPattern = responseBody['weeklyOffPattern'];
              _checkedInFromApi = responseBody['checkedIn'] as bool?;
              _attendanceStatusFetched = true;
              _embeddedBusinessShiftsFromApi = null;
              final bs = responseBody['businessShifts'];
              if (bs is List && bs.isNotEmpty) {
                _embeddedBusinessShiftsFromApi = List<dynamic>.from(bs);
              }
            });
            _reconcileShiftKeyWithAttendanceTemplate();
          }
          final data = responseBody['data'] ?? responseBody;
          if (mounted) {
            setState(() {
              _attendanceData = data is Map<String, dynamic> ? data : null;
              _attendanceDataFetchedFor = DateTime.now();
            });
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              final punchIn = _attendanceData?['punchIn']?.toString().trim();
              final hasPunchInToday = punchIn != null && punchIn.isNotEmpty;
              showAbsentAlertIfNeeded(
                context,
                hasPunchInToday: hasPunchInToday,
                suppressAlert:
                    _isHoliday ||
                    _isOnLeave ||
                    _isPaidLeaveToday ||
                    _halfDayLeave != null ||
                    _isWeeklyOff ||
                    _isCompensationWeekOff ||
                    _isCompensationCompOff,
              );
            });
          }

          // Store in SharedPrefs for check-in alert and selfie check-in
          final toStore = <String, dynamic>{
            'template': template,
            'branch': branch,
            'shiftAssigned': responseBody['shiftAssigned'] ?? true,
            'isHoliday': responseBody['isHoliday'] ?? false,
            'isWeeklyOff': responseBody['isWeeklyOff'] ?? false,
            'holidayInfo': responseBody['holidayInfo'],
            'checkInAllowed': responseBody['checkInAllowed'] ?? true,
            'checkOutAllowed': responseBody['checkOutAllowed'] ?? true,
          };
          await AttendanceTemplateStore.saveTemplateDetails(toStore);
          debugPrint(
            '[Attendance] Template details saved to SharedPrefs: template=${template != null}, branch=${branch != null}, shiftAssigned=${responseBody['shiftAssigned']}',
          );
          debugPrint('[Attendance] Template fetch complete');
        }
      } else {
        debugPrint(
          '[Attendance] Today attendance fetch failed or empty: success=${result['success']}, hasData=${result['data'] != null}',
        );
        if (mounted) {
          setState(() {
            _staffHasAttendanceTemplate = staffHasAssignedAttendanceTemplate(
              profileAttendanceTemplateRef: _profileAttendanceTemplateId,
              todayAttendanceTemplate: _attendanceTemplate,
            );
          });
        }
        if (mounted &&
            !isValidAttendanceTemplateMap(_attendanceTemplate) &&
            _staffHasAttendanceTemplate == true &&
            !_retryingTemplateFetch) {
          setState(() => _retryingTemplateFetch = true);
          await _fetchAllTemplateDetails();
        }
      }
    } on TimeoutException catch (e) {
      debugPrint(
        '[Attendance] Template fetch timed out after retry: ${e.message ?? e.toString()}',
      );
      if (mounted) setState(() => _attendanceStatusFetched = true);
    } catch (e, st) {
      debugPrint('[Attendance] Template fetch error: $e');
      if (kDebugMode) {
        debugPrint('[Attendance] Stack trace: $st');
      }
      if (mounted) setState(() => _attendanceStatusFetched = true);
    }
    if (mounted) await _loadBusinessForAppliedShiftLookup();
  }

  /// Prefer [businessShifts] from attendance APIs, then settings/business, then merged today template.
  Map<String, dynamic>? _companyDocForAppliedShiftResolution() {
    final embedded = _embeddedBusinessShiftsFromApi;
    if (embedded != null && embedded.isNotEmpty) {
      return {
        'settings': {
          'attendance': {'shifts': embedded},
        },
      };
    }
    return companyDocForShiftResolution(
      profilePopulatedCompany: _shiftResolutionCompanyDocFromTemplate(),
      businessFromSettingsBusinessApi: _businessDocForShifts,
    );
  }

  Future<void> _loadBusinessForAppliedShiftLookup({
    bool forceRefresh = false,
  }) async {
    final lastLookup = _lastBusinessLookupAt;
    if (!forceRefresh &&
        _businessDocForShifts != null &&
        lastLookup != null &&
        DateTime.now().difference(lastLookup) < _businessLookupCacheDuration) {
      return;
    }
    try {
      final res = await _settingsService.getBusiness();
      if (!mounted) return;
      if (res['success'] == true && res['data'] is Map) {
        final data = Map<String, dynamic>.from(res['data'] as Map);
        final b = data['business'];
        if (b is Map) {
          setState(() {
            _businessDocForShifts = Map<String, dynamic>.from(b as Map);
            _lastBusinessLookupAt = DateTime.now();
          });
          return;
        }
      }
      if (mounted) {
        setState(() {
          _businessDocForShifts = null;
          _lastBusinessLookupAt = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _businessDocForShifts = null;
          _lastBusinessLookupAt = null;
        });
      }
    }
  }

  void _reconcileShiftKeyWithAttendanceTemplate() {
    if (!mounted || _profileStaffDataSnapshot == null) return;
    final t = _attendanceTemplate;
    String? templateLabel;
    if (t != null && t.isNotEmpty) {
      templateLabel = (t['name'] ?? t['shiftName'])?.toString().trim();
      if (templateLabel != null && templateLabel.isEmpty) {
        templateLabel = null;
      }
    }
    final newKey = staffShiftKeyFromProfileMap(
      _profileStaffDataSnapshot!,
      attendanceTemplateName: templateLabel,
    );
    if (newKey == _profileStaffShiftName) return;
    setState(() {
      _profileStaffShiftName = newKey;
    });
  }

  /// Profile staff snapshot + shift key (for template-name / shiftId reconciliation).
  void _syncShiftCalendarContextFromStaff(Map<String, dynamic>? staffData) {
    String? shiftKey;
    _profileStaffDataSnapshot = null;
    if (staffData != null) {
      final m = Map<String, dynamic>.from(staffData);
      _profileStaffDataSnapshot = Map<String, dynamic>.from(m);
      shiftKey = staffShiftKeyFromProfileMap(m);
    }
    if (!mounted) return;
    setState(() {
      _profileStaffShiftName = shiftKey;
    });
  }

  Future<void> _fetchFineCalculation() async {
    try {
      final result = await _attendanceService.getFineCalculation();
      if (!mounted) return;
      if (result['success'] == true && result['data'] != null) {
        setState(
          () => _fineCalculation = result['data'] as Map<String, dynamic>?,
        );
      } else {
        setState(() => _fineCalculation = null);
      }
    } catch (_) {
      if (mounted) setState(() => _fineCalculation = null);
    }
  }

  /// Load from profile whether staff has attendanceTemplateId (staffs collection). Used to avoid showing "Template not mapped" then refreshing to punch.
  Future<void> _updateStaffHasAttendanceTemplate() async {
    try {
      final profileResult = await _authService.getProfile();
      if (!mounted) return;
      final staffData =
          profileResult['data']?['staffData'] as Map<String, dynamic>?;
      _profileAttendanceTemplateId = staffData?['attendanceTemplateId'];
      _syncShiftCalendarContextFromStaff(staffData);
      _reconcileShiftKeyWithAttendanceTemplate();
      if (mounted) {
        setState(() {
          _staffHasAttendanceTemplate = staffHasAssignedAttendanceTemplate(
            profileAttendanceTemplateRef: _profileAttendanceTemplateId,
            todayAttendanceTemplate: _attendanceTemplate,
          );
        });
      }
    } catch (_) {
      if (mounted) setState(() => _staffHasAttendanceTemplate = null);
    }
  }

  Future<void> _refreshData({bool forceRefresh = false}) async {
    if (!mounted) return;
    if (forceRefresh) {
      _attendanceService.clearCachesForRefresh();
    }
    final year = _focusedDay.year;
    final month = _focusedDay.month;
    final statusDate = _showHistoryView ? _focusedDay : DateTime.now();
    await Future.wait<void>([
      _fetchAttendanceStatus(date: statusDate),
      _fetchHistory(refresh: true),
      _fetchMonthData(year, month, forceRefresh: forceRefresh),
      _fetchFineCalculation(),
      _loadBusinessForAppliedShiftLookup(forceRefresh: forceRefresh),
    ]);
  }

  Future<void> _fetchMonthData(
    int year,
    int month, {
    bool forceRefresh = false,
  }) async {
    debugPrint(
      '[Attendance] month fetch START $year-$month (forceRefresh=$forceRefresh)',
    );
    if (mounted) {
      setState(() {
        _isLoadingMonthData = true;
        // NOTE: do NOT wipe _monthData / the day-status maps here. The success branch
        // below clears and rebuilds them atomically once fresh data arrives. Wiping up
        // front made the calendar flash blank on every load and — worse — left it blank
        // when the fetch failed (e.g. throttled "Too many requests"), so the user had to
        // tap a second time to make markings appear. Markings are keyed by full yyyy-MM-dd
        // so stale entries from another month never render on the new month's cells.
      });
    }
    try {
      final result = await _attendanceService
          .getMonthAttendance(year, month, forceRefresh: forceRefresh)
          .timeout(_networkTimeout);
      if (!mounted) return;

      // Drop stale / out-of-order responses. While navigating months, more than one month
      // fetch can be in flight at once; without this guard a slower response for the month
      // the user just left would overwrite _monthData (and the day-status sets) with the
      // wrong month's data, so the calendar shows no colors until you toggle months and the
      // correct fetch happens to win the race. Only apply a response for the focused month.
      if (_focusedDay.year != year || _focusedDay.month != month) {
        // This response is for a month the user already navigated away from — don't
        // apply it. Still clear the loading flag so a dropped/out-of-order response
        // can never leave the calendar stuck behind a spinner with the dates hidden.
        // The fetch for the now-focused month manages its own loading state.
        debugPrint(
          '[Attendance] month fetch DROPPED (stale) for $year-$month; focused=${_focusedDay.year}-${_focusedDay.month}',
        );
        if (mounted) setState(() => _isLoadingMonthData = false);
        return;
      }

      if (!result['success']) {
        debugPrint(
          '[Attendance] month fetch FAILED $year-$month: ${result['message']}',
        );
        setState(() {
          _isLoadingMonthData = false;
          _monthLoadError = (result['message'] ?? 'Unknown error').toString();
        });
        // Single-click guarantee: a failed month fetch — most often a transient
        // "Too many requests" throttle when the screen fires several calls at once
        // on open — used to leave the calendar blank until the user tapped again.
        // Retry automatically (forcing a fresh fetch) so the markings appear from
        // the user's first action. Previously loaded data stays visible meanwhile
        // because we no longer wipe it at the start of a fetch.
        //
        // The retry must also fire on forceRefresh paths: tab-switch
        // (didUpdateWidget) and pull-to-refresh both call _fetchMonthData with
        // forceRefresh: true, so the old `!forceRefresh` guard meant a transient
        // failure on the most common entry points left the calendar permanently
        // colorless until a manual refresh. Retry whenever the first pass was soft
        // OR we still have nothing to display, bounded per-month so a genuinely
        // broken endpoint can't spin a 1.2s retry loop forever.
        const maxMonthRetries = 3;
        final monthKey = '$year-$month';
        if (_monthRetryKey != monthKey) {
          _monthRetryKey = monthKey;
          _monthRetryAttempts = 0;
        }
        final shouldRetry = (!forceRefresh || _monthData == null) &&
            !_monthRetryScheduled &&
            _monthRetryAttempts < maxMonthRetries;
        if (shouldRetry) {
          _monthRetryScheduled = true;
          _monthRetryAttempts++;
          Future.delayed(const Duration(milliseconds: 1200), () {
            if (!mounted) {
              _monthRetryScheduled = false;
              return;
            }
            _monthRetryScheduled = false;
            // Only retry if the user is still looking at the same month.
            if (_focusedDay.year == year && _focusedDay.month == month) {
              _fetchMonthData(year, month, forceRefresh: true);
            }
          });
        }
        return;
      }

      // Guard: never let a success-but-EMPTY response wipe a calendar that already
      // has markings for this same month. A second fetch (another screen sharing the
      // static cache, a transient backend hiccup, a partial response) that comes back
      // success:true with zero attendance/present/absent/holiday/weekOff/leave was
      // blanking the colors right after they had loaded — the user saw data appear,
      // then vanish, and had to tap to reload. A genuinely empty FUTURE month still
      // loads fine because there are no existing markings to protect.
      final newData = result['data'];
      bool listHas(dynamic m, String k) =>
          m is Map && (m[k] is List) && (m[k] as List).isNotEmpty;
      final bool newHasMarkers = newData is Map &&
          (listHas(newData, 'attendance') ||
              listHas(newData, 'presentDates') ||
              listHas(newData, 'absentDates') ||
              listHas(newData, 'holidays') ||
              listHas(newData, 'weekOffDates') ||
              listHas(newData, 'leaveDates') ||
              listHas(newData, 'alternateWorkDatesInMonth'));
      final bool currentHasMarkers = _dayStatusByDate.isNotEmpty ||
          _presentDateSet.isNotEmpty ||
          _absentDateSet.isNotEmpty ||
          _holidayDateSet.isNotEmpty ||
          _weekOffDateSet.isNotEmpty ||
          _leaveDateSet.isNotEmpty;
      final bool sameFocusedMonth =
          year == _focusedDay.year && month == _focusedDay.month;
      if ((newData == null || !newHasMarkers) &&
          _monthData != null &&
          currentHasMarkers &&
          sameFocusedMonth) {
        debugPrint(
          '[Attendance] month fetch OK but EMPTY for $year-$month — keeping '
          'already-loaded markings (ignoring blank response)',
        );
        if (mounted) setState(() => _isLoadingMonthData = false);
        return;
      }

      setState(() {
        _isLoadingMonthData = false;
        // Fresh data arrived — clear the per-month retry budget so a later
        // transient failure on this month gets its own full set of retries.
        _monthRetryAttempts = 0;
        _monthRetryKey = null;
        _monthLoadError = null;

        _monthData = result['data'];
        final _md = _monthData;
        if (_md != null) {
          debugPrint(
            '[Attendance] month fetch OK $year-$month: '
            'attendance=${(_md['attendance'] as List?)?.length ?? 0} '
            'present=${(_md['presentDates'] as List?)?.length ?? 0} '
            'absent=${(_md['absentDates'] as List?)?.length ?? 0} '
            'holidays=${(_md['holidays'] as List?)?.length ?? 0} '
            'weekOff=${(_md['weekOffDates'] as List?)?.length ?? 0} '
            'leave=${(_md['leaveDates'] as List?)?.length ?? 0}',
          );
        } else {
          debugPrint(
            '[Attendance] month fetch OK $year-$month but data is NULL',
          );
        }
        _embeddedBusinessShiftsFromApi = null;
        final mdRoot = _monthData;
        if (mdRoot != null) {
          final bs = mdRoot['businessShifts'];
          if (bs is List && bs.isNotEmpty) {
            _embeddedBusinessShiftsFromApi = List<dynamic>.from(bs);
          }
        }

        // Rebuild lookup maps/sets so History calendar matches dashboard calendar.
        _dayStatusByDate.clear();
        _dayLeaveTypeByDate.clear();
        _dayIsPaidLeaveByDate.clear();
        _dayCompensationTypeByDate.clear();
        _dayWorkHoursByDate.clear();
        _holidayDateSet.clear();
        _holidayNameByDate.clear();
        _weekOffDateSet.clear();
        _alternateWorkDatesInMonth.clear();
        _presentDateSet.clear();
        _absentDateSet.clear();
        _leaveDateSet.clear();
        _pendingWithCheckInDateSet.clear();

        if (_monthData != null) {
          // Attendance-based maps: one record per date (use attendance collection date; deduplicate)
          if (_monthData!['attendance'] != null) {
            final attendanceList = _deduplicateAttendanceByDate(
              _monthData!['attendance'] as List,
            );
            for (var entry in attendanceList) {
              try {
                // Use attendance collection calendar date (UTC/ISO date part only, no timezone shift)
                final dateStr = _attendanceCalendarDate(entry['date']);
                if (dateStr.isEmpty) continue;
                final parts = dateStr.split('-');
                if (parts.length != 3) continue;
                final dayYear = int.tryParse(parts[0]) ?? 0;
                final dayMonth = int.tryParse(parts[1]) ?? 0;
                if (dayYear != year || dayMonth != month) continue;

                final statusVal = (entry['status'] as String?) ?? 'Present';
                _dayStatusByDate[dateStr] = statusVal;
                if (statusVal == 'Pending') {
                  final punchIn = entry['punchIn'];
                  if (punchIn != null && punchIn.toString().trim().isNotEmpty) {
                    _pendingWithCheckInDateSet.add(dateStr);
                  }
                }
                final leaveType = entry['leaveType'] as String?;
                if (leaveType != null && leaveType.isNotEmpty) {
                  _dayLeaveTypeByDate[dateStr] = leaveType;
                }
                if (entry['isPaidLeave'] == true) {
                  _dayIsPaidLeaveByDate[dateStr] = true;
                }
                final compType = entry['compensationType'] as String?;
                if (compType != null && compType.toString().trim().isNotEmpty) {
                  _dayCompensationTypeByDate[dateStr] = compType
                      .toString()
                      .trim()
                      .toLowerCase();
                }

                num? workHours = entry['workHours'] as num?;

                // Calculate workHours (in minutes) from punchIn and punchOut if not already present
                if (workHours == null) {
                  final punchIn = entry['punchIn'];
                  final punchOut = entry['punchOut'];
                  if (punchIn != null && punchOut != null) {
                    try {
                      final punchInTime = DateTime.parse(
                        punchIn.toString(),
                      ).toLocal();
                      final punchOutTime = DateTime.parse(
                        punchOut.toString(),
                      ).toLocal();
                      final duration = punchOutTime.difference(punchInTime);
                      if (duration.inMinutes > 0) {
                        workHours = duration.inMinutes; // store as minutes
                      }
                    } catch (_) {
                      // Ignore parse errors; leave workHours null
                    }
                  }
                }

                _dayWorkHoursByDate[dateStr] = workHours;
              } catch (_) {
                // Skip invalid date entries
                continue;
              }
            }
          }

          // Holiday dates
          if (_monthData!['holidays'] != null) {
            for (var h in _monthData!['holidays']) {
              try {
                final d = DateTime.parse(h['date'].toString()).toLocal();
                if (d.year != year || d.month != month) continue;
                final dateStr = DateFormat('yyyy-MM-dd').format(d);
                _holidayDateSet.add(dateStr);
                final hName = (h['name'] ?? '').toString().trim();
                if (hName.isNotEmpty) {
                  _holidayNameByDate[dateStr] = hName;
                }
              } catch (_) {
                continue;
              }
            }
          }

          // Week off dates (already computed by backend)
          if (_monthData!['weekOffDates'] != null) {
            for (var dateStr in _monthData!['weekOffDates']) {
              if (dateStr is String) {
                _weekOffDateSet.add(dateStr);
              }
            }
          }

          // Alternate work dates in this month (compensation week-off: do not show violet; employee can check-in)
          _alternateWorkDatesInMonth.clear();
          if (_monthData!['alternateWorkDatesInMonth'] != null) {
            for (var dateStr in _monthData!['alternateWorkDatesInMonth']) {
              if (dateStr is String) {
                _alternateWorkDatesInMonth.add(dateStr);
              }
            }
          }

          // Present dates
          if (_monthData!['presentDates'] != null) {
            for (var dateStr in _monthData!['presentDates']) {
              if (dateStr is String) {
                _presentDateSet.add(dateStr);
              }
            }
          }

          // Absent dates
          if (_monthData!['absentDates'] != null) {
            for (var dateStr in _monthData!['absentDates']) {
              if (dateStr is String) {
                _absentDateSet.add(dateStr);
              }
            }
          }

          // Approved leave dates (treat as On Leave when no overriding attendance)
          if (_monthData!['leaveDates'] != null) {
            for (var dateStr in _monthData!['leaveDates']) {
              if (dateStr is String) {
                _leaveDateSet.add(dateStr);
              }
            }
          }
        }
        // Recent activity: always today + last 5 days. Only update when fetching current month.
        final nowDate = DateTime.now();
        if (year == nowDate.year &&
            month == nowDate.month &&
            _monthData != null) {
          final combined = _getCombinedMonthHistory();
          final todayOnly = DateTime(nowDate.year, nowDate.month, nowDate.day);
          _recentActivityList = combined.where((e) {
            try {
              final d = _extractDateOnly(e['date']);
              final dateOnly = DateTime(d.year, d.month, d.day);
              final diff = todayOnly.difference(dateOnly).inDays;
              return diff >= 0 && diff < 6; // today and last 5 days
            } catch (_) {
              return false;
            }
          }).toList();
          _recentActivityList.sort((a, b) {
            DateTime da = _extractDateOnly(a['date']);
            DateTime db = _extractDateOnly(b['date']);
            return db.compareTo(da); // newest first
          });
        }
      });
    } catch (e) {
      debugPrint('[Attendance] month data fetch failed: $e');
      if (mounted) {
        setState(() {
          _isLoadingMonthData = false;
          _monthLoadError = e.toString();
        });
      }
    }
  }

  Future<void> _fetchHistory({bool refresh = false, int? page}) async {
    if (!mounted) return;
    // Allow refresh to proceed even when initial loading flag is already true.
    if (_isLoadingHistory && !refresh) return;

    final pageToFetch = page ?? (refresh ? 1 : _page);

    setState(() {
      _isLoadingHistory = true;
      if (refresh || pageToFetch == 1) {
        _historyList = [];
      }
    });

    try {
      final result = await _attendanceService
          .getAttendanceHistory(page: pageToFetch, limit: _limit)
          .timeout(_networkTimeout);

      if (result['success'] && mounted) {
        final payload = (result['data'] is Map<String, dynamic>)
            ? result['data'] as Map<String, dynamic>
            : <String, dynamic>{};
        final List<dynamic> newData = payload['data'] is List
            ? List<dynamic>.from(payload['data'] as List)
            : <dynamic>[];
        final pagination = payload['pagination'] is Map<String, dynamic>
            ? payload['pagination'] as Map<String, dynamic>
            : <String, dynamic>{'total': 0};

        setState(() {
          // For refresh or first page, replace the list.
          // For subsequent pages, append to preserve earlier history.
          if (refresh || pageToFetch == 1) {
            _historyList = newData;
          } else {
            _historyList = [..._historyList, ...newData];
          }
          _page = pageToFetch;
          _totalRecords = pagination['total'] ?? 0;
          _totalPages = ((_totalRecords / _limit).ceil())
              .clamp(1, double.infinity)
              .toInt();
          _isLoadingHistory = false;
        });
      } else {
        if (mounted) setState(() => _isLoadingHistory = false);
      }
    } catch (e) {
      debugPrint('[Attendance] history fetch failed: $e');
      if (mounted) setState(() => _isLoadingHistory = false);
    }
  }

  Future<void> _fetchAttendanceStatus({DateTime? date}) async {
    if (!mounted) return;
    final dateToFetch = date ?? (DateTime.now());
    String formattedDate = dateToFetch.toIso8601String().split('T')[0];
    bool didRetry = false;

    try {
      final result = await _attendanceService.getAttendanceByDate(
        formattedDate,
      );

      if (result['success'] && mounted) {
        final responseBody = result['data'];
        Map<String, dynamic>? data;
        Map<String, dynamic>? template;

        if (responseBody != null) {
          if (responseBody is Map<String, dynamic> &&
              responseBody.containsKey('data')) {
            data = responseBody['data'];
            template = asAttendanceTemplateMap(responseBody['template']);
            final branch = responseBody['branch'];

            setState(() {
              _attendanceTemplate = template;
              _staffHasAttendanceTemplate = staffHasAssignedAttendanceTemplate(
                profileAttendanceTemplateRef: _profileAttendanceTemplateId,
                todayAttendanceTemplate: template,
              );
              _branchData = branch is Map<String, dynamic> ? branch : null;
              _isOnLeave = responseBody['isOnLeave'] ?? false;
              _leaveMessage = responseBody['leaveMessage'] as String?;
              _halfDayLeave =
                  responseBody['halfDayLeave'] as Map<String, dynamic>?;
              _checkInAllowed = responseBody['checkInAllowed'] ?? true;
              _checkOutAllowed = responseBody['checkOutAllowed'] ?? true;
              _shiftAssigned = responseBody['shiftAssigned'] as bool? ?? true;
              _isHoliday = responseBody['isHoliday'] ?? false;
              _isWeeklyOff = responseBody['isWeeklyOff'] ?? false;
              _isAlternateWorkDate =
                  responseBody['isAlternateWorkDate'] ?? false;
              _isCompensationWeekOff =
                  responseBody['isCompensationWeekOff'] ?? false;
              _isCompensationCompOff =
                  responseBody['isCompensationCompOff'] ?? false;
              _isPaidLeaveToday = responseBody['isPaidLeaveToday'] ?? false;
              _holidayInfo = responseBody['holidayInfo'];
              _checkedInFromApi = responseBody['checkedIn'] as bool?;
              _embeddedBusinessShiftsFromApi = null;
              final bs = responseBody['businessShifts'];
              if (bs is List && bs.isNotEmpty) {
                _embeddedBusinessShiftsFromApi = List<dynamic>.from(bs);
              }
            });
          } else {
            data = responseBody;
            if (responseBody is Map<String, dynamic> &&
                responseBody.containsKey('checkedIn')) {
              setState(
                () => _checkedInFromApi = responseBody['checkedIn'] as bool?,
              );
            }
          }
        }

        final now = DateTime.now();
        final isToday =
            dateToFetch.year == now.year &&
            dateToFetch.month == now.month &&
            dateToFetch.day == now.day;
        if (mounted) {
          setState(() {
            _attendanceData = data;
            _attendanceDataFetchedFor = dateToFetch;
          });
          if (isToday) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              final punchIn = _attendanceData?['punchIn']?.toString().trim();
              final hasPunchInToday = punchIn != null && punchIn.isNotEmpty;
              showAbsentAlertIfNeeded(
                context,
                hasPunchInToday: hasPunchInToday,
                suppressAlert:
                    _isHoliday ||
                    _isOnLeave ||
                    _isPaidLeaveToday ||
                    _halfDayLeave != null ||
                    _isWeeklyOff ||
                    _isCompensationWeekOff ||
                    _isCompensationCompOff,
              );
            });
          }
        }

        // Save template details for today (for check-in alert and selfie check-in)
        if (isToday && responseBody != null && responseBody is Map) {
          final template = responseBody['template'];
          final branch = responseBody['branch'];
          if (template != null || (branch is Map<String, dynamic>)) {
            final toStore = <String, dynamic>{
              'template': template,
              'branch': branch,
              'shiftAssigned': responseBody['shiftAssigned'] ?? true,
              'isHoliday': responseBody['isHoliday'] ?? false,
              'isWeeklyOff': responseBody['isWeeklyOff'] ?? false,
              'holidayInfo': responseBody['holidayInfo'],
              'checkInAllowed': responseBody['checkInAllowed'] ?? true,
              'checkOutAllowed': responseBody['checkOutAllowed'] ?? true,
            };
            AttendanceTemplateStore.saveTemplateDetails(toStore);
          }
        }

        // Staff has template id but response had no template (e.g. first request failed) — retry once so we don't show "Template not mapped" then refresh to punch
        if (mounted &&
            !isValidAttendanceTemplateMap(_attendanceTemplate) &&
            _staffHasAttendanceTemplate == true &&
            !_retryingTemplateFetch) {
          didRetry = true;
          setState(() => _retryingTemplateFetch = true);
          await _fetchAttendanceStatus(date: dateToFetch);
        }
      }
    } finally {
      if (mounted && !didRetry) setState(() => _attendanceStatusFetched = true);
    }
  }

  // Helper method to extract date only (ignoring time and timezone)
  // This ensures dates are displayed correctly regardless of timezone
  // MongoDB stores dates in UTC, so we parse the full ISO string, convert to local,
  // and then extract the date components to preserve the correct date in user's timezone
  DateTime _extractDateOnly(dynamic dateValue) {
    if (dateValue == null) return DateTime.now();
    try {
      String dateStr = dateValue.toString();

      // Parse the full ISO string (handles both with and without time)
      DateTime parsed;
      if (dateStr.contains('T')) {
        // Full ISO string with time (e.g., "2026-01-26T10:30:00.000Z")
        parsed = DateTime.parse(dateStr).toLocal();
      } else {
        // Date only string (e.g., "2026-01-26")
        // Parse and assume it's in local timezone for date-only strings
        final parts = dateStr.split('-');
        if (parts.length == 3) {
          parsed = DateTime(
            int.parse(parts[0]),
            int.parse(parts[1]),
            int.parse(parts[2]),
          );
        } else {
          parsed = DateTime.parse(dateStr).toLocal();
        }
      }

      // Extract date components from local time and create a new DateTime
      // This ensures the date is preserved in the user's local timezone
      return DateTime(parsed.year, parsed.month, parsed.day);
    } catch (e) {
      return DateTime.now();
    }
  }

  // Helper method to format time
  String _formatTime(dynamic isoString) {
    if (isoString == null ||
        isoString.toString().isEmpty ||
        isoString == 'null') {
      return '--:--';
    }
    try {
      final date = DateTime.parse(isoString.toString()).toLocal();
      return DateFormat('hh:mm a').format(date);
    } catch (e) {
      return '--:--';
    }
  }

  /// Converts a 24-hour "HH:mm" shift-time string to 12-hour clock time, e.g.
  /// "19:00" → "7:00 PM". Returns the input unchanged if it isn't "HH:mm".
  String _formatShiftTime12(String time24) {
    final parts = time24.split(':');
    if (parts.length != 2) return time24;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return time24;
    final period = h >= 12 ? 'PM' : 'AM';
    final h12 = h % 12 == 0 ? 12 : h % 12;
    final mm = m.toString().padLeft(2, '0');
    return '$h12:$mm $period';
  }

  String _formatApprovedAt(dynamic value) {
    if (value == null || value.toString().isEmpty || value == 'null') {
      return '--';
    }
    try {
      final date = DateTime.parse(value.toString()).toLocal();
      return DateFormat('MMM dd, yyyy \'at\' hh:mm a').format(date);
    } catch (e) {
      return value.toString();
    }
  }

  /// Returns true if the value should be shown (not empty, not '-', not 'no').
  bool _hasMeaningfulValue(String? value) {
    if (value == null) return false;
    final s = value.trim();
    if (s.isEmpty) return false;
    if (s == '-') return false;
    if (s.toLowerCase() == 'no') return false;
    return true;
  }

  void _showSelfieDialog(String imageUrl, [String title = "Selfie View"]) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(title, style: TextStyle(fontWeight: FontWeight.bold)),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: double.infinity,
              child: Image.network(
                imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _buildImageNotFoundPlaceholder(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageNotFoundPlaceholder() {
    return Container(
      height: 200,
      width: double.infinity,
      color: Colors.grey.shade200,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.broken_image_outlined,
            size: 48,
            color: Colors.grey.shade500,
          ),
          const SizedBox(height: 8),
          Text(
            'Image not found',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  /// Calendar date (yyyy-MM-dd) from attendance collection date field.
  /// Uses UTC / ISO date part only so the same DB date always maps to the same day (no local timezone shift).
  /// Handles: ISO string "2026-03-12T00:00:00.000Z", date-only "2026-03-12", or DateTime (use UTC components).
  String _attendanceCalendarDate(dynamic dateValue) {
    if (dateValue == null) return '';
    try {
      if (dateValue is DateTime) {
        final u = dateValue.toUtc();
        return '${u.year}-${u.month.toString().padLeft(2, '0')}-${u.day.toString().padLeft(2, '0')}';
      }
      final s = dateValue.toString().trim();
      if (s.isEmpty) return '';
      if (s.contains('T')) return s.split('T').first;
      if (s.length >= 10 && s[4] == '-' && s[7] == '-')
        return s.substring(0, 10);
      final d = DateTime.parse(s);
      final u = d.toUtc();
      return '${u.year}-${u.month.toString().padLeft(2, '0')}-${u.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }

  String _dateKey(dynamic record) {
    if (record is! Map) return '';
    return _attendanceCalendarDate(record['date']);
  }

  /// When multiple attendance records exist for the same date, keep one per date:
  /// prefer record with punchIn (actual attendance), then latest by updatedAt.
  List<dynamic> _deduplicateAttendanceByDate(List<dynamic> attendance) {
    if (attendance.isEmpty) return [];
    final byDate = <String, Map<String, dynamic>>{};
    for (final r in attendance) {
      if (r is! Map) continue;
      final key = _dateKey(r);
      if (key.isEmpty) continue;
      final existing = byDate[key];
      if (existing == null) {
        byDate[key] = Map<String, dynamic>.from(r);
        continue;
      }
      final hasPunchIn =
          (r['punchIn'] != null && r['punchIn'].toString().trim().isNotEmpty);
      final existingHasPunchIn =
          (existing['punchIn'] != null &&
          existing['punchIn'].toString().trim().isNotEmpty);
      if (hasPunchIn && !existingHasPunchIn) {
        byDate[key] = Map<String, dynamic>.from(r);
      } else if (hasPunchIn == existingHasPunchIn) {
        final rUpdated = r['updatedAt'];
        final eUpdated = existing['updatedAt'];
        if (rUpdated != null && eUpdated != null) {
          final rTime = _extractDateOnly(rUpdated).millisecondsSinceEpoch;
          final eTime = _extractDateOnly(eUpdated).millisecondsSinceEpoch;
          if (rTime > eTime) byDate[key] = Map<String, dynamic>.from(r);
        }
      }
    }
    return byDate.values.toList();
  }

  // Helper method to get combined history for the focused month.
  // When _monthData is null we return [] so the UI shows loader (no stale _historyList).
  // Uses attendance collection date field; one record per date (deduplicated).
  List<dynamic> _getCombinedMonthHistory() {
    if (_monthData == null) {
      return [];
    }

    final attendance = (_monthData!['attendance'] as List?) ?? [];
    final weekOffDates =
        (_monthData!['weekOffDates'] as List?)?.cast<String>() ?? const [];
    final absentDates =
        (_monthData!['absentDates'] as List?)?.cast<String>() ?? const [];
    final holidayDates =
        (_monthData!['holidayDates'] as List?)?.cast<String>() ?? const [];
    final leaveDates =
        (_monthData!['leaveDates'] as List?)?.cast<String>() ?? const [];

    List<dynamic> combined = _deduplicateAttendanceByDate(attendance);

    // Helper to check if date already has a record (use same calendar date as backend, no timezone shift)
    bool hasRecord(String dateStr) {
      return combined.any((r) {
        if (r is! Map) return false;
        return _dateKey(r) == dateStr;
      });
    }

    for (var dateStr in absentDates) {
      if (!hasRecord(dateStr)) {
        combined.add({'date': dateStr, 'status': 'Absent'});
      }
    }
    for (var dateStr in weekOffDates) {
      if (!hasRecord(dateStr)) {
        combined.add({'date': dateStr, 'status': 'Weekend'});
      }
    }
    for (var dateStr in holidayDates) {
      if (!hasRecord(dateStr)) {
        combined.add({'date': dateStr, 'status': 'Holiday'});
      }
    }
    for (var dateStr in leaveDates) {
      if (!hasRecord(dateStr)) {
        combined.add({'date': dateStr, 'status': 'On Leave'});
      }
    }

    combined.sort((a, b) {
      DateTime da = _extractDateOnly(a['date']);
      DateTime db = _extractDateOnly(b['date']);
      return db.compareTo(da);
    });

    // Restrict to the focused calendar month only. The backend's month payload can
    // include a boundary record (e.g. a UTC-midnight date that resolves to the last
    // day of the PREVIOUS month in local time, or server-side padding), which made
    // "May 31" show under the June logs. History must list only the selected month.
    combined = combined.where((e) {
      try {
        final d = _extractDateOnly(e['date']);
        return d.year == _focusedDay.year && d.month == _focusedDay.month;
      } catch (_) {
        return false;
      }
    }).toList();

    // Show history only up to today; exclude future days
    final now = DateTime.now();
    final todayOnly = DateTime(now.year, now.month, now.day);
    combined = combined.where((e) {
      try {
        final d = _extractDateOnly(e['date']);
        return !d.isAfter(todayOnly);
      } catch (_) {
        return true;
      }
    }).toList();

    return combined;
  }

  void _showAttendanceDetails(Map<String, dynamic> record) {
    final dateStr = record['date'] ?? '';
    String formattedDate = 'Invalid Date';
    String formattedHeaderDate = '';
    try {
      final d = _extractDateOnly(dateStr);
      formattedDate = DateFormat('MMM dd, yyyy').format(d);
      formattedHeaderDate = DateFormat('dd MMM yyyy | EEE').format(d);
    } catch (_) {
      formattedDate = dateStr.toString();
      formattedHeaderDate = dateStr.toString();
    }

    final punchIn = record['punchIn'];
    final punchOut = record['punchOut'];
    final workHours = record['workHours'];
    final status = record['status'] ?? 'Present';
    final compensationType = (record['compensationType'] as String? ?? '')
        .toString()
        .trim();
    final isPaidLeave = record['isPaidLeave'] == true;
    // Prefer half-day details from Leaves collection (leaveDetails), else from attendance record
    final leaveDetails = record['leaveDetails'] as Map<String, dynamic>?;
    final leaveType =
        (leaveDetails?['leaveType'] ?? record['leaveType']) as String?;
    final session = (leaveDetails?['session'] ?? record['session'])?.toString();
    final leaveReason = leaveDetails?['reason'] as String?;
    final approvedAt = leaveDetails?['approvedAt'];
    final approvedByObj = leaveDetails?['approvedBy'] as Map<String, dynamic>?;
    final approvedByName = approvedByObj?['name'] as String?;
    String displayStatus = AttendanceDisplayUtil.formatAttendanceDisplayStatus(
      status,
      leaveType,
      session,
    );
    // Week-off by template should always show as Week Off, not Leave (even if record is On Leave for that date)
    final normalizedDateStr = _dateKey(record);
    if (normalizedDateStr.isNotEmpty &&
        _weekOffDateSet.contains(normalizedDateStr) &&
        !_alternateWorkDatesInMonth.contains(normalizedDateStr) &&
        status.toString().toLowerCase() == 'on leave') {
      displayStatus = 'Week Off';
    }
    // Only show "Waiting for Approval" when user has punched in (not for leave-related Pending without punch)
    if (status == 'Pending' && punchIn != null) {
      displayStatus = 'Waiting for Approval';
    }
    final summaryStatus = displayStatus == 'Waiting for Approval'
        ? 'Approval Pending'
        : displayStatus;
    final isLateIn = _isLateCheckIn(punchIn, record: record);
    final isEarlyOut = _isEarlyCheckOut(punchOut, record: record);

    // Fine information. record.fineAmount / fineHours cover late + early only;
    // break overage fine is stored separately under record.break, so the day's
    // TRUE total = late/early + break (matches the Shift Time day-detail sheet).
    final lateMinutes = record['lateMinutes'] as num?;
    final earlyMinutes = record['earlyMinutes'] as num?;
    final fineHours = record['fineHours'] as num?;
    final fineAmount = record['fineAmount'] as num?;
    final breakMapForFine =
        record['break'] is Map ? Map<String, dynamic>.from(record['break'] as Map) : null;
    final breakFineMins = breakMapForFine?['totalBreakFineMins'] as num?;
    final breakFineAmount = breakMapForFine?['totalBreakFineAmount'] as num?;
    final permissionFineMins = record['permissionFineMinutes'] as num?;
    final permissionFineAmount = record['permissionFineAmount'] as num?;
    final totalFineMinsDisplay = (fineHours?.toDouble() ?? 0) +
        (breakFineMins?.toDouble() ?? 0) +
        (permissionFineMins?.toDouble() ?? 0);
    final totalFineAmountDisplay = (fineAmount?.toDouble() ?? 0) +
        (breakFineAmount?.toDouble() ?? 0) +
        (permissionFineAmount?.toDouble() ?? 0);
    final hasFineInfo =
        (lateMinutes != null && lateMinutes > 0) ||
        (earlyMinutes != null && earlyMinutes > 0) ||
        (fineHours != null && fineHours > 0) ||
        (fineAmount != null && fineAmount > 0) ||
        (breakFineMins != null && breakFineMins > 0) ||
        (breakFineAmount != null && breakFineAmount > 0) ||
        (permissionFineMins != null && permissionFineMins > 0) ||
        (permissionFineAmount != null && permissionFineAmount > 0);

    // Permission usage details (stored in attendance collection for this date)
    final permissionLateMinutes = _parseLogNumericValue(
      record['permissionLateMinutes'],
    );
    final permissionEarlyMinutes = _parseLogNumericValue(
      record['permissionEarlyMinutes'],
    );
    final permissionApprovedMinutes = _parseLogNumericValue(
      record['permissionApprovedMinutes'],
    );
    final permissionConsumedMinutes = _parseLogNumericValue(
      record['permissionConsumedMinutes'],
    );
    final permissionRemainingMinutes = _parseLogNumericValue(
      record['permissionRemainingMinutes'] ?? record['permissionRemainingMinute'],
    );
    final hasPermissionInfo =
        (permissionApprovedMinutes != null && permissionApprovedMinutes > 0) ||
        (permissionConsumedMinutes != null && permissionConsumedMinutes > 0) ||
        (permissionRemainingMinutes != null && permissionRemainingMinutes > 0) ||
        (permissionLateMinutes != null && permissionLateMinutes > 0) ||
        (permissionEarlyMinutes != null && permissionEarlyMinutes > 0);

    // Extract location details
    String? punchInAddress;
    String? punchOutAddress;
    String? branchName;

    if (record['location'] != null) {
      final location = record['location'];
      if (location['punchIn'] != null) {
        final punchInLoc = location['punchIn'];
        punchInAddress =
            punchInLoc['address'] ??
            '${punchInLoc['area'] ?? ''}, ${punchInLoc['city'] ?? ''}, ${punchInLoc['pincode'] ?? ''}';
        branchName = punchInLoc['branchName'] ?? record['branchName'];
      }
      if (location['punchOut'] != null) {
        final punchOutLoc = location['punchOut'];
        punchOutAddress =
            punchOutLoc['address'] ??
            '${punchOutLoc['area'] ?? ''}, ${punchOutLoc['city'] ?? ''}, ${punchOutLoc['pincode'] ?? ''}';
        branchName ??= punchOutLoc['branchName'] ?? record['branchName'];
      }
    }

    // Selfie URLs
    final punchInSelfieUrl = record['punchInSelfie'];
    final punchOutSelfieUrl = record['punchOutSelfie'];
    final bool hasPunchInSelfie =
        punchInSelfieUrl != null &&
        punchInSelfieUrl.toString().startsWith('http');
    final bool hasPunchOutSelfie =
        punchOutSelfieUrl != null &&
        punchOutSelfieUrl.toString().startsWith('http');
    final logs = (record['logs'] is List)
        ? List<Map<String, dynamic>>.from(
            (record['logs'] as List).whereType<Map>(),
          )
        : <Map<String, dynamic>>[];

    // Status color
    Color statusColor = Colors.green;
    if (status == 'Pending') {
      statusColor = Colors.orange;
    } else if (status == 'Absent' || status == 'Rejected') {
      statusColor = Colors.red;
    } else if (status == 'On Leave') {
      statusColor = Colors.blue;
    } else if (status == 'Half Day') {
      statusColor = Colors.purple;
    } else if (status == 'Weekend') {
      statusColor = Colors.deepPurple;
    } else if (status == 'Holiday') {
      statusColor = Colors.amber;
    }

    final colorScheme = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Container(
          color: colorScheme.surface,
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        size: 18,
                      ),
                      onPressed: () => Navigator.pop(context),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Attendance Detail',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            formattedHeaderDate,
                            style: TextStyle(
                              fontSize: 12,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildAttendanceSummaryCard(
                        shiftLabel: _shiftLabelForAttendanceDetail(record),
                        shiftTime: _shiftTimeLineForAttendanceDetail(record),
                        status: summaryStatus,
                        statusColor: statusColor,
                        punchIn: _formatTime(punchIn),
                        punchOut: _formatTime(punchOut),
                        workHours: _formatWorkHoursWithUnits(
                          workHours is num ? workHours : null,
                        ),
                        paidLeaveLabel: isPaidLeave ? 'Paid Leave' : null,
                        sessionLabel: session != null && session.isNotEmpty
                            ? _formatHalfDaySessionLabel(session)
                            : null,
                        compensationType: _hasMeaningfulValue(compensationType)
                            ? compensationType.trim()
                            : null,
                        overtimeDisplay: _formatOvertimeForDisplay(
                          record['overtime'],
                        ),
                        openShiftBufferDisplay:
                            _isOpenShiftForRecordEvaluation(record)
                            ? _formatOpenShiftBufferForDisplay(
                                record['bufferTime'],
                              )
                            : null,
                      ),
                      if (hasFineInfo) ...[
                        const SizedBox(height: 20),
                        _buildDayDetailSection('Fine Details', Icons.money_off, [
                          if (lateMinutes != null && lateMinutes.toInt() > 0)
                            _buildDayDetailRow(
                              'Late Check-in',
                              '${lateMinutes.toInt()} minutes',
                              valueColor: Colors.orange.shade700,
                            ),
                          if (earlyMinutes != null && earlyMinutes.toInt() > 0)
                            _buildDayDetailRow(
                              'Early Check-out',
                              '${earlyMinutes.toInt()} minutes',
                              valueColor: Colors.orange.shade700,
                            ),
                          if (breakFineMins != null && breakFineMins.toInt() > 0)
                            _buildDayDetailRow(
                              'Break Fine',
                              '${breakFineMins.toInt()} mins',
                              valueColor: Colors.orange.shade700,
                            ),
                          if (permissionFineMins != null &&
                              permissionFineMins.toInt() > 0)
                            _buildDayDetailRow(
                              'Permission Fine',
                              '${permissionFineMins.toInt()} mins',
                              valueColor: Colors.orange.shade700,
                            ),
                          if (totalFineMinsDisplay > 0)
                            _buildDayDetailRow(
                              'Total Fine Min',
                              '${totalFineMinsDisplay.toInt()} mins',
                              valueColor: Colors.red.shade700,
                            ),
                          if (totalFineAmountDisplay > 0)
                            _buildDayDetailRow(
                              'Fine Amount',
                              '₹${NumberFormat('#,##0.00').format(totalFineAmountDisplay)}',
                              valueColor: Colors.red.shade700,
                              isBold: true,
                            ),
                        ]),
                      ],
                      if (hasPermissionInfo) ...[
                        const SizedBox(height: 20),
                        _buildDayDetailSection(
                          'Permission Details',
                          Icons.fact_check_outlined,
                          [
                            if (permissionApprovedMinutes != null)
                              _buildDayDetailRow(
                                'Permission Approved',
                                '${permissionApprovedMinutes.toInt()} mins',
                                valueColor: Colors.blueGrey.shade700,
                              ),
                            if (permissionRemainingMinutes != null)
                              _buildDayDetailRow(
                                'Permission Remaining',
                                '${permissionRemainingMinutes.toInt()} mins',
                                valueColor: Colors.green.shade700,
                              ),
                            if (permissionLateMinutes != null &&
                                permissionLateMinutes > 0)
                              _buildDayDetailRow(
                                'Permission Late Arrival',
                                '${permissionLateMinutes.toInt()} mins',
                                valueColor: Colors.deepOrange.shade700,
                              ),
                            if (permissionEarlyMinutes != null &&
                                permissionEarlyMinutes > 0)
                              _buildDayDetailRow(
                                'Permission Early Exit',
                                '${permissionEarlyMinutes.toInt()} mins',
                                valueColor: Colors.deepOrange.shade700,
                              ),
                          ],
                        ),
                      ],
                      if (logs.isNotEmpty ||
                          punchIn != null ||
                          punchOut != null) ...[
                        const SizedBox(height: 20),
                        _buildDayDetailSection(
                          'Log',
                          Icons.list_alt_rounded,
                          _buildAttendanceLogChildren(
                            logs,
                            punchIn: punchIn,
                            punchOut: punchOut,
                            branchName: branchName,
                            punchInSelfieUrl: hasPunchInSelfie
                                ? punchInSelfieUrl.toString()
                                : null,
                            punchOutSelfieUrl: hasPunchOutSelfie
                                ? punchOutSelfieUrl.toString()
                                : null,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFineRow(String label, String value, IconData icon, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade700,
              ),
            ),
          ],
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildAttendanceSummaryCard({
    required String shiftLabel,
    required String shiftTime,
    required String status,
    required Color statusColor,
    required String punchIn,
    required String punchOut,
    required String workHours,
    String? paidLeaveLabel,
    String? sessionLabel,
    String? compensationType,
    String? overtimeDisplay,
    String? openShiftBufferDisplay,
  }) {
    final shiftLine = shiftTime.trim().isEmpty
        ? shiftLabel
        : '$shiftLabel - $shiftTime';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      shiftLine,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (paidLeaveLabel != null || sessionLabel != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        [paidLeaveLabel, sessionLabel]
                            .whereType<String>()
                            .where((e) => e.trim().isNotEmpty)
                            .join(' • '),
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade700,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                    if (compensationType != null &&
                        compensationType.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        compensationType.trim(),
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Text(
                  status,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _buildSummaryMetric('Check In', punchIn)),
              const SizedBox(width: 12),
              Expanded(child: _buildSummaryMetric('Check Out', punchOut)),
              const SizedBox(width: 12),
              Expanded(child: _buildSummaryMetric('Work Hours', workHours)),
            ],
          ),
          if (overtimeDisplay != null && overtimeDisplay.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  Icons.more_time_rounded,
                  size: 18,
                  color: Colors.teal.shade700,
                ),
                const SizedBox(width: 8),
                Text(
                  'Overtime: $overtimeDisplay',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.teal.shade800,
                  ),
                ),
              ],
            ),
          ],
          if (openShiftBufferDisplay != null &&
              openShiftBufferDisplay.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(
                  Icons.hourglass_top_rounded,
                  size: 18,
                  color: Colors.blueGrey.shade600,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Buffer (tracked): $openShiftBufferDisplay',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.blueGrey.shade800,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSummaryMetric(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
        ),
      ],
    );
  }

  Widget _buildSelfieThumbnail({
    required String imageUrl,
    required String label,
  }) {
    return GestureDetector(
      onTap: () => _showSelfieDialog(imageUrl, '$label Selfie'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.shade300),
              image: DecorationImage(
                image: CachedNetworkImageProvider(imageUrl),
                fit: BoxFit.cover,
                onError: (_, __) {},
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildAttendanceLogChildren(
    List<Map<String, dynamic>> logs, {
    required dynamic punchIn,
    required dynamic punchOut,
    String? branchName,
    String? punchInSelfieUrl,
    String? punchOutSelfieUrl,
  }) {
    DateTime? parseLogEventTime(dynamic value) {
      return _parseAnyDateTimeToLocal(value);
    }

    int logSortMsFrom(dynamic value) {
      return parseLogEventTime(value)?.millisecondsSinceEpoch ?? -1;
    }

    final items = <Map<String, dynamic>>[];
    if (logs.isNotEmpty) {
      for (final log in logs) {
        final action = (log['action'] ?? '').toString().trim().toUpperCase();
        if (const {'APPROVED', 'REJECTED'}.contains(action)) {
          Map<String, dynamic>? newValueMap;
          final nv = log['newValue'];
          if (nv is Map) {
            newValueMap = Map<String, dynamic>.from(nv);
          }
          dynamic when = log['timestamp'];
          dynamic approvedAtRaw = newValueMap?['approvedAt'];
          if (approvedAtRaw is Map && approvedAtRaw['\$date'] != null) {
            approvedAtRaw = approvedAtRaw['\$date'];
          }
          if (approvedAtRaw != null) {
            when = approvedAtRaw;
          }
          final statusLabel = (newValueMap?['status'] ?? '').toString().trim();
          final title = action == 'REJECTED'
              ? 'Attendance rejected'
              : 'Attendance approved';
          final headlineParts = <String>[
            _formatLogTime(when),
            if (statusLabel.isNotEmpty) statusLabel,
          ];
          items.add({
            'title': title,
            'headline': headlineParts.where((e) => e.isNotEmpty).join(' | '),
            'subtitle': _formatLogByline(
              log['performedByName']?.toString(),
              when,
            ),
            'imageUrl': null,
            'tileIcon': action == 'REJECTED' ? 'rejection' : 'approval',
            'sortMs': logSortMsFrom(when),
          });
          continue;
        }
        if (action == 'UPDATED') {
          final changes = log['changes'];
          if (changes is List) {
            for (final change in changes) {
              if (change is! Map) continue;
              final map = Map<String, dynamic>.from(change);
              final field = (map['field'] ?? '').toString();
              if (field != 'fineAmount') continue;
              final oldNum = _parseLogNumericValue(map['oldValue']);
              final newNum = _parseLogNumericValue(map['newValue']);
              if (oldNum != null && newNum != null && oldNum == newNum) {
                continue;
              }
              final when = log['timestamp'] ?? log['createdAt'];
              items.add({
                'title': 'Fine amount updated',
                'headline': [
                  _formatLogTime(when),
                  '${_formatFineAmountForLog(oldNum)} → ${_formatFineAmountForLog(newNum)}',
                ].where((e) => e.isNotEmpty).join(' | '),
                'subtitle': _formatLogByline(
                  log['performedByName']?.toString(),
                  when,
                ),
                'imageUrl': null,
                'tileIcon': 'fine',
                'sortMs': logSortMsFrom(when),
              });
            }
          }
          continue;
        }
        if (!const {
          'PUNCH_IN',
          'PUNCH_OUT',
          'BREAK_START',
          'BREAK_END',
        }.contains(action)) {
          continue;
        }
        final when = switch (action) {
          'PUNCH_OUT' => log['punchOutDateTime'] ?? log['timestamp'],
          'PUNCH_IN' => log['punchInDateTime'] ?? log['timestamp'],
          'BREAK_START' => log['breakStartDateTime'] ?? log['timestamp'],
          'BREAK_END' => log['breakEndDateTime'] ?? log['timestamp'],
          _ =>
            log['timestamp'] ??
                log['punchOutDateTime'] ??
                log['punchInDateTime'],
        };
        final title = switch (action) {
          'PUNCH_IN' => 'Punched In',
          'PUNCH_OUT' => 'Punched Out',
          'BREAK_START' => 'Started Break',
          'BREAK_END' => 'Ended Break',
          _ => action.replaceAll('_', ' ').trim(),
        };
        final address = switch (action) {
          'PUNCH_OUT' => log['punchOutAddress']?.toString(),
          'PUNCH_IN' => log['punchInAddress']?.toString(),
          'BREAK_START' => log['breakStartAddress']?.toString(),
          'BREAK_END' => log['breakEndAddress']?.toString(),
          _ => null,
        };
        final breakDuration = action == 'BREAK_END'
            ? _formatBreakDuration(log['totalBreakSeconds'])
            : null;
        final headlineParts = [
          _formatLogTime(when),
          if (branchName != null && branchName.trim().isNotEmpty)
            branchName.trim(),
          if (breakDuration != null && breakDuration.isNotEmpty) breakDuration,
          if (address != null && address.trim().isNotEmpty) address.trim(),
        ];
        items.add({
          'title': title,
          'headline': headlineParts.whereType<String>().join(' | '),
          'subtitle': _formatLogByline(
            log['performedByName']?.toString(),
            when,
          ),
          'imageUrl': log['selfieUrl']?.toString(),
          'tileIcon': null,
          'sortMs': logSortMsFrom(when),
        });
      }
    } else {
      if (punchOut != null) {
        final headlineParts = [
          _formatLogTime(punchOut),
          if (branchName != null && branchName.trim().isNotEmpty)
            branchName.trim(),
        ];
        items.add({
          'title': 'Punched Out',
          'headline': headlineParts.join(' | '),
          'subtitle': _formatLogByline(null, punchOut),
          'imageUrl': punchOutSelfieUrl,
          'tileIcon': null,
          'sortMs': logSortMsFrom(punchOut),
        });
      }
      if (punchIn != null) {
        final headlineParts = [
          _formatLogTime(punchIn),
          if (branchName != null && branchName.trim().isNotEmpty)
            branchName.trim(),
        ];
        items.add({
          'title': 'Punched In',
          'headline': headlineParts.join(' | '),
          'subtitle': _formatLogByline(null, punchIn),
          'imageUrl': punchInSelfieUrl,
          'tileIcon': null,
          'sortMs': logSortMsFrom(punchIn),
        });
      }
    }

    items.sort((a, b) {
      final aMs = (a['sortMs'] as num?)?.toInt() ?? -1;
      final bMs = (b['sortMs'] as num?)?.toInt() ?? -1;
      return aMs.compareTo(bMs);
    });

    return items
        .map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _buildAttendanceLogTile(item),
          ),
        )
        .toList();
  }

  Widget _buildAttendanceLogTile(Map<String, dynamic> item) {
    final imageUrl = item['imageUrl']?.toString();
    final hasImage = imageUrl != null && imageUrl.startsWith('http');
    final subtitle = item['subtitle']?.toString();
    final headline = item['headline']?.toString() ?? '';
    final tileIcon = item['tileIcon']?.toString();

    Widget leading;
    if (tileIcon == 'rejection') {
      leading = Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          color: Colors.red.shade50,
        ),
        child: Icon(Icons.cancel_rounded, size: 20, color: Colors.red.shade700),
      );
    } else if (tileIcon == 'approval') {
      leading = Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          color: Colors.green.shade50,
        ),
        child: Icon(
          Icons.check_circle_rounded,
          size: 20,
          color: Colors.green.shade700,
        ),
      );
    } else if (tileIcon == 'fine') {
      leading = Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          color: Colors.amber.shade50,
        ),
        child: Icon(
          Icons.currency_rupee_rounded,
          size: 20,
          color: Colors.amber.shade900,
        ),
      );
    } else if (hasImage) {
      // Punch-in / punch-out selfie — render a proper, tappable thumbnail.
      leading = GestureDetector(
        onTap: () => _showSelfieDialog(imageUrl, item['title']),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.25),
              ),
              image: DecorationImage(
                image: CachedNetworkImageProvider(imageUrl),
                fit: BoxFit.cover,
              ),
            ),
          ),
        ),
      );
    } else {
      leading = Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          color: Colors.orange.shade100,
        ),
        child: Icon(
          Icons.access_time_rounded,
          size: 18,
          color: AppColors.primary,
        ),
      );
    }

    return Row(
      crossAxisAlignment:
          hasImage ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        leading,
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${item['title']} ${headline.isNotEmpty ? 'at $headline' : ''}',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (subtitle != null && subtitle.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatLogTime(dynamic value) {
    if (value == null) return 'N/A';
    final date = _parseAnyDateTimeToLocal(value);
    if (date == null) return value.toString();
    return DateFormat('hh:mm a').format(date);
  }

  String? _formatBreakDuration(dynamic totalSeconds) {
    if (totalSeconds == null) return null;
    final seconds = totalSeconds is num
        ? totalSeconds.toInt()
        : int.tryParse(totalSeconds.toString());
    if (seconds == null || seconds <= 0) return null;
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    if (minutes <= 0) {
      return '$remainingSeconds sec';
    }
    if (remainingSeconds == 0) {
      return '$minutes min';
    }
    return '$minutes min $remainingSeconds sec';
  }

  String? _formatLogByline(String? name, dynamic value) {
    final cleanName = name?.trim();
    final when = _formatLogDateWithTime(value);
    if ((cleanName == null || cleanName.isEmpty) && when == null) return null;
    if (cleanName == null || cleanName.isEmpty) return when;
    if (when == null) return 'By $cleanName';
    return 'By $cleanName on $when';
  }

  String? _formatLogDateWithTime(dynamic value) {
    if (value == null) return null;
    final date = _parseAnyDateTimeToLocal(value);
    if (date == null) return null;
    return DateFormat('dd MMM, hh:mm a').format(date);
  }

  DateTime? _parseAnyDateTimeToLocal(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value.isUtc ? value.toLocal() : value;
    if (value is Map) {
      final raw = value[r'$date'] ?? value['date'] ?? value['Date'];
      if (raw == null) return null;
      return _parseAnyDateTimeToLocal(raw);
    }
    if (value is num) {
      final n = value.round();
      final abs = n.abs();
      final ms = abs >= 10000000000 ? n : n * 1000;
      return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toLocal();
    }
    final s = value.toString().trim();
    if (s.isEmpty) return null;
    if (RegExp(r'^\d{10,16}$').hasMatch(s)) {
      return _parseAnyDateTimeToLocal(int.tryParse(s));
    }
    final d = DateTime.tryParse(s);
    if (d == null) return null;
    return d.toLocal();
  }

  double? _parseLogNumericValue(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is Map) {
      final m = Map<String, dynamic>.from(v);
      final nd = m[r'$numberDouble'];
      if (nd != null) return double.tryParse(nd.toString());
      final ni = m[r'$numberInt'];
      if (ni != null) return (ni as num).toDouble();
    }
    return double.tryParse(v.toString());
  }

  String _formatFineAmountForLog(double? v) {
    if (v == null) return '—';
    return '₹${NumberFormat('#,##0.00').format(v)}';
  }

  /// Section header + content box (matches salary breakdown form style)
  Widget _buildDayDetailSection(
    String title,
    IconData icon,
    List<Widget> children,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: AppColors.primary),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ),
      ],
    );
  }

  /// Row for section content (matches salary breakdown form style)
  Widget _buildDayDetailRow(
    String label,
    String value, {
    Color? valueColor,
    bool isBold = false,
    bool isFullWidth = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: isFullWidth
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
                    color: valueColor ?? Colors.black87,
                  ),
                  textAlign: TextAlign.left,
                ),
              ],
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                  ),
                ),
                const SizedBox(width: 16),
                Flexible(
                  child: Text(
                    value,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
                      color: valueColor ?? Colors.black87,
                    ),
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildDetailRow(
    String label,
    String value,
    IconData icon, [
    Color? valueColor,
  ]) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: AppColors.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: valueColor ?? AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _showWarningAlert(
    String message, {
    bool isLate = false,
    bool isEarly = false,
  }) async {
    final fullMessage = (isLate || isEarly)
        ? message
        : await AttendanceTemplateStore.appendRequireSelfieGeolocationToMessage(
            message,
          );
    if (!mounted) return;
    return showDialog<void>(
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
        final String? shiftTimingLine = (isLate || isEarly)
            ? _shiftTimingSummaryForWarningDialog()
            : null;

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
    } catch (_) {}
    return null;
  }

  String _buildLateAlertMessage({
    required String baseMessage,
    required int lateMinutes,
    required double fineAmount,
  }) {
    final formattedFine = NumberFormat('#,##0.00').format(fineAmount);
    return '$baseMessage\n'
        'LateMinutes: $lateMinutes\n'
        'Fine: ₹$formattedFine';
  }

  String _buildEarlyAlertMessage({
    required String baseMessage,
    required int earlyMinutes,
    required double fineAmount,
  }) {
    final formattedFine = NumberFormat('#,##0.00').format(fineAmount);
    return '$baseMessage\n'
        'EarlyMinutes: $earlyMinutes\n'
        'Fine: ₹$formattedFine';
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

      // Matching logic must mirror backend: rule matches when applyTo is null/empty,
      // or equals the punch type, or equals 'both'.
      final match = rules.cast<Map>().firstWhere((r) {
        final applyTo = r['applyTo'];
        if (applyTo == null) return true;
        final s = applyTo.toString();
        return s == actionApplyToType || s == 'both';
      }, orElse: () => <String, dynamic>{});

      final hasMatch = match.isNotEmpty && match['type'] != null;
      if (hasMatch) {
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
    final amount = hourlyRate * hours * multiplier;
    debugPrint(
      '[Fine] Rule Result: hourlyRate=$hourlyRate, hours=$hours, multiplier=$multiplier => amount=$amount',
    );
    return amount;
  }

  Future<Map<String, dynamic>> _buildFinePayloadForPunch({
    required bool isCheckedIn,
  }) async {
    // Always compute with the latest backend fine config.
    await _fetchFineCalculation();
    int lateMinutes = 0;
    int earlyMinutes = 0;
    double fineAmount = 0;
    final now = DateTime.now();
    final netPerDaySalary = await _loadPerDaySalaryFromPrefs();
    final sessionTimings = _getWorkingSessionTimings();

    if (!isCheckedIn) {
      if (_isOpenShiftTemplate()) {
        lateMinutes = 0;
        fineAmount = 0;
      } else {
        final shiftStartStr =
            sessionTimings?['startTime'] ?? _getShiftStartTimeFromDb();
        if (shiftStartStr != null && shiftStartStr.isNotEmpty) {
          try {
            final parts = shiftStartStr.split(':').map(int.parse).toList();
            final gracePeriod = _getGracePeriodMinutesForLateCheckIn();
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
                  sessionTimings?['endTime'] ?? _getShiftEndTime();
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
              final hasRules = _hasFineRules();
              final lateRule = _matchFineRuleForAction('lateArrival');
              if (hasRules) {
                if (lateRule == null) {
                  fineAmount = 0.0;
                } else {
                  final shiftHoursForFine = calculateShiftHours(
                    shiftStartStr,
                    shiftEndForFine,
                  );
                  fineAmount = _computeFineFromRule(
                    rule: lateRule,
                    minutes: lateMinutes,
                    netPerDaySalary: netPerDaySalary ?? 0.0,
                    shiftHours: shiftHoursForFine,
                  );
                }
              }
            }
          } catch (_) {}
        }
      }
    } else {
      lateMinutes = (_attendanceData?['lateMinutes'] as num?)?.toInt() ?? 0;
      final existingFineAmount =
          (_attendanceData?['fineAmount'] as num?)?.toDouble() ?? 0.0;
      if (_isOpenShiftTemplate()) {
        final punchInRaw = _attendanceData?['punchIn'];
        if (punchInRaw != null) {
          try {
            final punchIn = DateTime.parse(punchInRaw.toString()).toLocal();
            final reqH = _openShiftRequiredHours();
            final requiredMin = (reqH * 60).round();
            final workedMin = now.difference(punchIn).inMinutes;
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
            sessionTimings?['endTime'] ?? _getShiftEndTimeFromDb();
        final shiftStartForFine =
            sessionTimings?['startTime'] ?? _getShiftStartTime();
        if (shiftEndStr != null && shiftEndStr.isNotEmpty) {
          try {
            // Anchor to punch-in so overnight shifts (PM start / AM end)
            // resolve the end boundary on the correct calendar day.
            final punchInRaw = _attendanceData?['punchIn'];
            final punchInDt = punchInRaw != null
                ? DateTime.tryParse(punchInRaw.toString())?.toLocal()
                : null;
            final shiftEnd = _resolveShiftEndForEarly(
              shiftStartStr: shiftStartForFine,
              shiftEndStr: shiftEndStr,
              anchor: punchInDt ?? now,
            );
            if (shiftEnd != null && now.isBefore(shiftEnd)) {
              earlyMinutes = shiftEnd.difference(now).inMinutes;
              final shiftHours = calculateShiftHours(
                shiftStartForFine,
                shiftEndStr,
              );
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

    if (kDebugMode) {
      debugPrint(
        '[Fine TEST][Attendance][Payload] isCheckout=$isCheckedIn '
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

  /// Shows a popup alert for check-in/check-out validation failures (blocks marking attendance).
  /// Uses the same UI style as the "You are late" / "You are early" dialog.
  Future<void> _showValidationAlert(String message) async {
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

  // Used when attendance settings icon is shown in app bar (currently hidden)
  // ignore: unused_element
  void _showAttendanceSettings() {
    if (!isValidAttendanceTemplateMap(_attendanceTemplate)) {
      SnackBarUtils.showSnackBar(
        context,
        'Attendance settings not available',
        isError: true,
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Attendance Settings',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _attendanceTemplate?['name'] ?? 'Default Template',
                style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 24),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSettingItem(
                        'Geolocation',
                        _attendanceTemplate?['requireGeolocation'] ?? false,
                        'Required',
                        'Not Required',
                      ),
                      const SizedBox(height: 16),
                      _buildSettingItem(
                        'Selfie',
                        _attendanceTemplate?['requireSelfie'] ?? false,
                        'Required',
                        'Not Required',
                      ),
                      const SizedBox(height: 16),
                      _buildSettingItem(
                        'Late Entry',
                        _attendanceTemplate?['lateEntryAllowed'] ??
                            _attendanceTemplate?['allowLateEntry'] ??
                            true,
                        'Allowed',
                        'Not Allowed',
                      ),
                      const SizedBox(height: 16),
                      _buildSettingItem(
                        'Early Exit',
                        _attendanceTemplate?['earlyExitAllowed'] ??
                            _attendanceTemplate?['allowEarlyExit'] ??
                            true,
                        'Allowed',
                        'Not Allowed',
                      ),
                      const SizedBox(height: 16),
                      _buildSettingItem(
                        'Overtime',
                        _attendanceTemplate?['overtimeAllowed'] ??
                            _attendanceTemplate?['allowOvertime'] ??
                            true,
                        'Allowed',
                        'Not Allowed',
                      ),
                      const SizedBox(height: 16),
                      _buildSettingItem(
                        'Attendance on Holidays',
                        _attendanceTemplate?['allowAttendanceOnHolidays'] ??
                            false,
                        'Allowed',
                        'Not Allowed',
                      ),
                      const SizedBox(height: 16),
                      _buildSettingItem(
                        'Attendance on Weekly Off',
                        _attendanceTemplate?['allowAttendanceOnWeeklyOff'] ??
                            false,
                        'Allowed',
                        'Not Allowed',
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSettingItem(
    String label,
    bool value,
    String trueLabel,
    String falseLabel,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: value
                ? AppColors.success.withOpacity(0.1)
                : Colors.red.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: value ? AppColors.success : Colors.red,
              width: 1,
            ),
          ),
          child: Text(
            value ? trueLabel : falseLabel,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: value ? AppColors.success : Colors.red,
            ),
          ),
        ),
      ],
    );
  }

  /// Full merged `/attendance/today` template for [shiftsListFromCompany] (nested `settings` or root `attendance.shifts`).
  Map<String, dynamic>? _shiftResolutionCompanyDocFromTemplate() {
    final t = _attendanceTemplate;
    if (t == null || t.isEmpty) return null;
    return Map<String, dynamic>.from(t);
  }

  /// Standard shift window from [appliedShiftId] + business embedded shifts (when set on the record).
  Map<String, String>? _appliedShiftSessionTimesForRecord(
    Map<String, dynamic>? record,
  ) {
    if (record == null) return null;
    if (record['appliedShiftId'] == null) return null;
    final resolved = appliedShiftPastResolvedFromCompany(
      companyDoc: _companyDocForAppliedShiftResolution(),
      appliedShiftId: record['appliedShiftId'],
    );
    if (resolved == null ||
        resolved.isOpen ||
        resolved.startTime == null ||
        resolved.endTime == null) {
      return null;
    }
    final a = resolved.startTime!.trim();
    final b = resolved.endTime!.trim();
    if (a.isEmpty || b.isEmpty) return null;
    return {'startTime': a, 'endTime': b};
  }

  bool _isOpenShiftForRecordEvaluation(Map<String, dynamic>? record) {
    if (record != null && record['appliedShiftId'] != null) {
      final r = appliedShiftPastResolvedFromCompany(
        companyDoc: _companyDocForAppliedShiftResolution(),
        appliedShiftId: record['appliedShiftId'],
      );
      if (r != null) return r.isOpen;
    }
    return _isOpenShiftTemplate();
  }

  double _openShiftRequiredHoursForRecord(Map<String, dynamic>? record) {
    if (record != null && record['appliedShiftId'] != null) {
      final r = appliedShiftPastResolvedFromCompany(
        companyDoc: _companyDocForAppliedShiftResolution(),
        appliedShiftId: record['appliedShiftId'],
      );
      if (r != null && r.isOpen) {
        final h = r.openWorkHours;
        if (h != null && h > 0) return h;
      }
    }
    return _openShiftRequiredHours();
  }

  int _shiftSpanMinutesForPresentRecord(Map<String, dynamic> record) {
    if (record['appliedShiftId'] != null) {
      final r = appliedShiftPastResolvedFromCompany(
        companyDoc: _companyDocForAppliedShiftResolution(),
        appliedShiftId: record['appliedShiftId'],
      );
      if (r != null) {
        if (r.isOpen) {
          final h = r.openWorkHours;
          if (h != null && h > 0) return (h * 60).round();
        } else if (r.startTime != null &&
            r.endTime != null &&
            r.startTime!.isNotEmpty &&
            r.endTime!.isNotEmpty) {
          return (calculateShiftHours(r.startTime!, r.endTime!) * 60).round();
        }
      }
    }
    return _getShiftHoursMinutes();
  }

  int _halfDayMinutesThresholdForRecord(Map<String, dynamic> record) {
    final full = _shiftSpanMinutesForPresentRecord(record);
    return full ~/ 2;
  }

  String _shiftLabelForAttendanceDetail(Map<String, dynamic> record) {
    if (record['appliedShiftId'] != null) {
      final r = appliedShiftPastResolvedFromCompany(
        companyDoc: _companyDocForAppliedShiftResolution(),
        appliedShiftId: record['appliedShiftId'],
      );
      if (r != null && r.shiftName.isNotEmpty) return r.shiftName;
    }
    final fromRecord = (record['shiftName'] ?? '').toString().trim();
    if (fromRecord.isNotEmpty) {
      return fromRecord;
    }
    final tName =
        (_attendanceTemplate?['name'] ?? _attendanceTemplate?['shiftName'])
            ?.toString()
            .trim();
    if (tName != null && tName.isNotEmpty) return tName;
    return 'Shift';
  }

  String _shiftTimeLineForAttendanceDetail(Map<String, dynamic> record) {
    final statusLower = (record['status'] ?? '').toString().toLowerCase();
    final compensationLower =
        (record['compensationType'] ?? '').toString().toLowerCase();
    final dateKey = _dateKey(record);
    final isWeekOffRecord =
        statusLower == 'weekend' ||
        statusLower == 'week off' ||
        compensationLower == 'weekoff' ||
        (dateKey.isNotEmpty &&
            _weekOffDateSet.contains(dateKey) &&
            !_alternateWorkDatesInMonth.contains(dateKey));
    // Hide shift timing text for week-off days.
    if (isWeekOffRecord) return '';

    if (record['appliedShiftId'] != null) {
      final r = appliedShiftPastResolvedFromCompany(
        companyDoc: _companyDocForAppliedShiftResolution(),
        appliedShiftId: record['appliedShiftId'],
      );
      if (r != null) {
        if (r.isOpen) {
          final h = r.openWorkHours ?? 8.0;
          final label = h == h.roundToDouble()
              ? '${h.toInt()}'
              : h.toStringAsFixed(1);
          return 'Open shift · $label hrs required';
        }
        final a = r.startTime;
        final b = r.endTime;
        if (a == null || b == null) return 'N/A - N/A';
        return '${_formatShiftTime12(a)} - ${_formatShiftTime12(b)}';
      }
    }
    if (_isOpenShiftTemplate()) {
      final h = _openShiftRequiredHours();
      final label = h == h.roundToDouble()
          ? '${h.toInt()}'
          : h.toStringAsFixed(1);
      return 'Open shift · $label hrs required';
    }
    final halfDayTimings = _getWorkingSessionTimingsForRecord(record);
    final start = halfDayTimings != null
        ? halfDayTimings['startTime'] ?? 'N/A'
        : _attendanceTemplate?['shiftStartTime']?.toString() ?? 'N/A';
    final end = halfDayTimings != null
        ? halfDayTimings['endTime'] ?? 'N/A'
        : _attendanceTemplate?['shiftEndTime']?.toString() ?? 'N/A';
    if (start == 'N/A' || end == 'N/A') return '$start - $end';
    return '${_formatShiftTime12(start)} - ${_formatShiftTime12(end)}';
  }

  /// Grace period in minutes from DB (template). Prefers [gracePeriodMinutes],
  /// then [settings.attendance.shifts[0].graceTime]. Defaults to 15 only when absent.
  int _getGracePeriodMinutes() {
    final template = _attendanceTemplate;
    if (template == null) return 15;

    // Prefer flat gracePeriodMinutes (set by backend from company settings)
    final flat = template['gracePeriodMinutes'];
    if (flat != null) {
      if (flat is int) return flat;
      final parsed = int.tryParse(flat.toString());
      if (parsed != null) return parsed;
    }

    // Fallback: nested settings.attendance.shifts[0].graceTime
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

  /// Shift start time from DB (template). Single fallback when template not loaded.
  String _getShiftStartTime() {
    return _attendanceTemplate?['shiftStartTime']?.toString().trim() ?? '09:30';
  }

  /// Shift end time from DB (template). Single fallback when template not loaded.
  String _getShiftEndTime() {
    return _attendanceTemplate?['shiftEndTime']?.toString().trim() ?? '18:30';
  }

  /// Shift start from DB only (no fallback). Use for notice message so we never show hardcoded time.
  String? _getShiftStartTimeFromDb() {
    final v = _attendanceTemplate?['shiftStartTime']?.toString().trim();
    return (v != null && v.isNotEmpty) ? v : null;
  }

  /// Shift end from DB only (no fallback). Use for notice message so we never show hardcoded time.
  String? _getShiftEndTimeFromDb() {
    final v = _attendanceTemplate?['shiftEndTime']?.toString().trim();
    return (v != null && v.isNotEmpty) ? v : null;
  }

  /// Resolves the real shift-end DateTime for early-checkout math, handling
  /// overnight shifts (PM start / AM end, e.g. 21:00→06:00).
  ///
  /// Reconstructing the end clock-time on the same calendar day as the start is
  /// wrong for overnight shifts: the AM end lands *before* the PM start. Instead
  /// we anchor the shift start to the punch-in day and add the shift duration
  /// (which [calculateShiftHours] already computes correctly across midnight).
  ///
  /// [anchor] should be the punch-in time when available, else the punch-out
  /// time. Returns null if the times can't be parsed.
  DateTime? _resolveShiftEndForEarly({
    required String shiftStartStr,
    required String shiftEndStr,
    required DateTime anchor,
  }) {
    try {
      final startParts = shiftStartStr.split(':').map(int.parse).toList();
      final endParts = shiftEndStr.split(':').map(int.parse).toList();
      final startMinOfDay =
          startParts[0] * 60 + (startParts.length > 1 ? startParts[1] : 0);
      final endMinOfDay =
          endParts[0] * 60 + (endParts.length > 1 ? endParts[1] : 0);
      final isOvernight = endMinOfDay <= startMinOfDay;

      var shiftStartDt = DateTime(
        anchor.year,
        anchor.month,
        anchor.day,
        startParts[0],
        startParts.length > 1 ? startParts[1] : 0,
      );
      // Overnight shift where the anchor (punch-in) is after midnight means the
      // shift actually began the previous calendar day.
      if (isOvernight && (anchor.hour * 60 + anchor.minute) < startMinOfDay) {
        shiftStartDt = shiftStartDt.subtract(const Duration(days: 1));
      }

      final shiftHours = calculateShiftHours(shiftStartStr, shiftEndStr);
      return shiftStartDt.add(Duration(minutes: (shiftHours * 60).round()));
    } catch (_) {
      return null;
    }
  }

  static String _formatHhMmForDisplay(String hhmm) {
    final parts = hhmm.split(':');
    final h = int.tryParse(parts[0].trim()) ?? 0;
    final m = parts.length > 1 ? (int.tryParse(parts[1].trim()) ?? 0) : 0;
    final hour = h % 12 == 0 ? 12 : h % 12;
    final ampm = h < 12 ? 'AM' : 'PM';
    if (m == 0) return '$hour:00 $ampm';
    return '$hour:${m.toString().padLeft(2, '0')} $ampm';
  }

  /// One-line friendly shift window (half-day working session when applicable).
  String? _shiftTimingSummaryForWarningDialog() {
    if (_isOpenShiftTemplate()) return null;
    final session = _getWorkingSessionTimings();
    final startRaw = session?['startTime'] ?? _getShiftStartTimeFromDb();
    final endRaw = session?['endTime'] ?? _getShiftEndTimeFromDb();
    if (startRaw == null ||
        endRaw == null ||
        startRaw.isEmpty ||
        endRaw.isEmpty) {
      return null;
    }
    // Web-style 24h window (same as dashboard calendar cells)
    return '$startRaw-$endRaw';
  }

  String _formatHalfDaySessionLabel(String session) {
    final b = _getHalfDaySessionBoundaries();
    if (b == null) {
      return session == '1'
          ? 'Session 1 (First Half)'
          : 'Session 2 (Second Half)';
    }
    if (session == '1') {
      return 'Session 1 (${_formatHhMmForDisplay(b['session1Start']!)} – ${_formatHhMmForDisplay(b['session1End']!)})';
    }
    return 'Session 2 (${_formatHhMmForDisplay(b['session2Start']!)} – ${_formatHhMmForDisplay(b['session2End']!)})';
  }

  // Half-day session boundaries from shift: equal halves. Session 1 = first (total/2) hrs, Session 2 = next (total/2) hrs.
  // E.g. 10:00–19:00 (9h) → Session 1 = 10:00–14:30, Session 2 = 14:30–19:00. Matches backend getHalfDaySessionBoundaries.
  Map<String, String>? _getHalfDaySessionBoundaries() {
    final shiftStartStr = _getShiftStartTimeFromDb();
    final shiftEndStr = _getShiftEndTimeFromDb();
    if (shiftStartStr == null || shiftEndStr == null) return null;
    try {
      final startParts = shiftStartStr.split(':').map(int.parse).toList();
      final endParts = shiftEndStr.split(':').map(int.parse).toList();
      int startTotalMinutes =
          startParts[0] * 60 + (startParts.length > 1 ? startParts[1] : 0);
      int endTotalMinutes =
          endParts[0] * 60 + (endParts.length > 1 ? endParts[1] : 0);
      if (endTotalMinutes <= startTotalMinutes) endTotalMinutes += 24 * 60;
      final durationMinutes = endTotalMinutes - startTotalMinutes;
      final halfMinutes = durationMinutes ~/ 2;
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
    } catch (e) {
      return null;
    }
  }

  // Helper to get working session timings for Half Day (when employee is working, not on leave).
  // Session 1 leave → employee works Session 2. Session 2 leave → employee works Session 1.
  Map<String, String>? _getWorkingSessionTimings() {
    final bool isHalfDay =
        (_attendanceData?['status'] == 'Half Day') || _halfDayLeave != null;
    if (!isHalfDay) return null;

    final session =
        _halfDayLeave?['session']?.toString().trim() ??
        _attendanceData?['session']?.toString().trim();

    if (session != '1' && session != '2') return null;

    final b = _getHalfDaySessionBoundaries();
    if (b == null) return null;

    if (session == '1') {
      return {'startTime': b['session2Start']!, 'endTime': b['session2End']!};
    }
    if (session == '2') {
      return {'startTime': b['session1Start']!, 'endTime': b['session1End']!};
    }
    return null;
  }

  /// Working session timings for a specific record (e.g. from history). Use when evaluating late/early for that record.
  /// Session 1 leave → works Session 2. Session 2 leave → works Session 1.
  /// Treats as half-day when status is 'Half Day' OR record has halfDaySession/session (e.g. "Present (HA)" with session).
  Map<String, String>? _getWorkingSessionTimingsForRecord(
    Map<String, dynamic>? record,
  ) {
    if (record == null) return null;
    final status = (record['status'] ?? '').toString().trim().toLowerCase();
    final leaveDetails = record['leaveDetails'] as Map<String, dynamic>?;
    final leaveType = (leaveDetails?['leaveType'] ?? record['leaveType'])
        ?.toString()
        .trim()
        .toLowerCase();
    final rawSession = (leaveDetails?['session'] ?? record['session'])
        ?.toString()
        .trim();
    final hasHalfDaySession =
        (record['halfDaySession'] ?? leaveDetails?['halfDaySession']) != null;
    final isHalfDay =
        status == 'half day' ||
        leaveType == 'half day' ||
        hasHalfDaySession ||
        rawSession == '1' ||
        rawSession == '2';
    if (!isHalfDay) return null;
    final b = _getHalfDaySessionBoundaries();
    if (b == null) return null;
    String? session = (leaveDetails?['session'] ?? record['session'])
        ?.toString()
        .trim();
    if (session != '1' && session != '2') {
      final hd = (record['halfDaySession'] ?? leaveDetails?['halfDaySession'])
          ?.toString()
          .trim()
          .toLowerCase();
      if (hd == 'first half day' || hd == 'first half') {
        session = '1';
      } else if (hd == 'second half day' || hd == 'second half') {
        session = '2';
      } else {
        return null;
      }
    }
    if (session == '1') {
      return {'startTime': b['session2Start']!, 'endTime': b['session2End']!};
    }
    return {'startTime': b['session1Start']!, 'endTime': b['session1End']!};
  }

  /// Grace period for late check-in when evaluating a specific record (half-day: Session 1 leave = no grace).
  int _getGracePeriodMinutesForLateCheckInForRecord(
    Map<String, dynamic>? record,
  ) {
    if (record == null) return _getGracePeriodMinutes();
    if (_getWorkingSessionTimingsForRecord(record) == null) {
      return _getGracePeriodMinutes();
    }
    final leaveDetails = record['leaveDetails'] as Map<String, dynamic>?;
    final session =
        (leaveDetails?['session'] ??
                record['session'] ??
                record['halfDaySession'])
            ?.toString()
            .trim();
    final sessionLower = session?.toLowerCase();
    if (session == '1' ||
        sessionLower == 'first half day' ||
        sessionLower == 'first half') {
      return 0;
    }
    return _getGracePeriodMinutes();
  }

  /// For half-day Session 1 leave (employee works Session 2): no grace. Otherwise use template grace.
  int _getGracePeriodMinutesForLateCheckIn() {
    final session =
        _halfDayLeave?['session']?.toString().trim() ??
        _attendanceData?['session']?.toString().trim();
    if (session == '1') return 0; // Session 2 working: no grace
    return _getGracePeriodMinutes();
  }

  /// Parity with app_backend getShiftTimings: open / open shift, or shift name "OPEN".
  bool _isOpenShiftTemplate([Map<String, dynamic>? template]) {
    final t = template ?? _attendanceTemplate;
    if (t == null) return false;
    final st = (t['shiftType'] ?? '').toString().toLowerCase().trim();
    if (st == 'open' || st == 'open shift') return true;
    final name = (t['shiftName'] ?? t['name'] ?? '')
        .toString()
        .toLowerCase()
        .trim();
    if (name == 'open' || name == 'open shift') return true;
    return false;
  }

  double _openShiftRequiredHours([Map<String, dynamic>? template]) {
    final t = template ?? _attendanceTemplate;
    if (t == null || !_isOpenShiftTemplate(t)) return 8;
    for (final key in ['openWorkHours', 'workHours']) {
      final v = t[key];
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

  /// Returns (emoji, message) for check-in success overlay: before shift = very happy, after shift = happy, in grace = somewhat sad.
  ({String emoji, String message}) _getCheckInOverlayEmojiAndMessage(
    String userName,
  ) {
    final name = userName.isNotEmpty ? userName : 'there';
    if (_isOpenShiftTemplate()) {
      return (
        emoji: '😊',
        message: 'Hey $name, you have checked in. Have a productive day!',
      );
    }
    final sessionTimings = _getWorkingSessionTimings();
    final shiftStartStr =
        sessionTimings?['startTime'] ??
        _getShiftStartTimeFromDb() ??
        _getShiftStartTime();
    if (shiftStartStr.isEmpty) {
      return (
        emoji: '😊',
        message: 'Hey $name, you have checked in. Have a productive day!',
      );
    }
    final parts = shiftStartStr
        .split(':')
        .map((s) => int.tryParse(s.trim()) ?? 0)
        .toList();
    final now = DateTime.now();
    final shiftStart = DateTime(
      now.year,
      now.month,
      now.day,
      parts.isNotEmpty ? parts[0] : 9,
      parts.length > 1 ? parts[1] : 0,
    );
    final graceMinutes = _getGracePeriodMinutesForLateCheckIn();
    final graceEnd = shiftStart.add(Duration(minutes: graceMinutes));

    if (now.isBefore(shiftStart)) {
      return (emoji: '😄', message: "You're early! Have a great day!");
    }
    if (!now.isAfter(graceEnd)) {
      return (emoji: '😕', message: 'You checked in within grace time.');
    }
    // Late (after grace): use requested late-login emoji.
    return (emoji: '😕', message: 'You have checked in.');
  }

  // Helper to determine if late. Pass [record] when evaluating a specific record (e.g. history) so half-day uses that record's session.
  bool _isLateCheckIn(String? punchInTime, {Map<String, dynamic>? record}) {
    if (punchInTime == null) return false;
    final openEval = record != null
        ? _isOpenShiftForRecordEvaluation(record)
        : _isOpenShiftTemplate();
    if (openEval) return false;
    try {
      final punchIn = DateTime.parse(punchInTime).toLocal();

      // Half-day working session wins; else [appliedShiftId] window when set; else template.
      Map<String, String>? sessionTimings = record != null
          ? _getWorkingSessionTimingsForRecord(record)
          : _getWorkingSessionTimings();
      if (sessionTimings == null && record != null) {
        sessionTimings = _appliedShiftSessionTimesForRecord(record);
      }
      final shiftStartStr =
          sessionTimings?['startTime'] ?? _getShiftStartTime();
      final parts = shiftStartStr.split(':').map(int.parse).toList();
      final gracePeriod = record != null
          ? _getGracePeriodMinutesForLateCheckInForRecord(record)
          : _getGracePeriodMinutesForLateCheckIn();

      final shiftStart = DateTime(
        punchIn.year,
        punchIn.month,
        punchIn.day,
        parts[0],
        parts[1],
      ).add(Duration(minutes: gracePeriod));

      return punchIn.isAfter(shiftStart);
    } catch (e) {
      return false;
    }
  }

  bool _isLateCheckOut(String? punchOutTime, {Map<String, dynamic>? record}) {
    if (punchOutTime == null) return false;
    final openEval = record != null
        ? _isOpenShiftForRecordEvaluation(record)
        : _isOpenShiftTemplate();
    if (openEval) return false;
    try {
      final punchOut = DateTime.parse(punchOutTime).toLocal();

      Map<String, String>? sessionTimings = record != null
          ? _getWorkingSessionTimingsForRecord(record)
          : _getWorkingSessionTimings();
      if (sessionTimings == null && record != null) {
        sessionTimings = _appliedShiftSessionTimesForRecord(record);
      }
      final shiftEndStr = sessionTimings?['endTime'] ?? _getShiftEndTime();
      final parts = shiftEndStr.split(':').map(int.parse).toList();

      final shiftEnd = DateTime(
        punchOut.year,
        punchOut.month,
        punchOut.day,
        parts[0],
        parts[1],
      );

      return punchOut.isAfter(shiftEnd);
    } catch (e) {
      return false;
    }
  }

  bool _isEarlyCheckOut(String? punchOutTime, {Map<String, dynamic>? record}) {
    if (punchOutTime == null) return false;
    try {
      final punchOut = DateTime.parse(punchOutTime).toLocal();

      final openEval = record != null
          ? _isOpenShiftForRecordEvaluation(record)
          : _isOpenShiftTemplate();
      if (openEval) {
        final punchInRaw = record?['punchIn'];
        if (punchInRaw == null) return false;
        final punchIn = DateTime.parse(punchInRaw.toString()).toLocal();
        final worked = punchOut.difference(punchIn).inMinutes;
        final requiredH = record != null
            ? _openShiftRequiredHoursForRecord(record)
            : _openShiftRequiredHours();
        final required = (requiredH * 60).round();
        return worked < required;
      }

      Map<String, String>? sessionTimings = record != null
          ? _getWorkingSessionTimingsForRecord(record)
          : _getWorkingSessionTimings();
      if (sessionTimings == null && record != null) {
        sessionTimings = _appliedShiftSessionTimesForRecord(record);
      }
      final shiftEndStr = sessionTimings?['endTime'] ?? _getShiftEndTime();
      final shiftStartStr = sessionTimings?['startTime'] ?? _getShiftStartTime();

      // Anchor to punch-in so overnight shifts (PM start / AM end) resolve the
      // end boundary on the correct calendar day instead of the same morning.
      final punchInRaw = record?['punchIn'];
      final punchInDt = punchInRaw != null
          ? DateTime.tryParse(punchInRaw.toString())?.toLocal()
          : null;
      final shiftEnd = _resolveShiftEndForEarly(
        shiftStartStr: shiftStartStr,
        shiftEndStr: shiftEndStr,
        anchor: punchInDt ?? punchOut,
      );
      if (shiftEnd == null) return false;

      return punchOut.isBefore(shiftEnd);
    } catch (e) {
      return false;
    }
  }

  DateTime? _profileJoiningDateForShiftResolution() {
    final snap = _profileStaffDataSnapshot;
    if (snap == null) return null;
    return parseJoiningDate(snap['joiningDate']);
  }

  /// First day of the employee's joining month. The attendance calendar must not
  /// display months before this — there are no attendance records before the
  /// Date of Joining. Returns null when the joining date is unknown (no clamp).
  DateTime? get _joiningMonthStart {
    final doj = _profileJoiningDateForShiftResolution();
    if (doj == null) return null;
    return DateTime(doj.year, doj.month, 1);
  }

  /// True when [_focusedDay] is already at (or before) the joining month, so the
  /// calendar cannot navigate further back.
  bool get _isAtOrBeforeJoiningMonth {
    final start = _joiningMonthStart;
    if (start == null) return false;
    final focusedMonth = DateTime(_focusedDay.year, _focusedDay.month, 1);
    return !focusedMonth.isAfter(start);
  }

  bool _isTodayAssignedRotationalWeekOff() {
    final companyDoc = _companyDocForAppliedShiftResolution();
    if (companyDoc == null) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final effective = effectiveShiftForCalendarDay(
      companyDoc: companyDoc,
      staffShiftKey: _profileStaffShiftName,
      dayLocal: today,
      joiningDate: _profileJoiningDateForShiftResolution(),
      attendanceTodayTemplate: _attendanceTemplate,
    );
    return effective?.isWeekOff == true;
  }

  EffectiveShiftDay? _todayEffectiveShiftForAttendance() {
    final companyDoc = _companyDocForAppliedShiftResolution();
    if (companyDoc == null) return null;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return effectiveShiftForCalendarDay(
      companyDoc: companyDoc,
      staffShiftKey: _profileStaffShiftName,
      dayLocal: today,
      joiningDate: _profileJoiningDateForShiftResolution(),
      attendanceTodayTemplate: _attendanceTemplate,
    );
  }

  bool _isAssignedShiftRotationalWrapper() {
    final companyDoc = _companyDocForAppliedShiftResolution();
    final shifts = shiftsListFromCompany(companyDoc);
    final key = (_profileStaffShiftName ?? '').trim();
    if (shifts == null || shifts.isEmpty || key.isEmpty) return false;
    final wrapper = findShiftByStaffKey(shifts, key);
    if (wrapper == null) return false;
    return isRotationalShiftWrapper(wrapper);
  }

  /// Normalizes workHours to minutes. API stores in minutes; legacy values may be in hours (0–24 decimal).
  int? _workHoursToMinutes(num? workHours) {
    if (workHours == null) return null;
    final d = workHours.toDouble();
    if (d <= 0) return 0;
    // Legacy: value in (0, 24] with fraction treated as hours
    if (d < 24 && (d - d.truncate()).abs() > 0.001) {
      return (d * 60).round();
    }
    return d.round();
  }

  /// Overtime from API: stored as minutes (legacy rows may use fractional hours).
  int? _overtimeToDisplayMinutes(num? raw) {
    if (raw == null || raw <= 0) return null;
    return _workHoursToMinutes(raw);
  }

  String? _formatOvertimeForDisplay(dynamic raw) {
    final mins = _overtimeToDisplayMinutes(raw is num ? raw : null);
    if (mins == null || mins <= 0) return null;
    if (mins >= 60) {
      final h = mins ~/ 60;
      final m = mins % 60;
      if (m == 0) return '${h}h';
      return '${h}h ${m}m';
    }
    return '$mins min';
  }

  /// Open-shift OT buffer minutes from API (always stored as minutes when present).
  String? _formatOpenShiftBufferForDisplay(dynamic raw) {
    if (raw == null) return null;
    final n = raw is num ? raw.round() : int.tryParse(raw.toString());
    if (n == null || n <= 0) return null;
    if (n >= 60) {
      final h = n ~/ 60;
      final m = n % 60;
      if (m == 0) return '${h}h';
      return '${h}h ${m}m';
    }
    return '$n min';
  }

  /// Returns shift duration in minutes (from template shiftStartTime to shiftEndTime).
  int _getShiftHoursMinutes() {
    final b = _getHalfDaySessionBoundaries();
    if (b == null) return 540;
    try {
      final startParts = b['session1Start']!.split(':').map(int.parse).toList();
      final endParts = b['session2End']!.split(':').map(int.parse).toList();
      int startMins =
          (startParts.isNotEmpty ? startParts[0] : 0) * 60 +
          (startParts.length > 1 ? startParts[1] : 0);
      int endMins =
          (endParts.isNotEmpty ? endParts[0] : 0) * 60 +
          (endParts.length > 1 ? endParts[1] : 0);
      if (endMins <= startMins) endMins += 24 * 60;
      return endMins - startMins;
    } catch (_) {
      return 540;
    }
  }

  /// Returns half-day required hours in minutes (shift duration / 2).
  int _getHalfDayHoursMinutes() {
    return _getShiftHoursMinutes() ~/ 2;
  }

  /// Only show low hrs for Present and Half Day. Never for Leave, Week Off, Paid Leave.
  /// - workHours = 0: don't show low hrs
  /// - Present: show when workHours < shift hours
  /// - Half Day: show when workHours < half day hours
  bool _shouldShowLowWorkHours(dynamic record) {
    if (record == null || record is! Map) return false;
    final status = (record['status'] as String? ?? 'Present')
        .toString()
        .trim()
        .toLowerCase();
    final compType = (record['compensationType'] as String? ?? '')
        .toString()
        .toLowerCase();

    // Don't show for leave, week off, paid leave, comp off
    if (status == 'on leave') return false;
    if (compType == 'weekoff' || compType == 'compoff') return false;
    if (status == 'weekend' ||
        status == 'holiday' ||
        status == 'absent' ||
        status == 'rejected' ||
        status == 'pending') {
      return false;
    }

    // Only Present and Half Day
    final isPresent = status == 'present' || status == 'approved';
    final isHalfDay = status == 'half day';
    if (!isPresent && !isHalfDay) return false;

    num? workHours = record['workHours'] as num?;
    // Calculate from punchIn/punchOut if not present
    if (workHours == null &&
        record['punchIn'] != null &&
        record['punchOut'] != null) {
      try {
        final pi = DateTime.parse(record['punchIn'].toString()).toLocal();
        final po = DateTime.parse(record['punchOut'].toString()).toLocal();
        workHours = po.difference(pi).inMinutes;
      } catch (_) {}
    }
    if (workHours == null) return false;
    final mins = _workHoursToMinutes(workHours);
    if (mins == null || mins <= 0) return false;

    final recMap = Map<String, dynamic>.from(record as Map);
    if (isHalfDay) {
      return mins < _halfDayMinutesThresholdForRecord(recMap);
    }
    return mins < _shiftSpanMinutesForPresentRecord(recMap);
  }

  /// Formats work hours with unit "min" / "mins". Value from API is in minutes.
  String _formatWorkHoursWithUnits(num? workHours) {
    final mins = _workHoursToMinutes(workHours);
    if (mins == null) return 'N/A';
    if (mins == 0) return '0 mins';
    return '$mins min${mins == 1 ? '' : 's'}';
  }

  /// Formats work hours as HH:mm (e.g. 483 mins -> "08:03").
  String _formatWorkHoursAsHHmm(num? workHours) {
    final mins = _workHoursToMinutes(workHours);
    if (mins == null) return 'N/A';
    final h = (mins ~/ 60).toString().padLeft(2, '0');
    final m = (mins % 60).toString().padLeft(2, '0');
    return '$h:$m';
  }

  String _formatTimeShort(dynamic isoString) {
    if (isoString == null ||
        isoString.toString().isEmpty ||
        isoString == 'null') {
      return '--:--';
    }
    try {
      final date = DateTime.parse(isoString.toString()).toLocal();
      return DateFormat('hh:mm a').format(date);
    } catch (_) {
      return '--:--';
    }
  }

  /*
  // OLD calendar day builder - kept for reference (uses different color logic)
  Widget _buildCustomDay(DateTime day) {
    // ... old implementation ...
  }
  */

  Widget _buildCustomDay(BuildContext context, DateTime day) {
    final colorScheme = Theme.of(context).colorScheme;
    // Diagnostic: log the calendar's render state once per rebuild (when it draws
    // the 1st of the focused month). If colors "vanish after a second", this prints
    // at that moment and shows whether _monthData went null, the marker sets emptied,
    // or _focusedDay drifted to another month.
    if (day.day == 1 && day.month == _focusedDay.month) {
      debugPrint(
        '[Attendance][calRender] hashCode=$hashCode '
        'focused=${_focusedDay.year}-${_focusedDay.month} '
        'monthDataNull=${_monthData == null} '
        'present=${_presentDateSet.length} absent=${_absentDateSet.length} '
        'holiday=${_holidayDateSet.length} weekOff=${_weekOffDateSet.length} '
        'status=${_dayStatusByDate.length} loading=$_isLoadingMonthData '
        'historyView=$_showHistoryView',
      );
    }
    if (_monthData == null) {
      // Fallback: just show the day number with today's border if month data is unavailable
      final now = DateTime.now();
      final todayOnly = DateTime(now.year, now.month, now.day);
      final dateOnly = DateTime(day.year, day.month, day.day);
      return Container(
        margin: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          border: dateOnly == todayOnly
              ? Border.all(color: AppColors.primary, width: 2)
              : null,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Text(
            '${day.day}',
            style: TextStyle(fontSize: 13, color: colorScheme.onSurface),
          ),
        ),
      );
    }

    final now = DateTime.now();
    final todayOnly = DateTime(now.year, now.month, now.day);
    final dateStr = DateFormat('yyyy-MM-dd').format(day);

    final bool isCurrentMonth =
        day.year == _focusedDay.year && day.month == _focusedDay.month;
    final bool isToday =
        isCurrentMonth &&
        day.day == now.day &&
        day.month == now.month &&
        day.year == now.year;
    final bool isSelectedDay = isCurrentMonth && isSameDay(_selectedDay, day);

    Color bgColor = Colors.transparent;
    Color textColor = isCurrentMonth
        ? const Color(0xFF1E293B)
        : const Color(0xFFCBD5E1);

    // Initialize variables before use
    num? workHours;
    bool isLowHours = false;
    bool isFuture = false;
    String? leaveTypeAbbr;
    // True when a holiday falls on a week-off: the cell is styled as a Week Off,
    // but we still mark the holiday with a small indigo dot so it stays visible.
    bool showHolidayDot = false;

    if (isCurrentMonth) {
      final bool isHoliday = _holidayDateSet.contains(dateStr);
      final int dayOfWeek = day.weekday; // 1=Mon, ..., 7=Sun

      // Week off from backend, plus force Sundays as week off
      // Do NOT show violet for alternate work dates (compensation week-off days when employee can check-in)
      bool isWeekOff = _weekOffDateSet.contains(dateStr);
      if (isWeekOff && _alternateWorkDatesInMonth.contains(dateStr)) {
        isWeekOff = false;
      }
      if (dayOfWeek == DateTime.sunday &&
          !_alternateWorkDatesInMonth.contains(dateStr)) {
        isWeekOff = true;
      }

      // When a holiday and a week-off land on the same date, the date is shown as a
      // Week Off (grey "WF"), but the holiday is still flagged with an indigo dot.
      showHolidayDot = isHoliday && isWeekOff;

      final bool isPresentFromBackend = _presentDateSet.contains(dateStr);
      final bool isAbsentFromBackend = _absentDateSet.contains(dateStr);

      // Dark grey text for week offs
      if (isWeekOff) {
        textColor = const Color(0xFF475569);
      }

      // Priority: Present with LeaveType (Green) > Half Day (On Leave Blue) > Holiday > Week Off > Leave without attendance (On Leave Blue) > Present > Absent > Not Marked
      final status = _dayStatusByDate[dateStr];
      final hasLeaveType = _dayLeaveTypeByDate.containsKey(dateStr);
      // Never treat as present when record is Pending/Absent/Rejected (trust attendance list over presentDates)
      final isAbsentStatus =
          (status ?? '').toString().toLowerCase() == 'absent';
      final isPresentStatus =
          (status == 'Present' ||
              status == 'Approved' ||
              isPresentFromBackend) &&
          status != 'Pending' &&
          !isAbsentStatus &&
          status != 'Rejected';
      final isHalfDayStatus =
          status == 'Half Day' || (status?.toLowerCase() == 'half day');

      // 1. Present with leaveType → Green background with CL/SL/HA
      if (isPresentStatus && hasLeaveType) {
        bgColor = const Color(0xFFFCEFD2); // Present - Light Amber (Figma)
      }
      // 2. Half Day status → On Leave blue background with "HA"
      else if (isHalfDayStatus) {
        bgColor = const Color(0xFFBFDBFE); // Half Day - On Leave blue
      }
      // 2.5. Present on holiday when allowAttendanceOnHolidays or allowAttendanceOnWeeklyOff is enabled → show as Present
      else if (isPresentStatus &&
          isHoliday &&
          (_attendanceTemplate?['allowAttendanceOnHolidays'] == true ||
              _attendanceTemplate?['allowAttendanceOnWeeklyOff'] == true)) {
        bgColor = const Color(0xFFFCEFD2); // Present - Light Amber (Figma)
      }
      // 3. Holiday (only when it is NOT also a week-off — overlap shows as Week Off below)
      else if (isHoliday && !isWeekOff) {
        bgColor = const Color(0xFFEEF0FF); // Holiday - Light Indigo (Figma)
      }
      // 3.5. Alternate Working Day (compensation week-off day when employee can check-in)
      else if (_alternateWorkDatesInMonth.contains(dateStr)) {
        bgColor = const Color(0xFFE8D5C4); // Working Day - Light brown
      }
      // 3.7. Present on weekoff when allowAttendanceOnWeeklyOff is enabled → show as Present
      else if (isPresentStatus &&
          isWeekOff &&
          _attendanceTemplate?['allowAttendanceOnWeeklyOff'] == true) {
        bgColor = const Color(0xFFFCEFD2); // Present - Light Amber (Figma)
      }
      // 4. Week Off
      else if (isWeekOff) {
        bgColor = const Color(0xFFEDEFF2); // Week Off - Light Grey (Figma)
      }
      // 5. Leave date but no attendance → Blue with "L"
      else if (_leaveDateSet.contains(dateStr)) {
        bgColor = const Color(0xFFBFDBFE); // On Leave - light blue
      }
      // 6. Present without leaveType → Green
      else if (isPresentStatus) {
        bgColor = const Color(0xFFFCEFD2); // Present - Light Amber (Figma)
      }
      // 7. Other attendance statuses (Pending treated as Absent). Show red when status is Absent in attendances collection.
      else if (_dayStatusByDate.containsKey(dateStr)) {
        if (status == 'Pending' || isAbsentStatus || status == 'Rejected') {
          bgColor = const Color(0xFFFEE2E2); // Absent - light red
        } else if (status == 'On Leave') {
          bgColor = const Color(0xFFBFDBFE); // On Leave - light blue
        }
      }
      // 8. Absent from backend
      else if (isAbsentFromBackend) {
        if (!isWeekOff) {
          bgColor = const Color(0xFFFEE2E2); // Absent - light red
        }
      }
      // 9. Future dates
      else {
        final today = DateTime(now.year, now.month, now.day);
        final candidate = DateTime(day.year, day.month, day.day);
        if (candidate.isAfter(today)) {
          bgColor = const Color(0xFFE2E8F0); // Not Marked - Light grey
          textColor = const Color(
            0xFF475569,
          ); // Darker grey text for visibility
        }
      }

      // Leave type abbreviation logic (inside isCurrentMonth block where variables are available):
      // PL=Paid Leave, L=Leave, HA=Half Day, CF=Comp Off, WF=Week Off, WD=Working Day
      final statusForDay = _dayStatusByDate[dateStr] ?? '';
      final statusLower = statusForDay.toString().toLowerCase();
      final isAbsentStatusForAbbr = statusLower == 'absent';
      final isPresentStatusForAbbr =
          (statusForDay == 'Present' ||
              statusForDay == 'Approved' ||
              isPresentFromBackend) &&
          statusForDay != 'Pending' &&
          !isAbsentStatusForAbbr &&
          statusForDay != 'Rejected';
      final isHalfDayStatusForAbbr =
          statusForDay == 'Half Day' || statusLower == 'half day';
      final hasLeaveTypeForAbbr = _dayLeaveTypeByDate.containsKey(dateStr);
      final isOnLeaveStatus = statusLower == 'on leave';
      final isPaidLeave = _dayIsPaidLeaveByDate[dateStr] == true;
      final compType = _dayCompensationTypeByDate[dateStr] ?? '';

      if (isPresentStatusForAbbr && hasLeaveTypeForAbbr) {
        // Present with leaveType → Show CL/SL/HA (green background)
        leaveTypeAbbr = AttendanceDisplayUtil.leaveTypeToAbbreviation(
          _dayLeaveTypeByDate[dateStr],
        );
      } else if (isPresentStatusForAbbr &&
          isHoliday &&
          _attendanceTemplate?['allowAttendanceOnHolidays'] == true) {
        leaveTypeAbbr = 'P';
      } else if (isHoliday && !isWeekOff) {
        leaveTypeAbbr = 'H';
      } else if (isWeekOff &&
          !(isPresentStatusForAbbr &&
              _attendanceTemplate?['allowAttendanceOnWeeklyOff'] == true)) {
        leaveTypeAbbr = 'WF';
      } else if (_alternateWorkDatesInMonth.contains(dateStr)) {
        leaveTypeAbbr = 'WD';
      } else if (isHalfDayStatusForAbbr) {
        leaveTypeAbbr = 'HA';
      } else if (isOnLeaveStatus &&
          (compType == 'compoff' || compType == 'comp off')) {
        leaveTypeAbbr = 'CF';
      } else if (isOnLeaveStatus &&
          isPaidLeave &&
          compType != 'weekoff' &&
          compType != 'compoff') {
        leaveTypeAbbr = 'PL';
      } else if ((_leaveDateSet.contains(dateStr) || isOnLeaveStatus) &&
          !isPresentStatusForAbbr) {
        leaveTypeAbbr = 'L';
      } else if (_pendingWithCheckInDateSet.contains(dateStr)) {
        leaveTypeAbbr = 'WA'; // Waiting for Approval (Pending + has check-in)
      }

      // Low work-hours indicator (only Present and Half Day; not Leave/Week Off/Paid Leave)
      workHours = _dayWorkHoursByDate[dateStr];
      final calendarRecord = <String, dynamic>{
        'status': statusForDay,
        'workHours': workHours,
        'compensationType': isWeekOff ? 'weekoff' : compType,
        'isPaidLeave': isPaidLeave,
      };
      isLowHours = _shouldShowLowWorkHours(calendarRecord);
      isFuture = DateTime(day.year, day.month, day.day).isAfter(todayOnly);
    }

    return Container(
      margin: const EdgeInsets.all(4), // 8px spacing between cells
      decoration: BoxDecoration(
        color: bgColor == Colors.transparent ? null : bgColor,
        borderRadius: BorderRadius.circular(8),
        border: isToday
            ? Border.all(color: AppColors.primary, width: 2)
            : (isSelectedDay
                  ? Border.all(color: const Color(0xFF1E40AF), width: 2)
                  : null),
      ),
      child: Stack(
        children: [
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '${day.day}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isToday ? FontWeight.bold : FontWeight.w500,
                      color: bgColor != Colors.transparent
                          ? textColor
                          : (isCurrentMonth
                                ? colorScheme.onSurface
                                : colorScheme.onSurfaceVariant),
                    ),
                  ),
                  if (leaveTypeAbbr != null && leaveTypeAbbr.isNotEmpty) ...[
                    const SizedBox(height: 0),
                    Text(
                      leaveTypeAbbr,
                      style: TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.w600,
                        color:
                            (bgColor != Colors.transparent
                                    ? textColor
                                    : const Color(0xFF1E293B))
                                .withOpacity(0.9),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          // Red dot indicator for low work hours (top-left corner)
          if (isLowHours && !isFuture && bgColor != Colors.transparent)
            Positioned(
              top: 4,
              left: 4,
              child: Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          // Indigo dot (top-right) when a holiday overlaps a week-off: the cell is
          // styled as Week Off, but this marks that the date is also a holiday.
          if (showHolidayDot)
            Positioned(
              top: 4,
              right: 4,
              child: Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: AppColors.indigo,
                  shape: BoxShape.circle,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCalendarHeader() {
    // Figma "Attendance History": "Attendance" + subtitle on the left, a
    // "< MMM yyyy >" pill on the right. Month nav still calls _fetchMonthData
    // (logic unchanged) so the calendar/holiday/weekend data stays in sync.
    void shiftMonth(int delta) {
      final nd = DateTime(_focusedDay.year, _focusedDay.month + delta, 1);
      // Do not navigate before the employee's joining month — there are no records there.
      final joinStart = _joiningMonthStart;
      if (joinStart != null && nd.isBefore(joinStart)) {
        return;
      }
      setState(() {
        _focusedDay = nd;
        _selectedDay = nd;
      });
      _fetchMonthData(nd.year, nd.month);
    }

    final bool canGoBack = !_isAtOrBeforeJoiningMonth;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 4, 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            DateFormat('MMMM yyyy').format(_focusedDay),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                onTap: canGoBack ? () => shiftMonth(-1) : null,
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(Icons.chevron_left_rounded,
                      size: 22,
                      color: canGoBack
                          ? AppColors.textSecondary
                          : AppColors.textSecondary.withOpacity(0.3)),
                ),
              ),
              const SizedBox(width: 6),
              InkWell(
                onTap: () => shiftMonth(1),
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(Icons.chevron_right_rounded,
                      size: 22, color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Top card: header (month/date), date strip, "Your Attendance" with Check In / Check Out side-by-side cards.
  Widget _buildYourAttendanceTopCard() {
    final colorScheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final todayOnly = DateTime(now.year, now.month, now.day);
    final selectedDayOnly = DateTime(
      _selectedDay.year,
      _selectedDay.month,
      _selectedDay.day,
    );
    final isSelectedDayToday = selectedDayOnly == todayOnly;

    final punchIn = _attendanceData?['punchIn'];
    final punchOut = _attendanceData?['punchOut'];
    final hasPunchIn = _hasPunchValue(punchIn);
    final hasPunchOut = _hasPunchValue(punchOut);
    final isCompleted = hasPunchIn && hasPunchOut;
    final isCheckedIn = hasPunchIn && !hasPunchOut;
    final isAdminMarked =
        !hasPunchIn &&
        !hasPunchOut &&
        ((_attendanceData?['status'] ?? '') == 'Present' ||
            (_attendanceData?['status'] ?? '') == 'Approved');
    final canCheckIn =
        !_isPunchActionInProgress &&
        !isCompleted &&
        !isAdminMarked &&
        !hasPunchIn &&
        isSelectedDayToday;
    final canCheckOut =
        !_isPunchActionInProgress && isCheckedIn && isSelectedDayToday;

    final punchInTime = hasPunchIn ? _formatTimeShort(punchIn) : '--:--';
    final String punchOutDisplay = hasPunchOut
        ? _formatTimeShort(punchOut)
        : 'Not Yet';
    final shiftEnd = _getShiftEndTime();

    // Check-in status: On Time / Late
    String checkInStatus = 'Not Yet';
    if (punchIn != null) {
      final isLate =
          _isLateCheckIn(punchIn, record: _attendanceData) &&
          !(_attendanceTemplate?['allowLateEntry'] ??
              _attendanceTemplate?['lateEntryAllowed'] ??
              true);
      checkInStatus = isLate ? 'Late' : 'On Time';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Date section: header + date strip (white background)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(20),
              bottomRight: Radius.circular(20),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: Left arrow | Center date | Right calendar (yellow square)
              Row(
                children: [
                  GestureDetector(
                    onTap: () {
                      final todayOnly = DateTime(now.year, now.month, now.day);
                      setState(() {
                        _showHistoryView = false;
                        _selectedDay = todayOnly;
                      });
                      _fetchAttendanceStatus(date: todayOnly);
                    },
                    child: Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.chevron_right_rounded,
                        color: AppColors.primary,
                        size: 26,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          DateFormat('MMM yyyy').format(_selectedDay),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          DateFormat('EEE, d MMMM yyyy').format(_selectedDay),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.black,
                          ),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () => setState(() => _showHistoryView = true),
                    child: Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.calendar_month,
                            color: Colors.white,
                            size: 18,
                          ),
                          Text(
                            '${_selectedDay.day}',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        // Light section: Your Attendance + Check In/Out cards
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Your Attendance + See more
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Your Attendance',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  GestureDetector(
                    onTap: () => setState(() => _showHistoryView = true),
                    child: Text(
                      'See more',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Check In and Check Out cards (tappable, screenshot-style design)
              Row(
                children: [
                  Expanded(
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: canCheckIn
                            ? () => _openMarkAttendanceScreen()
                            : null,
                        borderRadius: BorderRadius.circular(12),
                        child: Opacity(
                          opacity: canCheckIn ? 1 : 0.7,
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: colorScheme.surface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: canCheckIn
                                    ? AppColors.primary.withOpacity(0.3)
                                    : colorScheme.outline.withOpacity(0.2),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color: AppColors.primary.withOpacity(
                                          0.2,
                                        ),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Icon(
                                        Icons.input,
                                        color: AppColors.primary,
                                        size: 20,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Check In',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: colorScheme.onSurface,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  punchInTime,
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: colorScheme.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  checkInStatus,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.black,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: canCheckOut
                            ? () => _openMarkAttendanceScreen()
                            : null,
                        borderRadius: BorderRadius.circular(12),
                        child: Opacity(
                          opacity: canCheckOut ? 1 : 0.7,
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: colorScheme.surface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: canCheckOut
                                    ? AppColors.primary.withOpacity(0.3)
                                    : colorScheme.outline.withOpacity(0.2),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color: AppColors.primary.withOpacity(
                                          0.2,
                                        ),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Icon(
                                        Icons.output,
                                        color: AppColors.primary,
                                        size: 20,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Check Out',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: colorScheme.onSurface,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  punchOutDisplay,
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: colorScheme.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  isCompleted ? 'Done' : 'Start at $shiftEnd',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.black,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMarkAttendanceTab() {
    final colorScheme = Theme.of(context).colorScheme;
    // Today's attendance is fetched only on: screen init (_initData), tab switch (listener), and pull-to-refresh.
    // Do NOT fetch inside build — it caused repeated /attendance/today calls and "Too many requests".
    return RefreshIndicator(
      onRefresh: () => _refreshData(forceRefresh: true),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(left: 0, right: 0, top: 0, bottom: 16),
        child: Container(
          color: AppColors.primary.withOpacity(0.18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildYourAttendanceTopCard(),
              const SizedBox(height: 20),
              // Recent Activity: white/light background section on yellow
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 12,
                      offset: const Offset(0, -4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Recent Activity',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildRecentActivityList(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Header bar: centered month / date (history calendar view).
  Widget _buildAttendanceHeaderBar() {
    final colorScheme = Theme.of(context).colorScheme;
    final now = _showHistoryView ? _focusedDay : DateTime.now();
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  DateFormat('MMM yyyy').format(now),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  DateFormat('EEE, d MMMM yyyy').format(now),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.black,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryTab() {
    return RefreshIndicator(
      onRefresh: () => _refreshData(forceRefresh: true),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Builder(
              builder: (context) {
                final colorScheme = Theme.of(context).colorScheme;
                return Container(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x0D000000),
                        blurRadius: 10,
                        offset: Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      _buildCalendarHeader(),
                      // When no month data is available the calendar grid can only
                      // render faint, colorless day numbers — which reads as a broken
                      // "stuck loading" calendar. Surface the real state instead: a
                      // spinner while the fetch is in flight, or an explicit Retry when
                      // it failed (e.g. throttle / timeout / server error). Markings
                      // appear automatically once the bounded auto-retry succeeds; this
                      // is the manual escape hatch.
                      if (_monthData == null)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: 10,
                            horizontal: 8,
                          ),
                          child: _isLoadingMonthData
                              ? Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: const [
                                    SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.2,
                                      ),
                                    ),
                                    SizedBox(width: 10),
                                    Text(
                                      'Loading attendance…',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Color(0xFF64748B),
                                      ),
                                    ),
                                  ],
                                )
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(
                                      Icons.error_outline_rounded,
                                      size: 18,
                                      color: Color(0xFF64748B),
                                    ),
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: Text(
                                        _monthLoadError == null ||
                                                _monthLoadError!.trim().isEmpty
                                            ? "Couldn't load this month's attendance."
                                            : "Couldn't load: ${_monthLoadError!}",
                                        style: const TextStyle(
                                          fontSize: 13,
                                          color: Color(0xFF64748B),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    TextButton(
                                      style: TextButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 4,
                                        ),
                                        minimumSize: Size.zero,
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      onPressed: () {
                                        // Manual retry: reset the per-month budget so the
                                        // user gets a fresh set of auto-retries too.
                                        _monthRetryAttempts = 0;
                                        _monthRetryKey = null;
                                        _fetchMonthData(
                                          _focusedDay.year,
                                          _focusedDay.month,
                                          forceRefresh: true,
                                        );
                                      },
                                      child: const Text(
                                        'Retry',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      TableCalendar(
                    key: ValueKey(
                      '${_focusedDay.year}-${_focusedDay.month}'
                      '-${_joiningMonthStart?.year ?? 0}-${_joiningMonthStart?.month ?? 0}',
                    ), // Force rebuild when month/year OR firstDay (joiningMonthStart) changes
                    // Start the calendar at the employee's joining month so months
                    // before the Date of Joining cannot be displayed/navigated to.
                    firstDay: _joiningMonthStart ?? DateTime(2020),
                    lastDay: DateTime.now().add(
                      const Duration(days: 730),
                    ), // Allow 2 years in future
                    focusedDay: _focusedDay,
                    selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                    onDaySelected: (selectedDay, focusedDay) {
                      // Allow selecting future dates to view holidays/weekends (but can't mark attendance)
                      setState(() {
                        _selectedDay = selectedDay;
                        _focusedDay = focusedDay;
                      });
                      // Fetch attendance status for selected day (will be null for future dates, which is fine)
                      _fetchAttendanceStatus(date: selectedDay);
                    },
                    headerVisible: false, // Using custom header
                    calendarFormat: CalendarFormat.month,
                    // Disable the calendar's own gestures. Its internal PageView
                    // (used for horizontal month swipes) would otherwise win the
                    // gesture arena over the large grid area and swallow vertical
                    // drags, so the parent SingleChildScrollView never scrolls.
                    // Month navigation is handled by the < > arrows in the custom
                    // header (_buildCalendarHeader -> shiftMonth), so swipe isn't
                    // needed.
                    availableGestures: AvailableGestures.none,
                    onCalendarCreated: (controller) =>
                        _calendarPageController = controller,
                    daysOfWeekHeight: 40,
                    calendarBuilders: CalendarBuilders(
                      defaultBuilder: (context, day, focusedDay) {
                        return _buildCustomDay(context, day);
                      },
                      selectedBuilder: (context, day, focusedDay) {
                        return _buildCustomDay(context, day);
                      },
                      todayBuilder: (context, day, focusedDay) {
                        return _buildCustomDay(context, day);
                      },
                      holidayBuilder: (context, day, focusedDay) {
                        return _buildCustomDay(context, day);
                      },
                      outsideBuilder: (context, day, focusedDay) {
                        return const SizedBox.shrink();
                      },
                    ),
                    onPageChanged: (focusedDay) {
                      // Swipe gestures are disabled (availableGestures.none), so the only
                      // legitimate month change is the header < > arrows (shiftMonth),
                      // which update _focusedDay AND fetch. TableCalendar also fires a
                      // SPURIOUS page event on first build, drifting its internal PageView
                      // to an ADJACENT month (e.g. it lands on July while _focusedDay is
                      // June). Because outsideBuilder renders blank and the loaded data is
                      // keyed to _focusedDay's month, that drift shows an EMPTY grid under
                      // the (correct) June header — the "data loads then vanishes" glitch.
                      // We must NOT follow the drift (that re-introduced the wrong-month
                      // fetch / July-blank). Instead snap the PageView back to _focusedDay.
                      final intendedMonth =
                          DateTime(_focusedDay.year, _focusedDay.month, 1);
                      final incomingMonth =
                          DateTime(focusedDay.year, focusedDay.month, 1);
                      if (incomingMonth == intendedMonth) {
                        return; // page already on the focused month — nothing to do
                      }
                      debugPrint(
                        '[Attendance][calPage] PageView drifted to '
                        '${focusedDay.year}-${focusedDay.month}; snapping back to '
                        '${_focusedDay.year}-${_focusedDay.month}',
                      );
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        final pc = _calendarPageController;
                        if (!mounted || pc == null || !pc.hasClients) return;
                        final monthsDelta =
                            (intendedMonth.year - incomingMonth.year) * 12 +
                                (intendedMonth.month - incomingMonth.month);
                        final current =
                            (pc.page ?? pc.initialPage.toDouble()).round();
                        final target = current + monthsDelta;
                        if (target >= 0 && target != current) {
                          pc.jumpToPage(target);
                        }
                      });
                    },
                  ),
                      const SizedBox(height: 8),
                      Divider(height: 1, color: colorScheme.outline),
                      const SizedBox(height: 12),
                      _buildStatusLegend(),
                      const SizedBox(height: 4),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            Builder(
              builder: (context) {
                final cs = Theme.of(context).colorScheme;
                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Attendance Logs',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: cs.onSurface,
                      ),
                    ),
                    // Figma Attendance-1: amber "View All" link → existing "All" filter.
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () {
                        setState(() { _activeFilter = 'All'; _page = 1; });
                        final now = DateTime.now();
                        _fetchMonthData(now.year, now.month);
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                        child: Text(
                          'View All',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 8),
            _buildHistoryList(),
            if (_effectiveHistoryTotalPages() > 1 &&
                _activeFilter != 'All' &&
                _activeFilter != 'This Month' &&
                _activeFilter != 'This Week') ...[
              const SizedBox(height: 24),
              _buildPaginationControls(),
            ],
          ],
        ),
      ),
    );
  }

  /// Logs (punch + admin APPROVED/REJECTED) are attached on GET month attendance only.
  /// Today's single-day fetch often omits [logs]; merge from [_monthData] when dates match.
  List<Map<String, dynamic>>? _logsFromMonthAttendanceForDate(String dateStr) {
    final raw = _monthData?['attendance'];
    if (raw is! List) return null;
    List<Map<String, dynamic>>? best;
    for (final e in raw) {
      if (e is! Map) continue;
      if (_dateKey(e) != dateStr) continue;
      final logs = e['logs'];
      if (logs is! List || logs.isEmpty) continue;
      final parsed = <Map<String, dynamic>>[];
      for (final x in logs) {
        if (x is Map) parsed.add(Map<String, dynamic>.from(x));
      }
      if (parsed.isEmpty) continue;
      if (best == null || parsed.length > best.length) best = parsed;
    }
    return best;
  }

  /// Builds a record for the selected calendar date.
  /// Prefers record from month history (same source as Attendance History list) so both show identical data.
  Map<String, dynamic> _buildSelectedDateRecord() {
    final selected = _selectedDay;
    final dateStr = DateFormat('yyyy-MM-dd').format(selected);

    // 1. Prefer record from combined month history (same source as Attendance History list)
    final combined = _getCombinedMonthHistory();
    for (final r in combined) {
      try {
        final rDate = _extractDateOnly(r['date']);
        if (rDate.year == selected.year &&
            rDate.month == selected.month &&
            rDate.day == selected.day) {
          final record = Map<String, dynamic>.from(r);
          record['date'] = dateStr; // Normalize date for display
          final monthLogs = _logsFromMonthAttendanceForDate(dateStr);
          if ((record['logs'] is! List || (record['logs'] as List).isEmpty) &&
              monthLogs != null &&
              monthLogs.isNotEmpty) {
            record['logs'] = monthLogs;
          }
          return record;
        }
      } catch (_) {}
    }

    // 2. Fallback: use _attendanceData from getAttendanceByDate when it corresponds to selected date
    final isDataForSelectedDay =
        _attendanceDataFetchedFor != null &&
        _selectedDay.year == _attendanceDataFetchedFor!.year &&
        _selectedDay.month == _attendanceDataFetchedFor!.month &&
        _selectedDay.day == _attendanceDataFetchedFor!.day;

    if (_attendanceData != null && isDataForSelectedDay) {
      final record = Map<String, dynamic>.from(_attendanceData!);
      record['date'] = dateStr;
      final monthLogs = _logsFromMonthAttendanceForDate(dateStr);
      if (monthLogs != null && monthLogs.isNotEmpty) {
        record['logs'] = monthLogs;
      }
      return record;
    }

    if (isDataForSelectedDay) {
      // Holiday, Weekend, Absent, On Leave with no punch record
      String status = 'Absent';
      if (_isHoliday) {
        status = 'Holiday';
      } else if (_isWeeklyOff)
        status = 'Weekend';
      else if (_halfDayLeave != null)
        status = 'Half Day';
      else if (_isOnLeave)
        status = 'On Leave';

      final record = <String, dynamic>{
        'date': dateStr,
        'status': status,
        'punchIn': null,
        'punchOut': null,
        'workHours': null,
      };
      if (_holidayInfo != null) record['holidayInfo'] = _holidayInfo;
      if (_halfDayLeave != null) record['leaveDetails'] = _halfDayLeave;
      return record;
    }

    return <String, dynamic>{
      'date': dateStr,
      'status': 'Loading',
      'punchIn': null,
      'punchOut': null,
      'workHours': null,
    };
  }

  /// Selected date card shown above Attendance History when a calendar date is clicked.
  Widget _buildSelectedDateCard() {
    final record = _buildSelectedDateRecord();
    return GestureDetector(
      onTap: () => _showAttendanceDetails(record),
      child: _buildHistoryDateCard(context, record),
    );
  }

  Widget _buildPaginationControls() {
    final colorScheme = Theme.of(context).colorScheme;
    final useMonthData = _isMonthDataHistoryFilter();
    final effectivePages = _effectiveHistoryTotalPages();
    final safePage = _page.clamp(1, effectivePages);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outline),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Previous button
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: safePage > 1
                ? () {
                    if (useMonthData) {
                      setState(() => _page = safePage - 1);
                    } else {
                      _fetchHistory(page: safePage - 1);
                    }
                  }
                : null,
            color: safePage > 1
                ? colorScheme.primary
                : Colors.black,
          ),
          const SizedBox(width: 8),
          // Page numbers
          Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(
              effectivePages.clamp(0, 10), // Show max 10 pages
              (index) {
                final pageNum = index + 1;
                final isCurrentPage = pageNum == safePage;
                return GestureDetector(
                  onTap: () {
                    if (useMonthData) {
                      setState(() => _page = pageNum);
                    } else {
                      _fetchHistory(page: pageNum);
                    }
                  },
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: isCurrentPage
                          ? colorScheme.primary
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isCurrentPage
                            ? colorScheme.primary
                            : colorScheme.outline,
                      ),
                    ),
                    child: Text(
                      '$pageNum',
                      style: TextStyle(
                        color: isCurrentPage
                            ? colorScheme.onPrimary
                            : colorScheme.onSurface,
                        fontWeight: isCurrentPage
                            ? FontWeight.bold
                            : FontWeight.normal,
                        fontSize: 12,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 8),
          // Next button
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: safePage < effectivePages
                ? () {
                    if (useMonthData) {
                      setState(() => _page = safePage + 1);
                    } else {
                      _fetchHistory(page: safePage + 1);
                    }
                  }
                : null,
            color: safePage < effectivePages
                ? colorScheme.primary
                : Colors.black,
          ),
        ],
      ),
    );
  }

  Widget _buildStatusLegend() {
    // Figma Attendance-1: solid dots — Present(amber) · Absent(red) ·
    // Holiday(indigo) · Weekend(grey). Extra statuses kept for parity.
    return Wrap(
      spacing: 16,
      runSpacing: 10,
      children: [
        _legendItem(AppColors.primary, 'Present'),
        _legendItem(AppColors.error, 'Absent'),
        _legendItem(AppColors.indigo, 'Holiday'),
        _legendItem(const Color(0xFF9CA3AF), 'Weekend'),
        _legendItem(const Color(0xFF8D6E63), 'Working Day'),
        _legendItem(AppColors.info, 'On Leave'),
        _legendItem(AppColors.warning, 'Low Work Hours'),
      ],
    );
  }

  Widget _legendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary)),
      ],
    );
  }

  // ignore: unused_element
  Widget _historyTimeColumn(
    String label,
    String value,
    ColorScheme colorScheme, {
    String? selfieUrl,
    VoidCallback? onSelfieTap,
  }) {
    final timeCol = Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(fontSize: 9, color: Colors.black),
        ),
      ],
    );
    if (selfieUrl != null &&
        selfieUrl.toString().startsWith('http') &&
        onSelfieTap != null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: onSelfieTap,
            child: Container(
              width: 36,
              height: 36,
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.primary.withOpacity(0.5),
                  width: 1.5,
                ),
                image: DecorationImage(
                  image: CachedNetworkImageProvider(selfieUrl),
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
          timeCol,
        ],
      );
    }
    return timeCol;
  }

  /// Builds formula text from company.settings.payroll.fineCalculation (fetched by businessId).
  String get _fineCalculationFormulaText {
    final fc = _fineCalculation;
    if (fc == null) return 'Fine formula: (loading…)';
    final formula = fc['formula'];
    if (formula != null && formula.toString().trim().isNotEmpty) {
      return formula.toString().trim();
    }
    final method =
        fc['calculationMethod'] ?? fc['calculationType'] ?? 'shiftBased';
    final rules = fc['fineRules'];
    final enabled = fc['enabled'] == true;
    final applyFines = fc['applyFines'] != false;
    final parts = <String>[
      'Fine calculation Formula: method=$method',
      'enabled=$enabled',
      'applyFines=$applyFines',
    ];
    if (rules is List && rules.isNotEmpty) {
      final ruleDesc = rules
          .map((r) => '${r['type'] ?? ''}(${r['applyTo'] ?? 'both'})')
          .join(', ');
      parts.add('rules: $ruleDesc');
    }
    return parts.join('; ');
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return BlocListener<AttendanceBloc, AttendanceState>(
      listener: (context, state) async {
        final shouldHandleForegroundUi =
            widget.isActiveTab == true || _isSubmittingFromAttendanceCamera;
        if (state is AttendanceCheckInSuccess ||
            state is AttendanceCheckOutSuccess) {
          if (_isSubmittingFromAttendanceCamera) {
            _isSubmittingFromAttendanceCamera = false;
            if (mounted) Navigator.of(context).pop();
          }
          if (!mounted) return;
          _setPunchActionInProgress(
            true,
            message: state is AttendanceCheckInSuccess
                ? 'Finalizing check-in...'
                : 'Finalizing check-out...',
          );
          final userName = await _authService.getCurrentUserName();
          if (!mounted) return;
          _setPunchActionInProgress(false);
          if (shouldHandleForegroundUi && mounted) {
            if (state is AttendanceCheckInSuccess) {
              final overlayContent = _getCheckInOverlayEmojiAndMessage(
                userName,
              );
              unawaited(
                AttendanceSuccessOverlay.show(
                  context,
                  isCheckIn: true,
                  userName: userName,
                  checkInEmoji: overlayContent.emoji,
                  checkInMessage: overlayContent.message,
                  snackbarMessage: overlayContent.message,
                ),
              );
            } else {
              unawaited(
                AttendanceSuccessOverlay.show(
                  context,
                  isCheckIn: false,
                  userName: userName,
                  checkOutEmoji: '😊',
                  checkOutMessage: 'Checkout success!',
                  snackbarMessage: 'Checkout success!',
                ),
              );
            }
          }
          if (state is AttendanceCheckInSuccess) {
            unawaited(
              _runPostPunchSuccessTasks(
                true,
                checkInLat: state.checkInLat,
                checkInLng: state.checkInLng,
              ),
            );
          } else {
            unawaited(_runPostPunchSuccessTasks(false));
          }
        } else if (state is AttendanceFailure) {
          if (kDebugMode) {
            debugPrint(
              '[PunchFlow][AttendanceTab][BlocListener] AttendanceFailure '
              'shouldHandleForegroundUi=$shouldHandleForegroundUi msg=${state.message}',
            );
          }
          _setPunchActionInProgress(false);
          if (_isSubmittingFromAttendanceCamera) {
            _isSubmittingFromAttendanceCamera = false;
            if (mounted) Navigator.of(context).pop();
          }
          if (mounted && shouldHandleForegroundUi) {
            SnackBarUtils.showSnackBar(
              context,
              ErrorMessageUtils.sanitizeForDisplay(state.message),
              isError: true,
              debugSource: 'AttendanceScreen.BlocListener.AttendanceFailure',
            );
          }
        }
      },
      child: Stack(
        children: [
          Scaffold(
            backgroundColor: AppColors.background,
            appBar: AppBar(
              leading: const MenuIconButton(),
              title: const Text('Attendance', style: AppTextStyles.headingMedium),
              centerTitle: false,
              elevation: 0,
              backgroundColor: AppColors.background,
              foregroundColor: AppColors.textPrimary,
              surfaceTintColor: Colors.transparent,
              actions: [
                if (_showHistoryView)
                  PopupMenuButton<String>(
                    icon: Icon(Icons.filter_list, color: AppColors.textPrimary),
                    onSelected: (value) {
                      setState(() { _activeFilter = value; _page = 1; });
                      if (value == 'All' || value == 'Late' || value == 'Low Hours') {
                        final now = DateTime.now();
                        _fetchMonthData(now.year, now.month);
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'All',       child: Text('All')),
                      PopupMenuItem(value: 'Late',      child: Text('Late / Early exit')),
                      PopupMenuItem(value: 'Low Hours', child: Text('Low hours')),
                    ],
                  ),
                const SizedBox(width: 8),
              ],
            ),
            drawer: AppDrawer(
              currentIndex: widget.dashboardTabIndex ?? 4,
              onNavigateToIndex: widget.onNavigateToIndex,
            ),
            body: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                //fine formula
                if (1 == 0)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    color: Colors.grey.shade100,
                    child: SelectableText(
                      _fineCalculationFormulaText,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade800,
                        height: 1.35,
                      ),
                    ),
                  ),
                Expanded(
                  child: _showHistoryView
                      ? _buildHistoryTab()
                      : _buildMarkAttendanceTab(),
                ),
              ],
            ),
          ),
          // Only veil the mark-attendance tab while template details load — its
          // punch in/out button state depends on them. The history/calendar view
          // needs only month data (fetched in parallel), so never block it behind
          // the template round-trip; that overlay was what made the calendar feel
          // slow to appear on open.
          if (_isFetchingTemplateDetails && !_showHistoryView)
            Container(
              color: colorScheme.surface.withOpacity(0.7),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [const AppTabLoader()],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    final colorScheme = Theme.of(context).colorScheme;
    return Text(
      title,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: colorScheme.onSurface,
      ),
    );
  }

  /// Fetches current position and address for camera-direct punch flow.
  Future<
    ({
      Position? position,
      String address,
      String? area,
      String? city,
      String? pincode,
    })
  >
  _getCurrentLocation() async {
    String address = '';
    String? area;
    String? city;
    String? pincode;
    Position? position;
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return (
          position: null,
          address: '',
          area: null,
          city: null,
          pincode: null,
        );
      }
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

  /// Submits attendance with captured selfie file (camera-direct flow).
  Future<void> _submitAttendanceFromCameraFile(
    File file, {
    required Position? position,
    required String address,
    required String? area,
    required String? city,
    required String? pincode,
    required bool isCheckedIn,
  }) async {
    final result = await FaceDetectionHelper.detectFromFile(file);
    if (!mounted) return;
    if (!result.valid) {
      _setPunchActionInProgress(false);
      if (mounted) Navigator.of(context).pop();
      SnackBarUtils.showSnackBar(
        context,
        result.message ?? 'Please take a selfie with exactly one face visible.',
        isError: true,
      );
      return;
    }
    final requireSelfie = _attendanceTemplate?['requireSelfie'] ?? true;
    final requireGeolocation =
        _attendanceTemplate?['requireGeolocation'] ?? true;
    if (kDebugMode) {
      debugPrint(
        '[Attendance][TemplateFlags][camera-submit] requireSelfie=$requireSelfie requireGeolocation=$requireGeolocation templateName=${_attendanceTemplate?['name'] ?? _attendanceTemplate?['title'] ?? 'unknown'}',
      );
    }
    if (requireGeolocation && position == null) {
      _setPunchActionInProgress(false);
      if (mounted) Navigator.of(context).pop();
      SnackBarUtils.showSnackBar(
        context,
        'Could not get location.',
        isError: true,
      );
      return;
    }
    // Compress once, off the UI isolate, and reuse the same payload for face
    // verification and the punch upload (verify previously sent full-res).
    final imageBytes = await file.readAsBytes();
    final selfiePayload =
        await AttendanceSelfieCompress.compressRawBytesToDataUrl(imageBytes);
    if (!mounted) return;

    if (AppConstants.enableAttendanceFaceMatching &&
        requireSelfie &&
        selfiePayload.isNotEmpty) {
      try {
        final verify = await _authService.verifyFace(selfiePayload);
        if (!mounted) return;
        if (verify['success'] != true || verify['match'] != true) {
          _setPunchActionInProgress(false);
          if (mounted) Navigator.of(context).pop();
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
    final lat = position?.latitude ?? 0.0;
    final lng = position?.longitude ?? 0.0;
    final finePayload = await _buildFinePayloadForPunch(
      isCheckedIn: isCheckedIn,
    );
    _isSubmittingFromAttendanceCamera = true;
    if (isCheckedIn) {
      context.read<AttendanceBloc>().add(
        AttendanceCheckOutRequested(
          lat: lat,
          lng: lng,
          address: address,
          area: area,
          city: city,
          pincode: pincode,
          selfie: selfiePayload,
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
          address: address,
          area: area,
          city: city,
          pincode: pincode,
          selfie: selfiePayload,
          lateMinutes: finePayload['lateMinutes'] as int?,
          earlyMinutes: finePayload['earlyMinutes'] as int?,
          fineAmount: finePayload['fineAmount'] as double?,
        ),
      );
    }
  }

  /// Submits attendance without selfie (when template says `requireSelfie: false`).
  Future<void> _submitAttendanceWithoutSelfie({
    required Position? position,
    required String address,
    required String? area,
    required String? city,
    required String? pincode,
    required bool isCheckedIn,
  }) async {
    final requireSelfie = _attendanceTemplate?['requireSelfie'] ?? true;
    final requireGeolocation =
        _attendanceTemplate?['requireGeolocation'] ?? true;
    if (kDebugMode) {
      debugPrint(
        '[Attendance][TemplateFlags][no-selfie-submit] requireSelfie=$requireSelfie requireGeolocation=$requireGeolocation templateName=${_attendanceTemplate?['name'] ?? _attendanceTemplate?['title'] ?? 'unknown'}',
      );
    }
    if (requireGeolocation && position == null) {
      _setPunchActionInProgress(false);
      SnackBarUtils.showSnackBar(
        context,
        'Location is required. Please enable location and try again.',
        isError: true,
      );
      return;
    }

    final lat = position?.latitude ?? 0.0;
    final lng = position?.longitude ?? 0.0;
    final finePayload = await _buildFinePayloadForPunch(
      isCheckedIn: isCheckedIn,
    );

    if (isCheckedIn) {
      context.read<AttendanceBloc>().add(
        AttendanceCheckOutRequested(
          lat: lat,
          lng: lng,
          address: address,
          area: area,
          city: city,
          pincode: pincode,
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
          address: address,
          area: area,
          city: city,
          pincode: pincode,
          selfie: null,
          lateMinutes: finePayload['lateMinutes'] as int?,
          earlyMinutes: finePayload['earlyMinutes'] as int?,
          fineAmount: finePayload['fineAmount'] as double?,
        ),
      );
    }
  }

  /// Opens punch in/out via camera-direct flow: load location, open camera, submit. No-op if completed/admin-marked.
  Future<void> _openMarkAttendanceScreen() async {
    if (_isPunchActionInProgress) return;
    final punchIn = _attendanceData?['punchIn'];
    final punchOut = _attendanceData?['punchOut'];
    final hasPunchIn = _hasPunchValue(punchIn);
    final hasPunchOut = _hasPunchValue(punchOut);
    final isCheckedIn = hasPunchIn && !hasPunchOut;
    final isCompleted = hasPunchIn && hasPunchOut;
    final isAdminMarked =
        !hasPunchIn &&
        !hasPunchOut &&
        ((_attendanceData?['status'] ?? '') == 'Present' ||
            (_attendanceData?['status'] ?? '') == 'Approved');

    if (isCompleted) {
      SnackBarUtils.showSnackBar(
        context,
        'You have already punched out today',
        isError: true,
      );
      return;
    }
    if (isAdminMarked) return;

    // Punch-out with an ongoing break: validate immediately (before location/
    // selfie work) so the user is told to end the break up front instead of
    // hitting "Kindly end the break" only after the whole punch flow runs.
    if (isCheckedIn) {
      final breakResult = await _breakService.getCurrentBreak();
      if (!mounted) return;
      final breakRow = breakResult['data'];
      final hasActiveBreak =
          breakResult['success'] == true &&
          breakRow is Map &&
          (breakRow['id']?.toString().trim().isNotEmpty ?? false) &&
          breakRow['endTime'] == null;
      if (hasActiveBreak) {
        SnackBarUtils.showSnackBar(
          context,
          'Please end your break before punching out.',
          isError: true,
        );
        return;
      }
    }

    _setPunchActionInProgress(
      true,
      message: isCheckedIn ? 'Preparing check-out...' : 'Preparing check-in...',
    );

    await _fetchAllTemplateDetails();
    if (!mounted) return;

    // --- Check-in/check-out validation: show popup and block if any check fails ---
    if (!staffHasAssignedAttendanceTemplate(
      profileAttendanceTemplateRef: _profileAttendanceTemplateId,
      todayAttendanceTemplate: _attendanceTemplate,
    )) {
      await _showValidationAlert(
        'Attendance template is not assigned. Contact HR.',
      );
      _setPunchActionInProgress(false);
      return;
    }
    if (!isValidAttendanceTemplateMap(_attendanceTemplate)) {
      await _showValidationAlert('Template not mapped. Contact HR.');
      _setPunchActionInProgress(false);
      return;
    }
    if (_shiftAssigned != true) {
      await _showValidationAlert('Shift not assigned. Contact HR.');
      _setPunchActionInProgress(false);
      return;
    }
    if (_branchData == null) {
      await _showValidationAlert('Branch not assigned.');
      _setPunchActionInProgress(false);
      return;
    }
    final branchStatus =
        (_branchData!['status']?.toString().trim().toUpperCase()) ?? '';
    if (branchStatus != 'ACTIVE') {
      await _showValidationAlert('Your branch is not active.');
      _setPunchActionInProgress(false);
      return;
    }
    final geofence = _branchData!['geofence'] as Map<String, dynamic>?;
    final requireTemplateGeolocation =
        _attendanceTemplate?['requireGeolocation'] ?? true;
    if (requireTemplateGeolocation == true) {
      final geofenceEnabled = geofence?['enabled'] == true;
      if (!geofenceEnabled) {
        await _showValidationAlert('Geo fence is not set for your branch.');
        _setPunchActionInProgress(false);
        return;
      }
      final branchLat = geofence?['latitude'];
      final branchLng = geofence?['longitude'];
      final bool latLngSet =
          branchLat != null &&
          branchLng != null &&
          (branchLat is num ||
              (branchLat is String && branchLat.toString().trim().isNotEmpty)) &&
          (branchLng is num ||
              (branchLng is String && branchLng.toString().trim().isNotEmpty));
      if (!latLngSet) {
        await _showValidationAlert('Lat and long is not set for the branch.');
        _setPunchActionInProgress(false);
        return;
      }
    }
    if (_attendanceTemplate!['isActive'] == false) {
      await _showValidationAlert(
        'Attendance template is not active. Contact HR.',
      );
      _setPunchActionInProgress(false);
      return;
    }
    final todayEffectiveShift = _todayEffectiveShiftForAttendance();
    if (kDebugMode) {
      debugPrint(
        '[PunchFlow][AttendanceTab][todayShift] '
        'name=${todayEffectiveShift?.displayName ?? '(none)'} '
        'type=${todayEffectiveShift?.shiftTypeLower ?? '(none)'} '
        'isWeekOff=${todayEffectiveShift?.isWeekOff == true} '
        'start=${todayEffectiveShift?.startTime ?? '(none)'} '
        'end=${todayEffectiveShift?.endTime ?? '(none)'}',
      );
    }
    if (todayEffectiveShift?.isWeekOff == true) {
      SnackBarUtils.showSnackBar(context, "Today is weekoff", isError: true);
      _setPunchActionInProgress(false);
      return;
    }
    final isOpenShiftForToday =
        todayEffectiveShift?.isOpen ?? _isOpenShiftTemplate();
    if (!isOpenShiftForToday) {
      final shiftStart =
          todayEffectiveShift?.startTime?.trim() ?? _getShiftStartTimeFromDb();
      final shiftEnd =
          todayEffectiveShift?.endTime?.trim() ?? _getShiftEndTimeFromDb();
      if (shiftStart == null ||
          shiftStart.isEmpty ||
          shiftEnd == null ||
          shiftEnd.isEmpty) {
        // Rotational wrappers may not carry direct start/end; effective day timing is resolved server-side.
        if (_isAssignedShiftRotationalWrapper()) {
          // Do not block here with a false "timings not set" error for rotational assignments.
        } else {
          await _showValidationAlert(
            _shiftAssigned == true
                ? 'Shift timings not set. Contact HR.'
                : 'Shift not assigned. Contact HR.',
          );
          _setPunchActionInProgress(false);
          return;
        }
      }
    }
    // --- End validation ---

    // Half-day leave: block check-in/out during leave half and show specific red snackbar
    final bool isSecondHalfLeave =
        _halfDayLeave != null &&
        (_halfDayLeave!['halfDayType'] == 'Second Half Day' ||
            _halfDayLeave!['halfDaySession'] == 'Second Half Day' ||
            _halfDayLeave!['session'] == '2');
    final bool isFirstHalfLeave =
        _halfDayLeave != null &&
        (_halfDayLeave!['halfDayType'] == 'First Half Day' ||
            _halfDayLeave!['halfDaySession'] == 'First Half Day' ||
            _halfDayLeave!['session'] == '1');
    if (!isCheckedIn && _isOnLeave && !_checkInAllowed) {
      final String msg = isSecondHalfLeave
          ? 'Not allowed check-in. You are on leave on second half.'
          : isFirstHalfLeave
          ? 'Not allowed check-in. You are on leave on first half.'
          : (_leaveMessage ?? 'Check-in is not allowed at this time.');
      SnackBarUtils.showSnackBar(
        context,
        ErrorMessageUtils.sanitizeForDisplay(msg),
        isError: true,
      );
      await NotificationReactionOverlay.show(context, emoji: '😊');
      _setPunchActionInProgress(false);
      return;
    }
    // Do not block check-out client-side when already punched in; server decides.

    if (_isHoliday &&
        _attendanceTemplate?['allowAttendanceOnHolidays'] == false) {
      SnackBarUtils.showSnackBar(context, "Today is a holiday", isError: true);
      _setPunchActionInProgress(false);
      return;
    }
    if (_isCompensationWeekOff) {
      SnackBarUtils.showSnackBar(
        context,
        "Today is compensation week off",
        isError: true,
      );
      _setPunchActionInProgress(false);
      return;
    }
    if (_isCompensationCompOff) {
      SnackBarUtils.showSnackBar(context, "Today is comp off", isError: true);
      _setPunchActionInProgress(false);
      return;
    }
    if (_isPaidLeaveContext && !isCheckedIn) {
      SnackBarUtils.showSnackBar(context, "Today is paid leave", isError: true);
      _setPunchActionInProgress(false);
      return;
    }
    if (_isTodayAssignedRotationalWeekOff()) {
      SnackBarUtils.showSnackBar(context, "Today is weekoff", isError: true);
      _setPunchActionInProgress(false);
      return;
    }
    if (_isWeeklyOff &&
        _attendanceTemplate?['allowAttendanceOnWeeklyOff'] == false &&
        !_isAlternateWorkDate) {
      final now = DateTime.now();
      // Exception: Allow check-in on Saturdays if it's the oddEvenSaturday pattern
      if (_weeklyOffPattern == 'oddEvenSaturday' &&
          now.weekday == DateTime.saturday) {
        // Allow check-in to proceed even though it's a Weekly Off
      } else {
        SnackBarUtils.showSnackBar(
          context,
          "Today is a holiday",
          isError: true,
        );
        _setPunchActionInProgress(false);
        return;
      }
    }

    final now = DateTime.now();
    // Block check-in after shift end time (full-day or half-day working session end)
    if (!isCheckedIn && !_isOpenShiftTemplate()) {
      final sessionTimings = _getWorkingSessionTimings();
      final shiftEndStrForBlock =
          sessionTimings?['endTime'] ?? _getShiftEndTimeFromDb();
      if (shiftEndStrForBlock != null && shiftEndStrForBlock.isNotEmpty) {
        try {
          final parts = shiftEndStrForBlock.split(':').map(int.parse).toList();
          final shiftEndForBlock = DateTime(
            now.year,
            now.month,
            now.day,
            parts[0],
            parts[1],
          );
          if (now.isAfter(shiftEndForBlock)) {
            SnackBarUtils.showSnackBar(
              context,
              'Check-in not allowed after shift end time ($shiftEndStrForBlock).',
              isError: true,
            );
            _setPunchActionInProgress(false);
            return;
          }
        } catch (_) {}
      }
    }
    // Late/early: fines are computed on the server; the app does not show minute-based
    // "fine-style" dialogs when punch is allowed. When NOT allowed, block with a short message.
    String? alertMessage;
    bool shouldBlock = false;
    await _fetchFineCalculation();
    final netPerDaySalary = await _loadPerDaySalaryFromPrefs();
    if (kDebugMode) {
      debugPrint(
        '[Fine TEST][Attendance] Refreshed fine rules before alert/fine evaluation',
      );
      debugPrint(
        '[Fine TEST][Attendance] Loaded grossPerDaySalary='
        '${netPerDaySalary?.toStringAsFixed(2) ?? "null"}',
      );
    }
    if (!isCheckedIn) {
      final allowLateEntry =
          _attendanceTemplate?['allowLateEntry'] ??
          _attendanceTemplate?['lateEntryAllowed'] ??
          true;
      if (_isOpenShiftTemplate()) {
        // Open shift: no late-login confirmation dialog.
      } else {
        final sessionTimings = _getWorkingSessionTimings();
        final shiftStartStr =
            sessionTimings?['startTime'] ?? _getShiftStartTimeFromDb();
        if (shiftStartStr == null && allowLateEntry == false) {
          alertMessage = 'Shift start time not set. Contact HR.';
          shouldBlock = true;
        } else if (shiftStartStr != null) {
          try {
            final parts = shiftStartStr.split(':').map(int.parse).toList();
            final gracePeriod = _getGracePeriodMinutesForLateCheckIn();
            final shiftStartOnly = DateTime(
              now.year,
              now.month,
              now.day,
              parts[0],
              parts[1],
            );
            final graceEnd = shiftStartOnly.add(Duration(minutes: gracePeriod));
            if (now.isAfter(graceEnd)) {
              final shiftEndForFine =
                  sessionTimings?['endTime'] ?? _getShiftEndTime();
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
              final hasRules = _hasFineRules();
              final shiftHoursForFormula = calculateShiftHours(
                shiftStartStr,
                shiftEndForFine,
              );
              final lateRule = _matchFineRuleForAction('lateArrival');
              double lateFineAmount = fineResult.fineAmount;
              if (hasRules) {
                if (lateRule == null) {
                  lateFineAmount = 0.0;
                } else {
                  lateFineAmount = _computeFineFromRule(
                    rule: lateRule,
                    minutes: fineResult.lateMinutes,
                    netPerDaySalary: netPerDaySalary ?? 0.0,
                    shiftHours: shiftHoursForFormula,
                  );
                }
              }
              if (kDebugMode) {
                final fineLog = _resolveFineLogForAction('lateArrival');
                debugPrint(
                  '[Fine TEST][Attendance][LateIn] start=$shiftStartStr '
                  'graceMin=$gracePeriod lateMin=${fineResult.lateMinutes} '
                  'grossPerDay=${netPerDaySalary?.toStringAsFixed(2) ?? "null"} '
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
                if (hasRules && lateRule != null && ruleTypeLower == 'custom') {
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
                  '[Fine FORMULA][Attendance][LateIn] '
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
                lateMinutes: fineResult.lateMinutes,
                fineAmount: lateFineAmount,
              );
              shouldBlock = allowLateEntry == false;
            }
          } catch (_) {}
        }
      }
    }
    if (isCheckedIn && alertMessage == null) {
      final allowEarlyExit =
          _attendanceTemplate?['allowEarlyExit'] ??
          _attendanceTemplate?['earlyExitAllowed'] ??
          true;
      if (_isOpenShiftTemplate()) {
        final punchInRaw = _attendanceData?['punchIn'];
        if (punchInRaw != null) {
          try {
            final punchIn = DateTime.parse(punchInRaw.toString()).toLocal();
            final reqH = _openShiftRequiredHours();
            final requiredMin = (reqH * 60).round();
            final workedMin = now.difference(punchIn).inMinutes;
            final earlyMinutes = workedMin >= requiredMin
                ? 0
                : (requiredMin - workedMin);
            if (earlyMinutes > 0) {
              double estimatedFine = 0;
              if (netPerDaySalary != null && netPerDaySalary > 0 && reqH > 0) {
                estimatedFine =
                    ((netPerDaySalary / reqH) * (earlyMinutes / 60) * 100)
                        .round() /
                    100;
              }
              final hasRules = _hasFineRules();
              final shiftHoursForFormula = reqH;
              final earlyRule = _matchFineRuleForAction('earlyExit');
              double earlyFineAmount = estimatedFine;
              if (hasRules) {
                if (earlyRule == null) {
                  earlyFineAmount = 0.0;
                } else {
                  earlyFineAmount = _computeFineFromRule(
                    rule: earlyRule,
                    minutes: earlyMinutes,
                    netPerDaySalary: netPerDaySalary ?? 0.0,
                    shiftHours: shiftHoursForFormula,
                  );
                }
              }
              if (kDebugMode) {
                debugPrint(
                  '[Fine TEST][Attendance][EarlyOut][open] requiredH=$reqH '
                  'earlyMin=$earlyMinutes fine=${earlyFineAmount.toStringAsFixed(2)}',
                );
              }
              final baseMessage = allowEarlyExit == false
                  ? 'Early check-out: you have not completed your required ${reqH == reqH.roundToDouble() ? reqH.toInt() : reqH} hour(s) for today.'
                  : 'You are checking out before completing your required hours.';
              alertMessage = _buildEarlyAlertMessage(
                baseMessage: baseMessage,
                earlyMinutes: earlyMinutes,
                fineAmount: earlyFineAmount,
              );
              shouldBlock = allowEarlyExit == false;
            }
          } catch (_) {}
        }
      } else {
        final sessionTimings = _getWorkingSessionTimings();
        final shiftEndStr =
            sessionTimings?['endTime'] ?? _getShiftEndTimeFromDb();
        if (shiftEndStr == null && allowEarlyExit == false) {
          alertMessage = 'Shift end time not set. Contact HR.';
          shouldBlock = true;
        } else if (shiftEndStr != null) {
          try {
            final shiftStartForFine =
                sessionTimings?['startTime'] ?? _getShiftStartTime();
            // Anchor to punch-in so overnight shifts (PM start / AM end) resolve
            // the end boundary on the correct calendar day.
            final punchInRaw = _attendanceData?['punchIn'];
            final punchInDt = punchInRaw != null
                ? DateTime.tryParse(punchInRaw.toString())?.toLocal()
                : null;
            final shiftEnd = _resolveShiftEndForEarly(
              shiftStartStr: shiftStartForFine,
              shiftEndStr: shiftEndStr,
              anchor: punchInDt ?? now,
            );
            if (shiftEnd != null && now.isBefore(shiftEnd)) {
              final earlyMinutes = shiftEnd.difference(now).inMinutes;
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
              final hasRules = _hasFineRules();
              final shiftHoursForFormula = calculateShiftHours(
                shiftStartForFine,
                shiftEndStr,
              );
              final earlyRule = _matchFineRuleForAction('earlyExit');
              double earlyFineAmount = estimatedFine;
              if (hasRules) {
                if (earlyRule == null) {
                  earlyFineAmount = 0.0;
                } else {
                  earlyFineAmount = _computeFineFromRule(
                    rule: earlyRule,
                    minutes: earlyMinutes,
                    netPerDaySalary: netPerDaySalary ?? 0.0,
                    shiftHours: shiftHoursForFormula,
                  );
                }
              }
              if (kDebugMode) {
                final fineLog = _resolveFineLogForAction('earlyExit');
                debugPrint(
                  '[Fine TEST][Attendance][EarlyOut] start=$shiftStartForFine '
                  'end=$shiftEndStr earlyMin=$earlyMinutes '
                  'grossPerDay=${netPerDaySalary?.toStringAsFixed(2) ?? "null"} '
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
                if (hasRules &&
                    earlyRule != null &&
                    ruleTypeLower == 'custom') {
                  final customAmount =
                      (earlyRule['customAmount'] as num?)?.toDouble() ?? 0.0;
                  final unitLower =
                      (earlyRule['customAmountUnit']?.toString() ?? 'perHour')
                          .toLowerCase();
                  if (unitLower == 'perminute') {
                    fineFormula =
                        '${customAmount.toStringAsFixed(2)} × $earlyMinutes';
                    fineFormulaWords =
                        'perDaySalary=${netPerDaySalary?.toStringAsFixed(2) ?? "0.00"}; '
                        'customAmount perMinute × earlyMinutes';
                  } else if (unitLower == 'perhour') {
                    fineFormula =
                        '${customAmount.toStringAsFixed(2)} × ($earlyMinutes / 60)';
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
                      '* ($earlyMinutes / 60)';
                  fineFormulaWords =
                      'perDaySalary/shiftHours × (earlyMinutes/60)';
                }
                debugPrint(
                  '[Fine FORMULA][Attendance][EarlyOut] '
                  'fineType=${fineLog['fineType']} '
                  'ruleType=${fineLog['ruleType']} '
                  'ruleApplyTo=${fineLog['ruleApplyTo']} '
                  'fineFormula=$fineFormula '
                  '= fineAmount:${earlyFineAmount.toStringAsFixed(2)} '
                  'fineFormulaWords=$fineFormulaWords',
                );
              }
              final baseMessage = allowEarlyExit == false
                  ? 'Early check-out is not allowed before shift end.'
                  : 'You are checking out early.';
              alertMessage = _buildEarlyAlertMessage(
                baseMessage: baseMessage,
                earlyMinutes: earlyMinutes,
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
      await _showWarningAlert(alertMessage, isLate: isLate, isEarly: isEarly);
      if (!mounted) return;
      if (shouldBlock) {
        _setPunchActionInProgress(false);
        return; // Block only when not allowed
      }
    }
    if (!mounted) return;

    // Selfie is required only on punch-out, not on punch-in.
    final requireSelfie =
        isCheckedIn ? (_attendanceTemplate?['requireSelfie'] ?? true) : false;
    final requireGeolocation =
        _attendanceTemplate?['requireGeolocation'] ?? true;
    if (kDebugMode) {
      debugPrint(
        '[Attendance][TemplateFlags][open-mark] requireSelfie=$requireSelfie requireGeolocation=$requireGeolocation templateName=${_attendanceTemplate?['name'] ?? _attendanceTemplate?['title'] ?? 'unknown'}',
      );
    }

    Position? position;
    String address = '';
    String? area;
    String? city;
    String? pincode;

    final location = await _getCurrentLocation();
    if (!mounted) return;
    if (location.position == null) {
      SnackBarUtils.showSnackBar(
        context,
        'Location is required. Please enable location and try again.',
        isError: true,
      );
      _setPunchActionInProgress(false);
      return;
    }
    position = location.position;
    address = location.address;
    area = location.area;
    city = location.city;
    pincode = location.pincode;

    final locationStr = address.isNotEmpty
        ? address
        : (area != null
              ? '$area, ${city ?? ''}${pincode != null ? ' $pincode' : ''}'
              : null);

    if (!requireSelfie) {
      await _submitAttendanceWithoutSelfie(
        position: position,
        address: address,
        area: area,
        city: city,
        pincode: pincode,
        isCheckedIn: isCheckedIn,
      );
      return;
    }

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
    File? file;
    if (result is File) {
      file = result;
    } else if (identical(result, useImagePickerFallback)) {
      _setPunchActionInProgress(false);
      SnackBarUtils.showSnackBar(
        context,
        'Camera unavailable. Try again later.',
        isError: true,
      );
      return;
    }
    if (file == null) {
      _setPunchActionInProgress(false);
      return;
    }

    await _submitAttendanceFromCameraFile(
      file,
      position: position,
      address: address,
      area: area,
      city: city,
      pincode: pincode,
      isCheckedIn: isCheckedIn,
    );
    // Success/failure handled in BlocListener
  }

  Widget _buildAttendanceCard() {
    final colorScheme = Theme.of(context).colorScheme;
    final punchIn = _attendanceData?['punchIn'];
    final punchOut = _attendanceData?['punchOut'];

    // Extract location details
    final punchInLoc = _attendanceData?['location']?['punchIn'];
    final punchOutLoc = _attendanceData?['location']?['punchOut'];

    String? punchInAddress;
    // Helper to format address with lat/lng
    String formatLoc(Map<String, dynamic> loc) {
      String addr = '';
      if (loc['address'] != null && loc['address'].toString().isNotEmpty) {
        addr = loc['address'];
      } else {
        final area = loc['area'] ?? '';
        final city = loc['city'] ?? '';
        final pincode = loc['pincode'] ?? '';
        List<String> parts = [
          area,
          city,
          pincode,
        ].where((s) => s != null && s.isNotEmpty).cast<String>().toList();
        if (parts.isNotEmpty) addr = parts.join(', ');
      }
      return addr;
    }

    if (punchInLoc != null) {
      punchInAddress = formatLoc(punchInLoc);
    }

    String? punchOutAddress;
    if (punchOutLoc != null) {
      punchOutAddress = formatLoc(punchOutLoc);
    }

    // For the Mark Attendance card, we ALWAYS use TODAY's date (not _focusedDay)
    // This ensures check-in/check-out buttons always work for today, regardless of History calendar selection
    // Mark Attendance tab always shows today's attendance, so no need to check past/future dates
    // (we already fetch today's data in _fetchAttendanceStatus)
    // If _attendanceData is null, it means no attendance marked for today yet (show check-in button)
    // We don't need to check past/future dates since this tab is always for today

    // Extract Status first
    String status = _attendanceData?['status'] ?? 'Not Marked';

    final hasPunchIn = _hasPunchValue(punchIn);
    final hasPunchOut = _hasPunchValue(punchOut);
    final isCheckedIn = hasPunchIn && !hasPunchOut;
    final isCompleted = hasPunchIn && hasPunchOut;

    // Check if this is admin-marked attendance (status is Present/Approved but no punch times)
    final isAdminMarked =
        !hasPunchIn &&
        !hasPunchOut &&
        (status == 'Present' || status == 'Approved');

    final isLate =
        _isLateCheckIn(punchIn, record: _attendanceData) &&
        !(_attendanceTemplate?['allowLateEntry'] ??
            _attendanceTemplate?['lateEntryAllowed'] ??
            true);

    // Half-day leave only when leave is approved (API sends halfDayLeave).
    // Prefer API (halfDayLeave) for which half to display so "Second Half" leave shows as "leave on second half", not first.
    final bool isHalfDayLeave = _halfDayLeave != null;
    final Object? attendanceHalf =
        _attendanceData?['halfDaySession'] ?? _attendanceData?['session'];
    final Object? apiHalf =
        _halfDayLeave?['halfDayType'] ??
        _halfDayLeave?['halfDaySession'] ??
        _halfDayLeave?['session'];
    final Object? resolvedHalf = apiHalf ?? attendanceHalf;
    final bool isFirstHalfLeave =
        resolvedHalf == 'First Half Day' || resolvedHalf == '1';
    final bool isSecondHalfLeave =
        resolvedHalf == 'Second Half Day' || resolvedHalf == '2';

    // PRIORITY 0: Paid leave day — block new check-in from app; if already punched in (e.g. web), show punch card for check-out.
    if (_isPaidLeaveContext && !isCheckedIn) {
      return Card(
        elevation: 0,
        color: Colors.blue.withOpacity(0.05),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.blue.withOpacity(0.1)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Center(
            child: Column(
              children: [
                Icon(Icons.paid_outlined, size: 48, color: Colors.blue),
                const SizedBox(height: 16),
                Text(
                  'Paid Leave Today',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.blue,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // PRIORITY 1: Check if On Approved Leave.
    // Full-day leave: show leave-only card (no punch). Half-day: show leave-only card only when
    // currently in leave session (check-in and check-out both disallowed); otherwise show punch card with half-day message.
    // Open punch session (check-in without check-out) always shows punch card so staff can complete check-out.
    bool isActuallyOnLeave = _isOnLeave;
    final bool inLeaveSessionNow =
        isHalfDayLeave && !_checkInAllowed && !_checkOutAllowed;
    final bool shouldShowLeaveOnlyCard =
        isActuallyOnLeave &&
        (!isHalfDayLeave || inLeaveSessionNow) &&
        !isCheckedIn;

    if (shouldShowLeaveOnlyCard) {
      // Show approved leave message: half-day → "You are on leave - First Half" / "Second Half" (based on attendance.halfDaySession / API); full-day → generic
      final String message;
      if (isHalfDayLeave && (isFirstHalfLeave || isSecondHalfLeave)) {
        message =
            _leaveMessage ??
            (isFirstHalfLeave
                ? 'You are on leave - First Half'
                : 'You are on leave - Second Half');
      } else {
        message =
            _leaveMessage ??
            'Your leave request is approved. Enjoy your leave.';
      }
      return Card(
        elevation: 0,
        color: Colors.blue.withOpacity(0.05),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.blue.withOpacity(0.1)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Center(
            child: Column(
              children: [
                Icon(Icons.beach_access, size: 48, color: Colors.blue),
                const SizedBox(height: 16),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.blue,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Half-day leave but outside session: show info banner and allow check-in (show punch card below)
    final halfDayCheckInAllowed = _halfDayLeave != null && _checkInAllowed;

    // Unified Non-Working Day Card (Holiday, Weekly Off, Compensation Week Off)
    // Only show this if they are NOT allowed to mark attendance
    // Note: Leave is handled above with highest priority
    bool showHolidayCard = false;
    String holidayText = "Today Holiday";
    IconData holidayIcon = Icons.beach_access;
    Color holidayColor = Colors.orange;

    if (_isCompensationWeekOff) {
      showHolidayCard = true;
      holidayText = "Today is compensation week off";
      holidayIcon = Icons.event_busy;
      holidayColor = Colors.orange;
    } else if (_isCompensationCompOff) {
      showHolidayCard = true;
      holidayText = "Today is comp off";
      holidayIcon = Icons.event_busy;
      holidayColor = Colors.orange;
    } else if (_isPaidLeaveContext && !isCheckedIn) {
      showHolidayCard = true;
      holidayText = "Paid Leave Today";
      holidayIcon = Icons.paid_outlined;
      holidayColor = Colors.blue;
    } else if (_isHoliday &&
        (_attendanceTemplate?['allowAttendanceOnHolidays'] == false ||
            _attendanceTemplate?['allowAttendanceOnHolidays'] == null)) {
      showHolidayCard = true;
      holidayText = "Today's a Holiday";
      holidayIcon = Icons.celebration;
      holidayColor = Colors.green;
    } else if (_isWeeklyOff &&
        (_attendanceTemplate?['allowAttendanceOnWeeklyOff'] == false ||
            _attendanceTemplate?['allowAttendanceOnWeeklyOff'] == null) &&
        !_isAlternateWorkDate) {
      showHolidayCard = true;
      holidayText =
          "Today is a Holiday"; // As per request: "Today is a holiday" for weekly off too
      holidayIcon = Icons.event_available;
      holidayColor = Colors.orange;
    }

    // Loading: until fetch completed, or staff has template but we're still loading/retrying (never show "Template not mapped" then refresh to punch)
    if (!_attendanceStatusFetched ||
        (!isValidAttendanceTemplateMap(_attendanceTemplate) &&
            _staffHasAttendanceTemplate == true)) {
      return Card(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: const Padding(
          padding: EdgeInsets.all(32.0),
          child: Center(child: AppTabLoader()),
        ),
      );
    }

    // Template not mapped: no usable template from API and no assignment signal from profile
    if (!isValidAttendanceTemplateMap(_attendanceTemplate) &&
        _staffHasAttendanceTemplate != true) {
      return Card(
        elevation: 0,
        color: Colors.orange.withOpacity(0.05),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.orange.withOpacity(0.2)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.schedule, size: 48, color: Colors.orange),
                const SizedBox(height: 16),
                Text(
                  'Template not mapped. Contact HR.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.orange,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (showHolidayCard) {
      return Card(
        elevation: 0,
        color: holidayColor.withOpacity(0.05),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: holidayColor.withOpacity(0.1)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Center(
            child: Column(
              children: [
                Icon(holidayIcon, size: 48, color: holidayColor),
                const SizedBox(height: 16),
                Text(
                  holidayText,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: holidayColor,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  (_isCompensationWeekOff ||
                          _isCompensationCompOff ||
                          _isPaidLeaveContext)
                      ? "Punch on your alternate work date instead."
                      : _isHoliday
                      ? (_holidayInfo?['name'] ?? "Public Holiday")
                      : "Relax and enjoy your day!",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: holidayColor.withOpacity(0.8)),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final bool punchDisabled =
        _isPunchActionInProgress ||
        (isHalfDayLeave &&
            ((!isCheckedIn && !_checkInAllowed) ||
                (isCheckedIn && !_checkOutAllowed && !_isPaidLeaveContext)));

    return Opacity(
      opacity: punchDisabled ? 0.65 : 1.0,
      child: IgnorePointer(
        ignoring: punchDisabled,
        child: GestureDetector(
          onTap: () {
            if (!isCompleted && !isAdminMarked && !punchDisabled) {
              _openMarkAttendanceScreen();
            }
          },
          child: Card(
            elevation: 0,
            color: punchDisabled
                ? colorScheme.surfaceContainerLowest
                : colorScheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: punchDisabled
                  ? BorderSide(color: colorScheme.outline)
                  : BorderSide.none,
            ),
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (halfDayCheckInAllowed)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16.0),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: 10,
                          horizontal: 12,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.blue.withOpacity(0.2),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              size: 20,
                              color: Colors.blue.shade700,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                // Prefer half-day session message; never show generic "Enjoy your leave" when in working half
                                (_halfDayLeave?['message']
                                                ?.toString()
                                                .trim()
                                                .isNotEmpty ==
                                            true
                                        ? _halfDayLeave!['message']!
                                              .toString()
                                              .trim()
                                        : null) ??
                                    ((_leaveMessage ?? '').trim().isNotEmpty &&
                                            !(_leaveMessage ?? '').contains(
                                              'Enjoy your leave',
                                            )
                                        ? _leaveMessage!.trim()
                                        : null) ??
                                    'Check-in allowed',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.blue.shade800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  _buildAttendanceRow(
                    'Punch In',
                    _formatTime(punchIn),
                    Icons.login_rounded,
                    AppColors.success,
                    address: punchInAddress,
                    isPlaceholder: !hasPunchIn,
                    isLate: isLate,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12.0),
                    child: Divider(height: 1, color: AppColors.divider),
                  ),
                  _buildAttendanceRow(
                    'Punch Out',
                    _formatTime(punchOut),
                    Icons.logout_rounded,
                    AppColors.error,
                    address: punchOutAddress,
                    isPlaceholder: !hasPunchOut,
                  ),
                  const SizedBox(height: 20),
                  if (isCompleted || isAdminMarked)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Center(
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  status == 'Pending'
                                      ? Icons.hourglass_bottom_rounded
                                      : status == 'Approved' ||
                                            status == 'Present'
                                      ? Icons.check_circle
                                      : Icons.info_outline,
                                  color: status == 'Pending'
                                      ? Colors.orange
                                      : status == 'Approved' ||
                                            status == 'Present'
                                      ? AppColors.success
                                      : Colors.blue,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  status == 'Pending'
                                      ? 'Waiting for Approval'
                                      : status,
                                  style: TextStyle(
                                    color: status == 'Pending'
                                        ? Colors.orange
                                        : status == 'Approved' ||
                                              status == 'Present'
                                        ? AppColors.success
                                        : Colors.blue,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            if (isAdminMarked &&
                                _attendanceData?['remarks'] != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 8.0),
                                child: Text(
                                  _attendanceData!['remarks'],
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  // Show action button whenever this is not admin-marked. Completed days show Check In again and snackbar on tap.
                  if (!isAdminMarked)
                    SizedBox(
                      width: double.infinity,
                      child: _isPunchActionInProgress
                          ? Container(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              decoration: BoxDecoration(
                                color: isCheckedIn
                                    ? AppColors.error
                                    : AppColors.primary,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Center(
                                child: SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.2,
                                    valueColor:
                                        const AlwaysStoppedAnimation<Color>(
                                          Colors.white,
                                        ),
                                  ),
                                ),
                              ),
                            )
                          : punchDisabled
                          ? Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: Colors.blue.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.blue.withOpacity(0.2),
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  isFirstHalfLeave
                                      ? 'You are on leave - First Half'
                                      : 'You are on leave - Second Half',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.blue.shade800,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            )
                          : ElevatedButton.icon(
                              onPressed: _isPunchActionInProgress
                                  ? null
                                  : _openMarkAttendanceScreen,
                              icon: Icon(
                                isCheckedIn &&
                                        (_attendanceTemplate?['requireSelfie'] ??
                                            true)
                                    ? Icons.camera_alt
                                    : Icons.touch_app,
                              ),
                              label: Text(
                                isCheckedIn
                                    ? (_attendanceTemplate?['requireSelfie'] ??
                                              true)
                                          ? 'Selfie Check Out'
                                          : 'Check Out'
                                    : 'Check In',
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isCheckedIn
                                    ? AppColors.error
                                    : AppColors.primary,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAttendanceRow(
    String label,
    String time,
    IconData icon,
    Color color, {
    String? address,
    bool isPlaceholder = false,
    bool isLate = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 24),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Row(
                children: [
                  Text(
                    time,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isPlaceholder
                          ? AppColors.textSecondary
                          : AppColors.textPrimary,
                    ),
                  ),
                  if (isLate)
                    Container(
                      margin: const EdgeInsets.only(left: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.orange, width: 0.5),
                      ),
                      child: Text(
                        'Late',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.deepOrange,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
              if (address != null && address.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4.0),
                  child: Row(
                    children: [
                      Icon(
                        Icons.location_on,
                        size: 12,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          address,
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                            height: 1.3,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// Recent activity: always today + last 5 days. Unaffected by History tab month change.
  Widget _buildRecentActivityList() {
    if (_recentActivityList.isEmpty && _isLoadingMonthData) {
      return const Center(
        child: Padding(padding: EdgeInsets.all(24.0), child: AppTabLoader()),
      );
    }
    return _buildHistoryList(limit: 6, forceDisplayList: _recentActivityList);
  }

  bool _isMonthDataHistoryFilter() {
    return _activeFilter == 'All' ||
        _activeFilter == 'This Month' ||
        _activeFilter == 'This Week' ||
        _activeFilter == 'Late' ||
        _activeFilter == 'Low Hours';
  }

  List<dynamic> _filteredHistoryRecords({required bool useMonthData}) {
    if (useMonthData) {
      List<dynamic> combined = _getCombinedMonthHistory();
      final now = DateTime.now();
      final currentMonth = DateTime(now.year, now.month);
      final nextMonth = DateTime(now.year, now.month + 1);

      if (_activeFilter == 'This Month') {
        combined = combined.where((r) {
          try {
            final d = _extractDateOnly(r['date']);
            return d.isAfter(currentMonth.subtract(const Duration(days: 1))) &&
                d.isBefore(nextMonth);
          } catch (_) {
            return false;
          }
        }).toList();
      } else if (_activeFilter == 'This Week') {
        final weekAgo = DateTime(
          now.year,
          now.month,
          now.day,
        ).subtract(const Duration(days: 7));
        combined = combined.where((r) {
          try {
            final d = _extractDateOnly(r['date']);
            return d.isAfter(weekAgo) || isSameDay(d, weekAgo);
          } catch (_) {
            return false;
          }
        }).toList();
      } else if (_activeFilter == 'Late') {
        combined = combined.where((r) {
          if (r['status'] != null &&
              (r['status'] == 'Absent' ||
                  r['status'] == 'Holiday' ||
                  r['status'] == 'Weekend' ||
                  r['status'] == 'On Leave')) {
            return false;
          }
          return _isLateCheckIn(r['punchIn'], record: r) ||
              _isLateCheckOut(r['punchOut'], record: r);
        }).toList();
      } else if (_activeFilter == 'Low Hours') {
        combined = combined.where((r) {
          if (r['status'] != null &&
              (r['status'] == 'Absent' ||
                  r['status'] == 'Holiday' ||
                  r['status'] == 'Weekend' ||
                  r['status'] == 'On Leave')) {
            return false;
          }
          return _shouldShowLowWorkHours(r);
        }).toList();
      }
      return combined;
    }

    return _historyList.where((r) {
      if (_activeFilter == 'Late Check-in' || _activeFilter == 'Late') {
        return _isLateCheckIn(r['punchIn'], record: r) ||
            _isLateCheckOut(r['punchOut'], record: r);
      } else if (_activeFilter == 'Late Check-out' ||
          _activeFilter == 'Late Out') {
        return _isLateCheckOut(r['punchOut'], record: r);
      } else if (_activeFilter == 'Low Work Hours' ||
          _activeFilter == 'Low Hours') {
        return _shouldShowLowWorkHours(r);
      }
      return true;
    }).toList();
  }

  int _effectiveHistoryTotalPages() {
    if (_isMonthDataHistoryFilter()) {
      final total = _filteredHistoryRecords(useMonthData: true).length;
      return ((total / _limit).ceil()).clamp(1, 99999);
    }
    return _totalPages.clamp(1, 99999);
  }

  Widget _buildHistoryList({int? limit, List<dynamic>? forceDisplayList}) {
    // When forceDisplayList is set (e.g. for Recent Activity), use it and skip filter logic.
    if (forceDisplayList != null) {
      final displayList = limit != null
          ? forceDisplayList.take(limit).toList()
          : List<dynamic>.from(forceDisplayList);
      return _buildHistoryListBody(displayList);
    }

    // Use month data for All, This Month, This Week, Late, and Low Hours
    // (if month data is available, it's more complete than paginated data)
    final bool useMonthData = _isMonthDataHistoryFilter();

    // For month-based view: show loader until month data is loaded (avoids Jan→Feb flicker)
    if (useMonthData && _monthData == null) {
      if (_isLoadingMonthData || _isLoadingHistory) {
        return const Center(
          child: Padding(padding: EdgeInsets.all(24.0), child: AppTabLoader()),
        );
      }
      // Month fetch failed or not started: show empty
    }

    if (!useMonthData && _isLoadingHistory && _historyList.isEmpty) {
      return const Center(
        child: Padding(padding: EdgeInsets.all(24.0), child: AppTabLoader()),
      );
    }

    List<dynamic> displayList = _filteredHistoryRecords(
      useMonthData: useMonthData,
    );

    if (limit != null) {
      displayList = displayList.take(limit).toList();
    } else if (useMonthData) {
      // 'All', 'This Month' and 'This Week' render the full month without pagination
      // controls (see _buildHistoryTab), so show every record instead of slicing to the
      // first page of _limit (which previously capped the list at 10 with no way to see more).
      final bool paginate = _activeFilter != 'All' &&
          _activeFilter != 'This Month' &&
          _activeFilter != 'This Week';
      if (paginate) {
        final effectivePages = _effectiveHistoryTotalPages();
        final safePage = _page.clamp(1, effectivePages);
        final start = (safePage - 1) * _limit;
        final end = (start + _limit).clamp(0, displayList.length);
        if (start < displayList.length) {
          displayList = displayList.sublist(start, end);
        } else {
          displayList = [];
        }
      }
    }

    return _buildHistoryListBody(displayList);
  }

  /// Builds a single attendance history date card (same UI for list items and selected date card).
  Widget _buildHistoryDateCard(BuildContext context, dynamic record) {
    final punchIn = record['punchIn'];
    final punchOut = record['punchOut'];
    final workHours = record['workHours'];
    final isLateIn = _isLateCheckIn(punchIn, record: record);
    final isLateOut = _isLateCheckOut(punchOut, record: record);
    final isEarlyOut = _isEarlyCheckOut(punchOut, record: record);
    final isLowHours = _shouldShowLowWorkHours(record);

    String status = record['status'] ?? 'Present';
    List<String> tags = [];

    final bool allowLate =
        _attendanceTemplate?['allowLateEntry'] ??
        _attendanceTemplate?['lateEntryAllowed'] ??
        true;
    final bool allowEarly =
        _attendanceTemplate?['earlyExitAllowed'] ??
        _attendanceTemplate?['allowEarlyExit'] ??
        true;
    final bool allowOvertime =
        _attendanceTemplate?['overtimeAllowed'] ??
        _attendanceTemplate?['allowOvertime'] ??
        true;

    final lateMins = record['lateMinutes'] as num?;
    if (isLateIn &&
        !allowLate &&
        (lateMins == null || lateMins.toDouble() != 0)) {
      tags.add('Late In');
    }
    if (isLateOut && !(allowOvertime || allowEarly)) {
      tags.add('Late Out');
    }
    if (isEarlyOut && !allowEarly) tags.add('Early Exit');
    if (isLowHours && !allowEarly) tags.add('Low Hrs');

    final leaveDetails = record['leaveDetails'] as Map<String, dynamic>?;
    final leaveType =
        (leaveDetails?['leaveType'] ?? record['leaveType']) as String?;
    // Use history card display: WF, CF, PL, HA, Present, On Leave
    final recordForDisplay = <String, dynamic>{
      'status': record['status'] ?? 'Present',
      'leaveType': leaveType ?? record['leaveType'],
      'compensationType': record['compensationType'],
      'isPaidLeave': record['isPaidLeave'],
    };
    String displayStatus = AttendanceDisplayUtil.getHistoryCardDisplayStatus(
      recordForDisplay,
    );
    // Week-off by template should show as WF
    final dateStr = _dateKey(record);
    if (dateStr.isNotEmpty &&
        _weekOffDateSet.contains(dateStr) &&
        !_alternateWorkDatesInMonth.contains(dateStr) &&
        (status.toString().toLowerCase() == 'on leave')) {
      displayStatus = 'WF';
    }
    // Holiday name (e.g. "Pongal") for this date — shown even when the date is
    // displayed as a Weekend/Week Off because the holiday overlaps a week-off.
    final holidayName = _holidayNameByDate[dateStr];
    if (status == 'Pending' && punchIn != null) displayStatus = 'Waiting';

    String? locationAddress;
    if (record['location'] != null && record['location']['punchIn'] != null) {
      final addr = record['location']['punchIn']['address'];
      if (addr != null && addr.toString().trim().isNotEmpty) {
        locationAddress = addr.toString();
      }
    }

    DateTime? parsedDate;
    try {
      parsedDate = _extractDateOnly(record['date'] ?? '');
    } catch (_) {}
    final dateText = parsedDate != null
        ? DateFormat('MMM d, EEE').format(parsedDate)
        : '--';
    num? workHoursVal = workHours;
    if (workHoursVal == null &&
        record['punchIn'] != null &&
        record['punchOut'] != null) {
      try {
        final pi = DateTime.parse(record['punchIn'].toString()).toLocal();
        final po = DateTime.parse(record['punchOut'].toString()).toLocal();
        workHoursVal = po.difference(pi).inMinutes;
      } catch (_) {}
    }
    final totalHoursStr = _formatWorkHoursAsHHmm(
      workHoursVal is num ? workHoursVal : null,
    );
    // Figma: white card, amber date badge, time range, status pill on right
    final isToday = parsedDate != null &&
        parsedDate.year == DateTime.now().year &&
        parsedDate.month == DateTime.now().month &&
        parsedDate.day == DateTime.now().day;

    final dateBgColor = isToday
        ? AppColors.primary
        : AppColors.primary.withValues(alpha: 0.12);
    final dateTextColor = isToday ? Colors.white : AppColors.primary;

    // Build time range string like "08:52 AM - 06:02 PM"
    final inStr  = _formatTime(punchIn);
    final outStr = _formatTime(punchOut);
    final timeRange = (inStr != '--:--' && outStr != '--:--')
        ? '$inStr - $outStr'
        : (inStr != '--:--' ? inStr : 'N/A');
    // Figma Attendance-1: amber login/logout icon tile + "MMM d, EEE" + time range.
    final displayTime = timeRange == 'N/A' ? 'Not applicable' : timeRange;
    IconData statusIcon;
    switch (status.toString().toLowerCase()) {
      case 'absent':
      case 'rejected':
      case 'pending':
        statusIcon = Icons.do_not_disturb_alt_rounded;
        break;
      case 'holiday':
        statusIcon = Icons.celebration_rounded;
        break;
      case 'on leave':
        statusIcon = Icons.event_busy_rounded;
        break;
      case 'weekend':
        statusIcon = Icons.weekend_rounded;
        break;
      default:
        statusIcon = Icons.login_rounded;
    }

    // Status style from AppColors
    final st = AppColors.statusStyle(status.toLowerCase());

    // Day-wise total fine = late/early (record.fineAmount) + break overage +
    // permission overage. Matches the detail sheet and shift screen.
    final breakMapForFine =
        record['break'] is Map ? Map<String, dynamic>.from(record['break'] as Map) : null;
    final dayFineAmount =
        ((record['fineAmount'] as num?)?.toDouble() ?? 0) +
        ((breakMapForFine?['totalBreakFineAmount'] as num?)?.toDouble() ?? 0) +
        ((record['permissionFineAmount'] as num?)?.toDouble() ?? 0);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Amber login/logout icon tile
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(color: dateBgColor, borderRadius: BorderRadius.circular(14)),
            child: Icon(statusIcon, color: dateTextColor, size: 22),
          ),
          const SizedBox(width: 14),
          // Middle content: date + time range
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(dateText,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                const SizedBox(height: 3),
                Text(displayTime,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textSecondary)),
                // if (holidayName != null && holidayName.isNotEmpty) ...[
                //   const SizedBox(height: 4),
                  // Row(
                  //   mainAxisSize: MainAxisSize.min,
                  //   children: [
                  //     Icon(Icons.celebration_rounded,
                  //         size: 12, color: AppColors.indigo),
                  //     const SizedBox(width: 4),
                  //     Flexible(
                  //       child: Text(holidayName,
                  //           maxLines: 1,
                  //           overflow: TextOverflow.ellipsis,
                  //           style: TextStyle(
                  //               fontSize: 11,
                  //               fontWeight: FontWeight.w600,
                  //               color: AppColors.indigo)),
                  //     ),
                  //   ],
                  // ),
                // ],
                if (locationAddress != null) ...[
                  const SizedBox(height: 2),
                  Text(locationAddress,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                ] else if (totalHoursStr.isNotEmpty && totalHoursStr != '--:--') ...[
                  const SizedBox(height: 2),
                  Text(totalHoursStr,
                      style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                ],
                if (tags.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Wrap(spacing: 4, children: tags.map((t) {
                    final c = t == 'Late In' || t == 'Late Out' ? Colors.orange
                        : t == 'Early Exit' ? Colors.blue : Colors.red;
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: c.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                      child: Text(t, style: TextStyle(fontSize: 9, color: c, fontWeight: FontWeight.w700)),
                    );
                  }).toList()),
                ],
                if (dayFineAmount > 0) ...[
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.money_off_rounded,
                          size: 12, color: Colors.red.shade600),
                      const SizedBox(width: 4),
                      Text(
                        'Fine ₹${NumberFormat('#,##0.00').format(dayFineAmount)}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.red.shade600,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          // Status badge on right
          if (displayStatus.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: st.bg,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(displayStatus.toUpperCase(),
                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: st.fg)),
            ),
        ],
      ),
    );
  }

  Widget _buildHistoryListBody(List<dynamic> displayList) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // History List
        if (displayList.isEmpty && !_isLoadingHistory)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.history_toggle_off,
                    size: 36,
                    color: AppColors.textSecondary.withOpacity(0.5),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'No history records found',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: displayList.length,
            separatorBuilder: (c, i) => const SizedBox(height: 6),
            itemBuilder: (context, index) {
              final record = displayList[index];
              return GestureDetector(
                onTap: () => _showAttendanceDetails(record),
                child: _buildHistoryDateCard(context, record),
              );
            },
          ),
      ],
    );
  }
}
