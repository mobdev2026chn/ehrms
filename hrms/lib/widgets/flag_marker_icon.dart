import 'package:hrms/config/app_colors.dart';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Plain flag (no circle behind it): the flag glyph in [color] with a thin white
/// outline so it stays readable on the map. Returns the icon and the anchor at
/// the foot of the flag pole, so the pole stands on the map point.
/// Punch In = green, Punch Out = red.
Future<({BitmapDescriptor icon, Offset anchor})> plainFlagMarkerIcon(
  BuildContext context,
  Color color, {
  double size = 30,
}) async {
  final dpr = MediaQuery.of(context).devicePixelRatio;
  const icon = Icons.flag_rounded;
  TextPainter paint(Paint? fg, Color? c) => TextPainter(
        text: TextSpan(
          text: String.fromCharCode(icon.codePoint),
          style: TextStyle(
            fontSize: size * dpr,
            fontFamily: icon.fontFamily,
            package: icon.fontPackage,
            foreground: fg,
            color: fg == null ? c : null,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

  final outline = paint(
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3 * dpr
      ..strokeJoin = StrokeJoin.round
      ..color = Colors.white,
    null,
  );
  final fill = paint(null, color);
  final pad = 2 * dpr;
  final w = fill.width + pad * 2;
  final h = fill.height + pad * 2;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  outline.paint(canvas, Offset(pad, pad));
  fill.paint(canvas, Offset(pad, pad));
  final img = await recorder.endRecording().toImage(w.ceil(), h.ceil());
  final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
  return (
    icon: BitmapDescriptor.bytes(bytes!.buffer.asUint8List(), imagePixelRatio: dpr),
    // Material "flag": pole at ~21% of the width, foot at ~88% of the height.
    anchor: const Offset(0.24, 0.86),
  );
}

/// Field In / Field Out dots: blue = in, orange = out.
const Color kFieldInDotColor = Color(0xFF0284C7);
const Color kFieldOutDotColor = AppColors.brandDark;

/// A small white-ringed dot with a short label tag beside it ("F1 in",
/// "F1 out"). [labelLeft] puts the tag on the dot's left — used for "out" so an
/// in/out pair at the same spot shows both tags. Returns the icon and the anchor
/// that centres the DOT on the map point.
Future<({BitmapDescriptor icon, Offset anchor})> dotLabelMarkerIcon(
  BuildContext context,
  Color color,
  String label, {
  bool labelLeft = false,
}) async {
  final dpr = MediaQuery.of(context).devicePixelRatio;
  final dot = 14 * dpr; // dot incl. white ring
  final gap = 3 * dpr;
  final tp = TextPainter(
    text: TextSpan(
      text: label,
      style: TextStyle(fontSize: 10.5 * dpr, fontWeight: FontWeight.w800, color: Colors.white),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  final padH = 5 * dpr, padV = 2 * dpr;
  final pillW = tp.width + padH * 2;
  final pillH = tp.height + padV * 2;
  final w = dot + gap + pillW;
  final h = pillH > dot ? pillH : dot;

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final dotX = labelLeft ? w - dot / 2 : dot / 2;
  final dc = Offset(dotX, h / 2);
  canvas.drawCircle(dc, dot / 2, Paint()..color = Colors.white);
  canvas.drawCircle(dc, dot / 2 - 2.5 * dpr, Paint()..color = color);

  final pillX = labelLeft ? 0.0 : dot + gap;
  final pill = RRect.fromRectAndRadius(
    Rect.fromLTWH(pillX, (h - pillH) / 2, pillW, pillH),
    Radius.circular(pillH / 2),
  );
  canvas.drawRRect(pill, Paint()..color = color);
  canvas.drawRRect(
    pill,
    Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2 * dpr,
  );
  tp.paint(canvas, Offset(pillX + padH, (h - tp.height) / 2));

  final img = await recorder.endRecording().toImage(w.ceil(), h.ceil());
  final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
  return (
    icon: BitmapDescriptor.bytes(bytes!.buffer.asUint8List(), imagePixelRatio: dpr),
    anchor: Offset(dotX / w, 0.5),
  );
}

/// Small, clear map marker: a white-ringed coloured circle with a white flag
/// (the same flag used in the route captions/timelines), optionally with a tiny
/// number badge (e.g. visit 1, 2, …). ~26 dp, drawn crisp for the device.
/// Use with `anchor: const Offset(0.5, 0.5)`.
Future<BitmapDescriptor> flagMarkerIcon(
  BuildContext context,
  Color color, {
  String? badge,
}) async {
  final dpr = MediaQuery.of(context).devicePixelRatio;
  final d = 26 * dpr; // circle diameter
  final b = badge == null ? 0.0 : 14 * dpr;
  final w = d + b * 0.55;
  final h = d + b * 0.35;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final c = Offset(d / 2, h - d / 2);

  canvas.drawCircle(c.translate(0, dpr), d / 2 - dpr, Paint()..color = const Color(0x33000000));
  canvas.drawCircle(c, d / 2 - dpr, Paint()..color = Colors.white);
  canvas.drawCircle(c, d / 2 - 3 * dpr, Paint()..color = color);

  const icon = Icons.flag_rounded;
  final tp = TextPainter(
    text: TextSpan(
      text: String.fromCharCode(icon.codePoint),
      style: TextStyle(
        fontSize: 15 * dpr,
        fontFamily: icon.fontFamily,
        package: icon.fontPackage,
        color: Colors.white,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));

  if (badge != null) {
    final bc = Offset(w - b / 2, b / 2);
    canvas.drawCircle(bc, b / 2, Paint()..color = Colors.white);
    canvas.drawCircle(bc, b / 2 - 1.5 * dpr, Paint()..color = const Color(0xFF0F172A));
    final np = TextPainter(
      text: TextSpan(
        text: badge,
        style: TextStyle(fontSize: 8.5 * dpr, fontWeight: FontWeight.w900, color: Colors.white),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    np.paint(canvas, bc - Offset(np.width / 2, np.height / 2));
  }

  final img = await recorder.endRecording().toImage(w.ceil(), h.ceil());
  final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
  return BitmapDescriptor.bytes(bytes!.buffer.asUint8List(), imagePixelRatio: dpr);
}
