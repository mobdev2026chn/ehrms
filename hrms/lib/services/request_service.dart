import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/error_message_utils.dart';
import '../utils/punch_flow_log.dart';
import 'api_client.dart';
import 'attendance_service.dart';

class RequestService {
  final ApiClient _api = ApiClient();

  Future<void> _setToken() async {
    final prefs = await SharedPreferences.getInstance();
    String? token = prefs.getString('token');
    if (token != null && (token.startsWith('"') || token.endsWith('"'))) {
      token = token.replaceAll('"', '');
    }
    if (token != null && token.isNotEmpty) _api.setAuthToken(token);
  }

  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    String? token = prefs.getString('token');
    if (token != null && (token.startsWith('"') || token.endsWith('"'))) {
      token = token.replaceAll('"', '');
    }
    return token;
  }

  String get baseUrl => _api.dio.options.baseUrl;

  // --- DASHBOARD ---

  Future<Map<String, dynamic>> getDashboardData() async {
    try {
      await _setToken();

      // HRMSbackend has no aggregate /staff/dashboard (only /staff/dashboard/celebrations),
      // so build the stats from the endpoints it does serve - fetched in parallel.
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

      final now = DateTime.now();
      final year = now.year;
      final month = now.month;

      Future<dynamic> getData(String path, [Map<String, dynamic>? query]) async {
        try {
          final res = await _api.dio.get<dynamic>(path, queryParameters: query);
          return res.data is Map ? (res.data as Map)['data'] : null;
        } catch (_) {
          return null;
        }
      }

      // Today punch + month attendance go through AttendanceService so the shell,
      // Home cards and Attendance tab share one (deduped, cached) request each.
      Future<dynamic> sharedData(Future<Map<String, dynamic>> f) async {
        try {
          final r = await f;
          return r['success'] == true ? r['data'] : null;
        } catch (_) {
          return null;
        }
      }

      final attendance = AttendanceService();
      final results = await Future.wait<dynamic>([
        sharedData(attendance.getTodayAttendance()),
        getData('/staff/requests/leave/my-balances'),
        (staffId != null && staffId.isNotEmpty)
            ? sharedData(attendance.getMonthAttendance(year, month))
            : Future<dynamic>.value(null),
        getData('/staff/requests/leave/my-requests'),
        getData('/staff/dashboard/celebrations'),
      ]);

      // 5. Celebrations ({ birthdays, anniversaries }) -> today / upcoming lists for the card.
      final todayCelebrations = <Map<String, dynamic>>[];
      final upcomingCelebrations = <Map<String, dynamic>>[];
      final celeb = results[4];
      if (celeb is Map) {
        void addAll(dynamic list, String type) {
          if (list is! List) return;
          for (final e in list.whereType<Map>()) {
            final isToday = e['isToday'] == true;
            final entry = <String, dynamic>{
              'name': e['name'],
              'department': e['department'],
              'type': type,
              'displayDate': isToday ? 'Today' : (e['date'] ?? ''),
              'daysLeft': e['inDays'],
              if (e['years'] != null) 'yearsOfService': e['years'],
            };
            (isToday ? todayCelebrations : upcomingCelebrations).add(entry);
          }
        }

        addAll(celeb['birthdays'], 'Birthday');
        addAll(celeb['anniversaries'], 'Work Anniversary');
      }

      // 1. Today Punch
      final Map<String, dynamic> todayPunch =
          results[0] is Map ? Map<String, dynamic>.from(results[0] as Map) : {};

      // 2. Leave balances ({ balances: [{ balance, ... }] })
      num totalAvailableBalance = 0;
      final balData = results[1];
      final balances = balData is Map ? balData['balances'] : balData;
      if (balances is List) {
        for (final b in balances) {
          final v = b is Map ? (b['balance'] ?? b['availableBalance']) : null;
          if (v is num) totalAvailableBalance += v;
        }
      }

      // 3. Month Attendance
      final Map<String, dynamic> monthAttendance =
          results[2] is Map ? Map<String, dynamic>.from(results[2] as Map) : {};

      // 4. Recent Leaves
      final leaveData = results[3];
      final leaveList = leaveData is Map ? leaveData['requests'] : leaveData;
      final List<dynamic> recentLeaves = leaveList is List ? leaveList : [];

      final presentDays = todayPunch['presentDays'] ?? monthAttendance['presentCount'] ?? 0;
      final totalWorkingDays = todayPunch['totalWorkingDays'] ?? monthAttendance['totalWorkingDays'] ?? 30;
      final estimatedNetSalary = (todayPunch['estimatedNetSalary'] as num?)?.toDouble() ?? 0.0;

      final stats = {
        'attendanceSummary': {
          'presentDays': presentDays,
          'totalWorkingDays': totalWorkingDays,
          'paidLeaveDays': monthAttendance['paidLeaveCount'] ?? 0,
        },
        'attendance': {
          'present': presentDays,
          'absent': monthAttendance['absentCount'] ?? 0,
          'totalWorkingDays': totalWorkingDays,
        },
        'leaves': {
          'availableBalance': totalAvailableBalance,
          'pending': recentLeaves.where((e) => e is Map && e['status'] == 'Pending').length,
          'approved': recentLeaves.where((e) => e is Map && e['status'] == 'Approved').length,
        },
        'attendanceToday': todayPunch,
        'salary': {
          'estimatedNetSalary': estimatedNetSalary,
        },
      };

      return {
        'success': true,
        'data': {
          'stats': stats,
          'recentLeaves': recentLeaves,
          'todayAnnouncements': [],
          'todayCelebrations': todayCelebrations,
          'upcomingCelebrations': upcomingCelebrations,
        },
      };
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  String _dioMessage(DioException e) {
    return ErrorMessageUtils.messageFromDioException(e);
  }

  // --- ANNOUNCEMENTS ---

  /// All announcements for the logged-in employee (assigned to them or company-wide).
  Future<Map<String, dynamic>> getAnnouncementsForEmployee() async {
    try {
      await _setToken();
      final response = await _api.dio.get<Map<String, dynamic>>(
        '/announcements/for-employee',
      );
      final body = response.data;
      if (body != null && body['success'] == true) {
        return {'success': true, 'data': body['data'] ?? []};
      }
      return {
        'success': false,
        'message': body?['message'] ?? 'Error fetching announcements',
      };
    } on DioException catch (e) {
      return {'success': false, 'message': _dioMessage(e)};
    } catch (e) {
      return {'success': false, 'message': _handleException(e)};
    }
  }

  // --- LEAVE ---

  Future<Map<String, dynamic>> getLeaveTypes({
    int? month,
    int? year,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      await _setToken();
      final q = <String, dynamic>{};
      if (startDate != null && endDate != null) {
        q['startDate'] = startDate.toIso8601String();
        q['endDate'] = endDate.toIso8601String();
      } else if (month != null && year != null) {
        q['month'] = month;
        q['year'] = year;
      }
      Response<dynamic>? response;
      try {
        response = await _api.dio.get<dynamic>(
          '/staff/requests/leave/types',
          queryParameters: q,
        );
      } on DioException catch (e1) {
        if (!_isMissingRoute(e1)) rethrow;
        try {
          response = await _api.dio.get<dynamic>(
            '/admin/staff/settings/Leave/types',
          );
        } on DioException catch (e2) {
          if (!_isMissingRoute(e2)) rethrow;
          response = await _api.dio.get<dynamic>(
            '/requests/leave-types',
            queryParameters: q,
          );
        }
      }
      final body = response?.data;
      List<dynamic> list = [];
      if (body is List) {
        list = body;
      } else if (body is Map) {
        final d = body['data'] ?? body;
        if (d is List) {
          list = d;
        } else if (d is Map) {
          final rawTypes = d['leaveTypes'] ?? d['types'] ?? d['balances'] ?? [];
          if (rawTypes is List) list = rawTypes;
        }
      }
      return {'success': true, 'data': list};
    } on DioException catch (e) {
      return {'success': false, 'message': _dioMessage(e)};
    } catch (e) {
      return {'success': false, 'message': _handleException(e)};
    }
  }

  /// Fetches leave types for the Apply Leave dropdown: staff's leave template +
  /// Unpaid Leave. Returns list of { type, days } where days is the limit (null
  /// for Unpaid Leave). `halfDayEnabled` reports whether the staff's shift permits
  /// half-day, so the form can offer First/Second Half as a duration on any type.
  Future<Map<String, dynamic>> getLeaveTypesForApply() async {
    try {
      await _setToken();
      Response<dynamic>? response;
      try {
        response = await _api.dio.get<dynamic>('/staff/requests/leave/types');
      } on DioException catch (e3) {
        if (!_isMissingRoute(e3)) rethrow;
        try {
          response = await _api.dio.get<dynamic>('/admin/staff/settings/Leave/types');
        } on DioException catch (e4) {
          if (!_isMissingRoute(e4)) rethrow;
          try {
            response = await _api.dio.get<dynamic>('/requests/leave-types/for-apply');
          } on DioException catch (e5) {
            if (!_isMissingRoute(e5)) rethrow;
            response = await _api.dio.get<dynamic>('/requests/leave-types');
          }
        }
      }
      final body = response?.data;
      List<dynamic> list = [];
      bool halfDay = true;
      if (body is List) {
        list = body;
      } else if (body is Map) {
        if (body['halfDayEnabled'] != null) halfDay = body['halfDayEnabled'] == true;
        final d = body['data'] ?? body;
        if (d is List) {
          list = d;
        } else if (d is Map) {
          if (d['halfDayEnabled'] != null) halfDay = d['halfDayEnabled'] == true;
          final rawTypes = d['leaveTypes'] ?? d['types'] ?? d['balances'] ?? [];
          if (rawTypes is List) list = rawTypes;
        }
      }
      return {
        'success': true,
        'data': list,
        'halfDayEnabled': halfDay,
      };
    } on DioException catch (e) {
      return {'success': false, 'message': _dioMessage(e)};
    } catch (e) {
      return {'success': false, 'message': _handleException(e)};
    }
  }

  /// Checks leave dates for conflict. Pass [startDate] and [endDate] (range), and optionally [selectedDates] for calendar selection.
  /// When [selectedDates] is provided, backend uses it for conflict check; otherwise uses range.
  /// Returns { success, hasConflict, effectiveDays }.
  Future<Map<String, dynamic>> checkLeaveDates(
    DateTime startDate,
    DateTime endDate, {
    List<DateTime>? selectedDates,
  }) async {
    try {
      await _setToken();
      final Map<String, dynamic> data;
      if (selectedDates != null && selectedDates.isNotEmpty) {
        data = {
          'selectedDates': selectedDates
              .map(
                (d) =>
                    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}',
              )
              .toList(),
        };
      } else {
        data = {
          'startDate': startDate.toIso8601String(),
          'endDate': endDate.toIso8601String(),
        };
      }
      final response = await _api.dio.post<Map<String, dynamic>>(
        '/requests/leave/check-dates',
        data: data,
      );
      final body = response.data;
      if (body == null || body['success'] != true) {
        return {'success': false, 'hasConflict': false};
      }
      final resData = body['data'] as Map<String, dynamic>?;
      List<String> list(dynamic value) => value is List
          ? List<String>.from(value.map((e) => e.toString()))
          : <String>[];
      return {
        'success': true,
        'hasConflict': resData?['hasConflict'] == true,
        'effectiveDays': (resData?['effectiveDays'] is int)
            ? resData!['effectiveDays'] as int
            : null,
        'paidLeaveDates': list(resData?['paidLeaveDates']),
        'pendingLeaveDates': list(resData?['pendingLeaveDates']),
        'approvedLeaveDates': list(resData?['approvedLeaveDates']),
        'weekOffDates': list(resData?['weekOffDates']),
        'holidayDates': list(resData?['holidayDates']),
      };
    } on DioException catch (e) {
      return {
        'success': false,
        'hasConflict': false,
        'message': _dioMessage(e),
      };
    } catch (e) {
      return {
        'success': false,
        'hasConflict': false,
        'message': _handleException(e),
      };
    }
  }

  /// Fetches leave balance: availableCasualLeaves from attendances, totalAllowed from leave template.
  ///
  /// [forMonth] scopes used/pending days to that month's quota. The template
  /// allocation resets monthly, so applying for a future month must draw against
  /// that month — pass the leave's start date here. Omitted = current month.
  Future<Map<String, dynamic>> getLeaveBalance({DateTime? forMonth}) async {
    try {
      await _setToken();
      final response = await _api.dio.get<Map<String, dynamic>>(
        '/requests/leave-balance',
        queryParameters: forMonth == null
            ? null
            : {'month': forMonth.month, 'year': forMonth.year},
      );
      final body = response.data;
      if (body == null || body['success'] != true) {
        return {
          'success': false,
          'message':
              ErrorMessageUtils.messageFromResponseData(body) ??
              'Failed to load balance',
        };
      }
      final data = body['data'] as Map<String, dynamic>?;
      return {
        'success': true,
        'availableCasualLeaves': (data?['availableCasualLeaves'] is num)
            ? (data!['availableCasualLeaves'] as num).toDouble()
            : 0.0,
        'totalAllowed': (data?['totalAllowed'] is num)
            ? (data!['totalAllowed'] as num).toDouble()
            : 0.0,
        // Null (not 0) when the backend doesn't send these, so the app can tell
        // "absent" from "zero" and fall back to computing usage from records.
        'usedDays': (data?['usedDays'] is num)
            ? (data!['usedDays'] as num).toDouble()
            : null,
        'pendingLeaveDays': (data?['pendingLeaveDays'] is num)
            ? (data!['pendingLeaveDays'] as num).toDouble()
            : (data?['pendingLeaves'] is num)
                ? (data!['pendingLeaves'] as num).toDouble()
                : null,
      };
    } on DioException catch (e) {
      return {'success': false, 'message': _dioMessage(e)};
    } catch (e) {
      return {'success': false, 'message': _handleException(e)};
    }
  }

  Future<Map<String, dynamic>> applyLeave(Map<String, dynamic> data) async {
    try {
      await _setToken();
      Response<dynamic> response;
      try {
        response = await _api.dio.post<dynamic>(
          '/staff/requests/leave/apply',
          data: data,
        );
      } on DioException catch (e6) {
        if (!_isMissingRoute(e6)) rethrow;
        response = await _api.dio.post<dynamic>(
          '/requests/leave',
          data: data,
        );
      }
      final body = response.data;
      if (body == null) {
        return {'success': false, 'message': 'Invalid response'};
      }
      var responseData = body;
      if (body is Map && body.containsKey('data') && body['data'] is Map) {
        final d = body['data'] as Map;
        if (d.containsKey('leave')) {
          responseData = d['leave'] as Map<String, dynamic>;
        } else {
          responseData = Map<String, dynamic>.from(d);
        }
      }
      return {'success': true, 'data': responseData};
    } on DioException catch (e) {
      return {'success': false, 'message': _dioMessage(e)};
    } catch (e) {
      return {'success': false, 'message': _handleException(e)};
    }
  }

  /// HRMSbackend names these `leaveTypeName` / `duration` (leave) and
  /// `durationMins` (permission); the screens read `leaveType` / `days` /
  /// `requestedMinutes`, so alias them without overwriting existing values.
  dynamic _normalizeMyRequestsBody(dynamic body) {
    dynamic fix(dynamic item) {
      if (item is! Map) return item;
      final m = Map<String, dynamic>.from(item);
      if (m['leaveType'] == null && m['leaveTypeName'] != null) m['leaveType'] = m['leaveTypeName'];
      if (m['days'] == null && m['duration'] != null) m['days'] = m['duration'];
      if (m['requestedMinutes'] == null && m['durationMins'] != null) {
        m['requestedMinutes'] = m['durationMins'];
      }
      return m;
    }

    List<dynamic> fixAll(List<dynamic> list) => list.map(fix).toList();

    if (body is List) return fixAll(body);
    if (body is Map) {
      final data = body['data'];
      if (data is List) return {...body, 'data': fixAll(data)};
      if (data is Map && data['requests'] is List) {
        return {
          ...body,
          'data': {...data, 'requests': fixAll(data['requests'] as List)},
        };
      }
    }
    return body;
  }

  /// id -> display name for colleagues and the company admin, from the staff chat
  /// directory. Loaded once per app session; used to name request reviewers.
  static Map<String, String>? _reviewerNames;

  /// Legacy-route fallbacks run only when the primary route does not exist.
  /// Anything else (validation 400, timeout) is surfaced as-is: falling through
  /// hid the server's message behind a legacy 404 and re-sent POSTs.
  static bool _isMissingRoute(DioException e) {
    final code = e.response?.statusCode;
    return code == 404 || code == 405;
  }

  static Future<Map<String, String>>? _reviewerNamesInFlight;

  /// The request tabs load together; share one directory fetch between them.
  Future<Map<String, String>> _loadReviewerNames() {
    final cached = _reviewerNames;
    if (cached != null) return Future.value(cached);
    final pending = _reviewerNamesInFlight;
    if (pending != null) return pending;
    final future = _fetchReviewerNames();
    _reviewerNamesInFlight = future;
    future.whenComplete(() => _reviewerNamesInFlight = null).ignore();
    return future;
  }

  Future<Map<String, String>> _fetchReviewerNames() async {
    final names = <String, String>{};
    try {
      final res = await _api.dio.get<dynamic>('/staff/interaction/chat/directory');
      final data = res.data is Map ? (res.data as Map)['data'] : null;
      if (data is Map) {
        final admin = data['admin'];
        if (admin is Map && admin['_id'] != null) {
          final n = (admin['name'] ?? admin['companyAdmin'] ?? '').toString().trim();
          if (n.isNotEmpty) names[admin['_id'].toString()] = n;
        }
        final staff = data['staff'];
        if (staff is List) {
          for (final s in staff.whereType<Map>()) {
            final n = '${s['firstName'] ?? ''} ${s['lastName'] ?? ''}'.trim();
            if (s['_id'] != null && n.isNotEmpty) names[s['_id'].toString()] = n;
          }
        }
      }
      _reviewerNames = names;
    } catch (_) {
      // Leave the cache empty so the next call retries.
    }
    return names;
  }

  /// HRMSbackend returns the reviewer as `reviewedBy` (an id) and, for expense/payslip,
  /// `approvedBy` as the reviewer's name string. The screens expect
  /// `approvedBy` / `rejectedBy` maps with a `name`, so build those here.
  Future<dynamic> _attachReviewerNames(dynamic body) async {
    final idPattern = RegExp(r'^[0-9a-fA-F]{24}$');
    List<dynamic>? list;
    if (body is List) {
      list = body;
    } else if (body is Map) {
      final data = body['data'];
      if (data is List) {
        list = data;
      } else if (data is Map && data['requests'] is List) {
        list = data['requests'] as List;
      }
    }
    if (list == null || list.isEmpty) return body;

    Map<String, String>? directory;
    for (var i = 0; i < list.length; i++) {
      final item = list[i];
      if (item is! Map) continue;
      final status = (item['status'] ?? '').toString().toLowerCase();
      final isRejected = status == 'rejected';
      final key = isRejected ? 'rejectedBy' : 'approvedBy';
      if (item[key] is Map && (item[key] as Map)['name'] != null) continue;

      String? name;
      final storedName = item['approvedBy'];
      if (storedName is String && storedName.trim().isNotEmpty && !idPattern.hasMatch(storedName.trim())) {
        name = storedName.trim();
      } else {
        final reviewer = item['reviewedBy'] ?? (storedName is String ? storedName : null);
        final reviewerId = reviewer is Map ? reviewer['_id']?.toString() : reviewer?.toString();
        if (reviewerId != null && reviewerId.isNotEmpty) {
          directory ??= await _loadReviewerNames();
          name = directory[reviewerId];
        }
      }

      final m = Map<String, dynamic>.from(item);
      // The raw string (a name or an id) is never a map the screens can read; without
      // this they fall back to a made-up "System". Unresolved reviewers show "-".
      if (m['approvedBy'] is String) m.remove('approvedBy');
      if (name != null) m[key] = {'name': name};
      list[i] = m;
    }
    return body;
  }

  /// HRMSbackend `/staff/requests/*/my-requests` returns every request and ignores
  /// status/search/date query params, so apply them here. Server-paginated
  /// responses are left untouched.
  dynamic _filterMyRequestsBody(
    dynamic body, {
    String? status,
    String? search,
    DateTime? startDate,
    DateTime? endDate,
  }) {
    final wantStatus = (status == null || status == 'All Status') ? null : status.toLowerCase();
    final q = search?.trim().toLowerCase() ?? '';
    if (wantStatus == null && q.isEmpty && startDate == null && endDate == null) return body;

    DateTime? parse(dynamic v) => v == null ? null : DateTime.tryParse(v.toString())?.toLocal();

    bool keep(dynamic item) {
      if (item is! Map) return true;
      if (wantStatus != null && (item['status'] ?? '').toString().toLowerCase() != wantStatus) {
        return false;
      }
      if (q.isNotEmpty) {
        final text = item.values
            .where((v) => v is String || v is num)
            .map((v) => v.toString().toLowerCase())
            .join(' ');
        if (!text.contains(q)) return false;
      }
      if (startDate != null || endDate != null) {
        final from = parse(item['startDate'] ?? item['date'] ?? item['expenseDate'] ?? item['createdAt']);
        final to = parse(item['endDate']) ?? from;
        if (from == null || to == null) return false;
        if (endDate != null && from.isAfter(endDate)) return false;
        if (startDate != null && to.isBefore(startDate)) return false;
      }
      return true;
    }

    List<dynamic> apply(List<dynamic> list) => list.where(keep).toList();

    if (body is List) return apply(body);
    if (body is Map) {
      final data = body['data'];
      if (data is List) return {...body, 'data': apply(data)};
      if (data is Map && data['requests'] is List && data['pagination'] == null) {
        return {
          ...body,
          'data': {...data, 'requests': apply(data['requests'] as List)},
        };
      }
    }
    return body;
  }

  Future<Map<String, dynamic>> getLeaveRequests({
    String? status,
    String? search,
    DateTime? startDate,
    DateTime? endDate,
    int page = 1,
    int limit = 10,
  }) async {
    try {
      await _setToken();
      final q = <String, dynamic>{
        'page': page,
        'limit': limit,
        if (status != null && status != 'All Status') 'status': status,
        if (search != null && search.isNotEmpty) 'search': search,
        if (startDate != null) 'startDate': startDate.toIso8601String(),
        if (endDate != null) 'endDate': endDate.toIso8601String(),
      };
      Response<dynamic> response;
      try {
        response = await _api.dio.get<dynamic>(
          '/staff/requests/leave/my-requests',
          queryParameters: q,
        );
      } on DioException catch (e7) {
        if (!_isMissingRoute(e7)) rethrow;
        response = await _api.dio.get<dynamic>(
          '/requests/leave',
          queryParameters: q,
        );
      }
      final body = _filterMyRequestsBody(
        await _attachReviewerNames(_normalizeMyRequestsBody(response.data)),
        status: status,
        search: search,
        startDate: startDate,
        endDate: endDate,
      );
      if (body is List) return {'success': true, 'data': body};
      if (body is Map && body['success'] == true) {
        final data = body['data'];
        if (data is Map && data['requests'] != null) {
          return {
            'success': true,
            'data': data,
            'requests': data['requests'],
            'pagination': data['pagination'],
          };
        }
        return {'success': true, 'data': data ?? body};
      }
      return {'success': true, 'data': body is Map && body['data'] != null ? body['data'] : []};
    } on DioException catch (e) {
      return {'success': false, 'message': _dioMessage(e)};
    } catch (e) {
      return {'success': false, 'message': _handleException(e)};
    }
  }

  Future<Map<String, dynamic>> cancelLeaveRequest(String requestId) async {
    try {
      await _setToken();
      Response<dynamic> response;
      try {
        response = await _api.dio.post<dynamic>(
          '/staff/requests/leave/cancel/$requestId',
        );
      } on DioException catch (e8) {
        if (!_isMissingRoute(e8)) rethrow;
        response = await _api.dio.patch<dynamic>(
          '/requests/leave/$requestId/cancel',
        );
      }
      final body = response.data;
      if (body != null && (body['success'] == true || response.statusCode == 200)) {
        return {'success': true, 'message': body['message'] ?? 'Leave cancelled'};
      }
      return {'success': false, 'message': body?['message'] ?? 'Failed to cancel leave'};
    } on DioException catch (e) {
      return {'success': false, 'message': _dioMessage(e)};
    } catch (e) {
      return {'success': false, 'message': _handleException(e)};
    }
  }

  // --- LOAN ---

  Future<Map<String, dynamic>> applyLoan(Map<String, dynamic> data) async {
    try {
      await _setToken();
      final response = await _api.dio.post<Map<String, dynamic>>(
        '/requests/loan',
        data: data,
      );
      final body = response.data;
      final responseData = body != null && body.containsKey('data')
          ? body['data']!
          : body;
      return {'success': true, 'data': responseData};
    } on DioException catch (e) {
      return {'success': false, 'message': _dioMessage(e)};
    } catch (e) {
      return {'success': false, 'message': _handleException(e)};
    }
  }

  Future<Map<String, dynamic>> getLoanRequests({
    String? status,
    String? search,
    DateTime? startDate,
    DateTime? endDate,
    int page = 1,
    int limit = 10,
  }) async {
    try {
      await _setToken();
      final q = <String, dynamic>{
        'page': page,
        'limit': limit,
        if (status != null && status != 'All Status') 'status': status,
        if (search != null && search.isNotEmpty) 'search': search,
        if (startDate != null) 'startDate': startDate.toIso8601String(),
        if (endDate != null) 'endDate': endDate.toIso8601String(),
      };
      final response = await _api.dio.get<Map<String, dynamic>>(
        '/requests/loan',
        queryParameters: q,
      );
      final body = response.data;
      if (body != null && body['success'] == true) {
        return {'success': true, 'data': body['data'] ?? body};
      }
      return {'success': true, 'data': body};
    } on DioException catch (e) {
      return {'success': false, 'message': _dioMessage(e)};
    } catch (e) {
      return {'success': false, 'message': _handleException(e)};
    }
  }

  /// All-time loan stats for the logged-in employee (active/pending counts,
  /// outstanding amount) - independent of any list pagination/filters.
  Future<Map<String, dynamic>> getLoanSummary() async {
    try {
      await _setToken();
      final response = await _api.dio.get<Map<String, dynamic>>(
        '/requests/loan/summary',
      );
      final body = response.data;
      if (body != null && body['success'] == true) {
        return {'success': true, 'data': body['data'] ?? {}};
      }
      return {'success': false, 'message': body?['message'] ?? 'Error'};
    } on DioException catch (e) {
      return {'success': false, 'message': _dioMessage(e)};
    } catch (e) {
      return {'success': false, 'message': _handleException(e)};
    }
  }

  // --- EXPENSE ---

  Future<Map<String, dynamic>> applyExpense(Map<String, dynamic> data) async {
    try {
      await _setToken();
      if (kDebugMode) {
        final headers = _api.dio.options.headers;
        debugPrint(
          '[ExpenseUpload] baseUrl=${_api.dio.options.baseUrl} '
          'X-Storage-Environment=${headers['X-Storage-Environment'] ?? headers['x-storage-environment']}',
        );
      }
      Response<dynamic> response;
      try {
        response = await _api.dio.post<dynamic>(
          '/staff/requests/expense/apply',
          data: data,
        );
      } on DioException catch (e9) {
        if (!_isMissingRoute(e9)) rethrow;
        response = await _api.dio.post<dynamic>(
          '/requests/expense',
          data: data,
        );
      }
      final body = response.data;
      if (body == null) {
        return {'success': false, 'message': 'Invalid response'};
      }
      var responseData = body;
      if (body is Map && body.containsKey('data') && body['data'] is Map) {
        final d = body['data'] as Map;
        if (d.containsKey('reimbursement')) {
          responseData = d['reimbursement'] as Map<String, dynamic>;
        } else {
          responseData = Map<String, dynamic>.from(d);
        }
      }
      return {'success': true, 'data': responseData};
    } on DioException catch (e) {
      return {'success': false, 'message': _dioMessage(e)};
    } catch (e) {
      return {'success': false, 'message': _handleException(e)};
    }
  }

  Future<Map<String, dynamic>> getExpenseRequests({
    String? status,
    String? search,
    DateTime? startDate,
    DateTime? endDate,
    int page = 1,
    int limit = 10,
  }) async {
    try {
      await _setToken();
      final q = <String, dynamic>{
        'page': page,
        'limit': limit,
        if (status != null && status != 'All Status') 'status': status,
        if (search != null && search.isNotEmpty) 'search': search,
        if (startDate != null) 'startDate': startDate.toIso8601String(),
        if (endDate != null) 'endDate': endDate.toIso8601String(),
      };
      Response<dynamic> response;
      try {
        response = await _api.dio.get<dynamic>(
          '/staff/requests/expense/my-requests',
          queryParameters: q,
        );
      } on DioException catch (e10) {
        if (!_isMissingRoute(e10)) rethrow;
        response = await _api.dio.get<dynamic>(
          '/requests/expense',
          queryParameters: q,
        );
      }
      final body = _filterMyRequestsBody(
        await _attachReviewerNames(response.data),
        status: status,
        search: search,
        startDate: startDate,
        endDate: endDate,
      );
      if (body is List) return {'success': true, 'data': body};
      if (body is Map && body['success'] == true) {
        final data = body['data'];
        if (data is Map && data['requests'] != null) {
          return {
            'success': true,
            'data': data,
            'requests': data['requests'],
            'pagination': data['pagination'],
          };
        }
        return {'success': true, 'data': data ?? body};
      }
      return {'success': true, 'data': body is Map && body['data'] != null ? body['data'] : []};
    } on DioException catch (e) {
      return {'success': false, 'message': _dioMessage(e)};
    } catch (e) {
      return {'success': false, 'message': _handleException(e)};
    }
  }

  /// All-time reimbursement totals for the logged-in employee (total
  /// reimbursed, pending amount/count) - independent of any list
  /// pagination/filters.
  Future<Map<String, dynamic>> getExpenseSummary() async {
    try {
      await _setToken();
      final response = await _api.dio.get<Map<String, dynamic>>(
        '/requests/expense/summary',
      );
      final body = response.data;
      if (body != null && body['success'] == true) {
        return {'success': true, 'data': body['data'] ?? {}};
      }
      return {'success': false, 'message': body?['message'] ?? 'Error'};
    } on DioException catch (e) {
      return {'success': false, 'message': _dioMessage(e)};
    } catch (e) {
      return {'success': false, 'message': _handleException(e)};
    }
  }

  // --- PAYSLIP ---

  Future<Map<String, dynamic>> requestPayslip(Map<String, dynamic> data) async {
    try {
      await _setToken();
      Response<dynamic> response;
      try {
        response = await _api.dio.post<dynamic>(
          '/staff/requests/payslip/apply',
          data: data,
        );
      } on DioException catch (e11) {
        if (!_isMissingRoute(e11)) rethrow;
        response = await _api.dio.post<dynamic>(
          '/requests/payslip',
          data: data,
        );
      }
      final body = response.data;
      if (body != null &&
          (body['success'] == true || response.statusCode == 201)) {
        return {
          'success': true,
          'data': body['data'],
          'message': body['message'],
        };
      }
      return {'success': true, 'data': body};
    } on DioException catch (e) {
      return {'success': false, 'message': _dioMessage(e)};
    } catch (e) {
      return {'success': false, 'message': _handleException(e)};
    }
  }

  Future<Map<String, dynamic>> getPayslipRequests({
    String? status,
    String? search,
    DateTime? startDate,
    DateTime? endDate,
    int page = 1,
    int limit = 10,
  }) async {
    try {
      await _setToken();
      final q = <String, dynamic>{
        'page': page,
        'limit': limit,
        if (status != null && status != 'All Status') 'status': status,
        if (search != null && search.isNotEmpty) 'search': search,
        if (startDate != null) 'startDate': startDate.toIso8601String(),
        if (endDate != null) 'endDate': endDate.toIso8601String(),
      };
      Response<dynamic> response;
      try {
        response = await _api.dio.get<dynamic>(
          '/staff/requests/payslip/my-requests',
          queryParameters: q,
        );
      } on DioException catch (e12) {
        if (!_isMissingRoute(e12)) rethrow;
        response = await _api.dio.get<dynamic>(
          '/requests/payslip',
          queryParameters: q,
        );
      }
      final body = _filterMyRequestsBody(
        await _attachReviewerNames(response.data),
        status: status,
        search: search,
        startDate: startDate,
        endDate: endDate,
      );
      if (body is List) return {'success': true, 'data': body};
      if (body is Map && body['success'] == true) {
        final data = body['data'];
        if (data is Map && data['requests'] != null) {
          return {
            'success': true,
            'data': data,
            'requests': data['requests'],
            'pagination': data['pagination'],
          };
        }
        return {'success': true, 'data': data ?? body};
      }
      return {'success': true, 'data': body is Map && body['data'] != null ? body['data'] : []};
    } on DioException catch (e) {
      return {'success': false, 'message': _dioMessage(e)};
    } catch (e) {
      return {'success': false, 'message': _handleException(e)};
    }
  }

  Future<Map<String, dynamic>> cancelExpenseRequest(String requestId) async {
    try {
      await _setToken();
      Response<dynamic> response;
      try {
        response = await _api.dio.post<dynamic>(
          '/staff/requests/expense/cancel/$requestId',
        );
      } on DioException catch (e13) {
        if (!_isMissingRoute(e13)) rethrow;
        response = await _api.dio.patch<dynamic>(
          '/requests/expense/$requestId/cancel',
        );
      }
      final body = response.data;
      if (body != null && (body['success'] == true || response.statusCode == 200)) {
        return {'success': true, 'message': body['message'] ?? 'Expense request cancelled'};
      }
      return {'success': false, 'message': body?['message'] ?? 'Failed to cancel expense'};
    } on DioException catch (e) {
      return {'success': false, 'message': _dioMessage(e)};
    } catch (e) {
      return {'success': false, 'message': _handleException(e)};
    }
  }

  Future<Map<String, dynamic>> cancelPayslipRequest(String requestId) async {
    try {
      await _setToken();
      Response<dynamic> response;
      try {
        response = await _api.dio.post<dynamic>(
          '/staff/requests/payslip/cancel/$requestId',
        );
      } on DioException catch (e14) {
        if (!_isMissingRoute(e14)) rethrow;
        response = await _api.dio.patch<dynamic>(
          '/requests/payslip/$requestId/cancel',
        );
      }
      final body = response.data;
      if (body != null && (body['success'] == true || response.statusCode == 200)) {
        return {'success': true, 'message': body['message'] ?? 'Payslip request cancelled'};
      }
      return {'success': false, 'message': body?['message'] ?? 'Failed to cancel payslip request'};
    } on DioException catch (e) {
      return {'success': false, 'message': _dioMessage(e)};
    } catch (e) {
      return {'success': false, 'message': _handleException(e)};
    }
  }

  Future<Map<String, dynamic>> viewPayslipRequest(String requestId) async {
    try {
      await _setToken();
      final response = await _api.dio.get<Map<String, dynamic>>(
        '/requests/payslip/$requestId/view',
      );
      final body = response.data;
      if (body != null &&
          body['success'] == true &&
          body['payslipUrl'] != null) {
        return {'success': true, 'payslipUrl': body['payslipUrl']};
      }
      return {
        'success': false,
        'message': body != null && body['error'] is Map
            ? (body['error']['message'] ?? 'Payslip not available yet')
            : 'Failed to view payslip',
      };
    } on DioException catch (e) {
      final msg = e.response?.data is Map
          ? (e.response?.data as Map)['error'] is Map
                ? ((e.response?.data as Map)['error'] as Map)['message']
                      ?.toString()
                : null
          : null;
      return {'success': false, 'message': msg ?? _dioMessage(e)};
    } catch (e) {
      return {'success': false, 'message': _handleException(e)};
    }
  }

  Future<Map<String, dynamic>> downloadPayslipRequest(String requestId) async {
    try {
      await _setToken();
      final response = await _api.dio.get<Map<String, dynamic>>(
        '/requests/payslip/$requestId/download',
      );
      final body = response.data;
      if (body != null &&
          body['success'] == true &&
          body['payslipUrl'] != null) {
        return {'success': true, 'payslipUrl': body['payslipUrl']};
      }
      return {
        'success': false,
        'message': body != null && body['error'] is Map
            ? (body['error']['message'] ?? 'Payslip not available yet')
            : 'Failed to download payslip',
      };
    } on DioException catch (e) {
      final msg = e.response?.data is Map
          ? (e.response?.data as Map)['error'] is Map
                ? ((e.response?.data as Map)['error'] as Map)['message']
                      ?.toString()
                : null
          : null;
      return {'success': false, 'message': msg ?? _dioMessage(e)};
    } catch (e) {
      return {'success': false, 'message': _handleException(e)};
    }
  }

  // --- PERMISSION ---

  Future<Map<String, dynamic>> getPermissionRequests({
    String? status,
    int? month,
    int? year,
  }) async {
    try {
      await _setToken();
      final now = DateTime.now();
      final q = <String, dynamic>{
        'month': month ?? now.month,
        'year': year ?? now.year,
        if (status != null && status != 'All Status') 'status': status,
      };
      Response<dynamic> response;
      try {
        response = await _api.dio.get<dynamic>(
          '/staff/requests/permission/my-requests',
          queryParameters: q,
        );
      } on DioException catch (e15) {
        if (!_isMissingRoute(e15)) rethrow;
        response = await _api.dio.get<dynamic>(
          '/requests/permission',
          queryParameters: q,
        );
      }
      final body = await _attachReviewerNames(_normalizeMyRequestsBody(response.data));
      punchFlowLog(
        '[Permission][App][getPermissionRequests] status=${response.statusCode} '
        'query=$q raw=$body',
      );
      if (body is List) {
        return {'success': true, 'data': body};
      }
      if (body != null && body['success'] == true) {
        final data = body['data'];
        if (data is Map && data['requests'] != null) {
          return {
            'success': true,
            'data': data,
            'requests': data['requests'],
            'pagination': data['pagination'],
          };
        }
        return {'success': true, 'data': data ?? body};
      }
      return {'success': true, 'data': body is Map && body['data'] != null ? body['data'] : []};
    } on DioException catch (e) {
      punchFlowLog(
        '[Permission][App][getPermissionRequests] DioException '
        'status=${e.response?.statusCode} data=${e.response?.data}',
      );
      return {'success': false, 'message': _dioMessage(e)};
    } catch (e) {
      punchFlowLog(
        '[Permission][App][getPermissionRequests] error=$e',
      );
      return {'success': false, 'message': _handleException(e)};
    }
  }

  Future<Map<String, dynamic>> createPermissionRequest({
    required DateTime date,
    required String type,
    required int requestedMinutes,
    required String reason,
    int? lateHours,
    int? lateMinutes,
    int? earlyHours,
    int? earlyMinutes,
    String? fromTime,
    String? toTime,
    String? permTypeWeb,
  }) async {
    try {
      await _setToken();
      final lH = lateHours ?? (type == 'Late' ? requestedMinutes ~/ 60 : 0);
      final lM = lateMinutes ?? (type == 'Late' ? requestedMinutes % 60 : 0);
      final eH = earlyHours ?? (type == 'Early' ? requestedMinutes ~/ 60 : 0);
      final eM = earlyMinutes ?? (type == 'Early' ? requestedMinutes % 60 : 0);
      final wireType = permTypeWeb ?? (type == 'lateArrival' ? 'Late' : (type == 'earlyExit' ? 'Early' : (type == 'both' ? 'Custom' : type)));

      final dateStr =
          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      final reqData = {
        'date': dateStr,
        'type': wireType,
        'lateHours': lH,
        'lateMinutes': lM,
        'earlyHours': eH,
        'earlyMinutes': eM,
        'durationMins': requestedMinutes,
        'requestedMinutes': requestedMinutes,
        'reason': reason,
        if (fromTime != null && fromTime.isNotEmpty) 'fromTime': fromTime,
        if (toTime != null && toTime.isNotEmpty) 'toTime': toTime,
      };
      Response<dynamic> response;
      try {
        response = await _api.dio.post<dynamic>(
          '/staff/requests/permission/apply',
          data: reqData,
        );
      } on DioException catch (e16) {
        if (!_isMissingRoute(e16)) rethrow;
        response = await _api.dio.post<dynamic>(
          '/requests/permission',
          data: reqData,
        );
      }
      final body = response.data;
      punchFlowLog(
        '[Permission][App][createPermissionRequest] status=${response.statusCode} '
        'date=${date.toIso8601String()} type=$type requestedMinutes=$requestedMinutes '
        'raw=$body',
      );
      if (body != null && (body['success'] == true || response.statusCode == 201)) {
        return {
          'success': true,
          'data': body['data'] ?? body,
          'notice': body['notice'],
        };
      }
      return {
        'success': false,
        'message': 'Failed to submit permission request',
      };
    } on DioException catch (e) {
      punchFlowLog(
        '[Permission][App][createPermissionRequest] DioException '
        'status=${e.response?.statusCode} data=${e.response?.data}',
      );
      return {'success': false, 'message': _dioMessage(e)};
    } catch (e) {
      punchFlowLog(
        '[Permission][App][createPermissionRequest] error=$e',
      );
      return {'success': false, 'message': _handleException(e)};
    }
  }

  Future<Map<String, dynamic>> cancelPermissionRequest(String requestId) async {
    try {
      await _setToken();
      Response<dynamic> response;
      try {
        response = await _api.dio.post<dynamic>(
          '/staff/requests/permission/cancel/$requestId',
        );
      } on DioException catch (e17) {
        if (!_isMissingRoute(e17)) rethrow;
        response = await _api.dio.patch<dynamic>(
          '/requests/permission/$requestId/cancel',
        );
      }
      final body = response.data;
      punchFlowLog(
        '[Permission][App][cancelPermissionRequest] status=${response.statusCode} '
        'requestId=$requestId raw=$body',
      );
      if (body != null && body['success'] == true) {
        return {'success': true, 'data': body['data'] ?? body};
      }
      return {
        'success': false,
        'message': 'Failed to cancel permission request',
      };
    } on DioException catch (e) {
      punchFlowLog(
        '[Permission][App][cancelPermissionRequest] DioException '
        'status=${e.response?.statusCode} data=${e.response?.data}',
      );
      return {'success': false, 'message': _dioMessage(e)};
    } catch (e) {
      punchFlowLog(
        '[Permission][App][cancelPermissionRequest] error=$e',
      );
      return {'success': false, 'message': _handleException(e)};
    }
  }

  /// Stamp Permission Out / Permission In for an approved custom-time permission.
  /// [action] is 'out' or 'in'. A [selfie] (base64 data URL) is required by the
  /// backend. On 'in', the backend returns actualMinutes and overrunMinutes so
  /// the caller can warn when a fine was applied.
  Future<Map<String, dynamic>> _permissionStamp(
    String id,
    String action, {
    required String selfie,
  }) async {
    try {
      await _setToken();
      final response = await _api.dio.post<Map<String, dynamic>>(
        '/requests/permission/$id/$action',
        data: {'selfie': selfie},
      );
      final body = response.data;
      punchFlowLog(
        '[Permission][App][permission$action] status=${response.statusCode} '
        'id=$id raw=$body',
      );
      if (body != null && body['success'] == true) {
        return {'success': true, 'data': body['data'] ?? body};
      }
      return {'success': false, 'message': 'Failed to record permission $action'};
    } on DioException catch (e) {
      punchFlowLog(
        '[Permission][App][permission$action] DioException '
        'status=${e.response?.statusCode} data=${e.response?.data}',
      );
      return {'success': false, 'message': _dioMessage(e)};
    } catch (e) {
      punchFlowLog('[Permission][App][permission$action] error=$e');
      return {'success': false, 'message': _handleException(e)};
    }
  }

  Future<Map<String, dynamic>> permissionOut(String id,
          {required String selfie}) =>
      _permissionStamp(id, 'out', selfie: selfie);

  Future<Map<String, dynamic>> permissionIn(String id,
          {required String selfie}) =>
      _permissionStamp(id, 'in', selfie: selfie);

  Future<Map<String, dynamic>> getPermissionBalance({
    int? month,
    int? year,
  }) async {
    try {
      await _setToken();
      final now = DateTime.now();
      final q = {
        'month': month ?? now.month,
        'year': year ?? now.year,
      };

      Response<dynamic>? res;
      String sourceEndpoint = '/staff/requests/permission/my-quota';
      try {
        // Web parity: primary endpoint.
        res = await _api.dio.get<dynamic>(
          '/staff/requests/permission/my-quota',
        );
      } on DioException catch (e18) {
        if (!_isMissingRoute(e18)) rethrow;
        try {
          sourceEndpoint = '/permissions/balance';
          res = await _api.dio.get<dynamic>(
            '/permissions/balance',
            queryParameters: q,
          );
        } on DioException catch (e19) {
          if (!_isMissingRoute(e19)) rethrow;
          sourceEndpoint = '/requests/permission/balance';
          res = await _api.dio.get<dynamic>(
            '/requests/permission/balance',
            queryParameters: q,
          );
        }
      }

      final balanceBody = res?.data;
      if (balanceBody == null || balanceBody['success'] != true) {
        return {'success': false, 'message': 'Failed to load permission balance'};
      }

      final dataMap = balanceBody['data'] is Map
          ? Map<String, dynamic>.from(balanceBody['data'] as Map)
          : <String, dynamic>{};

      num quota = (dataMap['monthlyQuotaMinutes'] ?? dataMap['monthlyQuotaMins']) as num? ?? 0;
      if (quota == 0 && dataMap['template'] is Map) {
        final t = dataMap['template'] as Map;
        quota = ((t['hours'] as num?) ?? 0) * 60 + ((t['minutes'] as num?) ?? 0);
      }
      num consumed = (dataMap['consumedMinutes'] ?? dataMap['usedMins']) as num? ?? 0;
      num remaining = (dataMap['remainingMinutes'] ?? dataMap['remainingMins']) as num? ?? 0;
      num pending = (dataMap['pendingMinutes'] ?? dataMap['pendingMins']) as num? ?? 0;

      if (remaining <= 0 && quota > 0 && consumed < quota) {
        remaining = (quota - consumed).clamp(0, quota);
      }

      dataMap['monthlyQuotaMinutes'] = quota;
      dataMap['consumedMinutes'] = consumed;
      dataMap['remainingMinutes'] = remaining;
      dataMap['pendingMinutes'] = pending;
      // Default to configured=true when the backend omits the flag
      dataMap['configured'] = true;
      dataMap['enabled'] = true;

      punchFlowLog(
        '[PermissionBalance][App] source=$sourceEndpoint '
        'month=${q['month']} year=${q['year']} '
        'quota=$quota consumed=$consumed remaining=$remaining pending=$pending '
        'configured=${dataMap['configured']} enabled=${dataMap['enabled']} '
        'raw=${balanceBody?['data']}',
      );

      return {'success': true, 'data': dataMap};
    } on DioException catch (e) {
      return {'success': false, 'message': _dioMessage(e)};
    } catch (e) {
      return {'success': false, 'message': _handleException(e)};
    }
  }

  /// Fetches PDF bytes from a full URL (e.g. Cloudinary payslipUrl). No auth.
  Future<Map<String, dynamic>> getPdfBytesFromUrl(String url) async {
    try {
      final uri = Uri.tryParse(url);
      if (uri == null || !uri.hasScheme) {
        return {'success': false, 'message': 'Invalid file URL'};
      }

      // Use a dedicated Dio (no baseUrl / auth interceptors) for absolute URLs.
      final dio = Dio(
        BaseOptions(
          responseType: ResponseType.bytes,
          followRedirects: true,
          receiveTimeout: const Duration(seconds: 30),
          sendTimeout: const Duration(seconds: 30),
          connectTimeout: const Duration(seconds: 30),
          validateStatus: (status) =>
              status != null && status >= 200 && status < 400,
          headers: {'Accept': '*/*'},
        ),
      );

      final response = await dio.get<List<int>>(url);
      final bytes = response.data;
      if (bytes != null && bytes.isNotEmpty) {
        return {'success': true, 'data': bytes};
      }
      return {'success': false, 'message': 'No data received'};
    } on DioException catch (e) {
      return {'success': false, 'message': _dioMessage(e)};
    } catch (e) {
      return {'success': false, 'message': _handleException(e)};
    }
  }

  /// Notifies the admin/manager that an employee has exceeded their leave or
  /// permission quota. Fire-and-forget — silently succeeds if the backend has
  /// not yet implemented POST /notifications/limit-exceeded.
  /// [type]: 'leave' or 'permission'
  Future<void> notifyAdminLimitExceeded({
    required String type,
    required num requested,
    required num limit,
  }) async {
    try {
      await _setToken();
      await _api.dio.post<dynamic>(
        '/notifications/limit-exceeded',
        data: {
          'type': type,
          'requested': requested,
          'limit': limit,
        },
      );
    } catch (_) {
      // Intentionally silent — admin notification is best-effort.
    }
  }

  // --- OVERTIME (Web Parity) ---

  /// Fetch employee's overtime requests & summary from web API:
  /// GET /staff/requests/overtime/my-requests?month=YYYY-MM&status=...
  Future<Map<String, dynamic>> getMyOvertimeRequests({
    String? month,
    String? status,
    String? date,
  }) async {
    try {
      await _setToken();
      final q = <String, dynamic>{
        if (month != null && month.isNotEmpty) 'month': month,
        if (status != null && status != 'All') 'status': status,
        if (date != null && date.isNotEmpty) 'date': date,
      };
      final response = await _api.dio.get<dynamic>(
        '/staff/requests/overtime/my-requests',
        queryParameters: q,
      );
      final body = response.data;
      if (body is Map && body['success'] == true) {
        return {'success': true, 'data': body['data'] ?? body};
      }
      return {'success': true, 'data': body};
    } on DioException catch (e) {
      return {'success': false, 'message': _dioMessage(e)};
    } catch (e) {
      return {'success': false, 'message': _handleException(e)};
    }
  }

  /// Respond to an overtime request (Accept / Reject) from web API:
  /// POST /staff/requests/overtime/respond/:id
  Future<Map<String, dynamic>> respondToOvertime({
    required String id,
    required String action, // 'Accepted' | 'Rejected'
  }) async {
    try {
      await _setToken();
      final response = await _api.dio.post<dynamic>(
        '/staff/requests/overtime/respond/$id',
        data: {'action': action},
      );
      final body = response.data;
      if (body is Map && body['success'] == true) {
        return {'success': true, 'data': body['data'] ?? body};
      }
      return {'success': true, 'data': body};
    } on DioException catch (e) {
      return {'success': false, 'message': _dioMessage(e)};
    } catch (e) {
      return {'success': false, 'message': _handleException(e)};
    }
  }

  String _handleException(dynamic error) {
    if (error is SocketException) {
      // SocketException can occur even with internet if server is unreachable
      String errorMsg = error.message.toLowerCase();
      if (errorMsg.contains('failed host lookup') ||
          errorMsg.contains('name resolution') ||
          errorMsg.contains('nodename nor servname provided')) {
        return 'Unable to reach server. Please check your internet connection or contact support if the problem persists.';
      } else if (errorMsg.contains('connection refused') ||
          errorMsg.contains('connection reset')) {
        return 'Server is not responding. Please try again in a moment or contact support.';
      } else {
        return 'Connection error5. Please check your internet connection and try again.';
      }
    } else if (error is TimeoutException) {
      return 'Connection timed out. Please try again.';
    } else if (error is FormatException) {
      return 'Invalid response format from server.';
    }

    String msg = error.toString();
    if (msg.startsWith('Exception: ')) {
      msg = msg.substring(11);
    }
    return msg;
  }
}
