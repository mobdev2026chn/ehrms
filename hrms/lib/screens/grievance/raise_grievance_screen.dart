import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../config/app_colors.dart';
import '../../config/app_text_styles.dart';
import '../../services/grievance_service.dart';
import '../../utils/error_message_utils.dart';
import '../../utils/snackbar_utils.dart';
import '../../widgets/bottom_navigation_bar.dart';
import '../../widgets/app_tab_loader.dart';
import '../../widgets/notification_reaction_overlay.dart';

class RaiseGrievanceScreen extends StatefulWidget {
  const RaiseGrievanceScreen({super.key});

  @override
  State<RaiseGrievanceScreen> createState() => _RaiseGrievanceScreenState();
}

class _RaiseGrievanceScreenState extends State<RaiseGrievanceScreen> {
  final GrievanceService _service = GrievanceService();
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();

  List<Map<String, dynamic>> _categories = [];
  String? _selectedCategoryId;
  String _priority = 'Medium';
  DateTime? _incidentDate;
  final List<String> _peopleInvolved = [];
  final _personController = TextEditingController();
  bool _isAnonymous = false;
  final List<File> _selectedFiles = [];
  bool _isLoading = false;
  bool _categoriesLoading = true;
  String? _categoriesError;

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _personController.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    setState(() {
      _categoriesLoading = true;
      _categoriesError = null;
    });
    final result = await _service.getCategories();
    if (!mounted) return;
    if (result['success'] == true) {
      final data = result['data'];
      setState(() {
        _categories = (data is List)
            ? (data).map((e) => e is Map<String, dynamic> ? e : {'_id': e['_id'], 'name': e['name']}).toList().cast<Map<String, dynamic>>()
            : [];
        _categoriesLoading = false;
        if (_categories.isNotEmpty && _selectedCategoryId == null) {
          _selectedCategoryId = _categories.first['_id']?.toString();
        }
      });
    } else {
      setState(() {
        _categoriesError = result['message']?.toString() ?? 'Failed to load categories';
        _categoriesLoading = false;
      });
    }
  }

  void _addPerson() {
    final v = _personController.text.trim();
    if (v.isNotEmpty && !_peopleInvolved.contains(v)) {
      setState(() {
        _peopleInvolved.add(v);
        _personController.clear();
      });
    }
  }

  void _removePerson(int index) {
    setState(() => _peopleInvolved.removeAt(index));
  }

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: ['pdf', 'doc', 'docx', 'jpg', 'jpeg', 'png', 'xls', 'xlsx', 'txt'],
    );
    if (result == null || result.files.isEmpty) return;
    final newFiles = result.files
        .where((f) => f.path != null)
        .map((f) => File(f.path!))
        .toList();
    setState(() {
      for (final f in newFiles) {
        if (!_selectedFiles.any((e) => e.path == f.path)) {
          _selectedFiles.add(f);
        }
      }
    });
  }

  void _removeFile(int index) => setState(() => _selectedFiles.removeAt(index));

  String _fileName(File f) => f.path.split(Platform.pathSeparator).last;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCategoryId == null) {
      SnackBarUtils.showSnackBar(context, 'Please select a category');
      return;
    }
    setState(() => _isLoading = true);
    try {
      final result = await _service.createGrievance(
        categoryId: _selectedCategoryId!,
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        incidentDate: _incidentDate != null ? DateFormat('yyyy-MM-dd').format(_incidentDate!) : null,
        peopleInvolved: _peopleInvolved.isEmpty ? null : _peopleInvolved,
        priority: _priority,
        isAnonymous: _isAnonymous,
      );
      if (!mounted) return;
      setState(() => _isLoading = false);
      if (result['success'] == true) {
        final data = result['data'] as Map<String, dynamic>?;
        final id = data?['_id']?.toString();
        if (id != null) {
          for (final file in _selectedFiles) {
            await _service.uploadAttachment(id, file);
          }
          if (mounted) Navigator.of(context).pop(true);
          if (mounted) {
            SnackBarUtils.showSnackBar(
              context,
              'Grievance submitted successfully',
            );
            await NotificationReactionOverlay.show(
              context,
              emoji: '🤝',
            );
          }
        }
      } else {
        SnackBarUtils.showSnackBar(
          context,
          ErrorMessageUtils.sanitizeForDisplay(result['message']?.toString(), fallback: 'Failed to submit'),
          isError: true,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        SnackBarUtils.showSnackBar(
          context,
          'Something went wrong',
          isError: true,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Back',
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Raise Grievance'),
      ),
      body: Column(
        children: [
          Expanded(
            child: Container(
              color: AppColors.surface,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(Icons.shield_outlined, size: 20, color: AppColors.primaryText),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Submit a formal complaint. All submissions are confidential.',
                            style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text('Category *', style: AppTextStyles.label),
                  const SizedBox(height: 8),
                  if (_categoriesLoading)
                    const Center(child: AppTabLoader())
                  else if (_categoriesError != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.errorBg,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.error_outline_rounded, size: 20, color: AppColors.error),
                          const SizedBox(width: 8),
                          Expanded(child: Text(_categoriesError!, style: const TextStyle(color: AppColors.error, fontSize: 13))),
                        ],
                      ),
                    )
                  else if (_categories.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        border: Border.all(color: const Color(0xFFE2E5EA)),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'No categories available. Contact HR to set up grievance categories.',
                        style: AppTextStyles.bodySmall,
                      ),
                    )
                  else
                    DropdownButtonFormField<String>(
                      initialValue: _selectedCategoryId,
                      isExpanded: true,
                      icon: const Icon(Icons.keyboard_arrow_down_rounded),
                      borderRadius: BorderRadius.circular(12),
                      decoration: const InputDecoration(
                        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                      items: _categories.map((c) {
                        final id = c['_id']?.toString() ?? '';
                        final name = c['name']?.toString() ?? '';
                        return DropdownMenuItem(value: id, child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis));
                      }).toList(),
                      onChanged: (v) => setState(() => _selectedCategoryId = v),
                    ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _titleController,
                    decoration: const InputDecoration(
                      labelText: 'Title *',
                      hintText: 'Brief description of your grievance',
                      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    maxLength: 200,
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _descriptionController,
                    decoration: const InputDecoration(
                      labelText: 'Description *',
                      hintText: 'Provide detailed information...',
                      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      alignLabelWithHint: true,
                    ),
                    maxLines: 6,
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 20),
                  const Text('Incident Date (Optional)', style: AppTextStyles.label),
                  const SizedBox(height: 8),
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate: _incidentDate ?? DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (d != null) setState(() => _incidentDate = d);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF7F8FA),
                        border: Border.all(color: const Color(0xFFE2E5EA)),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.calendar_today_outlined, size: 20, color: AppColors.primaryText),
                          const SizedBox(width: 12),
                          Text(
                            _incidentDate != null ? DateFormat('MMM d, yyyy').format(_incidentDate!) : 'Pick a date',
                            style: TextStyle(
                              fontSize: 14,
                              color: _incidentDate != null ? AppColors.textPrimary : AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text('People Involved (Optional)', style: AppTextStyles.label),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _personController,
                          decoration: const InputDecoration(
                            hintText: 'Enter name and tap Add',
                            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          ),
                          onSubmitted: (_) => _addPerson(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: _addPerson,
                        child: const Text('Add'),
                      ),
                    ],
                  ),
                  if (_peopleInvolved.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _peopleInvolved.asMap().entries.map((e) {
                        return Chip(
                          avatar: Icon(Icons.person_outline_rounded, size: 18, color: AppColors.primaryText),
                          label: Text(e.value),
                          onDeleted: () => _removePerson(e.key),
                          deleteIcon: const Icon(Icons.close_rounded, size: 18),
                          deleteIconColor: AppColors.error,
                        );
                      }).toList(),
                    ),
                  ],
                  const SizedBox(height: 20),
                  const Text('Priority', style: AppTextStyles.label),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: _priority,
                    icon: const Icon(Icons.keyboard_arrow_down_rounded),
                    borderRadius: BorderRadius.circular(12),
                    decoration: const InputDecoration(
                      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'Low', child: Text('Low')),
                      DropdownMenuItem(value: 'Medium', child: Text('Medium')),
                      DropdownMenuItem(value: 'High', child: Text('High')),
                      DropdownMenuItem(value: 'Critical', child: Text('Critical')),
                    ],
                    onChanged: (v) => setState(() => _priority = v ?? 'Medium'),
                  ),
                  const SizedBox(height: 20),
                  Card(
                    margin: EdgeInsets.zero,
                    clipBehavior: Clip.antiAlias,
                    child: SwitchListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      secondary: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppColors.indigoBg,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.visibility_off_outlined, size: 20, color: AppColors.indigo),
                      ),
                      title: const Text('Submit Anonymously', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                      subtitle: const Text('Your identity will be hidden from HR', style: AppTextStyles.bodySmall),
                      value: _isAnonymous,
                      onChanged: (v) => setState(() => _isAnonymous = v),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text('Attachments (Optional)', style: AppTextStyles.label),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: _pickFiles,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                      decoration: BoxDecoration(
                        border: Border.all(color: AppColors.primary.withValues(alpha: 0.4), style: BorderStyle.solid),
                        borderRadius: BorderRadius.circular(16),
                        color: AppColors.primary.withValues(alpha: 0.05),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(Icons.upload_file_outlined, size: 24, color: AppColors.primaryText),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Tap to upload files',
                            style: TextStyle(color: AppColors.primaryText, fontSize: 14, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'PDF, DOC, DOCX, Images, Excel, TXT',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_selectedFiles.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    ...List.generate(_selectedFiles.length, (i) {
                      final name = _fileName(_selectedFiles[i]);
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          border: Border.all(color: const Color(0xFFECEEF1)),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: AppColors.infoBg,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.insert_drive_file_outlined, size: 18, color: AppColors.info),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textPrimary)),
                            ),
                            GestureDetector(
                              onTap: () => _removeFile(i),
                              behavior: HitTestBehavior.opaque,
                              child: const Padding(
                                padding: EdgeInsets.all(12),
                                child: Icon(Icons.close_rounded, size: 18, color: AppColors.error),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                  const SizedBox(height: 28),
                  FilledButton(
                    onPressed: _isLoading ? null : _submit,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                    child: _isLoading
                        ? SizedBox(
                            height: 24,
                            width: 24,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onPrimary),
                          )
                        : const Text('Submit Grievance'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
        ],
      ),
      bottomNavigationBar: const AppBottomNavigationBar(currentIndex: -1),
    );
  }
}
