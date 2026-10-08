// Salary Overview: the month's salary register for every employee with a salary structure.
// GET /admin/staff/overview?month="August 2026". Tapping a row opens that employee's breakdown.

import 'package:flutter/material.dart';

import '../../../config/app_colors.dart';
import '../../../services/admin_salary_service.dart';
import 'admin_salary_overview_detail_screen.dart';
import 'admin_salary_ui.dart';

class AdminSalaryOverviewScreen extends StatefulWidget {
  const AdminSalaryOverviewScreen({super.key});

  @override
  State<AdminSalaryOverviewScreen> createState() => _AdminSalaryOverviewScreenState();
}

class _AdminSalaryOverviewScreenState extends State<AdminSalaryOverviewScreen> {
  final _search = TextEditingController();
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month, 1);
  String _status = 'All';
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = [];
  int _requestId = 0;

  static const _statuses = ['All', 'Released', 'Pending', 'On Hold'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool showLoader = true}) async {
    final req = ++_requestId;
    if (showLoader) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    final r = await AdminSalaryService.instance.getOverviewList(AdminUi.monthLabel(_month));
    if (!mounted || req != _requestId) return;
    setState(() {
      _loading = false;
      if (r['success'] == true) {
        _rows = List<Map<String, dynamic>>.from(r['data'] as List);
        _error = null;
      } else {
        _error = r['message']?.toString() ?? 'Could not load the salary overview.';
      }
    });
  }

  List<Map<String, dynamic>> get _filtered {
    final q = _search.text.trim().toLowerCase();
    return _rows.where((r) {
      final name = (r['name'] ?? '').toString().toLowerCase();
      final role = (r['role'] ?? '').toString().toLowerCase();
      final id = (r['id'] ?? '').toString().toLowerCase();
      final matches = q.isEmpty || name.contains(q) || role.contains(q) || id.contains(q);
      return matches && (_status == 'All' || r['status'] == _status);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final total = _rows.fold<double>(0, (s, r) => s + AdminUi.toDouble(r['netPay']));
    final avg = _rows.isEmpty ? 0.0 : total / _rows.length;
    final pending = _rows.where((r) => r['status'] == 'Pending').length;
    final slabs = _rows.map((r) => AdminUi.toDouble(r['baseSalary'])).toSet().length;
    final list = _filtered;

    return Scaffold(
      backgroundColor: AdminUi.bg,
      appBar: AdminUi.appBar('Salary Overview', actions: [
        IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded), tooltip: 'Refresh'),
      ]),
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: () => _load(showLoader: false),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            Row(children: [
              AdminMonthSwitcher(
                month: _month,
                onChanged: (m) {
                  setState(() => _month = m);
                  _load();
                },
              ),
              const Spacer(),
              _statusMenu(),
            ]),
            const SizedBox(height: 12),
            AdminSearchField(controller: _search, hint: 'Search salary registers...', onChanged: (_) => setState(() {})),
            const SizedBox(height: 16),
            if (_loading)
              const Padding(padding: EdgeInsets.only(top: 80), child: AdminLoading())
            else if (_error != null)
              Padding(padding: const EdgeInsets.only(top: 60), child: AdminErrorView(message: _error!, onRetry: _load))
            else ...[
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 2.1,
                children: [
                  AdminStatTile(label: 'Total Budget', value: AdminUi.money(total), icon: Icons.account_balance_wallet_outlined),
                  AdminStatTile(label: 'Average Net Pay', value: AdminUi.money(avg), icon: Icons.trending_up_rounded),
                  AdminStatTile(label: 'Pending Release', value: '$pending employees', icon: Icons.pending_actions_outlined),
                  AdminStatTile(label: 'Slabs Active', value: '$slabs Slabs', icon: Icons.layers_outlined),
                ],
              ),
              const SizedBox(height: 16),
              if (list.isEmpty)
                AdminEmptyView(
                  icon: Icons.receipt_long_outlined,
                  title: _rows.isEmpty ? 'No salary registers for ${AdminUi.monthLabel(_month)}' : 'No matching records',
                  subtitle: _rows.isEmpty ? 'Only employees with a salary structure appear here.' : 'Try another search or status.',
                )
              else
                ...list.map(_rowCard),
            ],
          ],
        ),
      ),
    );
  }

  Widget _statusMenu() => PopupMenuButton<String>(
        initialValue: _status,
        onSelected: (v) => setState(() => _status = v),
        itemBuilder: (_) => _statuses.map((s) => PopupMenuItem(value: s, child: Text(s))).toList(),
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E5EA)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.filter_list_rounded, size: 18, color: AdminUi.muted),
            const SizedBox(width: 6),
            Text(_status, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5, color: AdminUi.ink)),
            const SizedBox(width: 2),
            const Icon(Icons.expand_more_rounded, size: 18, color: AdminUi.muted),
          ]),
        ),
      );

  Widget _rowCard(Map<String, dynamic> r) {
    final name = (r['name'] ?? '').toString();
    final staffId = (r['staffId'] ?? '').toString();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AdminCard(
        onTap: staffId.isEmpty
            ? null
            : () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AdminSalaryOverviewDetailScreen(
                      staffId: staffId,
                      staffName: name,
                      initialMonth: AdminUi.monthLabel(_month),
                    ),
                  ),
                );
                if (mounted) _load(showLoader: false);
              },
        child: Column(children: [
          Row(children: [
            AdminAvatar(name),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AdminUi.ink)),
                const SizedBox(height: 2),
                Text('${r['id'] ?? ''} • ${r['role'] ?? ''}',
                    style: const TextStyle(fontSize: 12.5, color: AdminUi.muted), overflow: TextOverflow.ellipsis),
              ]),
            ),
            const SizedBox(width: 8),
            AdminPill((r['status'] ?? 'Pending').toString()),
          ]),
          const Divider(height: 28),
          Row(children: [
            _figure('Gross', AdminUi.money(AdminUi.toDouble(r['baseSalary']))),
            _figure('Allowances', AdminUi.money(AdminUi.toDouble(r['allowances']))),
            _figure('Deductions', AdminUi.money(AdminUi.toDouble(r['deductions'])), color: AdminUi.red),
            _figure('Net Pay', AdminUi.money(AdminUi.toDouble(r['netPay'])), color: AdminUi.green),
          ]),
        ]),
      ),
    );
  }

  Widget _figure(String label, String value, {Color color = AdminUi.ink}) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 11.5, color: AdminUi.muted, fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: color)),
          ),
        ]),
      );
}
