// lib/services/staff_interaction_service.dart
//
// Staff Interaction module (Chats, Polls & Surveys, Announcements) against
// HRMSbackend — the same backend the web uses:
//   Chat          /api/staff/interaction/chat/...      (+ Socket.IO for live updates)
//   Polls         /api/staff/interaction/polls/...
//   Announcements /api/staff/announcements/...
//
// Everything that changes data (send, read, vote, comment) goes over REST so it
// works even where the server's Socket.IO path isn't reachable. The socket is
// only used for live events (new message, typing, presence, read receipts);
// screens fall back to polling while it is disconnected.

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../config/constants.dart';
import 'api_client.dart';

// ── Models ────────────────────────────────────────────────────────────────────

Map<String, dynamic> _map(dynamic v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
List<dynamic> _list(dynamic v) => v is List ? v : const [];
String _str(dynamic v) => v == null ? '' : v.toString();
DateTime? _date(dynamic v) {
  final s = _str(v).trim();
  if (s.isEmpty) return null;
  return DateTime.tryParse(s)?.toLocal();
}

class ChatConversation {
  ChatConversation({
    required this.id,
    required this.type,
    required this.title,
    required this.subtitle,
    required this.avatar,
    required this.lastMessage,
    required this.lastMessageAt,
    required this.unreadCount,
    required this.participantId,
    required this.participantsCount,
  });

  final String id;

  /// 'direct' | 'group' | 'broadcast'
  final String type;
  final String title;
  final String subtitle;
  final String avatar;
  String lastMessage;
  DateTime? lastMessageAt;
  int unreadCount;

  /// Direct chats: the other person's id (for presence).
  final String participantId;
  final int participantsCount;

  bool get isBroadcast => type == 'broadcast';
  bool get isGroup => type == 'group';

  factory ChatConversation.fromJson(Map<String, dynamic> j, String? myId) {
    final parts = _list(j['participants']).map(_map).toList();
    var unread = 0;
    for (final p in parts) {
      if (_str(p['userId']) == myId) {
        unread = (p['unreadCount'] is num) ? (p['unreadCount'] as num).toInt() : 0;
      }
    }
    return ChatConversation(
      id: _str(j['id']).isNotEmpty ? _str(j['id']) : _str(j['_id']),
      type: _str(j['type']).isEmpty ? 'direct' : _str(j['type']),
      title: _str(j['title']).isEmpty ? 'Conversation' : _str(j['title']),
      subtitle: _str(j['subtitle']),
      avatar: _str(j['avatar']),
      lastMessage: _str(j['lastMessage']),
      lastMessageAt: _date(j['lastMessageAt'] ?? j['updatedAt']),
      unreadCount: unread,
      participantId: _str(j['participantId']),
      participantsCount: parts.length,
    );
  }
}

class ChatAttachment {
  ChatAttachment({required this.name, required this.size, required this.type, required this.url});
  final String name;
  final int size;

  /// 'image' | 'document' | 'pdf'
  final String type;
  final String url;

  bool get isImage => type == 'image';

  factory ChatAttachment.fromJson(Map<String, dynamic> j) => ChatAttachment(
        name: _str(j['name']).isEmpty ? 'attachment' : _str(j['name']),
        size: (j['size'] is num) ? (j['size'] as num).toInt() : 0,
        type: _str(j['type']).isEmpty ? 'document' : _str(j['type']),
        url: _str(j['url']),
      );

  Map<String, dynamic> toJson() => {'name': name, 'size': size, 'type': type, 'url': url};
}

class ChatMessage {
  ChatMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.senderName,
    required this.senderAvatar,
    required this.content,
    required this.attachments,
    required this.status,
    required this.createdAt,
    this.isSystem = false,
    this.pending = false,
    this.failed = false,
  });

  final String id;
  final String conversationId;
  final String senderId;
  final String senderName;
  final String senderAvatar;
  final String content;
  final List<ChatAttachment> attachments;
  String status;
  final DateTime createdAt;
  final bool isSystem;

  /// Local-only: sent from this device, waiting for the server.
  bool pending;
  bool failed;

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
        id: _str(j['id']).isNotEmpty ? _str(j['id']) : _str(j['_id']),
        conversationId: _str(j['conversationId']),
        senderId: _str(j['senderId']),
        senderName: _str(j['senderName']),
        senderAvatar: _str(j['senderAvatar']),
        content: _str(j['content']),
        attachments: _list(j['attachments']).map((a) => ChatAttachment.fromJson(_map(a))).toList(),
        status: _str(j['status']).isEmpty ? 'sent' : _str(j['status']),
        createdAt: _date(j['createdAt']) ?? DateTime.now(),
        isSystem: j['isSystemMessage'] == true,
      );
}

class ChatContact {
  ChatContact({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.avatar,
    this.isAdmin = false,
  });
  final String id;
  final String name;
  final String subtitle;
  final String avatar;
  final bool isAdmin;
}

class PollOption {
  PollOption({required this.id, required this.text, required this.votes});
  final String id;
  final String text;
  final int votes;
}

class StaffPoll {
  StaffPoll({
    required this.id,
    required this.question,
    required this.description,
    required this.multiple,
    required this.anonymous,
    required this.status,
    required this.endDate,
    required this.totalVotes,
    required this.options,
    required this.hasVoted,
    required this.myOptionIds,
    required this.createdBy,
    required this.targetLabel,
  });

  final String id;
  final String question;
  final String description;
  final bool multiple;
  final bool anonymous;
  final String status;
  final DateTime? endDate;
  final int totalVotes;
  final List<PollOption> options;
  final bool hasVoted;
  final List<String> myOptionIds;
  final String createdBy;
  final String targetLabel;

  /// Closed when completed, or past its end date (the server doesn't enforce
  /// the date, so the app does).
  bool get isClosed {
    if (status.toLowerCase() == 'completed') return true;
    final e = endDate;
    if (e == null) return false;
    final endOfDay = DateTime(e.year, e.month, e.day, 23, 59, 59);
    return DateTime.now().isAfter(endOfDay);
  }

  factory StaffPoll.fromJson(Map<String, dynamic> j, String? myId) {
    final options = _list(j['options']).map(_map).map((o) {
      return PollOption(
        id: _str(o['id']),
        text: _str(o['text']),
        votes: (o['votes'] is num) ? (o['votes'] as num).toInt() : 0,
      );
    }).toList();
    var mine = _list(j['userVotedOptionIds']).map(_str).toList();
    var hasVoted = j['hasVoted'] == true;
    // The vote response is the raw poll (no hasVoted): derive it from votesRecord.
    if (!hasVoted && myId != null) {
      for (final r in _list(j['votesRecord']).map(_map)) {
        if (_str(r['userId']) == myId) {
          hasVoted = true;
          mine = _list(r['optionIds']).map(_str).toList();
        }
      }
    }
    final total = (j['totalVotes'] is num)
        ? (j['totalVotes'] as num).toInt()
        : options.fold<int>(0, (a, o) => a + o.votes);
    return StaffPoll(
      id: _str(j['id']).isNotEmpty ? _str(j['id']) : _str(j['_id']),
      question: _str(j['question']),
      description: _str(j['description']),
      multiple: _str(j['choiceType']) == 'multiple',
      anonymous: _str(j['visibility']) == 'anonymous',
      status: _str(j['status']).isEmpty ? 'Active' : _str(j['status']),
      endDate: _date(j['endDate']),
      totalVotes: total,
      options: options,
      hasVoted: hasVoted,
      myOptionIds: mine,
      createdBy: _str(j['createdBy']),
      targetLabel: _str(j['targetLabel']),
    );
  }
}

class AnnouncementReply {
  AnnouncementReply({required this.senderName, required this.senderRole, required this.message, required this.createdAt});
  final String senderName;
  final String senderRole;
  final String message;
  final DateTime? createdAt;
}

class AnnouncementThread {
  AnnouncementThread({required this.id, required this.comment, required this.createdAt, required this.replies});
  final String id;
  final String comment;
  final DateTime? createdAt;
  final List<AnnouncementReply> replies;
}

class StaffAnnouncement {
  StaffAnnouncement({
    required this.id,
    required this.title,
    required this.subject,
    required this.description,
    required this.from,
    required this.coverUrl,
    required this.publishDate,
    required this.expiryDate,
    required this.sections,
    required this.attachments,
    required this.threads,
    this.audience = '',
    this.isDraft = false,
    this.rawPublishDate,
    this.createdAt,
  });

  final String id;
  final String title;
  final String subject;
  final String description;
  final String from;
  final String coverUrl;
  final DateTime? publishDate;
  final DateTime? expiryDate;
  final List<({String title, String body, String image})> sections;
  final List<ChatAttachment> attachments;
  final List<AnnouncementThread> threads;
  final String audience;
  final bool isDraft;

  /// The publish date as set (no createdAt fallback), for the Scheduled status.
  final DateTime? rawPublishDate;
  final DateTime? createdAt;

  /// Same rule as the web staff page: Draft → Expired (expiry before today) →
  /// Scheduled (publish date after today) → Published. Compared by calendar day.
  String get status {
    if (isDraft) return 'Draft';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    DateTime? day(DateTime? d) {
      if (d == null) return null;
      final l = d.toLocal();
      return DateTime(l.year, l.month, l.day);
    }
    final expiry = day(expiryDate);
    if (expiry != null && expiry.isBefore(today)) return 'Expired';
    final publish = day(rawPublishDate);
    return publish != null && publish.isAfter(today) ? 'Scheduled' : 'Published';
  }

  factory StaffAnnouncement.fromJson(Map<String, dynamic> j) {
    final sections = _list(j['subsections']).map(_map).map((s) {
      return (
        title: _str(s['title']).isNotEmpty ? _str(s['title']) : _str(s['heading']),
        body: _str(s['content']).isNotEmpty ? _str(s['content']) : _str(s['body']),
        image: _str(s['image']),
      );
    }).toList();
    final atts = _list(j['attachments']).map(_map).map((a) {
      final name = _str(a['name']);
      final lower = name.toLowerCase();
      final url = _str(a['url']);
      final isImg = RegExp(r'\.(png|jpe?g|gif|webp)$').hasMatch(lower) || url.startsWith('data:image');
      return ChatAttachment(
        name: name.isEmpty ? 'attachment' : name,
        size: (a['size'] is num) ? (a['size'] as num).toInt() : 0,
        type: isImg ? 'image' : (lower.endsWith('.pdf') ? 'pdf' : 'document'),
        url: url,
      );
    }).toList();
    final threads = _list(j['engagements']).map(_map).map((e) {
      final replies = <AnnouncementReply>[
        for (final r in _list(e['replies']).map(_map))
          AnnouncementReply(
            senderName: _str(r['senderName']),
            senderRole: _str(r['senderRole']),
            message: _str(r['message']),
            createdAt: _date(r['createdAt']),
          ),
        // Older records keep HR answers in hrResponses.
        for (final r in _list(e['hrResponses']).map(_map))
          AnnouncementReply(
            senderName: _str(r['senderName'] ?? r['responderName'] ?? 'HR'),
            senderRole: 'hr',
            message: _str(r['message'] ?? r['response'] ?? r['text']),
            createdAt: _date(r['createdAt']),
          ),
      ]..sort((a, b) => (a.createdAt ?? DateTime(0)).compareTo(b.createdAt ?? DateTime(0)));
      return AnnouncementThread(
        id: _str(e['id']).isNotEmpty ? _str(e['id']) : _str(e['_id']),
        comment: _str(e['comment']),
        createdAt: _date(e['createdAt']),
        replies: replies,
      );
    }).toList();
    return StaffAnnouncement(
      id: _str(j['id']).isNotEmpty ? _str(j['id']) : _str(j['_id']),
      title: _str(j['title']),
      subject: _str(j['subject']),
      description: _str(j['description']),
      from: _str(j['from']),
      coverUrl: _str(j['coverUrl']),
      publishDate: _date(j['publishDate'] ?? j['createdAt']),
      expiryDate: _date(j['expiryDate']),
      sections: sections,
      attachments: atts,
      threads: threads,
      audience: _str(j['audience']),
      isDraft: j['isDraft'] == true,
      rawPublishDate: _date(j['publishDate']),
      createdAt: _date(j['createdAt']),
    );
  }
}

/// Result wrapper: data on success, a user-facing message on failure.
class InteractionResult<T> {
  InteractionResult.ok(this.data) : error = null;
  InteractionResult.fail(this.error) : data = null;
  final T? data;
  final String? error;
  bool get ok => error == null;
}

// ── Service ───────────────────────────────────────────────────────────────────

class StaffInteractionService {
  StaffInteractionService._();
  static final StaffInteractionService instance = StaffInteractionService._();

  static const _chat = '/staff/interaction/chat';
  static const _polls = '/staff/interaction/polls';
  static const _ann = '/staff/announcements';

  Dio get _dio => ApiClient().dio;

  String? _myId;

  /// Signed-in staff id (from the stored user snapshot).
  Future<String?> myId() async {
    if (_myId != null) return _myId;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('user');
    if (raw == null || raw.isEmpty) return null;
    try {
      final u = jsonDecode(raw) as Map<String, dynamic>;
      _myId = (u['_id'] ?? u['id'])?.toString();
    } catch (_) {}
    return _myId;
  }

  static String _err(Object e, String fallback) {
    if (e is DioException) {
      final body = e.response?.data;
      if (body is Map && body['message'] != null) return body['message'].toString();
      if (e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        return 'No internet connection. Please try again.';
      }
    }
    return fallback;
  }

  // ── Chat ──

  Future<InteractionResult<List<ChatConversation>>> getConversations() async {
    try {
      final me = await myId();
      final res = await _dio.get('$_chat/conversations');
      final list = _list(_map(_map(res.data)['data'])['conversations'])
          .map((c) => ChatConversation.fromJson(_map(c), me))
          .toList();
      return InteractionResult.ok(list);
    } catch (e) {
      return InteractionResult.fail(_err(e, 'Could not load chats.'));
    }
  }

  Future<InteractionResult<List<ChatContact>>> getDirectory() async {
    try {
      final res = await _dio.get('$_chat/directory');
      final data = _map(_map(res.data)['data']);
      final out = <ChatContact>[];
      final admin = _map(data['admin']);
      if (_str(admin['_id']).isNotEmpty) {
        out.add(ChatContact(
          id: _str(admin['_id']),
          name: _str(admin['companyAdmin']).isNotEmpty ? _str(admin['companyAdmin']) : _str(admin['name']),
          subtitle: 'Admin',
          avatar: _str(admin['logo']),
          isAdmin: true,
        ));
      }
      for (final s in _list(data['staff']).map(_map)) {
        final status = _str(s['status']).toLowerCase();
        if (status.isNotEmpty && status != 'active') continue;
        final name = '${_str(s['firstName'])} ${_str(s['lastName'])}'.trim();
        final sub = [_str(s['designation']), _str(s['department'])].where((x) => x.isNotEmpty).join(' • ');
        out.add(ChatContact(
          id: _str(s['_id']),
          name: name.isEmpty ? _str(s['email']) : name,
          subtitle: sub,
          avatar: _str(s['profilePic']),
        ));
      }
      return InteractionResult.ok(out);
    } catch (e) {
      return InteractionResult.fail(_err(e, 'Could not load colleagues.'));
    }
  }

  /// Get-or-create a direct conversation; returns its id.
  Future<InteractionResult<String>> openDirect(String targetUserId) async {
    try {
      final res = await _dio.post('$_chat/direct', data: {'targetUserId': targetUserId});
      final conv = _map(_map(_map(res.data)['data'])['conversation']);
      final id = _str(conv['_id']).isNotEmpty ? _str(conv['_id']) : _str(conv['id']);
      if (id.isEmpty) return InteractionResult.fail('Could not start the chat.');
      return InteractionResult.ok(id);
    } catch (e) {
      return InteractionResult.fail(_err(e, 'Could not start the chat.'));
    }
  }

  /// Messages oldest → newest. The server returns the OLDEST `limit` messages,
  /// so a generous limit is asked for to include the latest ones.
  Future<InteractionResult<List<ChatMessage>>> getMessages(String conversationId, {int limit = 500}) async {
    try {
      final res = await _dio.get(
        '$_chat/conversations/$conversationId/messages',
        queryParameters: {'limit': limit},
      );
      final list = _list(_map(_map(res.data)['data'])['messages'])
          .map((m) => ChatMessage.fromJson(_map(m)))
          .toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      return InteractionResult.ok(list);
    } catch (e) {
      return InteractionResult.fail(_err(e, 'Could not load messages.'));
    }
  }

  Future<InteractionResult<ChatMessage>> sendMessage(
    String conversationId, {
    String content = '',
    List<ChatAttachment> attachments = const [],
  }) async {
    try {
      final res = await _dio.post(
        '$_chat/conversations/$conversationId/messages',
        data: {
          'content': content,
          if (attachments.isNotEmpty) 'attachments': attachments.map((a) => a.toJson()).toList(),
        },
        options: Options(sendTimeout: const Duration(seconds: 60)),
      );
      final m = _map(_map(_map(res.data)['data'])['message']);
      return InteractionResult.ok(ChatMessage.fromJson(m));
    } catch (e) {
      if (e is DioException && e.response?.statusCode == 413) {
        return InteractionResult.fail('File is too large to send.');
      }
      return InteractionResult.fail(_err(e, 'Message not sent.'));
    }
  }

  Future<void> markRead(String conversationId) async {
    try {
      await _dio.post('$_chat/conversations/$conversationId/read');
    } catch (_) {}
  }

  // ── Polls ──

  Future<InteractionResult<List<StaffPoll>>> getPolls() async {
    try {
      final me = await myId();
      final res = await _dio.get('$_polls/');
      final list = _list(_map(_map(res.data)['data'])['polls'])
          .map((p) => StaffPoll.fromJson(_map(p), me))
          .toList();
      return InteractionResult.ok(list);
    } catch (e) {
      return InteractionResult.fail(_err(e, 'Could not load polls.'));
    }
  }

  Future<InteractionResult<StaffPoll>> vote(String pollId, List<String> optionIds) async {
    try {
      final me = await myId();
      final res = await _dio.post('$_polls/$pollId/vote', data: {'optionIds': optionIds});
      final poll = _map(_map(_map(res.data)['data'])['poll']);
      return InteractionResult.ok(StaffPoll.fromJson(poll, me));
    } catch (e) {
      return InteractionResult.fail(_err(e, 'Vote not recorded.'));
    }
  }

  // ── Announcements ──

  Future<InteractionResult<({List<StaffAnnouncement> items, int totalPages})>> getAnnouncements({
    int page = 1,
    int limit = 10,
    String search = '',
  }) async {
    try {
      final res = await _dio.get(_ann, queryParameters: {
        'page': page,
        'limit': limit,
        if (search.trim().isNotEmpty) 'search': search.trim(),
      });
      final data = _map(_map(res.data)['data']);
      final items = _list(data['announcements']).map((a) => StaffAnnouncement.fromJson(_map(a))).toList();
      final pages = _map(data['pagination'])['totalPages'];
      return InteractionResult.ok((items: items, totalPages: pages is num ? pages.toInt() : 1));
    } catch (e) {
      return InteractionResult.fail(_err(e, 'Could not load announcements.'));
    }
  }

  Future<InteractionResult<StaffAnnouncement>> getAnnouncement(String id) async {
    try {
      final res = await _dio.get('$_ann/$id');
      final a = _map(_map(_map(res.data)['data'])['announcement']);
      return InteractionResult.ok(StaffAnnouncement.fromJson(a.isNotEmpty ? a : _map(_map(res.data)['data'])));
    } catch (e) {
      return InteractionResult.fail(_err(e, 'Could not load the announcement.'));
    }
  }

  StaffAnnouncement? _announcementFrom(dynamic body) {
    final data = _map(_map(body)['data']);
    final a = data['announcement'] is Map ? _map(data['announcement']) : data;
    return a.isEmpty ? null : StaffAnnouncement.fromJson(a);
  }

  Future<InteractionResult<StaffAnnouncement?>> commentOnAnnouncement(String id, String comment) async {
    try {
      final res = await _dio.post('$_ann/$id/engagements', data: {'comment': comment});
      return InteractionResult.ok(_announcementFrom(res.data));
    } catch (e) {
      return InteractionResult.fail(_err(e, 'Comment not posted.'));
    }
  }

  Future<InteractionResult<StaffAnnouncement?>> replyOnAnnouncement(
    String id,
    String engagementId,
    String message,
  ) async {
    try {
      final res = await _dio.post('$_ann/$id/engagements/$engagementId/reply', data: {'message': message});
      return InteractionResult.ok(_announcementFrom(res.data));
    } catch (e) {
      return InteractionResult.fail(_err(e, 'Reply not posted.'));
    }
  }

  // ── Live updates (Socket.IO) ────────────────────────────────────────────────

  io.Socket? _socket;
  final _messages = StreamController<ChatMessage>.broadcast();
  final _convUpdates = StreamController<Map<String, dynamic>>.broadcast();
  final _typing = StreamController<({String conversationId, String userId, String userName, bool isTyping})>.broadcast();
  final _readUpdates = StreamController<({String conversationId, String userId})>.broadcast();
  final Set<String> _online = {};
  final _presence = StreamController<Set<String>>.broadcast();
  final ValueNotifier<bool> connected = ValueNotifier(false);
  final Set<String> _joined = {};

  Stream<ChatMessage> get onMessage => _messages.stream;
  Stream<Map<String, dynamic>> get onConversationUpdated => _convUpdates.stream;
  Stream<({String conversationId, String userId, String userName, bool isTyping})> get onTyping => _typing.stream;
  Stream<({String conversationId, String userId})> get onRead => _readUpdates.stream;
  Stream<Set<String>> get onPresence => _presence.stream;
  bool isOnline(String userId) => _online.contains(userId);

  Future<void> connect() async {
    if (_socket != null) {
      if (_socket!.disconnected) _socket!.connect();
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    var token = prefs.getString('token')?.replaceAll('"', '').trim();
    if (token == null || token.isEmpty) return;

    final s = io.io(
      AppConstants.interactionSocketOrigin,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .setAuth({'token': token})
          .enableReconnection()
          .setReconnectionDelay(3000)
          .setReconnectionDelayMax(30000)
          .build(),
    );
    _socket = s;

    s.onConnect((_) {
      connected.value = true;
      for (final id in _joined) {
        s.emit('conversation:join', {'conversationId': id});
      }
    });
    s.onDisconnect((_) => connected.value = false);
    s.onConnectError((e) {
      connected.value = false;
      if (kDebugMode) debugPrint('[StaffInteraction] socket connect error: $e');
    });

    // The server sends message:new to both the conversation room and the user
    // room, so the same message can arrive twice — screens dedupe by id.
    s.on('message:new', (data) {
      final m = _map(_map(data)['message']);
      if (m.isEmpty) return;
      final msg = ChatMessage.fromJson(m);
      if (msg.conversationId.isEmpty) return;
      _messages.add(msg);
    });
    s.on('conversation:updated', (data) => _convUpdates.add(_map(data)));
    s.on('typing:update', (data) {
      final d = _map(data);
      _typing.add((
        conversationId: _str(d['conversationId']),
        userId: _str(d['userId']),
        userName: _str(d['userName']),
        isTyping: d['isTyping'] == true,
      ));
    });
    s.on('message:read_update', (data) {
      final d = _map(data);
      _readUpdates.add((conversationId: _str(d['conversationId']), userId: _str(d['userId'])));
    });
    s.on('presence:status_change', (data) {
      final d = _map(data);
      final uid = _str(d['userId']);
      if (uid.isEmpty) return;
      if (_str(d['status']) == 'online') {
        _online.add(uid);
      } else {
        _online.remove(uid);
      }
      _presence.add(Set.unmodifiable(_online));
    });

    s.connect();
  }

  void joinConversation(String id) {
    _joined.add(id);
    if (_socket?.connected == true) _socket!.emit('conversation:join', {'conversationId': id});
  }

  void leaveConversation(String id) {
    _joined.remove(id);
    if (_socket?.connected == true) _socket!.emit('conversation:leave', {'conversationId': id});
  }

  void setTyping(String conversationId, bool typing) {
    if (_socket?.connected != true) return;
    _socket!.emit(typing ? 'typing:start' : 'typing:stop', {'conversationId': conversationId});
  }

  /// Called on logout: drop the socket and anything tied to the old user.
  void reset() {
    _socket?.dispose();
    _socket = null;
    connected.value = false;
    _joined.clear();
    _online.clear();
    _myId = null;
  }
}
