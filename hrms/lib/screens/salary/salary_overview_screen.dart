import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import '../../config/app_colors.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/app_tab_loader.dart';
import '../../widgets/menu_icon_button.dart';
import '../../services/salary_service.dart';
import '../../services/auth_service.dart';
import '../../services/attendance_service.dart';
import '../../services/holiday_service.dart';
import '../../services/settings_service.dart';
import '../../models/holiday_model.dart';
import '../../services/request_service.dart';
import '../../utils/salary_structure_calculator.dart';
import '../../utils/salary_fine_summary.dart';
import '../../utils/fine_calculation_util.dart';
import '../../utils/app_event_bus.dart';
import '../../utils/attendance_display_util.dart';
import '../../utils/snackbar_utils.dart';

// -----------------------------------------------------------------------------
// MTD salary: same blended “sources of truth” as web EmployeeSalaryOverview.tsx
// -----------------------------------------------------------------------------
// "This Month" cards: MTD till date only — preview → client prorated → /payroll/stats
// (do not use processed payroll document gross/net on these cards; see web salary cards).
// Headline **present days** follow web `EmployeeSalaryOverview`: record reducer in
// [_computeWebAttendanceBreakdown] (`_webPresentDays`). `/payroll/stats` presentDays is not
// used for headline (it often disagrees with rows). Optional: `/attendance/month`
// stats only when within 0.01 of the reducer. Proration numerator uses `_webPresentDays`.
//
// **MTD “This Month” gross/net:** If payroll row is **Processed/Paid**, use it (web 472–473).
// Otherwise **preview → prorated → payroll** — pending payroll is a stale snapshot and does not
// update as attendance changes; `/payroll/stats` is not used for these cards.
// “This Month Gross” % and Attendance Summary badge both use MTD: present ÷ till-date
// working days (or preview `attendancePercentage`), not present ÷ full-month WD.
// -----------------------------------------------------------------------------

/// Earnings rows already covered by [MonthlySalaryStructure] — merge API extras only (e.g. expense claims).
bool _isCoreStructuralEarningName(String rawName) {
  final n = rawName.toLowerCase().trim();
  if (n.isEmpty) return false;
  if (n == 'basic salary' || n == 'basic') return true;
  if (n == 'da' || n.contains('dearness')) return true;
  if (n == 'hra' || n.contains('house rent')) return true;
  if (n.contains('special allowance')) return true;
  if (n.contains('employer pf') || n.contains('employer epf')) return true;
  if (n.contains('employer esi')) return true;
  if (n.contains('statutory pf')) return true;
  return false;
}

class SalaryOverviewScreen extends StatefulWidget {
  final int? dashboardTabIndex;
  final void Function(int index)? onNavigateToIndex;

  /// When true, this tab is visible. Used to refresh once when user opens the screen.
  final bool? isActiveTab;

  const SalaryOverviewScreen({
    super.key,
    this.dashboardTabIndex,
    this.onNavigateToIndex,
    this.isActiveTab,
  });

  @override
  State<SalaryOverviewScreen> createState() => _SalaryOverviewScreenState();
}

class _SalaryOverviewScreenState extends State<SalaryOverviewScreen>
    with WidgetsBindingObserver {
  final SalaryService _salaryService = SalaryService();
  final AuthService _authService = AuthService();
  final AttendanceService _attendanceService = AttendanceService();
  final HolidayService _holidayService = HolidayService();
  final SettingsService _settingsService = SettingsService();
  final RequestService _requestService = RequestService();
  late final StreamSubscription<AppEvent> _attendanceEventSub;
  bool _isLoading = true;
  String _error = '';
  bool _isFetching = false; // Prevent concurrent fetches
  /// Salary tab became visible while a fetch was in flight — run another fetch after it finishes.
  bool _pendingTabVisibleRefresh = false;
  /// After [AppLifecycleState.paused], refresh on resume if salary tab is still active.
  bool _refreshSalaryWhenAppResumes = false;
  Timer? _debounceTimer; // Debounce timer for rapid calls

  String _selectedMonth = _initialMonth();
  String _selectedYear = _initialYear();

  static String _initialMonth() => DateFormat('MMMM').format(DateTime.now());

  static String _initialYear() => DateFormat('yyyy').format(DateTime.now());

  // Calculated salary data
  CalculatedSalaryStructure? _calculatedSalary;
  ProratedSalary? _proratedSalary;
  WorkingDaysInfo? _workingDaysInfo;
  double _presentDays = 0;
  double _paidLeaveDays = 0;
  int _halfDayPaidLeaveCount = 0;
  double _leaveDays = 0;
  Map<String, dynamic>? _staffSalary;
  Map<String, dynamic>? _currentPayroll;

  /// Web `previewPayroll` — same as RTK `usePreviewPayrollMutation` when no payroll row for the month.
  Map<String, dynamic>? _payrollPreview;

  /// When selected month/year is a past month, payroll from API (staffId + month + year). Null if no payroll for that month.
  Map<String, dynamic>? _pastMonthPayroll;
  List<dynamic> _attendanceRecords = [];
  List<DateTime> _holidays = [];
  Set<String> _presentDates = {};
  Set<String> _absentDates = {};
  Set<String> _holidayDates = {};
  Set<String> _weekOffDates = {};
  Set<String> _leaveDates = {};
  String _weeklyOffPattern = 'standard';
  List<int> _weeklyHolidays =
      []; // Day numbers: 0=Sunday, 1=Monday, ..., 6=Saturday
  Map<String, dynamic> _fineInfo = {
    'totalFineAmount': 0.0,
    'lateDays': 0,
    'totalLateMinutes': 0,
  };

  /// Per-day late login fine (date yyyy-MM-dd -> amount) for Daily Breakdown in Month Salary Details.
  Map<String, double> _dailyFineAmounts = {};

  /// Shift times for day details modal (from template/business settings).
  String? _shiftStartTime;
  String? _shiftEndTime;

  int? _parseWeeklyHolidayDay(dynamic rawDay) {
    if (rawDay is int) return rawDay >= 0 && rawDay <= 6 ? rawDay : null;
    if (rawDay is num) {
      final v = rawDay.toInt();
      return v >= 0 && v <= 6 ? v : null;
    }
    if (rawDay is String) {
      final s = rawDay.trim().toLowerCase();
      final parsed = int.tryParse(s);
      if (parsed != null) return parsed >= 0 && parsed <= 6 ? parsed : null;
      const map = <String, int>{
        'sun': 0,
        'sunday': 0,
        'mon': 1,
        'monday': 1,
        'tue': 2,
        'tues': 2,
        'tuesday': 2,
        'wed': 3,
        'wednesday': 3,
        'thu': 4,
        'thur': 4,
        'thurs': 4,
        'thursday': 4,
        'fri': 5,
        'friday': 5,
        'sat': 6,
        'saturday': 6,
      };
      return map[s];
    }
    return null;
  }

  /// When set, use this for "This Month Net" (from backend /payroll/stats) so it matches payslip.
  double? _backendThisMonthNet;

  /// When set, use this for "This Month Gross" (from backend) for consistency.
  double? _backendThisMonthGross;
  List<Map<String, dynamic>> _backendEarnings = [];
  List<Map<String, dynamic>> _backendDeductionComponents = [];
  double _backendDeductionsTotal = 0.0;

  // Web-style attendance breakdown
  int _fullDayPresentCount = 0;
  int _halfDayPresentCount = 0;
  double _webPresentDays = 0.0;
  /// Last client-only sum from [_computeWebAttendanceBreakdown] before syncing to [_presentDays] (debug).
  double _clientPresentDaysBeforeSync = 0.0;
  double _webPaidLeaves = 0.0;
  double _webUnpaidLeaves = 0.0;
  Map<String, Map<String, double>> _webLeaveTypeBreakdown = {};

  /// From company.settings.payroll.payslip.isPayslipAutoGenerated. When true, show download payslip for months that have payroll.payslipUrl.
  bool _isPayslipAutoGenerated = false;

  /// Paginated payroll list for history table (web `useGetPayrollsQuery` without month/year).
  int _payrollHistoryPage = 1;
  int _payrollHistoryPageSize = 10;
  List<Map<String, dynamic>> _payrollHistoryRows = [];
  Map<String, dynamic>? _payrollHistoryPagination;
  bool _payrollHistoryLoading = false;

  /// Web `staffData.salaryDetailsAccessEnabled` — must be explicitly true (same as `!!` on web).
  bool _salaryDetailsAccessEnabled = false;

  /// Web `staffData.allowCurrentCycleSalaryAccess` — must be explicitly true to show current-month MTD.
  bool _allowCurrentCycleSalaryAccess = false;

  String? _staffId;

  /// Web parity: unpaid leave deducts daily net × unpaid days after proration.
  double _unpaidLeaveDeduction = 0;

  /// True when HR disabled salary overview entirely for this staff.
  bool _salaryAccessDenied = false;

  static const Duration _networkTimeout = Duration(seconds: 25);

  final List<String> _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  /// Web EmployeeSalaryOverview: years from current year − 50 through + 50 (not join-date limited).
  List<String> get _pickerYears {
    final cy = DateTime.now().year;
    return List.generate(101, (i) => '${cy - 50 + i}');
  }

  void _clampSelectedFiltersToAllowed() {
    final years = _pickerYears;
    if (years.isEmpty) return;
    final minY = int.parse(years.first);
    final maxY = int.parse(years.last);
    var y = int.tryParse(_selectedYear) ?? DateTime.now().year;
    y = y.clamp(minY, maxY);
    _selectedYear = '$y';
    if (!_months.contains(_selectedMonth)) {
      _selectedMonth = _months[DateTime.now().month - 1];
    }
  }

  /// Web `visiblePayrolls`: current calendar month row only if allowed; other months only with payslipUrl.
  List<Map<String, dynamic>> get _visiblePayrollHistory {
    final now = DateTime.now();
    return _payrollHistoryRows.where((p) {
      final m = (p['month'] as num?)?.toInt() ?? 0;
      final y = (p['year'] as num?)?.toInt() ?? 0;
      final isRowCurrentMonth = m == now.month && y == now.year;
      if (isRowCurrentMonth) return _allowCurrentCycleSalaryAccess;
      final url = p['payslipUrl']?.toString().trim() ?? '';
      return url.isNotEmpty;
    }).map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<void> _loadPayrollHistory() async {
    if (_staffId == null ||
        _staffId!.isEmpty ||
        !_salaryDetailsAccessEnabled ||
        _salaryAccessDenied) {
      if (mounted) {
        setState(() {
          _payrollHistoryRows = [];
          _payrollHistoryPagination = null;
          _payrollHistoryLoading = false;
        });
      }
      return;
    }
    if (mounted) setState(() => _payrollHistoryLoading = true);
    try {
      final payrollData = await _salaryService
          .getPayrolls(page: _payrollHistoryPage, limit: _payrollHistoryPageSize)
          .timeout(_networkTimeout);
      var rows = <Map<String, dynamic>>[];
      Map<String, dynamic>? pag;
      if (payrollData['success'] == true && payrollData['data'] is Map) {
        final d = Map<String, dynamic>.from(payrollData['data'] as Map);
        final raw = d['payrolls'];
        if (raw is List) {
          rows = raw
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
        if (d['pagination'] is Map) {
          pag = Map<String, dynamic>.from(d['pagination'] as Map);
        }
      }
      if (mounted) {
        setState(() {
          _payrollHistoryRows = rows;
          _payrollHistoryPagination = pag;
          _payrollHistoryLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _payrollHistoryRows = [];
          _payrollHistoryLoading = false;
        });
      }
    }
  }

  /// True when selected month/year is the current month and year (calculation applies).
  bool _isCurrentMonth(int monthIndex, int year) {
    final now = DateTime.now();
    return monthIndex == now.month && year == now.year;
  }

  bool get _isSelectedCurrentMonth {
    final monthIndex = _months.indexOf(_selectedMonth) + 1;
    final year = int.tryParse(_selectedYear) ?? DateTime.now().year;
    return _isCurrentMonth(monthIndex, year);
  }

  /// Web `isCurrentCycleBlocked`: current calendar month and current-cycle salary hidden.
  bool get _isCurrentCycleBlocked =>
      _isSelectedCurrentMonth && !_allowCurrentCycleSalaryAccess;

  /// Pending payroll documents keep fixed gross/net until regenerated — use live prorated for MTD until finalized.
  bool _payrollRowIsFinalForMtd(Map<String, dynamic>? payroll) {
    if (payroll == null) return false;
    final s = (payroll['status'] ?? '').toString().trim().toLowerCase();
    return s == 'processed' || s == 'paid';
  }

  /// Build [CalculatedSalaryStructure] from profile staff.salary (new structure or legacy gross-only).
  void _resolveCalculatedSalaryFromStaff(Map<String, dynamic> raw) {
    _staffSalary = Map<String, dynamic>.from(raw);
    final basic = _staffSalary!['basicSalary'];
    final hasBasicField = basic != null && basic is num;
    final basicPositive = hasBasicField && basic.toDouble() > 0;
    final gross = _staffSalary!['gross'];
    final hasGross = gross != null && gross is num && gross.toDouble() > 0;
    final hasNet = _staffSalary!['net'] != null && _staffSalary!['net'] is num;
    final hasCtc =
        _staffSalary!['ctcYearly'] != null && _staffSalary!['ctcYearly'] is num;
    final hasOtherSalaryFields = hasGross || hasNet || hasCtc;

    if (hasBasicField && (basicPositive || hasOtherSalaryFields)) {
      _calculatedSalary = calculateSalaryStructure(
        SalaryStructureInputs.fromMap(_staffSalary!),
      );
    } else if (hasGross) {
      _calculatedSalary = calculatedSalaryFromLegacyStaffMap(_staffSalary!);
    } else {
      _calculatedSalary = null;
    }
  }

  /// Web `usePreviewPayrollMutation`: only when no payroll document exists for [monthIndex]/[year].
  Future<void> _tryFetchPayrollPreview(int monthIndex, int year) async {
    if (_staffId == null || _staffId!.isEmpty) return;
    try {
      final previewRes = await _salaryService
          .previewPayroll(employeeId: _staffId!, month: monthIndex, year: year)
          .timeout(_networkTimeout);
      if (previewRes['success'] == true &&
          previewRes['data'] is Map<String, dynamic>) {
        final d = previewRes['data'] as Map<String, dynamic>;
        final p = d['preview'];
        if (p is Map) {
          _payrollPreview = Map<String, dynamic>.from(p);
          debugPrint(
            '[SalaryOverview] preview MTD gross=${_payrollPreview!['grossSalary']} net=${_payrollPreview!['netPay']} '
            'attendance=${_payrollPreview!['attendance']}',
          );
        }
      }
    } catch (e) {
      debugPrint('[SalaryOverview] preview fetch error: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Auto-refresh salary when attendance changes (e.g. punch in/out)
    // Use debounce to prevent rapid calls
    _attendanceEventSub = AppEventBus.on(
      AppEventType.attendanceChanged,
    ).listen((_) => _fetchSalaryData(debounce: true));
    // Same as tab open: if salary is visible on first frame (e.g. dashboard initialIndex == 2),
    // clear caches and fetch; otherwise prefetch in background without clearing shared cache.
    if (widget.isActiveTab == true) {
      _onSalaryTabBecameVisible();
    } else {
      _fetchSalaryData();
    }
  }

  @override
  void didUpdateWidget(SalaryOverviewScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Full refresh when user opens the salary tab (clear attendance caches + refetch).
    if (widget.isActiveTab == true && oldWidget.isActiveTab != true) {
      _onSalaryTabBecameVisible();
    }
  }

  void _onSalaryTabBecameVisible() {
    _attendanceService.clearCachesForRefresh();
    if (_isFetching) {
      _pendingTabVisibleRefresh = true;
      return;
    }
    _fetchSalaryData();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _refreshSalaryWhenAppResumes = widget.isActiveTab == true;
    } else if (state == AppLifecycleState.resumed) {
      final shouldRefresh =
          _refreshSalaryWhenAppResumes && widget.isActiveTab == true;
      _refreshSalaryWhenAppResumes = false;
      if (shouldRefresh) _onSalaryTabBecameVisible();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _attendanceEventSub.cancel();
    _debounceTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchSalaryData({bool debounce = false}) async {
    // Prevent concurrent fetches
    if (_isFetching) {
      return;
    }

    // Debounce rapid calls (e.g., from event bus + dropdown changes)
    if (debounce) {
      _debounceTimer?.cancel();
      _debounceTimer = Timer(const Duration(milliseconds: 500), () {
        _fetchSalaryData(debounce: false);
      });
      return;
    }

    // Set fetching flag immediately to prevent concurrent calls
    _isFetching = true;
    _unpaidLeaveDeduction = 0;
    _staffId = null;
    _salaryDetailsAccessEnabled = false;
    _allowCurrentCycleSalaryAccess = false;
    _payrollPreview = null;
    if (mounted) {
      setState(() {
        _isLoading = true;
        _error = '';
        _salaryAccessDenied = false;
      });
    }

    // Fetch company payslip setting (company.settings.payroll.payslip.isPayslipAutoGenerated)
    try {
      final fcResult = await _attendanceService
          .getFineCalculation()
          .timeout(_networkTimeout);
      if (fcResult['success'] == true && mounted) {
        final payslip = fcResult['payslip'];
        setState(() {
          _isPayslipAutoGenerated =
              payslip is Map && (payslip['isPayslipAutoGenerated'] == true);
        });
      }
    } catch (_) {}

    if (!mounted) return;

    try {
      Map<String, dynamic>? profileData;
      Map<String, dynamic>? staffData;
      try {
        final profileResult = await _authService
            .getProfile()
            .timeout(_networkTimeout);
        if (profileResult['success'] == true && profileResult['data'] is Map) {
          profileData = Map<String, dynamic>.from(profileResult['data'] as Map);
          final dynamic rawStaffData = profileData['staffData'];
          if (rawStaffData is Map) {
            staffData = Map<String, dynamic>.from(rawStaffData);
          }

          _clampSelectedFiltersToAllowed();
          if (staffData != null) {
            _staffId = staffData['_id']?.toString();
            _salaryDetailsAccessEnabled =
                staffData['salaryDetailsAccessEnabled'] == true;
            _allowCurrentCycleSalaryAccess =
                staffData['allowCurrentCycleSalaryAccess'] == true;
            debugPrint(
              '[SalaryOverview] profile staffId=$_staffId salaryDetailsAccess=$_salaryDetailsAccessEnabled '
              'allowCurrentCycle=$_allowCurrentCycleSalaryAccess',
            );
          }
        }
      } catch (_) {}

      int monthIndex = _months.indexOf(_selectedMonth) + 1;
      int year = int.parse(_selectedYear);

      if (staffData != null && !_salaryDetailsAccessEnabled) {
        _salaryAccessDenied = true;
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
        _isFetching = false;
        return;
      }

      _calculatedSalary = null;
      if (staffData != null &&
          staffData['salary'] != null &&
          staffData['salary'] is Map) {
        _resolveCalculatedSalaryFromStaff(
          Map<String, dynamic>.from(staffData['salary'] as Map),
        );
        debugPrint(
          '[SalaryOverview] salary from profile: hasStructure=${_calculatedSalary != null}',
        );
      }

      // Past month: no calculation – use payroll for that month/year or show 0.00
      if (!_isCurrentMonth(monthIndex, year)) {
        _pastMonthPayroll = null;
        _currentPayroll = null;
        _proratedSalary = null;
        _workingDaysInfo = null;
        _backendThisMonthNet = null;
        _backendThisMonthGross = null;
        _backendEarnings = [];
        _backendDeductionComponents = [];
        _backendDeductionsTotal = 0.0;
        _presentDays = 0;
        _paidLeaveDays = 0;
        _fullDayPresentCount = 0;
        _halfDayPresentCount = 0;
        _webPresentDays = 0.0;
        _webPaidLeaves = 0.0;
        _webUnpaidLeaves = 0.0;
        _webLeaveTypeBreakdown = {};
        _attendanceRecords = [];
        _holidays = [];
        _presentDates = {};
        _absentDates = {};
        _holidayDates = {};
        _weekOffDates = {};
        _leaveDates = {};
        _dailyFineAmounts = {};
        _fineInfo = {
          'totalFineAmount': 0.0,
          'lateDays': 0,
          'totalLateMinutes': 0,
        };
        try {
          final payrollData = await _salaryService
              .getPayrolls(
                month: monthIndex,
                year: year,
                page: 1,
                limit: 1,
              )
              .timeout(_networkTimeout);
          if (payrollData['success'] == true && payrollData['data'] != null) {
            final payrolls = payrollData['data']['payrolls'] as List?;
            if (payrolls != null && payrolls.isNotEmpty) {
              _pastMonthPayroll = payrolls.first as Map<String, dynamic>;
              _currentPayroll = _pastMonthPayroll;
            }
          }
        } catch (_) {}
        if (_pastMonthPayroll == null) {
          await _tryFetchPayrollPreview(monthIndex, year);
        }
        await _loadPayrollHistory();
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      // Current month: clear past-month state and run full calculation
      _pastMonthPayroll = null;

      if (_isCurrentMonth(monthIndex, year) && !_allowCurrentCycleSalaryAccess) {
        debugPrint(
          '[SalaryOverview] current cycle blocked (web parity) — skip attendance/holidays/stats/MTD payroll',
        );
        _currentPayroll = null;
        _proratedSalary = null;
        _workingDaysInfo = null;
        _backendThisMonthNet = null;
        _backendThisMonthGross = null;
        _backendEarnings = [];
        _backendDeductionComponents = [];
        _backendDeductionsTotal = 0.0;
        _presentDays = 0;
        _paidLeaveDays = 0;
        _fullDayPresentCount = 0;
        _halfDayPresentCount = 0;
        _webPresentDays = 0.0;
        _webPaidLeaves = 0.0;
        _webUnpaidLeaves = 0.0;
        _webLeaveTypeBreakdown = {};
        _attendanceRecords = [];
        _holidays = [];
        _presentDates = {};
        _absentDates = {};
        _holidayDates = {};
        _weekOffDates = {};
        _leaveDates = {};
        _dailyFineAmounts = {};
        _fineInfo = {
          'totalFineAmount': 0.0,
          'lateDays': 0,
          'totalLateMinutes': 0,
        };
        _unpaidLeaveDeduction = 0;
        if (staffData != null &&
            staffData['salary'] != null &&
            staffData['salary'] is Map) {
          _resolveCalculatedSalaryFromStaff(
            Map<String, dynamic>.from(staffData['salary'] as Map),
          );
        }
        await _loadPayrollHistory();
        if (mounted) {
          setState(() => _isLoading = false);
        }
        _isFetching = false;
        return;
      }

      // 1. Fetch staff profile to get salary structure
      if (profileData == null) {
        throw Exception('Failed to fetch profile');
      }
      if (staffData == null || staffData['salary'] == null) {
        throw Exception(
          'No salary structure found. Please contact HR to set up your salary structure.',
        );
      }
      if (staffData['salary'] is! Map) {
        throw Exception(
          'No salary structure found. Please contact HR to set up your salary structure.',
        );
      }
      _resolveCalculatedSalaryFromStaff(
        Map<String, dynamic>.from(staffData['salary'] as Map),
      );
      if (_calculatedSalary == null) {
        throw Exception(
          'Salary structure not found. Please contact HR to set up your salary structure.',
        );
      }

      // Get weekly off: staff's WeeklyHolidayTemplate when assigned, else business (Company.settings.business)
      Map<String, dynamic>? businessSettings;
      if (staffData['branchId'] != null &&
          staffData['branchId'] is Map &&
          staffData['branchId']['businessId'] != null) {
        if (staffData['branchId']['businessId'] is Map) {
          businessSettings = staffData['branchId']['businessId'];
        }
      } else if (staffData['businessId'] != null &&
          staffData['businessId'] is Map) {
        businessSettings = staffData['businessId'];
      }

      final weeklyHolidayTemplate = staffData['weeklyHolidayTemplateId'];
      final hasTemplate =
          weeklyHolidayTemplate is Map<String, dynamic> &&
          (weeklyHolidayTemplate['settings'] != null) &&
          (weeklyHolidayTemplate['isActive'] != false);
      if (hasTemplate) {
        final template = weeklyHolidayTemplate;
        final s = template['settings'] as Map<String, dynamic>? ?? {};
        _weeklyOffPattern = (s['weeklyOffPattern'] is String)
            ? s['weeklyOffPattern'] as String
            : 'standard';
        if (s['weeklyHolidays'] != null && s['weeklyHolidays'] is List) {
          final weeklyHolidaysList = s['weeklyHolidays'] as List;
          _weeklyHolidays = weeklyHolidaysList
              .map((h) {
                if (h is Map) {
                  return _parseWeeklyHolidayDay(h['day']) ?? -1;
                }
                return _parseWeeklyHolidayDay(h) ?? -1;
              })
              .where((day) => day >= 0 && day <= 6)
              .toList();
        } else {
          _weeklyHolidays = [];
        }
      } else {
        // Web: `useGetBusinessQuery` — prefer live `GET /settings/business`, else nested staff company doc.
        Map<String, dynamic>? companyDoc = businessSettings;
        try {
          final gb = await _settingsService
              .getBusiness()
              .timeout(_networkTimeout);
          if (gb['success'] == true && gb['data'] is Map<String, dynamic>) {
            final data = gb['data'] as Map<String, dynamic>;
            final b = data['business'];
            if (b is Map) {
              companyDoc = Map<String, dynamic>.from(b as Map);
            }
          }
        } catch (_) {}
        if (companyDoc != null &&
            companyDoc['settings'] != null &&
            companyDoc['settings']['business'] != null) {
          final business =
              companyDoc['settings']['business'] as Map<String, dynamic>;
          final weeklyOffPatternValue = business['weeklyOffPattern'];
          _weeklyOffPattern =
              (weeklyOffPatternValue != null && weeklyOffPatternValue is String)
              ? weeklyOffPatternValue
              : 'standard';

          if (business['weeklyHolidays'] != null &&
              business['weeklyHolidays'] is List) {
            final weeklyHolidaysList = business['weeklyHolidays'] as List;
            _weeklyHolidays = weeklyHolidaysList
                .map((h) {
                  if (h is Map) {
                    return _parseWeeklyHolidayDay(h['day']) ?? -1;
                  }
                  return _parseWeeklyHolidayDay(h) ?? -1;
                })
                .where((day) => day >= 0 && day <= 6)
                .toList();
          } else {
            _weeklyHolidays = [];
          }
        } else {
          _weeklyOffPattern = 'standard';
          _weeklyHolidays = [];
        }
      }

      // 2. Fetch payroll stats from backend (has correct working days calculation)
      Map<String, dynamic>? backendStats;
      try {
        final statsResult = await _salaryService
            .getSalaryStats(month: monthIndex, year: year)
            .timeout(_networkTimeout);
        final stats = statsResult['stats'] as Map<String, dynamic>?;
        if (stats != null) {
          backendStats = stats;
          // Use backend's thisMonthNet/thisMonthGross when available so display matches payslip
          final net = stats['thisMonthNet'];
          _backendThisMonthNet = (net is num) ? net.toDouble() : null;
          final gross = stats['thisMonthGross'];
          _backendThisMonthGross = (gross is num) ? gross.toDouble() : null;
          final earningsRaw = stats['earnings'];
          _backendEarnings = earningsRaw is List
              ? earningsRaw
                    .whereType<Map>()
                    .map((e) => Map<String, dynamic>.from(e))
                    .toList()
              : [];
          final deductionsRaw = stats['deductionComponents'];
          _backendDeductionComponents = deductionsRaw is List
              ? deductionsRaw
                    .whereType<Map>()
                    .map((e) => Map<String, dynamic>.from(e))
                    .toList()
              : [];
          _backendDeductionsTotal = (stats['deductions'] as num?)?.toDouble() ?? 0.0;
          debugPrint(
            '[SalaryCalc] /payroll/stats: thisMonthGross=$_backendThisMonthGross thisMonthNet=$_backendThisMonthNet '
            'earnings=${_backendEarnings.map((e) => '${e['name']}:${e['amount']}').join('|')}',
          );
        } else {
          _backendThisMonthNet = null;
          _backendThisMonthGross = null;
          _backendEarnings = [];
          _backendDeductionComponents = [];
          _backendDeductionsTotal = 0.0;
        }
      } catch (e) {
        _backendThisMonthNet = null;
        _backendThisMonthGross = null;
        _backendEarnings = [];
        _backendDeductionComponents = [];
        _backendDeductionsTotal = 0.0;
      }

      // 3. Fetch attendance for the month
      // Keep previous values in case new fetch fails, so UI doesn't jump to 0
      final prevAttendanceRecords = List<dynamic>.from(_attendanceRecords);
      final prevPresentDays = _presentDays;
      final prevProratedSalary = _proratedSalary;
      bool attendanceUpdated = false;

      // Add a small delay on first load to avoid immediate rate limiting
      // when multiple screens load simultaneously
      if (_attendanceRecords.isEmpty && prevAttendanceRecords.isEmpty) {
        await Future.delayed(const Duration(milliseconds: 300));
      }

      // Web parity: rows from GET /attendance/employee/:id?startDate&endDate (Attendance collection),
      // same range as web (month start → today for current month, else full month).
      final monthStart = DateTime(year, monthIndex, 1);
      final monthEnd = DateTime(year, monthIndex + 1, 0);
      final todayNav = DateTime.now();
      final todayOnly = DateTime(todayNav.year, todayNav.month, todayNav.day);
      final attendanceEndDate = _isCurrentMonth(monthIndex, year)
          ? todayOnly
          : monthEnd;
      final startDateStr = DateFormat('yyyy-MM-dd').format(monthStart);
      final endDateStr = DateFormat('yyyy-MM-dd').format(attendanceEndDate);

      if (_staffId != null && _staffId!.isNotEmpty) {
        try {
          final employeeResult = await _attendanceService
              .getEmployeeAttendance(
                employeeId: _staffId!,
                startDate: startDateStr,
                endDate: endDateStr,
                page: 1,
                limit: 100,
              )
              .timeout(_networkTimeout);
          debugPrint(
            '[SalaryOverview] GET attendance/employee start=$startDateStr end=$endDateStr '
            'success=${employeeResult['success']}',
          );
          if (employeeResult['success'] == true &&
              employeeResult['data'] is Map) {
            final empData = employeeResult['data'] as Map<String, dynamic>;
            final empList = empData['attendance'];
            if (empList is List && empList.isNotEmpty) {
              final list = List<dynamic>.from(empList);
              final deduped = _dedupeAttendanceRecordsByCalendarDay(list);
              if (kDebugMode && deduped.length != list.length) {
                debugPrint(
                  '[SalaryCalendar] deduped duplicate calendar days: ${list.length} rows -> ${deduped.length}',
                );
              }
              _attendanceRecords = deduped;
              attendanceUpdated = true;
            }
          }
        } catch (e) {
          debugPrint('[SalaryOverview] employee attendance fetch error: $e');
        }
      }

      // Month endpoint: calendar sets (weekOffDates, server date sets) and stats fallback.
      Map<String, dynamic> attendanceResult = {'success': false};
      try {
        attendanceResult = await _attendanceService
            .getMonthAttendance(year, monthIndex)
            .timeout(_networkTimeout);
      } catch (e) {
        debugPrint('[SalaryOverview] month attendance fetch error: $e');
      }
      debugPrint(
        '[SalaryOverview] GET attendance/month year=$year month=$monthIndex '
        'success=${attendanceResult['success']}',
      );

      if (attendanceResult['success'] == true) {
        final attendanceData = attendanceResult['data'];
        final fetchedRecords = attendanceData is Map
            ? (attendanceData['attendance'] ?? [])
            : [];

        // Prefer range-based employee rows (web); else month payload.
        if (!attendanceUpdated && fetchedRecords.isNotEmpty) {
          final list = List<dynamic>.from(fetchedRecords);
          final deduped = _dedupeAttendanceRecordsByCalendarDay(list);
          if (kDebugMode && deduped.length != list.length) {
            debugPrint(
              '[SalaryCalendar] deduped duplicate calendar days: ${list.length} rows -> ${deduped.length}',
            );
          }
          _attendanceRecords = deduped;
          attendanceUpdated = true;
        }

        // Extract holidays from attendance data (even if records are empty)
        if (attendanceData is Map && attendanceData['holidays'] != null) {
          _holidays = (attendanceData['holidays'] as List)
              .map((h) {
                try {
                  if (h is! Map) return null;
                  final k = normalizeAttendanceDateKeyForSalary(h['date']);
                  if (k == null) return null;
                  return DateTime.parse('${k}T12:00:00.000Z');
                } catch (_) {
                  return null;
                }
              })
              .whereType<DateTime>()
              .toList();
        }
        // Web parity: holidays come from holidays employee endpoint.
        try {
          final holidaysResult = await _holidayService
              .getHolidays(year: year, month: monthIndex)
              .timeout(_networkTimeout);
          if (holidaysResult['success'] == true && holidaysResult['data'] is List) {
            final list = holidaysResult['data'] as List;
            final apiHolidays = list.whereType<Holiday>().toList();
            if (apiHolidays.isNotEmpty) {
              _holidays = apiHolidays.map((h) => h.date).toList();
            }
          }
        } catch (_) {}
        if (attendanceData is Map && attendanceData['weekOffDates'] != null) {
          _weekOffDates = (attendanceData['weekOffDates'] as List)
              .map((e) => _normalizeDateKey(e))
              .whereType<String>()
              .toSet();
        }
        if (attendanceData['presentDates'] != null) {
          _presentDates = (attendanceData['presentDates'] as List)
              .map((e) => _normalizeDateKey(e))
              .whereType<String>()
              .toSet();
        }
        if (attendanceData['absentDates'] != null) {
          _absentDates = (attendanceData['absentDates'] as List)
              .map((e) => _normalizeDateKey(e))
              .whereType<String>()
              .toSet();
        }
        if (attendanceData['holidayDates'] != null) {
          _holidayDates = (attendanceData['holidayDates'] as List)
              .map((e) => _normalizeDateKey(e))
              .whereType<String>()
              .toSet();
        }
        if (attendanceData is Map && attendanceData['leaveDates'] != null) {
          _leaveDates = (attendanceData['leaveDates'] as List)
              .map((e) => _normalizeDateKey(e))
              .whereType<String>()
              .toSet();
        }
        _debugLogSalaryCalendarPayload(year: year, monthIndex: monthIndex);
      } else {
        // API call failed (rate limit, network error, etc.) - keep existing data
        // The service should have returned cached data if available, but if not,
        // we preserve what we have
      }

      // 4. Present / paid leave: match web `EmployeeSalaryOverview` — primary source is the
      // attendance record reducer in [_computeWebAttendanceBreakdown] (incl. halfDaySession,
      // Pending half-day). Do **not** use `/payroll/stats` attendance.presentDays here — it
      // disagrees with month/employee rows (e.g. 14 vs 15.5). Prefer `/attendance/month`
      // stats only when they exist and supplement breakdown.
      _computeWebAttendanceBreakdown();
      // Headline present = web-style reducer on rows (same as web `presentDays`).
      _presentDays = _webPresentDays;
      _paidLeaveDays = _webPaidLeaves;
      if (attendanceResult['success'] == true &&
          attendanceResult['data'] != null) {
        final data = attendanceResult['data'] as Map<String, dynamic>;
        final stats = data['stats'] as Map<String, dynamic>?;
        final fromStats = (stats?['presentDays'] as num?)?.toDouble();
        final paidLeaveFromStats = (stats?['paidLeaveDays'] as num?)?.toDouble();
        // Month stats paid leave — do not overwrite with 0 when rows show paid leave (e.g. week-off paid).
        if (paidLeaveFromStats != null &&
            paidLeaveFromStats >= 0 &&
            (paidLeaveFromStats > 0 || _webPaidLeaves <= 0.001)) {
          _paidLeaveDays = paidLeaveFromStats;
        }
        if (fromStats != null &&
            fromStats >= 0 &&
            (fromStats - _webPresentDays).abs() <= 0.01) {
          // Only align when server agrees with client (avoids forcing 14 vs 16.5 drift).
          _presentDays = fromStats;
        }
      }
      // Restore previous data on failed fetch when we had data before
      if (!attendanceUpdated &&
          _attendanceRecords.isEmpty &&
          (prevAttendanceRecords.isNotEmpty || prevPresentDays > 0)) {
        _attendanceRecords
          ..clear()
          ..addAll(prevAttendanceRecords);
        if (prevProratedSalary != null) {
          _proratedSalary = prevProratedSalary;
        }
        _computeWebAttendanceBreakdown();
        _presentDays = _webPresentDays;
        _paidLeaveDays = _webPaidLeaves;
      } else if (!attendanceUpdated && _attendanceRecords.isEmpty) {
        _presentDays = 0;
        _paidLeaveDays = 0;
        _computeWebAttendanceBreakdown();
      }
      // Keep [_webPresentDays] as present-only from rows (web proration numerator). Do not
      // replace with [_presentDays] after optional stats tweak — proration uses _webPresentDays.
      _clientPresentDaysBeforeSync = _webPresentDays;

      // 4a. Working days/holidays for display (match web frontend behavior)
      // Web computes current-month working days and holidays till today, and full-month separately.
      _halfDayPaidLeaveCount = 0;
      _leaveDays = 0;
      final now = DateTime.now();
      final endDateForCurrentMonth = _isCurrentMonth(monthIndex, year)
          ? DateTime(now.year, now.month, now.day)
          : null;
      final webTillDateInfo = calculateWorkingDays(
        year,
        monthIndex,
        _holidays,
        _weeklyOffPattern,
        _weeklyHolidays,
        endDateForCurrentMonth,
      );
      final webFullMonthInfo = calculateWorkingDays(
        year,
        monthIndex,
        _holidays,
        _weeklyOffPattern,
        _weeklyHolidays,
      );

      // Web uses client `calculateWorkingDays` only (not /attendance/month stats).
      final int displayWorkingDays = webTillDateInfo.workingDays;
      final int displayWeekends = webTillDateInfo.weekends;
      final int displayHolidayCount = webTillDateInfo.holidayCount;

      _workingDaysInfo = WorkingDaysInfo(
        totalDays: webTillDateInfo.totalDays,
        workingDays: displayWorkingDays,
        weekends: displayWeekends,
        holidayCount: displayHolidayCount,
        workingDaysFullMonth: webFullMonthInfo.workingDays,
      );
      String? userEmailForLog;
      final prof = profileData['profile'];
      if (prof is Map<String, dynamic>) {
        userEmailForLog = prof['email']?.toString();
      }
      userEmailForLog ??= profileData['email']?.toString();
      _logSalaryDayCounts(
        year: year,
        monthIndex: monthIndex,
        attendanceResult: attendanceResult,
        displayWorkingDays: displayWorkingDays,
        fullMonthWorkingDays: webFullMonthInfo.workingDays,
        userEmail: userEmailForLog,
      );
      debugPrint(
        '[SalaryCalc] working days: tillDate=$displayWorkingDays fullMonth=${webFullMonthInfo.workingDays} '
        '(local calc till=${webTillDateInfo.workingDays}) holidaysMonth=${webFullMonthInfo.holidayCount}',
      );

      // Leave counters: `/payroll/stats` attendance often omits paid week-off leave — do not clobber [_paidLeaveDays].
      if (backendStats != null && backendStats['attendance'] != null) {
        final backendAttendance =
            backendStats['attendance'] as Map<String, dynamic>;
        _halfDayPaidLeaveCount =
            (backendAttendance['halfDayPaidLeaveCount'] as num?)?.toInt() ?? 0;
        _leaveDays =
            (backendAttendance['leaveDays'] as num?)?.toDouble() ?? 0.0;
      } else if (attendanceResult['success'] == true &&
          attendanceResult['data'] != null) {
        final data = attendanceResult['data'] as Map<String, dynamic>;
        final stats = data['stats'] as Map<String, dynamic>?;
        _halfDayPaidLeaveCount = (stats?['halfDayPaidLeaveCount'] as num?)?.toInt() ?? 0;
        _leaveDays = (stats?['leaveDays'] as num?)?.toDouble() ?? 0.0;
      }

      // 4b. Salary structure (BEFORE fine so dailySalary can use current run)
      if (_staffSalary != null && _staffSalary!['basicSalary'] != null) {
        final salaryInputs = SalaryStructureInputs.fromMap(_staffSalary!);
        _calculatedSalary = calculateSalaryStructure(salaryInputs);
        final m = _calculatedSalary!.monthly;
        debugPrint(
          '[SalaryCalc] structure from staff API: rawBasic=${_staffSalary!['basicSalary']} rawDA=${_staffSalary!['dearnessAllowance']} rawHRA=${_staffSalary!['houseRentAllowance']} '
          '=> monthly basic=${m.basicSalary} da=${m.dearnessAllowance} hra=${m.houseRentAllowance} '
          'grossFixed=${m.grossFixedSalary} gross=${m.grossSalary} net=${m.netMonthlySalary} empDed=${m.totalMonthlyDeductions}',
        );
      } else {
        debugPrint(
          '[SalaryCalc] skip calculateSalaryStructure: staffSalary=${_staffSalary != null} basic=${_staffSalary?['basicSalary']}',
        );
      }

      // Calculate fine information using grace time logic
      // Get shift timing from business settings based on staff's shiftName
      final staffShiftName = staffData['shiftName'] as String?;

      // Create shift timing from business settings (priority: shift-specific grace time)
      ShiftTiming? shiftTiming;
      if (businessSettings != null && staffShiftName != null) {
        shiftTiming = createShiftTimingFromBusinessSettings(
          businessSettings,
          staffShiftName,
        );
      }

      // Fallback: Try to get from attendance template if shift not found in business settings
      if (shiftTiming == null) {
        Map<String, dynamic>? attendanceTemplate;
        try {
          final todayAttendance = await _attendanceService
              .getTodayAttendance()
              .timeout(_networkTimeout);
          if (todayAttendance['success'] == true &&
              todayAttendance['data'] != null) {
            attendanceTemplate =
                todayAttendance['data']['template'] as Map<String, dynamic>?;
          }
        } catch (e) {
          // Ignore errors
        }
        shiftTiming = createShiftTimingFromTemplate(attendanceTemplate);
      }

      // Create fine settings from business settings
      final fineSettings = createFineSettingsFromBusinessSettings(
        businessSettings,
      );

      // Daily salary = Monthly NET salary / This month working days (1 day salary = net/this month WD)
      double? dailySalary;
      if (_staffSalary != null &&
          _calculatedSalary != null &&
          _workingDaysInfo != null) {
        final thisMonthWorkingDays =
            _workingDaysInfo!.workingDaysFullMonth ??
            _workingDaysInfo!.workingDays;
        if (thisMonthWorkingDays > 0) {
          dailySalary =
              _calculatedSalary!.monthly.netMonthlySalary /
              thisMonthWorkingDays;
          if (kDebugMode) {
            final netM = _calculatedSalary!.monthly.netMonthlySalary;
            final grossM = _calculatedSalary!.monthly.grossSalary;
            final perGross = grossM / thisMonthWorkingDays;
            debugPrint(
              '[SalaryPerDay] month=$monthIndex year=$year '
              'workingDaysFullMonth=$thisMonthWorkingDays '
              'netMonthly=${netM.toStringAsFixed(2)} '
              'perDayNet=${dailySalary!.toStringAsFixed(4)} '
              '(netMonthly / workingDaysFullMonth) '
              'grossMonthly=${grossM.toStringAsFixed(2)} '
              'perDayGross=${perGross.toStringAsFixed(4)} '
              '(grossMonthly / workingDaysFullMonth) — daily rows use perDayNet before fines',
            );
          }
        }
      }

      // Shift hours for calculatePayrollFine (same as dashboard)
      double shiftHours = 9.0;
      if (shiftTiming != null) {
        shiftHours = calculateShiftHours(
          shiftTiming.startTime,
          shiftTiming.endTime,
        );
      } else {
        try {
          final todayAttendance = await _attendanceService
              .getTodayAttendance()
              .timeout(_networkTimeout);
          if (todayAttendance['success'] == true &&
              todayAttendance['data'] != null) {
            final template =
                todayAttendance['data']['template'] as Map<String, dynamic>?;
            if (template != null) {
              final startTime =
                  template['shiftStartTime'] as String? ?? '09:30';
              final endTime = template['shiftEndTime'] as String? ?? '18:30';
              shiftHours = calculateShiftHours(startTime, endTime);
            }
          }
        } catch (e) {
          // Ignore
        }
      }

      // Fine totals: central utility (web calculateTotalFine parity).
      final fineSummary = aggregateSalaryFineSummary(_attendanceRecords);
      final double finalTotalFineAmount = fineSummary.totalFineAmount;

      // Do NOT use backend deductionComponents for late login fine - backend may include
      // fines from Absent/Pending; month rows here should already be the right set.
      _fineInfo = fineSummary.toLegacyFineInfoMap();
      _dailyFineAmounts = Map<String, double>.from(fineSummary.dailyFineByDateKey);

      // 5. Client proration (web `calculateProratedSalary`): numerator = present-only
      // (`presentDays` reducer), denominator = full-month working days.
      if (_calculatedSalary != null && _workingDaysInfo != null) {
        final thisMonthWorkingDays =
            _workingDaysInfo!.workingDaysFullMonth ??
            _workingDaysInfo!.workingDays;
        if (thisMonthWorkingDays > 0) {
          final presentDaysForProration = _webPresentDays;
          _proratedSalary = calculateProratedSalary(
            _calculatedSalary!,
            thisMonthWorkingDays,
            presentDaysForProration,
            finalTotalFineAmount,
          );
          final perDayNetForLog =
              _calculatedSalary!.monthly.netMonthlySalary / thisMonthWorkingDays;
          final perDayGrossForLog =
              _calculatedSalary!.monthly.grossSalary / thisMonthWorkingDays;
          debugPrint(
            '[SalaryCalc] prorated state: wdm=$thisMonthWorkingDays present=$_webPresentDays paidLeaveWeb=$_webPaidLeaves '
            'presentForProration=$presentDaysForProration fine=$finalTotalFineAmount '
            'perDayNet=${perDayNetForLog.toStringAsFixed(4)} perDayGross=${perDayGrossForLog.toStringAsFixed(4)} '
            'monthlyGross=${_calculatedSalary!.monthly.grossSalary} monthlyDed=${_calculatedSalary!.monthly.totalMonthlyDeductions} '
            '=> mtdGross=${_proratedSalary?.proratedGrossSalary} mtdNet=${_proratedSalary?.proratedNetSalary}',
          );
        } else {
          debugPrint(
            '[SalaryCalc] prorated SKIPPED: thisMonthWorkingDays=$thisMonthWorkingDays (<=0) — breakdown may recompute in build',
          );
        }
      } else {
        debugPrint(
          '[SalaryCalc] prorated SKIPPED: calculated=${_calculatedSalary != null} workingDaysInfo=${_workingDaysInfo != null}',
        );
      }

      // Web EmployeeSalaryOverview: deduct unpaid leave from prorated net (daily net × unpaid days).
      if (_proratedSalary != null &&
          _calculatedSalary != null &&
          _workingDaysInfo != null) {
        final wdm =
            _workingDaysInfo!.workingDaysFullMonth ??
            _workingDaysInfo!.workingDays;
        if (wdm > 0 && _webUnpaidLeaves > 0) {
          final dailyNet =
              _calculatedSalary!.monthly.netMonthlySalary / wdm;
          _unpaidLeaveDeduction = dailyNet * _webUnpaidLeaves;
          final p = _proratedSalary!;
          _proratedSalary = ProratedSalary(
            proratedGrossSalary: p.proratedGrossSalary,
            proratedDeductions: p.proratedDeductions,
            fineAmount: p.fineAmount,
            totalDeductions: p.totalDeductions + _unpaidLeaveDeduction,
            proratedNetSalary: math.max(
              0,
              p.proratedNetSalary - _unpaidLeaveDeduction,
            ),
            attendancePercentage: p.attendancePercentage,
          );
          debugPrint(
            '[SalaryOverview] unpaid leave: days=${_webUnpaidLeaves.toStringAsFixed(2)} '
            'deduction=${_unpaidLeaveDeduction.toStringAsFixed(2)} mtdNet=${_proratedSalary!.proratedNetSalary.toStringAsFixed(2)}',
          );
        }
      }

      // 8. Fetch payroll for selected month/year (web: useGetPayrollsQuery month+year limit 1)
      try {
        final payrollData = await _salaryService
            .getPayrolls(month: monthIndex, year: year, page: 1, limit: 1)
            .timeout(_networkTimeout);
        debugPrint(
          '[SalaryOverview] payroll list month=$monthIndex year=$year success=${payrollData['success']}',
        );
        if (payrollData['success'] == true && payrollData['data'] != null) {
          final payrolls = payrollData['data']['payrolls'] as List?;
          if (payrolls != null && payrolls.isNotEmpty) {
            final payroll = payrolls.first;
            final payrollMonth = payroll['month'];
            final payrollYear = payroll['year'];
            if (payrollMonth == monthIndex && payrollYear == year) {
              _currentPayroll = payroll;
              debugPrint(
                '[SalaryOverview] matched payroll id=${payroll['_id']} status=${payroll['status']} '
                'gross=${payroll['grossSalary']} net=${payroll['netPay']}',
              );
            }
          }
        }
      } catch (e) {
        debugPrint('[SalaryOverview] payroll fetch error: $e');
      }

      if (_currentPayroll == null) {
        await _tryFetchPayrollPreview(monthIndex, year);
      }
      if (kDebugMode && _payrollPreview != null) {
        final a = _payrollPreview!['attendance'];
        if (a is Map) {
          debugPrint(
            '[SalaryDayCounts] after payroll preview: presentDays=${a['presentDays']} '
            'workingDaysTill=${a['workingDaysTillCurrentDate'] ?? a['workingDays']} '
            'attendancePct=${a['attendancePercentage']}',
          );
        }
      }

      await _loadPayrollHistory();

      if (mounted) {
        setState(() {
          _shiftStartTime = shiftTiming?.startTime;
          _shiftEndTime = shiftTiming?.endTime;
          _isLoading = false;
        });
      }
    } catch (e) {
      // Extract a user-friendly error message
      String errorMessage = 'Your salary not updated';
      if (e is Exception) {
        final errorStr = e.toString();
        if (errorStr.contains('Exception: ')) {
          errorMessage = errorStr.replaceFirst('Exception: ', '');
        } else {
          errorMessage = errorStr;
        }
      } else {
        errorMessage = e.toString();
      }

      if (mounted) {
        setState(() {
          _error = errorMessage;
          _isLoading = false;
        });
      }
    } finally {
      _isFetching = false;
      if (_pendingTabVisibleRefresh && mounted) {
        _pendingTabVisibleRefresh = false;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _onSalaryTabBecameVisible();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: const MenuIconButton(),
        title: const Text(
          'Salary Overview',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        actions: [
          if (_currentPayroll != null &&
              (_currentPayroll!['status'] == 'Processed' ||
                  _currentPayroll!['status'] == 'Paid'))
            Container(
              margin: const EdgeInsets.only(right: 16),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.success.withOpacity(0.2),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.success),
              ),
              child: Text(
                'Processed',
                style: TextStyle(
                  color: AppColors.success,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
      drawer: AppDrawer(
        currentIndex: widget.dashboardTabIndex ?? 2,
        onNavigateToIndex: widget.onNavigateToIndex,
      ),
      body: _isLoading
          ? const Center(child: AppTabLoader())
          : _salaryAccessDenied
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.lock_outline,
                      size: 64,
                      color: Colors.grey.shade500,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Salary overview access is disabled for your profile.',
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Please contact HR.',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 13,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          : _error.isNotEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 64,
                      color: Colors.grey.shade500,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _error,
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: _fetchSalaryData,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 32,
                          vertical: 12,
                        ),
                      ),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
          : _calculatedSalary == null &&
                _proratedSalary == null &&
                _isSelectedCurrentMonth &&
                !_isCurrentCycleBlocked
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 64,
                      color: Colors.grey.shade500,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Your salary not updated',
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Please contact HR to set up your salary structure.',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: _fetchSalaryData,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 32,
                          vertical: 12,
                        ),
                      ),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Month/Year Filter (only previous months and non-future years)
                  Row(
                    children: [
                      Expanded(
                        child: _buildDropdown(
                          _months.contains(_selectedMonth)
                              ? _selectedMonth
                              : _months[DateTime.now().month - 1],
                          _months,
                          (val) {
                            if (val != null && _months.contains(val)) {
                              setState(() {
                                _selectedMonth = val;
                                _isLoading = true;
                                _error = '';
                              });
                              _fetchSalaryData(debounce: true);
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildDropdown(
                          _pickerYears.contains(_selectedYear)
                              ? _selectedYear
                              : '${DateTime.now().year}',
                          _pickerYears,
                          (val) {
                            if (val != null) {
                              setState(() {
                                _selectedYear = val;
                                _clampSelectedFiltersToAllowed();
                                _isLoading = true;
                                _error = '';
                              });
                              _fetchSalaryData(debounce: true);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // Download Payslip: only when isPayslipAutoGenerated and payroll has payslipUrl
                  if (_isPayslipAutoGenerated) ...[
                    _buildDownloadPayslipButton(),
                    const SizedBox(height: 10),
                  ],
                  if (_isCurrentCycleBlocked) ...[
                    Card(
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Text(
                          'Current month salary cycle is restricted for your profile. '
                          'Previous month payroll history is still available below.',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  _buildSummaryCards(),
                  const SizedBox(height: 10),
                  if (_isSelectedCurrentMonth && !_isCurrentCycleBlocked) ...[
                    _buildAttendanceSummary(),
                    const SizedBox(height: 10),
                    _buildAttendanceCalendarOverview(),
                    const SizedBox(height: 10),
                    _buildSalaryComponentBreakdown(),
                    const SizedBox(height: 10),
                    _buildDailyBreakdownOverview(),
                  ] else ...[
                    _buildSalaryComponentBreakdown(),
                    const SizedBox(height: 10),
                    if (!_isSelectedCurrentMonth) _buildPastMonthAttendancePlaceholder(),
                  ],
                  if (_calculatedSalary != null &&
                      (_payrollHistoryLoading ||
                          _visiblePayrollHistory.isNotEmpty)) ...[
                    const SizedBox(height: 10),
                    _buildPayrollHistoryCard(),
                  ],
                ],
              ),
            ),
    );
  }

  /// View / Download payslip (web parity): try payroll id PDF endpoints, then `payslipUrl`.
  Widget _buildDownloadPayslipButton() {
    final payroll = _pastMonthPayroll ?? _currentPayroll;
    if (payroll == null) {
      return OutlinedButton.icon(
        onPressed: null,
        icon: const Icon(Icons.download, size: 20),
        label: const Text('Payslip not available'),
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.grey,
          side: const BorderSide(color: Colors.grey),
        ),
      );
    }
    final url = payroll['payslipUrl']?.toString().trim() ?? '';
    final hasUrl = url.isNotEmpty;
    final id = payroll['_id']?.toString();
    final canOpen = hasUrl || (id != null && id.isNotEmpty);
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: hasUrl
                ? () => _sharePayslipPdfFromUrl(
                      url,
                      fileBaseName: 'Payslip_${_selectedMonth}',
                    )
                : null,
            icon: const Icon(Icons.ios_share_rounded, size: 20),
            label: const Text('Share'),
            style: OutlinedButton.styleFrom(
              foregroundColor: hasUrl ? AppColors.primary : Colors.grey,
              side: BorderSide(color: hasUrl ? AppColors.primary : Colors.grey),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: canOpen
                ? () => _openPayslipFromPayroll(payroll, download: true)
                : null,
            icon: const Icon(Icons.download, size: 20),
            label: const Text('Download'),
            style: OutlinedButton.styleFrom(
              foregroundColor: canOpen ? AppColors.primary : Colors.grey,
              side: BorderSide(color: canOpen ? AppColors.primary : Colors.grey),
            ),
          ),
        ),
      ],
    );
  }

  /// Same handling as Payslip Request: fetch PDF as bytes (blob), save to Payslips dir, open with OpenFilex.
  Future<void> _downloadPayslipFromUrl(
    String url, {
    required bool downloadOnly,
    String? month,
    int? year,
  }) async {
    bool loadingShown = false;
    try {
      if (downloadOnly) {
        final uri = Uri.tryParse(url);
        if (uri != null && uri.hasScheme && await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          if (mounted) {
            SnackBarUtils.showSnackBar(
              context,
              'Download started in browser (Google Downloads).',
            );
          }
          return;
        }
      }
      if (!loadingShown) {
        loadingShown = true;
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) =>
              const Center(child: AppTabLoader()),
        );
      }
      final result = await _requestService.getPdfBytesFromUrl(url);
      if (mounted && loadingShown) {
        Navigator.pop(context);
        loadingShown = false;
      }

      if (result['success'] != true || result['data'] == null) {
        _fallbackOpenPayslipInBrowser(url);
        return;
      }

      final bytes = result['data'] as List<int>;
      if (bytes.length < 4) {
        _fallbackOpenPayslipInBrowser(url);
        return;
      }
      final isPdf =
          bytes[0] == 0x25 &&
          bytes[1] == 0x50 &&
          bytes[2] == 0x44 &&
          bytes[3] == 0x46; // %PDF
      if (!isPdf) {
        if (mounted) {
          SnackBarUtils.showSnackBar(
            context,
            'Payslip could not be downloaded. Opening in browser instead.',
            isError: false,
          );
        }
        _fallbackOpenPayslipInBrowser(url);
        return;
      }

      final monthName = month ?? _selectedMonth;
      final selectedYear = year ?? int.tryParse(_selectedYear) ?? DateTime.now().year;
      await _openPdfBytes(
        bytes,
        month: monthName,
        year: selectedYear,
        downloadOnly: downloadOnly,
      );
      if (mounted) {
        SnackBarUtils.showSnackBar(
          context,
          downloadOnly ? 'Payslip downloaded to Downloads.' : 'Payslip opened.',
        );
      }
    } catch (e) {
      if (mounted) {
        if (loadingShown) Navigator.pop(context);
        SnackBarUtils.showSnackBar(
          context,
          'Error downloading payslip: ${e.toString()}',
          isError: true,
        );
      }
    }
  }

  Future<void> _fallbackOpenPayslipInBrowser(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) return;
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (mounted) {
          SnackBarUtils.showSnackBar(
            context,
            'Payslip opened in browser. You can view or download it there.',
          );
        }
      }
    } catch (_) {}
  }

  Future<void> _openPdfBytes(
    List<int> pdfBytes, {
    String? month,
    int? year,
    bool downloadOnly = false,
  }) async {
    try {
      final downloadsDir = await getDownloadsDirectory();
      final baseDir = downloadsDir ?? await getApplicationDocumentsDirectory();
      final payslipsDir = Directory('${baseDir.path}/Payslips');
      if (!await payslipsDir.exists()) {
        await payslipsDir.create(recursive: true);
      }
      final fileName = month != null && year != null
          ? 'Payslip_${month}_$year.pdf'
          : 'Payslip_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final file = File('${payslipsDir.path}/$fileName');
      await file.writeAsBytes(pdfBytes, flush: true);

      if (downloadOnly) {
        if (mounted) {
          SnackBarUtils.showSnackBar(context, 'Payslip downloaded to: ${file.path}');
        }
      } else {
        final result = await OpenFilex.open(file.path);
        if (result.type != ResultType.done && mounted) {
          SnackBarUtils.showSnackBar(
            context,
            'Unable to open payslip: ${result.message}',
            isError: true,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        SnackBarUtils.showSnackBar(
          context,
          'Error handling PDF: ${e.toString()}',
          isError: true,
        );
      }
    }
  }

  Future<void> _sharePayslipPdfFromUrl(
    String url, {
    required String fileBaseName,
  }) async {
    bool loadingShown = false;
    try {
      final trimmed = url.trim();
      if (trimmed.isEmpty) return;

      loadingShown = true;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: AppTabLoader()),
      );

      final result = await _requestService.getPdfBytesFromUrl(trimmed);
      if (mounted && loadingShown) {
        Navigator.pop(context);
        loadingShown = false;
      }

      if (result['success'] != true || result['data'] == null) {
        if (mounted) {
          SnackBarUtils.showSnackBar(
            context,
            'Unable to fetch payslip for sharing.',
            isError: true,
          );
        }
        return;
      }

      final bytes = result['data'] as List<int>;
      final isPdf = bytes.length >= 4 &&
          bytes[0] == 0x25 &&
          bytes[1] == 0x50 &&
          bytes[2] == 0x44 &&
          bytes[3] == 0x46; // %PDF
      if (!isPdf) {
        if (mounted) {
          SnackBarUtils.showSnackBar(
            context,
            'Payslip file is not a valid PDF.',
            isError: true,
          );
        }
        return;
      }

      final dir = await getTemporaryDirectory();
      final safeBase =
          fileBaseName.trim().isEmpty ? 'Payslip' : fileBaseName.trim();
      final file = File('${dir.path}/$safeBase.pdf');
      await file.writeAsBytes(bytes, flush: true);

      await Share.shareXFiles(
        [XFile(file.path)],
        subject: safeBase,
        text: safeBase,
      );
    } catch (e) {
      if (mounted) {
        if (loadingShown) Navigator.pop(context);
        SnackBarUtils.showSnackBar(
          context,
          'Error sharing payslip: ${e.toString()}',
          isError: true,
        );
      }
    }
  }

  /// Web: `handleViewPayslip` / `handleDownloadPayslip` by payroll id (blob), else `payslipUrl`.
  Future<void> _openPayslipFromPayroll(
    Map<String, dynamic> payroll, {
    required bool download,
  }) async {
    final id = payroll['_id']?.toString();
    final url = payroll['payslipUrl']?.toString().trim();
    final monthIdx = (payroll['month'] as num?)?.toInt();
    final y = (payroll['year'] as num?)?.toInt();
    final monthName = (monthIdx != null && monthIdx >= 1 && monthIdx <= 12)
        ? _months[monthIdx - 1]
        : _selectedMonth;
    final year = y ?? int.tryParse(_selectedYear) ?? DateTime.now().year;

    bool loadingShown = false;
    try {
      // For download action, prefer browser download manager flow when a URL exists.
      if (download && url != null && url.isNotEmpty) {
        await _downloadPayslipFromUrl(
          url,
          downloadOnly: true,
          month: monthName,
          year: year,
        );
        return;
      }

      if (mounted) {
        loadingShown = true;
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) =>
              const Center(child: AppTabLoader()),
        );
      }
      List<int>? bytes;
      if (id != null && id.isNotEmpty) {
        bytes = await _salaryService.getPayslipPdfBytes(
          id,
          download: download,
        );
      }
      if (bytes != null &&
          bytes.length >= 4 &&
          bytes[0] == 0x25 &&
          bytes[1] == 0x50 &&
          bytes[2] == 0x44 &&
          bytes[3] == 0x46) {
        if (mounted && loadingShown) {
          Navigator.pop(context);
          loadingShown = false;
        }
        await _openPdfBytes(
          bytes,
          month: monthName,
          year: year,
          downloadOnly: download,
        );
        if (mounted) {
          SnackBarUtils.showSnackBar(
            context,
            download ? 'Payslip downloaded to Downloads.' : 'Payslip opened.',
            isError: false,
          );
        }
        return;
      }

      if (mounted && loadingShown) {
        Navigator.pop(context);
        loadingShown = false;
      }

      if (url != null && url.isNotEmpty) {
        await _downloadPayslipFromUrl(
          url,
          downloadOnly: download,
          month: monthName,
          year: year,
        );
        return;
      }
      if (mounted) {
        SnackBarUtils.showSnackBar(
          context,
          'Payslip not available.',
          isError: true,
        );
      }
    } catch (e) {
      if (mounted && loadingShown) Navigator.pop(context);
      if (mounted) {
        SnackBarUtils.showSnackBar(
          context,
          'Error opening payslip: ${e.toString()}',
          isError: true,
        );
      }
    }
  }

  Widget _buildPayrollHistoryCard() {
    final currencyFormat = NumberFormat.currency(locale: 'en_IN', symbol: '₹');
    final visible = _visiblePayrollHistory;
    final pag = _payrollHistoryPagination;
    final pages = (pag?['pages'] as num?)?.toInt() ?? 0;
    final page = (pag?['page'] as num?)?.toInt() ?? _payrollHistoryPage;
    final total = (pag?['total'] as num?)?.toInt() ?? 0;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(Icons.history, color: AppColors.primary, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'Payroll History',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const Spacer(),
                if (!_payrollHistoryLoading)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${visible.length} records',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                const SizedBox(width: 8),
                if (_payrollHistoryLoading)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (visible.isEmpty && !_payrollHistoryLoading)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'No payroll records in this view.',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: visible.map((p) {
                  final m = (p['month'] as num?)?.toInt() ?? 1;
                  final y = (p['year'] as num?)?.toInt() ?? DateTime.now().year;
                  final label = '${_months[(m - 1).clamp(0, 11)]} $y';
                  final status = (p['status'] ?? '—').toString();
                  final statusLower = status.toLowerCase();
                  final payslipUrl = p['payslipUrl']?.toString().trim() ?? '';
                  final hasPayslipUrl = payslipUrl.isNotEmpty;
                  final hasPayslip =
                      hasPayslipUrl || ((p['_id']?.toString().isNotEmpty) ?? false);

                  final chipBg = statusLower == 'paid'
                      ? Colors.green.shade50
                      : statusLower == 'processed'
                          ? Colors.blue.shade50
                          : Colors.orange.shade50;
                  final chipFg = statusLower == 'paid'
                      ? Colors.green.shade700
                      : statusLower == 'processed'
                          ? Colors.blue.shade700
                          : Colors.orange.shade700;

                  return Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                label,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.black87,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: chipBg,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                status,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: chipFg,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        _buildComponentRow(
                          'Gross',
                          (p['grossSalary'] as num?)?.toDouble() ?? 0,
                          currencyFormat,
                        ),
                        _buildComponentRow(
                          'Deductions',
                          (p['deductions'] as num?)?.toDouble() ?? 0,
                          currencyFormat,
                          isDeduction: true,
                        ),
                        _buildComponentRow(
                          'Net Pay',
                          (p['netPay'] as num?)?.toDouble() ?? 0,
                          currencyFormat,
                        ),
                        const SizedBox(height: 8),
                        if (hasPayslip)
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              OutlinedButton.icon(
                                onPressed: hasPayslipUrl
                                    ? () => _sharePayslipPdfFromUrl(
                                          payslipUrl,
                                          fileBaseName:
                                              'Payslip_${_months[(m - 1).clamp(0, 11)]}',
                                        )
                                    : null,
                                icon: const Icon(Icons.ios_share_rounded, size: 18),
                                label: const Text('Share'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.primary,
                                  visualDensity: VisualDensity.compact,
                                ),
                              ),
                              OutlinedButton.icon(
                                onPressed: hasPayslipUrl
                                    ? () => _downloadPayslipFromUrl(
                                          payslipUrl,
                                          downloadOnly: true,
                                          month: _months[(m - 1).clamp(0, 11)],
                                          year: y,
                                        )
                                    : () => _openPayslipFromPayroll(
                                          p,
                                          download: true,
                                        ),
                                icon: const Icon(Icons.download_outlined, size: 18),
                                label: const Text('Download'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.primary,
                                  visualDensity: VisualDensity.compact,
                                ),
                              ),
                            ],
                          )
                        else
                          Text(
                            'Payslip not available',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          if (pages > 1) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Text(
                    'Page $page of $pages · $total total',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: page <= 1 || _payrollHistoryLoading
                        ? null
                        : () {
                            setState(() => _payrollHistoryPage = page - 1);
                            _loadPayrollHistory();
                          },
                    child: const Text('Previous'),
                  ),
                  TextButton(
                    onPressed: page >= pages || _payrollHistoryLoading
                        ? null
                        : () {
                            setState(() => _payrollHistoryPage = page + 1);
                            _loadPayrollHistory();
                          },
                    child: const Text('Next'),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 80,
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        value: _payrollHistoryPageSize,
                        isExpanded: true,
                        items: const [10, 20, 50]
                            .map(
                              (n) => DropdownMenuItem(
                                value: n,
                                child: Text('$n / page', style: const TextStyle(fontSize: 12)),
                              ),
                            )
                            .toList(),
                        onChanged: _payrollHistoryLoading
                            ? null
                            : (v) {
                                if (v == null) return;
                                setState(() {
                                  _payrollHistoryPageSize = v;
                                  _payrollHistoryPage = 1;
                                });
                                _loadPayrollHistory();
                              },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPastMonthAttendancePlaceholder() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
    );
  }

  /// MTD figures for the breakdown card. Recomputes if [_proratedSalary] was never set (avoids falling
  /// back to [_backendEarnings], which can show prorated Basic/DA/HRA and look like "wrong" contract pay).
  ProratedSalary? _resolveProrationForBreakdown() {
    if (_proratedSalary != null) return _proratedSalary;
    if (_calculatedSalary == null || _workingDaysInfo == null) return null;
    final wdm =
        _workingDaysInfo!.workingDaysFullMonth ?? _workingDaysInfo!.workingDays;
    if (wdm <= 0) return null;
    final fine = (_fineInfo['totalFineAmount'] as num?)?.toDouble() ?? 0.0;
    return calculateProratedSalary(
      _calculatedSalary!,
      wdm,
      _webPresentDays,
      fine,
    );
  }

  Widget _buildSalaryComponentBreakdown() {
    final selectedPayroll = _pastMonthPayroll ?? _currentPayroll;
    final previewHasComponents =
        (_payrollPreview?['components'] as List?)?.isNotEmpty == true;
    if (_calculatedSalary == null &&
        (selectedPayroll == null || (selectedPayroll['components'] as List?)?.isEmpty != false) &&
        _backendEarnings.isEmpty &&
        _backendDeductionComponents.isEmpty &&
        !previewHasComponents) {
      return const SizedBox.shrink();
    }
    final currencyFormat = NumberFormat.currency(locale: 'en_IN', symbol: '₹');
    final salary = _calculatedSalary;
    final monthly = salary?.monthly;
    final yearly = salary?.yearly;
    final payrollComponents = selectedPayroll != null && selectedPayroll['components'] is List
        ? (selectedPayroll['components'] as List)
        : const [];
    final payrollEarnings = payrollComponents
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .where((e) => (e['type']?.toString().toLowerCase() ?? '') == 'earning')
        .toList();
    final payrollDeductions = payrollComponents
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .where((e) => (e['type']?.toString().toLowerCase() ?? '') == 'deduction')
        .toList();

    final previewComponentsRaw =
        (_payrollPreview?['components'] as List?) ?? const [];
    final previewEarnings = previewComponentsRaw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .where((e) => (e['type']?.toString().toLowerCase() ?? '') == 'earning')
        .toList();
    final previewDeductions = previewComponentsRaw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .where((e) => (e['type']?.toString().toLowerCase() ?? '') == 'deduction')
        .toList();

    final employeePFRate = (_staffSalary?['employeePFRate'] as num?)?.toDouble();
    final employeeESIRate = (_staffSalary?['employeeESIRate'] as num?)?.toDouble();

    final payrollStatus =
        (selectedPayroll?['status'] ?? '').toString().toLowerCase();
    final payrollLocked =
        payrollStatus == 'processed' || payrollStatus == 'paid';

    // Web (EmployeeSalaryOverview): earnings list shows **full** Basic/DA/HRA; MTD row is prorated.
    // Do not require [_proratedSalary] for earnings — otherwise we fall back to [_backendEarnings] (wrong Basic).
    final wdm = _workingDaysInfo == null
        ? 0
        : (_workingDaysInfo!.workingDaysFullMonth ??
            _workingDaysInfo!.workingDays);
    final f = wdm > 0 ? (_webPresentDays / wdm) : 0.0;
    final useWebStyleStructure = payrollEarnings.isEmpty &&
        monthly != null &&
        !payrollLocked;
    final prBreakdown = _resolveProrationForBreakdown();
    final useWebStyleMtdRows = useWebStyleStructure && prBreakdown != null;
    final fineAmount = (_fineInfo['totalFineAmount'] as num?)?.toDouble() ?? 0.0;

    debugPrint(
      '[SalaryCalc] breakdown: payrollLocked=$payrollLocked payrollEarnings=${payrollEarnings.length} '
      'useWebStyleStructure=$useWebStyleStructure useWebStyleMtdRows=$useWebStyleMtdRows '
      'staffBasic=${_staffSalary?['basicSalary']} monthlyBasic=${monthly?.basicSalary} '
      'wdm=$wdm webPresent=$_webPresentDays f=${f.toStringAsFixed(4)} '
      'hadProratedState=${_proratedSalary != null} backendEarnings=${_backendEarnings.length} '
      '${_backendEarnings.map((e) => '${e['name']}:${e['amount']}').join(', ')}',
    );
    final pfStaticMonthly = monthly != null
        ? (monthly.grossSalary -
                monthly.grossFixedSalary -
                monthly.employerPF -
                monthly.employerESI)
            .clamp(0.0, double.infinity)
        : 0.0;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.account_balance_wallet, color: AppColors.primary, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Salary Breakdown — $_selectedMonth $_selectedYear',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ],
                ),
                if (_isPayslipAutoGenerated) ...[
                  const SizedBox(height: 8),
                  Builder(
                    builder: (context) {
                      final sel = selectedPayroll;
                      final pid = sel?['_id']?.toString();
                      final url = sel?['payslipUrl']?.toString().trim() ?? '';
                      final hasUrl = url.isNotEmpty;
                      if (sel != null && hasUrl && pid != null && pid.isNotEmpty) {
                        return Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            OutlinedButton.icon(
                              onPressed: () => _sharePayslipPdfFromUrl(
                                url,
                                fileBaseName: 'Payslip_${_selectedMonth}',
                              ),
                              icon: const Icon(Icons.ios_share_rounded, size: 18),
                              label: const Text('Share'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.primary,
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: () => _openPayslipFromPayroll(
                                sel,
                                download: true,
                              ),
                              icon: const Icon(Icons.download, size: 18),
                              label: const Text('Download PDF'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.primary,
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                          ],
                        );
                      }
                      if (sel != null) {
                        return Text(
                          'Payslip not generated yet',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade700,
                          ),
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Earnings',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 8),
                if (payrollEarnings.isNotEmpty)
                  ...payrollEarnings.map(
                    (e) => _buildComponentRow(
                      (e['name'] ?? 'Component').toString(),
                      (e['amount'] as num?)?.toDouble() ?? 0.0,
                      currencyFormat,
                    ),
                  )
                else if (previewEarnings.isNotEmpty)
                  ...previewEarnings.map(
                    (e) => _buildComponentRow(
                      (e['name'] ?? 'Component').toString(),
                      (e['amount'] as num?)?.toDouble() ?? 0.0,
                      currencyFormat,
                    ),
                  )
                else if (useWebStyleStructure) ...[
                  _buildComponentRow(
                    'Basic Salary',
                    monthly.basicSalary,
                    currencyFormat,
                  ),
                  _buildComponentRow(
                    'DA',
                    monthly.dearnessAllowance,
                    currencyFormat,
                  ),
                  _buildComponentRow(
                    'HRA',
                    monthly.houseRentAllowance,
                    currencyFormat,
                  ),
                  _buildComponentRow(
                    'Special Allowance',
                    monthly.specialAllowance,
                    currencyFormat,
                  ),
                  _buildComponentRow(
                    'Employer PF',
                    monthly.employerPF,
                    currencyFormat,
                  ),
                  _buildComponentRow(
                    'Employer ESI',
                    monthly.employerESI,
                    currencyFormat,
                  ),
                  if (pfStaticMonthly > 0.01)
                    _buildComponentRow(
                      'Statutory PF (Fixed)',
                      pfStaticMonthly,
                      currencyFormat,
                    ),
                  ..._backendEarnings
                      .where(
                        (e) => !_isCoreStructuralEarningName(
                          (e['name'] ?? '').toString(),
                        ),
                      )
                      .map(
                        (e) => _buildComponentRow(
                          (e['name'] ?? 'Component').toString(),
                          (e['amount'] as num?)?.toDouble() ?? 0.0,
                          currencyFormat,
                        ),
                      ),
                ]
                else if (_backendEarnings.isNotEmpty)
                  ..._backendEarnings.map(
                    (e) => _buildComponentRow(
                      (e['name'] ?? 'Component').toString(),
                      (e['amount'] as num?)?.toDouble() ?? 0.0,
                      currencyFormat,
                    ),
                  )
                else if (monthly != null) ...[
                  _buildComponentRow(
                    'Basic Salary',
                    monthly.basicSalary,
                    currencyFormat,
                  ),
                  _buildComponentRow(
                    'DA',
                    monthly.dearnessAllowance,
                    currencyFormat,
                  ),
                  _buildComponentRow(
                    'HRA',
                    monthly.houseRentAllowance,
                    currencyFormat,
                  ),
                  _buildComponentRow(
                    'Special Allowance',
                    monthly.specialAllowance,
                    currencyFormat,
                  ),
                  _buildComponentRow(
                    'Employer PF',
                    monthly.employerPF,
                    currencyFormat,
                  ),
                  _buildComponentRow(
                    'Employer ESI',
                    monthly.employerESI,
                    currencyFormat,
                  ),
                ],
                if (selectedPayroll?['grossSalary'] is num)
                  _buildComponentRow(
                    'Gross Salary',
                    (selectedPayroll!['grossSalary'] as num).toDouble(),
                    currencyFormat,
                  )
                else if (_payrollPreview?['grossSalary'] is num)
                  _buildComponentRow(
                    'Gross Salary',
                    (_payrollPreview!['grossSalary'] as num).toDouble(),
                    currencyFormat,
                  )
                else if (useWebStyleMtdRows)
                  _buildComponentRow(
                    'Month-to-Date Gross',
                    prBreakdown.proratedGrossSalary,
                    currencyFormat,
                  )
                else if (useWebStyleStructure && _backendThisMonthGross != null)
                  _buildComponentRow(
                    'Month-to-Date Gross',
                    _backendThisMonthGross!,
                    currencyFormat,
                  )
                else if (_backendThisMonthGross != null)
                  _buildComponentRow(
                    'Gross Salary',
                    _backendThisMonthGross!,
                    currencyFormat,
                  ),
                const SizedBox(height: 10),
                const Text(
                  'Deductions',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 8),
                if (payrollDeductions.isNotEmpty)
                  ...payrollDeductions.map(
                    (e) => _buildComponentRow(
                      (e['name'] ?? 'Deduction').toString(),
                      (e['amount'] as num?)?.toDouble() ?? 0.0,
                      currencyFormat,
                      isDeduction: true,
                    ),
                  )
                else if (previewDeductions.isNotEmpty)
                  ...previewDeductions.map(
                    (e) => _buildComponentRow(
                      (e['name'] ?? 'Deduction').toString(),
                      (e['amount'] as num?)?.toDouble() ?? 0.0,
                      currencyFormat,
                      isDeduction: true,
                    ),
                  )
                else if (useWebStyleStructure) ...[
                  _buildComponentRow(
                    employeePFRate != null
                        ? 'Employee PF (${employeePFRate.toStringAsFixed(0)}%)'
                        : 'Employee PF',
                    monthly.employeePF * f,
                    currencyFormat,
                    isDeduction: true,
                  ),
                  _buildComponentRow(
                    employeeESIRate != null
                        ? 'Employee ESI (${employeeESIRate.toStringAsFixed(2)}%)'
                        : 'Employee ESI',
                    monthly.employeeESI * f,
                    currencyFormat,
                    isDeduction: true,
                  ),
                  if (fineAmount > 0)
                    _buildComponentRow(
                      'Late Login Fine',
                      fineAmount,
                      currencyFormat,
                      isDeduction: true,
                    ),
                ]
                else if (_backendDeductionComponents.isNotEmpty)
                  ..._backendDeductionComponents.map(
                    (e) => _buildComponentRow(
                      (e['name'] ?? 'Deduction').toString(),
                      (e['amount'] as num?)?.toDouble() ?? 0.0,
                      currencyFormat,
                      isDeduction: true,
                    ),
                  )
                else if (monthly != null) ...[
                  _buildComponentRow(
                    employeePFRate != null
                        ? 'Employee PF (${employeePFRate.toStringAsFixed(0)}%)'
                        : 'Employee PF',
                    monthly.employeePF,
                    currencyFormat,
                    isDeduction: true,
                  ),
                  _buildComponentRow(
                    employeeESIRate != null
                        ? 'Employee ESI (${employeeESIRate.toStringAsFixed(2)}%)'
                        : 'Employee ESI',
                    monthly.employeeESI,
                    currencyFormat,
                    isDeduction: true,
                  ),
                ],
                if (selectedPayroll?['deductions'] is num)
                  _buildComponentRow(
                    'Total Deductions',
                    (selectedPayroll!['deductions'] as num).toDouble(),
                    currencyFormat,
                    isDeduction: true,
                  )
                else if (_payrollPreview?['deductions'] is num)
                  _buildComponentRow(
                    'Total Deductions',
                    (_payrollPreview!['deductions'] as num).toDouble(),
                    currencyFormat,
                    isDeduction: true,
                  )
                else if (useWebStyleMtdRows)
                  _buildComponentRow(
                    'Total Deductions',
                    prBreakdown.totalDeductions,
                    currencyFormat,
                    isDeduction: true,
                  )
                else if (useWebStyleStructure)
                  _buildComponentRow(
                    'Total Deductions',
                    monthly.totalMonthlyDeductions * f + fineAmount,
                    currencyFormat,
                    isDeduction: true,
                  )
                else if (_backendDeductionsTotal > 0)
                  _buildComponentRow(
                    'Total Deductions',
                    _backendDeductionsTotal,
                    currencyFormat,
                    isDeduction: true,
                  ),
                if (selectedPayroll?['netPay'] is num)
                  _buildComponentRow(
                    'Net Salary',
                    (selectedPayroll!['netPay'] as num).toDouble(),
                    currencyFormat,
                  )
                else if (_payrollPreview?['netPay'] is num)
                  _buildComponentRow(
                    'Net Salary',
                    (_payrollPreview!['netPay'] as num).toDouble(),
                    currencyFormat,
                  )
                else if (useWebStyleMtdRows)
                  _buildComponentRow(
                    'Net Salary',
                    prBreakdown.proratedNetSalary,
                    currencyFormat,
                  )
                else if (useWebStyleStructure && wdm > 0)
                  _buildComponentRow(
                    'Net Salary',
                    monthly.grossSalary * f -
                        monthly.totalMonthlyDeductions * f -
                        fineAmount,
                    currencyFormat,
                  )
                else if (_backendThisMonthNet != null)
                  _buildComponentRow(
                    'Net Salary',
                    _backendThisMonthNet!,
                    currencyFormat,
                  ),
                if (selectedPayroll != null &&
                    selectedPayroll['status'] != null &&
                    selectedPayroll['status'].toString().trim().isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200.withOpacity(0.45),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Text(
                          'Payroll status',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade700,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            selectedPayroll['status'].toString(),
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (selectedPayroll == null &&
                    (_payrollPreview != null ||
                        useWebStyleStructure ||
                        previewEarnings.isNotEmpty ||
                        previewDeductions.isNotEmpty)) ...[
                  const SizedBox(height: 8),
                  Text(
                    '* This is an estimated calculation. Final amount will be based on processed payroll.',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.amber.shade900,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Total CTC (Annual)',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Colors.grey.shade800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      _buildMiniRow(
                        'Annual Gross Salary',
                        yearly?.annualGrossSalary ?? 0.0,
                        currencyFormat,
                      ),
                      _buildMiniRow(
                        'Annual Benefits',
                        yearly?.totalAnnualBenefits ?? 0.0,
                        currencyFormat,
                      ),
                      if ((yearly?.annualIncentive ?? 0) > 0)
                        _buildMiniRow(
                          'Annual Incentive',
                          yearly!.annualIncentive,
                          currencyFormat,
                        ),
                      if ((yearly?.annualMobileAllowance ?? 0) > 0)
                        _buildMiniRow(
                          'Annual Mobile Allowance',
                          yearly!.annualMobileAllowance,
                          currencyFormat,
                        ),
                      const Divider(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Total CTC',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          Text(
                            currencyFormat.format(salary?.totalCTC ?? 0.0),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComponentRow(
    String label,
    double amount,
    NumberFormat currencyFormat, {
    bool isDeduction = false,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isDeduction ? Colors.red.shade50 : Colors.green.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDeduction ? Colors.red.shade100 : Colors.green.shade100,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            currencyFormat.format(amount),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: isDeduction ? Colors.red.shade700 : Colors.green.shade700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniRow(String label, double amount, NumberFormat currencyFormat) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            currencyFormat.format(amount),
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCards() {
    if (_isSelectedCurrentMonth && _isCurrentCycleBlocked) {
      return const SizedBox.shrink();
    }

    final isPastMonth = !_isSelectedCurrentMonth;
    if (isPastMonth) {
      // Past month: match web-style by showing selected month payroll values when available.
      final currencyFormat = NumberFormat.currency(
        locale: 'en_IN',
        symbol: '₹',
      );
      final gross = _calculatedSalary?.monthly.grossSalary ?? 0.0;
      final net = _calculatedSalary?.monthly.netMonthlySalary ?? 0.0;
      final selectedPayroll = _pastMonthPayroll ?? _currentPayroll;
      final payrollGross = (selectedPayroll?['grossSalary'] as num?)?.toDouble();
      final payrollNet = (selectedPayroll?['netPay'] as num?)?.toDouble();
      final previewGross =
          (_payrollPreview?['grossSalary'] as num?)?.toDouble();
      final previewNet = (_payrollPreview?['netPay'] as num?)?.toDouble();
      final selectedMonthGross = payrollGross ?? previewGross ?? 0.0;
      final selectedMonthNet = payrollNet ?? previewNet ?? 0.0;
      final hasSelectedPayroll = selectedPayroll != null;
      final hasPreview =
          _payrollPreview != null &&
          (previewGross != null || previewNet != null);
      final mtdSubtitle = hasSelectedPayroll
          ? 'From selected month payroll'
          : hasPreview
              ? 'From payroll preview (estimated)'
              : 'Payroll not available';
      final subtitle = _calculatedSalary != null
          ? 'From salary structure'
          : 'Salary structure not available';

      return LayoutBuilder(
        builder: (context, constraints) {
          bool isWide = constraints.maxWidth > 600;
          final cards = [
            _buildStatCard(
              'Monthly Gross',
              currencyFormat.format(gross),
              subtitle,
              AppColors.primary,
              textColor: Colors.white,
              usePrimaryGradient: true,
            ),
            _buildStatCard(
              'Monthly Net',
              currencyFormat.format(net),
              subtitle,
              AppColors.primary,
              textColor: Colors.white,
              usePrimaryGradient: true,
            ),
            _buildStatCard(
              'This Month Gross',
              currencyFormat.format(selectedMonthGross),
              mtdSubtitle,
              Colors.black,
              textColor: Colors.white,
            ),
            _buildStatCard(
              'This Month Net',
              currencyFormat.format(selectedMonthNet),
              mtdSubtitle,
              Colors.black,
              textColor: Colors.white,
            ),
          ];
          return GridView.count(
            crossAxisCount: isWide ? 4 : 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: isWide ? 2.4 : 1.5,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            children: cards,
          );
        },
      );
    }

    if (_calculatedSalary == null &&
        _payrollPreview == null &&
        _currentPayroll == null &&
        _proratedSalary == null) {
      return const SizedBox.shrink();
    }

    final currencyFormat = NumberFormat.currency(locale: 'en_IN', symbol: '₹');

    final payrollMtdGross =
        (_currentPayroll?['grossSalary'] as num?)?.toDouble();
    final payrollMtdNet = (_currentPayroll?['netPay'] as num?)?.toDouble();
    final previewGross =
        (_payrollPreview?['grossSalary'] as num?)?.toDouble();
    final previewNet = (_payrollPreview?['netPay'] as num?)?.toDouble();
    final previewAtt = _payrollPreview?['attendance'] as Map<String, dynamic>?;
    final previewCardDays =
        (previewAtt?['presentDays'] as num?)?.toDouble();
    final previewWorkingTill =
        (previewAtt?['workingDaysTillCurrentDate'] as num?)?.toInt();
    final previewAttPct =
        (previewAtt?['attendancePercentage'] as num?)?.toDouble();

    final payrollFinal = _payrollRowIsFinalForMtd(_currentPayroll);
    final double thisMonthGrossDisplay;
    final double rawThisMonthNet;
    if (payrollFinal) {
      thisMonthGrossDisplay = payrollMtdGross ??
          previewGross ??
          _proratedSalary?.proratedGrossSalary ??
          0.0;
      rawThisMonthNet = payrollMtdNet ??
          previewNet ??
          _proratedSalary?.proratedNetSalary ??
          0.0;
    } else {
      thisMonthGrossDisplay = previewGross ??
          _proratedSalary?.proratedGrossSalary ??
          payrollMtdGross ??
          0.0;
      rawThisMonthNet = previewNet ??
          _proratedSalary?.proratedNetSalary ??
          payrollMtdNet ??
          0.0;
    }

    final workingDaysTillForCards = _workingDaysInfo?.workingDays ?? 0;
    // Web: salaryCardPresentDays = preview?.attendance?.presentDays ?? presentDays (client reducer).
    final salaryCardPresentDays =
        previewCardDays ?? _presentDays;
    final salaryCardWorkingTill =
        previewWorkingTill ?? workingDaysTillForCards;
    // Web gross card: salaryCardAttendancePct = present / workingDaysTillCurrentDate.
    final attendancePercentForCards = previewAttPct ??
        (salaryCardWorkingTill > 0
            ? (salaryCardPresentDays / salaryCardWorkingTill) * 100
            : 0.0);

    // Do not show negative net for card display – clamp at 0
    final displayThisMonthNet = rawThisMonthNet < 0 ? 0.0 : rawThisMonthNet;
    final fineAmt =
        (_fineInfo['totalFineAmount'] as num?)?.toDouble() ?? 0.0;
    final netCardExtra = StringBuffer();
    if (_payrollRowIsFinalForMtd(_currentPayroll)) {
      netCardExtra.write('From processed payroll');
    } else if (_payrollPreview != null || _workingDaysInfo != null) {
      netCardExtra.write(
        'Based on ${_formatDayChip(salaryCardPresentDays)} days out of $salaryCardWorkingTill',
      );
      if (fineAmt > 0) {
        netCardExtra.write(' (Fine: ${currencyFormat.format(fineAmt)})');
      }
      if (_unpaidLeaveDeduction > 0) {
        netCardExtra
            .write(' (Unpaid Leave: ${currencyFormat.format(_unpaidLeaveDeduction)})');
      }
    } else {
      netCardExtra.write('Expected take-home');
    }

    debugPrint(
      '[SalaryOverview] summary cards payrollFinal=$payrollFinal '
      '(final: payroll→preview→prorated; else preview→prorated→payroll) '
      'payrollGross=$payrollMtdGross payrollNet=$payrollMtdNet '
      'previewGross=$previewGross previewNet=$previewNet '
      'proratedGross=${_proratedSalary?.proratedGrossSalary} proratedNet=${_proratedSalary?.proratedNetSalary} '
      'salaryCardPresentDays=$salaryCardPresentDays workTill=$salaryCardWorkingTill '
      'displayGross=$thisMonthGrossDisplay displayNet=$displayThisMonthNet',
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        // Use Grid or Row based on width
        bool isWide = constraints.maxWidth > 600;

        // Row 1: Monthly Gross, Monthly Net | Row 2: This Month Gross, This Month Net
        final List<Widget> cards = [
          _buildStatCard(
            'Monthly Gross',
            currencyFormat.format(_calculatedSalary?.monthly.grossSalary ?? 0.0),
            'From salary structure',
            AppColors.primary,
            textColor: Colors.white,
            usePrimaryGradient: true,
          ),
          _buildStatCard(
            'Monthly Net',
            currencyFormat.format(_calculatedSalary?.monthly.netMonthlySalary ?? 0.0),
            'From salary structure',
            AppColors.primary,
            textColor: Colors.white,
            usePrimaryGradient: true,
          ),
          _buildStatCard(
            'This Month Gross',
            currencyFormat.format(thisMonthGrossDisplay),
            (_workingDaysInfo != null || _payrollPreview != null)
                ? 'Based on ${_formatDayChip(salaryCardPresentDays)} present days out of $salaryCardWorkingTill working days\n${attendancePercentForCards.toStringAsFixed(1)}% attendance'
                : 'Pro-rated',
            Colors.black,
            textColor: Colors.white,
          ),
          _buildStatCard(
            'This Month Net',
            currencyFormat.format(displayThisMonthNet),
            netCardExtra.toString(),

            Colors.black,
            textColor: Colors.white,
          ),
        ];

        return GridView.count(
          crossAxisCount: isWide ? 4 : 2, // 2 cols on mobile
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: isWide ? 1.6 : 1.5,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          children: cards,
        );
      },
    );
  }

  /// This Month Net prominent card (same as Month Salary Details).
  Widget _buildThisMonthNetCard() {
    if (_calculatedSalary == null || _proratedSalary == null) {
      return const SizedBox.shrink();
    }
    final currencyFormat = NumberFormat.currency(locale: 'en_IN', symbol: '₹');
    final payrollNet = (_currentPayroll?['netPay'] as num?)?.toDouble();
    final previewNet = (_payrollPreview?['netPay'] as num?)?.toDouble();
    final rawThisMonthNet = (_payrollRowIsFinalForMtd(_currentPayroll)
            ? (payrollNet ?? previewNet ?? _proratedSalary!.proratedNetSalary)
            : (previewNet ?? _proratedSalary!.proratedNetSalary)) ??
        0.0;
    final displayThisMonthNet = rawThisMonthNet < 0 ? 0.0 : rawThisMonthNet;
    final workingTillToday = _workingDaysInfo?.workingDays ?? 0;
    final absentForChips =
        (workingTillToday - _presentDays).clamp(0.0, double.infinity);
    int pendingDaysCount = 0;
    for (final record in _attendanceRecords) {
      final status = (record['status'] as String? ?? '').trim().toLowerCase();
      if (status == 'pending') pendingDaysCount++;
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'This Month Net Salary',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            currencyFormat.format(displayThisMonthNet),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          const Divider(color: Colors.white24, thickness: 1),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              _buildOverviewStatChip(
                'Present: ${_formatDayChip(_presentDays)}',
                Colors.green,
              ),
              if (_paidLeaveDays > 0)
                _buildOverviewStatChip(
                  'Paid Leave: ${_formatDayChip(_paidLeaveDays)}',
                  Colors.blue,
                ),
              _buildOverviewStatChip(
                'Half Day: $_halfDayPaidLeaveCount',
                Colors.blue,
              ),
              _buildOverviewStatChip(
                'Leave: ${_formatDayChip(_leaveDays)}',
                Colors.orange,
              ),
              _buildOverviewStatChip(
                'Absent: ${_formatDayChip(absentForChips)}',
                Colors.red,
              ),
              if (pendingDaysCount > 0)
                _buildOverviewStatChip(
                  'Pending: $pendingDaysCount',
                  Colors.orange,
                ),
            ],
          ),
          if (_leaveDays > 0) ...[
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(left: 2),
              child: Text(
                'Leave = approved leave days this month (from attendance).',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.85),
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _formatDayChip(num value) {
    final d = value.toDouble();
    return d == d.roundToDouble() ? '${d.toInt()}' : d.toStringAsFixed(1);
  }

  Widget _buildOverviewStatChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.3)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    String subtitle,
    Color bgColor, {
    Color? textColor,
    bool usePrimaryGradient = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        gradient: usePrimaryGradient
            ? LinearGradient(
                colors: [AppColors.primary, AppColors.primaryDark],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        color: usePrimaryGradient ? null : bgColor,
        borderRadius: BorderRadius.circular(12),
        border: usePrimaryGradient
            ? null
            : Border.all(color: Colors.grey.shade200, width: 1),
        boxShadow: [
          BoxShadow(
            color: usePrimaryGradient
                ? AppColors.primary.withOpacity(0.3)
                : Colors.black.withOpacity(0.05),
            blurRadius: usePrimaryGradient ? 8 : 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: TextStyle(
              color: textColor ?? Colors.black,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                color: textColor ?? AppColors.success,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Flexible(
            child: Text(
              subtitle,
              style: TextStyle(color: textColor ?? Colors.black, fontSize: 9),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  /// Web `salaryCardAttendancePct`: preview % else (salaryCardPresentDays / salaryCardWorkingDays) * 100.
  double _monthGrossCardAttendancePercent() {
    final previewAtt = _payrollPreview?['attendance'] as Map<String, dynamic>?;
    final previewPct = (previewAtt?['attendancePercentage'] as num?)?.toDouble();
    if (previewPct != null) return previewPct;
    final previewDays = (previewAtt?['presentDays'] as num?)?.toDouble();
    final days = previewDays ?? _presentDays;
    final previewWd =
        (previewAtt?['workingDaysTillCurrentDate'] as num?)?.toInt() ??
        (previewAtt?['workingDays'] as num?)?.toInt();
    final w = previewWd ?? _workingDaysInfo?.workingDays ?? 0;
    if (w <= 0) return 0;
    return (days / w) * 100;
  }

  Widget _buildAttendanceSummary() {
    if (_workingDaysInfo == null ||
        (_proratedSalary == null &&
            _payrollPreview == null &&
            _currentPayroll == null)) {
      return const SizedBox.shrink();
    }

    final working = _workingDaysInfo!.workingDays;
    // Web lines 795–799, 828–838: `presentDays` client reducer; absent = workingDays − presentDays.
    final present = _presentDays;
    final absent = (working - present).clamp(0.0, double.infinity);
    final absentStr = absent == absent.roundToDouble()
        ? '${absent.toInt()}'
        : absent.toStringAsFixed(1);
    final holidays = _workingDaysInfo!.holidayCount;
    final percent = _monthGrossCardAttendancePercent();

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primary, AppColors.primaryDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Attendance Summary',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: Colors.white,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${percent.toStringAsFixed(1)}%',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 320;
              return Wrap(
                spacing: narrow ? 6 : 12,
                runSpacing: 6,
                children: [
                  _buildAttStat(
                    'Working Days',
                    '$working',
                    isPrimaryCard: true,
                  ),
                  _buildAttStat(
                    'Present',
                    '$present',
                    color: Colors.green,
                    isPrimaryCard: true,
                  ),
                  if (_webPaidLeaves > 0)
                    _buildAttStat(
                      'Paid Leave',
                      _formatDayChip(_webPaidLeaves),
                      color: Colors.blue,
                      isPrimaryCard: true,
                    ),
                  _buildAttStat(
                    'Absent Days',
                    absentStr,
                    color: Colors.red,
                    isPrimaryCard: true,
                  ),
                  if (_halfDayPaidLeaveCount > 0)
                    _buildAttStat(
                      'Half day paid leave',
                      '$_halfDayPaidLeaveCount',
                      isPrimaryCard: true,
                    ),
                  if (_leaveDays > 0)
                    _buildAttStat(
                      'Leave days',
                      _leaveDays == _leaveDays.roundToDouble()
                          ? '${_leaveDays.toInt()}'
                          : _leaveDays.toStringAsFixed(1),
                      isPrimaryCard: true,
                    ),
                  _buildAttStat(
                    'Holidays',
                    '$holidays',
                    color: Colors.orange,
                    isPrimaryCard: true,
                  ),
                ],
              );
            },
          ),
          // Fine Summary
          if (_fineInfo['totalFineAmount'] > 0) ...[
            Divider(height: 16, color: Colors.white.withOpacity(0.5)),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Late Login Fine',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${_fineInfo['lateDays']} late day(s) • ${_fineInfo['totalLateMinutes']} min late',
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.white,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Text(
                  NumberFormat.currency(
                    locale: 'en_IN',
                    symbol: '₹',
                  ).format(_fineInfo['totalFineAmount']),
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ],
          Divider(height: 16, color: Colors.white.withOpacity(0.5)),
          const SizedBox(height: 4),
          const Text(
            'Attendance Breakdown',
            style: TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildBreakdownPill(
                'Full Day Present',
                '$_fullDayPresentCount',
                Colors.green.shade100,
                Colors.green.shade900,
              ),
              _buildBreakdownPill(
                'Half Day Present',
                '$_halfDayPresentCount',
                Colors.blue.shade100,
                Colors.blue.shade900,
              ),
              _buildBreakdownPill(
                'Paid Leaves',
                '${_formatDayChip(_webPaidLeaves)} days',
                Colors.purple.shade100,
                Colors.purple.shade900,
              ),
              _buildBreakdownPill(
                'Unpaid Leaves',
                '${_formatDayChip(_webUnpaidLeaves)} days',
                Colors.orange.shade100,
                Colors.orange.shade900,
              ),
            ],
          ),
          if (_webLeaveTypeBreakdown.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Text(
              'Leave Type Breakdown',
              style: TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            ..._webLeaveTypeBreakdown.entries.map((entry) {
              final paid = entry.value['paid'] ?? 0.0;
              final unpaid = entry.value['unpaid'] ?? 0.0;
              final parts = <String>[];
              if (paid > 0) parts.add('${_formatDayChip(paid)} paid');
              if (unpaid > 0) parts.add('${_formatDayChip(unpaid)} unpaid');
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        '${entry.key}:',
                        style: const TextStyle(color: Colors.white, fontSize: 11),
                      ),
                    ),
                    Text(
                      parts.join('  '),
                      style: const TextStyle(color: Colors.white, fontSize: 11),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildAttStat(
    String label,
    String val, {
    Color? color,
    bool isPrimaryCard = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: isPrimaryCard ? Colors.white : Colors.grey,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          val,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 12,
            color: isPrimaryCard ? Colors.white : (color ?? Colors.black87),
          ),
        ),
      ],
    );
  }

  Widget _buildBreakdownPill(
    String label,
    String value,
    Color bg,
    Color fg,
  ) {
    return Container(
      constraints: const BoxConstraints(minWidth: 150),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withOpacity(0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Expanded(
            child: Text(
              '$label:',
              style: const TextStyle(fontSize: 11, color: Colors.white),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  /// Mongo/API can return **multiple documents for the same calendar day** (duplicate rows).
  /// Collapse to one row per `yyyy-MM-dd` using status priority, then latest `updatedAt`.
  List<dynamic> _dedupeAttendanceRecordsByCalendarDay(List<dynamic> raw) {
    if (raw.isEmpty) return raw;

    int statusRank(String? status) {
      final s = (status ?? '').trim().toLowerCase();
      if (s == 'present' || s == 'approved') return 0;
      if (s == 'half day') return 1;
      if (s == 'on leave' || s == 'company holiday') return 2;
      if (s == 'not marked') return 3;
      if (s == 'pending') return 4;
      if (s == 'absent') return 5;
      if (s == 'rejected') return 6;
      return 7;
    }

    DateTime? parseTs(dynamic v) {
      if (v == null) return null;
      try {
        return DateTime.parse(v.toString());
      } catch (_) {
        return null;
      }
    }

    final byKey = <String, Map<String, dynamic>>{};
    for (final r in raw) {
      if (r is! Map) continue;
      final m = Map<String, dynamic>.from(r);
      final key = normalizeAttendanceDateKeyForSalary(m['date']);
      if (key == null) continue;
      final prev = byKey[key];
      if (prev == null) {
        byKey[key] = m;
        continue;
      }
      final ra = statusRank(m['status'] as String?);
      final rb = statusRank(prev['status'] as String?);
      if (ra < rb) {
        byKey[key] = m;
      } else if (ra == rb) {
        final ta = parseTs(m['updatedAt']) ?? parseTs(m['createdAt']);
        final tb = parseTs(prev['updatedAt']) ?? parseTs(prev['createdAt']);
        if (ta != null && (tb == null || ta.isAfter(tb))) {
          byKey[key] = m;
        }
      }
    }

    final sorted = byKey.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return sorted.map((e) => e.value).toList();
  }

  /// Debug: single line for comparing app UI with `/attendance/month` + payroll preview.
  void _logSalaryDayCounts({
    required int year,
    required int monthIndex,
    required Map<String, dynamic> attendanceResult,
    required int displayWorkingDays,
    required int fullMonthWorkingDays,
    String? userEmail,
  }) {
    if (!kDebugMode) return;
    double? statsPd;
    double? statsPaid;
    double? statsAbsent;
    if (attendanceResult['success'] == true &&
        attendanceResult['data'] is Map<String, dynamic>) {
      final st = (attendanceResult['data'] as Map<String, dynamic>)['stats'];
      if (st is Map<String, dynamic>) {
        statsPd = (st['presentDays'] as num?)?.toDouble();
        statsPaid = (st['paidLeaveDays'] as num?)?.toDouble();
        final ab = st['absentDays'];
        if (ab is num) statsAbsent = ab.toDouble();
      }
    }
    final previewAtt = _payrollPreview?['attendance'] as Map<String, dynamic>?;
    final previewPresent = (previewAtt?['presentDays'] as num?)?.toDouble();
    final previewWdTill =
        (previewAtt?['workingDaysTillCurrentDate'] as num?)?.toInt();
    final previewPct =
        (previewAtt?['attendancePercentage'] as num?)?.toDouble();
    final wd = _workingDaysInfo?.workingDays ?? 0;
    final mtdPct =
        wd > 0 ? (_webPresentDays / wd) * 100 : null;

    debugPrint(
      '[SalaryDayCounts] email=${userEmail ?? "?"} staffId=$_staffId '
      'month=$monthIndex year=$year | '
      'headlinePresent(_presentDays)=${_presentDays.toStringAsFixed(2)} '
      'webReducerPresent(_webPresentDays)=${_webPresentDays.toStringAsFixed(2)} | '
      'clientLoopBeforeSync=${_clientPresentDaysBeforeSync.toStringAsFixed(2)} | '
      'stats.presentDays=${statsPd?.toStringAsFixed(2) ?? "n/a"} '
      'stats.paidLeaveDays=${statsPaid?.toStringAsFixed(2) ?? "n/a"} '
      'stats.absentDays=${statsAbsent?.toStringAsFixed(2) ?? "n/a"} | '
      'uiPaidLeave=${_webPaidLeaves.toStringAsFixed(2)} '
      'uiUnpaid=${_webUnpaidLeaves.toStringAsFixed(2)} | '
      'workingDaysTillDate=$displayWorkingDays fullMonthWD=$fullMonthWorkingDays | '
      'mtdPctPresentDivWdTill=${mtdPct?.toStringAsFixed(2) ?? "n/a"} | '
      'preview: present=${previewPresent?.toStringAsFixed(2) ?? "n/a"} '
      'wdTill=$previewWdTill pct=${previewPct?.toStringAsFixed(2) ?? "n/a"} | '
      'fullDayPresent=$_fullDayPresentCount halfDayPresent=$_halfDayPresentCount '
      'records=${_attendanceRecords.length}',
    );
  }

  /// Web `EmployeeSalaryOverview.tsx` → `getCalendarModifiers`: present/absent from rows only
  /// (Present/Approved green, **Absent** red — not Pending/Rejected). Holidays from holiday list;
  /// weekends from weekly pattern. App also shows **approved leave** (`leaveDates` + On Leave rows)
  /// in purple (web salary calendar has no leave tint).
  void _debugLogSalaryCalendarPayload({
    required int year,
    required int monthIndex,
  }) {
    if (!kDebugMode) return;
    final daysInMonth = DateTime(year, monthIndex + 1, 0).day;
    final holidayKeys = _holidayDates.isNotEmpty
        ? _holidayDates
        : _holidays.map((d) => _holidayCalendarKey(d)).whereType<String>().toSet();

    debugPrint(
      '[SalaryCalendar] summary year=$year month=$monthIndex '
      'records=${_attendanceRecords.length} presentDates=${_presentDates.length} '
      'absentDates=${_absentDates.length} holidayDates=${_holidayDates.length} '
      'weekOffDates=${_weekOffDates.length} leaveDates=${_leaveDates.length} '
      'holidaysModel=${_holidays.length}',
    );
    Map<String, Map<String, dynamic>> byKey = {};
    for (final r in _attendanceRecords) {
      if (r is! Map) continue;
      final k = _recordDateKey(r);
      if (k == null) continue;
      byKey[k] = Map<String, dynamic>.from(r);
    }
    for (var i = 0; i < _attendanceRecords.length; i++) {
      final r = _attendanceRecords[i];
      if (r is! Map) continue;
      final m = Map<String, dynamic>.from(r);
      final raw = m['date'];
      final key = _recordDateKey(m);
      if (key == null) continue;
      final parts = key.split('-');
      final d = parts.length == 3 ? int.tryParse(parts[2]) : null;
      final dt = d != null ? DateTime(year, monthIndex, d) : DateTime(year, monthIndex, 1);
      final dow = DateFormat('EEE').format(dt);
      final wo = _weekOffDates.isNotEmpty
          ? _weekOffDates.contains(key)
          : _isWeekOffDay(dt, holidayKeys.contains(key));
      final hol = holidayKeys.contains(key);
      debugPrint(
        '[SalaryCalendar] rec[$i] key=$key dow=$dow raw=$raw weekOff=$wo holiday=$hol '
        'status=${m['status']} isPaidLeave=${m['isPaidLeave']} comp=${m['compensationType']} '
        'leaveType=${m['leaveType']} halfDaySession=${m['halfDaySession'] != null}',
      );
    }
    for (int d = 1; d <= daysInMonth; d++) {
      final dt = DateTime(year, monthIndex, d);
      final key = DateFormat('yyyy-MM-dd').format(dt);
      final rec = byKey[key];
      final wo = _weekOffDates.isNotEmpty
          ? _weekOffDates.contains(key)
          : _isWeekOffDay(dt, holidayKeys.contains(key));
      final hol = holidayKeys.contains(key);
      final st = rec == null ? 'noRow' : '${rec['status']}';
      debugPrint(
        '[SalaryDay] $key dow=${DateFormat('EEE').format(dt)} weekOff=$wo holiday=$hol row=$st',
      );
    }
    if (_holidays.isNotEmpty) {
      final h = _holidays.first;
      debugPrint(
        '[SalaryCalendar] holiday[0] iso=${h.toIso8601String()} calendarKey=${_holidayCalendarKey(h)}',
      );
    }
  }

  Widget _buildAttendanceCalendarOverview() {
    final monthIndex = _months.indexOf(_selectedMonth) + 1;
    final year = int.tryParse(_selectedYear) ?? DateTime.now().year;
    final daysInMonth = DateTime(year, monthIndex + 1, 0).day;
    final firstDay = DateTime(year, monthIndex, 1);
    final leadingDays = firstDay.weekday % 7; // Sun=0, Mon=1...Sat=6
    final trailingDays = (7 - ((leadingDays + daysInMonth) % 7)) % 7;
    final totalCells = leadingDays + daysInMonth + trailingDays;

    final holidayKeys = _holidayDates.isNotEmpty
        ? _holidayDates
        : _holidays.map((d) => _holidayCalendarKey(d)).whereType<String>().toSet();

    // Weekends first — rows on Sun/Sat often carry "On Leave" (paid week-off); tint weekend/holiday, not purple leave.
    final weekendKeys = <String>{};
    for (int d = 1; d <= daysInMonth; d++) {
      final dt = DateTime(year, monthIndex, d);
      final key = DateFormat('yyyy-MM-dd').format(dt);
      final isWeekOff = _weekOffDates.isNotEmpty
          ? _weekOffDates.contains(key)
          : _isWeekOffDay(dt, holidayKeys.contains(key));
      if (isWeekOff) {
        weekendKeys.add(key);
      }
    }

    // Same as web: only Present/Approved → present; only Absent → absent (not Pending/Rejected).
    final presentKeys = <String>{};
    final absentKeys = <String>{};
    for (final r in _attendanceRecords) {
      final key = _recordDateKey(r);
      if (key == null) continue;
      final status = (r['status'] as String? ?? '').trim().toLowerCase();
      if (status == 'present' || status == 'approved') {
        presentKeys.add(key);
      } else if (status == 'absent') {
        absentKeys.add(key);
      }
    }

    // Leave tint only on working days (not holiday/weekend), even if row says "On Leave".
    final leaveKeys = <String>{..._leaveDates};
    for (final r in _attendanceRecords) {
      final key = _recordDateKey(r);
      if (key == null) continue;
      final status = (r['status'] as String? ?? '').trim().toLowerCase();
      if (status == 'on leave' &&
          !holidayKeys.contains(key) &&
          !weekendKeys.contains(key)) {
        leaveKeys.add(key);
      }
    }

    final List<Widget> cells = [];
    // Previous month trailing cells
    final prevMonthDate = DateTime(year, monthIndex, 0);
    final prevMonthDays = prevMonthDate.day;
    for (int i = 0; i < leadingDays; i++) {
      final d = prevMonthDays - leadingDays + i + 1;
      cells.add(_calendarCell('$d', muted: true));
    }

    int leaveDaysColored = 0;
    final int holidayCount = holidayKeys.length;
    final int weekendCount = weekendKeys.length;

    final recordByDateKey = <String, Map<String, dynamic>>{};
    for (final r in _attendanceRecords) {
      final k = _recordDateKey(r);
      if (k != null && !recordByDateKey.containsKey(k)) {
        try {
          recordByDateKey[k] = Map<String, dynamic>.from(r);
        } catch (_) {}
      }
    }

    for (int day = 1; day <= daysInMonth; day++) {
      final key = DateFormat('yyyy-MM-dd').format(DateTime(year, monthIndex, day));

      final isHoliday = holidayKeys.contains(key);
      final isWeekOff = weekendKeys.contains(key);
      Color bg = Colors.white;
      Color fg = Colors.black87;
      if (isHoliday) {
        bg = Colors.yellow.shade100;
      } else if (isWeekOff) {
        bg = Colors.grey.shade200;
      } else if (presentKeys.contains(key)) {
        bg = Colors.green.shade100;
      } else if (absentKeys.contains(key)) {
        bg = Colors.red.shade100;
      } else if (leaveKeys.contains(key)) {
        bg = Colors.purple.shade50;
        leaveDaysColored++;
      }

      cells.add(_calendarCell('$day', bg: bg, fg: fg));
    }

    // Next month leading cells
    for (int d = 1; d <= trailingDays; d++) {
      cells.add(_calendarCell('$d', muted: true));
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Attendance Calendar',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: AppColors.primary,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${_selectedMonth} $_selectedYear',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left, size: 18),
                onPressed: _goToPreviousAllowedMonth,
                visualDensity: VisualDensity.compact,
                splashRadius: 16,
              ),
              Expanded(
                child: Center(
                  child: Text(
                    '${_selectedMonth} $_selectedYear',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right, size: 18),
                onPressed: _goToNextAllowedMonth,
                visualDensity: VisualDensity.compact,
                splashRadius: 16,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _calendarLegendItem('Present Days (${_formatDayChip(_presentDays)})', Colors.green.shade100),
              _calendarLegendItem(
                'Absent Days (${_formatDayChip(((_workingDaysInfo?.workingDays ?? 0) - _presentDays).clamp(0.0, double.infinity))})',
                Colors.red.shade100,
              ),
              _calendarLegendItem('Leave ($leaveDaysColored)', Colors.purple.shade50),
              _calendarLegendItem('Holidays ($holidayCount)', Colors.yellow.shade100),
              _calendarLegendItem('Weekends ($weekendCount)', Colors.grey.shade200),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              Text('Sun', style: TextStyle(fontSize: 11)),
              Text('Mon', style: TextStyle(fontSize: 11)),
              Text('Tue', style: TextStyle(fontSize: 11)),
              Text('Wed', style: TextStyle(fontSize: 11)),
              Text('Thu', style: TextStyle(fontSize: 11)),
              Text('Fri', style: TextStyle(fontSize: 11)),
              Text('Sat', style: TextStyle(fontSize: 11)),
            ],
          ),
          const SizedBox(height: 6),
          GridView.count(
            crossAxisCount: 7,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
            childAspectRatio: 1.3,
            children: cells.take(totalCells).toList(),
          ),
        ],
      ),
    );
  }

  String? _recordDateKey(dynamic record) {
    try {
      final raw = (record?['date'] ?? '').toString().trim();
      if (raw.isEmpty) return null;
      return _normalizeDateKey(raw);
    } catch (_) {
      try {
        final raw = (record?['date'] ?? '').toString();
        if (raw.contains('T')) return raw.split('T')[0];
        if (raw.contains(' ')) return raw.split(' ')[0];
        return raw.isNotEmpty ? raw : null;
      } catch (_) {
        return null;
      }
    }
  }

  String? _normalizeDateKey(dynamic rawValue) =>
      normalizeAttendanceDateKeyForSalary(rawValue);

  /// Holiday `date` from API / model: match server-style calendar key (UTC components).
  String? _holidayCalendarKey(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) {
      final u = value.toUtc();
      return '${u.year.toString().padLeft(4, '0')}-'
          '${u.month.toString().padLeft(2, '0')}-'
          '${u.day.toString().padLeft(2, '0')}';
    }
    return _normalizeDateKey(value);
  }

  Widget _calendarCell(
    String label, {
    Color? bg,
    Color? fg,
    bool muted = false,
  }) {
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: muted ? Colors.grey.shade100 : (bg ?? Colors.white),
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: muted ? Colors.grey.shade500 : (fg ?? Colors.black87),
        ),
      ),
    );
  }

  bool _isWeekOffDay(DateTime date, bool isHoliday) {
    if (isHoliday) return false;
    final jsWeekday = date.weekday % 7; // Sun=0...Sat=6
    if (_weeklyOffPattern == 'oddEvenSaturday') {
      if (jsWeekday == 0) return true;
      if (jsWeekday == 6) return date.day % 2 == 0;
      return false;
    }
    if (_weeklyHolidays.isNotEmpty) {
      return _weeklyHolidays.contains(jsWeekday);
    }
    return jsWeekday == 0 || jsWeekday == 6;
  }

  void _goToPreviousAllowedMonth() {
    final currentIdx = _months.indexOf(_selectedMonth);
    if (currentIdx <= 0) return;
    final newDate = DateTime(int.parse(_selectedYear), currentIdx, 1);
    final newYear = '${newDate.year}';
    final newMonth = _months[newDate.month - 1];
    if (!_pickerYears.contains(newYear)) return;
    final oldYear = _selectedYear;
    setState(() {
      _selectedYear = newYear;
      _selectedMonth = newMonth;
      _clampSelectedFiltersToAllowed();
      if (_selectedYear != oldYear && !_months.contains(_selectedMonth)) {
        _selectedMonth = _months[newDate.month - 1];
      }
      _isLoading = true;
      _error = '';
    });
    _fetchSalaryData(debounce: true);
  }

  void _goToNextAllowedMonth() {
    final currentIdx = _months.indexOf(_selectedMonth);
    if (currentIdx < 0 || currentIdx >= 11) return;
    final newDate = DateTime(int.parse(_selectedYear), currentIdx + 2, 1);
    final newYear = '${newDate.year}';
    final newMonth = _months[newDate.month - 1];
    if (!_pickerYears.contains(newYear)) return;
    setState(() {
      _selectedYear = newYear;
      _selectedMonth = newMonth;
      _clampSelectedFiltersToAllowed();
      _isLoading = true;
      _error = '';
    });
    _fetchSalaryData(debounce: true);
  }

  Widget _calendarLegendItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: Colors.grey.shade300),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 10)),
      ],
    );
  }

  void _computeWebAttendanceBreakdown() {
    int fullDayPresent = 0;
    int halfDayPresent = 0;
    double presentDays = 0;
    double paidLeaves = 0;
    double unpaidLeaves = 0;
    final Map<String, Map<String, double>> byType = {};

    for (final r in _attendanceRecords) {
      final status = (r['status'] as String? ?? '').trim().toLowerCase();
      final leaveType = (r['leaveType'] as String? ?? 'Leave').trim();
      final leaveTypeLower = leaveType.toLowerCase();
      final hasHalfDaySession = r['halfDaySession'] != null;
      final isHalfDayStatus =
          status == 'half day' || leaveTypeLower == 'half day';
      final isHalfDay = isHalfDayStatus || hasHalfDaySession;

      if ((status == 'present' || status == 'approved') && !isHalfDay) {
        fullDayPresent += 1;
      }
      // Match web "Half Day Present" card:
      // count only Present/Approved/Pending records that carry halfDaySession.
      if ((status == 'present' || status == 'approved' || status == 'pending') &&
          hasHalfDaySession) {
        halfDayPresent += 1;
      }
      // Match web presentDays reducer used for salary proration.
      if (status == 'present' || status == 'approved') {
        presentDays += hasHalfDaySession ? 0.5 : 1.0;
      } else if (status == 'half day') {
        presentDays += 0.5;
      } else if (status == 'pending' && hasHalfDaySession) {
        presentDays += 0.5;
      }

      if (status == 'on leave' || status == 'half day') {
        final dayValue = isHalfDay ? 0.5 : 1.0;
        final compensationType = (r['compensationType'] as String?)?.trim().toLowerCase();
        final isPaidLeave = r['isPaidLeave'] == true ||
            compensationType == 'paid' ||
            (compensationType == null && r['isPaidLeave'] != false);

        byType.putIfAbsent(leaveType, () => {'paid': 0.0, 'unpaid': 0.0});
        if (isPaidLeave) {
          paidLeaves += dayValue;
          byType[leaveType]!['paid'] = (byType[leaveType]!['paid'] ?? 0) + dayValue;
        } else {
          unpaidLeaves += dayValue;
          byType[leaveType]!['unpaid'] = (byType[leaveType]!['unpaid'] ?? 0) + dayValue;
        }
      }
    }

    _fullDayPresentCount = fullDayPresent;
    _halfDayPresentCount = halfDayPresent;
    _webPresentDays = presentDays;
    _webPaidLeaves = paidLeaves;
    _webUnpaidLeaves = unpaidLeaves;
    _webLeaveTypeBreakdown = byType;
  }

  Widget _buildDailyBreakdownOverview() {
    if (_calculatedSalary == null ||
        _workingDaysInfo == null ||
        _proratedSalary == null) {
      return const SizedBox.shrink();
    }
    final thisMonthWorkingDays =
        _workingDaysInfo!.workingDaysFullMonth ?? _workingDaysInfo!.workingDays;
    if (thisMonthWorkingDays <= 0) return const SizedBox.shrink();

    final currencyFormat = NumberFormat.currency(locale: 'en_IN', symbol: '₹');
    final monthlyNet = _calculatedSalary!.monthly.netMonthlySalary;
    final dailySalaryNet = monthlyNet / thisMonthWorkingDays;
    final monthIndex = _months.indexOf(_selectedMonth);
    final year = int.parse(_selectedYear);
    final lastDay = DateTime(year, monthIndex + 2, 0).day;
    final holidayDateSet = _holidays
        .map((d) => DateFormat('yyyy-MM-dd').format(d))
        .toSet();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.calendar_today, color: AppColors.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Daily Breakdown',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: lastDay,
            separatorBuilder: (context, index) =>
                Divider(height: 1, color: Colors.grey.shade200),
            itemBuilder: (context, index) {
              final day = index + 1;
              final date = DateTime(year, monthIndex + 1, day);
              final dateStr = DateFormat('yyyy-MM-dd').format(date);

              Map<String, dynamic>? record;
              for (final r in _attendanceRecords) {
                if (r == null || r is! Map) continue;
                try {
                  final recDateStr = r['date']?.toString() ?? '';
                  final recDateOnly = recDateStr.contains('T')
                      ? recDateStr.split('T')[0]
                      : recDateStr.split(' ')[0];
                  if (recDateOnly == dateStr) {
                    record = Map<String, dynamic>.from(r);
                    break;
                  }
                } catch (e) {
                  // skip
                }
              }

              final isHoliday = holidayDateSet.contains(dateStr);
              final isWeekOff = _weekOffDates.isNotEmpty
                  ? _weekOffDates.contains(dateStr)
                  : _isWeekOffDay(date, isHoliday);
              final isLeave = _leaveDates.contains(dateStr);
              final isWorkingDay = !isHoliday && !isWeekOff;

              // Show details only for Present, Approved, or On Leave (same as Month Salary Details)
              final recordStatus = (record?['status'] as String? ?? '')
                  .trim()
                  .toLowerCase();
              final canShowDetails =
                  record != null &&
                  !isWeekOff &&
                  !isHoliday &&
                  (recordStatus == 'present' ||
                      recordStatus == 'approved' ||
                      recordStatus == 'on leave');

              return _buildDailyBreakdownDayRow(
                date,
                record,
                currencyFormat,
                dailySalaryNet,
                isHoliday: isHoliday,
                isWeekOff: isWeekOff,
                isLeave: isLeave,
                isWorkingDay: isWorkingDay,
                onTapDetails: canShowDetails
                    ? () => _showDayDetails(
                        context,
                        date,
                        record!,
                        currencyFormat,
                        dailySalaryNet,
                      )
                    : null,
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDailyBreakdownDayRow(
    DateTime date,
    Map<String, dynamic>? record,
    NumberFormat currencyFormat,
    double dailySalary, {
    bool isHoliday = false,
    bool isWeekOff = false,
    bool isLeave = false,
    bool isWorkingDay = false,
    VoidCallback? onTapDetails,
  }) {
    final dayName = DateFormat('EEE').format(date);
    final dateStr = DateFormat('dd MMM').format(date);

    String status = 'Not Marked';
    Color statusColor = Colors.grey;
    double salaryForDay = 0;
    double fineAmount = 0;
    int fineMinutes = 0;
    IconData statusIcon = Icons.help_outline;

    // Scheduled holiday / week-off before raw row — avoids Sundays showing as "On Leave".
    if (isHoliday) {
      status = 'Holiday';
      statusColor = Colors.orange;
      statusIcon = Icons.celebration;
    } else if (isWeekOff) {
      status = 'Week Off';
      statusColor = Colors.purple;
      statusIcon = Icons.weekend;
    } else if (record != null) {
      // Salary: only when (status Present/Approved) OR (On Leave AND isPaidLeave). Include fine for Present.
      final recordStatus = (record['status'] as String? ?? '')
          .trim()
          .toLowerCase();
      final leaveType = (record['leaveType'] as String? ?? '')
          .trim()
          .toLowerCase();
      final isHalfDay = recordStatus == 'half day' || leaveType == 'half day';
      final isPaidLeave = record['isPaidLeave'] == true;

      status = AttendanceDisplayUtil.getDailyBreakdownStatus(record);

      if (recordStatus == 'present' ||
          recordStatus == 'approved' ||
          recordStatus == 'half day') {
        if (isHalfDay) {
          statusColor = Colors.blue;
          statusIcon = Icons.schedule;
          salaryForDay = dailySalary * 0.5;
        } else {
          statusColor = Colors.green;
          statusIcon = Icons.check_circle;
          salaryForDay = dailySalary;
        }
        // Prefer attendance record fine over _dailyFineAmounts (trust backend)
        final dateKey = DateFormat('yyyy-MM-dd').format(date);
        fineAmount =
            (record['fineAmount'] as num?)?.toDouble() ??
            _dailyFineAmounts[dateKey] ??
            0.0;
        fineMinutes =
            (record['lateMinutes'] as num?)?.toInt() ??
            (record['fineHours'] as num?)?.toInt() ??
            0;
      } else if (recordStatus == 'on leave') {
        if (status == 'Comp Off') {
          statusColor = Colors.purple;
          statusIcon = Icons.event_busy;
        } else if (status == 'Week Off') {
          statusColor = Colors.purple;
          statusIcon = Icons.weekend;
        } else if (isPaidLeave) {
          statusColor = Colors.blue;
          statusIcon = Icons.event_busy;
          salaryForDay = dailySalary;
        } else {
          statusColor = Colors.blue;
          statusIcon = Icons.event_busy;
        }
        if (!isPaidLeave) {
          salaryForDay = 0;
        }
        fineAmount = 0;
      } else if (recordStatus == 'absent' || recordStatus == 'rejected') {
        statusColor = Colors.red;
        statusIcon = Icons.cancel;
        salaryForDay = 0;
        fineAmount = 0;
      } else if (recordStatus == 'pending') {
        statusColor = Colors.orange;
        statusIcon = Icons.pending;
        salaryForDay = 0;
        fineAmount = 0;
      }
    } else if (isLeave) {
      status = 'On Leave';
      statusColor = Colors.blue;
      statusIcon = Icons.event_busy;
    } else {
      final now = DateTime.now();
      if (date.isAfter(DateTime(now.year, now.month, now.day))) {
        status = 'Future';
        statusColor = Colors.grey;
        statusIcon = Icons.schedule;
      }
    }

    // Center shows actual attendance status (Present, Pending, etc.), not "Working Day"
    // since "Working Day" is already shown on the left
    final centerStatusText = status == 'Working Day' ? 'Present' : status;

    final canShowDetails = onTapDetails != null;

    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: record != null ? Colors.transparent : Colors.grey.shade50,
      child: Row(
        children: [
          SizedBox(
            width: 70,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  dateStr,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                Text(
                  dayName,
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                ),
                if (isWorkingDay)
                  Text(
                    'Working Day',
                    style: TextStyle(
                      fontSize: 9,
                      color: Colors.green.shade700,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Row(
              children: [
                Icon(statusIcon, size: 16, color: statusColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    centerStatusText,
                    style: TextStyle(
                      fontSize: 12,
                      color: statusColor,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (salaryForDay > 0)
                Text(
                  currencyFormat.format(salaryForDay),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
              if (fineAmount > 0) ...[
                const SizedBox(height: 2),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.schedule, size: 11, color: Colors.red.shade700),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        fineMinutes > 0
                            ? 'Late login fine: ${currencyFormat.format(fineAmount)} ($fineMinutes min)'
                            : 'Late login fine: ${currencyFormat.format(fineAmount)}',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: Colors.red.shade700,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
              // Net row when both salary and fine exist (same as Month Salary Details)
              if (salaryForDay > 0 && fineAmount > 0) ...[
                const SizedBox(height: 2),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'Net: ${currencyFormat.format(salaryForDay - fineAmount)}',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (canShowDetails) ...[
            const SizedBox(width: 8),
            Icon(Icons.chevron_right, size: 18, color: Colors.grey.shade400),
          ],
        ],
      ),
    );

    if (canShowDetails) {
      return InkWell(onTap: onTapDetails, child: content);
    }
    return content;
  }

  void _showDayDetails(
    BuildContext context,
    DateTime date,
    Map<String, dynamic> record,
    NumberFormat currencyFormat,
    double dailySalary,
  ) {
    final dateStr = DateFormat('EEEE, dd MMMM yyyy').format(date);
    final dateKey = DateFormat('yyyy-MM-dd').format(date);
    final status = record['status'] ?? 'N/A';
    final leaveType = record['leaveType'];
    final punchIn = record['punchIn'];
    final punchOut = record['punchOut'];
    final address = record['address'];
    final workHours = record['workHours'];
    final lateMinutes = (record['lateMinutes'] as num?)?.toInt() ?? 0;
    final earlyMinutes = (record['earlyMinutes'] as num?)?.toInt() ?? 0;
    // Late login fine only for Present/Approved/Half Day (never for Absent/Pending/On Leave)
    final recordStatusForFine = (record['status'] as String? ?? '')
        .trim()
        .toLowerCase();
    final fineAmount =
        (recordStatusForFine == 'present' ||
            recordStatusForFine == 'approved' ||
            recordStatusForFine == 'half day')
        ? ((record['fineAmount'] as num?)?.toDouble() ??
              _dailyFineAmounts[dateKey] ??
              0.0)
        : 0.0;

    final isHoliday = _holidays.any(
      (d) => _holidayCalendarKey(d) == dateKey,
    );
    final isWeekOff = _weekOffDates.contains(dateKey);
    final isWorkingDay = !isHoliday && !isWeekOff;

    String formatTime(String? isoString) {
      if (isoString == null) return 'Not recorded';
      try {
        final dateTime = DateTime.parse(isoString).toLocal();
        return DateFormat('hh:mm a').format(dateTime);
      } catch (e) {
        return 'Invalid time';
      }
    }

    final recordStatus = (status as String).trim().toLowerCase();
    final recordLeaveType = (leaveType as String? ?? '').trim().toLowerCase();
    final isHalfDay =
        recordStatus == 'half day' || recordLeaveType == 'half day';
    final isPaidLeave = record['isPaidLeave'] == true;

    double salaryForDay = 0;
    double actualFineAmount = 0;
    int actualLateMinutes = lateMinutes;

    if (recordStatus == 'present' ||
        recordStatus == 'approved' ||
        recordStatus == 'half day') {
      salaryForDay = isHalfDay ? dailySalary * 0.5 : dailySalary;
      actualFineAmount = fineAmount;
      actualLateMinutes = lateMinutes;
    } else if (recordStatus == 'on leave' && isPaidLeave) {
      salaryForDay = dailySalary;
    }

    String formatWorkHoursAsMins(num workHours) {
      final d = workHours.toDouble();
      if (d <= 0) return '0 mins';
      int mins;
      if (d < 24 && (d - d.truncate()).abs() > 0.001) {
        mins = (d * 60).round();
      } else {
        mins = d.round();
      }
      return '$mins min${mins == 1 ? '' : 's'}';
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.75,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
        ),
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
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    dateStr,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.green),
                    ),
                    child: Text(
                      AttendanceDisplayUtil.formatAttendanceDisplayStatus(
                        status,
                        leaveType,
                      ),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildDayDetailSection(
                      'Salary Information',
                      Icons.account_balance_wallet,
                      [
                        _buildDayDetailRow(
                          'Daily Salary Rate',
                          currencyFormat.format(dailySalary),
                        ),
                        if (salaryForDay > 0)
                          _buildDayDetailRow(
                            'Salary Earned',
                            currencyFormat.format(salaryForDay),
                            valueColor: Colors.green,
                            isBold: true,
                          ),
                        if (actualFineAmount > 0) ...[
                          const Divider(height: 16),
                          _buildDayDetailRow(
                            'Late Login Fine',
                            '- ${currencyFormat.format(actualFineAmount)}',
                            valueColor: Colors.red,
                            isBold: true,
                          ),
                          if (actualLateMinutes > 0)
                            _buildDayDetailRow(
                              'Late By',
                              '$actualLateMinutes minutes',
                              valueColor: Colors.red.shade600,
                            ),
                        ],
                        if (salaryForDay > 0) ...[
                          const Divider(height: 16),
                          _buildDayDetailRow(
                            'Net Salary (After Fine)',
                            currencyFormat.format(
                              salaryForDay - actualFineAmount,
                            ),
                            valueColor: Colors.green.shade700,
                            isBold: true,
                          ),
                        ],
                        if (salaryForDay == 0 &&
                            recordStatus != 'present' &&
                            recordStatus != 'approved') ...[
                          const Divider(height: 16),
                          _buildDayDetailRow(
                            'Note',
                            'No salary for ${status.toLowerCase()} status',
                            valueColor: Colors.grey.shade700,
                            isFullWidth: true,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 20),
                    _buildDayDetailSection(
                      'Attendance Details',
                      Icons.access_time,
                      [
                        _buildDayDetailRow('Status', status.toString()),
                        _buildDayDetailRow(
                          'Working Day',
                          isWorkingDay ? 'Yes' : 'No',
                        ),
                        _buildDayDetailRow('Check-in', formatTime(punchIn)),
                        _buildDayDetailRow('Check-out', formatTime(punchOut)),
                        if (workHours != null)
                          _buildDayDetailRow(
                            'Work Hours',
                            formatWorkHoursAsMins(workHours as num),
                          ),
                        if (_shiftStartTime != null || _shiftEndTime != null)
                          _buildDayDetailRow(
                            'Shift Time',
                            '${_shiftStartTime ?? 'N/A'} - ${_shiftEndTime ?? 'N/A'}',
                          ),
                        if (actualFineAmount > 0)
                          _buildDayDetailRow(
                            'Fine Amount',
                            currencyFormat.format(actualFineAmount),
                            valueColor: Colors.red,
                            isBold: true,
                          ),
                        if (actualLateMinutes > 0)
                          _buildDayDetailRow(
                            'Late Check-in',
                            '$actualLateMinutes minutes',
                            valueColor: Colors.orange.shade700,
                          ),
                        if (earlyMinutes > 0)
                          _buildDayDetailRow(
                            'Early Check-out',
                            '$earlyMinutes minutes',
                            valueColor: Colors.orange.shade700,
                          ),
                      ],
                    ),
                    if (address != null) ...[
                      const SizedBox(height: 20),
                      _buildDayDetailSection('Location', Icons.location_on, [
                        _buildDayDetailRow(
                          'Address',
                          address,
                          isFullWidth: true,
                        ),
                      ]),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

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
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }

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

  Widget _buildDropdown(
    String value,
    List<String> items,
    ValueChanged<String?> onChanged,
  ) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          items: items
              .map(
                (e) => DropdownMenuItem(
                  value: e,
                  child: Text(e, style: const TextStyle(fontSize: 12)),
                ),
              )
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}
