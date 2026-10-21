// Start / End Permission: the live-tracking counterpart to a "Custom" permission request
// (see screens/requests/my_requests_screen.dart RequestPermissionDialog, type 'Custom').
// Mirrors break_screen.dart's selfie/location/face-verification flow closely, against
// services/permission_service.dart instead of BreakService. Shown only when the employee has
// a Custom permission request for today (any status) - see PermissionService.getStatus()
// `hasRequest` - matching the web app's day-by-day gating.
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'selfie_camera_screen.dart' show SelfieCameraScreen, useImagePickerFallback;
import '../../config/app_colors.dart';
import '../../config/app_text_styles.dart';
import '../../config/constants.dart';
import '../../utils/face_enrollment_gate.dart';
import '../../services/auth_service.dart';
import '../../services/permission_service.dart';
import '../../services/face_identity_guard.dart';
import '../../services/geo/address_resolution_service.dart';
import '../../services/geo/accurate_location_helper.dart';
import '../../utils/attendance_selfie_compress.dart';
import '../../utils/error_message_utils.dart';
import '../../utils/snackbar_utils.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_tab_loader.dart';

class PermissionScreen extends StatefulWidget {
  const PermissionScreen({super.key});

  @override
  State<PermissionScreen> createState() => _PermissionScreenState();
}

class _PermissionScreenState extends State<PermissionScreen> {
  final PermissionService _permissionService = PermissionService();
  final AuthService _authService = AuthService();

  PermissionWindowStatus? _status;
  bool _isLoadingStatus = true;
  String? _loadError;

  Position? _position;
  String? _address;
  String? _area;
  String? _city;
  String? _pincode;
  bool _isLocationLoading = true;

  File? _imageFile;
  bool _isSubmitting = false;

  /// Tap instant of "End Permission" once the end request is committed - pins the live
  /// timer so the shown elapsed matches the saved duration, same reasoning as BreakScreen.
  DateTime? _endClickTime;

  bool get _isOnPermission => _status?.isOnPermission ?? false;

  @override
  void initState() {
    super.initState();
    _refreshStatus(silent: true);
    _determinePosition();
    PermissionService.stateRevision.addListener(_onStateChanged);
  }

  @override
  void dispose() {
    PermissionService.stateRevision.removeListener(_onStateChanged);
    super.dispose();
  }

  void _onStateChanged() {
    if (mounted) _refreshStatus(silent: true);
  }

  Future<void> _refreshStatus({bool silent = false}) async {
    if (!silent) setState(() => _isLoadingStatus = true);
    final result = await _permissionService.getStatus();
    if (!mounted) return;
    setState(() {
      _isLoadingStatus = false;
      if (result['success'] == true) {
        _status = result['status'] as PermissionWindowStatus;
        _loadError = null;
      } else if (!silent) {
        _loadError = result['message']?.toString() ?? 'Failed to load permission status.';
      }
    });
  }

  Future<void> _determinePosition() async {
    setState(() => _isLocationLoading = true);
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          SnackBarUtils.showSnackBar(context, 'Location services are disabled.', isError: true);
        }
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        if (mounted) {
          SnackBarUtils.showSnackBar(context, 'Location permission is required for this.', isError: true);
        }
        return;
      }

      final position = await getQuickPositionForUi();
      final resolved = await AddressResolutionService.reverseGeocodeForUi(
        position.latitude,
        position.longitude,
      );

      if (!mounted) return;
      setState(() {
        _position = position;
        _address = resolved?.formattedAddress ?? 'Lat: ${position.latitude}, Lng: ${position.longitude}';
        _area = resolved?.area;
        _city = resolved?.city ?? resolved?.state;
        _pincode = resolved?.pincode;
      });
    } catch (_) {
      if (mounted) setState(() => _address = 'Location found (Address unavailable)');
    } finally {
      if (mounted) setState(() => _isLocationLoading = false);
    }
  }

  String? _locationLabel() =>
      _address ?? (_area != null ? '$_area, ${_city ?? ''}${_pincode != null ? ' $_pincode' : ''}' : null);

  Future<void> _takeSelfie() async {
    var status = await Permission.camera.status;
    if (!status.isGranted) {
      status = await Permission.camera.request();
    }
    if (!status.isGranted) {
      if (!mounted) return;
      SnackBarUtils.showSnackBar(context, 'Camera permission is required.', isError: true);
      return;
    }

    if (!mounted) return;
    if (!await FaceEnrollmentGate.ensureEnrolled(context, actionLabel: 'permission')) {
      return;
    }
    if (!mounted) return;
    final captureResult = await SelfieCameraScreen.captureSelfie(
      context,
      location: _locationLabel(),
      infoText: _isOnPermission
          ? 'Approved budget: ${_status?.allowedMinutes ?? 0} min'
          : 'Remaining today: ${_status?.remainingMinutes ?? 0} min',
      onRefreshLocation: () async {
        await _determinePosition();
        return _address;
      },
      // Same scan-time face-match + buddy-punch identity check as break/punch.
      onCaptured: _verifyFace,
    );

    File? file;
    if (captureResult is File) {
      file = captureResult;
    } else if (identical(captureResult, useImagePickerFallback)) {
      final pickedFile = await ImagePicker().pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
        imageQuality: 85,
        maxWidth: 1024,
      );
      if (pickedFile != null) file = File(pickedFile.path);
    }

    if (file == null || !mounted) return;
    setState(() => _imageFile = file);
    unawaited(_submit());
  }

  /// Scan-time face validation, identical in shape to BreakScreen._verifyBreakFace.
  Future<String?> _verifyFace(File file) async {
    final bytes = await file.readAsBytes();
    final selfie = await AttendanceSelfieCompress.compressRawBytesToDataUrl(bytes);
    if (selfie.isEmpty) return 'Could not process selfie. Please try again.';

    final verifyFuture = AppConstants.enableAttendanceFaceMatching
        ? _authService.verifyFace(selfie)
        : Future.value(<String, dynamic>{'success': true, 'match': true});
    final identityFuture = FaceIdentityGuard.verify(selfie);

    final results = await Future.wait([
      verifyFuture.catchError((_) => <String, dynamic>{
            'success': false,
            'match': false,
            'message': 'Face verification failed. Please try again.',
          }),
      identityFuture,
    ]);

    final matchResult = results[0] as Map<String, dynamic>;
    if (matchResult['success'] != true || matchResult['match'] != true) {
      return matchResult['message']?.toString() ?? 'Face did not match. Please try again.';
    }
    final identity = results[1] as String?;
    return identity;
  }

  Future<String?> _encodeSelfie() async {
    final file = _imageFile;
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    return AttendanceSelfieCompress.compressRawBytesToDataUrl(bytes);
  }

  Future<void> _submit() async {
    if (_position == null) {
      SnackBarUtils.showSnackBar(context, 'Waiting for your location. Please try again in a moment.', isError: true);
      return;
    }
    final clickTime = DateTime.now();
    if (_isOnPermission) setState(() => _endClickTime = clickTime);

    final selfie = AppConstants.enableAttendanceSelfie ? await _encodeSelfie() : '';
    if (selfie == null) {
      if (mounted) setState(() => _endClickTime = null);
      return;
    }

    setState(() => _isSubmitting = true);
    final result = _isOnPermission
        ? await _permissionService.endPermission(
            lat: _position!.latitude,
            lng: _position!.longitude,
            address: _address ?? '',
            area: _area,
            city: _city,
            pincode: _pincode,
            selfie: selfie,
          )
        : await _permissionService.startPermission(
            lat: _position!.latitude,
            lng: _position!.longitude,
            address: _address ?? '',
            area: _area,
            city: _city,
            pincode: _pincode,
            selfie: selfie,
          );

    if (!mounted) return;
    setState(() {
      _isSubmitting = false;
      _imageFile = null;
    });

    if (result['success'] == true) {
      SnackBarUtils.showSnackBar(
        context,
        result['message']?.toString() ?? (_isOnPermission ? 'Permission ended' : 'Permission started'),
      );
      await _refreshStatus();
    } else {
      setState(() => _endClickTime = null);
      SnackBarUtils.showSnackBar(
        context,
        ErrorMessageUtils.sanitizeForDisplay(result['message']?.toString(), fallback: 'Something went wrong.'),
        isError: true,
      );
    }
  }

  Future<void> _onActionTap() async {
    final s = _status;
    if (s == null) return;
    if (!s.hasRequest) {
      // "Apply for Permission": no Custom request for today. Go back to Requests so the
      // employee can create one - starting a window with no approved budget always fails
      // on the server anyway (see staffPermissionService.ts executePermissionStart).
      Navigator.of(context).pop('apply');
      return;
    }
    if (!s.isOnPermission && s.requestStatus == 'Pending') {
      SnackBarUtils.showSnackBar(
        context,
        'Your Custom permission request for today is still awaiting approval.',
      );
      return;
    }
    if (!s.canStartPermission && !s.isOnPermission) {
      SnackBarUtils.showSnackBar(
        context,
        s.remainingMinutes <= 0
            ? 'You have already used your full approved permission time for today.'
            : 'Permission cannot be started right now.',
        isError: true,
      );
      return;
    }
    await _takeSelfie();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Permission')),
      body: _isLoadingStatus
          ? const Center(child: AppTabLoader())
          : _loadError != null
              ? _buildError()
              : SafeArea(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: _buildContent(),
                  ),
                ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 40, color: AppColors.error),
            const SizedBox(height: 12),
            Text(_loadError!, textAlign: TextAlign.center, style: AppTextStyles.bodyMedium),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: () => _refreshStatus(), child: const Text('Retry')),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    final s = _status;
    if (s == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: (s.isOnPermission ? AppColors.success : AppColors.primary).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      s.isOnPermission ? Icons.timer_rounded : Icons.badge_outlined,
                      color: s.isOnPermission ? AppColors.success : AppColors.primaryText,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Custom Permission', style: AppTextStyles.headingSmall),
                        const SizedBox(height: 2),
                        Text(
                          s.hasRequest
                              ? (s.requestStatus == 'Approved'
                                  ? 'Approved for today'
                                  : '${s.requestStatus ?? ''} for today')
                              : 'No request for today',
                          style: AppTextStyles.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (s.hasRequest) ...[
                const SizedBox(height: 16),
                const Divider(height: 1, color: Color(0xFFECEEF1)),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(child: _stat('Approved', '${s.allowedMinutes} min')),
                    Expanded(child: _stat('Used', '${s.totalPermissionMinutes} min')),
                    Expanded(child: _stat('Remaining', '${s.remainingMinutes} min')),
                  ],
                ),
                if (s.excessMinutes > 0) ...[
                  const SizedBox(height: 8),
                  Text(
                    'You exceeded your approved budget by ${s.excessMinutes} min today.',
                    style: AppTextStyles.bodySmall.copyWith(color: AppColors.error),
                  ),
                ],
              ],
              if (s.isOnPermission && s.activeStartAt != null) ...[
                const SizedBox(height: 16),
                _LivePermissionTimer(startTime: s.activeStartAt!, freezeAt: _endClickTime),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (_isLocationLoading) ...[
          const Center(child: Padding(padding: EdgeInsets.all(8), child: AppTabLoader())),
        ] else if (_address != null) ...[
          Row(
            children: [
              const Icon(Icons.location_on_outlined, size: 16, color: AppColors.textSecondary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(_address!, style: AppTextStyles.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
        ElevatedButton.icon(
          onPressed: _isSubmitting ? null : _onActionTap,
          icon: _isSubmitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : Icon(s.isOnPermission ? Icons.stop_circle_outlined : Icons.play_circle_outline),
          label: Text(_isSubmitting ? 'Please wait...' : s.actionLabel),
          style: ElevatedButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            backgroundColor: s.isOnPermission ? AppColors.error : AppColors.primary,
            foregroundColor: AppColors.onPrimary,
          ),
        ),
      ],
    );
  }

  Widget _stat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTextStyles.caption),
        const SizedBox(height: 2),
        Text(value, style: AppTextStyles.headingSmall.copyWith(fontSize: 15)),
      ],
    );
  }
}

/// Live "mm:ss" (or "h:mm:ss") elapsed since [startTime], pinned to [freezeAt] once set -
/// same reasoning as widgets/break_status_card.dart's timer.
class _LivePermissionTimer extends StatefulWidget {
  final DateTime startTime;
  final DateTime? freezeAt;

  const _LivePermissionTimer({required this.startTime, this.freezeAt});

  @override
  State<_LivePermissionTimer> createState() => _LivePermissionTimerState();
}

class _LivePermissionTimerState extends State<_LivePermissionTimer> {
  Timer? _timer;
  Duration _elapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    _tick();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void didUpdateWidget(covariant _LivePermissionTimer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.freezeAt != widget.freezeAt && widget.freezeAt != null) {
      _timer?.cancel();
      _timer = null;
      _tick();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _tick() {
    if (!mounted) return;
    final now = widget.freezeAt ?? DateTime.now();
    final diff = now.difference(widget.startTime);
    setState(() => _elapsed = diff.isNegative ? Duration.zero : diff);
  }

  String _format(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.successBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.fiber_manual_record, size: 10, color: AppColors.success),
          const SizedBox(width: 8),
          const Text('On permission', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.success)),
          const Spacer(),
          Text(
            _format(_elapsed),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.success, fontFeatures: [FontFeature.tabularFigures()]),
          ),
        ],
      ),
    );
  }
}
