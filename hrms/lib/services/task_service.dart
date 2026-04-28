import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:hrms/config/constants.dart';
import 'package:hrms/models/task.dart';
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
        'lat=${lat?.toStringAsFixed(6) ?? "-"} '
        'lng=${lng?.toStringAsFixed(6) ?? "-"} '
        'timestamp=${body['timestamp'] ?? "-"} '
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
          await sender._api.dio.post<dynamic>('/tracking/store', data: record);
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
    if (storedBusinessId != null && storedBusinessId.isNotEmpty) {
      body['businessId'] = storedBusinessId;
    }
    if (sourceLocation != null) body['sourceLocation'] = sourceLocation;
    if (destinationLocation != null) {
      body['destinationLocation'] = destinationLocation;
    }
    final response = await _api.dio.post<Map<String, dynamic>>(
      '/tasks',
      data: body,
    );
    final data = response.data;
    if (data == null) throw Exception('Failed to create task');
    return Task.fromJson(data);
  }

  Future<List<Task>> getAllTasks() async {
    try {
      await _setToken();
      final response = await _api.dio.get<dynamic>('/tasks');
      final body = response.data;
      if (body is List) {
        return (body)
            .map((j) => Task.fromJson(j as Map<String, dynamic>))
            .toList();
      }
      final list = (body is Map && body['data'] != null)
          ? body['data'] as List?
          : null;
      if (list != null) {
        return list
            .map((j) => Task.fromJson(j as Map<String, dynamic>))
            .toList();
      }
      throw Exception('Failed to load tasks: invalid response');
    } on DioException catch (e) {
      throw Exception(
        'Failed to load tasks: ${e.response?.statusCode ?? e.message}',
      );
    }
  }

  Future<List<Task>> getAssignedTasks(String staffId) async {
    try {
      await _setToken();
      final response = await _api.dio.get<dynamic>('/tasks/staff/$staffId');
      final body = response.data;
      if (body is List) {
        return (body)
            .map((j) => Task.fromJson(j as Map<String, dynamic>))
            .toList();
      }
      final list = (body is Map && body['data'] != null)
          ? body['data'] as List?
          : null;
      if (list != null) {
        return list
            .map((j) => Task.fromJson(j as Map<String, dynamic>))
            .toList();
      }
      throw Exception('Failed to load assigned tasks: invalid response');
    } on DioException catch (e) {
      throw Exception(
        'Failed to load assigned tasks: ${e.response?.statusCode ?? e.message}',
      );
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
      if (startDate != null) {
        query['startDate'] = DateTime(
          startDate.year,
          startDate.month,
          startDate.day,
        ).toUtc().toIso8601String();
      }
      if (endDate != null) {
        query['endDate'] = DateTime(
          endDate.year,
          endDate.month,
          endDate.day,
          23,
          59,
          59,
          999,
        ).toUtc().toIso8601String();
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
    try {
      await _setToken();
      final response = await _api.dio.get<Map<String, dynamic>>('/tasks/$id');
      final data = response.data;
      if (data == null) throw Exception('Failed to load task');
      return Task.fromJson(data);
    } on DioException catch (e) {
      throw Exception(
        'Failed to load task: ${e.response?.statusCode ?? e.message}',
      );
    }
  }

  /// GPS points from Tracking until Arrived (for task detail map polyline).
  /// Returns [{lat, lng}, ...] sorted by time, trimmed at first `status: arrived` or [arrivalTime].
  Future<List<Map<String, double>>> getTravelledPathUntilArrived(
    String taskMongoId, {
    DateTime? arrivalTime,
  }) async {
    try {
      await _setToken();
      final response = await _api.dio.get<Map<String, dynamic>>(
        '/tasks/$taskMongoId/tracking-path',
      );
      final path = response.data?['path'] as List<dynamic>? ?? [];
      return _filterTrackingPathUntilArrived(path, arrivalTime);
    } catch (_) {
      return [];
    }
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
      final lat = (r['latitude'] as num?)?.toDouble();
      final lng = (r['longitude'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;
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
      endExclusive = 0;
      for (var i = 0; i < rows.length; i++) {
        final t = rows[i]['ts'] as DateTime;
        if (t.isAfter(arrivalTime)) break;
        endExclusive = i + 1;
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

  /// Fetch full task completion report: task, timeline, route points from DB.
  Future<TaskCompletionReport> getTaskCompletionReport(String taskId) async {
    try {
      await _setToken();
      final response = await _api.dio.get<Map<String, dynamic>>(
        '/tasks/$taskId/completion-report',
      );
      final data = response.data;
      if (data == null) throw Exception('Failed to load completion report');
      return TaskCompletionReport.fromJson(data);
    } on DioException catch (e) {
      throw Exception(
        'Failed to load report: ${e.response?.statusCode ?? e.message}',
      );
    }
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
      final response = await _api.dio.patch<Map<String, dynamic>>(
        '/tasks/$id',
        data: body,
      );
      final data = response.data;
      if (data == null) throw Exception('Failed to update task');
      return Task.fromJson(data);
    } on DioException catch (e) {
      final msg = e.response?.data is Map
          ? (e.response!.data as Map)['message']?.toString()
          : null;
      throw Exception(
        msg ?? 'Failed to update task: ${e.response?.statusCode ?? e.message}',
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
      await _api.dio.post<dynamic>('/tracking/store', data: body);
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

  /// Upload photo proof for task. Returns updated task.
  Future<Task> uploadPhotoProof(
    String taskMongoId,
    String filePath, {
    String? description,
    double? lat,
    double? lng,
    String? fullAddress,
  }) async {
    await _setToken();
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

  /// Send OTP to customer email. Returns { success: true/false, message: string } for user-friendly success/failure feedback.
  Future<Map<String, dynamic>> sendOtp(String taskMongoId) async {
    await _setToken();
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
  }) async {
    await _setToken();
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
  }) async {
    await _setToken();
    final data = <String, dynamic>{
      'taskId': taskMongoId,
      'exitReason': exitReason,
      'exitType': exitType,
    };
    if (lat != null) data['lat'] = lat;
    if (lng != null) data['lng'] = lng;
    if (fullAddress != null && fullAddress.isNotEmpty) {
      data['fullAddress'] = fullAddress;
    }
    if (pincode != null && pincode.isNotEmpty) data['pincode'] = pincode;
    await _api.dio.post<dynamic>('/tracking/exit', data: data);
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
  }) async {
    await _setToken();
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
    await _api.dio.post<dynamic>('/tracking/arrived', data: data);
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
  }) async {
    await _setToken();
    final response = await _api.dio.post<Map<String, dynamic>>(
      '/tasks/$taskMongoId/end',
      data: travelActivityDuration == null
          ? null
          : {'travelActivityDuration': travelActivityDuration},
    );
    final data = response.data;
    if (data == null) throw Exception('Failed to end task');
    return Task.fromJson(data);
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
}
