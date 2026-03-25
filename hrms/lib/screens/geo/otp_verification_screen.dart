// OTP Verification screen – customer card, 4-digit OTP input, Verify & Complete.
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hrms/config/app_colors.dart';
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
  final List<TextEditingController> _controllers = List.generate(
    4,
    (_) => TextEditingController(),
  );
  final List<FocusNode> _focusNodes = List.generate(4, (_) => FocusNode());
  bool _verified = false;
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
    for (var c in _controllers) c.dispose();
    for (var f in _focusNodes) f.dispose();
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
    final result = await TaskService().sendOtp(taskId);
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
      final displayEmail = widget.task.customer?.effectiveEmail;
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
    if (otp.length != 4) {
      setState(() => _error = 'Enter 4-digit OTP');
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
      );
      if (mounted) {
        setState(() => _verifying = false);
        // Automatically go back to Arrived screen after successful verification
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().contains('Invalid')
              ? 'Invalid OTP. Try again.'
              : 'Verification failed.';
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
    final company = 'ABC Corporation'; // or from customer if available
    final phone = customer?.customerNumber ?? '+91 9940255566';
    final initial = customerName.isNotEmpty
        ? customerName[0].toUpperCase()
        : '?';

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'OTP Verification',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Material(
              color: Colors.red.shade400,
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
                    size: 22,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
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
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 32,
                      backgroundColor: Colors.white.withOpacity(0.3),
                      child: Text(
                        initial,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
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
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            company,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.white.withOpacity(0.95),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Icon(
                                Icons.phone_rounded,
                                size: 16,
                                color: Colors.white.withOpacity(0.95),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  phone,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.white.withOpacity(0.95),
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
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
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Task #${widget.task.taskId} - ${widget.task.taskTitle}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Colors.white,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 20),
              if (!_verified) ...[
                if (!_otpSent && !widget.autoSendOtp) ...[
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.06),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Send OTP to Customer',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey.shade800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'OTP will be sent to the customer\'s email via SendPulse. Ask the customer to share the 4-digit code with you.',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade600,
                          ),
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
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _sendingOtp ? null : _sendOtp,
                            icon: _sendingOtp
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.email_rounded, size: 20),
                            label: Text(
                              _sendingOtp
                                  ? 'Sending...'
                                  : 'Send OTP to Customer',
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                if (_otpSent || widget.autoSendOtp) ...[
                  if (widget.autoSendOtp) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: _sendingOtp
                            ? AppColors.primary.withOpacity(0.1)
                            : AppColors.primary.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          if (_sendingOtp)
                            SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.primary,
                              ),
                            )
                          else
                            Icon(
                              Icons.check_circle_rounded,
                              color: AppColors.primary,
                              size: 22,
                            ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _sendingOtp
                                  ? 'Sending OTP to customer email...'
                                  : _otpSent
                                  ? 'OTP sent to customer. Enter the code below.'
                                  : 'Sending OTP...',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey.shade800,
                                fontWeight: FontWeight.w500,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  // OTP input card
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.06),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Enter OTP from Customer',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey.shade800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Ask the customer for the 4-digit OTP sent to their email',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey.shade600,
                              ),
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
                              for (int i = 0; i < 4; i++) ...[
                                if (i > 0) const SizedBox(width: 12),
                                SizedBox(
                                  width: 56,
                                  child: TextField(
                                  controller: _controllers[i],
                                  focusNode: _focusNodes[i],
                                  keyboardType: TextInputType.number,
                                  textAlign: TextAlign.center,
                                  maxLength: 1,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                  ],
                                  decoration: InputDecoration(
                                    counterText: '',
                                    contentPadding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: BorderSide(
                                        color: _error != null
                                            ? AppColors.error
                                            : (_controllers[i].text.isNotEmpty
                                                  ? AppColors.primary
                                                        .withOpacity(0.6)
                                                  : Colors.grey.shade300),
                                      ),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: BorderSide(
                                        color: _error != null
                                            ? AppColors.error
                                            : (_controllers[i].text.isNotEmpty
                                                  ? AppColors.primary
                                                        .withOpacity(0.6)
                                                  : Colors.grey.shade300),
                                      ),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: BorderSide(
                                        color: AppColors.primary,
                                        width: 2,
                                      ),
                                    ),
                                  ),
                                  onChanged: (v) {
                                    if (v.length == 1 && i < 3) {
                                      _focusNodes[i + 1].requestFocus();
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
                            style: const TextStyle(
                              fontSize: 12,
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
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            Flexible(
                              child: GestureDetector(
                                onTap: _resendOtp,
                                child: Text(
                                  'Resend OTP',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: AppColors.primary,
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
                          child: ElevatedButton(
                            onPressed: _verifying ? null : _verifyOtp,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: _verifying
                                ? const SizedBox(
                                    height: 22,
                                    width: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
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
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.06),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.check_rounded,
                          color: Colors.white,
                          size: 40,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'OTP Verified Successfully!',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Customer identity confirmed. You can now complete the task.',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade600,
                        ),
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
                              border: Border.all(
                                color: AppColors.primary,
                                width: 2,
                              ),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              d,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey.shade800,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Verification Details',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey.shade800,
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
                        child: ElevatedButton.icon(
                          onPressed: _onBackToArrived,
                          icon: const Icon(Icons.arrow_back_rounded, size: 22),
                          label: const Text('Back to Arrived'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
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
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _verified
                        ? 'OTP Verified - Ready to Complete'
                        : 'OTP Verification',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade700,
                      fontWeight: FontWeight.w500,
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
          Icon(Icons.check_circle_rounded, size: 16, color: AppColors.primary),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
          ),
        ],
      ),
    );
  }
}
