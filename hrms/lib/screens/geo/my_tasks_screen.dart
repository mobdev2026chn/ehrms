// hrms/lib/screens/geo/my_tasks_screen.dart
import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:excel/excel.dart' hide Border;
import 'package:flutter/material.dart';
import 'package:hrms/config/app_colors.dart';
import 'package:hrms/config/app_route_observer.dart';
import 'package:hrms/models/task.dart';
import 'package:hrms/services/customer_service.dart';
import 'package:hrms/services/task_service.dart';
import 'package:hrms/services/geo/live_tracking_service.dart';
import 'package:hrms/services/geo/location_service.dart';
import 'package:hrms/services/presence_tracking_service.dart';
import 'package:hrms/screens/geo/field_out_form_screen.dart';
import 'package:background_location_tracker/background_location_tracker.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' show LatLng;
import 'package:hrms/screens/dashboard/dashboard_screen.dart';
import 'package:hrms/screens/geo/add_task_screen.dart';
import 'package:hrms/screens/geo/add_customer_screen.dart';
import 'package:hrms/models/customer.dart';
import 'package:hrms/widgets/app_drawer.dart';
import 'package:hrms/widgets/bottom_navigation_bar.dart';
import 'package:hrms/screens/geo/arrived_screen.dart';
import 'package:hrms/screens/geo/completed_task_detail_screen.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hrms/screens/geo/task_detail_screen.dart';
import 'package:hrms/screens/geo/my_day_route_screen.dart';
import 'package:intl/intl.dart';
import 'package:hrms/utils/date_display_util.dart';
import 'package:hrms/utils/error_message_utils.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:hrms/widgets/app_tab_loader.dart';
import 'package:hrms/utils/snackbar_utils.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MyTasksScreen extends StatefulWidget {
  final int? dashboardTabIndex;
  final void Function(int index)? onNavigateToIndex;

  /// Open on the History tab (the last tab), e.g. when coming back from a
  /// Task Completion Report.
  final bool openHistory;

  const MyTasksScreen({
    super.key,
    this.dashboardTabIndex,
    this.onNavigateToIndex,
    this.openHistory = false,
  });

  @override
  State<MyTasksScreen> createState() => _MyTasksScreenState();
}

class _MyTasksScreenState extends State<MyTasksScreen>
    with WidgetsBindingObserver, RouteAware, TickerProviderStateMixin {
  String? _loggedInStaffId;
  List<Task> _tasks = [];
  bool _isLoading = true;
  String? _errorMessage;

  late TabController _mainTabController;
  List<Customer> _customers = [];
  bool _isLoadingCustomers = true;

  bool _isInternalStaff = false;
  bool _isFieldEmployee = false;
  List<Map<String, dynamic>> _allowances = [];
  bool _isLoadingAllowances = false;
  List<Task> _historyTasks = [];
  bool _isLoadingHistory = false;
  Map<String, dynamic>? _activeJourney;

  /// Admin external Field-Out form fields, delivered by GET /journey as `requirements`.
  List<TaskRequirement> _journeyRequirements = const [];
  bool _isJourneyActionLoading = false;

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  DateTime? _filterStartDate;
  DateTime? _filterEndDate;
  bool _isSelectionMode = false;
  final Set<String> _selectedTaskIds = {};
  bool _exporting = false;
  // Selected status-filter group key; null = All Statuses.
  String? _statusFilter;
  String? _employeeTypeFilter;
  String _selectedDateRange = 'All Dates';

  // One group per status the backend actually has (Assigned, Pending, Requested, Started,
  // Arrived, Hold, Exited, Completed, plus the computed Expired); each status in exactly one.
  static const List<({String label, String? group})> _statusFilterOptions = [
    (label: 'All Statuses', group: null),
    (label: 'Assigned', group: 'Assigned'),
    (label: 'In Progress', group: 'Started'),
    (label: 'Requested', group: 'Requested'),
    (label: 'Completed', group: 'Completed'),
    (label: 'Expired / Exited', group: 'Expired'),
  ];

  static const List<({String label, String? type})> _employeeTypeOptions = [
    (label: 'All Types', type: null),
    (label: 'Internal', type: 'Internal'),
    (label: 'External', type: 'External'),
  ];

  static const List<String> _dateRangeOptions = [
    'All Dates',
    'Today',
    'Yesterday',
    'Last 7 Days',
    'Last 30 Days',
    'This Month',
    'Last Month',
    'Custom Date Range',
  ];
  int _tasksPage = 1;
  static const int _tasksPerPage = 5;

  // Customers are paginated client-side (the service returns the full list):
  // show 10 cards per page with a page-number + arrow bar like the task list.
  int _customersPage = 1;
  static const int _customersPerPage = 10;

  // One grid for the Tasks tab header (search, stats, status filter, journey
  // banner) so every block shares the same margins, gaps, radius and heights.
  static const double _kHeaderHPad = 12;
  static const double _kHeaderGap = 10;
  static const double _kHeaderRadius = 14;
  static const double _kHeaderControlHeight = 48;

  /// Card header date + time. HRMSbackend sends `assignedDate` as a date only
  /// ("2026-09-29"), so the time comes from when the task was started
  /// (`fieldInTime` / timeIn — for a Field Journey, the moment it was created).
  /// Not started yet → date only.
  static DateTime _taskCardDateTime(Task task) {
    final d = task.assignedDate ?? task.expectedCompletionDate;
    final day = d.isUtc ? d.toLocal() : d;
    final st = task.startTime;
    if (st == null) return day;
    final t = st.isUtc ? st.toLocal() : st;
    if (t.hour == 0 && t.minute == 0) return day;
    return DateTime(day.year, day.month, day.day, t.hour, t.minute);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // History is the last tab (index 3 for external staff; re-picked below once
    // the field type is known and internal staff get 3 tabs).
    _mainTabController = TabController(length: 4, vsync: this, initialIndex: widget.openHistory ? 3 : 0);
    _mainTabController.addListener(() {
      if (!_mainTabController.indexIsChanging && mounted) setState(() {});
    });
    _loadLoggedInStaffId();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      appRouteObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    appRouteObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    _mainTabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didPopNext() {
    if (mounted) {
      _fetchTasks();
      if (!_isInternalStaff) {
        _fetchCustomers();
        _fetchJourneyStatus();
      }
      _fetchAllowances();
      _fetchHistory();
    }
  }

  /// Every loaded task that matches the active search + date + status filters,
  /// ordered but NOT yet paginated. All filtering is done client-side over the
  /// full assigned-task list so the result is consistent no matter what the
  /// backend returns — this is what keeps the stat cards, the filter dropdown
  /// and the pagination bar in agreement (the previous server-paginated path
  /// left pagination counting tasks the status filter then hid).
  List<Task> get _matchedTasks {
    Iterable<Task> list = _tasks;

    // Strict fieldType filtering:
    // Internal employees only see Internal tasks; External employees only see External tasks.
    if (_isInternalStaff) {
      list = list.where((t) => (t.type ?? '').toLowerCase() == 'internal');
    } else {
      list = list.where((t) => (t.type ?? 'external').toLowerCase() == 'external');
    }

    final group = _statusFilter;
    if (group != null) {
      final allowed = _statusesForGroup(group);
      if (allowed.isNotEmpty) {
        list = list.where((t) => allowed.contains(t.status));
      }
    }

    final empType = _employeeTypeFilter;
    if (empType != null && empType.isNotEmpty) {
      list = list.where((t) => (t.type ?? 'External').toLowerCase() == empType.toLowerCase());
    }

    final q = _searchQuery.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((t) => _taskMatchesSearch(t, q));
    }

    if (_filterStartDate != null || _filterEndDate != null) {
      list = list.where(_taskInDateRange);
    }

    return _orderTasks(list.toList());
  }

  /// The slice of [_matchedTasks] shown on the current page.
  List<Task> get _filteredTasks {
    final matched = _matchedTasks;
    final start = (_currentTaskPage - 1) * _tasksPerPage;
    if (start >= matched.length) return const [];
    final end = math.min(start + _tasksPerPage, matched.length);
    return matched.sublist(start, end);
  }

  /// Mirrors the backend search: task id/title/description + customer
  /// name/number, all case-insensitive.
  bool _taskMatchesSearch(Task t, String q) {
    bool has(String? s) => (s ?? '').toLowerCase().contains(q);
    return has(t.taskId) ||
        has(t.taskTitle) ||
        has(t.description) ||
        has(t.customer?.customerName) ||
        has(t.customer?.customerNumber);
  }

  /// Whether the task's created-date calendar day falls within the selected
  /// range (inclusive). Uses [Task.assignedDate] (falls back to createdAt in
  /// the model), matching the date shown on each task card.
  bool _taskInDateRange(Task t) {
    final du = (t.assignedDate ?? t.expectedCompletionDate).toLocal();
    final day = DateTime(du.year, du.month, du.day);
    final s = _filterStartDate;
    if (s != null && day.isBefore(DateTime(s.year, s.month, s.day))) {
      return false;
    }
    final e = _filterEndDate;
    if (e != null && day.isAfter(DateTime(e.year, e.month, e.day))) {
      return false;
    }
    return true;
  }

  /// Orders tasks by assignment date, most recently assigned first.
  List<Task> _orderTasks(List<Task> tasks) {
    tasks.sort((a, b) {
      final da = a.assignedDate;
      final db = b.assignedDate;
      if (da == null && db == null) return 0;
      if (da == null) return 1;
      if (db == null) return -1;
      return db.compareTo(da);
    });
    return tasks;
  }

  /// TaskStatus values mapped to the exact Web filter categories.
  Set<TaskStatus> _statusesForGroup(String group) {
    switch (group.toLowerCase()) {
      case 'assigned':
      case 'pending':
        return {TaskStatus.assigned, TaskStatus.pending, TaskStatus.scheduled};
      case 'started':
      case 'inprogress':
        return {TaskStatus.inProgress, TaskStatus.arrived, TaskStatus.hold, TaskStatus.holdOnArrival};
      case 'completed':
        return {TaskStatus.completed, TaskStatus.approved, TaskStatus.staffapproved};
      case 'requested':
      case 'reopened':
        return {TaskStatus.requested, TaskStatus.reopened, TaskStatus.reopenedOnArrival};
      case 'expired':
      case 'exited':
      case 'rejected':
        return {TaskStatus.expired, TaskStatus.exited, TaskStatus.exitedOnArrival, TaskStatus.rejected, TaskStatus.cancelled};
      default:
        return const {};
    }
  }

  /// Same grouping as the filter, so a count always matches what the filter shows.
  int _statusGroupCount(String group) {
    final statuses = _statusesForGroup(group);
    return _tasks.where((t) => statuses.contains(t.status)).length;
  }

  bool get _hasAnyFilters =>
      _searchQuery.trim().isNotEmpty ||
      _filterStartDate != null ||
      _filterEndDate != null ||
      _statusFilter != null ||
      _employeeTypeFilter != null;

  int get _totalTaskPages =>
      math.max((_matchedTasks.length / _tasksPerPage).ceil(), 1);

  int get _currentTaskPage =>
      math.min(math.max(_tasksPage, 1), _totalTaskPages);

  int get _customersTotalPages =>
      math.max((_customers.length / _customersPerPage).ceil(), 1);

  int get _currentCustomerPage =>
      math.min(math.max(_customersPage, 1), _customersTotalPages);

  /// The slice of customers shown on the current page (up to 10).
  List<Customer> get _pagedCustomers {
    final start = (_currentCustomerPage - 1) * _customersPerPage;
    if (start >= _customers.length) return const [];
    final end = math.min(start + _customersPerPage, _customers.length);
    return _customers.sublist(start, end);
  }

  Future<void> _openTaskFilterBottomSheet() async {
    String? tempStatus = _statusFilter;
    String? tempType = _employeeTypeFilter;
    String tempDateRange = _selectedDateRange;
    DateTime? tempStart = _filterStartDate;
    DateTime? tempEnd = _filterEndDate;

    final colorScheme = Theme.of(context).colorScheme;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setBottomState) {
            void applyDateRangeSelection(String option) async {
              final now = DateTime.now();
              final today = DateTime(now.year, now.month, now.day);
              if (option == 'All Dates') {
                tempStart = null;
                tempEnd = null;
              } else if (option == 'Today') {
                tempStart = today;
                tempEnd = today;
              } else if (option == 'Yesterday') {
                final y = today.subtract(const Duration(days: 1));
                tempStart = y;
                tempEnd = y;
              } else if (option == 'Last 7 Days') {
                tempStart = today.subtract(const Duration(days: 6));
                tempEnd = today;
              } else if (option == 'Last 30 Days') {
                tempStart = today.subtract(const Duration(days: 29));
                tempEnd = today;
              } else if (option == 'This Month') {
                tempStart = DateTime(now.year, now.month, 1);
                tempEnd = DateTime(now.year, now.month + 1, 0);
              } else if (option == 'Last Month') {
                tempStart = DateTime(now.year, now.month - 1, 1);
                tempEnd = DateTime(now.year, now.month, 0);
              } else if (option == 'Custom Date Range') {
                final base = DateTime.now();
                final range = await showDateRangePicker(
                  context: ctx,
                  firstDate: DateTime(2020),
                  lastDate: base.add(const Duration(days: 365)),
                  initialDateRange: tempStart != null && tempEnd != null
                      ? DateTimeRange(start: tempStart!, end: tempEnd!)
                      : null,
                );
                if (range != null) {
                  setBottomState(() {
                    tempStart = range.start;
                    tempEnd = range.end;
                    tempDateRange = 'Custom Date Range';
                  });
                  return;
                }
              }
              setBottomState(() {
                tempDateRange = option;
              });
            }

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  20,
                  16,
                  20,
                  16 + MediaQuery.of(ctx).viewInsets.bottom,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Header
                      Row(
                        children: [
                          Icon(Icons.filter_alt_rounded, color: AppColors.primary, size: 22),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'TASK LIST FILTERS',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.of(ctx).pop(),
                            icon: const Icon(Icons.close, size: 20),
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Section 1: Task Status
                      const Text(
                        'TASK STATUS',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textSecondary,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String?>(
                            isExpanded: true,
                            value: tempStatus,
                            borderRadius: BorderRadius.circular(10),
                            items: _statusFilterOptions
                                .map((o) => DropdownMenuItem<String?>(
                                      value: o.group,
                                      child: Text(o.label),
                                    ))
                                .toList(),
                            onChanged: (val) {
                              setBottomState(() => tempStatus = val);
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Section 2: Employee Type
                      const Text(
                        'EMPLOYEE TYPE',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textSecondary,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String?>(
                            isExpanded: true,
                            value: tempType,
                            borderRadius: BorderRadius.circular(10),
                            items: _employeeTypeOptions
                                .map((o) => DropdownMenuItem<String?>(
                                      value: o.type,
                                      child: Text(o.label),
                                    ))
                                .toList(),
                            onChanged: (val) {
                              setBottomState(() => tempType = val);
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Section 3: Date Range
                      const Text(
                        'DATE RANGE',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textSecondary,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            isExpanded: true,
                            value: tempDateRange,
                            borderRadius: BorderRadius.circular(10),
                            items: _dateRangeOptions
                                .map((o) => DropdownMenuItem<String>(
                                      value: o,
                                      child: Text(o),
                                    ))
                                .toList(),
                            onChanged: (val) {
                              if (val != null) applyDateRangeSelection(val);
                            },
                          ),
                        ),
                      ),
                      if (tempStart != null && tempEnd != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Selected: ${DateFormat('dd MMM yyyy').format(tempStart!)} - ${DateFormat('dd MMM yyyy').format(tempEnd!)}',
                          style: TextStyle(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w600),
                        ),
                      ],
                      const SizedBox(height: 24),

                      // Actions: Reset + Apply
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () {
                                setBottomState(() {
                                  tempStatus = null;
                                  tempType = null;
                                  tempDateRange = 'All Dates';
                                  tempStart = null;
                                  tempEnd = null;
                                });
                                setState(() {
                                  _statusFilter = null;
                                  _employeeTypeFilter = null;
                                  _selectedDateRange = 'All Dates';
                                  _filterStartDate = null;
                                  _filterEndDate = null;
                                  _tasksPage = 1;
                                });
                                Navigator.of(ctx).pop();
                              },
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              child: const Text('Reset', style: TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () {
                                setState(() {
                                  _statusFilter = tempStatus;
                                  _employeeTypeFilter = tempType;
                                  _selectedDateRange = tempDateRange;
                                  _filterStartDate = tempStart;
                                  _filterEndDate = tempEnd;
                                  _tasksPage = 1;
                                });
                                Navigator.of(ctx).pop();
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                elevation: 0,
                              ),
                              child: const Text(
                                'Apply',
                                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSearchAndRefreshRow() {
    // Same page background, width and corner radius as the cards below it.
    const soft = OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(_kHeaderRadius)),
      borderSide: BorderSide(color: Color(0xFFE2E8F0)),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(_kHeaderHPad, _kHeaderGap, _kHeaderHPad, 0),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Customer name, task name, task ID',
          hintStyle: const TextStyle(fontSize: 14, color: Color(0xFF94A3B8)),
          prefixIcon: const Icon(Icons.search, size: 20, color: Color(0xFF94A3B8)),
          isDense: true,
          // 48px tall, same as the status filter.
          constraints: const BoxConstraints(minHeight: _kHeaderControlHeight),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 14,
          ),
          border: soft,
          enabledBorder: soft,
          focusedBorder: soft.copyWith(
            borderSide: BorderSide(color: AppColors.primary, width: 1.5),
          ),
          filled: true,
          fillColor: Colors.white,
        ),
        onChanged: (_) {
          // Filtering is client-side, so the list updates as the user types
          // without a network round-trip.
          setState(() {
            _searchQuery = _searchController.text;
            _tasksPage = 1;
          });
        },
      ),
    );
  }

  /// Safe string for Excel cell (null, dates, numbers).
  static String _cellStr(dynamic value) {
    if (value == null) return '';
    if (value is DateTime) {
      return DateDisplayUtil.formatForDisplay(value, 'yyyy-MM-dd HH:mm');
    }
    final s = value.toString().trim();
    return s.replaceAll('\r', ' ').replaceAll('\n', ' ');
  }

  Future<void> _exportSelectedToExcel() async {
    final ids = _selectedTaskIds.toList();
    final toExport = _filteredTasks
        .where((t) => ids.contains(t.id ?? t.taskId))
        .toList();
    if (toExport.isEmpty) {
      SnackBarUtils.showSnackBar(
        context,
        'Select at least one task to export',
        isError: true,
      );
      return;
    }
    setState(() => _exporting = true);
    try {
      final excel = Excel.createExcel();
      final sheetName = excel.getDefaultSheet() ?? 'Tasks';
      final sheet = excel[sheetName];

      // Headings row — important fields only.
      const headers = [
        'S.No',
        'Task ID',
        'Task Title',
        'Description',
        'Customer Name',
        'Customer Number',
        'Customer Address',
        'City',
        'Pincode',
        'Expected Completion Date',
        'Assigned Date',
        'Completed Date',
        'Status',
        'Destination Address',
      ];
      sheet.appendRow(headers.map((h) => TextCellValue(h)).toList());

      int sno = 1;
      for (final t in toExport) {
        final c = t.customer;
        final row = <CellValue?>[
          TextCellValue('$sno'),
          TextCellValue(t.taskId),
          TextCellValue(_cellStr(t.taskTitle)),
          TextCellValue(_cellStr(t.description)),
          TextCellValue(_cellStr(c?.customerName)),
          TextCellValue(_cellStr(c?.customerNumber)),
          TextCellValue(_cellStr(c?.address)),
          TextCellValue(_cellStr(c?.city)),
          TextCellValue(_cellStr(c?.pincode)),
          TextCellValue(_cellStr(t.expectedCompletionDate)),
          TextCellValue(_cellStr(t.assignedDate)),
          TextCellValue(_cellStr(t.completedDate)),
          TextCellValue(_statusLabel(t.status)),
          TextCellValue(_cellStr(t.destinationLocation?.displayAddress)),
        ];
        sheet.appendRow(row);
        sno++;
      }

      final bytes = excel.encode();
      if (bytes == null || bytes.isEmpty) {
        throw Exception('Excel encode returned empty');
      }
      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/tasks_export_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.xlsx',
      );
      await file.writeAsBytes(bytes);
      await OpenFilex.open(file.path);
      if (mounted) {
        setState(() {
          _isSelectionMode = false;
          _selectedTaskIds.clear();
          _exporting = false;
        });
        SnackBarUtils.showSnackBar(
          context,
          'Exported ${toExport.length} task(s) to Excel',
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _exporting = false);
        SnackBarUtils.showSnackBar(
          context,
          ErrorMessageUtils.toUserFriendlyMessage(e),
          isError: true,
        );
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed && mounted) {
      _refreshWhenReturning();
    }
  }

  void _refreshWhenReturning() {
    if (_loggedInStaffId != null || _tasks.isNotEmpty) {
      _fetchTasks();
    }
    if (!_isInternalStaff) {
      _fetchCustomers();
      _fetchJourneyStatus();
    }
    _fetchAllowances();
    _fetchHistory();
  }

  Future<void> _fetchCustomers() async {
    // Spinner only when there is nothing to show yet; refreshes keep the list.
    if (_customers.isEmpty) setState(() => _isLoadingCustomers = true);
    try {
      final customers = await CustomerService().getAllCustomers();
      if (mounted) {
        setState(() {
          _customers = customers;
          _customersPage = 1;
          _isLoadingCustomers = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingCustomers = false;
        });
      }
    }
  }

  Future<void> _fetchJourneyStatus() async {
    try {
      final journey = await TaskService().getJourneyStatus();
      if (mounted) {
        final openJourney = (journey != null && journey['open'] != null)
            ? Map<String, dynamic>.from(journey['open'] as Map)
            : null;
        setState(() {
          _activeJourney = openJourney;
          _journeyRequirements = TaskRequirement.listFrom(journey?['requirements']);
        });
      }
    } catch (_) {}
  }

  Future<Position> _getQuickAccurateLocation() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception('Location services are disabled. Please enable GPS.');
    }
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw Exception('Location permission denied.');
      }
    }
    if (permission == LocationPermission.deniedForever) {
      throw Exception('Location permissions are permanently denied. Please enable in Settings.');
    }

    // 1. Instant return if last known position is available
    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) return last;
    } catch (_) {}

    // 2. Fetch fresh position with strict Dart future timeout
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
      ).timeout(const Duration(seconds: 4));
    } catch (_) {
      try {
        return await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.low),
        ).timeout(const Duration(seconds: 3));
      } catch (_) {
        final last = await Geolocator.getLastKnownPosition();
        if (last != null) return last;
        throw Exception('Unable to acquire GPS location. Please check location settings.');
      }
    }
  }

  /// Precise position for journey Field In / Field Out. The backend pins the journey's
  /// start and end to these coordinates, so a stale last-known fix is not good enough.
  Future<Position> _getFreshLocation() async {
    await _getQuickAccurateLocation(); // permission / service checks
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      ).timeout(const Duration(seconds: 12));
    } catch (_) {
      return _getQuickAccurateLocation();
    }
  }

  Future<void> _handleJourneyFieldIn() async {
    // Field work happens inside the working day: require an open punch.
    final punch = await TaskService().getTodayPunchState();
    if (!mounted) return;
    if (punch != null && (!punch.punchedIn || punch.punchedOut)) {
      SnackBarUtils.showSnackBar(
        context,
        punch.punchedOut
            ? 'You have already punched out today. Field In is available only while punched in.'
            : 'Please punch in first to start a Field In.',
        isError: true,
      );
      return;
    }
    setState(() => _isJourneyActionLoading = true);

    BuildContext? loadingDialogContext;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        loadingDialogContext = ctx;
        return PopScope(
          canPop: false,
          child: Dialog(
            backgroundColor: Colors.white,
            elevation: 8,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(strokeWidth: 3),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Starting Field Journey...',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey.shade900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Validating location & starting live tracking...',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    try {
      final pos = await _getFreshLocation();
      final res = await TaskService().journeyFieldIn(
        latitude: pos.latitude,
        longitude: pos.longitude,
      );

      final journeyData = res['data'] is Map ? Map<String, dynamic>.from(res['data'] as Map) : null;
      // Live location for the whole journey (Field In -> Field Out), same pipeline as tasks.
      final journeyMongoId = (journeyData?['_id'] ?? '').toString();
      if (journeyMongoId.isNotEmpty) {
        try {
          await LiveTrackingService().startTracking(
            taskMongoId: journeyMongoId,
            taskId: (journeyData?['id'] ?? journeyMongoId).toString(),
            pickupLat: pos.latitude,
            pickupLng: pos.longitude,
            dropoffLat: pos.latitude,
            dropoffLng: pos.longitude,
            selfLogged: true,
          );
          unawaited(
            TaskService()
                .storeTracking(journeyMongoId, pos.latitude, pos.longitude, movementType: 'stop')
                .then((_) {}, onError: (_) {}),
          );
          PresenceTrackingService().pausePresenceTracking();
          // Starts the foreground position stream and the background tracker, which posts
          // points for the active journey (see LiveTrackingService.sendTrackingFromBackground).
          if (mounted) {
            unawaited(
              LocationService()
                  .initLocationService(
                    customerLocation: LatLng(pos.latitude, pos.longitude),
                    context: context,
                  )
                  .catchError((_) {}),
            );
          }
        } catch (_) {}
      }
      if (mounted) {
        setState(() {
          _activeJourney = journeyData;
        });
        _fetchTasks();
      }

      if (loadingDialogContext != null && loadingDialogContext!.mounted) {
        Navigator.of(loadingDialogContext!).pop();
        loadingDialogContext = null;
      }

      if (mounted) {
        SnackBarUtils.showSnackBar(context, 'Field In recorded successfully.');
        _fetchTasks();
        _fetchAllowances();
        _fetchHistory();
      }
    } catch (e) {
      if (loadingDialogContext != null && loadingDialogContext!.mounted) {
        Navigator.of(loadingDialogContext!).pop();
        loadingDialogContext = null;
      }
      if (mounted) {
        final cleanMsg = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '').trim();
        final displayMsg = (cleanMsg.isNotEmpty &&
                !cleanMsg.toLowerCase().contains('dioexception') &&
                !cleanMsg.toLowerCase().contains('socketexception'))
            ? cleanMsg
            : ErrorMessageUtils.toUserFriendlyMessage(e);
        SnackBarUtils.showSnackBar(context, displayMsg, isError: true);
      }
    } finally {
      if (loadingDialogContext != null && loadingDialogContext!.mounted) {
        Navigator.of(loadingDialogContext!).pop();
      }
      if (mounted) setState(() => _isJourneyActionLoading = false);
    }
  }

  Future<void> _handleJourneyFieldOut() async {
    // The admin's external Field-Out form (GET /journey `requirements`), same fields and
    // rules as a task's Field Out. Images are uploaded; Email fields are OTP-verified.
    if (_journeyRequirements.isEmpty) await _fetchJourneyStatus();
    if (!mounted) return;
    final answers = await FieldOutFormScreen.open(
      context,
      requirements: _journeyRequirements,
      title: 'Field Out',
      subtitle:
          'Recording Field Out at your current location closes this journey and calculates your travel allowance.',
    );
    if (answers == null || !mounted) return;
    String? answerFor(bool Function(TaskRequirement) test) {
      final reqs = _journeyRequirements.isNotEmpty ? _journeyRequirements : TaskRequirement.webDefaults;
      for (final r in reqs) {
        if (test(r) && answers[r.name] != null) return answers[r.name];
      }
      return null;
    }

    setState(() => _isJourneyActionLoading = true);

    BuildContext? loadingDialogContext;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        loadingDialogContext = ctx;
        return PopScope(
          canPop: false,
          child: Dialog(
            backgroundColor: Colors.white,
            elevation: 8,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(strokeWidth: 3),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Recording Field Out...',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey.shade900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Validating location & updating allowance...',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    try {
      final pos = await _getFreshLocation();
      final desc = answerFor((r) => r.isTextArea) ?? 'Completed field journey';
      await TaskService().journeyFieldOut(
        latitude: pos.latitude,
        longitude: pos.longitude,
        fieldOutNotes: desc,
        fieldOutImage: answerFor((r) => r.isImage),
        fieldOutOtp: answerFor((r) => r.isOtp),
        answers: answers,
      );
      // Journey closed: stop its live tracking and hand back to presence tracking.
      try {
        await LiveTrackingService().stopTracking();
        await BackgroundLocationTrackerManager.stopTracking();
        await PresenceTrackingService().resumePresenceTracking();
      } catch (_) {}
      if (loadingDialogContext != null && loadingDialogContext!.mounted) {
        Navigator.of(loadingDialogContext!).pop();
        loadingDialogContext = null;
      }
      if (mounted) {
        setState(() => _activeJourney = null);
        SnackBarUtils.showSnackBar(context, 'Field Out recorded! Journey completed.');
        _fetchTasks();
        _fetchAllowances();
        _fetchHistory();
      }
    } catch (e) {
      if (loadingDialogContext != null && loadingDialogContext!.mounted) {
        Navigator.of(loadingDialogContext!).pop();
        loadingDialogContext = null;
      }
      if (mounted) {
        final cleanMsg = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '').trim();
        final displayMsg = (cleanMsg.isNotEmpty &&
                !cleanMsg.toLowerCase().contains('dioexception') &&
                !cleanMsg.toLowerCase().contains('socketexception'))
            ? cleanMsg
            : ErrorMessageUtils.toUserFriendlyMessage(e);
        SnackBarUtils.showSnackBar(context, displayMsg, isError: true);
        _fetchJourneyStatus();
      }
    } finally {
      if (loadingDialogContext != null && loadingDialogContext!.mounted) {
        Navigator.of(loadingDialogContext!).pop();
      }
      if (mounted) setState(() => _isJourneyActionLoading = false);
    }
  }

  Future<void> _fetchAllowances() async {
    if (_allowances.isEmpty) setState(() => _isLoadingAllowances = true);
    try {
      final list = await TaskService().getStaffAllowances();
      if (mounted) {
        setState(() {
          _allowances = list;
          _isLoadingAllowances = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingAllowances = false);
    }
  }

  Future<void> _fetchHistory() async {
    if (_historyTasks.isEmpty) setState(() => _isLoadingHistory = true);
    try {
      final list = await TaskService().getStaffTaskHistory();
      if (mounted) {
        setState(() {
          _historyTasks = _isInternalStaff
              ? list.where((t) => (t.type ?? '').toLowerCase() == 'internal').toList()
              : list.where((t) => (t.type ?? 'external').toLowerCase() == 'external').toList();
          _isLoadingHistory = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingHistory = false);
    }
  }

  Future<void> _loadLoggedInStaffId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userString = prefs.getString('user');
      if (userString == null || userString.isEmpty) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorMessage = 'User not logged in.';
          });
        }
        return;
      }
      Map<String, dynamic>? userData;
      try {
        userData = jsonDecode(userString) as Map<String, dynamic>?;
      } catch (_) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorMessage = 'Invalid user data.';
          });
        }
        return;
      }
      if (userData == null) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorMessage = 'User not logged in.';
          });
        }
        return;
      }
      // API returns id and staffId (staffId = assigned-to-me for tasks)
      final staffId = userData['staffId'] ?? userData['_id'] ?? userData['id'];
      if (staffId != null) {
        if (mounted) {
          setState(() {
            _loggedInStaffId = staffId is String ? staffId : staffId.toString();
          });
        }
      }

      String? fieldType = (userData['fieldType'] ?? userData['staff']?['fieldType'])?.toString();
      if (fieldType == null || fieldType.isEmpty) {
        fieldType = await TaskService().getStaffFieldType();
        if (fieldType != null && fieldType.isNotEmpty) {
          userData['fieldType'] = fieldType;
          await prefs.setString('user', jsonEncode(userData));
        }
      }
      final isInternal = (fieldType ?? '').toLowerCase().contains('internal');
      final newLength = isInternal ? 3 : 4;
      if (_mainTabController.length != newLength) {
        _mainTabController.dispose();
        _mainTabController = TabController(
          length: newLength,
          vsync: this,
          initialIndex: widget.openHistory ? newLength - 1 : 0,
        );
        _mainTabController.addListener(() {
          if (!_mainTabController.indexIsChanging && mounted) setState(() {});
        });
      }
      if (mounted) {
        setState(() {
          _isInternalStaff = isInternal;
          // Internal or External Field Employee (Employee Access) — My Route is for them only.
          _isFieldEmployee = (fieldType ?? '').toLowerCase().contains('field');
        });
      }

      // Independent loads: run together instead of one round trip after another.
      await Future.wait<void>([
        _fetchTasks(),
        if (!_isInternalStaff) _fetchCustomers(),
        if (!_isInternalStaff) _fetchJourneyStatus(),
        _fetchAllowances(),
        _fetchHistory(),
      ]);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to load: ${e.toString()}';
        });
      }
    }
  }

  /// Loads the full assigned-task list in one shot. Search, date and status
  /// filtering plus pagination are all applied client-side (see [_matchedTasks]
  /// / [_filteredTasks]) so they stay consistent regardless of what the backend
  /// filters server-side.
  Future<void> _fetchTasks() async {
    if (!mounted) return;
    try {
      final List<Task> tasks =
          (_loggedInStaffId != null && _loggedInStaffId!.isNotEmpty)
          ? await TaskService().getAssignedTasks(_loggedInStaffId!)
          : await TaskService().getAllTasks();
      if (!mounted) return;
      setState(() {
        _tasks = tasks;
        _isLoading = false;
        _errorMessage = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load tasks';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _confirmContinueIncompleteTask(VoidCallback onYes) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Continue task?'),
        content: const Text('Are you sure you want to continue this task?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('No'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Yes'),
          ),
        ],
      ),
    );
    if (!mounted || yes != true) return;
    onYes();
  }

  /// Sets a single quick-filter group exclusively (or clears all when null),
  /// reusing the existing status-group filter + fetch logic.
  void _applyQuickFilter(String? group) {
    setState(() {
      _statusFilter = group;
      _tasksPage = 1;
    });
  }

  /// Figma task-list header: Pending/Completed stat cards, New Task button,
  /// and horizontal status filter chips.
  Widget _buildTaskListHeader() {
    final completed = _statusGroupCount('completed');
    // Pending = every loaded task that isn't completed/waiting-for-approval.
    // This covers pending, assigned, scheduled, in-progress, arrived and hold
    // states, so any task whose badge isn't "Completed" is counted here.
    final pending = _tasks.length - completed;

    return Padding(
      padding: const EdgeInsets.fromLTRB(_kHeaderHPad, _kHeaderGap, _kHeaderHPad, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  label: 'PENDING',
                  value: '$pending',
                  caption: 'Tasks',
                  icon: Icons.assignment_outlined,
                  filled: false,
                ),
              ),
              const SizedBox(width: _kHeaderGap),
              Expanded(
                child: _buildStatCard(
                  label: 'COMPLETED',
                  value: '$completed',
                  caption: 'Tasks',
                  icon: Icons.check_circle_outline_rounded,
                  filled: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: _kHeaderGap),
          // Status filter, full width. (The "New Task" button was removed;
          // tasks are still added from the app bar ➕ and the Add Task button.)
          _buildStatusFilterDropdown(),
        ],
      ),
    );
  }

  /// Status filter as a dropdown (replaces the horizontal chip row).
  Widget _buildStatusFilterDropdown() {
    final isActive = _statusFilter != null;
    return Container(
      height: _kHeaderControlHeight,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(_kHeaderRadius),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: isActive ? 0.5 : 0.25),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.filter_list_rounded, size: 18, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                isExpanded: true,
                value: _statusFilter,
                borderRadius: BorderRadius.circular(12),
                icon: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: AppColors.primary,
                ),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
                items: _statusFilterOptions
                    .map(
                      (o) => DropdownMenuItem<String?>(
                        value: o.group,
                        child: Text(o.label),
                      ),
                    )
                    .toList(),
                onChanged: (val) => _applyQuickFilter(val),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required String label,
    required String value,
    required String caption,
    required IconData icon,
    required bool filled,
  }) {
    final bg = filled ? AppColors.primary : Colors.white;
    final labelColor = filled
        ? Colors.white.withValues(alpha: 0.9)
        : AppColors.textSecondary;
    final valueColor = filled ? Colors.white : AppColors.textPrimary;
    final iconBg = filled
        ? Colors.white.withValues(alpha: 0.2)
        : AppColors.primary.withValues(alpha: 0.12);
    final iconColor = filled ? Colors.white : AppColors.primary;

    // Compact: icon tile on the left, label + count beside it (no empty space).
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(_kHeaderRadius),
        border: filled ? null : Border.all(color: const Color(0xFFF1F5F9)),
        boxShadow: [
          BoxShadow(
            color: filled
                ? AppColors.primary.withValues(alpha: 0.25)
                : Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 21, color: iconColor),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: labelColor,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      value,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: valueColor,
                        height: 1,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        caption,
                        style: TextStyle(fontSize: 12, color: labelColor),
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

  Widget _buildTaskPaginationBar(ColorScheme colorScheme) {
    if (_filteredTasks.isEmpty) return const SizedBox.shrink();
    return _buildPagerPill(
      current: _currentTaskPage,
      total: _totalTaskPages,
      onPrev: () => setState(() => _tasksPage = _currentTaskPage - 1),
      onNext: () => setState(() => _tasksPage = _currentTaskPage + 1),
      onPage: (p) => setState(() => _tasksPage = p),
    );
  }

  /// Centred numbered pager ("‹ 1 2 3 4 5 ›", current page filled) shared by
  /// the Tasks and Customers tabs. Shows a window of up to 5 page numbers
  /// around the current page; always visible so the page count is clear.
  Widget _buildPagerPill({
    required int current,
    required int total,
    required VoidCallback onPrev,
    required VoidCallback onNext,
    ValueChanged<int>? onPage,
  }) {
    final pages = total < 1 ? 1 : total;
    final cur = current.clamp(1, pages);
    const window = 5;
    var first = (cur - window ~/ 2).clamp(1, pages);
    final last = (first + window - 1).clamp(1, pages);
    first = (last - window + 1).clamp(1, pages);

    Widget arrow(IconData icon, bool enabled, VoidCallback onTap, String tip) => IconButton(
          onPressed: enabled ? onTap : null,
          tooltip: tip,
          visualDensity: VisualDensity.compact,
          iconSize: 22,
          color: AppColors.primary,
          disabledColor: const Color(0xFFCBD5E1),
          icon: Icon(icon),
        );

    Widget number(int p) {
      final selected = p == cur;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: selected || onPage == null ? null : () => onPage(p),
          child: Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? AppColors.primary : Colors.transparent,
              shape: BoxShape.circle,
            ),
            child: Text(
              '$p',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: selected ? Colors.white : const Color(0xFF334155),
              ),
            ),
          ),
        ),
      );
    }

    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: const [BoxShadow(color: Color(0x0F000000), blurRadius: 6, offset: Offset(0, 2))],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            arrow(Icons.chevron_left_rounded, cur > 1, onPrev, 'Previous page'),
            for (var p = first; p <= last; p++) number(p),
            arrow(Icons.chevron_right_rounded, cur < pages, onNext, 'Next page'),
          ],
        ),
      ),
    );
  }

  /// Pagination bar for the active tab, rendered as a fixed footer above the
  /// bottom navigation. Returns an empty box while loading, in selection mode,
  /// or when the active tab has no rows to page through.
  Widget _buildBottomPaginationBar(ColorScheme colorScheme) {
    final Widget bar;
    if (_mainTabController.index == 0) {
      if (_isLoading || _isSelectionMode || _filteredTasks.isEmpty) {
        return const SizedBox.shrink();
      }
      bar = _buildTaskPaginationBar(colorScheme);
    } else if (!_isInternalStaff && _mainTabController.index == 1) {
      if (_isLoadingCustomers || _customers.isEmpty) {
        return const SizedBox.shrink();
      }
      bar = _buildCustomerPaginationBar(colorScheme);
    } else {
      return const SizedBox.shrink();
    }
    // Transparent footer: just the pager pill on the page background.
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      child: bar,
    );
  }

  /// Opens a bottom sheet showing the full details of a customer when their
  /// card is tapped.
  Future<void> _showCustomerDetails(Customer customer) async {
    final colorScheme = Theme.of(context).colorScheme;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              12,
              20,
              20 + MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Row(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: colorScheme.primary.withOpacity(0.1),
                      child: Icon(
                        Icons.person,
                        color: colorScheme.primary,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            customer.customerName,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (customer.companyName != null &&
                              customer.companyName!.trim().isNotEmpty)
                            Text(
                              customer.companyName!.trim(),
                              style: TextStyle(
                                fontSize: 13,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _buildCustomerDetailRow(
                  Icons.phone_outlined,
                  'Phone',
                  _formatPhone(customer),
                ),
                _buildCustomerDetailRow(
                  Icons.email_outlined,
                  'Email',
                  customer.effectiveEmail,
                ),
                _buildCustomerDetailRow(
                  Icons.location_on_outlined,
                  'Address',
                  customer.address,
                ),
                _buildCustomerDetailRow(
                  Icons.location_city_outlined,
                  'City',
                  customer.city,
                ),
                _buildCustomerDetailRow(
                  Icons.pin_drop_outlined,
                  'Pincode',
                  customer.pincode,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Phone number prefixed with the customer's country dial code (e.g.
  /// "+91 5856932568"). Returns an empty string when no number is set.
  String _formatPhone(Customer customer) {
    final number = customer.customerNumber?.trim() ?? '';
    if (number.isEmpty) return '';
    final code = customer.countryCode?.trim() ?? '';
    if (code.isEmpty) return number;
    final dial = code.startsWith('+') ? code : '+$code';
    return '$dial $number';
  }

  /// A single labelled row inside the customer details sheet; hidden when the
  /// value is empty.
  Widget _buildCustomerDetailRow(IconData icon, String label, String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return const SizedBox.shrink();
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  text,
                  style: const TextStyle(
                    fontSize: 14,
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

  /// Page-number + arrow bar for the (client-side paginated) customer list.
  Widget _buildCustomerPaginationBar(ColorScheme colorScheme) {
    if (_customers.isEmpty) return const SizedBox.shrink();
    return _buildPagerPill(
      current: _currentCustomerPage,
      total: _customersTotalPages,
      onPrev: () => setState(() => _customersPage = _currentCustomerPage - 1),
      onNext: () => setState(() => _customersPage = _currentCustomerPage + 1),
      onPage: (p) => setState(() => _customersPage = p),
    );
  }

  Color _getStatusChipColor(TaskStatus status) {
    switch (status) {
      case TaskStatus.pending:
        return AppColors.brand;
      case TaskStatus.inProgress:
        return Colors.blue.shade600;
      case TaskStatus.arrived:
        return Colors.indigo.shade600;
      case TaskStatus.exited:
        return AppColors.brandDark;
      case TaskStatus.exitedOnArrival:
        return AppColors.brandDark;
      case TaskStatus.hold:
      case TaskStatus.holdOnArrival:
        return AppColors.brandDark;
      case TaskStatus.reopenedOnArrival:
        return Colors.teal.shade600;
      case TaskStatus.completed:
        return Colors.green.shade600;
      case TaskStatus.waitingForApproval:
        return AppColors.brand;
      case TaskStatus.assigned:
        return Colors.green.shade600;
      case TaskStatus.scheduled:
        return Colors.blue.shade600;
      case TaskStatus.approved:
      case TaskStatus.staffapproved:
        return Colors.teal.shade600;
      case TaskStatus.rejected:
        return Colors.red.shade600;
      case TaskStatus.reopened:
        return Colors.teal.shade600;
      case TaskStatus.requested:
        return Colors.purple.shade600;
      case TaskStatus.expired:
        return Colors.red.shade700;
      case TaskStatus.cancelled:
        return Colors.grey.shade600;
      case TaskStatus.onlineReady:
        return Colors.grey.shade600;
      default:
        return Colors.grey.shade600;
    }
  }

  String _statusLabel(TaskStatus status) {
    switch (status) {
      case TaskStatus.assigned:
        return 'Assigned';
      case TaskStatus.pending:
        return 'Pending';
      case TaskStatus.scheduled:
        return 'Scheduled';
      case TaskStatus.approved:
      case TaskStatus.staffapproved:
        return 'Approved';
      case TaskStatus.inProgress:
        return 'In Progress';
      case TaskStatus.arrived:
        return 'Arrived';
      case TaskStatus.exited:
        return 'Exited';
      case TaskStatus.exitedOnArrival:
        return 'Exited on Arrival';
      case TaskStatus.hold:
        return 'Hold';
      case TaskStatus.holdOnArrival:
        return 'Hold on Arrival';
      case TaskStatus.reopenedOnArrival:
        return 'Reopened on Arrival';
      case TaskStatus.waitingForApproval:
        return 'Waiting for Approval';
      case TaskStatus.completed:
        return 'Completed';
      case TaskStatus.rejected:
        return 'Rejected';
      case TaskStatus.cancelled:
        return 'Cancelled';
      case TaskStatus.reopened:
        return 'Reopened';
      case TaskStatus.requested:
        return 'Requested';
      case TaskStatus.expired:
        return 'Expired';
      case TaskStatus.onlineReady:
        return 'Ready';
      default:
        return '';
    }
  }

  Widget _buildRequirementChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color, width: 0.5),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w500,
        ),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _buildTaskCardDetailRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            '$label: ',
            style: TextStyle(
              fontSize: 11,
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_isSelectionMode) {
          setState(() {
            _isSelectionMode = false;
            _selectedTaskIds.clear();
          });
          return;
        }
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        } else {
          DashboardScreen.goToTab(context, 0);
        }
      },
      child: Builder(
        builder: (context) {
          final colorScheme = Theme.of(context).colorScheme;
          // Status-filtered view of the loaded page (see _filteredTasks).
          final visibleTasks = _filteredTasks;
          return Scaffold(
            drawer: const AppDrawer(),
            backgroundColor: colorScheme.surfaceContainerHighest,
            appBar: AppBar(
              leading: _isSelectionMode
                  ? IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() {
                        _isSelectionMode = false;
                        _selectedTaskIds.clear();
                      }),
                    )
                  : Builder(
                      builder: (ctx) => IconButton(
                        icon: const Icon(Icons.menu_rounded),
                        onPressed: () => Scaffold.of(ctx).openDrawer(),
                      ),
                    ),
              title: Text(
                _isSelectionMode
                    ? 'Select tasks to export (${_selectedTaskIds.length})'
                    : 'Tasks',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              centerTitle: true,
              elevation: 0,
              bottom: _isSelectionMode
                  ? null
                  : TabBar(
                      controller: _mainTabController,
                      labelColor: colorScheme.primary,
                      unselectedLabelColor: colorScheme.onSurfaceVariant,
                      indicatorColor: colorScheme.primary,
                      labelPadding: const EdgeInsets.symmetric(horizontal: 8),
                      tabs: _isInternalStaff
                          ? const [
                              Tab(text: 'Tasks'),
                              Tab(text: 'Allowance'),
                              Tab(text: 'History'),
                            ]
                          : const [
                              Tab(text: 'Tasks'),
                              Tab(text: 'Customers'),
                              Tab(text: 'Allowance'),
                              Tab(text: 'History'),
                            ],
                    ),
              actions: [
                // The day's route: punch-in → Field In/Out flags and leg distances.
                // Field employees only (the backend refuses anyone else).
                if (!_isSelectionMode && _isFieldEmployee)
                  IconButton(
                    icon: Icon(Icons.route_rounded, color: AppColors.primary, size: 24),
                    tooltip: 'My Route',
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const MyDayRouteScreen()),
                    ),
                  ),
                if (!_isSelectionMode && !_isInternalStaff && (_mainTabController.index == 0 || _mainTabController.index == 1))
                  IconButton(
                    icon: Icon(Icons.add_circle_outline_rounded, color: AppColors.primary, size: 26),
                    tooltip: _mainTabController.index == 0 ? 'Add Task' : 'Add Customer',
                    onPressed: () {
                      if (_mainTabController.index == 0) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                AddTaskScreen(staffId: _loggedInStaffId ?? ''),
                          ),
                        ).then((_) => _fetchTasks());
                      } else {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const AddCustomerScreen(),
                          ),
                        ).then((_) => _fetchCustomers());
                      }
                    },
                  ),
                if (!_isSelectionMode && _mainTabController.index == 0)
                  IconButton(
                    icon: Icon(
                      _hasAnyFilters
                          ? Icons.filter_alt
                          : Icons.filter_alt_outlined,
                      color: _hasAnyFilters ? colorScheme.primary : null,
                    ),
                    tooltip: 'Filter tasks',
                    onPressed: _openTaskFilterBottomSheet,
                  ),
                if (!_isSelectionMode && ((_isInternalStaff && _mainTabController.index > 0) || (!_isInternalStaff && _mainTabController.index >= 2)))
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded),
                    tooltip: 'Refresh',
                    onPressed: () {
                      final isAllowance = (_isInternalStaff && _mainTabController.index == 1) || (!_isInternalStaff && _mainTabController.index == 2);
                      if (isAllowance) {
                        _fetchAllowances();
                      } else {
                        _fetchHistory();
                      }
                    },
                  ),
              ],
            ),
            body: TabBarView(
              controller: _mainTabController,
              children: [
                // Tasks Tab
                _isLoading
                    ? const Center(child: AppTabLoader())
                    : RefreshIndicator(
                        onRefresh: _fetchTasks,
                        // Whole tab scrolls as one: the search row and stats
                        // header are slivers that scroll away with the task
                        // list instead of staying pinned above it.
                        child: CustomScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          slivers: [
                            if (!_isSelectionMode)
                              SliverToBoxAdapter(
                                child: _buildSearchAndRefreshRow(),
                              ),
                            if (!_isSelectionMode)
                              SliverToBoxAdapter(child: _buildTaskListHeader()),
                            if (!_isSelectionMode && !_isInternalStaff)
                              SliverToBoxAdapter(child: _buildFieldJourneyBanner(colorScheme)),
                            if (_errorMessage != null)
                              SliverFillRemaining(
                                hasScrollBody: false,
                                child: Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.info_outline_rounded,
                                        size: 64,
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        _errorMessage!,
                                        style: TextStyle(
                                          fontSize: 15,
                                          color: colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      ElevatedButton.icon(
                                        onPressed: _fetchTasks,
                                        icon: const Icon(Icons.refresh),
                                        label: const Text('Retry'),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            else if (visibleTasks.isEmpty)
                              SliverFillRemaining(
                                hasScrollBody: false,
                                child: Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.assignment_turned_in_rounded,
                                        size: 80,
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        _hasAnyFilters
                                            ? 'No tasks match filters'
                                            : 'No tasks assigned yet',
                                        style: TextStyle(
                                          fontSize: 16,
                                          color: colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            else
                              SliverPadding(
                                // Bottom room so the last card scrolls clear of
                                // the floating Add Task button.
                                padding: const EdgeInsets.fromLTRB(
                                  _kHeaderHPad,
                                  _kHeaderGap,
                                  _kHeaderHPad,
                                  96,
                                ),
                                // +1 for the pagination footer that scrolls
                                // with the list instead of being pinned above
                                // the nav.
                                sliver: SliverList(
                                  delegate: SliverChildBuilderDelegate((
                                    context,
                                    index,
                                  ) {
                                    final task = visibleTasks[index];
                                    final taskKey = task.id ?? task.taskId;
                                    final isCompleted =
                                        task.status == TaskStatus.completed;
                                    final statusColor = _getStatusChipColor(
                                      task.status,
                                    );
                                    final isSelected = _selectedTaskIds
                                        .contains(taskKey);

                                    return InkWell(
                                      onTap: _isSelectionMode
                                          ? () => setState(() {
                                              if (_selectedTaskIds.contains(
                                                taskKey,
                                              )) {
                                                _selectedTaskIds.remove(
                                                  taskKey,
                                                );
                                              } else {
                                                _selectedTaskIds.add(taskKey);
                                              }
                                            })
                                          : () {
                                              // An open self-logged journey has no task flow
                                              // (Field In is already done): offer its Field Out.
                                              if (task.selfLogged && !isCompleted) {
                                                if (!_isJourneyActionLoading) {
                                                  _handleJourneyFieldOut();
                                                }
                                                return;
                                              }
                                              if (isCompleted) {
                                                Navigator.push(
                                                  context,
                                                  MaterialPageRoute(
                                                    builder: (context) =>
                                                        CompletedTaskDetailScreen(
                                                          task: task,
                                                        ),
                                                  ),
                                                );
                                              } else if (task.status ==
                                                      TaskStatus.arrived ||
                                                  task.status ==
                                                      TaskStatus
                                                          .holdOnArrival ||
                                                  task.status ==
                                                      TaskStatus
                                                          .reopenedOnArrival) {
                                                void goArrived() {
                                                  Navigator.push(
                                                    context,
                                                    MaterialPageRoute(
                                                      builder: (context) => ArrivedScreen(
                                                        taskMongoId: task.id,
                                                        taskId: task.taskId,
                                                        task: task,
                                                        totalDuration: Duration(
                                                          seconds:
                                                              task.tripDurationSeconds ??
                                                              0,
                                                        ),
                                                        totalDistanceKm:
                                                            task.tripDistanceKm ??
                                                            0.0,
                                                        isWithinGeofence: false,
                                                        arrivalTime:
                                                            task.arrivalTime ??
                                                            DateTime.now(),
                                                        sourceLat: task
                                                            .sourceLocation
                                                            ?.lat,
                                                        sourceLng: task
                                                            .sourceLocation
                                                            ?.lng,
                                                        sourceAddress: task
                                                            .sourceLocation
                                                            ?.address,
                                                        destLat: task
                                                            .destinationLocation
                                                            ?.lat,
                                                        destLng: task
                                                            .destinationLocation
                                                            ?.lng,
                                                        destAddress: task
                                                            .destinationLocation
                                                            ?.address,
                                                        arrivalAtLat: task
                                                            .arrivalLocation
                                                            ?.lat,
                                                        arrivalAtLng: task
                                                            .arrivalLocation
                                                            ?.lng,
                                                        arrivalAtAddress: task
                                                            .arrivalLocation
                                                            ?.displayAddress,
                                                      ),
                                                    ),
                                                  );
                                                }

                                                if (task.status ==
                                                    TaskStatus.holdOnArrival) {
                                                  _confirmContinueIncompleteTask(
                                                    goArrived,
                                                  );
                                                } else {
                                                  goArrived();
                                                }
                                              } else {
                                                void goTaskDetail() {
                                                  Navigator.push(
                                                    context,
                                                    MaterialPageRoute(
                                                      builder: (context) =>
                                                          TaskDetailScreen(
                                                            task: task,
                                                          ),
                                                    ),
                                                  );
                                                }

                                                if (task.status ==
                                                    TaskStatus.hold) {
                                                  _confirmContinueIncompleteTask(
                                                    goTaskDetail,
                                                  );
                                                } else {
                                                  goTaskDetail();
                                                }
                                              }
                                            },
                                      borderRadius: BorderRadius.circular(14),
                                      child: Container(
                                        margin: const EdgeInsets.only(
                                          bottom: 8,
                                        ),
                                        decoration: BoxDecoration(
                                          color: colorScheme.surface,
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                          border: Border.all(
                                            color: isSelected
                                                ? colorScheme.primary
                                                : colorScheme.outline,
                                            width: isSelected ? 2 : 1,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: colorScheme.shadow
                                                  .withOpacity(0.08),
                                              blurRadius: 6,
                                              offset: const Offset(0, 2),
                                            ),
                                          ],
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsets.all(12),
                                          child: Opacity(
                                            opacity: isCompleted ? 0.7 : 1.0,
                                            child: Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                        right: 10,
                                                        top: 2,
                                                      ),
                                                  child: Icon(
                                                    _isSelectionMode
                                                        ? (isSelected
                                                              ? Icons
                                                                    .check_circle
                                                              : Icons
                                                                    .radio_button_unchecked)
                                                        : Icons
                                                              .assignment_rounded,
                                                    color: _isSelectionMode
                                                        ? (isSelected
                                                              ? colorScheme
                                                                    .primary
                                                              : colorScheme
                                                                    .onSurfaceVariant)
                                                        : colorScheme.primary,
                                                    size: _isSelectionMode
                                                        ? 22
                                                        : 20,
                                                  ),
                                                ),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Row(
                                                        mainAxisAlignment:
                                                            MainAxisAlignment
                                                                .spaceBetween,
                                                        children: [
                                                          Expanded(
                                                            child: Text(
                                                              'Task #${task.taskId}',
                                                              style: TextStyle(
                                                                fontSize: 14,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                                color: colorScheme
                                                                    .onSurface,
                                                              ),
                                                              maxLines: 1,
                                                              overflow:
                                                                  TextOverflow
                                                                      .ellipsis,
                                                            ),
                                                          ),
                                                          Text(
                                                            // Created date (assignedDate
                                                            // falls back to createdAt in
                                                            // the model); with the time.
                                                            DateDisplayUtil.formatShortDateTime(
                                                              _taskCardDateTime(task),
                                                            ),
                                                            style: TextStyle(
                                                              fontSize: 10,
                                                              color: Colors
                                                                  .grey
                                                                  .shade700,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w500,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                      const SizedBox(height: 4),
                                                      Text(
                                                        task.taskTitle,
                                                        style: const TextStyle(
                                                          fontSize: 15,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          color: Colors.black,
                                                        ),
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                      // Expected date dropped; show the
                                                      // Completed date only for completed
                                                      // tasks (created date sits top-right).
                                                      if (isCompleted &&
                                                          task.completedDate !=
                                                              null) ...[
                                                        const SizedBox(
                                                          height: 4,
                                                        ),
                                                        Row(
                                                          children: [
                                                            Icon(
                                                              Icons
                                                                  .calendar_today_outlined,
                                                              size: 12,
                                                              color: Colors
                                                                  .grey
                                                                  .shade600,
                                                            ),
                                                            const SizedBox(
                                                              width: 4,
                                                            ),
                                                            Flexible(
                                                              child: Text(
                                                                'Completed: ${DateDisplayUtil.formatShortDate(task.completedDate!)}',
                                                                style: TextStyle(
                                                                  fontSize: 11,
                                                                  color: Colors
                                                                      .grey
                                                                      .shade800,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w500,
                                                                ),
                                                                overflow:
                                                                    TextOverflow
                                                                        .ellipsis,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ],
                                                      if (task.customer !=
                                                          null) ...[
                                                        const SizedBox(
                                                          height: 4,
                                                        ),
                                                        _buildTaskCardDetailRow(
                                                          icon: Icons
                                                              .person_outline_rounded,
                                                          label: 'Customer',
                                                          value:
                                                              task.customer!.customerNumber !=
                                                                      null &&
                                                                  task
                                                                      .customer!
                                                                      .customerNumber!
                                                                      .isNotEmpty
                                                              ? '${task.customer!.customerName} · ${task.customer!.customerNumber}'
                                                              : task
                                                                    .customer!
                                                                    .customerName,
                                                        ),
                                                      ],
                                                      _buildTaskCardDetailRow(
                                                        icon: Icons
                                                            .location_on_outlined,
                                                        label: 'Destination',
                                                        value:
                                                            task
                                                                .destinationLocation
                                                                ?.displayAddress ??
                                                            '${task.customer?.address ?? ''}, ${task.customer?.city ?? ''}, ${task.customer?.pincode ?? ''}'
                                                                .trim(),
                                                      ),
                                                      const SizedBox(height: 8),
                                                      Row(
                                                        mainAxisAlignment:
                                                            MainAxisAlignment
                                                                .spaceBetween,
                                                        children: [
                                                          Expanded(
                                                            child: Wrap(
                                                              spacing: 6,
                                                              runSpacing: 4,
                                                              children: [
                                                                if (task
                                                                    .isOtpRequired)
                                                                  _buildRequirementChip(
                                                                    'OTP',
                                                                    Colors.blue,
                                                                  ),
                                                                if (task
                                                                    .isGeoFenceRequired)
                                                                  _buildRequirementChip(
                                                                    'Geo',
                                                                    Colors
                                                                        .purple,
                                                                  ),
                                                                if (task
                                                                    .isPhotoRequired)
                                                                  _buildRequirementChip(
                                                                    'Photo',
                                                                    Colors
                                                                        .orange,
                                                                  ),
                                                                if (task
                                                                    .isFormRequired)
                                                                  _buildRequirementChip(
                                                                    'Form',
                                                                    Colors.teal,
                                                                  ),
                                                              ],
                                                            ),
                                                          ),
                                                          Container(
                                                            padding:
                                                                const EdgeInsets.symmetric(
                                                                  horizontal: 8,
                                                                  vertical: 4,
                                                                ),
                                                            decoration: BoxDecoration(
                                                              color: statusColor
                                                                  .withOpacity(
                                                                    0.1,
                                                                  ),
                                                              borderRadius:
                                                                  BorderRadius.circular(
                                                                    12,
                                                                  ),
                                                            ),
                                                            child: Text(
                                                              _statusLabel(
                                                                task.status,
                                                              ),
                                                              style: TextStyle(
                                                                fontSize: 11,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                                color:
                                                                    statusColor,
                                                              ),
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
                                        ),
                                      ),
                                    );
                                  }, childCount: visibleTasks.length),
                                ),
                              ),
                          ],
                        ),
                      ),

                // Customers Tab (External Field Staff only)
                if (!_isInternalStaff)
                  _isLoadingCustomers
                      ? const Center(child: AppTabLoader())
                      : _customers.isEmpty
                      ? RefreshIndicator(
                          onRefresh: _fetchCustomers,
                          child: SingleChildScrollView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            child: SizedBox(
                              height: MediaQuery.of(context).size.height * 0.45,
                              child: Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.people_outline,
                                      size: 64,
                                      color: Colors.grey.shade400,
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      'No customers found',
                                      style: TextStyle(
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Pull to refresh or tap Add Customer',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _fetchCustomers,
                          child: ListView.builder(
                            // Room below the last card for the Add Customer button.
                            padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
                            itemCount: _pagedCustomers.length,
                            itemBuilder: (context, index) {
                              final customer = _pagedCustomers[index];
                              return Card(
                                elevation: 1,
                                margin: const EdgeInsets.only(bottom: 8),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: ListTile(
                                  onTap: () => _showCustomerDetails(customer),
                                  leading: CircleAvatar(
                                    backgroundColor: colorScheme.primary
                                        .withOpacity(0.1),
                                    child: Icon(
                                      Icons.person,
                                      color: colorScheme.primary,
                                    ),
                                  ),
                                  title: Text(
                                    customer.customerName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  subtitle: (customer.companyName != null &&
                                          customer.companyName!.trim().isNotEmpty)
                                      ? Text(
                                          customer.companyName!.trim(),
                                          style: const TextStyle(fontSize: 12),
                                        )
                                      : null,
                                  trailing: const Icon(
                                    Icons.chevron_right_rounded,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),

                // Allowance Tab
                _buildAllowanceTabView(colorScheme),

                // History Tab
                _buildHistoryTabView(colorScheme),
              ],
            ),
            bottomNavigationBar: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Pagination bar for the active tab, pinned as a fixed footer
                // just above the bottom navigation instead of scrolling away
                // with the list.
                _buildBottomPaginationBar(colorScheme),
                AppBottomNavigationBar(
                  currentIndex: -1,
                  onTap: (index) {
                    DashboardScreen.goToTab(context, index.clamp(0, 4));
                  },
                ),
              ],
            ),
            floatingActionButton: (_isSelectionMode || _isInternalStaff || _mainTabController.index >= 2)
                ? null
                : SizedBox(
                    height: 44,
                    child: FloatingActionButton.extended(
                      foregroundColor: Colors.white,
                      backgroundColor: _mainTabController.index == 0
                          ? AppColors.primary
                          : colorScheme.secondary,
                      onPressed: () {
                        if (_mainTabController.index == 0) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  AddTaskScreen(staffId: _loggedInStaffId ?? ''),
                            ),
                          ).then((_) => _fetchTasks());
                        } else {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const AddCustomerScreen(),
                            ),
                          ).then((_) => _fetchCustomers());
                        }
                      },
                      label: Text(
                        _mainTabController.index == 0 ? 'Add Task' : 'Add Customer',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      icon: Icon(
                        _mainTabController.index == 0
                            ? Icons.add_task_rounded
                            : Icons.person_add,
                        size: 18,
                      ),
                    ),
                  ),
          );
        },
      ),
    );
  }

  Widget _buildFieldJourneyBanner(ColorScheme colorScheme) {
    final hasActive = _activeJourney != null;
    return Container(
      margin: const EdgeInsets.fromLTRB(_kHeaderHPad, _kHeaderGap, _kHeaderHPad, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: hasActive ? Colors.green.shade50 : Colors.blue.shade50,
        borderRadius: BorderRadius.circular(_kHeaderRadius),
        border: Border.all(
          color: hasActive ? Colors.green.shade200 : Colors.blue.shade200,
        ),
      ),
      child: Row(
        children: [
          // Same 40px rounded tile as the stat cards' icons.
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: hasActive ? Colors.green.shade100 : Colors.blue.shade100,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              hasActive ? Icons.directions_walk_rounded : Icons.explore_outlined,
              color: hasActive ? Colors.green.shade800 : AppColors.primary,
              size: 22,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasActive ? 'At client' : 'Field Visit',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: hasActive ? Colors.green.shade900 : Colors.blue.shade900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  // Matches the allowance rule: travel is paid Punch In → Field In,
                  // Field Out → next Field In, …, last Field Out → Punch Out; the time
                  // between a visit's Field In and Field Out is time at the client.
                  hasActive
                      ? 'Field In at ${_activeJourney!['fieldInTime'] ?? _activeJourney!['startTime'] ?? '—'} • Tap Field Out when you leave'
                      : 'Field In when you reach a client · Field Out when you leave',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: hasActive ? Colors.green.shade800 : Colors.blue.shade800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (_isJourneyActionLoading)
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            ElevatedButton(
              onPressed: hasActive ? _handleJourneyFieldOut : _handleJourneyFieldIn,
              style: ElevatedButton.styleFrom(
                backgroundColor: hasActive ? Colors.green.shade700 : AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                minimumSize: const Size(0, 38),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
              child: Text(
                hasActive ? 'Field Out' : 'Field In',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAllowanceTabView(ColorScheme colorScheme) {
    if (_isLoadingAllowances) {
      return const Center(child: AppTabLoader());
    }
    if (_allowances.isEmpty) {
      return RefreshIndicator(
        onRefresh: _fetchAllowances,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.5,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.payments_outlined, size: 64, color: Colors.grey.shade400),
                  const SizedBox(height: 16),
                  Text(
                    'No travel allowances recorded yet',
                    style: TextStyle(fontSize: 15, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Complete tasks or field journeys to earn allowances',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _fetchAllowances,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
        itemCount: _allowances.length,
        itemBuilder: (context, index) {
          final item = _allowances[index];
          final dateStr = (item['date'] ?? '').toString();
          final distance = (item['totalDistanceKm'] ?? 0.0).toDouble();
          final amount = (item['generatedAmount'] ?? item['revisedAmount'] ?? 0.0).toDouble();
          final status = (item['status'] ?? 'Pending').toString();
          final rate = item['ratePerKm'] ?? item['transport']?['rate'];
          final transportName = item['transport']?['name']?.toString();

          Color statusColor = AppColors.brandDark;
          if (status.toLowerCase() == 'approved') {
            statusColor = Colors.green.shade700;
          } else if (status.toLowerCase() == 'rejected') {
            statusColor = Colors.red.shade700;
          }

          return Card(
            elevation: 1,
            margin: const EdgeInsets.only(bottom: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Icon(Icons.calendar_today_outlined, size: 14, color: colorScheme.onSurfaceVariant),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                dateStr.isNotEmpty ? dateStr : 'Today',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: statusColor, width: 0.6),
                        ),
                        child: Text(
                          status,
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: statusColor),
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Total Distance',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${distance.toStringAsFixed(2)} km',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                      if (rate != null)
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Text(
                                transportName ?? 'Rate/Km',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '₹$rate/km',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              'Allowance',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '₹ ${amount.toStringAsFixed(2)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.primary),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHistoryTabView(ColorScheme colorScheme) {
    if (_isLoadingHistory) {
      return const Center(child: AppTabLoader());
    }
    if (_historyTasks.isEmpty) {
      return RefreshIndicator(
        onRefresh: _fetchHistory,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.5,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.history_rounded, size: 64, color: Colors.grey.shade400),
                  const SizedBox(height: 16),
                  Text(
                    'No task history found',
                    style: TextStyle(fontSize: 15, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Completed branch and customer visits will appear here',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _fetchHistory,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
        itemCount: _historyTasks.length,
        itemBuilder: (context, index) {
          final task = _historyTasks[index];
          final completedStr = task.completedDate != null
              ? DateDisplayUtil.formatForDisplay(task.completedDate!, 'dd MMM yyyy, hh:mm a')
              : (task.assignedDate != null
                  ? DateDisplayUtil.formatForDisplay(task.assignedDate!, 'dd MMM yyyy')
                  : 'Past Task');

          return Card(
            elevation: 1,
            margin: const EdgeInsets.only(bottom: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CompletedTaskDetailScreen(task: task),
                  ),
                );
              },
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            task.taskTitle.isNotEmpty ? task.taskTitle : task.taskId,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.green.shade400, width: 0.6),
                          ),
                          child: Text(
                            _statusLabel(task.status),
                            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: Colors.green.shade700),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    if (task.customer?.customerName != null) ...[
                      Row(
                        children: [
                          Icon(Icons.person_outline, size: 14, color: colorScheme.onSurfaceVariant),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              task.customer!.customerName,
                              style: TextStyle(fontSize: 12, color: colorScheme.onSurface),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                    ],
                    if (task.destinationLocation?.displayAddress != null) ...[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.place_outlined, size: 14, color: colorScheme.onSurfaceVariant),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              task.destinationLocation!.displayAddress!,
                              style: TextStyle(fontSize: 11.5, color: colorScheme.onSurfaceVariant),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                    ],
                    Row(
                      children: [
                        Icon(Icons.check_circle_outline, size: 14, color: Colors.green.shade600),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            completedStr,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11.5, color: colorScheme.onSurfaceVariant),
                          ),
                        ),
                        Text(
                          'View Report',
                          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppColors.primary),
                        ),
                        Icon(Icons.chevron_right, size: 16, color: AppColors.primary),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
