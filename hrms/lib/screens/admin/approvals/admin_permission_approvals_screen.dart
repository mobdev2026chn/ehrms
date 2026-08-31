// lib/screens/admin/approvals/admin_permission_approvals_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../config/app_colors.dart';
import '../../../services/api_client.dart';
import '../../../utils/snackbar_utils.dart';
import '../../../widgets/app_drawer.dart';
import '../../../widgets/app_tab_loader.dart';

class AdminPermissionRecord {
  final String id;
  final String requestId;
  final String employeeId;
  final String name;
  final String department;
  final String designation;
  final String date;
  final String type; // 'Late' | 'Early' | 'Custom'
  final String durationText;
  final int durationMins;
  String status; // 'Approved' | 'Pending' | 'Rejected' | 'Cancelled'
  final String approvedBy;
  final String reason;
  final String remarks;

  AdminPermissionRecord({
    required this.id,
    required this.requestId,
    required this.employeeId,
    required this.name,
    required this.department,
    required this.designation,
    required this.date,
    required this.type,
    required this.durationText,
    this.durationMins = 30,
    required this.status,
    this.approvedBy = 'Admin',
    this.reason = '',
    this.remarks = '',
  });

  String get initials {
    final parts = name.trim().split(' ');
    if (parts.length > 1) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name.isNotEmpty ? name[0].toUpperCase() : 'U';
  }

  factory AdminPermissionRecord.fromJson(Map<String, dynamic> json) {
    final staffObj = json['staffId'] is Map ? json['staffId'] : json;
    final pType = (json['type'] ?? json['permissionType'] ?? 'Late').toString();
    final dMins = int.tryParse((json['durationMins'] ?? '30').toString()) ?? 30;

    String dText = (json['durationText'] ?? '').toString();
    if (dText.isEmpty) {
      if (pType == 'Late') {
        dText = 'Late: ${dMins}m';
      } else if (pType == 'Early') {
        dText = 'Early: ${dMins >= 60 ? "${(dMins / 60).toStringAsFixed(0)}h" : "${dMins}m"}';
      } else {
        dText = 'Custom: ${dMins}m';
      }
    }

    return AdminPermissionRecord(
      id: (json['_id'] ?? json['id'] ?? '').toString(),
      requestId: (json['requestId'] ?? 'PM-${(json['_id'] ?? json['id'] ?? '001').toString().toUpperCase().padLeft(3, '0')}').toString(),
      employeeId: (staffObj['employeeId'] ?? json['employeeId'] ?? 'EMP-007').toString(),
      name: (staffObj['name'] ?? '${staffObj['firstName'] ?? ''} ${staffObj['lastName'] ?? ''}'.trim()).toString().isNotEmpty
          ? (staffObj['name'] ?? '${staffObj['firstName'] ?? ''} ${staffObj['lastName'] ?? ''}'.trim()).toString()
          : (json['name'] ?? 'personal notouch').toString(),
      department: (staffObj['department'] is Map ? staffObj['department']['name'] : (staffObj['department'] ?? json['department'] ?? 'Engineering')).toString(),
      designation: (staffObj['designation'] is Map ? staffObj['designation']['name'] : (staffObj['designation'] ?? json['designation'] ?? 'Staff')).toString(),
      date: (json['date'] ?? json['permissionDate'] ?? 'Aug 28, 2026').toString(),
      type: pType,
      durationText: dText,
      durationMins: dMins,
      status: (json['status'] ?? 'Approved').toString(),
      approvedBy: (json['approvedBy'] ?? (json['status'] == 'Approved' ? 'Admin' : '—')).toString(),
      reason: (json['reason'] ?? 's').toString(),
      remarks: (json['remarks'] ?? '').toString(),
    );
  }
}

class AdminPermissionApprovalsScreen extends StatefulWidget {
  const AdminPermissionApprovalsScreen({super.key});

  @override
  State<AdminPermissionApprovalsScreen> createState() => _AdminPermissionApprovalsScreenState();
}

class _AdminPermissionApprovalsScreenState extends State<AdminPermissionApprovalsScreen> with SingleTickerProviderStateMixin {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final ApiClient _api = ApiClient();

  late TabController _tabController;
  bool _isLoading = true;
  String _searchQuery = '';
  String _timelineFilter = 'All Time'; // 'All Time' | 'Upcoming' | 'Past Only'
  String _statusFilter = 'All Statuses'; // 'All Statuses' | 'Pending' | 'Approved' | 'Rejected' | 'Cancelled'
  String _startDateFilter = '';
  String _endDateFilter = '';
  String _sortOrder = 'Newest First (Descending)';

  DateTime _calendarMonth = DateTime(2026, 8, 1);
  List<AdminPermissionRecord> _records = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData({bool showLoader = true}) async {
    if (showLoader && mounted) setState(() => _isLoading = true);

    try {
      final res = await _api.request(
        '/admin/staff/approvals/permission',
        queryParameters: {
          'search': _searchQuery.isNotEmpty ? _searchQuery : null,
          'status': _statusFilter != 'All Statuses' ? _statusFilter : null,
          'tab': _timelineFilter == 'Upcoming' ? 'upcoming' : (_timelineFilter == 'Past Only' ? 'previous' : null),
        },
      );

      if (res.data is Map && res.data['success'] == true) {
        final list = (res.data['data']?['requests'] as List?) ?? (res.data['data'] as List?) ?? [];
        if (list.isNotEmpty && mounted) {
          setState(() {
            _records = list.map((e) => AdminPermissionRecord.fromJson(Map<String, dynamic>.from(e as Map))).toList();
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
      AdminPermissionRecord(
        id: 'PM-001',
        requestId: 'PM-001',
        employeeId: 'EMP-007',
        name: 'personal notouch',
        department: 'Engineering',
        designation: 'Staff',
        date: 'Aug 28, 2026',
        type: 'Late',
        durationText: 'Late: 30m',
        durationMins: 30,
        status: 'Approved',
        approvedBy: 'Admin',
        reason: 's',
      ),
      AdminPermissionRecord(
        id: 'PM-002',
        requestId: 'PM-002',
        employeeId: 'EMP-007',
        name: 'personal notouch',
        department: 'Engineering',
        designation: 'Staff',
        date: 'Aug 29, 2026',
        type: 'Late',
        durationText: 'Late: 30m',
        durationMins: 30,
        status: 'Approved',
        approvedBy: 'Admin',
        reason: '1',
      ),
      AdminPermissionRecord(
        id: 'PM-003',
        requestId: 'PM-003',
        employeeId: 'EMP-007',
        name: 'personal notouch',
        department: 'Engineering',
        designation: 'Staff',
        date: 'Aug 31, 2026',
        type: 'Late',
        durationText: 'Late: 30m',
        durationMins: 30,
        status: 'Approved',
        approvedBy: 'Admin',
        reason: 'a',
      ),
      AdminPermissionRecord(
        id: 'PM-004',
        requestId: 'PM-004',
        employeeId: 'EMP-006',
        name: 'hp haith',
        department: 'IT',
        designation: 'Manager',
        date: 'Aug 28, 2026',
        type: 'Late',
        durationText: 'Late: 1m',
        durationMins: 1,
        status: 'Approved',
        approvedBy: 'Admin',
        reason: 'e',
      ),
      AdminPermissionRecord(
        id: 'PM-005',
        requestId: 'PM-005',
        employeeId: 'EMP-002',
        name: 'james fernado',
        department: 'IT',
        designation: 'Developer',
        date: 'Aug 26, 2026',
        type: 'Early',
        durationText: 'Early: 1h',
        durationMins: 60,
        status: 'Approved',
        approvedBy: 'Admin',
        reason: 'fcgb',
      ),
      AdminPermissionRecord(
        id: 'PM-006',
        requestId: 'PM-006',
        employeeId: 'EMP-002',
        name: 'james fernado',
        department: 'IT',
        designation: 'Developer',
        date: 'Aug 26, 2026',
        type: 'Custom',
        durationText: 'Early: 30m',
        durationMins: 30,
        status: 'Rejected',
        approvedBy: '—',
        reason: 'hyiikl',
        remarks: 'no',
      ),
      AdminPermissionRecord(
        id: 'PM-007',
        requestId: 'PM-007',
        employeeId: 'EMP-002',
        name: 'james fernado',
        department: 'IT',
        designation: 'Developer',
        date: 'Aug 25, 2026',
        type: 'Early',
        durationText: 'Early: 3h',
        durationMins: 180,
        status: 'Approved',
        approvedBy: 'Admin',
        reason: 'ghn',
      ),
    ];
  }

  List<AdminPermissionRecord> get _filteredRecords {
    return _records.where((r) {
      final matchesSearch = _searchQuery.isEmpty ||
          r.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          r.employeeId.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          r.reason.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          r.type.toLowerCase().contains(_searchQuery.toLowerCase());

      final matchesStatus = _statusFilter == 'All Statuses' || r.status.toLowerCase() == _statusFilter.toLowerCase();

      return matchesSearch && matchesStatus;
    }).toList();
  }

  // ── Action: View Permission Details Modal (Screenshot 3) ──
  void _showPermissionDetailModal(AdminPermissionRecord r) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        contentPadding: const EdgeInsets.all(20),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(color: const Color(0xFFFFFBEB), borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.description_outlined, color: Color(0xFFD97706), size: 18),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Permission Details', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF0F172A))),
                      Text(r.requestId, style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8))),
                    ],
                  ),
                ),
                IconButton(icon: const Icon(Icons.close_rounded, size: 18), onPressed: () => Navigator.pop(ctx)),
              ],
            ),
            const SizedBox(height: 14),

            // Staff Info
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFE2E8F0))),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: const Color(0xFFEFF6FF),
                    child: Text(r.initials, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF2563EB))),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r.name, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: Color(0xFF0F172A))),
                      Text('${r.employeeId} • ${r.department}', style: const TextStyle(fontSize: 10, color: Color(0xFF64748B))),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            _detailRow('PERMISSION TYPE', r.type),
            _detailRow('DURATION', '⏱ ${r.durationMins} Mins'),
            _detailRow('REQUESTED DATE', '📅 ${r.date}'),
            _detailRow('STATUS', r.status, isStatus: true),
            _detailRow('APPROVED BY', r.approvedBy),
            _detailRow('REASON', r.reason.isNotEmpty ? r.reason : '—'),
            _detailRow('REMARKS / NOTES', r.remarks.isNotEmpty ? r.remarks : 'No remarks provided.'),
            const SizedBox(height: 14),

            if (r.status == 'Pending')
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        setState(() => r.status = 'Rejected');
                        try {
                          await _api.request('/admin/staff/approvals/permission/${r.id}/reject', method: 'POST', data: {'reason': 'Rejected'});
                        } catch (_) {}
                        if (mounted) SnackBarUtils.showSnackBar(context, 'Permission request rejected');
                      },
                      style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFDC2626), side: const BorderSide(color: Color(0xFFFECACA))),
                      child: const Text('Reject', style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        setState(() => r.status = 'Approved');
                        try {
                          await _api.request('/admin/staff/approvals/permission/${r.id}/approve', method: 'POST', data: {'remarks': 'Approved'});
                        } catch (_) {}
                        if (mounted) SnackBarUtils.showSnackBar(context, 'Permission request approved');
                      },
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF16A34A), foregroundColor: Colors.white),
                      child: const Text('Approve', style: TextStyle(fontWeight: FontWeight.w800)),
                    ),
                  ),
                ],
              )
            else
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEFAA1F), foregroundColor: const Color(0xFF0F172A)),
                  child: const Text('Close Details', style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value, {bool isStatus = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF64748B))),
          if (isStatus)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: value == 'Approved' ? const Color(0xFFDCFCE7) : (value == 'Pending' ? const Color(0xFFFEF3C7) : const Color(0xFFFEE2E2)),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w900,
                  color: value == 'Approved' ? const Color(0xFF16A34A) : (value == 'Pending' ? const Color(0xFFD97706) : const Color(0xFFDC2626)),
                ),
              ),
            )
          else
            Text(value, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF0F172A))),
        ],
      ),
    );
  }

  // ── Action: Advanced Filters Slide-Over (Screenshot 5) ──
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
                        Text('ADVANCED FILTERS', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                      ],
                    ),
                    IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(ctx)),
                  ],
                ),
                const SizedBox(height: 14),

                // Permission Status (Screenshot 1)
                const Text('PERMISSION STATUS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF64748B))),
                const SizedBox(height: 4),
                _drawerDropdown(_statusFilter, ['All Statuses', 'Pending', 'Approved', 'Rejected', 'Cancelled'], (v) {
                  setDrawerState(() => _statusFilter = v);
                  setState(() => _statusFilter = v);
                }),
                const SizedBox(height: 12),

                // Start & End Date (Screenshot 1)
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('START DATE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF64748B))),
                          const SizedBox(height: 4),
                          InkWell(
                            onTap: () async {
                              final picked = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(2024), lastDate: DateTime(2028));
                              if (picked != null) {
                                final s = DateFormat('MM/dd/yyyy').format(picked);
                                setDrawerState(() => _startDateFilter = s);
                                setState(() => _startDateFilter = s);
                              }
                            },
                            child: Container(
                              height: 38,
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFE2E8F0))),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(_startDateFilter.isNotEmpty ? _startDateFilter : 'mm/dd/yyyy', style: TextStyle(fontSize: 11, color: _startDateFilter.isNotEmpty ? const Color(0xFF0F172A) : const Color(0xFF94A3B8))),
                                  const Icon(Icons.calendar_today_rounded, size: 14, color: Color(0xFF64748B)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('END DATE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF64748B))),
                          const SizedBox(height: 4),
                          InkWell(
                            onTap: () async {
                              final picked = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(2024), lastDate: DateTime(2028));
                              if (picked != null) {
                                final s = DateFormat('MM/dd/yyyy').format(picked);
                                setDrawerState(() => _endDateFilter = s);
                                setState(() => _endDateFilter = s);
                              }
                            },
                            child: Container(
                              height: 38,
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFE2E8F0))),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(_endDateFilter.isNotEmpty ? _endDateFilter : 'mm/dd/yyyy', style: TextStyle(fontSize: 11, color: _endDateFilter.isNotEmpty ? const Color(0xFF0F172A) : const Color(0xFF94A3B8))),
                                  const Icon(Icons.calendar_today_rounded, size: 14, color: Color(0xFF64748B)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Sort Order (Screenshot 2)
                const Text('SORT ORDER', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF64748B))),
                const SizedBox(height: 4),
                _drawerDropdown(_sortOrder, ['Newest First (Descending)', 'Oldest First (Ascending)'], (v) {
                  setDrawerState(() => _sortOrder = v);
                  setState(() => _sortOrder = v);
                }),
                const SizedBox(height: 20),

                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () {
                          setDrawerState(() {
                            _statusFilter = 'All Statuses';
                            _sortOrder = 'Newest First (Descending)';
                          });
                          setState(() {
                            _statusFilter = 'All Statuses';
                            _sortOrder = 'Newest First (Descending)';
                          });
                          Navigator.pop(ctx);
                        },
                        child: const Text('Clear All', style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w700)),
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

  Widget _drawerDropdown(String value, List<String> items, Function(String) onChanged) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFE2E8F0))),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: items.contains(value) ? value : items.first,
          isExpanded: true,
          items: items.map((i) => DropdownMenuItem(value: i, child: Text(i, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)))).toList(),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
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
          'Permission Requests',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
        ),
        centerTitle: false,
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        bottom: TabBar(
          controller: _tabController,
          labelColor: const Color(0xFFD97706),
          unselectedLabelColor: const Color(0xFF64748B),
          indicatorColor: const Color(0xFFEFAA1F),
          indicatorWeight: 3,
          labelStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
          tabs: [
            Tab(text: 'All Requests (${_records.length})'),
            const Tab(text: 'Permission Calendar'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: AppTabLoader())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildRequestsTab(),
                _buildCalendarTab(),
              ],
            ),
    );
  }

  // ── Tab 1: Requests List (Screenshots 1 & 2) ──
  Widget _buildRequestsTab() {
    return RefreshIndicator(
      onRefresh: () => _loadData(showLoader: false),
      color: AppColors.primary,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Search & Filter Row
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFF1F5F9))),
            child: Column(
              children: [
                // Search
                Container(
                  height: 38,
                  decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFE2E8F0))),
                  child: TextField(
                    onChanged: (v) => setState(() => _searchQuery = v),
                    decoration: const InputDecoration(
                      hintText: 'Search employee, ID, reason...',
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
                    // Timeline Dropdown (Screenshot 4)
                    Expanded(
                      child: Container(
                        height: 36,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(6), border: Border.all(color: const Color(0xFFE2E8F0))),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _timelineFilter,
                            isExpanded: true,
                            items: ['All Time', 'Upcoming', 'Past Only']
                                .map((t) => DropdownMenuItem(value: t, child: Text(t, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700))))
                                .toList(),
                            onChanged: (v) {
                              if (v != null) {
                                setState(() => _timelineFilter = v);
                                _loadData();
                              }
                            },
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Filters Button
                    OutlinedButton.icon(
                      onPressed: _showAdvancedFiltersDrawer,
                      icon: const Icon(Icons.filter_alt_outlined, size: 14),
                      label: const Text('Filters', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
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

          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('List of Permission Requests', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF0F172A))),
              Text('Showing ${_filteredRecords.length} requests', style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
            ],
          ),
          const SizedBox(height: 10),

          // Records List
          if (_filteredRecords.isEmpty)
            Container(
              padding: const EdgeInsets.all(36),
              alignment: Alignment.center,
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
              child: const Text('No permission requests found', style: TextStyle(fontSize: 13, color: Color(0xFF94A3B8))),
            )
          else
            ..._filteredRecords.map((r) => _buildPermissionCard(r)),
        ],
      ),
    );
  }

  Widget _buildPermissionCard(AdminPermissionRecord r) {
    final isApproved = r.status == 'Approved';
    final isPending = r.status == 'Pending';
    final isLate = r.type == 'Late';
    final isEarly = r.type == 'Early';

    Color typeBg = isLate ? const Color(0xFFFEF3C7) : (isEarly ? const Color(0xFFEFF6FF) : const Color(0xFFF3E8FF));
    Color typeFg = isLate ? const Color(0xFFD97706) : (isEarly ? const Color(0xFF2563EB) : const Color(0xFF7C3AED));

    return InkWell(
      onTap: () => _showPermissionDetailModal(r),
      child: Container(
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
                  backgroundColor: const Color(0xFFEFF6FF),
                  child: Text(r.initials, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF2563EB))),
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
                  decoration: BoxDecoration(
                    color: isApproved ? const Color(0xFFDCFCE7) : (isPending ? const Color(0xFFFEF3C7) : const Color(0xFFFEE2E2)),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(isApproved ? Icons.check_circle_outline_rounded : (isPending ? Icons.schedule_rounded : Icons.cancel_outlined), size: 11, color: isApproved ? const Color(0xFF16A34A) : (isPending ? const Color(0xFFD97706) : const Color(0xFFDC2626))),
                      const SizedBox(width: 4),
                      Text(r.status, style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900, color: isApproved ? const Color(0xFF16A34A) : (isPending ? const Color(0xFFD97706) : const Color(0xFFDC2626)))),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert_rounded, size: 18, color: Color(0xFF64748B)),
                  onSelected: (val) {
                    if (val == 'view') {
                      _showPermissionDetailModal(r);
                    }
                  },
                  itemBuilder: (ctx) => [
                    const PopupMenuItem(
                      value: 'view',
                      child: Row(
                        children: [
                          Icon(Icons.visibility_outlined, size: 16, color: Color(0xFF2563EB)),
                          SizedBox(width: 8),
                          Text('View Details', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),

            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFE2E8F0))),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Type
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: typeBg, borderRadius: BorderRadius.circular(4)),
                    child: Text(r.type, style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: typeFg)),
                  ),
                  // Duration
                  Text(r.durationText, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF1E293B))),
                  // Date
                  Text(r.date, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF64748B))),
                  // Reason
                  Text('Reason: ${r.reason}', style: const TextStyle(fontSize: 10.5, color: Color(0xFF64748B))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Tab 2: Permission Calendar ──
  Widget _buildCalendarTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFF1F5F9))),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: const [
                  Icon(Icons.calendar_month_outlined, color: Color(0xFFD97706), size: 18),
                  SizedBox(width: 6),
                  Text('Permission Calendar', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
                ],
              ),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left_rounded, size: 18),
                    onPressed: () => setState(() => _calendarMonth = DateTime(_calendarMonth.year, _calendarMonth.month - 1, 1)),
                  ),
                  Text(DateFormat('MMMM yyyy').format(_calendarMonth), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                  IconButton(
                    icon: const Icon(Icons.chevron_right_rounded, size: 18),
                    onPressed: () => setState(() => _calendarMonth = DateTime(_calendarMonth.year, _calendarMonth.month + 1, 1)),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        Row(
          children: ['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT'].map((d) {
            return Expanded(
              child: Center(child: Text(d, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF64748B)))),
            );
          }).toList(),
        ),
        // Grid of month days
        _buildCalendarGrid(),
        const SizedBox(height: 16),

        // Bottom Legend Bar (Screenshot 4)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Wrap(
            spacing: 12,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text('Legend:', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF64748B))),
              _legendItem('Late Arrival', const Color(0xFFD97706)),
              _legendItem('Early Leaving', const Color(0xFF2563EB)),
              _legendItem('Custom Break', const Color(0xFF7C3AED)),
              _legendItem('Rejected / Cancelled', const Color(0xFFDC2626)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _legendItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: Color(0xFF475569))),
      ],
    );
  }

  Widget _buildCalendarGrid() {
    final year = _calendarMonth.year;
    final month = _calendarMonth.month;
    final firstDayWeekday = DateTime(year, month, 1).weekday % 7;
    final totalDays = DateTime(year, month + 1, 0).day;

    final List<Widget> dayWidgets = [];

    for (int i = 0; i < firstDayWeekday; i++) {
      dayWidgets.add(Container(margin: const EdgeInsets.all(2), decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(6))));
    }

    for (int d = 1; d <= totalDays; d++) {
      final permsForDay = _records.where((r) => r.date.contains('$d,') || r.date.contains('$d ')).toList();

      dayWidgets.add(
        Container(
          margin: const EdgeInsets.all(2),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$d', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF0F172A))),
              if (permsForDay.isNotEmpty) ...[
                const SizedBox(height: 2),
                ...permsForDay.take(2).map((p) => InkWell(
                      onTap: () => _showPermissionDetailModal(p),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 1),
                        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
                        decoration: BoxDecoration(color: const Color(0xFFFEF3C7), borderRadius: BorderRadius.circular(2)),
                        child: Text(p.name, style: const TextStyle(fontSize: 7, fontWeight: FontWeight.w700, color: Color(0xFFD97706)), overflow: TextOverflow.ellipsis),
                      ),
                    )),
              ],
            ],
          ),
        ),
      );
    }

    return GridView.count(
      crossAxisCount: 7,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 0.85,
      children: dayWidgets,
    );
  }
}
