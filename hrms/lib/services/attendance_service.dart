import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:dio/dio.dart';
import 'package:intl/intl.dart';
import '../config/constants.dart';
import '../utils/attendance_selfie_compress.dart';
import '../utils/error_message_utils.dart';
import '../utils/punch_flow_log.dart';
import 'api_client.dart';
import 'web_hrms_api_dio.dart';

class AttendanceService {
  final String baseUrl = AppConstants.baseUrl;
  final ApiClient _api = ApiClient();
  Map<String, dynamic>? attendanceTemplate;
  /// Punch sends large payloads (selfie); allow headroom vs default Dio (45s) and cloud upload latency.
  static const Duration _punchRequestTimeout = Duration(seconds: 60);

  Options _punchDioOptions() => Options(
        sendTimeout: _punchRequestTimeout,
        receiveTimeout: _punchRequestTimeout,
        connectTimeout: _punchRequestTimeout,
        extra: const {'disable_429_retry': true},
      );

  Uint8List _selfieDataUrlToJpegBytes(String dataUrl) {
    final comma = dataUrl.indexOf(',');
    final b64 = comma >= 0 ? dataUrl.substring(comma + 1) : dataUrl;
    return Uint8List.fromList(base64Decode(b64));
  }

  Map<String, dynamic> _stringifyPunchFormFields(Map<String, dynamic> src) {
    final out = <String, dynamic>{};
    src.forEach((k, v) {
      if (v == null) return;
      if (v is bool) {
        out[k] = v ? 'true' : 'false';
      } else if (v is num) {
        out[k] = v.toString();
      } else {
        out[k] = v.toString();
      }
    });
    return out;
  }

  // Shared across all instances so Selfie Check-in (via BLoC) can use cache from Attendance tab.
  static Map<String, dynamic>? _cachedTodayAttendance;
  static DateTime? _lastTodayAttendanceFetch;

  // Cache for month attendance: key = "year-month", value = cached data
  final Map<String, Map<String, dynamic>> _cachedMonthAttendance = {};
  final Map<String, DateTime> _lastMonthAttendanceFetch = {};

  /// [SalaryOverviewScreen] only — web HRMS month payload (isolated from geo cache above).
  final Map<String, Map<String, dynamic>> _cachedWebMonthAttendance = {};
  final Map<String, DateTime> _lastWebMonthAttendanceFetch = {};

  // Simple per-endpoint throttle map (URL -> last call time)
  static final Map<String, DateTime> _lastCallTimestamps = {};
  static const Duration _throttleDuration = Duration(
    seconds: 2,
  ); // Reduced from 3 to allow faster retries
  static const Duration _cacheValidDuration = Duration(minutes: 5);

  bool _isThrottled(String url) {
    final now = DateTime.now();
    final lastCall = _lastCallTimestamps[url];
    if (lastCall != null && now.difference(lastCall) < _throttleDuration) {
      return true;
    }
    _lastCallTimestamps[url] = now;
    return false;
  }

  int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  void _logPermissionConsumption(String action, dynamic responseData) {
    if (responseData is! Map) return;
    final data = responseData['data'];
    final Map<dynamic, dynamic> payload =
        data is Map ? data as Map : responseData as Map;

    final consumed = _asInt(payload['permissionConsumedMinutes']);
    final approved = _asInt(payload['permissionApprovedMinutes']);
    final lateUsed = _asInt(payload['permissionLateMinutes']);
    final earlyUsed = _asInt(payload['permissionEarlyMinutes']);
    final remaining = _asInt(payload['permissionRemainingMinutes']);

    if (consumed > 0) {
      punchFlowLog(
        '[Permission][$action][Consumed] consumed=$consumed approved=$approved '
        'lateUsed=$lateUsed earlyUsed=$earlyUsed remaining=$remaining',
      );
    } else if (approved > 0) {
      punchFlowLog(
        '[Permission][$action][ApprovedNoConsume] approved=$approved '
        'consumed=$consumed remaining=$remaining',
      );
    }
  }

  /// Call after check-in/check-out so Recent Activity and History never show
  /// cached data. Also call from the attendance screen before a forced refresh.
  /// Clears throttle for today endpoint so the next getAttendanceByDate(today) gets fresh data (e.g. punch out).
  void clearCachesForRefresh({bool clearWebHrmsSalaryCaches = false}) {
    AttendanceService._cachedTodayAttendance = null;
    AttendanceService._lastTodayAttendanceFetch = null;
    _cachedMonthAttendance.clear();
    _lastMonthAttendanceFetch.clear();
    if (clearWebHrmsSalaryCaches) {
      _cachedWebMonthAttendance.clear();
      _lastWebMonthAttendanceFetch.clear();
    }
    // So the next fetch for today is not throttled and the main card gets updated punch out
    final now = DateTime.now();
    final todayStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    AttendanceService._lastCallTimestamps.remove('$baseUrl/attendance/today?date=$todayStr');
    AttendanceService._lastCallTimestamps.remove('$baseUrl/attendance/today');
  }

  Future<Map<String, String>> _getHeaders() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token'); // This token is now the accessToken
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  Future<Map<String, dynamic>> checkIn(
    double lat,
    double lng,
    String address, {
    String? area,
    String? city,
    String? pincode,
    String? selfie,
    String? movementType,
    int? lateMinutes,
    int? earlyMinutes,
    double? fineAmount,
    int retryCount = 0,
  }) async {
    try {
      final headers = await _getHeaders();
      final token = headers['Authorization']?.replaceFirst('Bearer ', '');
      if (token != null) _api.setAuthToken(token);
      final prefs = await SharedPreferences.getInstance();
      final businessId = prefs.getString('businessId');
      String? selfiePayload = selfie;
      if (selfiePayload != null && selfiePayload.isNotEmpty) {
        selfiePayload =
            await AttendanceSelfieCompress.compressDataUrlForPunch(selfiePayload);
      }

      final jsonFields = <String, dynamic>{
        'latitude': lat,
        'longitude': lng,
        'address': address,
        'area': area,
        'city': city,
        'pincode': pincode,
        'movementType': movementType,
        'source': 'app',
        'forceAppFine': true,
        'lateMinutes': lateMinutes,
        'earlyMinutes': earlyMinutes,
        'fineAmount': fineAmount,
      };
      if (businessId != null && businessId.isNotEmpty) {
        jsonFields['businessId'] = businessId;
      }

      final Response<Map<String, dynamic>> response;
      if (selfiePayload != null && selfiePayload.isNotEmpty) {
        final bytes = _selfieDataUrlToJpegBytes(selfiePayload);
        final formMap = <String, dynamic>{
          ..._stringifyPunchFormFields(jsonFields),
          'selfie': MultipartFile.fromBytes(
            bytes,
            filename: 'attendance_selfie.jpg',
          ),
        };
        response = await _api.dio.post<Map<String, dynamic>>(
          '/attendance/checkin',
          data: FormData.fromMap(formMap),
          options: _punchDioOptions(),
        );
      } else {
        response = await _api.dio.post<Map<String, dynamic>>(
          '/attendance/checkin',
          data: <String, dynamic>{...jsonFields, 'selfie': selfiePayload},
          options: _punchDioOptions(),
        );
      }
      final data = response.data;
      _logPermissionConsumption('checkIn', data);
      clearCachesForRefresh();
      return {'success': true, 'data': data};
    } on DioException catch (e) {
      if (e.response == null &&
          retryCount == 0 &&
          _isTransientNetworkError(e)) {
        await Future.delayed(const Duration(milliseconds: 800));
        return checkIn(
          lat,
          lng,
          address,
          area: area,
          city: city,
          pincode: pincode,
          selfie: selfie,
          movementType: movementType,
          lateMinutes: lateMinutes,
          earlyMinutes: earlyMinutes,
          fineAmount: fineAmount,
          retryCount: 1,
        );
      }
      if (e.response != null) {
        final msg = _dioErrorMessage(e);
        return {'success': false, 'message': msg ?? 'Check-in failed'};
      }
      return {'success': false, 'message': _handleException(e)};
    } catch (e) {
      return {'success': false, 'message': _handleException(e)};
    }
  }

  String? _dioErrorMessage(DioException e) {
    if (e.response?.statusCode == 429) {
      return 'Too many requests. Please wait a moment.';
    }
    return ErrorMessageUtils.messageFromResponseData(e.response?.data);
  }

  Future<Map<String, dynamic>> checkOut(
    double lat,
    double lng,
    String address, {
    String? area,
    String? city,
    String? pincode,
    String? selfie,
    String? movementType,
    int? lateMinutes,
    int? earlyMinutes,
    double? fineAmount,
    int retryCount = 0,
  }) async {
    try {
      final headers = await _getHeaders();
      final token = headers['Authorization']?.replaceFirst('Bearer ', '');
      if (token != null) _api.setAuthToken(token);
      final prefs = await SharedPreferences.getInstance();
      final businessId = prefs.getString('businessId');
      final appPerDayNetSalary = prefs.getDouble('app_net_per_day_salary');
      final appPerdayGrossSalary = prefs.getDouble('app_gross_per_day_salary');
      String? selfiePayload = selfie;
      if (selfiePayload != null && selfiePayload.isNotEmpty) {
        selfiePayload =
            await AttendanceSelfieCompress.compressDataUrlForPunch(selfiePayload);
      }

      final jsonFields = <String, dynamic>{
        'latitude': lat,
        'longitude': lng,
        'address': address,
        'area': area,
        'city': city,
        'pincode': pincode,
        'movementType': movementType,
        'source': 'app',
        'forceAppFine': true,
        'lateMinutes': lateMinutes,
        'earlyMinutes': earlyMinutes,
        'fineAmount': fineAmount,
        if (businessId != null && businessId.isNotEmpty) 'businessId': businessId,
        if (appPerDayNetSalary != null && appPerDayNetSalary > 0)
          'appPerDayNetSalary': appPerDayNetSalary,
        if (appPerdayGrossSalary != null && appPerdayGrossSalary > 0)
          'appPerdayGrossSalary': appPerdayGrossSalary,
      };

      final Response<Map<String, dynamic>> response;
      if (selfiePayload != null && selfiePayload.isNotEmpty) {
        final bytes = _selfieDataUrlToJpegBytes(selfiePayload);
        final formMap = <String, dynamic>{
          ..._stringifyPunchFormFields(jsonFields),
          'selfie': MultipartFile.fromBytes(
            bytes,
            filename: 'attendance_selfie.jpg',
          ),
        };
        response = await _api.dio.put<Map<String, dynamic>>(
          '/attendance/checkout',
          data: FormData.fromMap(formMap),
          options: _punchDioOptions(),
        );
      } else {
        response = await _api.dio.put<Map<String, dynamic>>(
          '/attendance/checkout',
          data: <String, dynamic>{...jsonFields, 'selfie': selfiePayload},
          options: _punchDioOptions(),
        );
      }
      final data = response.data;
      _logPermissionConsumption('checkOut', data);
      punchFlowLog(
        '[AttendanceService][checkOut] httpOK status=${response.statusCode} '
        'dataKeys=${data is Map ? (data as Map).keys.join(",") : data.runtimeType}',
      );
      clearCachesForRefresh();
      return {'success': true, 'data': data};
    } on DioException catch (e) {
      if (e.response == null &&
          retryCount == 0 &&
          _isTransientNetworkError(e)) {
        await Future.delayed(const Duration(milliseconds: 800));
        return checkOut(
          lat,
          lng,
          address,
          area: area,
          city: city,
          pincode: pincode,
          selfie: selfie,
          movementType: movementType,
          lateMinutes: lateMinutes,
          earlyMinutes: earlyMinutes,
          fineAmount: fineAmount,
          retryCount: 1,
        );
      }
      final errMsg = _dioErrorMessage(e) ?? _handleException(e);
      punchFlowLog(
        '[AttendanceService][checkOut] DioException status=${e.response?.statusCode} '
        'message=$errMsg rawType=${e.response?.data.runtimeType}',
      );
      return {'success': false, 'message': errMsg};
    } catch (e) {
      punchFlowLog(
        '[AttendanceService][checkOut] catch message=${_handleException(e)}',
      );
      return {'success': false, 'message': _handleException(e)};
    }
  }

  bool _isTransientNetworkError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
        return true;
      default:
        return false;
    }
  }

  Future<Map<String, dynamic>> getTodayAttendance({
    bool forceRefresh = false,
    String? date,
    bool useWebHrmsApi = false,
  }) async {
    if (useWebHrmsApi) {
      try {
        final nowStr = date ?? DateFormat('yyyy-MM-dd').format(DateTime.now());
        final response = await webHrmsApiDio().get<Map<String, dynamic>>(
          '/attendance/today',
          queryParameters: {'date': nowStr},
        );
        final data = response.data ?? {};
        return {'success': true, 'data': data};
      } on DioException catch (e) {
        return {
          'success': false,
          'message': _dioErrorMessage(e) ?? 'Failed to fetch status',
        };
      } catch (e) {
        return {'success': false, 'message': _handleException(e)};
      }
    }
    try {
      final nowStr = date ?? DateFormat('yyyy-MM-dd').format(DateTime.now());
      const endpointPath = '/attendance/today';
      final url = '$baseUrl$endpointPath?date=$nowStr';

      // Invalidate cache if it's from a different day
      if (_cachedTodayAttendance != null) {
        final now = DateTime.now();
        final isSameDay =
            _lastTodayAttendanceFetch?.year == now.year &&
            _lastTodayAttendanceFetch?.month == now.month &&
            _lastTodayAttendanceFetch?.day == now.day;
        if (!isSameDay) {
          _cachedTodayAttendance = null;
        }
      }

      // Return cached value if available and not forced to refresh
      if (!forceRefresh && date == null && _cachedTodayAttendance != null) {
        return {'success': true, 'data': _cachedTodayAttendance};
      }

      // Throttle repeated calls within a short window. [forceRefresh] skips throttle so
      // post check-in/out refetches do not hit empty-cache "too many requests".
      if (date == null && !forceRefresh && _isThrottled(url)) {
        if (_cachedTodayAttendance != null) {
          return {'success': true, 'data': _cachedTodayAttendance};
        }
        return {
          'success': false,
          'message': 'Too many requests. Please wait a moment.',
        };
      }
      if (date == null && forceRefresh) {
        _lastCallTimestamps[url] = DateTime.now();
      }

      final headers = await _getHeaders();
      final token = headers['Authorization']?.replaceFirst('Bearer ', '');
      if (token != null) _api.setAuthToken(token);
// Fetching today's attendance data for the current user
      final response = await _api.dio.get<Map<String, dynamic>>(
        endpointPath,
        queryParameters: {'date': nowStr},
      );
      final data = response.data ?? {};

      if (data['template'] != null) {
        attendanceTemplate = data['template'];
      }
      _cachedTodayAttendance = data;
      _lastTodayAttendanceFetch = DateTime.now();
      return {'success': true, 'data': data};
    } on DioException catch (e) {
      if (e.response?.statusCode == 429) {
        if (_cachedTodayAttendance != null) {
          return {'success': true, 'data': _cachedTodayAttendance};
        }
        return {
          'success': false,
          'message': 'Too many requests. Please wait a moment.',
        };
      }
      return {
        'success': false,
        'message': _dioErrorMessage(e) ?? 'Failed to fetch status',
      };
    } catch (e) {
      return {'success': false, 'message': _handleException(e)};
    }
  }

  /// Fetches company fine calculation config and payslip settings (company.settings.payroll) using staff's businessId.
  /// Returns { success, data: fineCalculation, payslip: { isPayslipAutoGenerated? } } or { success, message }.
  Future<Map<String, dynamic>> getFineCalculation({
    bool useWebHrmsApi = false,
  }) async {
    try {
      if (useWebHrmsApi) {
        final response = await webHrmsApiDio().get<Map<String, dynamic>>(
          '/attendance/fine-calculation',
        );
        final data = response.data ?? {};
        final fineCalculation = data['data'];
        final payslip = data['payslip'];
        return {'success': true, 'data': fineCalculation, 'payslip': payslip};
      }
      final headers = await _getHeaders();
      final token = headers['Authorization']?.replaceFirst('Bearer ', '');
      if (token != null) _api.setAuthToken(token);
      final response =
          await _api.dio.get<Map<String, dynamic>>('/attendance/fine-calculation');
      final data = response.data ?? {};
      final fineCalculation = data['data'];
      final payslip = data['payslip'];
      return {'success': true, 'data': fineCalculation, 'payslip': payslip};
    } on DioException catch (e) {
      return {
        'success': false,
        'message': _dioErrorMessage(e) ?? 'Failed to fetch fine calculation',
      };
    } catch (e) {
      return {'success': false, 'message': _handleException(e)};
    }
  }

  Future<Map<String, dynamic>> getAttendanceByDate(String date) async {
    try {
      final url = '$baseUrl/attendance/today?date=$date';
      if (_isThrottled(url)) {
        // When opening Selfie Check-in right after Attendance tab, we often hit throttle.
        // If we have cached data for today, return it so the user doesn't see "Too many requests".
        final now = DateTime.now();
        final todayStr =
            '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
        if (date == todayStr && _cachedTodayAttendance != null) {
          return {'success': true, 'data': _cachedTodayAttendance!};
        }
        return {
          'success': false,
          'message': 'Too many requests. Please wait a moment.',
        };
      }
      final headers = await _getHeaders();
      final token = headers['Authorization']?.replaceFirst('Bearer ', '');
      if (token != null) _api.setAuthToken(token);
      // Send device current time so server can evaluate half-day leave (Intl timezone can be wrong on server)
      final deviceNow = DateTime.now();
      final clientTimeIso = deviceNow.toUtc().toIso8601String();
      final clientLocalTime = '${deviceNow.hour.toString().padLeft(2, '0')}:${deviceNow.minute.toString().padLeft(2, '0')}';
      final response = await _api.dio.get<Map<String, dynamic>>(
        '/attendance/today',
        queryParameters: {'date': date, 'clientTime': clientTimeIso, 'clientLocalTime': clientLocalTime},
      );
      final data = response.data ?? {};
      // Share cache with getTodayAttendance so throttle/cache hits can return this data.
      final now = DateTime.now();
      final todayStr =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      if (date == todayStr) {
        _cachedTodayAttendance = data;
        _lastTodayAttendanceFetch = DateTime.now();
      }
      return {'success': true, 'data': data};
    } on DioException catch (e) {
      if (e.response?.statusCode == 429) {
        // On server 429, return cached today data if we have it so Selfie Check-in can still show status.
        final now = DateTime.now();
        final todayStr =
            '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
        if (date == todayStr && _cachedTodayAttendance != null) {
          return {'success': true, 'data': _cachedTodayAttendance!};
        }
        return {
          'success': false,
          'message': 'Too many requests. Please wait a moment.',
        };
      }
      return {
        'success': false,
        'message': _dioErrorMessage(e) ?? 'Failed to fetch attendance',
      };
    } catch (e) {
      return {'success': false, 'message': _handleException(e)};
    }
  }

  Future<Map<String, dynamic>> getAttendanceHistory({
    int page = 1,
    int limit = 10,
    String? date,
  }) async {
    try {
      String url = '$baseUrl/attendance/history?page=$page&limit=$limit';
      if (date != null) {
        url += '&date=$date';
      }

      if (_isThrottled(url)) {
        return {
          'success': false,
          'message': 'Too many requests. Please wait a moment.',
        };
      }
      final headers = await _getHeaders();
      final token = headers['Authorization']?.replaceFirst('Bearer ', '');
      if (token != null) _api.setAuthToken(token);
      final response = await _api.dio.get<Map<String, dynamic>>(
        '/attendance/history',
        queryParameters: {
          'page': page,
          'limit': limit,
          if (date != null) 'date': date,
        },
      );
      final raw = response.data ?? <String, dynamic>{};

      // Normalize both legacy and wrapped API response shapes to:
      // { data: { data: <list>, pagination: <map> } }
      Map<String, dynamic> payload;
      if (raw['data'] is Map<String, dynamic>) {
        final nested = raw['data'] as Map<String, dynamic>;
        payload = {
          'data': nested['data'] is List ? nested['data'] : <dynamic>[],
          'pagination': nested['pagination'] is Map<String, dynamic>
              ? nested['pagination']
              : <String, dynamic>{},
        };
      } else {
        payload = {
          'data': raw['data'] is List ? raw['data'] : <dynamic>[],
          'pagination': raw['pagination'] is Map<String, dynamic>
              ? raw['pagination']
              : <String, dynamic>{},
        };
      }

      return {'success': true, 'data': payload};
    } on DioException catch (e) {
      if (e.response?.statusCode == 429) {
        return {
          'success': false,
          'message': 'Too many requests. Please wait a moment.',
        };
      }
      return {
        'success': false,
        'message': _dioErrorMessage(e) ?? 'Failed to fetch history',
      };
    } catch (e) {
      return {'success': false, 'message': _handleException(e)};
    }
  }

  Future<Map<String, dynamic>> getMonthAttendance(
    int year,
    int month, {
    bool forceRefresh = false,
    bool useWebHrmsApi = false,
  }) async {
    return _getMonthAttendanceWithRetry(
      year,
      month,
      forceRefresh: forceRefresh,
      retryCount: 0,
      useWebHrmsApi: useWebHrmsApi,
    );
  }

  Future<Map<String, dynamic>> getEmployeeAttendance({
    required String employeeId,
    required String startDate,
    required String endDate,
    int page = 1,
    int limit = 100,
    bool useWebHrmsApi = false,
  }) async {
    try {
      if (useWebHrmsApi) {
        final response = await webHrmsApiDio().get<Map<String, dynamic>>(
          '/attendance/employee/$employeeId',
          queryParameters: {
            'startDate': startDate,
            'endDate': endDate,
            'page': page,
            'limit': limit,
          },
        );
        final data = response.data ?? {};
        if (data['success'] == true && data['data'] is Map) {
          return {'success': true, 'data': data['data']};
        }
        return {'success': false, 'message': 'Failed to fetch employee attendance'};
      }
      final headers = await _getHeaders();
      final token = headers['Authorization']?.replaceFirst('Bearer ', '');
      if (token != null) _api.setAuthToken(token);
      final response = await _api.dio.get<Map<String, dynamic>>(
        '/attendance/employee/$employeeId',
        queryParameters: {
          'startDate': startDate,
          'endDate': endDate,
          'page': page,
          'limit': limit,
        },
      );
      final data = response.data ?? {};
      if (data['success'] == true && data['data'] is Map) {
        return {'success': true, 'data': data['data']};
      }
      return {'success': false, 'message': 'Failed to fetch employee attendance'};
    } on DioException catch (e) {
      return {
        'success': false,
        'message': _dioErrorMessage(e) ?? 'Failed to fetch employee attendance',
      };
    } catch (e) {
      return {'success': false, 'message': _handleException(e)};
    }
  }

  Future<Map<String, dynamic>> _getMonthAttendanceWithRetry(
    int year,
    int month, {
    bool forceRefresh = false,
    int retryCount = 0,
    bool useWebHrmsApi = false,
  }) async {
    final cacheKey = '$year-$month';
    final cacheMap =
        useWebHrmsApi ? _cachedWebMonthAttendance : _cachedMonthAttendance;
    final fetchMap =
        useWebHrmsApi ? _lastWebMonthAttendanceFetch : _lastMonthAttendanceFetch;
    final webBase = AppConstants.webBaseUrl.replaceAll(RegExp(r'/+$'), '');
    try {
      final url = useWebHrmsApi
          ? '$webBase/attendance/month?year=$year&month=$month'
          : '$baseUrl/attendance/month?year=$year&month=$month';

      // Check cache first (unless forced refresh — never use cache after check-in/out)
      if (!forceRefresh && cacheMap.containsKey(cacheKey)) {
        final lastFetch = fetchMap[cacheKey];
        if (lastFetch != null &&
            DateTime.now().difference(lastFetch) < _cacheValidDuration) {
          return {'success': true, 'data': cacheMap[cacheKey]};
        }
      }

      // Throttle repeated calls — when forceRefresh, never return cached data
      if (_isThrottled(url)) {
        if (!forceRefresh && cacheMap.containsKey(cacheKey)) {
          return {'success': true, 'data': cacheMap[cacheKey]};
        }
        if (retryCount == 0) {
          await Future.delayed(const Duration(milliseconds: 1500));
          return _getMonthAttendanceWithRetry(
            year,
            month,
            forceRefresh: forceRefresh,
            retryCount: 1,
            useWebHrmsApi: useWebHrmsApi,
          );
        }
        return {
          'success': false,
          'message': 'Too many requests. Please wait a moment.',
        };
      }

      final Map<String, dynamic> data;
      if (useWebHrmsApi) {
        final response = await webHrmsApiDio().get<Map<String, dynamic>>(
          '/attendance/month',
          queryParameters: {'year': year, 'month': month},
        );
        data = response.data ?? {};
      } else {
        final headers = await _getHeaders();
        final token = headers['Authorization']?.replaceFirst('Bearer ', '');
        if (token != null) _api.setAuthToken(token);
        final response = await _api.dio.get<Map<String, dynamic>>(
          '/attendance/month',
          queryParameters: {'year': year, 'month': month},
        );
        data = response.data ?? {};
      }
      final attendanceData = data['data'] ?? data;
      cacheMap[cacheKey] = attendanceData;
      fetchMap[cacheKey] = DateTime.now();
      return {'success': true, 'data': attendanceData};
    } on DioException catch (e) {
      if (e.response?.statusCode == 429) {
        if (cacheMap.containsKey(cacheKey)) {
          return {'success': true, 'data': cacheMap[cacheKey]};
        }
        if (retryCount == 0) {
          await Future.delayed(const Duration(milliseconds: 2000));
          return _getMonthAttendanceWithRetry(
            year,
            month,
            forceRefresh: forceRefresh,
            retryCount: 1,
            useWebHrmsApi: useWebHrmsApi,
          );
        }
        return {
          'success': false,
          'message': 'Too many requests. Please wait a moment.',
        };
      }
      if (retryCount == 0 && _isTransientNetworkError(e)) {
        await Future.delayed(const Duration(milliseconds: 1000));
        return _getMonthAttendanceWithRetry(
          year,
          month,
          forceRefresh: forceRefresh,
          retryCount: 1,
          useWebHrmsApi: useWebHrmsApi,
        );
      }
      if (cacheMap.containsKey(cacheKey)) {
        return {'success': true, 'data': cacheMap[cacheKey]};
      }
      return {
        'success': false,
        'message': _dioErrorMessage(e) ?? 'Failed to fetch month attendance',
      };
    } catch (e) {
      // On exception, return cached data if available
      if (cacheMap.containsKey(cacheKey)) {
        return {'success': true, 'data': cacheMap[cacheKey]};
      }
      // If no cache and first retry, wait and retry once
      if (retryCount == 0 && e is TimeoutException) {
        await Future.delayed(const Duration(milliseconds: 1000));
        return _getMonthAttendanceWithRetry(
          year,
          month,
          forceRefresh: forceRefresh,
          retryCount: 1,
          useWebHrmsApi: useWebHrmsApi,
        );
      }
      return {'success': false, 'message': _handleException(e)};
    }
  }

  String _handleException(dynamic error) {
    if (error is DioException) {
      if (error.response != null) {
        return _dioErrorMessage(error) ?? 'Request failed';
      }
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          return 'Connection timed out. The server is taking too long to respond. Please try again.';
        case DioExceptionType.connectionError:
          return 'Connection error. Please check your internet connection and try again.';
        default:
          break;
      }
    }
    if (error is SocketException) {
      // SocketException can occur even with internet if server is unreachable
      // Check error message to provide more specific feedback
      String errorMsg = error.message.toLowerCase();
      if (errorMsg.contains('failed host lookup') ||
          errorMsg.contains('name resolution') ||
          errorMsg.contains('nodename nor servname provided')) {
        return 'Unable to reach server. Please check your internet connection or contact support if the problem persists.';
      } else if (errorMsg.contains('connection refused') ||
          errorMsg.contains('connection reset')) {
        return 'Server is not responding. Please try again in a moment or contact support.';
      } else {
        return 'Connection error. Please check your internet connection and try again.';
      }
    } else if (error is TimeoutException) {
      return 'Connection timed out. The server is taking too long to respond. Please try again.';
    } else if (error is FormatException) {
      return 'Invalid response format from server. Please try again.';
    }

    String msg = error.toString();
    if (msg.startsWith('Exception: ')) {
      msg = msg.substring(11);
    }
    return msg;
  }
}
