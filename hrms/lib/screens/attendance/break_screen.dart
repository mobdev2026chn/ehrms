import 'dart:io';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'selfie_camera_screen.dart'
    show SelfieCameraScreen, useImagePickerFallback;
import '../../config/app_colors.dart';
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
    if (selfie.isEmpty) return null;
    if (AppConstants.enableAttendanceFaceMatching) {
      try {
        final verify = await _authService.verifyFace(selfie);
        if (verify['success'] != true || verify['match'] != true) {
          return ErrorMessageUtils.sanitizeForDisplay(
            verify['message']?.toString() ?? 'Face not matching. Please try again.',
          );
        }
      } catch (_) {
        return 'Face verification failed. Please try again.';
      }
    }
    final verdict = await FaceIdentityGuard.verify(selfie);
    if (!verdict.allow) return verdict.message ?? 'Face identity check failed.';
    return null;
  }

  DateTime? _breakStartTime() {
    return breakDisplayStartFromApi(_activeBreak?['startTime']);
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

  /// Informational policy notice for the current break state, or null when breaks
  /// are normally configured (enabled + allowance). Break actions are ALWAYS
  /// allowed — this is purely informational and tells the employee the break time
  /// will be processed with Fine. Prefers the server-authored canonical wording
  /// (summary.breakNotice); falls back to the exact policy strings for older
  /// backends that don't send it. The four scenarios:
  ///  - disabled + quota > 0  (S3): "Break is disabled..."
  ///  - disabled + quota = 0  (S4): "Break is not configured..."
  ///  - enabled  + quota = 0  (S2): "Break is not configured..."
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
          ? 'Break is disabled for your shift.\n'
              'Contact HR to enable.\n'
              'Break duration will be processed with Fine.' // S3
          : 'Break is not configured for your shift. Contact HR.\n'
              'Break duration will be processed with Fine.'; // S4
    }
    if (summary.policyEnabled && !summary.policyConfigured) {
      return 'Break is not configured for your shift. Contact HR.\n'
          'Break duration will be processed with Fine.'; // S2
    }
    return null; // S1 normal
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
    if (_imageFile == null) {
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

    final selfie = await _encodeSelfie();
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
            breakId: _activeBreak!['id'].toString(),
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
    final accent = exhausted ? Colors.red.shade600 : AppColors.primary;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              accent.withValues(alpha: 0.12),
              accent.withValues(alpha: 0.04),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: accent.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.coffee_rounded, size: 18, color: accent),
                const SizedBox(width: 8),
                const Text(
                  'Break Balance Today',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                _balanceMetric(
                  'Used',
                  BreakSummary.formatDuration(usedSec),
                  Colors.black87,
                ),
                if (!unlimited) ...[
                  _balanceDivider(),
                  _balanceMetric(
                    'Allowed',
                    BreakSummary.formatDuration(allowedSec),
                    Colors.black87,
                  ),
                  _balanceDivider(),
                  _balanceMetric(
                    'Remaining',
                    BreakSummary.formatDuration(remainingSec),
                    accent,
                  ),
                ] else ...[
                  _balanceDivider(),
                  _balanceMetric('Limit', 'Unlimited', Colors.green.shade700),
                ],
              ],
            ),
            if (exhausted) ...[
              const SizedBox(height: 10),
              Text(
                'You have used your full break time for today. Further break time may attract a fine.',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.red.shade700,
                  fontWeight: FontWeight.w500,
                ),
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
              fontWeight: FontWeight.bold,
              color: valueColor,
            ),
          ),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _balanceDivider() {
    return Container(
      width: 1,
      height: 32,
      color: Colors.grey.withValues(alpha: 0.25),
    );
  }

  Widget _buildSelfieCard() {
    final primary = Theme.of(context).colorScheme.primary;
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                  padding: const EdgeInsets.all(12),
                  child: IconButton(
                    onPressed: _isDetectingFace ? null : _takeSelfie,
                    icon: Icon(Icons.refresh_rounded, color: primary, size: 28),
                    tooltip: 'Retake',
                  ),
                ),
              ],
            )
          : InkWell(
              onTap: _isDetectingFace ? null : _takeSelfie,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 28,
                  horizontal: 16,
                ),
                child: Column(
                  children: [
                    if (_isDetectingFace)
                      const CircularProgressIndicator(strokeWidth: 2)
                    else
                      Icon(Icons.camera_alt_rounded, size: 48, color: primary),
                    const SizedBox(height: 12),
                    Text(
                      _selfieLabel,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildLocationCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      child: Row(
        children: [
          Icon(Icons.location_on, color: AppColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: _isLocationLoading
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: Text(
                        'Location Fetching...',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Current Location',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _address ?? 'Unknown location',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      if (_city != null || _pincode != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            '${_city ?? ''} ${_pincode ?? ''}'.trim(),
                          ),
                        ),
                    ],
                  ),
          ),
          IconButton(
            onPressed: _determinePosition,
            icon: Icon(Icons.refresh, color: AppColors.primary),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final startTime = _breakStartTime();
    return Scaffold(
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
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildBalanceCard(),
                    if (_isOnBreak && startTime != null) ...[
                      BreakStatusCard(
                        startTime: startTime,
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
                            color: Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.orange.shade200),
                          ),
                          child: const Text(
                            'You are already on break. End that break to start a new one.',
                            style: TextStyle(fontWeight: FontWeight.w500),
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
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.orange.shade300),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.info_outline, size: 16, color: Colors.orange.shade700),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _breakInfoNotice!,
                                style: TextStyle(
                                  fontWeight: FontWeight.w500,
                                  color: Colors.orange.shade800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    _buildSelfieCard(),
                    const SizedBox(height: 20),
                    _buildLocationCard(),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: (_isLoading || _startBreakBlockedByPolicy)
                          ? null
                          : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              _submitLabel,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
