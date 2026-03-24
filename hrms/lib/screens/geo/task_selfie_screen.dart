import 'dart:io';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:hrms/config/app_colors.dart';
import 'package:hrms/models/task.dart';
import 'package:hrms/services/geo/address_resolution_service.dart';
import 'package:hrms/services/geo/accurate_location_helper.dart';
import 'package:hrms/services/task_service.dart';
import 'package:hrms/utils/error_message_utils.dart';
import 'package:hrms/utils/face_detection_helper.dart';
import 'package:hrms/utils/snackbar_utils.dart';
import 'package:hrms/screens/attendance/selfie_camera_screen.dart' show SelfieCameraScreen, useImagePickerFallback;

class TaskSelfieScreen extends StatefulWidget {
  final Task task;
  final String? taskMongoId;
  final String type; // 'checkin' or 'checkout'
  final VoidCallback? onSelfieUploaded;

  const TaskSelfieScreen({
    super.key,
    required this.task,
    required this.type,
    this.taskMongoId,
    this.onSelfieUploaded,
  });

  @override
  State<TaskSelfieScreen> createState() => _TaskSelfieScreenState();
}

class _TaskSelfieScreenState extends State<TaskSelfieScreen> {
  File? _imageFile;
  Position? _position;
  String? _address;
  String? _area;
  String? _city;
  String? _pincode;

  bool _isLocationLoading = true;
  bool _isDetectingFace = false;
  bool _uploading = false;

  /// Open selfie camera once after location is ready (check-in / check-out from Arrived).
  bool _didAutoOpenCamera = false;

  String get _title => widget.type == 'checkin' ? 'Check-in Selfie' : 'Check-out Selfie';
  String get _submitLabel => 'Upload Selfie';

  @override
  void initState() {
    super.initState();
    _determinePosition();
  }

  Future<void> _determinePosition() async {
    setState(() => _isLocationLoading = true);
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) SnackBarUtils.showSnackBar(context, 'Location services are disabled.', isError: true);
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        if (mounted) SnackBarUtils.showSnackBar(context, 'Location permission is required.', isError: true);
        return;
      }

      final position = await getQuickPositionForUi();
      ResolvedAddress? resolved;
      try {
        resolved = await AddressResolutionService.reverseGeocodeForUi(
          position.latitude,
          position.longitude,
        );
      } catch (_) {
        // GPS ok; address optional — still show coords on camera and allow upload.
      }

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
        // Open selfie camera immediately with resolved location (same for check-in & check-out).
        if (_position != null && !_didAutoOpenCamera) {
          _didAutoOpenCamera = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _takeSelfie();
          });
        }
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
      SnackBarUtils.showSnackBar(context, 'Camera permission is required.', isError: true);
      return;
    }

    final locationStr = _address ??
        (_area != null ? '$_area, ${_city ?? ''}${_pincode != null ? ' $_pincode' : ''}' : null);

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
      SnackBarUtils.showSnackBar(context, result.message ?? 'Please keep exactly one face visible.', isError: true);
      return;
    }

    setState(() => _imageFile = file);
  }

  Future<void> _uploadSelfie() async {
    if (_uploading) return;
    if (_imageFile == null || widget.taskMongoId == null) {
      SnackBarUtils.showSnackBar(context, 'Please take a selfie first.', isError: true);
      return;
    }
    if (_position == null) {
      await _determinePosition();
      if (!mounted) return;
      if (_position == null) {
        SnackBarUtils.showSnackBar(context, 'Location is required.', isError: true);
        return;
      }
    }

    setState(() => _uploading = true);

    try {
      await TaskService().uploadTaskSelfie(
        widget.taskMongoId!,
        widget.type,
        _imageFile!.path,
      );
      if (mounted) {
        widget.onSelfieUploaded?.call();
        SnackBarUtils.showSnackBar(context, '${_title} successful');
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _uploading = false);
        SnackBarUtils.showSnackBar(context, ErrorMessageUtils.toUserFriendlyMessage(e), isError: true);
      }
    }
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
                  onTap: _isDetectingFace || _uploading ? null : _takeSelfie,
                  child: AspectRatio(
                    aspectRatio: 3 / 4,
                    child: Image.file(_imageFile!, fit: BoxFit.cover),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: IconButton(
                    onPressed: _isDetectingFace || _uploading ? null : _takeSelfie,
                    icon: Icon(Icons.refresh_rounded, color: primary, size: 28),
                    tooltip: 'Retake',
                  ),
                ),
              ],
            )
          : InkWell(
              onTap: _isDetectingFace || _uploading ? null : _takeSelfie,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 16),
                child: Column(
                  children: [
                    if (_isDetectingFace)
                      const CircularProgressIndicator(strokeWidth: 2)
                    else
                      Icon(Icons.camera_alt_rounded, size: 48, color: primary),
                    const SizedBox(height: 12),
                    Text(
                      'Take $_title',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
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
            onPressed: () {
              if (!_uploading && !_isDetectingFace) _determinePosition();
            },
            icon: Icon(Icons.refresh, color: AppColors.primary),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: _isLocationLoading
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 20),
                    Text(
                      'Getting your location…',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade800,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Opening camera with location next.',
                      style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildSelfieCard(),
                  const SizedBox(height: 20),
                  _buildLocationCard(),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _uploading || _imageFile == null ? null : _uploadSelfie,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _uploading
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : Text(
                            _submitLabel,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                  ),
                ],
              ),
            ),
    );
  }
}
