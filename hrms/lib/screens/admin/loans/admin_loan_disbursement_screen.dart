// Disbursement (web loans/pages/Disbursement.tsx): approved loans and advances waiting to be
// paid out (GET /admin/loans?status=Approved) with a Disburse action (mode / date / reference /
// remarks - POST /admin/loans/:id/disburse), and the recently disbursed ones.

import 'package:flutter/material.dart';

import '../../../config/app_colors.dart';
import '../../../models/loan_models.dart';
import '../../../services/loan_service.dart';
import '../../../utils/error_message_utils.dart';
import '../../../widgets/app_tab_loader.dart';
import '../../loans/loan_detail_screen.dart';
import '../../loans/loan_widgets.dart';
import 'admin_loan_sheets.dart';

class AdminLoanDisbursementScreen extends StatelessWidget {
  const AdminLoanDisbursementScreen({super.key});

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 2,
        child: Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            title: const Text('Disbursement'),
            bottom: const TabBar(
              tabs: [Tab(text: 'Approved'), Tab(text: 'Disbursed')],
            ),
          ),
          body: const TabBarView(children: [_Queue(awaiting: true), _Queue(awaiting: false)]),
        ),
      );
}

class _Queue extends StatefulWidget {
  const _Queue({required this.awaiting});
  final bool awaiting;
  @override
  State<_Queue> createState() => _QueueState();
}

class _QueueState extends State<_Queue> with AutomaticKeepAliveClientMixin {
  List<Loan>? _items;
  String? _error;
  String _search = '';

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final List<Loan> list;
      if (widget.awaiting) {
        list = await LoanService().adminLoans(status: 'Approved');
      } else {
        list = (await LoanService().adminLoans()).where((l) => l.disbursedOn != null).toList()
          ..sort((a, b) => b.disbursedOn!.compareTo(a.disbursedOn!));
      }
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

  Future<void> _disburse(Loan l) async {
    final updated = await showLoanDisburseSheet(context, l);
    if (updated != null && mounted) {
      setState(() => _items = _items?.where((x) => x.id != l.id).toList());
    }
  }

  Future<void> _open(Loan l) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => LoanDetailScreen(loanId: l.id, admin: true)));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_error != null && _items == null) {
      return adminLoanErrorView(_error!, _load);
    }
    final items = _items;
    if (items == null) return const Center(child: AppTabLoader());
    final term = _search.trim().toLowerCase();
    final rows = term.isEmpty
        ? items
        : items
            .where((l) => '${l.employee.name} ${l.employee.employeeId} ${l.loanNo} ${l.loanType}'.toLowerCase().contains(term))
            .toList();
    return Column(
      children: [
        Container(
          decoration: adminLoanToolbarDecoration,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: TextField(
            onChanged: (v) => setState(() => _search = v),
            decoration: const InputDecoration(
              isDense: true,
              hintText: 'Search employee or loan number',
              prefixIcon: Icon(Icons.search_rounded, size: 20),
            ),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            color: AppColors.primary,
            onRefresh: _load,
            child: rows.isEmpty
                ? adminLoanEmptyView(
                    widget.awaiting ? Icons.hourglass_empty_rounded : Icons.payments_outlined,
                    widget.awaiting ? 'Nothing waiting to be disbursed.' : 'No disbursements yet.',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: rows.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (_, i) {
                      final l = rows[i];
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
                            Text(
                              '${l.isAdvance ? 'Salary Advance' : l.loanType} · ${l.loanNo}'
                              '${l.employee.department.isNotEmpty ? ' · ${l.employee.department}' : ''}',
                              style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                            ),
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: Divider(height: 1),
                            ),
                            Row(
                              children: [
                                Expanded(child: LoanStat('Amount', loanMoney(l.principal))),
                                Expanded(child: LoanStat('EMI', loanMoney(l.emiAmount))),
                                Expanded(
                                  child: widget.awaiting
                                      ? LoanStat('Tenure', '${l.tenure} mo')
                                      : LoanStat('Disbursed', loanDate(l.disbursedOn)),
                                ),
                              ],
                            ),
                            if (!widget.awaiting && l.disbursementMode.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 10),
                                child: Row(
                                  children: [
                                    const Icon(Icons.receipt_long_outlined, size: 16, color: AppColors.textSecondary),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        [l.disbursementMode, if (l.disbursementRef.isNotEmpty) l.disbursementRef].join(' · '),
                                        style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            if (widget.awaiting) ...[
                              const SizedBox(height: 16),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: () => _disburse(l),
                                  icon: const Icon(Icons.payments_outlined, size: 18),
                                  label: const Text('Disburse'),
                                ),
                              ),
                            ],
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
