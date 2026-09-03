import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
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

  /// Stored start time of the ongoing break so the live timer is cumulative
  /// (start time -> current time) and NEVER resets to 00:00 on navigation or reload.
  static DateTime? lastKnownBreakStartTime;
  static const String _kBreakStartPrefsKey = 'persisted_active_break_start_time';

  static Future<void> persistActiveBreakStart(DateTime? startTime) async {
    lastKnownBreakStartTime = startTime;
    final prefs = await SharedPreferences.getInstance();
    if (startTime != null) {
      await prefs.setString(_kBreakStartPrefsKey, startTime.toIso8601String());
    } else {
      await prefs.remove(_kBreakStartPrefsKey);
    }
  }

  static Future<DateTime?> getPersistedActiveBreakStart() async {
    if (lastKnownBreakStartTime != null) return lastKnownBreakStartTime;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kBreakStartPrefsKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final dt = DateTime.parse(raw).toLocal();
        lastKnownBreakStartTime = dt;
        return dt;
      } catch (_) {}
    }
    return null;
  }

  static DateTime? parseTimeStringToToday(String timeStr) {
    try {
      final now = DateTime.now();
      final clean = timeStr.trim();
      for (final fmt in ['hh:mm a', 'h:mm a', 'hh:mma', 'h:mma', 'HH:mm', 'H:mm']) {
        try {
          final d = DateFormat(fmt).parseLoose(clean);
          return DateTime(now.year, now.month, now.day, d.hour, d.minute);
        } catch (_) {}
      }
      return null;
    } catch (_) {
      return null;
    }
  }

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
    final id = (m['id'] ?? m['_id'])?.toString().trim();
    if (id == null || id.isEmpty || id == 'null') return false;
    final end = m['endTime'];
    return end == null || end.toString().isEmpty || end.toString() == 'null';
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
      Response<Map<String, dynamic>> response;
      try {
        response = await _api.dio.get<Map<String, dynamic>>(
          '/breaks/current',
        );
      } on DioException catch (de) {
        if (de.response?.statusCode == 404) {
          response = await _api.dio.get<Map<String, dynamic>>(
            '/staff/attendance/break-status',
          );
        } else {
          rethrow;
        }
      }
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
      if (!isOpen) {
        try {
          final bsRes = await _api.dio.get<Map<String, dynamic>>(
            '/staff/attendance/break-status',
          );
          if (bsRes.statusCode == 200 && bsRes.data is Map) {
            final bsData = bsRes.data!['data'];
            if (bsData is Map && bsData['isOnBreak'] == true) {
              final ab = bsData['activeBreak'];
              final start = (ab is Map) ? (ab['startTime'] ?? ab['startAt']) : null;
              final startDt = (start != null && start.toString().isNotEmpty)
                  ? parseTimeStringToToday(start.toString())
                  : null;
              if (startDt != null) {
                await persistActiveBreakStart(startDt);
              }
              lastKnownHasOpenBreak = true;
              return {
                'success': true,
                'hasActiveBreak': true,
                'data': {
                  'startTime': start,
                  'endTime': null,
                  'ongoing': true,
                },
              };
            }
          }
        } catch (_) {}
      }
      await BreakReminderService.sync(
        hasOpenBreak: isOpen,
        startedAt: isOpen ? _parseStartTime(rowMap) : null,
      );
      return {'success': true, 'data': isOpen ? rowMap : null};
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
    breakFlowLog('getTodayBreakSummary -> GET /staff/attendance/break-status');
    try {
      await _setToken();
      Response<Map<String, dynamic>> response;
      try {
        response = await _api.dio.get<Map<String, dynamic>>(
          '/staff/attendance/break-status',
        );
      } on DioException catch (de) {
        if (de.response?.statusCode == 404 || de.response?.statusCode == 405) {
          response = await _api.dio.get<Map<String, dynamic>>(
            '/breaks/today',
          );
        } else {
          rethrow;
        }
      }
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
      Response<Map<String, dynamic>> response;
      final bodyData = {
        'latitude': lat,
        'longitude': lng,
        'accuracy': 10,
        'address': address,
        'locationName': address,
        'area': area,
        'city': city,
        'pincode': pincode,
        'selfie': selfie,
        'device': 'Mobile App',
        'startTime': payloadStart,
        'timeStr': payloadStart,
      };
      try {
        response = await _api.dio.post<Map<String, dynamic>>(
          '/staff/attendance/break/start',
          data: bodyData,
        );
      } catch (postErr) {
        if (postErr is DioException && (postErr.response?.statusCode == 404 || postErr.response?.statusCode == 405)) {
          response = await _api.dio.post<Map<String, dynamic>>(
            '/breaks/start',
            data: bodyData,
          );
        } else if (postErr is DioException && postErr.response?.statusCode == 413) {
          final noSelfie = Map<String, dynamic>.from(bodyData)..remove('selfie');
          response = await _api.dio.post<Map<String, dynamic>>(
            '/staff/attendance/break/start',
            data: noSelfie,
          );
        } else {
          rethrow;
        }
      }
      breakFlowLog(
        'startBreak <- ok http=${response.statusCode} '
        '${_snapshotBreakRow(response.data?['data'])} '
        'msg=${response.data?['message']}',
      );
      // Break just opened — begin the every-10-minute "break ongoing" reminder,
      // anchored to the server's break start time when available.
      final startDt = _parseStartTime(_breakMapFrom(response.data?['data'])) ?? DateTime.now();
      await BreakReminderService.schedule(
        startedAt: startDt,
      );
      await persistActiveBreakStart(startDt);
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
      if ((status == 409 || status == 400) && body is Map) {
        final embedded = _breakMapFrom(body['data']);
        if (_isOpenBreakMap(embedded)) {
          final startDt = _parseStartTime(embedded) ?? DateTime.now();
          await persistActiveBreakStart(startDt);
          lastKnownHasOpenBreak = true;
          _bumpStateRevision();
          breakFlowLog(
            'startBreak reconcile $status -> treat as success ${_snapshotBreakRow(embedded)}',
          );
          return {
            'success': true,
            'data': embedded,
            'message': 'Break started successfully',
          };
        }
        final msg = body['message']?.toString() ?? '';
        if (msg.toLowerCase().contains('already running') ||
            msg.toLowerCase().contains('already on break')) {
          lastKnownHasOpenBreak = true;
          final match = RegExp(r'(\d{1,2}:\d{2}\s*(?:AM|PM|am|pm)?)').firstMatch(msg);
          if (match != null) {
            final timeStr = match.group(1)?.trim();
            if (timeStr != null) {
              final parsed = parseTimeStringToToday(timeStr);
              if (parsed != null) {
                await persistActiveBreakStart(parsed);
              }
            }
          }
          _bumpStateRevision();
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
      if (breakId.isEmpty || breakId == 'null') {
        final active = await getCurrentBreak();
        if (active['success'] == true && active['data'] is Map) {
          breakId = (active['data']['id'] ?? active['data']['_id'] ?? active['data']['breakId'])?.toString() ?? '';
        }
      }
      if (breakId.isEmpty || breakId == 'null') {
        try {
          final attRes = await _api.dio.get<Map<String, dynamic>>('/attendance/today');
          if (attRes.statusCode == 200 && attRes.data is Map) {
            final root = attRes.data!;
            final inner = (root['data'] is Map) ? root['data'] as Map : root;
            final brk = inner['break'];
            if (brk is Map && brk['breaks'] is List) {
              for (final b in (brk['breaks'] as List)) {
                if (b is Map) {
                  final end = b['endTime'];
                  final isOngoing = end == null || end.toString().isEmpty || end.toString() == 'null';
                  if (isOngoing) {
                    final foundId = (b['id'] ?? b['_id'] ?? b['breakId'])?.toString();
                    if (foundId != null && foundId.isNotEmpty && foundId != 'null') {
                      breakId = foundId;
                      break;
                    }
                  }
                }
              }
            }
          }
        } catch (_) {}
      }

      final payloadEnd = (clientTime != null && clientTime.isNotEmpty)
          ? clientTime
          : DateTime.now().toUtc().toIso8601String();
      Response<Map<String, dynamic>> response;
      final bodyData = {
        'latitude': lat,
        'longitude': lng,
        'accuracy': 10,
        'address': address,
        'locationName': address,
        'area': area,
        'city': city,
        'pincode': pincode,
        'selfie': selfie,
        'device': 'Mobile App',
        'endTime': payloadEnd,
        'timeStr': payloadEnd,
      };
      
      final candidates = <String>[
        '/staff/attendance/break/end',
      ];
      if (breakId.isNotEmpty && breakId != 'null') {
        candidates.add('/breaks/$breakId/end');
      }
      candidates.add('/breaks/end');

      Response<Map<String, dynamic>>? successfulRes;
      DioException? lastDioException;

      for (final endpoint in candidates) {
        // Try POST first (matching official /staff/attendance/break/end), then PATCH
        try {
          final res = await _api.dio.post<Map<String, dynamic>>(
            endpoint,
            data: bodyData,
          );
          if (res.statusCode == 200 || res.statusCode == 201) {
            successfulRes = res;
            break;
          }
        } on DioException catch (de) {
          lastDioException = de;
          if (de.response?.statusCode == 404 || de.response?.statusCode == 405) {
            try {
              final res = await _api.dio.patch<Map<String, dynamic>>(
                endpoint,
                data: bodyData,
              );
              if (res.statusCode == 200 || res.statusCode == 201) {
                successfulRes = res;
                break;
              }
            } catch (_) {}
          } else if (de.response?.statusCode == 413) {
            final noSelfie = Map<String, dynamic>.from(bodyData)..remove('selfie');
            try {
              final res = await _api.dio.post<Map<String, dynamic>>(
                endpoint,
                data: noSelfie,
              );
              if (res.statusCode == 200 || res.statusCode == 201) {
                successfulRes = res;
                break;
              }
            } catch (_) {}
          }
        } catch (_) {}
      }

      if (successfulRes != null) {
        response = successfulRes;
      } else if (lastDioException != null) {
        final status = lastDioException.response?.statusCode;
        final body = lastDioException.response?.data;
        final msg = body is Map ? body['message']?.toString() : null;
        if (status == 404 ||
            (msg != null &&
                (msg.toLowerCase().contains('no break') ||
                    msg.toLowerCase().contains('not found') ||
                    msg.toLowerCase().contains('already')))) {
          await BreakReminderService.cancel();
          await persistActiveBreakStart(null);
          lastKnownHasOpenBreak = false;
          _bumpStateRevision();
          return {
            'success': true,
            'message': 'Break ended successfully',
          };
        }
        throw lastDioException;
      } else {
        await BreakReminderService.cancel();
        await persistActiveBreakStart(null);
        lastKnownHasOpenBreak = false;
        _bumpStateRevision();
        return {
          'success': true,
          'message': 'Break ended successfully',
        };
      }

      breakFlowLog(
        'endBreak <- ok http=${response.statusCode} ${_snapshotBreakRow(response.data?['data'])}',
      );
      // Break closed — stop the every-10-minute reminder immediately.
      await BreakReminderService.cancel();
      await persistActiveBreakStart(null);
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
      final status = e.response?.statusCode;
      final body = e.response?.data;
      final msg = body is Map ? body['message']?.toString() : null;
      if (msg != null && (msg.contains('No break') || msg.contains('not found') || status == 404)) {
        await BreakReminderService.cancel();
        lastKnownHasOpenBreak = false;
        _bumpStateRevision();
        return {
          'success': true,
          'message': 'No active break running',
        };
      }
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
