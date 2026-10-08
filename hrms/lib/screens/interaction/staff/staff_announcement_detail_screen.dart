// Announcement detail (HRMSbackend /api/staff/announcements/:id): cover,
// sections, attachments, and the staff member's own comment threads with HR
// replies (comment → POST /:id/engagements, reply → /:id/engagements/:eid/reply).

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../config/app_colors.dart';
import '../../../services/staff_interaction_service.dart';
import '../../../utils/snackbar_utils.dart';
import '../../../widgets/app_card.dart';
import 'attachment_viewer.dart';
import 'staff_interaction_widgets.dart';

class StaffAnnouncementDetailScreen extends StatefulWidget {
  const StaffAnnouncementDetailScreen({super.key, required this.announcementId, this.initial});

  final String announcementId;
  final StaffAnnouncement? initial;

  @override
  State<StaffAnnouncementDetailScreen> createState() => _StaffAnnouncementDetailScreenState();
}

class _StaffAnnouncementDetailScreenState extends State<StaffAnnouncementDetailScreen> {
  final _svc = StaffInteractionService.instance;
  final _input = TextEditingController();
  StaffAnnouncement? _a;
  bool _loading = true;
  String? _error;
  bool _posting = false;

  /// Thread being replied to; null = new comment.
  AnnouncementThread? _replyTo;

  @override
  void initState() {
    super.initState();
    _a = widget.initial;
    _loading = _a == null;
    _load();
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final r = await _svc.getAnnouncement(widget.announcementId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r.ok) {
        _a = r.data;
        _error = null;
      } else if (_a == null) {
        _error = r.error;
      }
    });
  }

  Future<void> _post() async {
    final text = _input.text.trim();
    if (text.isEmpty || _a == null) return;
    setState(() => _posting = true);
    final r = _replyTo == null
        ? await _svc.commentOnAnnouncement(_a!.id, text)
        : await _svc.replyOnAnnouncement(_a!.id, _replyTo!.id, text);
    if (!mounted) return;
    setState(() => _posting = false);
    if (!r.ok) {
      SnackBarUtils.showSnackBar(context, r.error!, isError: true);
      return;
    }
    _input.clear();
    FocusScope.of(context).unfocus();
    setState(() {
      _replyTo = null;
      if (r.data != null) _a = r.data;
    });
    if (r.data == null) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Announcement'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2.5))
          : _a == null
              ? InteractionEmptyState(
                  icon: Icons.campaign_outlined,
                  title: 'Could not load the announcement',
                  message: _error ?? '',
                  action: OutlinedButton(onPressed: _load, child: const Text('Retry')),
                )
              : Column(
                  children: [
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: _load,
                        child: ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.only(bottom: 24),
                          children: _content(_a!),
                        ),
                      ),
                    ),
                    _composer(),
                  ],
                ),
    );
  }

  List<Widget> _content(StaffAnnouncement a) {
    final cover = mediaImageProvider(a.coverUrl);
    return [
      if (cover != null)
        GestureDetector(
          onTap: () => showImageViewer(context, a.coverUrl, title: a.title),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: AspectRatio(
                aspectRatio: 16 / 8,
                child: Image(image: cover, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox()),
              ),
            ),
          ),
        ),
      Container(
        margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        decoration: _cardDecoration,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.campaign_rounded, size: 16, color: AppColors.primaryText),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    a.from.isNotEmpty ? a.from : 'Announcement',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: kInteractionMuted),
                  ),
                ),
                if (a.publishDate != null)
                  Text(
                    DateFormat('d MMM yyyy').format(a.publishDate!),
                    style: const TextStyle(fontSize: 12, color: kInteractionMuted),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(a.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: kInteractionInk, height: 1.3)),
            if (a.subject.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(a.subject, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: kInteractionMuted)),
            ],
            if (a.description.isNotEmpty) ...[
              const SizedBox(height: 12),
              SelectableText(a.description, style: const TextStyle(fontSize: 14.5, color: kInteractionInk, height: 1.5)),
            ],
            if (a.expiryDate != null) ...[
              const SizedBox(height: 12),
              Text(
                'Valid till ${DateFormat('d MMM yyyy').format(a.expiryDate!)}',
                style: const TextStyle(fontSize: 12, color: kInteractionMuted),
              ),
            ],
          ],
        ),
      ),
      for (final s in a.sections)
        if (s.title.isNotEmpty || s.body.isNotEmpty || s.image.isNotEmpty)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            decoration: _cardDecoration,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (s.title.isNotEmpty)
                  Text(s.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: kInteractionInk)),
                if (s.image.isNotEmpty && mediaImageProvider(s.image) != null) ...[
                  const SizedBox(height: 10),
                  GestureDetector(
                    onTap: () => showImageViewer(context, s.image, title: s.title),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image(image: mediaImageProvider(s.image)!, fit: BoxFit.cover),
                    ),
                  ),
                ],
                if (s.body.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  SelectableText(s.body, style: const TextStyle(fontSize: 14, color: kInteractionInk, height: 1.5)),
                ],
              ],
            ),
          ),
      if (a.attachments.isNotEmpty)
        Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          decoration: _cardDecoration,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Attachments', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: kInteractionInk)),
              const SizedBox(height: 8),
              for (final att in a.attachments)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: (att.type == 'pdf' ? AppColors.error : AppColors.indigo).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      att.isImage
                          ? Icons.image_outlined
                          : (att.type == 'pdf' ? Icons.picture_as_pdf_rounded : Icons.insert_drive_file_outlined),
                      color: att.type == 'pdf' ? AppColors.error : AppColors.indigo,
                      size: 20,
                    ),
                  ),
                  title: Text(
                    att.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: kInteractionInk),
                  ),
                  subtitle: Text(
                    att.url.trim().isEmpty
                        ? 'File not uploaded'
                        : (att.size > 0 ? fileSizeLabel(att.size) : (att.type == 'pdf' ? 'PDF' : 'File')),
                    style: TextStyle(fontSize: 12, color: att.url.trim().isEmpty ? AppColors.error : kInteractionMuted),
                  ),
                  trailing: att.url.trim().isEmpty
                      ? null
                      : TextButton.icon(
                          onPressed: () => viewAttachment(context, att),
                          icon: const Icon(Icons.visibility_outlined, size: 18),
                          label: const Text('View'),
                        ),
                  onTap: () => viewAttachment(context, att),
                ),
            ],
          ),
        ),
      Container(
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        decoration: _cardDecoration,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              a.threads.isEmpty ? 'Questions or feedback?' : 'Your comments',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: kInteractionInk),
            ),
            const SizedBox(height: 4),
            Text(
              a.threads.isEmpty
                  ? 'Comment below — only you and HR can see your conversation.'
                  : 'Only you and HR can see these.',
              style: const TextStyle(fontSize: 13, color: kInteractionMuted),
            ),
            for (final t in a.threads) _thread(t),
          ],
        ),
      ),
    ];
  }

  static const BoxDecoration _cardDecoration = BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.all(Radius.circular(16)),
    border: Border.fromBorderSide(BorderSide(color: kInteractionLine)),
    boxShadow: kSoftCardShadow,
  );

  Widget _thread(AnnouncementThread t) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kInteractionLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _line('You', t.comment, t.createdAt, mine: true),
          for (final r in t.replies)
            _line(
              r.senderRole.toLowerCase() == 'staff' ? 'You' : (r.senderName.isNotEmpty ? r.senderName : 'HR'),
              r.message,
              r.createdAt,
              mine: r.senderRole.toLowerCase() == 'staff',
            ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => setState(() => _replyTo = t),
              icon: const Icon(Icons.reply_rounded, size: 16),
              label: const Text('Reply'),
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            ),
          ),
        ],
      ),
    );
  }

  Widget _line(String who, String text, DateTime? at, {required bool mine}) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InteractionAvatar(name: who, size: 26),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      who,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: mine ? kInteractionInk : AppColors.success,
                      ),
                    ),
                    if (!mine) ...[
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.successBg,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text('HR', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.success)),
                      ),
                    ],
                    const Spacer(),
                    if (at != null)
                      Text(
                        DateFormat('d MMM, hh:mm a').format(at),
                        style: const TextStyle(fontSize: 11, color: kInteractionMuted),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(text, style: const TextStyle(fontSize: 13.5, color: kInteractionInk, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _composer() {
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: kInteractionLine)),
        ),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_replyTo != null)
              Row(
                children: [
                  Icon(Icons.reply_rounded, size: 16, color: AppColors.primaryText),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Replying to: ${_replyTo!.comment}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: kInteractionMuted),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Cancel reply',
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: () => setState(() => _replyTo = null),
                  ),
                ],
              ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    minLines: 1,
                    maxLines: 4,
                    textCapitalization: TextCapitalization.sentences,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: _replyTo == null ? 'Write a comment…' : 'Write a reply…',
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: const BorderSide(color: Color(0xFFE2E5EA)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide(color: AppColors.primary, width: 1.6),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _posting || _input.text.trim().isEmpty ? null : _post,
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.onPrimary,
                    disabledBackgroundColor: const Color(0xFFE2E5EA),
                    disabledForegroundColor: AppColors.textCaption,
                    fixedSize: const Size(48, 48),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: _posting
                      ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onPrimary))
                      : const Icon(Icons.send_rounded, size: 20),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
