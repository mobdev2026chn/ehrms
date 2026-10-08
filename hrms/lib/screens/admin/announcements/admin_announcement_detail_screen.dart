// Admin announcement detail: Announcement tab (cover, content, audience, attachments,
// subsections) and Engagement tab (staff comments + HR replies), like the web admin.
// GET /admin/announcements/:id, POST /admin/announcements/:id/engagements/:engagementId/reply,
// DELETE /admin/announcements/:id.

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../config/app_colors.dart';
import '../../../config/app_text_styles.dart';
import '../../../services/admin_announcement_service.dart';
import '../../../utils/snackbar_utils.dart';
import '../../../widgets/app_tab_loader.dart';
import 'announcement_ui.dart';

class AdminAnnouncementDetailScreen extends StatefulWidget {
  const AdminAnnouncementDetailScreen({super.key, required this.announcementId, this.initial});

  final String announcementId;

  /// Row from the list, shown while the full record loads.
  final Map<String, dynamic>? initial;

  @override
  State<AdminAnnouncementDetailScreen> createState() => _AdminAnnouncementDetailScreenState();
}

class _AdminAnnouncementDetailScreenState extends State<AdminAnnouncementDetailScreen> {
  final _svc = AdminAnnouncementService.instance;
  Map<String, dynamic>? _a;
  bool _loading = true;
  String? _error;
  bool _changed = false;
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    _a = widget.initial;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final r = await _svc.getById(widget.announcementId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r['success'] == true) {
        _a = Map<String, dynamic>.from(r['data'] as Map);
      } else {
        _error = r['message']?.toString() ?? 'Could not load the announcement.';
      }
    });
    if (r['success'] != true && _a != null && mounted) {
      SnackBarUtils.showSnackBar(context, _error!, isError: true);
    }
  }

  Future<void> _delete() async {
    final a = _a;
    if (a == null || _deleting) return;
    final ok = await confirmAnnouncementDelete(context, (a['title'] ?? '').toString());
    if (ok != true || !mounted) return;
    setState(() => _deleting = true);
    final r = await _svc.delete(widget.announcementId);
    if (!mounted) return;
    setState(() => _deleting = false);
    if (r['success'] == true) {
      SnackBarUtils.showSnackBar(context, r['message']?.toString() ?? 'Announcement deleted.');
      Navigator.of(context).pop(true);
    } else {
      SnackBarUtils.showSnackBar(context, r['message']?.toString() ?? 'Could not delete.', isError: true);
    }
  }

  /// Sends a reply; returns true when the backend accepted it.
  Future<bool> _reply(String engagementId, String message) async {
    final r = await _svc.reply(widget.announcementId, engagementId, message);
    if (!mounted) return false;
    if (r['success'] == true) {
      final updated = r['data'];
      setState(() {
        _changed = true;
        if (updated is Map && updated.isNotEmpty) _a = Map<String, dynamic>.from(updated);
      });
      SnackBarUtils.showSnackBar(context, r['message']?.toString() ?? 'Response sent.');
      if (updated is! Map || updated.isEmpty) _load();
      return true;
    }
    SnackBarUtils.showSnackBar(context, r['message']?.toString() ?? 'Could not send the response.', isError: true);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final a = _a;
    final engagements = a?['engagements'] is List ? (a!['engagements'] as List).length : 0;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: DefaultTabController(
        length: 2,
        child: Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            title: const Text('Announcement'),
            actions: [
              IconButton(tooltip: 'Refresh', onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh_rounded)),
              IconButton(
                tooltip: 'Delete',
                onPressed: (a == null || _deleting) ? null : _delete,
                icon: _deleting
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.delete_outline_rounded, color: AppColors.error),
              ),
            ],
            bottom: TabBar(
              tabs: [const Tab(text: 'Announcement'), Tab(text: engagements > 0 ? 'Engagement ($engagements)' : 'Engagement')],
            ),
          ),
          body: a == null
              ? (_loading
                  ? const Center(child: AppTabLoader())
                  : announcementMessageView(
                      icon: Icons.error_outline_rounded,
                      title: 'Could not load',
                      message: _error ?? 'Announcement not found.',
                      onRetry: _load,
                    ))
              : TabBarView(children: [
                  RefreshIndicator(color: AppColors.primary, onRefresh: _load, child: _AnnouncementTab(a: a)),
                  RefreshIndicator(color: AppColors.primary, onRefresh: _load, child: _EngagementTab(a: a, onReply: _reply)),
                ]),
        ),
      ),
    );
  }
}

class _AnnouncementTab extends StatelessWidget {
  const _AnnouncementTab({required this.a});
  final Map<String, dynamic> a;

  Future<void> _openUrl(BuildContext context, String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) {
      SnackBarUtils.showSnackBar(context, 'This file has no downloadable link.', isError: true);
      return;
    }
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && context.mounted) {
        SnackBarUtils.showSnackBar(context, 'Could not open the file.', isError: true);
      }
    } catch (e) {
      if (context.mounted) SnackBarUtils.showSnackBar(context, 'Could not open the file.', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = announcementStatus(a);
    final cover = (a['coverUrl'] ?? '').toString();
    final from = (a['from'] ?? '').toString();
    final subject = (a['subject'] ?? '').toString();
    final description = (a['description'] ?? '').toString();
    final targets = a['targetStaff'] is List ? (a['targetStaff'] as List).whereType<Map>().toList() : const <Map>[];
    final attachments = a['attachments'] is List ? (a['attachments'] as List).whereType<Map>().toList() : const <Map>[];
    final subsections = a['subsections'] is List ? (a['subsections'] as List).whereType<Map>().toList() : const <Map>[];

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        if (cover.startsWith('http'))
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Image.network(cover, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(color: AppColors.inputFill, child: const Icon(Icons.broken_image_outlined, color: AppColors.textSecondary))),
            ),
          ),
        if (cover.startsWith('http')) const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: announcementCardDecoration,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: Text((a['title'] ?? 'Announcement').toString(), style: AppTextStyles.headingMedium)),
              const SizedBox(width: 8),
              AnnouncementStatusBadge(status),
            ]),
            if (subject.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(subject, style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w500, color: AppColors.textSecondary)),
            ],
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 16),
            _meta(Icons.person_outline_rounded, 'From', from.isEmpty ? '-' : from),
            _meta(Icons.groups_2_outlined, 'Audience', (a['audience'] ?? 'All Staff').toString()),
            _meta(Icons.event_available_outlined, 'Publish date', announcementDateLabel(a['publishDate'], empty: 'Immediately')),
            _meta(Icons.event_busy_outlined, 'Expiry date', announcementDateLabel(a['expiryDate'], empty: 'No expiry')),
            _meta(Icons.schedule_outlined, 'Created', announcementDateTimeLabel(a['createdAt'])),
            if (targets.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final t in targets)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      [(t['name'] ?? 'Staff').toString(), if ((t['designation'] ?? '').toString().isNotEmpty) '(${t['designation']})'].join(' '),
                      style: TextStyle(fontSize: 12, color: AppColors.primaryText, fontWeight: FontWeight.w600),
                    ),
                  ),
              ]),
            ],
          ]),
        ),
        const SizedBox(height: 12),
        if (description.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: announcementCardDecoration,
            child: SelectableText(description, style: AppTextStyles.bodyMedium.copyWith(height: 1.55)),
          ),
        if (attachments.isNotEmpty) ...[
          _section('Attachments (${attachments.length})'),
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: announcementCardDecoration,
            child: Material(
              type: MaterialType.transparency,
              child: Column(children: [
                for (var fi = 0; fi < attachments.length; fi++) ...[
                  if (fi > 0) const Divider(height: 1),
                  Builder(builder: (_) {
                    final f = attachments[fi];
                    return ListTile(
                      leading: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppColors.info.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.insert_drive_file_outlined, size: 20, color: AppColors.info),
                      ),
                      title: Text((f['name'] ?? 'attachment').toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.label),
                      subtitle: Text(formatAnnouncementBytes((f['size'] as num?) ?? 0), style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary)),
                      trailing: (f['url'] ?? '').toString().startsWith('http') ? const Icon(Icons.open_in_new_rounded, size: 18, color: AppColors.textCaption) : null,
                      onTap: (f['url'] ?? '').toString().startsWith('http') ? () => _openUrl(context, f['url'].toString()) : null,
                    );
                  }),
                ],
              ]),
            ),
          ),
        ],
        if (subsections.isNotEmpty) ...[
          _section('Subsections (${subsections.length})'),
          for (var i = 0; i < subsections.length; i++) _subsection(i, subsections[i]),
        ],
      ],
    );
  }

  Widget _subsection(int i, Map s) {
    final title = (s['title'] ?? s['heading'] ?? '').toString();
    final content = (s['content'] ?? s['body'] ?? '').toString();
    final img = s['image'];
    final imgUrl = img is Map ? (img['url'] ?? '').toString() : (img is String ? img : '');
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: announcementCardDecoration,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title.isEmpty ? 'Section ${i + 1}' : title, style: AppTextStyles.headingSmall),
        if (imgUrl.startsWith('http')) ...[
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(imgUrl, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(height: 80, color: AppColors.inputFill, child: const Center(child: Icon(Icons.broken_image_outlined, color: AppColors.textSecondary)))),
          ),
        ],
        if (content.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(content, style: AppTextStyles.bodyMedium.copyWith(height: 1.55)),
        ],
      ]),
    );
  }

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 24, 2, 8),
        child: Text(t, style: AppTextStyles.headingSmall),
      );

  Widget _meta(IconData icon, String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 16, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          SizedBox(width: 92, child: Text(label, style: AppTextStyles.bodySmall)),
          Expanded(child: Text(value, style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w600, color: AppColors.textPrimary))),
        ]),
      );
}

class _EngagementTab extends StatelessWidget {
  const _EngagementTab({required this.a, required this.onReply});
  final Map<String, dynamic> a;
  final Future<bool> Function(String engagementId, String message) onReply;

  @override
  Widget build(BuildContext context) {
    final list = a['engagements'] is List ? (a['engagements'] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : <Map<String, dynamic>>[];
    if (list.isEmpty) {
      return announcementMessageView(
        icon: Icons.forum_outlined,
        title: 'No engagement yet',
        message: 'Staff comments on this announcement will appear here.',
      );
    }
    list.sort((x, y) => (announcementDate(y['createdAt']) ?? DateTime(0)).compareTo(announcementDate(x['createdAt']) ?? DateTime(0)));
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [for (final e in list) _EngagementCard(key: ValueKey(e['id']), e: e, onReply: onReply)],
    );
  }
}

class _EngagementCard extends StatefulWidget {
  const _EngagementCard({super.key, required this.e, required this.onReply});
  final Map<String, dynamic> e;
  final Future<bool> Function(String engagementId, String message) onReply;

  @override
  State<_EngagementCard> createState() => _EngagementCardState();
}

class _EngagementCardState extends State<_EngagementCard> {
  final _ctrl = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// `replies` is the current thread; older records only have `hrResponses`.
  List<Map<String, dynamic>> get _replies {
    final e = widget.e;
    final r = e['replies'];
    if (r is List && r.isNotEmpty) return r.whereType<Map>().map((x) => Map<String, dynamic>.from(x)).toList();
    final h = e['hrResponses'];
    if (h is List) return h.whereType<Map>().map((x) => Map<String, dynamic>.from(x)).toList();
    return const [];
  }

  Future<void> _send() async {
    final msg = _ctrl.text.trim();
    final id = (widget.e['id'] ?? '').toString();
    if (msg.isEmpty) {
      SnackBarUtils.showSnackBar(context, 'Type a response first.', isError: true);
      return;
    }
    if (id.isEmpty) return;
    setState(() => _sending = true);
    final ok = await widget.onReply(id, msg);
    if (!mounted) return;
    setState(() => _sending = false);
    if (ok) _ctrl.clear();
  }

  Widget _avatar(String url, String name, {double r = 18}) {
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return CircleAvatar(
      radius: r,
      backgroundColor: AppColors.primary.withValues(alpha: 0.12),
      foregroundImage: url.startsWith('http') ? NetworkImage(url) : null,
      child: Text(initial, style: TextStyle(fontSize: r * 0.8, fontWeight: FontWeight.w700, color: AppColors.primaryText)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.e;
    final name = (e['staffName'] ?? 'Staff Member').toString();
    final empId = (e['employeeId'] ?? '').toString();
    final replies = _replies;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: announcementCardDecoration,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _avatar((e['staffAvatar'] ?? '').toString(), name, r: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: AppTextStyles.label.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text([if (empId.isNotEmpty) 'ID: $empId', announcementDateTimeLabel(e['createdAt'])].where((s) => s.isNotEmpty).join('  ·  '),
                  style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary)),
            ]),
          ),
        ]),
        const SizedBox(height: 12),
        Text((e['comment'] ?? '').toString(), style: AppTextStyles.bodyMedium.copyWith(height: 1.5)),
        if (replies.isNotEmpty) ...[
          const SizedBox(height: 12),
          for (final r in replies)
            Container(
              margin: const EdgeInsets.only(bottom: 8, left: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: (r['senderRole'] ?? 'Admin') == 'Staff' ? const Color(0xFFF7F8FA) : AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _avatar((r['avatarUrl'] ?? '').toString(), (r['senderName'] ?? 'Admin').toString(), r: 13),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${r['senderName'] ?? 'Admin response'}  ·  ${r['senderRole'] ?? 'Admin'}',
                        style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                    const SizedBox(height: 4),
                    Text((r['message'] ?? '').toString(), style: AppTextStyles.bodySmall.copyWith(color: AppColors.textPrimary)),
                    const SizedBox(height: 4),
                    Text(announcementDateTimeLabel(r['createdAt']), style: AppTextStyles.caption.copyWith(fontSize: 11, color: AppColors.textSecondary)),
                  ]),
                ),
              ]),
            ),
        ],
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _ctrl,
              minLines: 1,
              maxLines: 4,
              enabled: !_sending,
              decoration: InputDecoration(
                hintText: replies.isEmpty ? 'Write a response...' : 'Write a follow-up...',
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            onPressed: _sending ? null : _send,
            style: IconButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.onPrimary,
              minimumSize: const Size(44, 44),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: _sending
                ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onPrimary))
                : const Icon(Icons.send_rounded, size: 18),
            tooltip: replies.isEmpty ? 'Send response' : 'Send follow-up',
          ),
        ]),
      ]),
    );
  }
}
