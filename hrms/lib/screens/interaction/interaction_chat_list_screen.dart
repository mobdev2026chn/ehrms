// hrms/lib/screens/interaction/interaction_chat_list_screen.dart
// Messages list: search, All / Unread / Groups (web parity with ektaHR Interaction).

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../config/app_colors.dart';
import '../../utils/interaction_avatar_theme.dart';
import '../../utils/error_message_utils.dart';
import '../../services/interaction_service.dart';
import '../../services/interaction_socket_service.dart';
import 'interaction_chat_thread_screen.dart';
import 'interaction_new_chat_screen.dart';

class InteractionChatListScreen extends StatefulWidget {
  const InteractionChatListScreen({super.key});

  @override
  State<InteractionChatListScreen> createState() => _InteractionChatListScreenState();
}

class _InteractionChatListScreenState extends State<InteractionChatListScreen> {
  final _search = TextEditingController();
  List<Map<String, dynamic>> _chats = [];
  List<Map<String, dynamic>> _groupDirectory = [];
  List<Map<String, dynamic>> _suggestions = [];
  bool _loading = true;
  bool _suggestionsLoading = false;
  String? _error;
  StreamSubscription<Map<String, dynamic>>? _sub;
  Timer? _suggestDebounce;

  /// 0 All, 1 Unread, 2 Groups (matches web tabs).
  int _segment = 0;

  /// Chats the user has opened: rowKey → signature (last-message id/time) at the
  /// moment it was read. While that signature is unchanged we treat the chat as
  /// read locally, so the unread badge clears the instant you open the chat and
  /// stays clear across the post-return reload — even if the server's own unread
  /// count lags. A genuinely newer message changes the signature and the badge
  /// returns (WhatsApp behaviour).
  final Map<String, String> _readSignatures = {};

  String _rowKey(Map<String, dynamic> row) {
    final gid = row['groupId']?.toString();
    if (gid != null && gid.isNotEmpty) return 'g:$gid';
    final r = row['receiver'];
    final rid = (r is Map ? (r['_id']?.toString() ?? r['id']?.toString()) : null) ??
        row['receiverId']?.toString();
    if (rid != null && rid.isNotEmpty) return 'p:$rid';
    return 'c:${row['chatId']?.toString() ?? ''}';
  }

  String _lastMsgSignature(Map<String, dynamic> row) {
    final lm = row['lastMessage'];
    if (lm is Map) {
      final id = lm['_id']?.toString() ?? lm['id']?.toString();
      if (id != null && id.isNotEmpty) return id;
      final t = lm['sentTime']?.toString();
      if (t != null && t.isNotEmpty) return t;
    }
    return row['sentTime']?.toString() ?? '';
  }

  /// Mark a chat read locally up to its current latest message.
  void _markChatReadLocally(Map<String, dynamic> row) {
    final key = _rowKey(row);
    final sig = _lastMsgSignature(row);
    if (_readSignatures[key] == sig) return;
    setState(() => _readSignatures[key] = sig);
  }

  @override
  void initState() {
    super.initState();
    _sub = InteractionSocketService.instance.onNewMessage.listen((_) {
      _load();
    });
    _search.addListener(_onSearchChanged);
    _load();
  }

  void _onSearchChanged() {
    setState(() {});
    if (_segment == 1) {
      _suggestDebounce?.cancel();
      _suggestDebounce = Timer(const Duration(milliseconds: 400), _loadSuggestions);
    }
  }

  @override
  void dispose() {
    _suggestDebounce?.cancel();
    _search.removeListener(_onSearchChanged);
    _search.dispose();
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      try {
        final groupsRes = await InteractionService.instance.getGroups();
        final data = groupsRes['data'];
        final gList = <Map<String, dynamic>>[];
        if (data is List) {
          for (final e in data) {
            if (e is Map) {
              final m = <String, dynamic>{};
              e.forEach((k, v) => m[k.toString()] = v);
              gList.add(m);
            }
          }
        }
        if (mounted) setState(() => _groupDirectory = gList);
        final ids = gList
            .map((g) => g['_id'] ?? g['id'])
            .whereType<Object>()
            .map((x) => x.toString())
            .where((s) => s.isNotEmpty)
            .toList();
        InteractionSocketService.instance.joinGroupChats(ids);
      } on DioException catch (e) {
        if (!InteractionService.isInteractionApiUnavailable(e)) rethrow;
      }

      final chatRes = await InteractionService.instance.getChats();
      final data = chatRes['data'];
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
      int sentMs(Map<String, dynamic> row) {
        dynamic t = row['sentTime'];
        final lm = row['lastMessage'];
        if (t == null && lm is Map) t = lm['sentTime'];
        return DateTime.tryParse(t?.toString() ?? '')?.millisecondsSinceEpoch ?? 0;
      }

      list.sort((a, b) => sentMs(b).compareTo(sentMs(a)));
      if (mounted) {
        setState(() {
          _chats = list;
          _loading = false;
        });
      }
      if (_segment == 1 && _visibleChats.isEmpty && mounted) {
        await _loadSuggestions();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = InteractionService.isInteractionApiUnavailable(e)
              ? InteractionService.kInteractionMissingOnServerMessage
              : ErrorMessageUtils.toUserFriendlyMessage(e);
          _loading = false;
        });
      }
    }
  }

  List<Map<String, dynamic>> get _visibleChats {
    var list = List<Map<String, dynamic>>.from(_chats);
    final q = _search.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((row) {
        final t = _title(row).toLowerCase();
        final s = _subtitle(row).toLowerCase();
        return t.contains(q) || s.contains(q);
      }).toList();
    }
    switch (_segment) {
      case 1:
        return list.where((r) => _unreadCount(r) > 0).toList();
      case 2:
        return list.where((r) => r['groupId'] != null).toList();
      case 0:
      default:
        return list;
    }
  }

  Future<void> _loadSuggestions() async {
    if (!mounted) return;
    setState(() => _suggestionsLoading = true);
    try {
      final q = _search.text.trim();
      final res = await InteractionService.instance.getChatSuggestions(
        query: q.isEmpty ? null : q,
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
      if (mounted) setState(() => _suggestions = list);
    } catch (_) {
      if (mounted) setState(() => _suggestions = []);
    } finally {
      if (mounted) setState(() => _suggestionsLoading = false);
    }
  }

  String _groupDisplayName(Map<String, dynamic> g) {
    final raw = g['groupName'] ?? g['name'] ?? g['title'];
    if (raw != null && raw.toString().trim().isNotEmpty) return raw.toString().trim();
    return 'Group';
  }

  String? _nameForGroupId(String gid) {
    for (final m in _groupDirectory) {
      if (m['_id']?.toString() == gid || m['id']?.toString() == gid) {
        return _groupDisplayName(m);
      }
    }
    return null;
  }

  String _title(Map<String, dynamic> row) {
    final g = row['group'];
    if (g is Map) {
      final raw = g['name'] ?? g['groupName'] ?? g['title'];
      if (raw != null && raw.toString().trim().isNotEmpty) {
        return raw.toString().trim();
      }
    }
    final gid = row['groupId']?.toString();
    if (gid != null && gid.isNotEmpty) {
      final n = _nameForGroupId(gid);
      if (n != null && n.isNotEmpty) return n;
    }
    final r = row['receiver'];
    if (r is Map) return (r['name'] ?? 'Chat').toString();
    return 'Chat';
  }

  String _groupTypeForRow(Map<String, dynamic> row) {
    final g = row['group'];
    if (g is Map && g['groupType'] != null) {
      return g['groupType'].toString();
    }
    final gid = row['groupId']?.toString();
    if (gid == null) return '';
    for (final m in _groupDirectory) {
      if (m['_id']?.toString() == gid || m['id']?.toString() == gid) {
        return m['groupType']?.toString() ?? '';
      }
    }
    return '';
  }

  String? _avatar(Map<String, dynamic> row) {
    final g = row['group'];
    if (g is Map) {
      final u = g['avatarUrl'] ?? g['avatar'];
      final s = uToString(u);
      if (s.startsWith('http')) return s;
    }
    final gid = row['groupId']?.toString();
    if (gid != null) {
      for (final m in _groupDirectory) {
        if (m['_id']?.toString() == gid || m['id']?.toString() == gid) {
          final u = m['avatarUrl'] ?? m['avatar'];
          final s = uToString(u);
          if (s.startsWith('http')) return s;
        }
      }
    }
    final r = row['receiver'];
    if (r is Map) {
      final a = r['avatar'];
      if (a != null && uToString(a).startsWith('http')) return uToString(a);
    }
    return null;
  }

  static String uToString(dynamic u) => u.toString();

  String _groupTypePrefix(Map<String, dynamic> row) {
    final t = _groupTypeForRow(row);
    switch (t) {
      case 'broadcast':
        return 'Broadcast · ';
      case 'department':
        return 'Department · ';
      default:
        return '';
    }
  }

  String _subtitle(Map<String, dynamic> row) {
    final lm = row['lastMessage'];
    if (lm is! Map) return '';
    final type = lm['messageType']?.toString() ?? 'text';
    switch (type) {
      case 'image':
        return '${_groupTypePrefix(row)}📷 Photo';
      case 'file':
        return '${_groupTypePrefix(row)}📎 ${lm['fileName'] ?? 'File'}';
      case 'voice':
        return '${_groupTypePrefix(row)}🎤 Voice message';
      case 'poll':
        return '${_groupTypePrefix(row)}📊 Poll: ${lm['messageContent'] ?? ''}';
      case 'system':
        return '${_groupTypePrefix(row)}${lm['messageContent']?.toString() ?? ''}';
      default:
        return '${_groupTypePrefix(row)}${lm['messageContent']?.toString() ?? ''}';
    }
  }

  String _time(Map<String, dynamic> row) {
    dynamic t = row['sentTime'];
    final lm = row['lastMessage'];
    if (t == null && lm is Map) t = lm['sentTime'];
    if (t == null) return '';
    final dt = DateTime.tryParse(t.toString())?.toLocal();
    if (dt == null) return '';
    final now = DateTime.now();
    if (now.difference(dt).inDays < 1) {
      return DateFormat.jm().format(dt);
    }
    return DateFormat.MMMd().format(dt);
  }

  int _unreadCount(Map<String, dynamic> row) {
    // Locally read (and nothing newer has arrived) → no badge.
    final key = _rowKey(row);
    final sig = _readSignatures[key];
    if (sig != null && sig == _lastMsgSignature(row)) return 0;
    final raw = row['unreadCount'];
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw.trim()) ?? 0;
    final lm = row['lastMessage'];
    if (lm is Map) {
      final nested = lm['unreadCount'];
      if (nested is num) return nested.toInt();
      if (nested is String) return int.tryParse(nested.trim()) ?? 0;
    }
    return 0;
  }

  Future<void> _openThread(Map<String, dynamic> row) async {
    final chatId = row['chatId']?.toString() ?? 'personal';
    final receiver = row['receiver'];
    final receiverFromObj =
        receiver is Map ? (receiver['_id']?.toString() ?? receiver['id']?.toString()) : null;
    final receiverFromRow = row['receiverId']?.toString();
    // Web uses the selected receiver object id for personal thread fetch.
    // Prefer receiver object id, fallback to receiverId field.
    String? receiverId = (receiverFromObj != null && receiverFromObj.isNotEmpty)
        ? receiverFromObj
        : receiverFromRow;
    final groupId = row['groupId']?.toString();
    final isGroup = row['groupId'] != null;
    bool? canSend;
    final csTop = row['canSendMessages'];
    if (csTop is bool) {
      canSend = csTop;
    } else {
      final g = row['group'];
      if (g is Map && g['canSendMessages'] is bool) {
        canSend = g['canSendMessages'] as bool;
      }
    }
    bool? peerOnline;
    String? peerLastSeenAt;
    if (!isGroup) {
      final v = row['isOnline'];
      peerOnline = v is bool ? v : null;
      final ls = row['lastSeenAt']?.toString();
      peerLastSeenAt = (ls != null && ls.isNotEmpty) ? ls : null;
    } else {
      peerOnline = null;
      peerLastSeenAt = null;
    }
    // Clear the unread badge immediately on open (WhatsApp-style); the thread
    // marks the messages read on the server in the background.
    final key = _rowKey(row);
    _markChatReadLocally(row);
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => InteractionChatThreadScreen(
          chatId: isGroup ? (groupId ?? chatId) : chatId,
          receiverId: isGroup ? null : receiverId,
          title: _title(row),
          avatarUrl: _avatar(row),
          isGroup: isGroup,
          peerIsOnline: peerOnline,
          peerLastSeenAt: peerLastSeenAt,
          canSendMessages: canSend,
        ),
      ),
    );
    await _load();
    // Re-affirm read up to whatever is now the latest message, covering any
    // messages that arrived (and were viewed) while the thread was open.
    if (!mounted) return;
    final fresh = _chats.firstWhere(
      (r) => _rowKey(r) == key,
      orElse: () => const <String, dynamic>{},
    );
    if (fresh.isNotEmpty) _markChatReadLocally(fresh);
  }

  Widget _segmentBar() {
    const labels = ['All', 'Unread', 'Groups'];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: List.generate(3, (i) {
          final sel = _segment == i;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                decoration: BoxDecoration(
                  color: sel ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: sel
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () {
                      setState(() => _segment = i);
                      if (i == 1) {
                        _loadSuggestions();
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Text(
                        labels[i],
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontWeight: sel ? FontWeight.w600 : FontWeight.w500,
                          fontSize: 13,
                          color: sel ? AppColors.primary : Colors.grey.shade700,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _suggestionsBlock() {
    if (_segment != 1 || _visibleChats.isNotEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        Text(
          'No chats yet',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.grey.shade800),
        ),
        const SizedBox(height: 8),
        Text(
          'Start a conversation:',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 16),
        if (_suggestionsLoading) const LinearProgressIndicator(),
        ..._suggestions.map((u) {
          final id = u['_id']?.toString() ?? '';
          final name = u['name']?.toString() ?? 'User';
          final role = u['role']?.toString() ?? u['designation']?.toString() ?? '';
          final avatar = u['avatar']?.toString();
          final url = avatar != null && avatar.startsWith('http') ? avatar : null;
          final sugBg = InteractionAvatarTheme.backgroundForTitle(name);
          final sugFg = InteractionAvatarTheme.letterColor(sugBg);
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.grey.shade300),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: id.isEmpty
                    ? null
                    : () async {
                        await Navigator.push<void>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => InteractionChatThreadScreen(
                              chatId: 'personal',
                              receiverId: id,
                              title: name,
                              avatarUrl: url,
                              isGroup: false,
                            ),
                          ),
                        );
                        _load();
                      },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: sugBg,
                        backgroundImage: url != null ? CachedNetworkImageProvider(url) : null,
                        child: url == null
                            ? Text(
                                name.isNotEmpty ? name[0].toUpperCase() : '?',
                                style: TextStyle(
                                  color: sugFg,
                                  fontWeight: FontWeight.bold,
                                ),
                              )
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                            if (role.isNotEmpty)
                              Text(
                                role,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _chatTile(Map<String, dynamic> row) {
    final peer = row['receiverId']?.toString() ?? '';
    final gid = row['groupId']?.toString() ?? '';
    final listKey = gid.isNotEmpty ? 'g:$gid' : 'p:$peer';
    final unread = _unreadCount(row);
    final avatarUrl = _avatar(row);
    final title = _title(row);
    final gt = _groupTypeForRow(row);
    final letterBg =
        InteractionAvatarTheme.backgroundForTitle(title, groupType: gt.isEmpty ? null : gt);
    final letterFg = InteractionAvatarTheme.letterColor(letterBg);
    return ListTile(
      key: ValueKey(listKey),
      leading: CircleAvatar(
        backgroundColor: letterBg,
        backgroundImage: avatarUrl != null ? CachedNetworkImageProvider(avatarUrl) : null,
        child: avatarUrl == null
            ? Text(
                title.isNotEmpty ? title[0].toUpperCase() : '?',
                style: TextStyle(color: letterFg, fontWeight: FontWeight.bold),
              )
            : null,
      ),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        _subtitle(row),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(_time(row), style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          if (unread > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFE9A820),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  unread > 99 ? '99+' : '$unread',
                  style: const TextStyle(color: Colors.white, fontSize: 11),
                ),
              ),
            ),
        ],
      ),
      onTap: () => _openThread(row),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _chats.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _chats.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    final visible = _visibleChats;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _search,
                      style: const TextStyle(fontSize: 15),
                      decoration: InputDecoration(
                        hintText: 'Search conversations...',
                        hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 15),
                        prefixIcon: Icon(Icons.search, color: Colors.grey.shade600),
                        filled: true,
                        fillColor: Colors.white,
                        isDense: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(28),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(28),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(28),
                          borderSide: BorderSide(color: AppColors.primary, width: 1.5),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _segmentBar(),
                  ],
                ),
              ),
            ),
            if (_segment == 1 && visible.isEmpty)
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverToBoxAdapter(child: _suggestionsBlock()),
              ),
            if (visible.isEmpty && !(_segment == 1))
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Text(
                    _segment == 2 ? 'No group threads yet.' : 'No conversations match your search.',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                ),
              ),
            if (visible.isNotEmpty)
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) => _chatTile(visible[i]),
                  childCount: visible.length,
                ),
              ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.push<void>(
            context,
            MaterialPageRoute(builder: (_) => const InteractionNewChatScreen()),
          );
          _load();
        },
        backgroundColor: AppColors.primary,
        child: const Icon(Icons.chat, color: Colors.white),
      ),
    );
  }
}
