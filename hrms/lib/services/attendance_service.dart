import 'dart:io';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dio/dio.dart';
import '../config/constants.dart';
import '../utils/error_message_utils.dart';
import 'api_client.dart';

class AttendanceService {
  final String baseUrl = AppConstants.baseUrl;
  final ApiClient _api = ApiClient();
  Map<String, dynamic>? attendanceTemplate;

  // Shared across all instances so Selfie Check-in (via BLoC) can use cache from Attendance tab.
  static Map<String, dynamic>? _cachedTodayAttendance;
  static DateTime? _lastTodayAttendanceFetch;

  // Cache for month attendance: key = "year-month", value = cached data
  final Map<String, Map<String, dynamic>> _cachedMonthAttendance = {};
  final Map<String, DateTime> _lastMonthAttendanceFetch = {};

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

  /// Call after check-in/check-out so Recent Activity and History never show
  /// cached data. Also call from the attendance screen before a forced refresh.
  /// Clears throttle for today endpoint so the next getAttendanceByDate(today) gets fresh data (e.g. punch out).
  void clearCachesForRefresh() {
    AttendanceService._cachedTodayAttendance = null;
    AttendanceService._lastTodayAttendanceFetch = null;
    _cachedMonthAttendance.clear();
    _lastMonthAttendanceFetch.clear();
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
      final body = <String, dynamic>{
        'latitude': lat,
        'longitude': lng,
        'address': address,
        'area': area,
        'city': city,
        'pincode': pincode,
        'selfie': selfie,
        'movementType': movementType,
        'source': 'app',
        'forceAppFine': true,
        'lateMinutes': lateMinutes,
        'earlyMinutes': earlyMinutes,
        'fineAmount': fineAmount,
      };
      if (businessId != null && businessId.isNotEmpty) {
        body['businessId'] = businessId;
      }
      final response = await _api.dio.post<Map<String, dynamic>>(
        '/attendance/checkin',
        data: body,
      );
      final data = response.data;
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
      final body = {
        'latitude': lat,
        'longitude': lng,
        'address': address,
        'area': area,
        'city': city,
        'pincode': pincode,
        'selfie': selfie,
        'movementType': movementType,
        'source': 'app',
        'forceAppFine': true,
        'lateMinutes': lateMinutes,
        'earlyMinutes': earlyMinutes,
        'fineAmount': fineAmount,
      };
      final response = await _api.dio.put<Map<String, dynamic>>(
        '/attendance/checkout',
        data: body,
      );
      final data = response.data;
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
      return {
        'success': false,
        'message': _dioErrorMessage(e) ?? _handleException(e),
      };
    } catch (e) {
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
  }) async {
    try {
      const endpointPath = '/attendance/today';
      final url = '$baseUrl$endpointPath';

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
      if (!forceRefresh && _cachedTodayAttendance != null) {
        return {'success': true, 'data': _cachedTodayAttendance};
      }

      // Throttle repeated calls within a short window
      if (_isThrottled(url)) {
        // If we have cache, return it, otherwise surface a friendly message
        if (_cachedTodayAttendance != null) {
          return {'success': true, 'data': _cachedTodayAttendance};
        }
        return {
          'success': false,
          'message': 'Too many requests. Please wait a moment.',
        };
      }

      final headers = await _getHeaders();
      final token = headers['Authorization']?.replaceFirst('Bearer ', '');
      if (token != null) _api.setAuthToken(token);
      final response = await _api.dio.get<Map<String, dynamic>>(endpointPath);
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
  Future<Map<String, dynamic>> getFineCalculation() async {
    try {
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
  }) async {
    return _getMonthAttendanceWithRetry(
      year,
      month,
      forceRefresh: forceRefresh,
      retryCount: 0,
    );
  }

  Future<Map<String, dynamic>> getEmployeeAttendance({
    required String employeeId,
    required String startDate,
    required String endDate,
    int page = 1,
    int limit = 100,
  }) async {
    try {
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
  }) async {
    final cacheKey = '$year-$month';
    try {
      final url = '$baseUrl/attendance/month?year=$year&month=$month';

      // Check cache first (unless forced refresh — never use cache after check-in/out)
      if (!forceRefresh && _cachedMonthAttendance.containsKey(cacheKey)) {
        final lastFetch = _lastMonthAttendanceFetch[cacheKey];
        if (lastFetch != null &&
            DateTime.now().difference(lastFetch) < _cacheValidDuration) {
          return {'success': true, 'data': _cachedMonthAttendance[cacheKey]};
        }
      }

      // Throttle repeated calls — when forceRefresh, never return cached data
      if (_isThrottled(url)) {
        if (!forceRefresh && _cachedMonthAttendance.containsKey(cacheKey)) {
          return {'success': true, 'data': _cachedMonthAttendance[cacheKey]};
        }
        if (retryCount == 0) {
          await Future.delayed(const Duration(milliseconds: 1500));
          return _getMonthAttendanceWithRetry(
            year,
            month,
            forceRefresh: forceRefresh,
            retryCount: 1,
          );
        }
        return {
          'success': false,
          'message': 'Too many requests. Please wait a moment.',
        };
      }

      final headers = await _getHeaders();
      final token = headers['Authorization']?.replaceFirst('Bearer ', '');
      if (token != null) _api.setAuthToken(token);
      final response = await _api.dio.get<Map<String, dynamic>>(
        '/attendance/month',
        queryParameters: {'year': year, 'month': month},
      );
      final data = response.data ?? {};
      final attendanceData = data['data'] ?? data;
      _cachedMonthAttendance[cacheKey] = attendanceData;
      _lastMonthAttendanceFetch[cacheKey] = DateTime.now();
      return {'success': true, 'data': attendanceData};
    } on DioException catch (e) {
      if (e.response?.statusCode == 429) {
        if (_cachedMonthAttendance.containsKey(cacheKey)) {
          return {'success': true, 'data': _cachedMonthAttendance[cacheKey]};
        }
        if (retryCount == 0) {
          await Future.delayed(const Duration(milliseconds: 2000));
          return _getMonthAttendanceWithRetry(
            year,
            month,
            forceRefresh: forceRefresh,
            retryCount: 1,
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
        );
      }
      if (_cachedMonthAttendance.containsKey(cacheKey)) {
        return {'success': true, 'data': _cachedMonthAttendance[cacheKey]};
      }
      return {
        'success': false,
        'message': _dioErrorMessage(e) ?? 'Failed to fetch month attendance',
      };
    } catch (e) {
      // On exception, return cached data if available
      if (_cachedMonthAttendance.containsKey(cacheKey)) {
        return {'success': true, 'data': _cachedMonthAttendance[cacheKey]};
      }
      // If no cache and first retry, wait and retry once
      if (retryCount == 0 && e is TimeoutException) {
        await Future.delayed(const Duration(milliseconds: 1000));
        return _getMonthAttendanceWithRetry(
          year,
          month,
          forceRefresh: forceRefresh,
          retryCount: 1,
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
