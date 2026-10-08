import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/app_colors.dart';
import '../../config/app_text_styles.dart';
import '../../services/grievance_service.dart';
import '../../utils/error_message_utils.dart';
import '../../utils/snackbar_utils.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/bottom_navigation_bar.dart';
import '../../widgets/app_tab_loader.dart';

class GrievanceDetailScreen extends StatefulWidget {
  final String grievanceId;

  const GrievanceDetailScreen({
    super.key,
    required this.grievanceId,
  });

  @override
  State<GrievanceDetailScreen> createState() => _GrievanceDetailScreenState();
}

class _GrievanceDetailScreenState extends State<GrievanceDetailScreen> {
  final GrievanceService _service = GrievanceService();
  Map<String, dynamic>? _grievance;
  List<dynamic> _attachments = [];
  List<dynamic> _notes = [];
  List<dynamic> _statusHistory = [];
  Map<String, dynamic>? _feedback;
  bool _isLoading = true;
  String? _error;

  bool _showAddNote = false;
  final _noteController = TextEditingController();
  bool _isAddingNote = false;
  bool _isSubmittingFeedback = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    final result = await _service.getGrievanceById(widget.grievanceId);
    if (!mounted) return;
    if (result['success'] == true) {
      final data = result['data'] as Map<String, dynamic>?;
      setState(() {
        _grievance = data?['grievance'] as Map<String, dynamic>?;
        _attachments = (data?['attachments'] as List?)?.cast<dynamic>() ?? [];
        _notes = (data?['notes'] as List?)?.cast<dynamic>() ?? [];
        _statusHistory = (data?['statusHistory'] as List?)?.cast<dynamic>() ?? [];
        _feedback = data?['feedback'] as Map<String, dynamic>?;
        _isLoading = false;
      });
    } else {
      setState(() {
        _error = result['message']?.toString() ?? 'Failed to load grievance';
        _isLoading = false;
      });
    }
  }

  Future<void> _addNote() async {
    final content = _noteController.text.trim();
    if (content.isEmpty) return;
    setState(() => _isAddingNote = true);
    final result = await _service.addNote(widget.grievanceId, content);
    if (!mounted) return;
    setState(() {
      _isAddingNote = false;
      _showAddNote = false;
      _noteController.clear();
    });
    if (result['success'] == true) {
      _load();
      SnackBarUtils.showSnackBar(
        context,
        'Note added',
      );
    } else {
      SnackBarUtils.showSnackBar(
        context,
        ErrorMessageUtils.sanitizeForDisplay(result['message'], fallback: 'Failed to add note'),
        isError: true,
      );
    }
  }

  Future<void> _uploadFile(File file) async {
    final result = await _service.uploadAttachment(widget.grievanceId, file);
    if (!mounted) return;
    if (result['success'] == true) {
      _load();
      SnackBarUtils.showSnackBar(
        context,
        'File uploaded',
      );
    } else {
      SnackBarUtils.showSnackBar(
        context,
        ErrorMessageUtils.sanitizeForDisplay(result['message'], fallback: 'Upload failed'),
        isError: true,
      );
    }
  }

  Future<void> _openAttachment(String path) async {
    final url = GrievanceService.getFileUrl(path);
    if (url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'Submitted': return AppColors.info;
      case 'Under Review':
      case 'Assigned':
      case 'Investigation': return AppColors.warning;
      case 'Action Taken': return AppColors.primary;
      case 'Escalated':
      case 'Rejected': return AppColors.error;
      case 'Closed': return AppColors.success;
      default: return AppColors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Back',
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Grievance Detail'),
      ),
      drawer: const AppDrawer(),
      body: _buildBody(colorScheme),
      bottomNavigationBar: const AppBottomNavigationBar(currentIndex: -1),
    );
  }

  Widget _buildBody(ColorScheme colorScheme) {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const AppTabLoader(),
            const SizedBox(height: 16),
            const Text('Loading...', style: AppTextStyles.bodySmall),
          ],
        ),
      );
    }
    if (_error != null || _grievance == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(color: AppColors.errorBg, shape: BoxShape.circle),
                child: const Icon(Icons.error_outline_rounded, size: 30, color: AppColors.error),
              ),
              const SizedBox(height: 16),
              Text(_error ?? 'Grievance not found', textAlign: TextAlign.center, style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary)),
            ],
          ),
        ),
      );
    }

    final g = _grievance!;
    final status = g['status']?.toString() ?? 'Submitted';
    final isClosed = status == 'Closed';
    final canSubmitFeedback = isClosed && _feedback == null;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(g, colorScheme),
          if (canSubmitFeedback)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: _showFeedbackBottomSheet,
                  icon: const Icon(Icons.star_rounded, size: 18),
                  label: const Text('Submit Feedback'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.ink,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 12),
          _buildDetails(g, colorScheme),
          const SizedBox(height: 12),
          _buildAttachments(colorScheme),
          const SizedBox(height: 12),
          _buildNotes(colorScheme),
          const SizedBox(height: 12),
          _buildTimeline(colorScheme),
          const SizedBox(height: 12),
          _buildFeedback(colorScheme),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildHeader(Map<String, dynamic> g, ColorScheme colorScheme) {
    final ticketId = g['ticketId']?.toString() ?? '';
    final title = g['title']?.toString() ?? '';
    final status = g['status']?.toString() ?? 'Submitted';
    final slaBreached = g['slaBreached'] == true;
    final onHero = AppColors.onPrimary;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primary, AppColors.primaryDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.12),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
            Row(
              children: [
                Expanded(child: Text(ticketId, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, fontFamily: 'monospace', color: onHero.withValues(alpha: 0.8)))),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(status, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: onHero)),
                ),
                if (slaBreached) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: AppColors.errorBg, borderRadius: BorderRadius.circular(999)),
                    child: const Text('SLA Breached', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.error)),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            Text(title, style: TextStyle(fontSize: 20, height: 1.3, fontWeight: FontWeight.w700, color: onHero)),
        ],
      ),
    );
  }

  /// Section header used by the detail cards: tinted icon tile + title.
  Widget _sectionHeader(IconData icon, String title, {Widget? trailing}) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 20, color: AppColors.primaryText),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(title, style: AppTextStyles.headingSmall)),
        if (trailing != null) trailing,
      ],
    );
  }

  Widget _fieldLabel(String text) => Text(
        text,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
      );

  Widget _buildDetails(Map<String, dynamic> g, ColorScheme colorScheme) {
    final category = (g['categoryId'] is Map ? (g['categoryId'] as Map)['name'] : null) ?? g['category']?.toString() ?? '';
    final priority = g['priority']?.toString() ?? '';
    final description = g['description']?.toString() ?? '';
    final incidentDate = g['incidentDate'];
    DateTime? incDate;
    if (incidentDate != null) {
      if (incidentDate is String) {
        incDate = DateTime.tryParse(incidentDate);
      } else if (incidentDate is Map && incidentDate['\$date'] != null) incDate = DateTime.tryParse(incidentDate['\$date'].toString());
    }
    final peopleInvolved = g['peopleInvolved'];
    final people = peopleInvolved is List ? peopleInvolved.map((e) => e?.toString() ?? '').where((e) => e.isNotEmpty).toList() : <String>[];
    final resolutionSummary = g['resolutionSummary']?.toString();
    final actionTaken = g['actionTaken']?.toString();
    final createdAt = g['createdAt'];
    DateTime? created;
    if (createdAt != null) {
      if (createdAt is String) {
        created = DateTime.tryParse(createdAt);
      } else if (createdAt is Map && createdAt['\$date'] != null) created = DateTime.tryParse(createdAt['\$date'].toString());
      final c = created;
      if (c != null && c.isUtc) created = c.toLocal();
    }

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeader(Icons.info_outline_rounded, 'Details'),
            const SizedBox(height: 16),
            _detailRow('Category', category, colorScheme),
            _detailRow('Priority', priority, colorScheme),
            if (created != null) _detailRow('Created', DateFormat('MMM d, yyyy h:mm a').format(created), colorScheme),
            if (incDate != null) _detailRow('Incident Date', DateFormat('MMM d, yyyy').format(incDate), colorScheme),
            const SizedBox(height: 8),
            const Divider(height: 1),
            const SizedBox(height: 16),
            _fieldLabel('Description'),
            const SizedBox(height: 6),
            Text(description, style: AppTextStyles.bodyMedium.copyWith(height: 1.5)),
            if (people.isNotEmpty) ...[
              const SizedBox(height: 16),
              _fieldLabel('People Involved'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: people.map((p) => Chip(
                  avatar: Icon(Icons.person_outline_rounded, size: 18, color: AppColors.primaryText),
                  label: Text(p),
                )).toList(),
              ),
            ],
            if (resolutionSummary != null && resolutionSummary.isNotEmpty) ...[
              const SizedBox(height: 16),
              _fieldLabel('Resolution Summary'),
              const SizedBox(height: 6),
              Text(resolutionSummary, style: AppTextStyles.bodyMedium.copyWith(height: 1.5)),
            ],
            if (actionTaken != null && actionTaken.isNotEmpty) ...[
              const SizedBox(height: 16),
              _fieldLabel('Action Taken'),
              const SizedBox(height: 6),
              Text(actionTaken, style: AppTextStyles.bodyMedium.copyWith(height: 1.5)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value, ColorScheme colorScheme) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 120, child: Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 14))),
          Expanded(child: Text(value, style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }

  Future<void> _pickAndUploadFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'doc', 'docx', 'jpg', 'jpeg', 'png', 'webp', 'gif', 'xls', 'xlsx', 'txt'],
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.single.path;
    if (path == null) return;
    final file = File(path);
    if (!await file.exists()) return;
    final size = await file.length();
    if (size > 20 * 1024 * 1024) {
      if (mounted) {
        SnackBarUtils.showSnackBar(
          context,
          'File must be under 20MB',
          isError: true,
        );
      }
      return;
    }
    await _uploadFile(file);
  }

  Widget _buildAttachments(ColorScheme colorScheme) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeader(
              Icons.attach_file_rounded,
              'Attachments',
              trailing: TextButton.icon(
                onPressed: _pickAndUploadFile,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add'),
              ),
            ),
            const SizedBox(height: 12),
            if (_attachments.isEmpty)
              const Text('No attachments', style: AppTextStyles.bodySmall)
            else
              ..._attachments.map((a) {
                final name = (a is Map ? a['originalName'] ?? a['filename'] : '')?.toString() ?? 'File';
                final path = (a is Map ? a['fileUrl'] ?? a['filePath'] : null)?.toString();
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.infoBg,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.insert_drive_file_outlined, size: 20, color: AppColors.info),
                  ),
                  title: Text(name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.textPrimary)),
                  trailing: path != null
                      ? IconButton(
                          icon: Icon(Icons.download_rounded, color: AppColors.primaryText),
                          tooltip: 'Download',
                          onPressed: () => _openAttachment(path),
                        )
                      : null,
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildNotes(ColorScheme colorScheme) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeader(
              Icons.chat_bubble_outline_rounded,
              'Notes & Updates',
              trailing: TextButton.icon(
                onPressed: () => setState(() => _showAddNote = !_showAddNote),
                icon: Icon(_showAddNote ? Icons.close_rounded : Icons.add_rounded, size: 18),
                label: Text(_showAddNote ? 'Cancel' : 'Add Note'),
              ),
            ),
            const SizedBox(height: 12),
            if (_showAddNote) ...[
              TextField(
                controller: _noteController,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText: 'Enter your note...',
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _isAddingNote ? null : _addNote,
                child: _isAddingNote ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onPrimary)) : const Text('Add Note'),
              ),
              const SizedBox(height: 16),
            ],
            if (_notes.isEmpty && !_showAddNote)
              const Text('No notes yet', style: AppTextStyles.bodySmall)
            else
              ..._notes.map((n) {
                final content = (n is Map ? n['content'] : '')?.toString() ?? '';
                final author = (n is Map && n['createdBy'] is Map ? (n['createdBy'] as Map)['name'] : null)?.toString() ?? 'Unknown';
                final createdAt = n is Map ? n['createdAt'] : null;
                DateTime? dt;
                if (createdAt != null) {
                  if (createdAt is String) {
                    dt = DateTime.tryParse(createdAt);
                  } else if (createdAt is Map && createdAt['\$date'] != null) dt = DateTime.tryParse(createdAt['\$date'].toString());
                  if (dt != null && dt.isUtc) dt = dt.toLocal();
                }
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    border: Border.all(color: const Color(0xFFECEEF1)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(child: Text(author, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary))),
                          const SizedBox(width: 8),
                          if (dt != null) Text(DateFormat('MMM d, h:mm a').format(dt), style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(content, style: AppTextStyles.bodyMedium),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeline(ColorScheme colorScheme) {
    if (_statusHistory.isEmpty) return const SizedBox.shrink();
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeader(Icons.timeline_rounded, 'Status Timeline'),
            const SizedBox(height: 16),
            Stack(
              alignment: Alignment.centerLeft,
              children: [
                // Full-height continuous timeline line
                Positioned(
                  left: 5,
                  top: 0,
                  bottom: 0,
                  child: Container(
                    width: 2,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ..._statusHistory.asMap().entries.map((e) {
                      final h = e.value as Map<String, dynamic>;
                      final toStatus = h['toStatus']?.toString() ?? '';
                      final fromStatus = h['fromStatus']?.toString();
                      final changedBy = (h['changedBy'] is Map ? (h['changedBy'] as Map)['name'] : null)?.toString() ?? 'Unknown';
                      final createdAt = h['createdAt'];
                      DateTime? dt;
                      if (createdAt != null) {
                        if (createdAt is String) {
                          dt = DateTime.tryParse(createdAt);
                        } else if (createdAt is Map && createdAt['\$date'] != null) dt = DateTime.tryParse(createdAt['\$date'].toString());
                        if (dt != null && dt.isUtc) dt = dt.toLocal();
                      }
                      final reason = h['reason']?.toString();
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: _statusColor(toStatus),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (fromStatus != null && fromStatus.isNotEmpty)
                                    Text('$fromStatus → $toStatus', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                                  if (fromStatus == null || fromStatus.isEmpty) Text(toStatus, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                                  const SizedBox(height: 2),
                                  Text('By $changedBy', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                                  if (dt != null) Text(DateFormat('MMM d, h:mm a').format(dt), style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                                  if (reason != null && reason.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 6),
                                      child: Text(reason, style: AppTextStyles.bodySmall),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                    // End dot at bottom of timeline
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.35),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeedback(ColorScheme colorScheme) {
    if (_feedback == null) return const SizedBox.shrink();
    final f = _feedback!;
    final rating = (f['rating'] ?? 0) as int;
    final feedback = f['feedback']?.toString() ?? '';
    final onHero = AppColors.onPrimary;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primary, AppColors.primaryDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.12),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Your Feedback', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: onHero)),
          const SizedBox(height: 10),
          Row(
            children: List.generate(5, (i) => Icon(i < rating ? Icons.star_rounded : Icons.star_border_rounded, color: onHero, size: 24)),
          ),
          const SizedBox(height: 10),
          Text(feedback, style: TextStyle(fontSize: 14, height: 1.5, color: onHero)),
        ],
      ),
    );
  }

  void _showFeedbackBottomSheet() {
    final rating = ValueNotifier<int>(0);
    final controller = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => ValueListenableBuilder<int>(
        valueListenable: rating,
        builder: (_, feedbackRating, __) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Submit Feedback', style: AppTextStyles.headingMedium),
                const SizedBox(height: 20),
                Text('Rating', style: AppTextStyles.label.copyWith(color: AppColors.textSecondary)),
                const SizedBox(height: 4),
                Row(
                  children: List.generate(5, (i) {
                    final star = i + 1;
                    return IconButton(
                      icon: Icon(star <= feedbackRating ? Icons.star_rounded : Icons.star_border_rounded, color: AppColors.primary, size: 36),
                      onPressed: () => rating.value = star,
                    );
                  }),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Feedback',
                    hintText: 'Share your feedback about the resolution...',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 20),
                StatefulBuilder(
                  builder: (ctx2, setModalState) => FilledButton(
                    onPressed: _isSubmittingFeedback ? null : () async {
                      final r = rating.value;
                      final f = controller.text.trim();
                      if (r < 1 || f.isEmpty) {
                        SnackBarUtils.showSnackBar(
                          context,
                          'Please provide rating and feedback',
                          isError: true,
                        );
                        return;
                      }
                      setModalState(() => _isSubmittingFeedback = true);
                      final result = await _service.submitFeedback(widget.grievanceId, r, f);
                      if (!ctx2.mounted) return;
                      Navigator.of(ctx2).pop();
                      if (result['success'] == true) {
                        _load();
                        SnackBarUtils.showSnackBar(
                          context,
                          'Feedback submitted',
                        );
                      } else {
                        SnackBarUtils.showSnackBar(
                          context,
                          ErrorMessageUtils.sanitizeForDisplay(result['message'], fallback: 'Failed'),
                          isError: true,
                        );
                      }
                      if (mounted) setState(() => _isSubmittingFeedback = false);
                    },
                    child: _isSubmittingFeedback
                        ? SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onPrimary))
                        : const Text('Submit'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
