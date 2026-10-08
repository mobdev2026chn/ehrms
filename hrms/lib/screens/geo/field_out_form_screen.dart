// Field-Out form built from the admin's form template (HRMSbackend `requirements`).
// Same field rules as the web staff portal's submission modal: every active field is
// required, an Email field is verified by emailed OTP (and replaces the plain OTP field),
// images are uploaded and answered with their URL. Pops with the answers map
// (keyed by field name) or null when cancelled.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:hrms/config/app_colors.dart';
import 'package:hrms/config/app_text_styles.dart';
import 'package:hrms/widgets/app_card.dart';
import 'package:hrms/models/task.dart';
import 'package:hrms/services/task_service.dart';
import 'package:hrms/utils/snackbar_utils.dart';

class FieldOutFormScreen extends StatefulWidget {
  final String title;
  final String? subtitle;
  final List<TaskRequirement> requirements;

  /// Pre-fills an Email field (e.g. the customer's email).
  final String? prefillEmail;

  const FieldOutFormScreen({
    super.key,
    this.title = 'Field Out',
    this.subtitle,
    required this.requirements,
    this.prefillEmail,
  });

  /// Opens the form and returns the answers, or null if the user backed out.
  static Future<Map<String, String>?> open(
    BuildContext context, {
    required List<TaskRequirement> requirements,
    String title = 'Field Out',
    String? subtitle,
    String? prefillEmail,
  }) {
    return Navigator.of(context).push<Map<String, String>>(
      MaterialPageRoute(
        builder: (_) => FieldOutFormScreen(
          title: title,
          subtitle: subtitle,
          requirements: requirements.isNotEmpty ? requirements : TaskRequirement.webDefaults,
          prefillEmail: prefillEmail,
        ),
      ),
    );
  }

  @override
  State<FieldOutFormScreen> createState() => _FieldOutFormScreenState();
}

class _FieldOutFormScreenState extends State<FieldOutFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _service = TaskService();
  final Map<String, TextEditingController> _text = {};
  final Map<String, String> _imageUrls = {};
  final Map<String, String> _dropdown = {};
  final Set<String> _uploading = {};

  // Email OTP state (per Email field).
  final Map<String, TextEditingController> _emailOtp = {};
  final Set<String> _otpSent = {};
  final Set<String> _sendingOtp = {};
  final Set<String> _verifyingOtp = {};
  final Map<String, String> _verifiedEmail = {};

  bool _submitting = false;

  List<TaskRequirement> get _fields {
    final hasEmail = widget.requirements.any((r) => r.isEmail);
    // An Email field supersedes the plain OTP field - the passcode goes to that address.
    return widget.requirements.where((r) => !(hasEmail && r.isOtp)).toList();
  }

  @override
  void initState() {
    super.initState();
    for (final f in _fields) {
      if (f.isImage || f.isDropdown) continue;
      _text[f.name] = TextEditingController(
        text: f.isEmail ? (widget.prefillEmail ?? '') : '',
      );
      if (f.isEmail) _emailOtp[f.name] = TextEditingController();
      if (f.isGps) _fillGps(f.name);
    }
  }

  @override
  void dispose() {
    for (final c in [..._text.values, ..._emailOtp.values]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _fillGps(String name) async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      ).timeout(const Duration(seconds: 10));
      if (!mounted) return;
      _text[name]?.text = '${pos.latitude.toStringAsFixed(6)}, ${pos.longitude.toStringAsFixed(6)}';
      setState(() {});
    } catch (_) {}
  }

  Future<void> _pickImage(TaskRequirement f) async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
      maxWidth: 1600,
    );
    if (picked == null) return;
    setState(() => _uploading.add(f.name));
    try {
      final url = await _service.uploadFieldOutImage(picked.path);
      if (!mounted) return;
      setState(() => _imageUrls[f.name] = url);
    } catch (e) {
      if (mounted) {
        SnackBarUtils.showSnackBar(context, _msg(e), isError: true);
      }
    } finally {
      if (mounted) setState(() => _uploading.remove(f.name));
    }
  }

  Future<void> _sendOtp(TaskRequirement f) async {
    final email = _text[f.name]?.text.trim() ?? '';
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      SnackBarUtils.showSnackBar(context, 'Enter a valid email address', isError: true);
      return;
    }
    setState(() => _sendingOtp.add(f.name));
    try {
      await _service.sendEmailOtp(email);
      if (!mounted) return;
      setState(() {
        _otpSent.add(f.name);
        _verifiedEmail.remove(f.name);
      });
      SnackBarUtils.showSnackBar(context, 'OTP sent to $email');
    } catch (e) {
      if (mounted) SnackBarUtils.showSnackBar(context, _msg(e), isError: true);
    } finally {
      if (mounted) setState(() => _sendingOtp.remove(f.name));
    }
  }

  Future<void> _verifyOtp(TaskRequirement f) async {
    final email = _text[f.name]?.text.trim() ?? '';
    final otp = _emailOtp[f.name]?.text.trim() ?? '';
    if (otp.length != 6) {
      SnackBarUtils.showSnackBar(context, 'Enter the 6-digit OTP', isError: true);
      return;
    }
    setState(() => _verifyingOtp.add(f.name));
    try {
      await _service.verifyEmailOtp(email, otp);
      if (!mounted) return;
      setState(() => _verifiedEmail[f.name] = email);
      SnackBarUtils.showSnackBar(context, 'Email verified');
    } catch (e) {
      if (mounted) SnackBarUtils.showSnackBar(context, _msg(e), isError: true);
    } finally {
      if (mounted) setState(() => _verifyingOtp.remove(f.name));
    }
  }

  static String _msg(Object e) => e.toString().replaceFirst('Exception: ', '');

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final answers = <String, String>{};
    for (final f in _fields) {
      String value;
      if (f.isImage) {
        value = _imageUrls[f.name] ?? '';
      } else if (f.isDropdown) {
        value = _dropdown[f.name] ?? '';
      } else {
        value = _text[f.name]?.text.trim() ?? '';
      }
      if (value.isEmpty) {
        SnackBarUtils.showSnackBar(context, '${f.name} is required', isError: true);
        return;
      }
      if (f.isEmail && _verifiedEmail[f.name] != value) {
        SnackBarUtils.showSnackBar(context, 'Verify ${f.name} with the OTP first', isError: true);
        return;
      }
      answers[f.name] = value;
    }
    setState(() => _submitting = true);
    Navigator.of(context).pop(answers);
  }

  InputDecoration _decoration(String hint) => InputDecoration(
        hintText: hint,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      );

  String? _required(String? v) => (v == null || v.trim().isEmpty) ? 'Required' : null;

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text.rich(
          TextSpan(
            text: text,
            children: const [
              TextSpan(text: ' *', style: TextStyle(color: AppColors.error)),
            ],
          ),
          style: AppTextStyles.label.copyWith(fontWeight: FontWeight.w600),
        ),
      );

  Widget _buildField(TaskRequirement f) {
    if (f.isImage) return _imageField(f);
    if (f.isEmail) return _emailField(f);
    if (f.isDropdown) return _dropdownField(f);

    final controller = _text[f.name]!;
    if (f.isOtp) {
      return TextFormField(
        controller: controller,
        keyboardType: TextInputType.number,
        maxLength: 6,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 20, letterSpacing: 8, fontWeight: FontWeight.w700),
        decoration: _decoration('6-digit OTP').copyWith(counterText: ''),
        validator: (v) => (v == null || v.trim().length != 6) ? 'Enter the 6-digit OTP' : null,
      );
    }
    if (f.isGps) {
      return TextFormField(
        controller: controller,
        readOnly: true,
        decoration: _decoration('Fetching location...').copyWith(
          suffixIcon: IconButton(
            icon: const Icon(Icons.my_location_rounded, size: 20),
            tooltip: 'Refresh location',
            onPressed: () => _fillGps(f.name),
          ),
        ),
        validator: _required,
      );
    }
    return TextFormField(
      controller: controller,
      keyboardType: f.isNumeric ? TextInputType.number : TextInputType.text,
      minLines: f.isTextArea ? 3 : 1,
      maxLines: f.isTextArea ? 6 : 1,
      textCapitalization: TextCapitalization.sentences,
      decoration: _decoration(f.isTextArea ? 'Describe the work done...' : 'Enter ${f.name.toLowerCase()}'),
      validator: _required,
    );
  }

  Widget _imageField(TaskRequirement f) {
    final url = _imageUrls[f.name];
    final busy = _uploading.contains(f.name);
    return InkWell(
      onTap: busy ? null : () => _pickImage(f),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: url != null ? 180 : 110,
        width: double.infinity,
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: url != null ? AppColors.primary : const Color(0xFFE2E5EA),
            width: 1.2,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: busy
            ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
            : url != null
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.network(url, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox()),
                      Positioned(
                        right: 8,
                        bottom: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.camera_alt_rounded, size: 14, color: Colors.white),
                              SizedBox(width: 4),
                              Text('Retake', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.photo_camera_outlined, size: 20, color: AppColors.primaryText),
                      ),
                      const SizedBox(height: 8),
                      const Text('Tap to take a photo', style: AppTextStyles.bodySmall),
                    ],
                  ),
      ),
    );
  }

  Widget _emailField(TaskRequirement f) {
    final verified = _verifiedEmail[f.name] != null &&
        _verifiedEmail[f.name] == _text[f.name]!.text.trim();
    final sending = _sendingOtp.contains(f.name);
    final verifying = _verifyingOtp.contains(f.name);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextFormField(
                controller: _text[f.name],
                keyboardType: TextInputType.emailAddress,
                decoration: _decoration('customer@email.com').copyWith(
                  suffixIcon: verified
                      ? const Icon(Icons.verified_rounded, color: AppColors.success, size: 20)
                      : null,
                ),
                onChanged: (_) => setState(() {}),
                validator: _required,
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 48,
              child: OutlinedButton(
                onPressed: (sending || verified) ? null : () => _sendOtp(f),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primaryText,
                  side: BorderSide(color: AppColors.primary, width: 1.2),
                ),
                child: sending
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(_otpSent.contains(f.name) ? 'Resend' : 'Send OTP'),
              ),
            ),
          ],
        ),
        if (_otpSent.contains(f.name) && !verified) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _emailOtp[f.name],
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 18, letterSpacing: 6, fontWeight: FontWeight.w700),
                  decoration: _decoration('6-digit OTP').copyWith(counterText: ''),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: verifying ? null : () => _verifyOtp(f),
                  child: verifying
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onPrimary),
                        )
                      : const Text('Verify'),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _dropdownField(TaskRequirement f) {
    final options = f.response
        .split(RegExp(r'[,\n|]'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (options.isEmpty) {
      // No options configured: fall back to free text.
      _text.putIfAbsent(f.name, () => TextEditingController());
      return TextFormField(
        controller: _text[f.name],
        decoration: _decoration('Enter ${f.name.toLowerCase()}'),
        validator: _required,
      );
    }
    return DropdownButtonFormField<String>(
      initialValue: _dropdown[f.name],
      isExpanded: true,
      items: options
          .map((o) => DropdownMenuItem(
                value: o,
                child: Text(o, maxLines: 1, overflow: TextOverflow.ellipsis),
              ))
          .toList(),
      onChanged: (v) => setState(() {
        if (v != null) _dropdown[f.name] = v;
      }),
      decoration: _decoration('Select ${f.name.toLowerCase()}'),
      validator: (v) => v == null ? 'Required' : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            if (widget.subtitle != null && widget.subtitle!.isNotEmpty) ...[
              Text(
                widget.subtitle!,
                style: AppTextStyles.bodySmall,
              ),
              const SizedBox(height: 12),
            ],
            AppCard(
              border: Border.all(color: const Color(0xFFECEEF1)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (i, f) in _fields.indexed) ...[
                    if (i > 0) const SizedBox(height: 16),
                    _label(f.name),
                    _buildField(f),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: Color(0xFFECEEF1))),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: (_submitting || _uploading.isNotEmpty) ? null : _submit,
                child: const Text('Submit & Field Out'),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
