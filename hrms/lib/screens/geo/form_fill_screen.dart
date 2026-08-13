// Form fill screen – arrived screen: fill required form before completing task.
// UI matches profile edit form. Scrollable, keyboard-safe.
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:hrms/config/app_colors.dart';
import 'package:hrms/services/task_service.dart';
import 'package:image_picker/image_picker.dart';
import 'package:hrms/widgets/oriented_image.dart';

class FormFillScreen extends StatefulWidget {
  final Map<String, dynamic> template;
  final String taskMongoId;
  final String staffId;
  final VoidCallback? onFormSubmitted;

  const FormFillScreen({
    super.key,
    required this.template,
    required this.taskMongoId,
    required this.staffId,
    this.onFormSubmitted,
  });

  @override
  State<FormFillScreen> createState() => _FormFillScreenState();
}

class _FormFillScreenState extends State<FormFillScreen> {
  final Map<String, dynamic> _formData = {};
  final Map<String, String> _formErrors = {};
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, FocusNode> _focusNodes = {};
  bool _submitting = false;

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    for (final fn in _focusNodes.values) {
      fn.dispose();
    }
    super.dispose();
  }

  FocusNode _getFocusNode(String name) {
    return _focusNodes.putIfAbsent(name, () => FocusNode());
  }

  TextEditingController _getController(String name, String initial) {
    return _controllers.putIfAbsent(
      name,
      () => TextEditingController(text: initial),
    );
  }

  List<Map<String, dynamic>> get _fields {
    final fields = widget.template['fields'] as List?;
    if (fields == null) return [];
    final list = fields
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    list.sort(
      (a, b) =>
          ((a['order'] as num?) ?? 0).compareTo((b['order'] as num?) ?? 0),
    );
    return list;
  }

  String get _templateName =>
      (widget.template['templateName'] as String?) ?? 'Fill Form';

  String get _templateId {
    final v = widget.template['_id'] ?? widget.template['id'];
    if (v is String) return v;
    if (v is Map && v['\$oid'] != null) return v['\$oid'].toString();
    return v?.toString() ?? '';
  }

  void _setField(String name, dynamic value) {
    setState(() {
      _formData[name] = value;
      _formErrors.remove(name);
    });
  }

  void _syncFromControllers() {
    for (final entry in _controllers.entries) {
      final v = entry.value.text.trim();
      _formData[entry.key] = v.isEmpty ? null : v;
    }
  }

  bool _validate() {
    _syncFromControllers();
    final errors = <String, String>{};
    for (final field in _fields) {
      final name = field['name'] as String?;
      final mandatory = field['mandatory'] as bool? ?? false;
      if (name == null) continue;
      final value = _formData[name];
      if (mandatory && (value == null || value.toString().trim().isEmpty)) {
        errors[name] = '$name is required';
      }
    }
    setState(() {
      _formErrors.clear();
      _formErrors.addAll(errors);
    });
    return errors.isEmpty;
  }

  Future<void> _submit() async {
    if (!_validate()) return;
    setState(() => _submitting = true);
    try {
      await TaskService().submitFormResponse(
        templateId: _templateId,
        taskId: widget.taskMongoId,
        staffId: widget.staffId,
        responses: Map<String, dynamic>.from(_formData),
      );
      await TaskService().updateSteps(widget.taskMongoId, formFilled: true);
      if (mounted) {
        widget.onFormSubmitted?.call();
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _formErrors['_'] = 'Failed to submit: ${e.toString()}';
        });
      }
    }
  }

  Future<void> _pickImage(String fieldName, bool cameraOnly) async {
    try {
      final picker = ImagePicker();
      final xFile = await picker.pickImage(
        source: cameraOnly ? ImageSource.camera : ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1920,
      );
      if (xFile != null && mounted) {
        final bytes = await xFile.readAsBytes();
        final base64 = base64Encode(bytes);
        final mime = xFile.mimeType ?? 'image/jpeg';
        _setField(fieldName, 'data:$mime;base64,$base64');
      }
    } catch (e) {
      if (mounted) {
        _setField(fieldName, null);
        setState(() => _formErrors[fieldName] = 'Failed to pick image');
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
          onPressed: () => Navigator.of(context).pop(false),
        ),
        title: Text(
          _templateName,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                24,
                20,
                24,
                20 + MediaQuery.of(context).viewInsets.bottom + 48,
              ),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Fill in the required information for this form',
                    style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 24),
                  ..._fields.map((field) => _buildField(field)),
                  if (_formErrors['_'] != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _formErrors['_']!,
                      style: const TextStyle(
                        color: AppColors.error,
                        fontSize: 14,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: ElevatedButton(
                      onPressed: _submitting ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.secondary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: _submitting
                          ? const SizedBox(
                              height: 24,
                              width: 24,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Text('Submit Form'),
                    ),
                  ),
                  const SizedBox(height: 30),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  final Set<String> _scrollFocusSetup = {};

  void _setupScrollOnFocus(String fieldName, BuildContext fieldContext) {
    if (_scrollFocusSetup.contains(fieldName)) return;
    _scrollFocusSetup.add(fieldName);
    final fn = _getFocusNode(fieldName);
    fn.addListener(() {
      if (fn.hasFocus && fieldContext.mounted) {
        Future.microtask(() {
          if (fieldContext.mounted) {
            Scrollable.ensureVisible(
              fieldContext,
              alignment: 0.2,
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeInOut,
            );
          }
        });
      }
    });
  }

  Widget _wrapWithScrollOnFocus(
    Widget child,
    BuildContext fieldContext,
    String fieldName,
  ) {
    _setupScrollOnFocus(fieldName, fieldContext);
    return child;
  }

  InputDecoration _buildProfileStyleDecoration({
    required String label,
    required IconData icon,
    String? errorText,
  }) {
    return InputDecoration(
      labelText: label,
      errorText: errorText,
      prefixIcon: Icon(icon, size: 22, color: AppColors.primary),
      labelStyle: const TextStyle(color: Colors.black),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: AppColors.primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.error),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );
  }

  IconData _iconForType(String type) {
    switch (type) {
      case 'Email':
        return Icons.email;
      case 'Phone':
        return Icons.phone;
      case 'Number':
        return Icons.numbers;
      case 'Date':
        return Icons.calendar_today;
      case 'Textarea':
        return Icons.text_fields;
      case 'Image':
        return Icons.image;
      case 'Dropdown':
        return Icons.arrow_drop_down;
      default:
        return Icons.edit;
    }
  }

  Widget _buildField(Map<String, dynamic> field) {
    final name = field['name'] as String? ?? '';
    final type = (field['type'] as String?) ?? 'Text';
    final mandatory = field['mandatory'] as bool? ?? false;
    final cameraOnly = field['cameraOnly'] as bool? ?? false;
    final options = (field['options'] as List?)?.cast<String>() ?? [];
    final error = _formErrors[name];
    final value = _formData[name];
    final label = name + (mandatory ? ' *' : '');

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Builder(
        builder: (fieldContext) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (type == 'Text' || type == 'Email' || type == 'Phone')
                _wrapWithScrollOnFocus(
                  TextFormField(
                    controller: _getController(name, value?.toString() ?? ''),
                    focusNode: _getFocusNode(name),
                    keyboardType: type == 'Email'
                        ? TextInputType.emailAddress
                        : type == 'Phone'
                        ? TextInputType.phone
                        : TextInputType.text,
                    decoration: _buildProfileStyleDecoration(
                      label: label,
                      icon: _iconForType(type),
                      errorText: error,
                    ),
                    onChanged: (v) => _setField(name, v.isEmpty ? null : v),
                  ),
                  fieldContext,
                  name,
                )
              else if (type == 'Textarea')
                _wrapWithScrollOnFocus(
                  TextFormField(
                    controller: _getController(name, value?.toString() ?? ''),
                    focusNode: _getFocusNode(name),
                    maxLines: 4,
                    decoration: _buildProfileStyleDecoration(
                      label: label,
                      icon: Icons.text_fields,
                      errorText: error,
                    ),
                    onChanged: (v) => _setField(name, v.isEmpty ? null : v),
                  ),
                  fieldContext,
                  name,
                )
              else if (type == 'Number')
                _wrapWithScrollOnFocus(
                  TextFormField(
                    controller: _getController(name, value?.toString() ?? ''),
                    focusNode: _getFocusNode(name),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: _buildProfileStyleDecoration(
                      label: label,
                      icon: Icons.numbers,
                      errorText: error,
                    ),
                    onChanged: (v) => _setField(name, v.isEmpty ? null : v),
                  ),
                  fieldContext,
                  name,
                )
              else if (type == 'Date')
                InkWell(
                  onTap: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: DateTime.now(),
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (date != null) {
                      _setField(name, date.toIso8601String().split('T').first);
                    }
                  },
                  child: InputDecorator(
                    decoration: _buildProfileStyleDecoration(
                      label: label,
                      icon: Icons.calendar_today,
                      errorText: error,
                    ),
                    child: Text(
                      value?.toString() ?? 'Select date',
                      style: TextStyle(
                        color: value != null
                            ? Colors.grey.shade800
                            : Colors.grey.shade500,
                      ),
                    ),
                  ),
                )
              else if (type == 'Dropdown')
                DropdownButtonFormField<String>(
                  initialValue: value?.toString().isNotEmpty == true
                      ? value.toString()
                      : null,
                  decoration: _buildProfileStyleDecoration(
                    label: label,
                    icon: Icons.arrow_drop_down,
                    errorText: error,
                  ),
                  items: options
                      .map(
                        (opt) => DropdownMenuItem(value: opt, child: Text(opt)),
                      )
                      .toList(),
                  onChanged: (v) => _setField(name, v),
                )
              else if (type == 'Image')
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InkWell(
                      onTap: () => _pickImage(name, cameraOnly),
                      borderRadius: BorderRadius.circular(16),
                      child: InputDecorator(
                        decoration: _buildProfileStyleDecoration(
                          label: label,
                          icon: Icons.image,
                          errorText: error,
                        ),
                        child: Row(
                          children: [
                            Text(
                              value != null
                                  ? 'Image selected'
                                  : 'Tap to add image',
                              style: TextStyle(
                                color: value != null
                                    ? Colors.grey.shade800
                                    : Colors.grey.shade500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (value != null &&
                        value.toString().startsWith('data:')) ...[
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: OrientedImage.memory(
                          base64Decode(value.toString().split(',').last),
                          height: 120,
                          width: 120,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ],
                  ],
                )
              else
                _wrapWithScrollOnFocus(
                  TextFormField(
                    controller: _getController(name, value?.toString() ?? ''),
                    focusNode: _getFocusNode(name),
                    decoration: _buildProfileStyleDecoration(
                      label: label,
                      icon: Icons.edit,
                      errorText: error,
                    ),
                    onChanged: (v) => _setField(name, v.isEmpty ? null : v),
                  ),
                  fieldContext,
                  name,
                ),
            ],
          );
        },
      ),
    );
  }
}
