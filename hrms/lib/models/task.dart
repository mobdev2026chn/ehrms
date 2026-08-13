import 'package:hrms/models/customer.dart';

DateTime? _parseDate(dynamic value) {
  if (value == null) return null;
  if (value is String) return DateTime.tryParse(value);
  if (value is num) {
    return DateTime.fromMillisecondsSinceEpoch(value.toInt(), isUtc: true);
  }
  if (value is Map<dynamic, dynamic>) {
    final dateStr = value[r'$date'];
    if (dateStr != null) return DateTime.tryParse(dateStr.toString());
  }
  return null;
}

List<T> _parseList<T>(dynamic json, T Function(Map<String, dynamic>) fromJson) {
  if (json == null || json is! List) return [];
  final list = <T>[];
  for (final item in json) {
    if (item is Map<String, dynamic>) {
      try {
        list.add(fromJson(item));
      } catch (_) {}
    }
  }
  return list;
}

class TaskLocation {
  final double lat;
  final double lng;
  final String? address;
  final String? fullAddress;
  final String? pincode;

  /// When staff tapped "Arrived", backend may compute whether the arrival GPS
  /// differs from the customer's stored GPS (~50m threshold).
  final bool? overridencustomerlocation;

  /// When staff changed destination before arrival, backend may compute this.
  final bool? overridendestinationlocation;

  const TaskLocation({
    required this.lat,
    required this.lng,
    this.address,
    this.fullAddress,
    this.pincode,
    this.overridencustomerlocation,
    this.overridendestinationlocation,
  });

  String? get displayAddress => address ?? fullAddress;

  factory TaskLocation.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const TaskLocation(lat: 0, lng: 0);
    return TaskLocation(
      lat: (json['lat'] as num?)?.toDouble() ?? 0,
      lng: (json['lng'] as num?)?.toDouble() ?? 0,
      address: json['address'] as String?,
      fullAddress: json['fullAddress'] as String?,
      pincode: json['pincode'] as String?,
      overridencustomerlocation:
          json['overridencustomerlocation'] as bool?,
      overridendestinationlocation:
          json['overridendestinationlocation'] as bool?,
    );
  }

  Map<String, dynamic> toJson() => {
    'lat': lat,
    'lng': lng,
    if (address != null) 'address': address,
    if (fullAddress != null) 'fullAddress': fullAddress,
    if (pincode != null) 'pincode': pincode,
    if (overridencustomerlocation != null)
      'overridencustomerlocation': overridencustomerlocation,
    if (overridendestinationlocation != null)
      'overridendestinationlocation': overridendestinationlocation,
  };
}

class TravelActivityDuration {
  final int driveDuration;
  final int walkDuration;
  final int stopDuration;

  const TravelActivityDuration({
    this.driveDuration = 0,
    this.walkDuration = 0,
    this.stopDuration = 0,
  });

  factory TravelActivityDuration.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const TravelActivityDuration();
    return TravelActivityDuration(
      driveDuration: (json['driveDuration'] as num?)?.toInt() ?? 0,
      walkDuration: (json['walkDuration'] as num?)?.toInt() ?? 0,
      stopDuration: (json['stopDuration'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'driveDuration': driveDuration,
    'walkDuration': walkDuration,
    'stopDuration': stopDuration,
  };
}

class TaskExitRecord {
  final double lat;
  final double lng;
  final String? address;
  final String? fullAddress;
  final String? pincode;
  final String exitReason;
  final DateTime? exitedAt;
  final int? batteryPercent;

  const TaskExitRecord({
    required this.lat,
    required this.lng,
    this.address,
    this.fullAddress,
    this.pincode,
    required this.exitReason,
    this.exitedAt,
    this.batteryPercent,
  });

  factory TaskExitRecord.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const TaskExitRecord(lat: 0, lng: 0, exitReason: '');
    }
    final loc = json['exitLocation'] as Map<String, dynamic>? ?? json;
    return TaskExitRecord(
      lat: (loc['lat'] as num?)?.toDouble() ?? 0,
      lng: (loc['lng'] as num?)?.toDouble() ?? 0,
      address: (loc['address'] ?? loc['fullAddress']) as String?,
      fullAddress: loc['fullAddress'] as String?,
      pincode: loc['pincode'] as String?,
      exitReason: (json['exitReason'] as String?) ?? '',
      exitedAt: Task._dateFromJson(json['exitedAt'] ?? json['time']),
      batteryPercent: (json['batteryPercent'] as num?)?.toInt(),
    );
  }
}

class TaskRestartRecord {
  final double lat;
  final double lng;
  final String? address;
  final String? fullAddress;
  final String? pincode;
  final DateTime? resumedAt;
  final int? batteryPercent;

  const TaskRestartRecord({
    required this.lat,
    required this.lng,
    this.address,
    this.fullAddress,
    this.pincode,
    this.resumedAt,
    this.batteryPercent,
  });

  factory TaskRestartRecord.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const TaskRestartRecord(lat: 0, lng: 0);
    final loc = json['restartLocation'] as Map<String, dynamic>? ?? json;
    return TaskRestartRecord(
      lat: (loc['lat'] as num?)?.toDouble() ?? 0,
      lng: (loc['lng'] as num?)?.toDouble() ?? 0,
      address: (loc['address'] ?? loc['fullAddress']) as String?,
      fullAddress: loc['fullAddress'] as String?,
      pincode: loc['pincode'] as String?,
      resumedAt: _parseDate(
        json['restartedAt'] ?? json['resumedAt'] ?? json['time'],
      ),
      batteryPercent: (json['batteryPercent'] as num?)?.toInt(),
    );
  }
}

class TaskDestinationRecord {
  final double lat;
  final double lng;
  final String? address;
  final DateTime? changedAt;

  const TaskDestinationRecord({
    required this.lat,
    required this.lng,
    this.address,
    this.changedAt,
  });

  factory TaskDestinationRecord.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const TaskDestinationRecord(lat: 0, lng: 0);
    return TaskDestinationRecord(
      lat: (json['lat'] as num?)?.toDouble() ?? 0,
      lng: (json['lng'] as num?)?.toDouble() ?? 0,
      address: json['address'] as String?,
      changedAt: _parseDate(json['changedAt']),
    );
  }
}

enum TaskStatus {
  onlineReady,
  assigned,
  approved,
  staffapproved,
  pending,
  scheduled,
  inProgress,
  arrived,
  exited,
  exitedOnArrival,
  holdOnArrival,
  reopenedOnArrival,
  waitingForApproval,
  completed,
  rejected,
  cancelled,
  reopened,
  hold,
}

class Task {
  final String? id;
  final String taskId;
  final String taskTitle;
  final String description;
  final String assignedTo;
  final String? customerId;
  final Customer? customer;
  final DateTime expectedCompletionDate;
  final DateTime? completedDate;
  final DateTime? assignedDate;
  final TaskStatus status;
  final bool isOtpRequired;
  final bool isGeoFenceRequired;
  final bool isPhotoRequired;
  final bool isFormRequired;

  /// From customFields.otpVerified when present (e.g. after OTP verification).
  final bool? isOtpVerified;

  /// From customFields.otpVerifiedAt when present.
  final DateTime? otpVerifiedAt;

  /// From progressSteps.photoProof when present.
  final bool? photoProof;

  /// From progressSteps.formFilled when present.
  final bool? formFilled;

  /// From progressSteps.checkinCustomerPlace when present.
  final bool? checkinCustomerPlace;

  /// From progressSteps.checkoutCustomerPlace when present.
  final bool? checkoutCustomerPlace;

  /// URL of uploaded photo proof.
  final String? photoProofUrl;

  /// When photo proof was uploaded.
  final DateTime? photoProofUploadedAt;

  /// Company/workflow settings (read-only). Default false if not provided by API.
  final bool requireApprovalOnComplete;
  final bool autoApprove;

  final TaskLocation? sourceLocation;
  final TaskLocation? destinationLocation;
  /// GPS + address where staff tapped Arrived (TaskDetails / arrived* fields).
  final TaskLocation? arrivalLocation;

  /// Exit history – each exit is a separate record.
  final List<TaskExitRecord> tasksExit;

  /// Latest exit type from tasks.task_exit: 'hold' = staff can resume; 'exited' = only after admin reopens.
  final String? taskExitStatus;

  /// Restart history – when task resumed after exit.
  final List<TaskRestartRecord> tasksRestarted;

  /// Destination change history.
  final List<TaskDestinationRecord> destinations;

  /// Trip completion details (stored when staff arrives).
  final double? tripDistanceKm;
  final int? tripDurationSeconds;
  final DateTime? arrivalTime;
  final TravelActivityDuration? travelActivityDuration;

  /// Start time (when task was started).
  final DateTime? startTime;

  /// Photo proof address (where photo was taken).
  final String? photoProofAddress;

  /// OTP verified address.
  final String? otpVerifiedAddress;

  /// Battery at key events (from tracking; optional).
  final int? startBatteryPercent;
  final int? arrivalBatteryPercent;
  final int? photoProofBatteryPercent;
  final int? otpVerifiedBatteryPercent;
  final int? completedBatteryPercent;

  Task({
    this.id,
    required this.taskId,
    required this.taskTitle,
    required this.description,
    required this.assignedTo,
    this.customerId,
    this.customer,
    required this.expectedCompletionDate,
    this.completedDate,
    this.assignedDate,
    required this.status,
    this.isOtpRequired = false,
    this.isGeoFenceRequired = false,
    this.isPhotoRequired = false,
    this.isFormRequired = false,
    this.isOtpVerified,
    this.otpVerifiedAt,
    this.photoProof,
    this.formFilled,
    this.checkinCustomerPlace,
    this.checkoutCustomerPlace,
    this.photoProofUrl,
    this.photoProofUploadedAt,
    this.requireApprovalOnComplete = false,
    this.autoApprove = false,
    this.sourceLocation,
    this.destinationLocation,
    this.arrivalLocation,
    this.tasksExit = const [],
    this.taskExitStatus,
    this.tasksRestarted = const [],
    this.destinations = const [],
    this.tripDistanceKm,
    this.tripDurationSeconds,
    this.arrivalTime,
    this.travelActivityDuration,
    this.startTime,
    this.photoProofAddress,
    this.otpVerifiedAddress,
    this.startBatteryPercent,
    this.arrivalBatteryPercent,
    this.photoProofBatteryPercent,
    this.otpVerifiedBatteryPercent,
    this.completedBatteryPercent,
  });

  factory Task.fromJson(Map<String, dynamic> json) {
    final customerIdVal = json['customerId'];
    final customer = customerIdVal is Map
        ? Customer.fromJson(Map<String, dynamic>.from(customerIdVal))
        : (json['customer'] is Map
              ? Customer.fromJson(
                  Map<String, dynamic>.from(json['customer'] as Map),
                )
              : null);
    return Task(
      id: _stringFromId(json['_id']),
      taskId: (json['taskId'] as String?) ?? '',
      taskTitle: (json['taskTitle'] as String?) ?? '',
      description: (json['description'] as String?) ?? '',
      assignedTo: _stringFromId(json['assignedTo']) ?? '',
      customerId: _stringFromId(customerIdVal),
      customer: customer,
      expectedCompletionDate:
          _dateFromJson(json['expectedCompletionDate']) ?? DateTime.now(),
      completedDate: _dateFromJson(json['completedDate']),
      assignedDate:
          _dateFromJson(json['assignedDate']) ??
          _dateFromJson(json['createdAt']),
      status: statusFromJson((json['status'] as String?) ?? ''),
      isOtpRequired:
          (json['customFields'] != null
              ? (json['customFields']['otpRequired'] as bool?)
              : null) ??
          (json['isOtpRequired'] as bool?) ??
          false,
      isGeoFenceRequired: json['customFields'] != null
          ? (json['customFields']['geoFenceRequired'] as bool?) ?? false
          : false,
      isPhotoRequired: json['customFields'] != null
          ? (json['customFields']['photoRequired'] as bool?) ?? false
          : false,
      isFormRequired: json['customFields'] != null
          ? (json['customFields']['formRequired'] as bool?) ?? false
          : false,
      isOtpVerified:
          (json['customFields']?['otpVerified'] as bool?) ??
          (json['progressSteps']?['otpVerified'] as bool?),
      otpVerifiedAt: _dateFromJson(
        json['customFields']?['otpVerifiedAt'] ?? json['otpVerifiedAt'],
      ),
      photoProof: json['progressSteps'] != null
          ? (json['progressSteps']['photoProof'] as bool?)
          : null,
      formFilled: json['progressSteps'] != null
          ? (json['progressSteps']['formFilled'] as bool?)
          : null,
      checkinCustomerPlace: json['progressSteps'] != null
          ? (json['progressSteps']['checkinCustomerPlace'] as bool?)
          : null,
      checkoutCustomerPlace: json['progressSteps'] != null
          ? (json['progressSteps']['checkoutCustomerPlace'] as bool?)
          : null,
      photoProofUrl: json['photoProofUrl'] as String?,
      photoProofUploadedAt: _dateFromJson(json['photoProofUploadedAt']),
      requireApprovalOnComplete:
          (json['requireApprovalOnComplete'] as bool?) ??
          (json['settings'] != null
              ? (json['settings']['requireApprovalOnComplete'] as bool?) ??
                    false
              : false),
      autoApprove:
          (json['autoApprove'] as bool?) ??
          (json['settings'] != null
              ? (json['settings']['autoApprove'] as bool?) ?? false
              : false),
      sourceLocation: json['sourceLocation'] != null
          ? TaskLocation.fromJson(
              json['sourceLocation'] as Map<String, dynamic>,
            )
          : null,
      destinationLocation: json['destinationLocation'] != null
          ? TaskLocation.fromJson(
              json['destinationLocation'] as Map<String, dynamic>,
            )
          : null,
      arrivalLocation: _parseArrivalLocation(json),
      tasksExit: _parseList(
        json['exit'] ?? json['tasks_exit'],
        TaskExitRecord.fromJson,
      ),
      taskExitStatus: (json['task_exit'] is Map
          ? (json['task_exit'] as Map<String, dynamic>)['status'] as String?
          : null),
      tasksRestarted: _parseList(
        json['restarted'] ?? json['tasks_restarted'],
        TaskRestartRecord.fromJson,
      ),
      destinations: _parseList(
        json['destinations'],
        TaskDestinationRecord.fromJson,
      ),
      tripDistanceKm: (json['tripDistanceKm'] as num?)?.toDouble(),
      tripDurationSeconds: json['tripDurationSeconds'] as int?,
      arrivalTime: _dateFromJson(json['arrivalTime']),
      travelActivityDuration: json['travelActivityDuration'] != null
          ? TravelActivityDuration.fromJson(
              json['travelActivityDuration'] as Map<String, dynamic>,
            )
          : null,
      startTime: _dateFromJson(json['startTime']),
      photoProofAddress: json['photoProofAddress'] as String?,
      otpVerifiedAddress: json['otpVerifiedAddress'] as String?,
      startBatteryPercent: (json['startBatteryPercent'] as num?)?.toInt(),
      arrivalBatteryPercent: (json['arrivalBatteryPercent'] as num?)?.toInt(),
      photoProofBatteryPercent: (json['photoProofBatteryPercent'] as num?)
          ?.toInt(),
      otpVerifiedBatteryPercent: (json['otpVerifiedBatteryPercent'] as num?)
          ?.toInt(),
      completedBatteryPercent: (json['completedBatteryPercent'] as num?)
          ?.toInt(),
    );
  }

  static TaskLocation? _parseArrivalLocation(Map<String, dynamic> json) {
    final al = json['arrivalLocation'];
    if (al is Map<String, dynamic>) {
      final loc = TaskLocation.fromJson(al);
      if (loc.lat != 0 || loc.lng != 0) return loc;
    }
    final lat = (json['arrivedLatitude'] as num?)?.toDouble();
    final lng = (json['arrivedLongitude'] as num?)?.toDouble();
    if (lat != null && lng != null && (lat != 0 || lng != 0)) {
      final addr = json['arrivedFullAddress'] as String?;
      return TaskLocation(lat: lat, lng: lng, address: addr, fullAddress: addr);
    }
    return null;
  }

  static String? _stringFromId(dynamic value) {
    if (value == null) return null;
    if (value is String) return value;
    if (value is Map<dynamic, dynamic>) {
      final oid = value[r'$oid'];
      if (oid != null) return oid is String ? oid : oid.toString();
      final id = value['_id'];
      if (id != null) return id is String ? id : id.toString();
    }
    return value.toString();
  }

  static DateTime? _dateFromJson(dynamic value) {
    if (value == null) return null;
    if (value is String) return DateTime.tryParse(value);
    if (value is num) {
      return DateTime.fromMillisecondsSinceEpoch(value.toInt(), isUtc: true);
    }
    if (value is Map<dynamic, dynamic>) {
      final dateStr = value[r'$date'];
      if (dateStr != null) return DateTime.tryParse(dateStr.toString());
    }
    return null;
  }

  /// Backend expects snake_case: in_progress, waiting_for_approval, etc.
  static String statusToApiString(TaskStatus s) {
    switch (s) {
      case TaskStatus.inProgress:
        return 'in_progress';
      case TaskStatus.waitingForApproval:
        return 'waiting_for_approval';
      default:
        return s.name;
    }
  }

  /// Parse status from API: case-insensitive, trims spaces and underscores for matching.
  static TaskStatus statusFromJson(String status) {
    final raw = status.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    final noSpaces = raw.replaceAll(' ', '').replaceAll('_', '');
    switch (noSpaces) {
      case 'assigned':
      case 'assignedtasks':
        return TaskStatus.assigned;
      case 'pending':
      case 'pendingtasks':
        return TaskStatus.pending;
      case 'scheduled':
      case 'scheduledtasks':
        return TaskStatus.scheduled;
      case 'in_progress':
      case 'inprogress':
        return TaskStatus.inProgress;
      case 'completed':
      case 'completedtasks':
        return TaskStatus.completed;
      case 'arrived':
        return TaskStatus.arrived;
      case 'exited':
        return TaskStatus.exited;
      case 'exitedonarrival':
      case 'exitonarrival':
        return TaskStatus.exitedOnArrival;
      case 'holdonarrival':
        return TaskStatus.holdOnArrival;
      case 'reopenedonarrival':
        return TaskStatus.reopenedOnArrival;
      case 'waiting_for_approval':
      case 'waitingforapproval':
        return TaskStatus.waitingForApproval;
      case 'notyetstarted':
        return TaskStatus.assigned;
      case 'delayedtasks':
      case 'servingtoday':
        return TaskStatus.pending;
      case 'completedtasks':
        return TaskStatus.completed;
      case 'onhold':
        return TaskStatus.hold;
      case 'approved':
        return TaskStatus.approved;
      case 'staffapproved':
        return TaskStatus.staffapproved;
      case 'rejected':
        return TaskStatus.rejected;
      case 'cancelled':
      case 'cancelledtasks':
        return TaskStatus.cancelled;
      case 'reopened':
        return TaskStatus.reopened;
      case 'hold':
        return TaskStatus.hold;
      default:
        return TaskStatus.onlineReady;
    }
  }

  Map<String, dynamic> toJson() => {
    '_id': id,
    'taskId': taskId,
    'taskTitle': taskTitle,
    'description': description,
    'assignedTo': assignedTo,
    'customerId': customerId,
    'expectedCompletionDate': expectedCompletionDate.toIso8601String(),
    'completedDate': completedDate?.toIso8601String(),
    'travelActivityDuration': travelActivityDuration?.toJson(),
    'status': status.name, // Convert enum to string for JSON
    'isOtpRequired': isOtpRequired,
    'isGeoFenceRequired': isGeoFenceRequired,
    'isPhotoRequired': isPhotoRequired,
    'isFormRequired': isFormRequired,
  };

  Task copyWith({
    String? id,
    String? taskId,
    String? taskTitle,
    String? description,
    String? assignedTo,
    String? customerId,
    Customer? customer,
    DateTime? expectedCompletionDate,
    DateTime? completedDate,
    DateTime? assignedDate,
    TaskStatus? status,
    bool? isOtpRequired,
    bool? isGeoFenceRequired,
    bool? isPhotoRequired,
    bool? isFormRequired,
    bool? isOtpVerified,
    DateTime? otpVerifiedAt,
    bool? photoProof,
    bool? formFilled,
    bool? checkinCustomerPlace,
    bool? checkoutCustomerPlace,
    String? photoProofUrl,
    DateTime? photoProofUploadedAt,
    bool? requireApprovalOnComplete,
    bool? autoApprove,
    TaskLocation? sourceLocation,
    TaskLocation? destinationLocation,
    TaskLocation? arrivalLocation,
    List<TaskExitRecord>? tasksExit,
    List<TaskRestartRecord>? tasksRestarted,
    List<TaskDestinationRecord>? destinations,
    double? tripDistanceKm,
    int? tripDurationSeconds,
    DateTime? arrivalTime,
    TravelActivityDuration? travelActivityDuration,
    DateTime? startTime,
    String? photoProofAddress,
    String? otpVerifiedAddress,
  }) {
    return Task(
      id: id ?? this.id,
      taskId: taskId ?? this.taskId,
      taskTitle: taskTitle ?? this.taskTitle,
      description: description ?? this.description,
      assignedTo: assignedTo ?? this.assignedTo,
      customerId: customerId ?? this.customerId,
      customer: customer ?? this.customer,
      expectedCompletionDate:
          expectedCompletionDate ?? this.expectedCompletionDate,
      completedDate: completedDate ?? this.completedDate,
      assignedDate: assignedDate ?? this.assignedDate,
      status: status ?? this.status,
      isOtpRequired: isOtpRequired ?? this.isOtpRequired,
      isGeoFenceRequired: isGeoFenceRequired ?? this.isGeoFenceRequired,
      isPhotoRequired: isPhotoRequired ?? this.isPhotoRequired,
      isFormRequired: isFormRequired ?? this.isFormRequired,
      isOtpVerified: isOtpVerified ?? this.isOtpVerified,
      otpVerifiedAt: otpVerifiedAt ?? this.otpVerifiedAt,
      photoProof: photoProof ?? this.photoProof,
      formFilled: formFilled ?? this.formFilled,
      checkinCustomerPlace: checkinCustomerPlace ?? this.checkinCustomerPlace,
      checkoutCustomerPlace: checkoutCustomerPlace ?? this.checkoutCustomerPlace,
      photoProofUrl: photoProofUrl ?? this.photoProofUrl,
      photoProofUploadedAt: photoProofUploadedAt ?? this.photoProofUploadedAt,
      requireApprovalOnComplete:
          requireApprovalOnComplete ?? this.requireApprovalOnComplete,
      autoApprove: autoApprove ?? this.autoApprove,
      sourceLocation: sourceLocation ?? this.sourceLocation,
      destinationLocation: destinationLocation ?? this.destinationLocation,
      arrivalLocation: arrivalLocation ?? this.arrivalLocation,
      tasksExit: tasksExit ?? this.tasksExit,
      tasksRestarted: tasksRestarted ?? this.tasksRestarted,
      destinations: destinations ?? this.destinations,
      tripDistanceKm: tripDistanceKm ?? this.tripDistanceKm,
      tripDurationSeconds: tripDurationSeconds ?? this.tripDurationSeconds,
      arrivalTime: arrivalTime ?? this.arrivalTime,
      travelActivityDuration:
          travelActivityDuration ?? this.travelActivityDuration,
      startTime: startTime ?? this.startTime,
      photoProofAddress: photoProofAddress ?? this.photoProofAddress,
      otpVerifiedAddress: otpVerifiedAddress ?? this.otpVerifiedAddress,
    );
  }
}

/// Timeline event from completion report (DB: tasks + trackings).
class TimelineEvent {
  final String type;
  final String label;
  final DateTime? time;
  final String? address;
  final double? lat;
  final double? lng;
  final String? exitReason;
  final String? movementType;
  final int? batteryPercent;

  const TimelineEvent({
    required this.type,
    required this.label,
    this.time,
    this.address,
    this.lat,
    this.lng,
    this.exitReason,
    this.movementType,
    this.batteryPercent,
  });

  factory TimelineEvent.fromJson(Map<String, dynamic> json) {
    final timeVal = json['time'];
    DateTime? time;
    if (timeVal != null) {
      if (timeVal is String) {
        time = DateTime.tryParse(timeVal);
      } else if (timeVal is num)
        time = DateTime.fromMillisecondsSinceEpoch(
          timeVal.toInt(),
          isUtc: true,
        );
      else if (timeVal is Map && timeVal[r'$date'] != null) {
        time = DateTime.tryParse(timeVal[r'$date'].toString());
      }
    }
    return TimelineEvent(
      type: (json['type'] as String?) ?? '',
      label: (json['label'] as String?) ?? '',
      time: time,
      address: json['address'] as String?,
      lat: (json['lat'] as num?)?.toDouble(),
      lng: (json['lng'] as num?)?.toDouble(),
      exitReason: json['exitReason'] as String?,
      movementType: json['movementType'] as String?,
      batteryPercent: (json['batteryPercent'] as num?)?.toInt(),
    );
  }
}

/// Route point for polyline.
class RoutePoint {
  final double lat;
  final double lng;
  final DateTime? timestamp;
  final String? movementType;
  final String? address;

  const RoutePoint({
    required this.lat,
    required this.lng,
    this.timestamp,
    this.movementType,
    this.address,
  });

  factory RoutePoint.fromJson(Map<String, dynamic> json) {
    final ts = json['timestamp'];
    DateTime? time;
    if (ts != null) {
      if (ts is String) {
        time = DateTime.tryParse(ts);
      } else if (ts is num)
        time = DateTime.fromMillisecondsSinceEpoch(ts.toInt(), isUtc: true);
      else if (ts is Map && ts[r'$date'] != null) {
        time = DateTime.tryParse(ts[r'$date'].toString());
      }
    }
    return RoutePoint(
      lat: (json['lat'] as num?)?.toDouble() ?? 0,
      lng: (json['lng'] as num?)?.toDouble() ?? 0,
      timestamp: time,
      movementType: json['movementType'] as String?,
      address: json['address'] as String?,
    );
  }
}

/// Filled form response from completion report.
class FormResponseData {
  final String? id;
  final String? templateName;
  final Map<String, dynamic> responses;

  const FormResponseData({this.id, this.templateName, required this.responses});

  factory FormResponseData.fromJson(Map<String, dynamic> json) {
    final templateId = json['templateId'];
    String? templateName;
    if (templateId is Map) {
      templateName =
          (templateId['templateName'] as String?) ??
          (templateId['template_name'] as String?);
    }
    final resp = json['responses'] as Map<String, dynamic>? ?? {};
    return FormResponseData(
      id: _stringFromId(json['_id']),
      templateName: templateName ?? json['templateName'] as String?,
      responses: Map<String, dynamic>.from(resp),
    );
  }

  static String? _stringFromId(dynamic value) {
    if (value == null) return null;
    if (value is String) return value;
    if (value is Map<dynamic, dynamic>) {
      final oid = value[r'$oid'];
      if (oid != null) return oid is String ? oid : oid.toString();
    }
    return value.toString();
  }
}

/// Full task completion report from API.
class TaskCompletionReport {
  final Task task;
  final List<TimelineEvent> timeline;
  final List<RoutePoint> routePoints;
  final List<FormResponseData> formResponses;

  const TaskCompletionReport({
    required this.task,
    required this.timeline,
    required this.routePoints,
    this.formResponses = const [],
  });

  factory TaskCompletionReport.fromJson(Map<String, dynamic> json) {
    final taskJson = json['task'] as Map<String, dynamic>?;
    final task = taskJson != null
        ? Task.fromJson(taskJson)
        : throw Exception('Task required');
    final timelineList = json['timeline'] as List<dynamic>? ?? [];
    final timeline = timelineList
        .map((e) => TimelineEvent.fromJson(e as Map<String, dynamic>))
        .toList();
    final routeList = json['routePoints'] as List<dynamic>? ?? [];
    final routePoints = routeList
        .map((e) => RoutePoint.fromJson(e as Map<String, dynamic>))
        .toList();
    final formList = json['formResponses'] as List<dynamic>? ?? [];
    final formResponses = formList
        .map((e) => FormResponseData.fromJson(e as Map<String, dynamic>))
        .toList();
    return TaskCompletionReport(
      task: task,
      timeline: timeline,
      routePoints: routePoints,
      formResponses: formResponses,
    );
  }
}
