import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/app_colors.dart';
import '../../services/grievance_service.dart';
import '../../utils/error_message_utils.dart';
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Note added'), backgroundColor: AppColors.success),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ErrorMessageUtils.sanitizeForDisplay(result['message'], fallback: 'Failed to add note')),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _uploadFile(File file) async {
    final result = await _service.uploadAttachment(widget.grievanceId, file);
    if (!mounted) return;
    if (result['success'] == true) {
      _load();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('File uploaded'), backgroundColor: AppColors.success),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ErrorMessageUtils.sanitizeForDisplay(result['message'], fallback: 'Upload failed')),
          backgroundColor: AppColors.error,
        ),
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
      default: return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Grievance Detail', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
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
            Text('Loading...', style: TextStyle(color: colorScheme.onSurfaceVariant)),
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
              Icon(Icons.error_outline, size: 48, color: colorScheme.error),
              const SizedBox(height: 16),
              Text(_error ?? 'Grievance not found', textAlign: TextAlign.center),
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
              padding: const EdgeInsets.only(top: 20, bottom: 16),
              child: Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: _showFeedbackBottomSheet,
                  icon: const Icon(Icons.star, size: 18),
                  label: const Text('Submit Feedback'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                ),
              ),
            ),
          _buildDetails(g, colorScheme),
          const SizedBox(height: 16),
          _buildAttachments(colorScheme),
          const SizedBox(height: 16),
          _buildNotes(colorScheme),
          const SizedBox(height: 16),
          _buildTimeline(colorScheme),
          const SizedBox(height: 16),
          _buildFeedback(colorScheme),
        ],
      ),
    );
  }

  Widget _buildHeader(Map<String, dynamic> g, ColorScheme colorScheme) {
    final ticketId = g['ticketId']?.toString() ?? '';
    final title = g['title']?.toString() ?? '';
    final status = g['status']?.toString() ?? 'Submitted';
    final slaBreached = g['slaBreached'] == true;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primary, AppColors.primaryDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
            Row(
              children: [
                Text(ticketId, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, fontFamily: 'monospace', color: Colors.white)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.25),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(status, style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white)),
                ),
                if (slaBreached) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    decoration: BoxDecoration(color: Colors.white.withOpacity(0.25), borderRadius: BorderRadius.circular(8)),
                    child: const Text('SLA Breached', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Text(title, style: const TextStyle(fontSize: 16, color: Colors.white)),
        ],
      ),
    );
  }

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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Details', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: colorScheme.onSurface)),
            const SizedBox(height: 12),
            _detailRow('Category', category, colorScheme),
            _detailRow('Priority', priority, colorScheme),
            if (created != null) _detailRow('Created', DateFormat('MMM d, yyyy h:mm a').format(created), colorScheme),
            if (incDate != null) _detailRow('Incident Date', DateFormat('MMM d, yyyy').format(incDate), colorScheme),
            const SizedBox(height: 12),
            Text('Description', style: TextStyle(fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant)),
            const SizedBox(height: 4),
            Text(description, style: TextStyle(color: colorScheme.onSurface, height: 1.4)),
            if (people.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('People Involved', style: TextStyle(fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant)),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: people.map((p) => Chip(label: Text(p))).toList(),
              ),
            ],
            if (resolutionSummary != null && resolutionSummary.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Resolution Summary', style: TextStyle(fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant)),
              const SizedBox(height: 4),
              Text(resolutionSummary, style: TextStyle(color: colorScheme.onSurface)),
            ],
            if (actionTaken != null && actionTaken.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Action Taken', style: TextStyle(fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant)),
              const SizedBox(height: 4),
              Text(actionTaken, style: TextStyle(color: colorScheme.onSurface)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value, ColorScheme colorScheme) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 120, child: Text(label, style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 14))),
          Expanded(child: Text(value, style: TextStyle(color: colorScheme.onSurface, fontSize: 14))),
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('File must be under 20MB'), backgroundColor: AppColors.error),
        );
      }
      return;
    }
    await _uploadFile(file);
  }

  Widget _buildAttachments(ColorScheme colorScheme) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.attach_file, color: AppColors.primary),
                const SizedBox(width: 8),
                Text('Attachments', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const Spacer(),
                TextButton.icon(
                  onPressed: _pickAndUploadFile,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_attachments.isEmpty)
              Text('No attachments', style: TextStyle(color: colorScheme.onSurfaceVariant))
            else
              ..._attachments.map((a) {
                final name = (a is Map ? a['originalName'] ?? a['filename'] : '')?.toString() ?? 'File';
                final path = (a is Map ? a['fileUrl'] ?? a['filePath'] : null)?.toString();
                return ListTile(
                  leading: const Icon(Icons.insert_drive_file),
                  title: Text(name, overflow: TextOverflow.ellipsis),
                  trailing: path != null
                      ? IconButton(
                          icon: const Icon(Icons.download),
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.comment, color: AppColors.primary),
                const SizedBox(width: 8),
                Text('Notes & Updates', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => setState(() => _showAddNote = !_showAddNote),
                  icon: Icon(_showAddNote ? Icons.close : Icons.add, size: 18),
                  label: Text(_showAddNote ? 'Cancel' : 'Add Note'),
                ),
              ],
            ),
            if (_showAddNote) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _noteController,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: 'Enter your note...',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _isAddingNote ? null : _addNote,
                child: _isAddingNote ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Add Note'),
              ),
              const SizedBox(height: 16),
            ],
            if (_notes.isEmpty && !_showAddNote)
              Text('No notes yet', style: TextStyle(color: colorScheme.onSurfaceVariant))
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
                    color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(author, style: const TextStyle(fontWeight: FontWeight.w600)),
                          const Spacer(),
                          if (dt != null) Text(DateFormat('MMM d, h:mm a').format(dt), style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(content),
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Status Timeline', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Stack(
              alignment: Alignment.centerLeft,
              children: [
                // Full-height continuous timeline line
                Positioned(
                  left: 5,
                  top: 0,
                  bottom: 0,
                  child: Container(
                    width: 3,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.6),
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
                                    Text('$fromStatus → $toStatus', style: TextStyle(fontWeight: FontWeight.w600)),
                                  if (fromStatus == null || fromStatus.isEmpty) Text(toStatus, style: TextStyle(fontWeight: FontWeight.w600)),
                                  Text('By $changedBy', style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
                                  if (dt != null) Text(DateFormat('MMM d, h:mm a').format(dt), style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
                                  if (reason != null && reason.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(reason, style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant)),
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
                            color: AppColors.primary.withOpacity(0.6),
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primary, AppColors.primaryDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Your Feedback', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 8),
          Row(
            children: List.generate(5, (i) => Icon(i < rating ? Icons.star : Icons.star_border, color: Colors.white, size: 24)),
          ),
          const SizedBox(height: 8),
          Text(feedback, style: const TextStyle(color: Colors.white)),
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
                const Text('Submit Feedback', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                const Text('Rating'),
                Row(
                  children: List.generate(5, (i) {
                    final star = i + 1;
                    return IconButton(
                      icon: Icon(star <= feedbackRating ? Icons.star : Icons.star_border, color: AppColors.primary, size: 36),
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
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                StatefulBuilder(
                  builder: (ctx2, setModalState) => FilledButton(
                    onPressed: _isSubmittingFeedback ? null : () async {
                      final r = rating.value;
                      final f = controller.text.trim();
                      if (r < 1 || f.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Please provide rating and feedback')),
                        );
                        return;
                      }
                      setModalState(() => _isSubmittingFeedback = true);
                      final result = await _service.submitFeedback(widget.grievanceId, r, f);
                      if (!ctx2.mounted) return;
                      Navigator.of(ctx2).pop();
                      if (result['success'] == true) {
                        _load();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Feedback submitted'), backgroundColor: AppColors.success),
                        );
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(ErrorMessageUtils.sanitizeForDisplay(result['message'], fallback: 'Failed')),
                            backgroundColor: AppColors.error,
                          ),
                        );
                      }
                      if (mounted) setState(() => _isSubmittingFeedback = false);
                    },
                    child: _isSubmittingFeedback
                        ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
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
