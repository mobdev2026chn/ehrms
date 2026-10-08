// In-app viewer for announcement / chat attachments: images and PDFs open inside
// the app (zoomable); other types are saved to a temp file and handed to the
// phone's own app. Attachments stored without a file (url empty) say so.

import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart';

import '../../../services/staff_interaction_service.dart';
import 'staff_interaction_widgets.dart';

/// Opens [a] the best way for its type.
Future<void> viewAttachment(BuildContext context, ChatAttachment a) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (a.url.trim().isEmpty) {
    messenger?.showSnackBar(const SnackBar(
      content: Text('This file was not uploaded with the announcement, so it cannot be opened. Ask HR to re-attach it.'),
    ));
    return;
  }
  if (a.isImage) {
    showImageViewer(context, a.url, title: a.name);
    return;
  }
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => _AttachmentViewerScreen(attachment: a)));
}

/// The attachment's bytes, from a data: URI or a download.
Future<Uint8List> _attachmentBytes(ChatAttachment a) async {
  final inline = dataUrlBytes(a.url);
  if (inline != null) return inline;
  final res = await Dio().get<List<int>>(
    resolveMediaUrl(a.url),
    options: Options(responseType: ResponseType.bytes, receiveTimeout: const Duration(seconds: 60)),
  );
  return Uint8List.fromList(res.data ?? const []);
}

bool _isPdf(ChatAttachment a) => a.type == 'pdf' || a.name.toLowerCase().endsWith('.pdf');

class _AttachmentViewerScreen extends StatefulWidget {
  const _AttachmentViewerScreen({required this.attachment});
  final ChatAttachment attachment;

  @override
  State<_AttachmentViewerScreen> createState() => _AttachmentViewerScreenState();
}

class _AttachmentViewerScreenState extends State<_AttachmentViewerScreen> {
  Uint8List? _bytes;
  PdfControllerPinch? _pdf;
  String? _error;
  int _page = 1;
  int _pages = 0;

  ChatAttachment get _a => widget.attachment;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _pdf?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final bytes = await _attachmentBytes(_a);
      if (bytes.isEmpty) throw Exception('empty');
      if (!mounted) return;
      setState(() {
        _bytes = bytes;
        if (_isPdf(_a)) _pdf = PdfControllerPinch(document: PdfDocument.openData(bytes));
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load this file. Check your connection and try again.');
    }
  }

  /// Saves to a temp file and opens it in the phone's own app (also the
  /// fallback for types the app cannot show).
  Future<void> _openExternally() async {
    final bytes = _bytes;
    if (bytes == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final dir = await getTemporaryDirectory();
      final safe = _a.name.replaceAll(RegExp(r'[^\w.\- ]'), '_');
      final f = File('${dir.path}/$safe');
      await f.writeAsBytes(bytes, flush: true);
      final r = await OpenFilex.open(f.path);
      if (r.type != ResultType.done) {
        messenger.showSnackBar(SnackBar(content: Text(r.message.isEmpty ? 'No app on this phone can open this file.' : r.message)));
      }
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('Could not open the file.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE9ECF0),
      appBar: AppBar(
        title: Text(_a.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: kInteractionInk)),
        actions: [
          if (_bytes != null)
            IconButton(tooltip: 'Open in another app', icon: const Icon(Icons.open_in_new_rounded), onPressed: _openExternally),
        ],
      ),
      body: _body(),
      bottomNavigationBar: _pdf != null && _pages > 1
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: kInteractionLine),
                    ),
                    child: Text('Page $_page of $_pages', textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: kInteractionMuted)),
                  ),
                ),
              ),
            )
          : null,
    );
  }

  Widget _body() {
    if (_error != null) {
      return InteractionEmptyState(
        icon: Icons.cloud_off_rounded,
        title: 'File not loaded',
        message: _error!,
        action: OutlinedButton(onPressed: _load, child: const Text('Retry')),
      );
    }
    if (_bytes == null) return const Center(child: CircularProgressIndicator(strokeWidth: 2.5));
    final pdf = _pdf;
    if (pdf != null) {
      return PdfViewPinch(
        controller: pdf,
        onDocumentLoaded: (doc) => setState(() => _pages = doc.pagesCount),
        onPageChanged: (p) => setState(() => _page = p),
        onDocumentError: (_) => setState(() => _error = 'This PDF could not be displayed. Try "Open in another app".'),
      );
    }
    // Word / Excel / other: the phone's app shows these.
    return InteractionEmptyState(
      icon: Icons.insert_drive_file_outlined,
      title: _a.name,
      message: 'This file type opens in another app on your phone.',
      action: ElevatedButton.icon(
        onPressed: _openExternally,
        icon: const Icon(Icons.open_in_new_rounded, size: 18),
        label: const Text('Open file'),
      ),
    );
  }
}
