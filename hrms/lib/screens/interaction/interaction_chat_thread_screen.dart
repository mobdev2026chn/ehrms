// hrms/lib/screens/interaction/interaction_chat_thread_screen.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:dio/dio.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
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
import '../../utils/error_message_utils.dart';
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
    this.peerLastSeenAt,
    /// From API `canSendMessages` (e.g. broadcast read-only). When false, composer is disabled.
    this.canSendMessages,
  });

  final String chatId;
  final String? receiverId;
  final String title;
  final String? avatarUrl;
  final bool isGroup;
  final bool? peerIsOnline;
  final String? peerLastSeenAt;
  final bool? canSendMessages;

  @override
  State<InteractionChatThreadScreen> createState() => _InteractionChatThreadScreenState();
}

const Color _kChatHeaderIconGrey = Color(0xFF4A4A4A);
/// Web / WhatsApp-style outgoing bubble (light mint green).
const Color _kChatSentBubble = Color(0xFFDCF8C6);
const Color _kChatReceivedBubble = Color(0xFFFFFFFF);
OverlayEntry? _chatTopBannerEntry;
Timer? _chatTopBannerTimer;

void _hideChatTopBanner() {
  _chatTopBannerTimer?.cancel();
  _chatTopBannerTimer = null;
  _chatTopBannerEntry?.remove();
  _chatTopBannerEntry = null;
}

void showChatTopBanner(BuildContext context, String message) {
  _hideChatTopBanner();
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  final topInset = MediaQuery.of(context).padding.top + 10;
  final entry = OverlayEntry(
    builder: (ctx) => Positioned(
      left: 12,
      right: 12,
      top: topInset,
      child: Material(
        color: Colors.transparent,
        child: Container(
          constraints: const BoxConstraints(minHeight: 64),
          decoration: BoxDecoration(
            color: const Color(0xFFF1B434),
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 16,
                offset: Offset(0, 6),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Stack(
            children: [
              // Centered text across the full banner width, regardless of
              // how many lines it wraps to. Horizontal padding keeps it
              // clear of the leading icon and trailing close button.
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 34),
                child: Center(
                  child: Text(
                    message,
                    maxLines: 6,
                    overflow: TextOverflow.fade,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  width: 26,
                  height: 26,
                  decoration: const BoxDecoration(
                    color: Color(0x33FFFFFF),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.notifications_none, size: 16, color: Colors.white),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: GestureDetector(
                  onTap: _hideChatTopBanner,
                  child: const Icon(Icons.close, size: 18, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  _chatTopBannerEntry = entry;
  overlay.insert(entry);
  _chatTopBannerTimer = Timer(const Duration(seconds: 3), _hideChatTopBanner);
}

class _ChatThreadCacheEntry {
  _ChatThreadCacheEntry({
    required this.messages,
    required this.seenIds,
    required this.page,
    required this.hasMore,
    required this.cachedAt,
  });

  final List<Map<String, dynamic>> messages;
  final Set<String> seenIds;
  final int page;
  final bool hasMore;
  final DateTime cachedAt;
}

class _InteractionChatThreadScreenState extends State<InteractionChatThreadScreen> {
  static final Map<String, _ChatThreadCacheEntry> _threadCache = {};
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
  /// True while a media/document/voice upload is in flight, so the composer can
  /// show a sending spinner and block a second tap from starting a duplicate
  /// upload of the same (often large) file.
  bool _uploading = false;
  DateTime? _recordingStartedAt;
  Timer? _recordingTimer;
  Duration _recordingElapsed = Duration.zero;
  String? _pendingVoicePath;
  String? _pendingVoiceName;
  /// Inline header search (web-style); chat list hidden while active.
  bool _searchOpen = false;
  String? _myUserId;
  String? _myDisplayAvatarUrl;
  String _myDisplayName = '';
  int? _memberCount;
  String _groupType = 'custom';
  String _groupName = '';
  List<String> _allowedSenderIds = [];
  List<Map<String, dynamic>> _groupMembers = [];
  String? _myRole;
  bool _isCurrentGroupAdmin = false;
  StreamSubscription<Map<String, dynamic>>? _sub;
  final _seenIds = <String>{};
  Timer? _typingTimer;
  Timer? _markReadDebounce;
  final Set<String> _markReadInFlight = <String>{};
  /// Received message ids already marked read this session — one PATCH per id,
  /// so opening the thread reliably clears the server unread count without
  /// re-marking on every rebuild.
  final Set<String> _markedReadIds = <String>{};
  /// From `GET /interaction/polls` — option ids the current user selected per poll.
  Map<String, List<String>> _myPollOptionIds = {};
  bool _showScrollToBottom = false;
  bool? _resolvedCanSendMessages;
  String? _sendBlockedReason;
  String? _resolvedReceiverId;
  Map<String, dynamic>? _replyTo;
  String? _highlightMessageId;
  final Set<String> _failedAvatarUrls = <String>{};

  /// Web parity:
  /// - explicit false means read-only for regular users
  /// - but broadcast admins/allowed senders can still send.
  bool get _maySend {
    final base = (_resolvedCanSendMessages ?? widget.canSendMessages) != false;
    if (base) return true;
    if (!widget.isGroup || !_isBroadcast) return false;
    final me = _myUserId;
    if (me == null || me.isEmpty) return false;
    return _canSendForUserId(me);
  }

  String? get _personalPeerId {
    if (widget.isGroup) return null;
    final raw = (_resolvedReceiverId ?? widget.receiverId)?.trim();
    if (raw == null || raw.isEmpty) return null;
    return raw;
  }

  String get _threadCacheKey {
    if (widget.isGroup) return 'g:${widget.chatId}';
    return 'p:${_personalPeerId ?? widget.receiverId ?? widget.chatId}';
  }

  bool _restoreFromCache() {
    final cache = _threadCache[_threadCacheKey];
    if (cache == null) return false;
    // Keep cache reasonably fresh.
    if (DateTime.now().difference(cache.cachedAt) > const Duration(minutes: 10)) {
      _threadCache.remove(_threadCacheKey);
      return false;
    }
    _messages = List<Map<String, dynamic>>.from(cache.messages);
    _seenIds
      ..clear()
      ..addAll(cache.seenIds);
    _page = cache.page;
    _hasMore = cache.hasMore;
    _loading = false;
    _loadingMore = false;
    return _messages.isNotEmpty;
  }

  void _saveToCache() {
    if (_messages.isEmpty) return;
    _threadCache[_threadCacheKey] = _ChatThreadCacheEntry(
      messages: List<Map<String, dynamic>>.from(_messages),
      seenIds: Set<String>.from(_seenIds),
      page: _page,
      hasMore: _hasMore,
      cachedAt: DateTime.now(),
    );
  }

  void _showTopSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    showChatTopBanner(context, message);
  }

  String _friendlyErrorMessage(Object error) {
    if (error is DioException) {
      final t = error.type;
      if (t == DioExceptionType.connectionTimeout ||
          t == DioExceptionType.sendTimeout ||
          t == DioExceptionType.receiveTimeout) {
        return 'Request timed out. Please check your internet and try again.';
      }
      final msg = ErrorMessageUtils.messageFromDioException(
        error,
        fallback: 'Unable to send. Please try again.',
      );
      if (msg.toLowerCase().contains('timed out')) {
        return 'Request timed out. Please check your internet and try again.';
      }
      return msg;
    }
    return error.toString();
  }

  Widget _safeInitialAvatar({
    required String name,
    String? avatarUrl,
    required double radius,
    Color? fallbackBg,
    Color? fallbackFg,
  }) {
    final letter = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?';
    final bg = fallbackBg ?? InteractionAvatarTheme.backgroundForTitle(name.isEmpty ? 'U' : name);
    final fg = fallbackFg ?? InteractionAvatarTheme.letterColor(bg);
    final url = (avatarUrl != null && avatarUrl.startsWith('http') && !_failedAvatarUrls.contains(avatarUrl))
        ? avatarUrl
        : null;
    return CircleAvatar(
      radius: radius,
      backgroundColor: url != null ? Colors.transparent : bg,
      backgroundImage: url != null ? CachedNetworkImageProvider(url) : null,
      onBackgroundImageError: url == null
          ? null
          : (_, __) {
              if (!mounted) return;
              setState(() => _failedAvatarUrls.add(url));
            },
      child: url == null
          ? Text(
              letter,
              style: TextStyle(
                color: fg,
                fontWeight: FontWeight.bold,
                fontSize: radius * 0.8,
              ),
            )
          : null,
    );
  }

  void _applySendPermissionFromError(Object error) {
    if (error is! DioException) return;
    final code = error.response?.statusCode;
    if (code != 403) return;
    final msg = ErrorMessageUtils.messageFromDioException(error, fallback: 'You cannot send messages in this chat.');
    final lower = msg.toLowerCase();
    if (lower.contains('cannot send') ||
        lower.contains('view this broadcast') ||
        lower.contains('no longer a member') ||
        lower.contains('not a member')) {
      if (mounted) {
        setState(() {
          _resolvedCanSendMessages = false;
          _sendBlockedReason = msg;
        });
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _myUserId = await InteractionService.currentUserId();
    _resolvedReceiverId = widget.receiverId?.trim();
    _myRole = await InteractionService.currentUserRole();
    await _loadMyDisplay();
    if (widget.isGroup) {
      InteractionSocketService.instance.joinGroupChats([widget.chatId]);
    } else if (widget.receiverId != null) {
      InteractionSocketService.instance.joinDirectChat(widget.receiverId!);
    }
    await InteractionSocketService.instance.connect();
    _sub = InteractionSocketService.instance.onNewMessage.listen(_onSocketMessage);
    _scrollController.addListener(_onScroll);
    final restored = _restoreFromCache();
    if (!restored) {
      await _loadPage(1, replace: true);
    }
    unawaited(_loadGroupMeta());
    unawaited(_refreshSendCapabilityFromGroup());
    unawaited(_hydratePollVotes());
    _scheduleMarkVisibleRead();
  }

  Future<void> _refreshSendCapabilityFromGroup() async {
    if (!widget.isGroup) return;
    try {
      final res = await InteractionService.instance.getGroups();
      final data = res['data'];
      if (data is! List || !mounted) return;
      for (final g in data) {
        if (g is! Map) continue;
        final gid = g['_id']?.toString() ?? g['id']?.toString() ?? '';
        if (gid != widget.chatId) continue;
        final cs = g['canSendMessages'];
        if (cs is bool && mounted) {
          setState(() => _resolvedCanSendMessages = cs);
        }
        break;
      }
    } catch (_) {}
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
    bool? canSendFromGroupRow;
    try {
      final groupsRes = await InteractionService.instance.getGroups();
      final gdata = groupsRes['data'];
      if (gdata is List) {
        for (final e in gdata) {
          if (e is! Map) continue;
          final gid = e['_id']?.toString() ?? e['id']?.toString() ?? '';
          if (gid != widget.chatId) continue;
          _groupType = e['groupType']?.toString() ?? 'custom';
          _groupName = e['groupName']?.toString() ?? e['name']?.toString() ?? widget.title;
          final as = e['allowedSenderIds'];
          if (as is List) {
            _allowedSenderIds = as.map((x) => x.toString()).toList();
          }
          final cs = e['canSendMessages'];
          if (cs is bool) canSendFromGroupRow = cs;
          break;
        }
      }
      final res = await InteractionService.instance.getGroupMembers(widget.chatId);
      final data = res['data'];
      if (data is List && mounted) {
        final members = <Map<String, dynamic>>[];
        for (final e in data) {
          if (e is Map) {
            final m = <String, dynamic>{};
            e.forEach((k, v) => m[k.toString()] = v);
            members.add(m);
          }
        }
        final myIdLookup = _myUserId ?? '';
        final meRow = members.where((m) {
          final user = m['user'];
          final uid = user is Map ? (user['_id']?.toString() ?? user['id']?.toString() ?? '') : '';
          return uid == myIdLookup;
        }).cast<Map<String, dynamic>>().firstOrNull;
        final isAdmin = meRow != null && meRow['role']?.toString() == 'admin';
        final myId = _myUserId;
        bool? resolved = canSendFromGroupRow;
        if (resolved == null && _groupType == 'broadcast' && myId != null && myId.isNotEmpty) {
          // Web parity: if explicit server flag is absent, infer from broadcast sender rules.
          resolved = _canSendForUserId(myId);
        }
        setState(() {
          _groupMembers = members;
          _memberCount = members.length;
          _isCurrentGroupAdmin = isAdmin;
          if (resolved != null) _resolvedCanSendMessages = resolved;
        });
      }
    } catch (_) {}
  }

  bool get _canManageGroupSettings {
    if (!widget.isGroup) return false;
    final byRole = InteractionService.interactionGroupManagerRoles.contains((_myRole ?? '').trim());
    return byRole || _isCurrentGroupAdmin;
  }

  bool get _isBroadcast => _groupType == 'broadcast';

  bool _canSendForUserId(String userId) {
    final role = (_myRole ?? '').trim();
    if (role == 'Super Admin' || role == 'Admin' || role == 'HR' || role == 'Senior HR') return true;
    if (_isCurrentGroupAdmin) return true;
    return _allowedSenderIds.contains(userId);
  }

  Future<void> _openGroupSettingsSheet() async {
    if (!_canManageGroupSettings) return;
    final canAssignAdmin = _isCurrentGroupAdmin ||
        InteractionService.interactionGroupManagerRoles.contains((_myRole ?? '').trim());
    final tabs = <Tab>[
      const Tab(text: 'Profile'),
      const Tab(text: 'Members'),
      const Tab(text: 'Add people'),
      if (_isBroadcast) const Tab(text: 'Broadcast'),
    ];
    var ids = <String>{..._allowedSenderIds};
    var members = List<Map<String, dynamic>>.from(_groupMembers);
    var draftGroupName = _groupName.isNotEmpty ? _groupName : widget.title;
    var addSearch = '';
    var membersSearch = '';
    var broadcastSearch = '';
    var addLoading = false;
    var addResults = <Map<String, dynamic>>[];
    var selectedAddIds = <String>{};
    var savingName = false;
    var savingBroadcast = false;
    var mutatingMemberId = '';

    Future<void> runAddSearch(StateSetter setSheetState) async {
      final q = addSearch.trim();
      setSheetState(() => addLoading = true);
      try {
        final res = await InteractionService.instance.getChatSuggestions(query: q.isEmpty ? null : q);
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
        setSheetState(() => addResults = list);
      } catch (_) {
        setSheetState(() => addResults = []);
      } finally {
        setSheetState(() => addLoading = false);
      }
    }

    Future<void> refreshGroupState(StateSetter setSheetState) async {
      await _loadGroupMeta();
      if (!mounted) return;
      setSheetState(() {
        members = List<Map<String, dynamic>>.from(_groupMembers);
        ids = <String>{..._allowedSenderIds};
      });
    }

    try {
      final res = await InteractionService.instance.getChatSuggestions();
      final data = res['data'];
      if (data is List) {
        final list = <Map<String, dynamic>>[];
        for (final e in data) {
          if (e is Map) {
            final m = <String, dynamic>{};
            e.forEach((k, v) => m[k.toString()] = v);
            list.add(m);
          }
        }
        addResults = list;
      }
    } catch (_) {}
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Group settings',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (ctx, _, __) {
        final width = math.min(MediaQuery.sizeOf(ctx).width * 0.88, 460.0);
        return Align(
          alignment: Alignment.centerRight,
          child: Material(
            color: Colors.white,
            child: SizedBox(
              width: width,
              child: SafeArea(
                minimum: const EdgeInsets.only(bottom: 8),
                child: DefaultTabController(
                  length: tabs.length,
                  child: StatefulBuilder(
                    builder: (ctx, setSheetState) {
                      return Padding(
                        padding: EdgeInsets.only(
                          left: 14,
                          right: 14,
                          top: 10,
                          bottom: 10 +
                              MediaQuery.viewInsetsOf(ctx).bottom +
                              MediaQuery.viewPaddingOf(ctx).bottom,
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                const Expanded(
                                  child: Text(
                                    'Group settings',
                                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
                                  ),
                                ),
                                IconButton(
                                  onPressed: () => Navigator.of(ctx).pop(),
                                  icon: const Icon(Icons.close),
                                ),
                              ],
                            ),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'Profile, members, and permissions — same actions as before, organized in tabs.',
                                style: TextStyle(
                                  color: Colors.blueGrey.shade500,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            TabBar(isScrollable: true, tabs: tabs),
                            const SizedBox(height: 8),
                            Expanded(
                              child: TabBarView(
                                children: [
                                  ListView(
                                    children: [
                                      ListTile(
                                        contentPadding: EdgeInsets.zero,
                                        leading: _safeInitialAvatar(
                                          name: draftGroupName.isNotEmpty ? draftGroupName : 'Group',
                                          avatarUrl: widget.avatarUrl,
                                          radius: 30,
                                          fallbackBg: Colors.blueGrey.shade200,
                                          fallbackFg: Colors.white,
                                        ),
                                        title: const Text('Update group photo (optional).'),
                                        trailing: TextButton(
                                          onPressed: () async {
                                            try {
                                              final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
                                              if (picked == null) return;
                                              await InteractionService.instance.uploadGroupAvatar(
                                                groupId: widget.chatId,
                                                filePath: picked.path,
                                                filename: picked.name,
                                              );
                                              if (!mounted) return;
                                              await refreshGroupState(setSheetState);
                                              if (!mounted) return;
                                              _showTopSnackBar('Group photo updated');
                                            } catch (e) {
                                              if (!mounted) return;
                                              _showTopSnackBar(
                                                ErrorMessageUtils.toUserFriendlyMessage(e),
                                                isError: true,
                                              );
                                            }
                                          },
                                          child: const Text('Edit'),
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      TextFormField(
                                        initialValue: draftGroupName,
                                        onChanged: (v) => draftGroupName = v,
                                        decoration: const InputDecoration(labelText: 'Group name'),
                                      ),
                                      const SizedBox(height: 12),
                                      SizedBox(
                                        width: double.infinity,
                                        child: FilledButton(
                                          style: FilledButton.styleFrom(
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                          ),
                                        onPressed: savingName
                                            ? null
                                            : () async {
                                                final next = draftGroupName.trim();
                                                if (next.isEmpty) return;
                                                setSheetState(() => savingName = true);
                                                try {
                                                  await InteractionService.instance.updateGroup(
                                                    widget.chatId,
                                                    groupName: next,
                                                  );
                                                  if (!mounted) return;
                                                  setState(() => _groupName = next);
                                                  _showTopSnackBar('Group name updated');
                                                } catch (e) {
                                                  if (!mounted) return;
                                                  _showTopSnackBar(
                                                    ErrorMessageUtils.toUserFriendlyMessage(e),
                                                    isError: true,
                                                  );
                                                } finally {
                                                  setSheetState(() => savingName = false);
                                                }
                                              },
                                          child: const Text('Save name'),
                                        ),
                                      ),
                                    ],
                                  ),
                                  ListView.builder(
                                    itemCount: members.where((row) {
                                      final user = row['user'];
                                      if (user is! Map) return false;
                                      final q = membersSearch.trim().toLowerCase();
                                      if (q.isEmpty) return true;
                                      final name = (user['name']?.toString() ?? '').toLowerCase();
                                      final email = (user['email']?.toString() ?? '').toLowerCase();
                                      final code =
                                          ((user['employeeCode']?.toString() ?? user['empCode']?.toString() ?? ''))
                                              .toLowerCase();
                                      return name.contains(q) || email.contains(q) || code.contains(q);
                                    }).length + 1,
                                    itemBuilder: (_, i) {
                                      if (i == 0) {
                                        return Padding(
                                          padding: const EdgeInsets.only(bottom: 8),
                                          child: TextField(
                                            decoration: const InputDecoration(
                                              hintText: 'Search members...',
                                            ),
                                            onChanged: (v) => setSheetState(() => membersSearch = v),
                                          ),
                                        );
                                      }
                                      final filtered = members.where((row) {
                                        final user = row['user'];
                                        if (user is! Map) return false;
                                        final q = membersSearch.trim().toLowerCase();
                                        if (q.isEmpty) return true;
                                        final name = (user['name']?.toString() ?? '').toLowerCase();
                                        final email = (user['email']?.toString() ?? '').toLowerCase();
                                        final code =
                                            ((user['employeeCode']?.toString() ?? user['empCode']?.toString() ?? ''))
                                                .toLowerCase();
                                        return name.contains(q) || email.contains(q) || code.contains(q);
                                      }).toList();
                                      final row = filtered[i - 1];
                                      final user = row['user'];
                                      if (user is! Map) return const SizedBox.shrink();
                                      final uid = user['_id']?.toString() ?? user['id']?.toString() ?? '';
                                      final name = user['name']?.toString() ?? 'User';
                                      final email = user['email']?.toString() ?? '';
                                      final code = user['employeeCode']?.toString() ?? user['empCode']?.toString() ?? '';
                                      final role = row['role']?.toString() ?? 'member';
                                      if (uid.isEmpty) return const SizedBox.shrink();
                                      final isSelf = uid == _myUserId;
                                      return Container(
                                        margin: const EdgeInsets.only(bottom: 10),
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(color: const Color(0xFFE2E8F0)),
                                        ),
                                        child: Row(
                                          children: [
                                            CircleAvatar(
                                              radius: 18,
                                              backgroundColor: Colors.blueGrey.shade400,
                                              child: Text(
                                                name.isEmpty ? 'U' : name[0].toUpperCase(),
                                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    '${code.isNotEmpty ? '$code  ' : ''}${email.isNotEmpty ? email : '-'}',
                                                    style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 12),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    role == 'admin' ? 'Admin' : 'Member',
                                                    style: TextStyle(color: Colors.blueGrey.shade500, fontSize: 11),
                                                  ),
                                                  if (role == 'admin') ...[
                                                    const SizedBox(height: 4),
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: const Color(0xFFFFF4D9),
                                                        borderRadius: BorderRadius.circular(999),
                                                      ),
                                                      child: Text(
                                                        'group admin',
                                                        style: TextStyle(
                                                          color: Colors.orange.shade700,
                                                          fontSize: 11,
                                                          fontWeight: FontWeight.w600,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ),
                                            if (_canManageGroupSettings && !isSelf)
                                              Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  if (canAssignAdmin && role != 'admin')
                                                    TextButton(
                                                      onPressed: mutatingMemberId == uid
                                                          ? null
                                                          : () async {
                                                              setSheetState(() => mutatingMemberId = uid);
                                                              try {
                                                                await InteractionService.instance.updateGroupMemberRole(
                                                                  widget.chatId,
                                                                  userId: uid,
                                                                  role: 'admin',
                                                                );
                                                                await refreshGroupState(setSheetState);
                                                              } catch (e) {
                                                                if (!mounted) return;
                                                                _showTopSnackBar(
                                                                  ErrorMessageUtils.toUserFriendlyMessage(e),
                                                                  isError: true,
                                                                );
                                                              } finally {
                                                                setSheetState(() => mutatingMemberId = '');
                                                              }
                                                            },
                                                      style: TextButton.styleFrom(
                                                        foregroundColor: const Color(0xFFE4A115),
                                                        textStyle: const TextStyle(fontWeight: FontWeight.w600),
                                                      ),
                                                      child: const Text('Make admin'),
                                                    ),
                                                  if (canAssignAdmin && role == 'admin')
                                                    TextButton(
                                                      onPressed: mutatingMemberId == uid
                                                          ? null
                                                          : () async {
                                                              setSheetState(() => mutatingMemberId = uid);
                                                              try {
                                                                await InteractionService.instance.updateGroupMemberRole(
                                                                  widget.chatId,
                                                                  userId: uid,
                                                                  role: 'member',
                                                                );
                                                                await refreshGroupState(setSheetState);
                                                              } catch (e) {
                                                                if (!mounted) return;
                                                                _showTopSnackBar(
                                                                  ErrorMessageUtils.toUserFriendlyMessage(e),
                                                                  isError: true,
                                                                );
                                                              } finally {
                                                                setSheetState(() => mutatingMemberId = '');
                                                              }
                                                            },
                                                      style: TextButton.styleFrom(
                                                        foregroundColor: const Color(0xFFE4A115),
                                                        textStyle: const TextStyle(fontWeight: FontWeight.w600),
                                                      ),
                                                      child: const Text('Make member'),
                                                    ),
                                                  TextButton(
                                                    onPressed: mutatingMemberId == uid
                                                        ? null
                                                        : () async {
                                                            setSheetState(() => mutatingMemberId = uid);
                                                            try {
                                                              await InteractionService.instance.removeGroupMember(
                                                                widget.chatId,
                                                                userId: uid,
                                                              );
                                                              await refreshGroupState(setSheetState);
                                                            } catch (e) {
                                                              if (!mounted) return;
                                                              _showTopSnackBar(
                                                                ErrorMessageUtils.toUserFriendlyMessage(e),
                                                                isError: true,
                                                              );
                                                            } finally {
                                                              setSheetState(() => mutatingMemberId = '');
                                                            }
                                                          },
                                                    style: TextButton.styleFrom(
                                                      foregroundColor: const Color(0xFFFF4D4F),
                                                      textStyle: const TextStyle(fontWeight: FontWeight.w500),
                                                    ),
                                                    child: const Text('Remove'),
                                                  ),
                                                ],
                                              ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                  Column(
                                    children: [
                                      Text(
                                        'People already in this group are hidden here. Search by name, email, or employee code.',
                                        style: TextStyle(color: Colors.blueGrey.shade500),
                                      ),
                                      const SizedBox(height: 8),
                                      TextField(
                                        decoration: const InputDecoration(
                                          hintText: 'Search to add...',
                                        ),
                                        onChanged: (v) {
                                          addSearch = v;
                                          runAddSearch(setSheetState);
                                        },
                                      ),
                                      const SizedBox(height: 8),
                                      if (addLoading) const LinearProgressIndicator(minHeight: 2),
                                      const SizedBox(height: 8),
                                      Expanded(
                                        child: ListView.builder(
                                          itemCount: addResults.length,
                                          itemBuilder: (_, i) {
                                            final u = addResults[i];
                                            final uid = u['_id']?.toString() ?? u['id']?.toString() ?? '';
                                            final name = u['name']?.toString() ?? 'User';
                                            final email = u['email']?.toString() ?? '';
                                            final code = u['employeeCode']?.toString() ?? u['empCode']?.toString() ?? '';
                                            if (uid.isEmpty) return const SizedBox.shrink();
                                            final already = members.any((m) {
                                              final user = m['user'];
                                              if (user is! Map) return false;
                                              final id = user['_id']?.toString() ?? user['id']?.toString() ?? '';
                                              return id == uid;
                                            });
                                            if (already) return const SizedBox.shrink();
                                            final checked = selectedAddIds.contains(uid);
                                            return Container(
                                              margin: const EdgeInsets.only(bottom: 10),
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                              decoration: BoxDecoration(
                                                color: Colors.white,
                                                borderRadius: BorderRadius.circular(10),
                                                border: Border.all(color: const Color(0xFFE2E8F0)),
                                              ),
                                              child: Row(
                                                children: [
                                                  Checkbox(
                                                    value: checked,
                                                    onChanged: (v) {
                                                      setSheetState(() {
                                                        if (v == true) {
                                                          selectedAddIds.add(uid);
                                                        } else {
                                                          selectedAddIds.remove(uid);
                                                        }
                                                      });
                                                    },
                                                  ),
                                                  CircleAvatar(
                                                    radius: 16,
                                                    backgroundColor: Colors.blueGrey.shade400,
                                                    child: Text(
                                                      name.isEmpty ? 'U' : name[0].toUpperCase(),
                                                      style: const TextStyle(
                                                        color: Colors.white,
                                                        fontWeight: FontWeight.w700,
                                                        fontSize: 12,
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 10),
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      children: [
                                                        Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
                                                        const SizedBox(height: 2),
                                                        Text(
                                                          '${code.isNotEmpty ? '$code  ' : ''}${email.isNotEmpty ? email : '-'}',
                                                          style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 12),
                                                          maxLines: 1,
                                                          overflow: TextOverflow.ellipsis,
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                      SizedBox(
                                        width: double.infinity,
                                        child: FilledButton(
                                          style: FilledButton.styleFrom(
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                          ),
                                        onPressed: selectedAddIds.isEmpty
                                            ? null
                                            : () async {
                                                try {
                                                  await InteractionService.instance.addGroupMembers(
                                                    widget.chatId,
                                                    userIds: selectedAddIds.toList(),
                                                  );
                                                  selectedAddIds = <String>{};
                                                  await refreshGroupState(setSheetState);
                                                  if (!mounted) return;
                                                  _showTopSnackBar('Members added');
                                                } catch (e) {
                                                  if (!mounted) return;
                                                  _showTopSnackBar(
                                                    ErrorMessageUtils.toUserFriendlyMessage(e),
                                                    isError: true,
                                                  );
                                                }
                                              },
                                          child: const Text('Add members'),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (_isBroadcast)
                                    Column(
                                      children: [
                                        TextField(
                                          decoration: const InputDecoration(
                                            hintText: 'Search people...',
                                          ),
                                          onChanged: (v) => setSheetState(() => broadcastSearch = v),
                                        ),
                                        const SizedBox(height: 8),
                                        Expanded(
                                          child: ListView.builder(
                                            itemCount: members.where((row) {
                                              final user = row['user'];
                                              if (user is! Map) return false;
                                              final q = broadcastSearch.trim().toLowerCase();
                                              if (q.isEmpty) return true;
                                              final name = (user['name']?.toString() ?? '').toLowerCase();
                                              final email = (user['email']?.toString() ?? '').toLowerCase();
                                              final code = ((user['employeeCode']?.toString() ??
                                                          user['empCode']?.toString() ??
                                                          ''))
                                                      .toLowerCase();
                                              return name.contains(q) || email.contains(q) || code.contains(q);
                                            }).length,
                                            itemBuilder: (_, i) {
                                              final filtered = members.where((row) {
                                                final user = row['user'];
                                                if (user is! Map) return false;
                                                final q = broadcastSearch.trim().toLowerCase();
                                                if (q.isEmpty) return true;
                                                final name = (user['name']?.toString() ?? '').toLowerCase();
                                                final email = (user['email']?.toString() ?? '').toLowerCase();
                                                final code = ((user['employeeCode']?.toString() ??
                                                            user['empCode']?.toString() ??
                                                            ''))
                                                        .toLowerCase();
                                                return name.contains(q) || email.contains(q) || code.contains(q);
                                              }).toList();
                                              final row = filtered[i];
                                              final user = row['user'];
                                              if (user is! Map) return const SizedBox.shrink();
                                              final uid = user['_id']?.toString() ?? user['id']?.toString() ?? '';
                                              final name = user['name']?.toString() ?? 'User';
                                              if (uid.isEmpty) return const SizedBox.shrink();
                                              final on = ids.contains(uid);
                                              return SwitchListTile(
                                                title: Text(name),
                                                value: on,
                                                contentPadding: EdgeInsets.zero,
                                                onChanged: (v) {
                                                  setSheetState(() {
                                                    if (v) {
                                                      ids.add(uid);
                                                    } else {
                                                      ids.remove(uid);
                                                    }
                                                  });
                                                },
                                              );
                                            },
                                          ),
                                        ),
                                        SizedBox(
                                          width: double.infinity,
                                          child: FilledButton(
                                            style: FilledButton.styleFrom(
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                            ),
                                          onPressed: savingBroadcast
                                              ? null
                                              : () async {
                                                  setSheetState(() => savingBroadcast = true);
                                                  try {
                                                    await InteractionService.instance.updateGroup(
                                                      widget.chatId,
                                                      allowedSenderIds: ids.toList(),
                                                    );
                                                    if (!mounted) return;
                                                    setState(() {
                                                      _allowedSenderIds = ids.toList();
                                                      if (_myUserId != null) {
                                                        _resolvedCanSendMessages = _canSendForUserId(_myUserId!);
                                                      }
                                                    });
                                                    _showTopSnackBar('Broadcast permissions updated');
                                                  } catch (e) {
                                                    if (!mounted) return;
                                                    _showTopSnackBar(
                                                      ErrorMessageUtils.toUserFriendlyMessage(e),
                                                      isError: true,
                                                    );
                                                  } finally {
                                                    setSheetState(() => savingBroadcast = false);
                                                  }
                                                },
                                            child: const Text('Save permissions'),
                                          ),
                                        ),
                                      ],
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (ctx, animation, _, child) {
        return SlideTransition(
          position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
          ),
          child: child,
        );
      },
    );
  }

  bool _matchesThread(Map<String, dynamic> msg) {
    if (widget.isGroup) {
      return msg['groupId']?.toString() == widget.chatId;
    }
    final peer = _personalPeerId;
    if (peer == null) return false;
    final s = msg['senderId']?.toString();
    final r = msg['receiverId']?.toString();
    final me = _myUserId;
    if (me == null) return false;
    return (s == peer && r == me) || (s == me && r == peer);
  }

  /// One logical message per `_id`. Socket and REST response can both arrive (any order);
  /// we dedupe so the chat never shows duplicates until the next full reload.
  void _upsertMessageFromSendOrSocket(Map<String, dynamic> msg) {
    final id = msg['_id']?.toString();
    if (!mounted) return;
    if (id != null && id.isNotEmpty) {
      _seenIds.add(id);
      setState(() {
        final idx = _messages.indexWhere((m) => m['_id']?.toString() == id);
        if (idx >= 0) {
          _messages[idx] = msg;
        } else {
          _messages.insert(0, msg);
        }
      });
    } else {
      setState(() => _messages.insert(0, msg));
    }
    _saveToCache();
    _scheduleMarkVisibleRead();
  }

  void _scrollChatToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _onSocketMessage(Map<String, dynamic> msg) {
    if (!_matchesThread(msg)) return;
    if (!mounted) return;
    _upsertMessageFromSendOrSocket(msg);
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
        receiverId: widget.isGroup ? null : _personalPeerId,
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
      _resolveReceiverFromMessages(list);
      if (!mounted) return;
      setState(() {
        _sendBlockedReason = null;
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
      _saveToCache();
    } catch (e) {
      _applySendPermissionFromError(e);
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  void _resolveReceiverFromMessages(List<Map<String, dynamic>> list) {
    if (widget.isGroup) return;
    if (_personalPeerId != null) return;
    final me = _myUserId;
    if (me == null || me.isEmpty) return;
    for (final msg in list) {
      final s = msg['senderId']?.toString();
      final r = msg['receiverId']?.toString();
      if (s == me && r != null && r.isNotEmpty) {
        _resolvedReceiverId = r;
        return;
      }
      if (r == me && s != null && s.isNotEmpty) {
        _resolvedReceiverId = s;
        return;
      }
    }
  }

  Future<void> _markVisibleRead() async {
    final me = _myUserId;
    if (me == null) return;
    final ids = <String>[];
    for (final m in _messages.take(30)) {
      // Don't gate on `readStatus`: for group/broadcast messages that flag does
      // not reliably mean "the current user read it", so trusting it leaves the
      // conversation's unread count stuck. Instead mark every received message
      // once (deduped via _markedReadIds), which clears the count server-side.
      if (m['senderId']?.toString() == me) continue;
      final id = m['_id']?.toString();
      if (id == null || id.isEmpty) continue;
      if (_markedReadIds.contains(id)) continue;
      if (_markReadInFlight.contains(id)) continue;
      ids.add(id);
      _markReadInFlight.add(id);
    }
    if (ids.isEmpty) return;
    await Future.wait(
      ids.map((id) async {
        try {
          await InteractionService.instance.markMessageRead(id);
          _markedReadIds.add(id);
        } catch (_) {
          // Ignore read receipt failures for smooth chat UX.
        } finally {
          _markReadInFlight.remove(id);
        }
      }),
    );
  }

  void _scheduleMarkVisibleRead() {
    _markReadDebounce?.cancel();
    _markReadDebounce = Timer(const Duration(milliseconds: 250), () {
      unawaited(_markVisibleRead());
    });
  }

  Future<void> _sendText() async {
    if (!_maySend) return;
    if (!widget.isGroup && _personalPeerId == null) {
      _showTopSnackBar(
        'Unable to identify recipient for this personal chat. Please reopen this chat and try again.',
        isError: true,
      );
      return;
    }
    final text = _text.text.trim();
    if (text.isEmpty) return;
    final replyPrefix = _replyPrefixFor(_replyTo);
    final outbound = replyPrefix == null ? text : '$replyPrefix\n$text';
    _text.clear();
    if (mounted) setState(() {});
    try {
      final res = await InteractionService.instance.sendTextMessage(
        chatId: widget.isGroup ? widget.chatId : 'personal',
        messageContent: outbound,
        receiverId: widget.isGroup ? null : _personalPeerId,
      );
      final data = res['data'];
      if (data is Map) {
        final m = <String, dynamic>{};
        data.forEach((k, v) => m[k.toString()] = v);
        if (!mounted) return;
        _upsertMessageFromSendOrSocket(m);
        if (mounted) setState(() => _replyTo = null);
        _scrollChatToLatest();
      }
    } catch (e) {
      _applySendPermissionFromError(e);
      if (mounted) {
        _showTopSnackBar(_friendlyErrorMessage(e), isError: true);
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

  Future<void> _pickAudioFile() async {
    // Allow ANY audio file, not a hardcoded extension whitelist: a user's clip
    // may be .ogg/.opus/.flac/.amr/.wma/.3gp, etc. The interaction server's
    // upload allowlist is the real gate on what ultimately sends; the picker
    // shouldn't pre-filter and hide files the server would actually accept. If
    // the platform can't enumerate audio, fall back to picking any file.
    FilePickerResult? r;
    try {
      r = await FilePicker.platform.pickFiles(type: FileType.audio);
    } catch (_) {
      r = await FilePicker.platform.pickFiles();
    }
    if (r == null || r.files.isEmpty) return;
    final f = r.files.first;
    final path = f.path;
    if (path == null) return;
    await _upload(path, f.name, 'voice');
  }

  Future<void> _upload(String path, String filename, String type) async {
    if (_uploading) return;
    if (!widget.isGroup && _personalPeerId == null) {
      _showTopSnackBar(
        'Unable to identify recipient for this personal chat. Please reopen this chat and try again.',
        isError: true,
      );
      return;
    }
    if (mounted) setState(() => _uploading = true);
    try {
      final res = await InteractionService.instance.uploadChatMedia(
        chatId: widget.isGroup ? widget.chatId : 'personal',
        filePath: path,
        filename: filename,
        type: type,
        receiverId: widget.isGroup ? null : _personalPeerId,
      );
      final data = res['data'];
      if (data is Map) {
        final m = <String, dynamic>{};
        data.forEach((k, v) => m[k.toString()] = v);
        if (!mounted) return;
        _upsertMessageFromSendOrSocket(m);
        final id = m['_id']?.toString() ?? '';
        final mediaMissing = (type == 'image' || type == 'file' || type == 'voice' || type == 'video') &&
            _messageMediaUrl(m) == null &&
            id.isNotEmpty;
        if (mediaMissing) {
          unawaited(_refreshMessageById(id));
        }
        _scrollChatToLatest();
      }
    } catch (e) {
      _applySendPermissionFromError(e);
      if (mounted) {
        if (e is InteractionUploadException) {
          _showTopSnackBar(e.message, isError: true);
          _showUploadErrorDetails(e);
        } else {
          _showTopSnackBar(_friendlyErrorMessage(e), isError: true);
        }
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  /// Surface the per-shape upload diagnostics so a failing media send (notably
  /// voice) can be reported with the exact server reason, no log access needed.
  void _showUploadErrorDetails(InteractionUploadException e) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(e.message),
        content: SingleChildScrollView(
          child: SelectableText(
            e.diagnostics,
            style: const TextStyle(fontSize: 12, height: 1.4),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: e.diagnostics));
              Navigator.of(ctx).pop();
            },
            child: const Text('Copy'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _refreshMessageById(String id) async {
    try {
      final res = await InteractionService.instance.getChatMessages(
        chatId: widget.isGroup ? widget.chatId : 'personal',
        page: 1,
        receiverId: widget.isGroup ? null : _personalPeerId,
      );
      final data = res['data'];
      if (data is! List || !mounted) return;
      for (final e in data) {
        if (e is! Map) continue;
        final mid = e['_id']?.toString() ?? '';
        if (mid != id) continue;
        final m = <String, dynamic>{};
        e.forEach((k, v) => m[k.toString()] = v);
        _upsertMessageFromSendOrSocket(m);
        break;
      }
    } catch (_) {}
  }

  void _emitTyping() {
    if (widget.isGroup) {
      InteractionSocketService.instance.emitTyping(groupId: widget.chatId);
    } else if (_personalPeerId != null) {
      InteractionSocketService.instance.emitTyping(receiverId: _personalPeerId);
    }
    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 2), () {
      if (widget.isGroup) {
        InteractionSocketService.instance.emitStopTyping(groupId: widget.chatId);
      } else if (_personalPeerId != null) {
        InteractionSocketService.instance.emitStopTyping(receiverId: _personalPeerId);
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
      _recordingTimer?.cancel();
      _recordingTimer = null;
      _recordingStartedAt = null;
      if (path != null && path.isNotEmpty) {
        final name = path.contains(Platform.pathSeparator)
            ? path.split(Platform.pathSeparator).last
            : path.split('/').last;
        if (mounted) {
          setState(() {
            _pendingVoicePath = path;
            _pendingVoiceName = name;
          });
        }
      }
      return;
    }
    final mic = await Permission.microphone.request();
    if (!mic.isGranted) {
      if (mounted) {
        _showTopSnackBar(
          'Microphone permission is required for voice messages.',
          isError: true,
        );
      }
      return;
    }
    if (!mounted) return;
    if (!await _audioRecorder.hasPermission()) return;
    final dir = await getTemporaryDirectory();
    // Record AAC/m4a, not Opus/.ogg: the interaction server's upload filter
    // rejects OGG ("OGG, MP4, and WEBM file formats are not supported"), so an
    // Opus recording could never be sent. m4a is on the server allowlist.
    final filePath = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _audioRecorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc),
      path: filePath,
    );
    if (mounted) {
      setState(() {
        _recording = true;
        _pendingVoicePath = null;
        _pendingVoiceName = null;
        _recordingStartedAt = DateTime.now();
        _recordingElapsed = Duration.zero;
      });
    }
    _recordingTimer?.cancel();
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || !_recording) return;
      final started = _recordingStartedAt;
      if (started == null) return;
      setState(() => _recordingElapsed = DateTime.now().difference(started));
    });
  }

  String _senderLabel(Map<String, dynamic> msg) {
    if (msg['sender'] is Map) {
      return (msg['sender'] as Map)['name']?.toString() ?? '';
    }
    return '';
  }

  String _replyLabelFor(Map<String, dynamic> msg) {
    final me = _myUserId;
    final isMine = me != null && msg['senderId']?.toString() == me;
    if (isMine) return 'You';
    final s = _senderLabel(msg).trim();
    if (s.isNotEmpty) return s;
    return widget.title;
  }

  String _replySnippetFor(Map<String, dynamic> msg) {
    final t = msg['messageType']?.toString() ?? 'text';
    if (t == 'image') return 'Photo';
    if (t == 'video') return 'Video';
    if (t == 'file') return msg['fileName']?.toString() ?? 'Document';
    if (t == 'voice') return 'Voice message';
    if (t == 'poll') return 'Poll';
    final c = msg['messageContent']?.toString().trim() ?? '';
    if (c.isEmpty) return 'Message';
    return c.replaceAll('\n', ' ');
  }

  String? _replyPrefixFor(Map<String, dynamic>? msg) {
    if (msg == null) return null;
    final id = msg['_id']?.toString() ?? '';
    if (id.isEmpty) return null;
    final sender = _replyLabelFor(msg).replaceAll('|', '/').replaceAll(']', ')');
    final snippet = _replySnippetFor(msg).replaceAll('|', '/').replaceAll(']', ')');
    return '[reply_to:$id|$sender|$snippet]';
  }

  ({String? replyId, String? sender, String? snippet, String body}) _splitReplyPrefix(String raw) {
    final rx = RegExp(r'^\[reply_to:[^|]*\|([^|]*)\|([^\]]*)\]\n?');
    final m = rx.firstMatch(raw);
    if (m == null) return (replyId: null, sender: null, snippet: null, body: raw);
    final full = m.group(0) ?? '';
    final rid = full.replaceFirst(RegExp(r'^\[reply_to:'), '').split('|').first.trim();
    final sender = m.group(1)?.trim();
    final snippet = m.group(2)?.trim();
    final body = raw.substring(m.end).trimLeft();
    return (replyId: rid, sender: sender, snippet: snippet, body: body);
  }

  void _jumpToRepliedMessage(String? replyId) {
    if (replyId == null || replyId.isEmpty || !_scrollController.hasClients) return;
    final idx = _messages.indexWhere((m) => m['_id']?.toString() == replyId);
    if (idx < 0) return;
    final target = (idx * 120).toDouble();
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
    setState(() => _highlightMessageId = replyId);
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (mounted && _highlightMessageId == replyId) {
        setState(() => _highlightMessageId = null);
      }
    });
  }

  String? _peerAvatarUrl(Map<String, dynamic> msg) {
    final s = msg['sender'];
    if (s is! Map) return null;
    final a = s['avatar']?.toString();
    if (a == null || a.isEmpty) return null;
    final u =
        a.startsWith('http://') || a.startsWith('https://') ? a : AppConstants.getInteractionFileUrl(a);
    return u.startsWith('http') ? u : null;
  }

  String? _messageMediaUrl(Map<String, dynamic> msg) {
    final raw =
        msg['fileUrl']?.toString() ??
        msg['voiceUrl']?.toString() ??
        msg['url']?.toString() ??
        msg['file']?.toString();
    if (raw == null || raw.isEmpty) return null;
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
    if (raw.startsWith('/') || raw.contains('/uploads/') || raw.startsWith('uploads/')) {
      // Chat uploads live on the interaction host, not the geo [baseUrl] host.
      final u = AppConstants.getInteractionFileUrl(raw);
      return u.startsWith('http') ? u : null;
    }
    return null;
  }

  DateTime? _msgLocalTime(Map<String, dynamic> msg) {
    return DateTime.tryParse(msg['sentTime']?.toString() ?? '')?.toLocal();
  }

  static final RegExp _urlRegex = RegExp(r'(https?:\/\/[^\s]+)', caseSensitive: false);

  Widget _linkifiedText(
    String raw, {
    required TextStyle style,
    Color linkColor = const Color(0xFF1565C0),
  }) {
    if (raw.isEmpty || !_urlRegex.hasMatch(raw)) {
      return Text(raw, style: style);
    }
    final spans = <InlineSpan>[];
    var start = 0;
    final matches = _urlRegex.allMatches(raw).toList();
    for (final m in matches) {
      final s = m.start;
      final e = m.end;
      if (s > start) {
        spans.add(TextSpan(text: raw.substring(start, s), style: style));
      }
      final url = raw.substring(s, e);
      spans.add(
        TextSpan(
          text: url,
          style: style.copyWith(
            color: linkColor,
            decoration: TextDecoration.underline,
          ),
          recognizer: TapGestureRecognizer()
            ..onTap = () {
              final uri = Uri.tryParse(url);
              if (uri != null) unawaited(launchUrl(uri));
            },
        ),
      );
      start = e;
    }
    if (start < raw.length) {
      spans.add(TextSpan(text: raw.substring(start), style: style));
    }
    return RichText(text: TextSpan(children: spans));
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
    final bg = isMine
        ? InteractionAvatarTheme.backgroundForTitle(_myDisplayName.isNotEmpty ? _myDisplayName : 'U')
        : InteractionAvatarTheme.backgroundForTitle(peerName.isNotEmpty ? peerName : 'U');
    final fg = InteractionAvatarTheme.letterColor(bg);
    final url = isMine ? _myDisplayAvatarUrl : _peerAvatarUrl(msg);
    return _safeInitialAvatar(
      name: isMine ? _myDisplayName : peerName,
      avatarUrl: url,
      radius: 18,
      fallbackBg: bg,
      fallbackFg: fg,
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
              color: const Color(0xFFF6F3C6),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFEAE3A4)),
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
    final parsedReply = _splitReplyPrefix(msg['messageContent']?.toString() ?? '');

    Widget inner;
    switch (type) {
      case 'image':
        final url = _messageMediaUrl(msg);
        inner = url == null
            ? Text('Image', style: TextStyle(color: textColor.withValues(alpha: 0.7)))
            : ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: GestureDetector(
                  onTap: () => launchUrl(Uri.parse(url)),
                  child: CachedNetworkImage(
                    imageUrl: url,
                    width: 220,
                    // Fixed thumbnail height so the bubble stays compact and
                    // doesn't expand to the image's full natural size once it
                    // finishes loading. Tap opens the full image.
                    height: 220,
                    fit: BoxFit.cover,
                    fadeInDuration: const Duration(milliseconds: 120),
                    placeholder: (_, __) => Container(
                      width: 220,
                      height: 220,
                      color: Colors.black.withValues(alpha: 0.04),
                      alignment: Alignment.center,
                      child: const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                    errorWidget: (_, __, ___) => Container(
                      width: 220,
                      height: 220,
                      color: Colors.black.withValues(alpha: 0.04),
                      alignment: Alignment.center,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.broken_image_outlined,
                              color: textColor.withValues(alpha: 0.5)),
                          const SizedBox(height: 4),
                          Text('Tap to open',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: textColor.withValues(alpha: 0.6))),
                        ],
                      ),
                    ),
                  ),
                ),
              );
        break;
      case 'file':
        final name = msg['fileName']?.toString() ?? 'File';
        final url = _messageMediaUrl(msg);
        inner = InkWell(
          onTap: url != null ? () => launchUrl(Uri.parse(url)) : null,
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
      case 'video':
        final name = msg['fileName']?.toString() ?? 'Video';
        final url = _messageMediaUrl(msg);
        inner = InkWell(
          onTap: url != null ? () => launchUrl(Uri.parse(url)) : null,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.play_circle_fill, color: textColor.withValues(alpha: 0.8)),
              const SizedBox(width: 8),
              Flexible(child: Text(name, style: TextStyle(color: textColor))),
            ],
          ),
        );
        break;
      case 'voice':
        final url = _messageMediaUrl(msg);
        inner = (url == null)
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
                key: ValueKey<String>('poll-$pollId'),
                pollId: pollId,
                titleText: titleText,
                embeddedPollOptions: pollOptsFromMsg,
                myOptionIds: _myPollOptionIds[pollId] ?? const [],
                onOpenDetail: openPoll,
                onVoteSubmitted: () => unawaited(_hydratePollVotes()),
              );
        break;
      default:
        inner = _linkifiedText(
          parsedReply.body,
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
                if (type == 'text' && parsedReply.sender != null && parsedReply.snippet != null)
                  InkWell(
                    onTap: () => _jumpToRepliedMessage(parsedReply.replyId),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.fromLTRB(10, 7, 8, 7),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(8),
                        border: Border(
                          left: BorderSide(color: const Color(0xFFF59E0B), width: 3),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            parsedReply.sender!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFFF59E0B)),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            parsedReply.snippet!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade800),
                          ),
                        ],
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

    final highlighted = _highlightMessageId != null &&
        _highlightMessageId == (msg['_id']?.toString() ?? '');
    final column = Column(
      crossAxisAlignment: isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (highlighted)
          Container(
            width: 4,
            height: 16,
            margin: const EdgeInsets.only(bottom: 4),
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        bubble,
        meta,
      ],
    );

    final row = Padding(
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
    if (type == 'system') return row;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onLongPress: () {
        showModalBottomSheet<void>(
          context: context,
          builder: (ctx) => SafeArea(
            child: ListTile(
              leading: const Icon(Icons.reply),
              title: const Text('Reply'),
              onTap: () {
                Navigator.pop(ctx);
                setState(() => _replyTo = msg);
              },
            ),
          ),
        );
      },
      child: row,
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
      final lastSeen = DateTime.tryParse(widget.peerLastSeenAt ?? '')?.toLocal();
      final off = lastSeen == null ? 'Offline' : 'Last seen ${DateFormat.yMd().add_jm().format(lastSeen)}';
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
            online ? 'Online' : off,
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
          style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
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
    _markReadDebounce?.cancel();
    _hideChatTopBanner();
    _sub?.cancel();
    _recordingTimer?.cancel();
    _scrollController.dispose();
    _text.dispose();
    _searchQuery.dispose();
    _searchFocus.dispose();
    unawaited(_audioRecorder.dispose());
    super.dispose();
  }

  String _fmtMmSs(Duration d) {
    final total = d.inSeconds;
    final m = total ~/ 60;
    final s = total % 60;
    final ss = s < 10 ? '0$s' : '$s';
    return '$m:$ss';
  }

  void _discardPendingVoice() {
    if (!mounted) return;
    setState(() {
      _pendingVoicePath = null;
      _pendingVoiceName = null;
    });
  }

  Future<void> _sendPendingVoice() async {
    final path = _pendingVoicePath;
    final name = _pendingVoiceName ?? 'voice.m4a';
    if (path == null || path.isEmpty) return;
    await _upload(path, name, 'voice');
    if (!mounted) return;
    setState(() {
      _pendingVoicePath = null;
      _pendingVoiceName = null;
    });
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
        toolbarHeight: kToolbarHeight,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _safeInitialAvatar(
                  name: title,
                  avatarUrl: widget.avatarUrl,
                  radius: 20,
                  fallbackBg: letterBg,
                  fallbackFg: letterFg,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _searchOpen
                      ? Container(
                          height: 40,
                          padding: const EdgeInsets.only(left: 4, right: 12),
                          decoration: BoxDecoration(
                            color: Colors.white,
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
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                  ),
                                  onChanged: (_) => setState(() {}),
                                ),
                              ),
                            ],
                          ),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                        _groupName.isNotEmpty ? _groupName : title,
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
                if (_searchOpen)
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
                  )
                else
                  IconButton(
                    icon: Icon(Icons.search, color: Colors.grey.shade700),
                    onPressed: _openMessageSearch,
                  ),
                if (!_searchOpen && _canManageGroupSettings)
                  IconButton(
                    icon: Icon(Icons.settings, color: Colors.grey.shade700),
                    onPressed: _openGroupSettingsSheet,
                  ),
              ],
            ),
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
                              if (i == 0) {
                                final tFirst = _msgLocalTime(msg);
                                if (tFirst != null) {
                                  pieces.add(_dateSeparatorPill(tFirst));
                                }
                              }
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
                              // Key the row by message id so each item's
                              // element (and any stateful child like a poll
                              // card or voice player) stays bound to its own
                              // message when the list reorders — inserting a
                              // new message at index 0 shifts every index, and
                              // without a key Flutter reuses State by position,
                              // which flashes the previous poll's data for a
                              // frame before it reloads.
                              final rowKey = ValueKey<String>(
                                msg['_id']?.toString() ?? 'idx-$i',
                              );
                              return Column(
                                key: rowKey,
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
                      'Recording… ${_fmtMmSs(_recordingElapsed)}',
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
                              _sendBlockedReason ??
                                  'You can view this broadcast chat, but only selected users can send messages.',
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
                  color: Colors.white,
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_replyTo != null)
                            Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _replyLabelFor(_replyTo!),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF1565C0)),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          _replySnippetFor(_replyTo!),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.close, size: 18),
                                    onPressed: () => setState(() => _replyTo = null),
                                  ),
                                ],
                              ),
                            ),
                          Row(
                            // Center the circular send/mic button against the
                            // input pill so it doesn't sit low; the pill still
                            // grows upward for multi-line text.
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(28),
                                border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  IconButton(
                                    icon: Icon(Icons.attach_file, color: AppColors.primary, size: 22),
                                    onPressed: _uploading ? null : _showWebAttachSheet,
                                    visualDensity: VisualDensity.compact,
                                    padding: const EdgeInsets.symmetric(horizontal: 10),
                                    constraints: const BoxConstraints(),
                                  ),
                                  Expanded(
                                    child: _pendingVoicePath != null
                                        ? Padding(
                                            padding: const EdgeInsets.fromLTRB(6, 10, 6, 10),
                                            child: Row(
                                              children: [
                                                Container(
                                                  width: 28,
                                                  height: 28,
                                                  decoration: BoxDecoration(
                                                    color: AppColors.primary.withValues(alpha: 0.12),
                                                    shape: BoxShape.circle,
                                                  ),
                                                  alignment: Alignment.center,
                                                  child: Icon(Icons.play_arrow_rounded, color: AppColors.primary, size: 18),
                                                ),
                                                const SizedBox(width: 10),
                                                const Icon(Icons.mic_rounded, size: 18, color: Color(0xFF0F172A)),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: Text(
                                                    'Voice message',
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: TextStyle(color: const Color(0xFF0F172A).withValues(alpha: 0.75)),
                                                  ),
                                                ),
                                                IconButton(
                                                  visualDensity: VisualDensity.compact,
                                                  padding: EdgeInsets.zero,
                                                  icon: Icon(Icons.close, size: 18, color: Colors.grey.shade700),
                                                  onPressed: _discardPendingVoice,
                                                ),
                                              ],
                                            ),
                                          )
                                        : TextField(
                                            controller: _text,
                                            minLines: 1,
                                            maxLines: 4,
                                            decoration: const InputDecoration(
                                              hintText: 'Type a message...',
                                              hintStyle: TextStyle(color: Color(0xFF94A3B8)),
                                              filled: true,
                                              fillColor: Colors.white,
                                              border: InputBorder.none,
                                              enabledBorder: InputBorder.none,
                                              focusedBorder: InputBorder.none,
                                              isDense: true,
                                              contentPadding: EdgeInsets.fromLTRB(4, 12, 12, 12),
                                            ),
                                            onChanged: (_) {
                                              _emitTyping();
                                              setState(() {});
                                            },
                                          ),
                                  ),
                                  IconButton(
                                    icon: Icon(Icons.photo_camera_outlined, color: AppColors.primary, size: 22),
                                    onPressed: _uploading ? null : () => _pickImage(ImageSource.camera),
                                    visualDensity: VisualDensity.compact,
                                    padding: const EdgeInsets.symmetric(horizontal: 10),
                                    constraints: const BoxConstraints(),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (_uploading)
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                shape: BoxShape.circle,
                              ),
                              alignment: Alignment.center,
                              child: const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor:
                                      AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              ),
                            )
                          else if (_recording)
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
                          else if (_pendingVoicePath != null)
                            Container(
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                shape: BoxShape.circle,
                              ),
                              child: IconButton(
                                icon: const Icon(Icons.send_rounded),
                                color: Colors.white,
                                onPressed: _sendPendingVoice,
                              ),
                            )
                          else if (_text.text.trim().isNotEmpty)
                            Container(
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                shape: BoxShape.circle,
                              ),
                              child: IconButton(
                                icon: const Icon(Icons.send_rounded),
                                color: Colors.white,
                                onPressed: _sendText,
                              ),
                            )
                          else
                            Container(
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                shape: BoxShape.circle,
                              ),
                              child: IconButton(
                                icon: const Icon(Icons.mic_none_rounded),
                                color: Colors.white,
                                onPressed: _toggleRecording,
                              ),
                            ),
                        ],
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
    super.key,
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
  bool _isActive = true;
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
        _isActive = m['isActive'] != false;
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
      showChatTopBanner(context, 'Choose at least one option');
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
          showChatTopBanner(context, r['message']?.toString() ?? 'Could not submit vote');
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
    final showVoteUi = !_loading && !_isClosed && _isActive && !_cannotVote && !_alreadyVoted && _options.isNotEmpty;
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
                                    Expanded(child: Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, color: Color(0xFF0F172A)))),
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
                                  crossAxisAlignment: CrossAxisAlignment.center,
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
                                    Expanded(child: Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, color: Color(0xFF0F172A)))),
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
                              )
                            else if (!_isActive)
                              Text(
                                'Poll inactive',
                                style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w600),
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
