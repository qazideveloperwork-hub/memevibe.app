import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:audioplayers/audioplayers.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/tap_scale.dart';
import '../../auth/data/auth_controller.dart';
import '../../create/domain/camera_filter.dart';
import '../../create/domain/captured_media.dart';
import '../data/canvas_exporter.dart';
import '../data/editor_controller.dart';
import '../data/selfie_cutout.dart';
import '../data/video_exporter.dart';
import '../data/video_source_exporter.dart';
import '../domain/audio_track.dart';
import '../domain/canvas_layer.dart';
import '../domain/editor_state.dart';
import 'audio_sheet.dart';
import 'export_sheet.dart';
import 'video_export_progress_sheet.dart';

const _trashZoneFraction = 0.85;

// One full emoji bounce cycle for the export overlay sequence — 15 frames
// at 10fps is a 1.5s loop, close to _AnimatedEmoji's live 1.8s cycle
// without needing them to match exactly.
const _overlayAnimFrameCount = 15;
const _overlayAnimFramerate = 10.0;

enum _InlinePanel { none, filter, adjust }

class EditorScreen extends ConsumerStatefulWidget {
  const EditorScreen({super.key, required this.media});

  final CapturedMedia media;

  @override
  ConsumerState<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends ConsumerState<EditorScreen> {
  _InlinePanel _activePanel = _InlinePanel.none;
  bool _isExporting = false;
  final _canvasKey = GlobalKey();
  final _audioIndicatorKey = GlobalKey<_AudioIndicatorState>();

  // Gesture handling lives here at the canvas level (not per-layer) so a
  // pinch/rotate works no matter where on the canvas the second finger
  // lands, as long as a layer is selected — a per-layer GestureDetector
  // requires *both* fingers to start within that layer's own (often tiny)
  // bounds, which was unreliable for short text.
  String? _activeLayerId;
  Offset _dragOffset = Offset.zero;
  double _scale = 1.0;
  double _rotation = 0;
  bool _overTrash = false;

  (double min, double max) _sizeBoundsOf(CanvasLayer layer) => switch (layer) {
    TextCanvasLayer() => (
      TextCanvasLayer.minFontSize,
      TextCanvasLayer.maxFontSize,
    ),
    ImageCanvasLayer() => (ImageCanvasLayer.minSize, ImageCanvasLayer.maxSize),
  };

  double _baseSizeOf(CanvasLayer layer) => switch (layer) {
    TextCanvasLayer(:final fontSize) => fontSize,
    ImageCanvasLayer(:final size) => size,
  };

  /// A generous approximate bounding box for hit-testing (not for layout) —
  /// rotation is ignored for simplicity, and everything has a comfortable
  /// minimum so short text/emoji are easy to grab.
  Size _hitBoxOf(CanvasLayer layer) => switch (layer) {
    TextCanvasLayer(:final text, :final fontSize) => Size(
      math.max(48, fontSize * text.length * 0.62),
      math.max(48, fontSize * 1.4),
    ),
    ImageCanvasLayer(:final size) => Size(
      math.max(48, size),
      math.max(48, size),
    ),
  };

  CanvasLayer? _hitTestLayer(
    Offset point,
    List<CanvasLayer> layers,
    Size canvasSize,
  ) {
    for (final layer in layers.reversed) {
      final topLeft = Offset(
        layer.position.dx * canvasSize.width,
        layer.position.dy * canvasSize.height,
      );
      final box = _hitBoxOf(layer);
      if (Rect.fromLTWH(
        topLeft.dx,
        topLeft.dy,
        box.width,
        box.height,
      ).contains(point)) {
        return layer;
      }
    }
    return null;
  }

  void _onScaleStart(
    ScaleStartDetails details,
    EditorCanvas canvas,
    EditorController controller,
  ) {
    _selectAtPoint(details.localFocalPoint, canvas, controller);
  }

  // For video media the canvas GestureDetector also carries onTap (play/
  // pause toggle), which competes with onScaleStart in the same gesture
  // arena: a stationary tap with no movement resolves to the tap
  // recognizer, not the scale one, so onScaleStart's selection logic never
  // runs and a tap meant to deselect a layer just toggles playback instead.
  // onTapDown fires on every touch regardless of which recognizer
  // ultimately wins, so selection is handled here instead — onScaleStart
  // still calls into the same method for the drag case, which is a
  // harmless redundant call, not a behavior change.
  void _onTapDown(
    TapDownDetails details,
    EditorCanvas canvas,
    EditorController controller,
  ) {
    _selectAtPoint(details.localPosition, canvas, controller);
  }

  void _selectAtPoint(
    Offset point,
    EditorCanvas canvas,
    EditorController controller,
  ) {
    final hit = _hitTestLayer(point, canvas.layers, _lastCanvasSize!);
    setState(() {
      _activeLayerId = hit?.id;
      _dragOffset = Offset.zero;
      _scale = 1.0;
      _rotation = 0;
      _overTrash = false;
    });
    controller.selectLayer(hit?.id);
  }

  void _onScaleUpdate(ScaleUpdateDetails details, EditorCanvas canvas) {
    final id = _activeLayerId;
    if (id == null) return;
    final layer = canvas.layers.firstWhere((l) => l.id == id);
    final baseTopY = layer.position.dy * _lastCanvasSize!.height;
    setState(() {
      _dragOffset += details.focalPointDelta;
      _scale = details.scale;
      _rotation = details.rotation;
      _overTrash =
          (baseTopY + _dragOffset.dy) >
          _lastCanvasSize!.height * _trashZoneFraction;
    });
  }

  void _onScaleEnd(EditorCanvas canvas, EditorController controller) {
    final id = _activeLayerId;
    if (id == null) return;
    final layer = canvas.layers.firstWhere((l) => l.id == id);

    if (_overTrash) {
      controller.removeLayer(id);
    } else {
      final basePosition = Offset(
        layer.position.dx * _lastCanvasSize!.width,
        layer.position.dy * _lastCanvasSize!.height,
      );
      final newDx =
          ((basePosition.dx + _dragOffset.dx) / _lastCanvasSize!.width).clamp(
            0.0,
            1.0,
          );
      final newDy =
          ((basePosition.dy + _dragOffset.dy) / _lastCanvasSize!.height).clamp(
            0.0,
            1.0,
          );
      final (minSize, maxSize) = _sizeBoundsOf(layer);
      final baseSize = _baseSizeOf(layer);
      final clampedSize = (baseSize * _scale).clamp(minSize, maxSize);
      controller.transformLayer(
        id,
        Offset(newDx, newDy),
        clampedSize / baseSize,
        _rotation,
      );
    }

    setState(() {
      _activeLayerId = null;
      _dragOffset = Offset.zero;
      _scale = 1.0;
      _rotation = 0;
      _overTrash = false;
    });
  }

  Size? _lastCanvasSize;

  VideoPlayerController? _videoController;
  bool _videoReady = false;
  int? _videoDurationMs;
  String? _videoPosterPath;
  bool _capturingPoster = false;
  final _posterCaptureKey = GlobalKey();

  /// Transient — set true only while grabbing the layer-stack-only overlay
  /// PNG for video export burn-in, so the base media/backdrop/dim tint
  /// don't leak into what should be a transparent overlay.
  bool _captureOverlayOnly = false;

  /// Transient — non-null only while capturing one frame of the animated
  /// overlay sequence (see [_exportVideo]). 0 to 1, position within one
  /// bounce cycle for that specific captured frame.
  double? _emojiCapturePhase;

  @override
  void initState() {
    super.initState();
    if (widget.media.type == CapturedMediaType.video) {
      _initVideo();
    }
  }

  Future<void> _initVideo() async {
    final controller = VideoPlayerController.file(File(widget.media.path));
    _videoController = controller;
    await controller.initialize();
    await controller.setLooping(true);
    if (!mounted) return;
    setState(() {
      _videoReady = true;
      _videoDurationMs = controller.value.duration.inMilliseconds;
    });
    await _capturePosterFrame();
  }

  /// Grabs a single raw (unfiltered, no overlays) frame for the filter-strip
  /// swatch thumbnails — `Image.file` can't decode a video file directly, so
  /// this reuses [captureCanvas] on a briefly-mounted, invisible-but-painted
  /// (Opacity 0, not Offstage — Offstage skips painting entirely) copy of
  /// the video widget instead of pulling in a separate thumbnail package.
  Future<void> _capturePosterFrame() async {
    final controller = _videoController;
    if (controller == null || !mounted) return;
    setState(() => _capturingPoster = true);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    try {
      final bytes = await captureCanvas(_posterCaptureKey, pixelRatio: 1.0);
      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/video_poster_${DateTime.now().microsecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(bytes);
      if (!mounted) return;
      setState(() => _videoPosterPath = file.path);
    } catch (_) {
      // Filter strip falls back to the raw video path (which Image.file
      // can't decode either, but degrades to its own errorBuilder) — not
      // worth surfacing an error for a thumbnail-only failure.
    } finally {
      if (mounted) setState(() => _capturingPoster = false);
    }
  }

  void _toggleVideoPlayback() {
    final controller = _videoController;
    if (controller == null || !_videoReady) return;
    setState(() {
      if (controller.value.isPlaying) {
        controller.pause();
      } else {
        controller.play();
      }
    });
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  /// Dispatches to [_buildBaseImage] or [_buildBaseVideo] depending on what
  /// kind of media this editor session was opened with.
  Widget _buildBaseMedia(EditorCanvas canvas, {required BoxFit fit}) {
    return widget.media.type == CapturedMediaType.video
        ? _buildBaseVideo(canvas, fit: fit)
        : _buildBaseImage(canvas, fit: fit);
  }

  /// The base photo with filter/flip/straighten/rotate applied. Used twice —
  /// once as a blurred [BoxFit.cover] backdrop to fill the letterbox bars,
  /// once as the sharp [BoxFit.contain] foreground — so both stay in sync
  /// with every adjustment automatically instead of duplicating state.
  Widget _buildBaseImage(EditorCanvas canvas, {required BoxFit fit}) {
    return RotatedBox(
      quarterTurns: canvas.rotationQuarterTurns,
      child: ColorFiltered(
        colorFilter: ColorFilter.matrix(
          CameraFilterOption.withIntensity(
            canvas.filter.matrix,
            canvas.filterIntensity,
          ),
        ),
        child: Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..rotateZ(canvas.straightenDegrees * math.pi / 180)
            ..scaleByDouble(
              canvas.flipHorizontal ? -1.0 : 1.0,
              canvas.flipVertical ? -1.0 : 1.0,
              1.0,
              1.0,
            ),
          child: Image.file(
            File(widget.media.path),
            fit: fit,
            errorBuilder: (context, error, stackTrace) => const ColoredBox(
              color: AppColors.surfaceContainerHighest,
              child: Center(
                child: Icon(
                  Icons.broken_image_outlined,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Same rotate/filter/straighten/flip wrapper chain as [_buildBaseImage],
  /// just with a video texture as the innermost child instead of a static
  /// image — every adjustment already works here for free.
  Widget _buildBaseVideo(EditorCanvas canvas, {required BoxFit fit}) {
    final controller = _videoController;
    return RotatedBox(
      quarterTurns: canvas.rotationQuarterTurns,
      child: ColorFiltered(
        colorFilter: ColorFilter.matrix(
          CameraFilterOption.withIntensity(
            canvas.filter.matrix,
            canvas.filterIntensity,
          ),
        ),
        child: Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..rotateZ(canvas.straightenDegrees * math.pi / 180)
            ..scaleByDouble(
              canvas.flipHorizontal ? -1.0 : 1.0,
              canvas.flipVertical ? -1.0 : 1.0,
              1.0,
              1.0,
            ),
          child: (!_videoReady || controller == null)
              ? const ColoredBox(
                  color: AppColors.surfaceContainerHighest,
                  child: Center(
                    child: CircularProgressIndicator(color: Colors.white54),
                  ),
                )
              : FittedBox(
                  fit: fit,
                  child: SizedBox(
                    width: controller.value.size.width,
                    height: controller.value.size.height,
                    child: VideoPlayer(controller),
                  ),
                ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(editorControllerProvider);
    final controller = ref.read(editorControllerProvider.notifier);
    final canvas = state.canvas;

    // Keeps the live preview's actual playback volume in sync with the
    // Trim panel's slider — that slider only fed the export pipeline
    // before, so lowering/muting it had no audible effect until export.
    // Runs on every build (undo/redo included, not just the slider drag)
    // so it can't drift out of sync with canvas state. video_player only
    // supports [0,1] for real playback — the boosted 1.0-1.5 range is
    // export-only, via ffmpeg's volume filter.
    if (widget.media.type == CapturedMediaType.video &&
        _videoController != null) {
      _videoController!.setVolume(canvas.originalAudioVolume.clamp(0.0, 1.0));
    }

    return PopScope(
      canPop: _activePanel == _InlinePanel.none,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        setState(() => _activePanel = _InlinePanel.none);
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.containerPadding,
                  vertical: AppSpacing.stackSm,
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(
                        Icons.arrow_back,
                        color: AppColors.primary,
                      ),
                      onPressed: () => context.pop(),
                    ),
                    Expanded(
                      child: Text(
                        'Edit',
                        textAlign: TextAlign.center,
                        style: AppTypography.headlineLgMobile,
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.undo,
                        color: state.canUndo
                            ? AppColors.primary
                            : Colors.white24,
                      ),
                      onPressed: state.canUndo ? controller.undo : null,
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.redo,
                        color: state.canRedo
                            ? AppColors.primary
                            : Colors.white24,
                      ),
                      onPressed: state.canRedo ? controller.redo : null,
                    ),
                    TextButton(
                      onPressed: _isExporting
                          ? null
                          : () => _onDone(controller, canvas),
                      child: _isExporting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Done'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Center(
                  child: AspectRatio(
                    aspectRatio: 9 / 16,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final canvasSize = constraints.biggest;
                          _lastCanvasSize = canvasSize;
                          return GestureDetector(
                            onTap: widget.media.type == CapturedMediaType.video
                                ? _toggleVideoPlayback
                                : null,
                            onTapDown: (details) =>
                                _onTapDown(details, canvas, controller),
                            onScaleStart: (details) =>
                                _onScaleStart(details, canvas, controller),
                            onScaleUpdate: (details) =>
                                _onScaleUpdate(details, canvas),
                            onScaleEnd: (_) => _onScaleEnd(canvas, controller),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                RepaintBoundary(
                                  key: _canvasKey,
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      // Media that isn't already 9:16 has
                                      // letterbox bars once BoxFit.contain
                                      // stops it from being cropped to fill.
                                      // Rather than leave those bars flat
                                      // gray, they're filled with a blurred,
                                      // zoomed-in copy of the same media
                                      // (the Instagram-Stories trick) — an
                                      // uncropped photo/video that doesn't
                                      // look like it's floating in empty
                                      // space.
                                      //
                                      // Skipped entirely while capturing the
                                      // overlay-only PNG for video export
                                      // burn-in — that capture needs a
                                      // transparent background with just the
                                      // layers on it, not the media/dim tint.
                                      if (!_captureOverlayOnly) ...[
                                        ImageFiltered(
                                          imageFilter: ui.ImageFilter.blur(
                                            sigmaX: 24,
                                            sigmaY: 24,
                                          ),
                                          child: _buildBaseMedia(
                                            canvas,
                                            fit: BoxFit.cover,
                                          ),
                                        ),
                                        Container(
                                          color: Colors.black.withValues(
                                            alpha: 0.35,
                                          ),
                                        ),
                                        _buildBaseMedia(
                                          canvas,
                                          fit: BoxFit.contain,
                                        ),
                                      ],
                                      for (final layer in canvas.layers)
                                        _DraggableLayer(
                                          key: ValueKey(layer.id),
                                          layer: layer,
                                          canvasSize: canvasSize,
                                          selected:
                                              canvas.selectedLayerId ==
                                              layer.id,
                                          isActive: _activeLayerId == layer.id,
                                          liveOffset: _activeLayerId == layer.id
                                              ? _dragOffset
                                              : Offset.zero,
                                          liveScale: _activeLayerId == layer.id
                                              ? _scale
                                              : 1.0,
                                          liveRotation:
                                              _activeLayerId == layer.id
                                              ? _rotation
                                              : 0,
                                          overTrash:
                                              _activeLayerId == layer.id &&
                                              _overTrash,
                                          emojiCapturePhase:
                                              _emojiCapturePhase,
                                        ),
                                    ],
                                  ),
                                ),
                                _TrashZone(
                                  visible: _activeLayerId != null,
                                  active: _overTrash,
                                ),
                                if (widget.media.type ==
                                        CapturedMediaType.video &&
                                    _videoReady)
                                  IgnorePointer(
                                    child: Center(
                                      child: AnimatedOpacity(
                                        duration: const Duration(
                                          milliseconds: 150,
                                        ),
                                        opacity:
                                            (_videoController
                                                        ?.value
                                                        .isPlaying ??
                                                    false)
                                                ? 0
                                                : 1,
                                        child: Container(
                                          padding: const EdgeInsets.all(
                                            AppSpacing.stackMd,
                                          ),
                                          decoration: const BoxDecoration(
                                            color: Colors.black45,
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(
                                            Icons.play_arrow,
                                            color: Colors.white,
                                            size: 40,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                if (_capturingPoster && _videoController != null)
                                  Positioned(
                                    left: 0,
                                    top: 0,
                                    child: Opacity(
                                      opacity: 0,
                                      child: SizedBox(
                                        width: _videoController!.value.size.width
                                            .clamp(1, 1080),
                                        height: _videoController!.value.size.height
                                            .clamp(1, 1920),
                                        child: RepaintBoundary(
                                          key: _posterCaptureKey,
                                          child: VideoPlayer(_videoController!),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                child: switch (_activePanel) {
                  _InlinePanel.filter => _FilterStrip(
                    imagePath: widget.media.type == CapturedMediaType.video
                        ? (_videoPosterPath ?? widget.media.path)
                        : widget.media.path,
                    selected: canvas.filter,
                    intensity: canvas.filterIntensity,
                    onSelected: controller.setFilter,
                    onIntensityLive: controller.setFilterIntensityLive,
                    onIntensityCommit: controller.commitFilterIntensity,
                  ),
                  _InlinePanel.adjust => _AdjustPanel(
                    canvas: canvas,
                    controller: controller,
                    videoDurationMs: _videoDurationMs,
                    videoController: _videoController,
                  ),
                  _InlinePanel.none => const SizedBox(width: double.infinity),
                },
              ),
              if (canvas.audioTrack != null)
                _AudioIndicator(
                  key: _audioIndicatorKey,
                  track: canvas.audioTrack!,
                  onTap: () => _promptForAudio(context, controller, canvas),
                ),
              _BottomToolbar(
                filtersActive: _activePanel == _InlinePanel.filter,
                audioActive: canvas.audioTrack != null,
                flipActive: _activePanel == _InlinePanel.adjust,
                onText: () {
                  setState(() => _activePanel = _InlinePanel.none);
                  _promptForText(context, controller, canvas);
                },
                onPhoto: () {
                  setState(() => _activePanel = _InlinePanel.none);
                  _pickPhotoOverlay(context, controller);
                },
                onFilter: () => setState(
                  () => _activePanel = _activePanel == _InlinePanel.filter
                      ? _InlinePanel.none
                      : _InlinePanel.filter,
                ),
                onSticker: () {
                  setState(() => _activePanel = _InlinePanel.none);
                  _promptForEmoji(context, controller);
                },
                onAudio: () {
                  setState(() => _activePanel = _InlinePanel.none);
                  _promptForAudio(context, controller, canvas);
                },
                onFlip: () => setState(
                  () => _activePanel = _activePanel == _InlinePanel.adjust
                      ? _InlinePanel.none
                      : _InlinePanel.adjust,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _promptForText(
    BuildContext context,
    EditorController controller,
    EditorCanvas canvas,
  ) async {
    TextCanvasLayer? existing;
    final selectedId = canvas.selectedLayerId;
    if (selectedId != null) {
      final match = canvas.layers.where((l) => l.id == selectedId);
      if (match.isNotEmpty && match.first is TextCanvasLayer) {
        existing = match.first as TextCanvasLayer;
      }
    }

    final textController = TextEditingController(text: existing?.text ?? '');
    var color = existing?.color ?? Colors.white;
    var bold = existing?.bold ?? true;
    var italic = existing?.italic ?? false;
    var fontFamily = existing?.fontFamily ?? TextFontFamily.sora;
    var fontSize = existing?.fontSize ?? 32.0;

    final result = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppColors.surfaceElevated,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: AppSpacing.containerPadding,
            right: AppSpacing.containerPadding,
            top: AppSpacing.stackSm,
            bottom:
                MediaQuery.of(context).viewInsets.bottom +
                MediaQuery.of(context).padding.bottom +
                AppSpacing.containerPadding,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Center(child: _SheetHandle()),
              const SizedBox(height: AppSpacing.stackMd),
              Text(
                existing != null ? 'Edit Text' : 'Add Text',
                style: AppTypography.headlineLgMobile,
              ),
              const SizedBox(height: AppSpacing.stackMd),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: textController,
                      autofocus: true,
                      // Live-reflects the bold/color/font pickers below so
                      // the user sees the effect before confirming, instead
                      // of the input always looking the same regardless of
                      // what they've picked.
                      style: GoogleFonts.getFont(
                        fontFamily.googleFontsName,
                        textStyle: TextStyle(
                          color: color,
                          fontWeight: bold ? FontWeight.w800 : FontWeight.w400,
                          fontStyle: italic ? FontStyle.italic : FontStyle.normal,
                          fontSize: 16,
                        ),
                      ),
                      cursorColor: color,
                      decoration: const InputDecoration(
                        hintText: 'Type something...',
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.stackSm),
                  TapScale(
                    onTap: () => Navigator.of(context).pop(true),
                    child: Container(
                      padding: const EdgeInsets.all(AppSpacing.stackSm),
                      decoration: const BoxDecoration(
                        color: AppColors.primaryContainer,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check,
                        color: AppColors.onPrimaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.stackMd),
              Row(
                children: [
                  TapScale(
                    onTap: () => setSheetState(() => bold = !bold),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.stackMd,
                        vertical: AppSpacing.stackSm,
                      ),
                      decoration: BoxDecoration(
                        color: bold
                            ? AppColors.primaryContainer
                            : AppColors.surfaceContainer,
                        borderRadius: BorderRadius.circular(AppRadius.full),
                      ),
                      child: Icon(
                        Icons.format_bold,
                        color: bold
                            ? AppColors.onPrimaryContainer
                            : AppColors.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.stackSm),
                  TapScale(
                    onTap: () => setSheetState(() => italic = !italic),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.stackMd,
                        vertical: AppSpacing.stackSm,
                      ),
                      decoration: BoxDecoration(
                        color: italic
                            ? AppColors.primaryContainer
                            : AppColors.surfaceContainer,
                        borderRadius: BorderRadius.circular(AppRadius.full),
                      ),
                      child: Icon(
                        Icons.format_italic,
                        color: italic
                            ? AppColors.onPrimaryContainer
                            : AppColors.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.stackMd),
                  Expanded(
                    child: SizedBox(
                      height: 40,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: TextFontFamily.values.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(width: AppSpacing.stackSm),
                        itemBuilder: (context, index) {
                          final family = TextFontFamily.values[index];
                          final isSelected = family == fontFamily;
                          return TapScale(
                            onTap: () =>
                                setSheetState(() => fontFamily = family),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.stackMd,
                              ),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? AppColors.primaryContainer
                                    : AppColors.surfaceContainer,
                                borderRadius: BorderRadius.circular(
                                  AppRadius.full,
                                ),
                              ),
                              child: Text(
                                family.googleFontsName,
                                style: GoogleFonts.getFont(
                                  family.googleFontsName,
                                  textStyle: TextStyle(
                                    fontSize: 13,
                                    color: isSelected
                                        ? AppColors.onPrimaryContainer
                                        : AppColors.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.stackMd),
              SizedBox(
                height: 36,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _textColorChoices.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(width: AppSpacing.stackSm),
                  itemBuilder: (context, index) {
                    final option = _textColorChoices[index];
                    final isSelected = option.toARGB32() == color.toARGB32();
                    return TapScale(
                      onTap: () => setSheetState(() => color = option),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: option,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelected
                                ? AppColors.primaryContainer
                                : Colors.white24,
                            width: isSelected ? 2.5 : 1,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: AppSpacing.stackMd),
              Row(
                children: [
                  const Icon(
                    Icons.format_size,
                    size: 18,
                    color: AppColors.onSurfaceVariant,
                  ),
                  Expanded(
                    child: Slider(
                      min: TextCanvasLayer.minFontSize,
                      max: TextCanvasLayer.maxFontSize,
                      value: fontSize.clamp(
                        TextCanvasLayer.minFontSize,
                        TextCanvasLayer.maxFontSize,
                      ),
                      activeColor: AppColors.primary,
                      onChanged: (v) => setSheetState(() => fontSize = v),
                    ),
                  ),
                  SizedBox(
                    width: 30,
                    child: Text(
                      fontSize.round().toString(),
                      textAlign: TextAlign.right,
                      style: AppTypography.labelCaps.copyWith(
                        color: AppColors.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (result != true || textController.text.trim().isEmpty) return;
    final finalText = textController.text.trim();
    if (existing != null) {
      controller.editText(
        existing.id,
        text: finalText,
        fontSize: fontSize,
        color: color,
        bold: bold,
        italic: italic,
        fontFamily: fontFamily,
      );
    } else {
      controller.addText(
        finalText,
        fontSize: fontSize,
        color: color,
        bold: bold,
        italic: italic,
        fontFamily: fontFamily,
      );
    }
  }

  Future<void> _pickPhotoOverlay(
    BuildContext context,
    EditorController controller,
  ) async {
    final media = await context.push<List<CapturedMedia>>('/create/gallery');
    if (media == null || media.isEmpty) return;
    final image = media.firstWhere(
      (m) => m.type == CapturedMediaType.image,
      orElse: () => media.first,
    );
    if (image.type != CapturedMediaType.image) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick a photo, not a video, to overlay')),
      );
      return;
    }
    controller.addImage(image.path);
  }

  Future<void> _promptForEmoji(
    BuildContext context,
    EditorController controller,
  ) async {
    final result = await showModalBottomSheet<_EmojiSheetResult>(
      context: context,
      backgroundColor: AppColors.surfaceElevated,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (context) => const _EmojiSheet(),
    );
    if (result is _EmojiPicked) {
      controller.addEmoji(result.emoji);
    } else if (result is _AddPhotoRequested) {
      if (!context.mounted) return;
      await _addSelfieSticker(context, controller);
    }
  }

  Future<void> _addSelfieSticker(
    BuildContext context,
    EditorController controller,
  ) async {
    final source = await showModalBottomSheet<_PhotoSource>(
      context: context,
      backgroundColor: AppColors.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (context) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.containerPadding),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Center(child: _SheetHandle()),
              const SizedBox(height: AppSpacing.stackMd),
              Text('Add My Photo', style: AppTypography.headlineLgMobile),
              const SizedBox(height: AppSpacing.stackSm),
              Text(
                "Take or pick a photo of yourself — we'll cut you out "
                'on-device, right on your phone.',
                style: AppTypography.bodyMd.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.stackMd),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.photo_camera),
                title: const Text('Camera'),
                onTap: () => Navigator.of(context).pop(_PhotoSource.camera),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.photo_library),
                title: const Text('Gallery'),
                onTap: () => Navigator.of(context).pop(_PhotoSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );
    if (source == null || !context.mounted) return;

    String? imagePath;
    if (source == _PhotoSource.camera) {
      final media = await context.push<CapturedMedia>('/create/camera');
      if (media != null && media.type == CapturedMediaType.image) {
        imagePath = media.path;
      }
    } else {
      final media = await context.push<List<CapturedMedia>>('/create/gallery');
      final image = media?.firstWhereOrNull(
        (m) => m.type == CapturedMediaType.image,
      );
      if (image != null) imagePath = image.path;
    }
    if (imagePath == null || !context.mounted) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          const Center(child: CircularProgressIndicator()),
    );
    try {
      final cutoutPath = await extractSelfieCutout(imagePath);
      if (context.mounted) Navigator.of(context).pop();
      if (cutoutPath == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Couldn't find a person in that photo"),
            ),
          );
        }
        return;
      }
      controller.addImage(cutoutPath);
    } catch (error) {
      if (context.mounted) Navigator.of(context).pop();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Couldn't process photo: $error")),
        );
      }
    }
  }

  Future<void> _promptForAudio(
    BuildContext context,
    EditorController controller,
    EditorCanvas canvas,
  ) async {
    final result = await showAudioSheet(context, existing: canvas.audioTrack);
    if (result == null) return;
    if (result.removed) {
      controller.removeAudioTrack();
    } else if (result.track != null) {
      controller.setAudioTrack(result.track!);
    }
  }

  Future<void> _onDone(EditorController controller, EditorCanvas canvas) async {
    _audioIndicatorKey.currentState?.stopPreview();

    if (widget.media.type == CapturedMediaType.video) {
      await _exportVideo(controller, canvas);
      return;
    }
    await _exportImage(controller, canvas);
  }

  Future<void> _exportImage(
    EditorController controller,
    EditorCanvas canvas,
  ) async {
    final audio = canvas.audioTrack;
    bool exportAsVideo = false;
    if (audio != null) {
      final choice = await showModalBottomSheet<bool>(
        context: context,
        backgroundColor: AppColors.surfaceElevated,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.lg),
          ),
        ),
        builder: (context) => _ExportChoiceSheet(),
      );
      if (choice == null) return;
      exportAsVideo = choice;
    }

    final previousSelection = canvas.selectedLayerId;
    controller.selectLayer(null);
    setState(() => _isExporting = true);
    try {
      // Let the frame without the selection border actually paint before
      // capturing, otherwise the boundary may still hold the previous frame.
      await WidgetsBinding.instance.endOfFrame;
      final bytes = await captureCanvas(_canvasKey);
      final dir = await getTemporaryDirectory();
      final stamp = DateTime.now().microsecondsSinceEpoch;
      final imageFile = File('${dir.path}/creation_$stamp.png');
      await imageFile.writeAsBytes(bytes);

      if (!exportAsVideo) {
        if (!mounted) return;
        await showExportSheet(context, file: imageFile, kind: ExportKind.image);
        return;
      }

      // A single static snapshot can't carry emoji bounce — same fix as the
      // video-source export path: capture one full bounce cycle as a short
      // frame sequence and let ffmpeg loop it for the whole clip.
      String? imageSequencePattern;
      final hasAnimatedLayer = canvas.layers.any(
        (l) => l is TextCanvasLayer && l.animated,
      );
      if (hasAnimatedLayer) {
        for (var i = 0; i < _overlayAnimFrameCount; i++) {
          setState(() => _emojiCapturePhase = i / _overlayAnimFrameCount);
          await WidgetsBinding.instance.endOfFrame;
          final frameBytes = await captureCanvas(_canvasKey);
          final frameFile = File(
            '${dir.path}/creation_${stamp}_${i.toString().padLeft(3, '0')}.png',
          );
          await frameFile.writeAsBytes(frameBytes);
        }
        setState(() => _emojiCapturePhase = null);
        await WidgetsBinding.instance.endOfFrame;
        imageSequencePattern = '${dir.path}/creation_${stamp}_%03d.png';
      }

      final videoOutputPath = '${dir.path}/creation_$stamp.mp4';
      if (!mounted) return;
      final videoFile = await showVideoExportProgress(
        context,
        job: (onProgress, onSessionId) => exportImageWithAudioToVideo(
          imagePath: imageFile.path,
          imageSequencePattern: imageSequencePattern,
          imageSequenceFramerate: _overlayAnimFramerate,
          audio: audio!,
          outputPath: videoOutputPath,
          onProgress: onProgress,
          onSessionId: onSessionId,
        ),
        subtitle: 'Muxing your photo with the audio track',
      );
      if (videoFile == null || !mounted) return;
      await showExportSheet(
        context,
        file: videoFile,
        kind: ExportKind.video,
        previewImage: imageFile,
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Couldn\'t export: $error')));
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
        if (previousSelection != null) {
          controller.selectLayer(previousSelection);
        }
      }
    }
  }

  Future<void> _exportVideo(
    EditorController controller,
    EditorCanvas canvas,
  ) async {
    final durationMs = _videoDurationMs;
    if (durationMs == null) return;

    final previousSelection = canvas.selectedLayerId;
    controller.selectLayer(null);
    _videoController?.pause();
    setState(() => _isExporting = true);
    try {
      await WidgetsBinding.instance.endOfFrame;
      final dir = await getTemporaryDirectory();
      final stamp = DateTime.now().microsecondsSinceEpoch;
      final videoOutputPath = '${dir.path}/creation_$stamp.mp4';

      // The overlay-only burn-in capture below hides the base video/image
      // (see `if (!_captureOverlayOnly)` in the canvas Stack) to grab a
      // transparent PNG of just the text/stickers — which flashes as a
      // blank black canvas for however long the capture takes. Showing the
      // progress dialog *before* running the capture, instead of after,
      // means that flash happens behind the dialog's scrim instead of
      // being fully exposed on screen for those first few seconds.
      if (!mounted) return;
      final videoFile = await showVideoExportProgress(
        context,
        job: (onProgress, onSessionId) async {
          // The dialog invokes this from its own initState, which is
          // mid-build — any setState below (toggling _captureOverlayOnly)
          // would hit "setState() called during build" if it ran
          // synchronously here, so yield a frame first.
          await WidgetsBinding.instance.endOfFrame;
          String? overlayPngPath;
          String? overlaySequencePattern;
          if (canvas.layers.isNotEmpty) {
            final hasAnimatedLayer = canvas.layers.any(
              (l) => l is TextCanvasLayer && l.animated,
            );
            if (hasAnimatedLayer) {
              // A single static frame can't carry emoji bounce, so instead
              // capture a short looping sequence — one full bounce cycle,
              // deterministically phased per frame via emojiCapturePhase —
              // and let ffmpeg loop it for the export's whole duration.
              // Non-animated layers are just identical across every frame,
              // which is wasteful but simple and correct.
              for (var i = 0; i < _overlayAnimFrameCount; i++) {
                setState(() {
                  _captureOverlayOnly = true;
                  _emojiCapturePhase = i / _overlayAnimFrameCount;
                });
                await WidgetsBinding.instance.endOfFrame;
                final frameBytes = await captureCanvas(_canvasKey);
                final frameFile = File(
                  '${dir.path}/overlay_${stamp}_${i.toString().padLeft(3, '0')}.png',
                );
                await frameFile.writeAsBytes(frameBytes);
              }
              setState(() {
                _captureOverlayOnly = false;
                _emojiCapturePhase = null;
              });
              await WidgetsBinding.instance.endOfFrame;
              overlaySequencePattern = '${dir.path}/overlay_${stamp}_%03d.png';
            } else {
              setState(() => _captureOverlayOnly = true);
              await WidgetsBinding.instance.endOfFrame;
              final overlayBytes = await captureCanvas(_canvasKey);
              setState(() => _captureOverlayOnly = false);
              await WidgetsBinding.instance.endOfFrame;
              final overlayFile = File('${dir.path}/overlay_$stamp.png');
              await overlayFile.writeAsBytes(overlayBytes);
              overlayPngPath = overlayFile.path;
            }
          }

          return exportVideoProject(
            sourceVideoPath: widget.media.path,
            trimStartMs: canvas.videoTrimStartMs,
            trimEndMs: canvas.effectiveVideoTrimEndMs(durationMs),
            filterMatrix: CameraFilterOption.withIntensity(
              canvas.filter.matrix,
              canvas.filterIntensity,
            ),
            isIdentityFilter:
                canvas.filter.name == CameraFilterOption.all.first.name ||
                canvas.filterIntensity <= 0,
            flipHorizontal: canvas.flipHorizontal,
            flipVertical: canvas.flipVertical,
            straightenDegrees: canvas.straightenDegrees,
            rotationQuarterTurns: canvas.rotationQuarterTurns,
            overlayPngPath: overlayPngPath,
            overlaySequencePattern: overlaySequencePattern,
            overlaySequenceFramerate: _overlayAnimFramerate,
            originalAudioVolume: canvas.originalAudioVolume,
            addedAudio: canvas.audioTrack,
            isPro: ref.read(authControllerProvider).user?.isPro ?? false,
            outputPath: videoOutputPath,
            onProgress: onProgress,
            onSessionId: onSessionId,
          );
        },
        subtitle: 'Trimming, filtering, and encoding your clip',
      );
      if (videoFile == null || !mounted) return;
      await showExportSheet(context, file: videoFile, kind: ExportKind.video);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Couldn\'t export: $error')));
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
        if (previousSelection != null) {
          controller.selectLayer(previousSelection);
        }
      }
    }
  }
}

class _ExportChoiceSheet extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.containerPadding,
        right: AppSpacing.containerPadding,
        top: AppSpacing.stackSm,
        bottom:
            MediaQuery.of(context).padding.bottom + AppSpacing.containerPadding,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Center(child: _SheetHandle()),
          const SizedBox(height: AppSpacing.stackMd),
          Text('Export As', style: AppTypography.headlineLgMobile),
          const SizedBox(height: AppSpacing.stackSm),
          Text(
            'Your audio track is attached — choose how to export.',
            style: AppTypography.bodyMd.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.stackLg),
          _ExportChoiceTile(
            icon: Icons.image_outlined,
            title: 'Image Only',
            subtitle: 'A photo, no sound',
            onTap: () => Navigator.of(context).pop(false),
          ),
          const SizedBox(height: AppSpacing.stackSm),
          _ExportChoiceTile(
            icon: Icons.movie_creation_outlined,
            title: 'Video (with audio)',
            subtitle: 'Your photo + audio track, muxed into an mp4',
            highlighted: true,
            onTap: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
  }
}

class _ExportChoiceTile extends StatelessWidget {
  const _ExportChoiceTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.highlighted = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool highlighted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TapScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.stackMd),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainer,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: highlighted
                ? AppColors.primaryContainer
                : AppColors.outlineVariant,
            width: highlighted ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: highlighted
                    ? AppColors.primaryContainer
                    : AppColors.surfaceContainerHigh,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: highlighted
                    ? AppColors.onPrimaryContainer
                    : AppColors.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: AppSpacing.stackMd),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: AppTypography.bodyMd.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: AppTypography.bodyMd.copyWith(
                      color: AppColors.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

const _textColorChoices = [
  Colors.white,
  Colors.black,
  Color(0xFFFF3B30),
  Color(0xFFFF9500),
  Color(0xFFFFCC00),
  Color(0xFF34C759),
  Color(0xFF00C7BE),
  Color(0xFF007AFF),
  Color(0xFFAF52DE),
  Color(0xFFFF2D55),
];

/// Inline panel (same slot as [_FilterStrip]) for flip + straighten — flip
/// is two instant-tap icon toggles rather than a modal sheet, since there's
/// nothing to configure beyond on/off; straighten needs a slider, so it
/// gets one, with live preview while dragging.
class _AdjustPanel extends StatefulWidget {
  const _AdjustPanel({
    required this.canvas,
    required this.controller,
    this.videoDurationMs,
    this.videoController,
  });

  final EditorCanvas canvas;
  final EditorController controller;

  /// Non-null only when the editor's source is a video — enables the trim
  /// section above the flip/straighten/rotate controls, which apply to
  /// both media kinds identically.
  final int? videoDurationMs;
  final VideoPlayerController? videoController;

  @override
  State<_AdjustPanel> createState() => _AdjustPanelState();
}

class _AdjustPanelState extends State<_AdjustPanel> {
  double? _dragStartDegrees;
  int? _trimDragStartMs;
  int? _trimDragEndMs;
  double? _originalVolumeDragStart;

  @override
  Widget build(BuildContext context) {
    final canvas = widget.canvas;
    final durationMs = widget.videoDurationMs;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.containerPadding,
        vertical: AppSpacing.stackSm,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (durationMs != null) ...[
            Row(
              children: [
                const Icon(
                  Icons.content_cut,
                  size: 18,
                  color: AppColors.onSurfaceVariant,
                ),
                const SizedBox(width: AppSpacing.stackSm),
                Text('Trim', style: AppTypography.bodyMd),
                const Spacer(),
                Text(
                  '${_formatTrimMs(canvas.videoTrimStartMs)} – '
                  '${_formatTrimMs(canvas.effectiveVideoTrimEndMs(durationMs))}',
                  style: AppTypography.labelCaps.copyWith(
                    color: AppColors.onSurfaceVariant,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
            RangeSlider(
              min: 0,
              max: durationMs.toDouble(),
              values: RangeValues(
                canvas.videoTrimStartMs.toDouble().clamp(
                  0,
                  durationMs.toDouble(),
                ),
                canvas
                    .effectiveVideoTrimEndMs(durationMs)
                    .toDouble()
                    .clamp(0, durationMs.toDouble()),
              ),
              activeColor: AppColors.primary,
              onChangeStart: (values) {
                _trimDragStartMs = values.start.round();
                _trimDragEndMs = values.end.round();
              },
              onChanged: (values) {
                widget.controller.setVideoTrimLive(
                  values.start.round(),
                  values.end.round(),
                );
                widget.videoController?.seekTo(
                  Duration(milliseconds: values.start.round()),
                );
              },
              onChangeEnd: (_) => widget.controller.commitVideoTrim(
                _trimDragStartMs ?? 0,
                _trimDragEndMs ?? durationMs,
              ),
            ),
            Text(
              'Original Video Volume',
              style: AppTypography.labelCaps.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
            ),
            Row(
              children: [
                TapScale(
                  // Tap the icon to quickly toggle mute/restore, same
                  // shortcut most media apps offer alongside the slider.
                  onTap: () {
                    final wasZero = canvas.originalAudioVolume == 0;
                    widget.controller.setOriginalAudioVolumeLive(
                      wasZero ? 1.0 : 0.0,
                    );
                    widget.controller.commitOriginalAudioVolume(
                      canvas.originalAudioVolume,
                    );
                  },
                  child: Icon(
                    canvas.originalAudioVolume == 0
                        ? Icons.volume_off
                        : Icons.volume_up,
                    size: 18,
                    color: canvas.originalAudioVolume == 0
                        ? AppColors.error
                        : AppColors.onSurfaceVariant,
                  ),
                ),
                Expanded(
                  child: Slider(
                    min: 0,
                    max: 1.5,
                    value: canvas.originalAudioVolume,
                    activeColor: AppColors.primary,
                    onChangeStart: (v) => _originalVolumeDragStart = v,
                    onChanged: widget.controller.setOriginalAudioVolumeLive,
                    onChangeEnd: (_) =>
                        widget.controller.commitOriginalAudioVolume(
                          _originalVolumeDragStart ?? 1.0,
                        ),
                  ),
                ),
                SizedBox(
                  width: 34,
                  child: Text(
                    '${(canvas.originalAudioVolume * 100).round()}%',
                    textAlign: TextAlign.right,
                    style: AppTypography.labelCaps.copyWith(
                      color: AppColors.onSurfaceVariant,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.stackSm),
            const Divider(color: AppColors.outlineVariant),
            const SizedBox(height: AppSpacing.stackSm),
          ],
          Row(
            children: [
              Expanded(
                child: _FlipToggleButton(
                  icon: Icons.flip,
                  label: 'Flip Horizontal',
                  active: canvas.flipHorizontal,
                  onTap: widget.controller.toggleFlipHorizontal,
                ),
              ),
              const SizedBox(width: AppSpacing.stackSm),
              Expanded(
                child: _FlipToggleButton(
                  icon: Icons.flip,
                  iconTurns: 1,
                  label: 'Flip Vertical',
                  active: canvas.flipVertical,
                  onTap: widget.controller.toggleFlipVertical,
                ),
              ),
              const SizedBox(width: AppSpacing.stackSm),
              Expanded(
                child: _FlipToggleButton(
                  icon: Icons.rotate_90_degrees_ccw,
                  label: 'Rotate 90°',
                  active: canvas.rotationQuarterTurns != 0,
                  onTap: widget.controller.rotate90,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.stackSm),
          Row(
            children: [
              const Icon(
                Icons.straighten,
                size: 18,
                color: AppColors.onSurfaceVariant,
              ),
              const SizedBox(width: AppSpacing.stackSm),
              Expanded(
                child: Slider(
                  min: -45,
                  max: 45,
                  value: canvas.straightenDegrees,
                  activeColor: AppColors.primaryContainer,
                  onChangeStart: (v) => _dragStartDegrees = v,
                  onChanged: widget.controller.setStraightenLive,
                  onChangeEnd: (_) => widget.controller.commitStraighten(
                    _dragStartDegrees ?? 0,
                  ),
                ),
              ),
              SizedBox(
                width: 40,
                child: Text(
                  '${canvas.straightenDegrees.round()}°',
                  textAlign: TextAlign.right,
                  style: AppTypography.labelCaps.copyWith(
                    color: AppColors.onSurfaceVariant,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatTrimMs(int ms) {
    final total = Duration(milliseconds: ms);
    final minutes = total.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = total.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

class _FlipToggleButton extends StatelessWidget {
  const _FlipToggleButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.iconTurns = 0,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  final int iconTurns;

  @override
  Widget build(BuildContext context) {
    return TapScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.stackSm),
        decoration: BoxDecoration(
          color: active
              ? AppColors.primaryContainer.withValues(alpha: 0.15)
              : AppColors.surfaceContainer,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: active
                ? AppColors.primaryContainer
                : AppColors.outlineVariant,
            width: active ? 1.5 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RotatedBox(
              quarterTurns: iconTurns,
              child: Icon(
                icon,
                size: 20,
                color: active
                    ? AppColors.primaryContainer
                    : AppColors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: AppTypography.labelCaps.copyWith(
                fontSize: 9,
                color: active
                    ? AppColors.primaryContainer
                    : AppColors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 4,
      decoration: BoxDecoration(
        color: Colors.white24,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

// Plain Unicode characters — rendered by the OS font, not downloaded
// images, so there's no licensing concern at all (unlike GIF stickers,
// which need either a licensed API or admin-curated assets).
const _emojiCategories = <String, List<String>>{
  'Smileys': [
    '😀',
    '😃',
    '😄',
    '😁',
    '😆',
    '😅',
    '🤣',
    '😂',
    '🙂',
    '🙃',
    '😉',
    '😊',
    '😇',
    '🥰',
    '😍',
    '🤩',
    '😘',
    '😗',
    '😚',
    '😙',
    '😋',
    '😛',
    '😜',
    '🤪',
    '😝',
    '🤑',
    '🤗',
    '🤭',
    '🤫',
    '🤔',
    '🤐',
    '😐',
    '😑',
    '😶',
    '😏',
    '😒',
    '🙄',
    '😬',
    '😌',
    '😴',
    '🥳',
    '😎',
    '🤓',
    '🧐',
    '😭',
    '😱',
    '💀',
    '🤡',
  ],
  'Gestures': [
    '👍',
    '👎',
    '👌',
    '🤌',
    '✌️',
    '🤞',
    '🤟',
    '🤘',
    '🤙',
    '👈',
    '👉',
    '👆',
    '👇',
    '☝️',
    '✋',
    '🤚',
    '🖐️',
    '🖖',
    '👋',
    '🤝',
    '🙏',
    '💪',
    '👏',
    '🙌',
    '👐',
    '🤲',
    '🫶',
    '💃',
    '🕺',
    '🤦',
  ],
  'Hearts': [
    '❤️',
    '🧡',
    '💛',
    '💚',
    '💙',
    '💜',
    '🖤',
    '🤍',
    '🤎',
    '💔',
    '❣️',
    '💕',
    '💞',
    '💓',
    '💗',
    '💖',
    '💘',
    '💝',
    '💟',
    '💌',
  ],
  'Animals': [
    '🐶',
    '🐱',
    '🐭',
    '🐹',
    '🐰',
    '🦊',
    '🐻',
    '🐼',
    '🐨',
    '🐯',
    '🦁',
    '🐮',
    '🐷',
    '🐸',
    '🐵',
    '🙈',
    '🙉',
    '🙊',
    '🐔',
    '🐧',
    '🐦',
    '🐤',
    '🦆',
    '🦉',
    '🐺',
    '🐗',
    '🐴',
    '🦄',
    '🐝',
    '🐛',
  ],
  'Food': [
    '🍏',
    '🍎',
    '🍐',
    '🍊',
    '🍋',
    '🍌',
    '🍉',
    '🍇',
    '🍓',
    '🫐',
    '🍈',
    '🍒',
    '🍑',
    '🥭',
    '🍍',
    '🥥',
    '🥝',
    '🍅',
    '🍆',
    '🥑',
    '🌽',
    '🥕',
    '🍕',
    '🍔',
    '🍟',
    '🌭',
    '🍿',
    '🧁',
    '🍰',
    '🎂',
  ],
  'Activities': [
    '⚽',
    '🏀',
    '🏈',
    '⚾',
    '🎾',
    '🏐',
    '🏉',
    '🎱',
    '🏓',
    '🏸',
    '🥊',
    '🎮',
    '🎲',
    '🎯',
    '🎨',
    '🎬',
    '🎤',
    '🎧',
    '🎸',
    '🎉',
    '🎊',
    '🎁',
    '🏆',
    '🥇',
    '🔥',
    '✨',
    '💯',
    '💥',
    '⚡',
    '🌟',
  ],
  'Travel': [
    '🚗',
    '🚕',
    '🚙',
    '🚌',
    '🚓',
    '🚑',
    '🚒',
    '🚲',
    '🛵',
    '✈️',
    '🚀',
    '🚁',
    '⛵',
    '🚢',
    '🗺️',
    '🏖️',
    '🏔️',
    '🌋',
    '🗽',
    '🎡',
  ],
  'Flags': [
    '🇺🇸',
    '🇬🇧',
    '🇨🇦',
    '🇲🇽',
    '🇧🇷',
    '🇦🇷',
    '🇫🇷',
    '🇩🇪',
    '🇮🇹',
    '🇪🇸',
    '🇵🇹',
    '🇳🇱',
    '🇷🇺',
    '🇹🇷',
    '🇸🇦',
    '🇦🇪',
    '🇪🇬',
    '🇳🇬',
    '🇿🇦',
    '🇮🇳',
    '🇵🇰',
    '🇧🇩',
    '🇨🇳',
    '🇯🇵',
    '🇰🇷',
    '🇮🇩',
    '🇵🇭',
    '🇹🇭',
    '🇻🇳',
    '🇦🇺',
    '🇳🇿',
  ],
};

sealed class _EmojiSheetResult {}

class _EmojiPicked extends _EmojiSheetResult {
  _EmojiPicked(this.emoji);
  final String emoji;
}

class _AddPhotoRequested extends _EmojiSheetResult {}

enum _PhotoSource { camera, gallery }

class _EmojiSheet extends StatefulWidget {
  const _EmojiSheet();

  @override
  State<_EmojiSheet> createState() => _EmojiSheetState();
}

class _EmojiSheetState extends State<_EmojiSheet> {
  String _category = 'Smileys';

  @override
  Widget build(BuildContext context) {
    final emojis = _emojiCategories[_category]!;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          left: AppSpacing.containerPadding,
          right: AppSpacing.containerPadding,
          top: AppSpacing.stackSm,
          bottom: AppSpacing.containerPadding,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Center(child: _SheetHandle()),
            const SizedBox(height: AppSpacing.stackMd),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Add Emoji', style: AppTypography.headlineLgMobile),
                TapScale(
                  onTap: () => Navigator.of(
                    context,
                  ).pop(_AddPhotoRequested()),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.stackMd,
                      vertical: AppSpacing.stackSm,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primaryContainer,
                      borderRadius: BorderRadius.circular(AppRadius.full),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.face_retouching_natural,
                          size: 16,
                          color: AppColors.onPrimaryContainer,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'My Photo',
                          style: AppTypography.labelCaps.copyWith(
                            color: AppColors.onPrimaryContainer,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.stackMd),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final category in _emojiCategories.keys) ...[
                    _FilterTabChip(
                      label: category,
                      selected: _category == category,
                      onTap: () => setState(() => _category = category),
                    ),
                    const SizedBox(width: AppSpacing.stackSm),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.stackMd),
            SizedBox(
              height: 260,
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 6,
                  mainAxisSpacing: AppSpacing.stackSm,
                  crossAxisSpacing: AppSpacing.stackSm,
                ),
                itemCount: emojis.length,
                itemBuilder: (context, index) => TapScale(
                  onTap: () =>
                      Navigator.of(context).pop(_EmojiPicked(emojis[index])),
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainer,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: Center(
                      child: Text(
                        emojis[index],
                        style: const TextStyle(fontSize: 26),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Purely presentational — all gesture handling happens once, at the
/// canvas level, in [_EditorScreenState]. When [isActive], renders the
/// live in-progress transform; otherwise renders the committed layer state.
class _DraggableLayer extends StatelessWidget {
  const _DraggableLayer({
    super.key,
    required this.layer,
    required this.canvasSize,
    required this.selected,
    required this.isActive,
    required this.liveOffset,
    required this.liveScale,
    required this.liveRotation,
    required this.overTrash,
    this.emojiCapturePhase,
  });

  final CanvasLayer layer;
  final Size canvasSize;
  final bool selected;
  final bool isActive;
  final Offset liveOffset;
  final double liveScale;
  final double liveRotation;
  final bool overTrash;

  /// Non-null only while capturing one frame of the animated-overlay
  /// sequence for video export (see [_EditorScreenState._exportVideo]) — 0
  /// to 1 across one bounce cycle. Bypasses the live [_AnimatedEmoji]
  /// ticker so each captured frame reflects a specific, deterministic
  /// point in the cycle instead of whatever the live animation happens to
  /// be doing at capture time.
  final double? emojiCapturePhase;

  @override
  Widget build(BuildContext context) {
    final basePosition = Offset(
      layer.position.dx * canvasSize.width,
      layer.position.dy * canvasSize.height,
    );

    final (minSize, maxSize) = switch (layer) {
      TextCanvasLayer() => (
        TextCanvasLayer.minFontSize,
        TextCanvasLayer.maxFontSize,
      ),
      ImageCanvasLayer() => (
        ImageCanvasLayer.minSize,
        ImageCanvasLayer.maxSize,
      ),
    };
    final baseSize = switch (layer) {
      TextCanvasLayer(:final fontSize) => fontSize,
      ImageCanvasLayer(:final size) => size,
    };
    final clampedSize = (baseSize * liveScale).clamp(minSize, maxSize);
    final effectiveScale = isActive ? clampedSize / baseSize : 1.0;

    // Positioned must be a direct Stack child — a LayoutBuilder here (to
    // read the canvas size) would insert its own RenderObject between
    // Positioned and Stack, breaking the ParentData chain. The caller
    // measures the canvas once and passes canvasSize down instead.
    return Positioned(
      left: basePosition.dx + liveOffset.dx,
      top: basePosition.dy + liveOffset.dy,
      child: IgnorePointer(
        // Gestures are handled by the canvas-level GestureDetector; layers
        // themselves don't need to intercept touches.
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 120),
          opacity: overTrash ? 0.4 : 1.0,
          child: Transform.rotate(
            angle: layer.rotation + liveRotation,
            alignment: Alignment.topLeft,
            child: Transform.scale(
              scale: effectiveScale,
              alignment: Alignment.topLeft,
              child: Container(
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.stackSm,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: overTrash
                        ? AppColors.error
                        : (selected
                              ? AppColors.primaryContainer
                              : Colors.transparent),
                    width: 1.5,
                  ),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: _buildContent(layer),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(CanvasLayer layer) {
    return switch (layer) {
      TextCanvasLayer(
        :final text,
        :final fontSize,
        :final color,
        :final bold,
        :final italic,
        :final fontFamily,
        :final animated,
      ) =>
        _maybeAnimated(
          animated,
          Text(
            text,
            style: GoogleFonts.getFont(
              fontFamily.googleFontsName,
              textStyle: TextStyle(
                color: color,
                fontSize: fontSize,
                fontWeight: bold ? FontWeight.w800 : FontWeight.w400,
                fontStyle: italic ? FontStyle.italic : FontStyle.normal,
                shadows: const [Shadow(color: Colors.black54, blurRadius: 6)],
              ),
            ),
          ),
        ),
      ImageCanvasLayer(:final path, :final size) => ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Image.file(
          File(path),
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => Container(
            width: size,
            height: size,
            color: AppColors.surfaceContainerHigh,
            child: const Icon(
              Icons.broken_image_outlined,
              color: AppColors.onSurfaceVariant,
            ),
          ),
        ),
      ),
    };
  }

  Widget _maybeAnimated(bool animated, Widget child) {
    if (!animated) return child;
    if (emojiCapturePhase != null) {
      // Deterministic sine-wave scale for one export-overlay-sequence
      // frame — mirrors _AnimatedEmoji's 0.92-1.08 range without needing
      // its live ticker running during capture.
      final scale =
          0.92 + 0.08 * (0.5 + 0.5 * math.sin(2 * math.pi * emojiCapturePhase!));
      return Transform.scale(scale: scale, child: child);
    }
    return _AnimatedEmoji(child: child);
  }
}

/// A gentle continuous bounce for emoji/sticker layers ([TextCanvasLayer]
/// with [TextCanvasLayer.animated] set) — keyed by the layer's id via the
/// caller's [ValueKey], so this State (and its [AnimationController])
/// survives the frequent canvas rebuilds instead of restarting the loop
/// every time.
class _AnimatedEmoji extends StatefulWidget {
  const _AnimatedEmoji({required this.child});

  final Widget child;

  @override
  State<_AnimatedEmoji> createState() => _AnimatedEmojiState();
}

class _AnimatedEmojiState extends State<_AnimatedEmoji>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_controller.value);
        return Transform.scale(
          scale: 0.92 + (t * 0.16),
          child: child,
        );
      },
    );
  }
}

class _BottomToolbar extends StatelessWidget {
  const _BottomToolbar({
    required this.filtersActive,
    required this.audioActive,
    required this.flipActive,
    required this.onText,
    required this.onPhoto,
    required this.onFilter,
    required this.onSticker,
    required this.onAudio,
    required this.onFlip,
  });

  final bool filtersActive;
  final bool audioActive;
  final bool flipActive;
  final VoidCallback onText;
  final VoidCallback onPhoto;
  final VoidCallback onFilter;
  final VoidCallback onSticker;
  final VoidCallback onAudio;
  final VoidCallback onFlip;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.stackSm),
      decoration: const BoxDecoration(
        color: AppColors.surfaceCard,
        border: Border(top: BorderSide(color: AppColors.outlineVariant)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _ToolButton(icon: Icons.text_fields, label: 'Text', onTap: onText),
            _ToolButton(
              icon: Icons.image_outlined,
              label: 'Photo',
              onTap: onPhoto,
            ),
            _ToolButton(
              icon: Icons.auto_awesome,
              label: 'Filter',
              active: filtersActive,
              onTap: onFilter,
            ),
            _ToolButton(
              icon: Icons.music_note_outlined,
              label: 'Music',
              active: audioActive,
              onTap: onAudio,
            ),
            _ToolButton(
              icon: Icons.mood_outlined,
              label: 'Sticker',
              onTap: onSticker,
            ),
            _ToolButton(
              icon: Icons.tune,
              label: 'Adjust',
              active: flipActive,
              onTap: onFlip,
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.secondary : AppColors.onSurfaceVariant;
    return TapScale(
      onTap: onTap,
      child: SizedBox(
        width: 64,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: active
                    ? AppColors.secondary.withValues(alpha: 0.15)
                    : Colors.transparent,
                boxShadow: active
                    ? [
                        BoxShadow(
                          color: AppColors.secondary.withValues(alpha: 0.45),
                          blurRadius: 14,
                        ),
                      ]
                    : null,
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(height: 3),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: AppTypography.labelCaps.copyWith(
                color: color,
                fontSize: 9,
              ),
              child: Text(label),
            ),
            const SizedBox(height: 3),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: active ? 4 : 0,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.secondary,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrashZone extends StatelessWidget {
  const _TrashZone({required this.visible, required this.active});

  final bool visible;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 16,
      child: IgnorePointer(
        child: Center(
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 150),
            opacity: visible ? 1 : 0,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOut,
              width: active ? 64 : 52,
              height: active ? 64 : 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: active ? AppColors.error : Colors.black54,
                boxShadow: active
                    ? [
                        BoxShadow(
                          color: AppColors.error.withValues(alpha: 0.6),
                          blurRadius: 16,
                        ),
                      ]
                    : null,
              ),
              child: Icon(
                Icons.delete_outline,
                color: Colors.white,
                size: active ? 30 : 24,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

const _filterTabs = <String, FilterCategory?>{
  'All': null,
  'Portrait': FilterCategory.portrait,
  'Landscape': FilterCategory.landscape,
  'Food': FilterCategory.food,
  'Travel': FilterCategory.travel,
};

class _FilterStrip extends StatefulWidget {
  const _FilterStrip({
    required this.imagePath,
    required this.selected,
    required this.intensity,
    required this.onSelected,
    required this.onIntensityLive,
    required this.onIntensityCommit,
  });

  final String imagePath;
  final CameraFilterOption selected;
  final double intensity;
  final ValueChanged<CameraFilterOption> onSelected;
  final ValueChanged<double> onIntensityLive;
  final ValueChanged<double> onIntensityCommit;

  @override
  State<_FilterStrip> createState() => _FilterStripState();
}

class _FilterStripState extends State<_FilterStrip> {
  String _tab = 'All';
  double? _dragStartIntensity;

  @override
  Widget build(BuildContext context) {
    final activeCategory = _filterTabs[_tab];
    final options = CameraFilterOption.all
        .where(
          (option) =>
              activeCategory == null ||
              option.categories.contains(activeCategory),
        )
        .toList();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.containerPadding,
          ),
          child: Row(
            children: [
              const Icon(
                Icons.opacity,
                size: 16,
                color: AppColors.onSurfaceVariant,
              ),
              Expanded(
                child: Slider(
                  min: 0,
                  max: 100,
                  value: widget.intensity,
                  activeColor: AppColors.primaryContainer,
                  onChangeStart: (v) => _dragStartIntensity = v,
                  onChanged: widget.onIntensityLive,
                  onChangeEnd: (_) =>
                      widget.onIntensityCommit(_dragStartIntensity ?? 100),
                ),
              ),
              SizedBox(
                width: 32,
                child: Text(
                  '${widget.intensity.round()}%',
                  textAlign: TextAlign.right,
                  style: AppTypography.labelCaps.copyWith(
                    color: AppColors.onSurfaceVariant,
                    fontSize: 10,
                  ),
                ),
              ),
            ],
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.containerPadding,
          ),
          child: Row(
            children: [
              for (final label in _filterTabs.keys) ...[
                _FilterTabChip(
                  label: label,
                  selected: _tab == label,
                  onTap: () => setState(() => _tab = label),
                ),
                const SizedBox(width: AppSpacing.stackSm),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.stackSm),
        SizedBox(
          height: 76,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.containerPadding,
            ),
            itemCount: options.length,
            separatorBuilder: (context, index) =>
                const SizedBox(width: AppSpacing.stackSm),
            itemBuilder: (context, index) {
              final option = options[index];
              final isSelected = option.name == widget.selected.name;
              return TapScale(
                onTap: () => widget.onSelected(option),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected
                              ? AppColors.primaryContainer
                              : Colors.white38,
                          width: 2,
                        ),
                      ),
                      child: ClipOval(
                        child: ColorFiltered(
                          colorFilter: ColorFilter.matrix(option.matrix),
                          child: Image.file(
                            File(widget.imagePath),
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                const ColoredBox(
                                  color: AppColors.surfaceContainerHigh,
                                ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      option.name,
                      style: AppTypography.labelCaps.copyWith(
                        color: isSelected
                            ? AppColors.primaryContainer
                            : Colors.white70,
                        fontSize: 9,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _FilterTabChip extends StatelessWidget {
  const _FilterTabChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TapScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.stackMd,
          vertical: 4,
        ),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.full),
          border: Border.all(
            color: selected
                ? AppColors.primaryContainer
                : AppColors.outlineVariant,
          ),
        ),
        child: Text(
          label,
          style: AppTypography.labelCaps.copyWith(
            fontSize: 11,
            color: selected
                ? AppColors.onPrimaryContainer
                : AppColors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _AudioIndicator extends StatefulWidget {
  const _AudioIndicator({super.key, required this.track, required this.onTap});

  final AudioTrack track;
  final VoidCallback onTap;

  @override
  State<_AudioIndicator> createState() => _AudioIndicatorState();
}

class _AudioIndicatorState extends State<_AudioIndicator> {
  final _player = AudioPlayer();
  bool _isPlaying = false;
  StreamSubscription<Duration>? _positionSub;

  /// Called from the editor before export starts, so the raw audio preview
  /// and the exported video's own (identical) audio track never play at the
  /// same time — that overlap sounded like a distracting echo.
  void stopPreview() {
    if (!_isPlaying) return;
    _player.stop();
    setState(() => _isPlaying = false);
  }

  @override
  void didUpdateWidget(covariant _AudioIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.track.path != widget.track.path && _isPlaying) {
      _player.stop();
      _isPlaying = false;
    }
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _togglePlayback() async {
    final track = widget.track;
    if (_isPlaying) {
      await _player.stop();
      setState(() => _isPlaying = false);
      return;
    }
    await _player.setVolume(track.volume.clamp(0.0, 1.0));
    await _player.play(
      DeviceFileSource(track.path),
      position: Duration(milliseconds: track.trimStartMs),
    );
    setState(() => _isPlaying = true);
    _positionSub?.cancel();
    _positionSub = _player.onPositionChanged.listen((position) {
      if (position.inMilliseconds >= track.effectiveEndMs) {
        _player.stop();
        if (mounted) setState(() => _isPlaying = false);
      }
    });
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _isPlaying = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.containerPadding,
        vertical: AppSpacing.stackSm,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.stackSm,
        vertical: AppSpacing.stackSm,
      ),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(AppRadius.full),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Row(
        children: [
          TapScale(
            onTap: _togglePlayback,
            child: Container(
              width: 30,
              height: 30,
              decoration: const BoxDecoration(
                color: AppColors.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                _isPlaying ? Icons.stop_rounded : Icons.play_arrow,
                color: AppColors.onPrimaryContainer,
                size: 18,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.stackSm),
          Expanded(
            child: GestureDetector(
              onTap: widget.onTap,
              child: Text(
                widget.track.label,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.bodyMd,
              ),
            ),
          ),
          TapScale(
            onTap: widget.onTap,
            child: const Icon(
              Icons.tune,
              color: AppColors.onSurfaceVariant,
              size: 18,
            ),
          ),
        ],
      ),
    );
  }
}
