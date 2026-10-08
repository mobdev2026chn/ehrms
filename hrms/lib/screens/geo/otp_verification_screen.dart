// OTP Verification screen – customer card, 6-digit OTP input, Verify & Complete.
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hrms/config/app_colors.dart';
import 'package:hrms/config/app_text_styles.dart';
import 'package:hrms/widgets/app_card.dart';
import 'package:hrms/models/task.dart';
import 'package:hrms/services/geo/address_resolution_service.dart';
import 'package:hrms/services/task_service.dart';
import 'package:hrms/utils/date_display_util.dart';
import 'package:hrms/utils/snackbar_utils.dart';
import 'package:url_launcher/url_launcher.dart';

class OtpVerificationScreen extends StatefulWidget {
  final Task task;
  final String? taskMongoId;
  final DateTime arrivalTime;
  final Duration totalDuration;
  final double totalDistanceKm;

  /// When true, automatically send OTP email on screen load (e.g. when opened from "Get OTP from customer").
  final bool autoSendOtp;

  const OtpVerificationScreen({
    super.key,
    required this.task,
    this.taskMongoId,
    required this.arrivalTime,
    required this.totalDuration,
    required this.totalDistanceKm,
    this.autoSendOtp = false,
  });

  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen> {
  /// HRMSbackend emails a 6-digit passcode.
  static const int _otpLength = 6;

  final List<TextEditingController> _controllers = List.generate(
    _otpLength,
    (_) => TextEditingController(),
  );
  final List<FocusNode> _focusNodes = List.generate(_otpLength, (_) => FocusNode());
  final bool _verified = false;
  bool _verifying = false;
  bool _sendingOtp = false;
  bool _otpSent = false;
  String? _verifiedOtp;
  DateTime? _verifiedAt;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.autoSendOtp) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _sendOtp());
    }
  }

  @override
  void dispose() {
    for (var c in _controllers) {
      c.dispose();
    }
    for (var f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  String get _enteredOtp => _controllers.map((c) => c.text).join();

  Future<void> _sendOtp() async {
    if (widget.taskMongoId == null || widget.taskMongoId!.isEmpty) {
      developer.log('OTP verification: skip send - taskMongoId is null or empty', name: 'OtpVerificationScreen');
      return;
    }
    final taskId = widget.taskMongoId!;
    final email = widget.task.customer?.effectiveEmail ?? '(no email)';
    developer.log('OTP verification: sending OTP for taskId=$taskId, customerEmail=${email.isNotEmpty ? email.replaceAll(RegExp(r'(?<=.).(?=.*@)'), '*') : "(none)"}', name: 'OtpVerificationScreen');
    setState(() {
      _sendingOtp = true;
      _error = null;
    });
    final result = await TaskService().sendOtp(taskId, customer: widget.task.customer);
    if (!mounted) return;
    setState(() => _sendingOtp = false);
    final success = result['success'] == true;
    final message = result['message'] as String? ?? (success ? 'OTP sent.' : 'Failed to send OTP.');
    if (success) {
      developer.log('OTP verification: OTP sent successfully for taskId=$taskId', name: 'OtpVerificationScreen');
      setState(() {
        _otpSent = true;
        _error = null;
      });
      final displayEmail = (result['email'] as String?) ?? widget.task.customer?.effectiveEmail;
      final userMessage = displayEmail != null && displayEmail.isNotEmpty
          ? 'OTP sent to ${displayEmail.replaceAll(RegExp(r'(?<=.).(?=.*@)'), '*')}'
          : message;
      SnackBarUtils.showSnackBar(
        context,
        userMessage,
        backgroundColor: AppColors.primary,
      );
    } else {
      developer.log('OTP verification: failed to send OTP for taskId=$taskId', name: 'OtpVerificationScreen');
      setState(() => _error = message);
      SnackBarUtils.showSnackBar(context, message, isError: true);
    }
  }

  /// After OTP verified, pop back to Arrived screen (do not complete task here).
  void _onBackToArrived() {
    Navigator.of(context).pop();
  }

  Future<void> _verifyOtp() async {
    final otp = _enteredOtp;
    if (otp.length != _otpLength) {
      setState(() => _error = 'Enter the $_otpLength-digit OTP');
      return;
    }
    if (widget.taskMongoId == null || widget.taskMongoId!.isEmpty) {
      setState(() => _error = 'Task not found');
      return;
    }
    setState(() {
      _error = null;
      _verifying = true;
    });
    try {
      double? lat;
      double? lng;
      String? fullAddress;
      try {
        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );
        lat = pos.latitude;
        lng = pos.longitude;
        fullAddress =
            (await AddressResolutionService.reverseGeocode(lat, lng))
                ?.formattedAddress;
      } catch (_) {}
      await TaskService().verifyOtp(
        widget.taskMongoId!,
        otp,
        lat: lat,
        lng: lng,
        fullAddress: fullAddress,
        customer: widget.task.customer,
      );
      if (mounted) {
        setState(() => _verifying = false);
        // Automatically go back to Arrived screen after successful verification
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        final text = e.toString().replaceFirst('Exception: ', '');
        setState(() {
          _error = text.toLowerCase().contains('invalid')
              ? 'Invalid or expired OTP. Try again.'
              : (text.isNotEmpty ? text : 'Verification failed.');
          _verifying = false;
        });
      }
    }
  }

  void _resendOtp() {
    _sendOtp();
  }

  @override
  Widget build(BuildContext context) {
    final customer = widget.task.customer;
    final customerName = customer?.customerName ?? 'Customer';
    final company = customer?.companyName?.trim() ?? '';
    final phone = customer?.customerNumber?.trim() ?? '';
    final initial = customerName.isNotEmpty
        ? customerName[0].toUpperCase()
        : '?';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Back',
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('OTP Verification'),
        actions: [
          if (phone.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Material(
              color: AppColors.success,
              shape: const CircleBorder(),
              child: InkWell(
                onTap: () {
                  final uri = Uri.parse(
                    'tel:${phone.replaceAll(RegExp(r'\s'), '')}',
                  );
                  launchUrl(uri);
                },
                customBorder: const CircleBorder(),
                child: const Padding(
                  padding: EdgeInsets.all(10),
                  child: Icon(
                    Icons.phone_rounded,
                    color: Colors.white,
                    size: 20,
                    semanticLabel: 'Call customer',
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Customer & task card – same bg as dashboard Recent Leaves card
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppColors.primary, AppColors.primaryDark],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: AppColors.onPrimary.withValues(alpha: 0.12),
                      child: Text(
                        initial,
                        style: TextStyle(
                          color: AppColors.onPrimary,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            customerName,
                            style: AppTextStyles.headingMedium.copyWith(
                              fontWeight: FontWeight.w700,
                              color: AppColors.onPrimary,
                            ),
                          ),
                          if (company.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              company,
                              style: AppTextStyles.bodyMedium.copyWith(
                                color: AppColors.onPrimary.withValues(alpha: 0.85),
                              ),
                            ),
                          ],
                          if (phone.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Icon(
                                Icons.phone_outlined,
                                size: 16,
                                color: AppColors.onPrimary.withValues(alpha: 0.85),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  phone,
                                  style: AppTextStyles.bodyMedium.copyWith(
                                    color: AppColors.onPrimary.withValues(alpha: 0.85),
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFECEEF1)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.assignment_outlined,
                      size: 18,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Task #${widget.task.taskId} - ${widget.task.taskTitle}',
                        style: AppTextStyles.bodySmall.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (!_verified) ...[
                if (!_otpSent && !widget.autoSendOtp) ...[
                  AppCard(
                    padding: const EdgeInsets.all(20),
                    border: Border.all(color: const Color(0xFFECEEF1)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Send OTP to Customer',
                          style: AppTextStyles.headingSmall,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'OTP will be sent to the customer\'s email. Ask the customer to share the $_otpLength-digit code with you.',
                          style: AppTextStyles.bodySmall,
                        ),
                        if (widget.task.customer?.effectiveEmail != null &&
                            widget
                                .task
                                .customer!
                                .effectiveEmail!
                                .isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Email: ${widget.task.customer!.effectiveEmail}',
                            style: AppTextStyles.bodySmall.copyWith(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton.icon(
                            onPressed: _sendingOtp ? null : _sendOtp,
                            icon: _sendingOtp
                                ? SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppColors.onPrimary,
                                    ),
                                  )
                                : const Icon(Icons.email_outlined, size: 20),
                            label: Text(
                              _sendingOtp
                                  ? 'Sending...'
                                  : 'Send OTP to Customer',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (_otpSent || widget.autoSendOtp) ...[
                  if (widget.autoSendOtp) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: _sendingOtp
                            ? AppColors.primary.withValues(alpha: 0.1)
                            : _otpSent
                            ? AppColors.successBg
                            : AppColors.errorBg,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          if (_sendingOtp)
                            SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.primaryText,
                              ),
                            )
                          else if (_otpSent)
                            const Icon(
                              Icons.check_circle_rounded,
                              color: AppColors.success,
                              size: 20,
                            )
                          else
                            const Icon(
                              Icons.error_outline_rounded,
                              color: AppColors.error,
                              size: 20,
                            ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _sendingOtp
                                  ? 'Sending OTP to customer email...'
                                  : _otpSent
                                  ? 'OTP sent to customer. Enter the code below.'
                                  : 'We couldn\'t deliver the OTP to the customer email. Please try again or check email configuration.',
                              style: AppTextStyles.bodySmall.copyWith(
                                color: _sendingOtp || _otpSent
                                    ? AppColors.textPrimary
                                    : AppColors.error,
                                fontWeight: FontWeight.w500,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 2,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  // OTP input card
                  AppCard(
                    padding: const EdgeInsets.all(20),
                    border: Border.all(color: const Color(0xFFECEEF1)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Enter OTP from Customer',
                              style: AppTextStyles.headingSmall,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Ask the customer for the $_otpLength-digit OTP sent to their email',
                              style: AppTextStyles.bodySmall,
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (int i = 0; i < _otpLength; i++) ...[
                                if (i > 0) const SizedBox(width: 8),
                                SizedBox(
                                  width: 42,
                                  child: TextField(
                                  controller: _controllers[i],
                                  focusNode: _focusNodes[i],
                                  keyboardType: TextInputType.number,
                                  textAlign: TextAlign.center,
                                  maxLength: 1,
                                  style: AppTextStyles.headingMedium,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                  ],
                                  decoration: InputDecoration(
                                    counterText: '',
                                    contentPadding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(
                                        color: _error != null
                                            ? AppColors.error
                                            : (_controllers[i].text.isNotEmpty
                                                  ? AppColors.primary
                                                        .withValues(alpha: 0.6)
                                                  : const Color(0xFFE2E5EA)),
                                      ),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(
                                        color: _error != null
                                            ? AppColors.error
                                            : (_controllers[i].text.isNotEmpty
                                                  ? AppColors.primary
                                                        .withValues(alpha: 0.6)
                                                  : const Color(0xFFE2E5EA)),
                                      ),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(
                                        color: AppColors.primary,
                                        width: 1.6,
                                      ),
                                    ),
                                  ),
                                  onChanged: (v) {
                                    if (v.length == 1 && i < _otpLength - 1) {
                                      _focusNodes[i + 1].requestFocus();
                                    } else if (v.isEmpty && i > 0) {
                                      _focusNodes[i - 1].requestFocus();
                                    }
                                    setState(() => _error = null);
                                  },
                                ),
                              ),
                            ],
                            ],
                          ),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            _error!,
                            style: AppTextStyles.caption.copyWith(
                              color: AppColors.error,
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              "Didn't receive OTP? ",
                              style: AppTextStyles.bodySmall,
                            ),
                            Flexible(
                              child: GestureDetector(
                                onTap: _resendOtp,
                                child: Text(
                                  'Resend OTP',
                                  style: AppTextStyles.bodySmall.copyWith(
                                    color: AppColors.primaryText,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton(
                            onPressed: _verifying ? null : _verifyOtp,
                            child: _verifying
                                ? SizedBox(
                                    height: 22,
                                    width: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppColors.onPrimary,
                                    ),
                                  )
                                : const Text('Verify OTP'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ] else ...[
                // OTP verified success state
                AppCard(
                  padding: const EdgeInsets.all(24),
                  border: Border.all(color: const Color(0xFFECEEF1)),
                  child: Column(
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        decoration: const BoxDecoration(
                          color: AppColors.successBg,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.check_rounded,
                          color: AppColors.success,
                          size: 36,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'OTP Verified Successfully!',
                        style: AppTextStyles.headingMedium.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Customer identity confirmed. You can now complete the task.',
                        style: AppTextStyles.bodySmall,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: (_verifiedOtp ?? '').split('').map((d) {
                          return Container(
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.successBg.withValues(alpha: 0.5),
                              border: Border.all(
                                color: AppColors.success.withValues(alpha: 0.4),
                                width: 1.2,
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              d,
                              style: AppTextStyles.headingMedium.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 20),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.background,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFECEEF1)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Verification Details',
                              style: AppTextStyles.label.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            _verificationLine('OTP matched: $_verifiedOtp'),
                            _verificationLine(
                              'Verified at: ${_verifiedAt != null ? DateDisplayUtil.formatTime(_verifiedAt!) : '—'}',
                            ),
                            _verificationLine(
                              'Customer: $customerName ($phone)',
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton.icon(
                          onPressed: _onBackToArrived,
                          icon: const Icon(Icons.arrow_back_rounded, size: 20),
                          label: const Text('Back to Arrived'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),
              // Bottom step indicator
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        _verified ? '7' : '6',
                        style: TextStyle(
                          color: AppColors.onPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      _verified
                          ? 'OTP Verified - Ready to Complete'
                          : 'OTP Verification',
                      style: AppTextStyles.bodySmall.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _verificationLine(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          const Icon(Icons.check_circle_rounded, size: 16, color: AppColors.success),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              text,
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}
