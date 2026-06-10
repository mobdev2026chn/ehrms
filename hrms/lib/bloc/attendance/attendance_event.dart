part of 'attendance_bloc.dart';

/// Events for attendance flow. UI dispatches these; BLoC calls Repository only.
abstract class AttendanceEvent extends Equatable {
  const AttendanceEvent();
  @override
  List<Object?> get props => [];
}

/// Load attendance status for a given date (for selfie check-in screen).
class AttendanceStatusRequested extends AttendanceEvent {
  final String date;
  const AttendanceStatusRequested(this.date);
  @override
  List<Object?> get props => [date];
}

/// Check-in with location and optional selfie.
class AttendanceCheckInRequested extends AttendanceEvent {
  final double lat;
  final double lng;
  final String address;
  final String? area;
  final String? city;
  final String? pincode;
  final String? selfie;
  final String? movementType;
  final int? lateMinutes;
  final int? earlyMinutes;
  final double? fineAmount;

  /// UTC instant captured the moment the punch button was tapped, so location/selfie/
  /// network latency does not push the saved punch-in time forward. ISO-8601 string.
  final String? clientTime;
  const AttendanceCheckInRequested({
    required this.lat,
    required this.lng,
    required this.address,
    this.area,
    this.city,
    this.pincode,
    this.selfie,
    this.movementType,
    this.lateMinutes,
    this.earlyMinutes,
    this.fineAmount,
    this.clientTime,
  });
  @override
  List<Object?> get props => [
    lat,
    lng,
    address,
    area,
    city,
    pincode,
    selfie,
    movementType,
    lateMinutes,
    earlyMinutes,
    fineAmount,
    clientTime,
  ];
}

/// Check-out with location and optional selfie.
class AttendanceCheckOutRequested extends AttendanceEvent {
  final double lat;
  final double lng;
  final String address;
  final String? area;
  final String? city;
  final String? pincode;
  final String? selfie;
  final String? movementType;
  final int? lateMinutes;
  final int? earlyMinutes;
  final double? fineAmount;

  /// UTC instant captured the moment the punch button was tapped, so location/selfie/
  /// network latency does not push the saved punch-out time forward. ISO-8601 string.
  final String? clientTime;
  const AttendanceCheckOutRequested({
    required this.lat,
    required this.lng,
    required this.address,
    this.area,
    this.city,
    this.pincode,
    this.selfie,
    this.movementType,
    this.lateMinutes,
    this.earlyMinutes,
    this.fineAmount,
    this.clientTime,
  });
  @override
  List<Object?> get props => [
    lat,
    lng,
    address,
    area,
    city,
    pincode,
    selfie,
    movementType,
    lateMinutes,
    earlyMinutes,
    fineAmount,
    clientTime,
  ];
}
