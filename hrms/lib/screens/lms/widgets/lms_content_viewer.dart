// hrms/lib/screens/lms/widgets/lms_content_viewer.dart
// Embedded content viewer for YouTube, VIDEO, PDF, URL - mirrors web LMSCoursePlayer
// YouTube: uses loadHtmlString with baseUrl to fix Error 153 (Referer required)
// PDF: WebView loads the PDF link directly so it opens in-app; "Open in browser" as fallback.
//
// WebViewController is cached per content URL to avoid creating a new WebView on every rebuild.
// This reduces MediaCodec/Chromium teardown races (Pipe closed, BAD_INDEX) when leaving video or rebuilding.

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../config/constants.dart';

class LmsContentViewer extends StatefulWidget {
  final dynamic material;
  final VoidCallback? onMarkDone;

  const LmsContentViewer({super.key, required this.material, this.onMarkDone});

  @override
  State<LmsContentViewer> createState() => _LmsContentViewerState();
}

class _LmsContentViewerState extends State<LmsContentViewer> {
  WebViewController? _cachedController;
  String? _cachedControllerKey;

  String? _getVideoId() {
    final m = widget.material;
    var url = m['url'] ?? m['filePath'] ?? m['link'] ?? m['externalUrl'] ?? '';
    url = url.toString().trim();
    if (url.isEmpty) return null;
    if (url.contains('v=')) return url.split('v=')[1]?.split('&')[0];
    return url.split('/').last;
  }

  String? _getResolvedUrl() {
    final type = (widget.material['type'] ?? 'URL').toString().toUpperCase();
    var url =
        widget.material['url'] ??
        widget.material['filePath'] ??
        widget.material['link'] ??
        widget.material['externalUrl'] ??
        '';
    url = url.toString().trim();
    if (url.isEmpty) return null;

    if (type == 'YOUTUBE') {
      final videoId = _getVideoId();
      if (videoId != null && videoId.isNotEmpty) {
        return 'https://www.youtube.com/embed/$videoId?autoplay=0&rel=0&modestbranding=1';
      }
      return null;
    }

    if (url.startsWith('http') ||
        url.startsWith('https') ||
        url.startsWith('data:')) {
      return url;
    }
    return AppConstants.getLmsFileUrl(url);
  }

  /// YouTube embed HTML with referrerpolicy to fix Error 153. Load with baseUrl so Referer is sent.
  String _buildYouTubeEmbedHtml(String videoId) {
    final embedUrl =
        'https://www.youtube-nocookie.com/embed/$videoId'
        '?enablejsapi=1&rel=0&modestbranding=1&playsinline=1&autoplay=0&origin=https://www.youtube.com';
    return '''
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="referrer" content="strict-origin-when-cross-origin">
<style>html,body{margin:0;padding:0;height:100%;background:#000}
iframe{width:100%;height:100%;border:0;display:block}
</style>
</head>
<body>
<iframe src="$embedUrl"
  allow="accelerometer;autoplay;clipboard-write;encrypted-media;gyroscope;picture-in-picture"
  allowfullscreen
  referrerpolicy="strict-origin-when-cross-origin">
</iframe>
</body>
</html>''';
  }

  /// Returns a cached WebViewController for the given key, or creates and caches one.
  WebViewController _getOrCreateController({
    required String key,
    required void Function(WebViewController c) setup,
  }) {
    if (_cachedControllerKey == key && _cachedController != null) {
      return _cachedController!;
    }
    _cachedControllerKey = key;
    final c = WebViewController();
    setup(c);
    _cachedController = c;
    return c;
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Widget _buildPdfViewer(BuildContext context, String pdfUrl) {
    final uri = Uri.tryParse(pdfUrl);
    if (uri == null) {
      return _buildPlaceholder('Invalid PDF link.');
    }
    final controller = _getOrCreateController(
      key: 'pdf:$pdfUrl',
      setup: (c) {
        c.setJavaScriptMode(JavaScriptMode.unrestricted);
        c.setBackgroundColor(Colors.grey.shade100);
        c.loadRequest(uri);
      },
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: MediaQuery.of(context).size.height * 0.6,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: WebViewWidget(controller: controller),
          ),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: () => _openUrl(pdfUrl),
          icon: const Icon(Icons.open_in_browser, size: 18),
          label: const Text('Open in browser'),
          style: TextButton.styleFrom(foregroundColor: Colors.grey[700]),
        ),
      ],
    );
  }

  Widget _buildYouTubePlayer(BuildContext context) {
    final videoId = _getVideoId();
    if (videoId == null || videoId.isEmpty) {
      return _buildPlaceholder('Invalid YouTube link.');
    }
    final html = _buildYouTubeEmbedHtml(videoId);
    const baseUrl = 'https://www.youtube-nocookie.com/';
    final controller = _getOrCreateController(
      key: 'yt:$videoId',
      setup: (c) {
        c.setJavaScriptMode(JavaScriptMode.unrestricted);
        c.loadHtmlString(html, baseUrl: baseUrl);
      },
    );
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: WebViewWidget(controller: controller),
      ),
    );
  }

  Widget _buildVideoOrUrlViewer(BuildContext context, String urlToLoad) {
    final controller = _getOrCreateController(
      key: 'video:$urlToLoad',
      setup: (c) {
        c.setJavaScriptMode(JavaScriptMode.unrestricted);
        c.loadRequest(Uri.parse(urlToLoad));
      },
    );
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: WebViewWidget(controller: controller),
      ),
    );
  }

  @override
  void dispose() {
    _cachedController = null;
    _cachedControllerKey = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final type = (widget.material['type'] ?? 'URL').toString().toUpperCase();
    final urlToLoad = _getResolvedUrl();

    if (urlToLoad == null || urlToLoad.isEmpty) {
      return _buildPlaceholder(
        'No learning material available for this lesson.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (type == 'PDF')
          _buildPdfViewer(context, urlToLoad)
        else if (type == 'YOUTUBE')
          _buildYouTubePlayer(context)
        else
          _buildVideoOrUrlViewer(context, urlToLoad),
        if (widget.onMarkDone != null) ...[
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: widget.onMarkDone,
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('Mark Done'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildPlaceholder(String message) {
    return Container(
      padding: const EdgeInsets.all(48),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Text(
          message,
          style: TextStyle(color: Colors.grey[600]),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
