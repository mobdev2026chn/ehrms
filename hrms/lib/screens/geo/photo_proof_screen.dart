// Photo proof screen – tap to take photo, add description, upload via API (Digital Ocean).
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hrms/config/app_colors.dart';
import 'package:hrms/models/task.dart';
import 'package:hrms/services/geo/address_resolution_service.dart';
import 'package:hrms/services/task_service.dart';
import 'package:hrms/utils/error_message_utils.dart';
import 'package:image_picker/image_picker.dart';

class PhotoProofScreen extends StatefulWidget {
  final Task task;
  final String? taskMongoId;
  final VoidCallback? onPhotoUploaded;

  const PhotoProofScreen({
    super.key,
    required this.task,
    this.taskMongoId,
    this.onPhotoUploaded,
  });

  @override
  State<PhotoProofScreen> createState() => _PhotoProofScreenState();
}

class _PhotoProofScreenState extends State<PhotoProofScreen> {
  File? _photo;
  bool _uploading = false;
  String? _error;
  final TextEditingController _descriptionController = TextEditingController();

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _takePhoto() async {
    setState(() {
      _error = null;
      _photo = null;
    });
    try {
      final picker = ImagePicker();
      final xFile = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
        maxWidth: 1920,
      );
      if (xFile != null && mounted) {
        setState(() => _photo = File(xFile.path));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = ErrorMessageUtils.toUserFriendlyMessage(e));
      }
    }
  }

  Future<void> _uploadPhoto() async {
    if (_photo == null ||
        widget.taskMongoId == null ||
        widget.taskMongoId!.isEmpty) {
      setState(() => _error = 'Please take a photo first');
      return;
    }
    if (_descriptionController.text.trim().isEmpty) {
      setState(() => _error = 'Please enter a description');
      return;
    }
    setState(() {
      _uploading = true;
      _error = null;
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
      await TaskService().uploadPhotoProof(
        widget.taskMongoId!,
        _photo!.path,
        description: _descriptionController.text.trim(),
        lat: lat,
        lng: lng,
        fullAddress: fullAddress,
      );
      if (mounted) {
        widget.onPhotoUploaded?.call();
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _uploading = false;
          _error = ErrorMessageUtils.toUserFriendlyMessage(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Photo Proof',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GestureDetector(
                onTap: _uploading ? null : _takePhoto,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: 280,
                  decoration: BoxDecoration(
                    color: _photo != null
                        ? Colors.transparent
                        : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _photo != null
                          ? AppColors.primary.withOpacity(0.3)
                          : Colors.grey.shade300,
                      width: 2,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: _photo != null
                        ? Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.file(_photo!, fit: BoxFit.cover),
                              Positioned(
                                bottom: 8,
                                right: 8,
                                child: Material(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(8),
                                  child: InkWell(
                                    onTap: _uploading ? null : _takePhoto,
                                    borderRadius: BorderRadius.circular(8),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 8,
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.camera_alt_rounded,
                                            size: 18,
                                            color: Colors.white,
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            'Retake',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          )
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.camera_alt_rounded,
                                size: 64,
                                color: Colors.grey.shade400,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Upload proof',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Tap to take photo',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _descriptionController,
                maxLines: 3,
                onChanged: (_) {
                  if (mounted) setState(() {});
                },
                decoration: InputDecoration(
                  labelText: 'Description',
                  hintText: 'Add a description for this photo...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppColors.primary, width: 2),
                  ),
                ),
                enabled: !_uploading,
              ),
              const SizedBox(height: 16),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    _error!,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.error,
                    ),
                  ),
                ),
              if (_photo != null && _descriptionController.text.trim().isNotEmpty)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _uploading ? null : _uploadPhoto,
                    icon: _uploading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.cloud_upload_rounded, size: 20),
                    label: Text(_uploading ? 'Uploading...' : 'Upload Proof'),
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
      ),
    );
  }
}
