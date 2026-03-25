import 'dart:io';
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/holiday_model.dart';
import '../utils/error_message_utils.dart';
import 'api_client.dart';

class HolidayService {
  final ApiClient _api = ApiClient();

  Future<void> _setToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token != null && token.isNotEmpty) _api.setAuthToken(token);
  }

  Future<Map<String, dynamic>> getHolidays({
    int? year,
    int? month,
    String? search,
  }) async {
    try {
      await _setToken();
      final response = await _api.dio.get<Map<String, dynamic>>(
        '/holidays/employee',
        queryParameters: {
          'limit': 100,
          if (year != null) 'year': year,
          if (month != null) 'month': month,
          if (search != null && search.isNotEmpty) 'search': search,
        },
      );
      final body = response.data;
      if (body != null && body['success'] == true) {
        final data = body['data'];
        List<Holiday> holidays = [];
        if (data != null && data['holidays'] != null) {
          holidays = (data['holidays'] as List)
              .map((json) => Holiday.fromJson(json as Map<String, dynamic>))
              .toList();
        }
        return {'success': true, 'data': holidays};
      }
      return {
        'success': false,
        'message':
            ErrorMessageUtils.messageFromResponseData(body) ??
                'Failed to load holidays',
      };
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return {'success': true, 'data': <Holiday>[]};
      }
      return {'success': false, 'message': _dioMessage(e)};
    } catch (e) {
      return {'success': false, 'message': _handleException(e)};
    }
  }

  String _dioMessage(DioException e) {
    return ErrorMessageUtils.messageFromDioException(e);
  }

  String _handleException(dynamic error) {
    if (error is SocketException) {
      final msg = error.message.toLowerCase();
      if (msg.contains('failed host lookup') || msg.contains('name resolution')) {
        return 'Unable to reach server. Please check your internet connection or contact support.';
      }
      if (msg.contains('connection refused') || msg.contains('connection reset')) {
        return 'Server is not responding. Please try again in a moment or contact support.';
      }
      return 'Connection error. Please check your internet connection and try again.';
    }
    if (error is TimeoutException) {
      return 'Connection timed out. The server is taking too long to respond. Please try again.';
    }
    if (error is FormatException) {
      return 'Invalid response format from server. Please try again.';
    }
    return error.toString();
  }
}
