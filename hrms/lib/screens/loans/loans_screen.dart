// Staff "Employee Loans" - laid out like the web /staff/loans page: summary boxes
// (Outstanding Loan, Monthly EMI, Remaining EMI, Next Deduction), the four action tiles
// (Request Loan, Salary Advance, EMI Schedule, Loan History), Approval Status and
// My Active Loans. Data: GET /staff/loans/policy + GET /staff/loans.

import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../models/loan_models.dart';
import '../../services/loan_service.dart';
import '../../utils/error_message_utils.dart';
import '../../widgets/app_tab_loader.dart';
import 'loan_apply_screen.dart';
import 'loan_detail_screen.dart';
import 'loan_emi_schedule_screen.dart';
import 'loan_history_screen.dart';
import 'loan_request_detail_screen.dart';
import 'loan_widgets.dart';

class LoansScreen extends StatefulWidget {
  const LoansScreen({super.key});

  @override
  State<LoansScreen> createState() => _LoansScreenState();
}

class _LoansScreenState extends State<LoansScreen> {
  final _service = LoanService();
  LoanPolicyView? _policy;
  List<Loan> _loans = [];
  List<LoanRequest> _requests = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _policy == null;
      _error = null;
    });
    try {
      final results = await Future.wait([_service.getPolicy(), _service.getMyLoans()]);
      final mine = results[1] as ({List<Loan> loans, List<LoanRequest> requests});
      if (!mounted) return;
      setState(() {
        _policy = results[0] as LoanPolicyView;
        _loans = mine.loans;
        _requests = mine.requests;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = ErrorMessageUtils.toUserFriendlyMessage(e);
      });
    }
  }

  List<Loan> get _activeLoans => _loans.where((l) => l.isLive).toList();

  /// Approval Status = requests still in the approval flow (as on web).
  List<LoanRequest> get _pendingRequests => _requests.where((r) => r.isOpen).toList();

  Future<void> _push(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Employee Loans', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: _loading
          ? const Center(child: AppTabLoader())
          : RefreshIndicator(
              color: AppColors.primary,
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: _error != null
                    ? [
                        LoanCard(
                          child: Column(children: [
                            Text(_error!, textAlign: TextAlign.center),
                            TextButton(onPressed: _load, child: const Text('Retry')),
                          ]),
                        ),
                      ]
                    : [
                        _summary(),
                        const SizedBox(height: 14),
                        _actionTiles(),
                        // Like web: the section only appears while a request is in approval.
                        if (_pendingRequests.isNotEmpty) ...[
                          const LoanSectionTitle('Approval Status'),
                          ..._approvalStatus(),
                        ],
                        const LoanSectionTitle('My Active Loans'),
                        ..._activeLoanList(),
                      ],
              ),
            ),
    );
  }

  Widget _summary() {
    final live = _activeLoans;
    final outstanding = live.fold<double>(0, (s, l) => s + l.outstanding);
    final emi = live.fold<double>(0, (s, l) => s + l.emiAmount);
    final remaining = live.fold<int>(0, (s, l) => s + (l.tenure - l.paidEmis).clamp(0, l.tenure));
    final due = live.map((l) => l.nextDueDate).whereType<DateTime>().toList()..sort();
    Widget box(String label, String value, {Color? color}) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.divider),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: AppColors.textSecondary)),
                const SizedBox(height: 6),
                Text(value, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: color ?? AppColors.textPrimary)),
              ],
            ),
          ),
        );
    return LoanCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(children: [
            box('OUTSTANDING LOAN', loanMoney(outstanding), color: AppColors.brandDark),
            const SizedBox(width: 10),
            box('MONTHLY EMI', loanMoney(emi)),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            box('REMAINING EMI', live.isEmpty ? '—' : '$remaining'),
            const SizedBox(width: 10),
            box('NEXT DEDUCTION', due.isEmpty ? '—' : loanDate(due.first)),
          ]),
        ],
      ),
    );
  }

  /// The web's tiles. Request Loan is hidden (not greyed) when the salary is below the
  /// loan minimum (`meetsMinSalary`), exactly as web does; Salary Advance shows whenever
  /// advances are enabled. EMI Schedule is greyed until there is an active loan.
  Widget _actionTiles() {
    final p = _policy!;
    final showLoan = p.loanModuleEnabled && p.eligibility.meetsMinSalary && p.loanTypes.isNotEmpty;
    final showAdvance = p.salaryAdvanceEnabled;
    final tiles = <Widget>[
      if (showLoan)
        _tile('Request Loan', Icons.add, filled: true, onTap: () async {
          final ok = await Navigator.of(context).push<bool>(
            MaterialPageRoute(builder: (_) => LoanApplyScreen(policy: p, category: 'Loan')),
          );
          if (ok == true) _load();
        }),
      if (showAdvance)
        _tile('Salary Advance', Icons.add, filled: true, onTap: () async {
          final ok = await Navigator.of(context).push<bool>(
            MaterialPageRoute(builder: (_) => LoanApplyScreen(policy: p, category: 'SalaryAdvance')),
          );
          if (ok == true) _load();
        }),
      _tile('EMI Schedule', Icons.event_note_outlined,
          enabled: _activeLoans.isNotEmpty, onTap: () => _push(LoanEmiScheduleScreen(loans: _activeLoans))),
      _tile('Loan History', Icons.history_rounded, onTap: () => _push(LoanHistoryScreen(loans: _loans, requests: _requests))),
    ];
    // Two tiles per row.
    return Column(
      children: [
        for (var i = 0; i < tiles.length; i += 2)
          Padding(
            padding: EdgeInsets.only(bottom: i + 2 < tiles.length ? 10 : 0),
            child: Row(children: [
              Expanded(child: tiles[i]),
              const SizedBox(width: 10),
              Expanded(child: i + 1 < tiles.length ? tiles[i + 1] : const SizedBox.shrink()),
            ]),
          ),
      ],
    );
  }

  Widget _tile(String label, IconData icon, {bool filled = false, bool enabled = true, required VoidCallback onTap}) {
    final bg = filled ? AppColors.brand : Colors.white;
    return SizedBox(
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        child: Material(
          color: bg,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: enabled ? onTap : null,
            child: Container(
              height: 88,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: filled ? null : Border.all(color: AppColors.divider),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: filled ? const Color(0xFF111111) : AppColors.brandLight,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, size: 18, color: filled ? Colors.white : AppColors.brandDark),
                  ),
                  const SizedBox(height: 8),
                  Text(label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _emptyCard(IconData icon, String text) => LoanCard(
        padding: const EdgeInsets.symmetric(vertical: 28),
        child: Center(
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: AppColors.brandLight, borderRadius: BorderRadius.circular(14)),
                child: Icon(icon, color: AppColors.brandDark),
              ),
              const SizedBox(height: 10),
              Text(text, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
            ],
          ),
        ),
      );

  List<Widget> _approvalStatus() {
    final pending = _pendingRequests;
    if (pending.isEmpty) return [_emptyCard(Icons.hourglass_empty_rounded, 'No pending requests')];
    return [
      for (final r in pending)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: LoanCard(
            onTap: () => _push(LoanRequestDetailScreen(requestId: r.id)),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: AppColors.brandLight, borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.schedule_rounded, color: AppColors.brandDark, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r.isAdvance ? 'Salary Advance' : r.loanType,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text(loanMoney(r.requestedAmount), style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
                      Text('Applied ${loanDate(r.appliedOn)}', style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    LoanStatusChip(r.status),
                    if (r.needsClarification)
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text('Reply needed', style: TextStyle(fontSize: 11, color: AppColors.info, fontWeight: FontWeight.w700)),
                      ),
                  ],
                ),
                const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
              ],
            ),
          ),
        ),
    ];
  }

  List<Widget> _activeLoanList() {
    final live = _activeLoans;
    if (live.isEmpty) return [_emptyCard(Icons.account_balance_outlined, 'No active loans')];
    return [
      for (final l in live)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: LoanCard(
            onTap: () => _push(LoanDetailScreen(loanId: l.id)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                    child: Text(l.isAdvance ? 'Salary Advance' : l.loanType,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                  ),
                  LoanStatusChip(l.status),
                ]),
                Text(l.loanNo, style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: LoanStat('Principal', loanMoney(l.principal))),
                  Expanded(child: LoanStat('EMI', loanMoney(l.emiAmount))),
                  Expanded(
                    child: LoanStat('Outstanding', loanMoney(l.outstanding), color: l.overdueAmount > 0 ? AppColors.error : null),
                  ),
                ]),
                if (l.tenure > 0) ...[
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: (l.paidEmis / l.tenure).clamp(0.0, 1.0),
                      minHeight: 6,
                      backgroundColor: AppColors.inputFill,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${l.paidEmis} of ${l.tenure} EMIs paid${l.nextDueDate != null ? ' · next ${loanDate(l.nextDueDate)}' : ''}',
                    style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
                  ),
                ],
              ],
            ),
          ),
        ),
    ];
  }
}
