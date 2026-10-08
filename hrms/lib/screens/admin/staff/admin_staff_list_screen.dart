// lib/screens/admin/staff/admin_staff_list_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../config/app_colors.dart';
import '../../../config/app_text_styles.dart';
import '../../../services/admin_staff_detail_service.dart';
import '../../../services/admin_staff_service.dart';
import '../../../utils/snackbar_utils.dart';
import '../../../widgets/app_card.dart';
import '../../../widgets/app_drawer.dart';
import '../../../widgets/app_tab_loader.dart';
import 'admin_import_staff_screen.dart';
import 'admin_add_staff_screen.dart';
import 'detail/staff_detail_screen.dart';

class AdminStaffListScreen extends StatefulWidget {
  const AdminStaffListScreen({super.key});

  @override
  State<AdminStaffListScreen> createState() => _AdminStaffListScreenState();
}

class _AdminStaffListScreenState extends State<AdminStaffListScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final AdminStaffDetailService _detailService = AdminStaffDetailService();

  List<Map<String, dynamic>> _allStaff = [];
  List<Map<String, dynamic>> _filteredStaff = [];
  bool _isLoading = true;
  String? _loadError;

  // Active / Deactive tabs (status is driven by the tab, as on the web list) and the
  // counts of each under the current search + filters.
  String _activeTab = 'Active';
  int _activeCount = 0;
  int _deactiveCount = 0;

  // Search & Filter. The staff list endpoint takes no search or filter parameters (it returns
  // the caller's whole scope), so these are applied on the device.
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  String _selectedDepartment = 'All Departments';
  String _selectedBranch = 'All Branches';

  List<String> _departmentOptions = ['All Departments'];
  List<String> _configuredBranches = [];

  // Pagination
  int _currentPage = 1;
  int _itemsPerPage = 10;
  static const List<int> _pageSizes = [10, 25, 50, 100];

  // Subscription data for the Add Staff modal
  Map<String, dynamic>? _subscriptionData;
  String? _subscriptionError;

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
      _fetchStaffList(showLoader: false),
      _fetchBranches(),
      _fetchSubscriptionData(),
    ]);
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _fetchStaffList({bool showLoader = true}) async {
    if (showLoader && mounted) setState(() => _isLoading = true);
    try {
      final staffList = await _detailService.getStaffList();
      if (!mounted) return;
      final depts = <String>{};
      for (final s in staffList) {
        final d = s['department']?.toString().trim();
        if (d != null && d.isNotEmpty) depts.add(d);
      }
      final sortedDepts = depts.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      setState(() {
        _allStaff = staffList;
        _loadError = null;
        _departmentOptions = ['All Departments', ...sortedDepts];
        _applyFilters(resetPage: false);
      });
    } catch (e) {
      if (!mounted) return;
      final message = e is StaffDetailApiException ? e.message : 'Failed to load staff list';
      setState(() => _loadError = message);
      SnackBarUtils.showSnackBar(context, message, isError: true);
    }
    if (showLoader && mounted) setState(() => _isLoading = false);
  }

  Future<void> _fetchBranches() async {
    try {
      final branches = await _detailService.getBranches();
      if (!mounted) return;
      setState(() {
        _configuredBranches = branches
            .map((b) => (b['branchName'] ?? b['name'] ?? '').toString().trim())
            .where((name) => name.isNotEmpty)
            .toList();
      });
    } catch (e) {
      if (!mounted) return;
      SnackBarUtils.showSnackBar(
        context,
        e is StaffDetailApiException ? e.message : 'Could not load branches.',
        isError: true,
      );
    }
  }

  Future<void> _fetchSubscriptionData() async {
    try {
      final sub = await _detailService.getSubscription();
      if (!mounted) return;
      setState(() {
        _subscriptionData = sub;
        _subscriptionError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _subscriptionError = e is StaffDetailApiException ? e.message : 'Could not read subscription.');
    }
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(_applyFilters);
    });
  }

  static String _nameOf(Map<String, dynamic> s) =>
      (s['name'] ?? '${s['firstName'] ?? ''} ${s['lastName'] ?? ''}').toString().trim();

  static String _branchOf(Map<String, dynamic> s) {
    final b = s['branch'];
    if (b is Map) return (b['branchName'] ?? 'Main HQ').toString();
    final str = (b ?? '').toString().trim();
    return str.isEmpty ? 'Main HQ' : str;
  }

  static bool _isActive(Map<String, dynamic> s) => (s['status'] ?? 'Active').toString().toLowerCase() == 'active';

  /// Branch filter options: configured branches unioned with what rows carry (older records hold
  /// a plain string), names collapsed and sorted - the same rule as the web list.
  List<String> get _branchOptions {
    final names = <String>{..._configuredBranches, ..._allStaff.map(_branchOf)}.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return ['All Branches', ...names];
  }

  /// Call inside setState.
  void _applyFilters({bool resetPage = true}) {
    final query = _searchController.text.trim().toLowerCase();

    // Search covers the fields that identify a person: Employee ID, name and contact.
    final matching = _allStaff.where((s) {
      if (query.isNotEmpty) {
        final id = (s['employeeId'] ?? '').toString().toLowerCase();
        final name = _nameOf(s).toLowerCase();
        final email = (s['email'] ?? s['contact'] ?? '').toString().toLowerCase();
        if (!id.contains(query) && !name.contains(query) && !email.contains(query)) return false;
      }
      if (_selectedDepartment != 'All Departments' && (s['department'] ?? '').toString() != _selectedDepartment) {
        return false;
      }
      if (_selectedBranch != 'All Branches' && _branchOf(s) != _selectedBranch) return false;
      return true;
    }).toList();

    _activeCount = matching.where(_isActive).length;
    _deactiveCount = matching.length - _activeCount;
    _filteredStaff = matching.where((s) => _isActive(s) == (_activeTab == 'Active')).toList();
    if (resetPage || _currentPage > _totalPages) _currentPage = 1;
  }

  int get _totalPages => (_filteredStaff.length / _itemsPerPage).ceil().clamp(1, 1 << 30);

  List<Map<String, dynamic>> get _pagedStaff {
    final start = (_currentPage - 1) * _itemsPerPage;
    if (start >= _filteredStaff.length) return [];
    final end = (start + _itemsPerPage).clamp(0, _filteredStaff.length);
    return _filteredStaff.sublist(start, end);
  }

  bool get _hasActiveFilters => _selectedDepartment != 'All Departments' || _selectedBranch != 'All Branches';

  Future<void> _openDetail(Map<String, dynamic> staff) async {
    final staffId = (staff['_id'] ?? staff['id'] ?? '').toString();
    if (staffId.isEmpty) {
      SnackBarUtils.showSnackBar(context, 'Staff id not found', isError: true);
      return;
    }
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => StaffDetailScreen(staffId: staffId)),
    );
    if (changed == true && mounted) {
      _fetchStaffList(showLoader: false);
      _fetchSubscriptionData();
    }
  }

  Widget _filterDropdown({
    required String label,
    required String value,
    required List<String> options,
    required ValueChanged<String> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTextStyles.sectionLabel.copyWith(color: AppColors.textSecondary)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: const Color(0xFFF7F8FA),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E5EA)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: options.contains(value) ? value : options.first,
              isExpanded: true,
              icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.textSecondary),
              items: options
                  .map((d) => DropdownMenuItem(
                        value: d,
                        child: Text(d, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      ))
                  .toList(),
              onChanged: (val) {
                if (val != null) onChanged(val);
              },
            ),
          ),
        ),
      ],
    );
  }

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
                color: AppColors.surface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
                left: 20,
                right: 20,
                top: 12,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(999)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(Icons.filter_alt_outlined, color: AppColors.primaryText, size: 20),
                          ),
                          const SizedBox(width: 12),
                          const Text(
                            'ADVANCED FILTERS',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                      IconButton(
                        tooltip: 'Close',
                        icon: const Icon(Icons.close_rounded, size: 20, color: AppColors.textSecondary),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _filterDropdown(
                    label: 'DEPARTMENT',
                    value: _selectedDepartment,
                    options: _departmentOptions,
                    onChanged: (val) {
                      setModalState(() {});
                      setState(() => _selectedDepartment = val);
                    },
                  ),
                  const SizedBox(height: 16),
                  _filterDropdown(
                    label: 'BRANCH',
                    value: _selectedBranch,
                    options: _branchOptions,
                    onChanged: (val) {
                      setModalState(() {});
                      setState(() => _selectedBranch = val);
                    },
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () {
                            setState(() {
                              _selectedDepartment = 'All Departments';
                              _selectedBranch = 'All Branches';
                              _applyFilters();
                            });
                            Navigator.pop(ctx);
                          },
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            minimumSize: const Size(0, 48),
                          ),
                          child: const Text(
                            'Clear All',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton(
                          onPressed: () {
                            setState(_applyFilters);
                            Navigator.pop(ctx);
                          },
                          child: const Text('Apply Filters'),
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

  /// Plans on the company's active subscription with their seat usage (web: subscriptionModal.tsx).
  void _showSubscriptionModal() {
    if (_subscriptionError != null) {
      SnackBarUtils.showSnackBar(context, _subscriptionError!, isError: true);
      _fetchSubscriptionData();
      return;
    }
    final plans = ((_subscriptionData?['planDetails'] as List?) ?? const [])
        .whereType<Map>()
        .map((p) => Map<String, dynamic>.from(p))
        .toList();
    if (plans.isEmpty) {
      SnackBarUtils.showSnackBar(context, 'No active subscription plan found. Please contact the administrator.',
          isError: true);
      return;
    }
    int activeOf(Map<String, dynamic> p) => (p['activeUsers'] as List?)?.length ?? 0;
    int totalOf(Map<String, dynamic> p) => (p['totalSeat'] is num) ? (p['totalSeat'] as num).toInt() : 0;
    bool isFull(Map<String, dynamic> p) => totalOf(p) > 0 && activeOf(p) >= totalOf(p);

    var selected = plans.indexWhere((p) => !isFull(p));
    if (selected < 0) selected = 0;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setD) {
          final chosen = plans[selected];
          final full = isFull(chosen);
          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(24),
                boxShadow: const [BoxShadow(color: Color(0x1A000000), blurRadius: 24, offset: Offset(0, 8))],
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const SizedBox(width: 24),
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.auto_awesome_rounded, color: AppColors.primaryText, size: 26),
                        ),
                        IconButton(
                          tooltip: 'Close',
                          icon: const Icon(Icons.close_rounded, size: 20, color: AppColors.textCaption),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Select Subscription Plan',
                      style: AppTextStyles.headingMedium,
                    ),
                    const SizedBox(height: 20),
                    for (var i = 0; i < plans.length; i++)
                      _buildPlanCard(
                        plans[i],
                        selected: i == selected,
                        active: activeOf(plans[i]),
                        total: totalOf(plans[i]),
                        full: isFull(plans[i]),
                        onTap: () => setD(() => selected = i),
                      ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: full
                            ? null
                            : () async {
                                Navigator.pop(ctx);
                                final created = await Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (_) => const AdminAddStaffScreen()),
                                );
                                if (created == true) {
                                  _fetchStaffList();
                                  _fetchSubscriptionData();
                                }
                              },
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(full ? 'Seats full for this plan' : 'Continue to Add Staff'),
                            if (!full) ...[
                              const SizedBox(width: 8),
                              const Icon(Icons.arrow_forward_rounded, size: 16),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        });
      },
    );
  }

  Widget _buildPlanCard(
    Map<String, dynamic> plan, {
    required bool selected,
    required int active,
    required int total,
    required bool full,
    required VoidCallback onTap,
  }) {
    final planName = (plan['planName'] ?? 'Plan').toString();
    final remaining = (total - active) < 0 ? 0 : total - active;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary.withValues(alpha: 0.06) : AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? AppColors.primary : const Color(0xFFECEEF1),
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(10)),
                  child: Icon(Icons.bolt_rounded, color: AppColors.onPrimary, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(planName, style: AppTextStyles.headingSmall),
                ),
                if (full)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: AppColors.errorBg, borderRadius: BorderRadius.circular(999)),
                    child: const Text('FULL',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.error)),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.group_outlined, size: 16, color: AppColors.textSecondary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '$remaining seats remaining ($active/$total used)',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 22),
              child: Text('Total Seats Allocated: $total', style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary)),
            ),
          ],
        ),
      ),
    );
  }

  void _navigateToImport() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AdminImportStaffScreen()),
    ).then((_) {
      if (mounted) _fetchStaffList(showLoader: false);
    });
  }

  Widget _buildStatusTabs() {
    Widget tab(String key, int count) {
      final selected = _activeTab == key;
      return Expanded(
        child: InkWell(
          onTap: () {
            if (selected) return;
            setState(() {
              _activeTab = key;
              _applyFilters();
            });
          },
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: selected ? AppColors.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Text(
              '$key ($count)',
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: selected ? AppColors.onPrimary : AppColors.textSecondary,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFECEEF1)),
      ),
      child: Row(children: [tab('Active', _activeCount), const SizedBox(width: 4), tab('Deactive', _deactiveCount)]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final firstShown = _filteredStaff.isEmpty ? 0 : (_currentPage - 1) * _itemsPerPage + 1;
    final lastShown = ((_currentPage - 1) * _itemsPerPage + _pagedStaff.length).clamp(0, _filteredStaff.length);
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
        title: const Text('Staff List'),
        centerTitle: false,
        actions: [
          OutlinedButton.icon(
            onPressed: _navigateToImport,
            icon: const Icon(Icons.upload_file_outlined, size: 16),
            label: const Text('Import', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 36),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: ElevatedButton.icon(
              onPressed: _showSubscriptionModal,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add Staff', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(0, 36),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: [
                  // ── Search & Filter Row ──
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 48,
                          child: TextField(
                            controller: _searchController,
                            onChanged: _onSearchChanged,
                            style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
                            decoration: const InputDecoration(
                              hintText: 'Search by ID, name or email...',
                              prefixIcon: Icon(Icons.search_rounded, size: 20),
                              contentPadding: EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      InkWell(
                        onTap: _openFiltersDrawer,
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          height: 48,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          decoration: BoxDecoration(
                            color: _hasActiveFilters ? AppColors.primary.withValues(alpha: 0.12) : AppColors.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _hasActiveFilters ? AppColors.primary : const Color(0xFFE2E5EA),
                              width: _hasActiveFilters ? 1.4 : 1.2,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.tune_rounded,
                                size: 18,
                                color: _hasActiveFilters ? AppColors.primaryText : AppColors.textSecondary,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Filters',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: _hasActiveFilters ? AppColors.primaryText : AppColors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildStatusTabs(),
                  const SizedBox(height: 12),

                  // ── Count summary + page size ──
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Showing $firstShown to $lastShown of ${_filteredStaff.length} entries',
                          style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
                        ),
                      ),
                      if (_hasActiveFilters)
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              _selectedDepartment = 'All Departments';
                              _selectedBranch = 'All Branches';
                              _applyFilters();
                            });
                          },
                          child: Padding(
                            padding: const EdgeInsets.only(right: 12),
                            child: Text(
                              'Reset filters',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.primaryText),
                            ),
                          ),
                        ),
                      Container(
                        height: 32,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFE2E5EA)),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<int>(
                            value: _itemsPerPage,
                            isDense: true,
                            icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 16),
                            items: _pageSizes
                                .map((n) => DropdownMenuItem(
                                      value: n,
                                      child: Text('$n / page',
                                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                                    ))
                                .toList(),
                            onChanged: (n) {
                              if (n == null) return;
                              setState(() {
                                _itemsPerPage = n;
                                _currentPage = 1;
                              });
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // ── Staff Card List ──
                  if (_loadError != null && _allStaff.isEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      alignment: Alignment.center,
                      child: Column(
                        children: [
                          Container(
                            width: 64,
                            height: 64,
                            decoration: const BoxDecoration(color: AppColors.errorBg, shape: BoxShape.circle),
                            child: const Icon(Icons.error_outline_rounded, size: 30, color: AppColors.error),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _loadError!,
                            textAlign: TextAlign.center,
                            style: AppTextStyles.bodySmall,
                          ),
                          const SizedBox(height: 16),
                          OutlinedButton.icon(
                            onPressed: () => _fetchStaffList(),
                            icon: const Icon(Icons.refresh_rounded, size: 18),
                            label: const Text('Retry'),
                          ),
                        ],
                      ),
                    )
                  else if (_filteredStaff.isEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      alignment: Alignment.center,
                      child: Column(
                        children: [
                          Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.person_off_outlined, size: 30, color: AppColors.primaryText),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _activeTab == 'Active' ? 'No active staff members found' : 'No deactivated staff members found',
                            textAlign: TextAlign.center,
                            style: AppTextStyles.headingSmall,
                          ),
                        ],
                      ),
                    )
                  else
                    ..._pagedStaff.asMap().entries.map((entry) {
                      final index = (_currentPage - 1) * _itemsPerPage + entry.key + 1;
                      return _buildStaffCard(entry.value, index);
                    }),

                  const SizedBox(height: 16),

                  // ── Pagination Bar ──
                  if (_totalPages > 1) _buildPaginationBar(),
                ],
              ),
            ),
    );
  }

  /// Admin: see whether a staff member has a registered face and remove it
  /// (e.g. the wrong person's face was registered). After removal the staff
  /// member is asked to register again on their next punch.
  void _openFaceRegistrationSheet(Map<String, dynamic> staff, String name) {
    final staffId = (staff['_id'] ?? staff['id'] ?? '').toString();
    if (staffId.isEmpty) {
      SnackBarUtils.showSnackBar(context, 'Staff id not found', isError: true);
      return;
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) => _FaceRegistrationSheet(
        staffId: staffId,
        staffName: name.isNotEmpty ? name : 'this staff member',
        onRemoved: (message) {
          if (!mounted) return;
          SnackBarUtils.showSnackBar(context, message);
        },
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
    Color typeBg = AppColors.infoBg;
    Color typeColor = AppColors.info;
    if (type.contains('INTERN')) {
      typeBg = const Color(0xFFFAF5FF);
      typeColor = const Color(0xFF9333EA);
    } else if (type.contains('PART')) {
      typeBg = AppColors.brandLight;
      typeColor = AppColors.brandDark;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFECEEF1)),
        boxShadow: kSoftCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Row: S.NO, EMPLOYEE ID, STATUS, ACTIONS
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.inputFill,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '#$sNo',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  empId,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                ),
              ),
              const Spacer(),
              // Status Pill
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isActive ? AppColors.successBg : AppColors.inputFill,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  isActive ? 'Active' : 'Deactive',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isActive ? AppColors.success : AppColors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Face registration (view / remove)
              Tooltip(
                message: 'Face registration',
                child: InkWell(
                  onTap: () => _openFaceRegistrationSheet(staff, name),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFE2E5EA)),
                    ),
                    child: const Icon(Icons.face_retouching_natural_outlined, size: 18, color: AppColors.textSecondary),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // View Eye Button
              Tooltip(
                message: 'View details',
                child: InkWell(
                  onTap: () => _openDetail(staff),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.visibility_outlined, size: 18, color: AppColors.primaryText),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Middle Row: Avatar + Name + Designation & Dept + Type Pill
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  initial,
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.primaryText),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: AppTextStyles.headingSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$designation ${department.isNotEmpty ? '• $department' : ''}',
                      style: AppTextStyles.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: typeBg,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  type,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: typeColor, letterSpacing: 0.3),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),

          // Bottom Row: Contact Email + Joining Date
          Row(
            children: [
              const Icon(Icons.mail_outline_rounded, size: 16, color: AppColors.textCaption),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  email.isNotEmpty ? email : 'No email',
                  style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 12),
              Row(
                children: [
                  const Icon(Icons.calendar_today_outlined, size: 14, color: AppColors.textCaption),
                  const SizedBox(width: 4),
                  Text(
                    joiningDateStr,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textSecondary),
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
          tooltip: 'Previous page',
          icon: const Icon(Icons.chevron_left_rounded),
          color: _currentPage > 1 ? AppColors.textPrimary : AppColors.textHint,
          onPressed: _currentPage > 1 ? () => setState(() => _currentPage--) : null,
        ),
        // A window of up to five pages around the current one, so long lists fit the width.
        for (int p = (_currentPage - 2).clamp(1, (_totalPages - 4).clamp(1, _totalPages));
            p <= ((_currentPage - 2).clamp(1, (_totalPages - 4).clamp(1, _totalPages)) + 4).clamp(1, _totalPages);
            p++)
          InkWell(
            onTap: () => setState(() => _currentPage = p),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                color: _currentPage == p ? AppColors.primary : AppColors.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _currentPage == p ? AppColors.primary : const Color(0xFFE2E5EA),
                ),
              ),
              child: Text(
                '$p',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _currentPage == p ? AppColors.onPrimary : AppColors.textPrimary,
                ),
              ),
            ),
          ),
        IconButton(
          tooltip: 'Next page',
          icon: const Icon(Icons.chevron_right_rounded),
          color: _currentPage < _totalPages ? AppColors.textPrimary : AppColors.textHint,
          onPressed: _currentPage < _totalPages ? () => setState(() => _currentPage++) : null,
        ),
      ],
    );
  }
}

/// Bottom sheet: a staff member's face registration status with a
/// "Remove face" action (GET/DELETE /admin/face-recognition/:staffId).
class _FaceRegistrationSheet extends StatefulWidget {
  const _FaceRegistrationSheet({
    required this.staffId,
    required this.staffName,
    required this.onRemoved,
  });

  final String staffId;
  final String staffName;
  final ValueChanged<String> onRemoved;

  @override
  State<_FaceRegistrationSheet> createState() => _FaceRegistrationSheetState();
}

class _FaceRegistrationSheetState extends State<_FaceRegistrationSheet> {
  final _service = AdminStaffService();
  bool _loading = true;
  bool _removing = false;
  bool _enrolled = false;
  int _samples = 0;
  DateTime? _enrolledAt;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await _service.getStaffFaceStatus(widget.staffId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res['success'] == true) {
        _enrolled = res['enrolled'] == true;
        _samples = (res['samples'] is num) ? (res['samples'] as num).toInt() : 0;
        _enrolledAt =
            DateTime.tryParse(res['enrolledAt']?.toString() ?? '')?.toLocal();
      } else {
        _error = res['message']?.toString() ?? 'Could not read face registration.';
      }
    });
  }

  Future<void> _confirmAndRemove() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove registered face?'),
        content: Text(
          '${widget.staffName} will not be able to punch in with face '
          'verification until they register their face again. '
          'They will be asked to register on their next punch.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _removing = true);
    final res = await _service.resetStaffFace(widget.staffId);
    if (!mounted) return;
    setState(() => _removing = false);
    if (res['success'] == true) {
      Navigator.pop(context);
      widget.onRemoved(res['message']?.toString() ?? 'Face registration removed.');
    } else {
      SnackBarUtils.showSnackBar(
        context,
        res['message']?.toString() ?? 'Could not remove face registration.',
        isError: true,
      );
    }
  }

  String get _detailLine {
    if (!_enrolled) return 'Staff will be asked to register on their next punch.';
    final parts = <String>[
      if (_enrolledAt != null)
        'On ${DateFormat('dd MMM yyyy, hh:mm a').format(_enrolledAt!)}',
      _samples == 1 ? '1 sample' : '$_samples samples',
    ];
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Face Registration',
              style: AppTextStyles.headingMedium,
            ),
            const SizedBox(height: 4),
            Text(
              widget.staffName,
              style: AppTextStyles.bodySmall,
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
              )
            else if (_error != null)
              Row(
                children: [
                  const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _error!,
                      style: const TextStyle(fontSize: 13, color: AppColors.error),
                    ),
                  ),
                  TextButton(onPressed: _load, child: const Text('Retry')),
                ],
              )
            else ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _enrolled ? AppColors.successBg.withValues(alpha: 0.5) : AppColors.background,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _enrolled ? const Color(0xFFA7F3D0) : const Color(0xFFECEEF1),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: (_enrolled ? AppColors.success : AppColors.textSecondary).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        _enrolled ? Icons.verified_user_outlined : Icons.face_outlined,
                        size: 22,
                        color: _enrolled ? AppColors.success : AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _enrolled ? 'Face registered' : 'No face registered',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: _enrolled
                                  ? AppColors.success
                                  : AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _detailLine,
                            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (_enrolled) ...[
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _removing ? null : _confirmAndRemove,
                    icon: _removing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.delete_outline_rounded, size: 18),
                    label: Text(_removing ? 'Removing…' : 'Remove face'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.error,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      minimumSize: const Size(0, 48),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
