// hrms/lib/screens/geo/my_tasks_screen.dart
import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:excel/excel.dart' hide Border;
import 'package:flutter/material.dart';
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
  bool _filterInProgress = false;
  bool _filterHold = false;
  bool _filterCompleted = false;
  int _tasksPage = 1;
  static const int _tasksPerPage = 20;
  int _tasksTotal = 0;
  int _tasksTotalPages = 1;
  Timer? _searchDebounce;

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
    _searchDebounce?.cancel();
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

  List<Task> get _filteredTasks => _tasks;

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
      _filterInProgress ||
      _filterHold ||
      _filterCompleted;

  int get _totalTaskPages {
    return math.max(_tasksTotalPages, 1);
  }

  int get _currentTaskPage =>
      math.min(math.max(_tasksPage, 1), _totalTaskPages);

  List<Task> get _pagedFilteredTasks {
    return _filteredTasks;
  }

  List<String> _activeStatusGroups() {
    final groups = <String>[];
    if (_filterInProgress) groups.add('inProgress');
    if (_filterHold) groups.add('hold');
    if (_filterCompleted) groups.add('completed');
    return groups;
  }

  Future<void> _refreshAndResetAllFilters() async {
    _searchController.clear();
    setState(() {
      _searchQuery = '';
      _filterStartDate = null;
      _filterEndDate = null;
      _filterInProgress = false;
      _filterHold = false;
      _filterCompleted = false;
      _tasksPage = 1;
    });
    await _fetchTasks();
  }

  Future<void> _openTaskFilterBottomSheet() async {
    DateTime? tempStart = _filterStartDate;
    DateTime? tempEnd = _filterEndDate;
    bool tempInProgress = _filterInProgress;
    bool tempHold = _filterHold;
    bool tempCompleted = _filterCompleted;
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
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.date_range, size: 18),
                        label: Text(dateText()),
                        onPressed: () async {
                          final now = DateTime.now();
                          final initialStart = tempStart ?? now;
                          final initialEnd = tempEnd ?? tempStart ?? now;
                          final range = await showDateRangePicker(
                            context: ctx,
                            firstDate: DateTime(2020),
                            lastDate: now.add(const Duration(days: 365)),
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
                      const SizedBox(height: 16),
                      const Text(
                        'Status filter',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilterChip(
                            label: Text(
                              'In Progress (${_statusGroupCount('inProgress')})',
                            ),
                            selected: tempInProgress,
                            onSelected: (v) => setBottomState(() => tempInProgress = v),
                          ),
                          FilterChip(
                            label: Text('Hold (${_statusGroupCount('hold')})'),
                            selected: tempHold,
                            onSelected: (v) => setBottomState(() => tempHold = v),
                          ),
                          FilterChip(
                            label: Text('Completed (${_statusGroupCount('completed')})'),
                            selected: tempCompleted,
                            onSelected: (v) => setBottomState(() => tempCompleted = v),
                          ),
                        ],
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
                                  tempInProgress = false;
                                  tempHold = false;
                                  tempCompleted = false;
                                });
                                setState(() {
                                  _filterStartDate = null;
                                  _filterEndDate = null;
                                  _filterInProgress = false;
                                  _filterHold = false;
                                  _filterCompleted = false;
                                  _tasksPage = 1;
                                });
                                _fetchTasks();
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
                                  _filterInProgress = tempInProgress;
                                  _filterHold = tempHold;
                                  _filterCompleted = tempCompleted;
                                  _tasksPage = 1;
                                });
                                Navigator.of(ctx).pop();
                                _fetchTasks();
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
      child: Row(
        children: [
          Expanded(
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
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                filled: true,
                fillColor: colorScheme.surfaceContainerLowest,
              ),
              onChanged: (_) {
                setState(() {
                  _searchQuery = _searchController.text;
                  _tasksPage = 1;
                });
                _searchDebounce?.cancel();
                _searchDebounce = Timer(const Duration(milliseconds: 350), () {
                  if (mounted) _fetchTasks();
                });
              },
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh tasks and reset filters',
            onPressed: _refreshAndResetAllFilters,
            style: IconButton.styleFrom(
              backgroundColor: colorScheme.surfaceContainerLowest,
              side: BorderSide(color: colorScheme.outline),
            ),
          ),
        ],
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least one task to export')),
      );
      return;
    }
    setState(() => _exporting = true);
    try {
      final excel = Excel.createExcel();
      final sheetName = excel.getDefaultSheet() ?? 'Tasks';
      final sheet = excel[sheetName];

      // Headings row
      const headers = [
        'S.No',
        'Task ID',
        'Task Title',
        'Description',
        'Customer Name',
        'Customer Number',
        'Customer Email',
        'Customer Address',
        'City',
        'Pincode',
        'Expected Completion Date',
        'Assigned Date',
        'Completed Date',
        'Status',
        'Source Address',
        'Destination Address',
        'Start Time',
        'Arrival Time',
        'Trip Distance (km)',
        'Trip Duration (sec)',
        'OTP Required',
        'Geo Fence Required',
        'Photo Required',
        'Form Required',
        'OTP Verified',
        'OTP Verified At',
        'Photo Proof Done',
        'Form Filled',
        'Photo Proof Link',
        'Photo Proof Uploaded At',
        'Photo Proof Address',
        'OTP Verified Address',
        'Exit Status',
        'Require Approval',
        'Auto Approve',
        'Start Battery %',
        'Arrival Battery %',
        'Photo Proof Battery %',
        'Completed Battery %',
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
          TextCellValue(_cellStr(c?.effectiveEmail)),
          TextCellValue(_cellStr(c?.address)),
          TextCellValue(_cellStr(c?.city)),
          TextCellValue(_cellStr(c?.pincode)),
          TextCellValue(_cellStr(t.expectedCompletionDate)),
          TextCellValue(_cellStr(t.assignedDate)),
          TextCellValue(_cellStr(t.completedDate)),
          TextCellValue(t.status.name),
          TextCellValue(_cellStr(t.sourceLocation?.displayAddress)),
          TextCellValue(_cellStr(t.destinationLocation?.displayAddress)),
          TextCellValue(_cellStr(t.startTime)),
          TextCellValue(_cellStr(t.arrivalTime)),
          TextCellValue(t.tripDistanceKm != null ? '${t.tripDistanceKm}' : ''),
          TextCellValue(
            t.tripDurationSeconds != null ? '${t.tripDurationSeconds}' : '',
          ),
          TextCellValue(t.isOtpRequired ? 'Yes' : 'No'),
          TextCellValue(t.isGeoFenceRequired ? 'Yes' : 'No'),
          TextCellValue(t.isPhotoRequired ? 'Yes' : 'No'),
          TextCellValue(t.isFormRequired ? 'Yes' : 'No'),
          TextCellValue(
            t.isOtpVerified == true
                ? 'Yes'
                : (t.isOtpVerified == false ? 'No' : ''),
          ),
          TextCellValue(_cellStr(t.otpVerifiedAt)),
          TextCellValue(
            t.photoProof == true ? 'Yes' : (t.photoProof == false ? 'No' : ''),
          ),
          TextCellValue(
            t.formFilled == true ? 'Yes' : (t.formFilled == false ? 'No' : ''),
          ),
          TextCellValue(_cellStr(t.photoProofUrl)),
          TextCellValue(_cellStr(t.photoProofUploadedAt)),
          TextCellValue(_cellStr(t.photoProofAddress)),
          TextCellValue(_cellStr(t.otpVerifiedAddress)),
          TextCellValue(_cellStr(t.taskExitStatus)),
          TextCellValue(t.requireApprovalOnComplete ? 'Yes' : 'No'),
          TextCellValue(t.autoApprove ? 'Yes' : 'No'),
          TextCellValue(
            t.startBatteryPercent != null ? '${t.startBatteryPercent}' : '',
          ),
          TextCellValue(
            t.arrivalBatteryPercent != null ? '${t.arrivalBatteryPercent}' : '',
          ),
          TextCellValue(
            t.photoProofBatteryPercent != null
                ? '${t.photoProofBatteryPercent}'
                : '',
          ),
          TextCellValue(
            t.completedBatteryPercent != null
                ? '${t.completedBatteryPercent}'
                : '',
          ),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Exported ${toExport.length} task(s) to Excel'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _exporting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ErrorMessageUtils.toUserFriendlyMessage(e))),
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

  Future<void> _fetchTasks() async {
    if (!mounted) return;
    try {
      if (_loggedInStaffId != null && _loggedInStaffId!.isNotEmpty) {
        final res = await TaskService().getAssignedTasksPaginated(
          _loggedInStaffId!,
          page: _tasksPage,
          limit: _tasksPerPage,
          search: _searchQuery,
          startDate: _filterStartDate,
          endDate: _filterEndDate,
          statusGroups: _activeStatusGroups(),
        );
        if (!mounted) return;
        setState(() {
          _tasks = (res['tasks'] as List<Task>? ?? const []);
          _tasksTotal = (res['total'] as int?) ?? _tasks.length;
          _tasksTotalPages = (res['totalPages'] as int?) ?? 1;
          _tasksPage = (res['page'] as int?) ?? _tasksPage;
          _isLoading = false;
          _errorMessage = null;
        });
      } else {
        final assignedTasks = await TaskService().getAllTasks();
        if (!mounted) return;
        setState(() {
          _tasks = assignedTasks;
          _tasksTotal = assignedTasks.length;
          _tasksTotalPages = 1;
          _isLoading = false;
          _errorMessage = null;
        });
      }
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
        content: const Text(
          'Are you sure you want to continue this task?',
        ),
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

  Widget _buildTaskPaginationBar(ColorScheme colorScheme) {
    final totalPages = _totalTaskPages;
    if (_filteredTasks.isEmpty) return const SizedBox.shrink();
    final startItem = ((_currentTaskPage - 1) * _tasksPerPage) + 1;
    final endItem = math.min(_currentTaskPage * _tasksPerPage, _tasksTotal);
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
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
              Icon(Icons.view_list_rounded, size: 16, color: colorScheme.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Showing $startItem-$endItem of $_tasksTotal',
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                onPressed: _currentTaskPage > 1
                    ? () {
                        setState(() => _tasksPage = _currentTaskPage - 1);
                        _fetchTasks();
                      }
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
                    ? () {
                        setState(() => _tasksPage = _currentTaskPage + 1);
                        _fetchTasks();
                      }
                    : null,
                tooltip: 'Next page',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.chevron_right_rounded),
              ),
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
            if (!_isSelectionMode &&
                _mainTabController.index == 0 &&
                _loggedInStaffId != null &&
                _loggedInStaffId!.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.add),
                tooltip: 'Add Task',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => AddTaskScreen(staffId: _loggedInStaffId!),
                    ),
                  ).then((_) => _fetchTasks());
                },
              ),
            if (!_isSelectionMode && _mainTabController.index == 0)
              IconButton(
                icon: Icon(
                  _hasAnyFilters ? Icons.filter_alt : Icons.filter_alt_outlined,
                  color: _hasAnyFilters ? colorScheme.primary : null,
                ),
                tooltip: 'Filter tasks',
                onPressed: _openTaskFilterBottomSheet,
              ),
            if (_isSelectionMode || _mainTabController.index == 0)
              IconButton(
                icon: _exporting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        _isSelectionMode
                            ? Icons.file_download
                            : Icons.download_outlined,
                        color: _isSelectionMode ? colorScheme.primary : null,
                      ),
                tooltip: _isSelectionMode
                    ? 'Export selected tasks'
                    : 'Select tasks to export',
                onPressed: _exporting
                    ? null
                    : () {
                        if (_isSelectionMode) {
                          _exportSelectedToExcel();
                        } else {
                          setState(() => _isSelectionMode = true);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Select tasks to export, then tap Export again.',
                              ),
                            ),
                          );
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
                : _errorMessage != null
                    ? Center(child: Text(_errorMessage!))
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (!_isSelectionMode) _buildSearchAndRefreshRow(),
                          Expanded(
                    child: _tasks.isEmpty
                        ? RefreshIndicator(
                            onRefresh: _fetchTasks,
                            child: SingleChildScrollView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              child: SizedBox(
                                height:
                                    MediaQuery.of(context).size.height * 0.6,
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
                              ),
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _fetchTasks,
                            child: ListView.builder(
                              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                              itemCount: _tasks.length,
                              itemBuilder: (context, index) {
                                final task = _tasks[index];
                                final taskKey = task.id ?? task.taskId;
                                final isCompleted =
                                    task.status == TaskStatus.completed;
                                final statusColor = _getStatusChipColor(
                                  task.status,
                                );
                                final isSelected = _selectedTaskIds.contains(
                                  taskKey,
                                );

                                return InkWell(
                                  onTap: _isSelectionMode
                                      ? () => setState(() {
                                          if (_selectedTaskIds.contains(
                                            taskKey,
                                          )) {
                                            _selectedTaskIds.remove(taskKey);
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
                                                  TaskStatus.holdOnArrival ||
                                              task.status ==
                                                  TaskStatus
                                                      .reopenedOnArrival) {
                                            void goArrived() {
                                              Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (context) =>
                                                      ArrivedScreen(
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
                                                        .sourceLocation?.lat,
                                                    sourceLng: task
                                                        .sourceLocation?.lng,
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
                                                        .arrivalLocation?.lat,
                                                    arrivalAtLng: task
                                                        .arrivalLocation?.lng,
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
                                    margin: const EdgeInsets.only(bottom: 8),
                                    decoration: BoxDecoration(
                                      color: colorScheme.surface,
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: isSelected
                                            ? colorScheme.primary
                                            : colorScheme.outline,
                                        width: isSelected ? 2 : 1,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: colorScheme.shadow.withOpacity(0.08),
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
                                              padding: const EdgeInsets.only(
                                                right: 10,
                                                top: 2,
                                              ),
                                              child: Icon(
                                                _isSelectionMode
                                                    ? (isSelected
                                                          ? Icons.check_circle
                                                          : Icons
                                                                .radio_button_unchecked)
                                                    : Icons.assignment_rounded,
                                                color: _isSelectionMode
                                                    ? (isSelected
                                                          ? colorScheme.primary
                                                          : colorScheme.onSurfaceVariant)
                                                    : colorScheme.primary,
                                                size: _isSelectionMode
                                                    ? 22
                                                    : 20,
                                              ),
                                            ),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment
                                                            .spaceBetween,
                                                    children: [
                                                      Expanded(
                                                        child: Text(
                                                          'Task #${task.taskId}',
                                                          style:
                                                              TextStyle(
                                                                fontSize: 14,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                                color: colorScheme.onSurface,
                                                              ),
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                        ),
                                                      ),
                                                      Text(
                                                        DateDisplayUtil.formatShortDate(
                                                          task.expectedCompletionDate,
                                                        ),
                                                        style: TextStyle(
                                                          fontSize: 10,
                                                          color: Colors
                                                              .grey
                                                              .shade700,
                                                          fontWeight:
                                                              FontWeight.w500,
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
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                  const SizedBox(height: 4),
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
                                                      const SizedBox(width: 4),
                                                      Flexible(
                                                        child: Text(
                                                          'Expected: ${DateDisplayUtil.formatShortDate(task.expectedCompletionDate)}',
                                                          style: TextStyle(
                                                            fontSize: 11,
                                                            color: Colors
                                                                .grey
                                                                .shade800,
                                                            fontWeight:
                                                                FontWeight.w500,
                                                          ),
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                        ),
                                                      ),
                                                      if (isCompleted &&
                                                          task.completedDate !=
                                                              null) ...[
                                                        const SizedBox(
                                                          width: 12,
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
                                                    ],
                                                  ),
                                                  if (task.customer !=
                                                      null) ...[
                                                    const SizedBox(height: 4),
                                                    _buildTaskCardDetailRow(
                                                      icon: Icons
                                                          .person_outline_rounded,
                                                      label: 'Customer',
                                                      value:
                                                          task
                                                                      .customer!
                                                                      .customerNumber !=
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
                                                                Colors.purple,
                                                              ),
                                                            if (task
                                                                .isPhotoRequired)
                                                              _buildRequirementChip(
                                                                'Photo',
                                                                Colors.orange,
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
                                                              .withOpacity(0.1),
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
                                                                FontWeight.w600,
                                                            color: statusColor,
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
                              },
                            ),
                          ),
                  ),
                ],
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
                          itemCount: _customers.length,
                          itemBuilder: (context, index) {
                            final customer = _customers[index];
                            return Card(
                              elevation: 1,
                              margin: const EdgeInsets.only(bottom: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: colorScheme.primary.withOpacity(0.1),
                                  child: Icon(Icons.person, color: colorScheme.primary),
                                ),
                                title: Text(
                                  customer.customerName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                subtitle: Text(
                                  [
                                    if (customer.companyName != null &&
                                        customer.companyName!.trim().isNotEmpty)
                                      customer.companyName!.trim(),
                                    '${customer.customerNumber ?? 'No number'} · ${customer.city}, ${customer.pincode}',
                                  ].join('\n'),
                                  style: const TextStyle(fontSize: 12),
                                ),
                                isThreeLine:
                                    customer.companyName != null &&
                                    customer.companyName!.trim().isNotEmpty,
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
            if (_mainTabController.index == 0 && !_isSelectionMode)
              _buildTaskPaginationBar(colorScheme),
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
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
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
