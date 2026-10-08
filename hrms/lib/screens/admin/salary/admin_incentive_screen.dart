// Incentive Management: the month's incentive figures for eligible staff, their approval, and
// who is eligible. GET /admin/staff/incentive?month&department&status plus locked-months;
// edit / approve / reject / eligibility / import live in admin_incentive_sheets.dart.

import 'package:flutter/material.dart';

import '../../../config/app_colors.dart';
import '../../../services/admin_salary_service.dart';
import '../../../utils/snackbar_utils.dart';
import 'admin_incentive_sheets.dart';
import 'admin_salary_ui.dart';

class AdminIncentiveScreen extends StatefulWidget {
  const AdminIncentiveScreen({super.key});

  @override
  State<AdminIncentiveScreen> createState() => _AdminIncentiveScreenState();
}

class _AdminIncentiveScreenState extends State<AdminIncentiveScreen> {
  static const _statuses = ['All', 'No Data', 'Pending', 'Approved', 'Rejected'];

  final _search = TextEditingController();
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month, 1);
  String _department = 'All';
  String _status = 'All';
  bool _showEligible = true;

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _eligible = [];
  List<Map<String, dynamic>> _notEligible = [];
  List<String> _departments = [];
  bool _monthLocked = false;
  Set<String> _lockedMonths = {};
  String? _approvingId;
  bool _exporting = false;
  int _requestId = 0;

  String get _monthLabel => AdminUi.monthLabel(_month);

  bool get _isPastMonth {
    final now = DateTime.now();
    return _month.isBefore(DateTime(now.year, now.month, 1));
  }

  @override
  void initState() {
    super.initState();
    _load();
    _loadLockedMonths();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadLockedMonths() async {
    final r = await AdminSalaryService.instance.getIncentiveLockedMonths();
    if (!mounted) return;
    if (r['success'] == true) {
      setState(() => _lockedMonths = Set<String>.from(r['data'] as List));
    } else {
      SnackBarUtils.showSnackBar(context, r['message']?.toString() ?? 'Could not load locked months.', isError: true);
    }
  }

  Future<void> _load({bool showLoader = true}) async {
    final req = ++_requestId;
    if (showLoader) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    final r = await AdminSalaryService.instance
        .getIncentiveList(_monthLabel, department: _department, status: _status);
    if (!mounted || req != _requestId) return;
    setState(() {
      _loading = false;
      if (r['success'] == true) {
        final d = Map<String, dynamic>.from(r['data'] as Map);
        List<Map<String, dynamic>> rows(dynamic v) => v is List
            ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)..['month'] = _monthLabel).toList()
            : [];
        _eligible = rows(d['eligible']);
        _notEligible = rows(d['notEligible']);
        _departments = (d['departments'] is List) ? (d['departments'] as List).map((e) => e.toString()).toList() : [];
        if (_department != 'All' && !_departments.contains(_department)) _departments = [..._departments, _department];
        _monthLocked = d['monthLocked'] == true;
        _error = null;
      } else {
        _error = r['message']?.toString() ?? 'Could not load incentives.';
      }
    });
  }

  Future<void> _refreshAll() async {
    await Future.wait([_load(showLoader: false), _loadLockedMonths()]);
  }

  List<Map<String, dynamic>> _searchFilter(List<Map<String, dynamic>> rows) {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return rows;
    return rows
        .where((r) =>
            (r['name'] ?? '').toString().toLowerCase().contains(q) ||
            (r['employeeId'] ?? '').toString().toLowerCase().contains(q))
        .toList();
  }

  // ── Actions ───────────────────────────────────────────────────────────

  Future<void> _approve(Map<String, dynamic> row) async {
    // A run that is over or already generated has to be routed to a later one.
    if (_isPastMonth || row['payrollGenerated'] == true) {
      if (await showIncentiveApproveSheet(context, row)) _load(showLoader: false);
      return;
    }
    setState(() => _approvingId = row['id'].toString());
    final r = await AdminSalaryService.instance.approveIncentive(row['id'].toString());
    if (!mounted) return;
    setState(() => _approvingId = null);
    if (r['success'] == true) {
      SnackBarUtils.showSnackBar(context, r['message']?.toString() ?? 'Incentive approved.');
      _load(showLoader: false);
    } else if (r['code'] == 'PAYROLL_MONTH_REQUIRED') {
      SnackBarUtils.showSnackBar(context, r['message']?.toString() ?? 'Choose which payroll run should pay this incentive.');
      if (await showIncentiveApproveSheet(context, row)) _load(showLoader: false);
    } else {
      SnackBarUtils.showSnackBar(context, r['message']?.toString() ?? 'Could not approve the incentive.', isError: true);
    }
  }

  Future<void> _export() async {
    if (_eligible.isEmpty && _notEligible.isEmpty) {
      SnackBarUtils.showSnackBar(context, 'There is nothing to export for the current filters.', isError: true);
      return;
    }
    String n(dynamic v) => v == null ? '' : v.toString();
    setState(() => _exporting = true);
    try {
      await writeAndOpenXlsx('incentives_${_monthLabel.replaceAll(' ', '_')}.xlsx', [
        [
          'Employee ID', 'Employee Name', 'Department', 'Branch', 'Incentive Eligibility',
          'Target', 'Achieved', 'Incentive Amount', 'Status', 'Rejection Reason', 'Approval Date',
        ],
        ..._eligible.map((r) => [
              n(r['employeeId']), n(r['name']), n(r['department']), n(r['branch']), 'Yes',
              n(r['target']), n(r['achieved']), n(r['incentiveAmount']), n(r['status']), n(r['rejectionReason']),
              r['reviewedAt'] != null && (r['status'] == 'Approved' || r['status'] == 'Payroll Processed')
                  ? AdminUi.date(r['reviewedAt'])
                  : '',
            ]),
        ..._notEligible.map((r) => [
              n(r['employeeId']), n(r['name']), n(r['department']), n(r['branch']), 'No', '', '', '', '', '', '',
            ]),
      ]);
      if (mounted) SnackBarUtils.showSnackBar(context, 'Incentive data exported.');
    } catch (e) {
      if (mounted) SnackBarUtils.showSnackBar(context, e.toString().replaceFirst('Exception: ', ''), isError: true);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  // ── UI ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final approvedAmount = _eligible
        .where((r) => r['status'] == 'Approved' || r['status'] == 'Payroll Processed')
        .fold<double>(0, (s, r) => s + AdminUi.toDouble(r['incentiveAmount']));
    final pending = _eligible.where((r) => r['status'] == 'Pending').length;
    final rows = _searchFilter(_showEligible ? _eligible : _notEligible);

    return Scaffold(
      backgroundColor: AdminUi.bg,
      appBar: AdminUi.appBar('Incentive', actions: [
        IconButton(
          tooltip: 'Manage eligibility',
          icon: const Icon(Icons.how_to_reg_rounded),
          onPressed: () async {
            // Refreshed however the sheet closed - a drag-dismiss returns no result.
            await showIncentiveEligibilitySheet(context, _monthLabel);
            if (mounted) _load(showLoader: false);
          },
        ),
        PopupMenuButton<String>(
          onSelected: (v) async {
            if (v == 'import') {
              await showIncentiveImportSheet(context, _monthLabel);
              if (mounted) _load(showLoader: false);
            } else if (v == 'export') {
              _export();
            } else if (v == 'refresh') {
              _load();
              _loadLockedMonths();
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'import', child: ListTile(leading: Icon(Icons.upload_file_rounded), title: Text('Import'))),
            PopupMenuItem(
                value: 'export',
                enabled: !_exporting,
                child: const ListTile(leading: Icon(Icons.download_rounded), title: Text('Export'))),
            const PopupMenuItem(value: 'refresh', child: ListTile(leading: Icon(Icons.refresh_rounded), title: Text('Refresh'))),
          ],
        ),
      ]),
      body: RefreshIndicator(
        color: AdminUi.accent,
        onRefresh: _refreshAll,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            Row(children: [
              AdminMonthSwitcher(
                month: _month,
                allowFuture: true,
                lockedMonths: _lockedMonths,
                onChanged: (m) {
                  setState(() => _month = m);
                  _load();
                },
              ),
              const Spacer(),
              _filterButton(),
            ]),
            const SizedBox(height: 12),
            AdminSearchField(controller: _search, hint: 'Search by name or employee ID', onChanged: (_) => setState(() {})),
            const SizedBox(height: 16),
            if (_loading)
              const Padding(padding: EdgeInsets.only(top: 80), child: AdminLoading())
            else if (_error != null)
              Padding(padding: const EdgeInsets.only(top: 60), child: AdminErrorView(message: _error!, onRetry: _load))
            else ...[
              if (_monthLocked)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: AdminUi.greyBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AdminUi.border),
                  ),
                  child: Row(children: [
                    const Icon(Icons.lock_outline_rounded, size: 18, color: AdminUi.muted),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('Payroll for $_monthLabel is processed. Paid incentives are locked.',
                          style: const TextStyle(fontSize: 13, color: AdminUi.muted)),
                    ),
                  ]),
                ),
              Row(children: [
                Expanded(child: AdminStatTile(label: 'Eligible', value: '${_eligible.length}', icon: Icons.how_to_reg_outlined)),
                const SizedBox(width: 12),
                Expanded(child: AdminStatTile(label: 'Pending', value: '$pending', icon: Icons.pending_actions_outlined)),
              ]),
              const SizedBox(height: 12),
              AdminStatTile(label: 'Approved amount', value: AdminUi.money(approvedAmount), icon: Icons.trending_up_rounded),
              const SizedBox(height: 16),
              SegmentedButton<bool>(
                segments: [
                  ButtonSegment(value: true, label: Text('Eligible (${_eligible.length})')),
                  ButtonSegment(value: false, label: Text('Not eligible (${_notEligible.length})')),
                ],
                selected: {_showEligible},
                showSelectedIcon: false,
                style: SegmentedButton.styleFrom(
                  selectedBackgroundColor: AppColors.primary,
                  selectedForegroundColor: AppColors.onPrimary,
                  backgroundColor: AppColors.surface,
                  foregroundColor: AdminUi.muted,
                  side: const BorderSide(color: Color(0xFFE2E5EA)),
                  textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onSelectionChanged: (s) => setState(() => _showEligible = s.first),
              ),
              const SizedBox(height: 16),
              if (rows.isEmpty)
                AdminEmptyView(
                  icon: Icons.emoji_events_outlined,
                  title: _showEligible ? 'No eligible employees' : 'Everyone is eligible',
                  subtitle: _showEligible ? 'Use Manage eligibility (top right) to enable staff for incentives.' : null,
                )
              else
                ...rows.map((r) => _showEligible ? _eligibleCard(r) : _ineligibleCard(r)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _filterButton() {
    final count = (_department != 'All' ? 1 : 0) + (_status != 'All' ? 1 : 0);
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 44),
        backgroundColor: AppColors.surface,
        padding: const EdgeInsets.symmetric(horizontal: 14),
      ),
      onPressed: _openFilters,
      icon: const Icon(Icons.filter_list_rounded, size: 18),
      label: Text(count > 0 ? 'Filters ($count)' : 'Filters'),
    );
  }

  Future<void> _openFilters() async {
    String dept = _department;
    String status = _status;
    final apply = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.white,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('Filters', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18, color: AdminUi.ink)),
              const SizedBox(height: 20),
              DropdownButtonFormField<String>(
                initialValue: dept,
                decoration: AdminUi.input('Department'),
                items: ['All', ..._departments]
                    .map((d) => DropdownMenuItem(value: d, child: Text(d, overflow: TextOverflow.ellipsis)))
                    .toList(),
                onChanged: (v) => setS(() => dept = v ?? 'All'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: status,
                decoration: AdminUi.input('Status'),
                items: _statuses.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                onChanged: (v) => setS(() => status = v ?? 'All'),
              ),
              const SizedBox(height: 24),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => setS(() {
                      dept = 'All';
                      status = 'All';
                    }),
                    child: const Text('Reset'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                      style: AdminUi.primaryButton(), onPressed: () => Navigator.pop(ctx, true), child: const Text('Apply')),
                ),
              ]),
            ]),
          ),
        ),
      ),
    );
    if (apply == true && mounted) {
      setState(() {
        _department = dept;
        _status = status;
      });
      _load();
    }
  }

  Widget _figure(String label, String value) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 11.5, color: AdminUi.muted, fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AdminUi.ink)),
        ]),
      );

  String _plain(dynamic v) {
    if (v == null) return '—';
    final d = AdminUi.toDouble(v);
    return d == d.roundToDouble() ? d.toInt().toString() : d.toStringAsFixed(2);
  }

  Widget _eligibleCard(Map<String, dynamic> r) {
    final status = (r['status'] ?? 'No Data').toString();
    final name = (r['name'] ?? '').toString();
    final locked = r['locked'] == true;
    final deactivated = r['deactivated'] == true;
    final id = r['id']?.toString();
    final canWork = !locked && !deactivated && id != null && (status == 'Pending' || status == 'Rejected');

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AdminCard(
        onTap: status == 'No Data' ? null : () => _showDetails(r),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            AdminAvatar(name),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AdminUi.ink)),
                const SizedBox(height: 2),
                Text(
                  [r['employeeId'], r['department'], r['branch']]
                      .where((v) => v != null && v.toString().isNotEmpty)
                      .join(' • '),
                  style: const TextStyle(fontSize: 12.5, color: AdminUi.muted),
                  overflow: TextOverflow.ellipsis,
                ),
              ]),
            ),
            const SizedBox(width: 8),
            AdminPill(status == 'No Data' ? 'Awaiting Data' : status),
            if (canWork)
              _approvingId == id
                  ? const Padding(
                      padding: EdgeInsets.all(10),
                      child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
                  : PopupMenuButton<String>(
                      tooltip: 'Actions',
                      icon: const Icon(Icons.more_vert_rounded, color: AdminUi.muted),
                      onSelected: (v) async {
                        if (v == 'edit') {
                          if (await showIncentiveEditSheet(context, r)) _load(showLoader: false);
                        } else if (v == 'reject') {
                          if (await showIncentiveRejectSheet(context, r)) _load(showLoader: false);
                        } else if (v == 'approve') {
                          _approve(r);
                        }
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(value: 'edit', child: Text('Edit')),
                        if (status != 'Rejected') ...[
                          const PopupMenuItem(value: 'reject', child: Text('Reject')),
                          const PopupMenuItem(value: 'approve', child: Text('Approve')),
                        ],
                      ],
                    ),
          ]),
          if (status != 'No Data') ...[
            const Divider(height: 24),
            Row(children: [
              _figure('Target', _plain(r['target'])),
              _figure('Achieved', _plain(r['achieved'])),
              _figure('Incentive', AdminUi.money(r['incentiveAmount'] == null ? null : AdminUi.toDouble(r['incentiveAmount']))),
            ]),
          ],
          if (locked || deactivated || r['deferred'] == true || r['edited'] == true) ...[
            const SizedBox(height: 12),
            Wrap(spacing: 6, runSpacing: 6, children: [
              if (locked) const AdminPill('Locked', fg: AdminUi.muted, bg: AdminUi.greyBg),
              if (deactivated) const AdminPill('Deactivated', fg: AdminUi.red, bg: AdminUi.redBg),
              if (r['deferred'] == true && (r['payrollMonth'] ?? '').toString().isNotEmpty)
                AdminPill('Paid in ${r['payrollMonth']}', fg: AdminUi.blue, bg: AdminUi.blueBg),
              if (r['edited'] == true) const AdminPill('Edited', fg: AdminUi.amber, bg: AdminUi.amberBg),
            ]),
          ],
          if (status == 'Rejected' && (r['rejectionReason'] ?? '').toString().isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: AdminUi.redBg, borderRadius: BorderRadius.circular(12)),
              child: Text('Reason: ${r['rejectionReason']}',
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: AdminUi.red)),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _ineligibleCard(Map<String, dynamic> r) {
    final name = (r['name'] ?? '').toString();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AdminCard(
        child: Row(children: [
          AdminAvatar(name),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AdminUi.ink)),
              const SizedBox(height: 2),
              Text(
                [r['employeeId'], r['department'], r['branch']]
                    .where((v) => v != null && v.toString().isNotEmpty)
                    .join(' • '),
                style: const TextStyle(fontSize: 12.5, color: AdminUi.muted),
              ),
            ]),
          ),
          const AdminPill('Not eligible'),
        ]),
      ),
    );
  }

  void _showDetails(Map<String, dynamic> r) {
    final imported = r['imported'] is Map ? Map<String, dynamic>.from(r['imported'] as Map) : null;
    Widget kv(String k, String v, {Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 130, child: Text(k, style: const TextStyle(fontSize: 13, color: AdminUi.muted))),
            Expanded(
                child: Text(v, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: color ?? AdminUi.ink))),
          ]),
        );
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text((r['name'] ?? '').toString(), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 18, color: AdminUi.ink)),
            const SizedBox(height: 4),
            Text('${r['employeeId'] ?? ''} • $_monthLabel', style: const TextStyle(fontSize: 13, color: AdminUi.muted)),
            const SizedBox(height: 16),
            kv('Status', (r['status'] ?? '').toString()),
            kv('Target', _plain(r['target'])),
            kv('Achieved', _plain(r['achieved'])),
            kv('Incentive amount', AdminUi.money(AdminUi.toDouble(r['incentiveAmount']))),
            if ((r['payrollMonth'] ?? '').toString().isNotEmpty) kv('Payroll run', r['payrollMonth'].toString()),
            if ((r['reviewedByName'] ?? '').toString().isNotEmpty) kv('Reviewed by', r['reviewedByName'].toString()),
            if (r['reviewedAt'] != null) kv('Reviewed on', AdminUi.date(r['reviewedAt'])),
            if (r['status'] == 'Rejected') kv('Rejection reason', (r['rejectionReason'] ?? '').toString(), color: AdminUi.red),
            if (imported != null && r['edited'] == true) ...[
              const Divider(height: 24),
              const Text('As imported', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5, color: AdminUi.ink)),
              const SizedBox(height: 4),
              kv('Target', _plain(imported['target'])),
              kv('Achieved', _plain(imported['achieved'])),
              kv('Incentive amount', AdminUi.money(AdminUi.toDouble(imported['incentiveAmount']))),
              if (imported['importedAt'] != null) kv('Imported on', AdminUi.date(imported['importedAt'])),
            ],
          ]),
        ),
      ),
    );
  }
}
