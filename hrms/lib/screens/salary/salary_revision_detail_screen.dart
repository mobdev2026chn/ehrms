import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../../config/app_colors.dart';
import '../../utils/mongo_date_parse.dart';
import '../../utils/salary_ctc_helpers.dart';
import '../../utils/snackbar_utils.dart';

/// Single revision: summary + per-component previous vs revised (annualized from monthly map values).
class SalaryRevisionDetailScreen extends StatefulWidget {
  const SalaryRevisionDetailScreen({
    super.key,
    required this.entry,
    this.employeeName,
    this.employeeId,
  });

  final Map<String, dynamic> entry;

  /// Shown in the exported PDF header (payslip-style). Optional — falls back to
  /// generic text when the caller does not have employee details.
  final String? employeeName;
  final String? employeeId;

  @override
  State<SalaryRevisionDetailScreen> createState() =>
      _SalaryRevisionDetailScreenState();
}

class _SalaryRevisionDetailScreenState
    extends State<SalaryRevisionDetailScreen> {
  bool _exporting = false;

  static const _componentOrder = [
    'basicSalary',
    'dearnessAllowance',
    'houseRentAllowance',
    'specialAllowance',
    'mobileAllowance',
    'medicalInsuranceAmount',
  ];

  static const _labels = {
    'basicSalary': 'BASIC',
    'dearnessAllowance': 'DA',
    'houseRentAllowance': 'HRA',
    'specialAllowance': 'Special Allowance',
    'mobileAllowance': 'Mobile Allowance',
    'medicalInsuranceAmount': 'Medical Insurance',
    'employerPFRate': 'Employer PF %',
    'employerESIRate': 'Employer ESI %',
    'employeePFRate': 'Employee PF %',
    'employeeESIRate': 'Employee ESI %',
  };

  double? _monthly(Map<String, dynamic>? m, String key) {
    if (m == null) return null;
    final v = m[key];
    if (v is! num) return null;
    return v.toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(locale: 'en_IN', symbol: '₹');
    final prevRaw = widget.entry['previousSalary'];
    final revRaw = widget.entry['revisedSalary'];
    final prev = prevRaw is Map ? Map<String, dynamic>.from(prevRaw) : null;
    final rev = revRaw is Map ? Map<String, dynamic>.from(revRaw) : null;

    final prevCtc = yearlyCtcFromSalaryMap(prev);
    final revCtc = yearlyCtcFromSalaryMap(rev);
    final diffCtc = (prevCtc != null && revCtc != null) ? (revCtc - prevCtc) : null;
    final pctCtc = (prevCtc != null && prevCtc > 0 && diffCtc != null)
        ? (diffCtc / prevCtc) * 100
        : null;

    final eff = parseMongoJsonDate(widget.entry['effectiveFrom']);
    final effStr = eff != null ? DateFormat('d MMM, y').format(eff) : '—';
    final payoutStr = eff != null ? DateFormat('MMM yyyy').format(eff) : '—';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Salary Revision History',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        centerTitle: true,
        actions: [
          _exporting
              ? const Padding(
                  padding: EdgeInsets.only(right: 16),
                  child: Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              : IconButton(
                  tooltip: 'Download PDF',
                  onPressed: () => _exportToPdf(
                    prev: prev,
                    rev: rev,
                    currency: currency,
                    prevCtc: prevCtc,
                    revCtc: revCtc,
                    diffCtc: diffCtc,
                    pctCtc: pctCtc,
                    effStr: effStr,
                    payoutStr: payoutStr,
                  ),
                  icon: Icon(Icons.download_outlined, color: AppColors.primary),
                ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SummaryGrid(
            currency: currency,
            prevCtc: prevCtc,
            revCtc: revCtc,
            diff: diffCtc,
            pct: pctCtc,
            effectiveStr: effStr,
            payoutStr: payoutStr,
          ),
          const SizedBox(height: 20),
          const Text(
            'Earnings & components',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 10),
          for (final key in _componentOrder) ...[
            if (_monthly(prev, key) != null || _monthly(rev, key) != null)
              _ComponentCompare(
                title: _labels[key] ?? key,
                currency: currency,
                prevAnnual: _annual(prev, key),
                revAnnual: _annual(rev, key),
              ),
          ],
        ],
      ),
    );
  }

  double? _annual(Map<String, dynamic>? m, String key) {
    final mo = _monthly(m, key);
    if (mo == null) return null;
    return mo * 12;
  }

  /// Build a single-page PDF mirroring the on-screen summary + component table,
  /// save it under the device Downloads folder, then open it (share sheet as fallback).
  Future<void> _exportToPdf({
    required Map<String, dynamic>? prev,
    required Map<String, dynamic>? rev,
    required NumberFormat currency,
    required double? prevCtc,
    required double? revCtc,
    required double? diffCtc,
    required double? pctCtc,
    required String effStr,
    required String payoutStr,
  }) async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      // Embed the bundled Inter font so the ₹ glyph renders (the default PDF
      // Helvetica font has no rupee sign).
      final base = pw.Font.ttf(
        await rootBundle.load('assets/fonts/Inter_18pt-Regular.ttf'),
      );
      final boldFont = pw.Font.ttf(
        await rootBundle.load('assets/fonts/Inter_18pt-SemiBold.ttf'),
      );

      // Brand logo for the payslip-style header (best-effort — skip if missing).
      pw.MemoryImage? logo;
      try {
        final logoData = await rootBundle.load('assets/ekta_logo.jpeg');
        logo = pw.MemoryImage(logoData.buffer.asUint8List());
      } catch (_) {
        logo = null;
      }

      const accent = PdfColor.fromInt(0xFF2E7D32); // green, matches "Approved"
      const grey = PdfColor.fromInt(0xFF6B7280);
      const lightGrey = PdfColor.fromInt(0xFFF3F4F6);

      final doc = pw.Document();

      pw.Widget summaryRow(String label, String value, {PdfColor? valueColor}) {
        return pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 5),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(label,
                  style: const pw.TextStyle(fontSize: 11, color: grey)),
              pw.Text(value,
                  style: pw.TextStyle(
                      fontSize: 11,
                      fontWeight: pw.FontWeight.bold,
                      color: valueColor ?? PdfColors.black)),
            ],
          ),
        );
      }

      pw.Widget cell(String text,
          {bool header = false, PdfColor? color, pw.TextAlign? align}) {
        return pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
          child: pw.Text(
            text,
            textAlign: align ?? (header ? pw.TextAlign.center : pw.TextAlign.right),
            style: pw.TextStyle(
              fontSize: 9.5,
              fontWeight: header ? pw.FontWeight.bold : pw.FontWeight.normal,
              color: color ?? PdfColors.black,
            ),
          ),
        );
      }

      final componentRows = <pw.TableRow>[
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: lightGrey),
          children: [
            cell('Component', header: true, align: pw.TextAlign.left),
            cell('Previous (Annual)', header: true),
            cell('Revised (Annual)', header: true),
            cell('Changed by %', header: true),
            cell('Difference', header: true),
          ],
        ),
      ];
      for (final key in _componentOrder) {
        final pa = _annual(prev, key);
        final ra = _annual(rev, key);
        if (pa == null && ra == null) continue;
        final p = pa ?? 0;
        final r = ra ?? 0;
        final diff = r - p;
        final pct = p != 0 ? (diff / p) * 100 : (diff == 0 ? 0.0 : null);
        final pctColor =
            pct == null ? grey : (pct >= 0 ? accent : PdfColors.red700);
        componentRows.add(
          pw.TableRow(
            children: [
              cell(_labels[key] ?? key, align: pw.TextAlign.left),
              cell(currency.format(p)),
              cell(currency.format(r)),
              cell(pct != null ? '${pct.toStringAsFixed(2)}%' : '—',
                  color: pctColor),
              cell(currency.format(diff)),
            ],
          ),
        );
      }

      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          theme: pw.ThemeData.withFont(base: base, bold: boldFont),
          margin: const pw.EdgeInsets.all(28),
          build: (context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // ---- Payslip-style header ----
              pw.Center(
                child: pw.Column(
                  children: [
                    if (logo != null)
                      pw.Image(logo, height: 46),
                    if (logo != null) pw.SizedBox(height: 6),
                    pw.Text(
                      'EktaHR',
                      style: pw.TextStyle(
                          fontSize: 18, fontWeight: pw.FontWeight.bold),
                    ),
                    pw.SizedBox(height: 8),
                    pw.Text(
                      'SALARY REVISION STATEMENT',
                      style: pw.TextStyle(
                          fontSize: 14,
                          fontWeight: pw.FontWeight.bold,
                          color: accent),
                    ),
                    pw.SizedBox(height: 3),
                    pw.Text(
                      'Effective from $effStr',
                      style: const pw.TextStyle(fontSize: 10, color: grey),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 10),
              if ((widget.employeeName ?? '').trim().isNotEmpty ||
                  (widget.employeeId ?? '').trim().isNotEmpty)
                pw.Container(
                  width: double.infinity,
                  padding: const pw.EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: const pw.BoxDecoration(color: lightGrey),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        'Employee: ${(widget.employeeName ?? '—').trim()}',
                        style: pw.TextStyle(
                            fontSize: 10, fontWeight: pw.FontWeight.bold),
                      ),
                      if ((widget.employeeId ?? '').trim().isNotEmpty)
                        pw.Text(
                          'ID: ${widget.employeeId!.trim()}',
                          style: pw.TextStyle(
                              fontSize: 10, fontWeight: pw.FontWeight.bold),
                        ),
                    ],
                  ),
                ),
              pw.SizedBox(height: 16),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                    horizontal: 14, vertical: 8),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey300),
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Column(
                  children: [
                    summaryRow('Previous CTC',
                        prevCtc != null ? currency.format(prevCtc) : '—'),
                    summaryRow('Revised CTC',
                        revCtc != null ? currency.format(revCtc) : '—'),
                    summaryRow('Difference',
                        diffCtc != null ? currency.format(diffCtc) : '—'),
                    summaryRow(
                      'Change by',
                      pctCtc != null ? '${pctCtc.toStringAsFixed(2)}%' : '—',
                      valueColor: pctCtc == null
                          ? null
                          : (pctCtc >= 0 ? accent : PdfColors.red700),
                    ),
                    summaryRow('Effective From', effStr),
                    summaryRow('Payout Month', payoutStr),
                    summaryRow('Status', 'Approved', valueColor: accent),
                  ],
                ),
              ),
              pw.SizedBox(height: 20),
              pw.Text(
                'Earnings & components',
                style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 8),
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
                columnWidths: const {
                  0: pw.FlexColumnWidth(2.2),
                  1: pw.FlexColumnWidth(2),
                  2: pw.FlexColumnWidth(2),
                  3: pw.FlexColumnWidth(1.6),
                  4: pw.FlexColumnWidth(2),
                },
                children: componentRows,
              ),
              pw.SizedBox(height: 24),
              pw.Divider(color: PdfColors.grey300, thickness: 0.5),
              pw.SizedBox(height: 6),
              pw.Center(
                child: pw.Column(
                  children: [
                    pw.Text(
                      'This is a system generated document. No signature required.',
                      style: const pw.TextStyle(fontSize: 8, color: grey),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      'Generated on: ${DateFormat('d MMM, y').format(DateTime.now())}',
                      style: const pw.TextStyle(fontSize: 8, color: grey),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

      final bytes = await doc.save();
      if (bytes.isEmpty) {
        throw Exception('PDF encode returned empty');
      }

      final downloadsDir = await getDownloadsDirectory();
      final baseDir = downloadsDir ?? await getApplicationDocumentsDirectory();
      final outDir = Directory('${baseDir.path}/SalaryRevisions');
      if (!await outDir.exists()) {
        await outDir.create(recursive: true);
      }
      final safePayout = payoutStr.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
      final stamp = safePayout.isEmpty
          ? '${DateTime.now().millisecondsSinceEpoch}'
          : safePayout;
      final file = File('${outDir.path}/SalaryRevision_$stamp.pdf');
      await file.writeAsBytes(bytes, flush: true);

      if (!mounted) return;
      setState(() => _exporting = false);

      final result = await OpenFilex.open(file.path);
      if (!mounted) return;
      if (result.type != ResultType.done) {
        // No PDF viewer installed — let the user save/share it instead.
        await Share.shareXFiles(
          [XFile(file.path)],
          subject: 'Salary Revision History',
          text: 'Salary Revision History',
        );
      } else {
        SnackBarUtils.showSnackBar(context, 'Downloaded successfully');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _exporting = false);
        SnackBarUtils.showSnackBar(
          context,
          'Could not download: $e',
          isError: true,
        );
      }
    }
  }
}

class _SummaryGrid extends StatelessWidget {
  const _SummaryGrid({
    required this.currency,
    required this.prevCtc,
    required this.revCtc,
    required this.diff,
    required this.pct,
    required this.effectiveStr,
    required this.payoutStr,
  });

  final NumberFormat currency;
  final double? prevCtc;
  final double? revCtc;
  final double? diff;
  final double? pct;
  final String effectiveStr;
  final String payoutStr;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          _row2(
            'Previous CTC',
            prevCtc != null ? currency.format(prevCtc!) : '—',
            'Revised CTC',
            revCtc != null ? currency.format(revCtc!) : '—',
          ),
          const Divider(height: 20),
          _row2(
            'Difference',
            diff != null ? currency.format(diff!) : '—',
            'Change by',
            pct != null ? '${pct!.toStringAsFixed(2)}%' : '—',
            value2Color: pct != null && pct! >= 0 ? AppColors.success : AppColors.error,
            value2ArrowUp: pct != null && pct! > 0,
            value2ArrowDown: pct != null && pct! < 0,
          ),
          const Divider(height: 20),
          _row2(
            'Effective From',
            effectiveStr,
            'Payout Month',
            payoutStr,
          ),
          const Divider(height: 20),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Status',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.success.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Approved',
                  style: TextStyle(
                    color: AppColors.success,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _row2(
    String l1,
    String v1,
    String l2,
    String v2, {
    Color? value2Color,
    bool value2ArrowUp = false,
    bool value2ArrowDown = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _cell(l1, v1)),
        Expanded(child: _cell(l2, v2, color: value2Color, up: value2ArrowUp, down: value2ArrowDown)),
      ],
    );
  }

  Widget _cell(String label, String value, {Color? color, bool up = false, bool down = false}) {
    return Container(
      padding: const EdgeInsets.all(8),
      margin: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              if (up)
                Icon(Icons.arrow_upward, size: 16, color: color ?? AppColors.textPrimary),
              if (down)
                Icon(Icons.arrow_downward, size: 16, color: color ?? AppColors.textPrimary),
              Expanded(
                child: Text(
                  value,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: color ?? AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ComponentCompare extends StatelessWidget {
  const _ComponentCompare({
    required this.title,
    required this.currency,
    required this.prevAnnual,
    required this.revAnnual,
  });

  final String title;
  final NumberFormat currency;
  final double? prevAnnual;
  final double? revAnnual;

  @override
  Widget build(BuildContext context) {
    final p = prevAnnual ?? 0;
    final r = revAnnual ?? 0;
    final diff = r - p;
    final pct = p != 0 ? (diff / p) * 100 : (diff == 0 ? 0.0 : null);

    Color pctColor = AppColors.textPrimary;
    bool up = false;
    bool down = false;
    if (pct != null) {
      if (pct > 0) {
        pctColor = AppColors.success;
        up = true;
      } else if (pct < 0) {
        pctColor = AppColors.error;
        down = true;
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _mini('Previous Amount', currency.format(p)),
              ),
              Expanded(
                child: _mini('Revised Amount', currency.format(r)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _miniPct(
                  'Changed by',
                  pct != null ? '${pct.toStringAsFixed(2)} %' : '—',
                  pctColor,
                  up,
                  down,
                ),
              ),
              Expanded(
                child: _mini('Difference', currency.format(diff)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _mini(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
      ],
    );
  }

  Widget _miniPct(
    String label,
    String value,
    Color color,
    bool up,
    bool down,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
        const SizedBox(height: 2),
        Row(
          children: [
            if (up) Icon(Icons.arrow_upward, size: 14, color: color),
            if (down) Icon(Icons.arrow_downward, size: 14, color: color),
            Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: color,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
