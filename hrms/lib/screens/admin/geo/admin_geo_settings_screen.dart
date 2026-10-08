// Admin GEO settings hub: General (tracking, auto approval, per-employee switches), Custom
// Fields, Form Templates, Employee Access and Travel Allowance (transport modes and rates).
// Mirrors the web HRMS GEO → Settings sections.

import 'package:flutter/material.dart';

import '../../../config/app_colors.dart';

import 'admin_geo_custom_fields_screen.dart';
import 'admin_geo_employee_access_screen.dart';
import 'admin_geo_form_templates_screen.dart';
import 'admin_geo_general_settings_screen.dart';
import 'admin_geo_ta_settings_screen.dart';
import 'geo_admin_ui.dart';

class AdminGeoSettingsScreen extends StatelessWidget {
  const AdminGeoSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final sections = <(IconData, String, String, Widget Function())>[
      (Icons.settings_suggest_outlined, 'General settings', 'Live / timeline tracking, interval, history, auto task approval and per-employee switches',
          () => const AdminGeoGeneralSettingsScreen()),
      (Icons.dashboard_customize_outlined, 'Custom fields', 'Extra fields on customer and task forms', () => const AdminGeoCustomFieldsScreen()),
      (Icons.dynamic_form_outlined, 'Form templates', 'Task form fields for the internal and external layouts',
          () => const AdminGeoFormTemplatesScreen()),
      (Icons.manage_accounts_outlined, 'Employee access', 'Field type, transport and branches for each employee',
          () => const AdminGeoEmployeeAccessScreen()),
      (Icons.two_wheeler_rounded, 'Travel allowance', 'Transport modes and rate per km', () => const AdminGeoTaSettingsScreen()),
    ];
    return Scaffold(
      backgroundColor: GeoUi.bg,
      appBar: GeoUi.appBar('GEO Settings'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          for (final s in sections)
            GeoUi.card(
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => s.$4())),
              child: Row(children: [
                GeoUi.iconTile(s.$1),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(s.$2, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: GeoUi.ink)),
                    const SizedBox(height: 2),
                    Text(s.$3, style: const TextStyle(fontSize: 12.5, color: GeoUi.muted)),
                  ]),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right_rounded, color: AppColors.textCaption),
              ]),
            ),
        ],
      ),
    );
  }
}
