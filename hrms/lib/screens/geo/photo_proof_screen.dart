// Photo proof screen – tap to take photo, add description, upload via API (Digital Ocean).
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hrms/config/app_colors.dart';
import 'package:hrms/config/app_text_styles.dart';
import 'package:hrms/widgets/app_card.dart';
import 'package:hrms/models/task.dart';
import 'package:hrms/services/geo/address_resolution_service.dart';
import 'package:hrms/services/task_service.dart';
import 'package:hrms/utils/error_message_utils.dart';
import 'package:image_picker/image_picker.dart';
import 'package:hrms/widgets/oriented_image.dart';

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
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Back',
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Photo Proof'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
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
                        : AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _photo != null
                          ? AppColors.primary.withValues(alpha: 0.4)
                          : const Color(0xFFE2E5EA),
                      width: 1.5,
                    ),
                    boxShadow: _photo != null ? null : kSoftCardShadow,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(15),
                    child: _photo != null
                        ? Stack(
                            fit: StackFit.expand,
                            children: [
                              OrientedImage.file(_photo!, fit: BoxFit.cover),
                              Positioned(
                                bottom: 12,
                                right: 12,
                                child: Material(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(999),
                                  child: InkWell(
                                    onTap: _uploading ? null : _takePhoto,
                                    borderRadius: BorderRadius.circular(999),
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
                              Container(
                                width: 64,
                                height: 64,
                                decoration: BoxDecoration(
                                  color: AppColors.primary
                                      .withValues(alpha: 0.12),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.camera_alt_outlined,
                                  size: 28,
                                  color: AppColors.primaryText,
                                ),
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'Upload proof',
                                style: AppTextStyles.headingSmall,
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Tap to take photo',
                                style: AppTextStyles.bodySmall,
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
                decoration: const InputDecoration(
                  labelText: 'Description',
                  hintText: 'Add a description for this photo...',
                ),
                enabled: !_uploading,
              ),
              const SizedBox(height: 16),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.errorBg,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.error_outline_rounded,
                          size: 18,
                          color: AppColors.error,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _error!,
                            style: AppTextStyles.bodySmall.copyWith(
                              color: AppColors.error,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (_photo != null && _descriptionController.text.trim().isNotEmpty)
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: _uploading ? null : _uploadPhoto,
                    icon: _uploading
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.onPrimary,
                            ),
                          )
                        : const Icon(Icons.cloud_upload_outlined, size: 20),
                    label: Text(_uploading ? 'Uploading...' : 'Upload Proof'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
