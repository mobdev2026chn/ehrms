// Admin Staff > Settings hub. Mirrors the web's /admin/staff/settings sections:
// Attendance, Salary, Business (Company Master), Module Access, Shift Roster, Reports.

import 'package:flutter/material.dart';

import '../../../config/app_colors.dart';
import '../../../services/admin_settings_service.dart';
import 'attendance_templates_screen.dart';
import 'branches_screen.dart';
import 'company_master_screen.dart';
import 'module_access_screen.dart';
import 'salary_settings_screen.dart';
import 'settings_common.dart';
import 'settings_reports_screen.dart';
import 'shift_roster_screen.dart';

class _Entry {
  const _Entry(this.title, this.subtitle, this.icon, this.builder);
  final String title;
  final String subtitle;
  final IconData icon;
  final WidgetBuilder builder;
}

Widget _entryList(BuildContext context, List<(String, List<_Entry>)> sections) => ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        for (final (title, entries) in sections) ...[
          SettingsSectionTitle(title),
          for (final e in entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: SettingsListCard(
                leading: settingsIconTile(e.icon),
                title: e.title,
                subtitle: e.subtitle,
                trailing: const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Icon(Icons.chevron_right_rounded, color: AppColors.textCaption),
                ),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: e.builder)),
              ),
            ),
        ],
      ],
    );

class AdminSettingsHubScreen extends StatelessWidget {
  const AdminSettingsHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: settingsAppBar('Settings'),
      body: _entryList(context, [
        (
          'Staff settings',
          [
            _Entry('Attendance Settings', 'Shifts, leaves, holidays, week-offs, breaks, overtime, permissions, branches',
                Icons.event_available_outlined, (_) => const AttendanceSettingsScreen()),
            _Entry('Salary Settings', 'Payable days, salary components, templates, salary access',
                Icons.account_balance_wallet_outlined, (_) => const SalarySettingsScreen()),
            _Entry('Shift Roster', 'Permanent & temporary assignments, daily overrides',
                Icons.calendar_month_outlined, (_) => const ShiftRosterScreen()),
            _Entry('Reports', 'Download Excel reports', Icons.summarize_outlined, (_) => const SettingsReportsScreen()),
          ],
        ),
        (
          'Business',
          [
            _Entry('Company Master', 'Company details, logo, address and subscription', Icons.business_outlined,
                (_) => const CompanyMasterScreen()),
            _Entry('Module Access', 'Grant staff access to admin modules', Icons.admin_panel_settings_outlined,
                (_) => const ModuleAccessScreen()),
          ],
        ),
      ]),
    );
  }
}

class AttendanceSettingsScreen extends StatelessWidget {
  const AttendanceSettingsScreen({super.key});

  static const _icons = <String, IconData>{
    'attendance-templates': Icons.fact_check_outlined,
    'holiday-templates': Icons.celebration_outlined,
    'leave-templates': Icons.beach_access_outlined,
    'shifts': Icons.schedule_outlined,
    'weekly-off-templates': Icons.weekend_outlined,
    'break-templates': Icons.free_breakfast_outlined,
    'overtime-templates': Icons.more_time_outlined,
    'permission-templates': Icons.timer_outlined,
  };

  static const _subtitles = <String, String>{
    'attendance-templates': 'Geofence, selfie, holiday & week-off rules',
    'holiday-templates': 'Holiday calendars',
    'leave-templates': 'Leave types and yearly limits',
    'shifts': 'Standard, open and rotational shifts',
    'weekly-off-templates': 'Weekly off patterns',
    'break-templates': 'Break duration and fines',
    'overtime-templates': 'Overtime eligibility',
    'permission-templates': 'Short-leave permission hours',
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: settingsAppBar('Attendance Settings'),
      body: _entryList(context, [
        (
          'Templates',
          [
            for (final k in AttendanceTemplateKind.all)
              _Entry(k.title, _subtitles[k.segment] ?? '', _icons[k.segment] ?? Icons.settings_outlined,
                  (_) => AttendanceTemplatesScreen(kind: k)),
          ],
        ),
        (
          'Locations',
          [
            _Entry('Branches & Geofence', 'Branch details and geofence zones', Icons.location_on_outlined,
                (_) => const BranchesScreen()),
          ],
        ),
      ]),
    );
  }
}
