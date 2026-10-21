// "Custom" permission window lifecycle (Start Permission / End Permission), the live-tracking
// counterpart to a Custom PermissionRequest (see request_service.dart createPermissionRequest).
// Mirrors services/break_service.dart's shape and resilience patterns (status caching, 409/400
// reconciliation, ambiguous-failure recovery) against the matching HRMSbackend endpoints:
//   GET  /staff/attendance/permission-status   -> PermissionWindowStatus (see staffPermissionService.ts)
//   POST /staff/attendance/permission/start
//   POST /staff/attendance/permission/end
// There is only ever one active window per day (no id to track, unlike break's breakId) - the
// server finds "the" active one from the attendance record, so start/end never need an id.
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/error_message_utils.dart';
import 'api_client.dart';

/// The server's PermissionWindowStatus shape (staffPermissionService.ts), parsed into one place so
/// every screen reading it agrees on the field names - same reasoning as BreakSummary.
class PermissionWindowStatus {
  final bool hasRequest;
  final String? requestStatus; // 'Pending' | 'Approved' | 'Rejected' | 'Cancelled'
  final int allowedMinutes;
  final int totalPermissionMinutes;
  final int remainingMinutes;
  final int excessMinutes;
  final bool isOnPermission;
  final DateTime? activeStartAt;
  final bool canStartPermission;
  final bool canEndPermission;

  const PermissionWindowStatus({
    required this.hasRequest,
    required this.requestStatus,
    required this.allowedMinutes,
    required this.totalPermissionMinutes,
    required this.remainingMinutes,
    required this.excessMinutes,
    required this.isOnPermission,
    required this.activeStartAt,
    required this.canStartPermission,
    required this.canEndPermission,
  });

  factory PermissionWindowStatus.fromJson(Map<String, dynamic> json) {
    final active = json['activePermission'];
    final startAtRaw = active is Map ? active['startAt'] : null;
    return PermissionWindowStatus(
      hasRequest: json['hasRequest'] == true,
      requestStatus: json['requestStatus']?.toString(),
      allowedMinutes: (json['allowedMinutes'] as num?)?.toInt() ?? 0,
      totalPermissionMinutes: (json['totalPermissionMinutes'] as num?)?.toInt() ?? 0,
      remainingMinutes: (json['remainingMinutes'] as num?)?.toInt() ?? 0,
      excessMinutes: (json['excessMinutes'] as num?)?.toInt() ?? 0,
      isOnPermission: json['isOnPermission'] == true,
      activeStartAt: startAtRaw != null ? DateTime.tryParse(startAtRaw.toString())?.toLocal() : null,
      canStartPermission: json['canStartPermission'] == true,
      canEndPermission: json['canEndPermission'] == true,
    );
  }

  /// Matches the web app's button label: "Apply for Permission" with no request yet,
  /// "Start Permission (Pending)" while awaiting approval, else "Start Permission" / "End
  /// Permission" once there is an approved budget.
  String get actionLabel {
    if (isOnPermission) return 'End Permission';
    if (!hasRequest) return 'Apply for Permission';
    if (requestStatus == 'Pending') return 'Start Permission (Pending)';
    return 'Start Permission';
  }
}

class PermissionService {
  final ApiClient _api = ApiClient();

  /// Bumped on every successful start/end so any screen showing permission state can refresh,
  /// mirroring BreakService.stateRevision.
  static final ValueNotifier<int> stateRevision = ValueNotifier<int>(0);

  static void resetForNewUser() {
    _lastStatusResponse = null;
    _lastStatusAt = null;
    _statusInFlight = null;
    stateRevision.value++;
  }

  Future<void> _setToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token != null && token.isNotEmpty) {
      _api.setAuthToken(token);
    }
  }

  // Shared in-flight/short-cache pattern from BreakService._getBreakStatus, so concurrent
  // callers (dashboard + requests screen at startup) share one round-trip.
  static Future<Response<Map<String, dynamic>>>? _statusInFlight;
  static Response<Map<String, dynamic>>? _lastStatusResponse;
  static DateTime? _lastStatusAt;

  Future<Response<Map<String, dynamic>>> _getStatusResponse() {
    final now = DateTime.now();
    if (_lastStatusResponse != null &&
        _lastStatusAt != null &&
        now.difference(_lastStatusAt!).inSeconds < 2) {
      return Future.value(_lastStatusResponse);
    }
    final pending = _statusInFlight;
    if (pending != null) return pending;
    final future = _api.dio.get<Map<String, dynamic>>('/staff/attendance/permission-status');
    _statusInFlight = future;
    future.then((res) {
      _lastStatusResponse = res;
      _lastStatusAt = DateTime.now();
    }).catchError((_) {}).whenComplete(() {
      if (identical(_statusInFlight, future)) _statusInFlight = null;
    }).ignore();
    return future;
  }

  /// Today's permission status (also returned inline on GET /staff/attendance/today-punch as
  /// `permissionStatus`, for screens that already load that).
  Future<Map<String, dynamic>> getStatus() async {
    try {
      await _setToken();
      final response = await _getStatusResponse();
      final body = response.data ?? <String, dynamic>{};
      final data = body['data'];
      if (data is! Map) {
        return {'success': false, 'message': 'Unexpected response from server.'};
      }
      return {
        'success': true,
        'status': PermissionWindowStatus.fromJson(Map<String, dynamic>.from(data)),
      };
    } on DioException catch (e) {
      return {
        'success': false,
        'message': ErrorMessageUtils.messageFromDioException(e, fallback: 'Failed to load permission status'),
      };
    } catch (e) {
      return {'success': false, 'message': ErrorMessageUtils.toUserFriendlyMessage(e)};
    }
  }

  void _bumpStateRevision() {
    _lastStatusResponse = null;
    stateRevision.value++;
  }

  Future<Map<String, dynamic>> startPermission({
    required double lat,
    required double lng,
    required String address,
    String? area,
    String? city,
    String? pincode,
    String? selfie,
  }) async {
    try {
      await _setToken();
      final bodyData = {
        'latitude': lat,
        'longitude': lng,
        'accuracy': 10,
        'address': address,
        'locationName': address,
        'area': area,
        'city': city,
        'pincode': pincode,
        if (selfie != null && selfie.isNotEmpty) 'selfie': selfie,
        'device': 'Mobile App',
      };
      final response = await _api.dio.post<Map<String, dynamic>>(
        '/staff/attendance/permission/start',
        data: bodyData,
      );
      _bumpStateRevision();
      return {
        'success': true,
        'message': response.data?['message'],
        'data': response.data?['data'],
      };
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      final body = e.response?.data;
      // Race / duplicate start: the server already has one running. Re-read the real state
      // rather than guessing, same reasoning as BreakService's ambiguous-failure recovery.
      final ambiguousFailure =
          status == null ||
          (status >= 500 && status <= 599) ||
          e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.sendTimeout ||
          e.type == DioExceptionType.connectionError;
      if (status == 400 || ambiguousFailure) {
        final recovered = await getStatus();
        if (recovered['success'] == true) {
          final s = recovered['status'] as PermissionWindowStatus;
          if (s.isOnPermission) {
            _bumpStateRevision();
            return {'success': true, 'message': 'Permission started', 'status': s};
          }
        }
      }
      final msg = body is Map ? body['message']?.toString() : null;
      return {
        'success': false,
        'message': msg ?? ErrorMessageUtils.messageFromDioException(e, fallback: 'Failed to start permission'),
      };
    } catch (e) {
      return {'success': false, 'message': ErrorMessageUtils.toUserFriendlyMessage(e)};
    }
  }

  Future<Map<String, dynamic>> endPermission({
    required double lat,
    required double lng,
    required String address,
    String? area,
    String? city,
    String? pincode,
    String? selfie,
  }) async {
    try {
      await _setToken();
      final bodyData = {
        'latitude': lat,
        'longitude': lng,
        'accuracy': 10,
        'address': address,
        'locationName': address,
        'area': area,
        'city': city,
        'pincode': pincode,
        if (selfie != null && selfie.isNotEmpty) 'selfie': selfie,
        'device': 'Mobile App',
      };
      final response = await _api.dio.post<Map<String, dynamic>>(
        '/staff/attendance/permission/end',
        data: bodyData,
      );
      _bumpStateRevision();
      return {
        'success': true,
        'message': response.data?['message'],
        'data': response.data?['data'],
      };
    } on DioException catch (e) {
      final body = e.response?.data;
      final msg = body is Map ? body['message']?.toString() : null;
      // "No permission window is currently running" - already ended elsewhere (e.g. auto-closed
      // on punch out): treat as success, matching BreakService's equivalent reconciliation.
      if (msg != null && msg.toLowerCase().contains('no permission window')) {
        _bumpStateRevision();
        return {'success': true, 'message': 'No active permission window'};
      }
      return {
        'success': false,
        'message': msg ?? ErrorMessageUtils.messageFromDioException(e, fallback: 'Failed to end permission'),
      };
    } catch (e) {
      return {'success': false, 'message': ErrorMessageUtils.toUserFriendlyMessage(e)};
    }
  }
}
