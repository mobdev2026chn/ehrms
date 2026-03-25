import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'selfie_camera_screen.dart' show SelfieCameraScreen, useImagePickerFallback;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/app_colors.dart';
import '../../config/constants.dart';
import '../../services/auth_service.dart';
import '../../services/attendance_template_store.dart';
import '../../services/geo/address_resolution_service.dart';
import '../../services/geo/accurate_location_helper.dart';
import '../../services/geo/location_service.dart';
import '../../services/geo/movement_classification_service.dart';
import '../../services/presence_tracking_service.dart';
import '../../bloc/attendance/attendance_bloc.dart';
import '../../utils/face_detection_helper.dart';
import '../../utils/request_guard.dart';
import '../../utils/snackbar_utils.dart';
import '../../utils/error_message_utils.dart';
import '../../widgets/app_tab_loader.dart';
import '../../widgets/attendance_success_overlay.dart';

class SelfieCheckInScreen extends StatefulWidget {
  final Map<String, dynamic>? template;
  final bool? isCheckedIn;
  final bool? isCompleted;

  const SelfieCheckInScreen({
    super.key,
    this.template,
    this.isCheckedIn,
    this.isCompleted,
  });

  @override
  State<SelfieCheckInScreen> createState() => _SelfieCheckInScreenState();
}

const String _kAttendancePermissionDialogShown =
    'attendance_permission_dialog_shown';

class _SelfieCheckInScreenState extends State<SelfieCheckInScreen> {
  final AuthService _authService = AuthService();

  /// Template from widget or loaded from stored details (SharedPrefs).
  Map<String, dynamic>? _effectiveTemplate;

  File? _imageFile;
  String? _address;
  String? _area;
  String? _city;
  String? _pincode;
  Position? _position;

  bool _isLoading = false;
  bool _isLocationLoading = true;
  bool _isDetectingFace = false;

  // Attendance State
  Map<String, dynamic>? _branchData; // New branch data for 'Assigned Office'
  bool _isCheckedIn = false;
  bool _isCompleted = false; // Punched out already
  bool _isStatusLoading = true;

  // Half-day leave: check-in/check-out allowed by session (from backend)
  bool _checkInAllowed = true;
  bool _checkOutAllowed = true;
  String? _halfDayLeaveMessage;
  String? _halfDayType; // "First Half Day" | "Second Half Day" for snackbar

  /// Prevents double-tap on Check In / Check Out (429 and "server busy").
  final RequestGuard _submitGuard = RequestGuard(
    cooldown: const Duration(milliseconds: 1500),
  );

  @override
  void initState() {
    super.initState();
    _isCheckedIn = widget.isCheckedIn ?? false;
    _isCompleted = widget.isCompleted ?? false;
    if (widget.isCheckedIn != null || widget.isCompleted != null) {
      _isStatusLoading = false;
    }

    _loadEffectiveTemplate().then((_) {
      if (mounted) {
        _determinePositionFromTemplate();
      }
    });
    _fetchAttendanceStatus();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _maybeShowPermissionDialog(),
    );
  }

  Future<void> _loadEffectiveTemplate() async {
    if (widget.template != null) {
      setState(() => _effectiveTemplate = widget.template);
      return;
    }
    final stored = await AttendanceTemplateStore.loadTemplateDetails();
    if (mounted && stored != null) {
      final t = stored['template'];
      setState(() => _effectiveTemplate =
          t is Map<String, dynamic> ? t : (t is Map ? Map<String, dynamic>.from(t) : null));
    }
  }

  void _determinePositionFromTemplate() {
    final template = _effectiveTemplate ?? widget.template;
    final requireGeolocation = template?['requireGeolocation'] ?? true;
    if (requireGeolocation) {
      _determinePosition();
    } else {
      setState(() => _isLocationLoading = false);
    }
  }

  Map<String, dynamic>? get _template => _effectiveTemplate ?? widget.template;

  Future<void> _maybeShowPermissionDialog() async {
    final requireSelfie = _template?['requireSelfie'] ?? true;
    final requireGeolocation = _template?['requireGeolocation'] ?? true;
    if (!requireSelfie && !requireGeolocation) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_kAttendancePermissionDialogShown) == true) return;
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Material(
          color: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 340),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.camera_alt_rounded,
                    size: 48,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Camera & location',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.camera_alt_rounded,
                      size: 20,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Camera is used for your attendance selfie.',
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.4,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.location_on_rounded,
                      size: 20,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Location is used to record your check-in and check-out place.',
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.4,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: Material(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      onTap: () => Navigator.of(context).pop(),
                      borderRadius: BorderRadius.circular(12),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 14),
                        child: Text(
                          'OK',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await prefs.setBool(_kAttendancePermissionDialogShown, true);
  }

  void _fetchAttendanceStatus([DateTime? date]) {
    final targetDate = date ?? DateTime.now();
    final formattedDate = targetDate.toIso8601String().split('T')[0];
    setState(() => _isStatusLoading = true);
    context.read<AttendanceBloc>().add(
      AttendanceStatusRequested(formattedDate),
    );
  }

  Future<void> _onAttendanceStateChanged(BuildContext context, AttendanceState state) async {
    if (state is AttendanceStatusLoaded) {
      if (!mounted) return;
      setState(() {
        _branchData = state.branchData;
        _checkInAllowed = state.checkInAllowed;
        _checkOutAllowed = state.checkOutAllowed;
        _halfDayLeaveMessage = state.halfDayLeaveMessage;
        _halfDayType = state.halfDayType;
        _isCheckedIn = state.isCheckedIn;
        _isCompleted = state.isCompleted;
        _isStatusLoading = false;
      });
    } else if (state is AttendanceFailure) {
      if (!mounted) return;
      setState(() {
        _isStatusLoading = false;
        _isLoading = false;
      });
      final msg = state.message;
      if (msg.contains('Salary not configured')) {
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: Text('Cannot Check In'),
            content: Text(msg),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('OK'),
              ),
            ],
          ),
        );
      } else {
        SnackBarUtils.showSnackBar(context, ErrorMessageUtils.sanitizeForDisplay(msg), isError: true);
      }
    } else if (state is AttendanceCheckInSuccess) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      if (Platform.isAndroid && !await Permission.locationAlways.isGranted) {
        await LocationService.showBackgroundLocationDisclosureAndRequest(
          context,
          title: 'Background location for attendance',
          message:
              'To continue recording your attendance location while the app is in the background or the screen is off, this app needs "Allow all the time" location access.\n\n'
              'Your location is used only for attendance presence tracking and is sent to your organization\'s HRMS server.',
        );
      }
      await PresenceTrackingService().ensureTrackingIfPunchedIn(true);
      final userName = await _authService.getCurrentUserName();
      if (!mounted) return;
      final overlayContent = _getCheckInOverlayEmojiAndMessage(userName);
      await AttendanceSuccessOverlay.show(
        context,
        isCheckIn: true,
        userName: userName,
        checkInEmoji: overlayContent.emoji,
        checkInMessage: overlayContent.message,
        snackbarMessage: overlayContent.message,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } else if (state is AttendanceCheckOutSuccess) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      PresenceTrackingService().stopTracking();
      final userName = await _authService.getCurrentUserName();
      if (!mounted) return;
      await AttendanceSuccessOverlay.show(
        context,
        isCheckIn: false,
        userName: userName,
        checkOutEmoji: '😊',
        checkOutMessage: 'Checkout success!',
        snackbarMessage: 'Checkout success!',
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } else if (state is AttendanceLoadInProgress && _isLoading) {
      // Submitting check-in/out: keep _isLoading true (already set in _submitAttendance).
    } else if (state is AttendanceLoadInProgress) {
      // Loading status: _isStatusLoading already set in _fetchAttendanceStatus.
    }
  }

  Future<void> _determinePosition() async {
    setState(() => _isLocationLoading = true);
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        SnackBarUtils.showSnackBar(
          context,
          'Location services are disabled.',
          isError: true,
        );
      }

      setState(() => _isLocationLoading = false);
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (mounted) {
          SnackBarUtils.showSnackBar(
            context,
            'Location permissions are denied',
            isError: true,
          );
        }

        setState(() => _isLocationLoading = false);
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      if (mounted) {
        SnackBarUtils.showSnackBar(
          context,
          'Location permissions are permanently denied.',
          isError: true,
        );
      }

      setState(() => _isLocationLoading = false);
      return;
    }

    try {
      final position = await getQuickPositionForUi();

      _position = position;
      MovementClassificationService().addLocationAndClassify(
        lat: position.latitude,
        lng: position.longitude,
        time: DateTime.now(),
        accuracyM: position.accuracy,
      );

      final resolved = await AddressResolutionService.reverseGeocodeForUi(
        position.latitude,
        position.longitude,
      );

      if (resolved != null) {
        _area = resolved.area;
        _city = resolved.city ?? resolved.state;
        _pincode = resolved.pincode;
        _address = resolved.formattedAddress;
      } else {
        _address = 'Lat: ${position.latitude}, Lng: ${position.longitude}';
      }
    } catch (e) {
      _address = 'Location found (Address unavailable)';
    } finally {
      if (mounted) {
        if (_position != null) SnackBarUtils.dismiss();
        setState(() => _isLocationLoading = false);
      }
    }
  }

  String _resolveAttendanceMovementType() {
    final position = _position;
    if (position == null) return kMovementStop;

    return MovementClassificationService().classifyFromPosition(position);
  }

  Future<void> _takeSelfie() async {
    var status = await Permission.camera.status;
    if (!status.isGranted) {
      status = await Permission.camera.request();
      if (!mounted) return;
      if (!status.isGranted) {
        SnackBarUtils.showSnackBar(
          context,
          'Camera permission is needed to take a selfie. Please allow in app settings.',
          isError: true,
        );
        return;
      }
    }

    // In-app camera (live preview, location+refresh, no switch); fallback to system camera if init fails
    final locationStr = _address ??
        (_area != null ? '$_area, $_city${_pincode != null ? ' $_pincode' : ''}' : null);
    final captureResult = await SelfieCameraScreen.captureSelfie(
      context,
      location: locationStr,
      onRefreshLocation: () async {
        await _determinePosition();
        if (!mounted) return null;
        return _address ??
            (_area != null ? '$_area, $_city${_pincode != null ? ' $_pincode' : ''}' : null);
      },
    );
    File? file;
    if (captureResult is File) {
      file = captureResult;
    } else if (identical(captureResult, useImagePickerFallback)) {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
        imageQuality: 85,
        maxWidth: 1024,
      );
      if (pickedFile != null && mounted) file = File(pickedFile.path);
    }
    if (file == null || !mounted) return;

    setState(() => _isDetectingFace = true);
    final result = await FaceDetectionHelper.detectFromFile(file);
    if (!mounted) return;
    setState(() => _isDetectingFace = false);

    if (!result.valid) {
      SnackBarUtils.showSnackBar(
        context,
        result.message ?? 'Please take a selfie with exactly one face visible.',
        isError: true,
      );
      return;
    }

    setState(() => _imageFile = file);
  }

  Future<void> _showWarningDialog(List<dynamic> warnings) async {
    if (warnings.isEmpty) return;

    // Get the first warning message
    final warning = warnings[0];
    final message = warning['message'] ?? 'Warning';

    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: AppColors.primary, size: 28),
              const SizedBox(width: 8),
              Text('Notice'),
            ],
          ),
          content: Text(message),
          actions: <Widget>[
            TextButton(
              child: Text(
                'OK',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  void _showHalfDayNotAllowedSnackbar() {
    final bool isSecond = _halfDayType == 'Second Half Day';
    final bool isFirst = _halfDayType == 'First Half Day';
    final String half = isSecond ? 'second' : (isFirst ? 'first' : '');
    final String action = _isCheckedIn ? 'check-out' : 'check-in';
    final String msg = half.isNotEmpty
        ? 'Not allowed $action. You are on leave on $half half.'
        : (_halfDayLeaveMessage ?? 'Not allowed $action at this time.');
    SnackBarUtils.showSnackBar(context, msg, isError: true);
  }

  Future<void> _submitAttendance() async {
    if (!_submitGuard.allow) return; // Throttle double-tap to avoid 429
    if (_isCheckInDisabled || _isCheckOutDisabled) {
      _showHalfDayNotAllowedSnackbar();
      return;
    }
    final requireSelfie = _template?['requireSelfie'] ?? true;
    final bool requireGeolocation =
        _template?['requireGeolocation'] ?? true;
    if (requireSelfie && _imageFile == null) {
      SnackBarUtils.showSnackBar(
        context,
        'Please take a selfie first!',
        isError: true,
      );

      return;
    }

    if (requireGeolocation && _position == null) {
      // Re-trigger location if missing and required
      _determinePosition();

      SnackBarUtils.showSnackBar(
        context,
        'Waiting for location...',
        backgroundColor: Colors.orange,
      );

      return;
    }

    setState(() => _isLoading = true);

    // Convert image to Base64
    String? selfiePayload;
    if (_imageFile != null) {
      List<int> imageBytes = await _imageFile!.readAsBytes();
      String base64Image = base64Encode(imageBytes);
      selfiePayload = 'data:image/jpeg;base64,$base64Image';
    }

    // Verify selfie against profile photo when selfie is required (face matching disabled via constant)
    if (AppConstants.enableAttendanceFaceMatching &&
        requireSelfie &&
        selfiePayload != null &&
        selfiePayload.isNotEmpty) {
      Map<String, dynamic> verify;
      try {
        verify = await _authService.verifyFace(selfiePayload);
      } catch (_) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        SnackBarUtils.showSnackBar(
          context,
          'Face verification failed. Please try again.',
          isError: true,
        );
        return;
      }
      if (!mounted) return;
      if (!verify['success'] || verify['match'] != true) {
        setState(() => _isLoading = false);
        final msg =
            verify['message']?.toString() ??
            'Face not matching. Please try again.';
        SnackBarUtils.showSnackBar(context, ErrorMessageUtils.sanitizeForDisplay(msg), isError: true);
        return;
      }
      SnackBarUtils.showSnackBar(
        context,
        'Photo matched',
        backgroundColor: AppColors.primary,
      );
    }

    final movementType = _resolveAttendanceMovementType();

    if (!mounted) return;
    if (_isCheckedIn) {
      context.read<AttendanceBloc>().add(
        AttendanceCheckOutRequested(
          lat: _position?.latitude ?? 0.0,
          lng: _position?.longitude ?? 0.0,
          address: _address ?? '',
          area: _area,
          city: _city,
          pincode: _pincode,
          selfie: selfiePayload,
          movementType: movementType,
        ),
      );
    } else {
      context.read<AttendanceBloc>().add(
        AttendanceCheckInRequested(
          lat: _position?.latitude ?? 0.0,
          lng: _position?.longitude ?? 0.0,
          address: _address ?? '',
          area: _area,
          city: _city,
          pincode: _pincode,
          selfie: selfiePayload,
          movementType: movementType,
        ),
      );
    }
    // Success/failure handled in BlocListener (_onAttendanceStateChanged).
  }

  bool get _isCheckInDisabled => !_isCheckedIn && !_checkInAllowed;
  bool get _isCheckOutDisabled => _isCheckedIn && !_checkOutAllowed;
  bool get _isButtonDisabled =>
      _isCompleted ||
      _isLoading ||
      _isStatusLoading ||
      _isCheckInDisabled ||
      _isCheckOutDisabled;

  String get _shiftStartTime =>
      _template?['shiftStartTime']?.toString().trim() ?? '09:00';
  String get _shiftEndTime =>
      widget.template?['shiftEndTime']?.toString().trim() ?? '17:00';

  /// Grace period in minutes from template (for check-in overlay emoji).
  int _getGracePeriodMinutes() {
    final template = _template;
    if (template == null) return 15;
    final flat = template['gracePeriodMinutes'];
    if (flat != null) {
      if (flat is int) return flat;
      final parsed = int.tryParse(flat.toString());
      if (parsed != null) return parsed;
    }
    try {
      final shifts = template['settings']?['attendance']?['shifts'] as List?;
      if (shifts != null && shifts.isNotEmpty) {
        final shift = shifts[0] as Map<String, dynamic>?;
        final graceTime = shift?['graceTime'];
        if (graceTime is Map) {
          final value = graceTime['value'];
          final unit = graceTime['unit']?.toString().toLowerCase();
          final v = value is int ? value : int.tryParse(value?.toString() ?? '');
          if (v != null) {
            if (unit == 'hours') return v * 60;
            return v;
          }
        }
      }
    } catch (_) {}
    return 15;
  }

  /// Returns (emoji, message) for check-in success overlay: before shift = very happy, after shift = happy, in grace = somewhat sad.
  ({String emoji, String message}) _getCheckInOverlayEmojiAndMessage(String userName) {
    final shiftStr = _shiftStartTime;
    final parts = shiftStr.split(':').map((s) => int.tryParse(s) ?? 0).toList();
    final shiftHour = parts.isNotEmpty ? parts[0] : 9;
    final shiftMin = parts.length > 1 ? parts[1] : 0;
    final now = DateTime.now();
    final shiftStart = DateTime(now.year, now.month, now.day, shiftHour, shiftMin);
    final graceMinutes = _getGracePeriodMinutes();
    final graceEnd = shiftStart.add(Duration(minutes: graceMinutes));

    if (now.isBefore(shiftStart)) {
      return (emoji: '😄', message: "You're early! Have a great day!");
    }
    if (!now.isAfter(graceEnd)) {
      return (emoji: '😕', message: 'You checked in within grace time.');
    }
    // Late (after grace): sad emoji, snackbar "You have checked in."
    return (emoji: '😕', message: 'You have checked in.');
  }

  Widget _buildWorkingHoursCard({
    required IconData icon,
    required String time,
    required String label,
    required ColorScheme colorScheme,
  }) {
    final primary = colorScheme.primary;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outline),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: primary.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 20, color: primary),
          ),
          const SizedBox(height: 12),
          Text(
            time,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AttendanceBloc, AttendanceState>(
      listener: _onAttendanceStateChanged,
      child: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    // Determine button text and state
    String buttonText = 'Check In';
    Color buttonColor = AppColors.primary;
    if (_isCompleted) {
      buttonText = 'Attendance Completed';
      buttonColor = Colors.grey;
    } else if (_isCheckedIn) {
      buttonText = 'Check Out';
      buttonColor = AppColors.primary;
    }

    final colorScheme = Theme.of(context).colorScheme;
    final primary = colorScheme.primary;

    return Scaffold(
      appBar: AppBar(title: const Text('Mark attendance')),
      body: RefreshIndicator(
        onRefresh: () async {
          _fetchAttendanceStatus();
          await context
              .read<AttendanceBloc>()
              .stream
              .where(
                (s) => s is AttendanceStatusLoaded || s is AttendanceFailure,
              )
              .first;
          if (!mounted) return;
          if (_template?['requireGeolocation'] ?? true) {
            await _determinePosition();
          }
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: LayoutBuilder(
            builder: (context, constraints) {
              const padding = 12.0;
              return Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: padding,
                  vertical: 16,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Full-width card with camera icon or selfie photo + retake
                    if (widget.template?['requireSelfie'] ?? true) ...[
                      Card(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: _imageFile != null
                            ? Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  InkWell(
                                    onTap: (_isCompleted || _isDetectingFace)
                                        ? null
                                        : _takeSelfie,
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: AspectRatio(
                                        aspectRatio: 3 / 4,
                                        child: Image.file(
                                          _imageFile!,
                                          fit: BoxFit.cover,
                                          width: double.infinity,
                                        ),
                                      ),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: IconButton(
                                      onPressed: (_isCompleted || _isDetectingFace)
                                          ? null
                                          : _takeSelfie,
                                      icon: Icon(
                                        Icons.refresh_rounded,
                                        color: primary,
                                        size: 28,
                                      ),
                                      tooltip: 'Retake',
                                    ),
                                  ),
                                ],
                              )
                            : InkWell(
                                onTap: (_isCompleted || _isDetectingFace)
                                    ? null
                                    : _takeSelfie,
                                borderRadius: BorderRadius.circular(12),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 24,
                                    horizontal: 16,
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      if (_isDetectingFace)
                                        SizedBox(
                                          height: 40,
                                          width: 40,
                                          child: CircularProgressIndicator(
                                            color: primary,
                                            strokeWidth: 2,
                                          ),
                                        )
                                      else
                                        Icon(
                                          Icons.camera_alt_rounded,
                                          size: 48,
                                          color: primary,
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                      ),
                      const SizedBox(height: 24),
                    ],

                    // Working hours cards
                    Row(
                      children: [
                        Expanded(
                          child: _buildWorkingHoursCard(
                            icon: Icons.login_rounded,
                            time: _shiftStartTime,
                            label: 'To Work Time',
                            colorScheme: colorScheme,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildWorkingHoursCard(
                            icon: Icons.logout_rounded,
                            time: _shiftEndTime,
                            label: 'Check Out Time',
                            colorScheme: colorScheme,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Branch Info Card (compact)
                    if (_branchData != null) ...[
                      Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: colorScheme.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: colorScheme.outline),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.business_rounded,
                                  color: AppColors.primary,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Assigned Office',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                const Spacer(),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        color: primary.withOpacity(0.15),
                                        shape: BoxShape.circle,
                                      ),
                                      alignment: Alignment.center,
                                      child: Text(
                                        _shiftStartTime,
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.w600,
                                          color: colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        color: primary.withOpacity(0.15),
                                        shape: BoxShape.circle,
                                      ),
                                      alignment: Alignment.center,
                                      child: Text(
                                        _shiftEndTime,
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.w600,
                                          color: colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _branchData!['name'] ?? 'Main Branch',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _branchData!['address'] ?? '',
                              style: TextStyle(
                                fontSize: 13,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],

                    // Location Info
                    if (_template?['requireGeolocation'] ?? true) ...[
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerLowest,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: colorScheme.outline),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.location_on, color: AppColors.primary),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Current Location',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  _isLocationLoading
                                      ? const SizedBox(
                                          height: 15,
                                          width: 15,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              _address ?? 'Unknown Location',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: AppColors.textPrimary,
                                                fontSize: 14,
                                              ),
                                            ),
                                            if (_city != null ||
                                                _pincode != null)
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                  top: 4.0,
                                                ),
                                                child: Text(
                                                  '${_city ?? ''} - ${_pincode ?? ''}',
                                                  style: TextStyle(
                                                    fontSize: 13,
                                                    color:
                                                        colorScheme.onSurfaceVariant,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: Icon(
                                Icons.refresh,
                                color: AppColors.primary,
                              ),
                              onPressed: _determinePosition,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),
                    ],

                    // Half-day leave message when check-in/check-out is blocked
                    if (_halfDayLeaveMessage != null &&
                        (_isCheckInDisabled || _isCheckOutDisabled)) ...[
                      Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.orange.shade200),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              color: Colors.orange.shade700,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _halfDayLeaveMessage!,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.orange.shade900,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    // Submit Button
                    if (_isStatusLoading && widget.isCheckedIn == null)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: AppTabLoader(),
                        ),
                      )
                    else
                      ElevatedButton(
                        onPressed: () {
                          if (_isButtonDisabled) {
                            if (_isCheckInDisabled || _isCheckOutDisabled) {
                              _showHalfDayNotAllowedSnackbar();
                            }
                            return;
                          }
                          _submitAttendance();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _isButtonDisabled
                              ? Colors.grey
                              : buttonColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 2,
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                height: 24,
                                width: 24,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    _isCheckedIn ? Icons.logout : Icons.login,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    buttonText,
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

