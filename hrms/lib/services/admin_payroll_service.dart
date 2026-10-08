// lib/services/admin_payroll_service.dart
// Admin Payroll + Overtime APIs (HRMSbackend, mounted at /api/admin/staff).
//
// Payroll (routes/admin/salaryRoute.ts -> payRollController / salaryOverviewController):
//   GET  /admin/staff                                   staff list ({ data: { staff: [] } })
//   GET  /admin/staff/payroll?month=September 2026      payroll rows for a month
//   GET  /admin/staff/overview/detail/:staffId?month=   calculates + saves the Salary Overview
//   POST /admin/staff/payroll/generate {staffId, month} payslip from that overview (409 = paid)
//   PUT  /admin/staff/payroll/status/:id {status: 'Processed'} marks paid (final)
//   GET  /admin/staff/payroll/statement/:id/view?download=true  payslip PDF
//
// Overtime (routes/admin/staffRoute.ts -> overTimeController):
//   GET    /admin/staff/overtime/list?status=&month=YYYY-MM&search=&department=&staffId=
//   POST   /admin/staff/overtime/schedule {staffIds, scheduleType, date, startDate, endDate, notes}
//   DELETE /admin/staff/overtime/:id

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

import '../utils/error_message_utils.dart';
import 'api_client.dart';

/// A failed admin payroll/overtime call, carrying the backend's message.
class AdminPayrollException implements Exception {
  final String message;
  final int? statusCode;
  AdminPayrollException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

class AdminPayrollService {
  final ApiClient _api = ApiClient();

  AdminPayrollException _wrap(Object e, String fallback) {
    if (e is AdminPayrollException) return e;
    if (e is DioException) {
      return AdminPayrollException(
        ErrorMessageUtils.messageFromDioException(e, fallback: fallback),
        statusCode: e.response?.statusCode,
      );
    }
    return AdminPayrollException(fallback);
  }

  Map<String, dynamic> _body(Response res, String fallback) {
    final data = res.data;
    if (data is Map) {
      final map = Map<String, dynamic>.from(data);
      if (map['success'] == false) {
        throw AdminPayrollException(
          (map['message'] ?? fallback).toString(),
          statusCode: res.statusCode,
        );
      }
      return map;
    }
    throw AdminPayrollException(fallback, statusCode: res.statusCode);
  }

  // ── Staff ──

  /// Raw staff documents from `GET /admin/staff`.
  Future<List<Map<String, dynamic>>> getStaff() async {
    const fallback = 'Could not load the staff list.';
    try {
      final res = await _api.request('/admin/staff');
      final body = _body(res, fallback);
      final data = body['data'];
      final list = data is Map ? data['staff'] : data;
      if (list is! List) return [];
      return list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (e) {
      throw _wrap(e, fallback);
    }
  }

  // ── Payroll ──

  /// Payroll rows for [month] ("September 2026").
  Future<List<Map<String, dynamic>>> getPayrollList(String month) async {
    const fallback = 'Could not load payroll.';
    try {
      final res = await _api.request(
        '/admin/staff/payroll',
        queryParameters: {'month': month},
      );
      final body = _body(res, fallback);
      final list = body['data'];
      if (list is! List) return [];
      return list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (e) {
      throw _wrap(e, fallback);
    }
  }

  /// Calculates and saves the Salary Overview for the staff member and month. Must run
  /// before [generatePayroll] - the generate call reads the saved overview.
  Future<Map<String, dynamic>> getSalaryOverviewDetail(String staffId, String month) async {
    const fallback = 'Could not calculate the salary overview.';
    try {
      final res = await _api.request(
        '/admin/staff/overview/detail/$staffId',
        queryParameters: {'month': month},
      );
      final body = _body(res, fallback);
      final data = body['data'];
      return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
    } catch (e) {
      throw _wrap(e, fallback);
    }
  }

  /// Generates (or recalculates a pending) payslip. A paid month answers 409.
  Future<Map<String, dynamic>> generatePayroll(String staffId, String month) async {
    const fallback = 'Could not generate payroll.';
    try {
      final res = await _api.request(
        '/admin/staff/payroll/generate',
        method: 'POST',
        data: {'staffId': staffId, 'month': month},
      );
      return _body(res, fallback);
    } catch (e) {
      throw _wrap(e, fallback);
    }
  }

  /// Same two calls the web Generate makes: overview detail, then generate.
  Future<void> generatePayrollForStaff(String staffId, String month) async {
    await getSalaryOverviewDetail(staffId, month);
    await generatePayroll(staffId, month);
  }

  /// Marks a payroll paid. The backend only accepts `Processed`; paid is final.
  Future<void> updatePayrollStatus(String payrollId, {String status = 'Processed'}) async {
    const fallback = 'Could not update payroll status.';
    try {
      final res = await _api.request(
        '/admin/staff/payroll/status/$payrollId',
        method: 'PUT',
        data: {'status': status},
      );
      _body(res, fallback);
    } catch (e) {
      throw _wrap(e, fallback);
    }
  }

  /// Downloads the payslip statement PDF (`?download=true`) and saves it under
  /// `Payslips/` in the temp dir, or in Downloads/Documents when [keep] is true.
  Future<File> downloadPayslipPdf(
    String payrollId, {
    required String fileStem,
    bool keep = false,
  }) async {
    const fallback = 'The payslip could not be generated. Please try again.';
    List<int>? bytes;
    try {
      final res = await _api.request<List<int>>(
        '/admin/staff/payroll/statement/$payrollId/view',
        queryParameters: {'download': 'true'},
        headers: {'Accept': 'application/pdf'},
        options: Options(
          responseType: ResponseType.bytes,
          receiveTimeout: const Duration(seconds: 90),
        ),
      );
      bytes = res.data;
    } on DioException catch (e) {
      // Error bodies arrive as bytes too: decode the JSON/HTML message if possible.
      final raw = e.response?.data;
      if (raw is List<int>) {
        final text = String.fromCharCodes(raw);
        final match = RegExp(r'"message"\s*:\s*"([^"]+)"').firstMatch(text);
        final msg = match?.group(1) ??
            text.replaceAll(RegExp(r'<[^>]+>'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
        if (msg.isNotEmpty) {
          throw AdminPayrollException(
            msg.length > 160 ? msg.substring(0, 160) : msg,
            statusCode: e.response?.statusCode,
          );
        }
      }
      throw _wrap(e, fallback);
    } catch (e) {
      throw _wrap(e, fallback);
    }

    final isPdf = bytes != null &&
        bytes.length >= 4 &&
        bytes[0] == 0x25 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x44 &&
        bytes[3] == 0x46;
    if (!isPdf) throw AdminPayrollException(fallback);

    final Directory baseDir;
    if (keep) {
      baseDir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
    } else {
      baseDir = await getTemporaryDirectory();
    }
    final dir = Directory('${baseDir.path}/Payslips');
    if (!await dir.exists()) await dir.create(recursive: true);
    final safe = fileStem.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
    final file = File('${dir.path}/payslip-${safe.isEmpty ? payrollId : safe}.pdf');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  // ── Overtime ──

  /// Server-side filtered overtime list. [month] is `YYYY-MM`; `All`/empty values are omitted.
  Future<List<Map<String, dynamic>>> getOvertimeList({
    String? status,
    String? month,
    String? search,
    String? department,
    String? staffId,
  }) async {
    const fallback = 'Could not load overtime requests.';
    final query = <String, dynamic>{};
    if (status != null && status.isNotEmpty && status != 'All') query['status'] = status;
    if (month != null && month.isNotEmpty) query['month'] = month;
    if (search != null && search.trim().isNotEmpty) query['search'] = search.trim();
    if (department != null && department.isNotEmpty && department != 'All') {
      query['department'] = department;
    }
    if (staffId != null && staffId.isNotEmpty) query['staffId'] = staffId;
    try {
      final res = await _api.request(
        '/admin/staff/overtime/list',
        queryParameters: query.isEmpty ? null : query,
      );
      final body = _body(res, fallback);
      final data = body['data'];
      final list = data is Map ? data['requests'] : null;
      if (list is! List) return [];
      return list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (e) {
      throw _wrap(e, fallback);
    }
  }

  /// Schedules overtime for staff (`staffIds` are staff `_id`s). Returns the backend message.
  Future<String> scheduleOvertime({
    required List<String> staffIds,
    required String scheduleType, // 'Single Date' | 'Date Range'
    required String startDate, // yyyy-MM-dd
    required String endDate, // yyyy-MM-dd
    String? notes,
  }) async {
    const fallback = 'Failed to schedule overtime';
    final date = scheduleType == 'Single Date' ? startDate : '$startDate to $endDate';
    try {
      final res = await _api.request(
        '/admin/staff/overtime/schedule',
        method: 'POST',
        data: {
          'staffIds': staffIds,
          'scheduleType': scheduleType,
          'date': date,
          'startDate': startDate,
          'endDate': endDate,
          'notes': (notes == null || notes.trim().isEmpty)
              ? 'No additional notes provided.'
              : notes.trim(),
        },
      );
      final body = _body(res, fallback);
      return (body['message'] ?? 'Overtime scheduled').toString();
    } catch (e) {
      throw _wrap(e, fallback);
    }
  }

  Future<void> deleteOvertime(String id) async {
    const fallback = 'Failed to cancel overtime request';
    try {
      final res = await _api.request('/admin/staff/overtime/$id', method: 'DELETE');
      _body(res, fallback);
    } catch (e) {
      throw _wrap(e, fallback);
    }
  }
}
