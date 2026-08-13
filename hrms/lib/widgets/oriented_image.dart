import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../utils/image_orientation.dart';

/// An image widget that corrects EXIF orientation before display.
///
/// Flutter's built-in image widgets ignore the EXIF orientation tag, so camera
/// photos and scanned documents that carry one render rotated. [OrientedImage]
/// bakes the orientation into the pixels (off the UI isolate) and then shows the
/// upright result. Use it anywhere the app displays a user/camera/document photo
/// from raw bytes, a file, or a URL.
///
/// Baking an already-upright image is a no-op, so wrapping a source that is
/// already corrected (e.g. a baked selfie) is safe.
class OrientedImage extends StatefulWidget {
  /// Raw image bytes (e.g. a downloaded proof). Exactly one source is set.
  final Uint8List? bytes;

  /// A local image file (e.g. a freshly captured photo).
  final File? file;

  /// A remote image URL. The bytes are downloaded once, baked and cached.
  final String? url;

  final BoxFit? fit;
  final double? width;
  final double? height;

  /// Shown while the (async) orientation bake is in progress.
  final Widget? loading;

  /// Built when the source can't be loaded or decoded.
  final ImageErrorWidgetBuilder? errorBuilder;

  const OrientedImage.memory(
    Uint8List this.bytes, {
    super.key,
    this.fit,
    this.width,
    this.height,
    this.loading,
    this.errorBuilder,
  })  : file = null,
        url = null;

  const OrientedImage.file(
    File this.file, {
    super.key,
    this.fit,
    this.width,
    this.height,
    this.loading,
    this.errorBuilder,
  })  : bytes = null,
        url = null;

  const OrientedImage.network(
    String this.url, {
    super.key,
    this.fit,
    this.width,
    this.height,
    this.loading,
    this.errorBuilder,
  })  : bytes = null,
        file = null;

  @override
  State<OrientedImage> createState() => _OrientedImageState();
}

class _OrientedImageState extends State<OrientedImage> {
  /// Baked bytes cached per URL so a remote image is fetched + rotated once.
  static final Map<String, Future<Uint8List>> _networkCache = {};

  late Future<Uint8List> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(covariant OrientedImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url ||
        oldWidget.file?.path != widget.file?.path ||
        !identical(oldWidget.bytes, widget.bytes)) {
      _future = _load();
    }
  }

  Future<Uint8List> _load() {
    final url = widget.url;
    if (url != null) {
      return _networkCache.putIfAbsent(url, () => _downloadAndBake(url));
    }
    final file = widget.file;
    if (file != null) return ImageOrientation.bakeFile(file);
    return ImageOrientation.bakeBytes(widget.bytes!);
  }

  static Future<Uint8List> _downloadAndBake(String url) async {
    final resp = await Dio().get<List<int>>(
      url,
      options: Options(responseType: ResponseType.bytes),
    );
    final data = resp.data;
    if (data == null || data.isEmpty) {
      throw StateError('Empty image response');
    }
    return ImageOrientation.bakeBytes(Uint8List.fromList(data));
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return widget.errorBuilder?.call(
                context,
                snapshot.error!,
                snapshot.stackTrace,
              ) ??
              const SizedBox.shrink();
        }
        final data = snapshot.data;
        if (data == null) {
          return widget.loading ??
              const Center(child: CircularProgressIndicator());
        }
        return Image.memory(
          data,
          fit: widget.fit,
          width: widget.width,
          height: widget.height,
          errorBuilder: widget.errorBuilder,
        );
      },
    );
  }
}
