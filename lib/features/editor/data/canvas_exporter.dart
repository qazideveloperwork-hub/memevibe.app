import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Renders whatever is inside the [RepaintBoundary] identified by [key] to a
/// PNG. Used to snapshot the editor canvas (base image + filter + all
/// layers) exactly as it appears on screen, without any extra compositing
/// pass — the compositor already did that work for us on every frame.
Future<Uint8List> captureCanvas(
  GlobalKey key, {
  double pixelRatio = 3.0,
}) async {
  final boundary =
      key.currentContext!.findRenderObject() as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: pixelRatio);
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  return byteData!.buffer.asUint8List();
}
