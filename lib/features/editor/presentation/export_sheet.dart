import 'dart:io';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';

enum ExportKind { image, video }

Future<void> showExportSheet(
  BuildContext context, {
  required File file,
  required ExportKind kind,
  File? previewImage,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surfaceElevated,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
    ),
    builder: (context) =>
        ExportSheet(file: file, kind: kind, previewImage: previewImage),
  );
}

class ExportSheet extends StatefulWidget {
  const ExportSheet({
    super.key,
    required this.file,
    required this.kind,
    this.previewImage,
  });

  final File file;
  final ExportKind kind;

  /// Shown as a poster behind the video player while it initializes.
  final File? previewImage;

  @override
  State<ExportSheet> createState() => _ExportSheetState();
}

enum _SaveState { idle, saving, saved, error }

class _ExportSheetState extends State<ExportSheet> {
  _SaveState _saveState = _SaveState.idle;
  VideoPlayerController? _videoController;

  @override
  void initState() {
    super.initState();
    if (widget.kind == ExportKind.video) {
      final controller = VideoPlayerController.file(widget.file);
      _videoController = controller;
      controller
        ..setLooping(true)
        ..initialize().then((_) {
          if (mounted) setState(() {});
        });
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  Future<void> _saveToGallery() async {
    setState(() => _saveState = _SaveState.saving);
    try {
      final permission = await PhotoManager.requestPermissionExtend();
      if (!permission.isAuth && !permission.hasAccess) {
        setState(() => _saveState = _SaveState.error);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Photo library access is needed to save'),
          ),
        );
        return;
      }
      if (widget.kind == ExportKind.video) {
        await PhotoManager.editor.saveVideo(
          widget.file,
          title: widget.file.uri.pathSegments.last,
        );
      } else {
        await PhotoManager.editor.saveImage(
          await widget.file.readAsBytes(),
          filename: widget.file.uri.pathSegments.last,
          title: widget.file.uri.pathSegments.last,
        );
      }
      if (!mounted) return;
      setState(() => _saveState = _SaveState.saved);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saveState = _SaveState.error);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Couldn\'t save: $error')));
    }
  }

  Future<void> _share() async {
    await SharePlus.instance.share(
      ShareParams(files: [XFile(widget.file.path)]),
    );
  }

  void _togglePlayback() {
    final controller = _videoController;
    if (controller == null || !controller.value.isInitialized) return;
    setState(() {
      controller.value.isPlaying ? controller.pause() : controller.play();
    });
  }

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
          const Center(
            child: SizedBox(
              width: 36,
              height: 4,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.all(Radius.circular(2)),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.stackMd),
          Text('Your Creation', style: AppTypography.headlineLgMobile),
          const SizedBox(height: AppSpacing.stackMd),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: AspectRatio(aspectRatio: 9 / 16, child: _buildPreview()),
          ),
          const SizedBox(height: AppSpacing.stackLg),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _saveState == _SaveState.saving
                      ? null
                      : _saveToGallery,
                  icon: switch (_saveState) {
                    _SaveState.saving => const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    _SaveState.saved => const Icon(
                      Icons.check,
                      color: AppColors.primaryContainer,
                    ),
                    _ => const Icon(Icons.download),
                  },
                  label: Text(
                    _saveState == _SaveState.saved
                        ? 'Saved'
                        : 'Save to Gallery',
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.stackMd),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _share,
                  icon: const Icon(Icons.share),
                  label: const Text('Share'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPreview() {
    if (widget.kind == ExportKind.image) {
      return Image.file(widget.file, fit: BoxFit.cover);
    }

    final controller = _videoController;
    final isReady = controller != null && controller.value.isInitialized;

    return GestureDetector(
      onTap: _togglePlayback,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (widget.previewImage != null)
            Image.file(widget.previewImage!, fit: BoxFit.cover)
          else
            const ColoredBox(color: AppColors.surfaceContainerHigh),
          if (isReady)
            FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: controller.value.size.width,
                height: controller.value.size.height,
                child: VideoPlayer(controller),
              ),
            ),
          if (!isReady)
            const Center(
              child: CircularProgressIndicator(
                color: AppColors.primaryContainer,
              ),
            )
          else if (!controller.value.isPlaying)
            const Center(
              child: Icon(
                Icons.play_circle_fill,
                size: 56,
                color: Colors.white70,
              ),
            ),
        ],
      ),
    );
  }
}
