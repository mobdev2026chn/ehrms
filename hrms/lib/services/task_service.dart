import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:hrms/config/constants.dart';
import 'package:hrms/models/customer.dart';
import 'package:hrms/models/task.dart';
import 'package:hrms/services/geo/route_snapping_service.dart';
import 'package:hrms/services/auth_service.dart';
import 'package:hrms/services/customer_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hrms/services/geo/live_tracking_service.dart';
import 'package:hrms/services/geo/movement_classification_service.dart';
import 'package:hrms/services/geo/tracking_outlier_filter_service.dart';
import 'api_client.dart';

class TaskService {
  final ApiClient _api = ApiClient();
  static const String _offlineTrackingQueueKey =
      'task_tracking_offline_queue_v1';
  static const int _syncBatchSizeDefault = 20;
  static const int _syncBatchSizeFallback = 10;
  static Timer? _offlineSyncTimer;
  static bool _syncInProgress = false;
  static int _nextSyncBatchSize = _syncBatchSizeDefault;
  static int _offlineSendingCount = 0;
  static int _localOfflineInsertCount = 0;

  Future<void> _setToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token != null) _api.setAuthToken(token);
  }

  static Future<List<Map<String, dynamic>>> _loadOfflineQueue() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_offlineTrackingQueueKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> _saveOfflineQueue(List<Map<String, dynamic>> list) async {
    final prefs = await SharedPreferences.getInstance();
    if (list.isEmpty) {
      await prefs.remove(_offlineTrackingQueueKey);
      return;
    }
    await prefs.setString(_offlineTrackingQueueKey, jsonEncode(list));
  }

  static Future<bool> _hasInternetConnection() async {
    try {
      final probe = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 5),
        ),
      );
      final url = AppConstants.baseUrl.replaceAll(RegExp(r'/$'), '');
      await probe.get<dynamic>(url);
      return true;
    } on DioException catch (e) {
      final type = e.type;
      if (type == DioExceptionType.connectionError ||
          type == DioExceptionType.connectionTimeout ||
          type == DioExceptionType.receiveTimeout ||
          type == DioExceptionType.sendTimeout) {
        return false;
      }
      // Any HTTP response (401/404/etc.) still means internet is reachable.
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _startOfflineSyncTimerIfNeeded() async {
    final queue = await _loadOfflineQueue();
    if (queue.isEmpty) {
      _offlineSyncTimer?.cancel();
      _offlineSyncTimer = null;
      return;
    }
    if (_offlineSyncTimer != null) return;
    if (kDebugMode && AppConstants.logTrackingsToConsole) {
      debugPrint(
        '[Trackings] offline_sync timer_started pending=${queue.length} interval=1m',
      );
    }
    _offlineSyncTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      _syncOfflineQueueBatch();
    });
  }

  static Future<void> _enqueueOfflineTracking(Map<String, dynamic> body) async {
    final queue = await _loadOfflineQueue();
    final previousCount = queue.length;
    final offlineItem = <String, dynamic>{
      ...body,
      'status': 'offline',
      '_offlineId':
          '${DateTime.now().millisecondsSinceEpoch}_${body['taskId']}_${body['lat']}_${body['lng']}',
      '_queuedAt': DateTime.now().toUtc().toIso8601String(),
    };
    if (kDebugMode && AppConstants.logTrackingsToConsole) {
      final lat = (body['lat'] as num?)?.toDouble();
      final lng = (body['lng'] as num?)?.toDouble();
      debugPrint(
        '[Trackings] offline_store local_insert_prepare '
        'taskId=${body['taskId']} '
        'lat=${lat?.toStringAsFixed(6) ?? "-"}'
        'lng=${lng?.toStringAsFixed(6) ?? "-"}'
        'timestamp=${body['timestamp'] ?? "-"}'
        'queue_before=$previousCount',
      );
    }
    queue.add(offlineItem);
    await _saveOfflineQueue(queue);
    if (kDebugMode && AppConstants.logTrackingsToConsole) {
      debugPrint(
        '[Trackings] offline_store local_insert_done '
        'taskId=${body['taskId']} '
        'offlineId=${offlineItem['_offlineId']} '
        'queue_after=${queue.length}',
      );
      _localOfflineInsertCount += 1;
      debugPrint('****LOCAL-OFFLINE INSERT $_localOfflineInsertCount');
    }
    await _startOfflineSyncTimerIfNeeded();
  }

  static Future<void> _syncOfflineQueueBatch() async {
    if (_syncInProgress) return;
    _syncInProgress = true;
    try {
      final hasInternet = await _hasInternetConnection();
      if (!hasInternet) {
        if (kDebugMode && AppConstants.logTrackingsToConsole) {
          debugPrint('[Trackings] offline_sync skipped internet=off');
        }
        return;
      }

      final queue = await _loadOfflineQueue();
      if (queue.isEmpty) {
        _offlineSyncTimer?.cancel();
        _offlineSyncTimer = null;
        if (kDebugMode && AppConstants.logTrackingsToConsole) {
          debugPrint('[Trackings] offline_sync timer_stopped pending=0');
        }
        return;
      }

      final batchSize = _nextSyncBatchSize;
      final batch = queue.take(batchSize).toList();
      if (kDebugMode && AppConstants.logTrackingsToConsole) {
        debugPrint(
          '[Trackings] offline_sync cycle_start internet=on pending=${queue.length} batch_size=$batchSize sending=${batch.length}',
        );
      }
      final sender = TaskService();
      await sender._setToken();
      final syncedIds = <String>{};
      var hadNetworkFailure = false;

      for (final record in batch) {
        try {
          final taskId = record['taskId'];
          final lat = (record['lat'] as num?)?.toDouble();
          final lng = (record['lng'] as num?)?.toDouble();
          if (kDebugMode && AppConstants.logTrackingsToConsole) {
            debugPrint(
              '[Trackings] offline_sync sending taskId=$taskId lat=${lat?.toStringAsFixed(6) ?? "-"} lng=${lng?.toStringAsFixed(6) ?? "-"} ts=${record['timestamp'] ?? "-"}',
            );
          }
          try {
            await sender._api.dio.post<dynamic>('/staff/geo-task/live-tracking/record', data: record);
          } catch (_) {
            await sender._api.dio.post<dynamic>('/tracking/store', data: record);
          }
          final id = record['_offlineId']?.toString();
          if (id != null && id.isNotEmpty) syncedIds.add(id);
          if (kDebugMode && AppConstants.logTrackingsToConsole) {
            debugPrint('[Trackings] offline_sync sent_ok taskId=$taskId');
            _offlineSendingCount += 1;
            debugPrint('****COUNT OFFLINE-SENDING-$_offlineSendingCount');
          }
        } on DioException catch (e) {
          final type = e.type;
          if (type == DioExceptionType.connectionError ||
              type == DioExceptionType.connectionTimeout ||
              type == DioExceptionType.receiveTimeout ||
              type == DioExceptionType.sendTimeout) {
            hadNetworkFailure = true;
          }
          if (kDebugMode && AppConstants.logTrackingsToConsole) {
            debugPrint(
              '[Trackings] offline_sync sent_fail taskId=${record['taskId']} status=${e.response?.statusCode} type=${e.type}',
            );
          }
        } catch (_) {}
      }

      if (syncedIds.isNotEmpty) {
        final remaining = queue.where((item) {
          final id = item['_offlineId']?.toString();
          return id == null || !syncedIds.contains(id);
        }).toList();
        await _saveOfflineQueue(remaining);
        if (kDebugMode && AppConstants.logTrackingsToConsole) {
          debugPrint(
            '[Trackings] offline_sync cycle_done sent=${syncedIds.length} remaining=${remaining.length}',
          );
        }
        if (remaining.isEmpty) {
          _offlineSyncTimer?.cancel();
          _offlineSyncTimer = null;
          if (kDebugMode && AppConstants.logTrackingsToConsole) {
            debugPrint('[Trackings] offline_sync timer_stopped pending=0');
          }
        }
      } else if (kDebugMode && AppConstants.logTrackingsToConsole) {
        debugPrint(
          '[Trackings] offline_sync cycle_done sent=0 remaining=${queue.length}',
        );
      }

      _nextSyncBatchSize = hadNetworkFailure
          ? _syncBatchSizeFallback
          : _syncBatchSizeDefault;
    } finally {
      _syncInProgress = false;
    }
  }

  /// Create task via existing backend API. assignedTo = staffId.
  /// taskId is auto-generated on backend (format: TASK-XXXXXXXX-XXXX).
  /// businessId sent from stored login data (staffs collection) as fallback.
  Future<Task> createTask({
    required String taskTitle,
    required String description,
    required String assignedTo,
    required String customerId,
    required DateTime expectedCompletionDate,
    DateTime? earliestCompletionDate,
    DateTime? latestCompletionDate,
    String status = 'assigned',
    Map<String, dynamic>? sourceLocation,
    Map<String, dynamic>? destinationLocation,
  }) async {
    await _setToken();
    final prefs = await SharedPreferences.getInstance();
    final storedBusinessId = prefs.getString('businessId');
    final body = <String, dynamic>{
      'taskTitle': taskTitle,
      'description': description,
      'assignedTo': assignedTo,
      'customerId': customerId,
      'expectedCompletionDate': expectedCompletionDate
          .toUtc()
          .toIso8601String(),
      'status': status,
      'source': 'app',
    };
    // Completion-date range. Normalize to UTC midnight of the calendar date so
    // it matches how the backend stores/filters expectedCompletionDate.
    if (earliestCompletionDate != null) {
      body['earliestCompletionDate'] = DateTime.utc(
        earliestCompletionDate.year,
        earliestCompletionDate.month,
        earliestCompletionDate.day,
      ).toIso8601String();
    }
    if (latestCompletionDate != null) {
      body['latestCompletionDate'] = DateTime.utc(
        latestCompletionDate.year,
        latestCompletionDate.month,
        latestCompletionDate.day,
      ).toIso8601String();
    }
    if (storedBusinessId != null && storedBusinessId.isNotEmpty) {
      body['businessId'] = storedBusinessId;
    }
    if (sourceLocation != null) body['sourceLocation'] = sourceLocation;
    if (destinationLocation != null) {
      body['destinationLocation'] = destinationLocation;
    }

    // HRMSbackend createStaffTask (POST /staff/geo-task/tasks) reads title, startDate,
    // endDate, customerId and an optional destination override (customerAddress, latitude,
    // longitude, radius). The legacy keys above are kept for the old backend.
    String dateOnly(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    body['title'] = taskTitle;
    body['startDate'] = dateOnly(earliestCompletionDate ?? DateTime.now());
    body['endDate'] = dateOnly(latestCompletionDate ?? expectedCompletionDate);
    if (destinationLocation != null) {
      final addr = (destinationLocation['fullAddress'] ?? destinationLocation['address'])?.toString();
      if (addr != null && addr.isNotEmpty) body['customerAddress'] = addr;
      final lat = destinationLocation['lat'] ?? destinationLocation['latitude'];
      final lng = destinationLocation['lng'] ?? destinationLocation['longitude'];
      if (lat is num && lng is num) {
        body['latitude'] = lat;
        body['longitude'] = lng;
      }
    }

    Response<dynamic> response;
    try {
      response = await _api.dio.post<dynamic>('/staff/geo-task/tasks', data: body);
    } on DioException catch (e) {
      if (!_isMissingRoute(e)) rethrow;
      response = await _api.dio.post<dynamic>('/tasks', data: body);
    }
    final raw = response.data;
    if (raw is! Map) throw Exception('Failed to create task');
    final payload = raw['data'] is Map ? raw['data'] as Map : raw;
    return Task.fromJson(Map<String, dynamic>.from(payload));
  }

  Future<List<Task>> getAllTasks() async {
    try {
      await _setToken();
      for (final path in [
        '/staff/geo-task/tasks',
        '/tasks',
        '/admin/hrms-geo/task',
      ]) {
        try {
          final response = await _api.dio.get<dynamic>(path);
          final body = response.data;
          List? rawList;
          if (body is List) {
            rawList = body;
          } else if (body is Map && body['data'] is List) {
            rawList = body['data'] as List;
          } else if (body is Map && body['tasks'] is List) {
            rawList = body['tasks'] as List;
          }
          // A valid (even empty) list is the answer; only a failed call tries the next path.
          if (rawList != null) {
            return rawList
                .whereType<Map>()
                .map((j) => Task.fromJson(Map<String, dynamic>.from(j)))
                .toList();
          }
        } on DioException catch (e) {
          // Try the legacy routes only when this one is missing; a timeout or
          // auth error would just repeat on each of them.
          if (!_isMissingRoute(e)) break;
        } catch (_) {}
      }
      return <Task>[];
    } catch (_) {
      return <Task>[];
    }
  }

  Future<List<Task>> getAssignedTasks(String staffId) async {
    try {
      await _setToken();
      for (final path in [
        // HRMSbackend serves the signed-in staff member's tasks here.
        '/staff/geo-task/tasks',
        '/tasks/staff/$staffId',
        '/tasks',
        '/admin/hrms-geo/task',
      ]) {
        try {
          final response = await _api.dio.get<dynamic>(path);
          final body = response.data;
          List? rawList;
          if (body is List) {
            rawList = body;
          } else if (body is Map && body['data'] is List) {
            rawList = body['data'] as List;
          } else if (body is Map && body['tasks'] is List) {
            rawList = body['tasks'] as List;
          }
          if (rawList != null) {
            return rawList
                .whereType<Map>()
                .map((j) => Task.fromJson(Map<String, dynamic>.from(j)))
                .toList();
          }
        } on DioException catch (e) {
          // Try the legacy routes only when this one is missing; a timeout or
          // auth error would just repeat on each of them.
          if (!_isMissingRoute(e)) break;
        } catch (_) {}
      }
      return <Task>[];
    } catch (_) {
      return <Task>[];
    }
  }

  Future<Map<String, dynamic>> getAssignedTasksPaginated(
    String staffId, {
    int page = 1,
    int limit = 20,
    String? search,
    DateTime? startDate,
    DateTime? endDate,
    List<String>? statusGroups,
  }) async {
    try {
      await _setToken();
      final query = <String, dynamic>{'page': page, 'limit': limit};
      final q = (search ?? '').trim();
      if (q.isNotEmpty) query['search'] = q;
      // Send the picked calendar day as UTC midnight so it matches how
      // expectedCompletionDate is stored (UTC midnight of the calendar date)
      // and how the backend re-extracts UTC date parts. Using local
      // .toUtc() here shifted the day back one in +ve timezones (e.g. IST),
      // making the date filter return the wrong day's tasks.
      if (startDate != null) {
        query['startDate'] = DateTime.utc(
          startDate.year,
          startDate.month,
          startDate.day,
        ).toIso8601String();
      }
      if (endDate != null) {
        query['endDate'] = DateTime.utc(
          endDate.year,
          endDate.month,
          endDate.day,
          23,
          59,
          59,
          999,
        ).toIso8601String();
      }
      if (statusGroups != null && statusGroups.isNotEmpty) {
        query['statusGroups'] = statusGroups.join(',');
      }

      final response = await _api.dio.get<Map<String, dynamic>>(
        '/tasks/staff/$staffId/paginated',
        queryParameters: query,
      );
      final body = response.data ?? const <String, dynamic>{};
      final rawList = (body['data'] as List?) ?? const [];
      final pagination =
          body['pagination'] as Map<String, dynamic>? ?? const {};
      final tasks = rawList
          .whereType<Map>()
          .map((j) => Task.fromJson(Map<String, dynamic>.from(j)))
          .toList();
      return {
        'tasks': tasks,
        'page': (pagination['page'] as num?)?.toInt() ?? page,
        'limit': (pagination['limit'] as num?)?.toInt() ?? limit,
        'total': (pagination['total'] as num?)?.toInt() ?? tasks.length,
        'totalPages': (pagination['totalPages'] as num?)?.toInt() ?? 1,
      };
    } on DioException catch (e) {
      throw Exception(
        'Failed to load assigned tasks: ${e.response?.statusCode ?? e.message}',
      );
    }
  }

  Future<Task> getTaskById(String id) async {
    await _setToken();

    // 1. Primary: staff GEO task endpoint
    try {
      final response = await _api.dio.get<dynamic>('/staff/geo-task/$id');
      final data = response.data;
      if (data is Map && data['data'] != null) {
        return Task.fromJson(Map<String, dynamic>.from(data['data'] as Map));
      } else if (data is Map) {
        return Task.fromJson(Map<String, dynamic>.from(data));
      }
    } catch (_) {}

    // 2. Fallback: legacy tasks endpoint
    try {
      final response = await _api.dio.get<Map<String, dynamic>>('/tasks/$id');
      final data = response.data;
      if (data != null) return Task.fromJson(data);
    } on DioException catch (e) {
      throw Exception(
        'Failed to load task: ${e.response?.statusCode ?? e.message}',
      );
    }
    throw Exception('Failed to load task: not found');
  }

  /// GPS points from Tracking until Arrived (for task detail map polyline).
  /// Returns [{lat, lng}, ...] sorted by time, trimmed at first `status: arrived` or [arrivalTime].
  Future<List<Map<String, double>>> getTravelledPathUntilArrived(
    String taskMongoId, {
    DateTime? arrivalTime,
  }) async {
    try {
      await _setToken();
      // Primary: query live tracking trail from HRMSbackend
      final trailRes = await _api.dio.get<dynamic>(
        '/staff/geo-task/live-tracking/trail/$taskMongoId',
      );
      final trailData = trailRes.data;
      List<dynamic> path = [];
      if (trailData is Map && trailData['data'] is List) {
        path = trailData['data'] as List<dynamic>;
      } else if (trailData is List) {
        path = trailData;
      }
      if (path.isNotEmpty) {
        final filtered = _filterTrackingPathUntilArrived(path, arrivalTime);
        if (filtered.isNotEmpty) return filtered;
      }
    } catch (_) {}

    try {
      await _setToken();
      final response = await _api.dio.get<Map<String, dynamic>>(
        '/tasks/$taskMongoId/tracking-path',
      );
      final path = response.data?['path'] as List<dynamic>? ?? [];
      if (path.isNotEmpty) {
        final filtered = _filterTrackingPathUntilArrived(path, arrivalTime);
        if (filtered.isNotEmpty) return filtered;
      }
    } catch (_) {}

    // Fallback: Check if task document itself has stored travelledRoute
    try {
      final task = await getTaskById(taskMongoId);
      if (task.travelledRoute != null && task.travelledRoute!.isNotEmpty) {
        return task.travelledRoute!;
      }
    } catch (_) {}

    return [];
  }

  static List<Map<String, double>> _filterTrackingPathUntilArrived(
    List<dynamic> path,
    DateTime? arrivalTime,
  ) {
    DateTime? parseTs(dynamic v) {
      if (v == null) return null;
      if (v is String) return DateTime.tryParse(v);
      if (v is Map && v[r'$date'] != null) {
        return DateTime.tryParse(v[r'$date'].toString());
      }
      return null;
    }

    final rows = <Map<String, dynamic>>[];
    for (final r in path) {
      if (r is! Map) continue;
      final lat = ((r['lat'] ?? r['latitude']) as num?)?.toDouble();
      final lng = ((r['lng'] ?? r['longitude']) as num?)?.toDouble();
      if (lat == null || lng == null) continue;
      // Imprecise fixes land on the wrong street and zig-zag the drawn route.
      final acc = (r['accuracy'] as num?)?.toDouble();
      if (acc != null && acc > 30) continue;
      rows.add({
        'lat': lat,
        'lng': lng,
        'ts': parseTs(r['timestamp']) ?? DateTime.fromMillisecondsSinceEpoch(0),
        'status': r['status']?.toString().toLowerCase(),
      });
    }
    if (rows.isEmpty) return [];
    rows.sort((a, b) => (a['ts'] as DateTime).compareTo(b['ts'] as DateTime));

    int endExclusive = rows.length;
    for (var i = 0; i < rows.length; i++) {
      if (rows[i]['status'] == 'arrived') {
        endExclusive = i + 1;
        break;
      }
    }
    if (endExclusive == rows.length && arrivalTime != null) {
      final cutOff = arrivalTime.add(const Duration(minutes: 5));
      int matchedCount = 0;
      for (var i = 0; i < rows.length; i++) {
        final t = rows[i]['ts'] as DateTime;
        if (t.isAfter(cutOff)) break;
        matchedCount = i + 1;
      }
      if (matchedCount > 0) {
        endExclusive = matchedCount;
      }
    }

    final out = <Map<String, double>>[];
    for (var i = 0; i < endExclusive; i++) {
      out.add({
        'lat': rows[i]['lat'] as double,
        'lng': rows[i]['lng'] as double,
      });
    }
    return out;
  }

  /// Distance actually travelled on [taskMongoId], in km, from its saved GPS
  /// trail (see RouteSnappingService.travelledDistanceKm). Null when the trail
  /// can't be read or has too few points — callers keep their own figure then.
  Future<double?> getTravelledDistanceKm(String taskMongoId) async {
    try {
      await _setToken();
      final res = await _api.dio.get<dynamic>(
        '/staff/geo-task/live-tracking/trail/$taskMongoId',
      );
      final data = res.data is Map ? (res.data as Map)['data'] : res.data;
      if (data is! List) return null;
      final points = data
          .whereType<Map>()
          .map((e) => RoutePoint.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      if (points.length < 2) return null;
      final km = await RouteSnappingService.travelledDistanceKm(points);
      return km > 0 ? km : null;
    } catch (_) {
      return null;
    }
  }

  /// Fetch full task completion report: task, timeline, route points from DB.
  Future<TaskCompletionReport> getTaskCompletionReport(String taskId) async {
    await _setToken();

    // 1. Try dedicated completion-report endpoints
    final candidateEndpoints = [
      '/staff/geo-task/$taskId/completion-report',
      '/tasks/$taskId/completion-report',
    ];

    for (final endpoint in candidateEndpoints) {
      try {
        final response = await _api.dio.get<dynamic>(endpoint);
        final data = response.data;
        if (data is Map && (data['task'] != null || data['data'] != null)) {
          final reportMap = data['data'] is Map
              ? Map<String, dynamic>.from(data['data'] as Map)
              : Map<String, dynamic>.from(data);
          if (reportMap['task'] != null) {
            return TaskCompletionReport.fromJson(reportMap);
          }
        }
      } catch (_) {}
    }

    // 2. Robust fallback: Fetch task by ID from staff GEO route
    final task = await getTaskById(taskId);

    // 3. Fetch live tracking trail for breadcrumb route points
    List<RoutePoint> routePoints = [];
    try {
      final trailRes = await _api.dio.get<dynamic>('/staff/geo-task/live-tracking/trail/$taskId');
      if (trailRes.data is Map && trailRes.data['data'] is List) {
        routePoints = (trailRes.data['data'] as List)
            .whereType<Map>()
            .map((e) => RoutePoint.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
    } catch (_) {}

    if (routePoints.isEmpty && task.travelledRoute != null && task.travelledRoute!.isNotEmpty) {
      routePoints = task.travelledRoute!
          .map((p) => RoutePoint(
                lat: p['lat'] ?? 0,
                lng: p['lng'] ?? 0,
              ))
          .toList();
    }

    // 4. Build timeline events from available milestone timestamps
    final timeline = <TimelineEvent>[];
    if (task.startTime != null) {
      timeline.add(
        TimelineEvent(
          type: 'start',
          label: 'Start',
          time: task.startTime,
          address: task.sourceLocation?.displayAddress,
          lat: task.sourceLocation?.lat,
          lng: task.sourceLocation?.lng,
        ),
      );
    }
    if (task.arrivalTime != null) {
      timeline.add(
        TimelineEvent(
          type: 'arrived',
          label: 'Arrived',
          time: task.arrivalTime,
          address: task.arrivalLocation?.displayAddress ?? task.destinationLocation?.displayAddress,
          lat: task.arrivalLocation?.lat ?? task.destinationLocation?.lat,
          lng: task.arrivalLocation?.lng ?? task.destinationLocation?.lng,
        ),
      );
    }
    if (task.completedDate != null) {
      timeline.add(
        TimelineEvent(
          type: 'completed',
          label: 'Completed',
          time: task.completedDate,
          address: task.destinationLocation?.displayAddress,
          lat: task.destinationLocation?.lat,
          lng: task.destinationLocation?.lng,
        ),
      );
    }

    return TaskCompletionReport(
      task: task,
      timeline: timeline,
      routePoints: routePoints,
    );
  }

  Future<Task> updateTask(
    String id, {
    String? status,
    DateTime? startTime,
    double? startLat,
    double? startLng,
    Map<String, dynamic>? sourceLocation,
    Map<String, dynamic>? destinationLocation,
    bool? destinationChanged,
    double? tripDistanceKm,
    int? tripDurationSeconds,
    DateTime? arrivalTime,
  }) async {
    try {
      await _setToken();
      final body = <String, dynamic>{};
      if (status != null) body['status'] = status;
      if (startTime != null) {
        body['startTime'] = startTime.toUtc().toIso8601String();
      }
      if (startLat != null && startLng != null) {
        final now = DateTime.now().toUtc();
        body['startLocation'] = {
          'lat': startLat,
          'lng': startLng,
          'recordedAt': now.toIso8601String(),
        };
        body['startLatitude'] = startLat;
        body['startLongitude'] = startLng;
      }
      if (sourceLocation != null) body['sourceLocation'] = sourceLocation;
      if (destinationLocation != null) {
        body['destinationLocation'] = destinationLocation;
      }
      if (destinationChanged != null) {
        body['destinationChanged'] = destinationChanged;
      }
      if (tripDistanceKm != null) body['tripDistanceKm'] = tripDistanceKm;
      if (tripDurationSeconds != null) {
        body['tripDurationSeconds'] = tripDurationSeconds;
      }
      if (arrivalTime != null) {
        body['arrivalTime'] = arrivalTime.toUtc().toIso8601String();
      }

      // In HRMSbackend, the official staff endpoint is /staff/geo-task/:id
      final staffBody = Map<String, dynamic>.from(body);
      if (staffBody['status'] == 'in_progress') staffBody['status'] = 'Started';
      if (startLat != null && startLng != null) {
        staffBody['latitude'] = startLat;
        staffBody['longitude'] = startLng;
      }
      if (status == 'in_progress' || status == 'Started') {
        staffBody['fieldInTime'] = startTime != null
            ? '${startTime.toLocal().hour.toString().padLeft(2, '0')}:${startTime.toLocal().minute.toString().padLeft(2, '0')}'
            : '${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}';
      }

      // 1. Try PUT /staff/geo-task/:id (primary HRMSbackend staff route)
      try {
        final response = await _api.dio.put<dynamic>('/staff/geo-task/$id', data: staffBody);
        if (response.statusCode == 200 || response.statusCode == 201) {
          final data = response.data;
          final payload = (data is Map && data['data'] != null)
              ? (data['data'] is Map ? data['data'] as Map<String, dynamic> : data as Map<String, dynamic>)
              : (data is Map ? data as Map<String, dynamic> : null);
          if (payload != null) return Task.fromJson(payload);
        }
      } on DioException catch (e) {
        // Server refusals (geofence 400, awaiting approval 403, another task running 409)
        // are final — show the server's message instead of trying legacy routes.
        final code = e.response?.statusCode;
        if (e.response != null && (code == 400 || code == 403 || code == 409)) {
          final msg = (e.response?.data is Map)
              ? (e.response!.data['message'] ?? e.response!.data['error'])?.toString()
              : null;
          throw Exception(msg ?? 'Location validation failed');
        }
      } catch (e) {
        if (e is Exception && !e.toString().contains('DioException')) {
          rethrow;
        }
      }

      // 2. Fallback to PATCH /tasks/:id (legacy)
      try {
        final response = await _api.dio.patch<dynamic>('/tasks/$id', data: body);
        if (response.statusCode == 200 || response.statusCode == 201) {
          final data = response.data;
          final payload = (data is Map && data['data'] != null)
              ? (data['data'] is Map ? data['data'] as Map<String, dynamic> : data as Map<String, dynamic>)
              : (data is Map ? data as Map<String, dynamic> : null);
          if (payload != null) return Task.fromJson(payload);
        }
      } catch (_) {}

      // 3. Fallback to PUT /admin/hrms-geo/task/:id
      try {
        final altBody = Map<String, dynamic>.from(body);
        if (altBody['status'] == 'in_progress') altBody['status'] = 'Started';
        final response = await _api.dio.put<dynamic>('/admin/hrms-geo/task/$id', data: altBody);
        if (response.statusCode == 200 || response.statusCode == 201) {
          final data = response.data;
          final payload = (data is Map && data['data'] != null)
              ? (data['data'] is Map ? data['data'] as Map<String, dynamic> : data as Map<String, dynamic>)
              : (data is Map ? data as Map<String, dynamic> : null);
          if (payload != null) return Task.fromJson(payload);
        }
      } catch (_) {}

      final response = await _api.dio.patch<Map<String, dynamic>>(
        '/tasks/$id',
        data: body,
      );
      final data = response.data;
      if (data == null) throw Exception('Failed to update task');
      return Task.fromJson(data);
    } catch (e) {
      if (e is Exception && !e.toString().contains('DioException')) {
        rethrow;
      }
      final msg = (e is DioException && e.response?.data is Map)
          ? (e.response!.data['message'] ?? e.response!.data['error'])?.toString()
          : null;
      throw Exception(
        msg ?? 'Failed to update task',
      );
    }
  }

  /// Send GPS point: taskId, lat, lng, timestamp, batteryPercent, movementType.
  Future<void> updateLocation(
    String taskMongoId,
    double lat,
    double lng, {
    int? batteryPercent,
    String? movementType,
    String? address,
    String? fullAddress,
    String? city,
    String? area,
    String? pincode,
  }) async {
    // HRMSbackend has no /tasks/:id/location; the same point is already recorded by
    // [storeTracking] (POST /staff/geo-task/live-tracking/record). Only the legacy
    // backend (different host) serves this route.
    if (AppConstants.baseUrl.contains('ektahr.com')) return;
    await _setToken();
    final body = <String, dynamic>{
      'lat': lat,
      'lng': lng,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    };
    if (batteryPercent != null) body['batteryPercent'] = batteryPercent;
    if (movementType != null) body['movementType'] = movementType;
    if (address != null && address.isNotEmpty) body['address'] = address;
    if (fullAddress != null && fullAddress.isNotEmpty) {
      body['fullAddress'] = fullAddress;
    }
    if (city != null && city.isNotEmpty) body['city'] = city;
    if (area != null && area.isNotEmpty) body['area'] = area;
    if (pincode != null && pincode.isNotEmpty) body['pincode'] = pincode;
    await _api.dio.post<dynamic>('/tasks/$taskMongoId/location', data: body);
  }

  /// Store tracking point in Tracking collection (separate route, not socket.io).
  /// Call on Start Ride and every 15 sec during Live Tracking.
  /// Payload includes currentLat, currentLng, destinationLat, destinationLng.
  Future<bool> storeTracking(
    String taskMongoId,
    double lat,
    double lng, {
    int? batteryPercent,
    String? movementType,
    double? accuracyM,
    double? speedMps,
    int consecutiveLowSpeed = 0,
    double? destinationLat,
    double? destinationLng,
    String? address,
    String? fullAddress,
    String? city,
    String? area,
    String? pincode,
  }) async {
    await _setToken();
    final capturedAt = DateTime.now().toUtc();
    final outlierDecision = await TrackingOutlierFilterService.evaluate(
      scope: TrackingOutlierFilterService.taskScope(taskMongoId),
      lat: lat,
      lng: lng,
      timestamp: capturedAt,
      movementType: movementType ?? kMovementStop,
      accuracyM: accuracyM,
      sensorSpeedMps: speedMps,
    );
    if (outlierDecision.shouldSkip) {
      if (kDebugMode && AppConstants.logTrackingsToConsole) {
        debugPrint(
          '[Trackings] task_store SKIP outlier (fg) taskId=$taskMongoId '
          'reason=${outlierDecision.reason} '
          'distance=${outlierDecision.distanceM?.toStringAsFixed(2) ?? "—"}m '
          'speed=${outlierDecision.speedKmh?.toStringAsFixed(2) ?? "—"}kmh',
        );
      }
      return false;
    }
    final resolvedMovementType = outlierDecision.movementType;
    final body = <String, dynamic>{
      'taskId': taskMongoId,
      'lat': lat,
      'lng': lng,
      'timestamp': capturedAt.toIso8601String(),
    };
    if (batteryPercent != null) body['batteryPercent'] = batteryPercent;
    body['movementType'] = resolvedMovementType;
    if (destinationLat != null) body['destinationLat'] = destinationLat;
    if (destinationLng != null) body['destinationLng'] = destinationLng;
    if (address != null && address.isNotEmpty) body['address'] = address;
    if (fullAddress != null && fullAddress.isNotEmpty) {
      body['fullAddress'] = fullAddress;
    }
    if (city != null && city.isNotEmpty) body['city'] = city;
    if (area != null && area.isNotEmpty) body['area'] = area;
    if (pincode != null && pincode.isNotEmpty) body['pincode'] = pincode;
    try {
      await _startOfflineSyncTimerIfNeeded();
      try {
        await _api.dio.post<dynamic>('/staff/geo-task/live-tracking/record', data: body);
      } catch (_) {
        await _api.dio.post<dynamic>('/tracking/store', data: body);
      }
      await LiveTrackingService.persistStoredTrackingPoint(
        taskMongoId,
        lat,
        lng,
      );
      await LiveTrackingService.persistLastSentPosition(
        lat,
        lng,
        movementType: resolvedMovementType,
        consecutiveLowSpeed: resolvedMovementType == kMovementStop
            ? consecutiveLowSpeed
            : 0,
      );
      await TrackingOutlierFilterService.rememberValidRecord(
        scope: TrackingOutlierFilterService.taskScope(taskMongoId),
        lat: lat,
        lng: lng,
        timestamp: capturedAt,
        movementType: resolvedMovementType,
        accuracyM: accuracyM,
      );
      if (kDebugMode && AppConstants.logTrackingsToConsole) {
        debugPrint(
          '[Trackings] task_store OK (fg) taskId=$taskMongoId '
          'lat=${lat.toStringAsFixed(6)} lng=${lng.toStringAsFixed(6)} '
          'movement=$resolvedMovementType '
          'acc=${accuracyM?.toStringAsFixed(1) ?? "—"}m',
        );
      }
      return true;
    } on DioException catch (e) {
      await _enqueueOfflineTracking(body);
      if (kDebugMode && AppConstants.logTrackingsToConsole) {
        debugPrint(
          '[Trackings] task_store FAIL (fg) queued_offline taskId=$taskMongoId '
          '${e.response?.statusCode} ${e.response?.data}',
        );
      }
      return false;
    }
  }

  /// Update task progress steps (reachedLocation, photoProof, formFilled, otpVerified).
  Future<Task> updateSteps(
    String taskMongoId, {
    bool? reachedLocation,
    bool? photoProof,
    bool? formFilled,
    bool? otpVerified,
  }) async {
    await _setToken();
    final body = <String, dynamic>{};
    if (reachedLocation != null) body['reachedLocation'] = reachedLocation;
    if (photoProof != null) body['photoProof'] = photoProof;
    if (formFilled != null) body['formFilled'] = formFilled;
    if (otpVerified != null) body['otpVerified'] = otpVerified;
    final response = await _api.dio.patch<Map<String, dynamic>>(
      '/tasks/$taskMongoId/steps',
      data: body,
    );
    final data = response.data;
    if (data == null) throw Exception('Failed to update steps');
    return Task.fromJson(data);
  }

  static bool _isMissingRoute(DioException e) =>
      e.response?.statusCode == 404 && !_isTaskNotFound(e);

  /// HRMSbackend answers 404 with this message when the route exists but the task does not.
  static bool _isTaskNotFound(DioException e) {
    final body = e.response?.data;
    final msg = body is Map ? (body['message'] ?? '').toString().toLowerCase() : '';
    return msg.contains('task not found');
  }

  static String? _serverMessage(DioException e) {
    final body = e.response?.data;
    final msg = body is Map ? body['message']?.toString() : null;
    return (msg != null && msg.trim().isNotEmpty) ? msg.trim() : null;
  }

  /// Today's punch state (HRMSbackend `GET /staff/attendance/today-punch`).
  /// Returns null when it cannot be determined (network error) so callers can fail open.
  Future<({bool punchedIn, bool punchedOut})?> getTodayPunchState() async {
    await _setToken();
    try {
      final res = await _api.dio.get<dynamic>('/staff/attendance/today-punch');
      final d = res.data is Map ? (res.data as Map)['data'] : null;
      if (d is! Map) return null;
      return (punchedIn: d['isPunchedIn'] == true, punchedOut: d['isPunchedOut'] == true);
    } catch (_) {
      return null;
    }
  }

  /// Upload an image for a Field-Out form answer. HRMSbackend `POST /staff/geo-task/upload`
  /// takes a base64 data URL and returns the stored file's URL.
  Future<String> uploadFieldOutImage(String filePath) async {
    await _setToken();
    final bytes = await FlutterImageCompress.compressWithFile(
          filePath,
          minWidth: 1280,
          minHeight: 1280,
          quality: 75,
        ) ??
        await File(filePath).readAsBytes();
    try {
      final res = await _api.dio.post<dynamic>(
        '/staff/geo-task/upload',
        data: {'file': 'data:image/jpeg;base64,${base64Encode(bytes)}'},
        options: Options(sendTimeout: const Duration(seconds: 60)),
      );
      final url = res.data is Map ? (res.data as Map)['url']?.toString() : null;
      if (url == null || url.isEmpty) throw Exception('Photo upload failed. Please try again.');
      return url;
    } on DioException catch (e) {
      throw Exception(_serverMessage(e) ?? 'Photo upload failed. Please try again.');
    }
  }

  /// Email OTP for a Field-Out form's Email field (`POST /staff/geo-task/otp/send`).
  Future<void> sendEmailOtp(String email) async {
    await _setToken();
    try {
      await _api.dio.post<dynamic>('/staff/geo-task/otp/send', data: {'email': email.trim()});
    } on DioException catch (e) {
      throw Exception(_serverMessage(e) ?? 'Could not send the OTP. Please try again.');
    }
  }

  /// Verify the emailed OTP (`POST /staff/geo-task/otp/verify`). Field Out is then accepted
  /// for that email address.
  Future<void> verifyEmailOtp(String email, String otp) async {
    await _setToken();
    try {
      await _api.dio.post<dynamic>(
        '/staff/geo-task/otp/verify',
        data: {'email': email.trim(), 'otp': otp.trim()},
      );
    } on DioException catch (e) {
      throw Exception(_serverMessage(e) ?? 'Invalid OTP or OTP expired');
    }
  }

  /// Upload photo proof for task. Returns updated task.
  ///
  /// HRMSbackend: `POST /staff/geo-task/upload` takes the image as a base64 data URL and
  /// returns its URL, which `PUT /staff/geo-task/:id` stores as the task's proof image.
  Future<Task> uploadPhotoProof(
    String taskMongoId,
    String filePath, {
    String? description,
    double? lat,
    double? lng,
    String? fullAddress,
  }) async {
    await _setToken();
    try {
      // Keep the JSON body well under the server's 10 MB limit for this route.
      final bytes = await FlutterImageCompress.compressWithFile(
            filePath,
            minWidth: 1280,
            minHeight: 1280,
            quality: 75,
          ) ??
          await File(filePath).readAsBytes();
      final dataUrl = 'data:image/jpeg;base64,${base64Encode(bytes)}';
      final upload = await _api.dio.post<dynamic>(
        '/staff/geo-task/upload',
        data: {'file': dataUrl},
        options: Options(sendTimeout: const Duration(seconds: 60)),
      );
      final url = upload.data is Map ? (upload.data as Map)['url']?.toString() : null;
      if (url == null || url.isEmpty) throw Exception('Photo upload failed. Please try again.');
      await _api.dio.put<dynamic>('/staff/geo-task/$taskMongoId', data: {
        'fieldOutImage': url,
        if (description != null && description.trim().isNotEmpty) 'fieldOutNotes': description.trim(),
      });
      return getTaskById(taskMongoId);
    } on DioException catch (e) {
      if (!_isMissingRoute(e)) {
        throw Exception(_serverMessage(e) ?? 'Photo upload failed. Please try again.');
      }
    }

    // Legacy app_backend route.
    final formData = FormData.fromMap({
      'photo': await MultipartFile.fromFile(filePath, filename: 'photo.jpg'),
      if (description != null && description.isNotEmpty)
        'description': description,
      if (lat != null) 'lat': lat.toString(),
      if (lng != null) 'lng': lng.toString(),
      if (fullAddress != null && fullAddress.isNotEmpty)
        'fullAddress': fullAddress,
    });
    final response = await _api.dio.post<Map<String, dynamic>>(
      '/tasks/$taskMongoId/photo',
      data: formData,
      options: Options(
        contentType: 'multipart/form-data',
        sendTimeout: const Duration(seconds: 30),
      ),
    );
    final data = response.data;
    if (data == null) throw Exception('Failed to upload photo');
    return Task.fromJson(data);
  }

  /// Upload check-in or check-out selfie for task. [type] must be 'checkin' or 'checkout'.
  /// Returns updated task with progressSteps.checkinCustomerPlace or checkoutCustomerPlace set.
  Future<Task> uploadTaskSelfie(
    String taskMongoId,
    String type,
    String filePath, {
    double? lat,
    double? lng,
    String? fullAddress,
  }) async {
    await _setToken();
    if (type != 'checkin' && type != 'checkout') {
      throw Exception('Type must be checkin or checkout');
    }
    final formData = FormData.fromMap({
      'photo': await MultipartFile.fromFile(filePath, filename: 'photo.jpg'),
      'type': type,
      if (lat != null) 'lat': lat.toString(),
      if (lng != null) 'lng': lng.toString(),
      if (fullAddress != null && fullAddress.isNotEmpty)
        'fullAddress': fullAddress,
    });
    final response = await _api.dio.post<Map<String, dynamic>>(
      '/tasks/$taskMongoId/selfie',
      data: formData,
      options: Options(
        contentType: 'multipart/form-data',
        sendTimeout: const Duration(seconds: 30),
      ),
    );
    final data = response.data;
    if (data == null) throw Exception('Failed to upload selfie');
    return Task.fromJson(data);
  }

  /// Email the OTP was last sent to, per task, so verify checks the same address.
  static final Map<String, String> _otpEmailByTask = {};

  /// HRMSbackend's task payload carries no customer email, so fall back to the staff
  /// customer list (which does) and match on phone, then name.
  Future<String?> _resolveCustomerEmail(Customer? customer) async {
    final direct = customer?.effectiveEmail?.trim();
    if (direct != null && direct.isNotEmpty) return direct;
    if (customer == null) return null;
    try {
      final customers = await CustomerService().getAllCustomers();
      String digits(String? s) => (s ?? '').replaceAll(RegExp(r'\D'), '');
      final phone = digits(customer.customerNumber);
      final name = customer.customerName.trim().toLowerCase();
      Customer? match;
      if (phone.length >= 6) {
        for (final c in customers) {
          final p = digits(c.customerNumber);
          if (p.isNotEmpty && (p.endsWith(phone) || phone.endsWith(p))) {
            match = c;
            break;
          }
        }
      }
      if (match == null && name.isNotEmpty) {
        for (final c in customers) {
          if (c.customerName.trim().toLowerCase() == name) {
            match = c;
            break;
          }
        }
      }
      final email = match?.effectiveEmail?.trim();
      return (email != null && email.isNotEmpty) ? email : null;
    } catch (_) {
      return null;
    }
  }

  /// Send OTP to customer email. Returns { success: true/false, message: string } for user-friendly success/failure feedback.
  Future<Map<String, dynamic>> sendOtp(String taskMongoId, {Customer? customer}) async {
    await _setToken();
    final email = await _resolveCustomerEmail(customer);
    if (email != null) {
      try {
        // HRMSbackend: POST /staff/geo-task/otp/send { email }
        final response = await _api.dio.post<dynamic>(
          '/staff/geo-task/otp/send',
          data: {'email': email},
        );
        final data = response.data;
        final success = data is Map && data['success'] == true;
        if (success) _otpEmailByTask[taskMongoId] = email;
        return {
          'success': success,
          'email': email,
          'message': (data is Map ? data['message']?.toString() : null) ??
              (success ? 'OTP sent to customer email' : 'Failed to send OTP'),
        };
      } on DioException catch (e) {
        if (!_isMissingRoute(e)) {
          return {
            'success': false,
            'message': _serverMessage(e) ??
                'We couldn\'t deliver the OTP to the customer email. Please try again.',
          };
        }
      } catch (_) {
        return {'success': false, 'message': 'Failed to send OTP. Please try again.'};
      }
    } else if (customer != null) {
      return {
        'success': false,
        'message': 'This customer has no email address. Add an email to the customer to send an OTP.',
      };
    }

    // Legacy app_backend route.
    try {
      final response = await _api.dio.post<Map<String, dynamic>>(
        '/tasks/$taskMongoId/send-otp',
      );
      final data = response.data;
      final success = data?['success'] == true;
      return {
        'success': success,
        'message':
            data?['message'] as String? ??
            (success ? 'OTP sent to customer email' : 'Failed to send OTP'),
      };
    } on DioException catch (e) {
      final body = e.response?.data;
      final msg = body is Map ? (body['message'] as String?) : null;
      return {
        'success': false,
        'message':
            msg ??
            (e.response?.statusCode == 404
                ? 'Task not found.'
                : e.response?.statusCode == 400
                ? 'Customer email is required. Please add email to customer.'
                : 'We couldn\'t deliver the OTP to the customer email. Please try again or check email configuration.'),
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Failed to send OTP. Please try again.',
      };
    }
  }

  /// Verify OTP. Returns updated task.
  Future<Task> verifyOtp(
    String taskMongoId,
    String otp, {
    double? lat,
    double? lng,
    String? fullAddress,
    Customer? customer,
  }) async {
    await _setToken();
    final email = _otpEmailByTask[taskMongoId] ?? await _resolveCustomerEmail(customer);
    if (email != null) {
      try {
        // HRMSbackend: POST /staff/geo-task/otp/verify { email, otp }, then record it on the task.
        await _api.dio.post<dynamic>(
          '/staff/geo-task/otp/verify',
          data: {'email': email, 'otp': otp},
        );
        await _api.dio.put<dynamic>('/staff/geo-task/$taskMongoId', data: {'fieldOutOtp': otp});
        return getTaskById(taskMongoId);
      } on DioException catch (e) {
        if (!_isMissingRoute(e)) {
          throw Exception(_serverMessage(e) ?? 'Verification failed');
        }
      }
    }

    // Legacy app_backend route.
    final payload = <String, dynamic>{'otp': otp};
    if (lat != null) payload['lat'] = lat;
    if (lng != null) payload['lng'] = lng;
    if (fullAddress != null && fullAddress.isNotEmpty) {
      payload['fullAddress'] = fullAddress;
    }
    final response = await _api.dio.post<Map<String, dynamic>>(
      '/tasks/$taskMongoId/verify-otp',
      data: payload,
    );
    final result = response.data;
    if (result == null) throw Exception('Verification failed');
    return Task.fromJson(result);
  }

  /// Exit ride: record exitType ('hold'|'exited'), reason, GPS.
  /// hold = staff can resume; exited = only after admin reopens.
  Future<void> exitRide(
    String taskMongoId,
    String exitReason, {
    required String exitType,
    double? lat,
    double? lng,
    String? fullAddress,
    String? pincode,
    double? tripDistanceKm,
    int? tripDurationSeconds,
    Map<String, dynamic>? travelActivityDuration,
    List<dynamic>? travelledRoute,
  }) async {
    await _setToken();
    final data = <String, dynamic>{
      'taskId': taskMongoId,
      'status': exitType == 'hold' ? 'hold' : 'exited',
      'exitReason': exitReason,
      'exitType': exitType,
    };
    if (lat != null) {
      data['lat'] = lat;
      data['latitude'] = lat;
    }
    if (lng != null) {
      data['lng'] = lng;
      data['longitude'] = lng;
    }
    if (fullAddress != null && fullAddress.isNotEmpty) {
      data['fullAddress'] = fullAddress;
      data['address'] = fullAddress;
    }
    if (pincode != null && pincode.isNotEmpty) data['pincode'] = pincode;
    if (tripDistanceKm != null) data['tripDistanceKm'] = tripDistanceKm;
    if (tripDurationSeconds != null) data['tripDurationSeconds'] = tripDurationSeconds;
    if (travelActivityDuration != null) data['travelActivityDuration'] = travelActivityDuration;
    if (travelledRoute != null && travelledRoute.isNotEmpty) data['travelledRoute'] = travelledRoute;

    try {
      await _api.dio.post<dynamic>('/staff/geo-task/live-tracking/status', data: data);
    } catch (_) {
      try {
        await _api.dio.post<dynamic>('/tracking/exit', data: data);
      } catch (e) {
        debugPrint('[exitRide] endpoint fallback caught: $e');
      }
    }
  }

  /// Arrived at destination: record in tasks + trackings, set status arrived.
  Future<void> arrivedRide(
    String taskMongoId, {
    required double lat,
    required double lng,
    String? fullAddress,
    String? pincode,
    String? sourceFullAddress,
    double? tripDistanceKm,
    int? tripDurationSeconds,
    Map<String, dynamic>? sourceLocation,
    Map<String, dynamic>? travelActivityDuration,
    List<dynamic>? travelledRoute,
  }) async {
    await _setToken();
    final nowTime = '${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}';
    final updatePayload = <String, dynamic>{
      'actualFieldInTime': nowTime,
      'latitude': lat,
      'longitude': lng,
      if (tripDistanceKm != null) 'tripDistanceKm': tripDistanceKm,
      if (tripDurationSeconds != null) 'tripDurationSeconds': tripDurationSeconds,
      if (travelledRoute != null && travelledRoute.isNotEmpty) 'travelledRoute': travelledRoute,
    };

    // Primary: update task on staff GEO route (which validates Field In geofence for internal branch visits)
    try {
      await _api.dio.put<dynamic>('/staff/geo-task/$taskMongoId', data: updatePayload);
    } on DioException catch (e) {
      if (e.response != null && e.response?.statusCode == 400) {
        final msg = (e.response?.data is Map)
            ? (e.response!.data['message'] ?? e.response!.data['error'])?.toString()
            : null;
        throw Exception(msg ?? 'Field In location verification failed');
      }
    } catch (e) {
      if (e is Exception && !e.toString().contains('DioException')) {
        rethrow;
      }
    }

    // Update live tracking status
    try {
      await _api.dio.post<dynamic>('/staff/geo-task/live-tracking/status', data: {
        'taskId': taskMongoId,
        'status': 'arrived',
        'latitude': lat,
        'longitude': lng,
        if (tripDistanceKm != null) 'tripDistanceKm': tripDistanceKm,
        if (tripDurationSeconds != null) 'tripDurationSeconds': tripDurationSeconds,
        if (travelActivityDuration != null) 'travelActivityDuration': travelActivityDuration,
        if (travelledRoute != null && travelledRoute.isNotEmpty) 'travelledRoute': travelledRoute,
      });
    } catch (_) {}

    final data = <String, dynamic>{
      'taskId': taskMongoId,
      'lat': lat,
      'lng': lng,
    };
    if (fullAddress != null && fullAddress.isNotEmpty) {
      data['fullAddress'] = fullAddress;
    }
    if (pincode != null && pincode.isNotEmpty) data['pincode'] = pincode;
    if (sourceFullAddress != null && sourceFullAddress.isNotEmpty) {
      data['sourceFullAddress'] = sourceFullAddress;
    }
    if (tripDistanceKm != null) data['tripDistanceKm'] = tripDistanceKm;
    if (tripDurationSeconds != null) {
      data['tripDurationSeconds'] = tripDurationSeconds;
    }
    if (sourceLocation != null) data['sourceLocation'] = sourceLocation;
    if (travelActivityDuration != null) {
      data['travelActivityDuration'] = travelActivityDuration;
    }
    try {
      await _api.dio.post<dynamic>('/tracking/arrived', data: data);
    } catch (_) {}
  }

  /// Restart task after exit: record in tasks_restarted, set status in_progress.
  Future<void> restartTask(
    String taskMongoId, {
    double? lat,
    double? lng,
    String? fullAddress,
    String? pincode,
  }) async {
    await _setToken();

    // HRMSbackend has no restart route: resuming puts the task back into its in-progress
    // status with PUT /staff/geo-task/:id - 'Arrived' when Field In was already done
    // before the exit, otherwise 'Started'.
    try {
      var resumeStatus = 'Started';
      try {
        final current = await _api.dio.get<dynamic>('/staff/geo-task/$taskMongoId');
        final d = current.data is Map ? (current.data as Map)['data'] : null;
        if (d is Map && d['actualFieldInTime'] != null) resumeStatus = 'Arrived';
      } catch (_) {}
      await _api.dio.put<dynamic>('/staff/geo-task/$taskMongoId', data: {
        'status': resumeStatus,
        if (lat != null) 'latitude': lat,
        if (lng != null) 'longitude': lng,
      });
      // Resume point on the tracking trail.
      unawaited(
        _api.dio
            .post<dynamic>('/staff/geo-task/live-tracking/status', data: {
              'taskId': taskMongoId,
              'status': 'active',
              if (lat != null) 'latitude': lat,
              if (lng != null) 'longitude': lng,
              if (fullAddress != null && fullAddress.isNotEmpty) 'address': fullAddress,
            })
            .then((_) {}, onError: (_) {}),
      );
      return;
    } on DioException catch (e) {
      if (!_isMissingRoute(e)) {
        throw Exception(_serverMessage(e) ?? 'Could not resume the task. Please try again.');
      }
    }

    // Legacy app_backend route.
    final data = <String, dynamic>{'taskId': taskMongoId};
    if (lat != null) data['lat'] = lat;
    if (lng != null) data['lng'] = lng;
    if (fullAddress != null && fullAddress.isNotEmpty) {
      data['fullAddress'] = fullAddress;
    }
    if (pincode != null && pincode.isNotEmpty) data['pincode'] = pincode;
    await _api.dio.post<dynamic>('/tracking/restart', data: data);
  }

  /// Mark task as completed (sets status and completedDate).
  Future<Task> endTask(
    String taskMongoId, {
    Map<String, dynamic>? travelActivityDuration,
    double? lat,
    double? lng,
    String? fieldOutNotes,
    String? fieldOutOtp,
    String? fieldOutImage,
    Map<String, dynamic>? answers,
  }) async {
    await _setToken();
    final nowTime = '${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}';
    final resolvedAnswers = answers != null ? Map<String, dynamic>.from(answers) : <String, dynamic>{};
    final effectiveNotes = (fieldOutNotes != null && fieldOutNotes.trim().isNotEmpty)
        ? fieldOutNotes.trim()
        : (resolvedAnswers['Description']?.toString() ?? 'Completed');
    if (!resolvedAnswers.containsKey('Description') ||
        resolvedAnswers['Description'] == null ||
        resolvedAnswers['Description'].toString().trim().isEmpty) {
      resolvedAnswers['Description'] = effectiveNotes;
    }

    final completePayload = <String, dynamic>{
      'status': 'Completed',
      'fieldOutTime': nowTime,
      if (lat != null) 'latitude': lat,
      if (lng != null) 'longitude': lng,
      'fieldOutNotes': effectiveNotes,
      if (fieldOutOtp != null) 'fieldOutOtp': fieldOutOtp,
      if (fieldOutImage != null) 'fieldOutImage': fieldOutImage,
      'answers': resolvedAnswers,
    };

    // 1. Primary: Complete task via /staff/geo-task/:id (runs Field Out geofence check for internal tasks)
    try {
      final response = await _api.dio.put<dynamic>('/staff/geo-task/$taskMongoId', data: completePayload);
      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = response.data;
        final payload = (data is Map && data['data'] != null)
            ? (data['data'] is Map ? data['data'] as Map<String, dynamic> : data as Map<String, dynamic>)
            : (data is Map ? data as Map<String, dynamic> : null);
        if (payload != null) return Task.fromJson(payload);
      }
    } on DioException catch (e) {
      if (e.response != null && e.response?.statusCode == 400) {
        final msg = (e.response?.data is Map)
            ? (e.response!.data['message'] ?? e.response!.data['error'])?.toString()
            : null;
        throw Exception(msg ?? 'Field Out location verification failed');
      }
    } catch (e) {
      if (e is Exception && !e.toString().contains('DioException')) {
        rethrow;
      }
    }

    // 2. Legacy fallback
    try {
      final response = await _api.dio.post<Map<String, dynamic>>(
        '/tasks/$taskMongoId/end',
        data: travelActivityDuration == null
            ? null
            : {'travelActivityDuration': travelActivityDuration},
      );
      final data = response.data;
      if (data != null) return Task.fromJson(data);
    } catch (_) {}

    return getTaskById(taskMongoId);
  }

  /// Fetch travel allowances for the logged-in staff
  Future<List<Map<String, dynamic>>> getStaffAllowances() async {
    await _setToken();
    try {
      final response = await _api.dio.get<dynamic>('/staff/geo-task/allowances');
      final body = response.data;
      if (body is Map && body['data'] is List) {
        return (body['data'] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// Fetch task history for staff member
  Future<List<Task>> getStaffTaskHistory({String? date}) async {
    await _setToken();
    try {
      final query = <String, dynamic>{};
      if (date != null && date.isNotEmpty) query['date'] = date;
      final response = await _api.dio.get<dynamic>('/staff/geo-task/history', queryParameters: query);
      final body = response.data;
      if (body is Map && body['data'] is List) {
        return (body['data'] as List)
            .whereType<Map>()
            .map((e) => Task.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// Get active field journey status for external staff
  Future<Map<String, dynamic>?> getJourneyStatus() async {
    await _setToken();
    try {
      final response = await _api.dio.get<dynamic>('/staff/geo-task/journey');
      if (response.data is Map && response.data['data'] != null) {
        return Map<String, dynamic>.from(response.data['data'] as Map);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Start a self-logged field journey (External staff)
  Future<Map<String, dynamic>> journeyFieldIn({
    required double latitude,
    required double longitude,
    String? address,
  }) async {
    await _setToken();
    try {
      final response = await _api.dio.post<dynamic>(
        '/staff/geo-task/journey/field-in',
        data: {
          'latitude': latitude,
          'longitude': longitude,
          if (address != null) 'address': address,
        },
      );
      return Map<String, dynamic>.from(response.data as Map);
    } on DioException catch (e) {
      final msg = (e.response?.data is Map)
          ? (e.response!.data['message'] ?? e.response!.data['error'])?.toString()
          : null;
      throw Exception(msg ?? 'Failed to perform Field In');
    }
  }

  /// Complete a self-logged field journey (External staff)
  Future<Map<String, dynamic>> journeyFieldOut({
    required double latitude,
    required double longitude,
    String? address,
    String? fieldOutNotes,
    String? fieldOutImage,
    String? fieldOutOtp,
    Map<String, dynamic>? answers,
  }) async {
    await _setToken();
    final resolvedAnswers = answers != null ? Map<String, dynamic>.from(answers) : <String, dynamic>{};
    final effectiveNotes = (fieldOutNotes != null && fieldOutNotes.trim().isNotEmpty)
        ? fieldOutNotes.trim()
        : (resolvedAnswers['Description']?.toString() ?? 'Completed');
    if (!resolvedAnswers.containsKey('Description') ||
        resolvedAnswers['Description'] == null ||
        resolvedAnswers['Description'].toString().trim().isEmpty) {
      resolvedAnswers['Description'] = effectiveNotes;
    }
    if (fieldOutImage != null && fieldOutImage.isNotEmpty && !resolvedAnswers.containsKey('Proof Photo')) {
      resolvedAnswers['Proof Photo'] = fieldOutImage;
    }
    if (fieldOutOtp != null && fieldOutOtp.isNotEmpty && !resolvedAnswers.containsKey('OTP')) {
      resolvedAnswers['OTP'] = fieldOutOtp;
    }

    try {
      final response = await _api.dio.post<dynamic>(
        '/staff/geo-task/journey/field-out',
        data: {
          'latitude': latitude,
          'longitude': longitude,
          if (address != null) 'address': address,
          'fieldOutNotes': effectiveNotes,
          if (fieldOutImage != null) 'fieldOutImage': fieldOutImage,
          if (fieldOutOtp != null) 'fieldOutOtp': fieldOutOtp,
          'answers': resolvedAnswers,
        },
      );
      return Map<String, dynamic>.from(response.data as Map);
    } on DioException catch (e) {
      final msg = (e.response?.data is Map)
          ? (e.response!.data['message'] ?? e.response!.data['error'])?.toString()
          : null;
      throw Exception(msg ?? 'Failed to perform Field Out');
    }
  }

  // ─── Form (arrived screen) ───────────────────────────────────────────────

  /// Get form templates assigned to staff. Used on arrived screen.
  Future<List<Map<String, dynamic>>> getFormTemplatesForStaff(
    String staffId,
  ) async {
    await _setToken();
    final response = await _api.dio.get<Map<String, dynamic>>(
      '/forms/templates/assigned',
      queryParameters: {'staffId': staffId},
    );
    final data = response.data;
    if (data == null) return [];
    final list = data['data']?['templates'] as List?;
    if (list == null) return [];
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  /// Check if form response exists for task+staff.
  Future<List<Map<String, dynamic>>> getFormResponsesForTask({
    required String taskId,
    required String staffId,
  }) async {
    await _setToken();
    final response = await _api.dio.get<Map<String, dynamic>>(
      '/forms/responses',
      queryParameters: {'taskId': taskId, 'staffId': staffId},
    );
    final data = response.data;
    if (data == null) return [];
    final list = data['data']?['responses'] as List?;
    if (list == null) return [];
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  /// Submit form response. Returns created response.
  Future<void> submitFormResponse({
    required String templateId,
    required String taskId,
    required String staffId,
    required Map<String, dynamic> responses,
  }) async {
    await _setToken();
    await _api.dio.post<Map<String, dynamic>>(
      '/forms/responses',
      data: {
        'templateId': templateId,
        'taskId': taskId,
        'staffId': staffId,
        'responses': responses,
      },
    );
  }

  /// Fetch the current staff member's field type ('Internal Field Employee' or 'External Field Employee')
  Future<String?> getStaffFieldType() async {
    try {
      // Shared, cached profile instead of another raw /staff/profile round trip.
      final res = await AuthService().getProfile();
      final data = res['data'];
      if (data is Map) {
        final staff = data['staffData'] is Map ? data['staffData'] as Map : data;
        final fieldType = staff['fieldType']?.toString();
        if (fieldType != null && fieldType.isNotEmpty) {
          return fieldType;
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
