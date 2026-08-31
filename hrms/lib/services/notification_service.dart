import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/error_message_utils.dart';
import 'api_client.dart';

class StaffNotificationModel {
  final String id;
  final String staffId;
  final String? adminId;
  final String title;
  final String message;
  final String type; // 'APPROVAL_UPDATED' | 'TEMPLATE_UPDATED' | 'TASK_ASSIGNED'
  final String module; // 'requests' | 'profile' | 'tasks'
  final String? referenceId;
  final String status; // 'unread' | 'read'
  final String createdAt;
  final String updatedAt;

  StaffNotificationModel({
    required this.id,
    required this.staffId,
    this.adminId,
    required this.title,
    required this.message,
    required this.type,
    required this.module,
    this.referenceId,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isUnread => status.toLowerCase() == 'unread';

  factory StaffNotificationModel.fromJson(Map<String, dynamic> json) {
    return StaffNotificationModel(
      id: json['_id']?.toString() ?? json['id']?.toString() ?? '',
      staffId: json['staffId']?.toString() ?? '',
      adminId: json['adminId']?.toString(),
      title: json['title']?.toString() ?? 'Notification',
      message: json['message']?.toString() ?? '',
      type: json['type']?.toString() ?? 'SYSTEM',
      module: json['module']?.toString() ?? 'requests',
      referenceId: json['referenceId']?.toString(),
      status: json['status']?.toString() ?? 'unread',
      createdAt: json['createdAt']?.toString() ?? DateTime.now().toIso8601String(),
      updatedAt: json['updatedAt']?.toString() ?? DateTime.now().toIso8601String(),
    );
  }
}

class NotificationService {
  final ApiClient _api = ApiClient();

  Future<void> _setToken() async {
    final prefs = await SharedPreferences.getInstance();
    String? token = prefs.getString('token');
    if (token != null && (token.startsWith('"') || token.endsWith('"'))) {
      token = token.replaceAll('"', '');
    }
    if (token != null && token.isNotEmpty) _api.setAuthToken(token);
  }

  /// Fetches staff notifications from `GET /staff/notifications`
  Future<Map<String, dynamic>> getStaffNotifications() async {
    try {
      await _setToken();
      final response = await _api.dio.get<dynamic>('/staff/notifications');
      final body = response.data;
      if (body != null && body['success'] == true) {
        final rawList = body['data'] as List? ?? [];
        final items = rawList
            .whereType<Map>()
            .map((e) => StaffNotificationModel.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        final unreadCount = (body['unreadCount'] as num?)?.toInt() ??
            items.where((i) => i.isUnread).length;

        return {
          'success': true,
          'data': items,
          'unreadCount': unreadCount,
        };
      }
      return {
        'success': false,
        'data': <StaffNotificationModel>[],
        'unreadCount': 0,
        'message': body?['message'] ?? 'Failed to load notifications',
      };
    } on DioException catch (e) {
      return {
        'success': false,
        'data': <StaffNotificationModel>[],
        'unreadCount': 0,
        'message': ErrorMessageUtils.messageFromDioException(e),
      };
    } catch (e) {
      return {
        'success': false,
        'data': <StaffNotificationModel>[],
        'unreadCount': 0,
        'message': e.toString(),
      };
    }
  }

  /// Marks a single notification as read: `PUT /staff/notifications/:id/read`
  Future<bool> markNotificationAsRead(String notificationId) async {
    if (notificationId.isEmpty) return false;
    try {
      await _setToken();
      final response = await _api.dio.put<dynamic>(
        '/staff/notifications/$notificationId/read',
      );
      final body = response.data;
      return body != null && body['success'] == true;
    } catch (e) {
      debugPrint('[NotificationService] Failed to mark notification as read: $e');
      return false;
    }
  }

  /// Marks all notifications as read: `PUT /staff/notifications`
  Future<bool> markAllNotificationsAsRead() async {
    try {
      await _setToken();
      final response = await _api.dio.put<dynamic>(
        '/staff/notifications',
      );
      final body = response.data;
      return body != null && body['success'] == true;
    } catch (e) {
      debugPrint('[NotificationService] Failed to mark all notifications as read: $e');
      return false;
    }
  }
}
