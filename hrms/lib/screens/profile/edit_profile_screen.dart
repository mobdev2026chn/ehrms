// hrms/lib/screens/profile/edit_profile_screen.dart
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../config/app_colors.dart';
import '../../services/auth_service.dart';
import '../../utils/error_message_utils.dart';
import '../../utils/face_detection_helper.dart';
import '../../utils/snackbar_utils.dart';
import '../attendance/selfie_camera_screen.dart';

/// Full-screen Edit Profile matching the Figma design:
/// Cancel / Edit Profile header, avatar with camera button, editable
/// Personal Details (name, email, phone, address) and read-only Bank Details.
///
/// Pops with `true` when the profile was saved successfully so the caller can
/// refresh.
class EditProfileScreen extends StatefulWidget {
  /// Flattened map of profile + staff data (see [_flatten] in profile screen).
  final Map<String, dynamic> userData;

  const EditProfileScreen({super.key, required this.userData});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final AuthService _authService = AuthService();

  late final TextEditingController _nameCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _addressCtrl;

  String? _photoUrl;
  bool _photoError = false;
  bool _saving = false;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    final d = widget.userData;
    _nameCtrl = TextEditingController(text: d['name']?.toString() ?? '');
    _emailCtrl = TextEditingController(text: d['email']?.toString() ?? '');
    _phoneCtrl = TextEditingController(text: d['phone']?.toString() ?? '');
    _addressCtrl =
        TextEditingController(text: _composeAddress(d['address']));
    _photoUrl =
        (d['avatar'] ?? d['photoUrl'] ?? d['profilePic'])?.toString().trim();
    for (final c in [_nameCtrl, _emailCtrl, _phoneCtrl, _addressCtrl]) {
      c.addListener(() {
        if (!_dirty) setState(() => _dirty = true);
      });
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  String _composeAddress(dynamic address) {
    if (address is Map) {
      final parts = [
        address['line1'],
        address['city'],
        address['state'],
        address['postalCode'],
        address['country'],
      ].map((e) => e?.toString().trim() ?? '').where((e) => e.isNotEmpty);
      return parts.join(', ');
    }
    return address?.toString() ?? '';
  }

  bool get _hasPhoto {
    final url = _photoUrl;
    return url != null &&
        url.isNotEmpty &&
        (url.startsWith('http://') || url.startsWith('https://')) &&
        !_photoError;
  }

  @override
  Widget build(BuildContext context) {
    final name = _nameCtrl.text.isNotEmpty
        ? _nameCtrl.text
        : (widget.userData['name']?.toString() ?? 'User');
    final empId = widget.userData['employeeId']?.toString() ??
        widget.userData['empId']?.toString() ??
        '';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        automaticallyImplyLeading: false,
        leading: TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).maybePop(),
          child: const Text(
            'Cancel',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        leadingWidth: 84,
        title: const Text(
          'Edit Profile',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: AppColors.textPrimary,
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildAvatar(),
                      const SizedBox(height: 12),
                      Text(
                        name,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      if (empId.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Employee ID: #$empId',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      _buildPersonalDetailsCard(),
                      const SizedBox(height: 20),
                      _buildBankDetailsCard(),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ),
            _buildSaveBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar() {
    final initial = _nameCtrl.text.trim().isNotEmpty
        ? _nameCtrl.text.trim()[0].toUpperCase()
        : 'U';
    return Center(
      child: GestureDetector(
        onTap: _changePhoto,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            CircleAvatar(
              radius: 48,
              backgroundColor: AppColors.primary.withValues(alpha: 0.12),
              backgroundImage: _hasPhoto ? CachedNetworkImageProvider(_photoUrl!) : null,
              onBackgroundImageError: _hasPhoto
                  ? (_, __) {
                      if (mounted) setState(() => _photoError = true);
                    }
                  : null,
              child: _hasPhoto
                  ? null
                  : Text(
                      initial,
                      style: TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
            ),
            Positioned(
              bottom: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.background, width: 3),
                ),
                child: const Icon(Icons.camera_alt,
                    size: 16, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPersonalDetailsCard() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardHeader(Icons.person_outline, 'Personal Details'),
          const SizedBox(height: 20),
          _field(
            label: 'FULL NAME',
            controller: _nameCtrl,
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Name is required' : null,
          ),
          const SizedBox(height: 18),
          _field(
            label: 'EMAIL ADDRESS',
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            validator: (v) {
              if (v == null || v.trim().isEmpty) return null;
              final re = RegExp(r'^[^@]+@[^@]+\.[^@]+');
              return re.hasMatch(v.trim()) ? null : 'Enter a valid email';
            },
          ),
          const SizedBox(height: 18),
          _field(
            label: 'PHONE NUMBER',
            controller: _phoneCtrl,
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 18),
          _field(
            label: 'ADDRESS',
            controller: _addressCtrl,
            maxLines: 3,
          ),
        ],
      ),
    );
  }

  Widget _buildBankDetailsCard() {
    final bank = widget.userData['bankDetails'];
    final bankMap = bank is Map ? bank : const {};
    final bankName = bankMap['bankName']?.toString() ?? 'N/A';
    final ifsc = bankMap['ifscCode']?.toString() ?? 'N/A';
    final account = _maskAccount(bankMap['accountNumber']?.toString());

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.account_balance_outlined,
                  color: AppColors.primary, size: 20),
              const SizedBox(width: 10),
              const Text(
                'Bank Details',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              Icon(Icons.lock_outline,
                  size: 18, color: AppColors.textSecondary),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _readOnly('PRIMARY BANK', bankName)),
              Expanded(child: _readOnly('IFSC CODE', ifsc)),
            ],
          ),
          const SizedBox(height: 18),
          _readOnly('ACCOUNT NUMBER', account),
          const SizedBox(height: 16),
          Text(
            'To update bank details, please contact the HR department directly.',
            style: TextStyle(
              fontSize: 12,
              fontStyle: FontStyle.italic,
              color: AppColors.textSecondary,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSaveBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: BoxDecoration(
        color: AppColors.background,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SizedBox(
        width: double.infinity,
        height: 54,
        child: ElevatedButton.icon(
          onPressed: _saving ? null : _handleSave,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            disabledBackgroundColor:
                AppColors.primary.withValues(alpha: 0.6),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
            ),
          ),
          icon: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.save_outlined, color: Colors.white, size: 20),
          label: Text(
            _saving ? 'Saving...' : 'Save Changes',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  // ── Reusable bits ────────────────────────────────────────────────────────

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _cardHeader(IconData icon, String title) {
    return Row(
      children: [
        Icon(icon, color: AppColors.primary, size: 20),
        const SizedBox(width: 10),
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _field({
    required String label,
    required TextEditingController controller,
    TextInputType? keyboardType,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          maxLines: maxLines,
          validator: validator,
          style: const TextStyle(
            fontSize: 14,
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w500,
          ),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: AppColors.inputFill,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppColors.primary, width: 1.5),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppColors.error, width: 1.5),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppColors.error, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  Widget _readOnly(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }

  String _maskAccount(String? account) {
    if (account == null || account.trim().isEmpty) return 'N/A';
    final a = account.trim();
    if (a.length <= 4) return a;
    final last4 = a.substring(a.length - 4);
    return '**** **** $last4';
  }

  // ── Actions ──────────────────────────────────────────────────────────────

  Future<void> _changePhoto() async {
    try {
      // Capture through the guided oval camera (same flow as face enrollment):
      // it shows the alignment ring, auto-captures a centered face, corrects the
      // front-camera 180° flip, and crops to the oval guide box — so the saved
      // profile photo is the framed face, not the full camera frame (ceiling and
      // all). enrollMode relaxes the strict eyes-open/yaw gate to single-face.
      final captured = await SelfieCameraScreen.captureSelfie(
        context,
        title: 'Update Photo',
        enrollMode: true,
      );
      if (!mounted) return;

      File file;
      if (captured is File) {
        file = captured;
      } else if (captured == useImagePickerFallback) {
        // Camera failed to initialise — fall back to the system picker. The
        // SelfieCameraScreen already validated framing when it works; for this
        // fallback path we re-run the single-face check on the picked image.
        final picker = ImagePicker();
        final picked = await picker.pickImage(
          source: ImageSource.camera,
          preferredCameraDevice: CameraDevice.front,
          imageQuality: 80,
          maxWidth: 800,
        );
        if (picked == null) return;
        file = File(picked.path);

        final faceResult = await FaceDetectionHelper.detectFromFile(file);
        if (!faceResult.valid) {
          if (mounted) {
            SnackBarUtils.showSnackBar(
              context,
              faceResult.message ??
                  'Please take a selfie with exactly one face visible.',
              isError: true,
            );
          }
          return;
        }
      } else {
        // User backed out of the camera without capturing.
        return;
      }

      final result = await _authService.updateProfilePhoto(file);
      if (!mounted) return;
      if (result['success'] == true) {
        final url = result['data']?['photoUrl']?.toString();
        setState(() {
          if (url != null && url.isNotEmpty) _photoUrl = url;
          _photoError = false;
          _dirty = true;
        });
        SnackBarUtils.showSnackBar(context, 'Photo updated',
            backgroundColor: AppColors.primary);
      } else {
        SnackBarUtils.showSnackBar(context, 'Photo upload failed',
            isError: true);
      }
    } catch (_) {
      if (mounted) {
        SnackBarUtils.showSnackBar(context, 'Photo upload failed',
            isError: true);
      }
    }
  }

  Future<void> _handleSave() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);

    final payload = <String, dynamic>{
      'name': _nameCtrl.text.trim(),
      'email': _emailCtrl.text.trim(),
      'phone': _phoneCtrl.text.trim(),
    };
    final address = _addressCtrl.text.trim();
    if (address.isNotEmpty) {
      payload['address'] = {'line1': address};
    }

    final result = await _authService.updateProfile(payload);
    if (!mounted) return;

    if (result['success'] == true) {
      SnackBarUtils.showSnackBar(context, 'Profile updated',
          backgroundColor: AppColors.primary);
      Navigator.of(context).pop(true);
    } else {
      setState(() => _saving = false);
      SnackBarUtils.showSnackBar(
        context,
        ErrorMessageUtils.sanitizeForDisplay(
          result['message']?.toString(),
          fallback: 'Failed to update profile',
        ),
        isError: true,
      );
    }
  }
}
