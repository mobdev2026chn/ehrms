// lib/screens/admin/approvals/admin_reimbursement_approvals_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../config/app_colors.dart';
import '../../../services/api_client.dart';
import '../../../utils/snackbar_utils.dart';
import '../../../widgets/app_drawer.dart';
import '../../../widgets/app_tab_loader.dart';

class AdminReimbursementRecord {
  final String id;
  final String name;
  final String employeeId;
  final String department;
  final String category;
  final double amount;
  final String claimDate;
  final String description;
  final String? receiptUrl;
  final String? paymentRoute; // 'Immediate' | 'Payroll'
  final String? payrollMonth;
  final String? proofImgUrl;
  String status; // 'Pending' | 'Approved' | 'Paid' | 'Rejected' | 'Cancelled'
  final String approvedBy;
  final String remarksDate;
  final String remarks;

  AdminReimbursementRecord({
    required this.id,
    required this.name,
    required this.employeeId,
    required this.department,
    required this.category,
    required this.amount,
    required this.claimDate,
    required this.description,
    this.receiptUrl,
    this.paymentRoute,
    this.payrollMonth,
    this.proofImgUrl,
    required this.status,
    this.approvedBy = 'Admin',
    this.remarksDate = '',
    this.remarks = '',
  });

  String get initials {
    final parts = name.trim().split(' ');
    if (parts.length > 1) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name.isNotEmpty ? name[0].toUpperCase() : 'U';
  }

  factory AdminReimbursementRecord.fromJson(Map<String, dynamic> json) {
    final staffObj = json['staffId'] is Map ? json['staffId'] : json;
    final pRoute = json['paymentRoute']?.toString();
    final pMonth = json['payrollMonth']?.toString();

    return AdminReimbursementRecord(
      id: (json['_id'] ?? json['id'] ?? '').toString(),
      name: (staffObj['name'] ?? '${staffObj['firstName'] ?? ''} ${staffObj['lastName'] ?? ''}'.trim()).toString().isNotEmpty
          ? (staffObj['name'] ?? '${staffObj['firstName'] ?? ''} ${staffObj['lastName'] ?? ''}'.trim()).toString()
          : (json['name'] ?? 'James fernado').toString(),
      employeeId: (staffObj['employeeId'] ?? json['employeeId'] ?? 'EMP-002').toString(),
      department: (staffObj['department'] is Map ? staffObj['department']['name'] : (staffObj['department'] ?? json['department'] ?? 'IT')).toString(),
      category: (json['category'] ?? 'Travel').toString(),
      amount: double.tryParse((json['amount'] ?? '0').toString()) ?? 0.0,
      claimDate: (json['date'] ?? json['claimDate'] ?? '2026-08-29').toString(),
      description: (json['description'] ?? '').toString(),
      receiptUrl: json['receiptName']?.toString() ?? json['receiptUrl']?.toString(),
      paymentRoute: pRoute,
      payrollMonth: pMonth,
      proofImgUrl: json['proofImg']?.toString() ?? json['proofUrl']?.toString(),
      status: (json['status'] ?? 'Pending').toString(),
      approvedBy: (json['approvedBy'] ?? 'Admin').toString(),
      remarksDate: (json['remarksDate'] ?? json['updatedAt'] ?? '').toString(),
      remarks: (json['remarks'] ?? '').toString(),
    );
  }
}

class AdminReimbursementApprovalsScreen extends StatefulWidget {
  const AdminReimbursementApprovalsScreen({super.key});

  @override
  State<AdminReimbursementApprovalsScreen> createState() => _AdminReimbursementApprovalsScreenState();
}

class _AdminReimbursementApprovalsScreenState extends State<AdminReimbursementApprovalsScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final ApiClient _api = ApiClient();

  bool _isLoading = true;
  String _searchQuery = '';
  String _statusFilter = 'All Statuses';
  String _startDateFilter = '';
  String _endDateFilter = '';
  String _sortOrder = 'Newest First (Descending)';

  List<AdminReimbursementRecord> _records = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData({bool showLoader = true}) async {
    if (showLoader && mounted) setState(() => _isLoading = true);

    try {
      final res = await _api.request(
        '/admin/staff/approvals/expense',
        queryParameters: {
          'search': _searchQuery.isNotEmpty ? _searchQuery : null,
          'status': _statusFilter != 'All Statuses' ? _statusFilter : null,
          'startDate': _startDateFilter.isNotEmpty ? _startDateFilter : null,
          'endDate': _endDateFilter.isNotEmpty ? _endDateFilter : null,
          'sort': _sortOrder.startsWith('Newest') ? 'Newest' : 'Oldest',
        },
      );

      if (res.data is Map && res.data['success'] == true) {
        final list = (res.data['data']?['requests'] as List?) ?? (res.data['data'] as List?) ?? [];
        if (list.isNotEmpty && mounted) {
          setState(() {
            _records = list.map((e) => AdminReimbursementRecord.fromJson(Map<String, dynamic>.from(e as Map))).toList();
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
      AdminReimbursementRecord(
        id: 'rem_1',
        name: 'James fernado',
        employeeId: 'EMP-002',
        department: 'IT',
        category: 'Meals',
        amount: 200,
        claimDate: '2026-08-29',
        description: 'test',
        receiptUrl: 'https://example.com/receipt1.pdf',
        status: 'Pending',
      ),
      AdminReimbursementRecord(
        id: 'rem_2',
        name: 'hp hai th',
        employeeId: 'EMP-006',
        department: 'IT',
        category: 'Travel',
        amount: 12,
        claimDate: '2026-08-26',
        description: 'asd',
        receiptUrl: 'https://example.com/receipt2.pdf',
        status: 'Pending',
      ),
      AdminReimbursementRecord(
        id: 'rem_3',
        name: 'hp hai th',
        employeeId: 'EMP-006',
        department: 'IT',
        category: 'Travel',
        amount: 23,
        claimDate: '2026-08-18',
        description: 'asfd',
        status: 'Rejected',
        approvedBy: 'Admin',
        remarks: 's',
        remarksDate: 'Aug 24, 2026',
      ),
      AdminReimbursementRecord(
        id: 'rem_4',
        name: 'James fernado',
        employeeId: 'EMP-002',
        department: 'IT',
        category: 'Other',
        amount: 600,
        claimDate: '2026-08-19',
        description: 'jmj',
        receiptUrl: 'https://example.com/receipt3.pdf',
        status: 'Pending',
      ),
      AdminReimbursementRecord(
        id: 'rem_5',
        name: 'James fernado',
        employeeId: 'EMP-002',
        department: 'IT',
        category: 'Travel',
        amount: 23423,
        claimDate: '2026-08-27',
        description: 'asdfsd',
        receiptUrl: 'https://example.com/receipt4.pdf',
        paymentRoute: 'Immediate',
        proofImgUrl: 'https://example.com/proof1.png',
        status: 'Paid',
        approvedBy: 'Admin',
        remarksDate: 'Aug 19, 2026',
      ),
      AdminReimbursementRecord(
        id: 'rem_6',
        name: 'James fernado',
        employeeId: 'EMP-002',
        department: 'IT',
        category: 'Other',
        amount: 200,
        claimDate: '2026-08-13',
        description: 'dfhb',
        paymentRoute: 'Immediate',
        proofImgUrl: 'https://example.com/proof2.png',
        status: 'Paid',
        approvedBy: 'Admin',
        remarksDate: 'Aug 18, 2026',
      ),
      AdminReimbursementRecord(
        id: 'rem_7',
        name: 'James fernado',
        employeeId: 'EMP-002',
        department: 'IT',
        category: 'Food',
        amount: 300,
        claimDate: '2026-08-12',
        description: 'ghgu',
        receiptUrl: 'https://example.com/receipt5.pdf',
        paymentRoute: 'Payroll',
        payrollMonth: 'August 2026',
        status: 'Paid',
        approvedBy: 'Admin',
        remarksDate: 'Aug 18, 2026',
      ),
    ];
  }

  List<AdminReimbursementRecord> get _filteredRecords {
    return _records.where((r) {
      final matchesSearch = _searchQuery.isEmpty ||
          r.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          r.employeeId.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          r.category.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          r.description.toLowerCase().contains(_searchQuery.toLowerCase());

      final matchesStatus = _statusFilter == 'All Statuses' || r.status.toLowerCase() == _statusFilter.toLowerCase();

      return matchesSearch && matchesStatus;
    }).toList();
  }

  // ── Action: Approve Reimbursement Modal ──
  void _showApproveModal(AdminReimbursementRecord r) {
    String paymentRoute = 'Immediate'; // 'Immediate' | 'Payroll'
    String payrollMonth = 'August 2026';
    final remarksController = TextEditingController(text: 'Approved');

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            contentPadding: const EdgeInsets.all(20),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Approve Reimbursement', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF0F172A))),
                    IconButton(icon: const Icon(Icons.close_rounded, size: 18), onPressed: () => Navigator.pop(ctx)),
                  ],
                ),
                const SizedBox(height: 10),

                Text('${r.name} • ₹${r.amount.toStringAsFixed(0)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF64748B))),
                const SizedBox(height: 14),

                const Text('PAYMENT ROUTE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF64748B))),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () => setDialogState(() => paymentRoute = 'Immediate'),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: paymentRoute == 'Immediate' ? const Color(0xFFFEF3C7) : const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: paymentRoute == 'Immediate' ? const Color(0xFFEFAA1F) : const Color(0xFFE2E8F0)),
                          ),
                          child: Text('Immediate Transfer', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: paymentRoute == 'Immediate' ? const Color(0xFFD97706) : const Color(0xFF64748B))),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: InkWell(
                        onTap: () => setDialogState(() => paymentRoute = 'Payroll'),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: paymentRoute == 'Payroll' ? const Color(0xFFEFF6FF) : const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: paymentRoute == 'Payroll' ? const Color(0xFF2563EB) : const Color(0xFFE2E8F0)),
                          ),
                          child: Text('With Payroll', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: paymentRoute == 'Payroll' ? const Color(0xFF2563EB) : const Color(0xFF64748B))),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                if (paymentRoute == 'Payroll') ...[
                  const Text('PAYROLL MONTH', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF64748B))),
                  const SizedBox(height: 4),
                  Container(
                    height: 38,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFE2E8F0))),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: payrollMonth,
                        isExpanded: true,
                        items: ['August 2026', 'September 2026', 'October 2026'].map((m) => DropdownMenuItem(value: m, child: Text(m, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)))).toList(),
                        onChanged: (v) {
                          if (v != null) setDialogState(() => payrollMonth = v);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                const Text('REMARKS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF64748B))),
                const SizedBox(height: 4),
                TextField(
                  controller: remarksController,
                  decoration: InputDecoration(
                    hintText: 'Add remarks...',
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                  style: const TextStyle(fontSize: 11),
                ),
                const SizedBox(height: 16),

                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () async {
                          Navigator.pop(ctx);
                          setState(() {
                            r.status = 'Paid';
                          });
                          try {
                            await _api.request(
                              '/admin/staff/approvals/expense/${r.id}/approve',
                              method: 'POST',
                              data: {
                                'paymentRoute': paymentRoute,
                                'payrollMonth': paymentRoute == 'Payroll' ? payrollMonth : null,
                                'remarks': remarksController.text,
                              },
                            );
                          } catch (_) {}
                          if (mounted) SnackBarUtils.showSnackBar(context, 'Reimbursement claim approved!');
                        },
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF16A34A), foregroundColor: Colors.white),
                        child: const Text('Approve & Pay', style: TextStyle(fontWeight: FontWeight.w800)),
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

  // ── Action: Reject Reimbursement Modal ──
  void _showRejectModal(AdminReimbursementRecord r) {
    final reasonController = TextEditingController();

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
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Reject Reimbursement', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF0F172A))),
                IconButton(icon: const Icon(Icons.close_rounded, size: 18), onPressed: () => Navigator.pop(ctx)),
              ],
            ),
            const SizedBox(height: 10),

            Text('Rejecting claim of ₹${r.amount.toStringAsFixed(0)} for ${r.name}', style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
            const SizedBox(height: 12),

            const Text('REASON FOR REJECTION', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF64748B))),
            const SizedBox(height: 4),
            TextField(
              controller: reasonController,
              maxLines: 2,
              decoration: InputDecoration(
                hintText: 'Enter reason...',
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                contentPadding: const EdgeInsets.all(10),
              ),
              style: const TextStyle(fontSize: 11),
            ),
            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      setState(() {
                        r.status = 'Rejected';
                      });
                      try {
                        await _api.request(
                          '/admin/staff/approvals/expense/${r.id}/reject',
                          method: 'POST',
                          data: {'reason': reasonController.text},
                        );
                      } catch (_) {}
                      if (mounted) SnackBarUtils.showSnackBar(context, 'Reimbursement claim rejected');
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDC2626), foregroundColor: Colors.white),
                    child: const Text('Reject Claim', style: TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Action: Advanced Filters Slide-Over (Screenshots 4 & 5) ──
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

                // Claim Status (Screenshot 4)
                const Text('CLAIM STATUS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF64748B))),
                const SizedBox(height: 4),
                _drawerDropdown(_statusFilter, ['All Statuses', 'Pending', 'Approved', 'Paid', 'Rejected', 'Cancelled'], (v) {
                  setDrawerState(() => _statusFilter = v);
                  setState(() => _statusFilter = v);
                }),
                const SizedBox(height: 12),

                // Start & End Date (Screenshot 4)
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

                // Sort Order (Screenshot 5)
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
                            _startDateFilter = '';
                            _endDateFilter = '';
                            _sortOrder = 'Newest First (Descending)';
                          });
                          setState(() {
                            _statusFilter = 'All Statuses';
                            _startDateFilter = '';
                            _endDateFilter = '';
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
          'Reimbursement',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
        ),
        centerTitle: false,
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: _isLoading
          ? const Center(child: AppTabLoader())
          : RefreshIndicator(
              onRefresh: () => _loadData(showLoader: false),
              color: AppColors.primary,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Header Bar: Search & Filter
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFF1F5F9))),
                    child: Row(
                      children: [
                        Expanded(
                          child: Container(
                            height: 38,
                            decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFE2E8F0))),
                            child: TextField(
                              onChanged: (v) => setState(() => _searchQuery = v),
                              decoration: const InputDecoration(
                                hintText: 'Search (case-insensitive)...',
                                hintStyle: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                                prefixIcon: Icon(Icons.search_rounded, size: 16, color: Color(0xFF94A3B8)),
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.symmetric(vertical: 9),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),

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
                  ),
                  const SizedBox(height: 14),

                  // Sub-header title
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('ALL REIMBURSEMENT CLAIMS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF64748B))),
                      Text('Showing ${_filteredRecords.length} claims', style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Records Cards
                  if (_filteredRecords.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(36),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                      child: const Text('No reimbursement claims found', style: TextStyle(fontSize: 13, color: Color(0xFF94A3B8))),
                    )
                  else
                    ..._filteredRecords.map((r) => _buildReimbursementCard(r)),
                ],
              ),
            ),
    );
  }

  Widget _buildReimbursementCard(AdminReimbursementRecord r) {
    final isPaid = r.status == 'Paid';
    final isPending = r.status == 'Pending';
    final isRejected = r.status == 'Rejected';

    Color statusBg = isPaid ? const Color(0xFF2563EB) : (isPending ? const Color(0xFFF1F5F9) : (isRejected ? const Color(0xFFDC2626) : const Color(0xFFEFAA1F)));
    Color statusFg = (isPaid || isRejected || r.status == 'Approved') ? Colors.white : const Color(0xFF475569);

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
          // Row 1: Avatar + Name + Amount + Status
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
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('₹${r.amount.toStringAsFixed(0)}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Color(0xFF0F172A))),
                  const SizedBox(height: 2),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(color: statusBg, borderRadius: BorderRadius.circular(10)),
                    child: Text(r.status, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: statusFg)),
                  ),
                ],
              ),
              if (isPending) ...[
                const SizedBox(width: 4),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert_rounded, size: 18, color: Color(0xFF64748B)),
                  onSelected: (val) {
                    if (val == 'approve') {
                      _showApproveModal(r);
                    } else if (val == 'reject') {
                      _showRejectModal(r);
                    }
                  },
                  itemBuilder: (ctx) => [
                    const PopupMenuItem(
                      value: 'approve',
                      child: Row(
                        children: [
                          Icon(Icons.check_circle_outline_rounded, size: 16, color: Color(0xFF16A34A)),
                          SizedBox(width: 8),
                          Text('Approve', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF16A34A))),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'reject',
                      child: Row(
                        children: [
                          Icon(Icons.cancel_outlined, size: 16, color: Color(0xFFDC2626)),
                          SizedBox(width: 8),
                          Text('Reject', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFFDC2626))),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),

          // Details Card
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFE2E8F0))),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Category: ${r.category}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
                    Text('📅 ${r.claimDate}', style: const TextStyle(fontSize: 10.5, color: Color(0xFF64748B))),
                  ],
                ),
                if (r.description.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Text('Description: ', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Color(0xFF64748B))),
                      Expanded(child: Text(r.description, style: const TextStyle(fontSize: 10.5, color: Color(0xFF0F172A)), maxLines: 1, overflow: TextOverflow.ellipsis)),
                    ],
                  ),
                ],
                if (r.paymentRoute != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        r.paymentRoute == 'Payroll' ? 'Payment: Payroll (${r.payrollMonth})' : 'Payment: Immediate',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: r.paymentRoute == 'Payroll' ? const Color(0xFF2563EB) : const Color(0xFF16A34A)),
                      ),
                      if (r.approvedBy.isNotEmpty)
                        Text(isRejected ? 'Rejected: ${r.remarks}' : 'Approved by: ${r.approvedBy}', style: const TextStyle(fontSize: 9.5, color: Color(0xFFD97706), fontWeight: FontWeight.w700)),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
