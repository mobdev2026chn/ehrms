// The Incentive Management dialogs: edit, reject, approve (pick a payroll run), manage
// eligibility, and import from a spreadsheet. Each resolves true when it changed something.

import 'dart:convert';
import 'dart:io';

import 'package:excel/excel.dart' hide Border;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../../../config/app_colors.dart';
import '../../../services/admin_salary_service.dart';
import '../../../utils/snackbar_utils.dart';
import 'admin_salary_ui.dart';

ShapeBorder get _sheetShape => const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24)));

String _numText(dynamic v) {
  if (v == null) return '';
  final d = AdminUi.toDouble(v);
  return d == d.roundToDouble() ? d.toInt().toString() : d.toString();
}

Widget _sheetTitle(String title, String? subtitle) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Center(
        child: Container(
          width: 40,
          height: 4,
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(color: const Color(0xFFE2E5EA), borderRadius: BorderRadius.circular(999)),
        ),
      ),
      Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 18, color: AdminUi.ink)),
      if (subtitle != null) ...[
        const SizedBox(height: 4),
        Text(subtitle, style: const TextStyle(fontSize: 13, color: AdminUi.muted)),
      ],
    ]);

Widget _busyLabel(bool busy, String label) => busy
    ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onPrimary))
    : Text(label);

/// Writes [rows] to an .xlsx in the temp folder and opens it with the device's viewer.
Future<String> writeAndOpenXlsx(String fileName, List<List<String>> rows) async {
  final excel = Excel.createExcel();
  final sheetName = excel.getDefaultSheet() ?? 'Sheet1';
  excel.rename(sheetName, 'Incentives');
  final sheet = excel['Incentives'];
  for (final row in rows) {
    sheet.appendRow(row.map<CellValue?>((c) => TextCellValue(c)).toList());
  }
  final bytes = excel.encode();
  if (bytes == null || bytes.isEmpty) throw Exception('Could not build the spreadsheet.');
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$fileName');
  await file.writeAsBytes(bytes, flush: true);
  final result = await OpenFilex.open(file.path);
  if (result.type != ResultType.done) {
    throw Exception('Saved to ${file.path}, but no app could open it (${result.message}).');
  }
  return file.path;
}

// ── Edit ────────────────────────────────────────────────────────────────

Future<bool> showIncentiveEditSheet(BuildContext context, Map<String, dynamic> row) async {
  final r = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: _sheetShape,
    builder: (_) => _EditSheet(row: row),
  );
  return r == true;
}

class _EditSheet extends StatefulWidget {
  final Map<String, dynamic> row;
  const _EditSheet({required this.row});
  @override
  State<_EditSheet> createState() => _EditSheetState();
}

class _EditSheetState extends State<_EditSheet> {
  late final _target = TextEditingController(text: _numText(widget.row['target']));
  late final _achieved = TextEditingController(text: _numText(widget.row['achieved']));
  late final _amount = TextEditingController(text: _numText(widget.row['incentiveAmount']));
  bool _saving = false;

  @override
  void dispose() {
    _target.dispose();
    _achieved.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final t = double.tryParse(_target.text.trim());
    final a = double.tryParse(_achieved.text.trim());
    final m = double.tryParse(_amount.text.trim());
    if (t == null || a == null || m == null) {
      SnackBarUtils.showSnackBar(context, 'Target, Achieved and Incentive Amount are all required.', isError: true);
      return;
    }
    setState(() => _saving = true);
    final r = await AdminSalaryService.instance.updateIncentive(widget.row['id'].toString(), t, a, m);
    if (!mounted) return;
    setState(() => _saving = false);
    if (r['success'] == true) {
      SnackBarUtils.showSnackBar(context, r['message']?.toString() ?? 'Incentive updated.');
      Navigator.pop(context, true);
    } else {
      SnackBarUtils.showSnackBar(context, r['message']?.toString() ?? 'Could not update the incentive.', isError: true);
    }
  }

  Widget _field(TextEditingController c, String label, {String? prefix}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: c,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
          decoration: AdminUi.input(label, prefix: prefix),
        ),
      );

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _sheetTitle('Edit incentive', '${widget.row['name'] ?? ''} • ${widget.row['employeeId'] ?? ''}'),
              if (widget.row['status'] == 'Rejected')
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text('Saving puts this rejected incentive back to Pending for approval.',
                      style: TextStyle(fontSize: 12, color: AdminUi.amber)),
                ),
              const SizedBox(height: 20),
              _field(_target, 'Target'),
              _field(_achieved, 'Achieved'),
              _field(_amount, 'Incentive Amount', prefix: '₹ '),
              ElevatedButton(
                  style: AdminUi.primaryButton(), onPressed: _saving ? null : _save, child: _busyLabel(_saving, 'Save')),
            ]),
          ),
        ),
      );
}

// ── Reject ──────────────────────────────────────────────────────────────

Future<bool> showIncentiveRejectSheet(BuildContext context, Map<String, dynamic> row) async {
  final r = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: _sheetShape,
    builder: (_) => _RejectSheet(row: row),
  );
  return r == true;
}

class _RejectSheet extends StatefulWidget {
  final Map<String, dynamic> row;
  const _RejectSheet({required this.row});
  @override
  State<_RejectSheet> createState() => _RejectSheetState();
}

class _RejectSheetState extends State<_RejectSheet> {
  final _reason = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _reject() async {
    if (_reason.text.trim().isEmpty) {
      SnackBarUtils.showSnackBar(context, 'A rejection reason is required.', isError: true);
      return;
    }
    setState(() => _saving = true);
    final r = await AdminSalaryService.instance.rejectIncentive(widget.row['id'].toString(), _reason.text.trim());
    if (!mounted) return;
    setState(() => _saving = false);
    if (r['success'] == true) {
      SnackBarUtils.showSnackBar(context, r['message']?.toString() ?? 'Incentive rejected.');
      Navigator.pop(context, true);
    } else {
      SnackBarUtils.showSnackBar(context, r['message']?.toString() ?? 'Could not reject the incentive.', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _sheetTitle('Reject incentive', '${widget.row['name'] ?? ''} • ${AdminUi.money(AdminUi.toDouble(widget.row['incentiveAmount']))}'),
              const SizedBox(height: 20),
              TextField(
                controller: _reason,
                maxLines: 3,
                maxLength: 500,
                decoration: AdminUi.input('Reason', hint: 'Why is this incentive being rejected?'),
              ),
              const SizedBox(height: 6),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AdminUi.red, foregroundColor: Colors.white),
                onPressed: _saving ? null : _reject,
                child: _busyLabel(_saving, 'Reject'),
              ),
            ]),
          ),
        ),
      );
}

// ── Approve into a chosen payroll run ───────────────────────────────────

Future<bool> showIncentiveApproveSheet(BuildContext context, Map<String, dynamic> row) async {
  final r = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: _sheetShape,
    builder: (_) => _ApproveSheet(row: row),
  );
  return r == true;
}

class _ApproveSheet extends StatefulWidget {
  final Map<String, dynamic> row;
  const _ApproveSheet({required this.row});
  @override
  State<_ApproveSheet> createState() => _ApproveSheetState();
}

class _ApproveSheetState extends State<_ApproveSheet> {
  bool _loading = true;
  String? _error;
  List<String> _months = [];
  String _picked = '';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final r = await AdminSalaryService.instance.getIncentivePayrollMonths(widget.row['id'].toString());
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r['success'] == true) {
        _months = List<String>.from(r['data'] as List);
        if (_months.isNotEmpty) _picked = _months.first;
      } else {
        _error = r['message']?.toString() ?? 'Could not load the open payroll runs.';
      }
    });
  }

  Future<void> _approve() async {
    if (_picked.isEmpty) return;
    setState(() => _saving = true);
    final r = await AdminSalaryService.instance.approveIncentive(widget.row['id'].toString(), payrollMonth: _picked);
    if (!mounted) return;
    setState(() => _saving = false);
    if (r['success'] == true) {
      SnackBarUtils.showSnackBar(context, r['message']?.toString() ?? 'Incentive approved.');
      Navigator.pop(context, true);
    } else {
      SnackBarUtils.showSnackBar(context, r['message']?.toString() ?? 'Could not approve the incentive.', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final earned = (widget.row['month'] ?? '').toString();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _sheetTitle('Approve incentive',
              '${widget.row['name'] ?? ''} • ${AdminUi.money(AdminUi.toDouble(widget.row['incentiveAmount']))}'),
          const SizedBox(height: 8),
          const Text('This incentive’s own payroll run can no longer take it. Choose which payroll run should pay it.',
              style: TextStyle(fontSize: 12.5, color: AdminUi.muted)),
          const SizedBox(height: 12),
          if (_loading)
            const Padding(padding: EdgeInsets.all(20), child: AdminLoading())
          else if (_error != null)
            AdminErrorView(message: _error!, onRetry: _load)
          else if (_months.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('No payroll run is open to pay this incentive into.',
                  style: TextStyle(color: AdminUi.red, fontWeight: FontWeight.w600)),
            )
          else ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _months
                  .map((m) => ChoiceChip(
                        label: Text(m),
                        selected: _picked == m,
                        showCheckmark: false,
                        selectedColor: AdminUi.accent,
                        backgroundColor: AdminUi.greyBg,
                        side: BorderSide.none,
                        onSelected: (_) => setState(() => _picked = m),
                      ))
                  .toList(),
            ),
            if (_picked.isNotEmpty && _picked != earned) ...[
              const SizedBox(height: 10),
              Text('It will be paid on the $_picked payslip.', style: const TextStyle(fontSize: 12, color: AdminUi.muted)),
            ],
            const SizedBox(height: 20),
            ElevatedButton(
                style: AdminUi.primaryButton(),
                onPressed: _saving || _picked.isEmpty ? null : _approve,
                child: _busyLabel(_saving, 'Approve')),
          ],
        ]),
      ),
    );
  }
}

// ── Manage eligibility ──────────────────────────────────────────────────

Future<bool> showIncentiveEligibilitySheet(BuildContext context, String month) async {
  final r = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: _sheetShape,
    builder: (_) => _EligibilitySheet(month: month),
  );
  return r == true;
}

class _EligibilitySheet extends StatefulWidget {
  final String month;
  const _EligibilitySheet({required this.month});
  @override
  State<_EligibilitySheet> createState() => _EligibilitySheetState();
}

class _EligibilitySheetState extends State<_EligibilitySheet> {
  final _search = TextEditingController();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = [];
  final Set<String> _busy = {};
  bool _changed = false;

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

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final r = await AdminSalaryService.instance.getIncentiveEligibility(widget.month);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r['success'] == true) {
        final rows = (r['data'] as Map)['rows'];
        _rows = rows is List ? rows.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : [];
      } else {
        _error = r['message']?.toString() ?? 'Could not load eligibility.';
      }
    });
  }

  Future<void> _toggle(Map<String, dynamic> row, bool eligible) async {
    final id = row['staffId'].toString();
    setState(() => _busy.add(id));
    final r = await AdminSalaryService.instance.updateIncentiveEligibility(id, eligible, widget.month);
    if (!mounted) return;
    setState(() {
      _busy.remove(id);
      if (r['success'] == true) {
        row['eligible'] = eligible;
        _changed = true;
      }
    });
    if (r['success'] != true) {
      SnackBarUtils.showSnackBar(context, r['message']?.toString() ?? 'Could not update eligibility.', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _search.text.trim().toLowerCase();
    final rows = q.isEmpty
        ? _rows
        : _rows
            .where((r) =>
                (r['name'] ?? '').toString().toLowerCase().contains(q) ||
                (r['employeeId'] ?? '').toString().toLowerCase().contains(q) ||
                (r['department'] ?? '').toString().toLowerCase().contains(q))
            .toList();
    final eligibleCount = _rows.where((r) => r['eligible'] == true).length;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _changed);
      },
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        builder: (ctx, controller) => Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 8, 8),
            child: Row(children: [
              Expanded(
                  child: _sheetTitle('Manage eligibility',
                      _loading ? widget.month : '$eligibleCount of ${_rows.length} eligible • ${widget.month}')),
              IconButton(tooltip: 'Close', onPressed: () => Navigator.pop(context, _changed), icon: const Icon(Icons.close_rounded)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: AdminSearchField(controller: _search, hint: 'Search staff', onChanged: (_) => setState(() {})),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _loading
                ? const AdminLoading()
                : _error != null
                    ? AdminErrorView(message: _error!, onRetry: _load)
                    : rows.isEmpty
                        ? const AdminEmptyView(icon: Icons.people_outline_rounded, title: 'No staff found')
                        : ListView.separated(
                            controller: controller,
                            padding: const EdgeInsets.fromLTRB(10, 0, 10, 24),
                            itemCount: rows.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (_, i) {
                              final r = rows[i];
                              final eligible = r['eligible'] == true;
                              final blocked = !eligible && r['payrollGenerated'] == true;
                              final busy = _busy.contains(r['staffId'].toString());
                              return ListTile(
                                title: Text((r['name'] ?? '').toString(),
                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AdminUi.ink)),
                                subtitle: Text(
                                  blocked
                                      ? 'Payroll for ${widget.month} already generated'
                                      : [r['employeeId'], r['department'], r['branch']]
                                          .where((v) => v != null && v.toString().isNotEmpty)
                                          .join(' • '),
                                  style: TextStyle(fontSize: 11.5, color: blocked ? AdminUi.amber : AdminUi.muted),
                                ),
                                trailing: busy
                                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                                    : Switch(
                                        value: eligible,
                                        onChanged: blocked ? null : (v) => _toggle(r, v),
                                      ),
                              );
                            },
                          ),
          ),
        ]),
      ),
    );
  }
}

// ── Import ──────────────────────────────────────────────────────────────

const _templateHeaders = ['Employee ID', 'Employee Name', 'Department', 'Branch', 'Target', 'Achieved', 'Incentive Amount'];

String _headerKey(dynamic v) => (v ?? '').toString().toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

dynamic _cellValue(Data? d) {
  final v = d?.value;
  if (v == null) return null;
  if (v is IntCellValue) return v.value;
  if (v is DoubleCellValue) return v.value;
  return v.toString();
}

/// Rows of a picked .xlsx or .csv, header first.
List<List<dynamic>> _readGrid(String path, List<int> bytes) {
  if (path.toLowerCase().endsWith('.csv')) {
    final text = utf8.decode(bytes, allowMalformed: true);
    return const LineSplitter()
        .convert(text)
        .where((l) => l.trim().isNotEmpty)
        .map((l) => _splitCsvLine(l).map<dynamic>((c) => c).toList())
        .toList();
  }
  final excel = Excel.decodeBytes(bytes);
  if (excel.tables.isEmpty) return [];
  final sheet = excel.tables.values.first;
  return sheet.rows.map((r) => r.map(_cellValue).toList()).where((r) => r.any((c) => c != null && c.toString().trim().isNotEmpty)).toList();
}

List<String> _splitCsvLine(String line) {
  final out = <String>[];
  final buf = StringBuffer();
  var quoted = false;
  for (var i = 0; i < line.length; i++) {
    final ch = line[i];
    if (ch == '"') {
      if (quoted && i + 1 < line.length && line[i + 1] == '"') {
        buf.write('"');
        i++;
      } else {
        quoted = !quoted;
      }
    } else if (ch == ',' && !quoted) {
      out.add(buf.toString());
      buf.clear();
    } else {
      buf.write(ch);
    }
  }
  out.add(buf.toString());
  return out;
}

Future<bool> showIncentiveImportSheet(BuildContext context, String month) async {
  final r = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: _sheetShape,
    builder: (_) => _ImportSheet(month: month),
  );
  return r == true;
}

class _ImportSheet extends StatefulWidget {
  final String month;
  const _ImportSheet({required this.month});
  @override
  State<_ImportSheet> createState() => _ImportSheetState();
}

class _ImportSheetState extends State<_ImportSheet> {
  late DateTime _month;
  bool _downloading = false;
  bool _uploading = false;
  String _fileName = '';
  int? _imported;
  List<Map<String, dynamic>> _failures = [];
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _month = AdminUi.parseMonthLabel(widget.month) ?? DateTime(DateTime.now().year, DateTime.now().month, 1);
  }

  String get _label => AdminUi.monthLabel(_month);

  Future<void> _downloadTemplate() async {
    setState(() => _downloading = true);
    final r = await AdminSalaryService.instance.getIncentiveTemplate(_label);
    if (!mounted) return;
    if (r['success'] != true) {
      setState(() => _downloading = false);
      SnackBarUtils.showSnackBar(context, r['message']?.toString() ?? 'Could not generate the sample file.', isError: true);
      return;
    }
    final rowsRaw = (r['data'] as Map)['rows'];
    final rows = rowsRaw is List ? rowsRaw.whereType<Map>().toList() : <Map>[];
    if (rows.isEmpty) {
      setState(() => _downloading = false);
      SnackBarUtils.showSnackBar(
          context, 'No incentive eligible employees for this month. Enable eligibility first under Manage Eligibility.',
          isError: true);
      return;
    }
    try {
      await writeAndOpenXlsx('incentive_template_${_label.replaceAll(' ', '_')}.xlsx', [
        _templateHeaders,
        ...rows.map((e) => [
              (e['employeeId'] ?? '').toString(),
              (e['name'] ?? '').toString(),
              (e['department'] ?? '').toString(),
              (e['branch'] ?? '').toString(),
              '',
              '',
              '',
            ]),
      ]);
      if (mounted) SnackBarUtils.showSnackBar(context, 'Sample file ready with ${rows.length} eligible employee(s).');
    } catch (e) {
      if (mounted) SnackBarUtils.showSnackBar(context, e.toString().replaceFirst('Exception: ', ''), isError: true);
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<void> _pickAndImport() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'csv'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty || !mounted) return;
    final f = picked.files.single;
    setState(() {
      _uploading = true;
      _fileName = f.name;
      _failures = [];
      _imported = null;
    });
    List<Map<String, dynamic>> rows;
    try {
      final bytes = f.bytes ?? (f.path != null ? await File(f.path!).readAsBytes() : null);
      if (bytes == null) throw Exception('The file could not be read.');
      final grid = _readGrid(f.name, bytes);
      if (grid.length < 2) throw Exception('The file has no data rows beneath its header.');
      final header = grid.first.map(_headerKey).toList();
      int col(String label) => header.indexOf(_headerKey(label));
      final idCol = col('Employee ID'), tCol = col('Target'), aCol = col('Achieved'), mCol = col('Incentive Amount');
      if ([idCol, tCol, aCol, mCol].contains(-1)) {
        throw Exception('The file is missing required columns. Download the sample file and fill that in instead.');
      }
      dynamic at(List<dynamic> r, int i) => i < r.length ? r[i] : null;
      rows = grid
          .skip(1)
          .where((r) => (at(r, idCol) ?? '').toString().trim().isNotEmpty)
          .map((r) => {
                'employeeId': at(r, idCol).toString().trim(),
                'target': at(r, tCol),
                'achieved': at(r, aCol),
                'incentiveAmount': at(r, mCol),
              })
          .toList();
      if (rows.isEmpty) throw Exception('No rows with an Employee ID were found in the file.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploading = false);
      SnackBarUtils.showSnackBar(context, e.toString().replaceFirst('Exception: ', ''), isError: true);
      return;
    }

    final r = await AdminSalaryService.instance.importIncentives(_label, rows);
    if (!mounted) return;
    setState(() {
      _uploading = false;
      final data = r['data'] is Map ? Map<String, dynamic>.from(r['data'] as Map) : <String, dynamic>{};
      final failures = data['failures'];
      _failures = failures is List ? failures.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : [];
      if (r['success'] == true) {
        _imported = (data['imported'] as num?)?.toInt() ?? 0;
        _changed = true;
      }
    });
    SnackBarUtils.showSnackBar(
      context,
      r['message']?.toString() ?? (r['success'] == true ? 'Incentives imported.' : 'The file could not be imported.'),
      isError: r['success'] != true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final busy = _downloading || _uploading;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !busy) Navigator.pop(context, _changed);
      },
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: _sheetTitle('Import incentives', 'Upload Target, Achieved and Incentive Amount per employee.')),
              IconButton(
                  tooltip: 'Close',
                  onPressed: busy ? null : () => Navigator.pop(context, _changed),
                  icon: const Icon(Icons.close_rounded)),
            ]),
            const SizedBox(height: 20),
            const Text('1. Month the sheet is for', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AdminUi.ink)),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: AdminMonthSwitcher(
                month: _month,
                allowFuture: true,
                onChanged: busy
                    ? (_) {}
                    : (m) => setState(() {
                          _month = m;
                          _failures = [];
                          _imported = null;
                          _fileName = '';
                        }),
              ),
            ),
            const SizedBox(height: 20),
            const Text('2. Download the sample file', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AdminUi.ink)),
            const SizedBox(height: 4),
            const Text('It lists the employees eligible for this month. Fill in Target, Achieved and Incentive Amount.',
                style: TextStyle(fontSize: 13, color: AdminUi.muted, height: 1.4)),
            const SizedBox(height: 6),
            OutlinedButton.icon(
              onPressed: busy ? null : _downloadTemplate,
              icon: _downloading
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.download_rounded, size: 18),
              label: const Text('Download sample (.xlsx)'),
            ),
            const SizedBox(height: 20),
            const Text('3. Upload the filled file', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AdminUi.ink)),
            const SizedBox(height: 6),
            ElevatedButton.icon(
              style: AdminUi.primaryButton(),
              onPressed: busy ? null : _pickAndImport,
              icon: _uploading
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.upload_file_rounded, size: 18),
              label: Text(_fileName.isEmpty ? 'Choose .xlsx or .csv' : 'Choose another file'),
            ),
            if (_fileName.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(_fileName, style: const TextStyle(fontSize: 12, color: AdminUi.muted)),
            ],
            if (_imported != null) ...[
              const SizedBox(height: 12),
              Row(children: [
                const Icon(Icons.check_circle_rounded, color: AdminUi.green, size: 18),
                const SizedBox(width: 6),
                Text('$_imported record(s) imported for $_label',
                    style: const TextStyle(color: AdminUi.green, fontWeight: FontWeight.w700)),
              ]),
            ],
            if (_failures.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('${_failures.length} row(s) not imported',
                  style: const TextStyle(color: AdminUi.red, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              ..._failures.map((f) => Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: AdminUi.redBg, borderRadius: BorderRadius.circular(12)),
                    child: Text(
                      '${(f['row'] ?? 0) == 0 ? '' : 'Row ${f['row']} '}'
                      '${(f['employeeId'] ?? '').toString().isEmpty ? '' : '(${f['employeeId']}) '}'
                      '${f['reason'] ?? ''}',
                      style: const TextStyle(fontSize: 12, color: AdminUi.red),
                    ),
                  )),
            ],
          ]),
        ),
      ),
    );
  }
}
