// Admin "Loans": dashboard with charts (GET /admin/loans/dashboard), the approval queue
// (GET /admin/loans/requests) and the loan register (GET /admin/loans) with the web's
// filters (category / loan type / department / branch / dates). The app-bar menu opens the
// other loan screens: Salary Advance, Disbursement, Payroll Recovery, Policies, Configuration.
// The loan admin APIs accept the `admin` role only.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../config/app_colors.dart';
import '../../../models/loan_models.dart';
import '../../../services/loan_service.dart';
import '../../../utils/error_message_utils.dart';
import '../../../widgets/app_tab_loader.dart';
import '../../loans/loan_detail_screen.dart';
import '../../loans/loan_widgets.dart';
import 'admin_loan_dashboard.dart';
import 'admin_loan_disbursement_screen.dart';
import 'admin_loan_request_screen.dart';
import 'admin_loan_settings_screen.dart';
import 'admin_loan_sheets.dart';
import 'admin_payroll_recovery_screen.dart';
import 'admin_salary_advance_screen.dart';

class AdminLoansScreen extends StatefulWidget {
  const AdminLoansScreen({super.key, this.initialTab = 1});
  final int initialTab; // 0 dashboard, 1 requests, 2 loans

  @override
  State<AdminLoansScreen> createState() => _AdminLoansScreenState();
}

class _AdminLoansScreenState extends State<AdminLoansScreen> {
  void _openScreen(String key) {
    final Widget screen = switch (key) {
      'advance' => const AdminSalaryAdvanceScreen(),
      'disburse' => const AdminLoanDisbursementScreen(),
      'payroll' => const AdminPayrollRecoveryScreen(),
      'policies' => const AdminLoanSettingsScreen(group: LoanSettingsGroup.policies),
      _ => const AdminLoanSettingsScreen(group: LoanSettingsGroup.configuration),
    };
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      initialIndex: widget.initialTab,
      child: Builder(
        builder: (context) => Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            title: const Text('Loans'),
            actions: [
              PopupMenuButton<String>(
                tooltip: 'More loan screens',
                icon: const Icon(Icons.more_vert_rounded),
                onSelected: _openScreen,
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'advance', child: Text('Salary Advance')),
                  PopupMenuItem(value: 'disburse', child: Text('Disbursement')),
                  PopupMenuItem(value: 'payroll', child: Text('Payroll Recovery')),
                  PopupMenuItem(value: 'policies', child: Text('Loan Policies')),
                  PopupMenuItem(value: 'config', child: Text('Configuration')),
                ],
              ),
            ],
            bottom: const TabBar(
              tabs: [Tab(text: 'Dashboard'), Tab(text: 'Approvals'), Tab(text: 'Loans')],
            ),
          ),
          body: TabBarView(children: [
            AdminLoanDashboard(onOpenTab: (i) => DefaultTabController.of(context).animateTo(i)),
            const _RequestsTab(),
            const _LoansTab(),
          ]),
        ),
      ),
    );
  }
}

Widget _errorView(String message, VoidCallback retry) => ListView(
      padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
      children: [
        Center(
          child: Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(color: AppColors.errorBg, shape: BoxShape.circle),
            child: const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 30),
          ),
        ),
        const SizedBox(height: 16),
        Text(message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, color: AppColors.textSecondary, height: 1.4)),
        const SizedBox(height: 8),
        TextButton(onPressed: retry, child: const Text('Retry')),
      ],
    );

/// Centered empty state: tinted icon circle + message.
Widget _emptyView(IconData icon, String message) => ListView(
      padding: const EdgeInsets.fromLTRB(24, 64, 24, 24),
      children: [
        Center(
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: Icon(icon, color: AppColors.primaryText, size: 30),
          ),
        ),
        const SizedBox(height: 16),
        Text(message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
      ],
    );

class _RequestsTab extends StatefulWidget {
  const _RequestsTab();
  @override
  State<_RequestsTab> createState() => _RequestsTabState();
}

class _RequestsTabState extends State<_RequestsTab> {
  static const _statuses = ['Pending', 'Need Clarification', 'Approved', 'Rejected', 'Cancelled', 'All'];
  String _status = 'Pending';
  String _search = '';
  LoanListFilters _filters = const LoanListFilters();
  Timer? _debounce;
  List<LoanRequest>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final list = await LoanService().adminRequests(
        status: _status,
        search: _search,
        category: _filters.category,
        loanType: _filters.loanType,
        department: _filters.department,
        branch: _filters.branch,
        from: _filters.from,
        to: _filters.to,
      );
      if (mounted) {
        setState(() {
          _items = list;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = ErrorMessageUtils.toUserFriendlyMessage(e));
    }
  }

  Future<void> _open(LoanRequest r) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => AdminLoanRequestScreen(requestId: r.id)));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _Filters(
          statuses: _statuses,
          filters: _filters,
          onFilters: (f) {
            setState(() {
              _filters = f;
              _items = null;
            });
            _load();
          },
          selected: _status,
          onStatus: (s) {
            setState(() {
              _status = s;
              _items = null;
            });
            _load();
          },
          onSearch: (q) {
            _search = q;
            _debounce?.cancel();
            _debounce = Timer(const Duration(milliseconds: 400), _load);
          },
        ),
        Expanded(
          child: _error != null
              ? _errorView(_error!, _load)
              : _items == null
                  ? const Center(child: AppTabLoader())
                  : RefreshIndicator(
                      color: AppColors.primary,
                      onRefresh: _load,
                      child: _items!.isEmpty
                          ? _emptyView(Icons.inbox_outlined, 'No requests.')
                          : ListView.separated(
                              padding: const EdgeInsets.all(16),
                              itemCount: _items!.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 12),
                              itemBuilder: (_, i) {
                                final r = _items![i];
                                return LoanCard(
                                  onTap: () => _open(r),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(r.employee.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                                            Text(
                                              '${r.isAdvance ? 'Salary Advance' : r.loanType} · ${r.requestNo} · ${loanDate(r.appliedOn)}',
                                              style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.4),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        children: [
                                          Text(loanMoney(r.requestedAmount),
                                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                                          const SizedBox(height: 4),
                                          LoanStatusChip(r.status),
                                        ],
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
        ),
      ],
    );
  }
}

class _LoansTab extends StatefulWidget {
  const _LoansTab();
  @override
  State<_LoansTab> createState() => _LoansTabState();
}

class _LoansTabState extends State<_LoansTab> {
  static const _statuses = ['All', 'Approved', 'Disbursed', 'Active', 'Defaulted', 'Completed', 'Closed', 'Cancelled'];
  String _status = 'All';
  String _search = '';
  LoanListFilters _filters = const LoanListFilters();
  Timer? _debounce;
  List<Loan>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final list = await LoanService().adminLoans(
        status: _status,
        search: _search,
        category: _filters.category,
        loanType: _filters.loanType,
        department: _filters.department,
        branch: _filters.branch,
        from: _filters.from,
        to: _filters.to,
      );
      if (mounted) {
        setState(() {
          _items = list;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = ErrorMessageUtils.toUserFriendlyMessage(e));
    }
  }

  Future<void> _open(Loan l) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => LoanDetailScreen(loanId: l.id, admin: true)));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _Filters(
          statuses: _statuses,
          filters: _filters,
          onFilters: (f) {
            setState(() {
              _filters = f;
              _items = null;
            });
            _load();
          },
          selected: _status,
          onStatus: (s) {
            setState(() {
              _status = s;
              _items = null;
            });
            _load();
          },
          onSearch: (q) {
            _search = q;
            _debounce?.cancel();
            _debounce = Timer(const Duration(milliseconds: 400), _load);
          },
        ),
        Expanded(
          child: _error != null
              ? _errorView(_error!, _load)
              : _items == null
                  ? const Center(child: AppTabLoader())
                  : RefreshIndicator(
                      color: AppColors.primary,
                      onRefresh: _load,
                      child: _items!.isEmpty
                          ? _emptyView(Icons.account_balance_wallet_outlined, 'No loans.')
                          : ListView.separated(
                              padding: const EdgeInsets.all(16),
                              itemCount: _items!.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 12),
                              itemBuilder: (_, i) {
                                final l = _items![i];
                                return LoanCard(
                                  onTap: () => _open(l),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(l.employee.name,
                                                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                                          ),
                                          const SizedBox(width: 8),
                                          LoanStatusChip(l.status),
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Text('${l.isAdvance ? 'Salary Advance' : l.loanType} · ${l.loanNo}',
                                          style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.4)),
                                      const Padding(
                                        padding: EdgeInsets.symmetric(vertical: 12),
                                        child: Divider(height: 1),
                                      ),
                                      Row(
                                        children: [
                                          Expanded(child: LoanStat('Principal', loanMoney(l.principal))),
                                          Expanded(child: LoanStat('EMI', loanMoney(l.emiAmount))),
                                          Expanded(
                                            child: LoanStat('Outstanding', loanMoney(l.outstanding),
                                                color: l.overdueAmount > 0 ? AppColors.error : null),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
        ),
      ],
    );
  }
}

/// Search box, filter button and status chips shared by the two list tabs.
class _Filters extends StatelessWidget {
  const _Filters({
    required this.statuses,
    required this.selected,
    required this.onStatus,
    required this.onSearch,
    required this.filters,
    required this.onFilters,
  });
  final List<String> statuses;
  final String selected;
  final ValueChanged<String> onStatus;
  final ValueChanged<String> onSearch;
  final LoanListFilters filters;
  final ValueChanged<LoanListFilters> onFilters;

  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(bottom: BorderSide(color: Color(0xFFECEEF1))),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    onChanged: onSearch,
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: 'Search employee or number',
                      prefixIcon: Icon(Icons.search_rounded, size: 20),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.outlined(
                  tooltip: 'Filters',
                  onPressed: () async {
                    final f = await showLoanFiltersSheet(context, filters);
                    if (f != null) onFilters(f);
                  },
                  icon: Badge(
                    isLabelVisible: filters.count > 0,
                    label: Text('${filters.count}'),
                    backgroundColor: AppColors.primary,
                    textColor: AppColors.onPrimary,
                    child: const Icon(Icons.tune_rounded, size: 20),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final s in statuses)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(s,
                            style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: s == selected ? FontWeight.w600 : FontWeight.w500,
                                color: s == selected ? AppColors.textPrimary : AppColors.textSecondary)),
                        selected: s == selected,
                        showCheckmark: false,
                        visualDensity: VisualDensity.compact,
                        onSelected: (_) => onStatus(s),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
}
