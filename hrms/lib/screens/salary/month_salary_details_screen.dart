import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../config/app_colors.dart';
import '../../config/app_text_styles.dart';
import '../../widgets/app_card.dart';
import '../../services/attendance_service.dart';
import '../../utils/salary_structure_calculator.dart';
import '../../utils/salary_fine_summary.dart';
import '../../utils/attendance_display_util.dart';
import '../../utils/mongo_date_parse.dart';
import '../../widgets/app_tab_loader.dart';

/// Month Salary Details Screen
///
/// IMPORTANT: This screen does NOT calculate any salary or days count.
/// All calculations are done in the Salary Overview Screen and passed via constructor.
///
/// ARCHITECTURE:
/// 1. Salary Overview Screen:
///    - Fetches backend stats with priority: backend > attendance API > local calculation
///    - Calculates present days: Present=1, Approved=1, Half Day=0.5 (EXCLUDES Absent, Pending)
///    - Calculates working days from backend or utility function
///    - Calculates daily salary: Monthly Gross / Working Days
///    - Calculates fine amount using grace time logic (ONLY for Present/Approved)
///    - Calls calculateProratedSalary() utility to get prorated values
///    - Passes ALL calculated values to this screen
///
/// 2. This Screen (Month Salary Details):
///    - Receives ALL calculated values via constructor parameters
///    - Only fetches attendance records for DISPLAY purposes (daily breakdown)
///    - Does NOT recalculate present days, fines, or salary
///    - Ensures 100% consistency with salary overview
///
/// VALUES USED FROM SALARY OVERVIEW (DO NOT RECALCULATE):
///
/// ┌─────────────────────────────────────────────────────────────────────┐
/// │ VALUE FROM OVERVIEW           │ HOW IT'S CALCULATED IN OVERVIEW     │
/// ├─────────────────────────────────────────────────────────────────────┤
/// │ widget.presentDays            │ Priority:                           │
/// │                               │ 1. Backend stats presentDays        │
/// │                               │ 2. Attendance API stats             │
/// │                               │ 3. Computed from records:           │
/// │                               │    Present=1, Approved=1,           │
/// │                               │    Half Day=0.5                     │
/// │                               │    (EXCLUDES Absent, Pending)       │
/// ├─────────────────────────────────────────────────────────────────────┤
/// │ widget.workingDaysInfo        │ Priority:                           │
/// │  .workingDays                 │ 1. Backend stats workingDays        │
/// │  .workingDaysFullMonth        │ 2. Attendance API stats             │
/// │  .holidayCount                │ 3. calculateWorkingDays() utility   │
/// ├─────────────────────────────────────────────────────────────────────┤
/// │ widget.dailySalary            │ Formula:                            │
/// │                               │ Monthly NET salary / This month    │
/// │                               │ working days                       │
/// ├─────────────────────────────────────────────────────────────────────┤
/// │ widget.totalFine              │ Priority:                           │
/// │                               │ 1. Backend stats Late Login Fine    │
/// │                               │ 2. Calculated with grace time:      │
/// │                               │    - ONLY Present/Approved days     │
/// │                               │    - Uses shift timing grace period │
/// │                               │    - calculateFine() utility        │
/// │                               │    (EXCLUDES Absent, Pending)       │
/// ├─────────────────────────────────────────────────────────────────────┤
/// │ widget.proratedSalary         │ calculateProratedSalary() utility:  │
/// │  .proratedGrossSalary         │ - Prorates all components          │
/// │  .proratedDeductions          │ - Based on present days ratio      │
/// │  .proratedNetSalary           │ - Includes fine deduction          │
/// │  .attendancePercentage        │ - (presentDays/workingDays)*100    │
/// ├─────────────────────────────────────────────────────────────────────┤
/// │ widget.calculatedSalary       │ calculateSalaryStructure() utility: │
/// │  .monthly                     │ - All monthly components           │
/// │  .yearly                      │ - All yearly components            │
/// │  .totalCTC                    │ - Complete salary breakdown        │
/// ├─────────────────────────────────────────────────────────────────────┤
/// │ widget.halfDayPaidLeaveCount  │ From backend stats (if available)  │
/// │ widget.leaveDays              │ From backend stats (if available)  │
/// └─────────────────────────────────────────────────────────────────────┘
///
/// WHAT THIS SCREEN FETCHES:
/// - Attendance records: ONLY for display in daily breakdown (not for calculation)
/// - Holidays: ONLY for display purposes
/// - Week off dates: ONLY for display purposes
/// - Leave dates: ONLY for display purposes
///
/// RESULT: 100% consistency between Salary Overview and Salary Details screens
class MonthSalaryDetailsScreen extends StatefulWidget {
  final int month;
  final int year;
  final double dailySalary;
  final CalculatedSalaryStructure calculatedSalary;
  final WorkingDaysInfo workingDaysInfo;
  final ProratedSalary proratedSalary;
  final double presentDays;
  final double totalFine;

  /// Per-day late login fine (date yyyy-MM-dd -> amount) from Salary Overview for Daily Breakdown.
  final Map<String, double>? dailyFineAmounts;
  final int? halfDayPaidLeaveCount;
  final double? leaveDays;

  const MonthSalaryDetailsScreen({
    super.key,
    required this.month,
    required this.year,
    required this.dailySalary,
    required this.calculatedSalary,
    required this.workingDaysInfo,
    required this.proratedSalary,
    required this.presentDays,
    required this.totalFine,
    this.dailyFineAmounts,
    this.halfDayPaidLeaveCount,
    this.leaveDays,
  });

  @override
  State<MonthSalaryDetailsScreen> createState() =>
      _MonthSalaryDetailsScreenState();
}

class _MonthSalaryDetailsScreenState extends State<MonthSalaryDetailsScreen> {
  final AttendanceService _attendanceService = AttendanceService();
  bool _isLoading = true;
  String _error = '';
  List<dynamic> _attendanceRecords = [];
  List<DateTime> _holidays = [];
  Set<String> _weekOffDates = {};
  Set<String> _leaveDates = {};

  @override
  void initState() {
    super.initState();
    // Load attendance records ONLY for display purposes (daily breakdown)
    // These records are NOT used for any salary calculations
    _loadData();
  }

  /// Loads attendance records for display purposes only
  ///
  /// NOTE: This does NOT calculate or affect salary in any way.
  /// Attendance records are only fetched to show:
  /// - Daily breakdown list (date, status, salary earned that day)
  /// - Fine breakdown list (dates with fines)
  /// - Status chips count (Present: X, Half Day: Y, etc.)
  ///
  /// All salary calculations use values from Salary Overview Screen.
  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = '';
    });

    try {
      // Fetch attendance data
      final attendanceResult = await _attendanceService.getMonthAttendance(
        widget.year,
        widget.month,
      );

      if (attendanceResult['success'] == true) {
        final data = attendanceResult['data'];
        _attendanceRecords = data['attendance'] ?? [];

        // Extract holidays
        if (data['holidays'] != null) {
          _holidays = (data['holidays'] as List)
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

        // Extract week off dates
        if (data['weekOffDates'] != null) {
          _weekOffDates = (data['weekOffDates'] as List)
              .map((e) => e.toString())
              .toSet();
        }

        // Extract leave dates
        if (data['leaveDates'] != null) {
          _leaveDates = (data['leaveDates'] as List)
              .map((e) => e.toString())
              .toSet();
        }
      }

      setState(() => _isLoading = false);
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final monthName = DateFormat(
      'MMMM yyyy',
    ).format(DateTime(widget.year, widget.month));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          'Salary Details - $monthName',
          style: const TextStyle(fontSize: 16),
        ),
      ),
      body: _isLoading
          ? const Center(child: AppTabLoader())
          : _error.isNotEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: const BoxDecoration(
                        color: AppColors.errorBg,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.error_outline_rounded,
                        size: 32,
                        color: AppColors.error,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _error,
                      style: AppTextStyles.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: _loadData,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadData,
              color: AppColors.primary,
              child: _buildContent(monthName),
            ),
    );
  }

  Widget _buildContent(String monthName) {
    final currencyFormat = NumberFormat.currency(locale: 'en_IN', symbol: '₹');

    // ========================================================================
    // SALARY CALCULATION - USES VALUES FROM SALARY OVERVIEW (NO RECALCULATION)
    // ========================================================================
    // All salary calculations are done in the Salary Overview Screen.
    // This screen only DISPLAYS those pre-calculated values.

    // This Month Net Salary = Prorated Net Salary from overview
    // Formula (calculated in overview):
    //   Prorated Gross - Prorated Deductions - Fine Amount
    final rawThisMonthNet = widget.proratedSalary.proratedNetSalary;
    final displayThisMonthNet = rawThisMonthNet < 0 ? 0.0 : rawThisMonthNet;

    // Total Fine Amount = From overview (backend or calculated with grace time)
    // Formula (calculated in overview):
    //   Sum of fines for Present/Approved days only (EXCLUDES Absent, Pending)
    final totalFines = widget.totalFine;

    // Use SAME day counts as Salary Overview (from widget) so chips match "Present Days (till today)" and calculation
    final presentForChips = widget.presentDays;
    final halfDaysForChips = widget.halfDayPaidLeaveCount ?? 0;
    final leaveForChips = widget.leaveDays ?? 0.0;
    final workingTillToday = widget.workingDaysInfo.workingDays;
    final absentForChips = (workingTillToday - presentForChips).clamp(
      0.0,
      double.infinity,
    );

    // Pending count from records only (overview doesn't show it; keep for chip if needed)
    int pendingDaysCount = 0;
    for (final record in _attendanceRecords) {
      final status = (record['status'] as String? ?? '').trim().toLowerCase();
      if (status == 'pending') pendingDaysCount++;
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Summary Card - Use same day counts as Salary Overview (widget.presentDays, etc.)
          _buildSummaryCard(
            currencyFormat,
            displayThisMonthNet,
            totalFines,
            presentForChips,
            halfDaysForChips,
            leaveForChips,
            absentForChips,
            pendingDaysCount,
          ),
          const SizedBox(height: 16),

          // Daily Breakdown (fine is shown per date in daily list)
          _buildDailyBreakdown(currencyFormat, monthName),
        ],
      ),
    );
  }

  /// Formats a day count for chip display (integer if whole, else one decimal).
  String _formatDayChip(num value) {
    final d = value.toDouble();
    return d == d.roundToDouble() ? '${d.toInt()}' : d.toStringAsFixed(1);
  }

  Widget _buildSummaryCard(
    NumberFormat currencyFormat,
    double thisMonthNet,
    double totalFines,
    double presentDays,
    int halfDays,
    double leaveDays,
    double absentDays,
    int pendingDays,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.surfaceDark, AppColors.ink],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'This Month Net Salary',
            style: TextStyle(
              color: AppColors.primary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              currencyFormat.format(thisMonthNet),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 30,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Divider(color: Colors.white.withValues(alpha: 0.12), thickness: 1, height: 1),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildStatChip(
                'Present: ${_formatDayChip(presentDays)}',
                AppColors.success,
              ),
              _buildStatChip('Half Day: $halfDays', AppColors.info),
              _buildStatChip(
                'Leave: ${_formatDayChip(leaveDays)}',
                AppColors.brand,
              ),
              _buildStatChip(
                'Absent: ${_formatDayChip(absentDays)}',
                AppColors.error,
              ),
              if (pendingDays > 0)
                _buildStatChip('Pending: $pendingDays', AppColors.brand),
            ],
          ),
          if (leaveDays > 0) ...[
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.only(left: 2),
              child: Text(
                'Leave = approved leave days this month (from attendance).',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.65),
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  /// Builds the info card showing salary calculation breakdown
  ///
  /// ALL VALUES ARE FROM SALARY OVERVIEW - NO CALCULATION DONE HERE
  /// This card only DISPLAYS the values calculated in Salary Overview Screen
  Widget _buildInfoCard(NumberFormat currencyFormat) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.infoBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.infoBg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, color: AppColors.info, size: 20),
              const SizedBox(width: 8),
              Text(
                'Salary Calculation Info',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppColors.info,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // ALL VALUES BELOW ARE FROM SALARY OVERVIEW (widget.xxx)
          _buildInfoRow(
            'Monthly Gross',
            currencyFormat.format(widget.calculatedSalary.monthly.grossSalary),
          ),
          _buildInfoRow(
            'Monthly Net',
            currencyFormat.format(
              widget.calculatedSalary.monthly.netMonthlySalary,
            ),
          ),
          _buildInfoRow(
            'Working Days',
            '${widget.workingDaysInfo.workingDays}',
          ),
          if (widget.workingDaysInfo.workingDaysFullMonth != null)
            _buildInfoRow(
              'This Month Working Days',
              '${widget.workingDaysInfo.workingDaysFullMonth}',
            ),
          _buildInfoRow(
            '1 day gross',
            currencyFormat.format(_dailyGrossFromMonthly(widget)),
          ),
          _buildInfoRow(
            'Daily Salary (1 day net)',
            currencyFormat.format(widget.dailySalary),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 12, top: 2, bottom: 4),
            child: Text(
              'Same way: Monthly gross ÷ This month WD | Monthly net ÷ This month WD (${widget.workingDaysInfo.workingDaysFullMonth ?? widget.workingDaysInfo.workingDays} days)',
              style: TextStyle(fontSize: 10, color: AppColors.textSecondary),
            ),
          ),
          const Divider(height: 16),
          _buildInfoRow(
            'Present Days (till today)',
            widget.presentDays.toStringAsFixed(1),
          ),
          if (widget.halfDayPaidLeaveCount != null &&
              widget.halfDayPaidLeaveCount! > 0)
            _buildInfoRow(
              'Half day paid leave',
              '${widget.halfDayPaidLeaveCount}',
            ),
          if (widget.leaveDays != null && widget.leaveDays! > 0)
            _buildInfoRow(
              'Leave days',
              widget.leaveDays == widget.leaveDays!.roundToDouble()
                  ? '${widget.leaveDays!.toInt()}'
                  : widget.leaveDays!.toStringAsFixed(1),
            ),
          _buildInfoRow(
            'Attendance %',
            '${widget.proratedSalary.attendancePercentage.toStringAsFixed(1)}%',
          ),
          _buildInfoRow(
            'Prorated Gross',
            currencyFormat.format(widget.proratedSalary.proratedGrossSalary),
          ),
          _buildInfoRow(
            'Prorated Deductions',
            '- ${currencyFormat.format(widget.proratedSalary.proratedDeductions)}',
          ),
          _buildInfoRow(
            'Attendance Fine',
            '- ${currencyFormat.format(widget.totalFine)}',
          ),
          const Divider(height: 16),
          _buildInfoRow(
            'This Month Net',
            currencyFormat.format(
              widget.proratedSalary.proratedNetSalary < 0
                  ? 0
                  : widget.proratedSalary.proratedNetSalary,
            ),
            isBold: true,
          ),
          const SizedBox(height: 8),
          Text(
            '* Tap on any date below to see detailed attendance information',
            style: TextStyle(
              fontSize: 11,
              color: AppColors.info,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  /// 1 day gross = Monthly gross / This month working days (same way as daily net)
  double _dailyGrossFromMonthly(MonthSalaryDetailsScreen w) {
    final wd =
        w.workingDaysInfo.workingDaysFullMonth ?? w.workingDaysInfo.workingDays;
    return wd > 0 ? w.calculatedSalary.monthly.grossSalary / wd : 0;
  }

  Widget _buildInfoRow(String label, String value, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textPrimary,
                fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
              color: isBold ? AppColors.success : AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDailyBreakdown(NumberFormat currencyFormat, String monthName) {
    final lastDay = DateTime(widget.year, widget.month + 1, 0).day;
    final holidayDateSet = _holidays
        .map((d) => DateFormat('yyyy-MM-dd').format(d))
        .toSet();

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFECEEF1)),
        boxShadow: kSoftCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFFECEEF1))),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.calendar_today_outlined,
                      color: AppColors.primaryText, size: 20),
                ),
                const SizedBox(width: 12),
                Text(
                  'Daily Breakdown',
                  style: AppTextStyles.headingSmall,
                ),
              ],
            ),
          ),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: lastDay,
            separatorBuilder: (context, index) =>
                Divider(height: 1, color: const Color(0xFFECEEF1)),
            itemBuilder: (context, index) {
              final day = index + 1;
              final date = DateTime(widget.year, widget.month, day);
              final dateStr = DateFormat('yyyy-MM-dd').format(date);

              // Match Mongo/API instants to calendar day in IST (same as Salary Overview).
              dynamic record;
              for (final r in _attendanceRecords) {
                if (r == null || r is! Map) continue;
                try {
                  final key = attendanceIndiaCalendarKey((r as Map)['date']);
                  if (key != null && key == dateStr) {
                    record = r;
                    break;
                  }
                } catch (e) {
                  // skip
                }
              }

              // Determine if it's a holiday, week off, or leave
              final isHoliday = holidayDateSet.contains(dateStr);
              final isWeekOff = _weekOffDates.contains(dateStr);
              final isLeave = _leaveDates.contains(dateStr);

              return _buildDayRow(
                date,
                record,
                currencyFormat,
                isHoliday: isHoliday,
                isWeekOff: isWeekOff,
                isLeave: isLeave,
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDayRow(
    DateTime date,
    dynamic record,
    NumberFormat currencyFormat, {
    bool isHoliday = false,
    bool isWeekOff = false,
    bool isLeave = false,
  }) {
    final dayName = DateFormat('EEE').format(date);
    final dateStr = DateFormat('dd MMM').format(date);

    String status = 'Not Marked';
    Color statusColor = AppColors.textCaption;
    double salaryForDay = 0;
    double fineAmount = 0; // Initialize fine amount
    int fineMinutes =
        0; // From attendances collection: fineHours (total min) or lateMinutes
    IconData statusIcon = Icons.help_outline;

    // Attendance record takes precedence – use status from attendance when available
    if (record != null) {
      final recordStatus = (record['status'] as String? ?? '')
          .trim()
          .toLowerCase();
      final leaveType = (record['leaveType'] as String? ?? '')
          .trim()
          .toLowerCase();
      final isHalfDay = recordStatus == 'half day' || leaveType == 'half day';

      status = AttendanceDisplayUtil.getDailyBreakdownStatus(record);

      if (recordStatus == 'present' || recordStatus == 'approved') {
        if (isHalfDay) {
          statusColor = AppColors.info;
          statusIcon = Icons.schedule;
          salaryForDay = widget.dailySalary * 0.5;
        } else {
          statusColor = AppColors.success;
          statusIcon = Icons.check_circle;
          salaryForDay = widget.dailySalary;
        }

        // Prefer per-day fine from Overview (already late/early + break); else the
        // record's own total fine (late/early + break overage).
        final dateKey = DateFormat('yyyy-MM-dd').format(date);
        final recordTotal = recordTotalFineAmount(record);
        fineAmount =
            widget.dailyFineAmounts?[dateKey] ??
            (recordTotal > 0 ? recordTotal : 0.0);
        // Total fine duration in minutes (late + early + break).
        fineMinutes = recordTotalFineMinutes(record) > 0
            ? recordTotalFineMinutes(record)
            : ((record['lateMinutes'] as num?)?.toInt() ?? 0);
      } else if (recordStatus == 'on leave') {
        if (status == 'Comp Off') {
          statusColor = const Color(0xFF7C3AED);
          statusIcon = Icons.event_busy;
        } else if (status == 'Week Off') {
          statusColor = const Color(0xFF7C3AED);
          statusIcon = Icons.weekend;
        } else if (status == 'Paid Leave') {
          statusColor = AppColors.info;
          statusIcon = Icons.event_busy;
          salaryForDay = widget.dailySalary;
        } else {
          statusColor = AppColors.info;
          statusIcon = Icons.event_busy;
        }
        if (status != 'Paid Leave') {
          salaryForDay = 0;
        }
        fineAmount = 0;
      } else if (recordStatus == 'absent' || recordStatus == 'rejected') {
        statusColor = AppColors.error;
        statusIcon = Icons.cancel;
        salaryForDay = 0;
        fineAmount = 0;
      } else if (recordStatus == 'pending') {
        statusColor = AppColors.warning;
        statusIcon = Icons.pending;
        salaryForDay = 0;
        fineAmount = 0;
      }
    } else if (isHoliday) {
      status = 'Holiday';
      statusColor = AppColors.warning;
      statusIcon = Icons.celebration;
    } else if (isWeekOff) {
      status = 'Week Off';
      statusColor = const Color(0xFF7C3AED);
      statusIcon = Icons.weekend;
    } else if (isLeave) {
      status = 'On Leave';
      statusColor = AppColors.info;
      statusIcon = Icons.event_busy;
    } else {
      final now = DateTime.now();
      if (date.isAfter(DateTime(now.year, now.month, now.day))) {
        status = 'Future';
        statusColor = AppColors.textCaption;
        statusIcon = Icons.schedule;
      }
    }

    // Determine if details should be shown when tapped
    // Only show details for Present/Approved or On Leave status
    // Don't show for Absent, Week Off, Holiday, Pending, Future, Not Marked
    bool canShowDetails = false;
    if (record != null && !isWeekOff && !isHoliday) {
      final recordStatus = (record['status'] as String? ?? '')
          .trim()
          .toLowerCase();
      // Show details only for Present, Approved, or On Leave
      canShowDetails =
          recordStatus == 'present' ||
          recordStatus == 'approved' ||
          recordStatus == 'on leave';
    }

    return InkWell(
      onTap: canShowDetails
          ? () => _showDayDetails(date, record, currencyFormat)
          : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        color: record != null ? Colors.transparent : AppColors.background,
        child: Row(
          children: [
            // Date
            SizedBox(
              width: 56,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    dateStr,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    dayName,
                    style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),

            // Status
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(statusIcon, size: 14, color: statusColor),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          status,
                          style: TextStyle(
                            fontSize: 12,
                            color: statusColor == AppColors.textCaption
                                ? AppColors.textSecondary
                                : statusColor,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Salary/Fine on right side
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Show salary if earned that day
                if (salaryForDay > 0)
                  Text(
                    currencyFormat.format(salaryForDay),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: AppColors.success,
                    ),
                  ),
                // Show late login fine on that day when applicable (amount + fine duration in mins from attendances)
                if (fineAmount > 0) ...[
                  const SizedBox(height: 2),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.schedule,
                        size: 11,
                        color: AppColors.error,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          fineMinutes > 0
                              ? 'Attendance fine: ${currencyFormat.format(fineAmount)} ($fineMinutes min)'
                              : 'Attendance fine: ${currencyFormat.format(fineAmount)}',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: AppColors.error,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
                // Show net if both salary and fine exist
                if (salaryForDay > 0 && fineAmount > 0) ...[
                  const SizedBox(height: 2),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.inputFill,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'Net: ${currencyFormat.format(salaryForDay - fineAmount)}',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ],
            ),

            // Only show chevron if details can be shown
            if (canShowDetails) ...[
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right_rounded, size: 20, color: AppColors.textCaption),
            ],
          ],
        ),
      ),
    );
  }

  /// Work hours from API are in minutes; legacy may be hours. Format as "X mins".
  String _formatWorkHoursAsMins(num workHours) {
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

  void _showDayDetails(
    DateTime date,
    dynamic record,
    NumberFormat currencyFormat,
  ) {
    final dateStr = DateFormat('EEEE, dd MMMM yyyy').format(date);
    final status = record['status'] ?? 'N/A';
    final leaveType = record['leaveType'];
    final punchIn = record['punchIn'];
    final punchOut = record['punchOut'];
    final address = record['address'];
    final workHours = record['workHours'];
    final lateMinutes = record['lateMinutes'] ?? 0;
    // Total day fine = late/early + break overage.
    final fineAmount = recordTotalFineAmount(record);
    final fineMinutesTotal = recordTotalFineMinutes(record);

    String formatTime(String? isoString) {
      if (isoString == null) return 'Not recorded';
      try {
        final dateTime = DateTime.parse(isoString).toLocal();
        return DateFormat('hh:mm:ss a').format(dateTime);
      } catch (e) {
        return 'Invalid time';
      }
    }

    final recordStatus = (status as String).trim().toLowerCase();
    final recordLeaveType = (leaveType as String? ?? '').trim().toLowerCase();
    final isHalfDay =
        recordStatus == 'half day' || recordLeaveType == 'half day';

    // Calculate salary ONLY for Present/Approved status
    // EXCLUDE Absent and Pending from salary and fine calculation
    double salaryForDay = 0;
    double actualFineAmount = 0;
    int actualLateMinutes = lateMinutes;

    if (recordStatus == 'present' || recordStatus == 'approved') {
      salaryForDay = isHalfDay ? widget.dailySalary * 0.5 : widget.dailySalary;

      // Total fine + total fine minutes (late/early + break) from the record.
      actualFineAmount = fineAmount;
      actualLateMinutes = fineMinutesTotal > 0
          ? fineMinutesTotal
          : ((lateMinutes as num?)?.toInt() ?? 0);
    } else {
      // NO salary and NO FINE for Absent, Pending, On Leave, etc.
      salaryForDay = 0;
      actualFineAmount = 0;
      actualLateMinutes = 0;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.75,
        clipBehavior: Clip.antiAlias,
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
        ),
        child: Column(
          children: [
            // Handle
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.textHint,
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFFECEEF1))),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    dateStr,
                    style: AppTextStyles.headingMedium,
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.successBg,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      AttendanceDisplayUtil.formatAttendanceDisplayStatus(
                        status,
                        leaveType,
                      ),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.success,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Details
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Salary Section
                    _buildDetailSection(
                      'Salary Information',
                      Icons.account_balance_wallet_outlined,
                      [
                        _buildDetailRow(
                          'Daily Salary Rate',
                          currencyFormat.format(widget.dailySalary),
                        ),
                        if (salaryForDay > 0)
                          _buildDetailRow(
                            'Salary Earned',
                            currencyFormat.format(salaryForDay),
                            valueColor: AppColors.success,
                            isBold: true,
                          ),
                        if (actualFineAmount > 0) ...[
                          const Divider(height: 16),
                          _buildDetailRow(
                            'Attendance Fine',
                            '- ${currencyFormat.format(actualFineAmount)}',
                            valueColor: AppColors.error,
                            isBold: true,
                          ),
                          if (actualLateMinutes > 0)
                            _buildDetailRow(
                              'Fine Minutes',
                              '$actualLateMinutes minutes',
                              valueColor: AppColors.error,
                            ),
                        ],
                        if (salaryForDay > 0) ...[
                          const Divider(height: 16),
                          _buildDetailRow(
                            'Net Salary (After Fine)',
                            currencyFormat.format(
                              salaryForDay - actualFineAmount,
                            ),
                            valueColor: AppColors.success,
                            isBold: true,
                          ),
                        ],
                        if (salaryForDay == 0 &&
                            recordStatus != 'present' &&
                            recordStatus != 'approved') ...[
                          const Divider(height: 16),
                          _buildDetailRow(
                            'Note',
                            'No salary for ${status.toLowerCase()} status',
                            valueColor: AppColors.textSecondary,
                            isFullWidth: true,
                          ),
                        ],
                      ],
                    ),

                    const SizedBox(height: 20),

                    // Attendance Section
                    _buildDetailSection(
                      'Attendance Details',
                      Icons.access_time_rounded,
                      [
                        _buildDetailRow('Punch In', formatTime(punchIn)),
                        _buildDetailRow('Punch Out', formatTime(punchOut)),
                        if (workHours != null)
                          _buildDetailRow(
                            'Work Hours',
                            _formatWorkHoursAsMins(workHours as num),
                          ),
                        if (actualLateMinutes > 0 && actualFineAmount > 0) ...[
                          const Divider(height: 16),
                          _buildDetailRow(
                            'Late Minutes',
                            '$actualLateMinutes minutes',
                            valueColor: AppColors.error,
                          ),
                          _buildDetailRow(
                            'Fine Applied',
                            currencyFormat.format(actualFineAmount),
                            valueColor: AppColors.error,
                            isBold: true,
                          ),
                        ],
                      ],
                    ),

                    if (address != null) ...[
                      const SizedBox(height: 20),
                      _buildDetailSection('Location', Icons.location_on_outlined, [
                        _buildDetailRow('Address', address, isFullWidth: true),
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

  Widget _buildDetailSection(
    String title,
    IconData icon,
    List<Widget> children,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: AppColors.primaryText),
            const SizedBox(width: 8),
            Text(
              title,
              style: AppTextStyles.headingSmall.copyWith(fontSize: 15),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFECEEF1)),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _buildDetailRow(
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
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
                    color: valueColor ?? AppColors.textPrimary,
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
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                ),
                const SizedBox(width: 16),
                Flexible(
                  child: Text(
                    value,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
                      color: valueColor ?? AppColors.textPrimary,
                    ),
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
    );
  }
}
