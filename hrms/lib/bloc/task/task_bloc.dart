// bloc/task/task_bloc.dart
// Business logic for tasks. Calls TaskRepository only; no HTTP/JSON.

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../models/task.dart';
import '../../repository/task_repository.dart';
import '../../utils/error_message_utils.dart';

part 'task_event.dart';
part 'task_state.dart';

class TaskBloc extends Bloc<TaskEvent, TaskState> {
  TaskBloc({TaskRepository? repository})
      : _repo = repository ?? TaskRepository(),
        super(TaskInitial()) {
    on<TaskLoadAssignedRequested>(_onLoadAssigned);
    on<TaskLoadAllRequested>(_onLoadAll);
    on<TaskLoadByIdRequested>(_onLoadById);
    on<TaskLoadWithCustomersRequested>(_onLoadWithCustomers);
    on<TaskUpdateRequested>(_onUpdate);
    on<TaskUpdateStepsRequested>(_onUpdateSteps);
    on<TaskEndRequested>(_onEnd);
  }

  final TaskRepository _repo;

  Future<void> _onLoadAssigned(TaskLoadAssignedRequested event, Emitter<TaskState> emit) async {
    emit(TaskLoadInProgress());
    try {
      final tasks = await _repo.getAssignedTasks(event.staffId);
      emit(TasksLoaded(tasks));
    } catch (e) {
      emit(TaskFailure(message: ErrorMessageUtils.toUserFriendlyMessage(e)));
    }
  }

  Future<void> _onLoadAll(TaskLoadAllRequested event, Emitter<TaskState> emit) async {
    emit(TaskLoadInProgress());
    try {
      final tasks = await _repo.getAllTasks();
      emit(TasksLoaded(tasks));
    } catch (e) {
      emit(TaskFailure(message: ErrorMessageUtils.toUserFriendlyMessage(e)));
    }
  }

  Future<void> _onLoadById(TaskLoadByIdRequested event, Emitter<TaskState> emit) async {
    emit(TaskLoadInProgress());
    try {
      final task = await _repo.getTaskById(event.id);
      emit(TaskDetailLoaded(task));
    } catch (e) {
      emit(TaskFailure(message: ErrorMessageUtils.toUserFriendlyMessage(e)));
    }
  }

  Future<void> _onLoadWithCustomers(TaskLoadWithCustomersRequested event, Emitter<TaskState> emit) async {
    emit(TaskLoadInProgress());
    try {
      List<Task> tasks = event.staffId != null && event.staffId!.isNotEmpty
          ? await _repo.getAssignedTasks(event.staffId!)
          : await _repo.getAllTasks();
      List<Task> withCustomers = [];
      for (var task in tasks) {
        if (task.customerId != null) {
          try {
            final customer = await _repo.getCustomerById(task.customerId!);
            withCustomers.add(task.copyWith(customer: customer));
          } catch (_) {
            // If customer is not visible to this staff, still load the task.
            // UI will show task without customer details.
            withCustomers.add(task);
          }
        } else {
          withCustomers.add(task);
        }
      }
      emit(TasksLoaded(withCustomers));
    } catch (e) {
      emit(TaskFailure(message: ErrorMessageUtils.toUserFriendlyMessage(e)));
    }
  }

  Future<void> _onUpdate(TaskUpdateRequested event, Emitter<TaskState> emit) async {
    try {
      final task = await _repo.updateTask(
        event.id,
        status: event.status,
        startTime: event.startTime,
        startLat: event.startLat,
        startLng: event.startLng,
      );
      emit(TaskUpdateSuccess(task));
    } catch (e) {
      emit(TaskFailure(message: ErrorMessageUtils.toUserFriendlyMessage(e)));
    }
  }

  Future<void> _onUpdateSteps(TaskUpdateStepsRequested event, Emitter<TaskState> emit) async {
    try {
      final task = await _repo.updateSteps(
        event.taskMongoId,
        reachedLocation: event.reachedLocation,
        photoProof: event.photoProof,
        formFilled: event.formFilled,
        otpVerified: event.otpVerified,
      );
      emit(TaskUpdateSuccess(task));
    } catch (e) {
      emit(TaskFailure(message: ErrorMessageUtils.toUserFriendlyMessage(e)));
    }
  }

  Future<void> _onEnd(TaskEndRequested event, Emitter<TaskState> emit) async {
    try {
      await _repo.endTask(event.taskMongoId);
      emit(TaskEndSuccess());
    } catch (e) {
      emit(TaskFailure(message: ErrorMessageUtils.toUserFriendlyMessage(e)));
    }
  }
}
