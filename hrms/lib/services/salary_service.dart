import 'dart:async';
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

/// `salaryBasis.monthlyNet|GrossSalary` ÷ preview full-month working days (web HRMS parity).
Map<String, double>? perDayRatesFromPayrollPreviewForFine(
  Map<String, dynamic>? preview,
) {
  if (preview == null) return null;
  final basis = preview['salaryBasis'];
  final att = preview['attendance'];
  if (basis is! Map || att is! Map) return null;
  final b = Map<String, dynamic>.from(basis);
  final a = Map<String, dynamic>.from(att);
  final mn = (b['monthlyNetSalary'] as num?)?.toDouble();
  final mg = (b['monthlyGrossSalary'] as num?)?.toDouble();
  final wd = (a['fullMonthWorkingDays'] as num?)?.toInt() ??
      (a['workingDays'] as num?)?.toInt() ??
      0;
  if (wd <= 0 || mn == null || mn <= 0) return null;
  double r2(double x) => (x * 100).round() / 100;
  return {
    'net': r2(mn / wd),
    'gross': (mg != null && mg > 0) ? r2(mg / wd) : r2(mn / wd),
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

  /// Last [getSalaryStats] outcome for logs: `web_hrms`, `geo_main`, `empty`, `error`.
  static String lastPayrollStatsHostUsed = '';

  /// When web `/payroll/stats` is not used, short reason (HTTP, body shape, unusable stats).
  static String lastPayrollStatsWebRejectReason = '';

  static bool get _mainAndWebHostsAreSame {
    final main = AppConstants.baseUrl.replaceAll(RegExp(r'/+$'), '');
    final web = AppConstants.webBaseUrl.replaceAll(RegExp(r'/+$'), '');
    return main == web;
  }

  /// Web HRMS often returns `{ stats: null }` when the JWT staff is not linked there;
  /// geo [AppConstants.baseUrl] still has payroll stats for the same employee.
  static bool _statNumLike(dynamic v) {
    if (v is num) return true;
    if (v is String && v.trim().isNotEmpty) {
      return double.tryParse(v.trim()) != null;
    }
    return false;
  }

  static bool _payrollStatsEnvelopeHasUsableStats(Map<String, dynamic> envelope) {
    final st = envelope['stats'];
    if (st is! Map) return false;
    final sm = Map<String, dynamic>.from(st);
    if (_statNumLike(sm['thisMonthNet']) || _statNumLike(sm['thisMonthGross'])) {
      return true;
    }
    if (_statNumLike(sm['grossSalary']) || _statNumLike(sm['netSalary'])) {
      return true;
    }
    if (_statNumLike(sm['deductions'])) return true;
    final er = sm['earnings'];
    if (er is List && er.isNotEmpty) return true;
    final dr = sm['deductionComponents'];
    if (dr is List && dr.isNotEmpty) return true;
    final att = sm['attendance'];
    if (att is Map) {
      final a = Map<String, dynamic>.from(att);
      if (a['workingDays'] is num ||
          a['workingDaysFullMonth'] is num ||
          _statNumLike(a['workingDays']) ||
          _statNumLike(a['workingDaysFullMonth'])) {
        return true;
      }
    }
    return false;
  }

  /// Why [envelope] from `/payroll/stats` `data` is or is not usable (Salary Overview debug).
  static String _diagnoseStatsEnvelope(Map<String, dynamic> envelope) {
    if (!envelope.containsKey('stats')) {
      final keys = envelope.keys.take(14).join(',');
      return 'no_stats_key(envelopeKeys=$keys)';
    }
    final st = envelope['stats'];
    if (st == null) return 'stats_is_null';
    if (st is! Map) return 'stats_wrong_type(${st.runtimeType})';
    if (!_payrollStatsEnvelopeHasUsableStats(envelope)) {
      final sm = Map<String, dynamic>.from(st);
      return 'stats_present_but_unusable(keys=${sm.keys.join(",")})';
    }
    return 'usable';
  }

  Future<Map<String, dynamic>> _fetchPayrollStatsFromDio(
    Dio dio, {
    int? month,
    int? year,
  }) async {
    final host = dio.options.baseUrl;
    try {
      final response = await dio.get<Map<String, dynamic>>(
        '/payroll/stats',
        queryParameters: {
          if (month != null) 'month': month,
          if (year != null) 'year': year,
        },
        options: Options(
          sendTimeout: _salaryRequestTimeout,
          receiveTimeout: _salaryRequestTimeout,
          extra: const {'disable_429_retry': true},
        ),
      );
      final data = response.data;
      final http = response.statusCode;
      final innerData =
          (data != null && data['success'] == true) ? data['data'] : null;
      Map<String, dynamic> out;
      String note = '';
      if (innerData is Map) {
        out = Map<String, dynamic>.from(innerData);
      } else {
        out = _getEmptySalaryData();
        final body = response.data;
        if (body != null) {
          final d = Map<String, dynamic>.from(body);
          final err = d['error'];
          if (err is Map && err['message'] != null) {
            note = 'apiError=${err['message']}';
          } else if (d['message'] != null) {
            note = 'apiMessage=${d['message']}';
          } else {
            note = 'success_false_or_data_not_map';
          }
        } else {
          note = 'response_body_null';
        }
      }
      final usable = _payrollStatsEnvelopeHasUsableStats(out);
      final diag = _diagnoseStatsEnvelope(out);
      final topSuccess = data != null && data['success'] == true;
      _salaryLog(
        '[SalaryWebApi] GET /payroll/stats host=$host http=$http apiSuccess=$topSuccess '
        'parsedUsable=$usable diag=$diag${note.isEmpty ? "" : " $note"}',
      );
      return out;
    } on DioException catch (e) {
      _salaryLog(
        '[SalaryWebApi] GET /payroll/stats host=$host DioException '
        'http=${e.response?.statusCode} type=${e.type} message=${e.message} '
        'responseBody=${e.response?.data}',
      );
      rethrow;
    }
  }

  Future<Map<String, dynamic>> getSalaryStats({int? month, int? year}) async {
    lastPayrollStatsHostUsed = '';
    lastPayrollStatsWebRejectReason = '';
    final token = await _authService.getToken();
    if (token == null) {
      lastPayrollStatsWebRejectReason = 'no_auth_token';
      lastPayrollStatsHostUsed = 'empty';
      return _getEmptySalaryData();
    }

    Future<Map<String, dynamic>> tryWeb() async {
      _salaryLog(
        '[SalaryOverview] GET ${AppConstants.webBaseUrl}/payroll/stats month=$month year=$year',
      );
      return _fetchPayrollStatsFromDio(
        webHrmsApiDio(),
        month: month,
        year: year,
      );
    }

    Future<Map<String, dynamic>> tryMain() async {
      if (_mainAndWebHostsAreSame) return _getEmptySalaryData();
      _salaryLog(
        '[SalaryOverview] GET ${AppConstants.baseUrl}/payroll/stats (fallback) month=$month year=$year',
      );
      _api.setAuthToken(token);
      return _fetchPayrollStatsFromDio(
        _api.dio,
        month: month,
        year: year,
      );
    }

    try {
      Map<String, dynamic> envelope = await tryWeb();
      if (_payrollStatsEnvelopeHasUsableStats(envelope)) {
        lastPayrollStatsHostUsed = 'web_hrms';
        lastPayrollStatsWebRejectReason = '';
        _salaryLog(
          '[SalaryWebApi] payroll/stats CHOSEN=web_hrms (${AppConstants.webBaseUrl}) '
          'month=$month year=$year',
        );
        _logPayrollStatsForTest(data: envelope, month: month, year: year);
        return envelope;
      }
      lastPayrollStatsWebRejectReason = _diagnoseStatsEnvelope(envelope);
      _salaryLog(
        '[SalaryWebApi] payroll/stats web NOT used: $lastPayrollStatsWebRejectReason '
        '— trying geo API=${AppConstants.baseUrl}',
      );
      if (kDebugMode) {
        _salaryLog(
          '[SalaryOverview] payroll/stats web payload has no usable stats — trying main API',
        );
      }
      if (_mainAndWebHostsAreSame) {
        lastPayrollStatsHostUsed = 'empty';
        _salaryLog(
          '[SalaryWebApi] payroll/stats geo fallback SKIPPED (webBaseUrl == baseUrl same host)',
        );
        _logPayrollStatsForTest(data: envelope, month: month, year: year);
        return envelope;
      }
      envelope = await tryMain();
      if (_payrollStatsEnvelopeHasUsableStats(envelope)) {
        lastPayrollStatsHostUsed = 'geo_main';
        _salaryLog(
          '[SalaryWebApi] payroll/stats CHOSEN=geo_main (${AppConstants.baseUrl}) '
          'month=$month year=$year (web issue: $lastPayrollStatsWebRejectReason)',
        );
        _logPayrollStatsForTest(data: envelope, month: month, year: year);
        return envelope;
      }
      lastPayrollStatsHostUsed = 'empty';
      _salaryLog(
        '[SalaryWebApi] payroll/stats CHOSEN=none both_hosts_unusable '
        'webDiag=$lastPayrollStatsWebRejectReason geoDiag=${_diagnoseStatsEnvelope(envelope)}',
      );
      _logPayrollStatsForTest(data: envelope, month: month, year: year);
      return envelope;
    } on DioException catch (e) {
      lastPayrollStatsWebRejectReason =
          'web_dio http=${e.response?.statusCode} ${e.message} body=${e.response?.data}';
      _salaryLog(
        '[SalaryWebApi] payroll/stats web FAILED — $lastPayrollStatsWebRejectReason '
        '— trying geo API=${AppConstants.baseUrl}',
      );
      if (kDebugMode) {
        _salaryLog(
          '[SalaryOverview] payroll/stats web DioException ${e.response?.statusCode} — trying main API',
        );
      }
      try {
        Map<String, dynamic> envelope = await tryMain();
        if (_payrollStatsEnvelopeHasUsableStats(envelope)) {
          lastPayrollStatsHostUsed = 'geo_main';
          _salaryLog(
            '[SalaryWebApi] payroll/stats CHOSEN=geo_main after_web_dio_error month=$month year=$year',
          );
        } else {
          lastPayrollStatsHostUsed = 'empty';
          _salaryLog(
            '[SalaryWebApi] payroll/stats CHOSEN=none geo_after_web_error '
            'geoDiag=${_diagnoseStatsEnvelope(envelope)}',
          );
        }
        _logPayrollStatsForTest(data: envelope, month: month, year: year);
        return envelope;
      } catch (_) {
        lastPayrollStatsHostUsed = 'error';
        if (e.response?.statusCode == 404) return _getEmptySalaryData();
        return _getEmptySalaryData();
      }
    } catch (e) {
      lastPayrollStatsHostUsed = 'error';
      lastPayrollStatsWebRejectReason = 'unexpected:$e';
      _salaryLog('[SalaryWebApi] payroll/stats FATAL $e');
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

  Future<Map<String, dynamic>> getPayrolls({
    int? page,
    int? limit,
    int? month,
    int? year,
  }) async {
    final token = await _authService.getToken();
    if (token == null) throw Exception('No token found');
    try {
      final q = <String, dynamic>{
        'page': page ?? 1,
        'limit': limit ?? 10,
      };
      if (month != null) q['month'] = month;
      if (year != null) q['year'] = year;
      _salaryLog(
        '[SalaryOverview] GET ${AppConstants.webBaseUrl}/payroll query=$q',
      );
      final response = await webHrmsApiDio().get<Map<String, dynamic>>(
        '/payroll',
        queryParameters: q,
        options: Options(
          sendTimeout: _salaryRequestTimeout,
          receiveTimeout: _salaryRequestTimeout,
          extra: const {'disable_429_retry': true},
        ),
      );
      final data = response.data;
      if (data != null) {
        final list = data['data'];
        final payrolls = list is Map ? list['payrolls'] : null;
        final n = payrolls is List ? payrolls.length : -1;
        _salaryLog(
          '[SalaryWebApi] GET /payroll list host=${AppConstants.webBaseUrl} '
          'http=${response.statusCode} success=${data['success']} rowCount=$n',
        );
        return data;
      }
      return {
        'success': true,
        'data': {
          'payrolls': <dynamic>[],
          'pagination': {
            'page': page ?? 1,
            'limit': limit ?? 10,
            'total': 0,
            'pages': 0,
          },
        },
      };
    } on DioException catch (e) {
      _salaryLog(
        '[SalaryWebApi] GET /payroll list FAILED host=${AppConstants.webBaseUrl} '
        'http=${e.response?.statusCode} message=${e.message} body=${e.response?.data}',
      );
      if (e.response?.statusCode == 404) {
        return {
          'success': true,
          'data': {
            'payrolls': <dynamic>[],
            'pagination': {
              'page': page ?? 1,
              'limit': limit ?? 10,
              'total': 0,
              'pages': 0,
            },
          },
        };
      }
      throw Exception('Error fetching payrolls: ${e.message}');
    }
  }

  /// Web RTK `viewPayslip` / `downloadPayslip` — GET PDF bytes by payroll id.
  /// Returns null if the route is missing (404) or the body is not usable; callers fall back to [payslipUrl].
  Future<List<int>?> getPayslipPdfBytes(
    String payrollId, {
    required bool download,
  }) async {
    final token = await _authService.getToken();
    if (token == null) return null;
    try {
      final path = download
          ? '/payroll/$payrollId/payslip/download'
          : '/payroll/$payrollId/payslip/view';
      _salaryLog(
        '[SalaryOverview] GET ${AppConstants.webBaseUrl}$path',
      );
      final response = await webHrmsApiDio().get<dynamic>(
        path,
        options: Options(responseType: ResponseType.bytes),
      );
      final data = response.data;
      if (data is List<int>) return List<int>.from(data);
      return null;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      _salaryLog('[SalaryOverview] getPayslipPdfBytes: ${e.message}');
      return null;
    }
  }

  /// Web RTK `previewPayroll` / EmployeeSalaryOverview: tier 2 MTD (after processed payroll).
  /// Always calls [AppConstants.webBaseUrl] so the payload matches the web HRMS
  /// (`salaryBasis`, per-day rates, `fullMonthWorkingDays`, etc.).
  Future<Map<String, dynamic>> previewPayroll({
    required String employeeId,
    required int month,
    required int year,
  }) async {
    final body = <String, dynamic>{
      'employeeId': employeeId,
      'month': month,
      'year': year,
    };

    Map<String, dynamic> parseResponse(Response<Map<String, dynamic>>? r) {
      final data = r?.data;
      if (data != null) return Map<String, dynamic>.from(data);
      return {'success': false, 'data': null};
    }

    try {
      _salaryLog(
        '[SalaryOverview] POST ${AppConstants.webBaseUrl}/payroll/preview '
        'month=$month year=$year employeeId=$employeeId',
      );
      final r = await webHrmsApiDio().post<Map<String, dynamic>>(
        '/payroll/preview',
        data: body,
        options: Options(
          sendTimeout: _salaryRequestTimeout,
          receiveTimeout: _salaryRequestTimeout,
          extra: const {'disable_429_retry': true},
        ),
      );
      final out = parseResponse(r);
      _logPreviewSalaryNetGrossForTest(
        response: out,
        source: 'webHrms',
        employeeId: employeeId,
        month: month,
        year: year,
      );
      unawaited(
        syncPerDaySalaryPrefsFromPayrollPreview(
          out,
          month: month,
          year: year,
        ),
      );
      return out;
    } on DioException catch (e) {
      _salaryLog(
        '[SalaryWebApi] POST /payroll/preview host=${AppConstants.webBaseUrl} '
        'http=${e.response?.statusCode} message=${e.message} '
        'body=${e.response?.data} '
        '(expected 400 when payroll row already exists for month)',
      );
      _salaryLog('[SalaryOverview] previewPayroll web error: ${e.message}');
      return {'success': false, 'data': null};
    }
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
      phone: m['phone']?.toString(),
      staffType: m['staffType']?.toString(),
      salaryDetailsAccessEnabled: m['salaryDetailsAccessEnabled'] == true,
    );
  }

  /// Staff `salary` + `salaryRevisionHistory` from GET profile (geo backend, then web HRMS if needed).
  Future<StaffSalaryBundle?> getStaffSalaryBundle() async {
    try {
      Future<StaffSalaryBundle?> tryParse(Future<Map<String, dynamic>> future) async {
        final profileResult = await future;
        if (profileResult['success'] != true) return null;
        final data = profileResult['data'];
        if (data is! Map) return null;
        return staffSalaryBundleFromProfileData(
          Map<String, dynamic>.from(data),
        );
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
}

/// Debug: log preview MTD + contract month + working days (app_backend + web HRMS).
void _logPreviewSalaryNetGrossForTest({
  required Map<String, dynamic> response,
  required String source,
  required String employeeId,
  required int month,
  required int year,
}) {
  if (!kDebugMode) return;
  try {
    final data = response['data'];
    if (data is! Map) {
      _salaryLog(
        '[PreviewSalary][test] source=$source employeeId=$employeeId '
        'month=$month year=$year success=${response['success']} data=missing',
      );
      return;
    }
    final d = Map<String, dynamic>.from(data);
    final p = d['preview'];
    if (p is! Map) {
      _salaryLog(
        '[PreviewSalary][test] source=$source employeeId=$employeeId '
        'month=$month year=$year preview=null (no payroll preview in body)',
      );
      return;
    }
    final preview = Map<String, dynamic>.from(p);
    final mtdGross = preview['grossSalary'] ?? preview['gross'];
    final mtdNet =
        preview['netPay'] ?? preview['net'] ?? preview['netSalary'];

    num? monthGross;
    num? monthNet;
    final sb = preview['salaryBasis'];
    if (sb is Map) {
      final basis = Map<String, dynamic>.from(sb);
      monthGross = basis['monthlyGrossSalary'] as num?;
      monthNet = basis['monthlyNetSalary'] as num?;
    }

    int? workingDaysFullMonth;
    int? workingDaysTillDate;
    final att = preview['attendance'];
    if (att is Map) {
      final a = Map<String, dynamic>.from(att);
      workingDaysFullMonth =
          (a['fullMonthWorkingDays'] as num?)?.toInt() ??
              (a['workingDays'] as num?)?.toInt();
      workingDaysTillDate =
          (a['workingDaysTillCurrentDate'] as num?)?.toInt();
    }

    _salaryLog(
      '[PreviewSalary][test] source=$source employeeId=$employeeId '
      'month=$month year=$year '
      'mtdGross=$mtdGross mtdNet=$mtdNet '
      'monthGross=$monthGross monthNet=$monthNet '
      'workingDaysFullMonth=$workingDaysFullMonth '
      'workingDaysTillDate=$workingDaysTillDate',
    );
  } catch (e) {
    _salaryLog('[PreviewSalary][test] parse error: $e');
  }
}

/// Debug: full month + MTD + attendance working days from GET /payroll/stats.
void _logPayrollStatsForTest({
  required Map<String, dynamic> data,
  int? month,
  int? year,
}) {
  if (!kDebugMode) return;
  try {
    final m = month ?? (data['month'] as num?)?.toInt();
    final y = year ?? (data['year'] as num?)?.toInt();
    final stats = data['stats'];
    if (stats is! Map) {
      _salaryLog(
        '[PayrollStats][test] month=$m year=$y stats=null '
        'isProcessed=${data['isProcessed']}',
      );
      return;
    }
    final s = Map<String, dynamic>.from(stats);
    int? wdTill;
    int? wdFull;
    final att = s['attendance'];
    if (att is Map) {
      final a = Map<String, dynamic>.from(att);
      wdTill = (a['workingDays'] as num?)?.toInt();
      wdFull = (a['workingDaysFullMonth'] as num?)?.toInt();
    }
    _salaryLog(
      '[PayrollStats][test] month=$m year=$y '
      'monthGross=${s['grossSalary']} monthNet=${s['netSalary']} '
      'mtdGross=${s['thisMonthGross']} mtdNet=${s['thisMonthNet']} '
      'workingDaysTillToday=$wdTill workingDaysFullMonth=$wdFull',
    );
  } catch (e) {
    _salaryLog('[PayrollStats][test] parse error: $e');
  }
}
