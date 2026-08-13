part of 'auth_bloc.dart';

abstract class AuthEvent extends Equatable {
  const AuthEvent();
  @override
  List<Object?> get props => [];
}

class AuthLoginRequested extends AuthEvent {
  final String email;
  final String password;
  const AuthLoginRequested(this.email, this.password);
  @override
  List<Object?> get props => [email, password];
}

class AuthGoogleLoginRequested extends AuthEvent {
  final String email;
  const AuthGoogleLoginRequested(this.email);
  @override
  List<Object?> get props => [email];
}

class AuthLogoutRequested extends AuthEvent {
  const AuthLogoutRequested();
}

class AuthProfileRequested extends AuthEvent {
  const AuthProfileRequested();
}

/// Fired when the user submits their OTP after a 2FA challenge.
class Auth2FALoginRequested extends AuthEvent {
  final String email;
  final String password;
  final String otp;
  const Auth2FALoginRequested({required this.email, required this.password, required this.otp});
  @override
  List<Object?> get props => [email, password, otp];
}
