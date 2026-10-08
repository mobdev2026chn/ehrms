// Staff "Employee Loans" - laid out like the web /staff/loans page: summary boxes
// (Outstanding Loan, Monthly EMI, Remaining EMI, Next Deduction), the four action tiles
// (Request Loan, Salary Advance, EMI Schedule, Loan History), Approval Status and
// My Active Loans. Data: GET /staff/loans/policy + GET /staff/loans.

import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../config/app_text_styles.dart';
import '../../models/loan_models.dart';
import '../../services/loan_service.dart';
import '../../utils/error_message_utils.dart';
import '../../widgets/app_card.dart';
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
        title: const Text('Employee Loans'),
      ),
      body: _loading
          ? const Center(child: AppTabLoader())
          : RefreshIndicator(
              color: AppColors.primary,
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: _error != null
                    ? [
                        LoanCard(
                          padding: const EdgeInsets.all(20),
                          child: Column(children: [
                            Container(
                              width: 64,
                              height: 64,
                              decoration: const BoxDecoration(color: AppColors.errorBg, shape: BoxShape.circle),
                              child: const Icon(Icons.error_outline_rounded, size: 28, color: AppColors.error),
                            ),
                            const SizedBox(height: 12),
                            Text(_error!, textAlign: TextAlign.center, style: AppTextStyles.bodyMedium),
                            const SizedBox(height: 8),
                            TextButton(onPressed: _load, child: const Text('Retry')),
                          ]),
                        ),
                      ]
                    : [
                        _summary(),
                        const SizedBox(height: 16),
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
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.sectionLabel.copyWith(letterSpacing: 0.6, color: AppColors.textSecondary)),
                const SizedBox(height: 8),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(value,
                      style: AppTextStyles.headingMedium.copyWith(
                          fontSize: 20, fontWeight: FontWeight.w700, color: color ?? AppColors.textPrimary)),
                ),
              ],
            ),
          ),
        );
    return LoanCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(children: [
            box('OUTSTANDING LOAN', loanMoney(outstanding), color: AppColors.primaryText),
            const SizedBox(width: 12),
            box('MONTHLY EMI', loanMoney(emi)),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            box('REMAINING EMI', live.isEmpty ? '—' : '$remaining'),
            const SizedBox(width: 12),
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
            padding: EdgeInsets.only(bottom: i + 2 < tiles.length ? 12 : 0),
            child: Row(children: [
              Expanded(child: tiles[i]),
              const SizedBox(width: 12),
              Expanded(child: i + 1 < tiles.length ? tiles[i + 1] : const SizedBox.shrink()),
            ]),
          ),
      ],
    );
  }

  Widget _tile(String label, IconData icon, {bool filled = false, bool enabled = true, required VoidCallback onTap}) {
    final bg = filled ? AppColors.primary : AppColors.surface;
    return SizedBox(
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: filled ? null : kSoftCardShadow,
          ),
          child: Material(
            color: bg,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: enabled ? onTap : null,
              child: Container(
                height: 96,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: filled ? null : Border.all(color: kLoanHairline),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: filled ? AppColors.onPrimary : AppColors.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(icon, size: 20, color: filled ? AppColors.primary : AppColors.primaryText),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.label.copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: filled ? AppColors.onPrimary : AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _emptyCard(IconData icon, String text) => LoanCard(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        child: LoanEmptyState(icon, text),
      );

  List<Widget> _approvalStatus() {
    final pending = _pendingRequests;
    if (pending.isEmpty) return [_emptyCard(Icons.hourglass_empty_rounded, 'No pending requests')];
    return [
      for (final r in pending)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: LoanCard(
            onTap: () => _push(LoanRequestDetailScreen(requestId: r.id)),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.schedule_rounded, color: AppColors.primaryText, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r.isAdvance ? 'Salary Advance' : r.loanType,
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.label.copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(loanMoney(r.requestedAmount), style: AppTextStyles.headingSmall.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text('Applied ${loanDate(r.appliedOn)}', style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    LoanStatusChip(r.status),
                    if (r.needsClarification)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text('Reply needed',
                            style: AppTextStyles.caption.copyWith(color: AppColors.info, fontWeight: FontWeight.w600)),
                      ),
                  ],
                ),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right_rounded, color: AppColors.textCaption),
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
          padding: const EdgeInsets.only(bottom: 12),
          child: LoanCard(
            onTap: () => _push(LoanDetailScreen(loanId: l.id)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                    child: Text(l.isAdvance ? 'Salary Advance' : l.loanType,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.headingSmall),
                  ),
                  const SizedBox(width: 8),
                  LoanStatusChip(l.status),
                ]),
                const SizedBox(height: 2),
                Text(l.loanNo, style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary)),
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: LoanStat('Principal', loanMoney(l.principal))),
                  Expanded(child: LoanStat('EMI', loanMoney(l.emiAmount))),
                  Expanded(
                    child: LoanStat('Outstanding', loanMoney(l.outstanding), color: l.overdueAmount > 0 ? AppColors.error : null),
                  ),
                ]),
                if (l.tenure > 0) ...[
                  const SizedBox(height: 16),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: (l.paidEmis / l.tenure).clamp(0.0, 1.0),
                      minHeight: 6,
                      backgroundColor: AppColors.inputFill,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${l.paidEmis} of ${l.tenure} EMIs paid${l.nextDueDate != null ? ' · next ${loanDate(l.nextDueDate)}' : ''}',
                    style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
                  ),
                ],
              ],
            ),
          ),
        ),
    ];
  }
}
