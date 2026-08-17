import 'package:flutter/material.dart';

/// Base for anything draggable on the editor canvas — text, emoji (which is
/// just a [TextCanvasLayer] with a large font and no color styling), and
/// photo/sticker overlays.
sealed class CanvasLayer {
  const CanvasLayer({
    required this.id,
    required this.position,
    this.rotation = 0,
  });

  final String id;
  final Offset position;

  /// Radians.
  final double rotation;

  /// Applies the net result of one drag/pinch/rotate gesture: a new
  /// normalized [position], a multiplier on whatever this layer's "size"
  /// means (font size for text, box size for images), and a rotation delta.
  CanvasLayer transformed({
    required Offset position,
    required double scaleMultiplier,
    required double rotationDelta,
  });
}

/// One of the "most famous" Google Fonts families, offered in the text
/// style picker. Stored by name (not the TextStyle itself) so it survives
/// undo/redo and stays cheap to compare.
enum TextFontFamily {
  sora('Sora'),
  hankenGrotesk('Hanken Grotesk'),
  roboto('Roboto'),
  montserrat('Montserrat'),
  poppins('Poppins'),
  lato('Lato'),
  oswald('Oswald'),
  bebasNeue('Bebas Neue'),
  pacifico('Pacifico'),
  jetBrainsMono('JetBrains Mono'),
  // Added for status/story-style text — handwriting, script, and bold
  // display faces are what most status-text overlays actually reach for.
  caveat('Caveat'),
  dancingScript('Dancing Script'),
  playfairDisplay('Playfair Display'),
  anton('Anton'),
  permanentMarker('Permanent Marker'),
  greatVibes('Great Vibes'),
  righteous('Righteous'),
  kalam('Kalam'),
  indieFlower('Indie Flower'),
  amaticSc('Amatic SC');

  const TextFontFamily(this.googleFontsName);
  final String googleFontsName;
}

class TextCanvasLayer extends CanvasLayer {
  const TextCanvasLayer({
    required super.id,
    required super.position,
    required this.text,
    this.fontSize = 32,
    this.color = Colors.white,
    this.bold = true,
    this.italic = false,
    this.fontFamily = TextFontFamily.sora,
    this.animated = false,
    super.rotation,
  });

  static const minFontSize = 12.0;
  static const maxFontSize = 160.0;

  final String text;
  final double fontSize;
  final Color color;
  final bool bold;
  final bool italic;
  final TextFontFamily fontFamily;

  /// Set for emoji/stickers only (see [EditorController.addEmoji]) — gives
  /// them a gentle continuous bounce in the canvas instead of sitting
  /// static, without needing animated GIF assets (and the licensing
  /// questions that come with them).
  final bool animated;

  @override
  TextCanvasLayer transformed({
    required Offset position,
    required double scaleMultiplier,
    required double rotationDelta,
  }) => TextCanvasLayer(
    id: id,
    position: position,
    text: text,
    color: color,
    bold: bold,
    italic: italic,
    fontFamily: fontFamily,
    animated: animated,
    fontSize: (fontSize * scaleMultiplier).clamp(minFontSize, maxFontSize),
    rotation: rotation + rotationDelta,
  );

  /// Updates content/style in place — used by the text editor sheet, as
  /// opposed to [transformed] which is only for drag/pinch/rotate results.
  TextCanvasLayer withStyle({
    String? text,
    double? fontSize,
    Color? color,
    bool? bold,
    bool? italic,
    TextFontFamily? fontFamily,
  }) => TextCanvasLayer(
    id: id,
    position: position,
    rotation: rotation,
    animated: animated,
    fontSize: fontSize ?? this.fontSize,
    text: text ?? this.text,
    color: color ?? this.color,
    bold: bold ?? this.bold,
    italic: italic ?? this.italic,
    fontFamily: fontFamily ?? this.fontFamily,
  );
}

class ImageCanvasLayer extends CanvasLayer {
  const ImageCanvasLayer({
    required super.id,
    required super.position,
    required this.path,
    this.size = 120,
    super.rotation,
  });

  static const minSize = 40.0;
  static const maxSize = 400.0;

  final String path;
  final double size;

  @override
  ImageCanvasLayer transformed({
    required Offset position,
    required double scaleMultiplier,
    required double rotationDelta,
  }) => ImageCanvasLayer(
    id: id,
    position: position,
    path: path,
    size: (size * scaleMultiplier).clamp(minSize, maxSize),
    rotation: rotation + rotationDelta,
  );
}
