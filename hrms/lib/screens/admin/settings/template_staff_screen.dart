// Assigned / unassigned staff for any template that exposes
//   GET  <basePath>/:id/staff     -> { assigned, unassigned }
//   POST <basePath>/:id/assign    { staffIds }
//   POST <basePath>/:id/unassign  { staffIds }
// Used by every attendance template kind and by salary templates.

import 'package:flutter/material.dart';

import '../../../config/app_colors.dart';
import '../../../services/admin_settings_service.dart';
import 'settings_common.dart';

class TemplateStaffScreen extends StatefulWidget {
  const TemplateStaffScreen({
    super.key,
    required this.basePath,
    required this.templateId,
    required this.templateName,
  });

  final String basePath;
  final String templateId;
  final String templateName;

  @override
  State<TemplateStaffScreen> createState() => _TemplateStaffScreenState();
}

class _TemplateStaffScreenState extends State<TemplateStaffScreen> {
  final _svc = AdminSettingsService.instance;
  List<Map<String, dynamic>>? _assigned;
  List<Map<String, dynamic>>? _unassigned;
  String? _error;
  String _search = '';
  final Set<String> _selAssigned = {};
  final Set<String> _selUnassigned = {};
  bool _busy = false;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await _svc.templateStaff(widget.basePath, widget.templateId);
      if (!mounted) return;
      setState(() {
        _assigned = r.assigned;
        _unassigned = r.unassigned;
        _error = null;
        _selAssigned.clear();
        _selUnassigned.clear();
      });
    } catch (e) {
      if (mounted) setState(() => _error = settingsErrorText(e));
    }
  }

  Future<void> _apply(bool assign) async {
    final ids = (assign ? _selUnassigned : _selAssigned).toList();
    if (ids.isEmpty) return;
    setState(() => _busy = true);
    try {
      final msg = assign
          ? await _svc.assignStaff(widget.basePath, widget.templateId, ids)
          : await _svc.unassignStaff(widget.basePath, widget.templateId, ids);
      _changed = true;
      if (!mounted) return;
      showSettingsSuccess(context, msg ?? (assign ? 'Staff assigned' : 'Staff unassigned'));
      await _load();
    } catch (e) {
      if (mounted) showSettingsError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<Map<String, dynamic>> _filter(List<Map<String, dynamic>> list) {
    final q = _search.trim().toLowerCase();
    if (q.isEmpty) return list;
    return list.where((s) {
      final name = AdminSettingsService.staffName(s).toLowerCase();
      final emp = (s['employeeId'] ?? '').toString().toLowerCase();
      final dept = (s['department'] ?? '').toString().toLowerCase();
      return name.contains(q) || emp.contains(q) || dept.contains(q);
    }).toList();
  }

  Widget _list(List<Map<String, dynamic>> source, Set<String> selected, bool assignedTab) {
    final items = _filter(source);
    return Column(
      children: [
        if (items.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Row(
              children: [
                Text('${selected.length} selected', style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                const Spacer(),
                TextButton(
                  onPressed: () => setState(() {
                    final ids = items.map((s) => AdminSettingsService.idOf(s)).toSet();
                    if (selected.containsAll(ids)) {
                      selected.removeAll(ids);
                    } else {
                      selected.addAll(ids);
                    }
                  }),
                  child: const Text('Select all'),
                ),
              ],
            ),
          ),
        Expanded(
          child: RefreshIndicator(
            color: AppColors.primary,
            onRefresh: _load,
            child: items.isEmpty
                ? SettingsEmptyView(message: assignedTab ? 'No staff assigned.' : 'No staff available.')
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
                    itemCount: items.length,
                    itemBuilder: (_, i) {
                      final s = items[i];
                      final id = AdminSettingsService.idOf(s);
                      final sub = [s['employeeId'], s['department'], s['designation']]
                          .where((e) => e != null && e.toString().isNotEmpty)
                          .join(' · ');
                      return CheckboxListTile(
                        value: selected.contains(id),
                        activeColor: AppColors.primary,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: Text(AdminSettingsService.staffName(s),
                            style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                        subtitle: sub.isEmpty ? null : Text(sub, style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                        onChanged: _busy
                            ? null
                            : (v) => setState(() => v == true ? selected.add(id) : selected.remove(id)),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Builder(builder: (ctx) {
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) Navigator.of(context).pop(_changed);
          },
          child: Scaffold(
            backgroundColor: AppColors.background,
            appBar: settingsAppBar(
              widget.templateName,
              bottom: settingsTabBar([
                'Assigned${_assigned == null ? '' : ' (${_assigned!.length})'}',
                'Unassigned${_unassigned == null ? '' : ' (${_unassigned!.length})'}',
              ]),
            ),
            body: _error != null && _assigned == null
                ? SettingsErrorView(message: _error!, onRetry: _load)
                : _assigned == null
                    ? const SettingsLoading()
                    : Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                            child: TextField(
                              decoration: settingsInput('Search staff', suffixIcon: const Icon(Icons.search_rounded, size: 20)),
                              onChanged: (v) => setState(() => _search = v),
                            ),
                          ),
                          Expanded(
                            child: TabBarView(children: [
                              _list(_assigned!, _selAssigned, true),
                              _list(_unassigned!, _selUnassigned, false),
                            ]),
                          ),
                        ],
                      ),
            bottomNavigationBar: _assigned == null
                ? null
                : AnimatedBuilder(
                    animation: DefaultTabController.of(ctx),
                    builder: (_, __) {
                      final assignedTab = DefaultTabController.of(ctx).index == 0;
                      final count = assignedTab ? _selAssigned.length : _selUnassigned.length;
                      return SettingsSaveBar(
                        saving: _busy,
                        label: assignedTab ? 'Unassign selected ($count)' : 'Assign selected ($count)',
                        onSave: count == 0 ? () {} : () => _apply(!assignedTab),
                      );
                    },
                  ),
          ),
        );
      }),
    );
  }
}
