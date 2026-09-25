// One conversation (direct / group / broadcast) on HRMSbackend staff chat.
// Sends over REST (optimistic bubble, retry on failure); live updates via the
// socket, polling every few seconds while it is disconnected.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../services/staff_interaction_service.dart';
import '../../../utils/snackbar_utils.dart';
import 'staff_interaction_widgets.dart';

/// Attachments travel as data URLs inside the JSON body (server limit 3 MB).
const int _kMaxAttachmentBytes = 2 * 1024 * 1024;

class StaffChatThreadScreen extends StatefulWidget {
  const StaffChatThreadScreen({
    super.key,
    required this.conversationId,
    required this.title,
    this.avatar = '',
    this.type = 'direct',
    this.subtitle = '',
    this.participantId = '',
  });

  final String conversationId;
  final String title;
  final String avatar;
  final String type;
  final String subtitle;
  final String participantId;

  @override
  State<StaffChatThreadScreen> createState() => _StaffChatThreadScreenState();
}

class _StaffChatThreadScreenState extends State<StaffChatThreadScreen> {
  final _svc = StaffInteractionService.instance;
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<ChatMessage> _messages = [];
  final List<StreamSubscription> _subs = [];
  String? _myId;
  bool _loading = true;
  String? _error;
  Timer? _poll;
  Timer? _typingOff;
  bool _typingSent = false;
  final Map<String, String> _typingUsers = {}; // userId -> name
  final Map<String, Timer> _typingExpiry = {};
  bool _otherRead = false;

  bool get _isBroadcast => widget.type == 'broadcast';
  bool get _isGroup => widget.type == 'group';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _myId = await _svc.myId();
    await _svc.connect();
    _svc.joinConversation(widget.conversationId);

    _subs.add(_svc.onMessage.listen((m) {
      if (m.conversationId != widget.conversationId) return;
      _merge([m]);
      if (m.senderId != _myId) _svc.markRead(widget.conversationId);
    }));
    _subs.add(_svc.onTyping.listen((t) {
      if (t.conversationId != widget.conversationId || t.userId == _myId) return;
      _typingExpiry.remove(t.userId)?.cancel();
      setState(() {
        if (t.isTyping) {
          _typingUsers[t.userId] = t.userName;
          // Drop a stale indicator if the stop event never arrives.
          _typingExpiry[t.userId] = Timer(const Duration(seconds: 6), () {
            if (mounted) setState(() => _typingUsers.remove(t.userId));
          });
        } else {
          _typingUsers.remove(t.userId);
        }
      });
    }));
    _subs.add(_svc.onRead.listen((r) {
      if (r.conversationId == widget.conversationId && r.userId != _myId && mounted) {
        setState(() => _otherRead = true);
      }
    }));
    _subs.add(_svc.onPresence.listen((_) {
      if (mounted) setState(() {});
    }));

    await _load();
    _svc.markRead(widget.conversationId);

    _poll = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!_svc.connected.value) _load(silent: true);
    });
  }

  @override
  void dispose() {
    _svc.leaveConversation(widget.conversationId);
    if (_typingSent) _svc.setTyping(widget.conversationId, false);
    for (final s in _subs) {
      s.cancel();
    }
    for (final t in _typingExpiry.values) {
      t.cancel();
    }
    _poll?.cancel();
    _typingOff?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    final r = await _svc.getMessages(widget.conversationId);
    if (!mounted) return;
    if (!r.ok) {
      setState(() {
        _loading = false;
        if (!silent || _messages.isEmpty) _error = r.error;
      });
      return;
    }
    final hadNewFromOthers = r.data!.any((m) => m.senderId != _myId && !_messages.any((x) => x.id == m.id));
    setState(() {
      _loading = false;
      _error = null;
      // Keep local pending/failed bubbles; replace everything else with the server copy.
      final local = _messages.where((m) => m.pending || m.failed).toList();
      _messages
        ..clear()
        ..addAll(r.data!)
        ..addAll(local);
      _otherRead = _messages.any((m) => m.senderId == _myId && m.status == 'read');
    });
    if (silent && hadNewFromOthers) _svc.markRead(widget.conversationId);
  }

  void _merge(List<ChatMessage> incoming) {
    setState(() {
      for (final m in incoming) {
        if (_messages.any((x) => x.id == m.id)) continue; // socket sends it twice
        // Our own optimistic bubble: swap it for the server copy.
        final i = _messages.indexWhere((x) =>
            x.pending && x.senderId == m.senderId && x.content == m.content && x.attachments.length == m.attachments.length);
        if (i >= 0) {
          _messages[i] = m;
        } else {
          _messages.add(m);
        }
      }
      _messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      _typingUsers.removeWhere((uid, _) => incoming.any((m) => m.senderId == uid));
    });
  }

  // ── Sending ──

  void _onTextChanged(String v) {
    if (_isBroadcast) return;
    if (v.trim().isNotEmpty && !_typingSent) {
      _typingSent = true;
      _svc.setTyping(widget.conversationId, true);
    }
    _typingOff?.cancel();
    _typingOff = Timer(const Duration(seconds: 2), () {
      if (_typingSent) {
        _typingSent = false;
        _svc.setTyping(widget.conversationId, false);
      }
    });
    setState(() {});
  }

  Future<void> _sendText() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    _input.clear();
    _typingOff?.cancel();
    if (_typingSent) {
      _typingSent = false;
      _svc.setTyping(widget.conversationId, false);
    }
    await _send(content: text);
  }

  Future<void> _send({String content = '', List<ChatAttachment> attachments = const [], ChatMessage? retry}) async {
    final local = retry ??
        ChatMessage(
          id: 'local-${DateTime.now().microsecondsSinceEpoch}',
          conversationId: widget.conversationId,
          senderId: _myId ?? '',
          senderName: 'You',
          senderAvatar: '',
          content: content,
          attachments: attachments,
          status: 'sending',
          createdAt: DateTime.now(),
          pending: true,
        );
    setState(() {
      local
        ..pending = true
        ..failed = false;
      if (retry == null) _messages.add(local);
    });
    _scrollToBottom();

    final r = await _svc.sendMessage(widget.conversationId, content: local.content, attachments: local.attachments);
    if (!mounted) return;
    if (r.ok) {
      setState(() {
        final i = _messages.indexOf(local);
        final already = _messages.any((x) => x.id == r.data!.id);
        if (i >= 0) {
          if (already) {
            _messages.removeAt(i);
          } else {
            _messages[i] = r.data!;
          }
        }
        _otherRead = false;
      });
    } else {
      setState(() {
        local
          ..pending = false
          ..failed = true;
      });
      SnackBarUtils.showSnackBar(context, r.error!, isError: true);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(0, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  // ── Attachments ──

  Future<void> _pickAttachment() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _attachOption(ctx, 'camera', Icons.photo_camera_rounded, 'Camera', const Color(0xFFEC4899)),
              _attachOption(ctx, 'gallery', Icons.photo_library_rounded, 'Gallery', const Color(0xFF8B5CF6)),
              _attachOption(ctx, 'document', Icons.insert_drive_file_rounded, 'Document', const Color(0xFF6366F1)),
            ],
          ),
        ),
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == 'document') {
      await _pickDocument();
    } else {
      await _pickImage(choice == 'camera' ? ImageSource.camera : ImageSource.gallery);
    }
  }

  Widget _attachOption(BuildContext ctx, String key, IconData icon, String label, Color color) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => Navigator.pop(ctx, key),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(radius: 26, backgroundColor: color, child: Icon(icon, color: Colors.white)),
            const SizedBox(height: 6),
            Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final x = await ImagePicker().pickImage(source: source, maxWidth: 2000, maxHeight: 2000);
      if (x == null) return;
      var bytes = await FlutterImageCompress.compressWithFile(
        x.path,
        minWidth: 1280,
        minHeight: 1280,
        quality: 72,
        format: CompressFormat.jpeg,
      );
      bytes ??= await File(x.path).readAsBytes();
      if (bytes.length > _kMaxAttachmentBytes) {
        if (mounted) SnackBarUtils.showSnackBar(context, 'Image is too large (max 2 MB).', isError: true);
        return;
      }
      final name = 'IMG_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.jpg';
      await _send(attachments: [
        ChatAttachment(
          name: name,
          size: bytes.length,
          type: 'image',
          url: 'data:image/jpeg;base64,${base64Encode(bytes)}',
        ),
      ]);
    } catch (_) {
      if (mounted) SnackBarUtils.showSnackBar(context, 'Could not attach the image.', isError: true);
    }
  }

  Future<void> _pickDocument() async {
    try {
      final res = await FilePicker.platform.pickFiles(
        withData: true,
        type: FileType.custom,
        allowedExtensions: const ['pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt', 'csv'],
      );
      final f = res?.files.single;
      if (f == null) return;
      final bytes = f.bytes ?? (f.path != null ? await File(f.path!).readAsBytes() : null);
      if (bytes == null) return;
      if (bytes.length > _kMaxAttachmentBytes) {
        if (mounted) SnackBarUtils.showSnackBar(context, 'File is too large (max 2 MB).', isError: true);
        return;
      }
      final ext = (f.extension ?? '').toLowerCase();
      const mimes = {
        'pdf': 'application/pdf',
        'doc': 'application/msword',
        'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        'xls': 'application/vnd.ms-excel',
        'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        'ppt': 'application/vnd.ms-powerpoint',
        'pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
        'txt': 'text/plain',
        'csv': 'text/csv',
      };
      await _send(attachments: [
        ChatAttachment(
          name: f.name,
          size: bytes.length,
          type: ext == 'pdf' ? 'pdf' : 'document',
          url: 'data:${mimes[ext] ?? 'application/octet-stream'};base64,${base64Encode(bytes)}',
        ),
      ]);
    } catch (_) {
      if (mounted) SnackBarUtils.showSnackBar(context, 'Could not attach the file.', isError: true);
    }
  }

  // ── UI ──

  @override
  Widget build(BuildContext context) {
    final online = widget.type == 'direct' && _svc.isOnline(widget.participantId);
    final typingNames = _typingUsers.values.where((n) => n.isNotEmpty).toList();
    final String status;
    if (typingNames.isNotEmpty) {
      status = _isGroup ? '${typingNames.first.split(' ').first} is typing…' : 'typing…';
    } else if (online) {
      status = 'Online';
    } else {
      status = widget.subtitle;
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0.5,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        foregroundColor: kInteractionInk,
        titleSpacing: 0,
        title: Row(
          children: [
            InteractionAvatar(
              name: widget.title,
              url: widget.avatar,
              size: 38,
              icon: widget.avatar.isEmpty
                  ? (_isBroadcast ? Icons.campaign_rounded : (_isGroup ? Icons.groups_rounded : null))
                  : null,
              online: online,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                  if (status.isNotEmpty)
                    Text(
                      status,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: typingNames.isNotEmpty || online ? const Color(0xFF059669) : kInteractionMuted,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(child: _messagesView()),
          _isBroadcast ? _broadcastBar() : _composer(),
        ],
      ),
    );
  }

  Widget _messagesView() {
    if (_loading) return const Center(child: CircularProgressIndicator(strokeWidth: 2.5));
    if (_error != null && _messages.isEmpty) {
      return InteractionEmptyState(
        icon: Icons.wifi_off_rounded,
        title: 'Could not load messages',
        message: _error!,
        action: OutlinedButton(onPressed: () => _load(), child: const Text('Retry')),
      );
    }
    if (_messages.isEmpty) {
      return InteractionEmptyState(
        icon: Icons.waving_hand_outlined,
        title: _isBroadcast ? 'No announcements yet' : 'No messages yet',
        message: _isBroadcast ? '' : 'Say hello to ${widget.title.split(' ').first}!',
      );
    }

    // Newest at the bottom, list built reversed so it opens at the latest message.
    final items = <Object>[];
    DateTime? lastDay;
    for (final m in _messages) {
      final d = DateTime(m.createdAt.year, m.createdAt.month, m.createdAt.day);
      if (lastDay == null || d != lastDay) {
        items.add(d);
        lastDay = d;
      }
      items.add(m);
    }
    final lastMineIndex = _messages.lastIndexWhere((m) => m.senderId == _myId && !m.pending && !m.failed);
    final lastMine = lastMineIndex >= 0 ? _messages[lastMineIndex] : null;

    return ListView.builder(
      controller: _scroll,
      reverse: true,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      itemCount: items.length,
      itemBuilder: (_, i) {
        final item = items[items.length - 1 - i];
        if (item is DateTime) return _daySeparator(item);
        final m = item as ChatMessage;
        final idx = items.length - 1 - i;
        final prev = idx > 0 ? items[idx - 1] : null;
        final sameSenderAsPrev = prev is ChatMessage && prev.senderId == m.senderId;
        return _bubble(m, showName: _isGroup || _isBroadcast ? !sameSenderAsPrev : false, isLastMine: identical(m, lastMine));
      },
    );
  }

  Widget _daySeparator(DateTime d) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          boxShadow: const [BoxShadow(color: Color(0x0F000000), blurRadius: 4)],
        ),
        child: Text(
          chatDayLabel(d),
          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: kInteractionMuted),
        ),
      ),
    );
  }

  Widget _bubble(ChatMessage m, {required bool showName, required bool isLastMine}) {
    if (m.isSystem) {
      return Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 24),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFFFEF3C7),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(m.content, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12.5, color: Color(0xFF92400E))),
        ),
      );
    }
    final mine = m.senderId == _myId;
    final time = DateFormat('hh:mm a').format(m.createdAt);
    final bg = mine ? const Color(0xFFFFF1D6) : Colors.white;

    Widget statusIcon() {
      if (m.failed) return const Icon(Icons.error_outline_rounded, size: 14, color: Color(0xFFDC2626));
      if (m.pending) return const Icon(Icons.schedule_rounded, size: 13, color: kInteractionMuted);
      final read = m.status == 'read' || (isLastMine && _otherRead);
      return Icon(Icons.done_all_rounded, size: 15, color: read ? const Color(0xFF0EA5E9) : kInteractionMuted);
    }

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!mine && showName)
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Text(
              m.senderName,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: avatarTint(m.senderName)),
            ),
          ),
        for (final a in m.attachments) _attachmentView(a),
        if (m.content.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(top: m.attachments.isNotEmpty ? 6 : 0),
            child: Text(m.content, style: const TextStyle(fontSize: 14.5, color: kInteractionInk, height: 1.35)),
          ),
        const SizedBox(height: 3),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(time, style: const TextStyle(fontSize: 10.5, color: kInteractionMuted)),
            if (mine) ...[const SizedBox(width: 4), statusIcon()],
          ],
        ),
      ],
    );

    final bubble = GestureDetector(
      onTap: m.failed ? () => _send(retry: m) : null,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.76),
        margin: EdgeInsets.only(top: showName || mine ? 4 : 2, bottom: 2),
        padding: const EdgeInsets.fromLTRB(11, 8, 11, 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(mine ? 14 : 4),
            bottomRight: Radius.circular(mine ? 4 : 14),
          ),
          boxShadow: const [BoxShadow(color: Color(0x0D000000), blurRadius: 3, offset: Offset(0, 1))],
        ),
        child: content,
      ),
    );

    return Column(
      crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        bubble,
        if (m.failed)
          const Padding(
            padding: EdgeInsets.only(bottom: 4),
            child: Text('Not sent · tap to retry', style: TextStyle(fontSize: 11, color: Color(0xFFDC2626))),
          ),
      ],
    );
  }

  Widget _attachmentView(ChatAttachment a) {
    if (a.isImage) {
      final provider = mediaImageProvider(a.url);
      if (provider != null) {
        return GestureDetector(
          onTap: () => showImageViewer(context, a.url, title: a.name),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260, minWidth: 120),
              child: Image(
                image: provider,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox(
                  height: 80,
                  child: Center(child: Icon(Icons.broken_image_outlined, color: kInteractionMuted)),
                ),
              ),
            ),
          ),
        );
      }
    }
    final isPdf = a.type == 'pdf' || a.name.toLowerCase().endsWith('.pdf');
    return InkWell(
      onTap: () => openAttachment(context, a),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0x0F000000),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isPdf ? Icons.picture_as_pdf_rounded : Icons.insert_drive_file_rounded,
              color: isPdf ? const Color(0xFFDC2626) : const Color(0xFF6366F1),
              size: 30,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    a.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: kInteractionInk),
                  ),
                  if (a.size > 0)
                    Text(fileSizeLabel(a.size), style: const TextStyle(fontSize: 11, color: kInteractionMuted)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _broadcastBar() {
    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        color: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.campaign_outlined, size: 16, color: kInteractionMuted),
            SizedBox(width: 6),
            Flexible(
              child: Text(
                'Only admins can send messages in this broadcast channel.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: kInteractionMuted),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _composer() {
    final hasText = _input.text.trim().isNotEmpty;
    return SafeArea(
      top: false,
      child: Container(
        color: Colors.transparent,
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: const [BoxShadow(color: Color(0x12000000), blurRadius: 4, offset: Offset(0, 1))],
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const SizedBox(width: 14),
                    Expanded(
                      child: TextField(
                        controller: _input,
                        onChanged: _onTextChanged,
                        minLines: 1,
                        maxLines: 5,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          hintText: 'Message',
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: _pickAttachment,
                      icon: const Icon(Icons.attach_file_rounded, color: kInteractionMuted),
                      tooltip: 'Attach',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 6),
            AnimatedScale(
              duration: const Duration(milliseconds: 150),
              scale: hasText ? 1 : 0.9,
              child: Material(
                color: hasText ? kInteractionAccent : const Color(0xFFCBD5E1),
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: hasText ? _sendText : null,
                  child: const Padding(
                    padding: EdgeInsets.all(12),
                    child: Icon(Icons.send_rounded, color: Colors.white, size: 22),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
