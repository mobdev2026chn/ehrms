import 'dart:io';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'selfie_camera_screen.dart'
    show SelfieCameraScreen, useImagePickerFallback;
import '../../config/app_colors.dart';
import '../../models/break_summary.dart';
import '../../services/break_service.dart';
import '../../services/geo/address_resolution_service.dart';
import '../../services/geo/accurate_location_helper.dart';
import '../../utils/attendance_selfie_compress.dart';
import '../../utils/break_datetime_util.dart';
import '../../utils/error_message_utils.dart';
import '../../utils/face_detection_helper.dart';
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
    final captureResult = await SelfieCameraScreen.captureSelfie(
      context,
      location: locationStr,
      infoText: _remainingBreakText(),
      onRefreshLocation: () async {
        await _determinePosition();
        return _address;
      },
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

    setState(() => _isDetectingFace = true);
    final result = await FaceDetectionHelper.detectFromFile(file);
    if (!mounted) return;
    setState(() => _isDetectingFace = false);

    if (!result.valid) {
      SnackBarUtils.showSnackBar(
        context,
        result.message ?? 'Please keep exactly one face visible.',
        isError: true,
      );
      return;
    }

    setState(() => _imageFile = file);
  }

  Future<String?> _encodeSelfie() async {
    final file = _imageFile;
    if (file == null) return null;
    final imageBytes = await file.readAsBytes();
    return AttendanceSelfieCompress.compressRawBytesToDataUrl(imageBytes);
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
    final remainingSec =
        summary.remainingSeconds ?? (summary.remainingMin ?? 0) * 60;
    if (remainingSec <= 0) return 'Break limit reached';
    return 'Break left: ${BreakSummary.formatDuration(remainingSec)}';
  }

  /// Reason a NEW break may not be started because of the shift's break policy,
  /// or null when starting is allowed. Ending an already-running break is always
  /// allowed. Three distinct policy states are surfaced:
  ///  - disabled with a quota configured → "disabled, contact HR to enable"
  ///  - disabled with no quota / enabled with no quota → "not configured"
  String? get _breakPolicyBlockMessage {
    if (_isOnBreak) return null;
    final summary = _breakSummary;
    if (summary == null) return null;
    if (summary.policyDisabled) {
      return summary.configuredAllowedMinutes > 0
          ? 'Break is disabled for your shift. Contact HR to enable.'
          : 'Break is not configured for your shift. Contact HR.';
    }
    if (summary.policyEnabled && !summary.policyConfigured) {
      return 'Break is not configured for your shift. Contact HR.';
    }
    return null;
  }

  /// Whether starting a NEW break is blocked by the shift's break policy.
  bool get _startBreakBlockedByPolicy => _breakPolicyBlockMessage != null;

  Future<void> _submit() async {
    if (_isLoading) return;
    // The shift may have breaks turned off — block starting a new one up front
    // (the backend enforces this too), but never block ending an active break.
    final policyBlock = _breakPolicyBlockMessage;
    if (policyBlock != null) {
      SnackBarUtils.showSnackBar(
        context,
        policyBlock,
        isError: true,
      );
      return;
    }
    // Capture the break instant at the moment the button is tapped, before the
    // location/selfie/network work below, so loading latency does not push the
    // saved break start/end time forward.
    final String clickTime = DateTime.now().toUtc().toIso8601String();
    if (_imageFile == null) {
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
        SnackBarUtils.showSnackBar(
          context,
          'Location is required for breaks.',
          isError: true,
        );
        return;
      }
    }

    final selfie = await _encodeSelfie();
    if (selfie == null) return;

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
        SnackBarUtils.showSnackBar(context, 'Break ended successfully');
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
    final remainingSec = summary.remainingSeconds ?? 0;
    final allowedSec = summary.allowedSeconds ?? (summary.allowedMinutes * 60);
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
                  BreakSummary.formatDuration(summary.totalBreakSeconds),
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
                    if (_breakPolicyBlockMessage != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.orange.shade200),
                        ),
                        child: Text(
                          _breakPolicyBlockMessage!,
                          style: const TextStyle(fontWeight: FontWeight.w500),
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
