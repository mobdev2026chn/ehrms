// hrms/lib/screens/interaction/interaction_chat_thread_screen.dart

import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/app_colors.dart';
import '../../services/interaction_service.dart';
import '../../services/interaction_socket_service.dart';
import 'interaction_poll_detail_screen.dart';

class InteractionChatThreadScreen extends StatefulWidget {
  const InteractionChatThreadScreen({
    super.key,
    required this.chatId,
    required this.title,
    this.receiverId,
    this.avatarUrl,
    required this.isGroup,
  });

  final String chatId;
  final String? receiverId;
  final String title;
  final String? avatarUrl;
  final bool isGroup;

  @override
  State<InteractionChatThreadScreen> createState() => _InteractionChatThreadScreenState();
}

class _InteractionChatThreadScreenState extends State<InteractionChatThreadScreen> {
  final _text = TextEditingController();
  final _scrollController = ScrollController();
  List<Map<String, dynamic>> _messages = [];
  int _page = 1;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _myUserId;
  StreamSubscription<Map<String, dynamic>>? _sub;
  final _seenIds = <String>{};
  Timer? _typingTimer;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _myUserId = await InteractionService.currentUserId();
    if (widget.isGroup) {
      InteractionSocketService.instance.joinGroupChats([widget.chatId]);
    } else if (widget.receiverId != null) {
      InteractionSocketService.instance.joinDirectChat(widget.receiverId!);
    }
    await InteractionSocketService.instance.connect();
    _sub = InteractionSocketService.instance.onNewMessage.listen(_onSocketMessage);
    _scrollController.addListener(_onScroll);
    await _loadPage(1, replace: true);
    await _markVisibleRead();
  }

  bool _matchesThread(Map<String, dynamic> msg) {
    if (widget.isGroup) {
      return msg['groupId']?.toString() == widget.chatId;
    }
    final peer = widget.receiverId;
    if (peer == null) return false;
    final s = msg['senderId']?.toString();
    final r = msg['receiverId']?.toString();
    final me = _myUserId;
    if (me == null) return false;
    return (s == peer && r == me) || (s == me && r == peer);
  }

  void _onSocketMessage(Map<String, dynamic> msg) {
    if (!_matchesThread(msg)) return;
    final id = msg['_id']?.toString();
    if (id != null && _seenIds.contains(id)) return;
    if (id != null) _seenIds.add(id);
    if (!mounted) return;
    setState(() => _messages = [msg, ..._messages]);
    _markVisibleRead();
  }

  void _onScroll() {
    if (!_scrollController.hasClients || _loadingMore || !_hasMore) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 140) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    await _loadPage(_page + 1, replace: false);
  }

  Future<void> _loadPage(int page, {required bool replace}) async {
    if (replace) {
      if (mounted) setState(() => _loading = true);
    } else {
      if (mounted) setState(() => _loadingMore = true);
    }
    try {
      final res = await InteractionService.instance.getChatMessages(
        chatId: widget.isGroup ? widget.chatId : 'personal',
        page: page,
        receiverId: widget.isGroup ? null : widget.receiverId,
      );
      final data = res['data'];
      final list = <Map<String, dynamic>>[];
      if (data is List) {
        for (final e in data) {
          if (e is Map) {
            final m = <String, dynamic>{};
            e.forEach((k, v) => m[k.toString()] = v);
            list.add(m);
          }
        }
      }
      if (!mounted) return;
      setState(() {
        if (replace) {
          _messages = list;
          _page = 1;
          _seenIds
            ..clear()
            ..addAll(list.map((m) => m['_id']?.toString()).whereType<String>());
        } else {
          _page = page;
          for (final m in list) {
            final id = m['_id']?.toString();
            if (id != null && !_seenIds.contains(id)) {
              _seenIds.add(id);
              _messages.add(m);
            }
          }
        }
        _hasMore = list.length >= 50;
        _loading = false;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  Future<void> _markVisibleRead() async {
    final me = _myUserId;
    if (me == null) return;
    for (final m in _messages) {
      if (m['readStatus'] == true) continue;
      if (m['senderId']?.toString() == me) continue;
      final id = m['_id']?.toString();
      if (id == null) continue;
      try {
        await InteractionService.instance.markMessageRead(id);
      } catch (_) {}
    }
  }

  Future<void> _sendText() async {
    final text = _text.text.trim();
    if (text.isEmpty) return;
    _text.clear();
    try {
      final res = await InteractionService.instance.sendTextMessage(
        chatId: widget.isGroup ? widget.chatId : 'personal',
        messageContent: text,
        receiverId: widget.isGroup ? null : widget.receiverId,
      );
      final data = res['data'];
      if (data is Map) {
        final m = <String, dynamic>{};
        data.forEach((k, v) => m[k.toString()] = v);
        final id = m['_id']?.toString();
        if (id != null) _seenIds.add(id);
        if (mounted) setState(() => _messages = [m, ..._messages]);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    final pick = ImagePicker();
    final x = await pick.pickImage(source: source, imageQuality: 85);
    if (x == null) return;
    await _upload(x.path, x.name, 'image');
  }

  Future<void> _pickFile() async {
    final r = await FilePicker.platform.pickFiles();
    if (r == null || r.files.isEmpty) return;
    final f = r.files.first;
    final path = f.path;
    if (path == null) return;
    await _upload(path, f.name, 'file');
  }

  Future<void> _upload(String path, String filename, String type) async {
    try {
      final res = await InteractionService.instance.uploadChatMedia(
        chatId: widget.isGroup ? widget.chatId : 'personal',
        filePath: path,
        filename: filename,
        type: type,
        receiverId: widget.isGroup ? null : widget.receiverId,
      );
      final data = res['data'];
      if (data is Map) {
        final m = <String, dynamic>{};
        data.forEach((k, v) => m[k.toString()] = v);
        final id = m['_id']?.toString();
        if (id != null) _seenIds.add(id);
        if (mounted) setState(() => _messages = [m, ..._messages]);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  void _emitTyping() {
    if (widget.isGroup) {
      InteractionSocketService.instance.emitTyping(groupId: widget.chatId);
    } else if (widget.receiverId != null) {
      InteractionSocketService.instance.emitTyping(receiverId: widget.receiverId);
    }
    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 2), () {
      if (widget.isGroup) {
        InteractionSocketService.instance.emitStopTyping(groupId: widget.chatId);
      } else if (widget.receiverId != null) {
        InteractionSocketService.instance.emitStopTyping(receiverId: widget.receiverId);
      }
    });
  }

  void _openAttachSheet() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('Camera'),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Gallery'),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.attach_file),
              title: const Text('Document'),
              onTap: () {
                Navigator.pop(ctx);
                _pickFile();
              },
            ),
          ],
        ),
      ),
    );
  }

  String _senderLabel(Map<String, dynamic> msg) {
    if (msg['sender'] is Map) {
      return (msg['sender'] as Map)['name']?.toString() ?? '';
    }
    return '';
  }

  Widget _bubble(Map<String, dynamic> msg) {
    final me = _myUserId;
    final isMine = me != null && msg['senderId']?.toString() == me;
    final type = msg['messageType']?.toString() ?? 'text';
    if (type == 'system') {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 24),
        child: Center(
          child: Text(
            msg['messageContent']?.toString() ?? '',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
        ),
      );
    }

    final sent = DateTime.tryParse(msg['sentTime']?.toString() ?? '')?.toLocal();
    final timeStr = sent == null ? '' : DateFormat.jm().format(sent);

    Widget inner;
    switch (type) {
      case 'image':
        final url = msg['fileUrl']?.toString();
        inner = url == null || !url.startsWith('http')
            ? const Text('Image')
            : ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(url, width: 200, fit: BoxFit.cover),
              );
        break;
      case 'file':
        final name = msg['fileName']?.toString() ?? 'File';
        final url = msg['fileUrl']?.toString();
        inner = InkWell(
          onTap: url != null && url.startsWith('http') ? () => launchUrl(Uri.parse(url)) : null,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.insert_drive_file),
                    const SizedBox(width: 8),
                    Flexible(child: Text(name)),
            ],
          ),
        );
        break;
      case 'voice':
        final url = msg['voiceUrl']?.toString();
        inner = InkWell(
          onTap: url != null && url.startsWith('http') ? () => launchUrl(Uri.parse(url)) : null,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.mic, color: AppColors.primary),
              const SizedBox(width: 8),
              const Text('Voice message'),
            ],
          ),
        );
        break;
      case 'poll':
        final pollId = msg['pollId']?.toString();
        inner = Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: pollId == null
                ? null
                : () {
                    Navigator.push<void>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => InteractionPollDetailScreen(
                          pollId: pollId,
                          previewTitle: msg['messageContent']?.toString(),
                        ),
                      ),
                    );
                  },
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('📊 Poll', style: TextStyle(fontWeight: FontWeight.bold)),
                  Text(msg['messageContent']?.toString() ?? 'Tap to vote'),
                  const SizedBox(height: 8),
                  Text('Open', style: TextStyle(color: AppColors.primary)),
                ],
              ),
            ),
          ),
        );
        break;
      default:
        inner = Text(msg['messageContent']?.toString() ?? '', style: const TextStyle(color: Color(0xFF1E293B)));
    }

    final showName = widget.isGroup && !isMine && _senderLabel(msg).isNotEmpty;

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        padding: const EdgeInsets.all(10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        decoration: BoxDecoration(
          color: isMine ? AppColors.primary.withOpacity(0.2) : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showName)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  _senderLabel(msg),
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.primary),
                ),
              ),
            inner,
            const SizedBox(height: 4),
            Text(timeStr, style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    _sub?.cancel();
    _scrollController.dispose();
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              backgroundColor: AppColors.primary.withOpacity(0.2),
              backgroundImage:
                  widget.avatarUrl != null && widget.avatarUrl!.startsWith('http')
                      ? NetworkImage(widget.avatarUrl!)
                      : null,
              child: widget.avatarUrl != null && widget.avatarUrl!.startsWith('http')
                  ? null
                  : Text(
                      widget.title.isNotEmpty ? widget.title[0].toUpperCase() : '?',
                      style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                widget.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          if (_loading) const LinearProgressIndicator(),
          Expanded(
            child: _messages.isEmpty && !_loading
                ? const Center(child: Text('No messages yet. Say hello!'))
                : ListView.builder(
                    controller: _scrollController,
                    reverse: true,
                    padding: const EdgeInsets.only(bottom: 12),
                    itemCount: _messages.length + (_loadingMore ? 1 : 0),
                    itemBuilder: (context, i) {
                      if (_loadingMore && i == _messages.length) {
                        return const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                        );
                      }
                      return _bubble(_messages[i]);
                    },
                  ),
          ),
          Material(
            elevation: 8,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      onPressed: _openAttachSheet,
                    ),
                    Expanded(
                      child: TextField(
                        controller: _text,
                        minLines: 1,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          hintText: 'Message',
                          border: OutlineInputBorder(),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                        onChanged: (_) => _emitTyping(),
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.send, color: AppColors.primary),
                      onPressed: _sendText,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
