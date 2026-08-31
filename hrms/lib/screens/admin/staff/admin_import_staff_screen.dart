// lib/screens/admin/staff/admin_import_staff_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import '../../../config/app_colors.dart';
import '../../../services/admin_staff_service.dart';
import '../../../utils/snackbar_utils.dart';
import '../../../widgets/app_tab_loader.dart';

class AdminImportStaffScreen extends StatefulWidget {
  const AdminImportStaffScreen({super.key});

  @override
  State<AdminImportStaffScreen> createState() => _AdminImportStaffScreenState();
}

class _AdminImportStaffScreenState extends State<AdminImportStaffScreen> {
  final AdminStaffService _staffService = AdminStaffService();
  bool _isLoading = true;

  // Setup template options
  List<dynamic> _branches = [];
  List<dynamic> _attendanceTemplates = [];
  List<dynamic> _weeklyOffTemplates = [];
  List<dynamic> _leaveTemplates = [];
  List<dynamic> _holidayTemplates = [];
  List<dynamic> _breakTemplates = [];
  List<dynamic> _overtimeTemplates = [];
  List<dynamic> _permissionTemplates = [];

  // Selected values
  String? _selectedBranch;
  String? _selectedAttendance;
  String? _selectedWeeklyOff;
  String? _selectedLeave;
  String? _selectedHoliday;
  String? _selectedBreak;
  String? _selectedOvertime;
  String? _selectedPermission;

  // File state
  String? _fileName;
  int _totalRecords = 0;
  int _fieldsMapped = 31;
  int _validationErrors = 0;

  @override
  void initState() {
    super.initState();
    _loadSetup();
  }

  Future<void> _loadSetup() async {
    setState(() => _isLoading = true);
    final res = await _staffService.getStaffSetup();
    if (mounted && res['success'] == true && res['data'] != null) {
      final d = res['data'] as Map<String, dynamic>;
      setState(() {
        _branches = (d['branches'] as List?) ?? [];
        _attendanceTemplates = (d['attendanceTemplates'] as List?) ?? [];
        _weeklyOffTemplates = (d['weeklyOffTemplates'] as List?) ?? [];
        _leaveTemplates = (d['leaveTemplates'] as List?) ?? [];
        _holidayTemplates = (d['holidayTemplates'] as List?) ?? [];
        _breakTemplates = (d['breakTemplates'] as List?) ?? [];
        _overtimeTemplates = (d['overtimeTemplates'] as List?) ?? [];
        _permissionTemplates = (d['permissionTemplates'] as List?) ?? [];
      });
    }
    if (mounted) setState(() => _isLoading = false);
  }

  void _pickExcelFile() {
    // Pick file mockup / notification
    SnackBarUtils.showSnackBar(context, 'Excel file picker: Select .xlsx or .xls');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF0F172A)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Import Staff Members',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF0F172A)),
        ),
        elevation: 0,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: const Color(0xFFF1F5F9), height: 1),
        ),
      ),
      body: _isLoading
          ? const Center(child: AppTabLoader())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Subtitle
                const Text(
                  'Bulk import via Excel — parse, preview, and configure templates',
                  style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
                ),
                const SizedBox(height: 16),

                // ── Upload Excel File Card ──
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: const [
                          Icon(Icons.file_upload_outlined, size: 16, color: Color(0xFF0F172A)),
                          SizedBox(width: 8),
                          Text(
                            'Upload Excel File',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      InkWell(
                        onTap: _pickExcelFile,
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: const Color(0xFFCBD5E1),
                              style: BorderStyle.solid,
                              width: 1.5,
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              Icon(Icons.description_outlined, size: 36, color: Color(0xFF94A3B8)),
                              SizedBox(height: 8),
                              Text(
                                'Drag & drop or click to upload',
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF334155)),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Accepts .xlsx or .xls files only',
                                style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // ── Mapping Metrics ──
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Mapping Metrics',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                      ),
                      const SizedBox(height: 12),
                      _metricRow('Total records', '$_totalRecords'),
                      _metricRow('Fields mapped', '$_fieldsMapped columns'),
                      _metricRow('Validation errors', '$_validationErrors'),
                      _metricRow('Showing (filtered)', '$_totalRecords'),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // ── Configure Templates Card ──
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Configure Templates',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Select a branch and templates, then assign them to the filtered staff members',
                        style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                      ),
                      const SizedBox(height: 16),

                      _dropdownField('Branch', _branches, _selectedBranch, (v) => setState(() => _selectedBranch = v)),
                      const SizedBox(height: 12),
                      _dropdownField('Attendance Template', _attendanceTemplates, _selectedAttendance, (v) => setState(() => _selectedAttendance = v)),
                      const SizedBox(height: 12),
                      _dropdownField('Weekly Off Template', _weeklyOffTemplates, _selectedWeeklyOff, (v) => setState(() => _selectedWeeklyOff = v)),
                      const SizedBox(height: 12),
                      _dropdownField('Leave Template', _leaveTemplates, _selectedLeave, (v) => setState(() => _selectedLeave = v)),
                      const SizedBox(height: 12),
                      _dropdownField('Holiday Template', _holidayTemplates, _selectedHoliday, (v) => setState(() => _selectedHoliday = v)),
                      const SizedBox(height: 12),
                      _dropdownField('Break Template', _breakTemplates, _selectedBreak, (v) => setState(() => _selectedBreak = v)),
                      const SizedBox(height: 12),
                      _dropdownField('Overtime Template', _overtimeTemplates, _selectedOvertime, (v) => setState(() => _selectedOvertime = v)),
                      const SizedBox(height: 12),
                      _dropdownField('Permission Template', _permissionTemplates, _selectedPermission, (v) => setState(() => _selectedPermission = v)),
                      const SizedBox(height: 18),

                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () {
                            SnackBarUtils.showSnackBar(context, 'Assigned to filtered records');
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFF1F5F9),
                            foregroundColor: const Color(0xFF64748B),
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          child: const Text(
                            'Assign to filtered (0)',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _metricRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
          Text(value, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Color(0xFF0F172A))),
        ],
      ),
    );
  }

  Widget _dropdownField(String label, List<dynamic> items, String? selectedValue, ValueChanged<String?> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF475569))),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: selectedValue,
              hint: Text('Select ${label.toLowerCase()}', style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
              isExpanded: true,
              icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: Color(0xFF64748B)),
              items: items.map((item) {
                final name = item is Map
                    ? (item['name'] ?? item['branchName'] ?? item['templateName'] ?? item['title'] ?? '').toString()
                    : item.toString();
                final id = item is Map ? (item['_id'] ?? item['id'] ?? name).toString() : name;
                return DropdownMenuItem<String>(
                  value: id,
                  child: Text(name, style: const TextStyle(fontSize: 12.5, color: Color(0xFF0F172A))),
                );
              }).toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}
