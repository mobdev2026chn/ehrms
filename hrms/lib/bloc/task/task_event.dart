part of 'task_bloc.dart';

abstract class TaskEvent extends Equatable {
  const TaskEvent();
  @override
  List<Object?> get props => [];
}

class TaskLoadAssignedRequested extends TaskEvent {
  final String staffId;
  const TaskLoadAssignedRequested(this.staffId);
  @override
  List<Object?> get props => [staffId];
}

class TaskLoadAllRequested extends TaskEvent {
  const TaskLoadAllRequested();
}

class TaskLoadByIdRequested extends TaskEvent {
  final String id;
  const TaskLoadByIdRequested(this.id);
  @override
  List<Object?> get props => [id];
}

/// Load tasks (by staffId or all) and attach Customer for each task that has customerId.
class TaskLoadWithCustomersRequested extends TaskEvent {
  final String? staffId;
  const TaskLoadWithCustomersRequested({this.staffId});
  @override
  List<Object?> get props => [staffId];
}

class TaskUpdateRequested extends TaskEvent {
  final String id;
  final String? status;
  final DateTime? startTime;
  final double? startLat;
  final double? startLng;
  const TaskUpdateRequested({
    required this.id,
    this.status,
    this.startTime,
    this.startLat,
    this.startLng,
  });
  @override
  List<Object?> get props => [id, status, startTime, startLat, startLng];
}

class TaskUpdateStepsRequested extends TaskEvent {
  final String taskMongoId;
  final bool? reachedLocation;
  final bool? photoProof;
  final bool? formFilled;
  final bool? otpVerified;
  const TaskUpdateStepsRequested({
    required this.taskMongoId,
    this.reachedLocation,
    this.photoProof,
    this.formFilled,
    this.otpVerified,
  });
  @override
  List<Object?> get props => [taskMongoId, reachedLocation, photoProof, formFilled, otpVerified];
}

class TaskEndRequested extends TaskEvent {
  final String taskMongoId;
  const TaskEndRequested(this.taskMongoId);
  @override
  List<Object?> get props => [taskMongoId];
}
