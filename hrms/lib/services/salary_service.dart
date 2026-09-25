import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/constants.dart';
import 'api_client.dart';
import 'auth_service.dart';
import 'web_hrms_api_dio.dart';

/// Profile-derived salary + revision history for in-app structure screens.
class StaffSalaryBundle {
  StaffSalaryBundle({
    required this.salary,
    required this.revisionHistory,
    this.employeeName,
    this.employeeId,
    this.phone,
    this.staffType,
    this.salaryDetailsAccessEnabled = false,
  });

  final Map<String, dynamic> salary;
  final List<Map<String, dynamic>> revisionHistory;
  final String? employeeName;
  final String? employeeId;
  final String? phone;
  final String? staffType;
  final bool salaryDetailsAccessEnabled;
}

/// Salary Details Access from a profile payload. HRMSbackend `/staff/profile` returns the
/// staff record itself with `salaryDetailsAccess`; app_backend nests it as
/// `staffData.salaryDetailsAccessEnabled`. Null when neither is present.
bool? salaryDetailsAccessFromProfile(Map? data) {
  if (data == null) return null;
  for (final m in [data['staffData'], data['staff'], data]) {
    if (m is! Map) continue;
    final v = m['salaryDetailsAccessEnabled'] ?? m['salaryDetailsAccess'];
    if (v is bool) return v;
  }
  return null;
}

/// Current-month salary visibility. HRMSbackend has no separate switch, so granted
/// Salary Details Access covers the current cycle too.
bool currentCycleSalaryAccessFromProfile(Map? data) {
  for (final m in [data?['staffData'], data?['staff'], data]) {
    if (m is Map && m['allowCurrentCycleSalaryAccess'] is bool) {
      return m['allowCurrentCycleSalaryAccess'] as bool;
    }
  }
  return salaryDetailsAccessFromProfile(data) == true;
}

final AuthService _salaryAuthServiceForAppPerDay = AuthService();

/// Per-day salary in SharedPreferences (fines, check-in preview). Written from web preview [salaryBasis].
const kAppNetPerDaySalaryPrefsKey = 'app_net_per_day_salary';
const kAppGrossPerDaySalaryPrefsKey = 'app_gross_per_day_salary';
const kAppLegacyPerDaySalaryPrefsKey = 'app_per_day_salary';

// Salary debug logs toggle.
// Set true when you need these verbose salary traces again.
const bool _kEnableSalaryVerboseLogs = true;

void _salaryLog(String message) {
  if (_kEnableSalaryVerboseLogs) {
    debugPrint(message);
  }
}

/// Per-day rates for the fine, using the company's payable-days denominator
/// (calendar days / exclude week-offs / fixed days) — the same basis the backend
/// fine uses. Prefers the backend's pre-computed `salaryBasis.perDay*Salary`
/// (already divided by `payableDaysForRate`); otherwise divides monthly salary by
/// `payableDaysForRate` / `attendance.payableDaysBase`, falling back to full-month
/// working days only when no payable-days basis is available.
Map<String, double>? perDayRatesFromPayrollPreviewForFine(
  Map<String, dynamic>? preview,
) {
  if (preview == null) return null;
  final basis = preview['salaryBasis'];
  final att = preview['attendance'];
  if (basis is! Map || att is! Map) return null;
  final b = Map<String, dynamic>.from(basis);
  final a = Map<String, dynamic>.from(att);
  double r2(double x) => (x * 100).round() / 100;

  // Backend already exposes payable-days-based per-day rates; use them directly.
  final preNet = (b['perDayNetSalary'] as num?)?.toDouble();
  final preGross = (b['perDayGrossSalary'] as num?)?.toDouble();
  if (preNet != null && preNet > 0) {
    return {
      'net': r2(preNet),
      'gross': (preGross != null && preGross > 0) ? r2(preGross) : r2(preNet),
    };
  }

  final mn = (b['monthlyNetSalary'] as num?)?.toDouble();
  final mg = (b['monthlyGrossSalary'] as num?)?.toDouble();
  // Payable-days denominator first; full-month working days is a last resort.
  final days = (b['payableDaysForRate'] as num?)?.toInt() ??
      (a['payableDaysBase'] as num?)?.toInt() ??
      (a['fullMonthWorkingDays'] as num?)?.toInt() ??
      (a['workingDays'] as num?)?.toInt() ??
      0;
  if (days <= 0 || mn == null || mn <= 0) return null;
  return {
    'net': r2(mn / days),
    'gross': (mg != null && mg > 0) ? r2(mg / days) : r2(mn / days),
  };
}

/// When preview has no salaryBasis: payroll row ÷ full-month working days.
Map<String, double>? perDayRatesFromPayrollRowForFine(
  Map<String, dynamic>? payroll,
  int fullMonthWorkingDays,
) {
  if (payroll == null || fullMonthWorkingDays <= 0) return null;
  final net = (payroll['netPay'] as num?)?.toDouble();
  final gross = (payroll['grossSalary'] as num?)?.toDouble();
  if (net == null || net <= 0) return null;
  double r2(double x) => (x * 100).round() / 100;
  final wd = fullMonthWorkingDays.toDouble();
  return {
    'net': r2(net / wd),
    'gross': (gross != null && gross > 0) ? r2(gross / wd) : r2(net / wd),
  };
}

Future<void> syncPerDaySalaryPrefsFromPayrollPreview(
  Map<String, dynamic> response, {
  required int month,
  required int year,
}) async {
  final now = DateTime.now();
  if (month != now.month || year != now.year) return;
  if (response['success'] != true) return;
  final data = response['data'];
  if (data is! Map) return;
  final p = data['preview'];
  if (p is! Map) return;
  final rates = perDayRatesFromPayrollPreviewForFine(
    Map<String, dynamic>.from(p),
  );
  if (rates == null) return;
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(kAppNetPerDaySalaryPrefsKey, rates['net']!);
    await prefs.setDouble(kAppGrossPerDaySalaryPrefsKey, rates['gross']!);
    await prefs.setDouble(kAppLegacyPerDaySalaryPrefsKey, rates['net']!);
    if (kDebugMode) {
      _salaryLog(
        '[PreviewSalary] SharedPrefs per-day from preview: net=${rates['net']} '
        'gross=${rates['gross']} month=$month year=$year',
      );
    }
    final syncRes = await _salaryAuthServiceForAppPerDay.updateProfile({
      'appPerDayNetSalary': rates['net']!,
      'appPerdayGrossSalary': rates['gross']!,
    });
    if (syncRes['success'] != true && kDebugMode) {
      _salaryLog(
        '[PreviewSalary] Staff DB sync failed: ${syncRes['message'] ?? syncRes}',
      );
    } else if (kDebugMode) {
      _salaryLog(
        '[PreviewSalary] Staff collection appPerDayNetSalary/appPerdayGrossSalary updated',
      );
    }
  } catch (e) {
    if (kDebugMode) {
      _salaryLog('[PreviewSalary] prefs/Staff sync error: $e');
    }
  }
}

class SalaryService {
  final AuthService _authService = AuthService();
  final ApiClient _api = ApiClient();
  static const Duration _salaryRequestTimeout = Duration(seconds: 25);

  /// Fetches the staff's salary structure from `/admin/staff/salary-structures/staff/:staffId`
  /// exactly like the web dashboard (`Dashboard.tsx`).
  Future<Map<String, dynamic>?> getSalaryStructure(String staffId) async {
    if (staffId.trim().isEmpty) return null;
    // 1. Try webHrmsApiDio
    try {
      final dio = webHrmsApiDio();
      final response = await dio.get<Map<String, dynamic>>(
        '/admin/staff/salary-structures/staff/$staffId',
        options: Options(
          sendTimeout: _salaryRequestTimeout,
          receiveTimeout: _salaryRequestTimeout,
        ),
      );
      final body = response.data;
      if (body != null && body['success'] == true && body['data'] != null) {
        return Map<String, dynamic>.from(body['data']);
      }
    } catch (e) {
      _salaryLog('[SalaryService] getSalaryStructure webHrmsApiDio error: $e');
    }

    // 2. Fallback to main _api client (only when it is a different host).
    if (_mainAndWebHostsAreSame) return null;
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token')?.replaceAll('"', '');
      if (token != null && token.isNotEmpty) _api.setAuthToken(token);
      final response = await _api.dio.get<Map<String, dynamic>>(
        '/admin/staff/salary-structures/staff/$staffId',
      );
      final body = response.data;
      if (body != null && body['success'] == true && body['data'] != null) {
        return Map<String, dynamic>.from(body['data']);
      }
    } catch (e) {
      _salaryLog('[SalaryService] getSalaryStructure _api.dio fallback error: $e');
    }

    return null;
  }


  // ---------------------------------------------------------------------------
  // HRMSbackend payroll adapters
  //
  // HRMSbackend has no `/payroll`, `/payroll/stats` or `/payroll/preview`. A staff
  // member's month-wise salary lives in the Salary Overview record
  // (`GET /admin/staff/overview/detail/:staffId?month=September 2026`), the issued
  // payslip is a PayRoll document found through the staff's own payslip requests
  // (`GET /staff/requests/payslip/my-requests` → `payrollId`, set only once Paid) and
  // rendered by `GET /admin/staff/payroll/statement/:id/view?download=true`.
  // The methods below keep the response shapes the salary screens were written
  // against (`payrolls[]` rows, `stats` envelope) and fill them from those routes.
  // ---------------------------------------------------------------------------

  /// Last [getSalaryStats] outcome for logs: `hrmsbackend`, `empty`, `error`.
  static String lastPayrollStatsHostUsed = '';

  /// When stats could not be built, short reason (logs only).
  static String lastPayrollStatsWebRejectReason = '';

  static const List<String> _monthNames = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  /// Oldest month the payroll history scans back to, counted from the current month.
  static const int _maxHistoryMonths = 24;
  static const Duration _hrmsCacheTtl = Duration(seconds: 20);

  static final Map<String, _TimedValue<Map<String, dynamic>?>> _overviewCache = {};
  static final Map<String, Future<Map<String, dynamic>?>> _overviewInFlight = {};
  static _TimedValue<Map<String, String>>? _payslipIdCache;
  static final Map<String, _TimedValue<Map<String, dynamic>?>> _structureCache = {};

  /// HRMSbackend month key: `"September 2026"`.
  static String hrmsMonthLabel(int month, int year) =>
      '${_monthNames[(month - 1).clamp(0, 11)]} $year';

  static double? _num(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.trim());
    return null;
  }

  /// Staff record from the cached profile: HRMSbackend `/staff/profile` returns the
  /// staff document itself; app_backend nests it under `staffData`.
  Future<Map<String, dynamic>?> _currentStaffRecord() async {
    try {
      final res = await _authService.getProfile();
      final data = res['data'];
      if (res['success'] == true && data is Map) {
        final sd = data['staffData'];
        if (sd is Map && sd['_id'] != null) return Map<String, dynamic>.from(sd);
        if (data['_id'] != null) return Map<String, dynamic>.from(data);
      }
    } catch (_) {}
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('user');
      if (raw != null && raw.trim().isNotEmpty) {
        final m = jsonDecode(raw);
        if (m is Map) {
          final id = m['_id'] ?? m['id'];
          if (id != null) return {...Map<String, dynamic>.from(m), '_id': id};
        }
      }
    } catch (_) {}
    return null;
  }

  Future<String?> _currentStaffId() async {
    final s = await _currentStaffRecord();
    final id = s?['_id']?.toString().trim();
    return (id == null || id.isEmpty) ? null : id;
  }

  /// `GET /admin/staff/overview/detail/:staffId?month=` — recalculated Salary Overview
  /// for one month (earnings/deductions breakdown, attendance counts, status
  /// `Pending` / `On Hold` / `Released`, `isGenerated`). Null when the month has no
  /// salary structure (backend 404) or the call fails.
  Future<Map<String, dynamic>?> _getSalaryOverviewDetail(
    String staffId,
    int month,
    int year,
  ) {
    final label = hrmsMonthLabel(month, year);
    final key = '$staffId|$label';
    final cached = _overviewCache[key];
    if (cached != null && cached.isFresh(_hrmsCacheTtl)) {
      return Future.value(cached.value);
    }
    final pending = _overviewInFlight[key];
    if (pending != null) return pending;
    final future = () async {
      try {
        final response = await webHrmsApiDio().get<Map<String, dynamic>>(
          '/admin/staff/overview/detail/$staffId',
          queryParameters: {'month': label},
          options: Options(
            sendTimeout: _salaryRequestTimeout,
            receiveTimeout: _salaryRequestTimeout,
            extra: const {'disable_429_retry': true},
          ),
        );
        final body = response.data;
        final data = body?['data'];
        final out = (body != null && body['success'] == true && data is Map)
            ? Map<String, dynamic>.from(data)
            : null;
        _overviewCache[key] = _TimedValue(out);
        return out;
      } on DioException catch (e) {
        final code = e.response?.statusCode;
        _salaryLog(
          '[SalaryHrms] GET /admin/staff/overview/detail month="$label" http=$code',
        );
        // 404 = no salary structure effective for that month: a real "no data".
        if (code == 404) _overviewCache[key] = _TimedValue(null);
        return null;
      } catch (e) {
        _salaryLog('[SalaryHrms] overview detail error: $e');
        return null;
      }
    }();
    _overviewInFlight[key] = future;
    return future.whenComplete(() => _overviewInFlight.remove(key));
  }

  /// Payroll ids of issued payslips, keyed by lower-cased `"september 2026"`.
  ///
  /// `GET /staff/requests/payslip/my-requests` (staff-scoped) returns
  /// `payrollId` only when that month's payroll is Paid — the payslip is released
  /// on approval (HRMSbackend creates the approved request itself).
  Future<Map<String, String>> _getIssuedPayslipIds() async {
    final cached = _payslipIdCache;
    if (cached != null && cached.isFresh(_hrmsCacheTtl)) return cached.value;
    final out = <String, String>{};
    try {
      final response = await webHrmsApiDio().get<Map<String, dynamic>>(
        '/staff/requests/payslip/my-requests',
        options: Options(
          sendTimeout: _salaryRequestTimeout,
          receiveTimeout: _salaryRequestTimeout,
          extra: const {'disable_429_retry': true},
        ),
      );
      final data = response.data?['data'];
      final list = data is Map ? data['requests'] : (data is List ? data : null);
      if (list is List) {
        for (final r in list.whereType<Map>()) {
          final pid = r['payrollId'];
          final id = pid is Map ? pid['_id']?.toString() : pid?.toString();
          if (id == null || id.isEmpty || id == 'null') continue;
          final m = r['month'];
          final y = r['year']?.toString().trim() ?? '';
          String? monthName;
          if (m is num && m >= 1 && m <= 12) {
            monthName = _monthNames[m.toInt() - 1];
          } else if (m != null) {
            final s = m.toString().trim();
            final asInt = int.tryParse(s);
            monthName = (asInt != null && asInt >= 1 && asInt <= 12)
                ? _monthNames[asInt - 1]
                : s;
          }
          if (monthName == null || monthName.isEmpty || y.isEmpty) continue;
          out['${monthName.toLowerCase()} $y'] = id;
        }
      }
      _payslipIdCache = _TimedValue(out);
    } catch (e) {
      _salaryLog('[SalaryHrms] GET /staff/requests/payslip/my-requests error: $e');
    }
    return out;
  }

  /// Raw `{ structure, history }` from the salary structure route, cached briefly.
  Future<Map<String, dynamic>?> _getStructureCached(String staffId) async {
    final cached = _structureCache[staffId];
    if (cached != null && cached.isFresh(_hrmsCacheTtl)) return cached.value;
    final data = await getSalaryStructure(staffId);
    _structureCache[staffId] = _TimedValue(data);
    return data;
  }

  /// All salary structures (active + history), newest `effectiveFrom` first.
  static List<Map<String, dynamic>> _allStructures(Map<String, dynamic>? data) {
    if (data == null) return const [];
    final out = <Map<String, dynamic>>[];
    final active = data['structure'];
    if (active is Map) out.add(Map<String, dynamic>.from(active));
    final hist = data['history'];
    if (hist is List) {
      out.addAll(hist.whereType<Map>().map((e) => Map<String, dynamic>.from(e)));
    }
    DateTime eff(Map<String, dynamic> s) =>
        DateTime.tryParse(s['effectiveFrom']?.toString() ?? '') ?? DateTime(1970);
    out.sort((a, b) => eff(b).compareTo(eff(a)));
    return out;
  }

  static List<Map<String, dynamic>> _componentList(dynamic raw) {
    if (raw is! Map) return const [];
    final out = <Map<String, dynamic>>[];
    raw.forEach((k, v) {
      if (v is Map) {
        out.add({
          'name': k.toString(),
          'monthly': _num(v['month']) ?? 0.0,
          'yearly': _num(v['year']) ?? 0.0,
        });
      }
    });
    return out;
  }

  /// Staff `salary` map (legacy shape the salary screens read) from one HRMSbackend
  /// SalaryStructure document. `gross` / `net` / `ctcYearly` are the backend's own
  /// totals (so [calculatedSalaryFromLegacyStaffMap] reproduces them exactly), and
  /// `structure` carries every component line for the breakdown screens.
  static Map<String, dynamic>? salaryMapFromHrmsStructure(
    Map<String, dynamic>? struct,
  ) {
    if (struct == null) return null;
    double monthOf(dynamic v) =>
        v is Map ? (_num(v['month']) ?? 0.0) : (_num(v) ?? 0.0);
    final gross = monthOf(struct['grossSalary']);
    final net = monthOf(struct['netSalary']);
    final ctc = _num(struct['totalCTC']) ?? 0.0;
    if (gross <= 0 && net <= 0 && ctc <= 0) return null;
    return {
      'gross': gross,
      'net': net,
      'ctcYearly': ctc > 0 ? ctc : gross * 12,
      'effectiveFrom': struct['effectiveFrom'],
      'source': 'hrmsbackend_salary_structure',
      'structure': {
        'basicMonthly': monthOf(struct['basicSalary']),
        'grossMonthly': gross,
        'grossYearly': struct['grossSalary'] is Map
            ? (_num(struct['grossSalary']['year']) ?? gross * 12)
            : gross * 12,
        'netMonthly': net,
        'netYearly': struct['netSalary'] is Map
            ? (_num(struct['netSalary']['year']) ?? net * 12)
            : net * 12,
        'totalCTC': ctc,
        'earnings': _componentList(struct['Earnings']),
        'allowances': _componentList(struct['Allowances']),
        'deductions': _componentList(struct['deductions']),
        'benefits': _componentList(struct['Benefits']),
        'variables': _componentList(struct['Variables']),
      },
    };
  }

  /// Active salary as a legacy `salary` map for [staffId], or null when HRMSbackend
  /// has no structure for the staff.
  Future<Map<String, dynamic>?> getSalaryMapForStaff(String staffId) async {
    if (staffId.trim().isEmpty) return null;
    final data = await _getStructureCached(staffId);
    final all = _allStructures(data);
    final active = data?['structure'] is Map
        ? Map<String, dynamic>.from(data!['structure'] as Map)
        : (all.isNotEmpty ? all.last : null);
    return salaryMapFromHrmsStructure(active);
  }

  /// `payrolls[]` row (shape the salary screens use) from a Salary Overview record.
  Map<String, dynamic> _payrollRowFromOverview(
    Map<String, dynamic> ov, {
    required int month,
    required int year,
    String? payrollId,
  }) {
    final rawStatus = ov['status']?.toString().trim() ?? '';
    final hasPayslip = payrollId != null && payrollId.isNotEmpty;
    final String status;
    if (hasPayslip) {
      status = 'Paid';
    } else if (rawStatus.toLowerCase().contains('hold')) {
      status = 'Hold';
    } else {
      status = 'Pending';
    }
    final components = <Map<String, dynamic>>[];
    final earnings = ov['earningsBreakdown'];
    if (earnings is List) {
      for (final e in earnings.whereType<Map>()) {
        components.add({
          'name': e['label']?.toString() ?? 'Earning',
          'amount': _num(e['earned']) ?? 0.0,
          'fixedAmount': _num(e['fixed']) ?? 0.0,
          'type': 'earning',
        });
      }
    }
    final deductions = ov['deductionsBreakdown'];
    if (deductions is List) {
      for (final d in deductions.whereType<Map>()) {
        components.add({
          'name': d['label']?.toString() ?? 'Deduction',
          'amount': _num(d['value']) ?? 0.0,
          'type': 'deduction',
        });
      }
    }
    return {
      // `_id` is the PayRoll id and is only set once a payslip exists, so the
      // screens' "has payslip" checks (`_id` / `payslipUrl`) stay truthful.
      if (hasPayslip) '_id': payrollId,
      if (hasPayslip) 'payrollId': payrollId,
      'overviewId': ov['_id']?.toString(),
      'month': month,
      'year': year,
      'monthLabel': hrmsMonthLabel(month, year),
      'duration': ov['duration'],
      'status': status,
      'rawStatus': rawStatus,
      'isGenerated': ov['isGenerated'] == true,
      'payslipAvailable': hasPayslip,
      'payslipUrl': '',
      'grossSalary': _num(ov['gross']) ?? 0.0,
      'netPay': _num(ov['net']) ?? 0.0,
      'deductions': _num(ov['deductions']) ?? 0.0,
      'payableDays': _num(ov['payableDays']),
      'presentDays': _num(ov['presentDays']),
      'absentDays': _num(ov['absentDays']),
      'halfDays': _num(ov['halfDays']),
      'leaves': _num(ov['leaves']),
      'hoursWorked': ov['hoursWorked'],
      'otHours': ov['otHours'],
      'totalFineHours': ov['totalFineHours'],
      'components': components,
    };
  }

  /// Month-wise payroll for the signed-in staff member, in the legacy
  /// `{ success, data: { payrolls: [...], pagination } }` shape.
  ///
  /// With [month] + [year]: that month only. Without: the history, newest first,
  /// from the current month back to the first salary structure (max
  /// [_maxHistoryMonths] months), paged by [page] / [limit]. Every month with a
  /// salary structure is listed whatever its status (Pending / Hold / Paid).
  Future<Map<String, dynamic>> getPayrolls({
    int? page,
    int? limit,
    int? month,
    int? year,
  }) async {
    final p = (page ?? 1) < 1 ? 1 : (page ?? 1);
    final l = (limit ?? 10) < 1 ? 10 : (limit ?? 10);
    Map<String, dynamic> envelope(List<Map<String, dynamic>> rows, int total) => {
          'success': true,
          'data': {
            'payrolls': rows,
            'pagination': {
              'page': p,
              'limit': l,
              'total': total,
              'pages': total == 0 ? 0 : ((total + l - 1) ~/ l),
            },
          },
        };

    final staffId = await _currentStaffId();
    if (staffId == null) throw Exception('No staff session found');

    if (month != null && year != null) {
      final results = await Future.wait<dynamic>([
        _getSalaryOverviewDetail(staffId, month, year),
        _getIssuedPayslipIds(),
      ]);
      final ov = results[0] as Map<String, dynamic>?;
      final ids = results[1] as Map<String, String>;
      if (ov == null) return envelope(const [], 0);
      final row = _payrollRowFromOverview(
        ov,
        month: month,
        year: year,
        payrollId: ids[hrmsMonthLabel(month, year).toLowerCase()],
      );
      _salaryLog(
        '[SalaryHrms] payroll month=${row['monthLabel']} status=${row['status']} '
        'gross=${row['grossSalary']} net=${row['netPay']} payslip=${row['payslipAvailable']}',
      );
      return envelope([row], 1);
    }

    // History: every month from the earliest salary structure up to now.
    final structures = _allStructures(await _getStructureCached(staffId));
    if (structures.isEmpty) return envelope(const [], 0);
    final earliest = structures
        .map((s) => DateTime.tryParse(s['effectiveFrom']?.toString() ?? ''))
        .whereType<DateTime>()
        .map((d) => d.toLocal())
        .fold<DateTime?>(null, (a, b) => a == null || b.isBefore(a) ? b : a);
    final now = DateTime.now();
    final months = <DateTime>[];
    var cursor = DateTime(now.year, now.month);
    final floor = earliest == null ? null : DateTime(earliest.year, earliest.month);
    while (months.length < _maxHistoryMonths &&
        (floor == null || !cursor.isBefore(floor))) {
      months.add(cursor);
      cursor = DateTime(cursor.year, cursor.month - 1);
    }
    final start = (p - 1) * l;
    if (start >= months.length) return envelope(const [], months.length);
    final slice = months.sublist(start, (start + l).clamp(0, months.length));
    final ids = await _getIssuedPayslipIds();
    final overviews = await Future.wait(
      slice.map((d) => _getSalaryOverviewDetail(staffId, d.month, d.year)),
    );
    final rows = <Map<String, dynamic>>[];
    for (var i = 0; i < slice.length; i++) {
      final ov = overviews[i];
      if (ov == null) continue;
      final d = slice[i];
      rows.add(
        _payrollRowFromOverview(
          ov,
          month: d.month,
          year: d.year,
          payrollId: ids[hrmsMonthLabel(d.month, d.year).toLowerCase()],
        ),
      );
    }
    _salaryLog(
      '[SalaryHrms] payroll history page=$p limit=$l months=${months.length} rows=${rows.length}',
    );
    return envelope(rows, months.length);
  }

  /// Payslip PDF for a PayRoll id:
  /// `GET /admin/staff/payroll/statement/:id/view?download=true` (HRMSbackend renders
  /// the payslip HTML to PDF). Null when unavailable; [download] only affects how
  /// the caller handles the bytes.
  Future<List<int>?> getPayslipPdfBytes(
    String payrollId, {
    required bool download,
  }) async {
    final token = await _authService.getToken();
    if (token == null || payrollId.trim().isEmpty) return null;
    try {
      final response = await webHrmsApiDio().get<List<int>>(
        '/admin/staff/payroll/statement/$payrollId/view',
        queryParameters: {'download': 'true'},
        options: Options(
          responseType: ResponseType.bytes,
          headers: {'Accept': 'application/pdf'},
          receiveTimeout: const Duration(seconds: 60),
        ),
      );
      final data = response.data;
      if (data != null &&
          data.length >= 4 &&
          data[0] == 0x25 &&
          data[1] == 0x50 &&
          data[2] == 0x44 &&
          data[3] == 0x46) {
        return List<int>.from(data);
      }
      return null;
    } on DioException catch (e) {
      _salaryLog(
        '[SalaryHrms] payslip PDF http=${e.response?.statusCode} ${e.message}',
      );
      return null;
    }
  }

  /// `stats` envelope the salary screens read (`thisMonthGross/Net`, `earnings`,
  /// `deductionComponents`, contract gross/net/CTC), built from the month's Salary
  /// Overview plus the active salary structure. Defaults to the current month.
  Future<Map<String, dynamic>> getSalaryStats({int? month, int? year}) async {
    lastPayrollStatsHostUsed = '';
    lastPayrollStatsWebRejectReason = '';
    final now = DateTime.now();
    final m = month ?? now.month;
    final y = year ?? now.year;
    final staffId = await _currentStaffId();
    if (staffId == null) {
      lastPayrollStatsHostUsed = 'empty';
      lastPayrollStatsWebRejectReason = 'no_staff_session';
      return _getEmptySalaryData();
    }
    try {
      final results = await Future.wait<dynamic>([
        _getSalaryOverviewDetail(staffId, m, y),
        _getStructureCached(staffId),
        _getIssuedPayslipIds(),
      ]);
      final ov = results[0] as Map<String, dynamic>?;
      final structData = results[1] as Map<String, dynamic>?;
      final ids = results[2] as Map<String, String>;
      final salary = salaryMapFromHrmsStructure(
        structData?['structure'] is Map
            ? Map<String, dynamic>.from(structData!['structure'] as Map)
            : null,
      );
      if (ov == null && salary == null) {
        lastPayrollStatsHostUsed = 'empty';
        lastPayrollStatsWebRejectReason = 'no_overview_and_no_structure';
        return {..._getEmptySalaryData(), 'month': m, 'year': y, 'stats': null};
      }
      final stats = <String, dynamic>{
        if (salary != null) ...{
          'grossSalary': salary['gross'],
          'netSalary': salary['net'],
          'ctc': salary['ctcYearly'],
          'monthlyContractGrossSalary': salary['gross'],
          'monthlyContractNetSalary': salary['net'],
        },
      };
      if (ov != null) {
        final row = _payrollRowFromOverview(
          ov,
          month: m,
          year: y,
          payrollId: ids[hrmsMonthLabel(m, y).toLowerCase()],
        );
        final comps = (row['components'] as List).cast<Map<String, dynamic>>();
        stats.addAll({
          'thisMonthGross': row['grossSalary'],
          'thisMonthNet': row['netPay'],
          'deductions': row['deductions'],
          'status': row['status'],
          'earnings': comps
              .where((c) => c['type'] == 'earning')
              .map((c) => {'name': c['name'], 'amount': c['amount']})
              .toList(),
          'deductionComponents': comps
              .where((c) => c['type'] == 'deduction')
              .map((c) => {'name': c['name'], 'amount': c['amount']})
              .toList(),
          'attendance': {
            'presentDays': row['presentDays'],
            'absentDays': row['absentDays'],
            'halfDays': row['halfDays'],
            'leaves': row['leaves'],
            'payableDays': row['payableDays'],
          },
        });
      }
      lastPayrollStatsHostUsed = 'hrmsbackend';
      return {
        'month': m,
        'year': y,
        'isProcessed': ov != null && ids.containsKey(hrmsMonthLabel(m, y).toLowerCase()),
        'stats': stats,
      };
    } catch (e) {
      lastPayrollStatsHostUsed = 'error';
      lastPayrollStatsWebRejectReason = 'unexpected:$e';
      _salaryLog('[SalaryHrms] getSalaryStats error: $e');
      return _getEmptySalaryData();
    }
  }

  Map<String, dynamic> _getEmptySalaryData() {
    return {
      'netPay': 0,
      'grossSalary': 0,
      'deductions': 0,
      'workingDays': 0,
      'presentDays': 0,
      'lopDays': 0,
      'earnings': [],
      'deductionsList': [],
    };
  }

  /// HRMSbackend has no payroll preview route; month figures come from the Salary
  /// Overview record via [getPayrolls] / [getSalaryStats] instead. Kept so callers
  /// compile and fall back without a network round-trip.
  Future<Map<String, dynamic>> previewPayroll({
    required String employeeId,
    required int month,
    required int year,
  }) async {
    return {
      'success': false,
      'data': null,
      'message': 'Payroll preview is not available; using the salary overview record.',
    };
  }

  Future<Map<String, dynamic>?> getStaffSalaryDetails() async {
    try {
      final profileResult = await _authService.getProfile();
      if (profileResult['success'] == true) {
        final staffData = profileResult['data']?['staffData'];
        if (staffData != null && staffData['salary'] != null) {
          return staffData['salary'] as Map<String, dynamic>;
        }
      }
      final staffId = await _currentStaffId();
      if (staffId != null) return getSalaryMapForStaff(staffId);
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Parse `GET /auth/profile` `data` into [StaffSalaryBundle], or null if no usable salary.
  static StaffSalaryBundle? staffSalaryBundleFromProfileData(
    Map<String, dynamic>? data,
  ) {
    if (data == null) return null;
    final staffData = data['staffData'];
    if (staffData is! Map) return null;
    final m = Map<String, dynamic>.from(staffData);
    final sal = m['salary'];
    if (sal is! Map) return null;
    final histRaw = m['salaryRevisionHistory'];
    final history = <Map<String, dynamic>>[];
    if (histRaw is List) {
      for (final e in histRaw) {
        if (e is Map) {
          history.add(Map<String, dynamic>.from(e));
        }
      }
    }
    final profile = data['profile'];
    String? name;
    if (profile is Map) {
      name = profile['name']?.toString();
    }
    return StaffSalaryBundle(
      salary: Map<String, dynamic>.from(sal),
      revisionHistory: history,
      employeeName: name,
      employeeId: m['employeeId']?.toString(),
      phone: (m['phoneNumber'] ?? m['phone'])?.toString(),
      staffType: m['staffType']?.toString(),
      salaryDetailsAccessEnabled: salaryDetailsAccessFromProfile(data) == true,
    );
  }

  /// HRMSbackend: the profile is the staff record itself (no `salary`), so the
  /// structure comes from `GET /admin/staff/salary-structures/staff/:id` and the
  /// revision history from its `history` list (each entry paired with the one it
  /// replaced). Salary is not fetched at all while access is off.
  Future<StaffSalaryBundle?> _hrmsStaffSalaryBundle(
    Map<String, dynamic> staff,
  ) async {
    final staffId = staff['_id']?.toString() ?? '';
    if (staffId.isEmpty) return null;
    final access = salaryDetailsAccessFromProfile(staff) == true;
    final name = (staff['name']?.toString().trim().isNotEmpty ?? false)
        ? staff['name'].toString().trim()
        : '${staff['firstName'] ?? ''} ${staff['lastName'] ?? ''}'.trim();
    StaffSalaryBundle bundle(Map<String, dynamic> salary,
            List<Map<String, dynamic>> history) =>
        StaffSalaryBundle(
          salary: salary,
          revisionHistory: history,
          employeeName: name.isEmpty ? null : name,
          employeeId: staff['employeeId']?.toString(),
          phone: (staff['phoneNumber'] ?? staff['phone'])?.toString(),
          staffType: staff['staffType']?.toString(),
          salaryDetailsAccessEnabled: access,
        );
    if (!access) return bundle(const {}, const []);

    final data = await _getStructureCached(staffId);
    final all = _allStructures(data);
    final activeRaw = data?['structure'] is Map
        ? Map<String, dynamic>.from(data!['structure'] as Map)
        : (all.isNotEmpty ? all.last : null);
    final salary = salaryMapFromHrmsStructure(activeRaw);
    if (salary == null) return null;
    final history = <Map<String, dynamic>>[];
    for (var i = 0; i < all.length; i++) {
      final revised = salaryMapFromHrmsStructure(all[i]);
      if (revised == null) continue;
      final previous =
          i + 1 < all.length ? salaryMapFromHrmsStructure(all[i + 1]) : null;
      history.add({
        'effectiveFrom': all[i]['effectiveFrom'],
        'revisedAt': all[i]['revisedAt'],
        'note': all[i]['note'],
        'revisedSalary': revised,
        if (previous != null) 'previousSalary': previous,
      });
    }
    return bundle(salary, history);
  }

  /// Staff `salary` + `salaryRevisionHistory` from GET profile (geo backend, then web HRMS if needed);
  /// on HRMSbackend, from the salary structure route.
  Future<StaffSalaryBundle?> getStaffSalaryBundle() async {
    try {
      Future<StaffSalaryBundle?> tryParse(Future<Map<String, dynamic>> future) async {
        final profileResult = await future;
        if (profileResult['success'] != true) return null;
        final data = profileResult['data'];
        if (data is! Map) return null;
        final map = Map<String, dynamic>.from(data);
        final legacy = staffSalaryBundleFromProfileData(map);
        if (legacy != null) return legacy;
        final staff = map['staffData'] is Map && (map['staffData'] as Map)['_id'] != null
            ? Map<String, dynamic>.from(map['staffData'] as Map)
            : (map['_id'] != null ? map : null);
        if (staff == null) return null;
        return _hrmsStaffSalaryBundle(staff);
      }

      var bundle = await tryParse(_authService.getProfile());
      if (bundle == null && !_mainAndWebHostsAreSame) {
        bundle = await tryParse(_authService.getProfile(useWebHrmsApi: true));
      }
      return bundle;
    } catch (_) {
      return null;
    }
  }

  static bool get _mainAndWebHostsAreSame {
    final main = AppConstants.baseUrl.replaceAll(RegExp(r'/+$'), '');
    final web = AppConstants.webBaseUrl.replaceAll(RegExp(r'/+$'), '');
    return main == web;
  }
}

class _TimedValue<T> {
  _TimedValue(this.value) : at = DateTime.now();
  final T value;
  final DateTime at;
  bool isFresh(Duration ttl) => DateTime.now().difference(at) < ttl;
}
