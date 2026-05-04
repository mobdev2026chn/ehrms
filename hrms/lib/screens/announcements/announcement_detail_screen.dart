import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/constants.dart';
import '../../services/interaction_service.dart';
import '../../utils/error_message_utils.dart';
import '../../widgets/bottom_navigation_bar.dart';

class AnnouncementDetailScreen extends StatefulWidget {
  final Map<String, dynamic> announcement;
  final Color accent;

  const AnnouncementDetailScreen({
    super.key,
    required this.announcement,
    required this.accent,
  });

  @override
  State<AnnouncementDetailScreen> createState() =>
      _AnnouncementDetailScreenState();
}

class _AnnouncementDetailScreenState extends State<AnnouncementDetailScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final TextEditingController _messageController = TextEditingController();
  bool _loadingEngagement = true;
  bool _sendingMessage = false;
  List<Map<String, dynamic>> _myReplies = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _syncReadAndSeen();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _syncReadAndSeen() async {
    final id =
        widget.announcement['_id']?.toString() ??
        widget.announcement['id']?.toString() ??
        '';
    if (id.isEmpty) {
      if (mounted) setState(() => _loadingEngagement = false);
      return;
    }
    try {
      await InteractionService.instance.markAnnouncementRead(id);
      await InteractionService.instance.markAnnouncementHrSeen(id);
      final repliesRes = await InteractionService.instance
          .getAnnouncementMyReplies(id);
      final engagementRes = await InteractionService.instance
          .getAnnouncementEngagement(id);
      final detailRes = await InteractionService.instance.getAnnouncementById(
        id,
      );

      if (kDebugMode) {
        debugPrint(
          '[Announcement][Engagement] my-replies raw: ${repliesRes['data']}',
        );
        debugPrint(
          '[Announcement][Engagement] engagement raw: ${engagementRes['data']}',
        );
        debugPrint(
          '[Announcement][Engagement] detail engagement raw: ${detailRes['data']?['engagement']}',
        );
      }

      final myRepliesList = _extractItems(repliesRes);

      // Full conversation should come from engagement route, then merge with my-replies.
      var engagementList = _extractItems(engagementRes);
      if (engagementList.isEmpty) {
        engagementList = _extractItems(detailRes['data']?['engagement']);
      }
      if (engagementList.isEmpty) {
        engagementList = _extractItems(widget.announcement['engagement']);
      }
      if (engagementList.isEmpty) {
        engagementList = List<Map<String, dynamic>>.from(myRepliesList);
      }
      final mergedThreads = _mergeConversationThreads(
        primary: engagementList,
        secondary: myRepliesList,
      );
      if (kDebugMode) {
        debugPrint(
          '[Announcement][Engagement] myRepliesList=${myRepliesList.length} engagementList=${engagementList.length} merged=${mergedThreads.length}',
        );
        for (final t in mergedThreads) {
          final msg =
              t['replyText']?.toString() ??
              t['messageText']?.toString() ??
              t['query']?.toString() ??
              t['message']?.toString() ??
              t['reply']?.toString() ??
              '';
          final time =
              t['repliedAt']?.toString() ??
              t['createdAt']?.toString() ??
              t['date']?.toString() ??
              '';
          final replies = (t['replies'] is List)
              ? (t['replies'] as List)
              : const [];
          debugPrint(
            '[Announcement][Engagement][Thread] msg="$msg" time="$time" replies=${replies.length}',
          );
          for (final r in replies) {
            if (r is! Map) continue;
            final rt =
                r['text']?.toString() ??
                r['replyText']?.toString() ??
                r['messageText']?.toString() ??
                r['responseText']?.toString() ??
                r['followUpText']?.toString() ??
                r['message']?.toString() ??
                r['reply']?.toString() ??
                '';
            final rtime =
                r['responseTime']?.toString() ??
                r['createdAt']?.toString() ??
                r['date']?.toString() ??
                '';
            debugPrint(
              '[Announcement][Engagement][Reply] text="$rt" time="$rtime"',
            );
          }
        }
      }
      if (mounted) {
        setState(() {
          _myReplies = mergedThreads;
        });
      }
    } catch (_) {
      // Keep UI usable even if engagement endpoints fail for one announcement.
    } finally {
      if (mounted) setState(() => _loadingEngagement = false);
    }
  }

  Map<String, dynamic>? _asStringMap(dynamic item) {
    if (item is! Map) return null;
    final m = <String, dynamic>{};
    item.forEach((k, v) => m[k.toString()] = v);
    return m;
  }

  List<Map<String, dynamic>> _extractItems(dynamic data) {
    final list = <Map<String, dynamic>>[];

    void pull(dynamic value) {
      if (value == null) return;
      if (value is List) {
        for (final e in value) {
          final m = _asStringMap(e);
          if (m != null) list.add(m);
        }
        return;
      }
      final m = _asStringMap(value);
      if (m == null) return;

      // If this looks like a single message/thread object, keep it.
      if (m.containsKey('message') ||
          m.containsKey('replyText') ||
          m.containsKey('messageText') ||
          m.containsKey('query') ||
          m.containsKey('reply') ||
          m.containsKey('content') ||
          m.containsKey('text') ||
          m.containsKey('replies') ||
          m.containsKey('responses') ||
          m.containsKey('hrResponse') ||
          m.containsKey('followUp')) {
        list.add(m);
      }

      // Handle common wrapper keys used by APIs.
      const keys = <String>[
        'data',
        'items',
        'rows',
        'threads',
        'messages',
        'replies',
        'responses',
        'hrResponse',
        'followUp',
        'hrReplies',
        'hrFollowUps',
        'adminReplies',
        'followUps',
        'followupReplies',
        'threadsWithReplies',
        'engagementReplies',
        'myReplies',
        'engagement',
      ];
      for (final k in keys) {
        pull(m[k]);
      }
    }

    pull(data);
    return list;
  }

  List<Map<String, dynamic>> _mergeConversationThreads({
    required List<Map<String, dynamic>> primary,
    required List<Map<String, dynamic>> secondary,
  }) {
    final byKey = <String, Map<String, dynamic>>{};

    String keyFor(Map<String, dynamic> item) {
      return item['_id']?.toString() ??
          item['id']?.toString() ??
          item['threadId']?.toString() ??
          item['createdAt']?.toString() ??
          item['date']?.toString() ??
          item['replyText']?.toString() ??
          item['message']?.toString() ??
          item.toString();
    }

    List<dynamic> repliesFor(Map<String, dynamic> item) {
      final synthesized = <Map<String, dynamic>>[];
      final hrResponse = item['hrResponse']?.toString() ?? '';
      if (hrResponse.isNotEmpty) {
        synthesized.add({
          'replyText': hrResponse,
          'responseTime': item['responseTime'],
          'fromName': 'HR/Admin',
          'kind': 'response',
        });
      }
      if (item['hrFollowUps'] is List) {
        for (final fu in item['hrFollowUps'] as List) {
          if (fu is! Map) continue;
          final text = fu['text']?.toString() ?? '';
          if (text.isEmpty) continue;
          synthesized.add({
            'replyText': text,
            'responseTime': fu['responseTime'] ?? item['responseTime'],
            'fromName': 'HR/Admin',
            'kind': 'followup',
          });
        }
      }
      final fromLists = (item['replies'] is List)
          ? (item['replies'] as List)
          : (item['responses'] is List)
          ? (item['responses'] as List)
          : (item['hrReplies'] is List)
          ? (item['hrReplies'] as List)
          : (item['adminReplies'] is List)
          ? (item['adminReplies'] as List)
          : (item['followUps'] is List)
          ? (item['followUps'] as List)
          : const [];
      final combined = <dynamic>[...synthesized, ...fromLists];
      final seen = <String>{};
      final deduped = <dynamic>[];
      for (final r in combined) {
        if (r is Map) {
          final text =
              r['text']?.toString() ??
              r['replyText']?.toString() ??
              r['messageText']?.toString() ??
              r['responseText']?.toString() ??
              r['followUpText']?.toString() ??
              r['message']?.toString() ??
              r['reply']?.toString() ??
              '';
          final time =
              r['responseTime']?.toString() ??
              r['createdAt']?.toString() ??
              r['date']?.toString() ??
              '';
          final k = '${text.trim()}|$time';
          if (k.trim().isEmpty || seen.contains(k)) continue;
          seen.add(k);
          deduped.add(r);
        } else {
          final k = r.toString();
          if (seen.contains(k)) continue;
          seen.add(k);
          deduped.add(r);
        }
      }
      return deduped;
    }

    Map<String, dynamic> normalized(Map<String, dynamic> src) {
      final out = Map<String, dynamic>.from(src);
      final reps = repliesFor(src);
      if (reps.isNotEmpty) out['replies'] = reps;
      return out;
    }

    for (final item in secondary) {
      final n = normalized(item);
      byKey[keyFor(n)] = n;
    }
    for (final item in primary) {
      final n = normalized(item);
      final key = keyFor(n);
      final existing = byKey[key];
      if (existing == null) {
        byKey[key] = n;
        continue;
      }
      final existingReplies = (existing['replies'] is List)
          ? List<dynamic>.from(existing['replies'] as List)
          : <dynamic>[];
      final newReplies = (n['replies'] is List)
          ? List<dynamic>.from(n['replies'] as List)
          : <dynamic>[];
      if (newReplies.isNotEmpty) {
        String replyKey(dynamic r) {
          if (r is Map) {
            final text =
                r['text']?.toString() ??
                r['replyText']?.toString() ??
                r['messageText']?.toString() ??
                r['responseText']?.toString() ??
                r['followUpText']?.toString() ??
                r['message']?.toString() ??
                r['reply']?.toString() ??
                '';
            final time =
                r['responseTime']?.toString() ??
                r['createdAt']?.toString() ??
                r['created_at']?.toString() ??
                r['date']?.toString() ??
                '';
            return '${text.trim()}|$time';
          }
          return r.toString();
        }

        final seen = <String>{...existingReplies.map(replyKey)};
        for (final r in newReplies) {
          final k = replyKey(r);
          if (k.trim().isEmpty || seen.contains(k)) continue;
          seen.add(k);
          existingReplies.add(r);
        }
        existing['replies'] = existingReplies;
      }
      for (final entry in n.entries) {
        if (existing[entry.key] == null ||
            existing[entry.key].toString().isEmpty) {
          existing[entry.key] = entry.value;
        }
      }
    }

    final merged = byKey.values.toList();
    // Remove duplicate top-level threads by (message text + replied/created time).
    final uniq = <String, Map<String, dynamic>>{};
    for (final t in merged) {
      final msg =
          t['replyText']?.toString() ??
          t['messageText']?.toString() ??
          t['query']?.toString() ??
          t['message']?.toString() ??
          t['reply']?.toString() ??
          '';
      final time =
          t['repliedAt']?.toString() ??
          t['createdAt']?.toString() ??
          t['date']?.toString() ??
          '';
      final key = '${msg.trim()}|$time';
      if (!uniq.containsKey(key)) {
        uniq[key] = t;
      }
    }
    final mergedUnique = uniq.values.toList();
    mergedUnique.sort((a, b) {
      final da = _parseDate(a['createdAt'] ?? a['created_at'] ?? a['date']);
      final db = _parseDate(b['createdAt'] ?? b['created_at'] ?? b['date']);
      if (da == null && db == null) return 0;
      if (da == null) return 1;
      if (db == null) return -1;
      return da.compareTo(db);
    });
    return mergedUnique;
  }

  String get _announcementId =>
      widget.announcement['_id']?.toString() ??
      widget.announcement['id']?.toString() ??
      '';

  Future<void> _sendEngagementMessage() async {
    final id = _announcementId;
    final message = _messageController.text.trim();
    if (id.isEmpty || message.isEmpty || _sendingMessage) return;
    setState(() => _sendingMessage = true);
    try {
      final res = await InteractionService.instance
          .sendAnnouncementEngagementMessage(id, message: message);
      final ok = res['success'] != false;
      if (!ok) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              res['message']?.toString() ?? 'Failed to send message',
            ),
          ),
        );
        return;
      }
      _messageController.clear();
      await _syncReadAndSeen();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ErrorMessageUtils.toUserFriendlyMessage(e)),
        ),
      );
    } finally {
      if (mounted) setState(() => _sendingMessage = false);
    }
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is String) return DateTime.tryParse(value);
    if (value is Map && value['\$date'] != null) {
      return DateTime.tryParse(value['\$date'].toString());
    }
    return null;
  }

  static List<String> _getImageUrls(Map<String, dynamic> a) {
    final list = <String>[];
    final cover = a['coverImage']?.toString();
    if (cover != null && cover.trim().isNotEmpty) {
      if (cover.startsWith('http://') || cover.startsWith('https://')) {
        list.add(cover);
      } else {
        final path = cover.startsWith('/') ? cover : '/$cover';
        list.add('${AppConstants.fileBaseUrl}$path');
      }
    }
    final attachments = a['attachments'];
    if (attachments is List) {
      for (final item in attachments) {
        if (item is! Map) continue;
        final mimeType = (item['mimeType'] as String?)?.toLowerCase() ?? '';
        if (mimeType.isNotEmpty && !mimeType.startsWith('image/')) continue;
        final url = _getAttachmentUrl(item);
        if (url != null && !list.contains(url)) list.add(url);
      }
    }
    return list;
  }

  static String? _getAttachmentUrl(dynamic item) {
    if (item is String && item.trim().isNotEmpty) {
      return item.startsWith('http')
          ? item
          : '${AppConstants.fileBaseUrl}${item.startsWith('/') ? item : '/$item'}';
    }
    if (item is Map) {
      final u = (item['path'] ?? item['url'])?.toString();
      if (u != null && u.trim().isNotEmpty) {
        return u.startsWith('http')
            ? u
            : '${AppConstants.fileBaseUrl}${u.startsWith('/') ? u : '/$u'}';
      }
    }
    return null;
  }

  static Future<void> _openAttachmentUrl(
    BuildContext context,
    String url,
  ) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
  }

  static Widget _buildAttachmentTile(
    BuildContext context, {
    required String name,
    required String url,
    required String mimeType,
    required Color accent,
    required ColorScheme colorScheme,
  }) {
    final isPdf = mimeType.contains('pdf');
    final isImage = mimeType.startsWith('image/');
    final icon = isPdf
        ? Icons.picture_as_pdf_outlined
        : isImage
        ? Icons.image_outlined
        : Icons.insert_drive_file_outlined;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _openAttachmentUrl(context, url),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: accent.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: accent, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    name,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: colorScheme.onSurface,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(Icons.open_in_new, size: 18, color: accent),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static List<Map<String, dynamic>> _getAttachments(Map<String, dynamic> a) {
    final list = <Map<String, dynamic>>[];
    final attachments = a['attachments'];
    if (attachments is! List) return list;
    for (final item in attachments) {
      if (item is! Map) continue;
      final url = _getAttachmentUrl(item);
      if (url == null) continue;
      final name = (item['name'] as String?)?.trim() ?? 'Attachment';
      final mimeType = (item['mimeType'] as String?)?.toLowerCase() ?? '';
      list.add({'name': name, 'url': url, 'mimeType': mimeType});
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final title = widget.announcement['title']?.toString() ?? 'Announcement';
    final description = widget.announcement['description']?.toString() ?? '';
    final fromName = widget.announcement['fromName']?.toString();
    final date =
        _parseDate(widget.announcement['publishDate']) ??
        _parseDate(widget.announcement['effectiveDate']);
    final dateStr = date != null
        ? DateFormat('d MMM y, h:mm a').format(date)
        : '';
    final imageUrls = _getImageUrls(widget.announcement);
    final attachments = _getAttachments(widget.announcement);

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerHighest,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: colorScheme.onSurface,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        centerTitle: true,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Announcement'),
            Tab(text: 'Engagement'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border(
                      left: BorderSide(color: widget.accent, width: 4),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: widget.accent.withOpacity(0.1),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: widget.accent.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          Icons.campaign_rounded,
                          color: widget.accent,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                                color: widget.accent,
                              ),
                            ),
                            if (fromName != null && fromName.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                'From: $fromName',
                                style: TextStyle(
                                  color: colorScheme.onSurfaceVariant,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                            if (dateStr.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Icon(
                                    Icons.schedule_rounded,
                                    size: 18,
                                    color: widget.accent.withOpacity(0.9),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    dateStr,
                                    style: TextStyle(
                                      color: widget.accent.withOpacity(0.9),
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (imageUrls.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  ...imageUrls.map(
                    (url) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          url,
                          width: double.infinity,
                          height: 220,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: colorScheme.surface,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: colorScheme.shadow.withOpacity(0.08),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Description',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          description,
                          style: TextStyle(
                            fontSize: 15,
                            color: colorScheme.onSurface,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (attachments.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: colorScheme.surface,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: colorScheme.shadow.withOpacity(0.08),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.attach_file,
                              size: 18,
                              color: widget.accent,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Attachments',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ...attachments.map(
                          (att) => _buildAttachmentTile(
                            context,
                            name: att['name'] as String,
                            url: att['url'] as String,
                            mimeType: att['mimeType'] as String? ?? '',
                            accent: widget.accent,
                            colorScheme: colorScheme,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 24),
              ],
            ),
          ),
          RefreshIndicator(
            onRefresh: _syncReadAndSeen,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  'You can send multiple messages about this announcement; they appear in order below. HR/Admin can reply to each thread and send follow-up messages when needed.',
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 14),
                if (_loadingEngagement)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                if (!_loadingEngagement && _myReplies.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('No engagement yet.'),
                  ),
                if (_myReplies.isNotEmpty) ...[
                  ..._myReplies.map((r) {
                    final myMessage =
                        r['replyText']?.toString() ??
                        r['messageText']?.toString() ??
                        r['query']?.toString() ??
                        r['message']?.toString() ??
                        r['reply']?.toString() ??
                        r['answer']?.toString() ??
                        r['optionText']?.toString() ??
                        '';
                    final created = _parseDate(
                      r['repliedAt'] ??
                          r['createdAt'] ??
                          r['created_at'] ??
                          r['date'],
                    );
                    final replies = (r['replies'] is List)
                        ? r['replies'] as List
                        : (r['hrReplies'] is List)
                        ? r['hrReplies'] as List
                        : (r['adminReplies'] is List)
                        ? r['adminReplies'] as List
                        : (r['followUps'] is List)
                        ? r['followUps'] as List
                        : (r['hrFollowUps'] is List)
                        ? r['hrFollowUps'] as List
                        : (r['hrResponse'] != null &&
                              r['hrResponse'].toString().trim().isNotEmpty)
                        ? [
                            {
                              'replyText': r['hrResponse'],
                              'responseTime': r['responseTime'],
                              'fromName': 'HR/Admin',
                              'kind': 'response',
                            },
                            ...(r['hrFollowUps'] is List
                                ? List<dynamic>.from(r['hrFollowUps'] as List)
                                : const []),
                          ]
                        : const [];
                    if (myMessage.isEmpty && replies.isEmpty) {
                      return const SizedBox.shrink();
                    }
                    return Container(
                      margin: const EdgeInsets.only(bottom: 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (myMessage.isNotEmpty)
                            Align(
                              alignment: Alignment.centerRight,
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 280,
                                ),
                                child: Container(
                                  padding: const EdgeInsets.all(11),
                                  decoration: BoxDecoration(
                                    color: colorScheme.primaryContainer,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        myMessage,
                                        textAlign: TextAlign.right,
                                        style: TextStyle(
                                          color: colorScheme.onPrimaryContainer,
                                        ),
                                      ),
                                      if (created != null) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          DateFormat(
                                            'd MMM, h:mm a',
                                          ).format(created.toLocal()),
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: colorScheme
                                                .onPrimaryContainer
                                                .withOpacity(0.8),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          if (replies.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            ...replies.map((hr) {
                              if (hr is! Map) return const SizedBox.shrink();
                              final hrText =
                                  hr['text']?.toString() ??
                                  hr['replyText']?.toString() ??
                                  hr['messageText']?.toString() ??
                                  hr['responseText']?.toString() ??
                                  hr['followUpText']?.toString() ??
                                  hr['message']?.toString() ??
                                  hr['reply']?.toString() ??
                                  hr['answer']?.toString() ??
                                  '';
                              if (hrText.isEmpty)
                                return const SizedBox.shrink();
                              final hrDate = _parseDate(
                                hr['responseTime'] ??
                                    hr['createdAt'] ??
                                    hr['created_at'] ??
                                    hr['date'],
                              );
                              return Align(
                                alignment: Alignment.centerLeft,
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 280,
                                  ),
                                  child: Container(
                                    margin: const EdgeInsets.only(top: 8),
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: colorScheme.surface,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: colorScheme.outlineVariant,
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          (hr['kind'] == 'followup'
                                                  ? 'Follow-up from HR / Admin'
                                                  : null) ??
                                              hr['fromName']?.toString() ??
                                              hr['senderName']?.toString() ??
                                              'HR/Admin',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color: colorScheme.primary,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(hrText),
                                        if (hrDate != null) ...[
                                          const SizedBox(height: 4),
                                          Text(
                                            DateFormat(
                                              'd MMM, h:mm a',
                                            ).format(hrDate.toLocal()),
                                            style: TextStyle(
                                              fontSize: 11,
                                              color:
                                                  colorScheme.onSurfaceVariant,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            }),
                          ] else if (myMessage.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'Awaiting response from HR.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  }),
                ],
                const SizedBox(height: 10),
                Text(
                  'Send another message',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: colorScheme.onSurface,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _messageController,
                  minLines: 3,
                  maxLines: 5,
                  textInputAction: TextInputAction.newline,
                  decoration: InputDecoration(
                    hintText: 'Write your feedback or questions for HR...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: _sendingMessage ? null : _sendEngagementMessage,
                    child: _sendingMessage
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Send'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: const AppBottomNavigationBar(currentIndex: -1),
    );
  }
}
