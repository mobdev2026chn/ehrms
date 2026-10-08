// Documents tab of the admin Staff Detail screen (web: staffManagement/documents.tsx).
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:mime/mime.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../../config/app_colors.dart';
import '../../../../../config/app_text_styles.dart';
import '../../../../../services/admin_staff_detail_service.dart';
import '../staff_detail_common.dart';

const _categories = [
  'Identity Proof',
  'Academic Proof',
  'Address Proof',
  'Bank Info',
  'Health Proof',
  'Previous Employment',
  'Other',
];

const _maxBytes = 15 * 1024 * 1024;

String _formatBytes(int bytes) {
  if (bytes <= 0) return '0 Bytes';
  const units = ['Bytes', 'KB', 'MB', 'GB'];
  var size = bytes.toDouble();
  var i = 0;
  while (size >= 1024 && i < units.length - 1) {
    size /= 1024;
    i++;
  }
  final s = size.toStringAsFixed(2).replaceAll(RegExp(r'\.?0+$'), '');
  return '$s ${units[i]}';
}

class StaffDocumentsTab extends StatefulWidget {
  const StaffDocumentsTab({super.key, required this.staffId});

  final String staffId;

  @override
  State<StaffDocumentsTab> createState() => _StaffDocumentsTabState();
}

class _StaffDocumentsTabState extends State<StaffDocumentsTab> {
  final _service = AdminStaffDetailService();

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _docs = [];
  String? _deletingId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final docs = await _service.getDocuments(widget.staffId);
      if (!mounted) return;
      setState(() {
        _docs = docs.reversed.toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = sdErrorText(e);
        _loading = false;
      });
    }
  }

  Future<void> _open(Map<String, dynamic> doc) async {
    final uri = Uri.tryParse(sdStr(doc['url']));
    if (uri == null || !uri.hasScheme) {
      sdShowError(context, StaffDetailApiException('This document has no file link.'));
      return;
    }
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) sdShowError(context, StaffDetailApiException('Could not open the document.'));
  }

  Future<void> _delete(Map<String, dynamic> doc) async {
    final id = sdId(doc);
    final ok = await sdConfirm(context,
        title: 'Delete Document',
        message: 'Delete "${sdStr(doc['name'], 'this document')}"? This cannot be undone.',
        confirmText: 'Delete',
        danger: true);
    if (!ok) return;
    setState(() => _deletingId = id);
    try {
      final res = await _service.deleteDocument(widget.staffId, id);
      if (!mounted) return;
      setState(() {
        _deletingId = null;
        _docs.removeWhere((d) => sdId(d) == id);
      });
      sdShowSuccess(context, sdStr(res['message'], 'Document deleted successfully'));
    } catch (e) {
      if (!mounted) return;
      setState(() => _deletingId = null);
      sdShowError(context, e);
    }
  }

  Future<void> _upload() async {
    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _UploadSheet(staffId: widget.staffId),
    );
    if (added == true) _load();
  }

  IconData _icon(String type) {
    final t = type.toLowerCase();
    if (t.contains('pdf')) return Icons.picture_as_pdf_outlined;
    if (t.contains('image')) return Icons.image_outlined;
    return Icons.insert_drive_file_outlined;
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Row(children: [
            const Expanded(
              child: Text('Documents', style: AppTextStyles.headingMedium),
            ),
            ElevatedButton.icon(
              onPressed: _upload,
              style: sdPrimaryButton(),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add Document'),
            ),
          ]),
          const SizedBox(height: 12),
          if (_loading)
            const SdLoading()
          else if (_error != null)
            SdErrorView(message: _error!, onRetry: _load)
          else if (_docs.isEmpty)
            const SdEmptyView(message: 'No documents uploaded yet', icon: Icons.folder_open_outlined)
          else
            for (final d in _docs)
              SdCard(
                child: Row(children: [
                  Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                    child: Icon(_icon(sdStr(d['type'])), size: 22, color: AppColors.primaryText),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(sdStr(d['name'], 'Document'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: kSdInk)),
                      const SizedBox(height: 2),
                      Text('${sdStr(d['category'], '-')} · ${sdStr(d['size'], '-')}',
                          style: AppTextStyles.bodySmall),
                      Text('Uploaded ${sdFmtDate(d['uploaded'])}', style: AppTextStyles.caption.copyWith(color: kSdSubtle)),
                    ]),
                  ),
                  IconButton(
                    tooltip: 'View',
                    icon: const Icon(Icons.visibility_outlined, size: 20, color: kSdMuted),
                    onPressed: () => _open(d),
                  ),
                  _deletingId == sdId(d)
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : IconButton(
                          tooltip: 'Delete',
                          icon: const Icon(Icons.delete_outline_rounded, size: 20, color: AppColors.error),
                          onPressed: () => _delete(d),
                        ),
                ]),
              ),
        ],
      ),
    );
  }
}

class _UploadSheet extends StatefulWidget {
  const _UploadSheet({required this.staffId});
  final String staffId;

  @override
  State<_UploadSheet> createState() => _UploadSheetState();
}

class _UploadSheetState extends State<_UploadSheet> {
  final _service = AdminStaffDetailService();
  final _name = TextEditingController();
  String _category = _categories.first;
  PlatformFile? _file;
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'webp', 'doc', 'docx'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final f = result.files.single;
    if (f.size > _maxBytes) {
      setState(() => _error = 'The file is larger than 15 MB. Please upload a smaller file.');
      return;
    }
    setState(() {
      _file = f;
      _error = null;
      if (_name.text.trim().isEmpty) {
        final dot = f.name.lastIndexOf('.');
        _name.text = dot > 0 ? f.name.substring(0, dot) : f.name;
      }
    });
  }

  Future<void> _submit() async {
    final file = _file;
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Document name is required.');
      return;
    }
    if (file == null) {
      setState(() => _error = 'Please choose a file to upload.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final bytes = file.bytes ?? (file.path != null ? await File(file.path!).readAsBytes() : null);
      if (bytes == null) throw StaffDetailApiException('Could not read the selected file.');
      final mimeType = lookupMimeType(file.name, headerBytes: bytes.take(16).toList()) ?? 'application/octet-stream';
      final res = await _service.addDocument(
        staffId: widget.staffId,
        name: _name.text.trim(),
        category: _category,
        type: mimeType,
        size: _formatBytes(bytes.length),
        proofFile: 'data:$mimeType;base64,${base64Encode(bytes)}',
      );
      if (!mounted) return;
      sdShowSuccess(context, sdStr(res['message'], 'Document added successfully'));
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = sdErrorText(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Add Document', style: AppTextStyles.headingMedium),
              const SizedBox(height: 16),
              TextField(controller: _name, decoration: sdInput('Document Name')),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _category,
                decoration: sdInput('Category'),
                items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                onChanged: _saving ? null : (v) => setState(() => _category = v ?? _category),
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: _saving ? null : _pick,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                  decoration: BoxDecoration(
                    color: kSdBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _file != null ? AppColors.success : kSdLine, width: _file != null ? 1.4 : 1),
                  ),
                  child: Column(children: [
                    Icon(_file != null ? Icons.check_circle_outline_rounded : Icons.upload_file_outlined,
                        size: 28, color: _file != null ? AppColors.success : AppColors.primaryText),
                    const SizedBox(height: 8),
                    Text(
                      _file != null ? '${_file!.name} (${_formatBytes(_file!.size)})' : 'Tap to choose a file (max 15 MB)',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: kSdInk),
                    ),
                  ]),
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_error!, style: const TextStyle(fontSize: 12, color: AppColors.error)),
                ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saving ? null : _submit,
                  style: sdPrimaryButton(),
                  child: _saving
                      ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onPrimary))
                      : const Text('Upload'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
