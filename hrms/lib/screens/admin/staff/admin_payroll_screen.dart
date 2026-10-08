// lib/screens/admin/staff/admin_payroll_screen.dart
// Admin Payroll Management - mirrors the web Payroll page
// (HRMSfrontend features/admin/staff/salary/payroll): month list, single + bulk generate
// (overview detail -> generate), approve (mark paid), and the server's payslip statement.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:pdfx/pdfx.dart';
import 'package:share_plus/share_plus.dart';

import '../../../config/app_colors.dart';
import '../../../config/app_text_styles.dart';
import '../../../services/admin_payroll_service.dart';
import '../../../utils/snackbar_utils.dart';
import '../../../widgets/app_card.dart';
import '../../../widgets/app_drawer.dart';
import '../../../widgets/app_tab_loader.dart';

const List<String> _kMonths = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December'
];

final NumberFormat _inr = NumberFormat('#,##,##0.00', 'en_IN');
String _money(double v) => '₹ ${_inr.format(v)}';

class AdminPayrollRecord {
  final String id;
  final String staffId;
  final String employeeId;
  final String name;
  final String department;
  final String designation;
  final double gross;
  final double deductions;
  final double netPay;
  final String status; // 'Pending' | 'Processed'
  final String monthYear;

  AdminPayrollRecord({
    required this.id,
    required this.staffId,
    required this.employeeId,
    required this.name,
    required this.department,
    required this.designation,
    required this.gross,
    required this.deductions,
    required this.netPay,
    required this.status,
    required this.monthYear,
  });

  bool get isProcessed => status == 'Processed';

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.length > 1) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return parts.isNotEmpty ? parts[0][0].toUpperCase() : 'U';
  }

  static double _num(dynamic v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0.0;

  /// Row shape of `GET /admin/staff/payroll` (payRollController.getPayRollList).
  factory AdminPayrollRecord.fromJson(Map<String, dynamic> json, String monthYear) {
    final staff = json['staffId'];
    return AdminPayrollRecord(
      id: (json['id'] ?? json['_id'] ?? '').toString(),
      staffId: (staff is Map ? (staff['_id'] ?? '') : (staff ?? '')).toString(),
      employeeId: (json['employeeId'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      department: (json['department'] ?? '').toString(),
      designation: (json['designation'] ?? '').toString(),
      gross: _num(json['gross']),
      deductions: _num(json['deductions']),
      netPay: _num(json['netPay']),
      status: (json['status'] ?? 'Pending').toString(),
      monthYear: monthYear,
    );
  }
}

/// A staff member as the generate dialogs need them.
class _PayrollEmployee {
  final String id;
  final String employeeId;
  final String name;
  final DateTime? joiningDate;
  final bool isActive;

  _PayrollEmployee({
    required this.id,
    required this.employeeId,
    required this.name,
    required this.joiningDate,
    required this.isActive,
  });

  factory _PayrollEmployee.fromStaff(Map<String, dynamic> s) {
    final id = (s['_id'] ?? s['id'] ?? '').toString();
    final name = '${s['firstName'] ?? ''} ${s['lastName'] ?? ''}'.trim();
    final status = (s['status'] ?? 'Active').toString().trim().toLowerCase();
    DateTime? joining;
    final raw = s['joiningDate'];
    if (raw != null && raw.toString().isNotEmpty) joining = DateTime.tryParse(raw.toString())?.toLocal();
    return _PayrollEmployee(
      id: id,
      employeeId: (s['employeeId'] ?? (id.length > 18 ? 'EMP-${id.substring(18)}' : id)).toString(),
      name: name.isNotEmpty ? name : (s['name'] ?? s['employeeId'] ?? 'Employee').toString(),
      joiningDate: joining,
      isActive: status == 'active',
    );
  }
}

/// Payroll periods an employee can have: the joining month through the current month,
/// newest first (web `monthLabelsFrom`). No joining date -> only the current month.
List<({String month, String year})> _periodsFor(DateTime? joiningDate) {
  final now = DateTime.now();
  final current = DateTime(now.year, now.month);
  if (joiningDate == null) {
    return [(month: _kMonths[now.month - 1], year: '${now.year}')];
  }
  var cursor = DateTime(joiningDate.year, joiningDate.month);
  final out = <({String month, String year})>[];
  while (!cursor.isAfter(current)) {
    out.add((month: _kMonths[cursor.month - 1], year: '${cursor.year}'));
    cursor = DateTime(cursor.year, cursor.month + 1);
  }
  return out.reversed.toList();
}

class AdminPayrollScreen extends StatefulWidget {
  const AdminPayrollScreen({super.key});

  @override
  State<AdminPayrollScreen> createState() => _AdminPayrollScreenState();
}

class _AdminPayrollScreenState extends State<AdminPayrollScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final AdminPayrollService _service = AdminPayrollService();

  bool _isLoading = true;
  String? _error;
  String _searchQuery = '';
  late String _selectedMonth;
  late String _selectedYear;
  String _selectedStatus = 'All'; // 'All' | 'Pending' | 'Processed'
  String _selectedDepartment = 'All';

  List<AdminPayrollRecord> _records = [];
  List<_PayrollEmployee>? _employees;
  final Set<String> _busyIds = {};
  late final List<String> _years;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedMonth = _kMonths[now.month - 1];
    _selectedYear = '${now.year}';
    _years = [for (var y = 2024; y <= now.year + 1; y++) '$y'];
    _loadData();
  }

  String get _monthStr => '$_selectedMonth $_selectedYear';

  double get _grossSalaryTotal => _records.fold(0.0, (sum, r) => sum + r.gross);
  double get _deductionsTotal => _records.fold(0.0, (sum, r) => sum + r.deductions);
  double get _netPayableTotal => _records.fold(0.0, (sum, r) => sum + r.netPay);
  int get _processedCount => _records.where((r) => r.isProcessed).length;

  List<String> get _departments {
    final set = <String>{};
    for (final r in _records) {
      if (r.department.isNotEmpty) set.add(r.department);
    }
    return ['All', ...set];
  }

  void _showError(Object e) {
    if (!mounted) return;
    SnackBarUtils.showSnackBar(context, e.toString(), isError: true);
  }

  Future<void> _loadData({bool showLoader = true}) async {
    if (showLoader && mounted) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }
    final month = _monthStr;
    try {
      final list = await _service.getPayrollList(month);
      if (!mounted || month != _monthStr) return;
      setState(() {
        _records = list.map((e) => AdminPayrollRecord.fromJson(e, month)).toList();
        _error = null;
        if (!_departments.contains(_selectedDepartment)) _selectedDepartment = 'All';
      });
    } catch (e) {
      if (!mounted) return;
      if (showLoader || _records.isEmpty) {
        setState(() => _error = e.toString());
      } else {
        _showError(e);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<List<_PayrollEmployee>?> _ensureEmployees() async {
    if (_employees != null) return _employees;
    try {
      final staff = await _service.getStaff();
      _employees = staff.map(_PayrollEmployee.fromStaff).where((e) => e.id.isNotEmpty).toList();
      return _employees;
    } catch (e) {
      _showError(e);
      return null;
    }
  }

  List<AdminPayrollRecord> get _filteredRecords {
    final q = _searchQuery.toLowerCase();
    return _records.where((r) {
      final matchesSearch = q.isEmpty ||
          r.name.toLowerCase().contains(q) ||
          r.employeeId.toLowerCase().contains(q) ||
          r.designation.toLowerCase().contains(q);
      final matchesStatus = _selectedStatus == 'All' || r.status == _selectedStatus;
      final matchesDept = _selectedDepartment == 'All' || r.department == _selectedDepartment;
      return matchesSearch && matchesStatus && matchesDept;
    }).toList();
  }

  // ── Generate (single) ──

  Future<void> _showGeneratePayrollModal() async {
    final employees = await _ensureEmployees();
    if (employees == null || !mounted) return;
    if (employees.isEmpty) {
      SnackBarUtils.showSnackBar(context, 'No staff found to generate payroll for.', isError: true);
      return;
    }

    final result = await showDialog<({_PayrollEmployee emp, String month, String year})>(
      context: context,
      builder: (ctx) => _GeneratePayrollDialog(employees: employees, service: _service),
    );
    if (result == null || !mounted) return;

    final monthStr = '${result.month} ${result.year}';
    SnackBarUtils.showSnackBar(context, 'Generating payroll for ${result.emp.name}...');
    try {
      await _service.generatePayrollForStaff(result.emp.id, monthStr);
      if (!mounted) return;
      SnackBarUtils.showSnackBar(context, 'Payroll generated for ${result.emp.name} ($monthStr)');
      if (monthStr != _monthStr) {
        setState(() {
          _selectedMonth = result.month;
          _selectedYear = result.year;
        });
      }
      await _loadData(showLoader: false);
    } catch (e) {
      _showError('Failed to generate: $e');
    }
  }

  // ── Generate (bulk) ──

  Future<void> _showBulkGenerateModal() async {
    final employees = await _ensureEmployees();
    if (employees == null || !mounted) return;

    final result = await showDialog<({String month, String year, int generated, int alreadyPaid, List<String> failed})>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _BulkGenerateDialog(employees: employees, service: _service),
    );
    if (result == null || !mounted) return;

    setState(() {
      _selectedMonth = result.month;
      _selectedYear = result.year;
    });
    await _loadData(showLoader: false);
    if (!mounted) return;

    final monthStr = '${result.month} ${result.year}';
    final parts = <String>[
      'Payroll generated for ${result.generated} employee${result.generated == 1 ? '' : 's'} ($monthStr)',
      if (result.alreadyPaid > 0) '${result.alreadyPaid} already paid',
      if (result.failed.isNotEmpty) 'not generated: ${result.failed.join(', ')} - check their salary structure',
    ];
    SnackBarUtils.showSnackBar(
      context,
      '${parts.join('. ')}.',
      isError: result.failed.isNotEmpty && result.generated == 0,
      duration: const Duration(seconds: 5),
    );
  }

  // ── Approve (mark paid) ──

  Future<void> _confirmApprove(AdminPayrollRecord r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.check_circle_outline_rounded, color: AppColors.success, size: 22),
            SizedBox(width: 8),
            Text('Approve Payroll', style: AppTextStyles.headingSmall),
          ],
        ),
        content: Text(
          'Mark ${_money(r.netPay)} as paid to ${r.name} for ${r.monthYear}? '
          'Payslips are issued to the employees, and a paid payroll is locked - it cannot be '
          'regenerated or moved back to pending.',
          style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.success, foregroundColor: Colors.white, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: const Text('Yes, Mark as Paid'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _busyIds.add(r.id));
    try {
      await _service.updatePayrollStatus(r.id, status: 'Processed');
      if (!mounted) return;
      SnackBarUtils.showSnackBar(context, 'Payroll processed successfully for ${r.name}!');
      await _loadData(showLoader: false);
    } catch (e) {
      _showError('Failed to process: $e');
    } finally {
      if (mounted) setState(() => _busyIds.remove(r.id));
    }
  }

  // ── Statement / payslip ──

  Future<void> _viewStatement(AdminPayrollRecord r) async {
    if (_busyIds.contains(r.id)) return;
    setState(() => _busyIds.add(r.id));
    try {
      final file = await _service.downloadPayslipPdf(
        r.id,
        fileStem: '${r.employeeId}-${r.monthYear}',
      );
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => _PayrollStatementViewer(record: r, file: file),
      ));
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _busyIds.remove(r.id));
    }
  }

  Future<void> _downloadPayslip(AdminPayrollRecord r) async {
    if (_busyIds.contains(r.id)) return;
    setState(() => _busyIds.add(r.id));
    SnackBarUtils.showSnackBar(context, "Preparing ${r.name}'s payslip PDF...");
    try {
      final file = await _service.downloadPayslipPdf(
        r.id,
        fileStem: '${r.employeeId}-${r.monthYear}',
        keep: true,
      );
      final result = await OpenFilex.open(file.path);
      if (!mounted) return;
      if (result.type != ResultType.done) {
        SnackBarUtils.showSnackBar(context, 'Payslip saved to: ${file.path}');
      }
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _busyIds.remove(r.id));
    }
  }

  @override
  Widget build(BuildContext context) {
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
        title: const Text('Payroll Management'),
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
            // Actions (Bulk Generate, Generate) - as on the web page
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _showBulkGenerateModal,
                    icon: Icon(Icons.groups_rounded, size: 18, color: AppColors.primaryText),
                    label: Text('Bulk Generate', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.primaryText)),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: AppColors.primary, width: 1.2),
                      backgroundColor: AppColors.primary.withValues(alpha: 0.08),
                      minimumSize: const Size(0, 48),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _showGeneratePayrollModal,
                    icon: const Icon(Icons.add_rounded, size: 20),
                    label: const Text('Generate'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ── Filters Bar (Month, Year, Status, Department, Search) ──
            AppCard(
              border: Border.all(color: const Color(0xFFECEEF1)),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _filterDropdown('MONTH', _selectedMonth, _kMonths, (v) {
                          setState(() => _selectedMonth = v);
                          _loadData();
                        }),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _filterDropdown('YEAR', _selectedYear, _years, (v) {
                          setState(() => _selectedYear = v);
                          _loadData();
                        }),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _filterDropdown('STATUS', _selectedStatus, const ['All', 'Pending', 'Processed'], (v) {
                          setState(() => _selectedStatus = v);
                        }),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _filterDropdown('DEPARTMENT', _selectedDepartment, _departments, (v) {
                          setState(() => _selectedDepartment = v);
                        }),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 48,
                    child: TextField(
                      onChanged: (v) => setState(() => _searchQuery = v),
                      style: const TextStyle(fontSize: 14),
                      decoration: const InputDecoration(
                        hintText: 'Search by employee name or ID...',
                        prefixIcon: Icon(Icons.search_rounded, size: 20),
                        contentPadding: EdgeInsets.symmetric(vertical: 12),
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
              _errorState()
            else ...[
              // ── 4 Statistics Cards ──
              Row(
                children: [
                  Expanded(child: _payrollStatCard('GROSS SALARY', _money(_grossSalaryTotal), 'This month', Icons.currency_rupee_rounded, AppColors.warning, AppColors.warningBg)),
                  const SizedBox(width: 12),
                  Expanded(child: _payrollStatCard('DEDUCTIONS', _money(_deductionsTotal), 'PF, ESI, Tax', Icons.currency_rupee_rounded, AppColors.error, AppColors.errorBg)),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _payrollStatCard('NET PAYABLE', _money(_netPayableTotal), 'Ready to disburse', Icons.check_circle_outline_rounded, AppColors.success, AppColors.successBg)),
                  const SizedBox(width: 12),
                  Expanded(child: _payrollStatCard('PROCESSED', '$_processedCount', 'Out of ${_records.length}', Icons.schedule_rounded, AppColors.info, AppColors.infoBg)),
                ],
              ),
              const SizedBox(height: 24),

              const Text('Employee Payroll Details', style: AppTextStyles.headingSmall),
              const SizedBox(height: 12),

              if (_filteredRecords.isEmpty)
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
                          child: Icon(Icons.receipt_long_outlined, size: 30, color: AppColors.primaryText),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _records.isEmpty
                              ? 'No payroll generated for $_monthStr'
                              : 'No payroll entries match the active search and filter settings.',
                          textAlign: TextAlign.center,
                          style: AppTextStyles.bodySmall,
                        ),
                      ],
                    ),
                  ),
                )
              else
                ..._filteredRecords.map(_buildPayrollCard),
            ],
          ],
        ),
      ),
    );
  }

  Widget _errorState() {
    return AppCard(
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
          Text(_error ?? 'Could not load payroll.', textAlign: TextAlign.center, style: AppTextStyles.bodySmall),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => _loadData(),
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _filterDropdown(String label, String value, List<String> items, Function(String) onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTextStyles.sectionLabel.copyWith(fontSize: 10.5, color: AppColors.textSecondary)),
        const SizedBox(height: 6),
        Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(color: const Color(0xFFF7F8FA), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE2E5EA))),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: items.contains(value) ? value : items.first,
              isExpanded: true,
              icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.textSecondary),
              items: items.map((item) => DropdownMenuItem(value: item, child: Text(item, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textPrimary)))).toList(),
              onChanged: (v) {
                if (v != null) onChanged(v);
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _payrollStatCard(String title, String amount, String subtitle, IconData icon, Color color, Color bg) {
    return AppCard(
      border: Border.all(color: const Color(0xFFECEEF1)),
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
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(amount, maxLines: 1, style: AppTextStyles.displayLarge.copyWith(fontSize: 22)),
          ),
          const SizedBox(height: 4),
          Text(title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.5, color: AppColors.textSecondary)),
          const SizedBox(height: 2),
          Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.caption.copyWith(color: AppColors.textCaption)),
        ],
      ),
    );
  }

  Widget _buildPayrollCard(AdminPayrollRecord r) {
    final isProcessed = r.isProcessed;
    final busy = _busyIds.contains(r.id);

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
                    Text('${r.employeeId} • ${r.designation} (${r.department})',
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.bodySmall),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isProcessed ? AppColors.successBg : AppColors.warningBg,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  r.status.toUpperCase(),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                    color: isProcessed ? AppColors.success : AppColors.warning,
                  ),
                ),
              ),
              if (busy)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                )
              else
                PopupMenuButton<String>(
                  tooltip: 'More actions',
                  icon: const Icon(Icons.more_vert_rounded, size: 20, color: AppColors.textSecondary),
                  onSelected: (val) {
                    if (val == 'statement') {
                      _viewStatement(r);
                    } else if (val == 'download') {
                      _downloadPayslip(r);
                    } else if (val == 'approve') {
                      _confirmApprove(r);
                    }
                  },
                  itemBuilder: (ctx) => [
                    const PopupMenuItem(value: 'statement', child: Row(children: [Icon(Icons.receipt_long_rounded, size: 20, color: AppColors.info), SizedBox(width: 12), Text('View Statement', style: TextStyle(fontSize: 14))])),
                    const PopupMenuItem(value: 'download', child: Row(children: [Icon(Icons.download_rounded, size: 20, color: AppColors.brandDark), SizedBox(width: 12), Text('Download Payslip', style: TextStyle(fontSize: 14))])),
                    if (!isProcessed)
                      const PopupMenuItem(value: 'approve', child: Row(children: [Icon(Icons.check_circle_outline_rounded, size: 20, color: AppColors.success), SizedBox(width: 12), Text('Approve', style: TextStyle(fontSize: 14))]))
                    else
                      const PopupMenuItem(enabled: false, child: Row(children: [Icon(Icons.check_rounded, size: 20, color: AppColors.success), SizedBox(width: 12), Text('Approved', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.success))])),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 12),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(12)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: _metricItem('GROSS', _money(r.gross), AppColors.textPrimary)),
                const SizedBox(width: 6),
                Expanded(child: _metricItem('DEDUCTIONS', _money(r.deductions), AppColors.error)),
                const SizedBox(width: 6),
                Expanded(child: _metricItem('NET PAY', _money(r.netPay), AppColors.success)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricItem(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, letterSpacing: 0.4, color: AppColors.textSecondary)),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(value, maxLines: 1, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: color)),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Generate Payroll dialog (web generateModal.tsx)
// ─────────────────────────────────────────────────────────────────────────────

class _GeneratePayrollDialog extends StatefulWidget {
  final List<_PayrollEmployee> employees;
  final AdminPayrollService service;

  const _GeneratePayrollDialog({required this.employees, required this.service});

  @override
  State<_GeneratePayrollDialog> createState() => _GeneratePayrollDialogState();
}

class _GeneratePayrollDialogState extends State<_GeneratePayrollDialog> {
  late _PayrollEmployee _emp;
  late String _month;
  late String _year;
  // staffId -> 'Pending' | 'Processed' for the chosen month
  final Map<String, Map<String, String>> _statusByMonth = {};
  bool _loadingStatus = false;

  @override
  void initState() {
    super.initState();
    _emp = widget.employees.first;
    final now = DateTime.now();
    _month = _kMonths[now.month - 1];
    _year = '${now.year}';
    _syncPeriod();
    _loadExisting();
  }

  List<({String month, String year})> get _periods => _periodsFor(_emp.joiningDate);
  String get _monthStr => '$_month $_year';
  Map<String, String> get _existing => _statusByMonth[_monthStr] ?? const {};
  String? get _selectedStatus => _existing[_emp.id];
  bool get _isLocked => _selectedStatus == 'Processed';

  /// Keeps the chosen period one of this employee's periods.
  void _syncPeriod() {
    final periods = _periods;
    if (periods.isEmpty) return;
    if (!periods.any((p) => p.month == _month && p.year == _year)) {
      _month = periods.first.month;
      _year = periods.first.year;
    }
  }

  Future<void> _loadExisting() async {
    final key = _monthStr;
    if (_statusByMonth.containsKey(key)) return;
    setState(() => _loadingStatus = true);
    try {
      final list = await widget.service.getPayrollList(key);
      final map = <String, String>{};
      for (final rec in list) {
        final sid = (rec['staffId'] ?? '').toString();
        if (sid.isNotEmpty) map[sid] = (rec['status'] ?? '').toString();
      }
      _statusByMonth[key] = map;
    } catch (e) {
      if (mounted) SnackBarUtils.showSnackBar(context, e.toString(), isError: true);
    } finally {
      if (mounted) setState(() => _loadingStatus = false);
    }
  }

  void _onPeriodChanged() {
    _syncPeriod();
    setState(() {});
    _loadExisting();
  }

  @override
  Widget build(BuildContext context) {
    final periods = _periods;
    final hasPeriods = periods.isNotEmpty;
    final years = periods.map((p) => p.year).toSet().toList();
    final monthsInYear = periods.where((p) => p.year == _year).map((p) => p.month).toList();
    final lockedMessage = 'Payroll for ${_emp.name} for $_monthStr is already generated and paid. It cannot be generated again.';

    String suffixFor(_PayrollEmployee e) {
      final s = _existing[e.id];
      if (s == 'Processed') return ' - Already generated';
      if (s == 'Pending') return ' - Pending approval';
      return '';
    }

    return AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Generate Payroll', style: AppTextStyles.headingMedium),
                SizedBox(height: 4),
                Text('Generate payroll for an employee based on salary structure and attendance', style: AppTextStyles.bodySmall),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Close',
            icon: const Icon(Icons.close_rounded, size: 20, color: AppColors.textSecondary),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Employee', style: AppTextStyles.label),
            const SizedBox(height: 6),
            Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.primary, width: 1.4),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _emp.id,
                  isExpanded: true,
                  items: widget.employees
                      .map((e) => DropdownMenuItem(
                            value: e.id,
                            child: Text('${e.name} (${e.employeeId})${suffixFor(e)}', overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: AppColors.textPrimary)),
                          ))
                      .toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    _emp = widget.employees.firstWhere((e) => e.id == v);
                    _onPeriodChanged();
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _dialogDropdown('Year', hasPeriods ? _year : null, years, hasPeriods
                      ? (v) {
                          _year = v;
                          final inYear = periods.where((p) => p.year == v).toList();
                          if (!inYear.any((p) => p.month == _month) && inYear.isNotEmpty) _month = inYear.first.month;
                          _onPeriodChanged();
                        }
                      : null),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _dialogDropdown('Month', hasPeriods ? _month : null, monthsInYear, hasPeriods
                      ? (v) {
                          _month = v;
                          _onPeriodChanged();
                        }
                      : null),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_loadingStatus)
              const LinearProgressIndicator(minHeight: 2)
            else if (_isLocked)
              _notice(lockedMessage, Icons.warning_amber_rounded, AppColors.errorBg, AppColors.error)
            else if (_selectedStatus == 'Pending')
              _notice('Payroll for $_monthStr is already generated and pending approval. Generating again will recalculate it.',
                  Icons.info_outline_rounded, AppColors.warningBg, AppColors.warning),
            const SizedBox(height: 8),
            Text(
              hasPeriods
                  ? (_emp.joiningDate != null
                      ? 'Payroll is available from ${periods.last.month} ${periods.last.year} — the month ${_emp.name} joined.'
                      : 'No joining date on record, so only the current month is offered.')
                  : '${_emp.name} has a joining date in the future, so there is no payroll period to generate yet.',
              style: TextStyle(fontSize: 12, color: hasPeriods ? AppColors.textSecondary : AppColors.warning, fontWeight: hasPeriods ? FontWeight.w400 : FontWeight.w600),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
        ),
        ElevatedButton(
          onPressed: (!hasPeriods || _isLocked || _loadingStatus)
              ? null
              : () => Navigator.pop(context, (emp: _emp, month: _month, year: _year)),
          style: ElevatedButton.styleFrom(minimumSize: const Size(0, 44)),
          child: Text(_selectedStatus == 'Pending' ? 'Regenerate' : 'Generate'),
        ),
      ],
    );
  }
}

Widget _notice(String text, IconData icon, Color bg, Color fg) {
  return Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: fg),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, height: 1.4, color: fg))),
      ],
    ),
  );
}

Widget _dialogDropdown(String label, String? value, List<String> items, ValueChanged<String>? onChanged) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: AppTextStyles.label),
      const SizedBox(height: 6),
      Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF7F8FA),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E5EA)),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: value != null && items.contains(value) ? value : null,
            isExpanded: true,
            items: items.map((m) => DropdownMenuItem(value: m, child: Text(m, style: const TextStyle(fontSize: 13.5, color: AppColors.textPrimary)))).toList(),
            onChanged: onChanged == null
                ? null
                : (v) {
                    if (v != null) onChanged(v);
                  },
          ),
        ),
      ),
    ],
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Bulk Generate dialog (web bulkGenerateModal.tsx + Payroll.handleBulkGenerateSubmit)
// ─────────────────────────────────────────────────────────────────────────────

class _BulkGenerateDialog extends StatefulWidget {
  final List<_PayrollEmployee> employees;
  final AdminPayrollService service;

  const _BulkGenerateDialog({required this.employees, required this.service});

  @override
  State<_BulkGenerateDialog> createState() => _BulkGenerateDialogState();
}

class _BulkGenerateDialogState extends State<_BulkGenerateDialog> {
  late String _month;
  late String _year;
  int? _done;
  int _total = 0;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = _kMonths[now.month - 1];
    _year = '${now.year}';
  }

  List<_PayrollEmployee> get _active => widget.employees.where((e) => e.isActive).toList();

  List<String> get _years {
    final now = DateTime.now();
    var first = now.year;
    for (final e in _active) {
      final j = e.joiningDate;
      if (j != null && j.year < first) first = j.year;
    }
    return [for (var y = now.year; y >= first; y--) '$y'];
  }

  List<String> get _monthsForYear {
    final now = DateTime.now();
    return int.tryParse(_year) == now.year ? _kMonths.sublist(0, now.month) : _kMonths;
  }

  /// Active employees who had joined by the end of the chosen month.
  List<_PayrollEmployee> get _eligible {
    final monthEnd = DateTime(int.parse(_year), _kMonths.indexOf(_month) + 2, 0, 23, 59, 59, 999);
    return _active.where((e) => e.joiningDate == null || !e.joiningDate!.isAfter(monthEnd)).toList();
  }

  bool get _running => _done != null;

  Future<void> _run() async {
    final employees = _eligible;
    final monthStr = '$_month $_year';
    var generated = 0;
    var alreadyPaid = 0;
    final failed = <String>[];
    setState(() {
      _done = 0;
      _total = employees.length;
    });
    for (final emp in employees) {
      try {
        await widget.service.generatePayrollForStaff(emp.id, monthStr);
        generated++;
      } on AdminPayrollException catch (e) {
        if (e.statusCode == 409) {
          alreadyPaid++;
        } else {
          failed.add(emp.name);
        }
      }
      if (!mounted) return;
      setState(() => _done = (_done ?? 0) + 1);
    }
    if (!mounted) return;
    Navigator.pop(context, (month: _month, year: _year, generated: generated, alreadyPaid: alreadyPaid, failed: failed));
  }

  @override
  Widget build(BuildContext context) {
    final months = _monthsForYear;
    if (!months.contains(_month)) _month = months.last;
    final eligible = _eligible;

    return PopScope(
      canPop: !_running,
      child: AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Bulk Generate Payroll', style: AppTextStyles.headingMedium),
                  SizedBox(height: 4),
                  Text('Generate payroll for all active employees for the selected period', style: AppTextStyles.bodySmall),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Close',
            icon: const Icon(Icons.close_rounded, size: 20, color: AppColors.textSecondary),
              onPressed: _running ? null : () => Navigator.pop(context),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: _dialogDropdown('Month', _month, months, _running ? null : (v) => setState(() => _month = v)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _dialogDropdown('Year', _year, _years, _running ? null : (v) => setState(() => _year = v)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _notice(
              '${eligible.length} active employee${eligible.length == 1 ? '' : 's'} for $_month $_year. '
              'Payroll already paid for the month is left as it is, and pending payroll is recalculated.',
              Icons.info_outline_rounded,
              AppColors.background,
              AppColors.textSecondary,
            ),
            if (_running) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(value: _total == 0 ? null : (_done ?? 0) / _total, minHeight: 3),
              const SizedBox(height: 6),
              Text('Generating ${_done ?? 0} of $_total...', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: _running ? null : () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            onPressed: (_running || eligible.isEmpty) ? null : _run,
            style: ElevatedButton.styleFrom(minimumSize: const Size(0, 44)),
            child: Text(_running ? 'Generating...' : 'Generate All'),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Payslip statement viewer: the server-rendered statement PDF
// (GET /admin/staff/payroll/statement/:id/view?download=true) shown in-app.
// ─────────────────────────────────────────────────────────────────────────────

class _PayrollStatementViewer extends StatefulWidget {
  final AdminPayrollRecord record;
  final File file;

  const _PayrollStatementViewer({required this.record, required this.file});

  @override
  State<_PayrollStatementViewer> createState() => _PayrollStatementViewerState();
}

class _PayrollStatementViewerState extends State<_PayrollStatementViewer> {
  late final PdfControllerPinch _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = PdfControllerPinch(document: PdfDocument.openFile(widget.file.path));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _openExternally() async {
    final result = await OpenFilex.open(widget.file.path);
    if (!mounted) return;
    if (result.type != ResultType.done) {
      SnackBarUtils.showSnackBar(context, result.message.isNotEmpty ? result.message : 'No app found to open the PDF.', isError: true);
    }
  }

  Future<void> _share() async {
    try {
      await SharePlus.instance.share(ShareParams(
        files: [XFile(widget.file.path, mimeType: 'application/pdf')],
        subject: 'Payslip - ${widget.record.name} - ${widget.record.monthYear}',
      ));
    } catch (e) {
      if (mounted) SnackBarUtils.showSnackBar(context, 'Could not share the payslip: $e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.record;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${r.name} - Statement', style: AppTextStyles.headingSmall),
            Text('${r.employeeId} • ${r.monthYear}', style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary)),
          ],
        ),
        actions: [
          IconButton(onPressed: _share, icon: const Icon(Icons.share_rounded), tooltip: 'Share'),
          IconButton(onPressed: _openExternally, icon: const Icon(Icons.open_in_new_rounded), tooltip: 'Open in another app'),
        ],
      ),
      body: Column(
        children: [
          Container(
            color: AppColors.surface,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Row(
              children: [
                Expanded(child: _summary('GROSS', _money(r.gross), AppColors.textPrimary)),
                Expanded(child: _summary('DEDUCTIONS', _money(r.deductions), AppColors.error)),
                Expanded(child: _summary('NET PAY', _money(r.netPay), AppColors.success)),
              ],
            ),
          ),
          Expanded(
            child: _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_error!, textAlign: TextAlign.center, style: AppTextStyles.bodySmall),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: _openExternally,
                            icon: const Icon(Icons.open_in_new_rounded, size: 18),
                            label: const Text('Open in another app'),
                          ),
                        ],
                      ),
                    ),
                  )
                : PdfViewPinch(
                    controller: _controller,
                    onDocumentError: (_) => setState(() => _error = 'This payslip could not be displayed here.'),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _summary(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, letterSpacing: 0.4, color: AppColors.textSecondary)),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(value, maxLines: 1, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: color)),
        ),
      ],
    );
  }
}
