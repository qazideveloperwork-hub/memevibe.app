import 'dart:io';

import 'package:google_mlkit_selfie_segmentation/google_mlkit_selfie_segmentation.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

/// Runs on-device person segmentation (Google ML Kit's selfie segmenter) on
/// a photo the user just took or picked of *themselves*, and returns the
/// path to a new PNG with everything but the person made transparent —
/// turning it into a droppable sticker layer. Nothing leaves the device.
///
/// Returns null if no photo/person could be confidently extracted.
Future<String?> extractSelfieCutout(String imagePath) async {
  final segmenter = SelfieSegmenter(
    mode: SegmenterMode.single,
    enableRawSizeMask: false,
  );
  try {
    final mask = await segmenter.processImage(InputImage.fromFilePath(imagePath));
    if (mask == null) return null;

    final original = img.decodeImage(await File(imagePath).readAsBytes());
    if (original == null) return null;

    // enableRawSizeMask: false means ML Kit already rescaled the mask to
    // the input image's own dimensions, so mask and image pixels line up
    // 1:1 without any extra resampling on our end — resizing here is only
    // a safety net if that assumption ever doesn't hold on some device.
    final source = (original.width == mask.width && original.height == mask.height)
        ? original
        : img.copyResize(original, width: mask.width, height: mask.height);

    final cutout = img.Image(
      width: mask.width,
      height: mask.height,
      numChannels: 4,
    );
    for (var y = 0; y < mask.height; y++) {
      for (var x = 0; x < mask.width; x++) {
        final pixel = source.getPixel(x, y);
        final confidence = mask.confidences[y * mask.width + x].clamp(0.0, 1.0);
        cutout.setPixelRgba(x, y, pixel.r, pixel.g, pixel.b, confidence * 255);
      }
    }

    final dir = await getTemporaryDirectory();
    final outPath =
        '${dir.path}/selfie_cutout_${DateTime.now().microsecondsSinceEpoch}.png';
    await File(outPath).writeAsBytes(img.encodePng(cutout));
    return outPath;
  } finally {
    await segmenter.close();
  }
}
