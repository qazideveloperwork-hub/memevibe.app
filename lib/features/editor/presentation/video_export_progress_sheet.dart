import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';

typedef VideoExportJob = Future<File> Function(
  void Function(double progress) onProgress,
  void Function(int sessionId) onSessionId,
);

/// Runs [job] and shows a live percentage while it works. Not dismissible
/// mid-export — resolves to the finished [File], or `null` if the export
/// failed (the caller is responsible for surfacing the error). [job] itself
/// is exporter-agnostic — the still-image+audio muxer and the real
/// video-source exporter both fit this same `(onProgress) -> File` shape.
Future<File?> showVideoExportProgress(
  BuildContext context, {
  required VideoExportJob job,
  String title = 'Rendering your video…',
  String subtitle = 'This can take a moment',
}) {
  return showDialog<File?>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _VideoExportProgressDialog(
      job: job,
      title: title,
      subtitle: subtitle,
    ),
  );
}

class _VideoExportProgressDialog extends StatefulWidget {
  const _VideoExportProgressDialog({
    required this.job,
    required this.title,
    required this.subtitle,
  });

  final VideoExportJob job;
  final String title;
  final String subtitle;

  @override
  State<_VideoExportProgressDialog> createState() =>
      _VideoExportProgressDialogState();
}

class _VideoExportProgressDialogState
    extends State<_VideoExportProgressDialog> {
  double _progress = 0;
  String? _error;
  int? _sessionId;
  bool _cancelling = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    try {
      final file = await widget.job(
        (p) {
          if (mounted) setState(() => _progress = p);
        },
        (id) => _sessionId = id,
      );
      if (mounted) Navigator.of(context).pop(file);
    } catch (error) {
      if (_cancelling) return;
      if (mounted) setState(() => _error = '$error');
    }
  }

  void _cancel() {
    setState(() => _cancelling = true);
    final id = _sessionId;
    if (id != null) FFmpegKit.cancel(id);
    Navigator.of(context).pop(null);
  }

  Future<void> _confirmCancel() async {
    final shouldStop = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        title: const Text('Stop processing?'),
        content: const Text(
          'Rendering is still in progress. Stopping now cancels this export '
          '— you can start it again from the editor.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep rendering'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Stop'),
          ),
        ],
      ),
    );
    if (shouldStop == true && mounted) _cancel();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _error != null,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop || _error != null) return;
        _confirmCancel();
      },
      child: Dialog(
        backgroundColor: AppColors.surfaceElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.containerPadding + 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_error == null) ...[
                _ProgressRing(progress: _progress),
                const SizedBox(height: AppSpacing.stackLg),
                Text(widget.title, style: AppTypography.headlineLgMobile),
                const SizedBox(height: AppSpacing.stackSm),
                Text(
                  widget.subtitle,
                  style: AppTypography.bodyMd.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.stackLg),
                TextButton(
                  onPressed: _cancelling ? null : _cancel,
                  child: const Text('Cancel'),
                ),
              ] else ...[
                const Icon(
                  Icons.error_outline,
                  color: AppColors.error,
                  size: 40,
                ),
                const SizedBox(height: AppSpacing.stackMd),
                Text('Export failed', style: AppTypography.headlineLgMobile),
                const SizedBox(height: AppSpacing.stackSm),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.35,
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      _error!,
                      style: AppTypography.bodyMd.copyWith(
                        color: AppColors.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.stackLg),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(null),
                  child: const Text('Close'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A gradient-stroked progress ring with the percentage in the center —
/// bespoke rather than a stock [CircularProgressIndicator] so a genuinely
/// long ffmpeg render doesn't feel like a generic spinner.
class _ProgressRing extends StatelessWidget {
  const _ProgressRing({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 96,
      height: 96,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: const Size(96, 96),
            painter: _RingPainter(progress: progress),
          ),
          Text(
            '${(progress * 100).clamp(0, 100).round()}%',
            style: AppTypography.headlineLgMobile.copyWith(fontSize: 20),
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 6;

    final track = Paint()
      ..color = AppColors.surfaceContainerHigh
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, track);

    final rect = Rect.fromCircle(center: center, radius: radius);
    final sweep = Paint()
      ..shader = const SweepGradient(
        startAngle: 0,
        endAngle: math.pi * 2,
        colors: [
          AppColors.primaryContainer,
          AppColors.secondary,
          AppColors.primaryContainer,
        ],
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * progress.clamp(0.0, 1.0),
      false,
      sweep,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
