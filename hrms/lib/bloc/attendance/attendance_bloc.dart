// bloc/attendance/attendance_bloc.dart
// Business logic and state for attendance. Calls AttendanceRepository only; no HTTP/JSON.

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../repository/attendance_repository.dart';

part 'attendance_event.dart';
part 'attendance_state.dart';

class AttendanceBloc extends Bloc<AttendanceEvent, AttendanceState> {
  AttendanceBloc({AttendanceRepository? repository})
    : _repo = repository ?? AttendanceRepository(),
      super(AttendanceInitial()) {
    on<AttendanceStatusRequested>(_onStatusRequested);
    on<AttendanceCheckInRequested>(_onCheckInRequested);
    on<AttendanceCheckOutRequested>(_onCheckOutRequested);
  }

  final AttendanceRepository _repo;

  Future<void> _onStatusRequested(
    AttendanceStatusRequested event,
    Emitter<AttendanceState> emit,
  ) async {
    emit(AttendanceLoadInProgress());
    final result = await _repo.getAttendanceByDate(event.date);
    if (result['success'] != true || !result.containsKey('data')) {
      emit(
        AttendanceFailure(
          message: result['message'] as String? ?? 'Failed to load attendance',
        ),
      );
      return;
    }
    final responseBody = result['data'];
    var data = responseBody;
    if (responseBody != null &&
        (responseBody.containsKey('data') ||
            responseBody.containsKey('branch'))) {
      data = responseBody['data'];
    }
    final now = DateTime.now();
    final todayStr = now.toIso8601String().split('T')[0];
    final isToday = event.date == todayStr;
    bool isCheckedIn = false;
    bool isCompleted = false;
    if (data != null && isToday) {
      if (responseBody is Map && responseBody.containsKey('checkedIn')) {
        isCheckedIn = responseBody['checkedIn'] == true;
        isCompleted = responseBody['hasPunchIn'] == true && responseBody['hasPunchOut'] == true;
      } else {
        isCheckedIn = data['punchIn'] != null && data['punchOut'] == null;
        isCompleted = data['punchIn'] != null && data['punchOut'] != null;
      }
    } else if (!isToday) {
      isCompleted = true;
    }
    final branch = responseBody is Map ? responseBody['branch'] : null;
    final halfDay = responseBody is Map ? responseBody['halfDayLeave'] : null;
    final halfDayMessage = halfDay is Map
        ? halfDay['message'] as String?
        : null;
    final halfDayType = halfDay is Map
        ? (halfDay['halfDayType'] ?? halfDay['halfDaySession']) as String?
        : null;
    emit(
      AttendanceStatusLoaded(
        branchData: branch is Map<String, dynamic> ? branch : null,
        checkInAllowed: responseBody['checkInAllowed'] ?? true,
        checkOutAllowed: responseBody['checkOutAllowed'] ?? true,
        halfDayLeaveMessage: halfDayMessage,
        halfDayType: halfDayType,
        isCheckedIn: isCheckedIn,
        isCompleted: isCompleted,
        isToday: isToday,
      ),
    );
  }

  Future<void> _onCheckInRequested(
    AttendanceCheckInRequested event,
    Emitter<AttendanceState> emit,
  ) async {
    emit(AttendanceLoadInProgress());
    final result = await _repo.checkIn(
      event.lat,
      event.lng,
      event.address,
      area: event.area,
      city: event.city,
      pincode: event.pincode,
      selfie: event.selfie,
      movementType: event.movementType,
    );
    if (result['success'] == true) {
      emit(AttendanceCheckInSuccess());
    } else {
      emit(
        AttendanceFailure(
          message: result['message'] as String? ?? 'Check-in failed',
        ),
      );
    }
  }

  Future<void> _onCheckOutRequested(
    AttendanceCheckOutRequested event,
    Emitter<AttendanceState> emit,
  ) async {
    emit(AttendanceLoadInProgress());
    final result = await _repo.checkOut(
      event.lat,
      event.lng,
      event.address,
      area: event.area,
      city: event.city,
      pincode: event.pincode,
      selfie: event.selfie,
      movementType: event.movementType,
    );
    if (result['success'] == true) {
      emit(AttendanceCheckOutSuccess());
    } else {
      emit(
        AttendanceFailure(
          message: result['message'] as String? ?? 'Check-out failed',
        ),
      );
    }
  }
}
