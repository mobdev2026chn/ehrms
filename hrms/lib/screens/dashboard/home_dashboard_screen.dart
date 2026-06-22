import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import '../../config/app_colors.dart';
import '../../config/app_text_styles.dart';
import '../../config/constants.dart';
import '../../widgets/animations.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/confetti_burst.dart';
import '../../widgets/cloud_punch_card.dart';
import '../../services/fcm_service.dart';
import '../announcements/announcements_screen.dart';
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
import '../../services/interaction_service.dart';
import '../../services/break_service.dart';
import '../../services/performance_service.dart';
import '../../models/break_summary.dart';
import '../salary/salary_structure_detail_screen.dart';
import '../salary/staff_salary_structure_screen.dart';
import '../salary/request_payslip_screen.dart';
import '../performance/my_performance_screen.dart';
import '../../utils/salary_structure_calculator.dart';
import '../../utils/salary_fine_summary.dart';
import '../../utils/attendance_display_util.dart';
import '../../utils/absent_alert_helper.dart';
import '../../utils/rotational_shift_util.dart';
import '../../utils/snackbar_utils.dart';
import '../../utils/error_message_utils.dart';
import '../../utils/attendance_selfie_compress.dart';
import '../../utils/avatar_orientation.dart';
import '../attendance/selfie_camera_screen.dart'
    show SelfieCameraScreen, useImagePickerFallback;
import '../attendance/shift_screen.dart';

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

  /// Staffs collection `salaryDetailsAccessEnabled` (profile [staffData]) — same strict `== true` as [SalaryOverviewScreen]; controls Salary Overview quick action only.
  final bool hasSalaryOverviewAccess;

  const HomeDashboardScreen({
    super.key,
    this.onNavigate,
    this.embeddedInDashboard = false,
    this.dashboardTabIndex,
    this.onNavigateToIndex,
    this.isActiveTab,
    this.refreshTrigger,
    this.onDashboardDataRefreshed,
    this.hasSalaryOverviewAccess = false,
  });

  @override
  State<HomeDashboardScreen> createState() => _HomeDashboardScreenState();
}

class _HomeDashboardScreenState extends State<HomeDashboardScreen> {
  final GlobalKey<ScaffoldState> _dashboardScaffoldKey =
      GlobalKey<ScaffoldState>();
  String _userName = 'User';
  String _companyName = '';
  String? _avatarUrl;
  // Whether the header avatar must be flipped 180° on display (some devices stored
  // the first-punch selfie upside-down). Seeded from a fast timestamp guess, then
  // corrected by detecting the image's actual orientation (see _resolveAvatarFlip).
  bool _avatarNeedsFlip = false;

  final RequestService _requestService = RequestService();
  final AttendanceService _attendanceService = AttendanceService();
  final AuthService _authService = AuthService();
  final SettingsService _settingsService = SettingsService();
  final SalaryService _salaryService = SalaryService();
  final BreakService _breakService = BreakService();
  final PerformanceService _performanceService = PerformanceService();

  /// Today's break summary (list + total) for the punch card.
  BreakSummary? _breakSummary;

  /// Today's approved custom-time ('both') permission, if any. Drives the
  /// Permission Out / Permission In control shown under the punch card.
  Map<String, dynamic>? _todayPermission;
  bool _isPermissionStamping = false;

  /// Overall performance rating from completed review cycles. Stays `null`
  /// until the summary loads; `<= 0` means performance has not been evaluated
  /// yet, so the Performance card shows a placeholder instead of a fake score.
  double? _performanceRating;

  List<dynamic> _recentLeaves = [];

  // ignore: unused_field - kept for when Active Loans card is shown again
  List<dynamic> _activeLoans = [];
  bool _isLoadingDashboard = false;
  bool _isFetchingMonthAttendance = false;

  /// Single-flight guard for [_loadData] so overlapping triggers (initState +
  /// tab focus + refreshTrigger) can't fire concurrent network bursts.
  bool _isLoadDataInFlight = false;

  /// When the last [_loadData] finished, used to throttle the reload that fires
  /// every time the Home tab regains focus (see [didUpdateWidget]).
  DateTime? _lastDashboardLoadAt;
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
  bool _isAdminLike = false;
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
    // When the user returns to the Dashboard tab, refresh — but throttle so a
    // quick tab in-and-out doesn't trigger a full reload (and flicker) each
    // time. A stale-data window keeps the screen reasonably fresh without
    // re-hitting the network on every focus change.
    if (widget.isActiveTab == true && oldWidget.isActiveTab != true) {
      final last = _lastDashboardLoadAt;
      final isStale = last == null ||
          DateTime.now().difference(last) > const Duration(seconds: 30);
      if (isStale) {
        _loadData();
      }
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

  /// Dashboard announcement visibility: hide expired ones, any created before
  /// the employee joined, and any targeted to other staff. When the joining date
  /// isn't loaded yet, only the expiry/recipient rules apply (the Announcements
  /// screen does the authoritative pass).
  bool _isDashboardAnnouncementVisible(dynamic item) {
    if (!_isDashboardAnnouncementNotExpired(item)) return false;
    if (!_isDashboardAnnouncementForMe(item)) return false;
    final joining = _profileJoiningDate;
    if (joining == null || item is! Map) return true;
    final raw = item['createdAt'] ?? item['publishDate'] ?? item['effectiveDate'];
    final created = DateTime.tryParse(raw?.toString() ?? '')?.toLocal();
    if (created == null) return true;
    final joinDay = DateTime(joining.year, joining.month, joining.day);
    return !created.isBefore(joinDay);
  }

  /// Whether an announcement targets the current employee. Company-wide
  /// announcements (no recipient list) are visible to all; a personally-targeted
  /// announcement (`targetStaffIds`/`assignedTo`/`recipients`) is shown only when
  /// the current staff id is in that list. Guards against the web/interaction
  /// backend returning a targeted announcement to the wrong staff member.
  bool _isDashboardAnnouncementForMe(dynamic item) {
    if (item is! Map) return true;
    String? idStr(dynamic v) {
      if (v == null) return null;
      if (v is String) return v.trim();
      if (v is Map) return idStr(v['_id'] ?? v['\$oid'] ?? v['id'] ?? v['staffId']);
      return v.toString().trim();
    }

    final targets = <String>{};
    for (final key in const [
      'targetStaffIds',
      'assignedTo',
      'recipients',
      'staffIds',
      'targetStaff',
      'employees',
      'staff',
      'specificStaff',
      'selectedStaff',
      'selectedEmployees',
      'audienceIds',
      'to',
    ]) {
      final v = item[key];
      if (v is List) {
        for (final e in v) {
          final id = idStr(e);
          if (id != null && id.isNotEmpty) targets.add(id);
        }
      }
    }
    if (targets.isNotEmpty) {
      final myStaffId = idStr(_profileStaffDataSnapshot?['_id']);
      if (myStaffId == null || myStaffId.isEmpty) return false;
      return targets.contains(myStaffId);
    }
    // No resolvable recipient list. Mirror the backend audienceFilter: an
    // announcement explicitly flagged "specific" must not fall back to
    // company-wide — fail closed (hide) rather than leak it to everyone.
    for (final key in const ['audienceType', 'audience', 'visibility', 'type']) {
      final v = item[key];
      if (v is String &&
          RegExp(r'^\s*specific\s*$', caseSensitive: false).hasMatch(v)) {
        return false;
      }
    }
    return true; // company-wide
  }

  /// Geo [getDashboardData] `todayAnnouncements` can be empty while web HRMS
  /// `/interaction/announcements` has items — same source as [AnnouncementsScreen].
  Future<List<dynamic>> _tryLoadAnnouncementsFromInteractionApi() async {
    try {
      final res = await InteractionService.instance.getAnnouncements();
      if (res['success'] != true) return [];
      final raw = res['data'] is List ? res['data'] : res['announcements'];
      if (raw is! List) return [];
      final out = <dynamic>[];
      for (final e in raw) {
        if (e is! Map) continue;
        final m = Map<String, dynamic>.from(e);
        if (!_isDashboardAnnouncementVisible(m)) continue;
        out.add(m);
      }
      if (kDebugMode) {
        debugPrint(
          '[DashboardLoad] interaction announcements fallback count=${out.length}',
        );
      }
      return out;
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          '[DashboardLoad] interaction announcements fallback error: $e',
        );
      }
      return [];
    }
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

  /// Loads today's break summary (list + total) for the punch card. Runs in
  /// parallel with the rest of the dashboard load so it never blocks first paint.
  Future<void> _fetchBreakSummary() async {
    try {
      final result = await _breakService.getTodayBreakSummary();
      if (!mounted) return;
      if (result['success'] == true && result['data'] is Map) {
        final summary = BreakSummary.fromJson(
          Map<String, dynamic>.from(result['data'] as Map),
        );
        if (kDebugMode) {
          debugPrint(
            '[BreakSummary] OK | count=${summary.totalBreakCount} '
            'totalMin=${summary.totalBreakMin} '
            'allowed=${summary.allowedMinutes} '
            'remaining=${summary.remainingMin} '
            'unlimited=${summary.isUnlimited} '
            'policyEnabled=${summary.policyEnabled}',
          );
        }
        setState(() => _breakSummary = summary);
      } else if (kDebugMode) {
        debugPrint(
          '[BreakSummary] FAILED | success=${result['success']} '
          'message=${result['message']} '
          '(is the backend restarted with GET /api/breaks/today?)',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[BreakSummary] ERROR | $e');
      }
      // Non-fatal: the card simply omits the break section.
    }
  }

  /// Loads today's custom-time ('both') permission so the punch card can offer
  /// Permission Out / Permission In. Accepts Pending (applied) or Approved so the
  /// employee can stamp as soon as they apply. Stores the first match in
  /// [_todayPermission]; clears it when none applies. Non-fatal on error.
  Future<void> _fetchTodayPermission() async {
    try {
      final result = await _requestService.getPermissionRequests();
      if (!mounted) return;
      final data = result['data'];
      final list = data is Map ? data['permissions'] : null;
      Map<String, dynamic>? found;
      if (list is List) {
        final now = DateTime.now();
        for (final raw in list) {
          if (raw is! Map) continue;
          final p = Map<String, dynamic>.from(raw);
          if (p['type']?.toString() != 'both') continue;
          final status = p['status']?.toString();
          if (status != 'Pending' && status != 'Approved') continue;
          final d = DateTime.tryParse(p['date']?.toString() ?? '')?.toLocal();
          if (d == null ||
              d.year != now.year ||
              d.month != now.month ||
              d.day != now.day) {
            continue;
          }
          found = p;
          break;
        }
      }
      setState(() => _todayPermission = found);
    } catch (e) {
      if (kDebugMode) debugPrint('[TodayPermission] ERROR | $e');
    }
  }

  /// Captures a required in-app selfie (single face) and returns it as a
  /// compressed base64 data URL, or null if cancelled / camera denied / no face.
  Future<String?> _capturePermissionSelfie() async {
    var status = await Permission.camera.status;
    if (!status.isGranted) {
      status = await Permission.camera.request();
      if (!mounted) return null;
      if (!status.isGranted) {
        SnackBarUtils.showSnackBar(
          context,
          'Camera permission is required for permission selfie.',
          isError: true,
        );
        return null;
      }
    }
    if (!mounted) return null;
    final captureResult =
        await SelfieCameraScreen.captureSelfie(context, title: 'Permission Selfie');
    File? file;
    if (captureResult is File) {
      file = captureResult;
    } else if (identical(captureResult, useImagePickerFallback)) {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
        imageQuality: 85,
        maxWidth: 1024,
      );
      if (picked != null) file = File(picked.path);
    }
    if (file == null || !mounted) return null;
    // No client-side ML Kit face gate — server FACE-MATCH (verifyFace) is the single check.
    final bytes = await file.readAsBytes();
    return AttendanceSelfieCompress.compressRawBytesToDataUrl(bytes);
  }

  /// Stamp Permission Out ([isOut] true) or Permission In on today's permission,
  /// then refresh. Requires a selfie. On Permission In with overrun, warn that a
  /// fine was applied for that day.
  Future<void> _handlePermissionStamp(bool isOut) async {
    final id = _todayPermission?['_id']?.toString();
    if (id == null || id.isEmpty || _isPermissionStamping) return;

    // Permission Out requires a completed Punch In for the day.
    if (isOut) {
      final punchInRaw = _todayAttendance?['punchIn']?.toString().trim();
      final hasPunchedIn =
          (punchInRaw != null && punchInRaw.isNotEmpty) ||
          _todayAttendance?['hasPunchIn'] == true;
      if (!hasPunchedIn) {
        SnackBarUtils.showSnackBar(
          context,
          'Please Punch In before recording Permission Out.',
          isError: true,
        );
        return;
      }
    }

    final selfie = await _capturePermissionSelfie();
    if (selfie == null || selfie.isEmpty || !mounted) return;

    // Validate the permission selfie against the rolling face reference before
    // stamping, mirroring the attendance punch and break flows.
    if (AppConstants.enableAttendanceFaceMatching) {
      setState(() => _isPermissionStamping = true);
      Map<String, dynamic> verify;
      try {
        verify = await _authService.verifyFace(selfie);
      } catch (_) {
        if (!mounted) return;
        setState(() => _isPermissionStamping = false);
        SnackBarUtils.showSnackBar(
          context,
          'Face verification failed. Please try again.',
          isError: true,
        );
        return;
      }
      if (!mounted) return;
      if (!verify['success'] || verify['match'] != true) {
        setState(() => _isPermissionStamping = false);
        SnackBarUtils.showSnackBar(
          context,
          ErrorMessageUtils.sanitizeForDisplay(
            verify['message']?.toString() ?? 'Face not matching. Please try again.',
          ),
          isError: true,
        );
        return;
      }
    }

    setState(() => _isPermissionStamping = true);
    final result = isOut
        ? await _requestService.permissionOut(id, selfie: selfie)
        : await _requestService.permissionIn(id, selfie: selfie);
    if (!mounted) return;
    setState(() => _isPermissionStamping = false);

    if (result['success'] == true) {
      if (!isOut) {
        final data = result['data'];
        final overrun = data is Map
            ? (num.tryParse('${data['overrunMinutes'] ?? 0}') ?? 0)
            : 0;
        SnackBarUtils.showSnackBar(
          context,
          overrun > 0
              ? 'Permission In recorded. You overran by ${overrun.toInt()} min — '
                    'a fine will apply for today.'
              : 'Permission In recorded.',
          isError: overrun > 0,
        );
      } else {
        SnackBarUtils.showSnackBar(context, 'Permission Out recorded.');
      }
      await _fetchTodayPermission();
    } else {
      SnackBarUtils.showSnackBar(
        context,
        ErrorMessageUtils.sanitizeForDisplay(
          result['message']?.toString(),
          fallback: 'Failed to record permission ${isOut ? 'out' : 'in'}',
        ),
        isError: true,
      );
    }
  }

  /// Permission Out / In control rendered under the punch card. Returns an empty
  /// box unless an approved custom-time permission exists for today.
  Widget _buildPermissionStampCard() {
    final p = _todayPermission;
    if (p == null) return const SizedBox.shrink();

    final hasOut = (p['actualOutAt']?.toString().trim().isNotEmpty) ?? false;
    final hasIn = (p['actualInAt']?.toString().trim().isNotEmpty) ?? false;
    final from = p['fromTime']?.toString() ?? '';
    final to = p['toTime']?.toString() ?? '';
    final windowLabel = (from.isNotEmpty && to.isNotEmpty)
        ? '$from – $to'
        : '${p['requestedMinutes'] ?? ''} min';
    final overrun = num.tryParse('${p['overrunMinutes'] ?? 0}') ?? 0;

    // Permission Out may only be stamped after the employee has punched in for
    // the day; Permission In (the return stamp) is unaffected.
    final punchInRaw = _todayAttendance?['punchIn']?.toString().trim();
    final bool hasPunchedIn =
        (punchInRaw != null && punchInRaw.isNotEmpty) ||
        _todayAttendance?['hasPunchIn'] == true;

    final bool actionable = !hasIn;
    final bool isOutAction = !hasOut;
    final bool blockedForNoPunchIn = isOutAction && !hasPunchedIn;
    final String buttonLabel = isOutAction ? 'Permission Out' : 'Permission In';
    final IconData buttonIcon =
        isOutAction ? Icons.logout_rounded : Icons.login_rounded;

    final pending = p['status']?.toString() == 'Pending';
    String statusLine;
    if (!hasOut) {
      statusLine = blockedForNoPunchIn
          ? 'Punch In first — Permission Out is available once you have punched in.'
          : '${pending ? 'Permission (pending approval)' : 'Permission'} ($windowLabel). '
              'Tap when you step out.';
    } else if (!hasIn) {
      statusLine = 'Out since ${_fmtStamp(p['actualOutAt'])}. Tap when you return.';
    } else {
      statusLine = overrun > 0
          ? 'Completed — overran by ${overrun.toInt()} min (fine applied).'
          : 'Completed within the approved window.';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(Icons.event_available_rounded,
              color: AppColors.primary, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Permission',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  statusLine,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textCaption,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (actionable)
            ElevatedButton.icon(
              onPressed: (_isPermissionStamping || blockedForNoPunchIn)
                  ? null
                  : () => _handlePermissionStamp(isOutAction),
              icon: _isPermissionStamping
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(buttonIcon, size: 18),
              label: Text(buttonLabel),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
            )
          else
            Icon(Icons.check_circle_rounded,
                color: Colors.green.shade500, size: 24),
        ],
      ),
    );
  }

  /// Local "hh:mm a" for an ISO timestamp; '-' when unparseable.
  String _fmtStamp(dynamic value) {
    final d = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
    if (d == null) return '-';
    return DateFormat('hh:mm a').format(d);
  }

  Future<void> _loadData() async {
    // Single-flight: ignore overlapping triggers while a load is already running
    // so we don't fire duplicate parallel request bursts.
    if (_isLoadDataInFlight) return;
    _isLoadDataInFlight = true;
    final hasCachedData = _stats != null;
    // Full-screen loading only when no cached data; otherwise show cached
    // content and refresh silently (pull-to-refresh shows its own spinner).
    if (!hasCachedData) {
      setState(() => _isLoadingDashboard = true);
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
            final role = (data['role'] ?? '').toString().toLowerCase().trim();
            _isAdminLike = role == 'admin' ||
                role == 'super admin' ||
                role == 'superadmin' ||
                role == 'hr' ||
                role == 'senior hr';
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
            _avatarNeedsFlip = _computeAvatarFlip(
              _avatarUrl,
              data['faceFirstImage']?.toString(),
              data['faceFirstImageAt'],
            );
          });
          if (_avatarUrl != null) _resolveAvatarFlip(_avatarUrl!);
        }
      }

      // Run dashboard, month attendance, loans, and profile (shifts for rotational calendar) in parallel
      final dashboardFuture = _requestService.getDashboardData();
      final liveTodayFuture = _attendanceService.getTodayAttendance(
        forceRefresh: true,
      );
      final profileFuture = _authService.getProfile();
      final businessFuture = _settingsService.getBusiness();
      final monthFuture = _fetchMonthAttendance(forceRefresh: true);
      final loansFuture = _fetchActiveLoans();
      final breakFuture = _fetchBreakSummary();
      final permissionFuture = _fetchTodayPermission();
      final perfFuture = _fetchPerformanceSummary();
      final fcmFuture = FcmService.getStoredNotifications();
      final fcmSeenFuture = FcmService.getNotificationsLastSeen();
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
      final fcmLastSeen = await fcmSeenFuture;
      if (kDebugMode) {
        debugPrint(
          '[DashboardLoad] core requests settled in ${sw.elapsedMilliseconds}ms | '
          'dashboardSuccess=${result['success']} | '
          'liveTodaySuccess=${liveTodayResult['success']} | '
          'fcmCount=${fcmList.length}',
        );
      }

      // Keep profile/settings enrichment non-blocking so dashboard content is not delayed.
      final enrichFuture = Future<void>(() async {
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
            final profileData =
                Map<String, dynamic>.from(profileSettled['data'] as Map);
            _applyShiftContextFromProfile(
              profileData,
              businessFromSettingsApi: businessFromSettings,
            );
            // Refresh the header avatar from the latest profile so the first-punch
            // image (which the backend saves as the profile photo) shows up here.
            unawaited(_applyAvatarFromProfile(profileData));
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
      Future<void> salaryFuture = Future<void>.value();
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
          var announcementsList = data['todayAnnouncements'] is List
              ? (data['todayAnnouncements'] as List)
                    .where(_isDashboardAnnouncementVisible)
                    .toList()
              : <dynamic>[];
          if (announcementsList.isEmpty) {
            announcementsList = await _tryLoadAnnouncementsFromInteractionApi();
          }
          if (!mounted) return;
          setState(() {
            _stats = stats;
            _recentLeaves = data['recentLeaves'] ?? [];
            _activeLoans = loansList;
            _activeLoansCount = loansList.length;
            _todayAttendance = liveTodayAttendance ?? stats?['attendanceToday'];
            _todayAnnouncements = announcementsList;
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
            _fcmNotificationCount = FcmService.unreadCountFor(
              fcmList,
              fcmLastSeen,
            );
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
          salaryFuture = _calculateSalaryFromModule();
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
            () => _fcmNotificationCount = FcmService.unreadCountFor(
              fcmList,
              fcmLastSeen,
            ),
          );
        }
      }

      // Reveal the dashboard the moment the core data (stats + today) is applied
      // — do NOT hold the full-screen loader waiting on secondary cards. Each
      // secondary fetch (month attendance, loans, break, performance, salary,
      // profile enrichment) updates its own card via setState when it lands, and
      // those cards render their own per-card loaders/placeholders until then.
      // Holding the global loader here was the main "stuck on spinner" cause:
      // a slow month/salary/profile call could keep the whole screen blank for
      // many seconds even after the dashboard data was ready to show.
      if (!hasCachedData && mounted) {
        setState(() => _isLoadingDashboard = false);
      }
      // Let the secondary futures finish in the background; never block the UI.
      unawaited(
        Future.wait<void>([
          monthFuture.catchError((_) {}),
          loansFuture.catchError((_) {}),
          breakFuture.catchError((_) {}),
          permissionFuture.catchError((_) {}),
          perfFuture.catchError((_) {}),
          enrichFuture.catchError((_) {}),
          salaryFuture.catchError((_) {}),
        ]),
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[DashboardLoad] exception: $e');
      }
      // Keep existing UI data on transient failures.
    } finally {
      // Safety net: ensure the loader is cleared even if the early reveal above
      // was skipped (e.g. an exception before core data was applied).
      if (mounted && _isLoadingDashboard) {
        setState(() => _isLoadingDashboard = false);
      }
      _lastDashboardLoadAt = DateTime.now();
      _isLoadDataInFlight = false;
      // Notify the parent without blocking the load's completion: this callback
      // re-fetches profile + punch nav state and must not gate the in-flight
      // guard (an unbounded call here used to keep the spinner up).
      if (widget.onDashboardDataRefreshed != null) {
        unawaited(Future(() => widget.onDashboardDataRefreshed!.call()));
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

  /// Refresh the header avatar from the latest profile. The backend saves the
  /// first punch selfie as the profile photo (Staff.avatar / User.avatar), so once
  /// an employee punches in this picks it up and shows it in the header circle.
  /// Also persists to the cached `user` so it sticks across screens and relaunch.
  Future<void> _applyAvatarFromProfile(Map<String, dynamic> data) async {
    String? av;
    String? faceFirstImage;
    dynamic faceFirstImageAt;
    final staffData = data['staffData'];
    if (staffData is Map) {
      if (staffData['avatar'] != null) av = staffData['avatar']?.toString();
      faceFirstImage = staffData['faceFirstImage']?.toString();
      faceFirstImageAt = staffData['faceFirstImageAt'];
    }
    if (av == null || av.trim().isEmpty) {
      final profile = data['profile'];
      if (profile is Map && profile['avatar'] != null) {
        av = profile['avatar']?.toString();
      }
    }
    if ((av == null || av.trim().isEmpty) && data['avatar'] != null) {
      av = data['avatar']?.toString();
    }
    if (av == null || !av.trim().startsWith('http')) return;
    final url = av.trim();
    final flip = _computeAvatarFlip(url, faceFirstImage, faceFirstImageAt);
    if (url != _avatarUrl || flip != _avatarNeedsFlip) {
      if (mounted) {
        setState(() {
          _avatarUrl = url;
          _avatarNeedsFlip = flip;
        });
      }
    }
    // Correct the timestamp-based guess with the image's real orientation.
    _resolveAvatarFlip(url);
    try {
      final prefs = await SharedPreferences.getInstance();
      final userStr = prefs.getString('user');
      if (userStr != null) {
        final user = jsonDecode(userStr) as Map<String, dynamic>;
        user['avatar'] = url;
        user['photoUrl'] = url;
        if (faceFirstImage != null) user['faceFirstImage'] = faceFirstImage;
        if (faceFirstImageAt != null) {
          user['faceFirstImageAt'] = faceFirstImageAt.toString();
        }
        await prefs.setString('user', jsonEncode(user));
      }
    } catch (_) {}
  }

  /// Fast initial guess for whether the header avatar needs a 180° flip, used
  /// only until [_resolveAvatarFlip] detects the image's real orientation. The
  /// avatar is seeded from the first-punch selfie; legacy seeds (captured before
  /// the capture-time orientation fix) were stored upside-down. Only guess "flip"
  /// when the avatar IS the seeded first image (not a manual upload, which is
  /// upright) and predates the fix — a missing timestamp means a legacy seed.
  bool _computeAvatarFlip(
    String? avatarUrl,
    String? faceFirstImage,
    dynamic faceFirstImageAt,
  ) {
    if (avatarUrl == null || faceFirstImage == null) return false;
    if (avatarUrl.trim() != faceFirstImage.trim()) return false;
    final iso = faceFirstImageAt?.toString();
    if (iso == null || iso.isEmpty) return true;
    final dt = DateTime.tryParse(iso);
    if (dt == null) return true;
    return dt.toUtc().isBefore(AppConstants.selfieOrientationFixCutoffUtc);
  }

  /// Correct [_avatarNeedsFlip] using the avatar image's ACTUAL orientation.
  /// The timestamp guess in [_computeAvatarFlip] can't know a stored image's
  /// real orientation, so it both wrongly flips upright photos (showing them
  /// upside-down) and misses inverted ones. This detects the face orientation
  /// (cached per-URL) and updates the flag; it no-ops when detection can't
  /// decide, leaving the guess in place.
  Future<void> _resolveAvatarFlip(String url) async {
    final resolved = await AvatarOrientation.resolveNeedsFlip(url);
    if (resolved == null || !mounted) return;
    if (url != _avatarUrl || resolved == _avatarNeedsFlip) return;
    setState(() => _avatarNeedsFlip = resolved);
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
          border: Border.all(
            color: colorScheme.outline.withValues(alpha: 0.35),
          ),
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

    final requestYear = _selectedMonth.year;
    final requestMonth = _selectedMonth.month;
    _isFetchingMonthAttendance = true;
    try {
      final result = await _attendanceService.getMonthAttendance(
        requestYear,
        requestMonth,
        forceRefresh: forceRefresh,
      );
      if (mounted) {
        if (result['success']) {
          final currentYear = _selectedMonth.year;
          final currentMonth = _selectedMonth.month;
          if (currentYear != requestYear || currentMonth != requestMonth) {
            return;
          }
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

  /// Loads the overall performance rating so the home card reflects whether
  /// performance has actually been evaluated, instead of a hardcoded score.
  Future<void> _fetchPerformanceSummary() async {
    try {
      final result = await _performanceService.getEmployeeSummary();
      final data = result['data'] as Map<String, dynamic>?;
      if (mounted && data != null) {
        final rating = ((data['averageRating'] ?? 0.0) as num).toDouble();
        setState(() => _performanceRating = rating);
      }
    } catch (_) {
      // Ignore — card stays in its "not evaluated" placeholder state.
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
      color: AppColors.primary,
      onRefresh: _loadData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: FadeSlideIn.staggered([
            // 1. Welcome header
            _buildWelcomeCard(),
            const SizedBox(height: 20),

            // 2. Today's Attendance label + card
            _buildFigmaLabel('TODAY\'S ATTENDANCE'),
           // const SizedBox(height: 10),
          //  _buildFigmaAttendanceCard(),
            const SizedBox(height: 20),
               if (!_isCandidate) ...[
              _buildMonthAttendanceCard(dashboardCompact: true),
              const SizedBox(height: 16),
            ],

//const SizedBox(height: 10),

            // 3. Quick Actions (3 evenly-spaced, per Figma)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: _buildRequestQuickActionButtons(),
            ),
            const SizedBox(height: 20),

            // 4. Recent Leaves (amber card)
            _buildRecentLeavesCard(),
            const SizedBox(height: 16),

            // 5. Celebrations  +  Performance (2-col)
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _buildCelebrationsCard()),
                  const SizedBox(width: 12),
                  Expanded(child: _buildPerformanceCard()),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 6. Announcement  +  This Month Net (2-col)
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _buildAnnouncementSummaryCard(),
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
            const SizedBox(height: 16),

            // 7. Attendance compact (punch card + today sub-card)
            // if (!_isCandidate) ...[
            //   _buildMonthAttendanceCard(dashboardCompact: true),
            //   const SizedBox(height: 16),
            // ],

            // 8. Menu rows
            _buildFigmaMenuItems(),
          ]),
        ),
      ),
    );
    final appBar = AppBar(
      // Figma: no hamburger — the avatar opens the drawer (see _buildWelcomeCard).
      automaticallyImplyLeading: false,
      toolbarHeight: 0,
      title: null,
      elevation: 0,
      backgroundColor: AppColors.background,
      foregroundColor: AppColors.textPrimary,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
    );

    // Cold load (no cached data): show a single loader and reveal the fully
    // populated dashboard once, instead of painting empty/placeholder cards that
    // then swap to real values in staggered waves. `_isLoadingDashboard` is only
    // ever true on a first load (see _loadData), so warm refreshes keep showing
    // cached content and update in place.
    final bodyChild = _isLoadingDashboard
        ? const Center(child: AppTabLoader())
        : content;

    if (widget.embeddedInDashboard) {
      return Scaffold(
        key: _dashboardScaffoldKey,
        backgroundColor: const Color(0xFFF5F7FA),
        appBar: appBar,
        drawer: AppDrawer(
          currentIndex: widget.dashboardTabIndex ?? 0,
          onNavigateToIndex: widget.onNavigateToIndex,
        ),
        body: bodyChild,
      );
    }
    return Scaffold(
      key: _dashboardScaffoldKey,
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: appBar,
      drawer: const AppDrawer(),
      body: bodyChild,
    );
  }

  // ─── Figma: small section label (e.g. "TODAY'S ATTENDANCE") ──────────────
  Widget _buildFigmaLabel(String label) {
    return Text(label, style: AppTextStyles.sectionLabel);
  }

  // ─── Figma: Today's Attendance white card ──────────────────────────────────
  Widget _buildFigmaAttendanceCard() {
    // In/Out times and Working Hours live solely on the dark CloudPunchCard
    // (see _buildMonthAttendanceCard) — this card now only conveys today's status.
    final statusRaw = _todayAttendance != null
        ? (_todayAttendance!['status'] ?? 'Absent').toString()
        : 'Absent';
    final statusStyle = AppColors.statusStyle(statusRaw.toLowerCase());

    return AppCard(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.access_time_rounded,
              color: AppColors.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              "Today's Status",
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: statusStyle.bg,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              statusStyle.label.toUpperCase(),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: statusStyle.fg,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Figma: Performance white card ────────────────────────────────────────
  Widget _buildPerformanceCard() {
    final rating = _performanceRating;
    final hasRating = rating != null && rating > 0;

    return AppCard(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const MyPerformanceScreen()),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Performance',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: AppColors.indigo,
            ),
          ),
          const SizedBox(height: 8),
          if (hasRating) ...[
            Row(
              children: [
                Text(
                  rating.toStringAsFixed(1),
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  '/5.0',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.trending_up_rounded,
                  color: AppColors.success,
                  size: 16,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Keep Rocking',
              style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
            ),
          ] else ...[
            Text(
              'Not rated',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Not evaluated yet',
              style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
            ),
          ],
          const Spacer(),
          Text(
            'VIEW DETAILS →',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Figma: Bottom menu rows (Salary Structure / Payslip / Attendance) ─────
  Widget _buildFigmaMenuItems() {
    final onNavigate = widget.onNavigate;
    final items = [
      (
        Icons.account_balance_wallet_outlined,
        'Salary Structure',
        () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const SalaryStructureDetailScreen(),
          ),
        ),
      ),
      (
        Icons.description_outlined,
        'Request Payslip',
        () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const RequestPayslipScreen())),
      ),
      // (
      //   Icons.access_time_outlined,
      //   'Attendance History',
      //   () => onNavigate?.call(4, subTabIndex: 1),
      // ),
      // (
      //   Icons.calendar_month_outlined,
      //   'Shifts',
      //   // Opens the Attendance Calendar (history view), which surfaces the
      //   // "Today's working shift (this cycle)" card and per-day shift windows.
      //   () => onNavigate?.call(4, subTabIndex: 1),
      // ),
    ];
    return AppCard(
      padding: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (int i = 0; i < items.length; i++) ...[
            InkWell(
              onTap: items[i].$3,
              borderRadius: BorderRadius.vertical(
                top: i == 0 ? const Radius.circular(16) : Radius.zero,
                bottom: i == items.length - 1
                    ? const Radius.circular(16)
                    : Radius.zero,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 16,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.inputFill,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        items[i].$1,
                        color: AppColors.textSecondary,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(items[i].$2, style: AppTextStyles.label),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: AppColors.textCaption,
                    ),
                  ],
                ),
              ),
            ),
            if (i < items.length - 1)
              const Divider(
                height: 1,
                indent: 68,
                endIndent: 18,
                color: Color(0xFFF3F4F6),
              ),
          ],
        ],
      ),
    );
  }

  /// Figma-exact welcome header: avatar + name/date + notification bell.
  /// Time-of-day greeting shown above the user's name in the header.
  String _greetingForNow() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  Widget _buildWelcomeCard() {
    final dateStr = DateFormat('EEEE, MMM d').format(DateTime.now());
    final initial = _userName.isNotEmpty ? _userName[0].toUpperCase() : 'U';
    final hasAvatar =
        _avatarUrl != null && _avatarUrl!.trim().startsWith('http');
    final greeting = _greetingForNow();

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, AppColors.primaryDark],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.35),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Avatar — opens the drawer (Figma replaces the app bar hamburger with this).
          GestureDetector(
            onTap: () => _dashboardScaffoldKey.currentState?.openDrawer(),
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.7),
                  width: 2,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              // Flip legacy (pre-fix, upside-down) seeded avatars 180° on display.
              child: RotatedBox(
                quarterTurns: (hasAvatar && _avatarNeedsFlip) ? 2 : 0,
                child: CircleAvatar(
                  radius: 24,
                  backgroundColor: Colors.white.withValues(alpha: 0.25),
                  backgroundImage: hasAvatar
                      ? CachedNetworkImageProvider(_avatarUrl!)
                      : null,
                  child: hasAvatar
                      ? null
                      : Text(
                          initial,
                          style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          // Greeting + name + date
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  greeting,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _userName,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Icon(
                      Icons.calendar_today_rounded,
                      size: 11,
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      dateStr,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Live-tracking access (moved here from the removed app bar) — only when active.
          if (_liveTrackingActive)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: _buildHeaderIconButton(
                icon: Icons.gps_fixed,
                tooltip: 'Live tracking active',
                onTap: _openLiveTracking,
              ),
            ),
          // Notification bell
          _buildHeaderIconButton(
            icon: Icons.notifications_none_rounded,
            tooltip: 'Notifications',
            badgeCount: _fcmNotificationCount,
            onTap: _openNotifications,
          ),
        ],
      ),
    );
  }

  /// Opens the notifications list. Marks everything as read up front so the bell
  /// badge clears the instant the user taps it, then reconciles on return in
  /// case new notifications arrived while the list was open.
  Future<void> _openNotifications() async {
    final navigator = Navigator.of(context);
    await FcmService.markNotificationsSeen();
    if (mounted) setState(() => _fcmNotificationCount = 0);
    await navigator.push(
      MaterialPageRoute(builder: (_) => const NotificationsScreen()),
    );
    final count = await FcmService.getUnreadNotificationCount();
    if (mounted) setState(() => _fcmNotificationCount = count);
  }

  /// Frosted circular icon button used in the gradient welcome header.
  Widget _buildHeaderIconButton({
    required IconData icon,
    required VoidCallback onTap,
    String? tooltip,
    int badgeCount = 0,
  }) {
    final button = GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 22, color: Colors.white),
          ),
          if (badgeCount > 0)
            Positioned(
              top: -2,
              right: -2,
              child: Container(
                padding: const EdgeInsets.all(2),
                constraints: const BoxConstraints(minWidth: 17, minHeight: 17),
                decoration: BoxDecoration(
                  color: AppColors.error,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
                alignment: Alignment.center,
                child: Text(
                  badgeCount > 9 ? '9+' : '$badgeCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
    return tooltip != null ? Tooltip(message: tooltip, child: button) : button;
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
                showViewFullAttendanceButton: false,
              ),
            ),
          ),
          bottomNavigationBar: AppBottomNavigationBar(currentIndex: -1),
        ),
      ),
    );
  }

  /// Whether a celebration entry is a work anniversary.
  ///
  /// Prefers the backend `type` field, but falls back to the presence of
  /// `yearsOfService` — which only anniversary entries carry — so an older
  /// backend that omits `type` is still classified correctly instead of
  /// defaulting every entry to a birthday.
  bool _isAnniversary(dynamic c) {
    if (c is! Map) return false;
    final type = c['type']?.toString();
    if (type == 'anniversary') return true;
    if (type == 'birthday') return false;
    return c['yearsOfService'] != null;
  }

  /// Builds an accurate summary label for today's celebrations, counting
  /// birthdays and work anniversaries separately (the list mixes both types).
  String _todayCelebrationsLabel() {
    var birthdays = 0;
    var anniversaries = 0;
    for (final c in _todayCelebrations) {
      if (_isAnniversary(c)) {
        anniversaries++;
      } else {
        birthdays++;
      }
    }
    final parts = <String>[];
    if (birthdays > 0) {
      parts.add('$birthdays ${birthdays == 1 ? 'Birthday' : 'Birthdays'}');
    }
    if (anniversaries > 0) {
      parts.add(
        '$anniversaries ${anniversaries == 1 ? 'Work Anniversary' : 'Work Anniversaries'}',
      );
    }
    return '${parts.join(' · ')} today';
  }

  /// Figma: Celebrations card (left in 2-col row). Clean white card with only
  /// a falling colour-paper (confetti) effect.
  Widget _buildCelebrationsCard() {
    final count = _todayCelebrations.length;
    final hasAny =
        count > 0 || (_isAdminLike && _upcomingCelebrations.isNotEmpty);

    const Color avatarRing = Colors.white;
    final Color avatarFill = AppColors.primary.withValues(alpha: 0.85);
    final Color ctaColor = AppColors.primary;

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
          Row(
            children: [
              const Icon(
                Icons.celebration,
                size: 20,
                color: Color(0xFFFFC107), // gold
              ),
              const SizedBox(width: 6),
              const Text(
                'Celebrations',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1F2937),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (count == 0)
            Text(
              'No celebrations today',
              style: TextStyle(
                fontSize: 11,
                color: const Color(0xFF1F2937).withValues(alpha: 0.55),
              ),
            )
          else ...[
            // Avatar row
            SizedBox(
              height: 28,
              child: Stack(
                children: [
                  for (int i = 0; i < math.min(count, 3); i++)
                    Positioned(
                      left: i * 20.0,
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: avatarFill,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: avatarRing,
                            width: 2,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            (_todayCelebrations[i]['name']?.toString() ??
                                    '?')[0]
                                .toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (count > 3)
                    Positioned(
                      left: 3 * 20.0,
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: avatarRing,
                            width: 2,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            '+${count - 3}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _todayCelebrationsLabel(),
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF1F2937),
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Text(
                  'Tap to view',
                  style: TextStyle(
                    fontSize: 10,
                    color: ctaColor.withValues(alpha: 0.95),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  size: 14,
                  color: ctaColor.withValues(alpha: 0.95),
                ),
              ],
            ),
          ],
        ],
    );

    return GestureDetector(
      onTap: hasAny ? _openCelebrationsSheet : null,
      behavior: HitTestBehavior.opaque,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: kSoftCardShadow,
        ),
        child: Stack(
          children: [
            // Falling colour-paper (confetti) — the only effect on the card.
            // Slow motion + smaller particles.
            const Positioned.fill(
              child: ConfettiBurst(
                duration: Duration(milliseconds: 6000),
                minSize: 3,
                maxSize: 7,
                repeat: true,
              ),
            ),
            Padding(padding: const EdgeInsets.all(16), child: content),
          ],
        ),
      ),
    );
  }

  /// Bottom sheet listing who is celebrating today and in the coming days
  /// (birthdays and work anniversaries) for the current business.
  void _openCelebrationsSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.55,
          minChildSize: 0.3,
          maxChildSize: 0.9,
          expand: false,
          builder: (ctx, scrollController) {
            final hasToday = _todayCelebrations.isNotEmpty;
            return Stack(
              children: [
                Container(
              decoration: const BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFCBD5E1),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Icon(
                        Icons.celebration_outlined,
                        color: AppColors.primary,
                        size: 22,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Celebrations',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      children: [
                        if (_todayCelebrations.isNotEmpty) ...[
                          ..._buildGroupedCelebrationTiles(
                            _todayCelebrations,
                            isToday: true,
                          ),
                          const SizedBox(height: 8),
                        ],
                        if (_isAdminLike &&
                            _upcomingCelebrations.isNotEmpty) ...[
                          _buildCelebrationSectionLabel('Upcoming'),
                          const SizedBox(height: 8),
                          ..._buildGroupedCelebrationTiles(
                            _upcomingCelebrations,
                            isToday: false,
                          ),
                        ],
                        if (_todayCelebrations.isEmpty &&
                            (!_isAdminLike ||
                                _upcomingCelebrations.isEmpty))
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 24),
                            child: Center(
                              child: Text(
                                'No celebrations',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: const Color(0xFF475569).withValues(
                                    alpha: 0.8,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
                ),
                // Festive confetti overlay when someone is celebrating today.
                if (hasToday)
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(24),
                      ),
                      child: const ConfettiBurst(),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  /// Splits a mixed celebration list into Birthdays and Work Anniversaries,
  /// each under its own section label (birthdays first). Sections with no
  /// entries are omitted; whenever a section has at least one entry its label
  /// is shown — so even a single birthday or single anniversary appears under
  /// the correct header.
  List<Widget> _buildGroupedCelebrationTiles(
    List<dynamic> items, {
    required bool isToday,
  }) {
    final birthdays = items.where((c) => !_isAnniversary(c)).toList();
    final anniversaries = items.where((c) => _isAnniversary(c)).toList();
    final widgets = <Widget>[];

    if (birthdays.isNotEmpty) {
      widgets.add(
        _buildCelebrationSectionLabel(
          birthdays.length == 1 ? 'Birthday' : 'Birthdays',
          count: birthdays.length,
        ),
      );
      widgets.add(const SizedBox(height: 10));
      for (final c in birthdays) {
        widgets.add(_buildCelebrationTile(c, isToday: isToday));
      }
    }

    if (anniversaries.isNotEmpty) {
      if (birthdays.isNotEmpty) widgets.add(const SizedBox(height: 16));
      widgets.add(
        _buildCelebrationSectionLabel(
          anniversaries.length == 1
              ? 'Work Anniversary'
              : 'Work Anniversaries',
          count: anniversaries.length,
        ),
      );
      widgets.add(const SizedBox(height: 10));
      for (final c in anniversaries) {
        widgets.add(_buildCelebrationTile(c, isToday: isToday));
      }
    }

    return widgets;
  }

  Widget _buildCelebrationSectionLabel(String label, {int? count}) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 14,
          margin: const EdgeInsets.only(right: 8),
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Color(0xFF334155),
            letterSpacing: 0.2,
          ),
        ),
        if (count != null) ...[
          const SizedBox(width: 6),
          Text(
            '($count)',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF94A3B8),
            ),
          ),
        ],
      ],
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

  /// Age the person turns on their next (or today's) birthday, computed from
  /// the raw `dob` the backend sends in `date`. Falls back to the backend's
  /// `turningAge` field. Returns null if neither is usable.
  int? _birthdayTurningAge(dynamic c) {
    final raw = c['date']?.toString();
    if (raw != null && raw.isNotEmpty) {
      final dob = DateTime.tryParse(raw);
      if (dob != null) {
        final now = DateTime.now();
        // Next occurrence of the birthday (today counts as the upcoming one).
        var nextYear = now.year;
        final bdayThisYear = DateTime(now.year, dob.month, dob.day);
        if (bdayThisYear.isBefore(DateTime(now.year, now.month, now.day))) {
          nextYear = now.year + 1;
        }
        final age = nextYear - dob.year;
        if (age > 0) return age;
      }
    }
    return (c['turningAge'] is int) ? c['turningAge'] as int : null;
  }

  Widget _buildCelebrationTile(dynamic c, {required bool isToday}) {
    final colorScheme = Theme.of(context).colorScheme;
    final name = c['name']?.toString() ?? '—';
    final displayDate = c['displayDate']?.toString() ?? '';
    final daysLeft = (c['daysLeft'] is int) ? c['daysLeft'] as int : 0;
    final isAnniversary = _isAnniversary(c);
    final yearsOfService = (c['yearsOfService'] is int)
        ? c['yearsOfService'] as int
        : 1;
    final turningAge = _birthdayTurningAge(c);
    final typeLabel = isAnniversary
        ? 'Work Anniversary · ${_anniversaryYearsLabel(yearsOfService)}'
        : (turningAge != null
              ? 'Birthday · turning $turningAge ${turningAge == 1 ? 'year' : 'years'}'
              : 'Birthday');
    final subtitle = isToday
        ? typeLabel
        : '$typeLabel · ${daysLeft == 1 ? '1 day left' : '$daysLeft days left'}';
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
            color: accentColor.withValues(alpha: 0.12),
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
                  color: accentColor.withValues(alpha: 0.9),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Figma quick actions: Request Permission | Request Leave | Expense Claim
  List<Widget> _buildRequestQuickActionButtons() {
    // Wrapped in Expanded so all actions share the row width evenly and
    // fit on a single screen — no horizontal scroll.
    return [
      // Shift Time is only meaningful for staff on a rotational shift (their
      // working window changes per cycle day). Fixed-shift employees always
      // work the same window, so the quick action is hidden for them.
      if (_profileShiftIsRotational)
        Expanded(
          child: _buildQuickActionButton(
            icon: Icons.access_time_rounded,
            label: 'Shift\nTime',
            onTap: _openShiftTimeSheet,
          ),
        ),
      Expanded(
        child: _buildQuickActionButton(
          icon: Icons.badge_outlined,
          label: 'Request\nPermission',
          onTap: _openRequestPermissionSheet,
        ),
      ),
      Expanded(
        child: _buildQuickActionButton(
          icon: Icons.event_available_outlined,
          label: 'Request\nLeave',
          onTap: _openRequestLeaveSheet,
        ),
      ),
      Expanded(
        child: _buildQuickActionButton(
          icon: Icons.receipt_long_outlined,
          label: 'Expense\nClaim',
          onTap: _openClaimExpenseSheet,
        ),
      ),
    ];
  }

  /// Navigates to the Requests screen on the Permission tab.
  void _openRequestPermissionSheet() {
    widget.onNavigate?.call(1, subTabIndex: 1);
  }

  /// Navigates to the Requests screen on the Leave tab.
  void _openRequestLeaveSheet() {
    widget.onNavigate?.call(1, subTabIndex: 0);
  }

  /// Navigates to the Requests screen on the Expense tab.
  void _openClaimExpenseSheet() {
    widget.onNavigate?.call(1, subTabIndex: 2);
  }

  /// Opens the full-page Shift screen. Passes the raw shift-resolution inputs
  /// so [ShiftScreen] can compute the effective shift for any calendar day with
  /// the same rotational logic as the assigned-shift header (no re-fetch).
  void _openShiftTimeSheet() {
    final now = DateTime.now();
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

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ShiftScreen(
          companyDoc: _profileCompanyDoc,
          staffShiftKey: _profileStaffShiftName,
          joiningDate: _profileJoiningDate,
          todayTemplate: _todayAttendanceTemplateMap(),
          appliedHeaderLine: appliedHeaderLine,
          referenceDate: now,
          initialMonthData: _monthData,
        ),
      ),
    );
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
            color: isPrimaryCard
                ? Colors.white.withValues(alpha: 0.9)
                : accentColor,
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
                  ? Colors.white.withValues(alpha: 0.85)
                  : colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
    // Vibrant multi-colour gradient for the primary card: a full warm-to-cool
    // sweep. Plain surface for the secondary variants.
    const cardGradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color(0xFFFF4E50), // red
        Color(0xFFF9A825), // amber
        Color(0xFF43E97B), // green
        Color(0xFF2563EB), // blue
        Color(0xFF8E2DE2), // purple
      ],
    );

    final card = Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isPrimaryCard ? null : colorScheme.surface,
        gradient: isPrimaryCard ? cardGradient : null,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isPrimaryCard
              ? Colors.white.withValues(alpha: 0.25)
              : colorScheme.outline.withValues(alpha: 0.4),
        ),
        boxShadow: [
          BoxShadow(
            color: isPrimaryCard
                ? const Color(0xFFD62976).withValues(alpha: 0.35)
                : accentColor.withValues(alpha: 0.08),
            blurRadius: isPrimaryCard ? 16 : 10,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: (icon != null || imageAsset != null)
          ? Row(
              children: [
                if (icon != null)
                  PopPulse(
                    child:
                        iconGradientColors != null &&
                            iconGradientColors.length >= 2
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
                          ),
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

    // Gentle entrance animation when the card first mounts.
    return FadeSlideIn(child: card);
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
            color: Colors.black.withValues(alpha: 0.02),
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
            color: Colors.black.withValues(alpha: 0.02),
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

  /// Figma: circular amber icon + label below
  Widget _buildQuickActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      // No fixed width — the parent Expanded controls the column width so four
      // actions fit on one row across small screens.
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: AppColors.primary, size: 22),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Figma: Announcements white card (bottom-left of 2-col row) — replaces
  /// the former "Leave Requests" summary card.
  Widget _buildAnnouncementSummaryCard() {
    Map<String, dynamic>? latest;
    if (_todayAnnouncements.isNotEmpty) {
      final first = _todayAnnouncements.first;
      if (first is Map) latest = Map<String, dynamic>.from(first);
    }
    final hasItems = latest != null;
    final title = latest?['title']?.toString().trim() ?? '';
    final description = latest?['description']?.toString().trim() ?? '';

    return AppCard(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const AnnouncementsScreen()),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                Icons.campaign_rounded,
                size: 16,
                color: AppColors.primary,
              ),
              const SizedBox(width: 6),
              Text(
                'Announcements',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            hasItems && title.isNotEmpty ? title : 'No announcements',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
              letterSpacing: -0.2,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              hasItems
                  ? (description.isNotEmpty ? description : 'Tap to view')
                  : 'You\'re all caught up',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10, color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  /// Figma: This Month Net white card (bottom-right of 2-col row)
  /// Tapping "This Month Net" opens the Salary Structure page, which loads the
  /// staff salary bundle and handles its own access-denied messaging.
  void _openSalaryStructure() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const StaffSalaryStructureScreen(),
      ),
    );
  }

  Widget _buildThisMonthNetSummaryCard(
    String mtdAmount,
    String? monthlyAmount,
    String presentDaysSubtitle,
  ) {
    return AppCard(
      onTap: _openSalaryStructure,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'This Month Net',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              mtdAmount,
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: AppColors.indigo,
                letterSpacing: -0.5,
              ),
            ),
          ),
          if (presentDaysSubtitle.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                presentDaysSubtitle,
                style: TextStyle(fontSize: 10, color: AppColors.textSecondary),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRecentLeavesCard() {
    final showInitialLoader =
        _isLoadingDashboard && _stats == null && _recentLeaves.isEmpty;
    return AppCard(
      onTap: () => widget.onNavigate?.call(1, subTabIndex: 0),
      padding: const EdgeInsets.all(18),
      color: AppColors.primary,
      boxShadow: [
        BoxShadow(
          color: AppColors.primary.withValues(alpha: 0.28),
          blurRadius: 14,
          offset: const Offset(0, 5),
        ),
      ],
      child: _recentLeavesContent(showInitialLoader),
    );
  }

  /// Featured most-recent-leave content for the amber dashboard card (Figma):
  /// label + status badge, big leave-type title, then the dated range.
  Widget _recentLeavesContent(bool showInitialLoader) {
    Widget label() => Text(
      'RECENT LEAVES',
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        color: Colors.white.withValues(alpha: 0.8),
        letterSpacing: 1.1,
      ),
    );

    if (showInitialLoader) {
      return const Center(
        child: Padding(padding: EdgeInsets.all(20), child: AppTabLoader()),
      );
    }

    final leave = _recentLeaves.isNotEmpty && _recentLeaves.first is Map
        ? _recentLeaves.first as Map
        : null;
    if (leave == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          label(),
          const SizedBox(height: 14),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'No recent leave requests',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ],
      );
    }

    final leaveType = leave['leaveType']?.toString() ?? 'Leave';
    final status = leave['status']?.toString() ?? '';
    String dateStr = '';
    try {
      final s = DateTime.parse(leave['startDate'].toString());
      final endRaw = leave['endDate'];
      final e = endRaw != null ? DateTime.parse(endRaw.toString()) : null;
      dateStr = e != null
          ? '${DateFormat('MMM d').format(s)} - ${DateFormat('MMM d, y').format(e)}'
          : DateFormat('MMM d, y').format(s);
    } catch (_) {}

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            label(),
            const Spacer(),
            if (status.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.20),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  status.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          leaveType,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        if (dateStr.isNotEmpty) ...[
          const SizedBox(height: 14),
          Row(
            children: [
              Icon(
                Icons.calendar_today_rounded,
                size: 14,
                color: Colors.white.withValues(alpha: 0.9),
              ),
              const SizedBox(width: 8),
              Text(
                dateStr,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.white.withValues(alpha: 0.95),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  // ignore: unused_element
  Widget _buildRecentLeaveItem(dynamic leave) {
    final leaveType = leave['leaveType']?.toString() ?? 'Leave';
    final status = leave['status']?.toString() ?? 'N/A';
    String dateStr = '';
    try {
      final s = DateTime.parse(leave['startDate'].toString());
      dateStr = DateFormat('MMM d, y').format(s);
    } catch (_) {}

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(
            Icons.circle,
            size: 8,
            color: Colors.white.withValues(alpha: 0.6),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  leaveType,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                if (dateStr.isNotEmpty)
                  Text(
                    dateStr,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              status.toUpperCase(),
              style: const TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
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
    bool showViewFullAttendanceButton = true,
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
                  breakSummary: _breakSummary,
                );
              },
            ),
            const SizedBox(height: 16),
          ],
          // Permission Out / In for an approved custom-time permission today.
          // Shown regardless of punch state (the window may start before punch-in).
          _buildPermissionStampCard(),
          // _buildTodayAttendanceSubCard(
          //   showCalendarIconInHeader: false,
          //   standaloneDashboardCard: true,
          // ),
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
            color: Colors.black.withValues(alpha: 0.2),
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
          if (showViewFullAttendanceButton) ...[
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
    final todayLabel = DateFormat('dd MMM, EEEE').format(now);

    String formatTime(String? isoString) {
      if (isoString == null) return '--:--';
      try {
        return DateFormat(
          'hh:mm a',
        ).format(DateTime.parse(isoString).toLocal());
      } catch (_) {
        return '--:--';
      }
    }

    final punchIn = _todayAttendance?['punchIn'];
    final punchOut = _todayAttendance?['punchOut'];
    final address = _todayAttendance != null
        ? (_todayAttendance?['address'] ?? 'Location recorded')
        : null;

    final statusText = _todayAttendance != null
        ? (_todayAttendance?['status'] == 'Pending' &&
                  _todayAttendance?['punchIn'] != null
              ? 'Awaiting Approval'
              : AttendanceDisplayUtil.formatAttendanceDisplayStatus(
                  _todayAttendance?['status'] ?? 'Present',
                  _todayAttendance?['leaveType'],
                ))
        : 'Absent';

    final statusColorFg = _todayAttendance != null
        ? (_todayAttendance?['status'] == 'Pending'
              ? Colors.orange
              : (_todayAttendance?['status'] == 'Rejected' ||
                        _todayAttendance?['status'] == 'Absent'
                    ? Colors.red
                    : _todayAttendance?['status'] == 'On Leave'
                    ? Colors.blue
                    : Colors.green))
        : Colors.red;

    final hasPunched = punchIn != null && punchIn.toString().trim().isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: standaloneDashboardCard
          ? BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.07),
                  blurRadius: 16,
                  offset: const Offset(0, 5),
                ),
              ],
            )
          : BoxDecoration(
              color: colorScheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: colorScheme.outline),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Today\'s Attendance',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF1E293B),
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    todayLabel,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                  ),
                ],
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: statusColorFg.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: statusColorFg.withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  statusText,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: statusColorFg,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildPunchTimeChip(
                  label: 'Punch In',
                  time: formatTime(punchIn),
                  icon: Icons.login_rounded,
                  color: Colors.green,
                  active: hasPunched,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildPunchTimeChip(
                  label: 'Punch Out',
                  time: formatTime(punchOut),
                  icon: Icons.logout_rounded,
                  color: AppColors.primary,
                  active:
                      punchOut != null && punchOut.toString().trim().isNotEmpty,
                ),
              ),
            ],
          ),
          if (address != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  Icons.location_on_outlined,
                  size: 13,
                  color: Colors.grey.shade400,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    address,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPunchTimeChip({
    required String label,
    required String time,
    required IconData icon,
    required Color color,
    required bool active,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: active
            ? color.withValues(alpha: 0.08)
            : Colors.grey.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: active
              ? color.withValues(alpha: 0.25)
              : Colors.grey.withValues(alpha: 0.15),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: active ? color : Colors.grey.shade400),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey.shade500,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  time,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: active
                        ? const Color(0xFF1E293B)
                        : Colors.grey.shade400,
                  ),
                ),
              ],
            ),
          ),
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
            side: BorderSide(
              color: colorScheme.outline.withValues(alpha: 0.35),
            ),
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
                        const SizedBox(width: 48, height: 48),
                        Text(
                          DateFormat('MMMM yyyy').format(_selectedMonth),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(width: 48, height: 48),
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
                              webBadgeLabel = 'H';
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
                                  color: colorScheme.outline.withValues(
                                    alpha: 0.6,
                                  ),
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
                                    : colorScheme.outline.withValues(
                                        alpha: 0.6,
                                      ),
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
        _buildLegendItem('H', 'Holiday', textColor: const Color(0xFF92400E)),
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
            border: Border.all(
              color: colorScheme.outline.withValues(alpha: 0.6),
            ),
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
