import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../services/auth_service.dart';
import '../../config/app_colors.dart';
import '../../bloc/auth/auth_bloc.dart';
import '../dashboard/dashboard_screen.dart';
import '../../utils/snackbar_utils.dart';
import '../../utils/error_message_utils.dart';
import 'forgot_password_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _emailFocusNode = FocusNode();
  final _passwordFocusNode = FocusNode();
  final _otpFocusNode = FocusNode();
  // Firebase Google Sign-In only; login/logout go through AuthBloc → AuthRepository.
  final _authService = AuthService();
  final _formKey = GlobalKey<FormState>();

  bool _isPasswordVisible = false;
  bool _lastAttemptWasGoogle = false;

  // 2FA state
  bool _show2FAInput = false;
  String _2faEmail = '';
  String _2faPassword = '';
  final _otpController = TextEditingController();

  // Entrance animations
  late AnimationController _entranceController;
  late Animation<double> _bgOpacity;
  late Animation<double> _bgScale;
  late Animation<double> _cardSlide;
  late Animation<double> _cardOpacity;

  // Success overlay
  bool _showSuccessOverlay = false;
  late AnimationController _successController;
  late Animation<double> _successCheckScale;
  late Animation<double> _successMessageOpacity;

  // Button press feedback
  late AnimationController _buttonScaleController;
  late Animation<double> _buttonScale;

  @override
  void initState() {
    super.initState();
    _emailFocusNode.addListener(_resetKeyboardStateOnFocus);
    _passwordFocusNode.addListener(_resetKeyboardStateOnFocus);
    _otpFocusNode.addListener(_resetKeyboardStateOnFocus);
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _bgOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0, 0.4, curve: Curves.easeOut),
      ),
    );
    _bgScale = Tween<double>(begin: 1.08, end: 1).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0, 0.5, curve: Curves.easeOut),
      ),
    );
    _cardSlide = Tween<double>(begin: 60, end: 0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.25, 0.85, curve: Curves.easeOutCubic),
      ),
    );
    _cardOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.3, 0.9, curve: Curves.easeOut),
      ),
    );
    _entranceController.forward();

    _successController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    // App icon: small → larger (scale up animation)
    _successCheckScale = Tween<double>(begin: 0.2, end: 1.15).animate(
      CurvedAnimation(
        parent: _successController,
        curve: const Interval(0.0, 0.55, curve: Curves.easeOutCubic),
      ),
    );
    _successMessageOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _successController,
        curve: const Interval(0.45, 0.75, curve: Curves.easeOut),
      ),
    );

    _buttonScaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _buttonScale = Tween<double>(begin: 1, end: 0.96).animate(
      CurvedAnimation(parent: _buttonScaleController, curve: Curves.easeInOut),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _clearHardwareKeyboardState();
    });
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _successController.dispose();
    _buttonScaleController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _otpController.dispose();
    _emailFocusNode
      ..removeListener(_resetKeyboardStateOnFocus)
      ..dispose();
    _passwordFocusNode
      ..removeListener(_resetKeyboardStateOnFocus)
      ..dispose();
    _otpFocusNode
      ..removeListener(_resetKeyboardStateOnFocus)
      ..dispose();
    super.dispose();
  }

  void _resetKeyboardStateOnFocus() {
    if (_emailFocusNode.hasFocus ||
        _passwordFocusNode.hasFocus ||
        _otpFocusNode.hasFocus) {
      _clearHardwareKeyboardState();
    }
  }

  void _clearHardwareKeyboardState() {
    try {
      // ignore: invalid_use_of_visible_for_testing_member
      ServicesBinding.instance.keyboard.clearState();
    } catch (_) {
      // Best-effort workaround for Flutter's Android key-state mismatch.
    }
  }

  void _handleLogin() {
    if (_formKey.currentState!.validate()) {
      context.read<AuthBloc>().add(
        AuthLoginRequested(
          _emailController.text.trim(),
          _passwordController.text,
        ),
      );
    }
  }

  void _handleVerifyOTP() {
    final otp = _otpController.text.trim();
    if (otp.length != 6) {
      SnackBarUtils.showSnackBar(
        context,
        'Please enter the 6-digit OTP',
        isError: true,
      );
      return;
    }
    context.read<AuthBloc>().add(
      Auth2FALoginRequested(email: _2faEmail, password: _2faPassword, otp: otp),
    );
  }

  void _handleResendOTP() {
    _otpController.clear();
    context.read<AuthBloc>().add(AuthLoginRequested(_2faEmail, _2faPassword));
  }

  Future<void> _handleGoogleLogin() async {
    try {
      final userCredential = await _authService.signInWithGoogle();
      if (userCredential == null || userCredential.user?.email == null) return;
      if (!mounted) return;
      _lastAttemptWasGoogle = true;
      context.read<AuthBloc>().add(
        AuthGoogleLoginRequested(userCredential.user!.email!),
      );
    } catch (error) {
      if (mounted) {
        SnackBarUtils.showSnackBar(
          context,
          ErrorMessageUtils.toUserFriendlyMessage(error),
          isError: true,
        );
      }
    }
  }

  void _playSuccessAndNavigate(BuildContext context) {
    setState(() => _showSuccessOverlay = true);
    _successController.forward(from: 0).then((_) {
      if (!mounted) return;
      Future.delayed(const Duration(milliseconds: 400), () {
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => DashboardScreen(),
            transitionDuration: const Duration(milliseconds: 500),
            transitionsBuilder: (_, animation, __, child) {
              return FadeTransition(
                opacity: animation,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.95, end: 1).animate(
                    CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutCubic,
                    ),
                  ),
                  child: child,
                ),
              );
            },
          ),
        );
      });
    });
  }

  void _onAuthStateChanged(BuildContext context, AuthState state) {
    if (state is AuthRequires2FA) {
      setState(() {
        _show2FAInput = true;
        _2faEmail = state.email;
        _2faPassword = state.password;
        _otpController.clear();
      });
    } else if (state is AuthLoginSuccess) {
      setState(() => _show2FAInput = false);
      final userData = state.data['user'] ?? state.data;
      final role = (userData['role'] ?? '').toString().toLowerCase();
      if (role == 'candidate') {
        context.read<AuthBloc>().add(const AuthLogoutRequested());
        SnackBarUtils.showSnackBar(
          context,
          'login credentials not matching',
          isError: true,
        );
        return;
      }
      _playSuccessAndNavigate(context);
    } else if (state is AuthFailure) {
      if (_lastAttemptWasGoogle) {
        _lastAttemptWasGoogle = false;
        context.read<AuthBloc>().add(const AuthLogoutRequested());
      }
      SnackBarUtils.showSnackBar(
        context,
        ErrorMessageUtils.sanitizeForDisplay(
          state.message,
          fallback: 'Login failed',
        ),
        isError: true,
      );
    } else if (state is AuthLoadInProgress) {
      _lastAttemptWasGoogle = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<AuthBloc, AuthState>(
      listener: _onAuthStateChanged,
      builder: (context, state) {
        final isLoading = state is AuthLoadInProgress;
        return Scaffold(
          resizeToAvoidBottomInset: false,
          backgroundColor: const Color(0xFF1A1A1A),
          body: Stack(
            children: [
              // Animated background
              AnimatedBuilder(
                animation: _entranceController,
                builder: (context, child) {
                  return Opacity(
                    opacity: _bgOpacity.value,
                    child: Transform.scale(
                      scale: _bgScale.value,
                      alignment: Alignment.center,
                      child: Container(
                        height: MediaQuery.of(context).size.height * 0.45,
                        width: double.infinity,
                        decoration: const BoxDecoration(
                          image: DecorationImage(
                            image: AssetImage(
                              'assets/images/ektaHr_feature_graphic.png',
                            ),
                            fit: BoxFit.cover,
                          ),
                          borderRadius: BorderRadius.only(
                            bottomLeft: Radius.circular(40),
                            bottomRight: Radius.circular(40),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),

              // Main content with entrance animation
              SafeArea(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
                    child: AnimatedBuilder(
                      animation: _entranceController,
                      builder: (context, child) {
                        return Transform.translate(
                          offset: Offset(0, _cardSlide.value),
                          child: Opacity(
                            opacity: _cardOpacity.value,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const SizedBox(height: 100),
                                const SizedBox(height: 32),
                                AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 350),
                                  switchInCurve: Curves.easeOutCubic,
                                  switchOutCurve: Curves.easeInCubic,
                                  transitionBuilder: (child, animation) {
                                    return FadeTransition(
                                      opacity: animation,
                                      child: SlideTransition(
                                        position: Tween<Offset>(
                                          begin: const Offset(0, 0.05),
                                          end: Offset.zero,
                                        ).animate(animation),
                                        child: child,
                                      ),
                                    );
                                  },
                                  child: _show2FAInput
                                      ? KeyedSubtree(
                                          key: const ValueKey<bool>(true),
                                          child: _build2FACard(isLoading),
                                        )
                                      : KeyedSubtree(
                                          key: const ValueKey<bool>(false),
                                          child: _buildLoginCard(isLoading),
                                        ),
                                ),
                                const SizedBox(height: 24),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),

              // Success overlay with celebration
              if (_showSuccessOverlay) _buildSuccessOverlay(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSuccessOverlay() {
    const double iconSize = 140;
    return AnimatedBuilder(
      animation: _successController,
      builder: (context, child) {
        return Container(
          color: const Color(0xFF1A1A1A).withOpacity(0.95),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: iconSize,
                  height: iconSize,
                  child: ScaleTransition(
                    scale: _successCheckScale,
                    alignment: Alignment.center,
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withOpacity(0.35),
                            blurRadius: 24,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: ClipOval(
                        child: Image.asset(
                          'assets/ekta_logo.jpeg',
                          width: iconSize,
                          height: iconSize,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                Opacity(
                  opacity: _successMessageOpacity.value,
                  child: Text(
                    'Welcome',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ─── Login card ────────────────────────────────────────────────────────────
  static const Color _cardBg = Color(0xFF2D2D2D);
  static const Color _inputFill = Color(0xFF3D3D3D);

  Widget _buildLoginCard(bool isLoading) {
    return Card(
      color: _cardBg,
      elevation: 8,
      shadowColor: Colors.black26,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // EktaHR · attendance sign-in header
              TextFormField(
                controller: _emailController,
                focusNode: _emailFocusNode,
                keyboardType: TextInputType.emailAddress,
                onTap: _clearHardwareKeyboardState,
                validator: (value) {
                  final email = value?.trim() ?? '';
                  if (email.isEmpty) return 'Please enter your email';
                  // Keep validation permissive so valid modern domains
                  // (long TLDs, plus signs, subdomains) are not blocked locally.
                  final at = email.indexOf('@');
                  if (at <= 0 || at != email.lastIndexOf('@')) {
                    return 'Please enter a valid email';
                  }
                  final domain = email.substring(at + 1);
                  if (!domain.contains('.') ||
                      domain.startsWith('.') ||
                      domain.endsWith('.')) {
                    return 'Please enter a valid email';
                  }
                  return null;
                },
                style: const TextStyle(color: Colors.white, fontSize: 16),
                decoration: InputDecoration(
                  labelText: 'Email',
                  labelStyle: TextStyle(
                    color: Colors.grey.shade400,
                    fontSize: 14,
                  ),
                  fillColor: _inputFill,
                  filled: true,
                  prefixIcon: Icon(
                    Icons.email_outlined,
                    color: AppColors.primary,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF555555)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppColors.primary, width: 2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _passwordController,
                focusNode: _passwordFocusNode,
                obscureText: !_isPasswordVisible,
                onTap: _clearHardwareKeyboardState,
                validator: (value) {
                  if (value == null || value.isEmpty)
                    return 'Please enter your password';
                  return null;
                },
                style: const TextStyle(color: Colors.white, fontSize: 16),
                decoration: InputDecoration(
                  labelText: 'Password',
                  labelStyle: TextStyle(
                    color: Colors.grey.shade400,
                    fontSize: 14,
                  ),
                  fillColor: _inputFill,
                  filled: true,
                  prefixIcon: Icon(
                    Icons.lock_outline,
                    color: AppColors.primary,
                  ),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _isPasswordVisible
                          ? Icons.visibility
                          : Icons.visibility_off,
                      color: Colors.grey,
                    ),
                    onPressed: () => setState(
                      () => _isPasswordVisible = !_isPasswordVisible,
                    ),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF555555)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppColors.primary, width: 2),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: isLoading
                      ? null
                      : () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const ForgotPasswordScreen(),
                          ),
                        ),
                  child: Text(
                    'Forgot Password?',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _AnimatedLoginButton(
                isLoading: isLoading,
                onPressed: _handleLogin,
                buttonScale: _buttonScale,
                onTapDown: () {
                  if (!isLoading) _buttonScaleController.forward();
                },
                onTapUp: () => _buttonScaleController.reverse(),
                onTapCancel: () => _buttonScaleController.reverse(),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  // ─── 2FA OTP card ──────────────────────────────────────────────────────────
  Widget _build2FACard(bool isLoading) {
    return Card(
      color: _cardBg,
      elevation: 8,
      shadowColor: Colors.black26,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.shield_outlined,
                    color: AppColors.primary,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Two-Factor Authentication',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Enter the 6-digit OTP sent to your email',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade400,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Email info
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: _inputFill,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.email_outlined,
                    size: 16,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _2faEmail,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade400,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // OTP input
            TextFormField(
              controller: _otpController,
              focusNode: _otpFocusNode,
              keyboardType: TextInputType.number,
              onTap: _clearHardwareKeyboardState,
              maxLength: 6,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                letterSpacing: 8,
                color: Colors.white,
              ),
              decoration: InputDecoration(
                labelText: 'Enter OTP',
                labelStyle: TextStyle(
                  color: Colors.grey.shade400,
                  fontSize: 14,
                ),
                fillColor: _inputFill,
                filled: true,
                counterText: '',
                prefixIcon: Icon(Icons.lock_outline, color: AppColors.primary),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF555555)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppColors.primary, width: 2),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Verify button
            ElevatedButton(
              onPressed: isLoading ? null : _handleVerifyOTP,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 2,
              ),
              child: isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Verify & Login',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
            const SizedBox(height: 12),

            // Resend OTP
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  "Didn't receive the OTP? ",
                  style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                ),
                GestureDetector(
                  onTap: isLoading ? null : _handleResendOTP,
                  child: Text(
                    'Resend',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Back to login
            TextButton(
              onPressed: isLoading
                  ? null
                  : () {
                      // Reset BLoC to initial so stale error/2FA state is cleared
                      context.read<AuthBloc>().add(const AuthLogoutRequested());
                      setState(() {
                        _show2FAInput = false;
                        _otpController.clear();
                      });
                    },
              child: Text(
                '← Back to Login',
                style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Interactive login button with scale-on-press feedback.
class _AnimatedLoginButton extends StatelessWidget {
  const _AnimatedLoginButton({
    required this.isLoading,
    required this.onPressed,
    required this.buttonScale,
    required this.onTapDown,
    required this.onTapUp,
    required this.onTapCancel,
  });

  final bool isLoading;
  final VoidCallback onPressed;
  final Animation<double> buttonScale;
  final VoidCallback onTapDown;
  final VoidCallback onTapUp;
  final VoidCallback onTapCancel;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => onTapDown(),
      onPointerUp: (_) => onTapUp(),
      onPointerCancel: (_) => onTapCancel(),
      child: ScaleTransition(
        scale: buttonScale,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withOpacity(0.4),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ElevatedButton(
            onPressed: isLoading ? null : onPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 2,
            ),
            child: isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text(
                    'Login',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
          ),
        ),
      ),
    );
  }
}
