// lib/screens/admin/staff/admin_import_staff_screen.dart
//
// Bulk staff import - mirrors the web admin page
// (HRMSfrontend features/admin/staff/staff/staff/pages/importStaff.tsx):
// pick a spreadsheet, map its columns onto the Add Staff fields, preview,
// assign a branch + templates to the filtered rows, then
// POST /admin/staff/import { rows, defaultBranch }.
import 'dart:convert';
import 'dart:io';

import 'package:excel/excel.dart' as xl;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../config/app_colors.dart';
import '../../../config/app_text_styles.dart';
import '../../../services/admin_staff_service.dart';
import '../../../utils/snackbar_utils.dart';
import '../../../widgets/app_card.dart';
import '../../../widgets/app_tab_loader.dart';

/// Hairline card border and field border (match the global theme).
const _cardBorder = Color(0xFFECEEF1);
const _fieldBorder = Color(0xFFE2E5EA);

/// Columns that must be present in the header row (same as web).
const List<String> _requiredHeaders = [
  'EmployeeId', 'Name', 'Email', 'Phone', 'Designation', 'Department', 'BranchName', 'JoiningDate',
];

/// Every column the importer understands (same as web).
const List<String> _allExpectedHeaders = [
  'EmployeeId', 'Name', 'Email', 'Phone', 'AlternativePhone', 'Designation', 'Department', 'StaffType',
  'BranchName', 'JoiningDate', 'Status', 'ManagerEmployeeId', 'Role', 'Gender', 'DOB', 'MaritalStatus',
  'BloodGroup', 'AddressLine1', 'AddressState', 'AddressPostalCode', 'AddressCountry', 'BankName',
  'BankAccountNumber', 'BankIFSC', 'BankAccountHolderName', 'BankUPI', 'UAN', 'PAN', 'Aadhaar',
  'PFNumber', 'ESINumber',
];

/// Spreadsheet column -> staff field, shown as a reference (same as web).
const List<List<String>> _columnMapReference = [
  ['EmployeeId', 'employeeId'],
  ['Name', 'firstName (full name)'],
  ['Email', 'email'],
  ['Phone', 'phoneNumber'],
  ['AlternativePhone', 'alternatePhoneNumber'],
  ['Designation', 'designation'],
  ['Department', 'department'],
  ['StaffType', 'employmentType'],
  ['BranchName', 'branch'],
  ['JoiningDate', 'joiningDate'],
  ['Status', 'status'],
  ['ManagerEmployeeId', 'reportingManager'],
  ['Role', 'jobRole'],
  ['Gender', 'gender'],
  ['DOB', 'dateOfBirth'],
  ['MaritalStatus', 'maritalStatus'],
  ['BloodGroup', 'bloodGroup'],
  ['AddressLine1', 'currentAddress.address'],
  ['AddressState', 'currentAddress.state'],
  ['AddressPostalCode', 'currentAddress.pincode'],
  ['AddressCountry', 'currentAddress.country'],
  ['BankName', 'bankName'],
  ['BankAccountNumber', 'accountNumber'],
  ['BankIFSC', 'ifscCode'],
  ['BankAccountHolderName', 'accountHolderName'],
  ['BankUPI', 'upiId'],
  ['UAN', 'uanNumber'],
  ['PAN', 'panNumber'],
  ['Aadhaar', 'aadhaarNumber'],
  ['PFNumber', 'pfNumber'],
  ['ESINumber', 'esiNumber'],
];

/// Template fields on a row, with their labels (order as the web preview).
const List<List<String>> _templateFields = [
  ['leaveTemplate', 'Leave'],
  ['attendanceTemplate', 'Attendance'],
  ['holidayTemplate', 'Holiday'],
  ['breakTemplate', 'Break'],
  ['overtimeTemplate', 'Overtime'],
  ['weeklyOffTemplate', 'Weekly Off'],
  ['permissionTemplate', 'Permission'],
];

class AdminImportStaffScreen extends StatefulWidget {
  const AdminImportStaffScreen({super.key});

  @override
  State<AdminImportStaffScreen> createState() => _AdminImportStaffScreenState();
}

class _AdminImportStaffScreenState extends State<AdminImportStaffScreen> {
  final AdminStaffService _staffService = AdminStaffService();
  final TextEditingController _searchController = TextEditingController();

  // Setup (branches + templates)
  bool _isLoading = true;
  String? _loadError;
  List<Map<String, dynamic>> _branches = [];
  List<Map<String, dynamic>> _attendanceTemplates = [];
  List<Map<String, dynamic>> _weeklyOffTemplates = [];
  List<Map<String, dynamic>> _leaveTemplates = [];
  List<Map<String, dynamic>> _holidayTemplates = [];
  List<Map<String, dynamic>> _breakTemplates = [];
  List<Map<String, dynamic>> _overtimeTemplates = [];
  List<Map<String, dynamic>> _permissionTemplates = [];

  // Selected defaults (ids)
  String? _selectedBranch;
  String? _selectedAttendance;
  String? _selectedWeeklyOff;
  String? _selectedLeave;
  String? _selectedHoliday;
  String? _selectedBreak;
  String? _selectedOvertime;
  String? _selectedPermission;

  // File / parse state
  bool _isParsing = false;
  String? _fileName;
  List<Map<String, dynamic>> _rows = [];
  List<String> _validationErrors = [];
  List<String> _validationWarnings = [];

  // Filters
  String _search = '';
  String _filterStatus = 'All';
  String _filterDept = 'All';
  String _filterBranch = 'All';

  // Import
  bool _isImporting = false;
  Map<String, dynamic>? _importResult;

  @override
  void initState() {
    super.initState();
    _loadSetup();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  static List<Map<String, dynamic>> _maps(dynamic list) => (list is List ? list : const [])
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList();

  Future<void> _loadSetup() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    final results = await Future.wait([
      _staffService.getStaffSetup(),
      _staffService.getBranches(),
    ]);
    if (!mounted) return;
    final setupRes = results[0];
    final branchRes = results[1];

    if (setupRes['success'] != true) {
      setState(() {
        _isLoading = false;
        _loadError = (setupRes['message'] ?? 'Could not load staff templates.').toString();
      });
      return;
    }
    if (branchRes['success'] != true) {
      setState(() {
        _isLoading = false;
        _loadError = (branchRes['message'] ?? 'Could not load branches.').toString();
      });
      return;
    }

    final d = setupRes['data'] is Map ? Map<String, dynamic>.from(setupRes['data'] as Map) : <String, dynamic>{};
    setState(() {
      _branches = _maps(branchRes['data']);
      _attendanceTemplates = _maps(d['attendanceTemplates']);
      _weeklyOffTemplates = _maps(d['weeklyOffTemplates']);
      _leaveTemplates = _maps(d['leaveTemplates']);
      _holidayTemplates = _maps(d['holidayTemplates']);
      _breakTemplates = _maps(d['breakTemplates']);
      _overtimeTemplates = _maps(d['overtimeTemplates']);
      _permissionTemplates = _maps(d['permissionTemplates']);
      _isLoading = false;
    });
  }

  // ─────────────────────────── File picking & parsing ───────────────────────────

  Future<void> _pickFile() async {
    FilePickerResult? picked;
    try {
      picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['xlsx', 'xls', 'csv'],
        withData: true,
      );
    } catch (e) {
      if (mounted) {
        SnackBarUtils.showSnackBar(context, 'Could not open the file picker: $e', isError: true);
      }
      return;
    }
    if (picked == null || picked.files.isEmpty) return;
    final file = picked.files.first;
    final name = file.name;
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';

    if (ext != 'xlsx' && ext != 'xls' && ext != 'csv') {
      setState(() {
        _validationErrors = ['Invalid file type. Please upload only .xlsx, .xls or .csv files.'];
        _validationWarnings = [];
        _rows = [];
        _fileName = null;
      });
      return;
    }

    setState(() {
      _isParsing = true;
      _importResult = null;
    });

    try {
      List<int>? bytes = file.bytes;
      if (bytes == null && file.path != null) {
        bytes = await File(file.path!).readAsBytes();
      }
      if (bytes == null || bytes.isEmpty) {
        throw const FormatException('The selected file is empty or could not be read.');
      }

      final List<List<dynamic>> rawRows;
      if (ext == 'csv') {
        rawRows = _parseCsv(utf8.decode(bytes, allowMalformed: true));
      } else {
        rawRows = _parseXlsx(bytes, ext);
      }
      _processRows(name, rawRows);
    } on FormatException catch (e) {
      setState(() {
        _fileName = name;
        _rows = [];
        _validationWarnings = [];
        _validationErrors = [e.message];
      });
    } catch (e) {
      setState(() {
        _fileName = name;
        _rows = [];
        _validationWarnings = [];
        _validationErrors = [
          ext == 'xls'
              ? 'Could not read this .xls file. Legacy .xls workbooks are not supported on mobile - please save it as .xlsx or .csv and try again.'
              : 'Failed to parse the file. Please check the file format.',
        ];
      });
    } finally {
      if (mounted) setState(() => _isParsing = false);
    }
  }

  /// First sheet of an .xlsx workbook as rows of raw cell values.
  List<List<dynamic>> _parseXlsx(List<int> bytes, String ext) {
    final xl.Excel book;
    try {
      book = xl.Excel.decodeBytes(bytes);
    } catch (_) {
      throw FormatException(
        ext == 'xls'
            ? 'Could not read this .xls file. Legacy .xls workbooks are not supported on mobile - please save it as .xlsx or .csv and try again.'
            : 'Failed to parse the Excel file. Please check the file format.',
      );
    }
    if (book.tables.isEmpty) {
      throw const FormatException('No sheets found in the workbook.');
    }
    final sheetName = book.tables.keys.first;
    final sheet = book.tables[sheetName]!;
    return sheet.rows.map((r) => r.map((c) => _cellRaw(c?.value)).toList()).toList();
  }

  static dynamic _cellRaw(xl.CellValue? v) {
    if (v == null) return null;
    if (v is xl.TextCellValue) return v.value.toString();
    if (v is xl.IntCellValue) return v.value;
    if (v is xl.DoubleCellValue) return v.value;
    if (v is xl.BoolCellValue) return v.value;
    if (v is xl.DateCellValue) return DateTime(v.year, v.month, v.day);
    if (v is xl.DateTimeCellValue) return DateTime(v.year, v.month, v.day, v.hour, v.minute, v.second);
    return v.toString();
  }

  /// Minimal RFC-4180 CSV reader (quoted fields, escaped quotes, CRLF/LF).
  static List<List<dynamic>> _parseCsv(String input) {
    var text = input;
    if (text.startsWith('﻿')) text = text.substring(1);
    final rows = <List<dynamic>>[];
    var row = <dynamic>[];
    final field = StringBuffer();
    var inQuotes = false;
    for (var i = 0; i < text.length; i++) {
      final ch = text[i];
      if (inQuotes) {
        if (ch == '"') {
          if (i + 1 < text.length && text[i + 1] == '"') {
            field.write('"');
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          field.write(ch);
        }
        continue;
      }
      if (ch == '"') {
        inQuotes = true;
      } else if (ch == ',') {
        row.add(field.toString());
        field.clear();
      } else if (ch == '\r' || ch == '\n') {
        if (ch == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
        row.add(field.toString());
        field.clear();
        rows.add(row);
        row = <dynamic>[];
      } else {
        field.write(ch);
      }
    }
    if (field.isNotEmpty || row.isNotEmpty) {
      row.add(field.toString());
      rows.add(row);
    }
    return rows;
  }

  static String _dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// "YYYY-MM-DD" when y-m-d is a real calendar date, otherwise null.
  static String? _validDateKey(int y, int m, int d) {
    final date = DateTime(y, m, d);
    if (date.year != y || date.month != m || date.day != d) return null;
    return _dateKey(date);
  }

  /// Same accepted forms as the web importer: a date cell, an Excel serial
  /// number, DD/MM/YYYY (or DD-MM-YYYY), YYYY-MM-DD, or another parseable date.
  static String? _parseDate(dynamic raw) {
    if (raw == null) return null;
    if (raw is DateTime) return _dateKey(raw);
    if (raw is num) {
      if (!raw.isFinite || raw <= 0) return null;
      final d = DateTime(1899, 12, 30).add(Duration(days: raw.floor()));
      return _validDateKey(d.year, d.month, d.day);
    }
    final str = raw.toString().trim();
    final ddMm = RegExp(r'^(\d{1,2})[/\-](\d{1,2})[/\-](\d{4})$').firstMatch(str);
    if (ddMm != null) {
      return _validDateKey(int.parse(ddMm.group(3)!), int.parse(ddMm.group(2)!), int.parse(ddMm.group(1)!));
    }
    final iso = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(str);
    if (iso != null) {
      return _validDateKey(int.parse(iso.group(1)!), int.parse(iso.group(2)!), int.parse(iso.group(3)!));
    }
    if (RegExp(r'^\d+$').hasMatch(str)) return null;
    final parsed = DateTime.tryParse(str);
    return parsed == null ? null : _dateKey(parsed);
  }

  /// Cell value as trimmed text. Integral numbers lose their ".0" so phone
  /// numbers and IDs stored as numbers read as typed.
  static String _cellText(dynamic v) {
    if (v == null) return '';
    if (v is double) {
      if (v.isFinite && v == v.truncateToDouble()) return v.toInt().toString();
      return v.toString();
    }
    if (v is DateTime) return _dateKey(v);
    return v.toString().trim();
  }

  void _processRows(String fileName, List<List<dynamic>> rawRows) {
    if (rawRows.isEmpty) {
      throw const FormatException('The uploaded sheet is empty.');
    }
    final headers = rawRows.first.map((h) => _cellText(h)).toList();
    if (headers.isEmpty || headers.every((h) => h.isEmpty)) {
      throw const FormatException('Could not read column headers from the file.');
    }

    final missingRequired = _requiredHeaders.where((h) => !headers.contains(h)).toList();
    if (missingRequired.isNotEmpty) {
      setState(() {
        _fileName = fileName;
        _rows = [];
        _validationWarnings = [];
        _validationErrors = missingRequired.map((h) => 'Missing required column: $h').toList();
      });
      return;
    }

    final warnings = <String>[];
    final missingOptional =
        _allExpectedHeaders.where((h) => !_requiredHeaders.contains(h) && !headers.contains(h)).toList();
    if (missingOptional.isNotEmpty) {
      warnings.add('Optional columns not found (will be blank): ${missingOptional.join(', ')}');
    }

    dynamic rawVal(List<dynamic> row, String header) {
      final idx = headers.indexOf(header);
      if (idx == -1 || idx >= row.length) return null;
      return row[idx];
    }

    String getVal(List<dynamic> row, String header) => _cellText(rawVal(row, header));

    final parsed = <Map<String, dynamic>>[];
    final errors = <String>[];
    final seenEmpIds = <String>{};
    final emailRe = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

    for (var i = 1; i < rawRows.length; i++) {
      final row = rawRows[i];
      if (row.isEmpty || row.every((c) => _cellText(c).isEmpty)) continue;
      final rowNo = i + 1;

      final empId = getVal(row, 'EmployeeId');
      final name = getVal(row, 'Name');
      final email = getVal(row, 'Email');
      final phone = getVal(row, 'Phone');
      final altPhone = getVal(row, 'AlternativePhone');
      final jDateRaw = rawVal(row, 'JoiningDate');
      final dobRaw = rawVal(row, 'DOB');

      var blocking = false;
      if (empId.isEmpty) {
        errors.add('Row $rowNo: EmployeeId is missing.');
        blocking = true;
      } else if (seenEmpIds.contains(empId.toLowerCase())) {
        errors.add('Row $rowNo: Duplicate EmployeeId "$empId".');
      }

      if (name.isEmpty) errors.add('Row $rowNo: Name is missing.');
      if (email.isEmpty) {
        errors.add('Row $rowNo: Email is missing.');
      } else if (!emailRe.hasMatch(email)) {
        errors.add('Row $rowNo: Invalid Email format "$email".');
      }
      if (phone.isEmpty) errors.add('Row $rowNo: Phone number is missing.');

      var joiningDate = '';
      if (_cellText(jDateRaw).isEmpty) {
        errors.add('Row $rowNo: JoiningDate is missing.');
      } else {
        final p = _parseDate(jDateRaw);
        if (p == null) {
          errors.add('Row $rowNo: Invalid JoiningDate "${_cellText(jDateRaw)}". Use YYYY-MM-DD or DD/MM/YYYY.');
        } else {
          joiningDate = p;
        }
      }

      var dateOfBirth = '';
      if (_cellText(dobRaw).isNotEmpty) {
        final p = _parseDate(dobRaw);
        if (p == null) {
          errors.add('Row $rowNo: Invalid DOB "${_cellText(dobRaw)}". Use YYYY-MM-DD or DD/MM/YYYY.');
        } else {
          dateOfBirth = p;
        }
      }

      if (blocking) continue;
      seenEmpIds.add(empId.toLowerCase());

      final status = getVal(row, 'Status');
      parsed.add({
        // Sheet row number, so the server's failure report points at the right row.
        'rowNumber': rowNo,
        'employeeId': empId,
        'firstName': name.trim(),
        'lastName': '',
        'email': email,
        'phoneNumber': phone,
        'alternatePhoneNumber': altPhone,
        'designation': getVal(row, 'Designation'),
        'department': getVal(row, 'Department'),
        'employmentType': getVal(row, 'StaffType'),
        'branch': getVal(row, 'BranchName'),
        'joiningDate': joiningDate,
        'status': status.isEmpty ? 'Active' : status,
        'reportingManager': getVal(row, 'ManagerEmployeeId'),
        'jobRole': getVal(row, 'Role'),
        'gender': getVal(row, 'Gender'),
        'dateOfBirth': dateOfBirth,
        'maritalStatus': getVal(row, 'MaritalStatus'),
        'bloodGroup': getVal(row, 'BloodGroup'),
        'currentAddress': {
          'address': getVal(row, 'AddressLine1'),
          'state': getVal(row, 'AddressState'),
          'pincode': getVal(row, 'AddressPostalCode'),
          'country': getVal(row, 'AddressCountry'),
        },
        'bankName': getVal(row, 'BankName'),
        'accountNumber': getVal(row, 'BankAccountNumber'),
        'ifscCode': getVal(row, 'BankIFSC'),
        'accountHolderName': getVal(row, 'BankAccountHolderName'),
        'upiId': getVal(row, 'BankUPI'),
        'uanNumber': getVal(row, 'UAN'),
        'panNumber': getVal(row, 'PAN'),
        'aadhaarNumber': getVal(row, 'Aadhaar'),
        'pfNumber': getVal(row, 'PFNumber'),
        'esiNumber': getVal(row, 'ESINumber'),
        'password': 'User@123',
        'leaveTemplate': '',
        'holidayTemplate': '',
        'weeklyOffTemplate': '',
        'breakTemplate': '',
        'overtimeTemplate': '',
        'permissionTemplate': '',
        'attendanceTemplate': '',
      });
    }

    setState(() {
      _fileName = fileName;
      _validationErrors = errors;
      _validationWarnings = warnings;
      _rows = parsed;
      _search = '';
      _searchController.clear();
      _filterStatus = 'All';
      _filterDept = 'All';
      _filterBranch = 'All';
    });
  }

  // ─────────────────────────── Derived data ───────────────────────────

  String _s(Map<String, dynamic> r, String k) => (r[k] ?? '').toString();

  List<String> get _departmentsList =>
      _rows.map((r) => _s(r, 'department')).where((s) => s.isNotEmpty).toSet().toList();

  List<String> get _branchesList =>
      _rows.map((r) => _s(r, 'branch')).where((s) => s.isNotEmpty).toSet().toList();

  List<Map<String, dynamic>> get _filtered {
    final q = _search.toLowerCase();
    return _rows.where((r) {
      final matchSearch = q.isEmpty ||
          ['employeeId', 'firstName', 'email', 'phoneNumber', 'designation', 'department']
              .any((k) => _s(r, k).toLowerCase().contains(q));
      final matchStatus = _filterStatus == 'All' || _s(r, 'status').toLowerCase() == _filterStatus.toLowerCase();
      final matchDept = _filterDept == 'All' || _s(r, 'department').toLowerCase() == _filterDept.toLowerCase();
      final matchBranch = _filterBranch == 'All' || _s(r, 'branch').toLowerCase() == _filterBranch.toLowerCase();
      return matchSearch && matchStatus && matchDept && matchBranch;
    }).toList();
  }

  bool get _hasActiveFilter => _filterStatus != 'All' || _filterDept != 'All' || _filterBranch != 'All';

  Map<String, String> get _templateNameById {
    final map = <String, String>{};
    for (final list in [
      _attendanceTemplates,
      _weeklyOffTemplates,
      _leaveTemplates,
      _holidayTemplates,
      _breakTemplates,
      _overtimeTemplates,
      _permissionTemplates,
    ]) {
      for (final t in list) {
        final id = (t['_id'] ?? '').toString();
        if (id.isNotEmpty) map[id] = (t['name'] ?? t['title'] ?? id).toString();
      }
    }
    return map;
  }

  String _branchLabel(String value) {
    if (value.isEmpty) return '';
    for (final b in _branches) {
      if ((b['_id'] ?? '').toString() == value) return (b['branchName'] ?? value).toString();
    }
    return value;
  }

  // ─────────────────────────── Actions ───────────────────────────

  void _assignTemplates() {
    if (_rows.isEmpty) {
      SnackBarUtils.showSnackBar(context, 'Please upload a spreadsheet first.', isError: true);
      return;
    }
    final filtered = _filtered;
    if (filtered.isEmpty) {
      SnackBarUtils.showSnackBar(context, 'No staff members match the current filter criteria.', isError: true);
      return;
    }
    final ids = filtered.map((r) => _s(r, 'employeeId').toLowerCase()).toSet();
    var updated = 0;
    String pick(String? sel, Map<String, dynamic> r, String key) =>
        (sel != null && sel.isNotEmpty) ? sel : _s(r, key);

    setState(() {
      _rows = _rows.map((r) {
        if (!ids.contains(_s(r, 'employeeId').toLowerCase())) return r;
        updated++;
        return {
          ...r,
          'leaveTemplate': pick(_selectedLeave, r, 'leaveTemplate'),
          'holidayTemplate': pick(_selectedHoliday, r, 'holidayTemplate'),
          'weeklyOffTemplate': pick(_selectedWeeklyOff, r, 'weeklyOffTemplate'),
          'breakTemplate': pick(_selectedBreak, r, 'breakTemplate'),
          'overtimeTemplate': pick(_selectedOvertime, r, 'overtimeTemplate'),
          'permissionTemplate': pick(_selectedPermission, r, 'permissionTemplate'),
          'attendanceTemplate': pick(_selectedAttendance, r, 'attendanceTemplate'),
          // A selected branch overrides whatever BranchName the sheet carried.
          'branch': pick(_selectedBranch, r, 'branch'),
        };
      }).toList();
    });
    SnackBarUtils.showSnackBar(context, 'Assigned templates to $updated filtered staff records.');
  }

  Future<void> _save() async {
    if (_rows.isEmpty || _isImporting) return;
    if (_validationErrors.isNotEmpty) {
      SnackBarUtils.showSnackBar(context, 'Fix the validation errors before saving.', isError: true);
      return;
    }
    setState(() => _isImporting = true);
    // Every parsed row is sent, not just the filtered view (same as web).
    final res = await _staffService.importStaff(rows: _rows, defaultBranch: _selectedBranch);
    if (!mounted) return;
    setState(() => _isImporting = false);

    if (res['success'] != true || res['data'] is! Map) {
      SnackBarUtils.showSnackBar(
        context,
        (res['message'] ?? 'Failed to import staff members.').toString(),
        isError: true,
      );
      return;
    }
    final data = Map<String, dynamic>.from(res['data'] as Map);
    setState(() => _importResult = data);
    final imported = (data['imported'] as num?)?.toInt() ?? 0;
    final total = (data['totalRows'] as num?)?.toInt() ?? _rows.length;
    final failed = (data['failed'] as num?)?.toInt() ?? 0;
    if (failed > 0) {
      SnackBarUtils.showSnackBar(
        context,
        'Imported $imported of $total. $failed row${failed > 1 ? 's' : ''} could not be imported.',
        isError: true,
      );
    } else if (imported > 0) {
      SnackBarUtils.showSnackBar(context, 'Imported $imported of $total staff members.');
    }
  }

  void _clear() {
    setState(() {
      _rows = [];
      _fileName = null;
      _validationErrors = [];
      _validationWarnings = [];
      _search = '';
      _searchController.clear();
      _filterStatus = 'All';
      _filterDept = 'All';
      _filterBranch = 'All';
      _importResult = null;
    });
  }

  // ─────────────────────────── UI ───────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context, _importResult != null),
        ),
        title: const Text('Import Staff Members'),
      ),
      body: _isLoading
          ? const Center(child: AppTabLoader())
          : _loadError != null
              ? _buildLoadError()
              : _buildContent(),
      bottomNavigationBar: _rows.isNotEmpty ? _buildSaveBar() : null,
    );
  }

  Widget _buildLoadError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(color: AppColors.errorBg, shape: BoxShape.circle),
              child: const Icon(Icons.error_outline_rounded, size: 30, color: AppColors.error),
            ),
            const SizedBox(height: 16),
            Text(
              _loadError!,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodySmall,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadSetup,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    final filtered = _filtered;
    final nameById = _templateNameById;
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              const Text(
                'Bulk import via Excel or CSV — parse, preview, and configure templates',
                style: AppTextStyles.bodySmall,
              ),
              const SizedBox(height: 16),
              _buildUploadCard(),
              if (_validationErrors.isNotEmpty || _validationWarnings.isNotEmpty) ...[
                const SizedBox(height: 12),
                _buildValidationCard(),
              ],
              const SizedBox(height: 12),
              _buildMetricsCard(filtered.length),
              const SizedBox(height: 12),
              _buildMappingCard(),
              const SizedBox(height: 12),
              _buildTemplatesCard(filtered.length),
              if (_importResult != null) ...[
                const SizedBox(height: 12),
                _buildResultCard(),
              ],
              if (_rows.isNotEmpty) ...[
                const SizedBox(height: 12),
                _buildPreviewHeader(filtered.length),
                const SizedBox(height: 12),
              ],
              if (_fileName == null && _rows.isEmpty && _validationErrors.isEmpty) ...[
                const SizedBox(height: 12),
                _buildEmptyState(),
              ],
            ]),
          ),
        ),
        if (_rows.isNotEmpty)
          filtered.isEmpty
              ? const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(
                      child: Text(
                        'No records match your search or filter criteria.',
                        textAlign: TextAlign.center,
                        style: AppTextStyles.bodySmall,
                      ),
                    ),
                  ),
                )
              : SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (ctx, i) => _buildRowCard(filtered[i], i, nameById),
                      childCount: filtered.length,
                    ),
                  ),
                ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }

  BoxDecoration get _cardDecoration => BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _cardBorder),
        boxShadow: kSoftCardShadow,
      );

  /// Card header: tinted icon tile (or numbered step badge) + headingSmall title.
  Widget _cardTitle(IconData icon, String title, {Widget? trailing, int? step, Color? color}) {
    final tint = color ?? AppColors.primaryText;
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: (color ?? AppColors.primary).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 20, color: tint),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (step != null) ...[
                Text('STEP $step', style: AppTextStyles.sectionLabel),
                const SizedBox(height: 2),
              ],
              Text(title, style: AppTextStyles.headingSmall),
            ],
          ),
        ),
        if (trailing != null) trailing,
      ],
    );
  }

  Widget _buildUploadCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitle(Icons.file_upload_outlined, 'Upload Spreadsheet', step: 1),
          const SizedBox(height: 16),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _isParsing ? null : _pickFile,
              borderRadius: BorderRadius.circular(16),
              child: Ink(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.45), width: 1.5),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      alignment: Alignment.center,
                      child: _isParsing
                          ? SizedBox(
                              width: 26,
                              height: 26,
                              child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.primaryText),
                            )
                          : Icon(Icons.cloud_upload_outlined, size: 28, color: AppColors.primaryText),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _isParsing ? 'Reading file…' : 'Tap to choose a file',
                      style: AppTextStyles.headingSmall.copyWith(fontSize: 15),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Accepts .xlsx, .xls or .csv files',
                      style: AppTextStyles.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_fileName != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
              decoration: BoxDecoration(
                color: _rows.isNotEmpty ? AppColors.successBg.withValues(alpha: 0.5) : AppColors.errorBg.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: (_rows.isNotEmpty ? AppColors.success : AppColors.error).withValues(alpha: 0.25),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _rows.isNotEmpty ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                    size: 20,
                    color: _rows.isNotEmpty ? AppColors.success : AppColors.error,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _fileName!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.label.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${_rows.length} employee records parsed',
                          style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  TextButton(onPressed: _clear, child: const Text('Clear')),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _note(String text, {bool danger = false}) {
    final fg = danger ? AppColors.error : AppColors.warning;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: danger ? AppColors.errorBg.withValues(alpha: 0.6) : AppColors.warningBg.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: fg.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            danger ? Icons.error_outline_rounded : Icons.warning_amber_rounded,
            size: 18,
            color: fg,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildValidationCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitle(
            Icons.shield_outlined,
            'Validation Report',
            color: _validationErrors.isEmpty ? AppColors.warning : AppColors.error,
            trailing: _validationErrors.isEmpty
                ? null
                : Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.errorBg,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${_validationErrors.length} error${_validationErrors.length > 1 ? 's' : ''}',
                      style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w600, color: AppColors.error),
                    ),
                  ),
          ),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 260),
            child: SingleChildScrollView(
              child: Column(
                children: [
                  ..._validationErrors.map((e) => _note(e, danger: true)),
                  ..._validationWarnings.map((w) => _note(w)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricRow(String label, String value, {bool errored = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppTextStyles.bodySmall),
          Text(
            value,
            style: AppTextStyles.label.copyWith(
              fontWeight: FontWeight.w600,
              color: errored ? AppColors.error : AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricsCard(int filteredCount) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitle(Icons.bar_chart_rounded, 'Mapping Metrics', color: AppColors.info),
          const SizedBox(height: 8),
          _metricRow('Total records', '${_rows.length}'),
          const Divider(height: 1),
          _metricRow('Fields mapped', '${_columnMapReference.length} columns'),
          const Divider(height: 1),
          _metricRow('Validation errors', '${_validationErrors.length}', errored: _validationErrors.isNotEmpty),
          const Divider(height: 1),
          _metricRow('Showing (filtered)', '$filteredCount'),
        ],
      ),
    );
  }

  Widget _buildMappingCard() {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: _cardDecoration,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.table_chart_outlined, size: 20, color: AppColors.primaryText),
          ),
          title: const Text(
            'Spreadsheet to Staff Mapping',
            style: AppTextStyles.headingSmall,
          ),
          subtitle: const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Text(
              'Row 1 must hold these exact column headers. * = required',
              style: AppTextStyles.caption,
            ),
          ),
          children: _columnMapReference.map((pair) {
            final required = _requiredHeaders.contains(pair[0]);
            return Container(
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: _cardBorder)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${pair[0]}${required ? ' *' : ''}',
                      style: TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                        fontWeight: required ? FontWeight.w700 : FontWeight.w500,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      pair[1],
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontSize: 11.5, fontFamily: 'monospace', color: AppColors.textSecondary),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildTemplatesCard(int filteredCount) {
    final canAssign = _rows.isNotEmpty && filteredCount > 0;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitle(Icons.tune_rounded, 'Configure Templates', step: 2),
          const SizedBox(height: 8),
          const Text(
            'Select a branch and templates, then assign them to the filtered staff members',
            style: AppTextStyles.bodySmall,
          ),
          const SizedBox(height: 16),
          _dropdownField(
            'Branch',
            _branches,
            _selectedBranch,
            (v) => setState(() => _selectedBranch = v),
            nameKey: 'branchName',
            emptyText: 'No branches configured',
          ),
          const SizedBox(height: 12),
          _dropdownField('Attendance Template', _attendanceTemplates, _selectedAttendance,
              (v) => setState(() => _selectedAttendance = v)),
          const SizedBox(height: 12),
          _dropdownField('Weekly Off Template', _weeklyOffTemplates, _selectedWeeklyOff,
              (v) => setState(() => _selectedWeeklyOff = v)),
          const SizedBox(height: 12),
          _dropdownField('Leave Template', _leaveTemplates, _selectedLeave, (v) => setState(() => _selectedLeave = v)),
          const SizedBox(height: 12),
          _dropdownField('Holiday Template', _holidayTemplates, _selectedHoliday,
              (v) => setState(() => _selectedHoliday = v)),
          const SizedBox(height: 12),
          _dropdownField('Break Template', _breakTemplates, _selectedBreak, (v) => setState(() => _selectedBreak = v)),
          const SizedBox(height: 12),
          _dropdownField('Overtime Template', _overtimeTemplates, _selectedOvertime,
              (v) => setState(() => _selectedOvertime = v)),
          const SizedBox(height: 12),
          _dropdownField('Permission Template', _permissionTemplates, _selectedPermission,
              (v) => setState(() => _selectedPermission = v)),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: canAssign ? _assignTemplates : null,
              icon: const Icon(Icons.auto_awesome_rounded, size: 18),
              label: Text('Assign to filtered ($filteredCount)'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.ink,
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dropdownField(
    String label,
    List<Map<String, dynamic>> items,
    String? selectedValue,
    ValueChanged<String?> onChanged, {
    String nameKey = 'name',
    String? emptyText,
  }) {
    final options = items
        .map((t) {
          final id = (t['_id'] ?? '').toString();
          final name = (t[nameKey] ?? t['name'] ?? t['title'] ?? id).toString();
          return MapEntry(id, name);
        })
        .where((e) => e.key.isNotEmpty)
        .toList();
    final value = options.any((e) => e.key == selectedValue) ? selectedValue : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTextStyles.label.copyWith(fontSize: 13, color: AppColors.textSecondary)),
        const SizedBox(height: 6),
        InputDecorator(
          decoration: const InputDecoration(
            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isDense: true,
              borderRadius: BorderRadius.circular(12),
              hint: Text(
                options.isEmpty ? (emptyText ?? 'No templates available') : 'Select ${label.toLowerCase()}',
                style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textCaption),
              ),
              isExpanded: true,
              icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 20, color: AppColors.textSecondary),
              items: [
                if (options.isNotEmpty)
                  DropdownMenuItem<String>(
                    value: null,
                    child: Text('— None —', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textCaption)),
                  ),
                ...options.map((e) => DropdownMenuItem<String>(
                      value: e.key,
                      child: Text(e.value, style: AppTextStyles.bodyMedium),
                    )),
              ],
              onChanged: options.isEmpty ? null : onChanged,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPreviewHeader(int filteredCount) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitle(Icons.preview_outlined, 'Preview — Final Mapped Data', step: 3),
          const SizedBox(height: 8),
          Text(
            '$filteredCount of ${_rows.length} records · Verify before proceeding',
            style: AppTextStyles.bodySmall,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  onChanged: (v) => setState(() => _search = v),
                  style: AppTextStyles.bodyMedium,
                  decoration: InputDecoration(
                    hintText: 'Search staff...',
                    isDense: true,
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    suffixIcon: _search.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear search',
                            icon: const Icon(Icons.close_rounded, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _search = '');
                            },
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: _openFilters,
                  icon: Icon(Icons.filter_list_rounded, size: 18,
                      color: _hasActiveFilter ? AppColors.onPrimary : AppColors.textPrimary),
                  label: Text(
                    'Filters',
                    style: TextStyle(color: _hasActiveFilter ? AppColors.onPrimary : AppColors.textPrimary),
                  ),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: _hasActiveFilter ? AppColors.primary : AppColors.surface,
                    side: BorderSide(color: _hasActiveFilter ? AppColors.primary : _fieldBorder),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _openFilters() async {
    var status = _filterStatus;
    var dept = _filterDept;
    var branch = _filterBranch;
    final depts = _departmentsList;
    final branches = _branchesList;

    final applied = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          Widget simpleDropdown(String label, String value, List<String> opts, String allLabel, ValueChanged<String> on) {
            final all = ['All', ...opts];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppTextStyles.label.copyWith(fontSize: 13, color: AppColors.textSecondary)),
                const SizedBox(height: 6),
                InputDecorator(
                  decoration: const InputDecoration(
                    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: all.contains(value) ? value : 'All',
                      isExpanded: true,
                      isDense: true,
                      borderRadius: BorderRadius.circular(12),
                      icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 20, color: AppColors.textSecondary),
                      items: all
                          .map((o) => DropdownMenuItem(
                                value: o,
                                child: Text(
                                  o == 'All' ? allLabel : _branchLabelOr(o, label),
                                  style: AppTextStyles.bodyMedium,
                                ),
                              ))
                          .toList(),
                      onChanged: (v) => on(v ?? 'All'),
                    ),
                  ),
                ),
              ],
            );
          }

          return Padding(
            padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(999)),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Advanced Filters', style: AppTextStyles.headingMedium),
                const SizedBox(height: 16),
                simpleDropdown('Status', status, const ['Active', 'Deactive'], 'All statuses',
                    (v) => setSheet(() => status = v)),
                const SizedBox(height: 12),
                simpleDropdown('Department', dept, depts, 'All departments', (v) => setSheet(() => dept = v)),
                const SizedBox(height: 12),
                simpleDropdown('Branch', branch, branches, 'All branches', (v) => setSheet(() => branch = v)),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: OutlinedButton(
                          onPressed: () {
                            status = 'All';
                            dept = 'All';
                            branch = 'All';
                            Navigator.pop(ctx, true);
                          },
                          child: const Text('Clear all'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Apply filters'),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
    if (applied == true && mounted) {
      setState(() {
        _filterStatus = status;
        _filterDept = dept;
        _filterBranch = branch;
      });
    }
  }

  String _branchLabelOr(String value, String label) => label == 'Branch' ? _branchLabel(value) : value;

  Widget _kv(String k, String v, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 110, child: Text(k, style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary))),
          Expanded(
            child: Text(
              v.isEmpty ? '—' : v,
              style: AppTextStyles.bodySmall.copyWith(
                fontWeight: FontWeight.w500,
                color: v.isEmpty ? AppColors.textCaption : (valueColor ?? AppColors.textPrimary),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRowCard(Map<String, dynamic> r, int index, Map<String, String> nameById) {
    final addr = r['currentAddress'] is Map ? Map<String, dynamic>.from(r['currentAddress'] as Map) : <String, dynamic>{};
    final branch = _branchLabel(_s(r, 'branch'));
    final status = _s(r, 'status');
    final isActive = status.toLowerCase() == 'active';
    String tmpl(String key) {
      final id = _s(r, key);
      return id.isEmpty ? '' : (nameById[id] ?? id);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      decoration: _cardDecoration,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.fromLTRB(16, 4, 12, 4),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          title: Row(
            children: [
              Text('${index + 1}. ', style: AppTextStyles.bodySmall),
              Expanded(
                child: Text(
                  _s(r, 'firstName').isEmpty ? '—' : _s(r, 'firstName'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.headingSmall.copyWith(fontSize: 15),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isActive ? AppColors.successBg : AppColors.inputFill,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  status.isEmpty ? 'Active' : status,
                  style: AppTextStyles.caption.copyWith(
                    fontWeight: FontWeight.w600,
                    color: isActive ? AppColors.success : AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_s(r, 'employeeId')} · ${_s(r, 'email')}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 2),
                Text.rich(
                  TextSpan(
                    style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
                    children: [
                      TextSpan(text: '${_s(r, 'designation').isEmpty ? '—' : _s(r, 'designation')} · '),
                      branch.isEmpty
                          ? const TextSpan(
                              text: 'Branch unset',
                              style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w600),
                            )
                          : TextSpan(text: branch),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          children: [
            const Divider(height: 1),
            const SizedBox(height: 8),
            _kv('Phone', _s(r, 'phoneNumber')),
            _kv('Alt Phone', _s(r, 'alternatePhoneNumber')),
            _kv('Department', _s(r, 'department')),
            _kv('Job Role', _s(r, 'jobRole')),
            _kv('Staff Type', _s(r, 'employmentType')),
            _kv('Branch', branch, valueColor: branch.isEmpty ? AppColors.error : null),
            _kv('Joining Date', _s(r, 'joiningDate')),
            _kv('Manager', _s(r, 'reportingManager')),
            _kv('Gender', _s(r, 'gender')),
            _kv('DOB', _s(r, 'dateOfBirth')),
            _kv('Marital', _s(r, 'maritalStatus')),
            _kv('Blood Group', _s(r, 'bloodGroup')),
            _kv('Address', (addr['address'] ?? '').toString()),
            _kv('State', (addr['state'] ?? '').toString()),
            _kv('Pincode', (addr['pincode'] ?? '').toString()),
            _kv('Country', (addr['country'] ?? '').toString()),
            _kv('Bank', _s(r, 'bankName')),
            _kv('Acc No', _s(r, 'accountNumber')),
            _kv('IFSC', _s(r, 'ifscCode')),
            _kv('Acc Holder', _s(r, 'accountHolderName')),
            _kv('UPI', _s(r, 'upiId')),
            _kv('UAN', _s(r, 'uanNumber')),
            _kv('PAN', _s(r, 'panNumber')),
            _kv('Aadhaar', _s(r, 'aadhaarNumber')),
            _kv('PF No', _s(r, 'pfNumber')),
            _kv('ESI No', _s(r, 'esiNumber')),
            const Divider(height: 16),
            ..._templateFields.map((f) => _kv('${f[1]} Tmpl', tmpl(f[0]))),
          ],
        ),
      ),
    );
  }

  Widget _buildSaveBar() {
    final hasErrors = _validationErrors.isNotEmpty;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: _cardBorder)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  hasErrors ? Icons.error_outline_rounded : Icons.info_outline_rounded,
                  size: 16,
                  color: hasErrors ? AppColors.error : AppColors.textSecondary,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    hasErrors
                        ? 'Resolve ${_validationErrors.length} validation error${_validationErrors.length > 1 ? 's' : ''} before saving.'
                        : 'Saves all ${_rows.length} parsed record${_rows.length == 1 ? '' : 's'} to staff.',
                    style: AppTextStyles.caption.copyWith(color: hasErrors ? AppColors.error : AppColors.textSecondary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: (_isImporting || hasErrors) ? null : _save,
                icon: _isImporting
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryText),
                      )
                    : const Icon(Icons.check_circle_outline_rounded, size: 20),
                label: Text(_isImporting ? 'Saving...' : 'Save ${_rows.length} staff'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _resultTile(String label, String value, {bool errored = false, Color? accent}) {
    final tint = errored ? AppColors.error : (accent ?? AppColors.textPrimary);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: errored ? AppColors.errorBg.withValues(alpha: 0.6) : AppColors.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: errored ? AppColors.error.withValues(alpha: 0.25) : _cardBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w500, color: AppColors.textSecondary)),
            const SizedBox(height: 4),
            Text(
              value,
              style: AppTextStyles.headingLarge.copyWith(color: tint),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultCard() {
    final r = _importResult!;
    int n(String k) => (r[k] as num?)?.toInt() ?? 0;
    final seats = r['seatsRemaining'];
    final failures = _maps(r['failures']);
    final warnings = _maps(r['warnings']);
    String line(Map<String, dynamic> f) {
      final emp = (f['employeeId'] ?? '').toString();
      return 'Row ${f['row']}${emp.isNotEmpty ? ' ($emp)' : ''}: ${f['reason'] ?? ''}';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitle(Icons.check_circle_outline_rounded, 'Import Result', color: AppColors.success),
          const SizedBox(height: 16),
          Row(
            children: [
              _resultTile('Total rows', '${n('totalRows')}'),
              const SizedBox(width: 8),
              _resultTile('Imported', '${n('imported')}', accent: AppColors.success),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _resultTile('Failed', '${n('failed')}', errored: n('failed') > 0),
              const SizedBox(width: 8),
              _resultTile('Seats left', seats == null ? 'Unlimited' : '$seats'),
            ],
          ),
          if (failures.isNotEmpty || warnings.isNotEmpty) ...[
            const SizedBox(height: 12),
            ...failures.map((f) => _note(line(f), danger: true)),
            ...warnings.map((w) => _note(line(w))),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
      decoration: _cardDecoration,
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.description_outlined, size: 28, color: AppColors.primaryText),
          ),
          const SizedBox(height: 12),
          const Text(
            'No spreadsheet uploaded yet',
            textAlign: TextAlign.center,
            style: AppTextStyles.headingSmall,
          ),
          const SizedBox(height: 4),
          const Text(
            'Upload a .xlsx, .xls or .csv file above to preview imported staff data and configure templates.',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodySmall,
          ),
        ],
      ),
    );
  }
}
