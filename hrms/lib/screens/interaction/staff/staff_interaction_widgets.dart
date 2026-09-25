// Shared bits for the staff Interaction screens (chats, polls, announcements).

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../config/constants.dart';
import '../../../services/staff_interaction_service.dart';

const kInteractionAccent = Color(0xFFEFAA1F);
const kInteractionInk = Color(0xFF0F172A);
const kInteractionMuted = Color(0xFF64748B);
const kInteractionLine = Color(0xFFF1F5F9);

/// Bytes of a `data:*;base64,...` URL, else null.
Uint8List? dataUrlBytes(String url) {
  if (!url.startsWith('data:')) return null;
  final i = url.indexOf('base64,');
  if (i < 0) return null;
  try {
    return base64Decode(url.substring(i + 7));
  } catch (_) {
    return null;
  }
}

/// Absolute URL for server paths ("/uploads/...") and plain http(s) URLs.
String resolveMediaUrl(String url) {
  if (url.isEmpty || url.startsWith('data:')) return url;
  return AppConstants.getInteractionFileUrl(url);
}

ImageProvider? mediaImageProvider(String url) {
  if (url.trim().isEmpty) return null;
  final bytes = dataUrlBytes(url);
  if (bytes != null) return MemoryImage(bytes);
  final abs = resolveMediaUrl(url);
  if (!abs.startsWith('http')) return null;
  return CachedNetworkImageProvider(abs);
}

String initialsOf(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first[0].toUpperCase();
  return (parts.first[0] + parts.last[0]).toUpperCase();
}

/// Stable soft colour per name, for initials avatars.
Color avatarTint(String seed) {
  const palette = [
    Color(0xFFF59E0B), Color(0xFF6366F1), Color(0xFF10B981), Color(0xFFEF4444),
    Color(0xFF0EA5E9), Color(0xFF8B5CF6), Color(0xFFEC4899), Color(0xFF14B8A6),
  ];
  var h = 0;
  for (final c in seed.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return palette[h % palette.length];
}

class InteractionAvatar extends StatelessWidget {
  const InteractionAvatar({
    super.key,
    required this.name,
    this.url = '',
    this.size = 44,
    this.icon,
    this.online = false,
  });

  final String name;
  final String url;
  final double size;
  final IconData? icon;
  final bool online;

  @override
  Widget build(BuildContext context) {
    final provider = mediaImageProvider(url);
    final tint = avatarTint(name);
    final avatar = CircleAvatar(
      radius: size / 2,
      backgroundColor: tint.withValues(alpha: 0.15),
      foregroundImage: provider,
      onForegroundImageError: provider == null ? null : (_, _) {},
      child: icon != null
          ? Icon(icon, color: tint, size: size * 0.48)
          : Text(
              initialsOf(name),
              style: TextStyle(color: tint, fontWeight: FontWeight.w800, fontSize: size * 0.34),
            ),
    );
    if (!online) return avatar;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        avatar,
        Positioned(
          right: 0,
          bottom: 0,
          child: Container(
            width: size * 0.28,
            height: size * 0.28,
            decoration: BoxDecoration(
              color: const Color(0xFF22C55E),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
          ),
        ),
      ],
    );
  }
}

/// "10:42 AM" today, "Yesterday", weekday within a week, else "25 Sep".
String chatListTime(DateTime? t) {
  if (t == null) return '';
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(t.year, t.month, t.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return DateFormat('hh:mm a').format(t);
  if (diff == 1) return 'Yesterday';
  if (diff < 7) return DateFormat('EEEE').format(t);
  return DateFormat(t.year == now.year ? 'd MMM' : 'd MMM yyyy').format(t);
}

/// Day separator label in a thread.
String chatDayLabel(DateTime t) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(t.year, t.month, t.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  return DateFormat(t.year == now.year ? 'EEE, d MMM' : 'd MMM yyyy').format(t);
}

String fileSizeLabel(int bytes) {
  if (bytes <= 0) return '';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// Opens an attachment: http URLs in the browser/viewer, data URLs saved to a
/// temp file and opened with the system app.
Future<void> openAttachment(BuildContext context, ChatAttachment a) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    final bytes = dataUrlBytes(a.url);
    if (bytes != null) {
      final dir = await getTemporaryDirectory();
      final safe = a.name.replaceAll(RegExp(r'[^\w.\- ]'), '_');
      final f = File('${dir.path}/$safe');
      await f.writeAsBytes(bytes, flush: true);
      final r = await OpenFilex.open(f.path);
      if (r.type != ResultType.done) {
        messenger?.showSnackBar(SnackBar(content: Text(r.message.isEmpty ? 'No app to open this file.' : r.message)));
      }
      return;
    }
    final uri = Uri.tryParse(resolveMediaUrl(a.url));
    if (uri == null || !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      messenger?.showSnackBar(const SnackBar(content: Text('Could not open the file.')));
    }
  } catch (_) {
    messenger?.showSnackBar(const SnackBar(content: Text('Could not open the file.')));
  }
}

/// Full-screen, zoomable image.
void showImageViewer(BuildContext context, String url, {String? title}) {
  final provider = mediaImageProvider(url);
  if (provider == null) return;
  Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(title ?? '', style: const TextStyle(fontSize: 15)),
      ),
      body: Center(
        child: InteractiveViewer(maxScale: 5, child: Image(image: provider)),
      ),
    ),
  ));
}

class InteractionEmptyState extends StatelessWidget {
  const InteractionEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message = '',
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: kInteractionAccent.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 34, color: kInteractionAccent),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: kInteractionInk),
            ),
            if (message.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: kInteractionMuted, height: 1.4),
              ),
            ],
            if (action != null) ...[const SizedBox(height: 14), action!],
          ],
        ),
      ),
    );
  }
}
