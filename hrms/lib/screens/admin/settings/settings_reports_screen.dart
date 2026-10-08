// Staff Settings > Reports: Excel downloads from /admin/settings/reports/*.
// Filters mirror the web report modals (features/admin/staff/settings/Report).
// The file is saved to the device and can be opened or shared.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../config/app_colors.dart';
import '../../../services/admin_settings_service.dart';
import 'settings_common.dart';

enum _Filter { dateRange, monthYear, yearMonthKey, department, branch, overtimeStatus, staffStatus, employmentType, shiftType }

class _ReportDef {
  const _ReportDef(this.type, this.title, this.description, this.icon, this.filters, this.filePrefix);
  final String type;
  final String title;
  final String description;
  final IconData icon;
  final List<_Filter> filters;
  final String filePrefix;
}

const _kReports = <_ReportDef>[
  _ReportDef('leave', 'Leave Report', 'Leave requests in a date range', Icons.beach_access_outlined,
      [_Filter.dateRange, _Filter.department], 'Leave_Report'),
  _ReportDef('salary-structure', 'Salary Structure Report', 'Salary structure of staff for a month', Icons.account_balance_wallet_outlined,
      [_Filter.monthYear, _Filter.department], 'Salary_Structure_Report'),
  _ReportDef('attendance', 'Attendance Report', 'Daily attendance in a date range', Icons.fact_check_outlined,
      [_Filter.dateRange, _Filter.department], 'Attendance_Report'),
  _ReportDef('payroll', 'Payroll Report', 'Payroll for a month', Icons.payments_outlined,
      [_Filter.monthYear, _Filter.department], 'Payroll_Report'),
  _ReportDef('reimbursement', 'Reimbursement Report', 'Expense claims in a date range', Icons.receipt_long_outlined,
      [_Filter.dateRange, _Filter.department], 'Reimbursement_Report'),
  _ReportDef('shift-roster', 'Shift Roster Report', 'Resolved shifts for a month', Icons.calendar_view_month_outlined,
      [_Filter.yearMonthKey, _Filter.branch, _Filter.department, _Filter.shiftType], 'Shift_Roster_Report'),
  _ReportDef('overtime', 'Overtime Report', 'Overtime requests in a date range', Icons.more_time_outlined,
      [_Filter.dateRange, _Filter.department, _Filter.overtimeStatus], 'Overtime_Report'),
  _ReportDef('staff', 'Staff Report', 'Full staff master data', Icons.badge_outlined,
      [_Filter.branch, _Filter.department, _Filter.staffStatus, _Filter.employmentType], 'Staff_Report'),
];

/// Label shown -> value sent. Add Staff stores IT as "Engineering" and Marketing as "Design".
const _kDepartments = <String, String>{
  'All Departments': 'All Departments',
  'IT': 'Engineering',
  'HR': 'HR',
  'Sales': 'Sales',
  'Marketing': 'Design',
};
const _kOvertimeStatus = ['All Statuses', 'Pending', 'Accepted', 'Rejected', 'Expired'];
const _kStaffStatus = ['All Status', 'Active', 'Deactive'];
const _kEmploymentTypes = ['All Types', 'Full Time', 'Part Time', 'Contract', 'Intern'];
const _kShiftTypes = ['All Shift Types', 'Permanent Shift', 'Temporary Shift', 'Rotation'];

class SettingsReportsScreen extends StatelessWidget {
  const SettingsReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: settingsAppBar('Reports'),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _kReports.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, i) {
          final r = _kReports[i];
          return SettingsListCard(
            leading: settingsIconTile(r.icon),
            title: r.title,
            subtitle: r.description,
            trailing: const Padding(
              padding: EdgeInsets.only(left: 8),
              child: Icon(Icons.download_rounded, color: AppColors.brandDark),
            ),
            onTap: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (_) => _ReportSheet(def: r),
            ),
          );
        },
      ),
    );
  }
}

class _ReportSheet extends StatefulWidget {
  const _ReportSheet({required this.def});
  final _ReportDef def;

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  final _svc = AdminSettingsService.instance;
  late DateTime _start = DateTime(DateTime.now().year, DateTime.now().month, 1);
  late DateTime _end = DateTime.now();
  int _month = DateTime.now().month;
  int _year = DateTime.now().year;
  String _department = 'All Departments';
  String _branch = 'All Branches';
  String _otStatus = _kOvertimeStatus.first;
  String _staffStatus = _kStaffStatus.first;
  String _employment = _kEmploymentTypes.first;
  String _shiftType = _kShiftTypes.first;
  List<String> _branches = const ['All Branches'];
  String? _branchError;
  bool _busy = false;
  File? _file;

  bool _has(_Filter f) => widget.def.filters.contains(f);

  @override
  void initState() {
    super.initState();
    if (_has(_Filter.branch)) _loadBranches();
  }

  Future<void> _loadBranches() async {
    try {
      final list = await _svc.listBranches();
      if (!mounted) return;
      setState(() {
        _branches = ['All Branches', ...list.map((b) => (b['branchName'] ?? '').toString()).where((n) => n.isNotEmpty)];
        _branchError = null;
      });
    } catch (e) {
      if (mounted) setState(() => _branchError = settingsErrorText(e));
    }
  }

  Map<String, dynamic> _params() {
    final p = <String, dynamic>{};
    if (_has(_Filter.dateRange)) {
      p['startDate'] = fmtYmd(_start);
      p['endDate'] = fmtYmd(_end);
    }
    if (_has(_Filter.monthYear)) {
      p['month'] = '$_month';
      p['year'] = '$_year';
    }
    if (_has(_Filter.yearMonthKey)) p['month'] = '$_year-${_month.toString().padLeft(2, '0')}';
    if (_has(_Filter.department)) p['department'] = _kDepartments[_department] ?? _department;
    if (_has(_Filter.branch)) p['branch'] = _branch;
    if (_has(_Filter.overtimeStatus)) p['status'] = _otStatus;
    if (_has(_Filter.staffStatus)) p['status'] = _staffStatus;
    if (_has(_Filter.employmentType)) p['employmentType'] = _employment;
    if (_has(_Filter.shiftType)) p['shiftType'] = _shiftType;
    return p;
  }

  String _fallbackName() {
    final d = widget.def;
    if (_has(_Filter.dateRange)) return '${d.filePrefix}_${fmtYmd(_start)}_to_${fmtYmd(_end)}.xlsx';
    if (_has(_Filter.monthYear) || _has(_Filter.yearMonthKey)) return '${d.filePrefix}_${_year}_${_month.toString().padLeft(2, '0')}.xlsx';
    return '${d.filePrefix}_${DateFormat('yyyyMMdd').format(DateTime.now())}.xlsx';
  }

  Future<void> _download() async {
    if (_has(_Filter.dateRange) && _end.isBefore(_start)) {
      showSettingsError(context, 'End date cannot be before start date.');
      return;
    }
    setState(() {
      _busy = true;
      _file = null;
    });
    try {
      final report = await _svc.downloadReport(widget.def.type, _params(), fallbackName: _fallbackName());
      final dir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
      final folder = Directory('${dir.path}/Reports');
      if (!await folder.exists()) await folder.create(recursive: true);
      final safe = report.fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
      final file = File('${folder.path}/$safe');
      await file.writeAsBytes(report.bytes, flush: true);
      if (!mounted) return;
      setState(() => _file = file);
      showSettingsSuccess(context, 'Report saved');
      await _open();
    } catch (e) {
      if (mounted) showSettingsError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open() async {
    final f = _file;
    if (f == null) return;
    final res = await OpenFilex.open(f.path);
    if (res.type != ResultType.done && mounted) {
      showSettingsError(context, 'No app found to open the Excel file. Use Share instead.');
    }
  }

  Future<void> _share() async {
    final f = _file;
    if (f == null) return;
    try {
      await SharePlus.instance.share(ShareParams(
        files: [XFile(f.path, mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')],
        subject: widget.def.title,
      ));
    } catch (e) {
      if (mounted) showSettingsError(context, 'Could not share the report. ${settingsErrorText(e)}');
    }
  }

  Widget _drop(String label, String value, List<String> options, ValueChanged<String> onChanged) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: SettingsDropdown<String>(
          label: label,
          value: value,
          items: [for (final o in options) DropdownMenuItem(value: o, child: Text(o, overflow: TextOverflow.ellipsis))],
          onChanged: (v) => setState(() => onChanged(v ?? options.first)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final years = [for (var y = now.year - 5; y <= now.year + 1; y++) y];
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(widget.def.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          Text(widget.def.description, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          if (_has(_Filter.dateRange))
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    onPressed: () async {
                      final d = await pickSettingsDate(context, initial: _start, last: _end);
                      if (d != null) setState(() => _start = d);
                    },
                    icon: const Icon(Icons.event_outlined, size: 18),
                    label: Text(fmtDisplayDate(_start)),
                  ),
                ),
                const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('to', style: TextStyle(color: AppColors.textSecondary))),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    onPressed: () async {
                      final d = await pickSettingsDate(context, initial: _end, first: _start);
                      if (d != null) setState(() => _end = d);
                    },
                    icon: const Icon(Icons.event_outlined, size: 18),
                    label: Text(fmtDisplayDate(_end)),
                  ),
                ),
              ]),
            ),
          if (_has(_Filter.monthYear) || _has(_Filter.yearMonthKey))
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(children: [
                Expanded(
                  child: SettingsDropdown<int>(
                    label: 'Month',
                    value: _month,
                    items: [
                      for (var m = 1; m <= 12; m++) DropdownMenuItem(value: m, child: Text(DateFormat('MMMM').format(DateTime(2000, m)))),
                    ],
                    onChanged: (v) => setState(() => _month = v ?? _month),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SettingsDropdown<int>(
                    label: 'Year',
                    value: _year,
                    items: [for (final y in years) DropdownMenuItem(value: y, child: Text('$y'))],
                    onChanged: (v) => setState(() => _year = v ?? _year),
                  ),
                ),
              ]),
            ),
          if (_has(_Filter.branch)) ...[
            _drop('Branch', _branch, _branches, (v) => _branch = v),
            if (_branchError != null)
              Row(children: [
                Expanded(child: Text(_branchError!, style: const TextStyle(color: AppColors.error, fontSize: 12.5))),
                TextButton(onPressed: _loadBranches, child: const Text('Retry')),
              ]),
          ],
          if (_has(_Filter.department)) _drop('Department', _department, _kDepartments.keys.toList(), (v) => _department = v),
          if (_has(_Filter.shiftType)) _drop('Shift type', _shiftType, _kShiftTypes, (v) => _shiftType = v),
          if (_has(_Filter.overtimeStatus)) _drop('Status', _otStatus, _kOvertimeStatus, (v) => _otStatus = v),
          if (_has(_Filter.employmentType)) _drop('Employment type', _employment, _kEmploymentTypes, (v) => _employment = v),
          if (_has(_Filter.staffStatus)) _drop('Status', _staffStatus, _kStaffStatus, (v) => _staffStatus = v),
          const SizedBox(height: 12),
          SettingsSaveBar(saving: _busy, onSave: _download, label: 'Download Excel'),
          if (_file != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.check_circle_outline_rounded, size: 18, color: AppColors.success),
                  const SizedBox(width: 8),
                  Expanded(child: Text('Saved to ${_file!.path}', style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary))),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: OutlinedButton.icon(onPressed: _open, icon: const Icon(Icons.open_in_new_rounded, size: 18), label: const Text('Open'))),
                  const SizedBox(width: 12),
                  Expanded(child: OutlinedButton.icon(onPressed: _share, icon: const Icon(Icons.share_rounded, size: 18), label: const Text('Share'))),
                ]),
              ]),
            ),
        ]),
      ),
    );
  }
}
