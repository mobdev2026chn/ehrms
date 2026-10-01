// Admin "Loans": overview (GET /admin/loans/dashboard), the approval queue
// (GET /admin/loans/requests) and the loan register (GET /admin/loans), like the web.
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
import 'admin_loan_request_screen.dart';

class AdminLoansScreen extends StatefulWidget {
  const AdminLoansScreen({super.key, this.initialTab = 1});
  final int initialTab; // 0 overview, 1 requests, 2 loans

  @override
  State<AdminLoansScreen> createState() => _AdminLoansScreenState();
}

class _AdminLoansScreenState extends State<AdminLoansScreen> {
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      initialIndex: widget.initialTab,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('Loans', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
          backgroundColor: Colors.white,
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          bottom: const TabBar(
            labelColor: AppColors.brandDark,
            unselectedLabelColor: AppColors.textSecondary,
            indicatorColor: AppColors.brand,
            tabs: [Tab(text: 'Overview'), Tab(text: 'Requests'), Tab(text: 'Loans')],
          ),
        ),
        body: const TabBarView(children: [_OverviewTab(), _RequestsTab(), _LoansTab()]),
      ),
    );
  }
}

Widget _errorView(String message, VoidCallback retry) => ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(message, textAlign: TextAlign.center),
        TextButton(onPressed: retry, child: const Text('Retry')),
      ],
    );

class _OverviewTab extends StatefulWidget {
  const _OverviewTab();
  @override
  State<_OverviewTab> createState() => _OverviewTabState();
}

class _OverviewTabState extends State<_OverviewTab> {
  Map<String, dynamic>? _totals;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await LoanService().adminDashboard();
      if (mounted) setState(() => _totals = d['totals'] is Map ? Map<String, dynamic>.from(d['totals']) : {});
    } catch (e) {
      if (mounted) setState(() => _error = ErrorMessageUtils.toUserFriendlyMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return _errorView(_error!, _load);
    final t = _totals;
    if (t == null) return const Center(child: AppTabLoader());
    num n(String k) => (t[k] as num?) ?? 0;
    final tiles = <(String, String, Color?)>[
      ('Pending requests', '${n('pending')}', AppColors.brandDark),
      ('Total loans', '${n('totalLoans')}', null),
      ('Approved (to disburse)', '${n('approved')}', null),
      ('Disbursed', '${n('disbursed')}', null),
      ('Overdue loans', '${n('overdue')}', n('overdue') > 0 ? AppColors.error : null),
      ('Defaulted', '${n('defaulted')}', n('defaulted') > 0 ? AppColors.error : null),
      ('Amount disbursed', loanMoney(n('disbursedAmount')), null),
      ('Recovered', loanMoney(n('recoveredAmount')), AppColors.success),
      ('Outstanding', loanMoney(n('outstandingAmount')), null),
      ('Overdue amount', loanMoney(n('overdueAmount')), n('overdueAmount') > 0 ? AppColors.error : null),
      ('Interest earned', loanMoney(n('interestEarned')), null),
      ('Active advances', '${n('activeAdvances')}', null),
    ];
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _load,
      child: GridView.count(
        padding: const EdgeInsets.all(16),
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 2.2,
        children: [
          for (final (label, value, color) in tiles) LoanCard(child: LoanStat(label, value, color: color)),
        ],
      ),
    );
  }
}

class _RequestsTab extends StatefulWidget {
  const _RequestsTab();
  @override
  State<_RequestsTab> createState() => _RequestsTabState();
}

class _RequestsTabState extends State<_RequestsTab> {
  static const _statuses = ['Pending', 'Need Clarification', 'Approved', 'Rejected', 'Cancelled', 'All'];
  String _status = 'Pending';
  String _search = '';
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
      final list = await LoanService().adminRequests(status: _status, search: _search);
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
                          ? ListView(children: const [
                              Padding(
                                padding: EdgeInsets.all(32),
                                child: Center(child: Text('No requests.', style: TextStyle(color: AppColors.textSecondary))),
                              ),
                            ])
                          : ListView.separated(
                              padding: const EdgeInsets.all(16),
                              itemCount: _items!.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 10),
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
                                            Text(r.employee.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                                            Text(
                                              '${r.isAdvance ? 'Salary Advance' : r.loanType} · ${r.requestNo} · ${loanDate(r.appliedOn)}',
                                              style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        children: [
                                          Text(loanMoney(r.requestedAmount),
                                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
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
      final list = await LoanService().adminLoans(status: _status, search: _search);
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
                          ? ListView(children: const [
                              Padding(
                                padding: EdgeInsets.all(32),
                                child: Center(child: Text('No loans.', style: TextStyle(color: AppColors.textSecondary))),
                              ),
                            ])
                          : ListView.separated(
                              padding: const EdgeInsets.all(16),
                              itemCount: _items!.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 10),
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
                                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                                          ),
                                          LoanStatusChip(l.status),
                                        ],
                                      ),
                                      Text('${l.isAdvance ? 'Salary Advance' : l.loanType} · ${l.loanNo}',
                                          style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
                                      const SizedBox(height: 8),
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

/// Search box + status chips shared by the two list tabs.
class _Filters extends StatelessWidget {
  const _Filters({required this.statuses, required this.selected, required this.onStatus, required this.onSearch});
  final List<String> statuses;
  final String selected;
  final ValueChanged<String> onStatus;
  final ValueChanged<String> onSearch;

  @override
  Widget build(BuildContext context) => Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
        child: Column(
          children: [
            TextField(
              onChanged: onSearch,
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Search employee or number',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                filled: true,
                fillColor: AppColors.inputFill,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final s in statuses)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(s, style: const TextStyle(fontSize: 12)),
                        selected: s == selected,
                        selectedColor: AppColors.brandLight,
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
