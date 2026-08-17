import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:path_provider/path_provider.dart';

/// Crops and composites captured photos using dart:ui canvas drawing —
/// no extra native image-processing dependency needed.
class ImageCompositor {
  Future<ui.Image> _decode(String path) async {
    final bytes = await File(path).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  Future<File> _saveCanvas(
    ui.PictureRecorder recorder,
    int width,
    int height,
  ) async {
    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/composite_${DateTime.now().microsecondsSinceEpoch}.png',
    );
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    return file;
  }

  /// Center-crops [sourcePath] to [aspectRatio] (width / height) and saves
  /// the result as a new file.
  Future<File> cropToAspectRatio(String sourcePath, double aspectRatio) async {
    final image = await _decode(sourcePath);
    final srcW = image.width.toDouble();
    final srcH = image.height.toDouble();
    final srcRatio = srcW / srcH;

    late Rect cropRect;
    if (srcRatio > aspectRatio) {
      final newW = srcH * aspectRatio;
      cropRect = Rect.fromLTWH((srcW - newW) / 2, 0, newW, srcH);
    } else {
      final newH = srcW / aspectRatio;
      cropRect = Rect.fromLTWH(0, (srcH - newH) / 2, srcW, newH);
    }

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final destRect = Rect.fromLTWH(0, 0, cropRect.width, cropRect.height);
    canvas.drawImageRect(image, cropRect, destRect, Paint());

    return _saveCanvas(
      recorder,
      cropRect.width.round(),
      cropRect.height.round(),
    );
  }

  /// Composites [framePaths] into a single 9:16 canvas split into equal
  /// cells — 3 frames stack as horizontal thirds, 4 frames form a 2x2 grid.
  Future<File> composeGrid(List<String> framePaths) async {
    final images = await Future.wait(framePaths.map(_decode));
    const canvasWidth = 1080.0;
    const canvasHeight = 1920.0;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, canvasWidth, canvasHeight),
      Paint()..color = const Color(0xFF000000),
    );

    final cells = _cellsFor(images.length, canvasWidth, canvasHeight);
    for (var i = 0; i < images.length; i++) {
      _drawCovered(canvas, images[i], cells[i]);
    }

    return _saveCanvas(recorder, canvasWidth.round(), canvasHeight.round());
  }

  List<Rect> _cellsFor(int count, double width, double height) {
    if (count == 4) {
      final halfW = width / 2;
      final halfH = height / 2;
      return [
        Rect.fromLTWH(0, 0, halfW, halfH),
        Rect.fromLTWH(halfW, 0, halfW, halfH),
        Rect.fromLTWH(0, halfH, halfW, halfH),
        Rect.fromLTWH(halfW, halfH, halfW, halfH),
      ];
    }
    // 3 frames: equal horizontal thirds, stacked.
    final thirdH = height / 3;
    return List.generate(3, (i) => Rect.fromLTWH(0, i * thirdH, width, thirdH));
  }

  void _drawCovered(Canvas canvas, ui.Image image, Rect cell) {
    final srcRatio = image.width / image.height;
    final cellRatio = cell.width / cell.height;
    late Rect srcRect;
    if (srcRatio > cellRatio) {
      final newW = image.height * cellRatio;
      srcRect = Rect.fromLTWH(
        (image.width - newW) / 2,
        0,
        newW,
        image.height.toDouble(),
      );
    } else {
      final newH = image.width / cellRatio;
      srcRect = Rect.fromLTWH(
        0,
        (image.height - newH) / 2,
        image.width.toDouble(),
        newH,
      );
    }
    canvas.save();
    canvas.clipRect(cell);
    canvas.drawImageRect(image, srcRect, cell, Paint());
    canvas.restore();
  }
}
