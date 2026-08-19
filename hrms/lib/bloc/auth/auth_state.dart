part of 'auth_bloc.dart';

abstract class AuthState extends Equatable {
  const AuthState();
  @override
  List<Object?> get props => [];
}

class AuthInitial extends AuthState {}

class AuthLoadInProgress extends AuthState {}

class AuthLoginSuccess extends AuthState {
  final dynamic data;
  const AuthLoginSuccess({this.data});
  @override
  List<Object?> get props => [data];
}

/// Emitted when the backend returns requiresOTP: true (2FA enabled).
/// The login screen should show an OTP input and re-submit with the OTP.
class AuthRequires2FA extends AuthState {
  final String email;
  final String password;
  final String message;
  const AuthRequires2FA({required this.email, required this.password, required this.message});
  @override
  List<Object?> get props => [email, password, message];
}

class AuthProfileLoaded extends AuthState {
  final dynamic data;
  const AuthProfileLoaded({this.data});
  @override
  List<Object?> get props => [data];
}

class AuthFailure extends AuthState {
  final String message;
  const AuthFailure({required this.message});
  @override
  List<Object?> get props => [message];
}
