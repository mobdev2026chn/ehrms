// Generic list for every attendance template kind under
// /admin/settings/attendance/<kind>: list, add/edit, delete, assigned staff.

import 'package:flutter/material.dart';

import '../../../config/app_colors.dart';
import '../../../services/admin_settings_service.dart';
import 'attendance_template_form_screen.dart';
import 'settings_common.dart';
import 'template_staff_screen.dart';

class AttendanceTemplatesScreen extends StatefulWidget {
  const AttendanceTemplatesScreen({super.key, required this.kind});
  final AttendanceTemplateKind kind;

  @override
  State<AttendanceTemplatesScreen> createState() => _AttendanceTemplatesScreenState();
}

class _AttendanceTemplatesScreenState extends State<AttendanceTemplatesScreen> {
  final _svc = AdminSettingsService.instance;
  List<Map<String, dynamic>>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await _svc.listTemplates(widget.kind.basePath);
      if (mounted) {
        setState(() {
          _items = list;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = settingsErrorText(e));
        if (_items != null) showSettingsError(context, e);
      }
    }
  }

  Future<void> _openForm([Map<String, dynamic>? t]) async {
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => AttendanceTemplateFormScreen(kind: widget.kind, templateId: t == null ? null : AdminSettingsService.idOf(t)),
    ));
    if (saved == true) _load();
  }

  Future<void> _openStaff(Map<String, dynamic> t) async {
    final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => TemplateStaffScreen(
        basePath: widget.kind.basePath,
        templateId: AdminSettingsService.idOf(t),
        templateName: (t['name'] ?? widget.kind.singular).toString(),
      ),
    ));
    if (changed == true) _load();
  }

  Future<void> _delete(Map<String, dynamic> t) async {
    final ok = await confirmSettingsAction(
      context,
      title: 'Delete ${widget.kind.singular}?',
      message: 'Delete "${t['name']}"? This cannot be undone.',
    );
    if (!ok || !mounted) return;
    try {
      await _svc.deleteTemplate(widget.kind.basePath, AdminSettingsService.idOf(t));
      if (!mounted) return;
      showSettingsSuccess(context, '${widget.kind.singular} deleted');
      setState(() => _items = _items?.where((e) => AdminSettingsService.idOf(e) != AdminSettingsService.idOf(t)).toList());
    } catch (e) {
      if (mounted) showSettingsError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: settingsAppBar(widget.kind.title),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: settingsAsyncBody<Map<String, dynamic>>(
        items: _items,
        error: _error,
        onRefresh: _load,
        emptyText: 'No ${widget.kind.title.toLowerCase()} yet. Tap Add to create one.',
        builder: (items) => ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (_, i) {
            final t = items[i];
            final count = toInt(t['assignedStaff']) ?? 0;
            return SettingsListCard(
              leading: settingsIconTile(Icons.description_outlined, size: 40),
              title: (t['name'] ?? '-').toString(),
              subtitle: templateSummary(widget.kind, t),
              onTap: () => _openForm(t),
              trailing: PopupMenuButton<String>(
                tooltip: 'More actions',
                onSelected: (v) {
                  if (v == 'edit') _openForm(t);
                  if (v == 'staff') _openStaff(t);
                  if (v == 'delete') _delete(t);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Edit')),
                  PopupMenuItem(value: 'staff', child: Text('Assigned staff')),
                  PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: AppColors.error))),
                ],
              ),
              footer: Row(
                children: [
                  activeChip(t['isActive'] != false),
                  const SizedBox(width: 8),
                  InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: () => _openStaff(t),
                    child: SettingsChip('$count staff assigned', color: AppColors.info, background: AppColors.infoBg),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// One-line summary shown on a template card.
String templateSummary(AttendanceTemplateKind kind, Map<String, dynamic> t) {
  switch (kind.segment) {
    case 'attendance-templates':
      final flags = <String>[
        if (t['requireGeofence'] == true) 'Geofence',
        if (t['requireSelfie'] == true) 'Selfie',
        if (t['allowAttendanceOnHolidays'] == true) 'Holiday work',
        if (t['allowAttendanceOnWeeklyOff'] == true) 'Week-off work',
        if (t['sandwichLeave'] == true) 'Sandwich leave',
      ];
      return flags.isEmpty ? 'No restrictions' : flags.join(' · ');
    case 'holiday-templates':
      final n = (t['holidays'] as List?)?.length ?? 0;
      return '$n holiday${n == 1 ? '' : 's'}';
    case 'leave-templates':
      final leaves = AdminSettingsService.asList(t['leaves']);
      final days = leaves.fold<num>(0, (a, l) => a + (toNum(l['days']) ?? 0));
      return '${leaves.length} leave type${leaves.length == 1 ? '' : 's'} · $days days';
    case 'shifts':
      final type = (t['shiftType'] ?? 'standard').toString();
      if (type == 'open') return 'Open shift · ${t['workHours'] ?? '-'}h';
      if (type == 'rotational') return 'Rotational · ${(t['rotationType'] ?? '').toString().replaceAll('_', ' ')}';
      return 'Standard · ${t['startTime'] ?? '--'} - ${t['endTime'] ?? '--'}';
    case 'weekly-off-templates':
      final p = (t['patternType'] ?? 'standard').toString();
      final days = (t['selectedDays'] as List?)?.join(', ') ?? '';
      if (p == 'custom_weekday') return 'Any ${t['customDaysCount'] ?? 1} day(s) per week';
      if (p == 'alternate') return 'Alternate (${t['alternateWeeks'] ?? 'even'}) Saturdays · Sundays';
      return '${p == 'custom' ? 'Custom' : 'Standard'} · ${days.isEmpty ? 'No days' : days}';
    case 'break-templates':
      return '${t['duration'] ?? 0} min · Fine ${t['fineRule'] ?? 'auto'}';
    case 'overtime-templates':
      return 'Min ${t['minOvertime'] ?? 0} min · Max ${t['maxOvertimeHours'] ?? '-'} h';
    case 'permission-templates':
      return '${t['hours'] ?? 0}h ${t['minutes'] ?? 0}m allowed';
  }
  return (t['description'] ?? '').toString();
}
