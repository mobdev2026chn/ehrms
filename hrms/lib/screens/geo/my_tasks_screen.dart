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
import 'package:hrms/screens/dashboard/dashboard_screen.dart';
import 'package:hrms/screens/geo/add_task_screen.dart';
import 'package:hrms/screens/geo/add_customer_screen.dart';
import 'package:hrms/models/customer.dart';
import 'package:hrms/widgets/app_drawer.dart';
import 'package:hrms/widgets/bottom_navigation_bar.dart';
import 'package:hrms/screens/geo/arrived_screen.dart';
import 'package:hrms/screens/geo/completed_task_detail_screen.dart';
import 'package:hrms/screens/geo/task_detail_screen.dart';
import 'package:intl/intl.dart';
import 'package:hrms/utils/date_display_util.dart';
import 'package:hrms/utils/error_message_utils.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:hrms/widgets/app_tab_loader.dart';
import 'package:hrms/utils/snackbar_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MyTasksScreen extends StatefulWidget {
  final int? dashboardTabIndex;
  final void Function(int index)? onNavigateToIndex;

  const MyTasksScreen({
    super.key,
    this.dashboardTabIndex,
    this.onNavigateToIndex,
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

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  DateTime? _filterStartDate;
  DateTime? _filterEndDate;
  bool _isSelectionMode = false;
  final Set<String> _selectedTaskIds = {};
  bool _exporting = false;
  // Selected status-filter group key sent to the backend; null = All Statuses.
  String? _statusFilter;

  // Dropdown options: label shown to the user + backend status-group key.
  static const List<({String label, String? group})> _statusFilterOptions = [
    (label: 'All Statuses', group: null),
    (label: 'Pending/Assigned', group: 'pending'),
    (label: 'In Progress', group: 'inProgress'),
    (label: 'Hold', group: 'hold'),
    (label: 'Hold on Arrival', group: 'holdOnArrival'),
    (label: 'Waiting for Approval', group: 'waitingForApproval'),
    (label: 'Completed', group: 'completed'),
    (label: 'Exit on Arrival', group: 'exitOnArrival'),
    (label: 'Exited', group: 'exited'),
    (label: 'Reopened', group: 'reopened'),
    (label: 'Rejected', group: 'rejected'),
  ];
  int _tasksPage = 1;
  static const int _tasksPerPage = 5;

  // Customers are paginated client-side (the service returns the full list):
  // show 10 cards per page with a page-number + arrow bar like the task list.
  int _customersPage = 1;
  static const int _customersPerPage = 10;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _mainTabController = TabController(length: 2, vsync: this);
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
      _fetchCustomers();
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

    final group = _statusFilter;
    if (group != null) {
      final allowed = _statusesForGroup(group);
      if (allowed.isNotEmpty) {
        list = list.where((t) => allowed.contains(t.status));
      }
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
  /// the model), matching the date shown on each task card. Compared using
  /// local date parts since [_filterStartDate]/[_filterEndDate] are derived
  /// from the device's local "today" (Today/This Week/This Month) —
  /// comparing against the UTC date could shift tasks into the wrong day near
  /// midnight depending on the device's timezone offset.
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

  /// Orders tasks by assignment date, most recently assigned first, so the
  /// list shows a stable, predictable order regardless of what the backend
  /// returns. Tasks without an assigned date are pushed to the end.
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

  /// TaskStatus values whose card badge belongs to a dropdown status group.
  /// Mirrors _statusLabel so the filter matches exactly what the card shows.
  Set<TaskStatus> _statusesForGroup(String group) {
    switch (group) {
      case 'pending':
        return {TaskStatus.pending, TaskStatus.assigned, TaskStatus.scheduled};
      case 'inProgress':
        return {TaskStatus.inProgress, TaskStatus.arrived};
      case 'hold':
        return {TaskStatus.hold};
      case 'holdOnArrival':
        return {TaskStatus.holdOnArrival};
      case 'waitingForApproval':
        return {TaskStatus.waitingForApproval};
      case 'completed':
        return {TaskStatus.completed};
      case 'exitOnArrival':
        return {TaskStatus.exitedOnArrival};
      case 'exited':
        return {TaskStatus.exited};
      case 'reopened':
        return {TaskStatus.reopened};
      case 'rejected':
        return {TaskStatus.rejected};
      default:
        return const {};
    }
  }

  int _statusGroupCount(String group) {
    switch (group) {
      case 'inProgress':
        return _tasks
            .where(
              (t) =>
                  t.status == TaskStatus.inProgress ||
                  t.status == TaskStatus.arrived,
            )
            .length;
      case 'hold':
        return _tasks
            .where(
              (t) =>
                  t.status == TaskStatus.hold ||
                  t.status == TaskStatus.holdOnArrival,
            )
            .length;
      case 'completed':
        return _tasks
            .where(
              (t) =>
                  t.status == TaskStatus.completed ||
                  t.status == TaskStatus.waitingForApproval,
            )
            .length;
      default:
        return 0;
    }
  }

  bool get _hasAnyFilters =>
      _searchQuery.trim().isNotEmpty ||
      _filterStartDate != null ||
      _filterEndDate != null ||
      _statusFilter != null;

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
            String dateText() {
              if (tempStart == null && tempEnd == null) return 'Not selected';
              if (tempStart != null && tempEnd != null) {
                return '${DateFormat('dd/MM/yy').format(tempStart!)} - ${DateFormat('dd/MM/yy').format(tempEnd!)}';
              }
              if (tempStart != null) {
                return 'From ${DateFormat('dd/MM/yy').format(tempStart!)}';
              }
              return 'To ${DateFormat('dd/MM/yy').format(tempEnd!)}';
            }

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  12,
                  16,
                  12 + MediaQuery.of(ctx).viewInsets.bottom,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'Filter tasks',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            onPressed: () => Navigator.of(ctx).pop(),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Date filter',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Builder(
                        builder: (_) {
                          final now = DateTime.now();
                          final today = DateTime(now.year, now.month, now.day);
                          final weekStart = today.subtract(
                            Duration(days: today.weekday - 1),
                          );
                          final weekEnd = weekStart.add(
                            const Duration(days: 6),
                          );
                          final monthStart = DateTime(now.year, now.month, 1);
                          final monthEnd = DateTime(now.year, now.month + 1, 0);

                          bool sameDay(DateTime? a, DateTime? b) =>
                              a != null &&
                              b != null &&
                              a.year == b.year &&
                              a.month == b.month &&
                              a.day == b.day;
                          bool isRange(DateTime s, DateTime e) =>
                              sameDay(tempStart, s) && sameDay(tempEnd, e);

                          void selectRange(DateTime s, DateTime e) {
                            setBottomState(() {
                              tempStart = s;
                              tempEnd = e;
                            });
                          }

                          final isCustom =
                              (tempStart != null || tempEnd != null) &&
                              !isRange(today, today) &&
                              !isRange(weekStart, weekEnd) &&
                              !isRange(monthStart, monthEnd);

                          return Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              ChoiceChip(
                                label: const Text('Today'),
                                selected: isRange(today, today),
                                onSelected: (_) => selectRange(today, today),
                              ),
                              ChoiceChip(
                                label: const Text('This Week'),
                                selected: isRange(weekStart, weekEnd),
                                onSelected: (_) =>
                                    selectRange(weekStart, weekEnd),
                              ),
                              ChoiceChip(
                                label: const Text('This Month'),
                                selected: isRange(monthStart, monthEnd),
                                onSelected: (_) =>
                                    selectRange(monthStart, monthEnd),
                              ),
                              ChoiceChip(
                                avatar: Icon(
                                  Icons.date_range,
                                  size: 18,
                                  color: isCustom
                                      ? colorScheme.onSecondaryContainer
                                      : colorScheme.onSurfaceVariant,
                                ),
                                label: Text(isCustom ? dateText() : 'Custom'),
                                selected: isCustom,
                                onSelected: (_) async {
                                  final base = DateTime.now();
                                  final initialStart = tempStart ?? base;
                                  final initialEnd =
                                      tempEnd ?? tempStart ?? base;
                                  final range = await showDateRangePicker(
                                    context: ctx,
                                    firstDate: DateTime(2020),
                                    lastDate: base.add(
                                      const Duration(days: 365),
                                    ),
                                    initialDateRange: DateTimeRange(
                                      start: initialStart.isBefore(initialEnd)
                                          ? initialStart
                                          : initialEnd,
                                      end: initialEnd.isAfter(initialStart)
                                          ? initialEnd
                                          : initialStart,
                                    ),
                                    helpText: 'Select date range',
                                  );
                                  if (range != null) {
                                    setBottomState(() {
                                      tempStart = range.start;
                                      tempEnd = range.end;
                                    });
                                  }
                                },
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () {
                                setBottomState(() {
                                  tempStart = null;
                                  tempEnd = null;
                                });
                                setState(() {
                                  _filterStartDate = null;
                                  _filterEndDate = null;
                                  _tasksPage = 1;
                                });
                              },
                              child: const Text('Reset'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () {
                                setState(() {
                                  _filterStartDate = tempStart;
                                  _filterEndDate = tempEnd;
                                  _tasksPage = 1;
                                });
                                Navigator.of(ctx).pop();
                              },
                              child: const Text('Apply'),
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
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      color: colorScheme.surface,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Customer name, task name, task ID',
          prefixIcon: const Icon(Icons.search, size: 20),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          filled: true,
          fillColor: colorScheme.surfaceContainerLowest,
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
    _fetchCustomers();
  }

  Future<void> _fetchCustomers() async {
    setState(() => _isLoadingCustomers = true);
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
      await _fetchTasks();
      await _fetchCustomers();
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
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
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
              const SizedBox(width: 12),
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
          const SizedBox(height: 12),
          // New Task button and status filter share one row: the filter
          // expands to fill the space, the button sits compact beside it.
          // IntrinsicHeight bounds the row's height so CrossAxisAlignment.stretch
          // has a finite constraint to stretch against — without it, the row
          // inherits the Column's unbounded height and throws
          // "BoxConstraints forces an infinite height".
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _buildStatusFilterDropdown()),
                if (_loggedInStaffId != null &&
                    _loggedInStaffId!.isNotEmpty) ...[
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              AddTaskScreen(staffId: _loggedInStaffId!),
                        ),
                      ).then((_) => _fetchTasks());
                    },
                    icon: const Icon(
                      Icons.add_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                    label: const Text(
                      'New Task',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Status filter as a dropdown (replaces the horizontal chip row).
  Widget _buildStatusFilterDropdown() {
    final isActive = _statusFilter != null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
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

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: filled
                ? AppColors.primary.withValues(alpha: 0.3)
                : Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: iconColor),
          ),
          const SizedBox(height: 12),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
              color: labelColor,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: valueColor,
                  height: 1,
                ),
              ),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  caption,
                  style: TextStyle(fontSize: 13, color: labelColor),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTaskPaginationBar(ColorScheme colorScheme) {
    final totalPages = _totalTaskPages;
    if (_filteredTasks.isEmpty) return const SizedBox.shrink();
    return Container(
      color: Colors.transparent,
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 0),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              const Spacer(),
              IconButton(
                onPressed: _currentTaskPage > 1
                    ? () => setState(() => _tasksPage = _currentTaskPage - 1)
                    : null,
                tooltip: 'Previous page',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              Text(
                '$_currentTaskPage/$totalPages',
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
              IconButton(
                onPressed: _currentTaskPage < totalPages
                    ? () => setState(() => _tasksPage = _currentTaskPage + 1)
                    : null,
                tooltip: 'Next page',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.chevron_right_rounded),
              ),
              const Spacer(),
            ],
          ),
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
    } else {
      if (_isLoadingCustomers || _customers.isEmpty) {
        return const SizedBox.shrink();
      }
      bar = _buildCustomerPaginationBar(colorScheme);
    }
    return Material(
      color: colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
        child: bar,
      ),
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
    final totalPages = _customersTotalPages;
    return Container(
      color: Colors.transparent,
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 0),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              const Spacer(),
              IconButton(
                onPressed: _currentCustomerPage > 1
                    ? () => setState(
                        () => _customersPage = _currentCustomerPage - 1,
                      )
                    : null,
                tooltip: 'Previous page',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              Text(
                '$_currentCustomerPage/$totalPages',
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
              IconButton(
                onPressed: _currentCustomerPage < totalPages
                    ? () => setState(
                        () => _customersPage = _currentCustomerPage + 1,
                      )
                    : null,
                tooltip: 'Next page',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.chevron_right_rounded),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }

  Color _getStatusChipColor(TaskStatus status) {
    switch (status) {
      case TaskStatus.pending:
        return Colors.orange.shade600;
      case TaskStatus.inProgress:
        return Colors.blue.shade600;
      case TaskStatus.arrived:
        return Colors.indigo.shade600;
      case TaskStatus.exited:
        return Colors.amber.shade700;
      case TaskStatus.exitedOnArrival:
        return Colors.orange.shade800;
      case TaskStatus.hold:
      case TaskStatus.holdOnArrival:
        return Colors.amber.shade700;
      case TaskStatus.reopenedOnArrival:
        return Colors.teal.shade600;
      case TaskStatus.completed:
        return Colors.green.shade600;
      case TaskStatus.waitingForApproval:
        return Colors.amber.shade600;
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
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const DashboardScreen()),
            (route) => false,
          );
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
                      tabs: const [
                        Tab(text: 'Tasks'),
                        Tab(text: 'Customers'),
                      ],
                    ),
              actions: [
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
                //if (_isSelectionMode || _mainTabController.index == 0)
                  // IconButton(
                  //   icon: _exporting
                  //       ? const SizedBox(
                  //           width: 20,
                  //           height: 20,
                  //           child: CircularProgressIndicator(strokeWidth: 2),
                  //         )
                  //       : Icon(
                  //           _isSelectionMode
                  //               ? Icons.file_download
                  //               : Icons.download_outlined,
                  //           color: _isSelectionMode
                  //               ? colorScheme.primary
                  //               : null,
                  //         ),
                  //   tooltip: _isSelectionMode
                  //       ? 'Export selected tasks'
                  //       : 'Select tasks to export',
                  //   onPressed: _exporting
                  //       ? null
                  //       : () {
                  //           if (_isSelectionMode) {
                  //             _exportSelectedToExcel();
                  //           } else {
                  //             setState(() => _isSelectionMode = true);
                  //             SnackBarUtils.showSnackBar(
                  //               context,
                  //               'Select tasks to export, then tap Export again.',
                  //             );
                  //           }
                  //         },
                  // ),
              ],
            ),
            body: TabBarView(
              controller: _mainTabController,
              children: [
                // Tasks Tab
                _isLoading
                    ? const Center(child: AppTabLoader())
                    : _errorMessage != null
                    ? Center(child: Text(_errorMessage!))
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
                            if (visibleTasks.isEmpty)
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
                                padding: const EdgeInsets.fromLTRB(
                                  12,
                                  8,
                                  12,
                                  12,
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
                                                            // the model); shown as-is.
                                                            DateDisplayUtil.formatShortDate(
                                                              task.assignedDate ??
                                                                  task.expectedCompletionDate,
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

                // Customers Tab
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
                          padding: const EdgeInsets.all(12),
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
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(
                        builder: (_) =>
                            DashboardScreen(initialIndex: index.clamp(0, 4)),
                      ),
                      (route) => false,
                    );
                  },
                ),
              ],
            ),
            floatingActionButton: _mainTabController.index == 1
                ? SizedBox(
                    height: 40,
                    child: FloatingActionButton.extended(
                      foregroundColor: Colors.white,
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const AddCustomerScreen(),
                          ),
                        ).then((_) => _fetchCustomers());
                      },
                      label: const Text(
                        'Add Customer',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      icon: const Icon(Icons.person_add, size: 18),
                      backgroundColor: colorScheme.secondary,
                    ),
                  )
                : null,
          );
        },
      ),
    );
  }
}
