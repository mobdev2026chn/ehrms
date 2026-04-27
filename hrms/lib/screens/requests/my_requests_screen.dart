import 'package:flutter/material.dart';
import 'dart:async';
import 'package:intl/intl.dart';
import 'dart:io';
import 'package:hrms/utils/snackbar_utils.dart';
import 'package:hrms/utils/error_message_utils.dart';
import 'package:hrms/utils/request_success_dialog.dart';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:hrms/widgets/app_tab_loader.dart';
import '../../config/app_colors.dart';
import '../../services/request_service.dart';
import '../../services/auth_service.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/menu_icon_button.dart';

/// Returns true if [s] is half-day leave type (case and space insensitive).
/// Backend may send "half day", "Half Day", "halfday", "half", "Half", etc.
bool _isHalfDayLeave(String? s) {
  if (s == null || s.isEmpty) return false;
  final n = s.toLowerCase().replaceAll(RegExp(r'\s+'), '');
  return n == 'halfday' || n == 'half';
}

class MyRequestsScreen extends StatefulWidget {
  final int initialTabIndex;
  final int? dashboardTabIndex;
  final void Function(int index)? onNavigateToIndex;

  /// Called when user changes tab so dashboard can keep requested tab in sync for quick-action navigation.
  final void Function(int index)? onTabIndexChanged;

  /// When true, this screen is the visible tab (e.g. user tapped Request in bottom nav).
  final bool? isActiveTab;

  const MyRequestsScreen({
    super.key,
    this.initialTabIndex = 0,
    this.dashboardTabIndex,
    this.onNavigateToIndex,
    this.onTabIndexChanged,
    this.isActiveTab,
  });

  @override
  State<MyRequestsScreen> createState() => _MyRequestsScreenState();
}

class _MyRequestsScreenState extends State<MyRequestsScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  final GlobalKey<_LeaveRequestsTabState> _leaveTabKey = GlobalKey();
  final GlobalKey<_LoanRequestsTabState> _loanTabKey = GlobalKey();
  final GlobalKey<_ExpenseRequestsTabState> _expenseTabKey = GlobalKey();
  final GlobalKey<_PermissionRequestsTabState> _permissionTabKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 4,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, 3),
    );
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        widget.onTabIndexChanged?.call(_tabController.index);
        setState(() {});
      }
    });
  }

  @override
  void didUpdateWidget(MyRequestsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActiveTab == true && oldWidget.isActiveTab != true) {
      _refreshCurrentTab();
    }
  }

  void _refreshCurrentTab() {
    switch (_tabController.index) {
      case 0:
        _leaveTabKey.currentState?.refresh();
        break;
      case 1:
        _loanTabKey.currentState?.refresh();
        break;
      case 2:
        _expenseTabKey.currentState?.refresh();
        break;
      case 3:
        _permissionTabKey.currentState?.refresh();
        break;
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerHighest,
      appBar: AppBar(
        leading: const MenuIconButton(),
        title: Text(
          'My Requests',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_alt_outlined),
            tooltip: 'Toggle Filters',
            onPressed: () {
              switch (_tabController.index) {
                case 0:
                  _leaveTabKey.currentState?.toggleFilters();
                  break;
                case 1:
                  _loanTabKey.currentState?.toggleFilters();
                  break;
                case 2:
                  _expenseTabKey.currentState?.toggleFilters();
                  break;
                case 3:
                  _permissionTabKey.currentState?.toggleFilters();
                  break;
              }
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: false,
          labelColor: Colors.black,
          unselectedLabelColor: Colors.black,
          labelStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
          unselectedLabelStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
          indicatorColor: colorScheme.primary,
          indicatorSize: TabBarIndicatorSize.tab,
          labelPadding: EdgeInsets.zero,
          indicator: BoxDecoration(
            color: colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(6),
          ),
          tabs: [
            Tab(child: _CompactRequestTab(text: 'Leave', icon: Icons.calendar_today)),
            Tab(child: _CompactRequestTab(text: 'Loan', icon: Icons.account_balance_wallet)),
            Tab(child: _CompactRequestTab(text: 'Expense', icon: Icons.receipt)),
            Tab(child: _CompactRequestTab(text: 'Permission', icon: Icons.fact_check_outlined)),
          ],
          onTap: (index) {
            _tabController.animateTo(index);
            setState(() {});
          },
        ),
      ),
      drawer: AppDrawer(
        currentIndex: widget.dashboardTabIndex ?? 1,
        onNavigateToIndex: widget.onNavigateToIndex,
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          LeaveRequestsTab(key: _leaveTabKey),
          LoanRequestsTab(key: _loanTabKey),
          ExpenseRequestsTab(key: _expenseTabKey),
          PermissionRequestsTab(key: _permissionTabKey),
        ],
      ),
      floatingActionButton: _buildFab(),
    );
  }

  Widget? _buildFab() {
    final style = const TextStyle(fontSize: 13, fontWeight: FontWeight.bold);
    switch (_tabController.index) {
      case 0: // Leave
        return SizedBox(
          height: 40,
          child: FloatingActionButton.extended(
            foregroundColor: Colors.white,
            onPressed: () => _leaveTabKey.currentState?.showApplyLeaveDialog(),
            label: Text('Apply Leave', style: style),
            icon: const Icon(Icons.add, size: 18),
            backgroundColor: AppColors.primary,
          ),
        );
      case 1: // Loan
        return SizedBox(
          height: 40,
          child: FloatingActionButton.extended(
            foregroundColor: Colors.white,
            onPressed: () => _loanTabKey.currentState?.showRequestLoanDialog(),
            label: Text('Request Loan', style: style),
            icon: const Icon(Icons.add, size: 18),
            backgroundColor: AppColors.primary,
          ),
        );
      case 2: // Expense
        return SizedBox(
          height: 40,
          child: FloatingActionButton.extended(
            foregroundColor: Colors.white,
            onPressed: () =>
                _expenseTabKey.currentState?.showClaimExpenseDialog(),
            label: Text('Claim Expense', style: style),
            icon: const Icon(Icons.add, size: 18),
            backgroundColor: AppColors.primary,
          ),
        );
      case 3: // Permission
        return SizedBox(
          height: 40,
          child: FloatingActionButton.extended(
            foregroundColor: Colors.white,
            onPressed: () =>
                _permissionTabKey.currentState?.showRequestPermissionDialog(),
            label: Text('Request Permission', style: style),
            icon: const Icon(Icons.add, size: 18),
            backgroundColor: AppColors.primary,
          ),
        );
      default:
        return null;
    }
  }
}

class _CompactRequestTab extends StatelessWidget {
  final String text;
  final IconData icon;

  const _CompactRequestTab({required this.text, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 19),
        const SizedBox(height: 2),
        Text(
          text,
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

/// Shows a single calendar in a bottom sheet to select from-date and to-date (range) in the same calendar.
/// Returns [DateTimeRange] with start at 00:00:00 and end at 23:59:59 of the selected days, or null if dismissed.
Future<DateTimeRange?> showDateRangePickerSameCalendar({
  required BuildContext context,
  required DateTime firstDate,
  required DateTime lastDate,
  DateTime? initialStart,
  DateTime? initialEnd,
}) async {
  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
  DateTime _clampDay(DateTime d, DateTime min, DateTime max) {
    final day = _dateOnly(d);
    final minDay = _dateOnly(min);
    final maxDay = _dateOnly(max);
    if (day.isBefore(minDay)) return minDay;
    if (day.isAfter(maxDay)) return maxDay;
    return day;
  }

  final firstDay = _dateOnly(firstDate);
  final lastDay = _dateOnly(lastDate);
  final now = DateTime.now();
  DateTime? rangeStart = initialStart != null
      ? DateTime(initialStart.year, initialStart.month, initialStart.day)
      : null;
  DateTime? rangeEnd = initialEnd != null
      ? DateTime(initialEnd.year, initialEnd.month, initialEnd.day)
      : null;
  DateTime focusedDay = _clampDay(
    rangeEnd ?? rangeStart ?? DateTime(now.year, now.month, now.day),
    firstDay,
    lastDay,
  );

  final result = await showModalBottomSheet<DateTimeRange>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      return StatefulBuilder(
        builder: (context, setModalState) {
          return DraggableScrollableSheet(
            initialChildSize: 0.6,
            minChildSize: 0.4,
            maxChildSize: 0.9,
            expand: false,
            builder: (context, scrollController) => Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Select from - to date',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            if (rangeStart != null && rangeEnd != null) {
                              final start = rangeStart!.isAfter(rangeEnd!)
                                  ? rangeEnd!
                                  : rangeStart!;
                              final end = rangeStart!.isAfter(rangeEnd!)
                                  ? rangeStart!
                                  : rangeEnd!;
                              Navigator.pop(
                                context,
                                DateTimeRange(start: start, end: end),
                              );
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Select start and end date in the calendar',
                                  ),
                                ),
                              );
                            }
                          },
                          child: Text('Apply'),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      controller: scrollController,
                      child: TableCalendar(
                        firstDay: firstDay,
                        lastDay: lastDay,
                        focusedDay: focusedDay,
                        rangeStartDay: rangeStart,
                        rangeEndDay: rangeEnd,
                        rangeSelectionMode: RangeSelectionMode.enforced,
                        onRangeSelected: (start, end, focused) {
                          setModalState(() {
                            rangeStart = start;
                            rangeEnd = end;
                            focusedDay = _clampDay(focused, firstDay, lastDay);
                          });
                        },
                        onPageChanged: (focused) {
                          setModalState(
                            () => focusedDay = _clampDay(focused, firstDay, lastDay),
                          );
                        },
                        calendarFormat: CalendarFormat.month,
                        headerStyle: HeaderStyle(
                          formatButtonVisible: false,
                          titleCentered: true,
                        ),
                        calendarStyle: CalendarStyle(
                          rangeStartDecoration: BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                          ),
                          rangeEndDecoration: BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                          ),
                          rangeHighlightColor: AppColors.primary.withOpacity(
                            0.2,
                          ),
                          selectedDecoration: BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                          ),
                          todayDecoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.5),
                            shape: BoxShape.circle,
                          ),
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
    },
  );
  return result;
}

/// Reusable bottom sheet for request details (Leave, Loan, Expense, Payslip).
class _RequestDetailBottomSheet extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color iconColor;
  final List<Widget> children;

  const _RequestDetailBottomSheet({
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withOpacity(0.3),
            blurRadius: 20,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.35,
        maxChildSize: 0.92,
        expand: false,
        builder: (context, scrollController) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.outline,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const SizedBox(width: 20),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: iconColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: iconColor, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Flexible(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: colorScheme.outline),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: children,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(context),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: colorScheme.onPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text('Close'),
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
}

// --- LEAVE TAB ---

class LeaveRequestsTab extends StatefulWidget {
  const LeaveRequestsTab({super.key});

  @override
  State<LeaveRequestsTab> createState() => _LeaveRequestsTabState();
}

class _LeaveRequestsTabState extends State<LeaveRequestsTab> {
  final RequestService _requestService = RequestService();
  List<dynamic> _leaves = [];
  List<dynamic> _leaveBalances = [];
  bool _isLoading = true;
  bool _isLoadingBalances = true;
  String _selectedStatus = 'All Status';
  final List<String> _statusOptions = [
    'All Status',
    'Pending',
    'Approved',
    'Rejected',
  ];
  Timer? _debounce;
  final TextEditingController _searchController = TextEditingController();
  DateTime? _startDate;
  DateTime? _endDate;
  int _currentPage = 1;
  final int _itemsPerPage = 10;
  int _totalPages = 0;
  bool _showFilters = false;

  /// Start of month for [date]; end of that month (23:59:59) for [_endDate].
  static DateTime _firstDayOfMonth(DateTime date) =>
      DateTime(date.year, date.month, 1);
  static DateTime _lastDayOfMonth(DateTime date) =>
      DateTime(date.year, date.month + 1, 0, 23, 59, 59, 999);

  void toggleFilters() {
    setState(() {
      _showFilters = !_showFilters;
    });
  }

  void refresh() {
    _fetchLeaves();
  }

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _startDate = _firstDayOfMonth(now);
    _endDate = _lastDayOfMonth(now);
    _fetchLeaves();
    _fetchLeaveBalances();
  }

  Future<void> _fetchLeaveBalances() async {
    setState(() => _isLoadingBalances = true);

    final start = _startDate;
    final end = _endDate;
    final result = await _requestService.getLeaveTypes(
      startDate: start,
      endDate: end,
      month: start == null ? DateTime.now().month : null,
      year: start == null ? DateTime.now().year : null,
    );

    if (mounted) {
      if (result['success']) {
        setState(() {
          _leaveBalances = (result['data'] as List).where((e) {
            final type = e['type'].toString().toLowerCase();
            return type != 'paid' && type != 'paid leave';
          }).toList();
          _isLoadingBalances = false;
        });
      } else {
        setState(() => _isLoadingBalances = false);
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _fetchLeaves() async {
    _fetchLeaveBalances(); // Also refresh balances
    setState(() => _isLoading = true);
    final result = await _requestService.getLeaveRequests(
      status: _selectedStatus,
      search: _searchController.text,
      startDate: _startDate,
      endDate: _endDate,
      page: _currentPage,
      limit: _itemsPerPage,
    );
    if (mounted) {
      if (result['success']) {
        setState(() {
          if (result['data'] is Map) {
            _leaves = result['data']['leaves'] ?? [];
            final pagination = result['data']['pagination'];
            if (pagination != null) {
              _totalPages = pagination['pages'] ?? 0;
              _currentPage = pagination['page'] ?? 1;
            }
          } else if (result['data'] is List) {
            _leaves = result['data'];
            _totalPages = 1;
            _currentPage = 1;
          }
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
        SnackBarUtils.showSnackBar(
          context,
          ErrorMessageUtils.sanitizeForDisplay(
            result['message']?.toString(),
            fallback: 'Failed to fetch leaves',
          ),
          isError: true,
        );
      }
    }
  }

  /// Pick from-date and to-date in same calendar; leaves and balances are shown for that range.
  Future<void> _pickDateRange() async {
    final picked = await showDateRangePickerSameCalendar(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialStart: _startDate,
      initialEnd: _endDate,
    );
    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
      _fetchLeaves();
    }
  }

  void _resetToCurrentMonth() {
    final now = DateTime.now();
    setState(() {
      _startDate = _firstDayOfMonth(now);
      _endDate = _lastDayOfMonth(now);
    });
    _fetchLeaves();
  }

  void showApplyLeaveDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      builder: (ctx) => ApplyLeaveDialog(onSuccess: _fetchLeaves),
    );
  }

  void _showLeaveDetails(Map<String, dynamic> leave) {
    // Debug: log leave response for Half day on / approvedBy
    final halfDayOnValue =
        leave['halfDayType']?.toString().trim() ??
        leave['halfDaySession']?.toString().trim() ??
        (leave['session'] == '1'
            ? 'First Half Day'
            : leave['session'] == '2'
            ? 'Second Half Day'
            : '—');
    final start = DateFormat(
      'MMM dd, yyyy',
    ).format(DateTime.parse(leave['startDate']).toLocal());
    final end = DateFormat(
      'MMM dd, yyyy',
    ).format(DateTime.parse(leave['endDate']).toLocal());
    final appliedDate = DateFormat(
      'MMM dd, yyyy',
    ).format(DateTime.parse(leave['createdAt']));
    // Resolve approvedBy / rejectedBy: backend may populate with { name, email }
    String approvedBy = '—';
    String rejectedBy = '—';
    final approver = leave['approvedBy'];
    final rejector = leave['rejectedBy'];
    if (approver != null) {
      if (approver is Map && approver['name'] != null) {
        approvedBy = approver['name'].toString().trim();
        if (approvedBy.isEmpty) approvedBy = '—';
      } else {
        approvedBy = 'System';
      }
    }
    if (rejector != null) {
      if (rejector is Map && rejector['name'] != null) {
        rejectedBy = rejector['name'].toString().trim();
        if (rejectedBy.isEmpty) rejectedBy = '—';
      } else {
        rejectedBy = 'System';
      }
    } else if (leave['status'] == 'Rejected' && approver != null) {
      rejectedBy = approvedBy; // Backend may use approvedBy for rejector
    }
    final rejectionReason = leave['rejectionReason']?.toString().trim();
    final isRejected = leave['status'] == 'Rejected';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _RequestDetailBottomSheet(
        title: 'Leave Details',
        icon: Icons.calendar_today,
        iconColor: AppColors.primary,
        children: [
          _detailRow('Leave Type', leave['leaveType'] ?? ''),
          if (_isHalfDayLeave(leave['leaveType']))
            _detailRow('Half day on', halfDayOnValue),
          _detailRow('Start Date', start),
          _detailRow('End Date', end),
          _detailRow('Days', '${leave['days']}'),
          _detailRow('Applied Date', appliedDate),
          _detailRow('Status', leave['status'] ?? ''),
          if (isRejected) ...[
            _detailRow('Rejected By', rejectedBy),
            if (rejectionReason != null && rejectionReason.isNotEmpty)
              _detailRow('Rejection Reason', rejectionReason),
          ] else
            _detailRow('Approved By', approvedBy),
          if (leave['reason'] != null && leave['reason'].toString().isNotEmpty)
            _detailRow('Reason', leave['reason']),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Widget _buildLeaveCard(Map<String, dynamic> leave) {
    final colorScheme = Theme.of(context).colorScheme;
    final start = DateFormat(
      'MMM dd, yyyy',
    ).format(DateTime.parse(leave['startDate']).toLocal());
    final end = DateFormat(
      'MMM dd, yyyy',
    ).format(DateTime.parse(leave['endDate']).toLocal());
    final appliedDate = DateFormat(
      'MMM dd, yyyy',
    ).format(DateTime.parse(leave['createdAt']));
    final approver = leave['approvedBy'];
    final rejector = leave['rejectedBy'];
    final isRejectedLeave = leave['status'] == 'Rejected';
    final approvedBy = approver != null
        ? (approver is Map ? approver['name'] : 'System')
        : '-';
    final rejectedBy = rejector != null
        ? (rejector is Map ? rejector['name'] : 'System')
        : (isRejectedLeave && approver != null ? approvedBy : '-');

    Color statusColor = Colors.grey;
    if (leave['status'] == 'Approved') {
      statusColor = AppColors.success;
    } else if (leave['status'] == 'Rejected') {
      statusColor = AppColors.error;
    } else if (leave['status'] == 'Pending') {
      statusColor = AppColors.warning;
    }

    return InkWell(
      onTap: () => _showLeaveDetails(leave),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colorScheme.outline),
          boxShadow: [
            BoxShadow(
              color: colorScheme.shadow.withOpacity(0.08),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              // Icon
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.calendar_today,
                  color: AppColors.primary,
                  size: 32,
                ),
              ),
              const SizedBox(width: 16),
              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Leave Type and Status
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            leave['leaveType'] ?? 'Leave',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onSurface,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: statusColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            leave['status'] ?? '',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: statusColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Details
                    _buildCardDetailRow(
                      Icons.date_range,
                      'Dates',
                      '$start - $end',
                    ),
                    const SizedBox(height: 4),
                    _buildCardDetailRow(
                      Icons.event,
                      'Days',
                      '${leave['days']}',
                    ),
                    const SizedBox(height: 4),
                    _buildCardDetailRow(
                      Icons.access_time,
                      'Applied',
                      appliedDate,
                    ),
                    if (isRejectedLeave && rejectedBy != '-') ...[
                      const SizedBox(height: 4),
                      _buildCardDetailRow(
                        Icons.person_off_outlined,
                        'Rejected By',
                        rejectedBy,
                      ),
                    ] else if (!isRejectedLeave && approvedBy != '-') ...[
                      const SizedBox(height: 4),
                      _buildCardDetailRow(
                        Icons.person,
                        'Approved By',
                        approvedBy,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCardDetailRow(IconData icon, String label, String value) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 14, color: colorScheme.onSurfaceVariant),
        const SizedBox(width: 6),
        Text(
          '$label: ',
          style: TextStyle(
            fontSize: 12,
            color: colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildBalanceCard(dynamic balance) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: 140, // Slightly wider for longer text
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 8,
      ), // Reduced vertical padding
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outline),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withOpacity(0.08),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            balance['type'] ?? 'Leave',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurfaceVariant,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            '${balance['takenCount'] ?? 0}',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: colorScheme.primary,
            ),
          ),
          Text(
            'Leaves Taken',
            style: TextStyle(fontSize: 9, color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Leave Balance Summary
        if (!_isLoadingBalances && _leaveBalances.isNotEmpty)
          Container(
            height: 110, // Increased from 100
            margin: const EdgeInsets.only(top: 12, bottom: 4),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _leaveBalances.length,
              itemBuilder: (context, index) {
                final balance = _leaveBalances[index];
                return _buildBalanceCard(balance);
              },
            ),
          ),
        // Controls Column
        if (_showFilters)
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search Leave...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 0,
                    ),
                  ),
                  onChanged: (val) {
                    if (_debounce?.isActive ?? false) _debounce!.cancel();
                    _debounce = Timer(const Duration(milliseconds: 500), () {
                      _fetchLeaves();
                    });
                  },
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade400),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _selectedStatus,
                            isExpanded: true,
                            items: _statusOptions
                                .map(
                                  (e) => DropdownMenuItem(
                                    value: e,
                                    child: Text(e),
                                  ),
                                )
                                .toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setState(() => _selectedStatus = val);
                                _fetchLeaves();
                              }
                            },
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    InkWell(
                      onTap: _pickDateRange,
                      child: Container(
                        height: 48,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade400),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.calendar_today,
                              color: Colors.grey[600],
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _startDate == null || _endDate == null
                                  ? 'Select from - to date'
                                  : '${DateFormat('MMM dd').format(_startDate!)} - ${DateFormat('MMM dd').format(_endDate!)}',
                              style: TextStyle(color: Colors.black),
                            ),
                            if (_startDate != null && _endDate != null)
                              IconButton(
                                icon: const Icon(Icons.close, size: 16),
                                onPressed: _resetToCurrentMonth,
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

        // List Body
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              setState(() => _currentPage = 1);
              await _fetchLeaves();
            },
            child: _isLoading
                ? const Center(child: AppTabLoader())
                : _leaves.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      SizedBox(
                        height: MediaQuery.of(context).size.height * 0.5,
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.calendar_today_outlined,
                                size: 64,
                                color: Colors.grey[400],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No leave requests found',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.black,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  )
                : ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    itemCount: _leaves.length,
                    itemBuilder: (ctx, i) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12.0),
                        child: _buildLeaveCard(_leaves[i]),
                      );
                    },
                  ),
          ),
        ),

        // Pagination Controls
        if (!_isLoading && _leaves.isNotEmpty)
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 140, 16),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left, size: 22),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: _currentPage > 1
                      ? () {
                          setState(() => _currentPage--);
                          _fetchLeaves();
                        }
                      : null,
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '$_currentPage',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.chevron_right, size: 22),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: _currentPage < _totalPages
                      ? () {
                          setState(() => _currentPage++);
                          _fetchLeaves();
                        }
                      : null,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class ApplyLeaveDialog extends StatefulWidget {
  final VoidCallback onSuccess;
  const ApplyLeaveDialog({super.key, required this.onSuccess});

  @override
  State<ApplyLeaveDialog> createState() => _ApplyLeaveDialogState();
}

class _ApplyLeaveDialogState extends State<ApplyLeaveDialog> {
  final _formKey = GlobalKey<FormState>();
  final RequestService _requestService = RequestService();

  String? _leaveType;
  String? _session; // For Half Day
  List<dynamic> _allowedTypes = [];
  DateTime? _startDate;
  DateTime? _endDate;
  bool _isOneDay = true;
  final TextEditingController _reasonController = TextEditingController();
  bool _isSubmitting = false;
  bool _isLoadingTypes = true;
  double _availableCasualLeaves = 0.0;
  double _totalAllowed = 0.0;

  @override
  void initState() {
    super.initState();
    _fetchLeaveTypes();
    _fetchLeaveBalance();
  }

  @override
  void dispose() {
    SnackBarUtils.dismiss();
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _fetchLeaveBalance() async {
    final result = await _requestService.getLeaveBalance();
    if (mounted && result['success'] == true) {
      setState(() {
        _availableCasualLeaves =
            (result['availableCasualLeaves'] as num?)?.toDouble() ?? 0.0;
        _totalAllowed = (result['totalAllowed'] as num?)?.toDouble() ?? 0.0;
      });
    }
  }

  Future<void> _fetchLeaveTypes() async {
    final result = await _requestService.getLeaveTypesForApply();
    if (mounted) {
      if (result['success']) {
        final raw = List<dynamic>.from(result['data'] as List? ?? []);
        // Ensure Half Day is always present as static option (backend sends it; add if missing)
        final hasHalfDay = raw.any((e) {
          final t = (e is Map ? e['type'] as String? : null) ?? '';
          return t.toLowerCase().replaceAll(RegExp(r'\s+'), '') == 'halfday';
        });
        if (!hasHalfDay) {
          raw.insert(0, {'type': 'Half Day', 'days': 0.5});
        }
        setState(() {
          _allowedTypes = raw;
          if (_allowedTypes.isNotEmpty) {
            _leaveType = _allowedTypes.first['type'] as String?;
          }
          _isLoadingTypes = false;
        });
      } else {
        setState(() => _isLoadingTypes = false);
      }
    }
  }

  int get _days {
    if (_startDate == null) return 0;
    if (_isHalfDayLeave(_leaveType)) return 0; // 0.5 on backend
    if (_isOneDay) return 1;
    if (_endDate == null) return 1;
    return _endDate!.difference(_startDate!).inDays + 1;
  }

  Future<void> _pickDate(bool isStart) async {
    final today = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    );
    final picked = await showDatePicker(
      context: context,
      initialDate: (isStart ? _startDate : _endDate) ?? today,
      firstDate: today,
      lastDate: DateTime(2030, 12, 31),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isStart) {
        _startDate = picked;
        if (_isOneDay || _isHalfDayLeave(_leaveType)) {
          _endDate = picked;
        } else if (_endDate != null && _endDate!.isBefore(picked)) {
          _endDate = picked;
        }
      } else {
        _endDate = picked;
        if (_startDate != null && picked.isBefore(_startDate!)) {
          _startDate = picked;
        }
      }
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_startDate == null) {
      SnackBarUtils.showSnackBar(context, 'Please select date');
      return;
    }
    final today = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    );
    if (_startDate!.isBefore(today)) {
      SnackBarUtils.showSnackBar(
        context,
        'Cannot select past dates. Please select today or future dates.',
        isError: true,
      );
      return;
    }
    final effectiveEnd = _isOneDay || _isHalfDayLeave(_leaveType)
        ? _startDate!
        : _endDate;
    if (!_isOneDay &&
        !_isHalfDayLeave(_leaveType) &&
        (effectiveEnd == null || effectiveEnd.isBefore(today))) {
      SnackBarUtils.showSnackBar(
        context,
        'End date cannot be in the past.',
        isError: true,
      );
      return;
    }
    if (!_isOneDay && _endDate != null && _endDate!.isBefore(_startDate!)) {
      SnackBarUtils.showSnackBar(
        context,
        'End date must be on or after start date.',
        isError: true,
      );
      return;
    }
    if (_isHalfDayLeave(_leaveType) &&
        !_isOneDay &&
        _endDate != null &&
        _endDate != _startDate) {
      SnackBarUtils.showSnackBar(
        context,
        'Half Day leave allows only one date.',
        isError: true,
      );
      return;
    }
    if (_isHalfDayLeave(_leaveType) && _session == null) {
      SnackBarUtils.showSnackBar(
        context,
        'Please select a session for Half Day leave',
        isError: true,
      );
      return;
    }

    final daysValue = _isHalfDayLeave(_leaveType) ? 0.5 : _days;
    final requestedDays = _isHalfDayLeave(_leaveType) ? 0.5 : _days.toDouble();
    final rangeEnd = effectiveEnd ?? _startDate!;

    // Unpaid Leave: no balance validation
    final isUnpaidLeave =
        _leaveType != null &&
        _leaveType!.toLowerCase().replaceAll(RegExp(r'\s+'), '') ==
            'unpaidleave';
    if (!isUnpaidLeave) {
      await _fetchLeaveBalance();
      if (!mounted) return;
      if (_availableCasualLeaves <= 0) {
        SnackBarUtils.showSnackBar(
          context,
          "You don't have enough leave balance.",
          isError: true,
        );
        return;
      }
      if (_availableCasualLeaves == 0.5) {
        if (!_isHalfDayLeave(_leaveType)) {
          SnackBarUtils.showSnackBar(
            context,
            "You don't have enough leave balance.",
            isError: true,
          );
          return;
        }
      } else if (requestedDays > _availableCasualLeaves) {
        SnackBarUtils.showSnackBar(
          context,
          "You don't have enough leave balance.",
          isError: true,
        );
        return;
      }
    }

    // Backend checks "leave already applied" and returns a single error message
    final payload = {
      'leaveType': _leaveType,
      'startDate': _startDate!.toIso8601String(),
      'endDate': rangeEnd.toIso8601String(),
      'days': daysValue,
      'reason': _reasonController.text,
      'session': _isHalfDayLeave(_leaveType) ? _session : null,
      if (_isHalfDayLeave(_leaveType) && _session != null)
        'halfDaySession': _session == '1'
            ? 'First Half Day'
            : 'Second Half Day',
    };

    setState(() => _isSubmitting = true);
    final result = await _requestService.applyLeave(payload);
    setState(() => _isSubmitting = false);

    if (mounted) {
      if (result['success']) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!context.mounted) return;
          final overlay = Navigator.of(context, rootNavigator: true).overlay;
          Navigator.of(context).pop();
          widget.onSuccess();
          if (overlay != null && overlay.context.mounted) {
            showRequestSubmittedSuccessDialog(overlay.context);
          }
        });
      } else {
        SnackBarUtils.showSnackBar(
          context,
          ErrorMessageUtils.sanitizeForDisplay(
            result['message']?.toString(),
            fallback: 'Failed to submit leave',
          ),
          isError: true,
        );
      }
    }
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 22, color: AppColors.primary),
      labelStyle: const TextStyle(color: Colors.black),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: AppColors.primary, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 24,
        right: 24,
        top: 24,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.calendar_month,
                          color: AppColors.primary,
                          size: 26,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Apply Leave',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Submit a new leave request',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, size: 28),
                ),
              ],
            ),
            const Divider(),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 16),
                    if (_isLoadingTypes)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 20),
                        child: Center(child: AppTabLoader()),
                      )
                    else if (_allowedTypes.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 20),
                        child: Text(
                          'No leave types available. Please contact HR to assign a leave template.',
                          style: TextStyle(color: Colors.red),
                        ),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.only(bottom: 20),
                        child: DropdownButtonFormField<String>(
                          initialValue: _leaveType,
                          items: _allowedTypes.map((e) {
                            final type = e['type'] as String? ?? '';
                            return DropdownMenuItem<String>(
                              value: type,
                              child: Text(type),
                            );
                          }).toList(),
                          onChanged: (val) {
                            setState(() {
                              _leaveType = val!;
                              if (_isHalfDayLeave(_leaveType)) {
                                _session = '1';
                                _isOneDay = true;
                                if (_startDate != null) _endDate = _startDate;
                              }
                            });
                          },
                          decoration: _inputDecoration(
                            'Leave Type *',
                            Icons.calendar_today,
                          ),
                        ),
                      ),
                    if (_allowedTypes.isNotEmpty &&
                        _leaveType != null &&
                        _leaveType!.toLowerCase().replaceAll(
                              RegExp(r'\s+'),
                              '',
                            ) !=
                            'unpaidleave') ...[
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          'Leave balance: ${_availableCasualLeaves.toStringAsFixed(1)} days${_totalAllowed > 0 ? ' (of ${_totalAllowed.toStringAsFixed(0)} total)' : ''}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ),
                    ],

                    const Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: Text(
                        'Date',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        Expanded(child: Text('One day')),
                        Switch(
                          value: _isHalfDayLeave(_leaveType) ? true : _isOneDay,
                          onChanged: _isHalfDayLeave(_leaveType)
                              ? null
                              : (v) {
                                  setState(() {
                                    _isOneDay = v;
                                    if (_isOneDay && _startDate != null) {
                                      _endDate = _startDate;
                                    }
                                  });
                                },
                          activeThumbColor: AppColors.primary,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: () => _pickDate(true),
                      child: InputDecorator(
                        decoration: _inputDecoration(
                          _isOneDay || _isHalfDayLeave(_leaveType)
                              ? 'Date *'
                              : 'Start Date *',
                          Icons.calendar_today,
                        ),
                        child: Text(
                          _startDate != null
                              ? DateFormat('dd-MM-yyyy').format(_startDate!)
                              : 'Select date',
                          style: TextStyle(
                            color: _startDate != null
                                ? Colors.black87
                                : Colors.grey,
                          ),
                        ),
                      ),
                    ),
                    if (!_isOneDay && !_isHalfDayLeave(_leaveType)) ...[
                      const SizedBox(height: 12),
                      InkWell(
                        onTap: () => _pickDate(false),
                        child: InputDecorator(
                          decoration: _inputDecoration(
                            'End Date *',
                            Icons.calendar_today,
                          ),
                          child: Text(
                            _endDate != null
                                ? DateFormat('dd-MM-yyyy').format(_endDate!)
                                : 'Select end date',
                            style: TextStyle(
                              color: _endDate != null
                                  ? Colors.black87
                                  : Colors.grey,
                            ),
                          ),
                        ),
                      ),
                    ],
                    if (_startDate != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          _isHalfDayLeave(_leaveType)
                              ? 'Total: 0.5 day — ${_availableCasualLeaves.toStringAsFixed(1)} days remaining'
                              : 'Total: $_days day${_days == 1 ? '' : 's'} — ${_availableCasualLeaves.toStringAsFixed(1)} days remaining',
                          style: TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    if (_isHalfDayLeave(_leaveType) && _startDate != null) ...[
                      const SizedBox(height: 12),
                      const Text(
                        'Session for Half Day *',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          ChoiceChip(
                            label: const Text('First Half Day'),
                            selected: _session == '1',
                            onSelected: (v) => setState(() => _session = '1'),
                            selectedColor: AppColors.primary.withOpacity(0.3),
                          ),
                          const SizedBox(width: 12),
                          ChoiceChip(
                            label: const Text('Second Half Day'),
                            selected: _session == '2',
                            onSelected: (v) => setState(() => _session = '2'),
                            selectedColor: AppColors.primary.withOpacity(0.3),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _reasonController,
                      maxLines: 3,
                      style: TextStyle(fontWeight: FontWeight.w500),
                      decoration: _inputDecoration(
                        'Reason *',
                        Icons.note,
                      ).copyWith(hintText: 'Enter reason for leave'),
                      validator: (val) => val == null || val.isEmpty
                          ? 'Reason is required'
                          : null,
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: BorderSide(color: AppColors.primary),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isSubmitting ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                      child: _isSubmitting
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text('Submit Request'),
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
}

// --- LOAN TAB ---

class LoanRequestsTab extends StatefulWidget {
  const LoanRequestsTab({super.key});

  @override
  State<LoanRequestsTab> createState() => _LoanRequestsTabState();
}

class _LoanRequestsTabState extends State<LoanRequestsTab> {
  final RequestService _requestService = RequestService();
  List<dynamic> _loans = [];
  bool _isLoading = true;
  String _selectedStatus = 'All Status';
  final List<String> _statusOptions = [
    'All Status',
    'Pending',
    'Approved',
    'Active',
    'Rejected',
    'Closed',
  ];

  Timer? _debounce;
  final TextEditingController _searchController = TextEditingController();
  DateTime? _startDate;
  DateTime? _endDate;
  int _currentPage = 1;
  final int _itemsPerPage = 10;
  int _totalPages = 0;
  bool _showFilters = false;

  void toggleFilters() {
    setState(() {
      _showFilters = !_showFilters;
    });
  }

  void refresh() {
    _fetchLoans();
  }

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _startDate = DateTime(now.year, now.month, 1);
    _endDate = DateTime(now.year, now.month + 1, 0, 23, 59, 59, 999);
    _fetchLoans();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _fetchLoans() async {
    setState(() => _isLoading = true);
    final result = await _requestService.getLoanRequests(
      status: _selectedStatus,
      search: _searchController.text,
      startDate: _startDate,
      endDate: _endDate,
      page: _currentPage,
      limit: _itemsPerPage,
    );
    if (mounted) {
      if (result['success']) {
        setState(() {
          if (result['data'] is Map) {
            _loans = result['data']['loans'] ?? [];
            final pagination = result['data']['pagination'];
            if (pagination != null) {
              _totalPages = pagination['pages'] ?? 0;
              _currentPage = pagination['page'] ?? 1;
            }
          } else if (result['data'] is List) {
            _loans = result['data'];
            _totalPages = 1;
            _currentPage = 1;
          }
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
        SnackBarUtils.showSnackBar(
          context,
          ErrorMessageUtils.sanitizeForDisplay(
            result['message']?.toString(),
            fallback: 'Failed to fetch loan requests',
          ),
          isError: true,
        );
      }
    }
  }

  void showRequestLoanDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      builder: (ctx) => RequestLoanDialog(onSuccess: _fetchLoans),
    );
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePickerSameCalendar(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialStart: _startDate,
      initialEnd: _endDate,
    );
    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end.add(
          const Duration(hours: 23, minutes: 59, seconds: 59),
        );
      });
      _fetchLoans();
    }
  }

  void _showLoanDetails(Map<String, dynamic> loan) {
    String approvedBy = '—';
    String rejectedBy = '—';
    final approver = loan['approvedBy'];
    final rejector = loan['rejectedBy'];
    if (approver != null) {
      if (approver is Map && approver['name'] != null) {
        approvedBy = approver['name'].toString().trim();
        if (approvedBy.isEmpty) approvedBy = '—';
      } else {
        approvedBy = 'System';
      }
    }
    if (rejector != null) {
      if (rejector is Map && rejector['name'] != null) {
        rejectedBy = rejector['name'].toString().trim();
        if (rejectedBy.isEmpty) rejectedBy = '—';
      } else {
        rejectedBy = 'System';
      }
    } else if (loan['status'] == 'Rejected' && approver != null) {
      rejectedBy = approvedBy;
    }
    final rejectionReason = loan['rejectionReason']?.toString().trim();
    final isRejected = loan['status'] == 'Rejected';
    final requestedOn = loan['createdAt'] != null
        ? DateFormat('MMM dd, yyyy').format(DateTime.parse(loan['createdAt']))
        : '—';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _RequestDetailBottomSheet(
        title: 'Loan Details',
        icon: Icons.account_balance_wallet,
        iconColor: AppColors.primary,
        children: [
          _detailRow('Type', loan['loanType'] ?? ''),
          _detailRow('Amount', '₹${loan['amount']}'),
          _detailRow(
            'Tenure',
            '${loan['tenure'] ?? loan['tenureMonths']} Months',
          ),
          _detailRow('EMI', '₹${loan['emi'] ?? 0}'),
          _detailRow('Interest Rate', '${loan['interestRate']}%'),
          _detailRow('Purpose', loan['purpose'] ?? ''),
          _detailRow('Status', loan['status'] ?? ''),
          if (isRejected) ...[
            _detailRow('Rejected By', rejectedBy),
            if (rejectionReason != null && rejectionReason.isNotEmpty)
              _detailRow('Rejection Reason', rejectionReason),
          ] else
            _detailRow('Approved By', approvedBy),
          _detailRow('Requested On', requestedOn),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Widget _buildLoanCard(Map<String, dynamic> loan) {
    final appliedDate = loan['createdAt'] != null
        ? DateFormat('MMM dd, yyyy').format(DateTime.parse(loan['createdAt']))
        : '-';
    Color statusColor = Colors.grey;
    if (loan['status'] == 'Approved' || loan['status'] == 'Active') {
      statusColor = AppColors.success;
    } else if (loan['status'] == 'Rejected') {
      statusColor = AppColors.error;
    } else if (loan['status'] == 'Pending') {
      statusColor = AppColors.warning;
    }

    String approvedByName = '-';
    String rejectedByName = '-';
    final approver = loan['approvedBy'];
    final rejector = loan['rejectedBy'];
    final isRejectedLoan = loan['status'] == 'Rejected';
    if (approver != null) {
      if (approver is Map) {
        approvedByName = approver['name'] ?? '-';
      } else {
        approvedByName = 'System';
      }
    }
    if (rejector != null) {
      if (rejector is Map) {
        rejectedByName = rejector['name'] ?? '-';
      } else {
        rejectedByName = 'System';
      }
    } else if (isRejectedLoan && approver != null) {
      rejectedByName = approvedByName;
    }

    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => _showLoanDetails(loan),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colorScheme.outline),
          boxShadow: [
            BoxShadow(
              color: colorScheme.shadow.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              // Icon
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.account_balance_wallet,
                  color: AppColors.primary,
                  size: 32,
                ),
              ),
              const SizedBox(width: 16),
              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Loan Type and Status
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            loan['loanType'] ?? 'Loan',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onSurface,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: statusColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            loan['status'] ?? '',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: statusColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Details
                    _buildLoanCardDetailRow(
                      Icons.currency_rupee,
                      'Amount',
                      '₹${loan['amount']}',
                    ),
                    const SizedBox(height: 4),
                    _buildLoanCardDetailRow(
                      Icons.calendar_today,
                      'Tenure',
                      '${loan['tenure'] ?? loan['tenureMonths']} Months',
                    ),
                    const SizedBox(height: 4),
                    _buildLoanCardDetailRow(
                      Icons.payment,
                      'EMI',
                      '₹${loan['emi'] ?? 0}',
                    ),
                    const SizedBox(height: 4),
                    _buildLoanCardDetailRow(
                      Icons.access_time,
                      'Applied',
                      appliedDate,
                    ),
                    if (isRejectedLoan && rejectedByName != '-') ...[
                      const SizedBox(height: 4),
                      _buildLoanCardDetailRow(
                        Icons.person_off_outlined,
                        'Rejected By',
                        rejectedByName,
                      ),
                    ] else if (!isRejectedLoan && approvedByName != '-') ...[
                      const SizedBox(height: 4),
                      _buildLoanCardDetailRow(
                        Icons.person,
                        'Approved By',
                        approvedByName,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoanCardDetailRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 14, color: const Color(0xFF424242)),
        const SizedBox(width: 6),
        Text(
          '$label: ',
          style: TextStyle(
            fontSize: 12,
            color: Color(0xFF424242),
            fontWeight: FontWeight.w600,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(fontSize: 12, color: Color(0xFF424242)),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Controls Column
        if (_showFilters)
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search Type, Purpose...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 0,
                    ),
                  ),
                  onChanged: (val) {
                    if (_debounce?.isActive ?? false) _debounce!.cancel();
                    _debounce = Timer(const Duration(milliseconds: 500), () {
                      _fetchLoans();
                    });
                  },
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade400),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _selectedStatus,
                            isExpanded: true,
                            items: _statusOptions
                                .map(
                                  (e) => DropdownMenuItem(
                                    value: e,
                                    child: Text(e),
                                  ),
                                )
                                .toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setState(() => _selectedStatus = val);
                                _fetchLoans();
                              }
                            },
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    InkWell(
                      onTap: _pickDateRange,
                      child: Container(
                        height: 48,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade400),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.calendar_today,
                              color: Colors.grey[600],
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _startDate == null
                                  ? 'Date'
                                  : '${DateFormat('MMM dd').format(_startDate!)} - ${DateFormat('MMM dd').format(_endDate!)}',
                              style: TextStyle(color: Colors.black),
                            ),
                            if (_startDate != null)
                              IconButton(
                                icon: const Icon(Icons.close, size: 16),
                                onPressed: () {
                                  setState(() {
                                    _startDate = null;
                                    _endDate = null;
                                  });
                                  _fetchLoans();
                                },
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

        // List Content
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              setState(() => _currentPage = 1);
              await _fetchLoans();
            },
            child: _isLoading
                ? const Center(child: AppTabLoader())
                : _loans.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      SizedBox(
                        height: MediaQuery.of(context).size.height * 0.5,
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.account_balance_wallet_outlined,
                                size: 64,
                                color: Colors.grey[400],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No loan requests found',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.black,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  )
                : ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    itemCount: _loans.length,
                    itemBuilder: (ctx, i) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12.0),
                        child: _buildLoanCard(_loans[i]),
                      );
                    },
                  ),
          ),
        ),

        // Pagination Controls
        if (!_isLoading && _loans.isNotEmpty)
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 140, 16),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left, size: 22),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: _currentPage > 1
                      ? () {
                          setState(() => _currentPage--);
                          _fetchLoans();
                        }
                      : null,
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '$_currentPage',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.chevron_right, size: 22),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: _currentPage < _totalPages
                      ? () {
                          setState(() => _currentPage++);
                          _fetchLoans();
                        }
                      : null,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class RequestLoanDialog extends StatefulWidget {
  final VoidCallback onSuccess;
  const RequestLoanDialog({super.key, required this.onSuccess});

  @override
  State<RequestLoanDialog> createState() => _RequestLoanDialogState();
}

class _RequestLoanDialogState extends State<RequestLoanDialog> {
  final _formKey = GlobalKey<FormState>();
  final RequestService _requestService = RequestService();

  String _loanType = 'Personal';
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _tenureController = TextEditingController();
  final TextEditingController _interestController = TextEditingController();
  final TextEditingController _purposeController = TextEditingController();
  bool _isSubmitting = false;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);
    final result = await _requestService.applyLoan({
      'loanType': _loanType,
      'amount': double.tryParse(_amountController.text) ?? 0,
      'tenure': int.tryParse(_tenureController.text) ?? 0,
      'interestRate': double.tryParse(_interestController.text) ?? 0,
      'purpose': _purposeController.text,
    });
    setState(() => _isSubmitting = false);

    if (mounted) {
      if (result['success']) {
        final overlay = Navigator.of(context, rootNavigator: true).overlay;
        widget.onSuccess();
        Navigator.pop(context);
        if (overlay != null && overlay.context.mounted) {
          showRequestSubmittedSuccessDialog(overlay.context);
        }
      } else {
        SnackBarUtils.showSnackBar(
          context,
          ErrorMessageUtils.sanitizeForDisplay(
            result['message']?.toString(),
            fallback: 'Failed to submit loan request',
          ),
          isError: true,
        );
      }
    }
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 22, color: AppColors.primary),
      labelStyle: const TextStyle(color: Colors.black),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: AppColors.primary, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 24,
        right: 24,
        top: 24,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.account_balance_wallet,
                          color: AppColors.primary,
                          size: 26,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Request Loan',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Submit a new loan request',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, size: 28),
                ),
              ],
            ),
            const Divider(),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: DropdownButtonFormField<String>(
                        initialValue: _loanType,
                        items: ['Personal', 'Advance', 'Emergency']
                            .map(
                              (e) => DropdownMenuItem(value: e, child: Text(e)),
                            )
                            .toList(),
                        onChanged: (val) => setState(() => _loanType = val!),
                        decoration: _inputDecoration(
                          'Loan Type',
                          Icons.category,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _amountController,
                      keyboardType: TextInputType.number,
                      style: TextStyle(fontWeight: FontWeight.w500),
                      decoration: _inputDecoration(
                        'Amount (₹)',
                        Icons.currency_rupee,
                      ).copyWith(hintText: 'Enter loan amount'),
                      validator: (val) => val == null || val.isEmpty
                          ? 'Amount is required'
                          : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _tenureController,
                      keyboardType: TextInputType.number,
                      style: TextStyle(fontWeight: FontWeight.w500),
                      decoration: _inputDecoration(
                        'Tenure (Months)',
                        Icons.calendar_month,
                      ).copyWith(hintText: 'Enter tenure in months'),
                      validator: (val) {
                        if (val == null || val.isEmpty) {
                          return 'Tenure is required';
                        }
                        final n = int.tryParse(val);
                        if (n == null || n <= 0) return 'Must be > 0';
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _interestController,
                      keyboardType: TextInputType.number,
                      style: TextStyle(fontWeight: FontWeight.w500),
                      decoration: _inputDecoration(
                        'Interest Rate (%)',
                        Icons.percent,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _purposeController,
                      maxLines: 3,
                      style: TextStyle(fontWeight: FontWeight.w500),
                      decoration: _inputDecoration(
                        'Purpose',
                        Icons.note,
                      ).copyWith(hintText: 'Enter purpose of loan'),
                      validator: (val) => val == null || val.isEmpty
                          ? 'Purpose is required'
                          : null,
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: BorderSide(color: AppColors.primary),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isSubmitting ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                      child: _isSubmitting
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text('Submit Request'),
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
}

// --- EXPENSE TAB ---

class ExpenseRequestsTab extends StatefulWidget {
  const ExpenseRequestsTab({super.key});

  @override
  State<ExpenseRequestsTab> createState() => _ExpenseRequestsTabState();
}

class _ExpenseRequestsTabState extends State<ExpenseRequestsTab> {
  final RequestService _requestService = RequestService();
  List<dynamic> _expenses = [];
  bool _isLoading = true;
  String _selectedStatus = 'All Status';
  final List<String> _statusOptions = [
    'All Status',
    'Pending',
    'Approved',
    'Rejected',
    'Paid',
  ];

  DateTime? _startDate;
  DateTime? _endDate;
  int _currentPage = 1;
  final int _itemsPerPage = 10;
  int _totalPages = 0;
  final TextEditingController _searchController = TextEditingController();
  bool _showFilters = false;

  void toggleFilters() {
    setState(() {
      _showFilters = !_showFilters;
    });
  }

  void refresh() {
    _fetchExpenses();
  }

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _startDate = DateTime(now.year, now.month, 1);
    _endDate = DateTime(now.year, now.month + 1, 0);
    _fetchExpenses();
  }

  Future<void> _fetchExpenses() async {
    setState(() => _isLoading = true);
    final result = await _requestService.getExpenseRequests(
      status: _selectedStatus,
      search: _searchController.text,
      startDate: _startDate,
      endDate: _endDate,
      page: _currentPage,
      limit: _itemsPerPage,
    );
    if (mounted) {
      if (result['success']) {
        setState(() {
          if (result['data'] is Map) {
            _expenses = result['data']['reimbursements'] ?? [];
            final pagination = result['data']['pagination'];
            if (pagination != null) {
              _totalPages = pagination['pages'] ?? 0;
              _currentPage = pagination['page'] ?? 1;
            }
          } else if (result['data'] is List) {
            _expenses = result['data'];
            _totalPages = 1;
            _currentPage = 1;
          }
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
        SnackBarUtils.showSnackBar(
          context,
          ErrorMessageUtils.sanitizeForDisplay(
            result['message']?.toString(),
            fallback: 'Failed to fetch expense requests',
          ),
          isError: true,
        );
      }
    }
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePickerSameCalendar(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialStart: _startDate,
      initialEnd: _endDate,
    );
    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
      _fetchExpenses();
    }
  }

  void _viewProof(String url) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppBar(
              title: Text('Proof Document'),
              backgroundColor: Colors.transparent,
              elevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.close, color: Colors.black),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
            Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.7,
              ),
              child: Image.network(
                url,
                loadingBuilder: (ctx, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return const Center(child: AppTabLoader());
                },
                errorBuilder: (ctx, error, stackTrace) => const Center(
                  child: Padding(
                    padding: EdgeInsets.all(20.0),
                    child: Text('Unable to load image or invalid format.'),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  // Changed to public for GlobalKey access
  void _showExpenseDetails(Map<String, dynamic> expense) {
    final date = DateFormat(
      'MMM dd, yyyy',
    ).format(DateTime.parse(expense['date']));
    final appliedDate = expense['createdAt'] != null
        ? DateFormat(
            'MMM dd, yyyy',
          ).format(DateTime.parse(expense['createdAt']))
        : '—';

    String approvedByName = '—';
    String rejectedByName = '—';
    final approver = expense['approvedBy'];
    final rejector = expense['rejectedBy'];
    if (approver != null) {
      if (approver is Map && approver['name'] != null) {
        approvedByName = approver['name'].toString().trim();
        if (approvedByName.isEmpty) approvedByName = '—';
      } else {
        approvedByName = 'System';
      }
    }
    if (rejector != null) {
      if (rejector is Map && rejector['name'] != null) {
        rejectedByName = rejector['name'].toString().trim();
        if (rejectedByName.isEmpty) rejectedByName = '—';
      } else {
        rejectedByName = 'System';
      }
    } else if (expense['status'] == 'Rejected' && approver != null) {
      rejectedByName = approvedByName;
    }
    final rejectionReason = expense['rejectionReason']?.toString().trim();
    final isRejected = expense['status'] == 'Rejected';

    List<dynamic> proofs = expense['proofFiles'] ?? [];
    final detailChildren = <Widget>[
      _expenseDetailRow(
        'Type',
        expense['type'] ?? expense['expenseType'] ?? 'Expense',
      ),
      _expenseDetailRow('Amount', '₹${expense['amount']}'),
      _expenseDetailRow('Date', date),
      _expenseDetailRow('Applied Date', appliedDate),
      if (expense['description'] != null &&
          expense['description'].toString().isNotEmpty)
        _expenseDetailRow('Description', expense['description']),
      _expenseDetailRow('Status', expense['status'] ?? ''),
      if (isRejected) ...[
        _expenseDetailRow('Rejected By', rejectedByName),
        if (rejectionReason != null && rejectionReason.isNotEmpty)
          _expenseDetailRow('Rejection Reason', rejectionReason),
      ] else
        _expenseDetailRow('Approved By', approvedByName),
      if (proofs.isNotEmpty) ...[
        const SizedBox(height: 12),
        Text(
          'Proof Files:',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        ...proofs.asMap().entries.map((entry) {
          final proof = entry.value;
          String proofUrl;
          if (proof is Map) {
            proofUrl =
                proof['url']?.toString() ??
                proof['fileUrl']?.toString() ??
                proof.toString();
          } else {
            proofUrl = proof.toString();
          }
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: InkWell(
              onTap: () => _viewProof(proofUrl),
              borderRadius: BorderRadius.circular(8),
              child: Row(
                children: [
                  Icon(Icons.attach_file, size: 18, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'View Proof',
                      style: TextStyle(
                        color: Colors.blue,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _RequestDetailBottomSheet(
        title: 'Expense Details',
        icon: Icons.receipt,
        iconColor: AppColors.primary,
        children: detailChildren,
      ),
    );
  }

  Widget _expenseDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Widget _buildExpenseCard(Map<String, dynamic> expense) {
    final date = DateFormat(
      'MMM dd, yyyy',
    ).format(DateTime.parse(expense['date']));
    final appliedDate = expense['createdAt'] != null
        ? DateFormat(
            'MMM dd, yyyy',
          ).format(DateTime.parse(expense['createdAt']))
        : '-';

    Color statusColor = Colors.grey;
    if (expense['status'] == 'Approved' || expense['status'] == 'Paid') {
      statusColor = AppColors.success;
    } else if (expense['status'] == 'Rejected') {
      statusColor = AppColors.error;
    } else if (expense['status'] == 'Pending') {
      statusColor = AppColors.warning;
    }

    String approvedByName = '-';
    String rejectedByName = '-';
    final approver = expense['approvedBy'];
    final rejector = expense['rejectedBy'];
    final isRejectedExpense = expense['status'] == 'Rejected';
    if (approver != null) {
      if (approver is Map) {
        approvedByName = approver['name'] ?? '-';
      } else {
        approvedByName = 'System';
      }
    }
    if (rejector != null) {
      if (rejector is Map) {
        rejectedByName = rejector['name'] ?? '-';
      } else {
        rejectedByName = 'System';
      }
    } else if (isRejectedExpense && approver != null) {
      rejectedByName = approvedByName;
    }

    List<dynamic> proofs = expense['proofFiles'] ?? [];
    bool hasProof = proofs.isNotEmpty;

    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => _showExpenseDetails(expense),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colorScheme.outline),
          boxShadow: [
            BoxShadow(
              color: colorScheme.shadow.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              // Icon
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.receipt, color: AppColors.primary, size: 32),
              ),
              const SizedBox(width: 16),
              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Expense Type and Status
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            expense['type'] ??
                                expense['expenseType'] ??
                                'Expense',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onSurface,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: statusColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            expense['status'] ?? '',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: statusColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Details
                    _buildExpenseCardDetailRow(
                      Icons.currency_rupee,
                      'Amount',
                      '₹${expense['amount']}',
                    ),
                    const SizedBox(height: 4),
                    _buildExpenseCardDetailRow(
                      Icons.calendar_today,
                      'Date',
                      date,
                    ),
                    const SizedBox(height: 4),
                    _buildExpenseCardDetailRow(
                      Icons.access_time,
                      'Applied',
                      appliedDate,
                    ),
                    if (expense['description'] != null &&
                        expense['description'].toString().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      _buildExpenseCardDetailRow(
                        Icons.description,
                        'Description',
                        expense['description'] ?? '',
                      ),
                    ],
                    if (hasProof) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.attach_file,
                            size: 14,
                            color: const Color(0xFF424242),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Proof: Available',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.blue[700],
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (isRejectedExpense && rejectedByName != '-') ...[
                      const SizedBox(height: 4),
                      _buildExpenseCardDetailRow(
                        Icons.person_off_outlined,
                        'Rejected By',
                        rejectedByName,
                      ),
                    ] else if (!isRejectedExpense && approvedByName != '-') ...[
                      const SizedBox(height: 4),
                      _buildExpenseCardDetailRow(
                        Icons.person,
                        'Approved By',
                        approvedByName,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildExpenseCardDetailRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 14, color: const Color(0xFF424242)),
        const SizedBox(width: 6),
        Text(
          '$label: ',
          style: TextStyle(
            fontSize: 12,
            color: Color(0xFF424242),
            fontWeight: FontWeight.w600,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(fontSize: 12, color: Color(0xFF424242)),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  void showClaimExpenseDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      builder: (ctx) => ClaimExpenseDialog(onSuccess: _fetchExpenses),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Controls Column
        if (_showFilters)
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search Type, Description...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 0,
                    ),
                  ),
                  onSubmitted: (_) => _fetchExpenses(),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade400),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _selectedStatus,
                            isExpanded: true,
                            items: _statusOptions
                                .map(
                                  (e) => DropdownMenuItem(
                                    value: e,
                                    child: Text(e),
                                  ),
                                )
                                .toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setState(() => _selectedStatus = val);
                                _fetchExpenses();
                              }
                            },
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Date Filter Button
                    InkWell(
                      onTap: _pickDateRange,
                      child: Container(
                        height: 48,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade400),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.calendar_today,
                              color: Colors.grey[600],
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _startDate == null
                                  ? 'Date'
                                  : '${DateFormat('MMM dd').format(_startDate!)} - ${DateFormat('MMM dd').format(_endDate!)}',
                              style: TextStyle(color: Colors.black),
                            ),
                            if (_startDate != null)
                              IconButton(
                                icon: const Icon(Icons.close, size: 16),
                                onPressed: () {
                                  setState(() {
                                    _startDate = null;
                                    _endDate = null;
                                  });
                                  _fetchExpenses();
                                },
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

        // List Content
        Expanded(
          child: _isLoading
              ? const Center(child: AppTabLoader())
              : _expenses.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.receipt_outlined,
                        size: 64,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No expense requests found',
                        style: TextStyle(fontSize: 16, color: Colors.black),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _expenses.length,
                  itemBuilder: (ctx, i) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12.0),
                      child: _buildExpenseCard(_expenses[i]),
                    );
                  },
                ),
        ),

        // Pagination Controls
        if (!_isLoading && _expenses.isNotEmpty)
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 140, 16),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left, size: 22),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: _currentPage > 1
                      ? () {
                          setState(() => _currentPage--);
                          _fetchExpenses();
                        }
                      : null,
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '$_currentPage',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.chevron_right, size: 22),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: _currentPage < _totalPages
                      ? () {
                          setState(() => _currentPage++);
                          _fetchExpenses();
                        }
                      : null,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class ClaimExpenseDialog extends StatefulWidget {
  final VoidCallback onSuccess;
  const ClaimExpenseDialog({super.key, required this.onSuccess});

  @override
  State<ClaimExpenseDialog> createState() => _ClaimExpenseDialogState();
}

class _ClaimExpenseDialogState extends State<ClaimExpenseDialog> {
  final _formKey = GlobalKey<FormState>();
  final RequestService _requestService = RequestService();

  String _expenseType = 'Travel';
  final TextEditingController _amountController = TextEditingController();
  DateTime? _date;
  final TextEditingController _descriptionController =
      TextEditingController(); // Description
  File? _selectedFile; // Add File variable
  bool _isSubmitting = false;

  Future<void> _pickFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
    );

    if (result != null) {
      if (result.files.single.path != null) {
        setState(() {
          _selectedFile = File(result.files.single.path!);
        });
      }
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final initial = _date != null && !_date!.isAfter(today) ? _date! : now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: today,
    );
    if (picked != null) {
      setState(() => _date = picked);
    }
  }

  /// Compress image file to reduce payload and avoid 413 Payload Too Large.
  static const int _maxProofImageWidth = 1200;
  static const int _proofImageQuality = 85;

  Future<List<int>> _compressImageFile(File file) async {
    final path = file.path.toLowerCase();
    final isImage =
        path.endsWith('.jpg') ||
        path.endsWith('.jpeg') ||
        path.endsWith('.png') ||
        path.endsWith('.webp');
    if (!isImage) {
      return await file.readAsBytes();
    }
    final result = await FlutterImageCompress.compressWithFile(
      file.absolute.path,
      minWidth: _maxProofImageWidth,
      minHeight: _maxProofImageWidth,
      quality: _proofImageQuality,
      format: path.endsWith('.png') ? CompressFormat.png : CompressFormat.jpeg,
    );
    if (result == null || result.isEmpty) {
      return await file.readAsBytes();
    }
    return result;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_date == null) {
      SnackBarUtils.showSnackBar(context, 'Please select a date');
      return;
    }
    final today = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    );
    if (_date!.isAfter(today)) {
      SnackBarUtils.showSnackBar(
        context,
        'Expense date cannot be in the future. Please select today or a past date.',
        isError: true,
      );
      return;
    }

    if (_selectedFile == null) {
      SnackBarUtils.showSnackBar(context, 'Please upload a proof document');
      return;
    }

    setState(() => _isSubmitting = true);

    // Process file if exists: compress images to avoid 413 Payload Too Large
    List<String> proofFiles = [];
    if (_selectedFile != null) {
      final path = _selectedFile!.path.toLowerCase();
      final isPdf = path.endsWith('.pdf');
      const maxProofBytes = 5 * 1024 * 1024; // 5 MB max for PDF

      if (isPdf) {
        final length = await _selectedFile!.length();
        if (length > maxProofBytes) {
          if (mounted) {
            setState(() => _isSubmitting = false);
            SnackBarUtils.showSnackBar(
              context,
              'Proof file is too large. Please use a file under 5 MB.',
              isError: true,
            );
          }
          return;
        }
        final bytes = await _selectedFile!.readAsBytes();
        final base64String = base64Encode(bytes);
        proofFiles.add('data:application/pdf;base64,$base64String');
      } else {
        // Image: compress to reduce payload and avoid 413
        final bytes = await _compressImageFile(_selectedFile!);
        final base64String = base64Encode(bytes);
        String mime = 'image/jpeg';
        if (path.endsWith('.png')) mime = 'image/png';
        proofFiles.add('data:$mime;base64,$base64String');
      }
    }

    final result = await _requestService.applyExpense({
      'type': _expenseType,
      'amount': double.tryParse(_amountController.text) ?? 0,
      'date': _date!.toIso8601String(),
      'description': _descriptionController.text,
      'proofFiles': proofFiles,
    });
    setState(() => _isSubmitting = false);

    if (mounted) {
      if (result['success']) {
        final overlay = Navigator.of(context, rootNavigator: true).overlay;
        widget.onSuccess();
        Navigator.pop(context);
        if (overlay != null && overlay.context.mounted) {
          showRequestSubmittedSuccessDialog(overlay.context);
        }
      } else {
        SnackBarUtils.showSnackBar(
          context,
          ErrorMessageUtils.sanitizeForDisplay(
            result['message']?.toString(),
            fallback: 'Failed to submit expense claim',
          ),
          isError: true,
        );
      }
    }
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 22, color: AppColors.primary),
      labelStyle: const TextStyle(color: Colors.black),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: AppColors.primary, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 24,
        right: 24,
        top: 24,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.receipt_long,
                          color: AppColors.primary,
                          size: 26,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Claim Expense',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Submit a new expense claim',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, size: 28),
                ),
              ],
            ),
            const Divider(),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: DropdownButtonFormField<String>(
                        initialValue: _expenseType,
                        items: ['Travel', 'Food', 'Accommodation', 'Other']
                            .map(
                              (e) => DropdownMenuItem(value: e, child: Text(e)),
                            )
                            .toList(),
                        onChanged: (val) => setState(() => _expenseType = val!),
                        decoration: _inputDecoration(
                          'Expense Type',
                          Icons.category,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _amountController,
                      keyboardType: TextInputType.number,
                      style: TextStyle(fontWeight: FontWeight.w500),
                      decoration: _inputDecoration(
                        'Amount (₹)',
                        Icons.currency_rupee,
                      ).copyWith(hintText: 'Enter expense amount'),
                      validator: (val) => val == null || val.isEmpty
                          ? 'Amount is required'
                          : null,
                    ),
                    const SizedBox(height: 16),
                    InkWell(
                      onTap: _pickDate,
                      child: InputDecorator(
                        decoration: _inputDecoration(
                          'Date *',
                          Icons.calendar_today,
                        ),
                        child: Text(
                          _date == null
                              ? 'dd-mm-yyyy'
                              : DateFormat('dd-MM-yyyy').format(_date!),
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            color: _date == null ? Colors.grey : Colors.black,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _descriptionController,
                      maxLines: 3,
                      style: TextStyle(fontWeight: FontWeight.w500),
                      decoration: _inputDecoration(
                        'Description',
                        Icons.note,
                      ).copyWith(hintText: 'Enter expense description'),
                      validator: (val) => val == null || val.isEmpty
                          ? 'Description is required'
                          : null,
                    ),
                    const SizedBox(height: 16),
                    InkWell(
                      onTap: _pickFile,
                      child: InputDecorator(
                        decoration: _inputDecoration(
                          'Proof Document *',
                          Icons.attach_file,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                _selectedFile != null
                                    ? _selectedFile!.path
                                          .split(RegExp(r'[/\\]'))
                                          .last
                                    : 'Select file (Image/PDF)',
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: FontWeight.w500,
                                  color: _selectedFile != null
                                      ? Colors.black
                                      : Colors.grey,
                                ),
                              ),
                            ),
                            Icon(
                              Icons.attach_file,
                              size: 20,
                              color: Colors.grey.shade600,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: BorderSide(color: AppColors.primary),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isSubmitting ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                      child: _isSubmitting
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text('Submit Claim'),
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
}

// --- PERMISSION TAB ---

class PermissionRequestsTab extends StatefulWidget {
  const PermissionRequestsTab({super.key});

  @override
  State<PermissionRequestsTab> createState() => _PermissionRequestsTabState();
}

class _PermissionRequestsTabState extends State<PermissionRequestsTab> {
  final RequestService _requestService = RequestService();
  List<dynamic> _requests = [];
  bool _isLoading = true;
  bool _showFilters = false;
  String _selectedStatus = 'All Status';
  final List<String> _statusOptions = const [
    'All Status',
    'Pending',
    'Approved',
    'Rejected',
    'Cancelled',
  ];
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  Map<String, dynamic>? _balance;

  void toggleFilters() {
    setState(() {
      _showFilters = !_showFilters;
    });
  }

  void refresh() {
    _fetchRequests();
  }

  @override
  void initState() {
    super.initState();
    _fetchRequests();
    _fetchBalance();
  }

  Future<void> _fetchRequests() async {
    setState(() => _isLoading = true);
    final result = await _requestService.getPermissionRequests(
      status: _selectedStatus,
      month: _selectedMonth.month,
      year: _selectedMonth.year,
    );
    if (!mounted) return;
    if (result['success'] == true) {
      final data = result['data'];
      setState(() {
        _requests = data is Map ? (data['permissions'] ?? []) : [];
        _isLoading = false;
      });
    } else {
      setState(() => _isLoading = false);
      SnackBarUtils.showSnackBar(
        context,
        ErrorMessageUtils.sanitizeForDisplay(
          result['message']?.toString(),
          fallback: 'Failed to fetch permission requests',
        ),
        isError: true,
      );
    }
  }

  Future<void> _fetchBalance() async {
    final result = await _requestService.getPermissionBalance(
      month: _selectedMonth.month,
      year: _selectedMonth.year,
    );
    if (!mounted) return;
    if (result['success'] == true) {
      setState(() {
        _balance = result['data'] is Map<String, dynamic>
            ? result['data'] as Map<String, dynamic>
            : (result['data'] is Map
                  ? Map<String, dynamic>.from(result['data'])
                  : null);
      });
    }
  }

  Future<void> _pickMonth() async {
    final now = DateTime.now();
    final initial = _selectedMonth;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 2, 1, 1),
      lastDate: DateTime(now.year + 2, 12, 31),
      helpText: 'Select Month',
      initialDatePickerMode: DatePickerMode.year,
    );
    if (picked == null) return;
    setState(() {
      _selectedMonth = DateTime(picked.year, picked.month);
    });
    await _fetchRequests();
    await _fetchBalance();
  }

  Future<void> _cancelRequest(String id) async {
    final result = await _requestService.cancelPermissionRequest(id);
    if (!mounted) return;
    if (result['success'] == true) {
      SnackBarUtils.showSnackBar(context, 'Permission request cancelled');
      await _fetchRequests();
    } else {
      SnackBarUtils.showSnackBar(
        context,
        ErrorMessageUtils.sanitizeForDisplay(
          result['message']?.toString(),
          fallback: 'Failed to cancel permission request',
        ),
        isError: true,
      );
    }
  }

  String _fmtDate(dynamic value) {
    if (value == null) return '-';
    final d = DateTime.tryParse(value.toString());
    if (d == null) return '-';
    return DateFormat('dd MMM yyyy').format(d.toLocal());
  }

  String _fmtType(String? type) {
    switch (type) {
      case 'lateArrival':
        return 'Late Arrival';
      case 'earlyExit':
        return 'Early Exit';
      case 'both':
        return 'Both';
      default:
        return type ?? '-';
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'Approved':
        return Colors.green;
      case 'Rejected':
        return Colors.red;
      case 'Cancelled':
        return Colors.grey;
      default:
        return Colors.orange;
    }
  }

  void showRequestPermissionDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      builder: (ctx) => RequestPermissionDialog(
        onSuccess: () {
          _fetchRequests();
          _fetchBalance();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final monthLabel = DateFormat('MMMM yyyy').format(_selectedMonth);
    final quota = (_balance?['monthlyQuotaMinutes'] as num?)?.toDouble() ?? 0;
    final consumed = (_balance?['consumedMinutes'] as num?)?.toDouble() ?? 0;
    final remain = (_balance?['remainingMinutes'] as num?)?.toDouble() ?? 0;
    final hours = (double v) => (v / 60).toStringAsFixed(2);

    return RefreshIndicator(
      onRefresh: () async {
        await _fetchRequests();
        await _fetchBalance();
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Permission Balance ($monthLabel)',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _pickMonth,
                    icon: const Icon(Icons.calendar_month),
                    label: const Text('Month'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _balanceTile('Quota', '${hours(quota)} h'),
              const SizedBox(width: 8),
              _balanceTile('Used', '${hours(consumed)} h'),
              const SizedBox(width: 8),
              _balanceTile('Left', '${hours(remain)} h'),
            ],
          ),
          const SizedBox(height: 12),
          if (_showFilters)
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: DropdownButtonFormField<String>(
                  value: _selectedStatus,
                  items: _statusOptions
                      .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                      .toList(),
                  decoration: const InputDecoration(labelText: 'Status'),
                  onChanged: (v) async {
                    if (v == null) return;
                    setState(() => _selectedStatus = v);
                    await _fetchRequests();
                  },
                ),
              ),
            ),
          if (_showFilters) const SizedBox(height: 12),
          if (_isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: AppTabLoader(),
              ),
            )
          else if (_requests.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('No permission requests found'),
              ),
            )
          else
            ..._requests.map((raw) {
              final req = raw is Map<String, dynamic>
                  ? raw
                  : Map<String, dynamic>.from(raw as Map);
              final status = (req['status'] ?? '').toString();
              final isPending = status == 'Pending';
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _fmtDate(req['date']),
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: _statusColor(status).withOpacity(0.12),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              status,
                              style: TextStyle(
                                color: _statusColor(status),
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text('Type: ${_fmtType(req['type']?.toString())}'),
                      Text(
                        'Requested Minutes: ${req['requestedMinutes'] ?? 0}',
                      ),
                      if ((req['reason'] ?? '')
                          .toString()
                          .trim()
                          .isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text('Reason: ${req['reason']}'),
                      ],
                      const SizedBox(height: 4),
                      Text('Applied: ${_fmtDate(req['createdAt'])}'),
                      if (isPending) ...[
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerRight,
                          child: OutlinedButton.icon(
                            onPressed: () =>
                                _cancelRequest(req['_id'].toString()),
                            icon: const Icon(Icons.cancel_outlined),
                            label: const Text('Cancel'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _balanceTile(String title, String value) {
    IconData icon;
    switch (title.toLowerCase()) {
      case 'quota':
        icon = Icons.inventory_2_outlined;
        break;
      case 'used':
        icon = Icons.timelapse_outlined;
        break;
      default:
        icon = Icons.check_circle_outline;
        break;
    }
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.primary.withOpacity(0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: AppColors.primary),
            const SizedBox(height: 6),
            Text(
              title,
              style: TextStyle(
                color: AppColors.primary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class RequestPermissionDialog extends StatefulWidget {
  final VoidCallback onSuccess;

  const RequestPermissionDialog({super.key, required this.onSuccess});

  @override
  State<RequestPermissionDialog> createState() =>
      _RequestPermissionDialogState();
}

class _RequestPermissionDialogState extends State<RequestPermissionDialog> {
  final _formKey = GlobalKey<FormState>();
  final RequestService _requestService = RequestService();
  DateTime _date = DateTime.now();
  String _type = 'both';
  final TextEditingController _minutesController = TextEditingController();
  final TextEditingController _reasonController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _minutesController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(DateTime.now().year - 1, 1, 1),
      lastDate: DateTime(DateTime.now().year + 1, 12, 31),
    );
    if (picked != null) {
      setState(() => _date = DateTime(picked.year, picked.month, picked.day));
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final minutes = int.tryParse(_minutesController.text.trim());
    final reason = _reasonController.text.trim();
    if (minutes == null || minutes <= 0) {
      SnackBarUtils.showSnackBar(
        context,
        'Requested minutes must be greater than 0',
        isError: true,
      );
      return;
    }
    if (reason.isEmpty) {
      SnackBarUtils.showSnackBar(context, 'Reason is required', isError: true);
      return;
    }

    setState(() => _isSubmitting = true);
    final result = await _requestService.createPermissionRequest(
      date: _date,
      type: _type,
      requestedMinutes: minutes,
      reason: reason,
    );
    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (result['success'] == true) {
      Navigator.of(context).pop();
      widget.onSuccess();
      final overlay = Navigator.of(context, rootNavigator: true).overlay;
      if (overlay != null && overlay.mounted) {
        showRequestSubmittedSuccessDialog(overlay.context);
      }
    } else {
      SnackBarUtils.showSnackBar(
        context,
        ErrorMessageUtils.sanitizeForDisplay(
          result['message']?.toString(),
          fallback: 'Failed to submit permission request',
        ),
        isError: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 24,
        right: 24,
        top: 24,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Request Permission',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Submit a new permission request',
                      style: TextStyle(fontSize: 14, color: Colors.black54),
                    ),
                    const SizedBox(height: 20),
                    InkWell(
                      onTap: _pickDate,
                      child: InputDecorator(
                        decoration: _inputDecoration(
                          'Date',
                          Icons.calendar_today,
                        ),
                        child: Text(
                          DateFormat('dd MMM yyyy').format(_date),
                          style: const TextStyle(fontSize: 16),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: _type,
                      decoration: _inputDecoration(
                        'Permission Type',
                        Icons.category,
                      ),
                      items: const [
                        DropdownMenuItem(value: 'both', child: Text('Both')),
                        DropdownMenuItem(
                          value: 'lateArrival',
                          child: Text('Late Arrival'),
                        ),
                        DropdownMenuItem(
                          value: 'earlyExit',
                          child: Text('Early Exit'),
                        ),
                      ],
                      onChanged: (v) => setState(() => _type = v ?? 'both'),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _minutesController,
                      keyboardType: TextInputType.number,
                      decoration: _inputDecoration(
                        'Requested Minutes',
                        Icons.access_time,
                      ),
                      validator: (value) {
                        final mins = int.tryParse((value ?? '').trim());
                        if (mins == null || mins <= 0) {
                          return 'Enter valid minutes';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _reasonController,
                      maxLines: 3,
                      decoration: _inputDecoration('Reason', Icons.notes),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter reason';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 28),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isSubmitting ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          _isSubmitting ? 'Submitting...' : 'Submit Request',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 22, color: AppColors.primary),
      labelStyle: const TextStyle(color: Colors.black),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: AppColors.primary, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );
  }
}

// --- PAYSLIP TAB ---

class PayslipRequestsTab extends StatefulWidget {
  const PayslipRequestsTab({super.key});

  @override
  State<PayslipRequestsTab> createState() => _PayslipRequestsTabState();
}

class _PayslipRequestsTabState extends State<PayslipRequestsTab> {
  final RequestService _requestService = RequestService();
  List<dynamic> _requests = [];
  bool _isLoading = true;
  String _selectedStatus = 'All Status';
  final List<String> _statusOptions = [
    'All Status',
    'Pending',
    'Approved',
    'Generated',
    'Rejected',
  ];

  Timer? _debounce;
  final TextEditingController _searchController = TextEditingController();
  DateTime? _startDate;
  DateTime? _endDate;
  int _currentPage = 1;
  final int _itemsPerPage = 10;
  int _totalPages = 0;
  bool _showFilters = false;

  void toggleFilters() {
    setState(() {
      _showFilters = !_showFilters;
    });
  }

  void refresh() {
    _fetchRequests();
  }

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _startDate = DateTime(now.year, now.month, 1);
    _endDate = DateTime(now.year, now.month + 1, 0, 23, 59, 59, 999);
    _fetchRequests();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _fetchRequests() async {
    setState(() => _isLoading = true);
    final result = await _requestService.getPayslipRequests(
      status: _selectedStatus,
      search: _searchController.text,
      startDate: _startDate,
      endDate: _endDate,
      page: _currentPage,
      limit: _itemsPerPage,
    );
    if (mounted) {
      if (result['success']) {
        setState(() {
          if (result['data'] is Map) {
            _requests = result['data']['requests'] ?? [];
            final pagination = result['data']['pagination'];
            if (pagination != null) {
              _totalPages = pagination['pages'] ?? 0;
              _currentPage = pagination['page'] ?? 1;
            }
          } else if (result['data'] is List) {
            _requests = result['data'];
            _totalPages = 1;
            _currentPage = 1;
          }
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
        SnackBarUtils.showSnackBar(
          context,
          ErrorMessageUtils.sanitizeForDisplay(
            result['message']?.toString(),
            fallback: 'Failed to fetch payslip requests',
          ),
          isError: true,
        );
      }
    }
  }

  Future<void> _viewPayslip(String? requestId, {String? payslipUrl}) async {
    if (requestId == null || requestId.isEmpty) {
      SnackBarUtils.showSnackBar(
        context,
        'Invalid payslip request id',
        isError: true,
      );
      return;
    }
    bool loadingShown = false;
    try {
      String? url = payslipUrl?.trim();
      // If URL is already present, open in browser directly (most reliable on mobile).
      if (url != null && url.isNotEmpty) {
        final uri = Uri.tryParse(url);
        if (uri != null && uri.hasScheme && await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          return;
        }
      }
      if (url == null || url.isEmpty) {
        loadingShown = true;
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(child: AppTabLoader()),
        );
        final result = await _requestService.viewPayslipRequest(requestId);
        if (mounted) {
          Navigator.pop(context);
          loadingShown = false;
        }
        url = result['payslipUrl']?.toString();
        if (url == null || url.isEmpty) {
          SnackBarUtils.showSnackBar(
            context,
            ErrorMessageUtils.sanitizeForDisplay(
              result['message']?.toString(),
              fallback: 'Payslip not available yet',
            ),
            isError: true,
          );
          return;
        }
      }

      // View: open in browser for consistent and reliable behavior on mobile.
      final uri = Uri.tryParse(url);
      if (uri != null && uri.hasScheme && await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return;
      }
      if (mounted) {
        SnackBarUtils.showSnackBar(
          context,
          'Unable to open payslip link.',
          isError: true,
        );
      }
    } catch (e) {
      if (mounted) {
        if (loadingShown) Navigator.pop(context);
        SnackBarUtils.showSnackBar(
          context,
          'Error viewing payslip: ${e.toString()}',
          isError: true,
        );
      }
    }
  }

  // Helper function to convert month number or name to month name
  String _getMonthName(dynamic month) {
    const months = [
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

    if (month is int && month >= 1 && month <= 12) {
      return months[month - 1];
    } else if (month is String) {
      // If it's already a month name, return it
      if (months.contains(month)) {
        return month;
      }
      // Try to parse as number
      final monthNum = int.tryParse(month);
      if (monthNum != null && monthNum >= 1 && monthNum <= 12) {
        return months[monthNum - 1];
      }
    }
    return month?.toString() ?? 'Unknown';
  }

  // Helper function to get period text from request
  String _getPeriodText(Map<String, dynamic> req) {
    if (req['period'] != null) {
      return req['period'].toString();
    } else if (req['month'] != null) {
      final monthName = _getMonthName(req['month']);
      final year = req['year']?.toString() ?? '';
      return '$monthName $year'.trim();
    }
    return '-';
  }

  Future<void> _downloadPayslip(
    String requestId,
    String month,
    int year, {
    String? payslipUrl,
  }) async {
    bool loadingShown = false;
    try {
      String? url = payslipUrl?.trim();
      // If URL is already present, download via browser so it lands in device Downloads.
      if (url != null && url.isNotEmpty) {
        final uri = Uri.tryParse(url);
        if (uri != null && uri.hasScheme && await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          if (mounted) {
            SnackBarUtils.showSnackBar(
              context,
              'Downloading file… Check your browser downloads.',
              isError: false,
            );
          }
          return;
        }
      }
      if (url == null || url.isEmpty) {
        loadingShown = true;
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(child: AppTabLoader()),
        );
        final result = await _requestService.downloadPayslipRequest(requestId);
        if (mounted) {
          Navigator.pop(context);
          loadingShown = false;
        }
        url = result['payslipUrl']?.toString().trim();
        if (url == null || url.isEmpty) {
          SnackBarUtils.showSnackBar(
            context,
            ErrorMessageUtils.sanitizeForDisplay(
              result['message']?.toString(),
              fallback: 'Payslip not available yet',
            ),
            isError: true,
          );
          return;
        }
      }

      // Download: always use browser so it downloads to device Downloads.
      final uri = Uri.tryParse(url);
      if (uri != null && uri.hasScheme && await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (mounted) {
          SnackBarUtils.showSnackBar(
            context,
            'Downloading file… Check your browser downloads.',
            isError: false,
          );
        }
        return;
      }
      if (mounted) {
        SnackBarUtils.showSnackBar(
          context,
          'Unable to start download.',
          isError: true,
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

  Future<void> _sharePayslipPdf({
    required String url,
    required String fileBaseName,
  }) async {
    bool loadingShown = false;
    try {
      final trimmed = url.trim();
      if (trimmed.isEmpty) {
        if (mounted) {
          SnackBarUtils.showSnackBar(
            context,
            'Payslip link not available yet',
            isError: true,
          );
        }
        return;
      }

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
      final isPdf =
          bytes.length >= 4 &&
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
      final safeBase = fileBaseName.trim().isEmpty
          ? 'Payslip'
          : fileBaseName.trim();
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

  Future<void> _openPdf(
    List<int> pdfBytes,
    String action, {
    String? month,
    int? year,
  }) async {
    try {
      // 1) Save PDF to app documents directory (visible via "App internal storage")
      final baseDir = await getApplicationDocumentsDirectory();
      final payslipsDir = Directory('${baseDir.path}/Payslips');
      if (!await payslipsDir.exists()) {
        await payslipsDir.create(recursive: true);
      }

      final fileName = month != null && year != null
          ? 'Payslip_${month}_$year.pdf'
          : 'Payslip_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final file = File('${payslipsDir.path}/$fileName');

      await file.writeAsBytes(pdfBytes, flush: true);

      if (action == 'view') {
        // 2a) VIEW: open directly with default PDF viewer
        final result = await OpenFilex.open(file.path);

        if (result.type != ResultType.done) {
          SnackBarUtils.showSnackBar(
            context,
            'Unable to open payslip: ${result.message}',
            isError: true,
          );
        }
      } else {
        // 2b) DOWNLOAD: just save file, do not open
        SnackBarUtils.showSnackBar(
          context,
          'Payslip downloaded to: ${file.path}',
        );
      }
    } catch (e) {
      SnackBarUtils.showSnackBar(
        context,
        'Error handling PDF: ${e.toString()}',
        isError: true,
      );
    }
  }

  void _showPayslipDetails(Map<String, dynamic> req) {
    final appliedDate = req['createdAt'] != null
        ? DateFormat('MMM dd, yyyy').format(DateTime.parse(req['createdAt']))
        : '—';
    String approvedBy = '—';
    String rejectedBy = '—';
    final approver = req['approvedBy'];
    final rejector = req['rejectedBy'];
    if (approver != null) {
      if (approver is Map && approver['name'] != null) {
        approvedBy = approver['name'].toString().trim();
        if (approvedBy.isEmpty) approvedBy = '—';
      } else {
        approvedBy = 'System';
      }
    }
    if (rejector != null) {
      if (rejector is Map && rejector['name'] != null) {
        rejectedBy = rejector['name'].toString().trim();
        if (rejectedBy.isEmpty) rejectedBy = '—';
      } else {
        rejectedBy = 'System';
      }
    } else if (req['status'] == 'Rejected' && approver != null) {
      rejectedBy = approvedBy;
    }
    final rejectionReason = (req['actionReason'] ?? req['rejectionReason'])
        ?.toString()
        .trim();
    final isRejected = req['status'] == 'Rejected';

    final children = <Widget>[
      _payslipDetailRow('Period', _getPeriodText(req)),
      if (req['reason'] != null && req['reason'].toString().isNotEmpty)
        _payslipDetailRow('Reason', req['reason']),
      _payslipDetailRow('Applied Date', appliedDate),
      _payslipDetailRow('Status', req['status'] ?? ''),
      if (isRejected) ...[
        _payslipDetailRow('Rejected By', rejectedBy),
        if (rejectionReason != null && rejectionReason.isNotEmpty)
          _payslipDetailRow('Rejection Reason', rejectionReason),
      ] else
        _payslipDetailRow('Approved By', approvedBy),
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _RequestDetailBottomSheet(
        title: 'Payslip Request Details',
        icon: Icons.description,
        iconColor: AppColors.primary,
        children: children,
      ),
    );
  }

  Widget _payslipDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Widget _buildPayslipCard(Map<String, dynamic> req) {
    final appliedDate = req['createdAt'] != null
        ? DateFormat('MMM dd, yyyy').format(DateTime.parse(req['createdAt']))
        : '-';
    final approver = req['approvedBy'];
    final rejector = req['rejectedBy'];
    final isRejectedPayslip = req['status'] == 'Rejected';
    final approvedBy = approver != null
        ? (approver is Map ? approver['name'] : 'System')
        : '-';
    final rejectedBy = rejector != null
        ? (rejector is Map ? rejector['name'] : 'System')
        : (isRejectedPayslip && approver != null ? approvedBy : '-');

    // Get month name from month number or period
    String periodText = 'Payslip Request';
    if (req['period'] != null) {
      periodText = req['period'].toString();
    } else if (req['month'] != null) {
      final monthName = _getMonthName(req['month']);
      final year = req['year']?.toString() ?? '';
      periodText = '$monthName $year'.trim();
    }

    Color statusColor = Colors.grey;
    if (req['status'] == 'Generated' || req['status'] == 'Approved') {
      statusColor = AppColors.success;
    } else if (req['status'] == 'Rejected') {
      statusColor = AppColors.error;
    } else if (req['status'] == 'Pending') {
      statusColor = AppColors.warning;
    }

    final isApproved =
        req['status'] == 'Approved' || req['status'] == 'Generated';

    // Payslip URL from payroll (when approved and generated)
    final payroll = req['payrollId'];
    final String? payslipUrl = payroll is Map
        ? (payroll['payslipUrl']?.toString().trim())
        : null;
    final bool hasPayslipUrl = payslipUrl != null && payslipUrl.isNotEmpty;
    if (hasPayslipUrl) {
      statusColor = AppColors.success;
    }

    // Status label: approved but not yet generated vs approved and viewable
    String statusLabel = req['status'] ?? '';
    if (isApproved && !hasPayslipUrl) {
      statusLabel = 'Approved - wait for generation';
    }
    if (hasPayslipUrl) {
      statusLabel = 'Generated';
    }

    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => _showPayslipDetails(req),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colorScheme.outline),
          boxShadow: [
            BoxShadow(
              color: colorScheme.shadow.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              // Icon
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.description,
                  color: AppColors.primary,
                  size: 32,
                ),
              ),
              const SizedBox(width: 16),
              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Period and Status
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            periodText,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onSurface,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: statusColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            statusLabel,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: statusColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Details
                    if (req['reason'] != null &&
                        req['reason'].toString().isNotEmpty) ...[
                      _buildPayslipCardDetailRow(
                        Icons.info_outline,
                        'Reason',
                        req['reason'] ?? '',
                      ),
                      const SizedBox(height: 4),
                    ],
                    _buildPayslipCardDetailRow(
                      Icons.access_time,
                      'Applied',
                      appliedDate,
                    ),
                    if (isRejectedPayslip && rejectedBy != '-') ...[
                      const SizedBox(height: 4),
                      _buildPayslipCardDetailRow(
                        Icons.person_off_outlined,
                        'Rejected By',
                        rejectedBy,
                      ),
                    ] else if (!isRejectedPayslip && approvedBy != '-') ...[
                      const SizedBox(height: 4),
                      _buildPayslipCardDetailRow(
                        Icons.person,
                        'Approved By',
                        approvedBy,
                      ),
                    ],
                    // Download / Share actions – show whenever payslip URL exists
                    if (hasPayslipUrl) ...[
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          IconButton(
                            tooltip: 'Share Payslip',
                            icon: const Icon(Icons.ios_share_rounded, size: 20),
                            color: AppColors.primary,
                            onPressed: () {
                              String monthName = 'Month';
                              int year = DateTime.now().year;
                              if (req['month'] != null && req['year'] != null) {
                                monthName = _getMonthName(req['month']);
                                final yr = req['year'];
                                if (yr is int) {
                                  year = yr;
                                } else if (yr is num) {
                                  year = yr.toInt();
                                } else if (yr is String) {
                                  year = int.tryParse(yr) ?? year;
                                }
                              } else {
                                final period = _getPeriodText(req);
                                final parts = period.split(' ');
                                if (parts.isNotEmpty) monthName = parts[0];
                                if (parts.length > 1) {
                                  final yr = int.tryParse(parts[1]);
                                  if (yr != null) year = yr;
                                }
                              }
                              _sharePayslipPdf(
                                url: payslipUrl,
                                fileBaseName: 'Payslip_$monthName',
                              );
                            },
                          ),
                          const SizedBox(width: 4),
                          IconButton(
                            tooltip: 'Download Payslip',
                            icon: const Icon(Icons.download_outlined, size: 20),
                            color: AppColors.primary,
                            onPressed: () {
                              final requestId = req['_id']?.toString();
                              if (requestId == null || requestId.isEmpty) {
                                SnackBarUtils.showSnackBar(
                                  context,
                                  'Invalid payslip request id',
                                  isError: true,
                                );
                                return;
                              }
                              String monthName = 'Month';
                              int year = DateTime.now().year;
                              if (req['month'] != null && req['year'] != null) {
                                monthName = _getMonthName(req['month']);
                                final yr = req['year'];
                                if (yr is int) {
                                  year = yr;
                                } else if (yr is num) {
                                  year = yr.toInt();
                                } else if (yr is String) {
                                  year = int.tryParse(yr) ?? year;
                                }
                              } else {
                                final period = _getPeriodText(req);
                                final parts = period.split(' ');
                                if (parts.isNotEmpty) monthName = parts[0];
                                if (parts.length > 1) {
                                  final yr = int.tryParse(parts[1]);
                                  if (yr != null) year = yr;
                                }
                              }
                              _downloadPayslip(
                                requestId,
                                monthName,
                                year,
                                payslipUrl: payslipUrl,
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPayslipCardDetailRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 14, color: const Color(0xFF424242)),
        const SizedBox(width: 6),
        Text(
          '$label: ',
          style: TextStyle(
            fontSize: 12,
            color: Color(0xFF424242),
            fontWeight: FontWeight.w600,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(fontSize: 12, color: Color(0xFF424242)),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  void showRequestPayslipDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      builder: (ctx) => RequestPayslipDialog(onSuccess: _fetchRequests),
    );
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePickerSameCalendar(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialStart: _startDate,
      initialEnd: _endDate,
    );
    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end.add(
          const Duration(hours: 23, minutes: 59, seconds: 59),
        );
      });
      _fetchRequests();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Controls Column
        if (_showFilters)
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search Reason, Month...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 0,
                    ),
                  ),
                  onChanged: (val) {
                    if (_debounce?.isActive ?? false) _debounce!.cancel();
                    _debounce = Timer(const Duration(milliseconds: 500), () {
                      _fetchRequests();
                    });
                  },
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade400),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _selectedStatus,
                            isExpanded: true,
                            items: _statusOptions
                                .map(
                                  (e) => DropdownMenuItem(
                                    value: e,
                                    child: Text(e),
                                  ),
                                )
                                .toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setState(() => _selectedStatus = val);
                                _fetchRequests();
                              }
                            },
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    InkWell(
                      onTap: _pickDateRange,
                      child: Container(
                        height: 48,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade400),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.calendar_today,
                              color: Colors.grey[600],
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _startDate == null
                                  ? 'Date'
                                  : '${DateFormat('MMM dd').format(_startDate!)} - ${DateFormat('MMM dd').format(_endDate!)}',
                              style: TextStyle(color: Colors.black),
                            ),
                            if (_startDate != null)
                              IconButton(
                                icon: const Icon(Icons.close, size: 16),
                                onPressed: () {
                                  setState(() {
                                    _startDate = null;
                                    _endDate = null;
                                  });
                                  _fetchRequests();
                                },
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

        // List Body
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              setState(() => _currentPage = 1);
              await _fetchRequests();
            },
            child: _isLoading
                ? const Center(child: AppTabLoader())
                : _requests.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      SizedBox(
                        height: MediaQuery.of(context).size.height * 0.5,
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.description_outlined,
                                size: 64,
                                color: Colors.grey[400],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No payslip requests found',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.black,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  )
                : ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    itemCount: _requests.length,
                    itemBuilder: (ctx, i) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12.0),
                        child: _buildPayslipCard(_requests[i]),
                      );
                    },
                  ),
          ),
        ),

        // Pagination Controls
        if (!_isLoading && _requests.isNotEmpty)
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 140, 16),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left, size: 22),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: _currentPage > 1
                      ? () {
                          setState(() => _currentPage--);
                          _fetchRequests();
                        }
                      : null,
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '$_currentPage',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.chevron_right, size: 22),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: _currentPage < _totalPages
                      ? () {
                          setState(() => _currentPage++);
                          _fetchRequests();
                        }
                      : null,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class RequestPayslipDialog extends StatefulWidget {
  final VoidCallback onSuccess;
  const RequestPayslipDialog({super.key, required this.onSuccess});

  @override
  State<RequestPayslipDialog> createState() => _RequestPayslipDialogState();
}

class _RequestPayslipDialogState extends State<RequestPayslipDialog> {
  final _formKey = GlobalKey<FormState>();
  final RequestService _requestService = RequestService();
  final AuthService _authService = AuthService();

  bool _isBulkMode = false;
  String _month = 'January';
  final TextEditingController _yearController = TextEditingController(
    text: DateTime.now().year.toString(),
  );
  final TextEditingController _reasonController = TextEditingController();
  bool _isSubmitting = false;
  List<dynamic> _existingRequests = [];
  final Set<String> _selectedMonths = {};
  DateTime? _joiningDate;

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

  @override
  void initState() {
    super.initState();
    _loadJoiningDateAndExistingRequests();
  }

  /// Parse joining date from API/prefs (ISO string or { "$date": "..." }).
  static DateTime? _parseJoiningDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    String? str;
    if (value is String) {
      str = value;
    } else if (value is Map && value.containsKey(r'$date')) {
      str = value[r'$date']?.toString();
    }
    if (str == null || str.isEmpty) return null;
    return DateTime.tryParse(str);
  }

  Future<void> _loadJoiningDateAndExistingRequests() async {
    final profileResult = await _authService.getProfile();
    DateTime? joining;
    if (profileResult['success'] == true && profileResult['data'] is Map) {
      final data = profileResult['data'] as Map<String, dynamic>;
      final staffData = data['staffData'];
      if (staffData is Map && staffData.containsKey('joiningDate')) {
        joining = _parseJoiningDate(staffData['joiningDate']);
      }
      if (joining == null && data.containsKey('joiningDate')) {
        joining = _parseJoiningDate(data['joiningDate']);
      }
    }
    final result = await _requestService.getPayslipRequests();
    if (mounted) {
      setState(() {
        _joiningDate = joining;
        if (result['success'] && result['data'] != null) {
          if (result['data'] is Map) {
            _existingRequests = result['data']['requests'] ?? [];
          } else if (result['data'] is List) {
            _existingRequests = result['data'];
          }
        }
        _clampMonthAndYearToAllowed();
      });
    }
  }

  int get _currentYear => DateTime.now().year;
  int get _currentMonth => DateTime.now().month;
  int get _joiningYear => _joiningDate?.year ?? _currentYear;
  int get _joiningMonth => _joiningDate?.month ?? 1;

  List<int> get _allowedYears {
    final joinYear = _joiningYear;
    final end = _currentYear;
    if (joinYear > end) return [end];
    return List.generate(end - joinYear + 1, (i) => joinYear + i);
  }

  int get _selectedYear {
    final y = int.tryParse(_yearController.text) ?? _currentYear;
    final allowed = _allowedYears;
    if (allowed.isEmpty) return _currentYear;
    if (y < allowed.first) return allowed.first;
    if (y > allowed.last) return allowed.last;
    return y;
  }

  List<String> get _allowedMonthsForSelectedYear {
    final year = _selectedYear;
    int first = 1;
    int last = 12;
    if (year == _joiningYear) first = _joiningMonth;
    // Only completed previous months – exclude current month (payslip not ready for current month yet)
    if (year == _currentYear) last = _currentMonth - 1;
    if (first > last) return [];
    return _months.sublist(first - 1, last);
  }

  void _clampMonthAndYearToAllowed() {
    final allowedYears = _allowedYears;
    if (allowedYears.isEmpty) return;
    int year = int.tryParse(_yearController.text) ?? _currentYear;
    if (year < allowedYears.first || year > allowedYears.last) {
      _yearController.text = allowedYears.last.toString();
    }
    final allowedMonths = _allowedMonthsForSelectedYear;
    if (allowedMonths.isEmpty) return;
    if (!allowedMonths.contains(_month)) {
      _month = allowedMonths.last;
    }
    _selectedMonths.removeWhere((m) => !allowedMonths.contains(m));
  }

  bool _isDuplicateRequest(String month, int year) {
    // Convert month name to number for comparison
    final monthNumber = _months.indexOf(month) + 1;
    return _existingRequests.any((req) {
      final reqMonth = req['month'];
      // Handle both number and string formats
      final reqMonthNumber = reqMonth is int
          ? reqMonth
          : (reqMonth is String ? _months.indexOf(reqMonth) + 1 : 0);
      return reqMonthNumber == monthNumber && req['year'] == year;
    });
  }

  Future<void> _pickYear() async {
    final years = _allowedYears;
    if (years.isEmpty) return;
    final currentYear = _selectedYear;
    if (!mounted) return;
    final picked = await showModalBottomSheet<int>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Select Year',
                  style: Theme.of(
                    ctx,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: years.length,
                  itemBuilder: (context, index) {
                    final year = years[index];
                    return ListTile(
                      title: Text('$year'),
                      selected: year == currentYear,
                      onTap: () => Navigator.pop(context, year),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
    if (picked != null && mounted) {
      setState(() {
        _yearController.text = picked.toString();
        _clampMonthAndYearToAllowed();
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final selectedYear =
        int.tryParse(_yearController.text) ?? DateTime.now().year;
    final reason = _reasonController.text.trim();

    if (_isBulkMode) {
      // Bulk request
      if (_selectedMonths.isEmpty) {
        SnackBarUtils.showSnackBar(
          context,
          'Please select at least one month',
          isError: true,
        );
        return;
      }

      // Check for duplicates
      final duplicateMonths = _selectedMonths
          .where((month) => _isDuplicateRequest(month, selectedYear))
          .toList();

      if (duplicateMonths.isNotEmpty) {
        SnackBarUtils.showSnackBar(
          context,
          'Requests already exist for: ${duplicateMonths.join(", ")}',
          isError: true,
        );
        return;
      }

      setState(() => _isSubmitting = true);
      // Convert month names to numbers (January = 1, December = 12)
      final monthNumbers = _selectedMonths
          .map((monthName) => _months.indexOf(monthName) + 1)
          .toList();
      final result = await _requestService.requestPayslip({
        'months': monthNumbers,
        'year': selectedYear,
        'reason': reason,
      });
      setState(() => _isSubmitting = false);

      if (mounted) {
        if (result['success']) {
          final overlay = Navigator.of(context, rootNavigator: true).overlay;
          widget.onSuccess();
          Navigator.pop(context);
          if (overlay != null && overlay.context.mounted) {
            showRequestSubmittedSuccessDialog(overlay.context);
          }
        } else {
          SnackBarUtils.showSnackBar(
            context,
            ErrorMessageUtils.sanitizeForDisplay(
              result['message']?.toString(),
              fallback: 'Failed to submit payslip requests',
            ),
            isError: true,
          );
        }
      }
    } else {
      // Single request
      if (_isDuplicateRequest(_month, selectedYear)) {
        SnackBarUtils.showSnackBar(
          context,
          'A payslip request for $_month $selectedYear already exists',
          isError: true,
        );
        return;
      }

      setState(() => _isSubmitting = true);
      // Convert month name to number (January = 1, December = 12)
      final monthNumber = _months.indexOf(_month) + 1;
      final result = await _requestService.requestPayslip({
        'month': monthNumber,
        'year': selectedYear,
        'reason': reason,
      });
      setState(() => _isSubmitting = false);

      if (mounted) {
        if (result['success']) {
          final overlay = Navigator.of(context, rootNavigator: true).overlay;
          widget.onSuccess();
          Navigator.pop(context);
          if (overlay != null && overlay.context.mounted) {
            showRequestSubmittedSuccessDialog(overlay.context);
          }
        } else {
          SnackBarUtils.showSnackBar(
            context,
            ErrorMessageUtils.sanitizeForDisplay(
              result['message']?.toString(),
              fallback: 'Failed to submit payslip request',
            ),
            isError: true,
          );
        }
      }
    }
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 22, color: AppColors.primary),
      labelStyle: const TextStyle(color: Colors.black),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: AppColors.primary, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 24,
        right: 24,
        top: 24,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.description,
                          color: AppColors.primary,
                          size: 26,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Request Payslip',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Submit a new payslip request',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, size: 28),
                ),
              ],
            ),
            const Divider(),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: ChoiceChip(
                            label: Text('Single Month'),
                            selected: !_isBulkMode,
                            selectedColor: AppColors.primary.withOpacity(0.2),
                            onSelected: (selected) {
                              setState(() {
                                _isBulkMode = !selected;
                                if (!_isBulkMode) _selectedMonths.clear();
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ChoiceChip(
                            label: Text('Bulk Months'),
                            selected: _isBulkMode,
                            selectedColor: AppColors.primary.withOpacity(0.2),
                            onSelected: (selected) {
                              setState(() {
                                _isBulkMode = selected;
                                if (_isBulkMode) {
                                  _month =
                                      _allowedMonthsForSelectedYear.isNotEmpty
                                      ? _allowedMonthsForSelectedYear.first
                                      : 'January';
                                }
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    if (!_isBulkMode) ...[
                      Padding(
                        padding: const EdgeInsets.only(bottom: 20),
                        child: DropdownButtonFormField<String>(
                          initialValue:
                              _allowedMonthsForSelectedYear.contains(_month)
                              ? _month
                              : (_allowedMonthsForSelectedYear.isNotEmpty
                                    ? _allowedMonthsForSelectedYear.first
                                    : 'January'),
                          items: _allowedMonthsForSelectedYear
                              .map(
                                (e) =>
                                    DropdownMenuItem(value: e, child: Text(e)),
                              )
                              .toList(),
                          onChanged: _allowedMonthsForSelectedYear.isEmpty
                              ? null
                              : (val) => setState(() => _month = val!),
                          decoration: _inputDecoration(
                            'Month',
                            Icons.calendar_month,
                          ),
                        ),
                      ),
                    ] else ...[
                      Text(
                        'Select Months *',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        padding: const EdgeInsets.all(12),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _allowedMonthsForSelectedYear.map((month) {
                            final isSelected = _selectedMonths.contains(month);
                            return FilterChip(
                              label: Text(month),
                              selected: isSelected,
                              selectedColor: AppColors.primary.withOpacity(0.2),
                              onSelected: (selected) {
                                setState(() {
                                  if (selected) {
                                    _selectedMonths.add(month);
                                  } else {
                                    _selectedMonths.remove(month);
                                  }
                                });
                              },
                            );
                          }).toList(),
                        ),
                      ),
                      if (_selectedMonths.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Selected: ${_selectedMonths.length} month(s)',
                          style: TextStyle(
                            color: AppColors.primary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                    ],

                    InkWell(
                      onTap: _pickYear,
                      borderRadius: BorderRadius.circular(16),
                      child: IgnorePointer(
                        child: TextFormField(
                          controller: _yearController,
                          readOnly: true,
                          style: TextStyle(fontWeight: FontWeight.w500),
                          decoration:
                              _inputDecoration(
                                'Year',
                                Icons.calendar_today,
                              ).copyWith(
                                hintText: 'Tap to select year',
                                suffixIcon: const Icon(
                                  Icons.arrow_drop_down,
                                  color: Colors.grey,
                                ),
                              ),
                          validator: (val) => val == null || val.isEmpty
                              ? 'Year is required'
                              : null,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: _reasonController,
                      maxLines: 3,
                      style: TextStyle(fontWeight: FontWeight.w500),
                      decoration: _inputDecoration(
                        'Reason *',
                        Icons.note,
                      ).copyWith(hintText: 'Enter reason for payslip request'),
                      validator: (val) => val == null || val.trim().isEmpty
                          ? 'Reason is required'
                          : null,
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: BorderSide(color: AppColors.primary),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isSubmitting ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                      child: _isSubmitting
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              _isBulkMode
                                  ? 'Submit Bulk Request'
                                  : 'Submit Request',
                            ),
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
}
