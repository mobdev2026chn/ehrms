import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../config/app_colors.dart';
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
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Raise Grievance', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: Column(
        children: [
          Expanded(
            child: Container(
              color: Colors.white,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                  Text(
                    'Submit a formal complaint. All submissions are confidential.',
                    style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 14),
                  ),
                  const SizedBox(height: 20),
                  const Text('Category *', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  if (_categoriesLoading)
                    const Center(child: AppTabLoader())
                  else if (_categoriesError != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colorScheme.errorContainer.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(_categoriesError!, style: TextStyle(color: colorScheme.error)),
                    )
                  else if (_categories.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        border: Border.all(color: colorScheme.outline),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'No categories available. Contact HR to set up grievance categories.',
                        style: TextStyle(color: colorScheme.onSurfaceVariant),
                      ),
                    )
                  else
                    DropdownButtonFormField<String>(
                      initialValue: _selectedCategoryId,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                      items: _categories.map((c) {
                        final id = c['_id']?.toString() ?? '';
                        final name = c['name']?.toString() ?? '';
                        return DropdownMenuItem(value: id, child: Text(name));
                      }).toList(),
                      onChanged: (v) => setState(() => _selectedCategoryId = v),
                    ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _titleController,
                    decoration: InputDecoration(
                      labelText: 'Title *',
                      hintText: 'Brief description of your grievance',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    maxLength: 200,
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _descriptionController,
                    decoration: InputDecoration(
                      labelText: 'Description *',
                      hintText: 'Provide detailed information...',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      alignLabelWithHint: true,
                    ),
                    maxLines: 6,
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 16),
                  const Text('Incident Date (Optional)', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  InkWell(
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
                        border: Border.all(color: colorScheme.outline),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.calendar_today, color: colorScheme.primary),
                          const SizedBox(width: 12),
                          Text(
                            _incidentDate != null ? DateFormat('MMM d, yyyy').format(_incidentDate!) : 'Pick a date',
                            style: TextStyle(
                              color: _incidentDate != null ? colorScheme.onSurface : colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('People Involved (Optional)', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _personController,
                          decoration: InputDecoration(
                            hintText: 'Enter name and tap Add',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          ),
                          onSubmitted: (_) => _addPerson(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: _addPerson,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Add'),
                      ),
                    ],
                  ),
                  if (_peopleInvolved.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _peopleInvolved.asMap().entries.map((e) {
                        return Chip(
                          label: Text(e.value),
                          onDeleted: () => _removePerson(e.key),
                          deleteIconColor: AppColors.error,
                        );
                      }).toList(),
                    ),
                  ],
                  const SizedBox(height: 16),
                  const Text('Priority', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    initialValue: _priority,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'Low', child: Text('Low')),
                      DropdownMenuItem(value: 'Medium', child: Text('Medium')),
                      DropdownMenuItem(value: 'High', child: Text('High')),
                      DropdownMenuItem(value: 'Critical', child: Text('Critical')),
                    ],
                    onChanged: (v) => setState(() => _priority = v ?? 'Medium'),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: SwitchListTile(
                      title: const Text('Submit Anonymously'),
                      subtitle: const Text('Your identity will be hidden from HR'),
                      value: _isAnonymous,
                      onChanged: (v) => setState(() => _isAnonymous = v),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('Attachments (Optional)', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: _pickFiles,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      decoration: BoxDecoration(
                        border: Border.all(color: colorScheme.outline, style: BorderStyle.solid),
                        borderRadius: BorderRadius.circular(12),
                        color: colorScheme.surfaceContainerLowest,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.upload_file_outlined, size: 32, color: AppColors.primary),
                          const SizedBox(height: 8),
                          Text(
                            'Tap to upload files',
                            style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'PDF, DOC, DOCX, Images, Excel, TXT',
                            style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_selectedFiles.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    ...List.generate(_selectedFiles.length, (i) {
                      final name = _fileName(_selectedFiles[i]);
                      return Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          border: Border.all(color: colorScheme.outline),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.insert_drive_file_outlined, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                            ),
                            GestureDetector(
                              onTap: () => _removeFile(i),
                              child: const Icon(Icons.close, size: 18, color: AppColors.error),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _isLoading ? null : _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            height: 24,
                            width: 24,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
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
