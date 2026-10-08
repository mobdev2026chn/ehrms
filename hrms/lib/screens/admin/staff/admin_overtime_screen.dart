// lib/screens/admin/staff/admin_overtime_screen.dart
// Admin Overtime Management - mirrors the web Overtime page
// (HRMSfrontend features/admin/staff/overtime). The list is filtered server-side by
// status / search / department (GET /admin/staff/overtime/list), exactly the params the web
// sends; branch and date have no backend param, so they narrow the result locally as on web.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../config/app_colors.dart';
import '../../../config/app_text_styles.dart';
import '../../../services/admin_payroll_service.dart';
import '../../../utils/snackbar_utils.dart';
import '../../../widgets/app_card.dart';
import '../../../widgets/app_drawer.dart';
import '../../../widgets/app_tab_loader.dart';

String _dateOnly(dynamic raw) {
  if (raw == null) return '';
  final d = DateTime.tryParse(raw.toString());
  if (d == null) return raw.toString();
  return DateFormat('yyyy-MM-dd').format(d.toLocal());
}

String _deptOf(dynamic v) {
  if (v is Map) return (v['name'] ?? '').toString();
  return (v ?? '').toString();
}

String _branchOf(dynamic v) {
  if (v is Map) return (v['branchName'] ?? v['name'] ?? '').toString();
  return (v ?? '').toString();
}

class AdminOvertimeRecord {
  final String id;
  final String employeeId;
  final String name;
  final String department;
  final String designation;
  final String branch;
  final String workMode;
  final String scheduleType; // 'Single Date' | 'Date Range'
  final String date;
  final String startDate;
  final String endDate;
  final String notes;
  final String status; // 'Pending' | 'Accepted' | 'Rejected' | 'Expired'
  final String requestedAt;

  AdminOvertimeRecord({
    required this.id,
    required this.employeeId,
    required this.name,
    required this.department,
    required this.designation,
    this.branch = '',
    this.workMode = '',
    required this.scheduleType,
    required this.date,
    required this.startDate,
    required this.endDate,
    required this.notes,
    required this.status,
    required this.requestedAt,
  });

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.length > 1) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return parts.isNotEmpty ? parts[0][0].toUpperCase() : 'U';
  }

  /// One item of `data.requests` from `GET /admin/staff/overtime/list` (staffId populated).
  factory AdminOvertimeRecord.fromJson(Map<String, dynamic> json) {
    final staffObj = json['staffId'] is Map ? Map<String, dynamic>.from(json['staffId'] as Map) : <String, dynamic>{};
    final fullName = '${staffObj['firstName'] ?? ''} ${staffObj['lastName'] ?? ''}'.trim();
    final workMode = staffObj['workMode'] is Map ? staffObj['workMode']['mode'] : staffObj['workMode'];
    final start = _dateOnly(json['startDate']);
    return AdminOvertimeRecord(
      id: (json['_id'] ?? json['id'] ?? '').toString(),
      employeeId: (staffObj['employeeId'] ?? '').toString(),
      name: fullName.isNotEmpty ? fullName : (staffObj['name'] ?? 'Employee').toString(),
      department: _deptOf(staffObj['department']),
      designation: _deptOf(staffObj['designation']),
      branch: _branchOf(staffObj['branch']),
      workMode: (workMode ?? 'In Office').toString(),
      scheduleType: (json['scheduleType'] ?? 'Single Date').toString(),
      date: (json['date'] ?? start).toString(),
      startDate: start,
      endDate: _dateOnly(json['endDate']),
      notes: ((json['notes'] ?? '').toString().trim().isEmpty) ? '—' : json['notes'].toString(),
      status: (json['status'] ?? 'Pending').toString(),
      requestedAt: _dateOnly(json['requestedAt'] ?? json['createdAt']),
    );
  }
}

class AdminOvertimeScreen extends StatefulWidget {
  const AdminOvertimeScreen({super.key});

  @override
  State<AdminOvertimeScreen> createState() => _AdminOvertimeScreenState();
}

class _AdminOvertimeScreenState extends State<AdminOvertimeScreen> {
  static const String _allStatuses = 'All Statuses';
  static const String _allDepartments = 'All Departments';
  static const String _allBranches = 'All Branches';

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final AdminPayrollService _service = AdminPayrollService();
  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _searchDebounce;
  int _loadSeq = 0;

  bool _isLoading = true;
  String? _error;
  String _searchQuery = '';
  String _statusFilter = _allStatuses;
  DateTime? _selectedDateFilter;
  String _selectedDepartmentFilter = _allDepartments;
  String _selectedBranchFilter = _allBranches;

  List<AdminOvertimeRecord> _records = [];
  List<Map<String, dynamic>> _staffList = [];
  List<String> _departments = [_allDepartments];
  List<String> _branches = [_allBranches];

  @override
  void initState() {
    super.initState();
    _loadStaff();
    _loadData();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  int get _totalRequestsCount => _records.length;
  int get _pendingCount => _records.where((r) => r.status == 'Pending').length;
  int get _acceptedCount => _records.where((r) => r.status == 'Accepted').length;
  int get _rejectedCount => _records.where((r) => r.status == 'Rejected').length;

  void _showError(Object e) {
    if (!mounted) return;
    SnackBarUtils.showSnackBar(context, e.toString(), isError: true);
  }

  /// Staff for the scheduling picker and the department/branch dropdowns.
  Future<void> _loadStaff() async {
    try {
      final staff = await _service.getStaff();
      if (!mounted) return;
      final depts = <String>{};
      final brs = <String>{};
      for (final s in staff) {
        final d = _deptOf(s['department']);
        final b = _branchOf(s['branch']);
        if (d.isNotEmpty) depts.add(d);
        if (b.isNotEmpty) brs.add(b);
      }
      setState(() {
        _staffList = staff;
        _departments = [_allDepartments, ...depts];
        _branches = [_allBranches, ...brs];
      });
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _loadData({bool showLoader = true}) async {
    final seq = ++_loadSeq;
    if (showLoader && mounted) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }
    try {
      final list = await _service.getOvertimeList(
        status: _statusFilter == _allStatuses ? null : _statusFilter,
        search: _searchQuery,
        department: _selectedDepartmentFilter == _allDepartments ? null : _selectedDepartmentFilter,
      );
      if (!mounted || seq != _loadSeq) return;
      setState(() {
        _records = list.map(AdminOvertimeRecord.fromJson).toList();
        _error = null;
      });
    } catch (e) {
      if (!mounted || seq != _loadSeq) return;
      if (showLoader || _records.isEmpty) {
        setState(() => _error = e.toString());
      } else {
        _showError(e);
      }
    } finally {
      if (mounted && seq == _loadSeq) setState(() => _isLoading = false);
    }
  }

  void _onSearchChanged(String v) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 400), () {
      if (!mounted || v == _searchQuery) return;
      setState(() => _searchQuery = v);
      _loadData(showLoader: false);
    });
  }

  void _setStatus(String status) {
    if (status == _statusFilter) return;
    setState(() => _statusFilter = status);
    _loadData();
  }

  /// Branch and date have no backend param: narrowed locally like the web page.
  List<AdminOvertimeRecord> get _filteredRecords {
    final q = _searchQuery.toLowerCase();
    return _records.where((r) {
      final matchesSearch = q.isEmpty ||
          r.name.toLowerCase().contains(q) ||
          r.employeeId.toLowerCase().contains(q) ||
          r.designation.toLowerCase().contains(q);
      final matchesBranch = _selectedBranchFilter == _allBranches || r.branch == _selectedBranchFilter;
      var matchesDate = true;
      if (_selectedDateFilter != null) {
        final target = DateFormat('yyyy-MM-dd').format(_selectedDateFilter!);
        final start = r.startDate;
        final end = r.endDate.isEmpty ? r.startDate : r.endDate;
        matchesDate = start.isNotEmpty && target.compareTo(start) >= 0 && target.compareTo(end) <= 0;
      }
      return matchesSearch && matchesBranch && matchesDate;
    }).toList();
  }

  Future<void> _pickDateFilter() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDateFilter ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(DateTime.now().year + 2, 12, 31),
    );
    if (picked != null && mounted) setState(() => _selectedDateFilter = picked);
  }

  // ── Action: Cancel (delete) a Pending/Expired overtime request ──
  Future<void> _deleteOvertime(AdminOvertimeRecord r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.delete_outline_rounded, color: AppColors.error, size: 22),
            SizedBox(width: 8),
            Expanded(child: Text('Cancel Overtime Request', style: AppTextStyles.headingSmall)),
          ],
        ),
        content: Text('Are you sure you want to cancel the overtime request for ${r.name} on ${r.date}?', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep', style: TextStyle(color: AppColors.textSecondary))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error, foregroundColor: Colors.white, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: const Text('Cancel Request'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _service.deleteOvertime(r.id);
      if (!mounted) return;
      setState(() => _records.removeWhere((item) => item.id == r.id));
      SnackBarUtils.showSnackBar(context, 'Overtime request cancelled successfully');
    } catch (e) {
      _showError(e);
    }
  }

  // ── Action: Advanced Filters (department -> server, branch -> local) ──
  void _showAdvancedFiltersDrawer() {
    String dept = _selectedDepartmentFilter;
    String branch = _selectedBranchFilter;

    void apply(BuildContext ctx) {
      Navigator.pop(ctx);
      final deptChanged = dept != _selectedDepartmentFilter;
      setState(() {
        _selectedDepartmentFilter = dept;
        _selectedBranchFilter = branch;
      });
      if (deptChanged) _loadData();
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDrawerState) {
          return Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.filter_alt_outlined, color: AppColors.primaryText, size: 20),
                        const SizedBox(width: 8),
                        const Text('Advanced Filters', style: AppTextStyles.headingMedium),
                      ],
                    ),
                    IconButton(tooltip: 'Close', icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(ctx)),
                  ],
                ),
                const SizedBox(height: 16),
                const Text('DEPARTMENT', style: AppTextStyles.sectionLabel),
                const SizedBox(height: 8),
                _boxedDropdown(dept, _departments, (v) => setDrawerState(() => dept = v), height: 48, fontSize: 14),
                const SizedBox(height: 16),
                const Text('BRANCH', style: AppTextStyles.sectionLabel),
                const SizedBox(height: 8),
                _boxedDropdown(branch, _branches, (v) => setDrawerState(() => branch = v), height: 48, fontSize: 14),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () {
                          dept = _allDepartments;
                          branch = _allBranches;
                          apply(ctx);
                        },
                        style: TextButton.styleFrom(minimumSize: const Size(0, 48)),
                        child: const Text('Reset', style: TextStyle(color: AppColors.textSecondary)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => apply(ctx),
                        style: ElevatedButton.styleFrom(minimumSize: const Size(0, 48)),
                        child: const Text('Apply Filters'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _boxedDropdown(String value, List<String> items, ValueChanged<String> onChanged, {double height = 36, double fontSize = 11}) {
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(color: const Color(0xFFF7F8FA), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE2E5EA))),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: items.contains(value) ? value : items.first,
          isExpanded: true,
          items: items.map((d) => DropdownMenuItem(value: d, child: Text(d, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: fontSize, color: AppColors.textPrimary)))).toList(),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }

  // ── Action: 2-Step Request Overtime Wizard (web staffListModel.tsx) ──
  void _showRequestOvertimeWizard() {
    // Only currently employed staff can be scheduled ("Deactive" is the deactivated status).
    final assignable = _staffList.where((s) => (s['status'] ?? 'Active').toString() != 'Deactive').toList();
    if (assignable.isEmpty) {
      SnackBarUtils.showSnackBar(context, 'No active staff available to schedule overtime for.', isError: true);
      if (_staffList.isEmpty) _loadStaff();
      return;
    }

    String nameOf(Map<String, dynamic> s) {
      final n = '${s['firstName'] ?? ''} ${s['lastName'] ?? ''}'.trim();
      return n.isNotEmpty ? n : (s['name'] ?? 'Employee').toString();
    }

    int currentStep = 1;
    final Set<String> selectedIds = {}; // staff _id
    String searchEmpText = '';
    String filterDept = _allDepartments;
    String filterBranch = _allBranches;
    String scheduleType = 'Single Date';
    DateTime? singleDate;
    DateTime? startDate;
    DateTime? endDate;
    bool submitting = false;
    final notesCtrl = TextEditingController();
    final fmt = DateFormat('yyyy-MM-dd');

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setWizardState) {
          final filteredEmployees = assignable.where((s) {
            final id = (s['employeeId'] ?? '').toString().toLowerCase();
            final name = nameOf(s).toLowerCase();
            final dept = _deptOf(s['department']);
            final br = _branchOf(s['branch']);
            final q = searchEmpText.toLowerCase();
            final matchesSearch = q.isEmpty || id.contains(q) || name.contains(q) || dept.toLowerCase().contains(q);
            final matchesDept = filterDept == _allDepartments || dept == filterDept;
            final matchesBranch = filterBranch == _allBranches || br == filterBranch;
            return matchesSearch && matchesDept && matchesBranch;
          }).toList();

          Future<DateTime?> pick(DateTime? initial) => showDatePicker(
                context: context,
                initialDate: initial ?? DateTime.now(),
                firstDate: DateTime.now().subtract(const Duration(days: 365)),
                lastDate: DateTime.now().add(const Duration(days: 365)),
              );

          Future<void> submit() async {
            String? err;
            if (selectedIds.isEmpty) {
              err = 'Please select at least one employee';
            } else if (scheduleType == 'Single Date' && singleDate == null) {
              err = 'Please select an overtime date';
            } else if (scheduleType == 'Date Range' && (startDate == null || endDate == null)) {
              err = 'Please select start and end dates';
            } else if (scheduleType == 'Date Range' && startDate!.isAfter(endDate!)) {
              err = 'Start date cannot be after end date';
            }
            if (err != null) {
              SnackBarUtils.showSnackBar(context, err, isError: true);
              return;
            }
            final start = fmt.format(scheduleType == 'Single Date' ? singleDate! : startDate!);
            final end = fmt.format(scheduleType == 'Single Date' ? singleDate! : endDate!);
            setWizardState(() => submitting = true);
            try {
              await _service.scheduleOvertime(
                staffIds: selectedIds.toList(),
                scheduleType: scheduleType,
                startDate: start,
                endDate: end,
                notes: notesCtrl.text,
              );
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              if (!mounted) return;
              SnackBarUtils.showSnackBar(this.context, 'Overtime request scheduled for ${selectedIds.length} employee(s)');
              _loadData(showLoader: false);
            } catch (e) {
              if (ctx.mounted) setWizardState(() => submitting = false);
              _showError(e);
            }
          }

          Widget dateField(String label, DateTime? value, ValueChanged<DateTime> onPicked) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppTextStyles.sectionLabel),
                const SizedBox(height: 8),
                InkWell(
                  onTap: () async {
                    final picked = await pick(value);
                    if (picked != null) onPicked(picked);
                  },
                  child: Container(
                    height: 48,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(color: const Color(0xFFF7F8FA), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE2E5EA))),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(value == null ? 'Select date' : fmt.format(value),
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: value == null ? AppColors.textCaption : AppColors.textPrimary)),
                        const Icon(Icons.calendar_month_outlined, size: 20, color: AppColors.textSecondary),
                      ],
                    ),
                  ),
                ),
              ],
            );
          }

          return AlertDialog(
            backgroundColor: AppColors.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            contentPadding: EdgeInsets.zero,
            content: SizedBox(
              width: MediaQuery.of(context).size.width * 0.9,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.10),
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                        border: Border(bottom: BorderSide(color: AppColors.primary.withValues(alpha: 0.25))),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.schedule_rounded, color: AppColors.primaryText, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  currentStep == 1 ? 'Select Employees for Overtime' : 'Configure Overtime Schedule',
                                  style: AppTextStyles.headingSmall,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              _stepIndicator(1, 'Staff Selection', currentStep == 1, currentStep > 1),
                              const SizedBox(width: 8),
                              Container(width: 20, height: 1, color: AppColors.textHint),
                              const SizedBox(width: 8),
                              _stepIndicator(2, 'Schedule Setup', currentStep == 2, false),
                            ],
                          ),
                        ],
                      ),
                    ),

                    if (currentStep == 1) ...[
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          children: [
                            Container(
                              height: 44,
                              decoration: BoxDecoration(color: const Color(0xFFF7F8FA), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE2E5EA))),
                              child: TextField(
                                onChanged: (v) => setWizardState(() => searchEmpText = v),
                                decoration: const InputDecoration(
                                  hintText: 'Search by ID, Name, Department',
                                  hintStyle: TextStyle(fontSize: 13, color: AppColors.textCaption),
                                  prefixIcon: Icon(Icons.search_rounded, size: 20, color: AppColors.textCaption),
                                  border: InputBorder.none,
                                  contentPadding: EdgeInsets.symmetric(vertical: 12),
                                  filled: false,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(child: _boxedDropdown(filterDept, _departments, (v) => setWizardState(() => filterDept = v))),
                                const SizedBox(width: 8),
                                Expanded(child: _boxedDropdown(filterBranch, _branches, (v) => setWizardState(() => filterBranch = v))),
                              ],
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                        height: 240,
                        child: filteredEmployees.isEmpty
                            ? const Center(child: Text('No employees match', style: TextStyle(fontSize: 12, color: AppColors.textCaption)))
                            : ListView.builder(
                                itemCount: filteredEmployees.length,
                                itemBuilder: (context, idx) {
                                  final emp = filteredEmployees[idx];
                                  final sid = (emp['_id'] ?? emp['id'] ?? '').toString();
                                  final empId = (emp['employeeId'] ?? '').toString();
                                  final dept = _deptOf(emp['department']);
                                  final branch = _branchOf(emp['branch']);
                                  final wm = (emp['workMode'] is Map ? emp['workMode']['mode'] : emp['workMode'] ?? 'In Office').toString();
                                  return CheckboxListTile(
                                    value: selectedIds.contains(sid),
                                    activeColor: AppColors.primary,
                                    checkColor: AppColors.onPrimary,
                                    onChanged: sid.isEmpty
                                        ? null
                                        : (val) => setWizardState(() => val == true ? selectedIds.add(sid) : selectedIds.remove(sid)),
                                    title: Text(nameOf(emp), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                                    subtitle: Text([empId, dept, branch].where((x) => x.isNotEmpty).join(' • '), style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary)),
                                    secondary: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(color: AppColors.infoBg, borderRadius: BorderRadius.circular(999)),
                                      child: Text(wm.toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.info)),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],

                    if (currentStep == 2)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('SELECTED EMPLOYEES (${selectedIds.length})', style: AppTextStyles.sectionLabel),
                                GestureDetector(
                                  onTap: () => setWizardState(() => selectedIds.clear()),
                                  child: const Text('Clear All', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.error)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: selectedIds.map((sid) {
                                final emp = assignable.firstWhere((s) => (s['_id'] ?? s['id']).toString() == sid, orElse: () => {'name': sid});
                                return Chip(
                                  label: Text(nameOf(emp), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                  deleteIcon: const Icon(Icons.close_rounded, size: 14),
                                  onDeleted: () => setWizardState(() => selectedIds.remove(sid)),
                                  backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                                  side: BorderSide.none,
                                  shape: const StadiumBorder(),
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 12),
                            const Text('SCHEDULE TYPE', style: AppTextStyles.sectionLabel),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Expanded(
                                  child: _scheduleTypeCard('Single Day Overtime', 'Specific calendar date', Icons.calendar_today_rounded,
                                      scheduleType == 'Single Date', () => setWizardState(() => scheduleType = 'Single Date')),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _scheduleTypeCard('Multi-Day Range', 'Continuous date span', Icons.date_range_rounded,
                                      scheduleType == 'Date Range', () => setWizardState(() => scheduleType = 'Date Range')),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            if (scheduleType == 'Single Date')
                              dateField('DATE *', singleDate, (d) => setWizardState(() => singleDate = d))
                            else
                              Row(
                                children: [
                                  Expanded(child: dateField('START DATE *', startDate, (d) => setWizardState(() => startDate = d))),
                                  const SizedBox(width: 8),
                                  Expanded(child: dateField('END DATE *', endDate, (d) => setWizardState(() => endDate = d))),
                                ],
                              ),
                            const SizedBox(height: 12),
                            const Text('NOTES / REASON', style: AppTextStyles.sectionLabel),
                            const SizedBox(height: 4),
                            TextField(
                              controller: notesCtrl,
                              maxLines: 2,
                              style: const TextStyle(fontSize: 14),
                              decoration: const InputDecoration(
                                hintText: 'Provide notes/reason for the overtime (e.g. Critical system upgrade support)',
                                hintStyle: TextStyle(fontSize: 13, color: AppColors.textCaption),
                                contentPadding: EdgeInsets.all(12),
                              ),
                            ),
                          ],
                        ),
                      ),

                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFECEEF1)))),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          TextButton(
                            onPressed: submitting
                                ? null
                                : () {
                                    if (currentStep == 2) {
                                      setWizardState(() => currentStep = 1);
                                    } else {
                                      Navigator.pop(ctx);
                                    }
                                  },
                            child: Text(currentStep == 2 ? 'Back' : 'Cancel', style: const TextStyle(color: AppColors.textSecondary)),
                          ),
                          ElevatedButton(
                            onPressed: submitting
                                ? null
                                : () {
                                    if (currentStep == 1) {
                                      if (selectedIds.isEmpty) {
                                        SnackBarUtils.showSnackBar(context, 'Please select at least one employee', isError: true);
                                        return;
                                      }
                                      setWizardState(() => currentStep = 2);
                                    } else {
                                      submit();
                                    }
                                  },
                            style: ElevatedButton.styleFrom(
                              minimumSize: const Size(0, 44),
                            ),
                            child: submitting
                                ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onPrimary))
                                : Text(currentStep == 1 ? 'Continue' : 'Send Request'),
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
      ),
    ).whenComplete(notesCtrl.dispose);
  }

  Widget _stepIndicator(int stepNum, String title, bool isActive, bool isDone) {
    return Row(
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: isDone ? AppColors.success : (isActive ? AppColors.primary : AppColors.divider),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: isDone
              ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
              : Text('$stepNum', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: isActive ? AppColors.onPrimary : AppColors.textSecondary)),
        ),
        const SizedBox(width: 4),
        Text(title, style: TextStyle(fontSize: 12, fontWeight: isActive ? FontWeight.w600 : FontWeight.w500, color: isActive ? AppColors.textPrimary : AppColors.textSecondary)),
      ],
    );
  }

  Widget _scheduleTypeCard(String title, String subtitle, IconData icon, bool isSelected, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary.withValues(alpha: 0.10) : AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isSelected ? AppColors.primary : const Color(0xFFE2E5EA), width: isSelected ? 1.4 : 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: isSelected ? AppColors.primaryText : AppColors.textSecondary),
                const SizedBox(width: 4),
                Expanded(child: Text(title, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: isSelected ? AppColors.textPrimary : AppColors.textSecondary))),
              ],
            ),
            const SizedBox(height: 2),
            Text(subtitle, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredRecords;
    final hasMoreFilters = _selectedDepartmentFilter != _allDepartments || _selectedBranchFilter != _allBranches;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppColors.background,
      drawer: const AppDrawer(),
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Open menu',
          icon: const Icon(Icons.menu_rounded),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        title: const Text('Overtime Management'),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 24),
            onPressed: () => _loadData(),
            tooltip: 'Refresh',
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _loadData(showLoader: false),
        color: AppColors.primary,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            AppCard(
              padding: const EdgeInsets.all(20),
              border: Border.all(color: const Color(0xFFECEEF1)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.more_time_rounded, size: 22, color: AppColors.primaryText),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text('Overtime Management', style: AppTextStyles.headingSmall),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text('Schedule and track employee overtime requests. Requests require employee acceptance to take effect.', style: AppTextStyles.bodySmall),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _showRequestOvertimeWizard,
                      icon: const Icon(Icons.add_rounded, size: 20),
                      label: const Text('Request Overtime'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(child: _topStatCard('TOTAL REQUESTS', '$_totalRequestsCount', Icons.schedule_rounded, AppColors.info, AppColors.infoBg, _allStatuses)),
                const SizedBox(width: 12),
                Expanded(child: _topStatCard('PENDING', '$_pendingCount', Icons.warning_amber_rounded, AppColors.warning, AppColors.warningBg, 'Pending')),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _topStatCard('ACCEPTED', '$_acceptedCount', Icons.check_circle_outline_rounded, AppColors.success, AppColors.successBg, 'Accepted')),
                const SizedBox(width: 12),
                Expanded(child: _topStatCard('REJECTED', '$_rejectedCount', Icons.cancel_outlined, AppColors.error, AppColors.errorBg, 'Rejected')),
              ],
            ),
            const SizedBox(height: 12),

            AppCard(
              border: Border.all(color: const Color(0xFFECEEF1)),
              child: Column(
                children: [
                  SizedBox(
                    height: 48,
                    child: TextField(
                      controller: _searchCtrl,
                      onChanged: _onSearchChanged,
                      style: const TextStyle(fontSize: 14),
                      decoration: const InputDecoration(
                        hintText: 'Search by name, ID or designation...',
                        prefixIcon: Icon(Icons.search_rounded, size: 20),
                        contentPadding: EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _boxedDropdown(_statusFilter, const [_allStatuses, 'Pending', 'Accepted', 'Rejected', 'Expired'], _setStatus, height: 44, fontSize: 13),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: InkWell(
                          onTap: _pickDateFilter,
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            height: 44,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(color: const Color(0xFFF7F8FA), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE2E5EA))),
                            child: Row(
                              children: [
                                const Icon(Icons.calendar_today_rounded, size: 16, color: AppColors.textSecondary),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _selectedDateFilter == null ? 'Any date' : DateFormat('yyyy-MM-dd').format(_selectedDateFilter!),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textPrimary),
                                  ),
                                ),
                                if (_selectedDateFilter != null)
                                  GestureDetector(
                                    onTap: () => setState(() => _selectedDateFilter = null),
                                    child: const Icon(Icons.close_rounded, size: 18, color: AppColors.textCaption),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _showAdvancedFiltersDrawer,
                      icon: Icon(Icons.filter_alt_outlined, size: 18, color: hasMoreFilters ? AppColors.primaryText : AppColors.textSecondary),
                      label: Text(hasMoreFilters ? 'More Filters (active)' : 'More Filters',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: hasMoreFilters ? AppColors.primaryText : AppColors.textPrimary)),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: hasMoreFilters ? AppColors.primary : const Color(0xFFE2E5EA), width: 1.2),
                        backgroundColor: hasMoreFilters ? AppColors.primary.withValues(alpha: 0.12) : null,
                        minimumSize: const Size(0, 44),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            if (_isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 60),
                child: Center(child: AppTabLoader()),
              )
            else if (_error != null)
              AppCard(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                border: Border.all(color: const Color(0xFFECEEF1)),
                child: Column(
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: const BoxDecoration(color: AppColors.errorBg, shape: BoxShape.circle),
                      child: const Icon(Icons.cloud_off_rounded, size: 30, color: AppColors.error),
                    ),
                    const SizedBox(height: 16),
                    Text(_error!, textAlign: TextAlign.center, style: AppTextStyles.bodySmall),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: () => _loadData(),
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              )
            else if (filtered.isEmpty)
              AppCard(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                border: Border.all(color: const Color(0xFFECEEF1)),
                child: Center(
                  child: Column(
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.12), shape: BoxShape.circle),
                        child: Icon(Icons.more_time_rounded, size: 30, color: AppColors.primaryText),
                      ),
                      const SizedBox(height: 16),
                      const Text('No overtime requests found', textAlign: TextAlign.center, style: AppTextStyles.headingSmall),
                      const SizedBox(height: 4),
                      const Text('Try adjusting your search criteria or create a new overtime schedule.', textAlign: TextAlign.center, style: AppTextStyles.bodySmall),
                    ],
                  ),
                ),
              )
            else
              ...filtered.map(_buildOvertimeCard),
          ],
        ),
      ),
    );
  }

  Widget _topStatCard(String title, String count, IconData icon, Color color, Color bg, String targetFilter) {
    final isSelected = _statusFilter == targetFilter;
    return InkWell(
      onTap: () => _setStatus(isSelected ? _allStatuses : targetFilter),
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.06) : AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isSelected ? color : const Color(0xFFECEEF1), width: isSelected ? 1.4 : 1),
          boxShadow: kSoftCardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, size: 20, color: color),
            ),
            const SizedBox(height: 12),
            Text(count, style: AppTextStyles.displayLarge.copyWith(fontSize: 24)),
            const SizedBox(height: 2),
            Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.5, color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }

  Widget _buildOvertimeCard(AdminOvertimeRecord r) {
    final isAccepted = r.status == 'Accepted';
    final isPending = r.status == 'Pending';
    final isExpired = r.status == 'Expired';
    final canCancel = isPending || isExpired;

    final Color stBg = isAccepted
        ? AppColors.successBg
        : isPending
            ? AppColors.brandLight
            : isExpired
                ? AppColors.inputFill
                : AppColors.errorBg;
    final Color stFg = isAccepted
        ? AppColors.success
        : isPending
            ? AppColors.brandDark
            : isExpired
                ? AppColors.textSecondary
                : AppColors.error;
    final IconData stIcon = isAccepted
        ? Icons.check_circle_outline_rounded
        : isPending
            ? Icons.schedule_rounded
            : isExpired
                ? Icons.history_rounded
                : Icons.cancel_outlined;

    return AppCard(
      margin: const EdgeInsets.only(bottom: 12),
      border: Border.all(color: const Color(0xFFECEEF1)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                child: Text(r.initials, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.primaryText)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.headingSmall),
                    const SizedBox(height: 2),
                    Text([r.employeeId, r.department].where((x) => x.isNotEmpty).join(' • '),
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.bodySmall),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: stBg, borderRadius: BorderRadius.circular(999)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(stIcon, size: 14, color: stFg),
                    const SizedBox(width: 4),
                    Text(r.status, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: stFg)),
                  ],
                ),
              ),
              // Answered requests feed attendance and the OT report - only unanswered ones can be cancelled.
              if (canCancel)
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, size: 20, color: AppColors.error),
                  tooltip: 'Cancel Overtime Request',
                  onPressed: () => _deleteOvertime(r),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(12)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Icon(Icons.event_outlined, size: 16, color: AppColors.textSecondary),
                    const SizedBox(width: 6),
                    Expanded(child: Text('Scheduled Date: ${r.date}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary))),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(999), border: Border.all(color: const Color(0xFFE2E5EA))),
                      child: Text(r.scheduleType, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text('Notes: ${r.notes}', style: AppTextStyles.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
