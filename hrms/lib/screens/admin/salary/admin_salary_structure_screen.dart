// Salary Structure: pick an employee to see, add or revise their salary structure.
// The staff directory is GET /admin/staff; the structure itself opens in
// AdminSalaryStructureDetailScreen.

import 'package:flutter/material.dart';

import '../../../config/app_colors.dart';
import '../../../services/admin_salary_service.dart';
import 'admin_salary_structure_detail_screen.dart';
import 'admin_salary_ui.dart';

class AdminSalaryStructureScreen extends StatefulWidget {
  const AdminSalaryStructureScreen({super.key});

  @override
  State<AdminSalaryStructureScreen> createState() => _AdminSalaryStructureScreenState();
}

class _AdminSalaryStructureScreenState extends State<AdminSalaryStructureScreen> {
  final _search = TextEditingController();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _staff = [];
  Map<String, String> _templateTitles = {};

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
    if (showLoader) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    final results = await Future.wait([
      AdminSalaryService.instance.getStaffList(),
      AdminSalaryService.instance.getSalaryTemplates(),
    ]);
    if (!mounted) return;
    final staffRes = results[0];
    final tplRes = results[1];
    setState(() {
      _loading = false;
      if (staffRes['success'] == true) {
        _staff = List<Map<String, dynamic>>.from(staffRes['data'] as List);
        _error = null;
      } else {
        _error = staffRes['message']?.toString() ?? 'Could not load staff.';
      }
      // Template names are a nicety on this list; the detail screen reports its own failure.
      if (tplRes['success'] == true) {
        _templateTitles = {
          for (final t in List<Map<String, dynamic>>.from(tplRes['data'] as List))
            (t['_id'] ?? '').toString(): (t['title'] ?? '').toString(),
        };
      }
    });
  }

  static String nameOf(Map<String, dynamic> s) {
    final n = (s['name'] ?? '').toString().trim();
    if (n.isNotEmpty) return n;
    return '${s['firstName'] ?? ''} ${s['lastName'] ?? ''}'.trim();
  }

  static String templateIdOf(Map<String, dynamic> s) {
    final t = s['salaryTemplate'];
    if (t is Map) return (t['_id'] ?? '').toString();
    return (t ?? '').toString();
  }

  List<Map<String, dynamic>> get _filtered {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return _staff;
    return _staff.where((s) {
      return nameOf(s).toLowerCase().contains(q) ||
          (s['employeeId'] ?? '').toString().toLowerCase().contains(q) ||
          (s['department'] ?? '').toString().toLowerCase().contains(q) ||
          (s['designation'] ?? '').toString().toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final list = _filtered;
    return Scaffold(
      backgroundColor: AdminUi.bg,
      appBar: AdminUi.appBar('Salary Structure', actions: [
        IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded), tooltip: 'Refresh'),
      ]),
      body: _loading
          ? const AdminLoading()
          : _error != null
              ? AdminErrorView(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  color: AppColors.primary,
                  onRefresh: () => _load(showLoader: false),
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                    children: [
                      AdminSearchField(
                          controller: _search, hint: 'Search by name, ID or department', onChanged: (_) => setState(() {})),
                      const SizedBox(height: 16),
                      if (list.isEmpty)
                        AdminEmptyView(
                          icon: Icons.people_outline_rounded,
                          title: _staff.isEmpty ? 'No staff yet' : 'No matching staff',
                        )
                      else
                        ...list.map(_card),
                    ],
                  ),
                ),
    );
  }

  Widget _card(Map<String, dynamic> s) {
    final name = nameOf(s);
    final tplId = templateIdOf(s);
    final tplTitle = _templateTitles[tplId] ?? '';
    final inactive = (s['status'] ?? '').toString().toLowerCase().contains('deactiv') ||
        (s['status'] ?? '').toString().toLowerCase() == 'inactive';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AdminCard(
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => AdminSalaryStructureDetailScreen(staffId: (s['_id'] ?? '').toString(), staffName: name),
            ),
          );
          if (mounted) _load(showLoader: false);
        },
        child: Row(children: [
          AdminAvatar(name),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AdminUi.ink)),
              const SizedBox(height: 2),
              Text(
                [s['employeeId'], s['designation'], s['department']]
                    .where((v) => v != null && v.toString().isNotEmpty)
                    .join(' • '),
                style: const TextStyle(fontSize: 12.5, color: AdminUi.muted),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: tplId.isEmpty ? AdminUi.amberBg : AdminUi.greyBg,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(tplId.isEmpty ? Icons.warning_amber_rounded : Icons.description_outlined,
                      size: 14, color: tplId.isEmpty ? AdminUi.amber : AdminUi.muted),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      tplId.isEmpty ? 'No salary template' : (tplTitle.isEmpty ? 'Template assigned' : tplTitle),
                      style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w500, color: tplId.isEmpty ? AdminUi.amber : AdminUi.muted),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ]),
              ),
            ]),
          ),
          if (inactive) ...[const SizedBox(width: 8), const AdminPill('Inactive')],
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right_rounded, color: AdminUi.faint),
        ]),
      ),
    );
  }
}
