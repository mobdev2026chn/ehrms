// hrms/lib/screens/salary/all_payslips_screen.dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:dio/dio.dart';
import '../../services/payslip_service.dart';
import 'payslip_screen.dart';

import '../../config/app_colors.dart';
import '../../services/request_service.dart';
import '../../services/salary_service.dart';
import '../../utils/snackbar_utils.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_tab_loader.dart';
import '../../widgets/profile_app_bar_actions.dart';

const List<String> _kMonths = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

/// Month name for a payslip request: app_backend sends 1-12, HRMSbackend the
/// month name ("August") with the year as a separate string.
String? _payslipMonthName(dynamic raw) {
  if (raw is num && raw >= 1 && raw <= 12) return _kMonths[raw.toInt() - 1];
  if (raw is String && raw.trim().isNotEmpty) {
    final n = int.tryParse(raw.trim());
    if (n != null) return (n >= 1 && n <= 12) ? _kMonths[n - 1] : null;
    return raw.trim();
  }
  return null;
}

/// HRMSbackend payslip requests carry the issued PayRoll id as a plain string
/// (`payrollId`, set once payroll is Paid) instead of a populated `payslipUrl`.
String? payslipPayrollIdOf(dynamic req) {
  if (req is! Map) return null;
  final pid = req['payrollId'];
  if (pid is! String) return null;
  final id = pid.trim();
  return (id.isEmpty || id == 'null') ? null : id;
}

/// Downloads the payslip PDF for [payrollId] (HRMSbackend
/// `GET /admin/staff/payroll/statement/:id/view?download=true`), saves it under
/// Downloads/Payslips and opens it.
Future<void> openPayslipPdfForPayrollId(
  BuildContext context,
  String payrollId, {
  String? period,
}) async {
  // Mobile payslip (native view + Download PDF / Share, black EktaHR logo).
  // Falls back to the server's A4 statement only if the staff payslip API is
  // missing on this backend.
  try {
    await PayslipService().getPayslip(payrollId);
    if (!context.mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => PayslipScreen(payrollId: payrollId, period: period),
    ));
    return;
  } on DioException catch (e) {
    final code = e.response?.statusCode;
    if (code != 404 && code != 405) {
      if (context.mounted) {
        await Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => PayslipScreen(payrollId: payrollId, period: period),
        ));
      }
      return;
    }
    // Route missing (older backend) → A4 statement PDF below.
  } catch (_) {}
  if (!context.mounted) return;
  await openPayslipStatementPdf(context, payrollId, period: period);
}

/// The server's A4 payslip statement as a PDF (HRMSbackend
/// `GET /admin/staff/payroll/statement/:id/view?download=true`): saved under
/// Downloads/Payslips and opened. Used when the mobile payslip API is not on the
/// backend yet.
Future<void> openPayslipStatementPdf(
  BuildContext context,
  String payrollId, {
  String? period,
}) async {
  var loadingShown = true;
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: AppTabLoader()),
  );
  void closeLoading() {
    if (loadingShown && context.mounted) {
      Navigator.of(context).pop();
      loadingShown = false;
    }
  }

  try {
    final bytes =
        await SalaryService().getPayslipPdfBytes(payrollId, download: true);
    closeLoading();
    if (!context.mounted) return;
    if (bytes == null) {
      SnackBarUtils.showSnackBar(context, 'Unable to download payslip.',
          isError: true);
      return;
    }
    final downloadsDir = await getDownloadsDirectory();
    final baseDir = downloadsDir ?? await getApplicationDocumentsDirectory();
    final dir = Directory('${baseDir.path}/Payslips');
    if (!await dir.exists()) await dir.create(recursive: true);
    final safe = (period ?? '').trim().replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
    final file = File(
      '${dir.path}/Payslip_${safe.isEmpty ? DateTime.now().millisecondsSinceEpoch : safe}.pdf',
    );
    await file.writeAsBytes(bytes, flush: true);
    final result = await OpenFilex.open(file.path);
    if (!context.mounted) return;
    if (result.type != ResultType.done) {
      SnackBarUtils.showSnackBar(context, 'Payslip saved to: ${file.path}');
    }
  } catch (e) {
    closeLoading();
    if (context.mounted) {
      SnackBarUtils.showSnackBar(context, 'Error downloading payslip: $e',
          isError: true);
    }
  }
}

/// Full list of the signed-in user's payslip requests, reached from the
/// "VIEW ALL" action on [RequestPayslipScreen]. Unlike the generic
/// `MyRequestsScreen`, this only shows payslip requests and keeps the same
/// card + quick-download affordance used on the request screen.
class AllPayslipsScreen extends StatefulWidget {
  const AllPayslipsScreen({super.key});

  @override
  State<AllPayslipsScreen> createState() => _AllPayslipsScreenState();
}

class _AllPayslipsScreenState extends State<AllPayslipsScreen> {
  final RequestService _requestService = RequestService();

  List<dynamic> _requests = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    final result = await _requestService.getPayslipRequests(limit: 100);
    if (!mounted) return;
    setState(() {
      _requests = _extractRequests(result);
      _loading = false;
    });
  }

  Future<void> _refresh() async {
    final result = await _requestService.getPayslipRequests(limit: 100);
    if (!mounted) return;
    setState(() => _requests = _extractRequests(result));
  }

  List<dynamic> _extractRequests(Map<String, dynamic> result) {
    if (result['success'] != true || result['data'] == null) return const [];
    final data = result['data'];
    if (data is Map) return (data['requests'] as List?) ?? const [];
    if (data is List) return data;
    return const [];
  }

  Future<void> _openPayslip(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (mounted) {
      SnackBarUtils.showSnackBar(context, 'Unable to open payslip',
          isError: true);
    }
  }

  void _onDownload(String? url) {
    if (url != null) {
      _openPayslip(url);
    } else {
      SnackBarUtils.showSnackBar(context, 'Payslip is not generated yet');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleSpacing: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        title: const Text(
          'All Payslips',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: AppColors.textPrimary,
          ),
        ),
        actions: const [ProfileAppBarActions()],
      ),
      body: _loading
          ? const Center(child: AppTabLoader())
          : RefreshIndicator(
              onRefresh: _refresh,
              child: _requests.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 120),
                          child: Center(
                            child: Text(
                              'No payslip requests yet.',
                              style: TextStyle(
                                fontSize: 13,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                        ),
                      ],
                    )
                  : ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                      itemCount: _requests.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (_, i) => PayslipRequestCard(
                        req: _requests[i],
                        onDownload: _onDownload,
                        onDownloadPayroll: (id, period) =>
                            openPayslipPdfForPayrollId(context, id,
                                period: period),
                      ),
                    ),
            ),
    );
  }
}

/// Reusable payslip-request row: period, request/generated date and a quick
/// download button. Shared by [RequestPayslipScreen] and [AllPayslipsScreen].
class PayslipRequestCard extends StatelessWidget {
  const PayslipRequestCard({
    super.key,
    required this.req,
    required this.onDownload,
    this.onDownloadPayroll,
  });

  final dynamic req;

  /// Called with the payslip URL when one exists, or `null` when the payslip
  /// has not been generated yet.
  final void Function(String? url) onDownload;

  /// Called instead of [onDownload] when the request has no URL but carries an
  /// issued payroll id (HRMSbackend), with the id and the display period.
  final void Function(String payrollId, String period)? onDownloadPayroll;

  String? _payslipUrl(dynamic req) {
    final payroll = req is Map ? req['payrollId'] : null;
    final url = payroll is Map ? payroll['payslipUrl']?.toString().trim() : null;
    return (url != null && url.isNotEmpty) ? url : null;
  }

  @override
  Widget build(BuildContext context) {
    final monthName = _payslipMonthName(req is Map ? req['month'] : null);
    final year = req is Map ? req['year']?.toString() : null;
    final period = (req is Map && req['period'] != null)
        ? req['period'].toString()
        : [monthName, year].whereType<String>().join(' ').trim();

    final url = _payslipUrl(req);
    final payrollId =
        onDownloadPayroll != null && url == null ? payslipPayrollIdOf(req) : null;
    final hasUrl = url != null || payrollId != null;

    String when = '';
    final created = req is Map ? req['createdAt'] : null;
    final updated = req is Map ? req['updatedAt'] : null;
    final dateStr = (hasUrl ? (updated ?? created) : created)?.toString();
    final date = dateStr != null ? DateTime.tryParse(dateStr) : null;
    if (date != null) {
      final fmt = DateFormat('MMM dd, yyyy').format(date.toLocal());
      when = hasUrl ? 'Generated on $fmt' : 'Requested on $fmt';
    } else {
      when = (req is Map ? req['status']?.toString() : null) ?? '';
    }

    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.surfaceDark,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.description, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  period.isEmpty ? 'Payslip Request' : period,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  when,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: () => payrollId != null
                ? onDownloadPayroll!(payrollId, period)
                : onDownload(url),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: hasUrl
                    ? AppColors.primary.withValues(alpha: 0.12)
                    : AppColors.inputFill,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.download_rounded,
                size: 20,
                color: hasUrl ? AppColors.primary : AppColors.textCaption,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
