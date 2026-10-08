import 'package:flutter/material.dart';
import '../../config/app_colors.dart';
import '../../services/auth_service.dart';
import '../../utils/snackbar_utils.dart';
import '../../utils/error_message_utils.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _authService = AuthService();

  final _emailController = TextEditingController();
  final _otpController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  final _formKey = GlobalKey<FormState>();

  int _step = 0; // 0: email, 1: otp, 2: reset
  bool _isLoading = false;
  bool _isPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;

  String get _email => _emailController.text.trim();

  @override
  void dispose() {
    _emailController.dispose();
    _otpController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    if (_email.isEmpty || !_email.contains('@') || !_email.contains('.')) {
      SnackBarUtils.showSnackBar(
        context,
        'Please enter a valid email address',
        isError: true,
      );
      return;
    }

    setState(() => _isLoading = true);

    final result = await _authService.forgotPassword(_email);

    setState(() => _isLoading = false);

    if (!mounted) return;

    if (result['success'] == true) {
      setState(() => _step = 1);
      SnackBarUtils.showSnackBar(
        context,
        ErrorMessageUtils.sanitizeForDisplay(result['message']?.toString(), fallback: 'OTP sent to your email'),
      );
    } else {
      SnackBarUtils.showSnackBar(
        context,
        result['message'] ?? 'Failed to send OTP',
        isError: true,
      );
    }
  }

  Future<void> _verifyOtp() async {
    final otp = _otpController.text.trim();
    if (otp.length != 6) {
      SnackBarUtils.showSnackBar(
        context,
        'Please enter the 6-digit OTP',
        isError: true,
      );
      return;
    }

    setState(() => _isLoading = true);

    final result = await _authService.verifyOtp(email: _email, otp: otp);

    setState(() => _isLoading = false);

    if (!mounted) return;

    if (result['success'] == true) {
      setState(() => _step = 2);
      SnackBarUtils.showSnackBar(
        context,
        ErrorMessageUtils.sanitizeForDisplay(result['message']?.toString(), fallback: 'OTP verified successfully'),
      );
    } else {
      SnackBarUtils.showSnackBar(
        context,
        result['message'] ?? 'Invalid or expired OTP',
        isError: true,
      );
    }
  }

  Future<void> _resetPassword() async {
    if (!_formKey.currentState!.validate()) return;

    final otp = _otpController.text.trim();
    if (otp.length != 6) {
      SnackBarUtils.showSnackBar(
        context,
        'Please enter the 6-digit OTP',
        isError: true,
      );
      return;
    }

    setState(() => _isLoading = true);

    final result = await _authService.resetPassword(
      email: _email,
      otp: otp,
      newPassword: _passwordController.text.trim(),
    );

    setState(() => _isLoading = false);

    if (!mounted) return;

    if (result['success'] == true) {
      SnackBarUtils.showSnackBar(
        context,
        ErrorMessageUtils.sanitizeForDisplay(result['message']?.toString(), fallback: 'Password reset successfully'),
      );
      Navigator.pop(context);
    } else {
      SnackBarUtils.showSnackBar(
        context,
        ErrorMessageUtils.sanitizeForDisplay(result['message']?.toString(), fallback: 'Failed to reset password'),
        isError: true,
      );
    }
  }

  // ─── Presentation ──────────────────────────────────────────────────────────

  Widget _stepHeader({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: AppColors.primaryText, size: 24),
        ),
        const SizedBox(height: 18),
        Text(
          title,
          style: const TextStyle(
            fontSize: 24,
            height: 1.2,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: const TextStyle(
            fontSize: 14,
            height: 1.45,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _primaryButton({
    required String label,
    required VoidCallback onPressed,
  }) {
    final onPrimary = AppColors.onPrimary;
    return ElevatedButton(
      onPressed: _isLoading ? null : onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: onPrimary,
        disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.75),
        disabledForegroundColor: onPrimary,
        minimumSize: const Size.fromHeight(52),
      ),
      child: _isLoading
          ? SizedBox(
              height: 22,
              width: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                color: onPrimary,
              ),
            )
          : Text(label),
    );
  }

  Widget _visibilityToggle({
    required bool visible,
    required VoidCallback onPressed,
  }) {
    return IconButton(
      tooltip: visible ? 'Hide password' : 'Show password',
      icon: Icon(
        visible ? Icons.visibility_outlined : Icons.visibility_off_outlined,
        size: 20,
      ),
      onPressed: onPressed,
    );
  }

  Widget _buildStepContent() {
    switch (_step) {
      case 0:
        return Column(
          key: const ValueKey<int>(0),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _stepHeader(
              icon: Icons.mark_email_read_outlined,
              title: 'Forgot Password',
              subtitle:
                  'Enter your registered email address. We will send a 6-digit OTP to reset your password.',
            ),
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email',
                prefixIcon: Icon(Icons.mail_outline_rounded, size: 20),
              ),
            ),
            const SizedBox(height: 24),
            _primaryButton(label: 'Send OTP', onPressed: _sendOtp),
          ],
        );
      case 1:
        return Column(
          key: const ValueKey<int>(1),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _stepHeader(
              icon: Icons.password_rounded,
              title: 'Enter OTP',
              subtitle:
                  'We have sent a 6-digit OTP to $_email. Please enter it below to verify.',
            ),
            TextField(
              controller: _otpController,
              keyboardType: TextInputType.number,
              maxLength: 6,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                letterSpacing: 8,
                color: AppColors.textPrimary,
              ),
              decoration: const InputDecoration(
                labelText: 'OTP',
                counterText: '',
                prefixIcon: Icon(Icons.password_outlined, size: 20),
                // Balances the prefix icon so the digits sit centred.
                suffixIcon: SizedBox(width: 48),
              ),
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _isLoading ? null : _sendOtp,
                child: const Text('Resend OTP'),
              ),
            ),
            const SizedBox(height: 12),
            _primaryButton(label: 'Verify OTP', onPressed: _verifyOtp),
          ],
        );
      case 2:
      default:
        return Column(
          key: const ValueKey<int>(2),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _stepHeader(
              icon: Icons.lock_reset_rounded,
              title: 'Reset Password',
              subtitle: 'Create a strong new password for your account.',
            ),
            TextFormField(
              controller: _passwordController,
              obscureText: !_isPasswordVisible,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter a new password';
                }
                if (value.length < 6) {
                  return 'Password should be at least 6 characters';
                }
                return null;
              },
              decoration: InputDecoration(
                labelText: 'New Password',
                prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
                suffixIcon: _visibilityToggle(
                  visible: _isPasswordVisible,
                  onPressed: () {
                    setState(() {
                      _isPasswordVisible = !_isPasswordVisible;
                    });
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _confirmPasswordController,
              obscureText: !_isConfirmPasswordVisible,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please confirm your new password';
                }
                if (value != _passwordController.text) {
                  return 'Passwords do not match';
                }
                return null;
              },
              decoration: InputDecoration(
                labelText: 'Confirm New Password',
                prefixIcon: const Icon(Icons.lock_reset_outlined, size: 20),
                suffixIcon: _visibilityToggle(
                  visible: _isConfirmPasswordVisible,
                  onPressed: () {
                    setState(() {
                      _isConfirmPasswordVisible = !_isConfirmPasswordVisible;
                    });
                  },
                ),
              ),
            ),
            const SizedBox(height: 24),
            _primaryButton(label: 'Reset Password', onPressed: _resetPassword),
          ],
        );
    }
  }

  /// Three-segment progress: email → OTP → new password.
  Widget _buildStepIndicator() {
    const labels = ['Email', 'Verify', 'Reset'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            for (var i = 0; i < labels.length; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  height: 4,
                  decoration: BoxDecoration(
                    color: i <= _step
                        ? AppColors.primary
                        : const Color(0xFFE5E7EB),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),
        Text(
          'STEP ${_step + 1} OF 3 · ${labels[_step.clamp(0, 2)].toUpperCase()}',
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
            color: AppColors.primaryText,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Forgot Password')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Container(
                padding: const EdgeInsets.fromLTRB(24, 22, 24, 24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFFECEEF1)),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x120F172A),
                      blurRadius: 32,
                      offset: Offset(0, 14),
                    ),
                  ],
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildStepIndicator(),
                      const SizedBox(height: 24),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 280),
                        switchInCurve: Curves.easeOutCubic,
                        transitionBuilder: (child, animation) =>
                            FadeTransition(
                              opacity: animation,
                              child: SlideTransition(
                                position: Tween<Offset>(
                                  begin: const Offset(0.04, 0),
                                  end: Offset.zero,
                                ).animate(animation),
                                child: child,
                              ),
                            ),
                        child: _buildStepContent(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
