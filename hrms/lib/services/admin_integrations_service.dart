// Admin "Integrations" against HRMSbackend - the same APIs the web uses:
//   /admin/integrations/google-calendar/*  (routes/admin/googleCalendarRoute.ts,
//   controllers/admin/recruitment/googleCalendar/googleCalendarController.ts)
//     GET    /status       -> {configured, connected, needsReconnect, googleEmail, connectedByName, connectedAt}
//     GET    /connect-url  -> {url}   (query: origin, returnTo)
//     DELETE /             -> status after disconnecting
// The email services (SMTP, SendGrid, SendPulse) have no backend yet.
// Every call throws an Exception carrying the server's message on failure.

import 'package:dio/dio.dart';

import 'api_client.dart';

class GoogleCalendarStatus {
  final bool configured; // server has GOOGLE_CLIENT_ID / GOOGLE_CLIENT_SECRET
  final bool connected;
  final bool needsReconnect;
  final String googleEmail;
  final String connectedByName;
  final DateTime? connectedAt;

  const GoogleCalendarStatus({
    required this.configured,
    required this.connected,
    required this.needsReconnect,
    required this.googleEmail,
    required this.connectedByName,
    required this.connectedAt,
  });

  factory GoogleCalendarStatus.fromJson(Map<String, dynamic> j) => GoogleCalendarStatus(
        configured: j['configured'] == true,
        connected: j['connected'] == true,
        needsReconnect: j['needsReconnect'] == true,
        googleEmail: (j['googleEmail'] ?? '').toString(),
        connectedByName: (j['connectedByName'] ?? '').toString(),
        connectedAt: j['connectedAt'] == null ? null : DateTime.tryParse(j['connectedAt'].toString())?.toLocal(),
      );
}

class AdminIntegrationsService {
  final ApiClient _api = ApiClient();

  static const _base = '/admin/integrations/google-calendar';

  static Map<String, dynamic> _data(Response<dynamic> res) {
    final body = res.data;
    if (body is Map && body['success'] == true) {
      final d = body['data'];
      return d is Map ? Map<String, dynamic>.from(d) : <String, dynamic>{};
    }
    throw Exception(body is Map ? (body['message'] ?? 'Request failed') : 'Request failed');
  }

  static Exception _error(Object e, String fallback) {
    if (e is DioException) {
      final body = e.response?.data;
      final msg = body is Map ? body['message']?.toString() : null;
      if (msg != null && msg.isNotEmpty) return Exception(msg);
      if (e.response == null) return Exception('$fallback. Please check your connection.');
    }
    if (e is Exception) return e;
    return Exception(fallback);
  }

  Future<GoogleCalendarStatus> getGoogleCalendarStatus() async {
    try {
      return GoogleCalendarStatus.fromJson(_data(await _api.dio.get<dynamic>('$_base/status')));
    } catch (e) {
      throw _error(e, 'Could not load the Google Calendar status');
    }
  }

  /// Google's consent screen URL. The backend falls back to its first allowed web origin when
  /// [origin] is not one of them, so after consent Google returns the admin to the web page
  /// at [returnTo]; the app refreshes the status when it is resumed.
  Future<String> getGoogleCalendarConnectUrl({
    String returnTo = '/admin/integrations/google-calendar',
    String? origin,
  }) async {
    try {
      final d = _data(await _api.dio.get<dynamic>(
        '$_base/connect-url',
        queryParameters: {'returnTo': returnTo, if (origin != null) 'origin': origin},
      ));
      final url = (d['url'] ?? '').toString();
      if (url.isEmpty) throw Exception('The server did not return a Google sign-in link');
      return url;
    } catch (e) {
      throw _error(e, 'Could not start the Google connection');
    }
  }

  /// Disconnects the company's Google account. Returns the status afterwards.
  Future<GoogleCalendarStatus> disconnectGoogleCalendar() async {
    try {
      return GoogleCalendarStatus.fromJson(_data(await _api.dio.delete<dynamic>(_base)));
    } catch (e) {
      throw _error(e, 'Could not disconnect the Google account');
    }
  }
}
