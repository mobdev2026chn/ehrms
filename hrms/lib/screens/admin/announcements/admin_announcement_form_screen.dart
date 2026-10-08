// Admin "New announcement" form, matching the web admin: title, sender, cover poster,
// audience (All Staff / Individual Staff with a staff picker from GET /admin/staff),
// publish + expiry dates, attachments, subject, content and subsections. Publish or save
// as draft via POST /admin/announcements. The backend has no update route, so there is
// no edit mode.
//
// Images (cover, subsection images) and attachment files go up as base64 data URLs,
// which the backend uploads to storage so staff can open them.

import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../config/app_colors.dart';
import '../../../config/app_text_styles.dart';
import '../../../services/admin_announcement_service.dart';
import '../../../utils/snackbar_utils.dart';
import '../../../widgets/app_tab_loader.dart';
import 'announcement_ui.dart';

class AdminAnnouncementFormScreen extends StatefulWidget {
  const AdminAnnouncementFormScreen({super.key});

  @override
  State<AdminAnnouncementFormScreen> createState() => _AdminAnnouncementFormScreenState();
}

class _PickedImage {
  _PickedImage(this.name, this.bytes);
  final String name;
  final Uint8List bytes;
}

class _Subsection {
  _Subsection(this.id);
  final String id;
  final title = TextEditingController();
  final content = TextEditingController();
  _PickedImage? image;
  void dispose() {
    title.dispose();
    content.dispose();
  }
}

class _AdminAnnouncementFormScreenState extends State<AdminAnnouncementFormScreen> {
  static const _titleLimit = 120;
  static const _subjectLimit = 160;
  static const _maxImageBytes = 5 * 1024 * 1024;

  /// The route's JSON body limit is 25mb; base64 grows bytes by a third.
  static const _maxPayloadBytes = 15 * 1024 * 1024;

  final _svc = AdminAnnouncementService.instance;
  final _title = TextEditingController();
  final _from = TextEditingController();
  final _subject = TextEditingController();
  final _description = TextEditingController();

  _PickedImage? _cover;
  String _audience = 'All Staff';
  final List<Map<String, dynamic>> _selectedStaff = [];
  DateTime? _publishDate;
  DateTime? _expiryDate;
  final List<Map<String, dynamic>> _attachments = [];
  final List<_Subsection> _subsections = [];
  final Map<String, String> _errors = {};
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _from.dispose();
    _subject.dispose();
    _description.dispose();
    for (final s in _subsections) {
      s.dispose();
    }
    super.dispose();
  }

  bool get _dirty =>
      _title.text.isNotEmpty ||
      _from.text.isNotEmpty ||
      _subject.text.isNotEmpty ||
      _description.text.isNotEmpty ||
      _cover != null ||
      _publishDate != null ||
      _expiryDate != null ||
      _selectedStaff.isNotEmpty ||
      _attachments.isNotEmpty ||
      _subsections.isNotEmpty;

  String _newId(String prefix) => '$prefix-${DateTime.now().microsecondsSinceEpoch}';

  Future<_PickedImage?> _pickImage() async {
    try {
      final r = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
      if (r == null || r.files.isEmpty) return null;
      final f = r.files.first;
      final bytes = f.bytes;
      if (bytes == null) {
        if (mounted) SnackBarUtils.showSnackBar(context, 'Could not read that image.', isError: true);
        return null;
      }
      if (bytes.length > _maxImageBytes) {
        if (mounted) SnackBarUtils.showSnackBar(context, 'That image is over 5MB. Pick a smaller one.', isError: true);
        return null;
      }
      return _PickedImage(f.name, bytes);
    } catch (e) {
      if (mounted) SnackBarUtils.showSnackBar(context, 'Could not open the image picker.', isError: true);
      return null;
    }
  }

  Future<void> _pickAttachments() async {
    try {
      final r = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'gif', 'webp'],
        withData: true,
      );
      if (r == null || r.files.isEmpty || !mounted) return;
      final skipped = <String>[];
      setState(() {
        for (final f in r.files) {
          final bytes = f.bytes;
          if (bytes == null || bytes.length > _maxImageBytes) {
            skipped.add(f.name);
            continue;
          }
          _attachments.add({'id': _newId('att'), 'name': f.name, 'size': f.size, 'bytes': bytes});
        }
      });
      if (skipped.isNotEmpty) {
        SnackBarUtils.showSnackBar(
          context,
          'Not added (unreadable or over 5MB): ${skipped.join(', ')}',
          isError: true,
        );
      }
    } catch (e) {
      if (mounted) SnackBarUtils.showSnackBar(context, 'Could not open the file picker.', isError: true);
    }
  }

  Future<void> _pickDate({required bool publish}) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final current = publish ? _publishDate : _expiryDate;
    final first = publish ? DateTime(now.year - 1) : (_publishDate ?? today);
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? (first.isAfter(today) ? first : today),
      firstDate: first,
      lastDate: DateTime(now.year + 3),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (publish) {
        _publishDate = picked;
        if (_expiryDate != null && _expiryDate!.isBefore(picked)) _expiryDate = null;
      } else {
        _expiryDate = picked;
      }
      _errors.remove('expiryDate');
    });
  }

  Future<void> _pickStaff() async {
    final result = await showModalBottomSheet<List<Map<String, dynamic>>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _StaffPickerSheet(initial: _selectedStaff),
    );
    if (result == null || !mounted) return;
    setState(() {
      _selectedStaff
        ..clear()
        ..addAll(result);
      _errors.remove('staff');
    });
  }

  bool _validate(bool asDraft) {
    _errors.clear();
    if (_title.text.trim().isEmpty) _errors['title'] = 'Give the announcement a title.';
    if (!asDraft) {
      if (_subject.text.trim().isEmpty) _errors['subject'] = 'Add a short subject line.';
      if (_description.text.trim().isEmpty) _errors['description'] = 'Write the announcement content.';
      if (_audience == 'Individual Staff' && _selectedStaff.isEmpty) {
        _errors['staff'] = 'Select at least one staff member.';
      }
    }
    if (_publishDate != null && _expiryDate != null && _expiryDate!.isBefore(_publishDate!)) {
      _errors['expiryDate'] = 'The expiry date cannot fall before the publish date.';
    }
    setState(() {});
    return _errors.isEmpty;
  }

  Future<void> _save({required bool asDraft}) async {
    if (_saving) return;
    if (!_validate(asDraft)) {
      SnackBarUtils.showSnackBar(context, 'Check the highlighted fields.', isError: true);
      return;
    }
    var payloadBytes = _cover?.bytes.length ?? 0;
    for (final s in _subsections) {
      payloadBytes += s.image?.bytes.length ?? 0;
    }
    for (final a in _attachments) {
      payloadBytes += (a['bytes'] as Uint8List).length;
    }
    if (payloadBytes > _maxPayloadBytes) {
      SnackBarUtils.showSnackBar(context, 'Images and attachments are too large together (max 15MB). Remove some.', isError: true);
      return;
    }

    setState(() => _saving = true);
    final subsections = <Map<String, dynamic>>[];
    for (final s in _subsections) {
      final t = s.title.text.trim();
      final c = s.content.text.trim();
      if (t.isEmpty && c.isEmpty && s.image == null) continue;
      subsections.add({
        'id': s.id,
        'title': t,
        'content': c,
        'heading': t,
        'body': c,
        'image': s.image == null ? null : {'url': AdminAnnouncementService.imageDataUrl(s.image!.bytes, s.image!.name), 'name': s.image!.name},
      });
    }

    final r = await _svc.create(
      title: _title.text.trim(),
      subject: _subject.text.trim(),
      description: _description.text.trim(),
      from: _from.text.trim(),
      audience: _audience,
      targetStaff: _selectedStaff.map((s) => {'id': s['id'], 'name': s['name'], 'designation': s['designation'] ?? ''}).toList(),
      coverUrl: _cover == null ? null : AdminAnnouncementService.imageDataUrl(_cover!.bytes, _cover!.name),
      attachments: [
        for (final a in _attachments)
          {
            'id': a['id'],
            'name': a['name'],
            'size': a['size'],
            'url': AdminAnnouncementService.fileDataUrl(a['bytes'] as Uint8List, a['name'] as String),
          },
      ],
      subsections: subsections,
      publishDate: _publishDate,
      expiryDate: _expiryDate,
      isDraft: asDraft,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (r['success'] == true) {
      SnackBarUtils.showSnackBar(context, r['message']?.toString() ?? (asDraft ? 'Saved as a draft.' : 'Announcement published.'));
      Navigator.of(context).pop(true);
    } else {
      SnackBarUtils.showSnackBar(context, r['message']?.toString() ?? 'Could not save the announcement.', isError: true);
    }
  }

  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard this announcement?'),
        content: const Text('Everything typed here will be lost.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep editing')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error, foregroundColor: Colors.white),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || _saving) return;
        final nav = Navigator.of(context);
        if (await _confirmDiscard()) nav.pop(false);
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('New announcement'),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            _card('Details', [
              _field(_title, 'Title', 'e.g. Office closed on Friday', required: true, maxLength: _titleLimit, errorKey: 'title'),
              _field(_from, 'From', 'Sender name (optional)'),
              _label('Cover poster'),
              _coverPicker(),
            ]),
            _card('Audience & schedule', [
              _label('Audience', required: true),
              Wrap(spacing: 8, children: [
                for (final a in AdminAnnouncementService.audiences)
                  ChoiceChip(
                    selected: a == _audience,
                    onSelected: (_) => setState(() {
                      _audience = a;
                      _errors.remove('staff');
                    }),
                    showCheckmark: false,
                    selectedColor: AppColors.primary,
                    label: Text(a, style: TextStyle(fontWeight: FontWeight.w600, color: a == _audience ? AppColors.onPrimary : AppColors.textSecondary)),
                  ),
              ]),
              if (_audience == 'Individual Staff') ...[
                const SizedBox(height: 12),
                _staffSelector(),
              ],
              const SizedBox(height: 12),
              _dateRow('Publish date', _publishDate, 'Publish immediately', () => _pickDate(publish: true), () => setState(() => _publishDate = null)),
              _dateRow('Expiry date', _expiryDate, 'No expiry', () => _pickDate(publish: false), () => setState(() => _expiryDate = null)),
              if (_errors['expiryDate'] != null) _errorText(_errors['expiryDate']!),
            ]),
            _card('Content', [
              _field(_subject, 'Subject', 'Short summary shown in lists', required: true, maxLength: _subjectLimit, errorKey: 'subject'),
              _field(_description, 'Content', 'Full announcement text', required: true, lines: 6, errorKey: 'description'),
            ]),
            _card('Attachments', [
              for (var i = 0; i < _attachments.length; i++)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.info.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.insert_drive_file_outlined, size: 20, color: AppColors.info),
                  ),
                  title: Text(_attachments[i]['name'].toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.label),
                  subtitle: Text(formatAnnouncementBytes(_attachments[i]['size'] as num), style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary)),
                  trailing: IconButton(tooltip: 'Remove file', icon: const Icon(Icons.close_rounded, size: 18), onPressed: () => setState(() => _attachments.removeAt(i))),
                ),
              if (_attachments.isNotEmpty) const SizedBox(height: 8),
              OutlinedButton.icon(onPressed: _pickAttachments, icon: const Icon(Icons.attach_file_rounded, size: 18), label: const Text('Add files (PDF or image)')),
            ]),
            _card('Subsections', [
              for (var i = 0; i < _subsections.length; i++) _subsectionEditor(i),
              OutlinedButton.icon(
                onPressed: () => setState(() => _subsections.add(_Subsection(_newId('sub')))),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add subsection'),
              ),
            ]),
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Container(
            decoration: const BoxDecoration(
              color: AppColors.surface,
              border: Border(top: BorderSide(color: Color(0xFFECEEF1))),
            ),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(children: [
              Expanded(
                flex: 2,
                child: OutlinedButton(
                  onPressed: _saving ? null : () => _save(asDraft: true),
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                  child: const Text('Save draft'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 3,
                child: ElevatedButton(
                  onPressed: _saving ? null : () => _save(asDraft: false),
                  style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                  child: _saving
                      ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onPrimary))
                      : const Text('Publish'),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _coverPicker() {
    if (_cover == null) {
      return OutlinedButton.icon(
        onPressed: () async {
          final img = await _pickImage();
          if (img != null && mounted) setState(() => _cover = img);
        },
        icon: const Icon(Icons.image_outlined, size: 18),
        label: const Text('Choose image (max 5MB)'),
      );
    }
    return Stack(children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: AspectRatio(aspectRatio: 16 / 9, child: Image.memory(_cover!.bytes, fit: BoxFit.cover)),
      ),
      Positioned(
        top: 8,
        right: 8,
        child: IconButton.filled(
          tooltip: 'Remove cover',
          style: IconButton.styleFrom(backgroundColor: Colors.black54, foregroundColor: Colors.white),
          onPressed: () => setState(() => _cover = null),
          icon: const Icon(Icons.close_rounded, size: 18),
        ),
      ),
    ]);
  }

  Widget _staffSelector() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: _label('Selected staff (${_selectedStaff.length})', required: true)),
        TextButton.icon(onPressed: _pickStaff, icon: const Icon(Icons.person_add_alt_1_outlined, size: 18), label: const Text('Select')),
      ]),
      if (_selectedStaff.isNotEmpty)
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final s in _selectedStaff)
            InputChip(
              visualDensity: VisualDensity.compact,
              backgroundColor: AppColors.primary.withValues(alpha: 0.12),
              side: BorderSide.none,
              deleteIconColor: AppColors.primaryText,
              label: Text(s['name'].toString(), style: TextStyle(fontSize: 12, color: AppColors.primaryText, fontWeight: FontWeight.w600)),
              onDeleted: () => setState(() => _selectedStaff.removeWhere((x) => x['id'] == s['id'])),
            ),
        ]),
      if (_errors['staff'] != null) _errorText(_errors['staff']!),
    ]);
  }

  Widget _subsectionEditor(int i) {
    final s = _subsections[i];
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 12),
      decoration: BoxDecoration(color: const Color(0xFFFAFBFC), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFECEEF1))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('Subsection ${i + 1}', style: AppTextStyles.label.copyWith(fontWeight: FontWeight.w600))),
          IconButton(
            tooltip: 'Remove',
            visualDensity: VisualDensity.compact,
            onPressed: () => setState(() => _subsections.removeAt(i).dispose()),
            icon: const Icon(Icons.delete_outline_rounded, size: 19, color: AppColors.error),
          ),
        ]),
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _field(s.title, 'Heading', 'Section heading'),
        _field(s.content, 'Text', 'Section text', lines: 3),
        if (s.image == null)
          TextButton.icon(
            onPressed: () async {
              final img = await _pickImage();
              if (img != null && mounted) setState(() => s.image = img);
            },
            icon: const Icon(Icons.image_outlined, size: 18),
            label: const Text('Add image'),
          )
        else
          Row(children: [
            ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.memory(s.image!.bytes, width: 64, height: 48, fit: BoxFit.cover)),
            const SizedBox(width: 12),
            Expanded(child: Text(s.image!.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.bodySmall.copyWith(color: AppColors.textPrimary))),
            IconButton(tooltip: 'Remove image', onPressed: () => setState(() => s.image = null), icon: const Icon(Icons.close_rounded, size: 18)),
          ]),
          ]),
        ),
      ]),
    );
  }

  Widget _card(String title, List<Widget> children) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: announcementCardDecoration,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(title, style: AppTextStyles.headingSmall),
          const SizedBox(height: 16),
          ...children,
        ]),
      );

  Widget _label(String t, {bool required = false}) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text.rich(TextSpan(
          text: t,
          style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w600),
          children: [if (required) const TextSpan(text: ' *', style: TextStyle(color: AppColors.error))],
        )),
      );

  Widget _errorText(String t) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(t, style: AppTextStyles.caption.copyWith(color: AppColors.error)),
      );

  Widget _dateRow(String label, DateTime? value, String emptyText, VoidCallback onPick, VoidCallback onClear) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.event_outlined, size: 20, color: AppColors.primaryText),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary)),
              const SizedBox(height: 2),
              Text(value == null ? emptyText : DateFormat('d MMM yyyy').format(value),
                  style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w600)),
            ]),
          ),
          TextButton(onPressed: onPick, child: Text(value == null ? 'Set' : 'Change')),
          if (value != null) IconButton(tooltip: 'Clear date', onPressed: onClear, icon: const Icon(Icons.close_rounded, size: 18)),
        ]),
      );

  Widget _field(TextEditingController c, String label, String hint, {int lines = 1, bool required = false, int? maxLength, String? errorKey}) {
    final err = errorKey == null ? null : _errors[errorKey];
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _label(label, required: required),
        TextField(
          controller: c,
          maxLines: lines,
          minLines: lines > 1 ? lines : null,
          maxLength: maxLength,
          onChanged: (_) {
            if (errorKey != null && _errors.containsKey(errorKey)) setState(() => _errors.remove(errorKey));
          },
          decoration: InputDecoration(
            hintText: hint,
            errorText: err,
          ),
        ),
      ]),
    );
  }
}

/// Multi-select of staff from GET /admin/staff. Pops the chosen `[{id, name, designation}]`.
class _StaffPickerSheet extends StatefulWidget {
  const _StaffPickerSheet({required this.initial});
  final List<Map<String, dynamic>> initial;

  @override
  State<_StaffPickerSheet> createState() => _StaffPickerSheetState();
}

class _StaffPickerSheetState extends State<_StaffPickerSheet> {
  List<Map<String, dynamic>> _all = [];
  late final Map<String, Map<String, dynamic>> _selected = {for (final s in widget.initial) s['id'].toString(): s};
  String _q = '';
  bool _loading = true;
  String? _error;

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
    final r = await AdminAnnouncementService.instance.staffOptions();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r['success'] == true) {
        _all = List<Map<String, dynamic>>.from(r['data'] as List);
      } else {
        _error = r['message']?.toString() ?? 'Could not load staff.';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final q = _q.toLowerCase();
    final filtered = q.isEmpty
        ? _all
        : _all.where((s) => '${s['name']} ${s['designation']} ${s['employeeId']}'.toLowerCase().contains(q)).toList();
    return Container(
      height: MediaQuery.of(context).size.height * 0.8,
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      decoration: const BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      child: Column(children: [
        const SizedBox(height: 12),
        Container(width: 40, height: 4, decoration: BoxDecoration(color: const Color(0xFFE2E5EA), borderRadius: BorderRadius.circular(2))),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
          child: Row(children: [
            Expanded(child: Text('Select staff (${_selected.length})', style: AppTextStyles.headingMedium)),
            TextButton(
              onPressed: () => Navigator.pop(context, _selected.values.toList()),
              child: const Text('Done'),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            onChanged: (v) => setState(() => _q = v.trim()),
            decoration: const InputDecoration(
              hintText: 'Search staff by name or role',
              isDense: true,
              prefixIcon: Icon(Icons.search_rounded, size: 20),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _loading
              ? const Center(child: AppTabLoader())
              : _error != null
                  ? announcementMessageView(icon: Icons.wifi_off_rounded, title: 'Could not load staff', message: _error!, onRetry: _load)
                  : filtered.isEmpty
                      ? announcementMessageView(
                          icon: Icons.person_search_outlined,
                          title: 'No staff found',
                          message: _all.isEmpty ? 'Add staff first to target them.' : 'Try a different search.',
                        )
                      : ListView.builder(
                          itemCount: filtered.length,
                          itemBuilder: (_, i) {
                            final s = filtered[i];
                            final id = s['id'].toString();
                            final sel = _selected.containsKey(id);
                            final sub = [s['designation'], s['employeeId']].where((x) => (x ?? '').toString().isNotEmpty).join(' · ');
                            return CheckboxListTile(
                              value: sel,
                              activeColor: AppColors.primary,
                              checkColor: AppColors.onPrimary,
                              dense: true,
                              title: Text(s['name'].toString(), style: AppTextStyles.label.copyWith(fontWeight: FontWeight.w600)),
                              subtitle: sub.isEmpty ? null : Text(sub, style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary)),
                              onChanged: (v) => setState(() {
                                if (v == true) {
                                  _selected[id] = s;
                                } else {
                                  _selected.remove(id);
                                }
                              }),
                            );
                          },
                        ),
        ),
      ]),
    );
  }
}
