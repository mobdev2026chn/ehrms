import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/constants.dart';
import '../core/network/dio_client.dart';
import 'api_client.dart';
import 'auth_service.dart';
import 'interaction_service.dart';

final AuthService _salaryAuthServiceForAppPerDay = AuthService();

/// Per-day salary in SharedPreferences (fines, check-in preview). Written from web preview [salaryBasis].
const kAppNetPerDaySalaryPrefsKey = 'app_net_per_day_salary';
const kAppGrossPerDaySalaryPrefsKey = 'app_gross_per_day_salary';
const kAppLegacyPerDaySalaryPrefsKey = 'app_per_day_salary';

// Salary debug logs toggle.
// Set true when you need these verbose salary traces again.
const bool _kEnableSalaryVerboseLogs = false;

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

  Future<Map<String, dynamic>> getSalaryStats({int? month, int? year}) async {
    final token = await _authService.getToken();
    if (token == null) return _getEmptySalaryData();
    try {
      _api.setAuthToken(token);
      _salaryLog(
        '[SalaryOverview] GET /payroll/stats month=$month year=$year',
      );
      final response = await _api.dio.get<Map<String, dynamic>>(
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
      if (data != null && data['success'] == true) {
        final result = data['data'];
        if (result is Map) {
          final m = Map<String, dynamic>.from(result);
          _logPayrollStatsForTest(data: m, month: month, year: year);
          return m;
        }
        return _getEmptySalaryData();
      }
      return _getEmptySalaryData();
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return _getEmptySalaryData();
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
      _api.setAuthToken(token);
      final q = <String, dynamic>{
        'page': page ?? 1,
        'limit': limit ?? 10,
      };
      if (month != null) q['month'] = month;
      if (year != null) q['year'] = year;
      _salaryLog(
        '[SalaryOverview] GET /payroll query=$q',
      );
      final response = await _api.dio.get<Map<String, dynamic>>(
        '/payroll',
        queryParameters: q,
        options: Options(
          sendTimeout: _salaryRequestTimeout,
          receiveTimeout: _salaryRequestTimeout,
          extra: const {'disable_429_retry': true},
        ),
      );
      final data = response.data;
      if (data != null) return data;
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
      _api.setAuthToken(token);
      final path = download
          ? '/payroll/$payrollId/payslip/download'
          : '/payroll/$payrollId/payslip/view';
      _salaryLog('[SalaryOverview] GET $path');
      final response = await _api.dio.get<dynamic>(
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

  /// True when the geo app uses a different API host than [AppConstants.webBaseUrl].
  /// Then [previewPayroll] calls the TypeScript HRMS API (same as web) so the payload
  /// includes `salaryBasis`, `mockPayroll`, and template-linked `attendance`.
  static bool get _previewShouldUseWebHrmsHost {
    final main = AppConstants.baseUrl.replaceAll(RegExp(r'/+$'), '');
    final web = AppConstants.webBaseUrl.replaceAll(RegExp(r'/+$'), '');
    return main != web;
  }

  static Dio _webHrmsPreviewDio() {
    var base = AppConstants.webBaseUrl.replaceAll(RegExp(r'/+$'), '');
    if (base.endsWith('/')) base = base.substring(0, base.length - 1);
    final dio = Dio(
      BaseOptions(
        baseUrl: base,
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 45),
        sendTimeout: const Duration(seconds: 45),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );
    dio.interceptors.add(FormDataContentTypeInterceptor());
    dio.interceptors.add(RetryOnRateLimitInterceptor(dio));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final prefs = await SharedPreferences.getInstance();
          var t = InteractionService.normalizeAccessToken(
            prefs.getString(AppConstants.interactionAccessTokenPrefsKey),
          );
          t ??= InteractionService.normalizeAccessToken(prefs.getString('token'));
          if (t == null) {
            final auth = ApiClient().dio.options.headers['Authorization'];
            if (auth is String) {
              t = InteractionService.normalizeAccessToken(
                auth.startsWith('Bearer ') ? auth.substring(7) : auth,
              );
            }
          }
          if (t != null) {
            options.headers['Authorization'] = 'Bearer $t';
          }
          handler.next(options);
        },
      ),
    );
    return dio;
  }

  /// Web RTK `previewPayroll` / EmployeeSalaryOverview: tier 2 MTD (after processed payroll).
  /// When [baseUrl] ≠ [webBaseUrl], calls `POST` on the TS backend (`hrms.askeva.net`-style)
  /// so the response matches web (`salaryBasis`, per-day rates, `fullMonthWorkingDays`, etc.).
  /// Otherwise uses the current app API (e.g. app_backend).
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

    if (_previewShouldUseWebHrmsHost) {
      try {
        if (kDebugMode) {
          _salaryLog(
            '[SalaryOverview] POST ${AppConstants.webBaseUrl}/payroll/preview '
            'month=$month year=$year employeeId=$employeeId (web HRMS)',
          );
        }
        final r = await _webHrmsPreviewDio().post<Map<String, dynamic>>(
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
        if (kDebugMode) {
          _salaryLog(
            '[SalaryOverview] previewPayroll web HRMS error: ${e.message} — retry main API',
          );
        }
      }
    }

    final token = await _authService.getToken();
    if (token == null) {
      return {'success': false, 'data': null};
    }
    try {
      _api.setAuthToken(token);
      if (kDebugMode) {
        _salaryLog(
          '[SalaryOverview] POST /payroll/preview month=$month year=$year employeeId=$employeeId',
        );
      }
      final response = await _api.dio.post<Map<String, dynamic>>(
        '/payroll/preview',
        data: body,
        options: Options(
          sendTimeout: _salaryRequestTimeout,
          receiveTimeout: _salaryRequestTimeout,
          extra: const {'disable_429_retry': true},
        ),
      );
      final out = parseResponse(response);
      _logPreviewSalaryNetGrossForTest(
        response: out,
        source: 'mainApi',
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
      _salaryLog('[SalaryOverview] previewPayroll error: ${e.message}');
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
