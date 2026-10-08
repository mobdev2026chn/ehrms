// Shared Exit Process constants and widgets. The exit types, timeline fields and choices mirror
// HRMSbackend models/admin/exitProcess/exitCaseModel.ts so a save is never refused for a value
// the screen offered.

import 'package:flutter/material.dart';

import '../../../config/app_colors.dart';
import '../salary/admin_salary_ui.dart';

class ExitUi {
  static const exitTypes = ['Resignation', 'Immediate resignation', 'Termination by employer', 'Absconded'];
  static const terminationType = 'Termination by employer';
  static const assetConditions = ['Good', 'Fair', 'Damaged', 'New'];
  static const assetStatuses = ['Pending', 'Returned', 'Damaged', 'Lost', 'Not Applicable'];

  /// The timeline fields each exit type uses; the backend clears the rest on save.
  static const timelineFields = <String, List<String>>{
    'Resignation': [
      'resignationDate', 'approvalDate', 'description', 'noticePeriodDays',
      'noticeFrom', 'noticeTo', 'leaveNote', 'lastWorkingDay', 'extendByApprovedLeave',
    ],
    'Immediate resignation': ['resignationDate', 'description', 'lastWorkingDay'],
    'Termination by employer': [
      'resignationDate', 'description', 'terminatedBy', 'terminationApprovedBy', 'terminationReason', 'lastWorkingDay',
    ],
    'Absconded': ['description', 'lastWorkingDay'],
  };

  static List<String> fieldsFor(String exitType) => timelineFields[exitType] ?? timelineFields['Resignation']!;

  static String exitDateLabel(String exitType) => switch (exitType) {
        'Immediate resignation' => 'Immediate resignation date',
        'Termination by employer' => 'Termination date',
        _ => 'Resignation date',
      };

  static String statusLabel(dynamic s) => switch (s?.toString()) {
        'completed' => 'Completed',
        'cancelled' => 'Cancelled',
        _ => 'In Progress',
      };

  static String sectionLabel(dynamic s) => switch (s?.toString()) {
        'completed' => 'Completed',
        'in_progress' => 'In Progress',
        _ => 'Pending',
      };

  static ({Color fg, Color bg}) exitTypeColors(String type) => switch (type) {
        'Resignation' => (fg: AdminUi.blue, bg: AdminUi.blueBg),
        'Immediate resignation' => (fg: AppColors.indigo, bg: AppColors.indigoBg),
        'Termination by employer' => (fg: AdminUi.red, bg: AdminUi.redBg),
        'Absconded' => (fg: AdminUi.amber, bg: AdminUi.amberBg),
        _ => (fg: AdminUi.muted, bg: AdminUi.greyBg),
      };

  static String addDays(String ymd, int days) {
    final d = AdminUi.parseYmd(ymd);
    if (d == null) return '';
    return AdminUi.ymd(DateTime(d.year, d.month, d.day + days));
  }

  static int? daysBetween(String from, String to) {
    final a = AdminUi.parseYmd(from);
    final b = AdminUi.parseYmd(to);
    if (a == null || b == null) return null;
    return DateTime.utc(b.year, b.month, b.day).difference(DateTime.utc(a.year, a.month, a.day)).inDays;
  }

  static bool isLink(String v) => RegExp(r'^https?://\S+$', caseSensitive: false).hasMatch(v.trim());
  static bool isEmail(String v) => RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(v.trim());
}

class ExitTypeBadge extends StatelessWidget {
  final String type;
  const ExitTypeBadge(this.type, {super.key});
  @override
  Widget build(BuildContext context) {
    final c = ExitUi.exitTypeColors(type);
    return AdminPill(type.isEmpty ? 'Exit type not set' : type, fg: c.fg, bg: c.bg);
  }
}

/// A "YYYY-MM-DD" date field with a picker and a clear button.
class ExitDateField extends StatelessWidget {
  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  final bool enabled;
  final String? helper;
  final String? firstDate;
  const ExitDateField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.helper,
    this.firstDate,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: !enabled
          ? null
          : () async {
              final first = AdminUi.parseYmd(firstDate) ?? DateTime(2000);
              var initial = AdminUi.parseYmd(value) ?? DateTime.now();
              if (initial.isBefore(first)) initial = first;
              final picked = await showDatePicker(
                context: context,
                initialDate: initial,
                firstDate: first,
                lastDate: DateTime(DateTime.now().year + 5, 12, 31),
              );
              if (picked != null) onChanged(AdminUi.ymd(picked));
            },
      child: InputDecorator(
        decoration: AdminUi.input(label, helper: helper).copyWith(
          suffixIcon: value.isNotEmpty && enabled
              ? IconButton(
                  tooltip: 'Clear date', icon: const Icon(Icons.close_rounded, size: 18), onPressed: () => onChanged(''))
              : const Icon(Icons.calendar_today_outlined, size: 18, color: AdminUi.muted),
        ),
        child: Text(value.isEmpty ? 'Select date' : AdminUi.date(value),
            style: TextStyle(color: value.isEmpty ? AdminUi.faint : AdminUi.ink, fontSize: 14)),
      ),
    );
  }
}

/// Edit / Cancel / Save controls shown at the top of an editable tab.
class ExitEditBar extends StatelessWidget {
  final bool editing;
  final bool saving;
  final VoidCallback onEdit;
  final VoidCallback onCancel;
  final VoidCallback onSave;
  final String title;
  final String status;
  const ExitEditBar({
    super.key,
    required this.title,
    required this.status,
    required this.editing,
    required this.saving,
    required this.onEdit,
    required this.onCancel,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: AdminUi.ink)),
              const SizedBox(height: 6),
              AdminPill(status),
            ]),
          ),
          if (!editing)
            OutlinedButton.icon(
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Edit'),
            )
          else ...[
            TextButton(onPressed: saving ? null : onCancel, child: const Text('Cancel')),
            const SizedBox(width: 8),
            ElevatedButton(
              style: AdminUi.primaryButton(),
              onPressed: saving ? null : onSave,
              child: saving
                  ? SizedBox(
                      width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onPrimary))
                  : const Text('Save'),
            ),
          ],
        ]),
      );
}

class ExitKv extends StatelessWidget {
  final String label;
  final String value;
  const ExitKv(this.label, this.value, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 140, child: Text(label, style: const TextStyle(fontSize: 13, color: AdminUi.muted))),
          Expanded(
            child: Text(value.isEmpty ? '-' : value,
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AdminUi.ink)),
          ),
        ]),
      );
}
