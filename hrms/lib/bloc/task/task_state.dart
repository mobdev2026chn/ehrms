part of 'task_bloc.dart';

abstract class TaskState extends Equatable {
  const TaskState();
  @override
  List<Object?> get props => [];
}

class TaskInitial extends TaskState {}

class TaskLoadInProgress extends TaskState {}

class TasksLoaded extends TaskState {
  final List<Task> tasks;
  const TasksLoaded(this.tasks);
  @override
  List<Object?> get props => [tasks];
}

class TaskDetailLoaded extends TaskState {
  final Task task;
  const TaskDetailLoaded(this.task);
  @override
  List<Object?> get props => [task];
}

class TaskUpdateSuccess extends TaskState {
  final Task task;
  const TaskUpdateSuccess(this.task);
  @override
  List<Object?> get props => [task];
}

class TaskEndSuccess extends TaskState {}

class TaskFailure extends TaskState {
  final String message;
  const TaskFailure({required this.message});
  @override
  List<Object?> get props => [message];
}
