import 'dart:io';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/constants.dart';
import '../utils/error_message_utils.dart';
import 'api_client.dart';

class GrievanceService {
  final ApiClient _api = ApiClient();

  Future<void> _setToken() async {
    final prefs = await SharedPreferences.getInstance();
    String? token = prefs.getString('token');
    if (token != null && (token.startsWith('"') || token.endsWith('"'))) {
      token = token.replaceAll('"', '');
    }
    if (token != null && token.isNotEmpty) _api.setAuthToken(token);
  }

  String _dioMessage(DioException e) {
    return ErrorMessageUtils.messageFromDioException(e);
  }

  Future<Map<String, dynamic>> getCategories() async {
    try {
      await _setToken();
      final response = await _api.dio.get<Map<String, dynamic>>(
        '/grievances/categories/list',
        queryParameters: {'isActive': 'true'},
      );
      final body = response.data;
      if (body != null && body['success'] == true) {
        return {'success': true, 'data': body['data'] ?? []};
      }
      return {
        'success': false,
        'message': body?['message'] ?? 'Error fetching categories',
      };
    } on DioException catch (e) {
      return {'success': false, 'message': _dioMessage(e)};
    } catch (e) {
      return {'success': false, 'message': 'Something went wrong'};
    }
  }

  Future<Map<String, dynamic>> getGrievances({
    String? status,
    String? search,
    int page = 1,
    int limit = 20,
    String sortBy = 'createdAt',
    String sortOrder = 'desc',
  }) async {
    try {
      await _setToken();
      final q = <String, dynamic>{
        'page': page,
        'limit': limit,
        'sortBy': sortBy,
        'sortOrder': sortOrder,
      };
      if (status != null && status.isNotEmpty && status != 'all') q['status'] = status;
      if (search != null && search.trim().isNotEmpty) q['search'] = search.trim();
      final response = await _api.dio.get<Map<String, dynamic>>(
        '/grievances',
        queryParameters: q,
      );
      final body = response.data;
      if (body != null && body['success'] == true) {
        return {
          'success': true,
          'data': body['data'] ?? {},
        };
      }
      return {
        'success': false,
        'message': body?['message'] ?? 'Error fetching grievances',
      };
    } on DioException catch (e) {
      return {'success': false, 'message': _dioMessage(e)};
    } catch (e) {
      return {'success': false, 'message': 'Something went wrong'};
    }
  }

  Future<Map<String, dynamic>> getGrievanceById(String id) async {
    try {
      await _setToken();
      final response = await _api.dio.get<Map<String, dynamic>>('/grievances/$id');
      final body = response.data;
      if (body != null && body['success'] == true) {
        return {'success': true, 'data': body['data'] ?? {}};
      }
      return {
        'success': false,
        'message': body?['message'] ?? 'Error fetching grievance',
      };
    } on DioException catch (e) {
      return {'success': false, 'message': _dioMessage(e)};
    } catch (e) {
      return {'success': false, 'message': 'Something went wrong'};
    }
  }

  Future<Map<String, dynamic>> createGrievance({
    required String categoryId,
    required String title,
    required String description,
    String? incidentDate,
    List<String>? peopleInvolved,
    String priority = 'Medium',
    bool isAnonymous = false,
  }) async {
    try {
      await _setToken();
      final payload = {
        'categoryId': categoryId,
        'title': title,
        'description': description,
        'priority': priority,
        'isAnonymous': isAnonymous,
        if (incidentDate != null && incidentDate.isNotEmpty) 'incidentDate': incidentDate,
        if (peopleInvolved != null && peopleInvolved.isNotEmpty) 'peopleInvolved': peopleInvolved,
      };
      final response = await _api.dio.post<Map<String, dynamic>>(
        '/grievances',
        data: payload,
      );
      final body = response.data;
      if (body != null && body['success'] == true) {
        return {'success': true, 'data': body['data'], 'message': body['message']};
      }
      return {
        'success': false,
        'message': body?['message'] ?? 'Failed to create grievance',
      };
    } on DioException catch (e) {
      return {'success': false, 'message': _dioMessage(e)};
    } catch (e) {
      return {'success': false, 'message': 'Something went wrong'};
    }
  }

  Future<Map<String, dynamic>> addNote(String grievanceId, String content) async {
    try {
      await _setToken();
      final response = await _api.dio.post<Map<String, dynamic>>(
        '/grievances/$grievanceId/notes',
        data: {'content': content, 'noteType': 'Public'},
      );
      final body = response.data;
      if (body != null && body['success'] == true) {
        return {'success': true, 'data': body['data']};
      }
      return {
        'success': false,
        'message': body?['message'] ?? 'Failed to add note',
      };
    } on DioException catch (e) {
      return {'success': false, 'message': _dioMessage(e)};
    } catch (e) {
      return {'success': false, 'message': 'Something went wrong'};
    }
  }

  Future<Map<String, dynamic>> uploadAttachment(String grievanceId, File file) async {
    try {
      await _setToken();
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(
          file.path,
          filename: file.path.split('/').last,
        ),
        'isInternal': 'false',
      });
      final response = await _api.dio.post<Map<String, dynamic>>(
        '/grievances/$grievanceId/attachments',
        data: formData,
      );
      final body = response.data;
      if (body != null && body['success'] == true) {
        return {'success': true, 'data': body['data']};
      }
      return {
        'success': false,
        'message': body?['message'] ?? 'Failed to upload file',
      };
    } on DioException catch (e) {
      return {'success': false, 'message': _dioMessage(e)};
    } catch (e) {
      return {'success': false, 'message': 'Something went wrong'};
    }
  }

  Future<Map<String, dynamic>> submitFeedback(String grievanceId, int rating, String feedback) async {
    try {
      await _setToken();
      final response = await _api.dio.post<Map<String, dynamic>>(
        '/grievances/$grievanceId/feedback',
        data: {'rating': rating, 'feedback': feedback},
      );
      final body = response.data;
      if (body != null && body['success'] == true) {
        return {'success': true, 'data': body['data']};
      }
      return {
        'success': false,
        'message': body?['message'] ?? 'Failed to submit feedback',
      };
    } on DioException catch (e) {
      return {'success': false, 'message': _dioMessage(e)};
    } catch (e) {
      return {'success': false, 'message': 'Something went wrong'};
    }
  }

  static String getFileUrl(String? path) {
    if (path == null || path.isEmpty) return '';
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    final base = AppConstants.fileBaseUrl;
    final p = path.startsWith('/') ? path : '/$path';
    return '$base$p';
  }
}
