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
  const AttendanceCheckInRequested({
    required this.lat,
    required this.lng,
    required this.address,
    this.area,
    this.city,
    this.pincode,
    this.selfie,
    this.movementType,
  });
  @override
  List<Object?> get props => [lat, lng, address, area, city, pincode, selfie, movementType];
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
  const AttendanceCheckOutRequested({
    required this.lat,
    required this.lng,
    required this.address,
    this.area,
    this.city,
    this.pincode,
    this.selfie,
    this.movementType,
  });
  @override
  List<Object?> get props => [lat, lng, address, area, city, pincode, selfie, movementType];
}
