// hrms/lib/screens/interaction/interaction_chat_list_screen.dart

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../config/app_colors.dart';
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
  List<Map<String, dynamic>> _chats = [];
  bool _loading = true;
  String? _error;
  StreamSubscription<Map<String, dynamic>>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = InteractionSocketService.instance.onNewMessage.listen((_) {
      _load();
    });
    _load();
  }

  @override
  void dispose() {
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
        final groupList = groupsRes['data'];
        if (groupList is List) {
          final ids = groupList
              .map((g) => g is Map ? (g['_id'] ?? g['id'])?.toString() : null)
              .whereType<String>()
              .where((s) => s.isNotEmpty)
              .toList();
          InteractionSocketService.instance.joinGroupChats(ids);
        }
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

  String _title(Map<String, dynamic> row) {
    final g = row['group'];
    if (g is Map) return (g['name'] ?? 'Group').toString();
    final r = row['receiver'];
    if (r is Map) return (r['name'] ?? 'Chat').toString();
    return 'Chat';
  }

  String? _avatar(Map<String, dynamic> row) {
    final g = row['group'];
    if (g is Map) {
      final u = g['avatarUrl'] ?? g['avatar'];
      if (u != null && u.toString().startsWith('http')) return u.toString();
    }
    final r = row['receiver'];
    if (r is Map) {
      final a = r['avatar'];
      if (a != null && a.toString().startsWith('http')) return a.toString();
    }
    return null;
  }

  String _groupTypePrefix(Map<String, dynamic> row) {
    final g = row['group'];
    if (g is! Map) return '';
    final t = g['groupType']?.toString() ?? '';
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
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          itemCount: _chats.length,
          itemBuilder: (context, i) {
            final row = _chats[i];
            final peer = row['receiverId']?.toString() ?? '';
            final gid = row['groupId']?.toString() ?? '';
            final listKey = gid.isNotEmpty ? 'g:$gid' : 'p:$peer';
            final unread = (row['unreadCount'] as num?)?.toInt() ?? 0;
            final avatarUrl = _avatar(row);
            final isGroup = row['groupId'] != null;
            return ListTile(
              key: ValueKey(listKey),
              leading: CircleAvatar(
                backgroundColor: AppColors.primary.withOpacity(0.2),
                backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
                child: avatarUrl == null
                    ? Text(
                        _title(row).isNotEmpty ? _title(row)[0].toUpperCase() : '?',
                        style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold),
                      )
                    : null,
              ),
              title: Text(_title(row), maxLines: 1, overflow: TextOverflow.ellipsis),
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
                          color: AppColors.primary,
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
              onTap: () async {
                final chatId = row['chatId']?.toString() ?? 'personal';
                final receiverId = row['receiverId']?.toString();
                final groupId = row['groupId']?.toString();
                await Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => InteractionChatThreadScreen(
                      chatId: isGroup ? (groupId ?? chatId) : chatId,
                      receiverId: isGroup ? null : receiverId,
                      title: _title(row),
                      avatarUrl: _avatar(row),
                      isGroup: isGroup,
                    ),
                  ),
                );
                _load();
              },
            );
          },
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
