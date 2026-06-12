import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../config/app_colors.dart';
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
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
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
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: _loadData,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadData,
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
      padding: const EdgeInsets.all(16),
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
            currencyFormat.format(thisMonthNet),
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
              _buildStatChip(
                'Present: ${_formatDayChip(presentDays)}',
                Colors.green,
              ),
              _buildStatChip('Half Day: $halfDays', Colors.blue),
              _buildStatChip(
                'Leave: ${_formatDayChip(leaveDays)}',
                Colors.orange,
              ),
              _buildStatChip(
                'Absent: ${_formatDayChip(absentDays)}',
                Colors.red,
              ),
              if (pendingDays > 0)
                _buildStatChip('Pending: $pendingDays', Colors.orange),
            ],
          ),
          if (leaveDays > 0) ...[
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

  Widget _buildStatChip(String label, Color color) {
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
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
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
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, color: Colors.blue.shade700, size: 20),
              const SizedBox(width: 8),
              Text(
                'Salary Calculation Info',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue.shade700,
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
              style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
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
              color: Colors.blue.shade700,
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
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.black87,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
              color: isBold ? AppColors.success : Colors.black87,
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
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
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
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
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
    Color statusColor = Colors.grey;
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
          statusColor = Colors.blue;
          statusIcon = Icons.schedule;
          salaryForDay = widget.dailySalary * 0.5;
        } else {
          statusColor = Colors.green;
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
          statusColor = Colors.purple;
          statusIcon = Icons.event_busy;
        } else if (status == 'Week Off') {
          statusColor = Colors.purple;
          statusIcon = Icons.weekend;
        } else if (status == 'Paid Leave') {
          statusColor = Colors.blue;
          statusIcon = Icons.event_busy;
          salaryForDay = widget.dailySalary;
        } else {
          statusColor = Colors.blue;
          statusIcon = Icons.event_busy;
        }
        if (status != 'Paid Leave') {
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
    } else if (isHoliday) {
      status = 'Holiday';
      statusColor = Colors.orange;
      statusIcon = Icons.celebration;
    } else if (isWeekOff) {
      status = 'Week Off';
      statusColor = Colors.purple;
      statusIcon = Icons.weekend;
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
        color: record != null ? Colors.transparent : Colors.grey.shade50,
        child: Row(
          children: [
            // Date
            SizedBox(
              width: 60,
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
                ],
              ),
            ),
            const SizedBox(width: 12),

            // Status
            Expanded(
              child: Row(
                children: [
                  Icon(statusIcon, size: 16, color: statusColor),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      status,
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
                      color: Colors.green,
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
                        color: Colors.red.shade700,
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
                            color: Colors.red.shade700,
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

            // Only show chevron if details can be shown
            if (canShowDetails) ...[
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, size: 18, color: Colors.grey.shade400),
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
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
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
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Header
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
                      Icons.account_balance_wallet,
                      [
                        _buildDetailRow(
                          'Daily Salary Rate',
                          currencyFormat.format(widget.dailySalary),
                        ),
                        if (salaryForDay > 0)
                          _buildDetailRow(
                            'Salary Earned',
                            currencyFormat.format(salaryForDay),
                            valueColor: Colors.green,
                            isBold: true,
                          ),
                        if (actualFineAmount > 0) ...[
                          const Divider(height: 16),
                          _buildDetailRow(
                            'Attendance Fine',
                            '- ${currencyFormat.format(actualFineAmount)}',
                            valueColor: Colors.red,
                            isBold: true,
                          ),
                          if (actualLateMinutes > 0)
                            _buildDetailRow(
                              'Fine Minutes',
                              '$actualLateMinutes minutes',
                              valueColor: Colors.red.shade600,
                            ),
                        ],
                        if (salaryForDay > 0) ...[
                          const Divider(height: 16),
                          _buildDetailRow(
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
                          _buildDetailRow(
                            'Note',
                            'No salary for ${status.toLowerCase()} status',
                            valueColor: Colors.grey.shade700,
                            isFullWidth: true,
                          ),
                        ],
                      ],
                    ),

                    const SizedBox(height: 20),

                    // Attendance Section
                    _buildDetailSection(
                      'Attendance Details',
                      Icons.access_time,
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
                            valueColor: Colors.red.shade600,
                          ),
                          _buildDetailRow(
                            'Fine Applied',
                            currencyFormat.format(actualFineAmount),
                            valueColor: Colors.red,
                            isBold: true,
                          ),
                        ],
                      ],
                    ),

                    if (address != null) ...[
                      const SizedBox(height: 20),
                      _buildDetailSection('Location', Icons.location_on, [
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
}
