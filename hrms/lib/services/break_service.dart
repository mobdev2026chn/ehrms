import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/break_flow_log.dart';
import '../utils/error_message_utils.dart';
import 'api_client.dart';

class BreakService {
  final ApiClient _api = ApiClient();

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
      final response = await _api.dio.get<Map<String, dynamic>>('/breaks/current');
      final data = response.data ?? <String, dynamic>{};
      final row = data['data'];
      breakFlowLog(
        'getCurrentBreak <- http=${response.statusCode} '
        'hasActive=${data['hasActiveBreak']} ${_snapshotBreakRow(row)}',
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

  Future<Map<String, dynamic>> startBreak({
    required double lat,
    required double lng,
    required String address,
    String? area,
    String? city,
    String? pincode,
    required String selfie,
  }) async {
    breakFlowLog(
      'startBreak -> POST /breaks/start lat=$lat lng=$lng '
      'selfieLen=${selfie.length} payloadStartTime sent in body',
    );
    try {
      await _setToken();
      final payloadStart = DateTime.now().toUtc().toIso8601String();
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
      final ambiguousFailure = status == null ||
          (status >= 500 && status <= 599) ||
          e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.sendTimeout ||
          e.type == DioExceptionType.connectionError;
      if (ambiguousFailure) {
        breakFlowLog('startBreak -> GET /breaks/current (recover after ambiguous failure)');
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
        breakFlowLog('startBreak recover: no open break from GET /breaks/current');
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
  }) async {
    breakFlowLog(
      'endBreak -> PATCH /breaks/$breakId/end lat=$lat lng=$lng selfieLen=${selfie.length}',
    );
    try {
      await _setToken();
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
          'endTime': DateTime.now().toUtc().toIso8601String(),
        },
      );
      breakFlowLog(
        'endBreak <- ok http=${response.statusCode} ${_snapshotBreakRow(response.data?['data'])}',
      );
      return {
        'success': true,
        'data': response.data?['data'],
        'message': response.data?['message'],
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
