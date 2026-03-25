import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/error_message_utils.dart';
import 'api_client.dart';

class BreakService {
  final ApiClient _api = ApiClient();

  Future<void> _setToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token != null && token.isNotEmpty) {
      _api.setAuthToken(token);
    }
  }

  Future<Map<String, dynamic>> getCurrentBreak() async {
    try {
      await _setToken();
      final response = await _api.dio.get<Map<String, dynamic>>('/breaks/current');
      final data = response.data ?? <String, dynamic>{};
      return {'success': true, 'data': data['data']};
    } on DioException catch (e) {
      return {
        'success': false,
        'message': ErrorMessageUtils.messageFromDioException(
          e,
          fallback: 'Failed to load break status',
        ),
      };
    } catch (e) {
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
    try {
      await _setToken();
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
          'startTime': DateTime.now().toIso8601String(),
        },
      );
      return {
        'success': true,
        'data': response.data?['data'],
        'message': response.data?['message'],
      };
    } on DioException catch (e) {
      return {
        'success': false,
        'message': ErrorMessageUtils.messageFromDioException(
          e,
          fallback: 'Failed to start break',
        ),
        'data': e.response?.data is Map
            ? (e.response?.data as Map)['data']
            : null,
      };
    } catch (e) {
      return {
        'success': false,
        'message': ErrorMessageUtils.toUserFriendlyMessage(e),
      };
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
          'endTime': DateTime.now().toIso8601String(),
        },
      );
      return {
        'success': true,
        'data': response.data?['data'],
        'message': response.data?['message'],
      };
    } on DioException catch (e) {
      return {
        'success': false,
        'message': ErrorMessageUtils.messageFromDioException(
          e,
          fallback: 'Failed to end break',
        ),
      };
    } catch (e) {
      return {
        'success': false,
        'message': ErrorMessageUtils.toUserFriendlyMessage(e),
      };
    }
  }
}
