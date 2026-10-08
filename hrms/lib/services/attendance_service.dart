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
import '../utils/salary_fine_summary.dart';
import 'api_client.dart';
import 'auth_service.dart';
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

  /// Drop every cached / in-flight attendance read. These are static (shared by all
  /// instances), so without this a user logging in on the same phone saw the
  /// previous user's today and month attendance until the caches expired.
  static void resetForNewUser() {
    _fineCalcCache = null;
    _fineCalcAt = null;
    _cachedTodayAttendance = null;
    _lastTodayAttendanceFetch = null;
    _cachedMonthAttendance.clear();
    _lastMonthAttendanceFetch.clear();
    _lastCallTimestamps.clear();
    _todayInFlight = null;
    _inFlightMonthRequests.clear();
  }
  static DateTime? _lastTodayAttendanceFetch;

  // Cache for month attendance: key = "year-month", value = cached data.
  // STATIC (shared across instances) — same as the today cache above and the
  // _lastCallTimestamps throttle below. This is the fix for "current month loads
  // blank but last month works": the Dashboard and Attendance screens each build
  // their own AttendanceService. The throttle is shared, so the Dashboard's
  // current-month fetch throttles the URL for everyone — but when this cache was
  // per-instance, the Attendance screen's empty instance cache had nothing to fall
  // back on while throttled, so its current-month fetch failed. Sharing the cache
  // lets the Attendance screen reuse the data the Dashboard already fetched.
  static final Map<String, Map<String, dynamic>> _cachedMonthAttendance = {};
  static final Map<String, DateTime> _lastMonthAttendanceFetch = {};

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
  ///
  /// [clearMonth] controls whether the month-attendance cache (calendar coloring) is
  /// wiped. Default true (post-punch / explicit refresh). Pass false when only the
  /// today/profile data needs to be fresh — e.g. the routine template fetch on every
  /// tab open. Wiping the month cache there threw away data the Dashboard had just
  /// loaded, forcing the Attendance calendar to re-fetch from scratch and sit blank
  /// for a few seconds on open.
  /// Today's data in the getAttendanceByDate envelope when it was fetched within
  /// [maxAge] (e.g. the shell/Home just loaded it), else null.
  Map<String, dynamic>? freshTodayByDateEnvelope({Duration maxAge = const Duration(seconds: 30)}) {
    final at = _lastTodayAttendanceFetch;
    final cached = _cachedTodayAttendance;
    if (cached == null || at == null || DateTime.now().difference(at) > maxAge) return null;
    return {'success': true, 'data': _asAttendanceByDateEnvelope(cached)};
  }

  void clearCachesForRefresh({
    bool clearWebHrmsSalaryCaches = false,
    bool clearMonth = true,
  }) {
    AttendanceService._cachedTodayAttendance = null;
    AttendanceService._lastTodayAttendanceFetch = null;
    if (clearMonth) {
      _cachedMonthAttendance.clear();
      _lastMonthAttendanceFetch.clear();
    }
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
    String? clientTime,
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

      // Button-tap instant; the server stores this as punchIn so selfie/network
      // latency does not push the saved time forward. Falls back to now if absent.
      final punchInTime = (clientTime != null && clientTime.isNotEmpty)
          ? clientTime
          : DateTime.now().toUtc().toIso8601String();

      final jsonFields = <String, dynamic>{
        'latitude': lat,
        'longitude': lng,
        'accuracy': 15.0,
        'locationName': address,
        'address': address,
        'area': area,
        'city': city,
        'pincode': pincode,
        'movementType': movementType,
        'source': 'app',
        'forceAppFine': false,
        'lateMinutes': lateMinutes,
        'earlyMinutes': earlyMinutes,
        'fineAmount': fineAmount,
        'punchInTime': punchInTime,
        'clientTime': punchInTime,
        'device': 'Mobile App',
      };
      if (businessId != null && businessId.isNotEmpty) {
        jsonFields['businessId'] = businessId;
      }

      Response<Map<String, dynamic>> response;
      final bodyData = <String, dynamic>{...jsonFields, 'selfie': selfiePayload};

      try {
        response = await _api.dio.post<Map<String, dynamic>>(
          '/staff/attendance/punch-in',
          data: bodyData,
          options: _punchDioOptions(),
        );
      } catch (punchErr) {
        if (punchErr is DioException) {
          final code = punchErr.response?.statusCode;
          if (code == 413) {
            final noSelfieData = await AttendanceSelfieCompress.withSmallSelfie(bodyData);
            response = await _api.dio.post<Map<String, dynamic>>(
              '/staff/attendance/punch-in',
              data: noSelfieData,
              options: _punchDioOptions(),
            );
          } else if (code == 404 || code == 405) {
            response = await _api.dio.post<Map<String, dynamic>>(
              '/attendance/checkin',
              data: bodyData,
              options: _punchDioOptions(),
            );
          } else {
            rethrow;
          }
        } else {
          rethrow;
        }
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
          clientTime: clientTime,
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
    String? clientTime,
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

      // Button-tap instant; the server stores this as punchOut so selfie/network
      // latency does not push the saved time (and work hours) forward.
      final punchOutTime = (clientTime != null && clientTime.isNotEmpty)
          ? clientTime
          : DateTime.now().toUtc().toIso8601String();

      final jsonFields = <String, dynamic>{
        'latitude': lat,
        'longitude': lng,
        'accuracy': 15.0,
        'locationName': address,
        'address': address,
        'area': area,
        'city': city,
        'pincode': pincode,
        'movementType': movementType,
        'source': 'app',
        'forceAppFine': false,
        'lateMinutes': lateMinutes,
        'earlyMinutes': earlyMinutes,
        'fineAmount': fineAmount,
        'punchOutTime': punchOutTime,
        'clientTime': punchOutTime,
        'device': 'Mobile App',
        if (businessId != null && businessId.isNotEmpty) 'businessId': businessId,
        if (appPerDayNetSalary != null && appPerDayNetSalary > 0)
          'appPerDayNetSalary': appPerDayNetSalary,
        if (appPerdayGrossSalary != null && appPerdayGrossSalary > 0)
          'appPerdayGrossSalary': appPerdayGrossSalary,
      };

      Response<Map<String, dynamic>> response;
      final bodyData = <String, dynamic>{...jsonFields, 'selfie': selfiePayload};

      try {
        response = await _api.dio.post<Map<String, dynamic>>(
          '/staff/attendance/punch-out',
          data: bodyData,
          options: _punchDioOptions(),
        );
      } catch (punchErr) {
        if (punchErr is DioException) {
          final code = punchErr.response?.statusCode;
          if (code == 413) {
            final noSelfieData = await AttendanceSelfieCompress.withSmallSelfie(bodyData);
            response = await _api.dio.post<Map<String, dynamic>>(
              '/staff/attendance/punch-out',
              data: noSelfieData,
              options: _punchDioOptions(),
            );
          } else if (code == 404 || code == 405) {
            response = await _api.dio.put<Map<String, dynamic>>(
              '/attendance/checkout',
              data: bodyData,
              options: _punchDioOptions(),
            );
          } else {
            rethrow;
          }
        } else {
          rethrow;
        }
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
          clientTime: clientTime,
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

  /// Shared in-flight today request: the shell, Home and Attendance all ask for
  /// today's punch at startup; collapse them into one network call.
  static Future<Map<String, dynamic>>? _todayInFlight;

  Future<Map<String, dynamic>> getTodayAttendance({
    bool forceRefresh = false,
    String? date,
    bool useWebHrmsApi = false,
  }) {
    if (useWebHrmsApi || date != null) {
      return _getTodayAttendanceImpl(
        forceRefresh: forceRefresh,
        date: date,
        useWebHrmsApi: useWebHrmsApi,
      );
    }
    final last = _lastTodayAttendanceFetch;
    if (_cachedTodayAttendance != null &&
        last != null &&
        DateTime.now().difference(last) < const Duration(seconds: 3)) {
      return Future.value({'success': true, 'data': _cachedTodayAttendance});
    }
    final pending = _todayInFlight;
    if (pending != null) return pending;
    final future = _getTodayAttendanceImpl(forceRefresh: forceRefresh);
    _todayInFlight = future;
    future.whenComplete(() {
      if (identical(_todayInFlight, future)) _todayInFlight = null;
    });
    return future;
  }

  static bool _isMissingRoute(Object e) {
    if (e is! DioException) return false;
    final code = e.response?.statusCode;
    return code == 404 || code == 405;
  }

  /// Converts a shift clock time ("09:30", "9:30 AM", "18:30:00") to "HH:mm"
  /// (24h), which is what the screens parse. Null when it can't be read.
  static String? _shiftTimeToHHmm(dynamic value) {
    final s = value?.toString().trim() ?? '';
    if (s.isEmpty || s.toLowerCase() == 'null') return null;
    final m = RegExp(
      r'^(\d{1,2}):(\d{2})(?::\d{2})?\s*(AM|PM)?$',
      caseSensitive: false,
    ).firstMatch(s);
    if (m == null) return null;
    var h = int.parse(m.group(1)!);
    final min = int.parse(m.group(2)!);
    final period = m.group(3)?.toUpperCase();
    if (period == 'PM' && h < 12) h += 12;
    if (period == 'AM' && h == 12) h = 0;
    if (h > 23 || min > 59) return null;
    return '${h.toString().padLeft(2, '0')}:${min.toString().padLeft(2, '0')}';
  }

  /// Normalizes a `/staff/attendance/today-punch` payload (the `data` object of
  /// the response) in place to the keys the mobile screens read.
  ///
  /// The server resolves today's shift (`data.shift` = roster/override/staff
  /// shift template with name/startTime/endTime); it is copied onto the merged
  /// `template` as `shiftName`/`shiftStartTime`/`shiftEndTime`, which is where
  /// the attendance screens read shift timings from.
  void _normalizeTodayPunchPayload(Map<String, dynamic> data) {
    final isPunchedIn = data['isPunchedIn'] == true;
    final isPunchedOut = data['isPunchedOut'] == true;
    data['checkedIn'] = isPunchedIn && !isPunchedOut;
    data['hasPunchIn'] = isPunchedIn;
    data['hasPunchOut'] = isPunchedOut;

    final checkInTime = data['checkInTime'] ?? data['punchIn'];
    final checkOutTime = data['checkOutTime'] ?? data['punchOut'];
    if (checkInTime != null && checkInTime.toString().trim() != 'NA') {
      data['punchIn'] = checkInTime;
    }
    if (checkOutTime != null && checkOutTime.toString().trim() != 'NA') {
      data['punchOut'] = checkOutTime;
    }

    final isWeekOff = data['isWeekOff'] == true || data['isWeeklyOff'] == true;
    final isHoliday = data['isHoliday'] == true;
    data['isWeeklyOff'] = isWeekOff;
    data['isWeekOff'] = isWeekOff;
    data['isHoliday'] = isHoliday;
    if (data['isOnLeave'] == null && data['isLeave'] is bool) {
      data['isOnLeave'] = data['isLeave'];
    }

    if (data['attendanceTemplate'] != null && data['template'] == null) {
      data['template'] = data['attendanceTemplate'];
    }

    // Today's assigned shift, as resolved by the server.
    final shiftRaw = data['shift'];
    final shift = shiftRaw is Map ? Map<String, dynamic>.from(shiftRaw) : null;
    if (data['shiftAssigned'] == null) {
      final setup = data['setupStatus'];
      data['shiftAssigned'] = (setup is Map && setup['shiftAssigned'] is bool)
          ? setup['shiftAssigned']
          : shift != null;
    }
    if (shift != null) {
      final start = _shiftTimeToHHmm(shift['startTime']);
      final end = _shiftTimeToHHmm(shift['endTime']);
      final name = shift['name']?.toString().trim();
      if (start != null && end != null) {
        final tmplRaw = data['template'];
        final tmpl = tmplRaw is Map
            ? Map<String, dynamic>.from(tmplRaw)
            : <String, dynamic>{};
        tmpl['shiftStartTime'] = start;
        tmpl['shiftEndTime'] = end;
        data['shiftStartTime'] = start;
        data['shiftEndTime'] = end;
        if (name != null && name.isNotEmpty) {
          tmpl['shiftName'] = name;
          data['shiftName'] = name;
        }
        data['template'] = tmpl;
      }
    }

    if (data['template'] != null) {
      attendanceTemplate = data['template'];
    }

    // Today's backend-calculated fine (today-punch `fineAdjustment` / `totalFine`),
    // on the same keys as the month records.
    applyServerFineFields(data);
    if (data['attendance'] is Map) {
      final att = Map<String, dynamic>.from(data['attendance'] as Map);
      applyServerFineFields(att);
      data['attendance'] = att;
    }

    if (data['status'] == null || data['status'].toString().isEmpty) {
      if (isWeekOff) {
        data['status'] = 'Week Off';
      } else if (isHoliday) {
        data['status'] = 'Holiday';
      } else if (isPunchedIn) {
        data['status'] = 'Present';
      }
    }
  }

  /// Callers of [getAttendanceByDate] read the legacy envelope: flags
  /// (`template`, `isWeeklyOff`, `checkedIn`, ...) at the top level and the day's
  /// record under `data`. Builds that from a flat normalized today-punch map.
  static Map<String, dynamic> _asAttendanceByDateEnvelope(
    Map<String, dynamic> flat,
  ) {
    if (flat['data'] is Map) return flat;
    return {...flat, 'data': Map<String, dynamic>.from(flat)};
  }

  Future<Map<String, dynamic>> _getTodayAttendanceImpl({
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

      // Primary: Web API Canonical endpoint /staff/attendance/today-punch
      Response<dynamic>? response;
      try {
        response = await _api.dio.get<dynamic>('/staff/attendance/today-punch');
      } catch (e) {
        // Only fall back when the route is missing — retrying legacy routes on a
        // timeout just tripled the wait before the error surfaced.
        if (!_isMissingRoute(e)) rethrow;
        try {
          response = await _api.dio.get<dynamic>(
            '/attendance/today',
            queryParameters: {'date': nowStr},
          );
        } catch (e2) {
          if (!_isMissingRoute(e2)) rethrow;
          response = await _api.dio.get<dynamic>(
            '/staff/attendance/today',
            queryParameters: {'date': nowStr},
          );
        }
      }

      final dynamic raw = response?.data;
      final Map<String, dynamic> rawMap =
          raw is Map ? Map<String, dynamic>.from(raw) : {};
      final dynamic innerData = rawMap['data'] ?? rawMap;
      final Map<String, dynamic> data =
          innerData is Map ? Map<String, dynamic>.from(innerData) : {};

      // Normalize web today-punch fields to standard mobile app keys
      _normalizeTodayPunchPayload(data);

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
  /// Company fine/payslip config changes rarely; Dashboard, Attendance and Salary
  /// each asked for it on open. One shared result for 10 min, one request in flight.
  static Map<String, dynamic>? _fineCalcCache;
  static DateTime? _fineCalcAt;
  static Future<Map<String, dynamic>>? _fineCalcInFlight;

  Future<Map<String, dynamic>> getFineCalculation({
    bool useWebHrmsApi = false,
  }) {
    final at = _fineCalcAt;
    if (_fineCalcCache != null && at != null && DateTime.now().difference(at) < const Duration(minutes: 10)) {
      return Future.value(_fineCalcCache!);
    }
    return _fineCalcInFlight ??= _getFineCalculationImpl(useWebHrmsApi: useWebHrmsApi).then((r) {
      if (r['success'] == true) {
        _fineCalcCache = r;
        _fineCalcAt = DateTime.now();
      }
      return r;
    }).whenComplete(() => _fineCalcInFlight = null);
  }

  Future<Map<String, dynamic>> _getFineCalculationImpl({
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
          return {'success': true, 'data': _asAttendanceByDateEnvelope(_cachedTodayAttendance!)};
        }
        if (_cachedTodayAttendance != null) {
          return {'success': true, 'data': _asAttendanceByDateEnvelope(_cachedTodayAttendance!)};
        }
        return {
          'success': true,
          'data': <String, dynamic>{},
        };
      }
      final headers = await _getHeaders();
      final token = headers['Authorization']?.replaceFirst('Bearer ', '');
      if (token != null) _api.setAuthToken(token);
      // Send device current time so server can evaluate half-day leave (Intl timezone can be wrong on server)
      final deviceNow = DateTime.now();
      final clientTimeIso = deviceNow.toUtc().toIso8601String();
      final clientLocalTime = '${deviceNow.hour.toString().padLeft(2, '0')}:${deviceNow.minute.toString().padLeft(2, '0')}';
      Response<dynamic> response;
      try {
        response = await _api.dio.get<dynamic>(
          '/staff/attendance/today-punch',
          queryParameters: {'date': date, 'clientTime': clientTimeIso, 'clientLocalTime': clientLocalTime},
        );
      } on DioException catch (e1) {
        if (!_isMissingRoute(e1)) rethrow;
        response = await _api.dio.get<dynamic>(
          '/attendance/today',
          queryParameters: {'date': date, 'clientTime': clientTimeIso, 'clientLocalTime': clientLocalTime},
        );
      }
      final body = response.data is Map ? Map<String, dynamic>.from(response.data as Map) : <String, dynamic>{};
      // today-punch wraps its payload as { success, data: {...} }; unwrap and
      // normalize it (shift, week-off, holiday, punch keys) so callers reading
      // top-level fields see the real values instead of null/defaults.
      final inner = body['data'];
      final isTodayPunch = inner is Map &&
          (inner.containsKey('isPunchedIn') ||
              inner.containsKey('setupStatus') ||
              inner.containsKey('shift'));
      Map<String, dynamic> flat = body;
      if (isTodayPunch) {
        flat = Map<String, dynamic>.from(inner);
        _normalizeTodayPunchPayload(flat);
      }
      final data = isTodayPunch ? _asAttendanceByDateEnvelope(flat) : body;
      // Share cache with getTodayAttendance so throttle/cache hits can return this data.
      final now = DateTime.now();
      final todayStr =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      if (date == todayStr) {
        _cachedTodayAttendance = flat;
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
          return {'success': true, 'data': _asAttendanceByDateEnvelope(_cachedTodayAttendance!)};
        }
        if (_cachedTodayAttendance != null) {
          return {'success': true, 'data': _asAttendanceByDateEnvelope(_cachedTodayAttendance!)};
        }
        return {
          'success': true,
          'data': <String, dynamic>{},
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

  // In-flight month requests keyed by "year-month-(app|web)". The Attendance
  // screen fires several month fetches at once on open (_initData + the
  // didUpdateWidget refresh), on filter taps, and on month navigation. Without
  // coalescing, the 2nd+ identical call hit the 2s client throttle and came back
  // as a hard "Too many requests" failure, leaving the calendar with no colored
  // markings until the user interacted again. Sharing one in-flight Future makes
  // the calendar populate on a single pass.
  // STATIC so concurrent fetches from DIFFERENT screens (Dashboard + Attendance,
  // which each build their own AttendanceService) coalesce onto a single network
  // request instead of the second one tripping the shared throttle and failing.
  static final Map<String, Future<Map<String, dynamic>>> _inFlightMonthRequests =
      {};

  Future<Map<String, dynamic>> getMonthAttendance(
    int year,
    int month, {
    bool forceRefresh = false,
    bool useWebHrmsApi = false,
  }) {
    final key = '$year-$month-${useWebHrmsApi ? 'web' : 'app'}';

    // Reuse an in-flight identical request. A forceRefresh (after punch in/out)
    // must not piggy-back on a possibly-stale in-flight read, so it always starts
    // its own call.
    final existing = _inFlightMonthRequests[key];
    if (existing != null && !forceRefresh) {
      return existing;
    }

    final future = _getMonthAttendanceWithRetry(
      year,
      month,
      forceRefresh: forceRefresh,
      retryCount: 0,
      useWebHrmsApi: useWebHrmsApi,
    );
    _inFlightMonthRequests[key] = future;
    // Only clear the slot if this exact future still owns it (a later forceRefresh
    // may have replaced it).
    future.whenComplete(() {
      if (identical(_inFlightMonthRequests[key], future)) {
        _inFlightMonthRequests.remove(key);
      }
    });
    return future;
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

      // Throttle repeated calls. When throttled we cannot fetch fresh right now, so
      // serve cached data for this month if we have any — a few-minutes-old calendar
      // beats a blank one. This is the fix for the "current month loads blank but last
      // month works" report: the dashboard fetches the current month on app open, so
      // when the user taps the Attendance tab seconds later this URL is throttled while
      // other months (different URLs) are not. Safe on forceRefresh too — a forced
      // refresh after punch in/out first calls clearCachesForRefresh(), which empties
      // the month cache, so there is nothing stale to serve here.
      if (_isThrottled(url)) {
        if (cacheMap.containsKey(cacheKey)) {
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

        // 1. Resolve Staff ID from local session or profile API
        final prefs = await SharedPreferences.getInstance();
        String? staffId;
        for (final key in ['user', 'staff', 'profile']) {
          final s = prefs.getString(key);
          if (s != null && s.isNotEmpty) {
            try {
              final u = jsonDecode(s);
              if (u is Map) {
                staffId = (u['id'] ?? u['_id'] ?? u['staffId'])?.toString();
                if (staffId != null && staffId.isNotEmpty) break;
              }
            } catch (_) {}
          }
        }
        if (staffId == null || staffId.isEmpty) {
          try {
            final prof = await AuthService().getProfile();
            final pData = prof['data'];
            if (pData is Map) {
              staffId = (pData['id'] ?? pData['_id'] ?? pData['staffId'])?.toString();
              if (staffId == null && pData['user'] is Map) {
                staffId = (pData['user']['id'] ?? pData['user']['_id'] ?? pData['user']['staffId'])?.toString();
              }
              if (staffId == null && pData['staff'] is Map) {
                staffId = (pData['staff']['id'] ?? pData['staff']['_id'] ?? pData['staff']['staffId'])?.toString();
              }
            }
          } catch (_) {}
        }

        Response<dynamic>? response;
        // Week offs for the month (HRMSbackend shift roster schedule), fetched alongside
        // the month attendance instead of after it.
        Future<dynamic>? rosterFuture;
        if (staffId != null && staffId.isNotEmpty) {
          rosterFuture = _api.dio
              .get<dynamic>(
                '/admin/settings/shift-roster/schedule/$staffId',
                queryParameters: {'year': year, 'month': month},
              )
              .then<dynamic>((r) => r.data is Map ? (r.data as Map)['data'] : null)
              .catchError((_) => null);
        }
        // 2. Primary: Canonical Web API endpoint
        if (staffId != null && staffId.isNotEmpty) {
          try {
            response = await _api.dio.get<dynamic>(
              '/admin/staff/attendance/staff/$staffId',
              queryParameters: {'year': year, 'month': month},
            );
          } on DioException catch (e) {
            // Only a missing route falls back to the legacy endpoints. A timeout / 5xx
            // used to walk the whole chain too, multiplying a slow load by 2-3x.
            if (!_isMissingRoute(e)) rethrow;
          }
        }

        // 3. Fallbacks
        if (response == null || response.statusCode != 200) {
          try {
            response = await _api.dio.get<dynamic>(
              '/staff/attendance/month',
              queryParameters: {'year': year, 'month': month},
            );
          } on DioException catch (e2) {
            if (!_isMissingRoute(e2)) rethrow;
            response = await _api.dio.get<dynamic>(
              '/attendance/month',
              queryParameters: {'year': year, 'month': month},
            );
          }
        }

        data = response.data is Map ? Map<String, dynamic>.from(response.data as Map) : {};

        // 4. Shift roster (week offs). The old '/admin/staff/settings/...' roster and holiday
        // template paths do not exist on HRMSbackend and only added two sequential 404s.
        final roster = await rosterFuture;
        if (roster != null) data['roster'] = roster;
      }

      final dynamic rawPayload = data['data'] ?? data;
      final Map<String, dynamic> rawData = rawPayload is Map ? Map<String, dynamic>.from(rawPayload) : {};

      // 6. Normalize attendances array & day lists
      final rawList = rawData['attendances'] ?? rawData['attendance'] ?? [];
      final List<Map<String, dynamic>> normalizedList = [];
      final List<String> presentDates = [];
      final List<String> absentDates = [];
      final List<String> halfDayDates = [];
      final List<String> leaveDates = [];
      final List<String> weekOffDates = [];
      final List<Map<String, dynamic>> holidayList = [];

      if (rawList is List) {
        for (final item in rawList) {
          if (item is! Map) continue;
          final m = Map<String, dynamic>.from(item);
          final rawDate = m['date']?.toString() ?? '';
          String dateStr = '';
          if (rawDate.isNotEmpty) {
            try {
              final parsed = DateTime.parse(rawDate).toLocal();
              dateStr = '${parsed.year}-${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')}';
            } catch (_) {
              if (rawDate.length >= 10) dateStr = rawDate.substring(0, 10);
            }
          }
          final rawStatus = (m['status']?.toString() ?? '').toLowerCase().trim();
          String status = 'Present';
          if (rawStatus == 'present') {
            status = 'Present';
            if (dateStr.isNotEmpty) presentDates.add(dateStr);
          } else if (rawStatus == 'half_day' || rawStatus == 'halfday' || rawStatus == 'half day') {
            status = 'Half Day';
            if (dateStr.isNotEmpty) halfDayDates.add(dateStr);
          } else if (rawStatus == 'absent') {
            status = 'Absent';
            if (dateStr.isNotEmpty) absentDates.add(dateStr);
          } else if (rawStatus == 'leave' || rawStatus == 'on_leave' || rawStatus == 'on leave') {
            status = 'On Leave';
            if (dateStr.isNotEmpty) leaveDates.add(dateStr);
          } else if (rawStatus == 'week_off' || rawStatus == 'weekly_off' || rawStatus == 'week off' || rawStatus == 'weekly off') {
            status = 'Week Off';
            if (dateStr.isNotEmpty) weekOffDates.add(dateStr);
          } else if (rawStatus == 'holiday') {
            status = 'Holiday';
          } else if (rawStatus == 'pending') {
            status = 'Pending';
          }

          final presentDetails = m['presentDetails'] is Map ? m['presentDetails'] as Map : null;
          final fineAdjustment = m['fineAdjustment'] is Map ? m['fineAdjustment'] as Map : null;
          final overtimeAdjustment = m['overtimeAdjustment'] is Map ? m['overtimeAdjustment'] as Map : null;

          final punchIn = presentDetails?['checkInTime'] ?? m['punchIn'] ?? m['checkIn'];
          final punchOut = presentDetails?['checkOutTime'] ?? m['punchOut'] ?? m['checkOut'];
          final workHours = presentDetails?['totalHours'] ?? m['workHours'] ?? m['workingHours'];
          final fine = fineAdjustment?['totalFine'] ?? m['fine'];
          final overtime = overtimeAdjustment?['amount'] ?? m['overtime'];

          final punchInSelfie = presentDetails?['checkInSelfie'] ?? m['punchInSelfie'] ?? m['checkInSelfie'];
          final punchOutSelfie = presentDetails?['checkOutSelfie'] ?? m['punchOutSelfie'] ?? m['checkOutSelfie'];
          final location = presentDetails?['location'] ?? m['location'] ?? m['punchInAddress'];
          final checkInCoordinates = presentDetails?['checkInCoordinates'] ?? m['checkInCoordinates'];
          final checkOutCoordinates = presentDetails?['checkOutCoordinates'] ?? m['checkOutCoordinates'];
          final breakSessions = presentDetails?['breakSessions'] ??
              presentDetails?['breaks'] ??
              (presentDetails?['break'] is Map ? (presentDetails?['break']['breaks'] ?? presentDetails?['break']['breakSessions']) : null) ??
              m['breakSessions'] ??
              m['breaks'] ??
              (m['break'] is Map ? (m['break']['breaks'] ?? m['break']['breakSessions']) : null);
          final breakDetails = m['breakDetails'];
          final activityLogs = m['activityLogs'] ?? m['logs'];

          m['status'] = status;
          m['date'] = dateStr.isNotEmpty ? dateStr : rawDate;
          if (punchIn != null && punchIn != 'NA') m['punchIn'] = punchIn;
          if (punchOut != null && punchOut != 'NA') m['punchOut'] = punchOut;
          if (workHours != null) m['workHours'] = workHours;
          if (fine != null) m['fine'] = fine;
          // Backend-calculated fines onto the keys the fine UI reads (same as web).
          applyServerFineFields(m);
          if (overtime != null) m['overtime'] = overtime;
          if (punchInSelfie != null) m['punchInSelfie'] = punchInSelfie;
          if (punchOutSelfie != null) m['punchOutSelfie'] = punchOutSelfie;
          if (location != null) m['location'] = location;
          if (checkInCoordinates != null) m['checkInCoordinates'] = checkInCoordinates;
          if (checkOutCoordinates != null) m['checkOutCoordinates'] = checkOutCoordinates;
          if (breakSessions != null) m['breakSessions'] = breakSessions;
          if (breakDetails != null) m['breakDetails'] = breakDetails;
          if (activityLogs != null) {
            m['activityLogs'] = activityLogs;
            m['logs'] = activityLogs;
          }

          normalizedList.add(m);
        }
      }

      // Populate week offs from roster if available
      final rosterDays = data['roster']?['days'];
      if (rosterDays is Map) {
        rosterDays.forEach((k, v) {
          // A day with no shift assigned is also `isOff` but is not a week off.
          if (v is Map &&
              v['isOff'] == true &&
              v['shiftName'] != 'Shift Not Assigned' &&
              !weekOffDates.contains(k.toString())) {
            weekOffDates.add(k.toString());
          }
        });
      }

      // Populate holidays from holiday templates
      final templates = data['holidayTemplates']?['templates'];
      if (templates is List) {
        for (final t in templates) {
          if (t is Map && t['holidays'] is List) {
            for (final h in t['holidays']) {
              if (h is Map && h['date'] != null) {
                try {
                  final hd = DateTime.parse(h['date'].toString()).toLocal();
                  if (hd.year == year && hd.month == month) {
                    holidayList.add({
                      'date': h['date'],
                      'name': h['name'] ?? 'Holiday',
                    });
                  }
                } catch (_) {}
              }
            }
          }
        }
      }

      final Map<String, dynamic> attendanceData = Map<String, dynamic>.from(rawData);
      attendanceData['attendance'] = normalizedList;
      attendanceData['attendances'] = normalizedList;
      attendanceData['presentDates'] = presentDates;
      attendanceData['absentDates'] = absentDates;
      attendanceData['halfDayDates'] = halfDayDates;
      attendanceData['leaveDates'] = leaveDates;
      attendanceData['weekOffDates'] = weekOffDates;
      if (holidayList.isNotEmpty) attendanceData['holidays'] = holidayList;

      attendanceData['presentCount'] = rawData['presentCount'] ?? presentDates.length;
      attendanceData['absentCount'] = rawData['absentCount'] ?? absentDates.length;
      attendanceData['halfDayCount'] = rawData['halfDayCount'] ?? halfDayDates.length;
      attendanceData['leaveCount'] = rawData['leaveCount'] ?? leaveDates.length;
      attendanceData['weeklyOffCount'] = rawData['weeklyOffCount'] ?? weekOffDates.length;
      attendanceData['holidayCount'] = rawData['holidayCount'] ?? holidayList.length;
      attendanceData['payableDays'] = rawData['payableDays'] ?? (presentDates.length + (halfDayDates.length * 0.5));

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
      // Have this month already? Show it now rather than waiting on a retry.
      if (cacheMap.containsKey(cacheKey)) {
        return {'success': true, 'data': cacheMap[cacheKey]};
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
          return 'Connection error2. Please check your internet connection and try again.';
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
        return 'Connection error3. Please check your internet connection and try again.';
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
