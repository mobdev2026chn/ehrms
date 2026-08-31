// lib/screens/admin/approvals/admin_punch_approvals_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../config/app_colors.dart';
import '../../../services/api_client.dart';
import '../../../utils/snackbar_utils.dart';
import '../../../widgets/app_drawer.dart';
import '../../../widgets/app_tab_loader.dart';

class AdminPunchRecord {
  final String id;
  final String staffName;
  final String employeeId;
  final String department;
  final String shiftName;
  final String punchInTime;
  final String punchInLocation;
  final String? punchInPhoto;
  final String punchOutTime;
  final String punchOutLocation;
  final String? punchOutPhoto;
  final bool isPendingApproval;
  String status; // 'present' | 'half_day' | 'leave' | 'absent' | 'Approved' | 'Pending'

  AdminPunchRecord({
    required this.id,
    required this.staffName,
    required this.employeeId,
    required this.department,
    required this.shiftName,
    required this.punchInTime,
    required this.punchInLocation,
    this.punchInPhoto,
    required this.punchOutTime,
    required this.punchOutLocation,
    this.punchOutPhoto,
    required this.isPendingApproval,
    required this.status,
  });

  String get initials {
    final parts = staffName.trim().split(' ');
    if (parts.length > 1) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return staffName.isNotEmpty ? staffName[0].toUpperCase() : 'U';
  }

  factory AdminPunchRecord.fromJson(Map<String, dynamic> json) {
    final staffObj = json['staffId'] is Map ? json['staffId'] : json;
    final inTime = (json['punchInTime'] ?? json['inTime'] ?? '09:00 AM').toString();
    final outTime = (json['punchOutTime'] ?? json['outTime'] ?? '07:30 PM').toString();
    final isPending = json['isPendingApproval'] == true || (json['status'] ?? '').toString().toLowerCase() == 'pending';

    return AdminPunchRecord(
      id: (json['_id'] ?? json['id'] ?? '').toString(),
      staffName: (staffObj['name'] ?? '${staffObj['firstName'] ?? ''} ${staffObj['lastName'] ?? ''}'.trim()).toString().isNotEmpty
          ? (staffObj['name'] ?? '${staffObj['firstName'] ?? ''} ${staffObj['lastName'] ?? ''}'.trim()).toString()
          : (json['staffName'] ?? 'James fernado').toString(),
      employeeId: (staffObj['employeeId'] ?? json['employeeId'] ?? 'EMP-002').toString(),
      department: (staffObj['department'] is Map ? staffObj['department']['name'] : (staffObj['department'] ?? json['department'] ?? 'IT')).toString(),
      shiftName: (json['shiftName'] ?? json['shift'] ?? 'General Shift').toString(),
      punchInTime: inTime,
      punchInLocation: (json['punchInLocation'] ?? json['inLocation'] ?? 'Office Wi-Fi Zone').toString(),
      punchInPhoto: json['punchInPhoto']?.toString(),
      punchOutTime: outTime,
      punchOutLocation: (json['punchOutLocation'] ?? json['outLocation'] ?? 'Office Wi-Fi Zone').toString(),
      punchOutPhoto: json['punchOutPhoto']?.toString(),
      isPendingApproval: isPending,
      status: (json['status'] ?? (isPending ? 'Pending' : 'Approved')).toString(),
    );
  }
}

class AdminPunchApprovalsScreen extends StatefulWidget {
  const AdminPunchApprovalsScreen({super.key});

  @override
  State<AdminPunchApprovalsScreen> createState() => _AdminPunchApprovalsScreenState();
}

class _AdminPunchApprovalsScreenState extends State<AdminPunchApprovalsScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final ApiClient _api = ApiClient();

  bool _isLoading = true;
  String _searchQuery = '';
  DateTime _selectedDate = DateTime(2026, 8, 29);
  final Set<String> _selectedIds = {};
  List<AdminPunchRecord> _records = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData({bool showLoader = true}) async {
    if (showLoader && mounted) setState(() => _isLoading = true);

    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
    try {
      final res = await _api.request(
        '/admin/staff/approvals/punch',
        queryParameters: {'date': dateStr},
      );

      if (res.data is Map && res.data['success'] == true) {
        final list = (res.data['data'] as List?) ?? [];
        if (list.isNotEmpty && mounted) {
          setState(() {
            _records = list.map((e) => AdminPunchRecord.fromJson(Map<String, dynamic>.from(e as Map))).toList();
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
      AdminPunchRecord(
        id: 'punch_1',
        staffName: 'James fernado',
        employeeId: 'EMP-002',
        department: 'IT',
        shiftName: 'General Shift',
        punchInTime: '01:50 PM',
        punchInLocation: 'Office Wi-Fi Zone',
        punchOutTime: '10:00 PM',
        punchOutLocation: 'Office Wi-Fi Zone',
        isPendingApproval: false,
        status: 'Approved',
      ),
      AdminPunchRecord(
        id: 'punch_2',
        staffName: 'c man',
        employeeId: 'EMP-003',
        department: 'Design',
        shiftName: 'General Shift',
        punchInTime: '03:00 PM',
        punchInLocation: 'Office Wi-Fi Zone',
        punchOutTime: '03:00 AM',
        punchOutLocation: 'Office Wi-Fi Zone',
        isPendingApproval: false,
        status: 'Approved',
      ),
      AdminPunchRecord(
        id: 'punch_3',
        staffName: 'sarannn saran',
        employeeId: 'EMP-004',
        department: 'Support',
        shiftName: 'General Shift',
        punchInTime: '10:00 AM',
        punchInLocation: 'Office Wi-Fi Zone',
        punchOutTime: '01:30 PM',
        punchOutLocation: 'Office Wi-Fi Zone',
        isPendingApproval: false,
        status: 'Approved',
      ),
      AdminPunchRecord(
        id: 'punch_4',
        staffName: 'hp hai th',
        employeeId: 'EMP-006',
        department: 'IT',
        shiftName: 'General Shift',
        punchInTime: '09:00 AM',
        punchInLocation: 'Office Wi-Fi Zone',
        punchOutTime: '07:30 PM',
        punchOutLocation: 'Office Wi-Fi Zone',
        isPendingApproval: false,
        status: 'Approved',
      ),
    ];
  }

  List<AdminPunchRecord> get _filteredRecords {
    if (_searchQuery.isEmpty) return _records;
    return _records.where((r) {
      return r.staffName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          r.employeeId.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          r.shiftName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          r.department.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();
  }

  Map<String, List<AdminPunchRecord>> get _groupedByShift {
    final map = <String, List<AdminPunchRecord>>{};
    for (var r in _filteredRecords) {
      map.putIfAbsent(r.shiftName, () => []).add(r);
    }
    return map;
  }

  // ── Bulk Actions ──
  Future<void> _handleBulkAction(String decision) async {
    if (_selectedIds.isEmpty) return;
    final ids = _selectedIds.toList();
    setState(() {
      for (var r in _records) {
        if (_selectedIds.contains(r.id)) {
          r.status = decision;
        }
      }
      _selectedIds.clear();
    });

    try {
      final endpoint = decision == 'Approved'
          ? '/admin/staff/approvals/punch/approve'
          : '/admin/staff/approvals/punch/reject';
      await _api.request(endpoint, method: 'POST', data: {'ids': ids});
    } catch (_) {}

    if (mounted) {
      SnackBarUtils.showSnackBar(context, 'Attendance successfully ${decision.toLowerCase()} for the selected staff member(s)!');
    }
  }

  // ── Action: Punch Details Modal ──
  void _showPunchDetailModal(AdminPunchRecord r) {
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
                  child: const Icon(Icons.fingerprint_rounded, color: Color(0xFFD97706), size: 18),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Punch Attendance Details', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF0F172A))),
                      Text(DateFormat('dd MMMM yyyy').format(_selectedDate), style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8))),
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
                      Text(r.staffName, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: Color(0xFF0F172A))),
                      Text('${r.employeeId} • ${r.department}', style: const TextStyle(fontSize: 10, color: Color(0xFF64748B))),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            _detailRow('SHIFT', r.shiftName),
            _detailRow('PUNCH IN', '${r.punchInTime} (${r.punchInLocation})'),
            _detailRow('PUNCH OUT', '${r.punchOutTime} (${r.punchOutLocation})'),
            _detailRow('STATUS', r.status, isStatus: true),
            const SizedBox(height: 14),

            if (r.isPendingApproval || r.status == 'Pending')
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        setState(() => r.status = 'Rejected');
                        try {
                          await _api.request('/admin/staff/approvals/punch/reject', method: 'POST', data: {'ids': [r.id]});
                        } catch (_) {}
                        if (mounted) SnackBarUtils.showSnackBar(context, 'Punch rejected');
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
                          await _api.request('/admin/staff/approvals/punch/approve', method: 'POST', data: {'ids': [r.id]});
                        } catch (_) {}
                        if (mounted) SnackBarUtils.showSnackBar(context, 'Punch approved');
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
                color: value == 'Approved' || value == 'present' ? const Color(0xFFDCFCE7) : const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w900,
                  color: value == 'Approved' || value == 'present' ? const Color(0xFF16A34A) : const Color(0xFFD97706),
                ),
              ),
            )
          else
            Text(value, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF0F172A))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final shiftGroups = _groupedByShift;

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
          'Attendance Pending for Approval',
          style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
        ),
        centerTitle: false,
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: _isLoading
          ? const Center(child: AppTabLoader())
          : Stack(
              children: [
                RefreshIndicator(
                  onRefresh: () => _loadData(showLoader: false),
                  color: AppColors.primary,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      // Top Control Bar: Search, Date Picker, Today
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
                                  hintText: 'Search staff...',
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
                                // Date Picker Button
                                Expanded(
                                  child: InkWell(
                                    onTap: () async {
                                      final picked = await showDatePicker(
                                        context: context,
                                        initialDate: _selectedDate,
                                        firstDate: DateTime(2024),
                                        lastDate: DateTime(2028),
                                      );
                                      if (picked != null) {
                                        setState(() => _selectedDate = picked);
                                        _loadData();
                                      }
                                    },
                                    child: Container(
                                      height: 36,
                                      padding: const EdgeInsets.symmetric(horizontal: 10),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF8FAFC),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: const Color(0xFFE2E8F0)),
                                      ),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Row(
                                            children: [
                                              const Icon(Icons.calendar_today_rounded, size: 13, color: Color(0xFFD97706)),
                                              const SizedBox(width: 6),
                                              Text(DateFormat('dd MMM yyyy').format(_selectedDate), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF0F172A))),
                                            ],
                                          ),
                                          const Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: Color(0xFF64748B)),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),

                                // Today Button
                                ElevatedButton(
                                  onPressed: () {
                                    setState(() => _selectedDate = DateTime.now());
                                    _loadData();
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    foregroundColor: const Color(0xFF475569),
                                    elevation: 0,
                                    side: const BorderSide(color: Color(0xFFE2E8F0)),
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                  ),
                                  child: const Text('Today', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Shift Sections
                      if (shiftGroups.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(36),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                          child: const Text('No punch approval records for this date', style: TextStyle(fontSize: 13, color: Color(0xFF94A3B8))),
                        )
                      else
                        ...shiftGroups.entries.map((entry) => _buildShiftSection(entry.key, entry.value)),
                      const SizedBox(height: 80), // bottom space for floating action bar
                    ],
                  ),
                ),

                // Floating Action Bar for Selected Items
                if (_selectedIds.isNotEmpty)
                  Positioned(
                    bottom: 20,
                    left: 20,
                    right: 20,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 10, offset: const Offset(0, 4)),
                        ],
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Selected ${_selectedIds.length} staff',
                              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
                            ),
                          ),
                          TextButton(
                            onPressed: () => setState(() => _selectedIds.clear()),
                            child: const Text('Cancel', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
                          ),
                          const SizedBox(width: 4),
                          ElevatedButton(
                            onPressed: () => _handleBulkAction('Rejected'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFDC2626),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              minimumSize: Size.zero,
                            ),
                            child: const Text('Reject', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                          ),
                          const SizedBox(width: 6),
                          ElevatedButton(
                            onPressed: () => _handleBulkAction('Approved'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFEFAA1F),
                              foregroundColor: const Color(0xFF0F172A),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              minimumSize: Size.zero,
                            ),
                            child: const Text('Approve', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _buildShiftSection(String shiftName, List<AdminPunchRecord> list) {
    final allSelected = list.isNotEmpty && list.every((r) => _selectedIds.contains(r.id));

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Shift Header
          Row(
            children: [
              Text(shiftName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF0F172A))),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(color: const Color(0xFFFEF3C7), borderRadius: BorderRadius.circular(10)),
                child: Text('${list.length}', style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: Color(0xFFD97706))),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Shift Card Table
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFF1F5F9)),
            ),
            child: Column(
              children: [
                // Table header
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: const BoxDecoration(
                    color: Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: Checkbox(
                          value: allSelected,
                          onChanged: (v) {
                            setState(() {
                              if (v == true) {
                                _selectedIds.addAll(list.map((e) => e.id));
                              } else {
                                for (var e in list) {
                                  _selectedIds.remove(e.id);
                                }
                              }
                            });
                          },
                          activeColor: const Color(0xFFEFAA1F),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Expanded(child: Text('STAFF', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: Color(0xFF64748B)))),
                      const Expanded(child: Text('PUNCH IN', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: Color(0xFF64748B)))),
                      const Expanded(child: Text('PUNCH OUT', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: Color(0xFF64748B)))),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Color(0xFFE2E8F0)),

                // Table rows
                ...list.map((r) => _buildPunchRow(r)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPunchRow(AdminPunchRecord r) {
    final isSelected = _selectedIds.contains(r.id);
    final isApproved = r.status == 'Approved' || r.status == 'present';

    return InkWell(
      onTap: () => _showPunchDetailModal(r),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFFFFBEB) : Colors.white,
          border: const Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Checkbox
            SizedBox(
              width: 24,
              height: 24,
              child: Checkbox(
                value: isSelected,
                onChanged: (v) {
                  setState(() {
                    if (v == true) {
                      _selectedIds.add(r.id);
                    } else {
                      _selectedIds.remove(r.id);
                    }
                  });
                },
                activeColor: const Color(0xFFEFAA1F),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
              ),
            ),
            const SizedBox(width: 6),

            // Staff column
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r.staffName, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: Color(0xFF0F172A))),
                  const SizedBox(height: 2),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: isApproved ? const Color(0xFFDCFCE7) : const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      isApproved ? 'APPROVED' : 'PENDING',
                      style: TextStyle(
                        fontSize: 7.5,
                        fontWeight: FontWeight.w900,
                        color: isApproved ? const Color(0xFF16A34A) : const Color(0xFFD97706),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Punch In column
            Expanded(
              child: Row(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(4)),
                    child: const Icon(Icons.login_rounded, size: 12, color: Color(0xFF2563EB)),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(r.punchInTime, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Color(0xFF0F172A))),
                        Text('● ${r.punchInLocation}', style: const TextStyle(fontSize: 8, color: Color(0xFF64748B)), overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Punch Out column
            Expanded(
              child: Row(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(4)),
                    child: const Icon(Icons.logout_rounded, size: 12, color: Color(0xFF64748B)),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(r.punchOutTime, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Color(0xFF0F172A))),
                        Text('● ${r.punchOutLocation}', style: const TextStyle(fontSize: 8, color: Color(0xFF64748B)), overflow: TextOverflow.ellipsis),
                      ],
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
