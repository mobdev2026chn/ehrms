import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/break_flow_log.dart';
import '../utils/error_message_utils.dart';
import 'api_client.dart';
import 'break_reminder_service.dart';

class BreakService {
  final ApiClient _api = ApiClient();

  /// Bumped on every successful break start/end so any screen showing break
  /// state (e.g. the dashboard's "break ongoing" card) can refresh — including
  /// when the break is ended from a different surface, such as the break screen
  /// opened by the reminder notification's "End Break" action.
  static final ValueNotifier<int> stateRevision = ValueNotifier<int>(0);

  /// Set to true/false after a successful start/end so listeners can optimistically
  /// update without waiting for the next API round-trip.
  static bool? lastKnownHasOpenBreak;

  static void _bumpStateRevision() => stateRevision.value++;

  static String _snapshotBreakRow(dynamic raw) {
    final m = _breakMapFrom(raw);
    if (m == null) return 'row=null';
    return 'id=${m['id']} startTime=${m['startTime']} endTime=${m['endTime']}';
  }

  static Map<String, dynamic>? _breakMapFrom(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return null;
  }

  /// Break row's start time as a [DateTime] (used to anchor the reminder's
  /// elapsed-minute count), or null when absent/unparseable.
  static DateTime? _parseStartTime(Map<String, dynamic>? m) {
    final raw = m?['startTime']?.toString();
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  /// True when API returned a break row that is still open (no end time).
  static bool _isOpenBreakMap(Map<String, dynamic>? m) {
    if (m == null) return false;
    final id = m['id']?.toString().trim();
    if (id == null || id.isEmpty) return false;
    return m['endTime'] == null;
  }

  Future<void> _setToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token != null && token.isNotEmpty) {
      _api.setAuthToken(token);
    }
  }

  Future<Map<String, dynamic>> getCurrentBreak() async {
    breakFlowLog('getCurrentBreak -> GET /breaks/current');
    try {
      await _setToken();
      final response = await _api.dio.get<Map<String, dynamic>>(
        '/breaks/current',
      );
      final data = response.data ?? <String, dynamic>{};
      final row = data['data'];
      breakFlowLog(
        'getCurrentBreak <- http=${response.statusCode} '
        'hasActive=${data['hasActiveBreak']} ${_snapshotBreakRow(row)}',
      );
      // Keep the every-10-minute break reminder in sync with the real break
      // state: schedule while a break is open, clear it once ended. Covers app
      // restarts and breaks ended from other flows (e.g. auto-end on checkout).
      final rowMap = _breakMapFrom(row);
      final isOpen = _isOpenBreakMap(rowMap);
      await BreakReminderService.sync(
        hasOpenBreak: isOpen,
        startedAt: isOpen ? _parseStartTime(rowMap) : null,
      );
      return {'success': true, 'data': row};
    } on DioException catch (e) {
      breakFlowLog(
        'getCurrentBreak <- dio status=${e.response?.statusCode} '
        'type=${e.type} msg=${e.message}',
      );
      return {
        'success': false,
        'message': ErrorMessageUtils.messageFromDioException(
          e,
          fallback: 'Failed to load break status',
        ),
      };
    } catch (e) {
      breakFlowLog('getCurrentBreak <- error $e');
      return {
        'success': false,
        'message': ErrorMessageUtils.toUserFriendlyMessage(e),
      };
    }
  }

  /// Daily break summary (today's breaks ascending, total used, allowed quota,
  /// remaining balance). Authoritative source for the punch card list/total and
  /// the break screen balance.
  Future<Map<String, dynamic>> getTodayBreakSummary() async {
    breakFlowLog('getTodayBreakSummary -> GET /breaks/today');
    try {
      await _setToken();
      final response = await _api.dio.get<Map<String, dynamic>>(
        '/breaks/today',
      );
      final data = response.data ?? <String, dynamic>{};
      final row = data['data'];
      breakFlowLog(
        'getTodayBreakSummary <- http=${response.statusCode} '
        'count=${row is Map ? (row['totalBreakCount']) : '?'} '
        'totalMin=${row is Map ? (row['totalBreakMin']) : '?'} '
        'remainingMin=${row is Map ? (row['remainingMin']) : '?'}',
      );
      return {
        'success': true,
        'data': row is Map ? Map<String, dynamic>.from(row) : null,
      };
    } on DioException catch (e) {
      breakFlowLog(
        'getTodayBreakSummary <- dio status=${e.response?.statusCode} '
        'type=${e.type} msg=${e.message}',
      );
      return {
        'success': false,
        'message': ErrorMessageUtils.messageFromDioException(
          e,
          fallback: 'Failed to load break summary',
        ),
      };
    } catch (e) {
      breakFlowLog('getTodayBreakSummary <- error $e');
      return {
        'success': false,
        'message': ErrorMessageUtils.toUserFriendlyMessage(e),
      };
    }
  }

  Future<Map<String, dynamic>> startBreak({
    required double lat,
    required double lng,
    required String address,
    String? area,
    String? city,
    String? pincode,
    required String selfie,
    String? clientTime,
  }) async {
    breakFlowLog(
      'startBreak -> POST /breaks/start lat=$lat lng=$lng '
      'selfieLen=${selfie.length} payloadStartTime sent in body',
    );
    try {
      await _setToken();
      // Button-tap instant captured by the screen; falls back to now if not provided.
      // The server stores this as the break start so location-load latency does not
      // push the saved start time forward.
      final payloadStart = (clientTime != null && clientTime.isNotEmpty)
          ? clientTime
          : DateTime.now().toUtc().toIso8601String();
      final response = await _api.dio.post<Map<String, dynamic>>(
        '/breaks/start',
        data: {
          'latitude': lat,
          'longitude': lng,
          'address': address,
          'area': area,
          'city': city,
          'pincode': pincode,
          'selfie': selfie,
          'startTime': payloadStart,
        },
      );
      breakFlowLog(
        'startBreak <- ok http=${response.statusCode} '
        '${_snapshotBreakRow(response.data?['data'])} '
        'msg=${response.data?['message']}',
      );
      // Break just opened — begin the every-10-minute "break ongoing" reminder,
      // anchored to the server's break start time when available.
      await BreakReminderService.schedule(
        startedAt: _parseStartTime(_breakMapFrom(response.data?['data'])),
      );
      lastKnownHasOpenBreak = true;
      _bumpStateRevision();
      return {
        'success': true,
        'data': response.data?['data'],
        'message': response.data?['message'],
      };
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      final body = e.response?.data;
      breakFlowLog(
        'startBreak <- dio status=$status type=${e.type} '
        'msg=${e.message}',
      );

      // Duplicate start / race: server already has an open break for this user.
      if (status == 409 && body is Map) {
        final embedded = _breakMapFrom(body['data']);
        if (_isOpenBreakMap(embedded)) {
          breakFlowLog(
            'startBreak reconcile 409 -> treat as success ${_snapshotBreakRow(embedded)}',
          );
          return {
            'success': true,
            'data': embedded,
            'message': 'Break started successfully',
          };
        }
      }

      // Request failed on the client (timeout, connection) or gateway error,
      // but POST may still have succeeded — confirm with GET /breaks/current.
      final ambiguousFailure =
          status == null ||
          (status >= 500 && status <= 599) ||
          e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.sendTimeout ||
          e.type == DioExceptionType.connectionError;
      if (ambiguousFailure) {
        breakFlowLog(
          'startBreak -> GET /breaks/current (recover after ambiguous failure)',
        );
        final recovered = await _fetchOpenBreakIfAny();
        if (_isOpenBreakMap(recovered)) {
          breakFlowLog(
            'startBreak reconcile after failure -> success ${_snapshotBreakRow(recovered)}',
          );
          return {
            'success': true,
            'data': recovered,
            'message': 'Break started successfully',
          };
        }
        breakFlowLog(
          'startBreak recover: no open break from GET /breaks/current',
        );
      }

      breakFlowLog(
        'startBreak <- fail userMsg=${ErrorMessageUtils.messageFromDioException(e, fallback: 'Failed to start break')}',
      );
      return {
        'success': false,
        'message': ErrorMessageUtils.messageFromDioException(
          e,
          fallback: 'Failed to start break',
        ),
        'data': body is Map ? body['data'] : null,
      };
    } catch (e) {
      breakFlowLog('startBreak <- catch $e');
      return {
        'success': false,
        'message': ErrorMessageUtils.toUserFriendlyMessage(e),
      };
    }
  }

  Future<Map<String, dynamic>?> _fetchOpenBreakIfAny() async {
    try {
      final r = await getCurrentBreak();
      if (r['success'] != true) return null;
      return _breakMapFrom(r['data']);
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> endBreak({
    required String breakId,
    required double lat,
    required double lng,
    required String address,
    String? area,
    String? city,
    String? pincode,
    required String selfie,
    String? clientTime,
  }) async {
    breakFlowLog(
      'endBreak -> PATCH /breaks/$breakId/end lat=$lat lng=$lng selfieLen=${selfie.length}',
    );
    try {
      await _setToken();
      // Button-tap instant captured by the screen; falls back to now if not provided.
      final payloadEnd = (clientTime != null && clientTime.isNotEmpty)
          ? clientTime
          : DateTime.now().toUtc().toIso8601String();
      final response = await _api.dio.patch<Map<String, dynamic>>(
        '/breaks/$breakId/end',
        data: {
          'latitude': lat,
          'longitude': lng,
          'address': address,
          'area': area,
          'city': city,
          'pincode': pincode,
          'selfie': selfie,
          'endTime': payloadEnd,
        },
      );
      breakFlowLog(
        'endBreak <- ok http=${response.statusCode} ${_snapshotBreakRow(response.data?['data'])}',
      );
      // Break closed — stop the every-10-minute reminder immediately.
      await BreakReminderService.cancel();
      lastKnownHasOpenBreak = false;
      _bumpStateRevision();
      return {
        'success': true,
        'data': response.data?['data'],
        'message': response.data?['message'],
        // Exact policy notice + exceeded minutes for the break that just ended.
        'notice': response.data?['notice'],
        'exceededMinutes': response.data?['exceededMinutes'],
      };
    } on DioException catch (e) {
      breakFlowLog(
        'endBreak <- dio status=${e.response?.statusCode} type=${e.type} msg=${e.message}',
      );
      return {
        'success': false,
        'message': ErrorMessageUtils.messageFromDioException(
          e,
          fallback: 'Failed to end break',
        ),
      };
    } catch (e) {
      breakFlowLog('endBreak <- catch $e');
      return {
        'success': false,
        'message': ErrorMessageUtils.toUserFriendlyMessage(e),
      };
    }
  }
}
