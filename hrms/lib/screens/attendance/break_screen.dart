import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'selfie_camera_screen.dart' show SelfieCameraScreen, useImagePickerFallback;
import '../../config/app_colors.dart';
import '../../services/break_service.dart';
import '../../services/geo/address_resolution_service.dart';
import '../../services/geo/accurate_location_helper.dart';
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

  bool _isLoading = false;
  bool _isBreakLoading = true;
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
    _refreshCurrentBreak();
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

  Future<void> _refreshCurrentBreak() async {
    setState(() => _isBreakLoading = true);
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
        _address = resolved?.formattedAddress ??
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

    final locationStr = _address ??
        (_area != null
            ? '$_area, ${_city ?? ''}${_pincode != null ? ' $_pincode' : ''}'
            : null);
    if (!mounted) return;
    final captureResult = await SelfieCameraScreen.captureSelfie(
      context,
      location: locationStr,
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
    return 'data:image/jpeg;base64,${base64Encode(imageBytes)}';
  }

  DateTime? _breakStartTime() {
    final raw = _activeBreak?['startTime']?.toString();
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw)?.toLocal();
  }

  Future<void> _submit() async {
    if (_isLoading) return;
    if (_imageFile == null) {
      SnackBarUtils.showSnackBar(context, 'Please take a selfie first!', isError: true);
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
          )
        : await _breakService.startBreak(
            lat: _position!.latitude,
            lng: _position!.longitude,
            address: _address ?? '',
            area: _area,
            city: _city,
            pincode: _pincode,
            selfie: selfie,
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
                padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
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
                    child: CircularProgressIndicator(strokeWidth: 2),
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
                          child: Text('${_city ?? ''} ${_pincode ?? ''}'.trim()),
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
                await _refreshCurrentBreak();
                await _determinePosition();
              },
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_isOnBreak && startTime != null) ...[
                      BreakStatusCard(
                        startTime: startTime,
                        onEndBreak: _submit,
                        isBusy: _isLoading,
                        showSuccessBanner: _showStartedBanner,
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
                    _buildSelfieCard(),
                    const SizedBox(height: 20),
                    _buildLocationCard(),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: _isLoading ? null : _submit,
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
