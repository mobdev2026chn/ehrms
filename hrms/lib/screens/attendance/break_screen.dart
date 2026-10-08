import 'dart:io';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'selfie_camera_screen.dart'
    show SelfieCameraScreen, useImagePickerFallback;
import '../../config/app_colors.dart';
import '../../config/app_text_styles.dart';
import '../../config/constants.dart';
import '../../utils/face_enrollment_gate.dart';
import '../../models/break_summary.dart';
import '../../services/auth_service.dart';
import '../../services/break_service.dart';
import '../../services/face_identity_guard.dart';
import '../../services/geo/address_resolution_service.dart';
import '../../services/geo/accurate_location_helper.dart';
import '../../utils/attendance_selfie_compress.dart';
import '../../utils/break_datetime_util.dart';
import '../../utils/error_message_utils.dart';
import '../../utils/snackbar_utils.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_tab_loader.dart';
import '../../widgets/break_status_card.dart';

const String _kBreakPermissionDialogShown = 'break_permission_dialog_shown';

class BreakScreen extends StatefulWidget {
  final Map<String, dynamic>? initialBreak;

  const BreakScreen({super.key, this.initialBreak});

  @override
  State<BreakScreen> createState() => _BreakScreenState();
}

class _BreakScreenState extends State<BreakScreen> {
  final BreakService _breakService = BreakService();
  final AuthService _authService = AuthService();

  File? _imageFile;
  Position? _position;
  String? _address;
  String? _area;
  String? _city;
  String? _pincode;
  Map<String, dynamic>? _activeBreak;
  BreakSummary? _breakSummary;

  bool _isLoading = false;
  bool _isBreakLoading = false;
  bool _isLocationLoading = true;
  bool _isDetectingFace = false;
  bool _showStartedBanner = false;

  /// Tap instant of "End Break" once the end request is committed. Pins the
  /// status card's live timer to the same moment recorded as the break end so
  /// the on-screen elapsed matches the saved duration (no upward drift while
  /// the face-verification/network round-trip runs).
  DateTime? _endClickTime;

  bool get _isOnBreak => _activeBreak != null;
  String get _submitLabel => _isOnBreak ? 'End Break' : 'Start Break';
  String get _selfieLabel =>
      _isOnBreak ? 'Take end break selfie' : 'Take start break selfie';

  @override
  void initState() {
    super.initState();
    _activeBreak = widget.initialBreak;
    // Render immediately, then refresh the break state and balance in the
    // background (no full-screen blocking) so the screen opens instantly.
    _refreshCurrentBreak(silent: true);
    _fetchBreakSummary();
    _determinePosition();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _maybeShowPermissionDialog(),
    );
  }

  Future<void> _maybeShowPermissionDialog() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_kBreakPermissionDialogShown) == true || !mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Camera & location'),
        content: const Text(
          'Break start and end require a selfie and your live location, just like attendance.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    await prefs.setBool(_kBreakPermissionDialogShown, true);
  }

  Future<void> _refreshCurrentBreak({bool silent = false}) async {
    if (!silent) setState(() => _isBreakLoading = true);
    final result = await _breakService.getCurrentBreak();
    if (!mounted) return;
    setState(() {
      _isBreakLoading = false;
      if (result['success'] == true) {
        final data = result['data'];
        _activeBreak = data is Map<String, dynamic>
            ? data
            : (data is Map ? Map<String, dynamic>.from(data) : null);
      }
    });
  }

  /// Loads today's break balance (used / allowed / remaining) from the API.
  /// Called on open and after every start/end so the balance is always current.
  Future<void> _fetchBreakSummary() async {
    try {
      final result = await _breakService.getTodayBreakSummary();
      if (!mounted) return;
      if (result['success'] == true && result['data'] is Map) {
        setState(() {
          _breakSummary = BreakSummary.fromJson(
            Map<String, dynamic>.from(result['data'] as Map),
          );
        });
      }
    } catch (_) {
      // Non-fatal: the balance card is simply hidden when unavailable.
    }
  }

  Future<void> _determinePosition() async {
    setState(() => _isLocationLoading = true);
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          SnackBarUtils.showSnackBar(
            context,
            'Location services are disabled.',
            isError: true,
          );
        }
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) {
          SnackBarUtils.showSnackBar(
            context,
            'Location permission is required for breaks.',
            isError: true,
          );
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
        _address =
            resolved?.formattedAddress ??
            'Lat: ${position.latitude}, Lng: ${position.longitude}';
        _area = resolved?.area;
        _city = resolved?.city ?? resolved?.state;
        _pincode = resolved?.pincode;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _address = 'Location found (Address unavailable)');
      }
    } finally {
      if (mounted) {
        setState(() => _isLocationLoading = false);
      }
    }
  }

  Future<void> _takeSelfie() async {
    var status = await Permission.camera.status;
    if (!status.isGranted) {
      status = await Permission.camera.request();
    }
    if (!status.isGranted) {
      if (!mounted) return;
      SnackBarUtils.showSnackBar(
        context,
        'Camera permission is required for breaks.',
        isError: true,
      );
      return;
    }

    final locationStr =
        _address ??
        (_area != null
            ? '$_area, ${_city ?? ''}${_pincode != null ? ' $_pincode' : ''}'
            : null);
    if (!mounted) return;
    // Require one-time face enrollment before the break face check.
    if (!await FaceEnrollmentGate.ensureEnrolled(context, actionLabel: 'break')) {
      return;
    }
    if (!mounted) return;
    final captureResult = await SelfieCameraScreen.captureSelfie(
      context,
      location: locationStr,
      infoText: _remainingBreakText(),
      // Carry the break-policy "processed with Fine" notice onto the camera screen
      // (only when starting) so the employee reliably reads it — parity with the
      // dashboard Break flow.
      noticeText: _isOnBreak ? null : _breakInfoNotice,
      onRefreshLocation: () async {
        await _determinePosition();
        return _address;
      },
      // Face-match + buddy-punch identity check AT SCAN TIME (right after capture),
      // so a wrong/other face is rejected on the camera — not after submitting.
      onCaptured: _verifyBreakFace,
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
      if (pickedFile != null) {
        file = File(pickedFile.path);
      }
    }

    if (file == null || !mounted) return;

    // No client-side ML Kit face gate — server FACE-MATCH (verifyFace) is the single
    // validation; a matched face proceeds.
    setState(() => _imageFile = file);
  }

  Future<String?> _encodeSelfie() async {
    final file = _imageFile;
    if (file == null) return null;
    final imageBytes = await file.readAsBytes();
    return AttendanceSelfieCompress.compressRawBytesToDataUrl(imageBytes);
  }

  /// Scan-time face validation for a break: face-match (1-to-1) + buddy-punch
  /// identity guard (1-to-many). Returns a user-facing error to REJECT (shown on the
  /// camera right after scanning, scan re-arms), or null to accept. Wired via
  /// SelfieCameraScreen.onCaptured, so the check no longer waits for break submit.
  Future<String?> _verifyBreakFace(File file) async {
    final bytes = await file.readAsBytes();
    final selfie = await AttendanceSelfieCompress.compressRawBytesToDataUrl(bytes);
    if (selfie.isEmpty) return 'Could not process selfie. Please try again.';

    final verifyFuture = AppConstants.enableAttendanceFaceMatching
        ? _authService.verifyFace(selfie)
        : Future.value(<String, dynamic>{'success': true, 'match': true});
    final identityFuture = FaceIdentityGuard.verify(selfie);

    final results = await Future.wait([
      // Fail closed: an error must never count as a verified face.
      verifyFuture.catchError((_) => <String, dynamic>{
        'success': false,
        'match': false,
        'message': 'Face verification failed. Please try again.',
      }),
      identityFuture.catchError((_) => const FaceIdentityVerdict(true)),
    ]);

    final verify = results[0] as Map<String, dynamic>;
    if (AppConstants.enableAttendanceFaceMatching) {
      if (verify['match'] != true) {
        final msg = verify['message']?.toString();
        return ErrorMessageUtils.sanitizeForDisplay(
          (msg != null && msg.isNotEmpty && !msg.toLowerCase().contains('matched'))
              ? msg
              : 'Face does not match your registered profile. You are not the registered person for this account.',
        );
      }
    }
    final verdict = results[1] as FaceIdentityVerdict;
    if (!verdict.allow) {
      return verdict.message ??
          'Face does not match this account. You are not the registered person for this account.';
    }
    return null;
  }

  DateTime? _breakStartTime() {
    final raw = _activeBreak?['startTime'] ??
        _activeBreak?['startAt'] ??
        _activeBreak?['breakStartDateTime'] ??
        _activeBreak?['createdAt'];
    final parsed = breakDisplayStartFromApi(raw);
    if (parsed != null) return parsed;
    final summary = _breakSummary;
    if (summary != null) {
      for (final b in summary.breaks) {
        if (b.ongoing && b.startTime != null) return b.startTime;
      }
    }
    return null;
  }

  /// Short balance label for the face-scan camera info pill, e.g.
  /// "Break left: 45m 00s", "Break limit reached", or "Break: Unlimited".
  /// Returns null until the summary loads so the pill stays hidden.
  String? _remainingBreakText() {
    final summary = _breakSummary;
    if (summary == null) return null;
    if (summary.isUnlimited) return 'Break: Unlimited';
    // Remaining is computed from completed breaks only — an ongoing break is not
    // deducted until it has been properly ended.
    final allowedSec = summary.allowedSeconds ?? (summary.allowedMinutes * 60);
    final remainingSec = allowedSec - summary.completedBreakSeconds > 0
        ? allowedSec - summary.completedBreakSeconds
        : 0;
    if (remainingSec <= 0) return 'Break limit reached';
    return 'Break left: ${BreakSummary.formatDuration(remainingSec)}';
  }

  /// Informational policy notice for the current break state. Break actions are
  /// ALWAYS allowed — this tells the employee how the break time is treated.
  /// Prefers the server-authored canonical wording (summary.breakNotice); falls
  /// back to the exact policy strings for older backends. The four scenarios:
  ///  - S1 enabled  + minutes > 0 : "Break allowed for X minutes. Beyond X → Fine."
  ///  - S2 enabled  + minutes = 0 : "Break taken will be considered as Fine. Contact HR."
  ///  - S3 disabled + minutes > 0 : "Break taken will be considered as Fine. Contact HR."
  ///  - S4 disabled + minutes = 0 : "Break is not configured... Fine will be calculated."
  String? get _breakInfoNotice {
    final summary = _breakSummary;
    if (summary == null) return null;
    final serverNotice = summary.breakNotice;
    if (serverNotice != null && serverNotice.trim().isNotEmpty) {
      return serverNotice;
    }
    // Client fallback (exact policy wording) when the backend omits breakNotice.
    if (summary.policyDisabled) {
      return summary.configuredAllowedMinutes > 0
          ? 'Break taken will be considered as Fine.\n'
              'Contact HR.' // S3 (disabled + minutes)
          : 'Break is not configured for your shift. Contact HR.\n'
              'Fine will be calculated.'; // S4 (disabled + no minutes)
    }
    if (summary.policyEnabled && !summary.policyConfigured) {
      return 'Break taken will be considered as Fine.\n'
          'Contact HR.'; // S2 (enabled + no minutes)
    }
    if (summary.policyEnabled && summary.policyConfigured) {
      // S1 (enabled + minutes): within the allowance is free; beyond is fined.
      final mins = summary.configuredAllowedMinutes > 0
          ? summary.configuredAllowedMinutes
          : summary.allowedMinutes;
      if (mins > 0) {
        return 'Break allowed for $mins minutes.\n'
            'Break taken beyond $mins minutes will be considered as Fine.';
      }
    }
    return null;
  }

  /// Breaks are ALWAYS allowed by policy — the Start Break action is never blocked.
  bool get _startBreakBlockedByPolicy => false;

  Future<void> _submit() async {
    if (_isLoading) return;
    // Break actions are ALWAYS allowed (policy). We never block starting a break;
    // the informational notice (_breakInfoNotice) already tells the employee the
    // time will be processed with Fine when the shift is disabled / has no allowance.
    // Capture the break instant at the moment the button is tapped, before the
    // location/selfie/network work below, so loading latency does not push the
    // saved break start/end time forward.
    final DateTime clickInstant = DateTime.now();
    final String clickTime = clickInstant.toUtc().toIso8601String();
    // Ending: pin the status card's live timer to the tap instant immediately,
    // before the selfie/location/network work below, so it stops climbing while
    // that work runs and the shown elapsed equals the recorded break duration
    // (which is computed from this same clickInstant). Every abort path below
    // restores _endClickTime to null so the timer resumes ticking.
    if (_isOnBreak && mounted) {
      setState(() => _endClickTime = clickInstant);
    }
    if (AppConstants.enableAttendanceSelfie && _imageFile == null) {
      if (mounted) setState(() => _endClickTime = null);
      SnackBarUtils.showSnackBar(
        context,
        'Please take a selfie first!',
        isError: true,
      );
      return;
    }
    if (_position == null) {
      await _determinePosition();
      if (!mounted) return;
      if (_position == null) {
        setState(() => _endClickTime = null);
        SnackBarUtils.showSnackBar(
          context,
          'Location is required for breaks.',
          isError: true,
        );
        return;
      }
    }

    // When the in-app selfie step is disabled, submit the break without a selfie
    // (empty string); the backend treats it as optional for breaks.
    final selfie = AppConstants.enableAttendanceSelfie
        ? await _encodeSelfie()
        : '';
    if (selfie == null) {
      if (mounted) setState(() => _endClickTime = null);
      return;
    }

    // NOTE: face-match (verifyFace) + buddy-punch identity guard now run AT SCAN TIME
    // via SelfieCameraScreen.onCaptured (_verifyBreakFace) — a wrong/other face is
    // rejected on the camera, before this submit runs. No re-check here.

    setState(() => _isLoading = true);
    final result = _isOnBreak
        ? await _breakService.endBreak(
            breakId: (_activeBreak?['id'] ?? _activeBreak?['_id'] ?? '').toString(),
            lat: _position!.latitude,
            lng: _position!.longitude,
            address: _address ?? '',
            area: _area,
            city: _city,
            pincode: _pincode,
            selfie: selfie,
            clientTime: clickTime,
          )
        : await _breakService.startBreak(
            lat: _position!.latitude,
            lng: _position!.longitude,
            address: _address ?? '',
            area: _area,
            city: _city,
            pincode: _pincode,
            selfie: selfie,
            clientTime: clickTime,
          );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result['success'] == true) {
      if (_isOnBreak) {
        // Prefer the exact server policy notice (entire-duration fine, or
        // "Allocated break time exceeded by N minutes."). Fall back to the
        // disabled-with-quota wording, then the plain success message.
        final serverNotice = result['notice'];
        final endMsg = (serverNotice is String && serverNotice.trim().isNotEmpty)
            ? serverNotice
            : (_breakSummary?.policyIsDisabledWithQuota == true)
                ? 'Break ended. Your break time will be added to Fine.'
                : 'Break ended successfully';
        SnackBarUtils.showSnackBar(context, endMsg);
        Navigator.of(context).pop(true);
        return;
      }
      setState(() {
        final data = result['data'];
        _activeBreak = data is Map<String, dynamic>
            ? data
            : (data is Map ? Map<String, dynamic>.from(data) : null);
        _imageFile = null;
        _showStartedBanner = true;
      });
      _fetchBreakSummary();
      SnackBarUtils.showSnackBar(context, 'Break started successfully');
      return;
    }

    // End request failed — release the timer freeze so it resumes ticking.
    setState(() => _endClickTime = null);
    final serverBreak = result['data'];
    if (serverBreak is Map) {
      setState(() {
        _activeBreak = Map<String, dynamic>.from(serverBreak);
      });
    }
    SnackBarUtils.showSnackBar(
      context,
      ErrorMessageUtils.sanitizeForDisplay(result['message']?.toString()),
      isError: true,
    );
  }

  static const Color _hairline = Color(0xFFECEEF1);

  /// Shows today's break balance: used / allowed / remaining (second precision).
  /// Hidden until the summary loads. When breaks are unlimited, shows only used.
  Widget _buildBalanceCard() {
    final summary = _breakSummary;
    if (summary == null) return const SizedBox.shrink();

    final unlimited = summary.isUnlimited;
    final allowedSec = summary.allowedSeconds ?? (summary.allowedMinutes * 60);
    // Break time is tallied only once a break has been properly ended, so an
    // ongoing break is excluded from used/remaining here (completed-only).
    final usedSec = summary.completedBreakSeconds;
    final remainingSec =
        allowedSec - usedSec > 0 ? allowedSec - usedSec : 0;
    final exhausted = !unlimited && remainingSec <= 0;
    final accent = exhausted ? AppColors.error : AppColors.primaryText;
    final accentTint =
        exhausted ? AppColors.errorBg : AppColors.primary.withValues(alpha: 0.12);

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: AppCard(
        border: Border.all(
          color: exhausted ? const Color(0xFFFCA5A5) : _hairline,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: accentTint,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.coffee_outlined, size: 20, color: accent),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Break Balance Today',
                    style: AppTextStyles.headingSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  _balanceMetric(
                    'Used',
                    BreakSummary.formatDuration(usedSec),
                    AppColors.textPrimary,
                  ),
                  if (!unlimited) ...[
                    _balanceDivider(),
                    _balanceMetric(
                      'Allowed',
                      BreakSummary.formatDuration(allowedSec),
                      AppColors.textPrimary,
                    ),
                    _balanceDivider(),
                    _balanceMetric(
                      'Remaining',
                      BreakSummary.formatDuration(remainingSec),
                      accent,
                    ),
                  ] else ...[
                    _balanceDivider(),
                    _balanceMetric('Limit', 'Unlimited', AppColors.success),
                  ],
                ],
              ),
            ),
            if (exhausted) ...[
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    size: 16,
                    color: AppColors.error,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'You have used your full break time for today. Further break time may attract a fine.',
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.error,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _balanceMetric(String label, String value, Color valueColor) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: valueColor,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: AppTextStyles.caption
                .copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _balanceDivider() {
    return Container(
      width: 1,
      height: 32,
      color: AppColors.divider,
    );
  }

  Widget _buildSelfieCard() {
    final primary = AppColors.primaryText;
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: _hairline),
      ),
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: _imageFile != null
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                InkWell(
                  onTap: _isDetectingFace ? null : _takeSelfie,
                  child: AspectRatio(
                    aspectRatio: 3 / 4,
                    child: Image.file(_imageFile!, fit: BoxFit.cover),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: IconButton(
                    onPressed: _isDetectingFace ? null : _takeSelfie,
                    icon: Icon(Icons.refresh_rounded, color: primary, size: 26),
                    tooltip: 'Retake',
                  ),
                ),
              ],
            )
          : InkWell(
              onTap: _isDetectingFace ? null : _takeSelfie,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 32,
                  horizontal: 16,
                ),
                child: Column(
                  children: [
                    if (_isDetectingFace)
                      const CircularProgressIndicator(strokeWidth: 2)
                    else
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.camera_alt_outlined,
                          size: 30,
                          color: primary,
                        ),
                      ),
                    const SizedBox(height: 12),
                    Text(
                      _selfieLabel,
                      style: AppTextStyles.headingSmall.copyWith(fontSize: 15),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildLocationCard() {
    return AppCard(
      border: Border.all(color: _hairline),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.location_on_outlined,
              size: 20,
              color: AppColors.primaryText,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _isLocationLoading
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: Text(
                        'Location Fetching...',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Current Location',
                        style: AppTextStyles.caption
                            .copyWith(color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _address ?? 'Unknown location',
                        style: AppTextStyles.bodyMedium
                            .copyWith(fontWeight: FontWeight.w600),
                      ),
                      if (_city != null || _pincode != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            '${_city ?? ''} ${_pincode ?? ''}'.trim(),
                            style: AppTextStyles.bodySmall,
                          ),
                        ),
                    ],
                  ),
          ),
          IconButton(
            onPressed: _determinePosition,
            tooltip: 'Refresh location',
            icon: Icon(Icons.refresh_rounded, color: AppColors.primaryText),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final startTime = _breakStartTime();
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Break')),
      body: _isBreakLoading
          ? const Center(child: AppTabLoader())
          : RefreshIndicator(
              onRefresh: () async {
                await Future.wait([
                  _refreshCurrentBreak(silent: true),
                  _fetchBreakSummary(),
                  _determinePosition(),
                ]);
              },
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildBalanceCard(),
                    if (_isOnBreak) ...[
                      BreakStatusCard(
                        startTime: startTime ?? DateTime.now(),
                        onEndBreak: _submit,
                        isBusy: _isLoading,
                        showSuccessBanner: _showStartedBanner,
                        completedBreakSecondsToday:
                            _breakSummary?.completedBreakSeconds ?? 0,
                        freezeAt: _endClickTime,
                      ),
                      const SizedBox(height: 12),
                      if (!_showStartedBanner)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.brandLight,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.brandBorder),
                          ),
                          child: const Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.free_breakfast_outlined,
                                size: 18,
                                color: AppColors.brandDark,
                              ),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'You are already on break. End that break to start a new one.',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 16),
                    ],
                    // Informational policy notice (exact tooltip wording) when the
                    // break time will be processed with Fine. Break is still allowed —
                    // shown as an info notice, never a block.
                    if (_breakInfoNotice != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.brandLight,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.brandBorder),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.info_outline_rounded,
                              size: 18,
                              color: AppColors.brandDark,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _breakInfoNotice!,
                                style: const TextStyle(
                                  fontSize: 13,
                                  height: 1.4,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.brandDark,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (AppConstants.enableAttendanceSelfie) ...[
                      _buildSelfieCard(),
                      const SizedBox(height: 16),
                    ],
                    _buildLocationCard(),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: (_isLoading || _startBreakBlockedByPolicy)
                          ? null
                          : _submit,
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                      ),
                      child: _isLoading
                          ? SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.onPrimary,
                              ),
                            )
                          : Text(_submitLabel),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
