// hrms/lib/screens/interaction/interaction_chat_thread_screen.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/app_colors.dart';
import '../../config/constants.dart';
import '../../services/interaction_service.dart';
import '../../services/interaction_socket_service.dart';
import '../../utils/interaction_avatar_theme.dart';
import 'interaction_poll_detail_screen.dart';

class InteractionChatThreadScreen extends StatefulWidget {
  const InteractionChatThreadScreen({
    super.key,
    required this.chatId,
    required this.title,
    this.receiverId,
    this.avatarUrl,
    required this.isGroup,
    /// From chat list `isOnline` (socket-backed on server). Omit for unknown.
    this.peerIsOnline,
    /// From API `canSendMessages` (e.g. broadcast read-only). When false, composer is disabled.
    this.canSendMessages,
  });

  final String chatId;
  final String? receiverId;
  final String title;
  final String? avatarUrl;
  final bool isGroup;
  final bool? peerIsOnline;
  final bool? canSendMessages;

  @override
  State<InteractionChatThreadScreen> createState() => _InteractionChatThreadScreenState();
}

const Color _kChatHeaderIconGrey = Color(0xFF4A4A4A);
/// Web / WhatsApp-style outgoing bubble (light mint green).
const Color _kChatSentBubble = Color(0xFFDCF8C6);
const Color _kChatReceivedBubble = Color(0xFFFFFFFF);

class _InteractionChatThreadScreenState extends State<InteractionChatThreadScreen> {
  final _text = TextEditingController();
  final _searchQuery = TextEditingController();
  final _searchFocus = FocusNode();
  final _scrollController = ScrollController();
  final _audioRecorder = AudioRecorder();
  List<Map<String, dynamic>> _messages = [];
  int _page = 1;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  bool _recording = false;
  /// Inline header search (web-style); chat list hidden while active.
  bool _searchOpen = false;
  String? _myUserId;
  String? _myDisplayAvatarUrl;
  String _myDisplayName = '';
  int? _memberCount;
  StreamSubscription<Map<String, dynamic>>? _sub;
  final _seenIds = <String>{};
  Timer? _typingTimer;
  /// From `GET /interaction/polls` — option ids the current user selected per poll.
  Map<String, List<String>> _myPollOptionIds = {};
  bool _showScrollToBottom = false;

  /// `null` / missing from API → allow send; explicit `false` = broadcast read-only (matches web).
  bool get _maySend => widget.canSendMessages != false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _myUserId = await InteractionService.currentUserId();
    await _loadMyDisplay();
    if (widget.isGroup) {
      InteractionSocketService.instance.joinGroupChats([widget.chatId]);
    } else if (widget.receiverId != null) {
      InteractionSocketService.instance.joinDirectChat(widget.receiverId!);
    }
    await InteractionSocketService.instance.connect();
    _sub = InteractionSocketService.instance.onNewMessage.listen(_onSocketMessage);
    _scrollController.addListener(_onScroll);
    await _loadPage(1, replace: true);
    unawaited(_loadGroupMeta());
    unawaited(_hydratePollVotes());
    await _markVisibleRead();
  }

  Future<void> _hydratePollVotes() async {
    try {
      final res = await InteractionService.instance.getPolls();
      final data = res['data'];
      if (data is! List || !mounted) return;
      final m = <String, List<String>>{};
      for (final e in data) {
        if (e is Map) {
          final id = e['_id']?.toString() ?? e['id']?.toString();
          final mo = e['myOptionIds'];
          if (id != null && mo is List) {
            m[id] = mo.map((x) => x.toString()).toList();
          }
        }
      }
      if (mounted) setState(() => _myPollOptionIds = m);
    } catch (_) {}
  }

  Future<void> _loadMyDisplay() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('user');
    if (raw == null || raw.isEmpty) return;
    try {
      final u = jsonDecode(raw) as Map<String, dynamic>;
      final av = u['avatar']?.toString();
      final name = u['name']?.toString() ?? '';
      var url = (av != null && av.isNotEmpty) ? AppConstants.getLmsFileUrl(av) : '';
      if (url.isNotEmpty && !url.startsWith('http')) url = '';
      if (mounted) {
        setState(() {
          _myDisplayName = name;
          _myDisplayAvatarUrl = url.isNotEmpty ? url : null;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadGroupMeta() async {
    if (!widget.isGroup) return;
    try {
      final res = await InteractionService.instance.getGroupMembers(widget.chatId);
      final data = res['data'];
      if (data is List && mounted) {
        setState(() => _memberCount = data.length);
      }
    } catch (_) {}
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
    if (_scrollController.hasClients) {
      final show = _scrollController.offset > 72;
      if (show != _showScrollToBottom && mounted) {
        setState(() => _showScrollToBottom = show);
      }
    }
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
    if (!_maySend) return;
    final text = _text.text.trim();
    if (text.isEmpty) return;
    _text.clear();
    if (mounted) setState(() {});
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

  Future<void> _pickVideo(ImageSource source) async {
    final pick = ImagePicker();
    final x = await pick.pickVideo(source: source);
    if (x == null) return;
    await _upload(x.path, x.name, 'file');
  }

  Future<void> _pickFile() async {
    final r = await FilePicker.platform.pickFiles();
    if (r == null || r.files.isEmpty) return;
    final f = r.files.first;
    final path = f.path;
    if (path == null) return;
    await _upload(path, f.name, 'file');
  }

  Future<void> _pickAudioFile() async {
    final r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['mp3', 'm4a', 'aac', 'wav', 'ogg'],
    );
    if (r == null || r.files.isEmpty) return;
    final f = r.files.first;
    final path = f.path;
    if (path == null) return;
    await _upload(path, f.name, 'voice');
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

  void _showPhotosAndVideosPicker() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Photo library'),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.video_library_outlined),
              title: const Text('Video library'),
              onTap: () {
                Navigator.pop(ctx);
                _pickVideo(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Camera'),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(ImageSource.camera);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showWebAttachSheet() {
    if (!_maySend) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Material(
              borderRadius: BorderRadius.circular(16),
              color: Colors.white,
              clipBehavior: Clip.antiAlias,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 4),
                  _attachRow(
                    icon: Icons.description_rounded,
                    iconBg: Colors.purple,
                    label: 'Document',
                    onTap: () {
                      Navigator.pop(ctx);
                      _pickFile();
                    },
                  ),
                  _attachRow(
                    icon: Icons.collections_rounded,
                    iconBg: Colors.blue,
                    label: 'Photos & videos',
                    onTap: () {
                      Navigator.pop(ctx);
                      _showPhotosAndVideosPicker();
                    },
                  ),
                  _attachRow(
                    icon: Icons.audiotrack_rounded,
                    iconBg: const Color(0xFF00897B),
                    label: 'Audio',
                    onTap: () {
                      Navigator.pop(ctx);
                      _pickAudioFile();
                    },
                  ),
                  const SizedBox(height: 4),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _attachRow({
    required IconData icon,
    required Color iconBg,
    required String label,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: iconBg,
        child: Icon(icon, color: Colors.white, size: 22),
      ),
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 15)),
      onTap: onTap,
    );
  }

  Future<void> _toggleRecording() async {
    if (!_maySend && !_recording) return;
    if (_recording) {
      final path = await _audioRecorder.stop();
      if (mounted) setState(() => _recording = false);
      if (path != null && path.isNotEmpty) {
        final name = path.contains(Platform.pathSeparator)
            ? path.split(Platform.pathSeparator).last
            : path.split('/').last;
        await _upload(path, name, 'voice');
      }
      return;
    }
    final mic = await Permission.microphone.request();
    if (!mic.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Microphone permission is required for voice messages.')),
        );
      }
      return;
    }
    if (!mounted) return;
    if (!await _audioRecorder.hasPermission()) return;
    final dir = await getTemporaryDirectory();
    final filePath = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _audioRecorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc),
      path: filePath,
    );
    if (mounted) setState(() => _recording = true);
  }

  String _senderLabel(Map<String, dynamic> msg) {
    if (msg['sender'] is Map) {
      return (msg['sender'] as Map)['name']?.toString() ?? '';
    }
    return '';
  }

  String? _peerAvatarUrl(Map<String, dynamic> msg) {
    final s = msg['sender'];
    if (s is! Map) return null;
    final a = s['avatar']?.toString();
    if (a == null || a.isEmpty) return null;
    final u =
        a.startsWith('http://') || a.startsWith('https://') ? a : AppConstants.getLmsFileUrl(a);
    return u.startsWith('http') ? u : null;
  }

  DateTime? _msgLocalTime(Map<String, dynamic> msg) {
    return DateTime.tryParse(msg['sentTime']?.toString() ?? '')?.toLocal();
  }

  String _dayPillLabel(DateTime dt) => DateFormat('EEE MMM dd yyyy').format(dt);

  Widget _dateSeparatorPill(DateTime dt) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade300),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4, offset: const Offset(0, 1)),
            ],
          ),
          child: Text(
            _dayPillLabel(dt),
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700, fontWeight: FontWeight.w500),
          ),
        ),
      ),
    );
  }

  Widget _messageSideAvatar({required bool isMine, required Map<String, dynamic> msg}) {
    final peerName = _senderLabel(msg);
    final label = isMine
        ? (_myDisplayName.isNotEmpty ? _myDisplayName[0].toUpperCase() : '?')
        : (peerName.isNotEmpty ? peerName[0].toUpperCase() : '?');
    final bg = isMine
        ? InteractionAvatarTheme.backgroundForTitle(_myDisplayName.isNotEmpty ? _myDisplayName : 'U')
        : InteractionAvatarTheme.backgroundForTitle(peerName.isNotEmpty ? peerName : 'U');
    final fg = InteractionAvatarTheme.letterColor(bg);
    final url = isMine ? _myDisplayAvatarUrl : _peerAvatarUrl(msg);
    return CircleAvatar(
      radius: 18,
      backgroundColor: url != null ? Colors.transparent : bg,
      backgroundImage: url != null ? NetworkImage(url) : null,
      child: url == null
          ? Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.bold, fontSize: 13))
          : null,
    );
  }

  Widget _bubble(Map<String, dynamic> msg) {
    final me = _myUserId;
    final isMine = me != null && msg['senderId']?.toString() == me;
    final type = msg['messageType']?.toString() ?? 'text';
    if (type == 'system') {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 24),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF9C4),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Text(
              msg['messageContent']?.toString() ?? '',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
            ),
          ),
        ),
      );
    }

    final sent = _msgLocalTime(msg);
    final timeStr = sent == null ? '' : DateFormat.jm().format(sent);
    final read = msg['readStatus'] == true;

    final bubbleColor = isMine ? _kChatSentBubble : _kChatReceivedBubble;
    final textColor = const Color(0xFF0F172A);

    Widget inner;
    switch (type) {
      case 'image':
        final url = msg['fileUrl']?.toString();
        inner = url == null || !url.startsWith('http')
            ? Text('Image', style: TextStyle(color: textColor.withValues(alpha: 0.7)))
            : ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(url, width: 220, fit: BoxFit.cover),
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
              Icon(Icons.insert_drive_file, color: textColor.withValues(alpha: 0.8)),
              const SizedBox(width: 8),
              Flexible(child: Text(name, style: TextStyle(color: textColor))),
            ],
          ),
        );
        break;
      case 'voice':
        final url = msg['voiceUrl']?.toString();
        inner = (url == null || !url.startsWith('http'))
            ? Text('Voice message', style: TextStyle(color: textColor.withValues(alpha: 0.75)))
            : _InlineVoiceMessagePlayer(url: url, isMine: isMine);
        break;
      case 'poll':
        final pollId = msg['pollId']?.toString();
        final titleText = msg['messageContent']?.toString() ?? 'Poll';
        List<Map<String, dynamic>>? pollOptsFromMsg;
        final rawPo = msg['pollOptions'];
        if (rawPo is List && rawPo.isNotEmpty) {
          final tmp = <Map<String, dynamic>>[];
          for (final e in rawPo) {
            if (e is Map) {
              final id = e['optionId']?.toString() ??
                  e['option_id']?.toString() ??
                  e['_id']?.toString() ??
                  e['id']?.toString();
              final tx = e['optionText']?.toString() ??
                  e['option_text']?.toString() ??
                  e['text']?.toString() ??
                  e['name']?.toString() ??
                  '';
              if (id != null && id.isNotEmpty) {
                tmp.add({'_id': id, 'optionText': tx});
              }
            }
          }
          if (tmp.isNotEmpty) pollOptsFromMsg = tmp;
        }
        Future<void> openPoll() async {
          if (pollId == null) return;
          await Navigator.push<void>(
            context,
            MaterialPageRoute(
              builder: (_) => InteractionPollDetailScreen(
                pollId: pollId,
                previewTitle: titleText,
              ),
            ),
          );
          if (mounted) unawaited(_hydratePollVotes());
        }

        inner = pollId == null
            ? Text(titleText, style: TextStyle(color: textColor.withValues(alpha: 0.7)))
            : _PollInlineCard(
                pollId: pollId,
                titleText: titleText,
                embeddedPollOptions: pollOptsFromMsg,
                myOptionIds: _myPollOptionIds[pollId] ?? const [],
                onOpenDetail: openPoll,
                onVoteSubmitted: () => unawaited(_hydratePollVotes()),
              );
        break;
      default:
        inner = Text(
          msg['messageContent']?.toString() ?? '',
          style: TextStyle(color: textColor, fontSize: 15, height: 1.35),
        );
    }

    final showName = widget.isGroup && !isMine && _senderLabel(msg).isNotEmpty;

    final bubble = Container(
      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: type == 'poll' ? Colors.transparent : bubbleColor,
        borderRadius: BorderRadius.circular(12),
        border: type == 'poll'
            ? null
            : Border.all(color: isMine ? const Color(0xFFB2DFDB).withValues(alpha: 0.5) : Colors.grey.shade200),
        boxShadow: type == 'poll'
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
      ),
      child: type == 'poll'
          ? inner
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showName)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      _senderLabel(msg),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1565C0),
                      ),
                    ),
                  ),
                inner,
              ],
            ),
    );

    final meta = Padding(
      padding: EdgeInsets.only(top: 4, left: isMine ? 0 : 6, right: isMine ? 6 : 0),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isMine) ...[
            Icon(
              Icons.done_all,
              size: 15,
              color: read ? const Color(0xFF53BDEB) : Colors.grey.shade500,
            ),
            const SizedBox(width: 4),
          ],
          Text(timeStr, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
        ],
      ),
    );

    final column = Column(
      crossAxisAlignment: isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [bubble, meta],
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: isMine
            ? [
                Flexible(child: column),
                const SizedBox(width: 8),
                _messageSideAvatar(isMine: true, msg: msg),
              ]
            : [
                _messageSideAvatar(isMine: false, msg: msg),
                const SizedBox(width: 8),
                Flexible(child: column),
              ],
      ),
    );
  }

  void _openMessageSearch() {
    setState(() => _searchOpen = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });
  }

  void _closeMessageSearch() {
    _searchFocus.unfocus();
    _searchQuery.clear();
    setState(() => _searchOpen = false);
  }

  List<Map<String, dynamic>> get _searchFiltered {
    final q = _searchQuery.text.trim().toLowerCase();
    if (q.isEmpty) return [];
    return _messages.where((m) {
      final content = m['messageContent']?.toString().toLowerCase() ?? '';
      final fn = m['fileName']?.toString().toLowerCase() ?? '';
      final snd = _senderLabel(m).toLowerCase();
      return content.contains(q) || fn.contains(q) || snd.contains(q);
    }).toList();
  }

  Widget _subtitleRow() {
    if (widget.isGroup && _memberCount != null) {
      return Text(
        '$_memberCount members',
        style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
      );
    }
    if (!widget.isGroup && widget.peerIsOnline != null) {
      final online = widget.peerIsOnline == true;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: online ? const Color(0xFF16A34A) : Colors.grey.shade500,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            online ? 'Online' : 'Offline',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: online ? const Color(0xFF16A34A) : Colors.grey.shade600,
            ),
          ),
        ],
      );
    }
    return const SizedBox.shrink();
  }

  Widget _searchResultsBody() {
    final q = _searchQuery.text.trim();
    if (q.isEmpty) {
      return Center(
        child: Text(
          'Search messages…',
          style: TextStyle(color: Colors.grey.shade600, fontSize: 15),
        ),
      );
    }
    final filtered = _searchFiltered;
    if (filtered.isEmpty) {
      return Center(
        child: Text('No matches', style: TextStyle(color: Colors.grey.shade600)),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: filtered.length,
      separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade200),
      itemBuilder: (ctx, i) {
        final m = filtered[i];
        final name = _senderLabel(m);
        final sent = DateTime.tryParse(m['sentTime']?.toString() ?? '')?.toLocal();
        final timeStr = sent == null ? '' : DateFormat.jm().format(sent);
        final letter = name.isNotEmpty ? name[0].toUpperCase() : '?';
        final bg = InteractionAvatarTheme.backgroundForTitle(name);
        final fg = InteractionAvatarTheme.letterColor(bg);
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: bg,
            radius: 20,
            child: Text(letter, style: TextStyle(color: fg, fontWeight: FontWeight.bold, fontSize: 14)),
          ),
          title: Text(
            m['messageContent']?.toString() ?? m['fileName']?.toString() ?? '(media)',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text('$name · $timeStr', maxLines: 1, overflow: TextOverflow.ellipsis),
        );
      },
    );
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    _sub?.cancel();
    _scrollController.dispose();
    _text.dispose();
    _searchQuery.dispose();
    _searchFocus.dispose();
    unawaited(_audioRecorder.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.title.trim();
    final letterBg =
        InteractionAvatarTheme.backgroundForTitle(title, groupType: widget.isGroup ? null : null);
    final letterFg = InteractionAvatarTheme.letterColor(letterBg);

    return PopScope(
      canPop: !_searchOpen,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _searchOpen) {
          _closeMessageSearch();
        }
      },
      child: Scaffold(
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        iconTheme: const IconThemeData(color: _kChatHeaderIconGrey),
        leadingWidth: 44,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          color: _kChatHeaderIconGrey,
          onPressed: () {
            if (_searchOpen) {
              _closeMessageSearch();
            } else {
              Navigator.of(context).maybePop();
            }
          },
        ),
        titleSpacing: 4,
        toolbarHeight: _searchOpen ? 96 : kToolbarHeight,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor:
                      (widget.avatarUrl != null && widget.avatarUrl!.startsWith('http'))
                      ? Colors.transparent
                      : letterBg,
                  backgroundImage:
                      widget.avatarUrl != null && widget.avatarUrl!.startsWith('http')
                          ? NetworkImage(widget.avatarUrl!)
                          : null,
                  child: widget.avatarUrl != null && widget.avatarUrl!.startsWith('http')
                      ? null
                      : Text(
                          title.isNotEmpty ? title[0].toUpperCase() : '?',
                          style: TextStyle(color: letterFg, fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                ),
                const SizedBox(width: 10),
                if (!_searchOpen)
                  IconButton(
                    icon: Icon(Icons.search, color: Colors.grey.shade700),
                    onPressed: _openMessageSearch,
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      _subtitleRow(),
                    ],
                  ),
                ),
              ],
            ),
            if (_searchOpen) ...[
              const SizedBox(height: 6),
              Container(
                height: 40,
                padding: const EdgeInsets.only(left: 4, right: 2),
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: Colors.grey.shade400),
                ),
                child: Row(
                  children: [
                    Icon(Icons.search, color: Colors.grey.shade600, size: 22),
                    Expanded(
                      child: TextField(
                        controller: _searchQuery,
                        focusNode: _searchFocus,
                        style: const TextStyle(fontSize: 15, color: Color(0xFF0F172A)),
                        decoration: InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          hintText: 'Search messages...',
                          hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 15),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close, size: 20, color: Colors.grey.shade700),
                      onPressed: () {
                        if (_searchQuery.text.isEmpty) {
                          _closeMessageSearch();
                        } else {
                          _searchQuery.clear();
                          setState(() {});
                        }
                      },
                      tooltip: 'Clear',
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: Image.asset(
              AppConstants.interactionChatBackgroundAsset,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => ColoredBox(color: Colors.grey.shade200),
            ),
          ),
          Positioned.fill(
            child: ColoredBox(
              color: Colors.white.withValues(alpha: 0.68),
            ),
          ),
          Column(
            children: [
              if (_loading) const LinearProgressIndicator(),
              Expanded(
                child: _searchOpen
                    ? _searchResultsBody()
                    : _messages.isEmpty && !_loading
                        ? Center(
                            child: Text(
                              'No messages yet. Say hello!',
                              style: TextStyle(color: Colors.grey.shade800),
                            ),
                          )
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
                              final msg = _messages[i];
                              final pieces = <Widget>[];
                              if (i > 0) {
                                final newer = _messages[i - 1];
                                final tCur = _msgLocalTime(msg);
                                final tNew = _msgLocalTime(newer);
                                if (tCur != null && tNew != null) {
                                  final dCur = DateTime(tCur.year, tCur.month, tCur.day);
                                  final dNew = DateTime(tNew.year, tNew.month, tNew.day);
                                  if (dCur != dNew) {
                                    pieces.add(_dateSeparatorPill(tCur));
                                  }
                                }
                              }
                              pieces.add(_bubble(msg));
                              return Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: pieces,
                              );
                            },
                          ),
              ),
              if (!_searchOpen && _maySend && _recording)
                Material(
                  color: Colors.grey.shade100,
                  child: ListTile(
                    dense: true,
                    leading: Icon(Icons.fiber_manual_record, color: Colors.red.shade700, size: 20),
                    title: Text(
                      'Recording… Tap the microphone again to send',
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade800),
                    ),
                  ),
                ),
              if (!_searchOpen && !_maySend)
                Material(
                  elevation: 2,
                  color: Colors.grey.shade200,
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.grey.shade700, size: 22),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'You can view this broadcast but cannot send messages.',
                              style: TextStyle(fontSize: 13, color: Colors.grey.shade800),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (!_searchOpen && _maySend)
                Material(
                  elevation: 6,
                  color: Colors.grey.shade100,
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(28),
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.only(left: 6, bottom: 6),
                                    child: Material(
                                      color: Colors.grey.shade100,
                                      shape: const CircleBorder(),
                                      child: InkWell(
                                        customBorder: const CircleBorder(),
                                        onTap: _showWebAttachSheet,
                                        child: Padding(
                                          padding: const EdgeInsets.all(10),
                                          child: Icon(Icons.attach_file, color: Colors.grey.shade600, size: 22),
                                        ),
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: TextField(
                                      controller: _text,
                                      minLines: 1,
                                      maxLines: 4,
                                      decoration: const InputDecoration(
                                        hintText: 'Type a message...',
                                        hintStyle: TextStyle(color: Color(0xFF94A3B8)),
                                        border: InputBorder.none,
                                        isDense: true,
                                        contentPadding: EdgeInsets.fromLTRB(4, 12, 12, 12),
                                      ),
                                      onChanged: (_) {
                                        _emitTyping();
                                        setState(() {});
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (_recording)
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                              child: IconButton(
                                icon: const Icon(Icons.stop_circle_outlined),
                                color: Colors.red.shade700,
                                onPressed: _toggleRecording,
                              ),
                            )
                          else if (_text.text.trim().isNotEmpty)
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                              child: IconButton(
                                icon: const Icon(Icons.send_rounded),
                                color: AppColors.primary,
                                onPressed: _sendText,
                              ),
                            )
                          else
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                              child: IconButton(
                                icon: const Icon(Icons.mic_none_rounded),
                                color: Colors.grey.shade800,
                                onPressed: _toggleRecording,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
          if (_showScrollToBottom && !_searchOpen)
            Positioned(
              right: 12,
              bottom: MediaQuery.viewInsetsOf(context).bottom + MediaQuery.paddingOf(context).bottom + 80,
              child: Material(
                elevation: 2,
                shape: const CircleBorder(),
                color: Colors.white,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () {
                    if (_scrollController.hasClients) {
                      _scrollController.animateTo(
                        0,
                        duration: const Duration(milliseconds: 280),
                        curve: Curves.easeOutCubic,
                      );
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Icon(Icons.keyboard_arrow_down, color: Colors.grey.shade700, size: 22),
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

/// Web-style poll card in the chat stream (options + Vote).
class _PollInlineCard extends StatefulWidget {
  const _PollInlineCard({
    required this.pollId,
    required this.titleText,
    this.embeddedPollOptions,
    required this.myOptionIds,
    required this.onOpenDetail,
    required this.onVoteSubmitted,
  });

  final String pollId;
  final String titleText;
  /// From chat message `pollOptions` (same as web) when GET /polls/:id is slow or unavailable.
  final List<Map<String, dynamic>>? embeddedPollOptions;
  final List<String> myOptionIds;
  final Future<void> Function() onOpenDetail;
  final VoidCallback onVoteSubmitted;

  @override
  State<_PollInlineCard> createState() => _PollInlineCardState();
}

class _PollInlineCardState extends State<_PollInlineCard> {
  static const Color _voteBlue = Color(0xFF1976D2);

  bool _loading = true;
  bool _submitting = false;
  String? _role;
  List<Map<String, dynamic>> _options = [];
  String _serverTitle = '';
  String _pollType = 'single';
  bool _isClosed = false;
  bool _isAnonymous = false;
  List<Map<String, dynamic>> _results = [];
  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    final hasEmbedded = widget.embeddedPollOptions != null && widget.embeddedPollOptions!.isNotEmpty;
    if (hasEmbedded) {
      _loading = false;
      _options = widget.embeddedPollOptions!.map((e) => Map<String, dynamic>.from(e)).toList();
    }
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant _PollInlineCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldSubmitted = oldWidget.myOptionIds.isNotEmpty;
    final newSubmitted = widget.myOptionIds.isNotEmpty;
    if (!oldSubmitted && newSubmitted) {
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    final hasEmbedded = widget.embeddedPollOptions != null && widget.embeddedPollOptions!.isNotEmpty;
    if (!hasEmbedded && mounted) setState(() => _loading = true);
    try {
      _role = await InteractionService.currentUserRole();
      final pollRes = await InteractionService.instance.getPoll(widget.pollId);
      final raw = pollRes['data'];
      _options = [];
      if (raw is Map) {
        final m = <String, dynamic>{};
        raw.forEach((k, v) => m[k.toString()] = v);
        _serverTitle = m['title']?.toString() ?? widget.titleText;
        _pollType = m['pollType']?.toString() ?? 'single';
        _isClosed = m['isClosed'] == true;
        _isAnonymous = m['isAnonymous'] == true;
        final opts = m['options'];
        if (opts is List) {
          for (final e in opts) {
            if (e is Map) {
              final o = <String, dynamic>{};
              e.forEach((k, v) => o[k.toString()] = v);
              _options.add(o);
            }
          }
        }
      }
      if (widget.myOptionIds.isNotEmpty || _isClosed || _cannotVote) {
        final res = await InteractionService.instance.getPollResults(widget.pollId);
        final raw = res['data'];
        _results = [];
        if (raw is List) {
          for (final e in raw) {
            if (e is Map) {
              final r = <String, dynamic>{};
              e.forEach((k, v) => r[k.toString()] = v);
              _results.add(r);
            }
          }
        }
      } else {
        _results = [];
      }
    } catch (_) {
      _options = [];
      _results = [];
    }
    if (_options.isEmpty && hasEmbedded) {
      _options = widget.embeddedPollOptions!.map((e) => Map<String, dynamic>.from(e)).toList();
    }
    if (mounted) setState(() => _loading = false);
  }

  bool get _cannotVote => InteractionService.roleCannotVote(_role);

  bool get _alreadyVoted => widget.myOptionIds.isNotEmpty;

  String get _footerLine =>
      _isAnonymous ? 'Anonymous poll.' : 'Named vote (normal poll).';

  void _openDetailSync() => unawaited(widget.onOpenDetail());

  Future<void> _submitVote() async {
    if (_cannotVote) {
      await widget.onOpenDetail();
      return;
    }
    if (_selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Choose at least one option')));
      return;
    }
    setState(() => _submitting = true);
    try {
      final r = await InteractionService.instance.votePoll(
        widget.pollId,
        optionIds: _selected.toList(),
      );
      if (r['success'] == false) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(r['message']?.toString() ?? 'Could not submit vote')),
          );
        }
        return;
      }
      _selected.clear();
      widget.onVoteSubmitted();
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget _chartIcon() {
    return SizedBox(
      width: 22,
      height: 20,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(width: 5, height: 8, decoration: BoxDecoration(color: Colors.green.shade600, borderRadius: BorderRadius.circular(1))),
          Container(width: 5, height: 14, decoration: BoxDecoration(color: Colors.blue.shade600, borderRadius: BorderRadius.circular(1))),
          Container(width: 5, height: 11, decoration: BoxDecoration(color: Colors.purple.shade400, borderRadius: BorderRadius.circular(1))),
        ],
      ),
    );
  }

  Widget _submittedResultsUi() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Vote already submitted.',
          style: TextStyle(fontSize: 13, color: Colors.grey.shade700, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 8),
        ..._results.map((r) {
          final label = r['optionText']?.toString() ?? '';
          final pct = (r['percentage'] as num?)?.toInt() ?? 0;
          final count = (r['voteCount'] as num?)?.toInt() ?? 0;
          final progress = (pct / 100).clamp(0.0, 1.0);
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 9),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14, color: Color(0xFF0F172A)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '$count ($pct%)',
                      style: const TextStyle(fontSize: 14, color: Color(0xFF0F172A), fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                    backgroundColor: const Color(0xFFE5E7EB),
                    valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final titleUpper = (_serverTitle.isNotEmpty ? _serverTitle : widget.titleText).toUpperCase();
    final showVoteUi = !_loading && !_isClosed && !_cannotVote && !_alreadyVoted && _options.isNotEmpty;
    final showSubmittedUi = !_loading && _alreadyVoted && _results.isNotEmpty;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _cannotVote || _loading ? _openDetailSync : null,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade300),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 6, offset: const Offset(0, 2)),
            ],
          ),
          child: _loading
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))),
                )
              : _options.isEmpty
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(titleUpper, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF0F172A))),
                        const SizedBox(height: 8),
                        TextButton(onPressed: _openDetailSync, child: const Text('Open poll')),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            _chartIcon(),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                titleUpper,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF0F172A)),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (showSubmittedUi) ...[
                          _submittedResultsUi(),
                          const SizedBox(height: 2),
                        ] else if (_pollType == 'single')
                          ..._options.map((o) {
                            final id = o['_id']?.toString() ?? o['id']?.toString() ?? '';
                            final label = o['optionText']?.toString() ?? '';
                            final locked = _alreadyVoted || _isClosed || _cannotVote;
                            final groupVal = _alreadyVoted && widget.myOptionIds.isNotEmpty ? widget.myOptionIds.first : null;
                            return InkWell(
                              onTap: locked
                                  ? _openDetailSync
                                  : () {
                                      setState(() {
                                        _selected
                                          ..clear()
                                          ..add(id);
                                      });
                                    },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 2),
                                child: Row(
                                  children: [
                                    Radio<String>(
                                      value: id,
                                      groupValue: showVoteUi
                                          ? (_selected.length == 1 ? _selected.first : null)
                                          : groupVal,
                                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      visualDensity: VisualDensity.compact,
                                      onChanged: locked
                                          ? null
                                          : (v) {
                                              if (v == null) return;
                                              setState(() {
                                                _selected
                                                  ..clear()
                                                  ..add(v);
                                              });
                                            },
                                    ),
                                    Expanded(child: Text(label, style: const TextStyle(fontSize: 14, color: Color(0xFF0F172A)))),
                                  ],
                                ),
                              ),
                            );
                          })
                        else
                          ..._options.map((o) {
                            final id = o['_id']?.toString() ?? o['id']?.toString() ?? '';
                            final label = o['optionText']?.toString() ?? '';
                            final locked = _alreadyVoted || _isClosed || _cannotVote;
                            final checked = locked ? widget.myOptionIds.contains(id) : _selected.contains(id);
                            return InkWell(
                              onTap: locked
                                  ? _openDetailSync
                                  : () {
                                      setState(() {
                                        if (_selected.contains(id)) {
                                          _selected.remove(id);
                                        } else {
                                          _selected.add(id);
                                        }
                                      });
                                    },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 2),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Checkbox(
                                      value: checked,
                                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      visualDensity: VisualDensity.compact,
                                      onChanged: locked
                                          ? null
                                          : (v) {
                                              setState(() {
                                                if (v == true) {
                                                  _selected.add(id);
                                                } else {
                                                  _selected.remove(id);
                                                }
                                              });
                                            },
                                    ),
                                    Expanded(child: Text(label, style: const TextStyle(fontSize: 14, color: Color(0xFF0F172A)))),
                                  ],
                                ),
                              ),
                            );
                          }),
                        const SizedBox(height: 6),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              child: Text(
                                _footerLine,
                                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                              ),
                            ),
                            if (showVoteUi)
                              FilledButton(
                                style: FilledButton.styleFrom(
                                  backgroundColor: _voteBlue,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                                onPressed: _submitting ? null : _submitVote,
                                child: _submitting
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                      )
                                    : const Text('Vote'),
                              )
                            else if (_cannotVote)
                              TextButton(
                                onPressed: _openDetailSync,
                                child: const Text('View'),
                              ),
                          ],
                        ),
                      ],
                    ),
        ),
      ),
    );
  }
}

class _InlineVoiceMessagePlayer extends StatefulWidget {
  const _InlineVoiceMessagePlayer({
    required this.url,
    required this.isMine,
  });

  final String url;
  final bool isMine;

  @override
  State<_InlineVoiceMessagePlayer> createState() => _InlineVoiceMessagePlayerState();
}

class _InlineVoiceMessagePlayerState extends State<_InlineVoiceMessagePlayer> {
  final AudioPlayer _player = AudioPlayer();

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _prepared = false;
  bool _loading = false;
  bool _hasError = false;
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _player.positionStream.listen((d) {
      if (!mounted) return;
      setState(() => _position = d);
    });
    _player.durationStream.listen((d) {
      if (!mounted || d == null) return;
      setState(() => _duration = d);
    });
    _player.playerStateStream.listen((s) {
      if (!mounted) return;
      final completed = s.processingState == ProcessingState.completed;
      setState(() => _playing = s.playing && !completed);
      if (completed) {
        _player.seek(Duration.zero);
      }
    });
  }

  @override
  void dispose() {
    unawaited(_player.dispose());
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_loading || _hasError) return;
    if (_playing) {
      await _player.pause();
      return;
    }
    if (!_prepared) {
      if (mounted) setState(() => _loading = true);
      try {
        await _player.setUrl(widget.url);
        _prepared = true;
      } catch (_) {
        if (mounted) setState(() => _hasError = true);
      } finally {
        if (mounted) setState(() => _loading = false);
      }
    }
    if (_prepared) {
      await _player.play();
    }
  }

  String _fmt(Duration d) {
    final total = d.inSeconds;
    final m = total ~/ 60;
    final s = total % 60;
    final ss = s < 10 ? '0$s' : '$s';
    return '$m:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.isMine ? const Color(0xFF2E7D32) : AppColors.primary;
    final maxMs = _duration.inMilliseconds > 0 ? _duration.inMilliseconds.toDouble() : 1.0;
    final posMs = _position.inMilliseconds.clamp(0, _duration.inMilliseconds > 0 ? _duration.inMilliseconds : 0);

    if (_hasError) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 18, color: Colors.red.shade700),
          const SizedBox(width: 6),
          const Text('Voice unavailable', style: TextStyle(fontSize: 13)),
        ],
      );
    }

    return SizedBox(
      width: 220,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: _toggle,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _loading
                    ? Icons.hourglass_top_rounded
                    : (_playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
                size: 20,
                color: accent,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2.8,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                overlayShape: SliderComponentShape.noOverlay,
                activeTrackColor: accent,
                thumbColor: accent,
                inactiveTrackColor: Colors.grey.shade300,
              ),
              child: Slider(
                min: 0,
                max: maxMs,
                value: posMs.toDouble(),
                onChanged: _duration.inMilliseconds == 0
                    ? null
                    : (v) => _player.seek(Duration(milliseconds: v.round())),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            _fmt(_duration.inSeconds > 0 ? _duration : _position),
            style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
          ),
        ],
      ),
    );
  }
}
