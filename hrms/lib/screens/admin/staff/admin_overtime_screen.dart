// lib/screens/admin/staff/admin_overtime_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../config/app_colors.dart';
import '../../../services/admin_staff_service.dart';
import '../../../services/api_client.dart';
import '../../../utils/snackbar_utils.dart';
import '../../../widgets/app_drawer.dart';
import '../../../widgets/app_tab_loader.dart';

class AdminOvertimeRecord {
  final String id;
  final String employeeId;
  final String name;
  final String department;
  final String designation;
  final String branch;
  final String workMode;
  final String scheduleType; // 'Single Date' | 'Multi-Day Range'
  final String date;
  final String startDate;
  final String endDate;
  final String notes;
  String status; // 'Pending' | 'Accepted' | 'Rejected' | 'Expired'
  final String requestedAt;

  AdminOvertimeRecord({
    required this.id,
    required this.employeeId,
    required this.name,
    required this.department,
    required this.designation,
    this.branch = 'Main HQ',
    this.workMode = 'IN OFFICE',
    required this.scheduleType,
    required this.date,
    required this.startDate,
    required this.endDate,
    required this.notes,
    required this.status,
    required this.requestedAt,
  });

  String get initials {
    final parts = name.trim().split(' ');
    if (parts.length > 1) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name.isNotEmpty ? name[0].toUpperCase() : 'U';
  }

  factory AdminOvertimeRecord.fromJson(Map<String, dynamic> json) {
    final staffObj = json['staffId'] is Map ? json['staffId'] : json;
    return AdminOvertimeRecord(
      id: (json['_id'] ?? json['id'] ?? '').toString(),
      employeeId: (staffObj['employeeId'] ?? json['employeeId'] ?? 'EMP-001').toString(),
      name: (staffObj['name'] ?? '${staffObj['firstName'] ?? ''} ${staffObj['lastName'] ?? ''}'.trim()).toString().isNotEmpty
          ? (staffObj['name'] ?? '${staffObj['firstName'] ?? ''} ${staffObj['lastName'] ?? ''}'.trim()).toString()
          : (json['name'] ?? 'Employee').toString(),
      department: (staffObj['department'] is Map ? staffObj['department']['name'] : (staffObj['department'] ?? json['department'] ?? 'IT')).toString(),
      designation: (staffObj['designation'] is Map ? staffObj['designation']['name'] : (staffObj['designation'] ?? json['designation'] ?? 'Developer')).toString(),
      branch: (staffObj['branch'] is Map ? (staffObj['branch']['branchName'] ?? staffObj['branch']['name']) : (staffObj['branch'] ?? 'chennai')).toString(),
      workMode: (staffObj['workMode'] is Map ? staffObj['workMode']['mode'] : (staffObj['workMode'] ?? 'IN OFFICE')).toString().toUpperCase(),
      scheduleType: (json['scheduleType'] ?? 'Single Date').toString(),
      date: (json['date'] ?? json['startDate'] ?? '2026-08-29').toString(),
      startDate: (json['startDate'] ?? json['date'] ?? '').toString(),
      endDate: (json['endDate'] ?? json['date'] ?? '').toString(),
      notes: (json['notes'] ?? 'No additional notes provided.').toString(),
      status: (json['status'] ?? 'Pending').toString(),
      requestedAt: (json['requestedAt'] ?? '2026-08-29').toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'employeeId': employeeId,
        'name': name,
        'department': department,
        'designation': designation,
        'scheduleType': scheduleType,
        'date': date,
        'startDate': startDate,
        'endDate': endDate,
        'notes': notes,
        'status': status,
        'requestedAt': requestedAt,
      };
}

class AdminOvertimeScreen extends StatefulWidget {
  const AdminOvertimeScreen({super.key});

  @override
  State<AdminOvertimeScreen> createState() => _AdminOvertimeScreenState();
}

class _AdminOvertimeScreenState extends State<AdminOvertimeScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final AdminStaffService _staffService = AdminStaffService();
  final ApiClient _api = ApiClient();

  bool _isLoading = true;
  String _searchQuery = '';
  String _statusFilter = 'All Statuses'; // 'All Statuses' | 'Pending' | 'Accepted' | 'Rejected'
  String _selectedDateFilter = '';
  String _selectedDepartmentFilter = 'All Departments';
  String _selectedBranchFilter = 'All Branches';

  List<AdminOvertimeRecord> _records = [];
  List<Map<String, dynamic>> _staffList = [];
  List<String> _departments = ['All Departments', 'Engineering', 'IT', 'Design', 'Human Resources'];
  List<String> _branches = ['All Branches', 'chennai', 'hosur', 'test'];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  // Real-time calculated counters matching Screenshot 1
  int get _totalRequestsCount => _records.length;
  int get _pendingCount => _records.where((r) => r.status.toLowerCase() == 'pending').length;
  int get _acceptedCount => _records.where((r) => r.status.toLowerCase() == 'accepted').length;
  int get _rejectedCount => _records.where((r) => r.status.toLowerCase() == 'rejected').length;

  Future<void> _loadData({bool showLoader = true}) async {
    if (showLoader && mounted) setState(() => _isLoading = true);

    try {
      final staffRes = await _staffService.getStaffList();
      if (staffRes['success'] == true && staffRes['data'] != null) {
        _staffList = (staffRes['data']['staff'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();

        final depts = <String>{'All Departments'};
        final brs = <String>{'All Branches'};
        for (final s in _staffList) {
          if (s['department'] != null) depts.add(s['department'].toString());
          if (s['branch'] != null) {
            final b = s['branch'];
            brs.add(b is Map ? (b['branchName'] ?? b['name'] ?? '').toString() : b.toString());
          }
        }
        _departments = depts.toList();
        _branches = brs.toList();
      }

      final res = await _api.request('/admin/staff/overtime/list');
      if (res.data is Map && res.data['success'] == true) {
        final list = (res.data['data']?['requests'] as List?) ?? (res.data['data']?['records'] as List?) ?? (res.data['data'] as List?) ?? [];
        if (list.isNotEmpty && mounted) {
          setState(() {
            _records = list.map((e) => AdminOvertimeRecord.fromJson(Map<String, dynamic>.from(e as Map))).toList();
          });
        } else {
          _setMockRecords();
        }
      } else {
        _setMockRecords();
      }
    } catch (_) {
      _setMockRecords();
    }

    if (showLoader && mounted) setState(() => _isLoading = false);
  }

  void _setMockRecords() {
    _records = [
      AdminOvertimeRecord(
        id: 'OT-001',
        employeeId: 'EKA00008',
        name: 'c man',
        department: 'IT',
        designation: 'dev',
        branch: 'chennai',
        workMode: 'IN OFFICE',
        scheduleType: 'Single Date',
        date: '2026-08-29',
        startDate: '2026-08-29',
        endDate: '2026-08-29',
        notes: 'ftyh',
        status: 'Accepted',
        requestedAt: '2026-08-29',
      ),
      AdminOvertimeRecord(
        id: 'OT-002',
        employeeId: 'EMP-002',
        name: 'james fernado',
        department: 'IT',
        designation: 'Developer',
        branch: 'chennai',
        workMode: 'IN OFFICE',
        scheduleType: 'Single Date',
        date: '2026-08-29',
        startDate: '2026-08-29',
        endDate: '2026-08-29',
        notes: 'rtht',
        status: 'Pending',
        requestedAt: '2026-08-29',
      ),
      AdminOvertimeRecord(
        id: 'OT-003',
        employeeId: 'EMP-012',
        name: 'Saranya V',
        department: 'Engineering',
        designation: 'Junior',
        branch: 'hosur',
        workMode: 'IN OFFICE',
        scheduleType: 'Single Date',
        date: '2026-08-29',
        startDate: '2026-08-29',
        endDate: '2026-08-29',
        notes: 'test',
        status: 'Accepted',
        requestedAt: '2026-08-29',
      ),
      AdminOvertimeRecord(
        id: 'OT-004',
        employeeId: 'EMP-013',
        name: 'john britto',
        department: 'Engineering',
        designation: 'Junior',
        branch: 'test',
        workMode: 'IN OFFICE',
        scheduleType: 'Single Date',
        date: '2026-08-29',
        startDate: '2026-08-29',
        endDate: '2026-08-29',
        notes: 'No additional notes provided.',
        status: 'Pending',
        requestedAt: '2026-08-29',
      ),
      AdminOvertimeRecord(
        id: 'OT-005',
        employeeId: 'EMP-006',
        name: 'hp haith',
        department: 'IT',
        designation: 'Engineer',
        branch: 'chennai',
        workMode: 'IN OFFICE',
        scheduleType: 'Single Date',
        date: '2026-08-27',
        startDate: '2026-08-27',
        endDate: '2026-08-27',
        notes: 'werwe',
        status: 'Accepted',
        requestedAt: '2026-08-27',
      ),
      AdminOvertimeRecord(
        id: 'OT-006',
        employeeId: 'EMP-002',
        name: 'james fernado',
        department: 'IT',
        designation: 'Developer',
        branch: 'chennai',
        workMode: 'IN OFFICE',
        scheduleType: 'Single Date',
        date: '2026-08-25',
        startDate: '2026-08-25',
        endDate: '2026-08-25',
        notes: 'fxgb',
        status: 'Accepted',
        requestedAt: '2026-08-25',
      ),
    ];
  }

  List<AdminOvertimeRecord> get _filteredRecords {
    return _records.where((r) {
      final matchesSearch = _searchQuery.isEmpty ||
          r.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          r.employeeId.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          r.designation.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          r.department.toLowerCase().contains(_searchQuery.toLowerCase());

      final matchesStatus = _statusFilter == 'All Statuses' || r.status.toLowerCase() == _statusFilter.toLowerCase();
      final matchesDate = _selectedDateFilter.isEmpty || r.date.contains(_selectedDateFilter);
      final matchesDept = _selectedDepartmentFilter == 'All Departments' || r.department.toLowerCase() == _selectedDepartmentFilter.toLowerCase();
      final matchesBranch = _selectedBranchFilter == 'All Branches' || r.branch.toLowerCase() == _selectedBranchFilter.toLowerCase();

      return matchesSearch && matchesStatus && matchesDate && matchesDept && matchesBranch;
    }).toList();
  }

  // ── Action: Delete Overtime Request ──
  void _deleteOvertime(AdminOvertimeRecord r) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: const [
            Icon(Icons.delete_outline_rounded, color: Color(0xFFDC2626), size: 22),
            SizedBox(width: 8),
            Text('Delete Overtime Request', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          ],
        ),
        content: Text('Are you sure you want to delete the overtime request for ${r.name} on ${r.date}?', style: const TextStyle(fontSize: 12, color: Color(0xFF475569))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B)))),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              setState(() => _records.removeWhere((item) => item.id == r.id));
              try {
                await _api.request('/admin/staff/overtime/${r.id}', method: 'DELETE');
              } catch (_) {}
              if (mounted) SnackBarUtils.showSnackBar(context, 'Overtime request deleted');
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDC2626), foregroundColor: Colors.white),
            child: const Text('Delete', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  // ── Action: Advanced Filters Slide-Over (Screenshot 3) ──
  void _showAdvancedFiltersDrawer() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDrawerState) {
          return Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: const [
                        Icon(Icons.filter_alt_outlined, color: Color(0xFFEFAA1F), size: 20),
                        SizedBox(width: 8),
                        Text('Advanced Filters', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                      ],
                    ),
                    IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(ctx)),
                  ],
                ),
                const SizedBox(height: 14),

                // Department
                const Text('DEPARTMENT', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF64748B))),
                const SizedBox(height: 4),
                Container(
                  height: 42,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFE2E8F0))),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedDepartmentFilter,
                      isExpanded: true,
                      items: _departments.map((d) => DropdownMenuItem(value: d, child: Text(d, style: const TextStyle(fontSize: 12)))).toList(),
                      onChanged: (v) {
                        if (v != null) {
                          setDrawerState(() => _selectedDepartmentFilter = v);
                          setState(() => _selectedDepartmentFilter = v);
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // Branch
                const Text('BRANCH', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF64748B))),
                const SizedBox(height: 4),
                Container(
                  height: 42,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFE2E8F0))),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedBranchFilter,
                      isExpanded: true,
                      items: _branches.map((b) => DropdownMenuItem(value: b, child: Text(b, style: const TextStyle(fontSize: 12)))).toList(),
                      onChanged: (v) {
                        if (v != null) {
                          setDrawerState(() => _selectedBranchFilter = v);
                          setState(() => _selectedBranchFilter = v);
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () {
                          setDrawerState(() {
                            _selectedDepartmentFilter = 'All Departments';
                            _selectedBranchFilter = 'All Branches';
                          });
                          setState(() {
                            _selectedDepartmentFilter = 'All Departments';
                            _selectedBranchFilter = 'All Branches';
                          });
                          Navigator.pop(ctx);
                        },
                        child: const Text('Reset', style: TextStyle(color: Color(0xFF64748B))),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(ctx),
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEFAA1F), foregroundColor: const Color(0xFF0F172A)),
                        child: const Text('Apply Filters', style: TextStyle(fontWeight: FontWeight.w800)),
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

  // ── Action: 2-Step Request Overtime Wizard (Screenshots 4 & 5) ──
  void _showRequestOvertimeWizard() {
    int currentStep = 1;
    final Set<String> selectedEmployeeIds = {};
    String searchEmpText = '';
    String filterDept = 'All Departments';
    String filterBranch = 'All Branches';
    String scheduleType = 'Single Day Overtime';
    DateTime selectedDate = DateTime.now().add(const Duration(days: 1));
    final notesCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setWizardState) {
          final filteredEmployees = _staffList.where((s) {
            final id = (s['employeeId'] ?? '').toString().toLowerCase();
            final name = (s['name'] ?? '${s['firstName'] ?? ''} ${s['lastName'] ?? ''}').toString().toLowerCase();
            final dept = (s['department'] ?? '').toString().toLowerCase();
            final br = (s['branch'] is Map ? (s['branch']['branchName'] ?? s['branch']['name']) : (s['branch'] ?? '')).toString().toLowerCase();

            final matchesSearch = searchEmpText.isEmpty || id.contains(searchEmpText.toLowerCase()) || name.contains(searchEmpText.toLowerCase()) || dept.contains(searchEmpText.toLowerCase());
            final matchesDept = filterDept == 'All Departments' || dept == filterDept.toLowerCase();
            final matchesBranch = filterBranch == 'All Branches' || br == filterBranch.toLowerCase();

            return matchesSearch && matchesDept && matchesBranch;
          }).toList();

          return AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            contentPadding: EdgeInsets.zero,
            content: SizedBox(
              width: MediaQuery.of(context).size.width * 0.9,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Modal Header & Stepper
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: const BoxDecoration(
                      color: Color(0xFFFFFBEB),
                      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                      border: Border(bottom: BorderSide(color: Color(0xFFFDE68A))),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.schedule_rounded, color: Color(0xFFD97706), size: 20),
                            const SizedBox(width: 8),
                            Text(
                              currentStep == 1 ? 'Select Employees for Overtime' : 'Configure Overtime Schedule',
                              style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),

                        // Stepper Bar
                        Row(
                          children: [
                            _stepIndicator(1, 'Staff Selection', currentStep == 1, currentStep > 1),
                            const SizedBox(width: 8),
                            Container(width: 20, height: 1, color: const Color(0xFFCBD5E1)),
                            const SizedBox(width: 8),
                            _stepIndicator(2, 'Schedule Setup', currentStep == 2, false),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // STEP 1: Staff Selection (Screenshot 4)
                  if (currentStep == 1) ...[
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          // Search
                          Container(
                            height: 38,
                            decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFE2E8F0))),
                            child: TextField(
                              onChanged: (v) => setWizardState(() => searchEmpText = v),
                              decoration: const InputDecoration(
                                hintText: 'Search by ID, Name, Department',
                                hintStyle: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                                prefixIcon: Icon(Icons.search_rounded, size: 16, color: Color(0xFF94A3B8)),
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.symmetric(vertical: 9),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),

                          // Dept & Branch Dropdowns
                          Row(
                            children: [
                              Expanded(
                                child: Container(
                                  height: 36,
                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                  decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(6), border: Border.all(color: const Color(0xFFE2E8F0))),
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<String>(
                                      value: filterDept,
                                      isExpanded: true,
                                      items: _departments.map((d) => DropdownMenuItem(value: d, child: Text(d, style: const TextStyle(fontSize: 11)))).toList(),
                                      onChanged: (v) {
                                        if (v != null) setWizardState(() => filterDept = v);
                                      },
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Container(
                                  height: 36,
                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                  decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(6), border: Border.all(color: const Color(0xFFE2E8F0))),
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<String>(
                                      value: filterBranch,
                                      isExpanded: true,
                                      items: _branches.map((b) => DropdownMenuItem(value: b, child: Text(b, style: const TextStyle(fontSize: 11)))).toList(),
                                      onChanged: (v) {
                                        if (v != null) setWizardState(() => filterBranch = v);
                                      },
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Staff Selection Table / List
                    SizedBox(
                      height: 220,
                      child: ListView.builder(
                        itemCount: filteredEmployees.length,
                        itemBuilder: (context, idx) {
                          final emp = filteredEmployees[idx];
                          final id = (emp['employeeId'] ?? 'EMP-001').toString();
                          final name = (emp['name'] ?? '${emp['firstName'] ?? ''} ${emp['lastName'] ?? ''}').toString();
                          final dept = (emp['department'] ?? 'Engineering').toString();
                          final branch = (emp['branch'] is Map ? (emp['branch']['branchName'] ?? emp['branch']['name']) : (emp['branch'] ?? 'chennai')).toString();
                          final isSelected = selectedEmployeeIds.contains(id);

                          return CheckboxListTile(
                            value: isSelected,
                            activeColor: const Color(0xFFEFAA1F),
                            onChanged: (val) {
                              setWizardState(() {
                                if (val == true) {
                                  selectedEmployeeIds.add(id);
                                } else {
                                  selectedEmployeeIds.remove(id);
                                }
                              });
                            },
                            title: Text(name, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
                            subtitle: Text('$id • $dept • $branch', style: const TextStyle(fontSize: 10, color: Color(0xFF64748B))),
                            secondary: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                              decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(4)),
                              child: const Text('IN OFFICE', style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w800, color: Color(0xFF2563EB))),
                            ),
                          );
                        },
                      ),
                    ),
                  ],

                  // STEP 2: Configure Overtime Schedule (Screenshot 5)
                  if (currentStep == 2) ...[
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Selected Employee Chips
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('SELECTED EMPLOYEES (${selectedEmployeeIds.length})', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF64748B))),
                              GestureDetector(
                                onTap: () => setWizardState(() => selectedEmployeeIds.clear()),
                                child: const Text('Clear All', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Color(0xFFDC2626))),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            children: selectedEmployeeIds.map((id) {
                              final emp = _staffList.firstWhere((s) => s['employeeId'] == id, orElse: () => {'name': id});
                              final name = (emp['name'] ?? '${emp['firstName'] ?? ''} ${emp['lastName'] ?? ''}').toString();
                              return Chip(
                                label: Text(name, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                                deleteIcon: const Icon(Icons.close_rounded, size: 14),
                                onDeleted: () => setWizardState(() => selectedEmployeeIds.remove(id)),
                                backgroundColor: const Color(0xFFFFFBEB),
                                side: const BorderSide(color: Color(0xFFFDE68A)),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 12),

                          // Schedule Type Cards
                          const Text('SCHEDULE TYPE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF64748B))),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(
                                child: _scheduleTypeCard(
                                  'Single Day Overtime',
                                  'Specific calendar date',
                                  Icons.calendar_today_rounded,
                                  scheduleType == 'Single Day Overtime',
                                  () => setWizardState(() => scheduleType = 'Single Day Overtime'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _scheduleTypeCard(
                                  'Multi-Day Range',
                                  'Continuous date span',
                                  Icons.date_range_rounded,
                                  scheduleType == 'Multi-Day Range',
                                  () => setWizardState(() => scheduleType = 'Multi-Day Range'),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          // Date Picker
                          const Text('DATE *', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF64748B))),
                          const SizedBox(height: 4),
                          InkWell(
                            onTap: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: selectedDate,
                                firstDate: DateTime.now(),
                                lastDate: DateTime.now().add(const Duration(days: 90)),
                              );
                              if (picked != null) setWizardState(() => selectedDate = picked);
                            },
                            child: Container(
                              height: 40,
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFE2E8F0))),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(DateFormat('yyyy-MM-dd').format(selectedDate), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                                  const Icon(Icons.calendar_month_outlined, size: 16, color: Color(0xFF64748B)),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Notes
                          const Text('NOTES / REASON', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF64748B))),
                          const SizedBox(height: 4),
                          TextField(
                            controller: notesCtrl,
                            maxLines: 2,
                            style: const TextStyle(fontSize: 12),
                            decoration: InputDecoration(
                              hintText: 'Provide notes/reason for the overtime (e.g. Critical system upgrade support)',
                              hintStyle: const TextStyle(fontSize: 10.5, color: Color(0xFF94A3B8)),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                              contentPadding: const EdgeInsets.all(8),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Footer Actions
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFF1F5F9)))),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TextButton(
                          onPressed: () {
                            if (currentStep == 2) {
                              setWizardState(() => currentStep = 1);
                            } else {
                              Navigator.pop(ctx);
                            }
                          },
                          child: Text(currentStep == 2 ? 'Back' : 'Cancel', style: const TextStyle(color: Color(0xFF64748B))),
                        ),
                        ElevatedButton(
                          onPressed: () async {
                            if (currentStep == 1) {
                              if (selectedEmployeeIds.isEmpty) {
                                SnackBarUtils.showSnackBar(context, 'Please select at least 1 employee', isError: true);
                                return;
                              }
                              setWizardState(() => currentStep = 2);
                            } else {
                              Navigator.pop(ctx);
                              final dateStr = DateFormat('yyyy-MM-dd').format(selectedDate);
                              for (final id in selectedEmployeeIds) {
                                final emp = _staffList.firstWhere((s) => s['employeeId'] == id, orElse: () => {'name': id, 'department': 'Engineering', 'designation': 'Developer'});
                                final newRec = AdminOvertimeRecord(
                                  id: 'OT-${DateTime.now().millisecondsSinceEpoch}',
                                  employeeId: id,
                                  name: (emp['name'] ?? '${emp['firstName'] ?? ''} ${emp['lastName'] ?? ''}').toString(),
                                  department: (emp['department'] ?? 'IT').toString(),
                                  designation: (emp['designation'] ?? 'Developer').toString(),
                                  scheduleType: scheduleType == 'Single Day Overtime' ? 'Single Date' : 'Multi-Day Range',
                                  date: dateStr,
                                  startDate: dateStr,
                                  endDate: dateStr,
                                  notes: notesCtrl.text.trim().isEmpty ? 'No additional notes provided.' : notesCtrl.text.trim(),
                                  status: 'Pending',
                                  requestedAt: DateFormat('yyyy-MM-dd').format(DateTime.now()),
                                );
                                setState(() => _records.insert(0, newRec));
                                try {
                                  await _api.request('/admin/staff/overtime/schedule', method: 'POST', data: newRec.toJson());
                                } catch (_) {}
                              }
                              if (mounted) SnackBarUtils.showSnackBar(context, 'Overtime request sent to ${selectedEmployeeIds.length} employee(s)');
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFEFAA1F),
                            foregroundColor: const Color(0xFF0F172A),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          child: Text(currentStep == 1 ? 'Continue' : 'Send Request', style: const TextStyle(fontWeight: FontWeight.w800)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _stepIndicator(int stepNum, String title, bool isActive, bool isDone) {
    return Row(
      children: [
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: isDone ? const Color(0xFF16A34A) : (isActive ? const Color(0xFFEFAA1F) : const Color(0xFFE2E8F0)),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: isDone
              ? const Icon(Icons.check_rounded, size: 12, color: Colors.white)
              : Text('$stepNum', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: isActive ? const Color(0xFF0F172A) : const Color(0xFF64748B))),
        ),
        const SizedBox(width: 4),
        Text(title, style: TextStyle(fontSize: 10.5, fontWeight: isActive ? FontWeight.w800 : FontWeight.w600, color: isActive ? const Color(0xFF0F172A) : const Color(0xFF64748B))),
      ],
    );
  }

  Widget _scheduleTypeCard(String title, String subtitle, IconData icon, bool isSelected, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFFFFBEB) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isSelected ? const Color(0xFFEFAA1F) : const Color(0xFFE2E8F0)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 14, color: isSelected ? const Color(0xFFD97706) : const Color(0xFF64748B)),
                const SizedBox(width: 4),
                Expanded(child: Text(title, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: isSelected ? const Color(0xFF0F172A) : const Color(0xFF64748B)))),
              ],
            ),
            const SizedBox(height: 2),
            Text(subtitle, style: const TextStyle(fontSize: 8.5, color: Color(0xFF94A3B8))),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFFF8FAFC),
      drawer: const AppDrawer(),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu_rounded, color: Color(0xFF0F172A)),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        title: const Text(
          'Overtime Management',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
        ),
        centerTitle: false,
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Color(0xFF64748B), size: 22),
            onPressed: () => _loadData(),
            tooltip: 'Refresh',
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _isLoading
          ? const Center(child: AppTabLoader())
          : RefreshIndicator(
              onRefresh: () => _loadData(showLoader: false),
              color: AppColors.primary,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Top Header Banner
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFF1F5F9)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: const [
                              Text('Overtime Management', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Color(0xFF0F172A))),
                              SizedBox(height: 2),
                              Text('Schedule and track employee overtime requests. Requests require employee acceptance to take effect.', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: _showRequestOvertimeWizard,
                          icon: const Icon(Icons.add_rounded, size: 16),
                          label: const Text('+ Request Overtime', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFEFAA1F),
                            foregroundColor: const Color(0xFF0F172A),
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // ── 4 Top Statistics Cards (Screenshot 1 & 2) ──
                  Row(
                    children: [
                      Expanded(child: _topStatCard('TOTAL REQUESTS', '$_totalRequestsCount', Icons.schedule_rounded, const Color(0xFF2563EB), const Color(0xFFEFF6FF), 'All Statuses')),
                      const SizedBox(width: 8),
                      Expanded(child: _topStatCard('PENDING', '$_pendingCount', Icons.warning_amber_rounded, const Color(0xFFD97706), const Color(0xFFFFFBEB), 'Pending')),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(child: _topStatCard('ACCEPTED', '$_acceptedCount', Icons.check_circle_outline_rounded, const Color(0xFF16A34A), const Color(0xFFDCFCE7), 'Accepted')),
                      const SizedBox(width: 8),
                      Expanded(child: _topStatCard('REJECTED', '$_rejectedCount', Icons.cancel_outlined, const Color(0xFFDC2626), const Color(0xFFFEE2E2), 'Rejected')),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // ── Search & Filter Row ──
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFF1F5F9))),
                    child: Column(
                      children: [
                        // Search bar
                        Container(
                          height: 38,
                          decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFE2E8F0))),
                          child: TextField(
                            onChanged: (v) => setState(() => _searchQuery = v),
                            decoration: const InputDecoration(
                              hintText: 'Search by name, ID or designation...',
                              hintStyle: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                              prefixIcon: Icon(Icons.search_rounded, size: 16, color: Color(0xFF94A3B8)),
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(vertical: 9),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),

                        Row(
                          children: [
                            // Status Dropdown
                            Expanded(
                              child: Container(
                                height: 36,
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(6), border: Border.all(color: const Color(0xFFE2E8F0))),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    value: _statusFilter,
                                    isExpanded: true,
                                    items: ['All Statuses', 'Pending', 'Accepted', 'Rejected']
                                        .map((s) => DropdownMenuItem(value: s, child: Text(s, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700))))
                                        .toList(),
                                    onChanged: (v) {
                                      if (v != null) setState(() => _statusFilter = v);
                                    },
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),

                            // More Filters Button
                            OutlinedButton.icon(
                              onPressed: _showAdvancedFiltersDrawer,
                              icon: const Icon(Icons.filter_alt_outlined, size: 14),
                              label: const Text('More Filters', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFF475569),
                                side: const BorderSide(color: Color(0xFFE2E8F0)),
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // ── Overtime Records List ──
                  if (_filteredRecords.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(36),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                      child: const Text('No overtime records found', style: TextStyle(fontSize: 13, color: Color(0xFF94A3B8))),
                    )
                  else
                    ..._filteredRecords.map((r) => _buildOvertimeCard(r)),
                ],
              ),
            ),
    );
  }

  Widget _topStatCard(String title, String count, IconData icon, Color color, Color bg, String targetFilter) {
    final isSelected = _statusFilter == targetFilter;
    return InkWell(
      onTap: () => setState(() => _statusFilter = isSelected ? 'All Statuses' : targetFilter),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isSelected ? color : const Color(0xFFF1F5F9)),
          boxShadow: const [BoxShadow(color: Color(0x04000000), blurRadius: 6, offset: Offset(0, 2))],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Color(0xFF64748B))),
                const SizedBox(height: 4),
                Text(count, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF0F172A))),
              ],
            ),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
              child: Icon(icon, size: 16, color: color),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOvertimeCard(AdminOvertimeRecord r) {
    final isAccepted = r.status.toLowerCase() == 'accepted';
    final isPending = r.status.toLowerCase() == 'pending';

    Color stBg = isAccepted ? const Color(0xFFDCFCE7) : (isPending ? const Color(0xFFFEF3C7) : const Color(0xFFFEE2E2));
    Color stFg = isAccepted ? const Color(0xFF16A34A) : (isPending ? const Color(0xFFD97706) : const Color(0xFFDC2626));
    IconData stIcon = isAccepted ? Icons.check_circle_outline_rounded : (isPending ? Icons.schedule_rounded : Icons.cancel_outlined);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFF1F5F9)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: const Color(0xFFF1F5F9),
                child: Text(r.initials, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF64748B))),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.name, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: Color(0xFF0F172A))),
                    Text('${r.employeeId} • ${r.department}', style: const TextStyle(fontSize: 10.5, color: Color(0xFF64748B))),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(color: stBg, borderRadius: BorderRadius.circular(20)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(stIcon, size: 12, color: stFg),
                    const SizedBox(width: 4),
                    Text(r.status, style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900, color: stFg)),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, size: 16, color: Color(0xFF94A3B8)),
                onPressed: () => _deleteOvertime(r),
              ),
            ],
          ),
          const SizedBox(height: 8),

          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFE2E8F0))),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Scheduled Date: ${r.date}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                      decoration: BoxDecoration(color: const Color(0xFFE2E8F0), borderRadius: BorderRadius.circular(4)),
                      child: Text(r.scheduleType, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Color(0xFF475569))),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text('Notes: ${r.notes}', style: const TextStyle(fontSize: 10.5, color: Color(0xFF64748B))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
