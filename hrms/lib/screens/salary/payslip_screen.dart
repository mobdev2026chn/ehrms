// Mobile payslip: native, phone-sized view of a paid payslip (HRMSbackend
// GET /staff/payslip/:payrollId) with the black EktaHR logo, plus Download PDF
// and Share (same layout as an A4 PDF).

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../services/payslip_service.dart';
import 'all_payslips_screen.dart' show openPayslipStatementPdf;
import '../../utils/error_message_utils.dart';
import '../../utils/snackbar_utils.dart';

class PayslipScreen extends StatefulWidget {
  const PayslipScreen({super.key, required this.payrollId, this.period});

  final String payrollId;
  final String? period;

  @override
  State<PayslipScreen> createState() => _PayslipScreenState();
}

class _PayslipScreenState extends State<PayslipScreen> {
  final _service = PayslipService();
  Payslip? _p;
  String? _error;
  bool _busy = false;

  static const _ink = Color(0xFF0F172A);
  static const _muted = Color(0xFF64748B);
  static const _line = Color(0xFFE2E8F0);
  static const _accent = Color(0xFFF4AB1F);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final p = await _service.getPayslip(widget.payrollId);
      if (mounted) setState(() => _p = p);
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if ((code == 404 || code == 405) && mounted) {
        // Backend without the mobile payslip API yet: open the server's A4
        // payslip PDF instead, so the payslip always opens.
        final nav = Navigator.of(context);
        final ctx = nav.context;
        nav.pop();
        if (!ctx.mounted) return;
        await openPayslipStatementPdf(ctx, widget.payrollId, period: widget.period);
        return;
      }
      if (mounted) setState(() => _error = ErrorMessageUtils.toUserFriendlyMessage(e));
    } catch (e) {
      if (mounted) setState(() => _error = ErrorMessageUtils.toUserFriendlyMessage(e));
    }
  }

  Future<File> _writePdf() async {
    final p = _p!;
    final bytes = await _service.buildPdf(p);
    final dir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
    final folder = Directory('${dir.path}/Payslips');
    if (!await folder.exists()) await folder.create(recursive: true);
    final safe = '${p.emp('employeeId')}_${p.month}'.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
    final file = File('${folder.path}/Payslip_$safe.pdf');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  Future<void> _download() async {
    if (_p == null || _busy) return;
    setState(() => _busy = true);
    try {
      final file = await _writePdf();
      if (!mounted) return;
      SnackBarUtils.showSnackBar(context, 'Payslip saved');
      await OpenFilex.open(file.path);
    } catch (_) {
      if (mounted) SnackBarUtils.showSnackBar(context, 'Could not create the payslip PDF.', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share() async {
    if (_p == null || _busy) return;
    setState(() => _busy = true);
    try {
      final file = await _writePdf();
      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path, mimeType: 'application/pdf')],
        subject: 'Payslip - ${_p!.month}',
      ));
    } catch (_) {
      if (mounted) SnackBarUtils.showSnackBar(context, 'Could not share the payslip.', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _p;
    return Scaffold(
      backgroundColor: const Color(0xFFE2E8F0),
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        foregroundColor: _ink,
        title: Text(
          p != null ? 'Payslip · ${p.month}' : (widget.period?.isNotEmpty == true ? 'Payslip · ${widget.period}' : 'Payslip'),
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
        ),
        actions: [
          if (p != null)
            IconButton(onPressed: _busy ? null : _share, icon: const Icon(Icons.share_rounded), tooltip: 'Share'),
        ],
      ),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.receipt_long_outlined, size: 40, color: _muted),
                  const SizedBox(height: 10),
                  Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: _muted)),
                  const SizedBox(height: 10),
                  OutlinedButton(onPressed: _load, child: const Text('Retry')),
                ]),
              ),
            )
          : p == null
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2.5))
              : InteractiveViewer(
                  // Pinch to zoom the sheet like a document.
                  maxScale: 3,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(10, 14, 10, 24),
                    children: [_sheet(p)],
                  ),
                ),
      bottomNavigationBar: p == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
                child: ElevatedButton.icon(
                  onPressed: _busy ? null : _download,
                  icon: _busy
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.download_rounded),
                  label: const Text('Download PDF', style: TextStyle(fontWeight: FontWeight.w800)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _ink,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ),
    );
  }

  // ── The paper sheet (same layout as the PDF) ──────────────────────────────

  static const _cellPad = EdgeInsets.symmetric(horizontal: 7, vertical: 6);
  static const _head = Color(0xFFF8FAFC);

  Widget _sheet(Payslip p) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
        boxShadow: const [BoxShadow(color: Color(0x26000000), blurRadius: 12, offset: Offset(0, 4))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Company + logo
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.companyName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: _ink)),
              if (p.companyAddress.isNotEmpty)
                Text(p.companyAddress, style: const TextStyle(fontSize: 10, color: _muted, height: 1.35)),
            ]),
          ),
          const SizedBox(width: 8),
          Image.asset('assets/images/ektahr_logo_black.png', height: 26),
        ]),
        const SizedBox(height: 10),
        Container(height: 2, color: _accent),
        const SizedBox(height: 10),
        // Title
        Center(
          child: Text('PAYSLIP FOR ${p.month.toUpperCase()}',
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900, color: _ink, letterSpacing: 0.6)),
        ),
        if (p.duration.isNotEmpty)
          Center(child: Text(p.duration, style: const TextStyle(fontSize: 10, color: _muted))),
        const SizedBox(height: 10),
        // Employee details: 2 label/value pairs per row
        _grid([
          ('Employee Name', p.emp('name')),
          ('Employee ID', p.emp('employeeId')),
          ('Designation', p.emp('designation')),
          ('Department', p.emp('department')),
          ('Date of Joining', p.empDate('dateOfJoining')),
          ('Work Location', p.emp('workLocation')),
          ('Bank', p.emp('bankName')),
          ('Account No.', p.emp('bankAccountNo')),
          ('PAN', p.emp('panNumber')),
          ('UAN', p.emp('uanNumber')),
        ]),
        const SizedBox(height: 10),
        // Attendance strip
        _attendanceStrip(p),
        const SizedBox(height: 10),
        // Earnings | Deductions
        _earningsDeductions(p),
        const SizedBox(height: 10),
        // Net pay
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: _ink, borderRadius: BorderRadius.circular(3)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              const Text('NET PAY', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: _accent, letterSpacing: 0.6)),
              const Spacer(),
              Text(formatInr(p.netPay), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.white)),
            ]),
            const SizedBox(height: 3),
            Text(rupeesInWords(p.netPay), style: const TextStyle(fontSize: 9.5, color: Color(0xFFCBD5E1))),
          ]),
        ),
        const SizedBox(height: 14),
        const Divider(height: 1, color: _line),
        const SizedBox(height: 6),
        Row(children: [
          const Expanded(
            child: Text('System-generated payslip; no signature required.',
                style: TextStyle(fontSize: 9, color: _muted)),
          ),
          const Text('Generated with ', style: TextStyle(fontSize: 9, color: _muted)),
          Image.asset('assets/images/ektahr_logo_black.png', height: 10),
        ]),
      ]),
    );
  }

  Widget _cell(String text, {bool bold = false, bool right = false, Color? color, double size = 10.5, Color? bg}) => Container(
        color: bg,
        padding: _cellPad,
        child: Text(
          text,
          textAlign: right ? TextAlign.right : TextAlign.left,
          style: TextStyle(fontSize: size, fontWeight: bold ? FontWeight.w800 : FontWeight.w500, color: color ?? _ink),
        ),
      );

  /// Label/value pairs, two per row, in a bordered table.
  Widget _grid(List<(String, String)> items) {
    final rows = <TableRow>[];
    for (var i = 0; i < items.length; i += 2) {
      final a = items[i];
      final b = i + 1 < items.length ? items[i + 1] : ('', '');
      rows.add(TableRow(children: [
        _cell(a.$1, color: _muted, size: 9.5, bg: _head),
        _cell(a.$2.isEmpty ? '-' : a.$2, bold: true, size: 10),
        _cell(b.$1, color: _muted, size: 9.5, bg: _head),
        _cell(b.$1.isEmpty ? '' : (b.$2.isEmpty ? '-' : b.$2), bold: true, size: 10),
      ]));
    }
    return Table(
      border: TableBorder.all(color: _line, width: 0.8),
      columnWidths: const {0: FlexColumnWidth(1.1), 1: FlexColumnWidth(1.4), 2: FlexColumnWidth(1.1), 3: FlexColumnWidth(1.4)},
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: rows,
    );
  }

  Widget _attendanceStrip(Payslip p) {
    final items = [
      ('Payable', p.att('payableDays')),
      ('Working', p.att('workingDays')),
      ('Present', p.att('presentDays')),
      ('Absent', p.att('absentDays')),
      ('Half Day', p.att('halfDays')),
      ('Leaves', p.att('leaves')),
      ('Holidays', p.att('holidays')),
      ('Week Off', p.att('weekOffs')),
    ];
    TableRow row(List<(String, String)> part) => TableRow(children: [
          for (final (k, v) in part)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(children: [
                Text(v.isEmpty ? '0' : v, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900, color: _ink)),
                Text(k, style: const TextStyle(fontSize: 8.5, color: _muted)),
              ]),
            ),
        ]);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        color: _head,
        padding: _cellPad,
        child: const Text('ATTENDANCE', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900, color: _ink, letterSpacing: 0.5)),
      ),
      Table(
        border: TableBorder.all(color: _line, width: 0.8),
        children: [row(items.sublist(0, 4)), row(items.sublist(4))],
      ),
      Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          'Worked ${p.att('hoursWorked')}  ·  OT ${p.att('otHours')}  ·  Fine hours ${p.att('fineHours')}',
          style: const TextStyle(fontSize: 9, color: _muted),
        ),
      ),
    ]);
  }

  Widget _earningsDeductions(Payslip p) {
    String n(double v) => formatInr(v).replaceFirst('₹ ', '');
    final e = p.earnings, d = p.deductions;
    final rows = e.length > d.length ? e.length : d.length;
    return Table(
      border: TableBorder.all(color: _line, width: 0.8),
      columnWidths: const {0: FlexColumnWidth(1.6), 1: FlexColumnWidth(1.1), 2: FlexColumnWidth(1.6), 3: FlexColumnWidth(1.1)},
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        TableRow(decoration: const BoxDecoration(color: _head), children: [
          _cell('EARNINGS', bold: true, size: 9.5),
          _cell('AMOUNT', bold: true, right: true, size: 9.5),
          _cell('DEDUCTIONS', bold: true, size: 9.5),
          _cell('AMOUNT', bold: true, right: true, size: 9.5),
        ]),
        for (var i = 0; i < rows; i++)
          TableRow(children: [
            _cell(i < e.length ? e[i].label : '', size: 10),
            _cell(i < e.length ? n(e[i].amount) : '', right: true, size: 10),
            _cell(i < d.length ? d[i].label : '', size: 10),
            _cell(i < d.length ? n(d[i].amount) : '', right: true, size: 10),
          ]),
        TableRow(decoration: const BoxDecoration(color: _head), children: [
          _cell('Total Earnings', bold: true, size: 10),
          _cell(n(p.totalEarnings), bold: true, right: true, size: 10, color: const Color(0xFF047857)),
          _cell('Total Deductions', bold: true, size: 10),
          _cell(n(p.totalDeductions), bold: true, right: true, size: 10, color: const Color(0xFFB91C1C)),
        ]),
      ],
    );
  }
}
