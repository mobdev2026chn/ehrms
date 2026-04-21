import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import '../../config/app_colors.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/cloud_punch_card.dart';
import '../../services/fcm_service.dart';
import '../announcements/announcements_screen.dart';
import '../alarm/alarm_set_sheet.dart';
import '../notifications/notifications_screen.dart';
import '../../widgets/app_tab_loader.dart';
import '../../widgets/menu_icon_button.dart';
import '../../widgets/bottom_navigation_bar.dart';
import '../../services/geo/live_tracking_service.dart';
import '../geo/live_tracking_screen.dart';
import '../../services/request_service.dart';
import '../../services/attendance_service.dart';
import '../../services/auth_service.dart';
import '../../services/settings_service.dart';
import '../../services/salary_service.dart';
import '../salary/staff_salary_structure_screen.dart';
import '../../utils/salary_structure_calculator.dart';
import '../../utils/salary_fine_summary.dart';
import '../../utils/attendance_display_util.dart';
import '../../utils/absent_alert_helper.dart';
import '../../utils/rotational_shift_util.dart';

class HomeDashboardScreen extends StatefulWidget {
  final Function(int index, {int subTabIndex})? onNavigate;

  /// When true, only the body content is built (no Scaffold/AppBar/drawer). Use when embedded in Dashboard.
  final bool embeddedInDashboard;

  /// Used when embedded in Dashboard: drawer tab index and callback for tab switching.
  final int? dashboardTabIndex;
  final void Function(int index)? onNavigateToIndex;

  /// When true, this screen is the active tab. Used to refresh once when opening.
  final bool? isActiveTab;

  /// When this notifier fires (e.g. after attendance submit), refresh dashboard data.
  final ValueListenable<int>? refreshTrigger;

  /// Optional parent callback to recompute bottom-nav punch visibility after refresh.
  final Future<void> Function()? onDashboardDataRefreshed;

  const HomeDashboardScreen({
    super.key,
    this.onNavigate,
    this.embeddedInDashboard = false,
    this.dashboardTabIndex,
    this.onNavigateToIndex,
    this.isActiveTab,
    this.refreshTrigger,
    this.onDashboardDataRefreshed,
  });

  @override
  State<HomeDashboardScreen> createState() => _HomeDashboardScreenState();
}

class _HomeDashboardScreenState extends State<HomeDashboardScreen> {
  String _userName = 'User';
  String _companyName = '';
  String? _avatarUrl;

  final RequestService _requestService = RequestService();
  final AttendanceService _attendanceService = AttendanceService();
  final AuthService _authService = AuthService();
  final SettingsService _settingsService = SettingsService();
  final SalaryService _salaryService = SalaryService();

  List<dynamic> _recentLeaves = [];

  // ignore: unused_field - kept for when Active Loans card is shown again
  List<dynamic> _activeLoans = [];
  bool _isLoadingDashboard = false;
  bool _isRefreshingInBackground = false;
  bool _isFetchingMonthAttendance = false;
  Map<String, dynamic>? _todayAttendance;
  Map<String, dynamic>? _monthData;
  Map<String, dynamic>? _stats;
  DateTime _selectedMonth = DateTime.now();

  /// Populated from GET /auth/profile (company.settings.attendance.shifts) for rotational calendar.
  Map<String, dynamic>? _profileCompanyDoc;
  String? _profileStaffShiftName;

  /// Latest `staffData` map from profile (for reconciling shift key after /attendance/today template loads).
  Map<String, dynamic>? _profileStaffDataSnapshot;
  DateTime? _profileJoiningDate;

  /// True when staff's assigned shift row is rotational (today's template only applies to "today").
  bool _profileShiftIsRotational = false;

  // Salary calculation data (same logic as Salary Overview "This Month Net")
  double _calculatedMonthSalary = 0;
  double _overallMonthlyNetSalary = 0;

  // ignore: unused_field - kept for when Present Days / salary breakdown is shown again
  int _workingDaysForSalary =
      0; // Full-month working days used for salary (same as Salary Overview)

  // Active loans count (from loan request module); kept for when Active Loans card is shown again
  // ignore: unused_field
  int _activeLoansCount = 0;

  bool _isCandidate = false;
  bool _liveTrackingActive = false;

  List<dynamic> _todayAnnouncements = [];
  List<dynamic> _todayCelebrations = [];
  List<dynamic> _upcomingCelebrations = [];
  int _fcmNotificationCount = 0;

  Future<void> _persistPerDaySalary(double value, {double? grossValue}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(kAppNetPerDaySalaryPrefsKey, value);
      if (grossValue != null) {
        await prefs.setDouble(kAppGrossPerDaySalaryPrefsKey, grossValue);
      }
      // Backward compatibility for already released readers.
      await prefs.setDouble(kAppLegacyPerDaySalaryPrefsKey, value);
      if (kDebugMode) {
        debugPrint(
          '[Fine TEST][Dashboard] Stored netPerDaySalary: '
          'key=$kAppNetPerDaySalaryPrefsKey value=${value.toStringAsFixed(2)} '
          'grossKey=$kAppGrossPerDaySalaryPrefsKey grossValue=${grossValue?.toStringAsFixed(2) ?? "n/a"}',
        );
      }
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    _loadData();
    _checkLiveTracking();
    widget.refreshTrigger?.addListener(_onRefreshTriggered);
  }

  void _onRefreshTriggered() {
    if (mounted) _loadData();
  }

  @override
  void dispose() {
    widget.refreshTrigger?.removeListener(_onRefreshTriggered);
    super.dispose();
  }

  @override
  void didUpdateWidget(HomeDashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshTrigger != widget.refreshTrigger) {
      oldWidget.refreshTrigger?.removeListener(_onRefreshTriggered);
      widget.refreshTrigger?.addListener(_onRefreshTriggered);
    }
    // Whenever user opens or switches to Dashboard tab, refresh all values
    if (widget.isActiveTab == true && oldWidget.isActiveTab != true) {
      _loadData();
      _checkLiveTracking();
    }
  }

  Future<void> _checkLiveTracking() async {
    final active = await LiveTrackingService().isActive();
    // Sync: if user tapped "Stop tracking" in notification, native stopped but we had stale state
    if (active) {
      // Retry: cold start can report false before native tracker is ready — avoid wiping trip prefs.
      final isTracking = await LiveTrackingService()
          .isBackgroundLocationTrackingRunningWithRetry();
      if (!isTracking) {
        await LiveTrackingService().stopTracking();
        if (mounted) setState(() => _liveTrackingActive = false);
        return;
      }
    }
    if (mounted) setState(() => _liveTrackingActive = active);
  }

  bool _isDashboardAnnouncementNotExpired(dynamic item) {
    if (item is! Map) return true;

    DateTime? parseLocal(dynamic value) {
      final raw = value?.toString().trim() ?? '';
      if (raw.isEmpty) return null;
      return DateTime.tryParse(raw)?.toLocal();
    }

    final now = DateTime.now();
    final expiryDate = parseLocal(item['expiryDate']);
    if (expiryDate != null && expiryDate.isBefore(now)) {
      return false;
    }

    final endDate = parseLocal(item['endDate']);
    if (endDate != null && endDate.isBefore(now)) {
      return false;
    }

    return true;
  }

  Future<void> _openLiveTracking() async {
    final info = await LiveTrackingService().getActiveTaskInfo();
    if (!mounted || info == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LiveTrackingScreen(
          taskId: info['taskId'] as String,
          taskMongoId: info['taskMongoId'] as String,
          pickupLocation: LatLng(
            info['pickupLat'] as double,
            info['pickupLng'] as double,
          ),
          dropoffLocation: LatLng(
            info['dropoffLat'] as double,
            info['dropoffLng'] as double,
          ),
          task: null,
        ),
      ),
    );
    if (mounted) _checkLiveTracking();
  }

  /// Uses [flattenTodayAttendancePayload] so holiday / week off / comp-off / leave
  /// flags from GET /attendance/today are not dropped (they live on the response root).
  Map<String, dynamic>? _extractLiveTodayAttendance(dynamic responseBody) {
    if (responseBody is! Map<String, dynamic>) return null;

    // 1. Try our helper that flattens the nested data + root flags
    final merged = flattenTodayAttendancePayload(responseBody);
    if (merged != null &&
        (merged['punchIn'] != null || merged['status'] != null)) {
      return merged;
    }

    // 2. Fallback to extracting just the inner data if merged failed
    final nested = responseBody['data'];
    if (nested is Map<String, dynamic>)
      return Map<String, dynamic>.from(nested);
    if (nested is Map) return Map<String, dynamic>.from(nested);

    // 3. Fallback to the root if fields are there directly
    final hasFields =
        responseBody['punchIn'] != null ||
        responseBody['punchOut'] != null ||
        responseBody['status'] != null;
    if (hasFields) return Map<String, dynamic>.from(responseBody);

    return null;
  }

  Future<void> _loadData() async {
    final hasCachedData = _stats != null;
    // Full-screen loading only when no cached data; otherwise show content and refresh in background
    if (!hasCachedData) {
      setState(() => _isLoadingDashboard = true);
    } else {
      setState(() => _isRefreshingInBackground = true);
    }

    try {
      const dashboardLoadTimeout = Duration(seconds: 35);
      final sw = Stopwatch()..start();
      if (kDebugMode) {
        debugPrint(
          '[DashboardLoad] start | hasCachedData=$hasCachedData | '
          'timeout=${dashboardLoadTimeout.inSeconds}s',
        );
      }
      // Load local user data (name, company) from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      if (kDebugMode) {
        debugPrint(
          '[DashboardLoad] prefs loaded in ${sw.elapsedMilliseconds}ms',
        );
      }
      final userString = prefs.getString('user');
      if (userString != null) {
        final data = jsonDecode(userString);
        if (mounted) {
          setState(() {
            _userName = data['name'] ?? 'User';
            _isCandidate =
                (data['role'] ?? '').toString().toLowerCase() == 'candidate';
            final cachedCompanyName = data['companyName'];
            if (cachedCompanyName is String &&
                cachedCompanyName.trim().isNotEmpty) {
              _companyName = cachedCompanyName.trim();
            }
            final av =
                (data['avatar'] ??
                        data['photoUrl'] ??
                        (data['profile'] is Map
                            ? data['profile']['avatar']
                            : null))
                    ?.toString();
            _avatarUrl =
                (av != null &&
                    av.trim().isNotEmpty &&
                    av.trim().startsWith('http'))
                ? av.trim()
                : null;
          });
        }
      }

      // Run dashboard, month attendance, loans, and profile (shifts for rotational calendar) in parallel
      final dashboardFuture = _requestService.getDashboardData();
      final liveTodayFuture = _attendanceService.getTodayAttendance(
        forceRefresh: true,
      );
      final profileFuture = _authService.getProfile();
      final businessFuture = _settingsService.getBusiness();
      _fetchMonthAttendance(forceRefresh: true);
      _fetchActiveLoans();
      final fcmFuture = FcmService.getStoredNotifications();
      if (kDebugMode) {
        debugPrint(
          '[DashboardLoad] parallel requests started at ${sw.elapsedMilliseconds}ms',
        );
      }

      final settled = await Future.wait<dynamic>([
        dashboardFuture.timeout(
          dashboardLoadTimeout,
          onTimeout: () => {'success': false, 'message': 'Dashboard timeout'},
        ),
        liveTodayFuture.timeout(
          dashboardLoadTimeout,
          onTimeout: () => {'success': false, 'data': null},
        ),
        fcmFuture.timeout(
          dashboardLoadTimeout,
          onTimeout: () => <Map<String, dynamic>>[],
        ),
      ]);

      final result = settled[0] as Map<String, dynamic>;
      final liveTodayResult = settled[1] as Map<String, dynamic>;
      final fcmList = settled[2] as List<dynamic>;
      if (kDebugMode) {
        debugPrint(
          '[DashboardLoad] core requests settled in ${sw.elapsedMilliseconds}ms | '
          'dashboardSuccess=${result['success']} | '
          'liveTodaySuccess=${liveTodayResult['success']} | '
          'fcmCount=${fcmList.length}',
        );
      }

      // Keep profile/settings enrichment non-blocking so dashboard content is not delayed.
      Future<void>(() async {
        try {
          final profileSettled = await profileFuture.timeout(
            dashboardLoadTimeout,
            onTimeout: () => {'success': false, 'data': null},
          );
          final businessSettled = await businessFuture.timeout(
            dashboardLoadTimeout,
            onTimeout: () => {'success': false, 'data': null},
          );
          if (!mounted) return;
          Map<String, dynamic>? businessFromSettings;
          if (businessSettled['success'] == true &&
              businessSettled['data'] is Map<String, dynamic>) {
            final b =
                (businessSettled['data'] as Map<String, dynamic>)['business'];
            if (b is Map) {
              businessFromSettings = Map<String, dynamic>.from(b);
            }
          }
          if (profileSettled['success'] == true &&
              profileSettled['data'] is Map) {
            _applyShiftContextFromProfile(
              Map<String, dynamic>.from(profileSettled['data'] as Map),
              businessFromSettingsApi: businessFromSettings,
            );
          }
          if (kDebugMode) {
            debugPrint(
              '[DashboardLoad] background profile/settings settled at ${sw.elapsedMilliseconds}ms | '
              'profileSuccess=${profileSettled['success']} | '
              'businessSuccess=${businessSettled['success']}',
            );
          }
        } catch (e) {
          if (kDebugMode) {
            debugPrint('[DashboardLoad] background profile/settings error: $e');
          }
        }
      });
      if (mounted) {
        if (result['success']) {
          final data = result['data'];
          final stats = data['stats'];
          final liveTodayAttendance = _extractLiveTodayAttendance(
            liveTodayResult['data'],
          );
          final activeLoansList = stats?['activeLoansList'];
          final loansList = activeLoansList is List
              ? activeLoansList
              : <dynamic>[];
          setState(() {
            _stats = stats;
            _recentLeaves = data['recentLeaves'] ?? [];
            _activeLoans = loansList;
            _activeLoansCount = loansList.length;
            _todayAttendance = liveTodayAttendance ?? stats?['attendanceToday'];
            _todayAnnouncements = data['todayAnnouncements'] is List
                ? (data['todayAnnouncements'] as List)
                      .where(_isDashboardAnnouncementNotExpired)
                      .toList()
                : [];
            _todayCelebrations = data['todayCelebrations'] is List
                ? data['todayCelebrations'] as List
                : [];
            _upcomingCelebrations = data['upcomingCelebrations'] is List
                ? data['upcomingCelebrations'] as List
                : [];
            if (kDebugMode) {
              debugPrint(
                '[Celebrations] today: ${_todayCelebrations.length} items',
              );
              for (final c in _todayCelebrations) {
                final map = c is Map ? c : <String, dynamic>{};
                debugPrint(
                  '  - ${map['name']} | type=${map['type']} | yearsOfService=${map['yearsOfService']} | displayDate=${map['displayDate']}',
                );
              }
              debugPrint(
                '[Celebrations] upcoming: ${_upcomingCelebrations.length} items',
              );
              for (final c in _upcomingCelebrations) {
                final map = c is Map ? c : <String, dynamic>{};
                debugPrint(
                  '  - ${map['name']} | type=${map['type']} | yearsOfService=${map['yearsOfService']} | daysLeft=${map['daysLeft']} | displayDate=${map['displayDate']}',
                );
              }
            }
            _fcmNotificationCount = fcmList
                .where((e) => ((e['body']?.toString() ?? '').trim()).isNotEmpty)
                .length;
          });
          if (kDebugMode) {
            debugPrint(
              '[DashboardLoad] state updated in ${sw.elapsedMilliseconds}ms | '
              'recentLeaves=${_recentLeaves.length} | '
              'todayAnnouncements=${_todayAnnouncements.length} | '
              'todayCelebrations=${_todayCelebrations.length}',
            );
          }
          _reconcileShiftKeyWithTodayTemplate();
          _calculateSalaryFromModule();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            final punchIn = _todayAttendance?['punchIn']?.toString().trim();
            final hasPunchInStr = punchIn != null && punchIn.isNotEmpty;
            final hasPunchInFlag = _todayAttendance?['hasPunchIn'] == true;
            showAbsentAlertIfNeeded(
              context,
              hasPunchInToday: hasPunchInStr || hasPunchInFlag,
              suppressAlert: shouldSuppressAbsentAlert(_todayAttendance),
            );
          });
        } else {
          if (kDebugMode) {
            debugPrint(
              '[DashboardLoad] dashboard API returned failure in ${sw.elapsedMilliseconds}ms | '
              'message=${result['message']}',
            );
          }
          setState(
            () => _fcmNotificationCount = fcmList
                .where((e) => ((e['body']?.toString() ?? '').trim()).isNotEmpty)
                .length,
          );
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[DashboardLoad] exception: $e');
      }
      // Keep existing UI data on transient failures.
    } finally {
      if (widget.onDashboardDataRefreshed != null) {
        await widget.onDashboardDataRefreshed!.call();
      }
      if (mounted) {
        setState(() {
          _isLoadingDashboard = false;
          _isRefreshingInBackground = false;
        });
      }
      if (kDebugMode) {
        debugPrint('[DashboardLoad] finished');
      }
    }
  }

  /// Prefer today's template name so [shiftName] that duplicates the attendance template label is ignored (backend parity).
  void _reconcileShiftKeyWithTodayTemplate() {
    if (!mounted || _profileStaffDataSnapshot == null) return;
    final t = _todayAttendance?['template'];
    String? templateLabel;
    if (t is Map) {
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
    var rotational = false;
    final shifts = shiftsListFromCompany(_profileCompanyDoc);
    final keyTrim = (newKey ?? '').trim();
    if (shifts != null) {
      final w = keyTrim.isNotEmpty
          ? findShiftByStaffKey(shifts, keyTrim)
          : (shifts.first is Map
                ? Map<String, dynamic>.from(shifts.first as Map)
                : null);
      if (w != null) {
        rotational = isRotationalShiftWrapper(Map<String, dynamic>.from(w));
      }
    }
    setState(() {
      _profileStaffShiftName = newKey;
      _profileShiftIsRotational = rotational;
    });
  }

  /// Company.shifts + staff.shiftName + joiningDate (web: full shifts from GET /settings/business).
  void _applyShiftContextFromProfile(
    Map<String, dynamic> data, {
    Map<String, dynamic>? businessFromSettingsApi,
  }) {
    if (!mounted) return;
    final staff = data['staffData'];
    Map<String, dynamic>? company;
    String? shiftKey;
    DateTime? jd;
    var rotational = false;
    _profileStaffDataSnapshot = null;
    if (staff is Map) {
      final m = Map<String, dynamic>.from(staff);
      _profileStaffDataSnapshot = Map<String, dynamic>.from(m);
      final bid = m['businessId'];
      if (bid is Map) company = Map<String, dynamic>.from(bid);
      shiftKey = staffShiftKeyFromProfileMap(m);
      jd = parseJoiningDate(m['joiningDate']);
      company = companyDocForShiftResolution(
        profilePopulatedCompany: company,
        businessFromSettingsBusinessApi: businessFromSettingsApi,
      );
      final shifts = shiftsListFromCompany(company);
      final keyTrim = (shiftKey ?? '').trim();
      if (shifts != null) {
        final w = keyTrim.isNotEmpty
            ? findShiftByStaffKey(shifts, keyTrim)
            : (shifts.first is Map
                  ? Map<String, dynamic>.from(shifts.first as Map)
                  : null);
        if (w != null) {
          rotational = isRotationalShiftWrapper(Map<String, dynamic>.from(w));
        }
      }
    }
    setState(() {
      _profileCompanyDoc = company;
      _profileStaffShiftName = shiftKey;
      _profileJoiningDate = jd;
      _profileShiftIsRotational = rotational;
    });
  }

  /// Merged `template` from live GET /attendance/today (openWorkHours matches server getShiftTimings).
  Map<String, dynamic>? _todayAttendanceTemplateMap() {
    final t = _todayAttendance?['template'];
    if (t is Map<String, dynamic>) return t;
    if (t is Map) return Map<String, dynamic>.from(t);
    return null;
  }

  /// For rotational staff, only merge today's template on the current calendar day.
  Map<String, dynamic>? _templateOverrideForCalendarDay(DateTime dayLocal) {
    final tmpl = _todayAttendanceTemplateMap();
    if (tmpl == null || tmpl.isEmpty) return null;
    if (!_profileShiftIsRotational) return tmpl;
    final n = DateTime.now();
    final same =
        dayLocal.year == n.year &&
        dayLocal.month == n.month &&
        dayLocal.day == n.day;
    return same ? tmpl : null;
  }

  /// Web-style status chip (top-right of calendar day).
  Widget _dashboardCalendarStatusChip(String label, Color bg, Color fg) {
    // Keep status style text-only (no badge background/border).
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1, vertical: 1),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.fade,
        softWrap: false,
        style: TextStyle(
          fontSize: 7,
          height: 1.0,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }

  Widget _buildDashboardAssignedShiftHeader() {
    final colorScheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final snap = effectiveShiftForCalendarDay(
      companyDoc: _profileCompanyDoc,
      staffShiftKey: _profileStaffShiftName,
      dayLocal: today,
      joiningDate: _profileJoiningDate,
      attendanceTodayTemplate: _todayAttendanceTemplateMap(),
    );
    final appliedId = _todayAppliedShiftIdForHeader();
    final appliedRes = appliedId != null
        ? appliedShiftPastResolvedFromCompany(
            companyDoc: _dashboardCompanyDocForAppliedShiftLookup(),
            appliedShiftId: appliedId,
          )
        : null;
    final appliedHeaderLine = appliedRes != null
        ? _appliedShiftCompactLineFromResult(appliedRes)
        : null;
    if (snap == null && appliedHeaderLine == null) {
      return const SizedBox.shrink();
    }

    if (kDebugMode && snap != null) {
      final reqMin = snap.requiredWorkMinutes();
      String reqHStr;
      if (reqMin == null) {
        reqHStr = 'n/a';
      } else if (reqMin % 60 == 0) {
        reqHStr = '${reqMin ~/ 60}h';
      } else {
        reqHStr = '${(reqMin / 60).toStringAsFixed(2)}h';
      }
      final windowStr =
          (snap.startTime != null &&
              snap.endTime != null &&
              snap.startTime!.isNotEmpty &&
              snap.endTime!.isNotEmpty)
          ? '${snap.startTime}-${snap.endTime}'
          : (snap.isOpen
                ? 'open required=${snap.openWorkHours ?? '-'}h'
                : 'n/a');
      final tmpl = _todayAttendanceTemplateMap();
      final tmplStart = tmpl == null
          ? '-'
          : (trimmedTimeField(tmpl['shiftStartTime']) ??
                trimmedTimeField(tmpl['startTime']) ??
                '-');
      final tmplEnd = tmpl == null
          ? '-'
          : (trimmedTimeField(tmpl['shiftEndTime']) ??
                trimmedTimeField(tmpl['endTime']) ??
                '-');
      debugPrint(
        '[DashboardTodayShift] name=${snap.displayName} '
        'type=${snap.shiftTypeLower} window=$windowStr '
        'requiredWorkMinutes=$reqMin requiredHours~$reqHStr '
        'openWorkHours=${snap.isOpen ? '${snap.openWorkHours}' : '-'} '
        'otBufferMin=${snap.otBufferMinutes ?? '-'} '
        'templateTimes=$tmplStart/$tmplEnd '
        'rotationTemplate=${snap.rotationTemplateName ?? '-'} '
        'rotationalMode=${snap.rotationalMode ?? '-'} '
        'cycleDay=${snap.cycleDayIndex1Based ?? '-'} '
        'cycleLen=${snap.cycleLength ?? '-'} '
        'compact="${snap.compactLine()}"',
      );
    }

    final refFmt = DateFormat('EEE, MMM d, yyyy').format(now);
    final rotName = snap?.rotationTemplateName;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colorScheme.outline.withOpacity(0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    'YOUR ASSIGNED SHIFT',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Text(
                  refFmt,
                  style: TextStyle(
                    fontSize: 11,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            if (rotName != null && rotName.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                rotName,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade100),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Today's working shift (this cycle)",
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.blue.shade900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    appliedHeaderLine ?? snap?.compactLine() ?? '',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      height: 1.2,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _fetchMonthAttendance({bool forceRefresh = false}) async {
    // Prevent concurrent calls for same operation
    if (_isFetchingMonthAttendance && !forceRefresh) return;

    _isFetchingMonthAttendance = true;
    try {
      final result = await _attendanceService.getMonthAttendance(
        _selectedMonth.year,
        _selectedMonth.month,
        forceRefresh: forceRefresh,
      );
      if (mounted) {
        if (result['success']) {
          setState(() {
            _monthData = result['data'];
          });
        }
      }
    } finally {
      if (mounted) {
        _isFetchingMonthAttendance = false;
      }
    }
  }

  Future<void> _fetchActiveLoans() async {
    try {
      final result = await _requestService.getLoanRequests(
        status: 'Active',
        page: 1,
        limit: 100, // Get all active loans
      );
      if (mounted && result['success']) {
        List<dynamic> loans = [];
        if (result['data'] is Map) {
          loans = result['data']['loans'] ?? [];
        } else if (result['data'] is List) {
          loans = result['data'];
        }
        setState(() {
          _activeLoans = loans;
          _activeLoansCount = loans.length;
        });
      }
    } catch (e) {
      // Ignore
    }
  }

  Future<void> _calculateSalaryFromModule() async {
    try {
      final now = DateTime.now();
      final monthIndex = now.month;
      final year = now.year;

      // 1. Fetch staff profile (same as Salary Overview)
      final profileResult = await _authService.getProfile();
      if (profileResult['success'] != true) return;

      final staffData = profileResult['data']?['staffData'];
      if (staffData == null || staffData['salary'] == null) return;

      final staffSalary = staffData['salary'] as Map<String, dynamic>;
      final staffId = staffData['_id']?.toString();
      final basicSalary = staffSalary['basicSalary'];
      if (basicSalary == null || (basicSalary is num && basicSalary <= 0)) {
        return;
      }

      // Company name from business
      String? companyName;
      try {
        final businessData = staffData['businessId'];
        if (businessData is Map<String, dynamic>) {
          companyName = businessData['name']?.toString();
        }
      } catch (_) {}

      // Business settings (weekly off, holidays) - same as Salary Overview
      // When staff has a weekly holiday template assigned, use it; else use business (Company.settings.business)
      Map<String, dynamic>? businessSettings;
      if (staffData['branchId'] != null &&
          staffData['branchId'] is Map &&
          staffData['branchId']['businessId'] != null &&
          staffData['branchId']['businessId'] is Map) {
        businessSettings = staffData['branchId']['businessId'];
      } else if (staffData['businessId'] != null &&
          staffData['businessId'] is Map) {
        businessSettings = staffData['businessId'];
      }

      String weeklyOffPattern = 'standard';
      List<int> weeklyHolidays = [];
      final weeklyHolidayTemplate = staffData['weeklyHolidayTemplateId'];
      final hasTemplate =
          weeklyHolidayTemplate is Map<String, dynamic> &&
          (weeklyHolidayTemplate['settings'] != null) &&
          (weeklyHolidayTemplate['isActive'] != false);
      if (hasTemplate) {
        final template = weeklyHolidayTemplate;
        final s = template['settings'] as Map<String, dynamic>? ?? {};
        weeklyOffPattern = (s['weeklyOffPattern'] is String)
            ? s['weeklyOffPattern'] as String
            : 'standard';
        if (s['weeklyHolidays'] != null && s['weeklyHolidays'] is List) {
          weeklyHolidays = (s['weeklyHolidays'] as List)
              .map((h) {
                if (h is Map) {
                  final day = h['day'];
                  return (day is int) ? day : (day is num ? day.toInt() : -1);
                }
                return -1;
              })
              .where((day) => day >= 0 && day <= 6)
              .toList();
        }
      } else if (businessSettings != null &&
          businessSettings['settings'] != null &&
          businessSettings['settings']['business'] != null) {
        final business =
            businessSettings['settings']['business'] as Map<String, dynamic>;
        weeklyOffPattern = (business['weeklyOffPattern'] is String)
            ? business['weeklyOffPattern'] as String
            : 'standard';
        if (business['weeklyHolidays'] != null &&
            business['weeklyHolidays'] is List) {
          weeklyHolidays = (business['weeklyHolidays'] as List)
              .map((h) {
                if (h is Map) {
                  final day = h['day'];
                  return (day is int) ? day : (day is num ? day.toInt() : -1);
                }
                return -1;
              })
              .where((day) => day >= 0 && day <= 6)
              .toList();
        }
      }

      // 2. Backend payroll stats (for working days only; This Month Net uses client calculation with Present + Approved)
      Map<String, dynamic>? backendStats;
      try {
        final statsResult = await _salaryService.getSalaryStats(
          month: monthIndex,
          year: year,
        );
        if (statsResult['stats'] != null) {
          backendStats = statsResult['stats'] as Map<String, dynamic>;
        }
      } catch (e) {
        // Ignore
      }

      // 3. Fetch attendance for current month
      final attendanceResult = await _attendanceService.getMonthAttendance(
        year,
        monthIndex,
      );
      List<dynamic> attendanceRecords = [];
      List<DateTime> holidays = [];
      if (attendanceResult['success'] == true) {
        final attendanceData = attendanceResult['data'];
        attendanceRecords = attendanceData['attendance'] ?? [];
        if (attendanceData['holidays'] != null) {
          holidays = (attendanceData['holidays'] as List)
              .map((h) {
                try {
                  return DateTime.parse(h['date']);
                } catch (e) {
                  return null;
                }
              })
              .whereType<DateTime>()
              .toList();
        }
      }

      // 4. Present days and Paid Leave – match Salary Overview reducer (present excludes paid leave).
      // Do NOT rely on /payrolls/stats attendance.presentDays here: it can differ in half-day/pending
      // handling and timezone parsing. Use the month attendance rows we already fetched.
      double presentDays = 0;
      double paidLeaveDays = 0;
      double unpaidLeaveDays = 0;
      if (attendanceRecords.isNotEmpty) {
        final today = DateTime.now();
        final todayKey = DateFormat(
          'yyyy-MM-dd',
        ).format(DateTime(today.year, today.month, today.day));
        for (final record in attendanceRecords) {
          final recordKey = normalizeAttendanceDateKeyForSalary(record['date']);
          if (recordKey != null && recordKey.compareTo(todayKey) > 0) {
            continue;
          }

          final status = (record['status'] as String? ?? '')
              .trim()
              .toLowerCase();
          final leaveType = (record['leaveType'] as String? ?? 'Leave')
              .trim()
              .toLowerCase();
          final hasHalfDaySession = record['halfDaySession'] != null;
          final isHalfDayStatus =
              status == 'half day' || leaveType == 'half day';
          final isHalfDay = isHalfDayStatus || hasHalfDaySession;

          // Present-days reducer (same as Salary Overview)
          if (status == 'present' || status == 'approved') {
            presentDays += hasHalfDaySession ? 0.5 : 1.0;
          } else if (status == 'half day') {
            presentDays += 0.5;
          } else if (status == 'pending' && hasHalfDaySession) {
            presentDays += 0.5;
          }

          // Paid / unpaid leave (same as Salary Overview `_computeWebAttendanceBreakdown`)
          if (status == 'on leave' || status == 'half day') {
            final dayValue = isHalfDay ? 0.5 : 1.0;
            final compensationType = (record['compensationType'] as String?)
                ?.trim()
                .toLowerCase();
            final isPaidLeave =
                record['isPaidLeave'] == true ||
                compensationType == 'paid' ||
                (compensationType == null && record['isPaidLeave'] != false);
            if (isPaidLeave) {
              paidLeaveDays += dayValue;
            } else {
              unpaidLeaveDays += dayValue;
            }
          }
        }
      } else if (backendStats != null && backendStats['attendance'] != null) {
        // Fallback only when month attendance isn't available.
        final att = backendStats['attendance'] as Map;
        presentDays = (att['presentDays'] as num?)?.toDouble() ?? 0;
        paidLeaveDays = (att['paidLeaveDays'] as num?)?.toDouble() ?? 0;
      }

      debugPrint(
        '[SalaryCalc][Dashboard] presentDays=$presentDays paidLeaveDays=$paidLeaveDays '
        'unpaidLeaveDays=$unpaidLeaveDays attendanceRows=${attendanceRecords.length}',
      );
      // 5. Working days — must match Salary Overview (`salary_overview_screen.dart` 4a):
      // client `calculateWorkingDays` only (till-date for current month + full month for denominator).
      // Do NOT use /payrolls/stats `workingDays` / `workingDaysFullMonth`: they often differ (e.g. 20/24
      // vs 19/22) and prorated MTD net will not match the Salary tab.
      final endDateForCurrentMonth =
          (year == now.year && monthIndex == now.month)
          ? DateTime(now.year, now.month, now.day)
          : null;
      final webTillDateInfo = calculateWorkingDays(
        year,
        monthIndex,
        holidays,
        weeklyOffPattern,
        weeklyHolidays,
        endDateForCurrentMonth,
      );
      final webFullMonthInfo = calculateWorkingDays(
        year,
        monthIndex,
        holidays,
        weeklyOffPattern,
        weeklyHolidays,
      );
      final workingDaysInfo = WorkingDaysInfo(
        totalDays: webTillDateInfo.totalDays,
        workingDays: webTillDateInfo.workingDays,
        weekends: webTillDateInfo.weekends,
        holidayCount: webTillDateInfo.holidayCount,
        workingDaysFullMonth: webFullMonthInfo.workingDays,
      );
      debugPrint(
        '[SalaryCalc][Dashboard] working days: tillDate=${workingDaysInfo.workingDays} '
        'fullMonth=${workingDaysInfo.workingDaysFullMonth} (Salary Overview parity)',
      );

      // 5b. Payable-days divisor from /payroll/stats (web template rule: fixed days, EXCLUDE_WEEK_OFFS, CALENDAR_DAYS, etc.)
      int? payableDaysBaseFromStats;
      String? payableRuleFromStats;
      if (backendStats != null && backendStats['attendance'] is Map) {
        final att = backendStats['attendance'] as Map;
        payableDaysBaseFromStats = (att['payableDaysBase'] as num?)?.toInt();
        payableRuleFromStats = att['payableRule']?.toString();
      }
      int salaryPayableBaseDays(int fallbackFullMonthWd) {
        final b = payableDaysBaseFromStats ?? 0;
        return b > 0 ? b : fallbackFullMonthWd;
      }

      // 6. Salary structure (same as Salary Overview)
      final salaryInputs = SalaryStructureInputs.fromMap(staffSalary);
      final calculatedSalary = calculateSalaryStructure(salaryInputs);

      // 7. Fine totals from attendance records only (server/web computes and persists fines).
      final fineSummary = aggregateSalaryFineSummary(attendanceRecords);
      final double totalFineAmount = fineSummary.totalFineAmount;

      // 7b. Payroll + preview (before per-day prefs for fines — match web preview salaryBasis ÷ fullMonth WD).
      Map<String, dynamic>? currentPayroll;
      Map<String, dynamic>? payrollPreview;
      if (staffId != null && staffId.isNotEmpty) {
        try {
          final payrollData = await _salaryService.getPayrolls(
            month: monthIndex,
            year: year,
            page: 1,
            limit: 1,
          );
          if (payrollData['success'] == true && payrollData['data'] != null) {
            final payrolls = payrollData['data']['payrolls'] as List?;
            if (payrolls != null && payrolls.isNotEmpty) {
              final row = payrolls.first;
              if (row is Map &&
                  row['month'] == monthIndex &&
                  row['year'] == year) {
                currentPayroll = Map<String, dynamic>.from(row);
              }
            }
          }
        } catch (_) {}

        try {
          final previewRes = await _salaryService.previewPayroll(
            employeeId: staffId,
            month: monthIndex,
            year: year,
          );
          if (previewRes['success'] == true &&
              previewRes['data'] is Map<String, dynamic>) {
            final d = previewRes['data'] as Map<String, dynamic>;
            final p = d['preview'];
            if (p is Map) {
              payrollPreview = Map<String, dynamic>.from(p);
            }
          }
        } catch (_) {}
      }

      // 8. Prorated salary: same divisor + numerator as Salary Overview (payable rule + web-style MTD)
      final fallbackWd =
          workingDaysInfo.workingDaysFullMonth ?? workingDaysInfo.workingDays;
      final thisMonthWorkingDaysForProration = salaryPayableBaseDays(
        fallbackWd,
      );
      final ruleLower = (payableRuleFromStats ?? 'present_plus_paid_leave')
          .toLowerCase();
      final payableNumerator = ruleLower == 'present_only'
          ? presentDays
          : presentDays + paidLeaveDays;
      final ProratedSalary proratedSalary;
      if (staffSalary['basicSalary'] != null) {
        proratedSalary = calculateWebStyleMtdProratedSalary(
          SalaryStructureInputs.fromMap(staffSalary),
          thisMonthWorkingDaysForProration,
          payableNumerator,
          totalFineAmount,
        );
      } else {
        proratedSalary = calculateProratedSalary(
          calculatedSalary,
          thisMonthWorkingDaysForProration,
          payableNumerator,
          totalFineAmount,
        );
      }
      final previewFineRates = perDayRatesFromPayrollPreviewForFine(
        payrollPreview,
      );
      final statsFullMonthWd =
          (backendStats != null && backendStats['attendance'] is Map)
          ? ((backendStats['attendance'] as Map)['workingDaysFullMonth']
                    as num?)
                ?.toInt()
          : null;
      final fullWdForPayrollPerDay =
          statsFullMonthWd ??
          workingDaysInfo.workingDaysFullMonth ??
          workingDaysInfo.workingDays;
      final payrollFineRates = previewFineRates == null
          ? perDayRatesFromPayrollRowForFine(
              currentPayroll,
              fullWdForPayrollPerDay,
            )
          : null;

      final perDaySalaryForApp =
          previewFineRates?['net'] ??
          payrollFineRates?['net'] ??
          (thisMonthWorkingDaysForProration > 0
              ? ((calculatedSalary.monthly.netMonthlySalary /
                                thisMonthWorkingDaysForProration) *
                            100)
                        .round() /
                    100
              : 0.0);
      final perDayGrossSalaryForApp =
          previewFineRates?['gross'] ??
          payrollFineRates?['gross'] ??
          (thisMonthWorkingDaysForProration > 0
              ? ((calculatedSalary.monthly.grossSalary /
                                thisMonthWorkingDaysForProration) *
                            100)
                        .round() /
                    100
              : 0.0);
      if (kDebugMode) {
        int? previewFullWd;
        if (payrollPreview != null && payrollPreview['attendance'] is Map) {
          final a = payrollPreview['attendance'] as Map;
          previewFullWd =
              (a['fullMonthWorkingDays'] as num?)?.toInt() ??
              (a['workingDays'] as num?)?.toInt();
        }
        debugPrint(
          '[SalaryCalc][Dashboard] per-day for fine prefs: '
          'previewBasis=${previewFineRates != null} payrollRow=${payrollFineRates != null} '
          'net=$perDaySalaryForApp gross=$perDayGrossSalaryForApp '
          'fullMonthWdPreview=$previewFullWd',
        );
      }
      await _persistPerDaySalary(
        perDaySalaryForApp,
        grossValue: perDayGrossSalaryForApp,
      );
      // Unpaid leave: same as Salary Overview (daily net × unpaid days subtracted from MTD net).
      var proratedNetForMtd = proratedSalary.proratedNetSalary;
      if (thisMonthWorkingDaysForProration > 0 && unpaidLeaveDays > 0) {
        final storedDailyNetRaw = staffData['appPerDayNetSalary'];
        final storedDailyNet = storedDailyNetRaw is num
            ? storedDailyNetRaw.toDouble()
            : null;
        debugPrint(
          '[SalaryCalc][Dashboard] appPerDayNetSalary=${storedDailyNet?.toStringAsFixed(2) ?? "null"} '
          'netMonthly=${calculatedSalary.monthly.netMonthlySalary.toStringAsFixed(2)} '
          'wdForProration=$thisMonthWorkingDaysForProration',
        );
        final dailyNet =
            previewFineRates?['net'] ??
            payrollFineRates?['net'] ??
            storedDailyNet ??
            calculatedSalary.monthly.netMonthlySalary /
                thisMonthWorkingDaysForProration;
        final unpaidDed = dailyNet * unpaidLeaveDays;
        proratedNetForMtd = math.max(
          0,
          proratedSalary.proratedNetSalary - unpaidDed,
        );
        debugPrint(
          '[SalaryCalc][Dashboard] unpaid leave deduction: days=$unpaidLeaveDays '
          'amount=$unpaidDed mtdNet=$proratedNetForMtd',
        );
      }
      debugPrint(
        '[SalaryCalc][Dashboard] proration wdm=$thisMonthWorkingDaysForProration present=$presentDays '
        'fine=$totalFineAmount mtdGross=${proratedSalary.proratedGrossSalary} mtdNet=$proratedNetForMtd',
      );

      final payrollMtdNet = (currentPayroll?['netPay'] as num?)?.toDouble();
      final previewNet = (payrollPreview?['netPay'] as num?)?.toDouble();
      // Salary Overview `_buildThisMonthNetCard`: whenever GET /payroll returns a row
      // (any status including Pending), "This Month Net" uses that document's `netPay`.
      final dynamic statsNetRaw = backendStats?['thisMonthNet'];
      final double? statsThisMonthNet = statsNetRaw is num
          ? statsNetRaw.toDouble()
          : (statsNetRaw is String
                ? double.tryParse(statsNetRaw.trim())
                : null);
      // Keep parity with Salary Overview/Web:
      // - payroll doc net wins when a row exists
      // - otherwise preview net should win over /payroll/stats fallback
      final rawThisMonthNet = currentPayroll != null
          ? (payrollMtdNet ?? previewNet ?? proratedNetForMtd)
          : (previewNet ?? statsThisMonthNet ?? proratedNetForMtd);
      final displayThisMonthNet = rawThisMonthNet < 0 ? 0.0 : rawThisMonthNet;

      if (mounted) {
        final workingDaysUsed = workingDaysInfo.workingDays;
        setState(() {
          _calculatedMonthSalary = displayThisMonthNet;
          _overallMonthlyNetSalary =
              calculatedSalary.monthly.netMonthlySalary < 0
              ? 0.0
              : calculatedSalary.monthly.netMonthlySalary;
          _workingDaysForSalary = workingDaysUsed;
          if (_companyName.isEmpty &&
              companyName != null &&
              companyName.trim().isNotEmpty) {
            _companyName = companyName.trim();
          }
        });
      }
    } catch (e) {
      // Ignore
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final pendingLeaves = _stats?['pendingLeaves']?.toString() ?? '0';
    final formatter = NumberFormat('#,##0.00');
    final mtdNet = _calculatedMonthSalary;
    final monthlyNet = _overallMonthlyNetSalary;
    final hasSalary = mtdNet > 0 || monthlyNet > 0;
    final mtdDisplay = hasSalary ? '₹${formatter.format(mtdNet)}' : '--';
    final monthlyDisplay = hasSalary
        ? '₹${formatter.format(monthlyNet)}'
        : null;
    final presentDaysVal =
        _stats?['attendanceSummary']?['presentDays']?.toString() ?? '0';
    final paidLeaveDaysVal =
        _stats?['attendanceSummary']?['paidLeaveDays']?.toString() ?? '0';
    final presentDaysInt = int.tryParse(presentDaysVal) ?? 0;
    final paidLeaveInt = int.tryParse(paidLeaveDaysVal) ?? 0;
    final presentDays = paidLeaveInt > 0
        ? '$presentDaysInt days present + $paidLeaveInt PL'
        : (presentDaysInt > 0 ? '$presentDaysInt days present' : '');

    final content = RefreshIndicator(
      onRefresh: _loadData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Welcome Card
                  _buildWelcomeCard(),
                  const SizedBox(height: 32),

                  // 2. Quick Actions
                  Text(
                    'Quick Actions',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 16,
                      horizontal: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: _buildQuickActionButtons(),
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // 3. Recent Leaves
                  _buildRecentLeavesCard(),
                  const SizedBox(height: 24),

                  // 4. Celebration and Announcement cards (always visible, one row)
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: _buildCelebrationsCard()),
                        const SizedBox(width: 16),
                        Expanded(child: _buildTodayAnnouncementsCard()),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // 5. Today attendance card
                  if (!_isCandidate) ...[
                    _buildMonthAttendanceCard(dashboardCompact: true),
                    const SizedBox(height: 24),
                  ],

                  // 6. Leave Requests and This Month Net
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: _buildPendingLeavesSummaryCard(pendingLeaves),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildThisMonthNetSummaryCard(
                            mtdDisplay,
                            monthlyDisplay,
                            presentDays,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (widget.embeddedInDashboard) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        extendBodyBehindAppBar: false,
        appBar: AppBar(
          leading: const MenuIconButton(),
          title: const Text(
            'Dashboard',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          centerTitle: true,
          elevation: 0,
          backgroundColor: Colors.white,
          foregroundColor: colorScheme.primary,
          actions: [
            if (1 == 0)
              IconButton(
                icon: Icon(Icons.alarm_outlined, color: AppColors.primary),
                tooltip: 'Alarm',
                onPressed: () {
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (_) => const AlarmSetSheet(),
                  );
                },
              ),
            IconButton(
              icon: _buildNotificationIcon(_fcmNotificationCount),
              tooltip: 'Notifications',
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const NotificationsScreen(),
                  ),
                );
                if (mounted) {
                  final list = await FcmService.getStoredNotifications();
                  setState(
                    () => _fcmNotificationCount = list
                        .where(
                          (e) =>
                              ((e['body']?.toString() ?? '').trim()).isNotEmpty,
                        )
                        .length,
                  );
                }
              },
            ),
            if (_isRefreshingInBackground)
              const Padding(
                padding: EdgeInsets.only(right: 8),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            if (_liveTrackingActive)
              IconButton(
                icon: const Icon(Icons.gps_fixed),
                tooltip: 'Live tracking in progress',
                onPressed: _openLiveTracking,
              ),
          ],
        ),
        drawer: AppDrawer(
          currentIndex: widget.dashboardTabIndex ?? 0,
          onNavigateToIndex: widget.onNavigateToIndex,
        ),
        body: content,
      );
    }
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: false,
      appBar: AppBar(
        leading: const MenuIconButton(),
        title: const Text(
          'Dashboard',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.primary,
        actions: [
          if (1 == 0)
            IconButton(
              icon: Icon(Icons.alarm_outlined, color: colorScheme.primary),
              tooltip: 'Alarm',
              onPressed: () {
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => const AlarmSetSheet(),
                );
              },
            ),
          IconButton(
            icon: _buildNotificationIcon(_fcmNotificationCount),
            tooltip: 'Notifications',
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const NotificationsScreen()),
              );
              if (mounted) {
                final list = await FcmService.getStoredNotifications();
                setState(
                  () => _fcmNotificationCount = list
                      .where(
                        (e) =>
                            ((e['body']?.toString() ?? '').trim()).isNotEmpty,
                      )
                      .length,
                );
              }
            },
          ),
          if (_isRefreshingInBackground)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          if (_liveTrackingActive)
            IconButton(
              icon: const Icon(Icons.gps_fixed),
              tooltip: 'Live tracking in progress',
              onPressed: _openLiveTracking,
            ),
        ],
      ),
      drawer: const AppDrawer(),
      body: content,
    );
  }

  Widget _buildWelcomeCard() {
    final dateStr = DateFormat('d/M, yyyy').format(DateTime.now());
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: AppColors.primary.withOpacity(0.2),
            backgroundImage:
                (_avatarUrl != null && _avatarUrl!.trim().startsWith('http'))
                ? NetworkImage(_avatarUrl!)
                : null,
            child: _avatarUrl == null || !_avatarUrl!.trim().startsWith('http')
                ? Text(
                    _userName.isNotEmpty ? _userName[0].toUpperCase() : 'U',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Welcome back, $_userName!',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      Icons.calendar_today,
                      size: 14,
                      color: Colors.grey.shade600,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      dateStr,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationIcon(int count) {
    const size = 26.0;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(
            Icons.notifications_outlined,
            size: size,
            color: AppColors.primary,
          ),
          if (count > 0)
            Positioned(
              top: -2,
              right: -2,
              child: Container(
                width: count > 9 ? 20 : 16,
                height: count > 9 ? 20 : 16,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x40000000),
                      blurRadius: 2,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: Text(
                  count > 99 ? '99+' : count.toString(),
                  style: TextStyle(
                    fontSize: count > 9 ? 9 : 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _openDashboardCalendarDetailsScreen() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            leading: const MenuIconButton(),
            title: const Text('Attendance Calendar'),
            centerTitle: true,
            backgroundColor: Colors.white,
            foregroundColor: AppColors.primary,
            elevation: 0,
          ),
          drawer: widget.onNavigateToIndex != null
              ? AppDrawer(
                  currentIndex: widget.dashboardTabIndex ?? 0,
                  onNavigateToIndex: widget.onNavigateToIndex,
                )
              : const AppDrawer(),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: _buildMonthAttendanceCard(
                showHeaderIcon: false,
                dashboardCompact: false,
              ),
            ),
          ),
          bottomNavigationBar: AppBottomNavigationBar(currentIndex: -1),
        ),
      ),
    );
  }

  Widget _buildDashboardAnnouncementTile(dynamic a, int i) {
    final map = a is Map<String, dynamic> ? a : <String, dynamic>{};
    final title = map['title']?.toString() ?? 'Announcement';
    final dateValue = map['publishDate'] ?? map['effectiveDate'];
    DateTime? date;
    if (dateValue != null) {
      if (dateValue is String) {
        date = DateTime.tryParse(dateValue);
      } else if (dateValue is Map && dateValue['\$date'] != null) {
        date = DateTime.tryParse(dateValue['\$date'].toString());
      }
    }
    final dateStr = date != null ? DateFormat('d MMM y').format(date) : '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '• ',
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade400,
              fontWeight: FontWeight.w600,
            ),
          ),
          Expanded(
            child: Text(
              '$title${dateStr.isNotEmpty ? ' - $dateStr' : ''}',
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade400,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTodayAnnouncementsCard() {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minWidth: 0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: const Color(0xFF2D2D2D),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(Icons.campaign, color: AppColors.primary, size: 18),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Announcements',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (_todayCelebrations.isNotEmpty)
                    Icon(Icons.celebration, color: AppColors.primary, size: 14),
                ],
              ),
              const SizedBox(height: 8),
              if (_todayAnnouncements.isEmpty)
                Text(
                  'No announcements',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                )
              else
                ..._todayAnnouncements
                    .take(3)
                    .map((a) => _buildDashboardAnnouncementTile(a, 0)),
              if (_todayAnnouncements.length > 3)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: GestureDetector(
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const AnnouncementsScreen(),
                        ),
                      );
                    },
                    child: Text(
                      'View all',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCelebrationsCard() {
    final todayList = _todayCelebrations;
    final allItems = todayList
        .take(2)
        .map((c) => _buildCelebrationBulletItem(c, true))
        .toList();

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minWidth: 0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: const Color(0xFF2D2D2D),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(Icons.celebration, color: AppColors.primary, size: 18),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Celebrations',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(Icons.cake, color: AppColors.primary, size: 14),
                ],
              ),
              const SizedBox(height: 8),
              if (allItems.isEmpty)
                Text(
                  'No celebrations',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                )
              else
                ...allItems,
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCelebrationBulletItem(dynamic c, bool isToday) {
    final name = c['name']?.toString() ?? '—';
    final type = c['type']?.toString() ?? 'birthday';
    final typeLabel = type == 'anniversary' ? 'Work Anniversary' : 'Birthday';
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '• ',
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade400,
              fontWeight: FontWeight.w600,
            ),
          ),
          Expanded(
            child: Text(
              '$name - $typeLabel',
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade400,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  String _anniversaryYearsLabel(int years) {
    if (years == 1) return '1 year';
    if (years == 2) return '2 years';
    final last = years % 10;
    final tens = (years ~/ 10) % 10;
    final suffix = (tens == 1)
        ? 'th'
        : (last == 1)
        ? 'st'
        : (last == 2)
        ? 'nd'
        : (last == 3)
        ? 'rd'
        : 'th';
    return '$years$suffix year';
  }

  // ignore: unused_element
  Widget _buildCelebrationTile(dynamic c, {required bool isToday}) {
    final colorScheme = Theme.of(context).colorScheme;
    final name = c['name']?.toString() ?? '—';
    final displayDate = c['displayDate']?.toString() ?? '';
    final daysLeft = (c['daysLeft'] is int) ? c['daysLeft'] as int : 0;
    final type = c['type']?.toString() ?? 'birthday';
    final yearsOfService = (c['yearsOfService'] is int)
        ? c['yearsOfService'] as int
        : 1;
    final typeLabel = type == 'anniversary'
        ? 'Work Anniversary · ${_anniversaryYearsLabel(yearsOfService)}'
        : 'Birthday';
    final datePart = displayDate.isNotEmpty ? ' · $displayDate' : '';
    final subtitle = isToday
        ? '$typeLabel · Today$datePart'
        : '$typeLabel · ${daysLeft == 1 ? '1 day left' : '$daysLeft days left'}$datePart';
    final accentColor = AppColors.primary;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: null,
        boxShadow: [
          BoxShadow(
            color: accentColor.withOpacity(0.12),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    color: accentColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF475569),
                  ),
                ),
              ],
            ),
          ),
          if (displayDate.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Text(
                displayDate,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  color: accentColor.withOpacity(0.9),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _buildQuickActionButtons() {
    final buttons = <Widget>[];
    final onNavigate = widget.onNavigate;

    final accent = AppColors.primary;
    if (!_isCandidate && onNavigate != null) {
      buttons.add(
        _buildQuickActionButton(
          icon: Icons.fingerprint,
          label: 'Attendance',
          color: accent,
          onTap: () => onNavigate(4, subTabIndex: 0),
        ),
      );
      buttons.add(
        _buildQuickActionButton(
          icon: Icons.account_balance_wallet_outlined,
          label: 'Salary Overview',
          color: accent,
          onTap: () => onNavigate(2),
        ),
      );
    }

    if (onNavigate != null) {
      buttons.addAll([
        if (!_isCandidate)
          _buildQuickActionButton(
            icon: Icons.account_balance_wallet_outlined,
            label: 'Salary Structure',
            color: accent,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const StaffSalaryStructureScreen(),
                ),
              );
            },
          ),
        _buildQuickActionButton(
          icon: Icons.calendar_today,
          label: 'Apply Leave',
          color: accent,
          onTap: () => onNavigate(1, subTabIndex: 0),
        ),
        _buildQuickActionButton(
          icon: Icons.account_balance_wallet,
          label: 'Request Loan',
          color: accent,
          onTap: () => onNavigate(1, subTabIndex: 1),
        ),
        _buildQuickActionButton(
          icon: Icons.receipt,
          label: 'Expense Claim',
          color: accent,
          onTap: () => onNavigate(1, subTabIndex: 2),
        ),
        _buildQuickActionButton(
          icon: Icons.fact_check_outlined,
          label: 'Request Permission',
          color: accent,
          onTap: () => onNavigate(1, subTabIndex: 3),
        ),
        _buildQuickActionButton(
          icon: Icons.attach_money,
          label: 'Request Payslip',
          color: accent,
          onTap: () => onNavigate(1, subTabIndex: 4),
        ),
      ]);
    }

    return buttons;
  }

  /// Celebration-style card: rounded corners, soft shadow. Optional [icon] or [imageAsset] for left graphic.
  /// When [iconGradientColors] is set with [icon], the icon is drawn with a gradient (mixed colors).
  // ignore: unused_element
  Widget _buildCelebrationStyleSummaryCard({
    required String title,
    required String value,
    String? subValue,
    required Color accentColor,
    IconData? icon,
    List<Color>? iconGradientColors,
    String? imageAsset,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final isPrimaryCard = accentColor == AppColors.primary;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12,
            color: isPrimaryCard ? Colors.white.withOpacity(0.9) : accentColor,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: title == 'This Month Net' ? 16 : 18,
            fontWeight: FontWeight.bold,
            color: isPrimaryCard ? Colors.white : colorScheme.onSurface,
          ),
        ),
        if (subValue != null && subValue.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            subValue,
            style: TextStyle(
              fontSize: 10,
              color: isPrimaryCard
                  ? Colors.white.withOpacity(0.85)
                  : colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isPrimaryCard ? AppColors.primary : colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isPrimaryCard
              ? AppColors.primary.withOpacity(0.5)
              : colorScheme.outline.withOpacity(0.4),
        ),
        boxShadow: [
          BoxShadow(
            color: accentColor.withOpacity(isPrimaryCard ? 0.25 : 0.08),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
          BoxShadow(
            color: colorScheme.shadow.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: (icon != null || imageAsset != null)
          ? Row(
              children: [
                if (icon != null)
                  iconGradientColors != null && iconGradientColors.length >= 2
                      ? ShaderMask(
                          blendMode: BlendMode.srcIn,
                          shaderCallback: (bounds) => LinearGradient(
                            colors: iconGradientColors,
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ).createShader(bounds),
                          child: Icon(icon, size: 44, color: Colors.white),
                        )
                      : Icon(
                          icon,
                          size: 44,
                          color: isPrimaryCard ? Colors.white : accentColor,
                        )
                else
                  Image.asset(
                    imageAsset!,
                    width: 44,
                    height: 44,
                    fit: BoxFit.contain,
                  ),
                const SizedBox(width: 12),
                Expanded(child: content),
              ],
            )
          : content,
    );
  }

  // ignore: unused_element - kept for when summary cards layout is reverted
  Widget _buildSummaryCard({
    required String title,
    required String value,
    String? subValue,
    required bool isWide,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.black,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              // Slightly smaller text for This Month Net to fit full amount
              fontSize: title == 'This Month Net' ? 16 : 18,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF1E293B),
            ),
          ),
          if (subValue != null) ...[
            const SizedBox(height: 2),
            Text(
              subValue,
              style: const TextStyle(
                fontSize: 10,
                color: Colors.black,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ignore: unused_element - kept for when Active Loans card is shown again
  Widget _buildActiveLoansCard({
    required String activeLoansCount,
    required List<dynamic> activeLoans,
    required bool isWide,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Active Loans',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.black,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            activeLoansCount,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1E293B),
            ),
          ),
          if (activeLoans.isNotEmpty) ...[
            const SizedBox(height: 6),
            ...activeLoans.take(2).map((loan) {
              final amount = loan['amount']?.toString() ?? '0';
              final loanType = loan['loanType']?.toString() ?? 'Loan';
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        loanType,
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.black,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '₹$amount',
                      style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFF1E293B),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              );
            }),
            if (activeLoans.length > 2)
              Text(
                '+${activeLoans.length - 2} more',
                style: const TextStyle(
                  fontSize: 9,
                  color: Colors.black,
                  fontWeight: FontWeight.w500,
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildQuickActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: 78,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  shape: BoxShape.circle,
                  border: Border.all(color: color.withOpacity(0.3), width: 1),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF475569),
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// White card with donut progress — pending leave requests count.
  Widget _buildPendingLeavesSummaryCard(String value) {
    final count = int.tryParse(value) ?? 0;
    final progress = count > 0 ? (count / 10.0).clamp(0.0, 1.0) : 0.0;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 48,
            height: 48,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: progress > 0 ? progress : 0.75,
                  strokeWidth: 4,
                  backgroundColor: AppColors.primary.withOpacity(0.2),
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Leave Requests',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E293B),
                  ),
                ),
                Text(
                  'Pending',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// White card — This Month Net (MTD) + contract monthly net subtitle.
  Widget _buildThisMonthNetSummaryCard(
    String mtdAmount,
    String? monthlyAmount,
    String presentDaysSubtitle,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.trending_up, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'This Month Net',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade700,
                  ),
                ),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    mtdAmount,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                ),
                if (monthlyAmount != null && monthlyAmount.isNotEmpty)
                  Text(
                    'Total monthly salary $monthlyAmount',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                if (presentDaysSubtitle.isNotEmpty)
                  Text(
                    presentDaysSubtitle,
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentLeavesCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primary, AppColors.primaryDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Recent Leaves',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          if (_isLoadingDashboard)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: AppTabLoader(),
              ),
            )
          else if (_recentLeaves.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 20.0),
                child: Text(
                  'No recent leave requests',
                  style: TextStyle(color: Colors.white.withOpacity(0.9)),
                ),
              ),
            )
          else ...[
            ..._recentLeaves
                .take(3)
                .map((leave) => _buildRecentLeaveItem(leave)),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton(
                onPressed: () {
                  final fn = widget.onNavigate;
                  if (fn != null) fn(1, subTabIndex: 0);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  elevation: 0,
                ),
                child: const Text(
                  'View All',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRecentLeaveItem(dynamic leave) {
    final leaveType = leave['leaveType']?.toString() ?? 'Leave';
    final status = leave['status']?.toString() ?? 'N/A';
    String dateStr = '';
    try {
      final start = DateTime.parse(leave['startDate'].toString());
      dateStr = DateFormat('dd-MM-yy').format(start);
    } catch (_) {}

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.check_circle, color: Colors.white, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$leaveType - $status${dateStr.isNotEmpty ? ' - $dateStr' : ''}',
              style: TextStyle(
                fontSize: 13,
                color: Colors.white.withOpacity(0.95),
                fontWeight: FontWeight.w500,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  /// Calendar date (yyyy-MM-dd) from attendance collection. UTC/ISO date only (no local timezone shift).
  /// Handles: ISO string, date-only string, or DateTime (UTC components).
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

  String _attendanceDateKey(dynamic record) {
    if (record is! Map) return '';
    return _attendanceCalendarDate(record['date']);
  }

  /// One record per date from attendance collection: prefer record with punchIn, then latest updatedAt.
  List<dynamic> _deduplicateAttendanceByDate(List<dynamic> attendance) {
    if (attendance.isEmpty) return [];
    final byDate = <String, Map<String, dynamic>>{};
    for (final r in attendance) {
      if (r is! Map) continue;
      final key = _attendanceDateKey(r);
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
          try {
            final rTime = DateTime.parse(
              rUpdated.toString(),
            ).millisecondsSinceEpoch;
            final eTime = DateTime.parse(
              eUpdated.toString(),
            ).millisecondsSinceEpoch;
            if (rTime > eTime) byDate[key] = Map<String, dynamic>.from(r);
          } catch (_) {}
        }
      }
    }
    return byDate.values.toList();
  }

  Widget _buildMonthAttendanceCard({
    bool showHeaderIcon = true,
    bool dashboardCompact = false,
  }) {
    final monthName = DateFormat('MMMM yyyy').format(_selectedMonth);

    // Dashboard: work hours card first, then Today card (siblings, no outer shell).
    if (dashboardCompact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_todayAttendance != null &&
              _todayAttendance!['punchIn'] != null &&
              _todayAttendance!['punchIn'].toString().trim().isNotEmpty) ...[
            Builder(
              builder: (context) {
                DateTime punchInTime = DateTime.now();
                try {
                  punchInTime = DateTime.parse(
                    _todayAttendance!['punchIn'].toString(),
                  ).toLocal();
                } catch (_) {}
                DateTime? punchOutTime;
                final po = _todayAttendance!['punchOut'];
                if (po != null && po.toString().trim().isNotEmpty) {
                  try {
                    punchOutTime = DateTime.parse(po.toString()).toLocal();
                  } catch (_) {}
                }
                final whRaw = _todayAttendance!['workHours'];
                final whNum = whRaw is num
                    ? whRaw
                    : num.tryParse(whRaw?.toString() ?? '');
                return CloudPunchCard(
                  key: ValueKey(
                    'worked_${punchInTime.millisecondsSinceEpoch}_'
                    '${punchOutTime?.millisecondsSinceEpoch ?? 0}_'
                    '${whNum ?? ''}',
                  ),
                  punchInTime: punchInTime,
                  punchOutTime: punchOutTime,
                  workHoursFromAttendance: whNum,
                );
              },
            ),
            const SizedBox(height: 16),
          ],
          _buildTodayAttendanceSubCard(
            showCalendarIconInHeader: showHeaderIcon,
            standaloneDashboardCard: true,
          ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        // color: const Color(0xFF2D2D2D),
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (showHeaderIcon) ...[
                InkWell(
                  onTap: _openDashboardCalendarDetailsScreen,
                  borderRadius: BorderRadius.circular(18),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.calendar_month,
                      size: 22,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  'Attendance ($monthName)',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _buildSimpleCalendar(),
          const SizedBox(height: 24),
          _buildStatusLegend(),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                final fn = widget.onNavigate;
                if (fn != null) fn(4, subTabIndex: 1);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: const Color(0xFF1E293B),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: const Text(
                'View Full Attendance',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTodayAttendanceSubCard({
    bool showCalendarIconInHeader = false,
    bool standaloneDashboardCard = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final todayLabel = "Today (${DateFormat('dd MMM').format(now)})";

    String formatTime(String? isoString) {
      if (isoString == null) return '--:--';
      try {
        final date = DateTime.parse(isoString).toLocal();
        return DateFormat('hh:mm:ss a').format(date);
      } catch (e) {
        return '--:--';
      }
    }

    final punchIn = _todayAttendance?['punchIn'];
    final punchOut = _todayAttendance?['punchOut'];
    final address = _todayAttendance != null
        ? (_todayAttendance?['address'] ?? 'Recorded')
        : 'None';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: standaloneDashboardCard
          ? BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colorScheme.outline.withOpacity(0.35)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            )
          : BoxDecoration(
              color: colorScheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colorScheme.outline),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (showCalendarIconInHeader) ...[
                InkWell(
                  onTap: _openDashboardCalendarDetailsScreen,
                  borderRadius: BorderRadius.circular(18),
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Icon(
                      Icons.calendar_month,
                      size: 22,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ],
              Expanded(
                child: Text(
                  todayLabel,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF475569),
                    fontSize: 14,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _todayAttendance != null
                        ? (_todayAttendance?['status'] == 'Pending'
                              ? Colors.orange.withOpacity(0.1)
                              : (_todayAttendance?['status'] == 'Rejected' ||
                                        _todayAttendance?['status'] == 'Absent'
                                    ? Colors.red.withOpacity(0.1)
                                    : _todayAttendance?['status'] == 'On Leave'
                                    ? Colors.blue.withOpacity(0.1)
                                    : Colors.green.withOpacity(0.1)))
                        : Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _todayAttendance != null
                        ? (_todayAttendance?['status'] == 'Pending' &&
                                  _todayAttendance?['punchIn'] != null
                              ? 'Waiting for Approval'
                              : AttendanceDisplayUtil.formatAttendanceDisplayStatus(
                                  _todayAttendance?['status'] ?? 'Present',
                                  _todayAttendance?['leaveType'],
                                ))
                        : 'Absent',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: _todayAttendance != null
                          ? (_todayAttendance?['status'] == 'Pending'
                                ? Colors.orange
                                : (_todayAttendance?['status'] == 'Rejected' ||
                                          _todayAttendance?['status'] ==
                                              'Absent'
                                      ? Colors.red
                                      : _todayAttendance?['status'] ==
                                            'On Leave'
                                      ? Colors.blue
                                      : Colors.green))
                          : Colors.red,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Punch In',
                style: TextStyle(color: colorScheme.onSurface, fontSize: 13),
              ),
              Flexible(
                child: Text(
                  formatTime(punchIn),
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1E293B),
                    fontSize: 13,
                  ),
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Punch Out',
                style: TextStyle(color: colorScheme.onSurface, fontSize: 13),
              ),
              Flexible(
                child: Text(
                  formatTime(punchOut),
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                    fontSize: 13,
                  ),
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                ),
              ),
            ],
          ),
          if (_todayAttendance != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(
                  Icons.location_on,
                  size: 14,
                  color: Color(0xFF94A3B8),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    address,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: Colors.black),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Normalizes workHours to minutes (API stores in minutes; legacy may be hours 0–24).
  int? _workHoursToMinutes(num? workHours) {
    if (workHours == null) return null;
    final d = workHours.toDouble();
    if (d <= 0) return 0;
    if (d < 24 && (d - d.truncate()).abs() > 0.001) {
      return (d * 60).round();
    }
    return d.round();
  }

  /// Full embedded shifts from month payload (preferred) or profile company for [appliedShiftId] lookup.
  Map<String, dynamic>? _dashboardCompanyDocForAppliedShiftLookup() {
    final md = _monthData;
    if (md != null) {
      final bs = md['businessShifts'];
      if (bs is List && bs.isNotEmpty) {
        return {
          'settings': {
            'attendance': {'shifts': List<dynamic>.from(bs)},
          },
        };
      }
    }
    return _profileCompanyDoc;
  }

  ({
    String shiftName,
    bool isOpen,
    String? startTime,
    String? endTime,
    double? openWorkHours,
  })?
  _dashboardAppliedShiftResult(Map<String, dynamic>? record) {
    if (record == null || record['appliedShiftId'] == null) return null;
    return appliedShiftPastResolvedFromCompany(
      companyDoc: _dashboardCompanyDocForAppliedShiftLookup(),
      appliedShiftId: record['appliedShiftId'],
    );
  }

  String _appliedShiftCompactLineFromResult(
    ({
      String shiftName,
      bool isOpen,
      String? startTime,
      String? endTime,
      double? openWorkHours,
    })
    r,
  ) {
    if (r.isOpen) {
      final h = r.openWorkHours;
      if (h == null || h <= 0) {
        return '${r.shiftName} · Open';
      }
      final label = h == h.roundToDouble()
          ? '${h.toInt()}h'
          : h.toStringAsFixed(1);
      return '${r.shiftName} · Open · $label required';
    }
    final a = r.startTime ?? '';
    final b = r.endTime ?? '';
    if (a.isEmpty || b.isEmpty) {
      return r.shiftName;
    }
    return '${r.shiftName} · $a-$b';
  }

  int? _calendarShiftWindowMinutes(String start, String end) {
    try {
      (int, int) parts(String s) {
        final seg = s.split(':');
        final h = int.parse(seg[0].trim());
        final m = seg.length > 1 ? int.parse(seg[1].trim()) : 0;
        return (h, m);
      }

      final sp = parts(start);
      final ep = parts(end);
      var sm = sp.$1 * 60 + sp.$2;
      var em = ep.$1 * 60 + ep.$2;
      var diff = em - sm;
      if (diff < 0) diff += 24 * 60;
      return diff;
    } catch (_) {
      return null;
    }
  }

  int? _appliedShiftRequiredMinutesFromResult(
    ({
      String shiftName,
      bool isOpen,
      String? startTime,
      String? endTime,
      double? openWorkHours,
    })
    r,
  ) {
    if (r.isOpen) {
      final h = r.openWorkHours;
      if (h == null || h <= 0) return 540;
      return (h * 60).round();
    }
    final a = r.startTime;
    final b = r.endTime;
    if (a == null || b == null || a.isEmpty || b.isEmpty) return null;
    return _calendarShiftWindowMinutes(a, b);
  }

  dynamic _todayAppliedShiftIdForHeader() {
    final n = DateTime.now();
    final dateStr = DateFormat(
      'yyyy-MM-dd',
    ).format(DateTime(n.year, n.month, n.day));
    final att = _monthData?['attendance'];
    if (att is List) {
      for (final e in _deduplicateAttendanceByDate(att)) {
        if (e is! Map) continue;
        if (_attendanceDateKey(e) == dateStr) {
          final id = e['appliedShiftId'];
          if (id != null) return id;
          break;
        }
      }
    }
    return _todayAttendance?['appliedShiftId'];
  }

  Widget _buildSimpleCalendar() {
    final colorScheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final firstDayOfMonth = DateTime(
      _selectedMonth.year,
      _selectedMonth.month,
      1,
    );
    final lastDayOfMonth = DateTime(
      _selectedMonth.year,
      _selectedMonth.month + 1,
      0,
    );
    final prevMonthLastDay = DateTime(
      _selectedMonth.year,
      _selectedMonth.month,
      0,
    );
    final int firstDayWeekday = firstDayOfMonth.weekday % 7;

    List<DateTime> days = [];
    for (int i = firstDayWeekday - 1; i >= 0; i--) {
      days.add(
        DateTime(
          prevMonthLastDay.year,
          prevMonthLastDay.month,
          prevMonthLastDay.day - i,
        ),
      );
    }
    for (int i = 1; i <= lastDayOfMonth.day; i++) {
      days.add(DateTime(_selectedMonth.year, _selectedMonth.month, i));
    }
    while (days.length % 7 != 0) {
      days.add(
        DateTime(
          lastDayOfMonth.year,
          lastDayOfMonth.month + 1,
          days.length - (lastDayOfMonth.day + firstDayWeekday) + 1,
        ),
      );
    }

    // Use date strings (yyyy-MM-dd) as keys; one record per date from attendance collection (deduplicate)
    Map<String, String> dayStatusByDate = {};
    Map<String, String?> dayLeaveTypeByDate = {};
    Map<String, bool> dayIsPaidLeaveByDate = {};
    Map<String, String> dayCompensationTypeByDate = {};
    Map<String, num?> dayWorkHoursByDate = {};
    Set<String> pendingWithCheckInDateSet = {};
    final rawAttendance = _monthData != null
        ? (_monthData!['attendance'] as List?) ?? []
        : [];
    final attendanceDeduped = _deduplicateAttendanceByDate(rawAttendance);
    if (attendanceDeduped.isNotEmpty) {
      for (var entry in attendanceDeduped) {
        try {
          // Use attendance collection calendar date (UTC/ISO date only, no timezone shift)
          final dateStr = _attendanceCalendarDate(entry['date']);
          if (dateStr.isEmpty) continue;
          final parts = dateStr.split('-');
          if (parts.length != 3) continue;
          final dayYear = int.tryParse(parts[0]) ?? 0;
          final dayMonth = int.tryParse(parts[1]) ?? 0;
          if (dayYear != _selectedMonth.year ||
              dayMonth != _selectedMonth.month) {
            continue;
          }
          final statusVal = entry['status'] ?? 'Present';
          dayStatusByDate[dateStr] = statusVal;
          if (statusVal == 'Pending') {
            final punchIn = entry['punchIn'];
            if (punchIn != null && punchIn.toString().trim().isNotEmpty) {
              pendingWithCheckInDateSet.add(dateStr);
            }
          }
          final leaveType = entry['leaveType'] as String?;
          if (leaveType != null && leaveType.isNotEmpty) {
            dayLeaveTypeByDate[dateStr] = leaveType;
          }
          if (entry['isPaidLeave'] == true) {
            dayIsPaidLeaveByDate[dateStr] = true;
          }
          final compType = entry['compensationType'] as String?;
          if (compType != null && compType.toString().trim().isNotEmpty) {
            dayCompensationTypeByDate[dateStr] = compType
                .toString()
                .trim()
                .toLowerCase();
          }
          num? workHours = entry['workHours'] as num?;

          // Calculate workHours (in minutes) from punchIn and punchOut if not available
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
                  workHours = duration.inMinutes; // store in minutes
                }
              } catch (_) {
                // If parsing fails, leave workHours as null
              }
            }
          }

          dayWorkHoursByDate[dateStr] = workHours;
        } catch (e) {
          // Skip invalid date entries
          continue;
        }
      }
    }

    // Create a set of holiday date strings for quick lookup
    Set<String> holidayDateSet = {};
    if (_monthData != null && _monthData!['holidays'] != null) {
      for (var h in _monthData!['holidays']) {
        try {
          final d = DateTime.parse(h['date']).toLocal();
          final dateStr = DateFormat('yyyy-MM-dd').format(d);
          // Check both year and month to ensure correct matching
          if (d.year == _selectedMonth.year &&
              d.month == _selectedMonth.month) {
            holidayDateSet.add(dateStr);
          }
        } catch (e) {
          // Skip invalid date entries
          continue;
        }
      }
    }

    // Create a set of week off dates from backend (source of truth - already calculated based on attendance template)
    Set<String> weekOffDateSet = {};
    if (_monthData != null && _monthData!['weekOffDates'] != null) {
      final weekOffDates = _monthData!['weekOffDates'] as List;
      for (var dateStr in weekOffDates) {
        if (dateStr is String) {
          weekOffDateSet.add(dateStr);
        }
      }
    }

    // Dates in this month that are alternate work dates (employee can check-in; do not show as week-off/violet)
    Set<String> alternateWorkDatesInMonthSet = {};
    if (_monthData != null &&
        _monthData!['alternateWorkDatesInMonth'] != null) {
      final altDates = _monthData!['alternateWorkDatesInMonth'] as List;
      for (var dateStr in altDates) {
        if (dateStr is String) {
          alternateWorkDatesInMonthSet.add(dateStr);
        }
      }
    }

    // Create a set of present dates from backend
    Set<String> presentDateSet = {};
    if (_monthData != null && _monthData!['presentDates'] != null) {
      final presentDates = _monthData!['presentDates'] as List;
      for (var dateStr in presentDates) {
        if (dateStr is String) {
          presentDateSet.add(dateStr);
        }
      }
    }

    // Create a set of absent dates (working days without attendance records)
    Set<String> absentDateSet = {};
    if (_monthData != null && _monthData!['absentDates'] != null) {
      final absentDates = _monthData!['absentDates'] as List;
      for (var dateStr in absentDates) {
        if (dateStr is String) {
          absentDateSet.add(dateStr);
        }
      }
    }

    // Create a set of approved leave dates (for showing "L" on calendar)
    Set<String> leaveDateSet = {};
    if (_monthData != null && _monthData!['leaveDates'] != null) {
      for (var dateStr in _monthData!['leaveDates']) {
        if (dateStr is String) {
          leaveDateSet.add(dateStr);
        }
      }
    }

    const calCrossSpacing = 0.0;
    const calColCount = 7;
    const calAspect = 0.48;
    final screenW = MediaQuery.sizeOf(context).width;
    // Wider than typical phone columns so status chips and shift text fit; scroll when needed.
    final calGridWidth = math.max(screenW, 560.0);
    final cellWidth =
        (calGridWidth - (calColCount - 1) * calCrossSpacing) / calColCount;
    final rowCount = days.length ~/ 7;
    final cellHeight = cellWidth / calAspect;
    final gridHeight = rowCount * cellHeight + (rowCount - 1) * calCrossSpacing;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildDashboardAssignedShiftHeader(),
        Card(
          clipBehavior: Clip.antiAlias,
          margin: EdgeInsets.zero,
          color: colorScheme.surfaceContainerLowest,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: colorScheme.outline.withOpacity(0.35)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 10, 8, 12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: calGridWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.chevron_left),
                          onPressed: () {
                            setState(() {
                              _selectedMonth = DateTime(
                                _selectedMonth.year,
                                _selectedMonth.month - 1,
                              );
                            });
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              _fetchMonthAttendance(forceRefresh: true);
                            });
                          },
                        ),
                        Text(
                          DateFormat('MMMM yyyy').format(_selectedMonth),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.chevron_right),
                          onPressed: () {
                            setState(() {
                              _selectedMonth = DateTime(
                                _selectedMonth.year,
                                _selectedMonth.month + 1,
                              );
                            });
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              _fetchMonthAttendance(forceRefresh: true);
                            });
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa']
                          .map(
                            (d) => SizedBox(
                              width: cellWidth,
                              child: Center(
                                child: Text(
                                  d,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.black,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: gridHeight,
                      child: GridView.builder(
                        key: ValueKey(
                          'calendar_${_selectedMonth.year}_${_selectedMonth.month}',
                        ),
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: calColCount,
                          mainAxisSpacing: calCrossSpacing,
                          crossAxisSpacing: calCrossSpacing,
                          childAspectRatio: calAspect,
                        ),
                        itemCount: days.length,
                        itemBuilder: (context, index) {
                          final dayDate = days[index];
                          final dateStr = DateFormat(
                            'yyyy-MM-dd',
                          ).format(dayDate);
                          final bool isCurrentMonth =
                              dayDate.month == _selectedMonth.month;
                          final bool isToday =
                              isCurrentMonth &&
                              dayDate.day == now.day &&
                              dayDate.month == now.month &&
                              dayDate.year == now.year;
                          Color bgColor = Colors.transparent;
                          Color textColor = isCurrentMonth
                              ? colorScheme.onSurface
                              : colorScheme.onSurfaceVariant;

                          // Initialize variables before use
                          num? workHours;
                          bool isLowHours = false;
                          bool isFuture = false;
                          EffectiveShiftDay? effShiftForCell;
                          String? webBadgeLabel;
                          Color? webBadgeBg;
                          Color? webBadgeFg;
                          bool calendarCellIsWeekOff = false;
                          ({
                            String shiftName,
                            bool isOpen,
                            String? startTime,
                            String? endTime,
                            double? openWorkHours,
                          })?
                          appliedShiftResolvedForCell;
                          String? appliedShiftCompactForCell;

                          if (isCurrentMonth) {
                            effShiftForCell = effectiveShiftForCalendarDay(
                              companyDoc: _profileCompanyDoc,
                              staffShiftKey: _profileStaffShiftName,
                              dayLocal: DateTime(
                                dayDate.year,
                                dayDate.month,
                                dayDate.day,
                              ),
                              joiningDate: _profileJoiningDate,
                              attendanceTodayTemplate:
                                  _templateOverrideForCalendarDay(
                                    DateTime(
                                      dayDate.year,
                                      dayDate.month,
                                      dayDate.day,
                                    ),
                                  ),
                            );
                            final bool isHoliday = holidayDateSet.contains(
                              dateStr,
                            );

                            final dayOfWeek =
                                dayDate.weekday %
                                7; // 0=Sunday, 1=Monday, ..., 6=Saturday

                            // Use backend calculated week off dates, but add validation:
                            // 1. Sundays (day 0) should ALWAYS be week off
                            // 2. Fridays (day 5) should NEVER be week off unless explicitly in backend data
                            // 3. Do NOT show violet for alternate work dates (compensation week-off days when employee can check-in)
                            bool isWeekOff = weekOffDateSet.contains(dateStr);
                            if (isWeekOff &&
                                alternateWorkDatesInMonthSet.contains(
                                  dateStr,
                                )) {
                              isWeekOff =
                                  false; // Alternate work date: can check-in, don't highlight as week off
                            }
                            // Validation: Sundays are always week off (unless it's an alternate work date)
                            if (dayOfWeek == 0 &&
                                !alternateWorkDatesInMonthSet.contains(
                                  dateStr,
                                )) {
                              isWeekOff = true;
                            }
                            // Rotational byWeekCalendar can explicitly mark a date as week off.
                            if (effShiftForCell?.isWeekOff == true) {
                              isWeekOff = true;
                            }

                            // Check if present from backend presentDates array
                            final bool isPresentFromBackend = presentDateSet
                                .contains(dateStr);

                            // Set secondary text color for Sundays/week offs
                            if (isWeekOff) {
                              textColor = colorScheme.onSurfaceVariant;
                            }

                            // Priority: Present with LeaveType (Green) > Half Day (On Leave Blue) > Holiday > Week Off > Leave without attendance (On Leave Blue) > Present > Absent > Not Marked
                            // IMPORTANT: Week offs (especially Sundays) should NEVER be marked as absent
                            final status = dayStatusByDate[dateStr];
                            final hasLeaveType = dayLeaveTypeByDate.containsKey(
                              dateStr,
                            );
                            // Never treat as present when record is Pending/Absent/Rejected (trust attendance list over presentDates)
                            final isAbsentStatus =
                                (status ?? '').toString().toLowerCase() ==
                                'absent';
                            final isPresentStatus =
                                (status == 'Present' ||
                                    status == 'Approved' ||
                                    isPresentFromBackend) &&
                                status != 'Pending' &&
                                !isAbsentStatus &&
                                status != 'Rejected';
                            final isHalfDayStatus =
                                status == 'Half Day' ||
                                (status?.toLowerCase() == 'half day');

                            // 1. Present with leaveType → Green background with CL/SL/HA
                            if (isPresentStatus && hasLeaveType) {
                              bgColor = const Color(
                                0xFFDCFCE7,
                              ); // Present - Light Green
                            }
                            // 2. Half Day status → On Leave blue background with "HA"
                            else if (isHalfDayStatus) {
                              bgColor = const Color(
                                0xFFBFDBFE,
                              ); // Half Day - On Leave blue
                            }
                            // 3. Holiday
                            else if (isHoliday) {
                              bgColor = const Color(
                                0xFFFEF3C7,
                              ); // Holiday - Light yellow
                            }
                            // 3.5. Alternate Working Day (compensation week-off day when employee can check-in)
                            else if (alternateWorkDatesInMonthSet.contains(
                              dateStr,
                            )) {
                              bgColor = const Color(
                                0xFFE8D5C4,
                              ); // Working Day - Light brown
                            }
                            // 4. Week Off
                            else if (isWeekOff) {
                              bgColor = const Color(
                                0xFFE9D5FF,
                              ); // Week Off - Light purple
                            }
                            // 5. Leave date but no attendance → Blue with "L"
                            else if (leaveDateSet.contains(dateStr)) {
                              bgColor = const Color(
                                0xFFBFDBFE,
                              ); // On Leave - light blue
                            }
                            // 6. Present without leaveType → Green
                            else if (isPresentStatus) {
                              bgColor = const Color(
                                0xFFDCFCE7,
                              ); // Present - Light Green
                            }
                            // 7. Other attendance statuses (Pending treated as Absent). Show red when status is Absent in attendances collection.
                            else if (dayStatusByDate.containsKey(dateStr)) {
                              if (status == 'Pending' ||
                                  isAbsentStatus ||
                                  status == 'Rejected') {
                                bgColor = const Color(
                                  0xFFFEE2E2,
                                ); // Absent - Light red
                              } else if (status == 'On Leave') {
                                bgColor = const Color(
                                  0xFFBFDBFE,
                                ); // On Leave - light blue
                              }
                            }
                            // 8. Absent from backend (never show today as absent - day may be in progress or data stale)
                            else if (absentDateSet.contains(dateStr)) {
                              if (!isWeekOff && !isToday) {
                                bgColor = const Color(
                                  0xFFFEE2E2,
                                ); // Absent - Light red
                              } else if (isToday) {
                                // Today: show as not marked so user isn't shown absent incorrectly
                                bgColor = const Color(
                                  0xFFE2E8F0,
                                ); // Not Marked - Light grey
                              }
                            }
                            // 9. Future dates
                            else {
                              final todayOnly = DateTime(
                                now.year,
                                now.month,
                                now.day,
                              );
                              final dateOnly = DateTime(
                                dayDate.year,
                                dayDate.month,
                                dayDate.day,
                              );
                              if (dateOnly.isAfter(todayOnly)) {
                                bgColor = const Color(
                                  0xFFE2E8F0,
                                ); // Not Marked - Light grey
                              }
                            }

                            // For today: prefer live _todayAttendance so we show Present if user has punched in
                            if (isToday && _todayAttendance != null) {
                              final st =
                                  _todayAttendance!['status']
                                      ?.toString()
                                      .toLowerCase() ??
                                  '';
                              if (st == 'present' || st == 'approved') {
                                bgColor = const Color(
                                  0xFFDCFCE7,
                                ); // Present - Light Green
                              }
                            }

                            Map<String, dynamic>? dayEntry;
                            for (final e in attendanceDeduped) {
                              if (e is! Map) continue;
                              if (_attendanceDateKey(e) == dateStr) {
                                dayEntry = Map<String, dynamic>.from(e);
                                break;
                              }
                            }
                            Map<String, dynamic>? entryForApplied = dayEntry;
                            if (isToday && _todayAttendance != null) {
                              final live = Map<String, dynamic>.from(
                                _todayAttendance!,
                              );
                              final id =
                                  live['appliedShiftId'] ??
                                  dayEntry?['appliedShiftId'];
                              if (id != null) {
                                entryForApplied = {
                                  ...?dayEntry,
                                  ...live,
                                  'appliedShiftId': id,
                                };
                              }
                            } else if (isToday &&
                                dayEntry == null &&
                                _todayAttendance?['appliedShiftId'] != null) {
                              entryForApplied = Map<String, dynamic>.from(
                                _todayAttendance!,
                              );
                            }

                            final cellWall = DateTime(
                              dayDate.year,
                              dayDate.month,
                              dayDate.day,
                            );
                            final todayWall = DateTime(
                              now.year,
                              now.month,
                              now.day,
                            );
                            if (!cellWall.isAfter(todayWall)) {
                              final resolvedApplied =
                                  _dashboardAppliedShiftResult(entryForApplied);
                              appliedShiftResolvedForCell = resolvedApplied;
                              if (resolvedApplied != null) {
                                appliedShiftCompactForCell =
                                    _appliedShiftCompactLineFromResult(
                                      resolvedApplied,
                                    );
                              }
                            }

                            // Status flags for chips, low-hours, leave interactions
                            final statusForDay = dayStatusByDate[dateStr] ?? '';
                            final statusLower = statusForDay
                                .toString()
                                .toLowerCase();
                            final isAbsentStatusForAbbr =
                                statusLower == 'absent';
                            final isPresentStatusForAbbr =
                                (statusForDay == 'Present' ||
                                    statusForDay == 'Approved' ||
                                    isPresentFromBackend) &&
                                statusForDay != 'Pending' &&
                                !isAbsentStatusForAbbr &&
                                statusForDay != 'Rejected';
                            final isHalfDayStatusForAbbr =
                                statusForDay == 'Half Day' ||
                                statusLower == 'half day';
                            final isOnLeaveStatus = statusLower == 'on leave';
                            final compType =
                                dayCompensationTypeByDate[dateStr] ?? '';

                            // Low work-hours indicator
                            workHours = dayWorkHoursByDate[dateStr];

                            // Calculate workHours from punchIn and punchOut if not available
                            if ((workHours == null || workHours == 0) &&
                                _monthData != null &&
                                _monthData!['attendance'] != null) {
                              try {
                                final entry =
                                    (_monthData!['attendance'] as List)
                                        .firstWhere((e) {
                                          try {
                                            final d = DateTime.parse(
                                              e['date'],
                                            ).toLocal();
                                            final eDateStr = DateFormat(
                                              'yyyy-MM-dd',
                                            ).format(d);
                                            return eDateStr == dateStr;
                                          } catch (_) {
                                            return false;
                                          }
                                        }, orElse: () => null);

                                if (entry != null) {
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
                                      final duration = punchOutTime.difference(
                                        punchInTime,
                                      );
                                      if (duration.inMinutes > 0) {
                                        workHours =
                                            duration.inMinutes /
                                            60.0; // Convert to hours
                                      }
                                    } catch (_) {
                                      // If parsing fails, leave workHours as null
                                    }
                                  }
                                }
                              } catch (_) {
                                // If lookup fails, leave workHours as is
                              }
                            }

                            // workHours from API/local are in minutes; threshold = resolved shift (or 9h default)
                            final workHoursMins = _workHoursToMinutes(
                              workHours,
                            );
                            var requiredWorkMins =
                                effShiftForCell?.requiredWorkMinutes() ?? 540;
                            final resolvedForReq = appliedShiftResolvedForCell;
                            final appliedReq = resolvedForReq != null
                                ? _appliedShiftRequiredMinutesFromResult(
                                    resolvedForReq,
                                  )
                                : null;
                            if (appliedReq != null) {
                              requiredWorkMins = appliedReq;
                            }
                            isLowHours =
                                workHoursMins != null &&
                                workHoursMins < requiredWorkMins;
                            // Don't show low work hours red dot for comp off, leave, week off, or absent
                            if (isWeekOff ||
                                compType == 'compoff' ||
                                compType == 'comp off' ||
                                isOnLeaveStatus ||
                                isAbsentStatusForAbbr ||
                                (leaveDateSet.contains(dateStr) &&
                                    !isPresentStatusForAbbr)) {
                              isLowHours = false;
                            }
                            isFuture = DateTime(
                              dayDate.year,
                              dayDate.month,
                              dayDate.day,
                            ).isAfter(DateTime(now.year, now.month, now.day));

                            // Web-style top-right status chip (single label per day)
                            final bool pureWeekOff =
                                isWeekOff &&
                                !alternateWorkDatesInMonthSet.contains(dateStr);
                            if (pureWeekOff) {
                              webBadgeLabel = 'WF';
                              webBadgeBg = const Color(0xFFE5E7EB);
                              webBadgeFg = const Color(0xFF374151);
                            } else if (alternateWorkDatesInMonthSet.contains(
                              dateStr,
                            )) {
                              webBadgeLabel = 'WA';
                              webBadgeBg = const Color(0xFFE8D5C4);
                              webBadgeFg = const Color(0xFF78350F);
                            } else if (isHoliday) {
                              webBadgeLabel = 'HA';
                              webBadgeBg = const Color(0xFFFEF3C7);
                              webBadgeFg = const Color(0xFF92400E);
                            } else if (isAbsentStatusForAbbr ||
                                statusForDay == 'Rejected') {
                              webBadgeLabel = 'Absent';
                              webBadgeBg = const Color(0xFFFEE2E2);
                              webBadgeFg = const Color(0xFFB91C1C);
                            } else if (isPresentStatusForAbbr) {
                              webBadgeLabel = 'Present';
                              webBadgeBg = const Color(0xFFDCFCE7);
                              webBadgeFg = const Color(0xFF166534);
                            } else if (status == 'Pending' ||
                                pendingWithCheckInDateSet.contains(dateStr)) {
                              webBadgeLabel = 'Pending';
                              webBadgeBg = const Color(0xFFE2E8F0);
                              webBadgeFg = const Color(0xFF475569);
                            } else if (isOnLeaveStatus ||
                                (leaveDateSet.contains(dateStr) &&
                                    !isPresentStatusForAbbr &&
                                    !isHalfDayStatusForAbbr)) {
                              webBadgeLabel = 'Leave';
                              webBadgeBg = const Color(0xFFEDE9FE);
                              webBadgeFg = const Color(0xFF5B21B6);
                            } else if (isHalfDayStatusForAbbr) {
                              webBadgeLabel = 'Leave';
                              webBadgeBg = const Color(0xFFFEF9C3);
                              webBadgeFg = const Color(0xFFA16207);
                            } else if (absentDateSet.contains(dateStr) &&
                                !isWeekOff &&
                                !isToday) {
                              webBadgeLabel = 'Absent';
                              webBadgeBg = const Color(0xFFFEE2E2);
                              webBadgeFg = const Color(0xFFB91C1C);
                            }

                            calendarCellIsWeekOff = isWeekOff;
                            // Calendar background status colors are intentionally disabled for now.
                            bgColor = Colors.transparent;
                          }

                          if (!isCurrentMonth) {
                            return Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.zero,
                                border: Border.all(
                                  color: colorScheme.outline.withOpacity(0.6),
                                  width: 1,
                                ),
                              ),
                              child: Align(
                                alignment: Alignment.topLeft,
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    4,
                                    4,
                                    2,
                                    2,
                                  ),
                                  child: Text(
                                    '${dayDate.day}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      height: 1.0,
                                      fontWeight: FontWeight.w500,
                                      color: textColor,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }

                          return Container(
                            clipBehavior: Clip.antiAlias,
                            decoration: BoxDecoration(
                              color: bgColor,
                              borderRadius: BorderRadius.zero,
                              border: Border.all(
                                color: isToday
                                    ? AppColors.primary
                                    : colorScheme.outline.withOpacity(0.6),
                                width: isToday ? 2 : 1,
                              ),
                            ),
                            child: Stack(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    3,
                                    4,
                                    3,
                                    4,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '${dayDate.day}',
                                            style: TextStyle(
                                              fontSize: 11,
                                              height: 1.0,
                                              fontWeight: isToday
                                                  ? FontWeight.bold
                                                  : FontWeight.w500,
                                              color: textColor,
                                            ),
                                          ),
                                          const Spacer(),
                                          if (webBadgeLabel != null &&
                                              webBadgeBg != null &&
                                              webBadgeFg != null)
                                            Flexible(
                                              child: Align(
                                                alignment:
                                                    Alignment.centerRight,
                                                child:
                                                    _dashboardCalendarStatusChip(
                                                      webBadgeLabel,
                                                      webBadgeBg,
                                                      webBadgeFg,
                                                    ),
                                              ),
                                            ),
                                        ],
                                      ),
                                      Expanded(
                                        child: Align(
                                          alignment: Alignment.center,
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 1,
                                            ),
                                            child: Column(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                if (!calendarCellIsWeekOff &&
                                                    (appliedShiftCompactForCell !=
                                                            null ||
                                                        effShiftForCell !=
                                                            null)) ...[
                                                  Text(
                                                    appliedShiftCompactForCell ??
                                                        effShiftForCell
                                                            ?.compactLine() ??
                                                        '',
                                                    maxLines: 2,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    textAlign: TextAlign.center,
                                                    style: const TextStyle(
                                                      fontSize: 8,
                                                      height: 1.1,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                      color: Color(0xFF6B7280),
                                                    ),
                                                  ),
                                                  if (appliedShiftCompactForCell ==
                                                          null &&
                                                      effShiftForCell
                                                              ?.rotationCalendarFooter() !=
                                                          null)
                                                    Padding(
                                                      padding:
                                                          const EdgeInsets.only(
                                                            top: 2,
                                                          ),
                                                      child: Text(
                                                        effShiftForCell!
                                                            .rotationCalendarFooter()!,
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        textAlign:
                                                            TextAlign.center,
                                                        style: const TextStyle(
                                                          fontSize: 7,
                                                          height: 1.05,
                                                          fontWeight:
                                                              FontWeight.w500,
                                                          color: Color(
                                                            0xFF6B7280,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                ],
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (isLowHours &&
                                    !isFuture &&
                                    bgColor != Colors.transparent)
                                  const Positioned(
                                    top: 2,
                                    left: 2,
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        color: Colors.red,
                                        shape: BoxShape.circle,
                                      ),
                                      child: SizedBox(width: 5, height: 5),
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatusLegend() {
    return Wrap(
      spacing: 16,
      runSpacing: 12,
      children: [
        _buildLegendItem(
          'WA',
          'Working Alternate Day',
          textColor: const Color(0xFF78350F),
        ),
        _buildLegendItem('WF', 'Week Off', textColor: const Color(0xFF374151)),
        _buildLegendItem('HA', 'Holiday', textColor: const Color(0xFF92400E)),
        _buildLegendItem(
          'LEAVE',
          'On Leave',
          textColor: const Color(0xFF5B21B6),
        ),
        _buildLegendItem(
          'PRESENT',
          'Present',
          textColor: const Color(0xFF166534),
        ),
        _buildLegendItem(
          'ABSENT',
          'Absent',
          textColor: const Color(0xFFB91C1C),
        ),
        _buildLegendItem(
          'PENDING',
          'Pending',
          textColor: const Color(0xFF475569),
        ),
      ],
    );
  }

  Widget _buildLegendItem(
    String shortCode,
    String fullForm, {
    Color? textColor,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final resolvedTextColor = textColor ?? colorScheme.onSurface;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            // Legend colors are intentionally disabled for now.
            // color: color,
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: colorScheme.outline.withOpacity(0.6)),
          ),
          child: Text(
            shortCode,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: resolvedTextColor,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          fullForm,
          style: TextStyle(fontSize: 11, color: resolvedTextColor),
        ),
      ],
    );
  }
}
