// Admin "Interaction" (Groups, Broadcasts, Polls & Surveys) against HRMSbackend - the same
// APIs the web admin uses (src/features/admin/interaction/**):
//   chat   /admin/interaction/chat/*   (controllers/admin/interactions/adminChatController.ts)
//   polls  /admin/interaction/polls/*  (controllers/admin/interactions/adminPollController.ts)
// Both are gated by the company 'interaction' module and the admin role.
// These controllers answer `{status: 'success', data: {...}}` (not `{success: true}`), and
// errors as `{status: 'fail'|'error', message}`. Every call throws an Exception carrying the
// server's message on failure.

import 'package:dio/dio.dart';

import 'api_client.dart';

// ── Models ──────────────────────────────────────────────────────────────

String _str(dynamic v, [String fallback = '']) => v == null ? fallback : v.toString();
int _int(dynamic v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;
DateTime? _date(dynamic v) => v == null ? null : DateTime.tryParse(v.toString())?.toLocal();
List<Map<String, dynamic>> _maps(dynamic v) =>
    v is List ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : <Map<String, dynamic>>[];
String _id(Map<String, dynamic> j) => _str(j['id'] ?? j['_id']);

/// A staff member from `GET /chat/staff` (raw Staff fields) or `GET /polls/staff` (formatted).
class InteractionStaff {
  final String id;
  final String name;
  final String department;
  final String designation;
  final String email;
  final String avatar;

  const InteractionStaff({
    required this.id,
    required this.name,
    required this.department,
    required this.designation,
    required this.email,
    required this.avatar,
  });

  factory InteractionStaff.fromJson(Map<String, dynamic> j) {
    final full = j['name'] != null
        ? _str(j['name'])
        : '${_str(j['firstName'])} ${_str(j['lastName'])}'.trim();
    final dept = _str(j['department']);
    final desig = _str(j['designation']);
    return InteractionStaff(
      id: _id(j),
      name: full.isEmpty ? 'Employee' : full,
      department: dept.isEmpty ? 'General' : dept,
      designation: desig.isEmpty ? 'Staff Member' : desig,
      email: _str(j['email']),
      avatar: _str(j['profilePic'] ?? j['profilePhoto'] ?? j['avatar']),
    );
  }
}

class ChatGroupMember {
  final String employeeId;
  final String name;
  final String department;
  final String role; // 'Admin' | 'Member'
  final DateTime? joinedDate;

  const ChatGroupMember({
    required this.employeeId,
    required this.name,
    required this.department,
    required this.role,
    this.joinedDate,
  });

  factory ChatGroupMember.fromJson(Map<String, dynamic> j) => ChatGroupMember(
        employeeId: _str(j['employeeId']),
        name: _str(j['name'], 'Member'),
        department: _str(j['department']),
        role: _str(j['role'], 'Member'),
        joinedDate: _date(j['joinedDate']),
      );
}

class ChatGroup {
  final String id;
  final String name;
  final String description;
  final String avatar;
  final int membersCount;
  final List<ChatGroupMember> members;
  final String createdBy;
  final List<String> tags;
  final DateTime? createdAt;

  const ChatGroup({
    required this.id,
    required this.name,
    required this.description,
    required this.avatar,
    required this.membersCount,
    required this.members,
    required this.createdBy,
    required this.tags,
    this.createdAt,
  });

  factory ChatGroup.fromJson(Map<String, dynamic> j) {
    final members = _maps(j['members']).map(ChatGroupMember.fromJson).toList();
    return ChatGroup(
      id: _id(j),
      name: _str(j['name'], 'Group'),
      description: _str(j['description']),
      avatar: _str(j['avatar']),
      membersCount: j['membersCount'] != null ? _int(j['membersCount']) : members.length,
      members: members,
      createdBy: _str(j['createdBy']),
      tags: j['tags'] is List ? (j['tags'] as List).map((e) => e.toString()).toList() : const [],
      createdAt: _date(j['createdAt']),
    );
  }
}

class BroadcastNotice {
  final String id;
  final String content;
  final DateTime? sentAt;
  final int readCount;

  const BroadcastNotice({required this.id, required this.content, this.sentAt, required this.readCount});

  factory BroadcastNotice.fromJson(Map<String, dynamic> j) => BroadcastNotice(
        id: _str(j['id']),
        content: _str(j['content']),
        sentAt: _date(j['sentAt']),
        readCount: _int(j['readCount']),
      );
}

class BroadcastRecipient {
  final String employeeId;
  final String name;
  final String department;
  final String branch;

  const BroadcastRecipient({
    required this.employeeId,
    required this.name,
    required this.department,
    required this.branch,
  });

  factory BroadcastRecipient.fromJson(Map<String, dynamic> j) => BroadcastRecipient(
        employeeId: _str(j['employeeId']),
        name: _str(j['name'], 'Employee'),
        department: _str(j['department']),
        branch: _str(j['branch']),
      );
}

class ChatBroadcast {
  final String id;
  final String title;
  final String description;
  final String targetType; // 'all' | 'specific'
  final String targetLabel;
  final int recipientsCount;
  final List<BroadcastRecipient> recipients;
  final String status; // Active | Draft | Archived | Completed
  final String createdBy;
  final List<BroadcastNotice> messages;
  final DateTime? lastBroadcastDate;
  final DateTime? createdAt;

  const ChatBroadcast({
    required this.id,
    required this.title,
    required this.description,
    required this.targetType,
    required this.targetLabel,
    required this.recipientsCount,
    required this.recipients,
    required this.status,
    required this.createdBy,
    required this.messages,
    this.lastBroadcastDate,
    this.createdAt,
  });

  factory ChatBroadcast.fromJson(Map<String, dynamic> j) => ChatBroadcast(
        id: _id(j),
        title: _str(j['title'], 'Broadcast'),
        description: _str(j['description']),
        targetType: _str(j['targetType'], 'all'),
        targetLabel: _str(j['targetLabel']),
        recipientsCount: _int(j['recipientsCount']),
        recipients: _maps(j['recipients']).map(BroadcastRecipient.fromJson).toList(),
        status: _str(j['status'], 'Active'),
        createdBy: _str(j['createdBy']),
        messages: _maps(j['messages']).map(BroadcastNotice.fromJson).toList(),
        lastBroadcastDate: _date(j['lastBroadcastDate']),
        createdAt: _date(j['createdAt']),
      );
}

/// A message of a chat conversation (`GET /chat/conversations/:id/messages`).
class AdminChatMessage {
  final String id;
  final String senderName;
  final String senderType; // 'admin' | 'staff'
  final String content;
  final DateTime? createdAt;

  const AdminChatMessage({
    required this.id,
    required this.senderName,
    required this.senderType,
    required this.content,
    this.createdAt,
  });

  factory AdminChatMessage.fromJson(Map<String, dynamic> j) => AdminChatMessage(
        id: _id(j),
        senderName: _str(j['senderName'], 'User'),
        senderType: _str(j['senderType']),
        content: _str(j['content']),
        createdAt: _date(j['createdAt']),
      );
}

class PollVoter {
  final String id;
  final String name;
  final DateTime? votedAt;

  const PollVoter({required this.id, required this.name, this.votedAt});

  factory PollVoter.fromJson(Map<String, dynamic> j) =>
      PollVoter(id: _str(j['id']), name: _str(j['name'], 'Unknown user'), votedAt: _date(j['votedAt']));
}

class PollOption {
  final String id;
  final String text;
  final int votes;
  final List<PollVoter> voters;

  const PollOption({required this.id, required this.text, required this.votes, required this.voters});

  factory PollOption.fromJson(Map<String, dynamic> j) => PollOption(
        id: _str(j['id']),
        text: _str(j['text']),
        votes: _int(j['votes']),
        voters: _maps(j['voters']).map(PollVoter.fromJson).toList(),
      );
}

class AdminPoll {
  final String id;
  final String question;
  final String description;
  final String choiceType; // single | multiple
  final String visibility; // normal | anonymous
  final String sendTo; // all | single | group | broadcast
  final String targetLabel;
  final String endDate; // 'YYYY-MM-DD' as sent by the server
  final bool sendAsChatAnnouncement;
  final String status; // Active | Completed | Draft
  final String createdBy;
  final String createdAt; // server-formatted date string
  final int totalVotes;
  final List<PollOption> options;

  const AdminPoll({
    required this.id,
    required this.question,
    required this.description,
    required this.choiceType,
    required this.visibility,
    required this.sendTo,
    required this.targetLabel,
    required this.endDate,
    required this.sendAsChatAnnouncement,
    required this.status,
    required this.createdBy,
    required this.createdAt,
    required this.totalVotes,
    required this.options,
  });

  bool get isAnonymous => visibility == 'anonymous';
  bool get isMultiple => choiceType == 'multiple';

  factory AdminPoll.fromJson(Map<String, dynamic> j) => AdminPoll(
        id: _id(j),
        question: _str(j['question']),
        description: _str(j['description']),
        choiceType: _str(j['choiceType'], 'single'),
        visibility: _str(j['visibility'], 'normal'),
        sendTo: _str(j['sendTo'], 'all'),
        targetLabel: _str(j['targetLabel']),
        endDate: _str(j['endDate']),
        sendAsChatAnnouncement: j['sendAsChatAnnouncement'] == true,
        status: _str(j['status'], 'Active'),
        createdBy: _str(j['createdBy']),
        createdAt: _str(j['createdAt']),
        totalVotes: _int(j['totalVotes']),
        options: _maps(j['options']).map(PollOption.fromJson).toList(),
      );
}

// ── Service ─────────────────────────────────────────────────────────────

class AdminInteractionService {
  final ApiClient _api = ApiClient();

  static const _chat = '/admin/interaction/chat';
  static const _polls = '/admin/interaction/polls';

  static Map<String, dynamic> _data(Response<dynamic> res) {
    final body = res.data;
    if (body is Map && (body['status'] == 'success' || body['success'] == true)) {
      final d = body['data'];
      return d is Map ? Map<String, dynamic>.from(d) : <String, dynamic>{};
    }
    throw Exception(body is Map ? (body['message'] ?? 'Request failed') : 'Request failed');
  }

  static Exception _error(Object e, String fallback) {
    if (e is DioException) {
      final body = e.response?.data;
      final msg = body is Map ? body['message']?.toString() : null;
      if (msg != null && msg.isNotEmpty) return Exception(msg);
      if (e.response == null) return Exception('$fallback. Please check your connection.');
      return Exception(fallback);
    }
    if (e is Exception) return e;
    return Exception(fallback);
  }

  Future<Map<String, dynamic>> _get(String path, String fallback, {Map<String, dynamic>? query}) async {
    try {
      return _data(await _api.dio.get<dynamic>(path, queryParameters: query));
    } catch (e) {
      throw _error(e, fallback);
    }
  }

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body, String fallback) async {
    try {
      return _data(await _api.dio.post<dynamic>(path, data: body));
    } catch (e) {
      throw _error(e, fallback);
    }
  }

  // ── Chat: staff directory, groups, broadcasts ─────────────────────────

  /// GET /admin/interaction/chat/staff - staff of this company, for member/recipient pickers.
  Future<List<InteractionStaff>> chatStaff() async {
    final d = await _get('$_chat/staff', 'Could not load the staff list');
    return _maps(d['staff']).map(InteractionStaff.fromJson).toList();
  }

  /// GET /admin/interaction/chat/groups - non-archived groups, newest first.
  Future<List<ChatGroup>> groups() async {
    final d = await _get('$_chat/groups', 'Could not load groups');
    return _maps(d['groups']).map(ChatGroup.fromJson).toList();
  }

  /// POST /admin/interaction/chat/groups -> `{group, conversation}`.
  Future<ChatGroup> createGroup({
    required String name,
    String description = '',
    List<String> memberIds = const [],
    List<String> tags = const [],
  }) async {
    final d = await _post('$_chat/groups', {
      'name': name,
      'description': description,
      'memberIds': memberIds,
      if (tags.isNotEmpty) 'tags': tags,
    }, 'Could not create the group');
    return ChatGroup.fromJson(Map<String, dynamic>.from((d['group'] as Map?) ?? const {}));
  }

  /// GET /admin/interaction/chat/broadcasts - newest first.
  Future<List<ChatBroadcast>> broadcasts() async {
    final d = await _get('$_chat/broadcasts', 'Could not load broadcasts');
    return _maps(d['broadcasts']).map(ChatBroadcast.fromJson).toList();
  }

  /// POST /admin/interaction/chat/broadcasts -> `{broadcast, conversation}`.
  /// [targetType] 'all' (every staff of the company) or 'specific' ([recipientIds]).
  Future<ChatBroadcast> createBroadcast({
    required String title,
    String description = '',
    required String targetType,
    required String targetLabel,
    List<String> recipientIds = const [],
    String? initialNoticeContent,
  }) async {
    final d = await _post('$_chat/broadcasts', {
      'title': title,
      'description': description,
      'targetType': targetType,
      'targetLabel': targetLabel,
      'recipientIds': targetType == 'specific' ? recipientIds : <String>[],
      if (initialNoticeContent != null && initialNoticeContent.isNotEmpty) 'initialNoticeContent': initialNoticeContent,
    }, 'Could not create the broadcast');
    return ChatBroadcast.fromJson(Map<String, dynamic>.from((d['broadcast'] as Map?) ?? const {}));
  }

  /// GET /admin/interaction/chat/conversations - every conversation of the company (admin view).
  Future<List<Map<String, dynamic>>> conversations() async {
    final d = await _get('$_chat/conversations', 'Could not load conversations');
    return _maps(d['conversations']);
  }

  /// The conversation id linked to a group (`conversation.groupId`), or null.
  Future<String?> conversationIdForGroup(String groupId) async {
    final list = await conversations();
    for (final c in list) {
      if (_str(c['groupId']) == groupId) return _id(c);
    }
    return null;
  }

  /// GET /admin/interaction/chat/conversations/:id/messages (oldest first, up to [limit]).
  Future<List<AdminChatMessage>> conversationMessages(String conversationId, {int limit = 50}) async {
    final d = await _get('$_chat/conversations/$conversationId/messages', 'Could not load messages',
        query: {'limit': limit});
    return _maps(d['messages']).map(AdminChatMessage.fromJson).toList();
  }

  // ── Polls & surveys ───────────────────────────────────────────────────

  /// GET /admin/interaction/polls - with per-option voters (empty for anonymous polls).
  Future<List<AdminPoll>> polls() async {
    final d = await _get(_polls, 'Could not load polls');
    return _maps(d['polls']).map(AdminPoll.fromJson).toList();
  }

  /// GET /admin/interaction/polls/staff - staff for the "single staff" target.
  Future<List<InteractionStaff>> pollStaff() async {
    final d = await _get('$_polls/staff', 'Could not load the staff list');
    return _maps(d['staff']).map(InteractionStaff.fromJson).toList();
  }

  /// POST /admin/interaction/polls -> `{poll}`. [endDate] is sent as 'YYYY-MM-DD'.
  Future<AdminPoll> createPoll({
    required String question,
    String description = '',
    required String choiceType,
    required String visibility,
    required String sendTo,
    required String targetLabel,
    String? targetId,
    required DateTime endDate,
    required bool sendAsChatAnnouncement,
    required List<String> options,
  }) async {
    String two(int n) => n.toString().padLeft(2, '0');
    final d = await _post(_polls, {
      'question': question,
      'description': description,
      'choiceType': choiceType,
      'visibility': visibility,
      'sendTo': sendTo,
      'targetLabel': targetLabel,
      if (targetId != null && targetId.isNotEmpty) 'targetId': targetId,
      'endDate': '${endDate.year}-${two(endDate.month)}-${two(endDate.day)}',
      'sendAsChatAnnouncement': sendAsChatAnnouncement,
      'options': [for (final o in options) {'text': o}],
    }, 'Could not create the poll');
    return AdminPoll.fromJson(Map<String, dynamic>.from((d['poll'] as Map?) ?? const {}));
  }
}
