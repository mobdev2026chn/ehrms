// Staff payslip: data from HRMSbackend GET /staff/payslip/:payrollId (own, Paid
// payslips only), rendered natively on the phone and exported as a PDF with the
// black EktaHR logo.

import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'api_client.dart';

class PayslipLine {
  PayslipLine(this.label, this.fixed, this.amount);
  final String label;
  final double fixed; // earnings only
  final double amount; // earned / deducted
}

class Payslip {
  Payslip(this.raw);
  final Map<String, dynamic> raw;

  Map<String, dynamic> _m(String k) => raw[k] is Map ? Map<String, dynamic>.from(raw[k] as Map) : {};
  static double _d(dynamic v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;
  static String _s(dynamic v) => (v ?? '').toString().trim();

  String get id => _s(raw['id']);
  String get month => _s(raw['month']);
  String get duration => _s(raw['duration']);
  bool get isPaid => _s(raw['paymentStatus']) == 'Paid';

  String get companyName => _s(_m('company')['name']);
  String get companyAddress => _s(_m('company')['address']);
  String? get companyLogo {
    final l = _s(_m('company')['logo']);
    return l.isEmpty ? null : l;
  }

  Map<String, dynamic> get employee => _m('employee');
  String emp(String k) => _s(employee[k]);
  String empDate(String k) {
    final d = DateTime.tryParse(emp(k));
    return d == null ? '' : DateFormat('dd MMM yyyy').format(d.toLocal());
  }

  Map<String, dynamic> get attendance => _m('attendance');
  String att(String k) => _s(attendance[k]);

  List<PayslipLine> get earnings => [
        for (final e in (raw['earnings'] as List? ?? const []))
          if (e is Map) PayslipLine(_s(e['label']), _d(e['fixed']), _d(e['earned'])),
      ];
  List<PayslipLine> get deductions => [
        for (final e in (raw['deductions'] as List? ?? const []))
          if (e is Map) PayslipLine(_s(e['label']), 0, _d(e['amount'])),
      ];

  double get fixedGross => _d(_m('totals')['fixedGross']);
  double get totalEarnings => _d(_m('totals')['earnings']);
  double get totalDeductions => _d(_m('totals')['deductions']);
  double get netPay => _d(_m('totals')['netPay']);
}

final NumberFormat _inr = NumberFormat.currency(locale: 'en_IN', symbol: '₹ ', decimalDigits: 2);
String formatInr(double v) => _inr.format(v);

/// "Rupees Twelve Thousand Three Hundred Forty Five and Fifty Paise Only" (Indian system).
String rupeesInWords(double amount) {
  const ones = [
    '', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight', 'Nine', 'Ten', 'Eleven',
    'Twelve', 'Thirteen', 'Fourteen', 'Fifteen', 'Sixteen', 'Seventeen', 'Eighteen', 'Nineteen',
  ];
  const tens = ['', '', 'Twenty', 'Thirty', 'Forty', 'Fifty', 'Sixty', 'Seventy', 'Eighty', 'Ninety'];
  String two(int n) => n < 20 ? ones[n] : '${tens[n ~/ 10]}${n % 10 > 0 ? ' ${ones[n % 10]}' : ''}';
  String three(int n) {
    final h = n ~/ 100, r = n % 100;
    return [if (h > 0) '${ones[h]} Hundred', if (r > 0) two(r)].join(' ');
  }

  var rupees = amount.floor();
  final paise = ((amount - rupees) * 100).round();
  if (rupees == 0 && paise == 0) return 'Rupees Zero Only';
  final parts = <String>[];
  final crore = rupees ~/ 10000000;
  rupees %= 10000000;
  final lakh = rupees ~/ 100000;
  rupees %= 100000;
  final thousand = rupees ~/ 1000;
  rupees %= 1000;
  if (crore > 0) parts.add('${three(crore)} Crore');
  if (lakh > 0) parts.add('${two(lakh)} Lakh');
  if (thousand > 0) parts.add('${two(thousand)} Thousand');
  if (rupees > 0) parts.add(three(rupees));
  final words = parts.join(' ');
  return 'Rupees ${words.isEmpty ? 'Zero' : words}${paise > 0 ? ' and ${two(paise)} Paise' : ''} Only';
}

class PayslipService {
  Future<Payslip> getPayslip(String payrollId) async {
    final res = await ApiClient().dio.get<dynamic>('/staff/payslip/$payrollId');
    final data = res.data is Map ? (res.data as Map)['data'] : null;
    if (data is! Map) throw Exception('Payslip not found.');
    return Payslip(Map<String, dynamic>.from(data));
  }

  /// A4 PDF of [p] with the black EktaHR logo.
  Future<Uint8List> buildPdf(Payslip p) async {
    final logo = pw.MemoryImage(
      (await rootBundle.load('assets/images/ektahr_logo_black.png')).buffer.asUint8List(),
    );
    final regular = pw.Font.ttf(await rootBundle.load('assets/fonts/Inter_18pt-Regular.ttf'));
    final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/Inter_18pt-Bold.ttf'));
    const ink = PdfColor.fromInt(0xFF0F172A);
    const muted = PdfColor.fromInt(0xFF64748B);
    const line = PdfColor.fromInt(0xFFE2E8F0);
    const accent = PdfColor.fromInt(0xFFF4AB1F);
    const soft = PdfColor.fromInt(0xFFF8FAFC);

    pw.Widget kv(String k, String v) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 2.5),
          child: pw.Row(children: [
            pw.SizedBox(width: 96, child: pw.Text(k, style: const pw.TextStyle(fontSize: 8.5, color: muted))),
            pw.Expanded(child: pw.Text(v.isEmpty ? '-' : v, style: pw.TextStyle(fontSize: 8.5, font: bold, color: ink))),
          ]),
        );
    pw.Widget box(String title, List<pw.Widget> children) => pw.Container(
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(border: pw.Border.all(color: line), borderRadius: pw.BorderRadius.circular(6)),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(title, style: pw.TextStyle(fontSize: 9.5, font: bold, color: ink)),
            pw.SizedBox(height: 6),
            ...children,
          ]),
        );
    pw.Widget cell(String t, {bool b = false, bool right = false, PdfColor? color}) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
          child: pw.Text(t,
              textAlign: right ? pw.TextAlign.right : pw.TextAlign.left,
              style: pw.TextStyle(fontSize: 8.5, font: b ? bold : regular, color: color ?? ink)),
        );
    String n(double v) => NumberFormat('#,##,##0.00', 'en_IN').format(v);

    final e = p.earnings, d = p.deductions;
    final rows = e.length > d.length ? e.length : d.length;

    final doc = pw.Document(theme: pw.ThemeData.withFont(base: regular, bold: bold));
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      build: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Expanded(
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text(p.companyName, style: pw.TextStyle(fontSize: 13, font: bold, color: ink)),
              if (p.companyAddress.isNotEmpty)
                pw.Text(p.companyAddress, style: const pw.TextStyle(fontSize: 8.5, color: muted)),
            ]),
          ),
          pw.Image(logo, height: 34),
        ]),
        pw.SizedBox(height: 10),
        pw.Container(height: 2, color: accent),
        pw.SizedBox(height: 10),
        pw.Row(children: [
          pw.Text('Payslip for ${p.month}', style: pw.TextStyle(fontSize: 12, font: bold, color: ink)),
          pw.Spacer(),
          if (p.duration.isNotEmpty) pw.Text(p.duration, style: const pw.TextStyle(fontSize: 8.5, color: muted)),
        ]),
        pw.SizedBox(height: 10),
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Expanded(
            child: box('Employee Details', [
              kv('Name', p.emp('name')),
              kv('Employee ID', p.emp('employeeId')),
              kv('Designation', p.emp('designation')),
              kv('Department', p.emp('department')),
              kv('Date of Joining', p.empDate('dateOfJoining')),
              kv('Work Location', p.emp('workLocation')),
            ]),
          ),
          pw.SizedBox(width: 10),
          pw.Expanded(
            child: box('Bank & Statutory', [
              kv('Bank', p.emp('bankName')),
              kv('Account No.', p.emp('bankAccountNo')),
              kv('PAN', p.emp('panNumber')),
              kv('UAN', p.emp('uanNumber')),
              kv('PF No.', p.emp('pfNumber')),
              kv('ESI No.', p.emp('esiNumber')),
            ]),
          ),
        ]),
        pw.SizedBox(height: 10),
        box('Attendance', [
          pw.Row(children: [
            for (final (k, v) in [
              ('Payable', p.att('payableDays')),
              ('Working', p.att('workingDays')),
              ('Present', p.att('presentDays')),
              ('Absent', p.att('absentDays')),
              ('Half Day', p.att('halfDays')),
              ('Leaves', p.att('leaves')),
              ('Holidays', p.att('holidays')),
              ('Week Off', p.att('weekOffs')),
            ])
              pw.Expanded(
                child: pw.Column(children: [
                  pw.Text(v.isEmpty ? '0' : v, style: pw.TextStyle(fontSize: 11, font: bold, color: ink)),
                  pw.Text(k, style: const pw.TextStyle(fontSize: 7.5, color: muted)),
                ]),
              ),
          ]),
        ]),
        pw.SizedBox(height: 10),
        pw.Table(
          border: pw.TableBorder.all(color: line, width: 0.8),
          columnWidths: const {
            0: pw.FlexColumnWidth(3),
            1: pw.FlexColumnWidth(1.6),
            2: pw.FlexColumnWidth(1.6),
            3: pw.FlexColumnWidth(3),
            4: pw.FlexColumnWidth(1.6),
          },
          children: [
            pw.TableRow(decoration: const pw.BoxDecoration(color: soft), children: [
              cell('Earnings', b: true),
              cell('Fixed', b: true, right: true),
              cell('Earned', b: true, right: true),
              cell('Deductions', b: true),
              cell('Amount', b: true, right: true),
            ]),
            for (var i = 0; i < rows; i++)
              pw.TableRow(children: [
                cell(i < e.length ? e[i].label : ''),
                cell(i < e.length ? n(e[i].fixed) : '', right: true),
                cell(i < e.length ? n(e[i].amount) : '', right: true),
                cell(i < d.length ? d[i].label : ''),
                cell(i < d.length ? n(d[i].amount) : '', right: true),
              ]),
            pw.TableRow(decoration: const pw.BoxDecoration(color: soft), children: [
              cell('Total Earnings', b: true),
              cell(n(p.fixedGross), b: true, right: true),
              cell(n(p.totalEarnings), b: true, right: true),
              cell('Total Deductions', b: true),
              cell(n(p.totalDeductions), b: true, right: true),
            ]),
          ],
        ),
        pw.SizedBox(height: 12),
        pw.Container(
          padding: const pw.EdgeInsets.all(12),
          decoration: pw.BoxDecoration(color: ink, borderRadius: pw.BorderRadius.circular(6)),
          child: pw.Row(children: [
            pw.Expanded(
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Text('NET PAY', style: pw.TextStyle(fontSize: 8.5, font: bold, color: accent)),
                pw.SizedBox(height: 2),
                pw.Text(rupeesInWords(p.netPay), style: const pw.TextStyle(fontSize: 8, color: PdfColors.white)),
              ]),
            ),
            pw.Text(formatInr(p.netPay), style: pw.TextStyle(fontSize: 15, font: bold, color: PdfColors.white)),
          ]),
        ),
        pw.Spacer(),
        pw.Divider(color: line),
        pw.Row(children: [
          pw.Text(
            'This is a system-generated payslip and does not require a signature.',
            style: const pw.TextStyle(fontSize: 7.5, color: muted),
          ),
          pw.Spacer(),
          pw.Text('Generated with ', style: const pw.TextStyle(fontSize: 7.5, color: muted)),
          pw.Image(logo, height: 10),
        ]),
      ]),
    ));
    return doc.save();
  }
}
