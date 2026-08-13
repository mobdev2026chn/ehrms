// repository/task_repository.dart
// Single data source abstraction for tasks. Delegates to TaskService + CustomerService (data layer).
// No HTTP or JSON here; same API contract as before.

import '../models/task.dart';
import '../models/customer.dart';
import '../services/task_service.dart';
import '../services/customer_service.dart';

class TaskRepository {
  TaskRepository({
    TaskService? taskService,
    CustomerService? customerService,
  })  : _taskService = taskService ?? TaskService(),
        _customerService = customerService ?? CustomerService();

  final TaskService _taskService;
  final CustomerService _customerService;

  Future<List<Task>> getAllTasks() async => _taskService.getAllTasks();

  Future<List<Task>> getAssignedTasks(String staffId) async =>
      _taskService.getAssignedTasks(staffId);

  Future<Task> getTaskById(String id) async => _taskService.getTaskById(id);

  Future<Customer> getCustomerById(String id) async => _customerService.getCustomerById(id);

  /// Update task (status, startTime, startLocation).
  Future<Task> updateTask(
    String id, {
    String? status,
    DateTime? startTime,
    double? startLat,
    double? startLng,
  }) async {
    return _taskService.updateTask(
      id,
      status: status,
      startTime: startTime,
      startLat: startLat,
      startLng: startLng,
    );
  }

  /// Send live location update for a task.
  Future<void> updateLocation(String taskMongoId, double lat, double lng) async {
    return _taskService.updateLocation(taskMongoId, lat, lng);
  }

  /// Update task progress steps (reachedLocation, photoProof, formFilled, otpVerified).
  Future<Task> updateSteps(
    String taskMongoId, {
    bool? reachedLocation,
    bool? photoProof,
    bool? formFilled,
    bool? otpVerified,
  }) async {
    return _taskService.updateSteps(
      taskMongoId,
      reachedLocation: reachedLocation,
      photoProof: photoProof,
      formFilled: formFilled,
      otpVerified: otpVerified,
    );
  }

  /// Mark task as completed.
  Future<Task> endTask(String taskMongoId) async => _taskService.endTask(taskMongoId);
}
