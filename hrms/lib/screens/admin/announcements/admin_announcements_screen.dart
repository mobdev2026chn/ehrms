// Admin Announcements: list every announcement (any status), post a new one, delete.
// HRMSbackend /api/admin/announcements. Staff see published ones via their Announcements module.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../services/admin_announcement_service.dart';
import '../../../utils/snackbar_utils.dart';

class AdminAnnouncementsScreen extends StatefulWidget {
  const AdminAnnouncementsScreen({super.key});

  @override
  State<AdminAnnouncementsScreen> createState() => _AdminAnnouncementsScreenState();
}

class _AdminAnnouncementsScreenState extends State<AdminAnnouncementsScreen> {
  static const _accent = Color(0xFFEFAA1F);
  static const _ink = Color(0xFF0F172A);
  static const _muted = Color(0xFF64748B);

  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _error = null);
    final r = await AdminAnnouncementService.instance.list();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r['success'] == true) {
        _items = List<Map<String, dynamic>>.from(r['data'] as List);
      } else {
        _error = r['message']?.toString() ?? 'Could not load announcements.';
      }
    });
  }

  /// Same rule as the staff view: Draft → Expired → Scheduled → Published.
  String _status(Map<String, dynamic> a) {
    if (a['isDraft'] == true) return 'Draft';
    final now = DateTime.now();
    DateTime? d(dynamic v) => v == null ? null : DateTime.tryParse(v.toString());
    final expiry = d(a['expiryDate']);
    if (expiry != null && expiry.isBefore(DateTime(now.year, now.month, now.day))) return 'Expired';
    final publish = d(a['publishDate']);
    if (publish != null && publish.isAfter(now)) return 'Scheduled';
    return 'Published';
  }

  Future<void> _delete(Map<String, dynamic> a) async {
    final id = (a['_id'] ?? a['id'] ?? '').toString();
    if (id.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete announcement'),
        content: Text('Delete “${a['title'] ?? 'this announcement'}”? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDC2626), foregroundColor: Colors.white),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final r = await AdminAnnouncementService.instance.delete(id);
    if (!mounted) return;
    if (r['success'] == true) {
      SnackBarUtils.showSnackBar(context, 'Announcement deleted.');
      _load();
    } else {
      SnackBarUtils.showSnackBar(context, r['message']?.toString() ?? 'Could not delete.', isError: true);
    }
  }

  Future<void> _create() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _CreateAnnouncementSheet(),
    );
    if (created == true) _load();
  }

  static const _statusColors = <String, (Color, Color)>{
    'Published': (Color(0xFFDCFCE7), Color(0xFF15803D)),
    'Scheduled': (Color(0xFFDBEAFE), Color(0xFF1D4ED8)),
    'Draft': (Color(0xFFF1F5F9), Color(0xFF475569)),
    'Expired': (Color(0xFFFEE2E2), Color(0xFFB91C1C)),
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        foregroundColor: _ink,
        title: const Text('Announcements', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        actions: [IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh_rounded))],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        backgroundColor: _accent,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('New', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2.5))
          : RefreshIndicator(
              onRefresh: _load,
              child: (_error != null && _items.isEmpty)
                  ? _center(Icons.wifi_off_rounded, 'Could not load', _error!)
                  : _items.isEmpty
                      ? _center(Icons.campaign_outlined, 'No announcements', 'Tap New to post one.')
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(14, 12, 14, 90),
                          children: _items.map(_card).toList(),
                        ),
            ),
    );
  }

  Widget _card(Map<String, dynamic> a) {
    final status = _status(a);
    final (bg, fg) = _statusColors[status] ?? _statusColors['Draft']!;
    final title = (a['title'] ?? 'Announcement').toString();
    final subject = (a['subject'] ?? a['description'] ?? '').toString();
    final audience = (a['audience'] ?? '').toString();
    final pub = a['publishDate'];
    final pubD = pub != null ? DateTime.tryParse(pub.toString()) : null;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFF1F5F9)),
        boxShadow: const [BoxShadow(color: Color(0x08000000), blurRadius: 8, offset: Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.campaign_rounded, size: 16, color: _accent),
          const SizedBox(width: 6),
          Expanded(child: Text(audience.isNotEmpty ? audience : 'Announcement', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _muted))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
            child: Text(status.toUpperCase(), style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: fg)),
          ),
        ]),
        const SizedBox(height: 8),
        Text(title, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: _ink, height: 1.3)),
        if (subject.isNotEmpty) ...[
          const SizedBox(height: 3),
          Text(subject, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: _muted, height: 1.4)),
        ],
        const SizedBox(height: 8),
        Row(children: [
          const Icon(Icons.event_outlined, size: 14, color: _muted),
          Text(' ${pubD != null ? DateFormat('d MMM yyyy').format(pubD) : '—'}', style: const TextStyle(fontSize: 12, color: _muted)),
          const Spacer(),
          TextButton.icon(
            onPressed: () => _delete(a),
            icon: const Icon(Icons.delete_outline_rounded, size: 16),
            label: const Text('Delete'),
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFDC2626), padding: const EdgeInsets.symmetric(horizontal: 8)),
          ),
        ]),
      ]),
    );
  }

  Widget _center(IconData icon, String title, String msg) => ListView(children: [
        const SizedBox(height: 120),
        Icon(icon, size: 40, color: _muted),
        const SizedBox(height: 10),
        Center(child: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: _ink))),
        const SizedBox(height: 4),
        Center(child: Text(msg, style: const TextStyle(fontSize: 12.5, color: _muted))),
        const SizedBox(height: 12),
        Center(child: OutlinedButton(onPressed: _load, child: const Text('Retry'))),
      ]);
}

class _CreateAnnouncementSheet extends StatefulWidget {
  const _CreateAnnouncementSheet();

  @override
  State<_CreateAnnouncementSheet> createState() => _CreateAnnouncementSheetState();
}

class _CreateAnnouncementSheetState extends State<_CreateAnnouncementSheet> {
  static const _accent = Color(0xFFEFAA1F);
  final _title = TextEditingController();
  final _subject = TextEditingController();
  final _body = TextEditingController();
  String _audience = 'All Staff';
  DateTime? _expiry;
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _subject.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _submit({required bool draft}) async {
    if (_title.text.trim().isEmpty) {
      SnackBarUtils.showSnackBar(context, 'Title is required.', isError: true);
      return;
    }
    setState(() => _saving = true);
    final r = await AdminAnnouncementService.instance.create(
      title: _title.text.trim(),
      subject: _subject.text.trim(),
      description: _body.text.trim(),
      audience: _audience,
      publishDate: DateTime.now(),
      expiryDate: _expiry,
      isDraft: draft,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (r['success'] == true) {
      SnackBarUtils.showSnackBar(context, draft ? 'Saved as draft.' : 'Announcement posted.');
      Navigator.pop(context, true);
    } else {
      SnackBarUtils.showSnackBar(context, r['message']?.toString() ?? 'Could not save.', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: const Color(0xFFE2E8F0), borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 14),
            const Text('New announcement', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            _field(_title, 'Title', 'e.g. Office closed on Friday'),
            const SizedBox(height: 10),
            _field(_subject, 'Subject', 'Short summary'),
            const SizedBox(height: 10),
            _field(_body, 'Message', 'Full announcement text', lines: 4),
            const SizedBox(height: 10),
            const Text('Audience', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Color(0xFF64748B))),
            const SizedBox(height: 6),
            Wrap(spacing: 8, children: AdminAnnouncementService.audiences.map((a) {
              final sel = a == _audience;
              return ChoiceChip(
                selected: sel,
                onSelected: (_) => setState(() => _audience = a),
                showCheckmark: false,
                selectedColor: _accent,
                backgroundColor: const Color(0xFFF1F5F9),
                side: BorderSide.none,
                label: Text(a, style: TextStyle(fontWeight: FontWeight.w700, color: sel ? Colors.white : const Color(0xFF0F172A))),
              );
            }).toList()),
            const SizedBox(height: 12),
            Row(children: [
              const Icon(Icons.event_busy_outlined, size: 18, color: Color(0xFF64748B)),
              const SizedBox(width: 8),
              Text(_expiry == null ? 'No expiry' : 'Expires ${DateFormat('d MMM yyyy').format(_expiry!)}', style: const TextStyle(fontSize: 13)),
              const Spacer(),
              TextButton(
                onPressed: () async {
                  final now = DateTime.now();
                  final picked = await showDatePicker(context: context, initialDate: now.add(const Duration(days: 7)), firstDate: now, lastDate: DateTime(now.year + 2));
                  if (picked != null) setState(() => _expiry = picked);
                },
                child: Text(_expiry == null ? 'Set expiry' : 'Change'),
              ),
              if (_expiry != null) IconButton(onPressed: () => setState(() => _expiry = null), icon: const Icon(Icons.close_rounded, size: 18)),
            ]),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _saving ? null : () => _submit(draft: true),
                  child: const Text('Save draft'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: _saving ? null : () => _submit(draft: false),
                  style: ElevatedButton.styleFrom(backgroundColor: _accent, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
                  child: _saving
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Post', style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _field(TextEditingController c, String label, String hint, {int lines = 1}) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Color(0xFF64748B))),
          const SizedBox(height: 6),
          TextField(
            controller: c,
            maxLines: lines,
            decoration: InputDecoration(
              hintText: hint,
              isDense: true,
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _accent, width: 1.5)),
            ),
          ),
        ],
      );
}
