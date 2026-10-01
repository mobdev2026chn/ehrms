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
      lat: (json['lat'] ?? json['latitude'] as num?)?.toDouble() ?? 0,
      lng: (json['lng'] ?? json['longitude'] as num?)?.toDouble() ?? 0,
      address: (json['address'] ?? json['name'] ?? json['branchName']) as String?,
      fullAddress: (json['fullAddress'] ?? json['address']) as String?,
      pincode: (json['pincode'] ?? json['pinCode']) as String?,
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
  final String? exitType;
  final DateTime? exitedAt;
  final int? batteryPercent;

  const TaskExitRecord({
    required this.lat,
    required this.lng,
    this.address,
    this.fullAddress,
    this.pincode,
    required this.exitReason,
    this.exitType,
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
      exitType: json['exitType'] as String?,
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
  requested,
  expired,
}

/// One active field of the admin's Field-Out form template (HRMSbackend
/// `FormTemplate.fields`, delivered on each task as `requirements`).
class TaskRequirement {
  final String name;
  /// e.g. 'Text Input', 'Text Area', 'Image File', 'Camera Capture', 'Numeric Input',
  /// 'Dropdown Select', 'GPS Tracker', 'email'.
  final String type;
  /// Extra hint from the template (e.g. 'Paragraph Text', or dropdown options).
  final String response;

  const TaskRequirement({required this.name, this.type = '', this.response = ''});

  factory TaskRequirement.fromJson(Map<String, dynamic> json) => TaskRequirement(
        name: (json['name'] ?? '').toString(),
        type: (json['type'] ?? '').toString(),
        response: (json['response'] ?? '').toString(),
      );

  String get _n => name.trim().toLowerCase();
  String get _t => type.trim().toLowerCase();

  bool get isEmail => _n == 'email' || _t == 'email';
  bool get isOtp => _n == 'otp' || (_t == 'numeric input' && _n.contains('otp'));
  bool get isImage => _n == 'proof photo' || _t == 'image file' || _t == 'camera capture';
  bool get isTextArea =>
      _n == 'description' || _t == 'text area' || response.trim().toLowerCase() == 'paragraph text';
  bool get isDropdown => _t == 'dropdown select';
  bool get isGps => _t == 'gps tracker';
  bool get isNumeric => _t == 'numeric input' && !isOtp;

  Map<String, dynamic> toJson() => {'name': name, 'type': type, 'response': response};

  /// What the web falls back to when a task carries no template.
  static const List<TaskRequirement> webDefaults = [
    TaskRequirement(name: 'Description', type: 'Text Area'),
    TaskRequirement(name: 'Proof Photo', type: 'Image File'),
    TaskRequirement(name: 'OTP', type: 'Numeric Input'),
  ];

  static List<TaskRequirement> listFrom(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => TaskRequirement.fromJson(Map<String, dynamic>.from(e)))
        .where((r) => r.name.trim().isNotEmpty)
        .toList();
  }
}

class Task {
  final String? id;
  final String taskId;
  final String taskTitle;
  final String description;
  final String assignedTo;
  final String? type;
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
  final String? fieldOutNotes;

  /// Complete route breadcrumbs of the employee's travel.
  final List<Map<String, double>>? travelledRoute;

  /// Admin Field-Out form fields (HRMSbackend `requirements`). Empty when not provided.
  final List<TaskRequirement> requirements;

  /// True for a self-logged Field In / Field Out journey (not an assigned task).
  final bool selfLogged;

  /// Field In at the destination already done (HRMSbackend `actualFieldInTime`).
  final String? actualFieldInTime;

  Task({
    this.id,
    required this.taskId,
    required this.taskTitle,
    required this.description,
    required this.assignedTo,
    this.type,
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
    this.fieldOutNotes,
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
    this.travelledRoute,
    this.requirements = const [],
    this.selfLogged = false,
    this.actualFieldInTime,
  });

  factory Task.fromJson(Map<String, dynamic> json) {
    final customerIdVal = json['customerId'];
    final custName = (json['customerName'] ?? json['customer_name'] ?? json['companyName'])?.toString();
    final custAddr = (json['customerAddress'] ?? json['customerLocation'] ?? json['address'] ?? json['location'])?.toString();
    final custPhone = (json['customerPhone'] ?? json['customerNumber'] ?? json['mobile'])?.toString();

    Customer? customer;
    if (customerIdVal is Map) {
      customer = Customer.fromJson(Map<String, dynamic>.from(customerIdVal));
    } else if (json['customer'] is Map) {
      customer = Customer.fromJson(Map<String, dynamic>.from(json['customer'] as Map));
    } else if (custName != null && custName.isNotEmpty) {
      customer = Customer(
        id: _stringFromId(customerIdVal),
        customerName: custName,
        customerNumber: custPhone,
        address: custAddr ?? '',
        city: (json['city'] ?? '').toString(),
        pincode: (json['pincode'] ?? json['pinCode'] ?? '').toString(),
      );
    }

    final titleStr = (json['taskTitle'] ?? json['title'] ?? '').toString();
    final taskIdStr = (json['taskId'] ?? json['id'] ?? json['_id'] ?? '').toString();
    final statusStr = (json['status'] ?? '').toString();
    final typeStr = (json['type'] ?? json['taskType'])?.toString();

    TaskLocation? destLoc;
    if (json['destinationLocation'] is Map) {
      destLoc = TaskLocation.fromJson(json['destinationLocation'] as Map<String, dynamic>);
    } else if (json['latitude'] != null || json['longitude'] != null || custAddr != null) {
      destLoc = TaskLocation(
        lat: (json['latitude'] as num?)?.toDouble() ?? 0,
        lng: (json['longitude'] as num?)?.toDouble() ?? 0,
        address: custAddr,
        fullAddress: custAddr,
      );
    }

    TaskLocation? srcLoc;
    if (json['sourceLocation'] is Map) {
      srcLoc = TaskLocation.fromJson(json['sourceLocation'] as Map<String, dynamic>);
    } else if (json['startLocation'] is Map) {
      srcLoc = TaskLocation.fromJson(json['startLocation'] as Map<String, dynamic>);
    } else if (json['startLatitude'] != null || json['startLongitude'] != null || json['sourceLocation'] != null || json['startBranchAddress'] != null || json['branchName'] != null) {
      final srcAddr = (json['sourceLocation'] ?? json['startBranchAddress'] ?? json['branchName'])?.toString();
      srcLoc = TaskLocation(
        lat: (json['startLatitude'] as num?)?.toDouble() ?? 0,
        lng: (json['startLongitude'] as num?)?.toDouble() ?? 0,
        address: srcAddr,
        fullAddress: srcAddr,
      );
    }

    final proofImgStr = (json['photoProofUrl'] ?? json['proofImg'] ?? json['fieldOutImage'])?.toString();
    // Verified if ANY source says so (the completion report sends `isOtpVerified`,
    // which also covers Email fields verified by OTP); a stale `false` elsewhere
    // must not hide it.
    final isOtpDone = json['customFields']?['otpVerified'] == true ||
        json['progressSteps']?['otpVerified'] == true ||
        json['isOtpVerified'] == true ||
        json['otpVerified'] == true ||
        (json['fieldOutOtp'] != null && json['fieldOutOtp'].toString().trim().isNotEmpty);
    final isPhotoDone = (json['progressSteps'] != null ? (json['progressSteps']['photoProof'] as bool?) : null) ??
        (proofImgStr != null && proofImgStr.isNotEmpty);

    // Start = when the task was started (HRMSbackend `fieldInTime` = task.timeIn);
    // `actualFieldInTime` is the Field In / Arrived moment and only a last resort
    // here — reading it first made Start show the Arrived time.
    final startTimeVal = _parseTimeOrDateTime(
      json['startTime'] ?? json['fieldInTime'] ?? json['timeIn'] ?? json['actualFieldInTime'] ?? json['startDate'],
    );
    final arrivalTimeVal = _parseTimeOrDateTime(
      json['arrivalTime'] ?? json['actualFieldInTime'] ?? json['timeIn'] ?? json['fieldInTime'],
    );
    final completedDateVal = _parseTimeOrDateTime(
      json['completedDate'] ?? json['timeOut'] ?? json['fieldOutTime'] ?? json['endDate'],
    );
    final requirementsVal = TaskRequirement.listFrom(json['requirements']);

    return Task(
      id: _stringFromId(json['_id'] ?? json['id']),
      taskId: taskIdStr,
      taskTitle: titleStr,
      description: (json['description'] ?? '').toString(),
      assignedTo: _stringFromId(json['assignedTo'] ?? json['staffId'] ?? json['staff']?['_id'] ?? json['staff']?['id']) ?? '',
      type: typeStr,
      customerId: _stringFromId(customerIdVal),
      customer: customer,
      expectedCompletionDate:
          // HRMSbackend sends `date` as the START date; the due date is `endDate`.
          _dateFromJson(json['expectedCompletionDate'] ?? json['endDate'] ?? json['date']) ?? DateTime.now(),
      completedDate: completedDateVal,
      assignedDate:
          _dateFromJson(json['assignedDate'] ?? json['startDate'] ?? json['createdAt']),
      status: statusFromJson(statusStr),
      // HRMSbackend hardcodes otpRequired (false on the list, true by id); the admin's
      // template (requirements) is the real answer whenever it is present.
      isOtpRequired: requirementsVal.isNotEmpty
          ? requirementsVal.any((r) => r.isOtp || r.isEmail)
          : (json['customFields'] != null
                  ? (json['customFields']['otpRequired'] as bool?)
                  : null) ??
              (json['isOtpRequired'] as bool?) ??
              (json['otpRequired'] as bool?) ??
              false,
      isGeoFenceRequired: json['customFields'] != null
          ? (json['customFields']['geoFenceRequired'] as bool?) ?? false
          : false,
      isPhotoRequired: json['customFields'] != null
          ? (json['customFields']['photoRequired'] as bool?) ?? false
          : (json['selfieRequired'] as bool?) ?? false,
      isFormRequired: json['customFields'] != null
          ? (json['customFields']['formRequired'] as bool?) ?? false
          : false,
      isOtpVerified: isOtpDone,
      otpVerifiedAt: _dateFromJson(
        json['customFields']?['otpVerifiedAt'] ?? json['otpVerifiedAt'],
      ),
      photoProof: isPhotoDone,
      formFilled: json['progressSteps'] != null
          ? (json['progressSteps']['formFilled'] as bool?)
          : null,
      checkinCustomerPlace: json['progressSteps'] != null
          ? (json['progressSteps']['checkinCustomerPlace'] as bool?)
          : null,
      checkoutCustomerPlace: json['progressSteps'] != null
          ? (json['progressSteps']['checkoutCustomerPlace'] as bool?)
          : null,
      photoProofUrl: proofImgStr,
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
      sourceLocation: srcLoc,
      destinationLocation: destLoc,
      arrivalLocation: _parseArrivalLocation(json),
      tasksExit: _parseList(
        json['exit'] ?? json['tasks_exit'],
        TaskExitRecord.fromJson,
      ),
      taskExitStatus: (json['task_exit'] is Map
              ? (json['task_exit'] as Map<String, dynamic>)['status'] as String?
              : null) ??
          json['taskExitStatus']?.toString(),
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
      arrivalTime: arrivalTimeVal,
      travelActivityDuration: json['travelActivityDuration'] != null
          ? TravelActivityDuration.fromJson(
              json['travelActivityDuration'] as Map<String, dynamic>,
            )
          : null,
      startTime: startTimeVal,
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
      fieldOutNotes: json['fieldOutNotes'] as String?,
      travelledRoute: _parseRoute(json['travelledRoute']),
      requirements: requirementsVal,
      selfLogged: json['selfLogged'] == true,
      actualFieldInTime: (json['actualFieldInTime']?.toString().trim().isNotEmpty ?? false)
          ? json['actualFieldInTime'].toString()
          : null,
    );
  }

  static List<Map<String, double>>? _parseRoute(dynamic raw) {
    if (raw is! List || raw.isEmpty) return null;
    final list = <Map<String, double>>[];
    for (final e in raw) {
      if (e is Map) {
        final lat = (e['lat'] ?? e['latitude'] as num?)?.toDouble();
        final lng = (e['lng'] ?? e['longitude'] as num?)?.toDouble();
        if (lat != null && lng != null) {
          list.add({'lat': lat, 'lng': lng});
        }
      }
    }
    return list.isNotEmpty ? list : null;
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

  static DateTime? _parseTimeOrDateTime(dynamic value, [DateTime? baseDate]) {
    if (value == null) return null;
    final parsed = _dateFromJson(value);
    if (parsed != null) return parsed;
    if (value is String) {
      final trimmed = value.trim();
      final match = RegExp(
        r'^(\d{1,2}):(\d{2})(?::(\d{2}))?\s*(am|pm)?$',
        caseSensitive: false,
      ).firstMatch(trimmed);
      if (match != null) {
        int hour = int.parse(match.group(1)!);
        final minute = int.parse(match.group(2)!);
        final second = match.group(3) != null ? int.parse(match.group(3)!) : 0;
        final ampm = match.group(4)?.toLowerCase();
        if (ampm == 'pm' && hour < 12) hour += 12;
        if (ampm == 'am' && hour == 12) hour = 0;
        final base = baseDate ?? DateTime.now();
        return DateTime(base.year, base.month, base.day, hour, minute, second);
      }
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
      case 'started':
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
      case 'requested':
      case 'requestedtasks':
        return TaskStatus.requested;
      case 'expired':
      case 'expiredtasks':
        return TaskStatus.expired;
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
    if (type != null) 'type': type,
    'requirements': requirements.map((r) => r.toJson()).toList(),
    'selfLogged': selfLogged,
    if (actualFieldInTime != null) 'actualFieldInTime': actualFieldInTime,
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
    String? fieldOutNotes,
    List<TaskRequirement>? requirements,
  }) {
    return Task(
      type: type,
      requirements: requirements ?? this.requirements,
      selfLogged: selfLogged,
      actualFieldInTime: actualFieldInTime,
      taskExitStatus: taskExitStatus,
      travelledRoute: travelledRoute,
      id: id ?? this.id,
      taskId: taskId ?? this.taskId,
      taskTitle: taskTitle ?? this.taskTitle,
      description: description ?? this.description,
      assignedTo: assignedTo ?? this.assignedTo,
      customerId: customerId ?? this.customerId,
      customer: customer ?? this.customer,
      fieldOutNotes: fieldOutNotes ?? this.fieldOutNotes,
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

  /// GPS accuracy in metres when the point was recorded (null if unknown).
  final double? accuracy;

  const RoutePoint({
    required this.lat,
    required this.lng,
    this.timestamp,
    this.movementType,
    this.address,
    this.accuracy,
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
    // Completion report sends lat/lng; the live-tracking trail sends latitude/longitude.
    return RoutePoint(
      lat: ((json['lat'] ?? json['latitude']) as num?)?.toDouble() ?? 0,
      lng: ((json['lng'] ?? json['longitude']) as num?)?.toDouble() ?? 0,
      timestamp: time,
      movementType: json['movementType'] as String?,
      address: json['address'] as String?,
      accuracy: (json['accuracy'] as num?)?.toDouble(),
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
