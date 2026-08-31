// lib/screens/admin/staff/admin_staff_list_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../config/app_colors.dart';
import '../../../config/app_text_styles.dart';
import '../../../services/admin_staff_service.dart';
import '../../../utils/snackbar_utils.dart';
import '../../../widgets/app_drawer.dart';
import '../../../widgets/app_tab_loader.dart';
import 'admin_import_staff_screen.dart';
import 'admin_add_staff_screen.dart';

class AdminStaffListScreen extends StatefulWidget {
  const AdminStaffListScreen({super.key});

  @override
  State<AdminStaffListScreen> createState() => _AdminStaffListScreenState();
}

class _AdminStaffListScreenState extends State<AdminStaffListScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final AdminStaffService _staffService = AdminStaffService();

  List<Map<String, dynamic>> _allStaff = [];
  List<Map<String, dynamic>> _filteredStaff = [];
  bool _isLoading = true;

  // Search & Filter
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  String _selectedStatus = 'All Statuses';
  String _selectedDepartment = 'All Departments';
  String _selectedBranch = 'All Branches';

  List<String> _departmentOptions = ['All Departments'];
  List<String> _branchOptions = ['All Branches'];

  // Pagination
  int _currentPage = 1;
  final int _itemsPerPage = 10;

  // Subscription data for modal
  Map<String, dynamic>? _subscriptionData;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);
    await Future.wait([
      _fetchStaffList(),
      _fetchSetupData(),
      _fetchSubscriptionData(),
    ]);
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _fetchStaffList({bool showLoader = true}) async {
    if (showLoader && mounted) setState(() => _isLoading = true);
    final res = await _staffService.getStaffList();
    if (!mounted) return;

    if (res['success'] == true && res['data'] != null) {
      final list = res['data']['staff'] as List? ?? [];
      final staffList = list.map((e) => Map<String, dynamic>.from(e as Map)).toList();

      final depts = <String>{'All Departments'};
      for (final s in staffList) {
        final d = s['department']?.toString().trim();
        if (d != null && d.isNotEmpty) depts.add(d);
      }

      setState(() {
        _allStaff = staffList;
        _departmentOptions = depts.toList();
        _applyFilters();
      });
    } else {
      if (showLoader) {
        SnackBarUtils.showSnackBar(
          context,
          res['message']?.toString() ?? 'Failed to load staff list',
          isError: true,
        );
      }
    }
    if (showLoader && mounted) setState(() => _isLoading = false);
  }

  Future<void> _fetchSetupData() async {
    final res = await _staffService.getStaffSetup();
    if (!mounted || res['success'] != true) return;
    final data = res['data'] as Map<String, dynamic>?;
    if (data != null && data['branches'] is List) {
      final branches = (data['branches'] as List)
          .map((b) => b is Map ? (b['branchName'] ?? b['name'] ?? '').toString() : b.toString())
          .where((name) => name.isNotEmpty)
          .toSet();
      setState(() {
        _branchOptions = ['All Branches', ...branches];
      });
    }
  }

  Future<void> _fetchSubscriptionData() async {
    final res = await _staffService.getAdminSubscription();
    if (!mounted || res['success'] != true) return;
    setState(() {
      _subscriptionData = res['data'] as Map<String, dynamic>?;
    });
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      _applyFilters();
    });
  }

  void _applyFilters() {
    final query = _searchController.text.trim().toLowerCase();

    List<Map<String, dynamic>> list = List.from(_allStaff);

    if (query.isNotEmpty) {
      list = list.where((s) {
        final id = (s['employeeId'] ?? '').toString().toLowerCase();
        final name = (s['name'] ?? '${s['firstName'] ?? ''} ${s['lastName'] ?? ''}').toString().toLowerCase();
        final role = (s['role'] ?? s['designation'] ?? '').toString().toLowerCase();
        final dept = (s['department'] ?? '').toString().toLowerCase();
        final email = (s['email'] ?? s['contact'] ?? '').toString().toLowerCase();
        return id.contains(query) ||
            name.contains(query) ||
            role.contains(query) ||
            dept.contains(query) ||
            email.contains(query);
      }).toList();
    }

    if (_selectedStatus != 'All Statuses') {
      list = list.where((s) {
        final status = (s['status'] ?? 'Active').toString().toLowerCase();
        return status == _selectedStatus.toLowerCase();
      }).toList();
    }

    if (_selectedDepartment != 'All Departments') {
      list = list.where((s) {
        final dept = (s['department'] ?? '').toString();
        return dept == _selectedDepartment;
      }).toList();
    }

    if (_selectedBranch != 'All Branches') {
      list = list.where((s) {
        final b = s['branch'];
        final branchName = b is Map ? (b['branchName'] ?? '') : (s['branchName'] ?? b ?? '').toString();
        return branchName == _selectedBranch;
      }).toList();
    }

    setState(() {
      _filteredStaff = list;
      _currentPage = 1;
    });
  }

  int get _totalPages => (_filteredStaff.length / _itemsPerPage).ceil();

  List<Map<String, dynamic>> get _pagedStaff {
    final start = (_currentPage - 1) * _itemsPerPage;
    if (start >= _filteredStaff.length) return [];
    final end = (start + _itemsPerPage).clamp(0, _filteredStaff.length);
    return _filteredStaff.sublist(start, end);
  }

  bool get _hasActiveFilters =>
      _selectedStatus != 'All Statuses' ||
      _selectedDepartment != 'All Departments' ||
      _selectedBranch != 'All Branches';

  void _openFiltersDrawer() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
                left: 20,
                right: 20,
                top: 20,
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
                          Icon(Icons.filter_alt_outlined, color: Color(0xFFD97706), size: 20),
                          SizedBox(width: 8),
                          Text(
                            'ADVANCED FILTERS',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF0F172A),
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, size: 20, color: Color(0xFF64748B)),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // STATUS
                  const Text(
                    'STATUS',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF64748B)),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedStatus,
                        isExpanded: true,
                        icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF64748B)),
                        items: ['All Statuses', 'Active', 'Deactive'].map((s) {
                          return DropdownMenuItem(
                            value: s,
                            child: Text(s, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setModalState(() => _selectedStatus = val);
                            setState(() => _selectedStatus = val);
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // DEPARTMENT
                  const Text(
                    'DEPARTMENT',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF64748B)),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _departmentOptions.contains(_selectedDepartment)
                            ? _selectedDepartment
                            : _departmentOptions.first,
                        isExpanded: true,
                        icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF64748B)),
                        items: _departmentOptions.map((d) {
                          return DropdownMenuItem(
                            value: d,
                            child: Text(d, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setModalState(() => _selectedDepartment = val);
                            setState(() => _selectedDepartment = val);
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // BRANCH
                  const Text(
                    'BRANCH',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF64748B)),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _branchOptions.contains(_selectedBranch)
                            ? _selectedBranch
                            : _branchOptions.first,
                        isExpanded: true,
                        icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF64748B)),
                        items: _branchOptions.map((b) {
                          return DropdownMenuItem(
                            value: b,
                            child: Text(b, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setModalState(() => _selectedBranch = val);
                            setState(() => _selectedBranch = val);
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Buttons: Clear All & Apply Filters
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () {
                            setModalState(() {
                              _selectedStatus = 'All Statuses';
                              _selectedDepartment = 'All Departments';
                              _selectedBranch = 'All Branches';
                            });
                            setState(() {
                              _selectedStatus = 'All Statuses';
                              _selectedDepartment = 'All Departments';
                              _selectedBranch = 'All Branches';
                              _applyFilters();
                            });
                            Navigator.pop(ctx);
                          },
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: const Text(
                            'Clear All',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton(
                          onPressed: () {
                            _applyFilters();
                            Navigator.pop(ctx);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'Apply Filters',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showSubscriptionModal() {
    final plan = _subscriptionData?['plan'] ?? _subscriptionData?['subscription'] ?? {};
    final planName = (plan['planName'] ?? plan['name'] ?? 'Lite').toString();
    final planType = (plan['planType'] ?? 'Single').toString();
    final totalSeats = (plan['maxEmployees'] ?? plan['totalSeats'] ?? 105) as num;
    final usedSeats = (_allStaff.length).clamp(0, totalSeats.toInt());
    final remainingSeats = (totalSeats - usedSeats).clamp(0, totalSeats.toInt());

    showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 20),
          child: Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: const [
                BoxShadow(color: Color(0x20000000), blurRadius: 20, offset: Offset(0, 8)),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const SizedBox(width: 24),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: const BoxDecoration(
                        color: Color(0xFFFFFBEB),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.auto_awesome_rounded, color: Color(0xFFD97706), size: 22),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20, color: Color(0xFF94A3B8)),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Text(
                  'Select Subscription Plan',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 18),
                // Plan Highlight Card
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFFDE68A), width: 1.5),
                    boxShadow: const [
                      BoxShadow(color: Color(0x0A000000), blurRadius: 10, offset: Offset(0, 4)),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: const Color(0xFFD97706),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.bolt_rounded, color: Colors.white, size: 16),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            planName,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Perfect for small growing teams.',
                        style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.group_outlined, size: 16, color: Color(0xFF64748B)),
                            const SizedBox(width: 6),
                            Text(
                              '$remainingSeats seats remaining ($usedSeats/$totalSeats used)',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF334155),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Icon(Icons.check_rounded, color: Color(0xFFD97706), size: 16),
                          const SizedBox(width: 6),
                          Text('Plan Type: $planType', style: const TextStyle(fontSize: 12, color: Color(0xFF475569))),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.check_rounded, color: Color(0xFFD97706), size: 16),
                          const SizedBox(width: 6),
                          Text('Total Seats Allocated: $totalSeats', style: const TextStyle(fontSize: 12, color: Color(0xFF475569))),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      final created = await Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const AdminAddStaffScreen()),
                      );
                      if (created == true) {
                        _fetchStaffList();
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Text('Continue to Add Staff', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                        SizedBox(width: 8),
                        Icon(Icons.arrow_forward_rounded, size: 16),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _navigateToImport() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AdminImportStaffScreen()),
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
          'Staff List',
          style: TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w900,
            color: Color(0xFF0F172A),
          ),
        ),
        centerTitle: false,
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: const Color(0xFFF1F5F9), height: 1),
        ),
        actions: [
          // Import button
          OutlinedButton.icon(
            onPressed: _navigateToImport,
            icon: const Icon(Icons.upload_file_outlined, size: 14),
            label: const Text('Import', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF334155),
              side: const BorderSide(color: Color(0xFFE2E8F0)),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
          const SizedBox(width: 8),
          // + Add Staff button
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: ElevatedButton.icon(
              onPressed: _showSubscriptionModal,
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('Add Staff', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: AppTabLoader())
          : RefreshIndicator(
              onRefresh: () => _fetchStaffList(showLoader: false),
              color: AppColors.primary,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                children: [
                  // ── Search & Filter Row ──
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 44,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                            boxShadow: const [
                              BoxShadow(color: Color(0x04000000), blurRadius: 6, offset: Offset(0, 2)),
                            ],
                          ),
                          child: TextField(
                            controller: _searchController,
                            onChanged: _onSearchChanged,
                            style: const TextStyle(fontSize: 13, color: Color(0xFF0F172A)),
                            decoration: const InputDecoration(
                              hintText: 'Search by ID, name, role, dept...',
                              hintStyle: TextStyle(fontSize: 12.5, color: Color(0xFF94A3B8)),
                              prefixIcon: Icon(Icons.search_rounded, size: 18, color: Color(0xFF94A3B8)),
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Filter Button
                      InkWell(
                        onTap: _openFiltersDrawer,
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          height: 44,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          decoration: BoxDecoration(
                            color: _hasActiveFilters ? const Color(0xFFFFFBEB) : Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _hasActiveFilters ? const Color(0xFFFDE68A) : const Color(0xFFE2E8F0),
                            ),
                            boxShadow: const [
                              BoxShadow(color: Color(0x04000000), blurRadius: 6, offset: Offset(0, 2)),
                            ],
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.tune_rounded,
                                size: 16,
                                color: _hasActiveFilters ? const Color(0xFFD97706) : const Color(0xFF64748B),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Filters',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: _hasActiveFilters ? const Color(0xFFD97706) : const Color(0xFF334155),
                                ),
                              ),
                              if (_hasActiveFilters) ...[
                                const SizedBox(width: 6),
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFD97706),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // ── Staff Count Summary Bar ──
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Showing ${_filteredStaff.isEmpty ? 0 : (_currentPage - 1) * _itemsPerPage + 1} to ${((_currentPage - 1) * _itemsPerPage + _pagedStaff.length).clamp(0, _filteredStaff.length)} of ${_filteredStaff.length} entries',
                        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
                      ),
                      if (_hasActiveFilters)
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              _selectedStatus = 'All Statuses';
                              _selectedDepartment = 'All Departments';
                              _selectedBranch = 'All Branches';
                              _applyFilters();
                            });
                          },
                          child: const Text(
                            'Reset filters',
                            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFFD97706)),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // ── Staff Card List ──
                  if (_filteredStaff.isEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      alignment: Alignment.center,
                      child: Column(
                        children: const [
                          Icon(Icons.person_off_outlined, size: 48, color: Color(0xFFCBD5E1)),
                          SizedBox(height: 12),
                          Text(
                            'No staff members found',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF64748B)),
                          ),
                        ],
                      ),
                    )
                  else
                    ..._pagedStaff.asMap().entries.map((entry) {
                      final index = (_currentPage - 1) * _itemsPerPage + entry.key + 1;
                      final s = entry.value;
                      return _buildStaffCard(s, index);
                    }),

                  const SizedBox(height: 16),

                  // ── Pagination Bar ──
                  if (_totalPages > 1) _buildPaginationBar(),
                ],
              ),
            ),
    );
  }

  Widget _buildStaffCard(Map<String, dynamic> staff, int sNo) {
    final empId = (staff['employeeId'] ?? '').toString();
    final name = (staff['name'] ?? '${staff['firstName'] ?? ''} ${staff['lastName'] ?? ''}').toString().trim();
    final designation = (staff['designation'] ?? staff['role'] ?? 'Staff').toString();
    final department = (staff['department'] ?? '').toString();
    final email = (staff['email'] ?? staff['contact'] ?? '').toString();
    final type = (staff['employmentType'] ?? staff['type'] ?? 'FULL TIME').toString().toUpperCase();
    final status = (staff['status'] ?? 'Active').toString();
    final isActive = status.toLowerCase() == 'active';

    String joiningDateStr = '-';
    if (staff['joiningDate'] != null) {
      try {
        final dt = DateTime.parse(staff['joiningDate'].toString());
        joiningDateStr = DateFormat('MMM d, yyyy').format(dt);
      } catch (_) {
        joiningDateStr = staff['joiningDate'].toString();
      }
    }

    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'S';

    // Type badge color
    Color typeBg = const Color(0xFFEFF6FF);
    Color typeColor = const Color(0xFF2563EB);
    if (type.contains('INTERN')) {
      typeBg = const Color(0xFFFAF5FF);
      typeColor = const Color(0xFF9333EA);
    } else if (type.contains('PART')) {
      typeBg = const Color(0xFFFFFBEB);
      typeColor = const Color(0xFFD97706);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF1F5F9)),
        boxShadow: const [
          BoxShadow(color: Color(0x06000000), blurRadius: 10, offset: Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Row: S.NO, EMPLOYEE ID, STATUS, ACTIONS
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '#$sNo',
                  style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Color(0xFF64748B)),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                empId,
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
              ),
              const Spacer(),
              // Status Pill
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isActive ? const Color(0xFFECFDF5) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isActive ? const Color(0xFFA7F3D0) : const Color(0xFFCBD5E1),
                  ),
                ),
                child: Text(
                  isActive ? 'Active' : 'Deactive',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: isActive ? const Color(0xFF059669) : const Color(0xFF64748B),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // View Eye Button
              InkWell(
                onTap: () {
                  // View staff detail
                  SnackBarUtils.showSnackBar(context, 'Staff details: $name');
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: const Icon(Icons.remove_red_eye_outlined, size: 15, color: Color(0xFF64748B)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Middle Row: Avatar + Name + Designation & Dept + Type Pill
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: const BoxDecoration(
                  color: Color(0xFFFEF3C7),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  initial,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFFD97706)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$designation ${department.isNotEmpty ? '• $department' : ''}',
                      style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: typeBg,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  type,
                  style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: typeColor, letterSpacing: 0.3),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          const SizedBox(height: 8),

          // Bottom Row: Contact Email + Joining Date
          Row(
            children: [
              const Icon(Icons.mail_outline_rounded, size: 13, color: Color(0xFF94A3B8)),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  email.isNotEmpty ? email : 'No email',
                  style: const TextStyle(fontSize: 11.5, color: Color(0xFF475569)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 10),
              Row(
                children: [
                  const Icon(Icons.calendar_today_outlined, size: 12, color: Color(0xFF94A3B8)),
                  const SizedBox(width: 4),
                  Text(
                    joiningDateStr,
                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPaginationBar() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left_rounded),
          color: _currentPage > 1 ? const Color(0xFF0F172A) : const Color(0xFFCBD5E1),
          onPressed: _currentPage > 1 ? () => setState(() => _currentPage--) : null,
        ),
        for (int p = 1; p <= _totalPages; p++)
          InkWell(
            onTap: () => setState(() => _currentPage = p),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                color: _currentPage == p ? AppColors.primary : Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _currentPage == p ? AppColors.primary : const Color(0xFFE2E8F0),
                ),
              ),
              child: Text(
                '$p',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: _currentPage == p ? Colors.white : const Color(0xFF334155),
                ),
              ),
            ),
          ),
        IconButton(
          icon: const Icon(Icons.chevron_right_rounded),
          color: _currentPage < _totalPages ? const Color(0xFF0F172A) : const Color(0xFFCBD5E1),
          onPressed: _currentPage < _totalPages ? () => setState(() => _currentPage++) : null,
        ),
      ],
    );
  }
}
