import 'package:dio/dio.dart';
import 'auth_service.dart';
import 'api_client.dart';
import '../utils/error_message_utils.dart';

/// Web RTK parity: `settingsApi` (e.g. `useGetBusinessQuery`).
/// Endpoint may be absent on minimal dev backends — callers should tolerate failure.
class SettingsService {
  final AuthService _authService = AuthService();
  final ApiClient _api = ApiClient();

  Future<void> _setToken() async {
    final token = await _authService.getToken();
    if (token != null && token.isNotEmpty) _api.setAuthToken(token);
  }

  /// Web: `GET /settings/business` — EmployeeSalaryOverview uses this for weekly-off fallback.
  Future<Map<String, dynamic>> getBusiness() async {
    try {
      await _setToken();
      final response = await _api.dio.get<Map<String, dynamic>>(
        '/settings/business',
      );
      final body = response.data;
      if (body != null && body['success'] == true) {
        return Map<String, dynamic>.from(body);
      }
      return {'success': false};
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return {'success': false};
      return {'success': false, 'message': ErrorMessageUtils.messageFromDioException(e)};
    } catch (_) {
      return {'success': false};
    }
  }
}
