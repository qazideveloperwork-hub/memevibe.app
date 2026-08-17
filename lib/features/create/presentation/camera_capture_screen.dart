import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/tap_scale.dart';
import '../data/image_compositor.dart';
import '../domain/camera_filter.dart';
import '../domain/captured_media.dart';
import '../domain/color_adjustments.dart';

const _maxRecordingDuration = Duration(seconds: 60);

enum _PanelTab { filters, adjust }

enum _AspectRatioOption {
  full(ratio: 9 / 16, label: 'Full'),
  portrait(ratio: 3 / 4, label: '3:4'),
  square(ratio: 1, label: '1:1');

  const _AspectRatioOption({required this.ratio, required this.label});
  final double ratio;
  final String label;
}

class CameraCaptureScreen extends StatefulWidget {
  const CameraCaptureScreen({super.key});

  @override
  State<CameraCaptureScreen> createState() => _CameraCaptureScreenState();
}

class _CameraCaptureScreenState extends State<CameraCaptureScreen>
    with SingleTickerProviderStateMixin {
  CameraController? _controller;
  Future<void>? _initializeFuture;
  List<CameraDescription> _cameras = [];
  int _cameraIndex = 0;
  bool _isRecordingVideo = false;
  Object? _error;

  FlashMode _flashMode = FlashMode.off;
  CameraFilterOption _filter = CameraFilterOption.all.first;

  bool _panelExpanded = false;
  _PanelTab _activeTab = _PanelTab.filters;
  double _brightness = 0;
  double _contrast = 1;
  double _saturation = 1;

  int _timerSeconds = 0;
  int? _countdownRemaining;
  _AspectRatioOption _ratio = _AspectRatioOption.full;
  bool _micEnabled = true;
  int _layoutFrames = 0;
  final List<String> _layoutCaptures = [];
  bool _isCompositing = false;

  double _baseZoom = 1;
  double _currentZoom = 1;
  double _minZoom = 1;
  double _maxZoom = 1;

  late final AnimationController _recordingProgress;
  Timer? _recordingTicker;
  Duration _recordingElapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    _recordingProgress = AnimationController(
      vsync: this,
      duration: _maxRecordingDuration,
    );
    _recordingProgress.addStatusListener((status) {
      if (status == AnimationStatus.completed && _isRecordingVideo) {
        _toggleVideoRecording();
      }
    });
    _setUpCamera();
  }

  Future<void> _setUpCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        setState(() => _error = 'No camera found on this device');
        return;
      }
      await _openController(_cameras[_cameraIndex]);
    } catch (error) {
      setState(() => _error = error);
    }
  }

  Future<void> _openController(CameraDescription description) async {
    final future = _createAndInitialize(description);
    setState(() {
      _initializeFuture = future;
    });
    await future;
  }

  /// Camera2/CameraX can transiently fail to open a new controller if the
  /// previous one's hardware release hasn't fully settled yet — seen
  /// specifically right after [_toggleMic]/[_switchCamera], both of which
  /// dispose and recreate the controller (mic on/off isn't runtime-settable
  /// on an existing one, it's constructor-only). A fresh controller after a
  /// short delay clears it, instead of that transient error flashing in the
  /// preview for a moment.
  Future<void> _createAndInitialize(CameraDescription description) async {
    var controller = CameraController(
      description,
      ResolutionPreset.high,
      enableAudio: _micEnabled,
    );
    _controller = controller;
    try {
      await controller.initialize();
    } catch (_) {
      await controller.dispose();
      await Future.delayed(const Duration(milliseconds: 250));
      controller = CameraController(
        description,
        ResolutionPreset.high,
        enableAudio: _micEnabled,
      );
      _controller = controller;
      await controller.initialize();
    }
    _minZoom = await controller.getMinZoomLevel();
    _maxZoom = await controller.getMaxZoomLevel();
    _currentZoom = _minZoom;
    await controller.setFlashMode(_flashMode);
  }

  // Both of these tear down and recreate the whole CameraController — safe
  // between shots, but doing it mid-recording kills the in-progress
  // recording session and briefly leaves the preview pointed at a disposed
  // controller (the "camera exception flashes for a moment" symptom). The
  // corresponding toolbar buttons are also disabled while recording so
  // there's no tap to guard against in the first place.
  Future<void> _switchCamera() async {
    if (_cameras.length < 2 || _isRecordingVideo) return;
    _cameraIndex = (_cameraIndex + 1) % _cameras.length;
    final oldController = _controller;
    // Clearing _initializeFuture here (not after dispose completes) is what
    // actually matters: it drops the preview to a loading spinner in the
    // SAME frame the old controller starts tearing down. Without this, a
    // rebuild can land mid-dispose — CameraController flags itself disposed
    // synchronously before the async platform cleanup finishes — and
    // CameraPreview still holds that now-disposed controller reference,
    // throwing "buildPreview() was called on a disposed CameraController."
    setState(() => _initializeFuture = null);
    await oldController?.dispose();
    await _openController(_cameras[_cameraIndex]);
  }

  Future<void> _toggleMic() async {
    if (_isRecordingVideo) return;
    final oldController = _controller;
    setState(() {
      _micEnabled = !_micEnabled;
      _initializeFuture = null;
    });
    await oldController?.dispose();
    await _openController(_cameras[_cameraIndex]);
  }

  Future<void> _cycleFlash() async {
    final next = switch (_flashMode) {
      FlashMode.off => FlashMode.auto,
      FlashMode.auto => FlashMode.torch,
      FlashMode.torch => FlashMode.off,
      FlashMode.always => FlashMode.off,
    };
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    await controller.setFlashMode(next);
    setState(() => _flashMode = next);
  }

  void _cycleTimer() {
    setState(() {
      _timerSeconds = switch (_timerSeconds) {
        0 => 3,
        3 => 10,
        _ => 0,
      };
    });
  }

  void _cycleRatio() {
    setState(() {
      _ratio = switch (_ratio) {
        _AspectRatioOption.full => _AspectRatioOption.portrait,
        _AspectRatioOption.portrait => _AspectRatioOption.square,
        _AspectRatioOption.square => _AspectRatioOption.full,
      };
    });
  }

  void _cycleLayout() {
    setState(() {
      _layoutFrames = switch (_layoutFrames) {
        0 => 3,
        3 => 4,
        _ => 0,
      };
      _layoutCaptures.clear();
    });
  }

  IconData get _flashIcon => switch (_flashMode) {
    FlashMode.off => Icons.flash_off,
    FlashMode.auto => Icons.flash_auto,
    FlashMode.torch => Icons.flash_on,
    FlashMode.always => Icons.flash_on,
  };

  IconData get _timerIcon => switch (_timerSeconds) {
    3 => Icons.timer_3,
    10 => Icons.timer_10,
    _ => Icons.timer_outlined,
  };

  IconData get _layoutIcon => switch (_layoutFrames) {
    3 => Icons.view_agenda_outlined,
    4 => Icons.grid_view,
    _ => Icons.crop_free,
  };

  void _onScaleStart(ScaleStartDetails details) {
    _baseZoom = _currentZoom;
  }

  Future<void> _onScaleUpdate(ScaleUpdateDetails details) async {
    final controller = _controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        _maxZoom <= _minZoom)
      return;
    final zoom = (_baseZoom * details.scale).clamp(_minZoom, _maxZoom);
    if (zoom == _currentZoom) return;
    _currentZoom = zoom;
    await controller.setZoomLevel(zoom);
    setState(() {});
  }

  Future<void> _runWithTimer(Future<void> Function() action) async {
    if (_timerSeconds <= 0) {
      await action();
      return;
    }
    for (var remaining = _timerSeconds; remaining > 0; remaining--) {
      if (!mounted) return;
      setState(() => _countdownRemaining = remaining);
      await Future.delayed(const Duration(seconds: 1));
    }
    if (!mounted) return;
    setState(() => _countdownRemaining = null);
    await action();
  }

  Future<void> _onShutterTap() async {
    if (_isRecordingVideo) return;
    if (_layoutFrames > 0) {
      await _runWithTimer(_captureLayoutFrame);
    } else {
      await _runWithTimer(_capturePhoto);
    }
  }

  Future<void> _onShutterLongPress() async {
    if (_layoutFrames > 0) return;
    if (_isRecordingVideo) {
      await _toggleVideoRecording();
    } else {
      await _runWithTimer(_toggleVideoRecording);
    }
  }

  Future<void> _capturePhoto() async {
    final controller = _controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        _isRecordingVideo)
      return;
    final file = await controller.takePicture();
    var path = file.path;
    if (_ratio != _AspectRatioOption.full) {
      setState(() => _isCompositing = true);
      final cropped = await ImageCompositor().cropToAspectRatio(
        file.path,
        _ratio.ratio,
      );
      path = cropped.path;
      if (!mounted) return;
      setState(() => _isCompositing = false);
    }
    if (!mounted) return;
    context.pop(CapturedMedia(path: path, type: CapturedMediaType.image));
  }

  Future<void> _captureLayoutFrame() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    final file = await controller.takePicture();
    setState(() => _layoutCaptures.add(file.path));
    if (_layoutCaptures.length >= _layoutFrames) {
      setState(() => _isCompositing = true);
      final composite = await ImageCompositor().composeGrid(_layoutCaptures);
      if (!mounted) return;
      context.pop(
        CapturedMedia(path: composite.path, type: CapturedMediaType.image),
      );
    }
  }

  Future<void> _toggleVideoRecording() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    if (_isRecordingVideo) {
      _recordingTicker?.cancel();
      _recordingProgress.stop();
      final file = await controller.stopVideoRecording();
      setState(() {
        _isRecordingVideo = false;
        _recordingElapsed = Duration.zero;
      });
      _recordingProgress.reset();
      if (!mounted) return;
      context.pop(
        CapturedMedia(path: file.path, type: CapturedMediaType.video),
      );
    } else {
      await controller.startVideoRecording();
      _recordingProgress.forward(from: 0);
      _recordingTicker = Timer.periodic(const Duration(seconds: 1), (_) {
        setState(() => _recordingElapsed += const Duration(seconds: 1));
      });
      setState(() => _isRecordingVideo = true);
    }
  }

  @override
  void dispose() {
    _recordingTicker?.cancel();
    _recordingProgress.dispose();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onScaleStart: _onScaleStart,
                onScaleUpdate: _onScaleUpdate,
                child: _buildPreview(),
              ),
            ),
            Positioned(
              top: AppSpacing.stackMd,
              left: AppSpacing.containerPadding,
              child: _CircleIconButton(
                icon: Icons.close,
                onTap: () => context.pop(),
              ),
            ),
            // Right-edge tool rail, TikTok-style.
            Positioned(
              top: AppSpacing.stackMd,
              right: AppSpacing.containerPadding,
              child: Column(
                children: [
                  _CircleIconButton(icon: _flashIcon, onTap: _cycleFlash),
                  if (_cameras.length > 1) ...[
                    const SizedBox(height: AppSpacing.stackSm),
                    _CircleIconButton(
                      icon: Icons.cameraswitch,
                      onTap: _switchCamera,
                      enabled: !_isRecordingVideo,
                    ),
                  ],
                  const SizedBox(height: AppSpacing.stackSm),
                  _CircleIconButton(
                    icon: _timerIcon,
                    onTap: _cycleTimer,
                    active: _timerSeconds > 0,
                  ),
                  const SizedBox(height: AppSpacing.stackSm),
                  _CircleIconButton(
                    icon: Icons.aspect_ratio,
                    onTap: _cycleRatio,
                    active: _ratio != _AspectRatioOption.full,
                  ),
                  const SizedBox(height: AppSpacing.stackSm),
                  _CircleIconButton(
                    icon: _micEnabled ? Icons.mic : Icons.mic_off,
                    onTap: _toggleMic,
                    active: !_micEnabled,
                    enabled: !_isRecordingVideo,
                  ),
                  const SizedBox(height: AppSpacing.stackSm),
                  _CircleIconButton(
                    icon: _layoutIcon,
                    onTap: _cycleLayout,
                    active: _layoutFrames > 0,
                  ),
                ],
              ),
            ),
            if (_maxZoom > _minZoom)
              Positioned(
                top: AppSpacing.stackMd,
                left: 0,
                right: 0,
                child: Center(
                  child: _Pill(text: '${_currentZoom.toStringAsFixed(1)}x'),
                ),
              ),
            if (_ratio != _AspectRatioOption.full)
              Positioned(
                top: AppSpacing.stackMd + 44,
                left: 0,
                right: 0,
                child: Center(child: _Pill(text: _ratio.label)),
              ),
            if (_isRecordingVideo)
              Positioned(
                top: AppSpacing.stackMd + 44,
                left: 0,
                right: 0,
                child: Center(
                  child: _Pill(
                    icon: Icons.fiber_manual_record,
                    iconColor: AppColors.hotPink,
                    text: _formatDuration(_recordingElapsed),
                  ),
                ),
              ),
            if (_layoutFrames > 0)
              Positioned(
                top: AppSpacing.stackMd + 88,
                left: 0,
                right: 0,
                child: Center(
                  child: _Pill(
                    text:
                        'Frame ${_layoutCaptures.length + 1} of $_layoutFrames',
                  ),
                ),
              ),
            if (_countdownRemaining != null)
              Positioned.fill(
                child: Center(
                  child: TweenAnimationBuilder<double>(
                    key: ValueKey(_countdownRemaining),
                    tween: Tween(begin: 1.4, end: 1.0),
                    duration: const Duration(milliseconds: 350),
                    curve: Curves.elasticOut,
                    builder: (context, scale, child) =>
                        Transform.scale(scale: scale, child: child),
                    child: Text(
                      '$_countdownRemaining',
                      style: AppTypography.displayLg.copyWith(
                        color: Colors.white,
                        fontSize: 96,
                      ),
                    ),
                  ),
                ),
              ),
            if (_isCompositing)
              Positioned.fill(
                child: Container(
                  color: Colors.black54,
                  child: const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
                ),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: AppSpacing.stackLg,
              child: Column(
                children: [
                  if (!_isRecordingVideo) ...[
                    AnimatedSize(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOutCubic,
                      alignment: Alignment.bottomCenter,
                      child: _panelExpanded
                          ? _buildExpandedPanel()
                          : const SizedBox(width: double.infinity),
                    ),
                    TapScale(
                      onTap: () =>
                          setState(() => _panelExpanded = !_panelExpanded),
                      child: AnimatedRotation(
                        turns: _panelExpanded ? 0.5 : 0,
                        duration: const Duration(milliseconds: 250),
                        child: Container(
                          width: 32,
                          height: 32,
                          margin: const EdgeInsets.only(
                            bottom: AppSpacing.stackSm,
                          ),
                          decoration: const BoxDecoration(
                            color: Colors.black45,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.keyboard_arrow_up,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  ],
                  AnimatedBuilder(
                    animation: _recordingProgress,
                    builder: (context, child) => _ShutterButton(
                      progress: _recordingProgress.value,
                      isRecording: _isRecordingVideo,
                      isLayoutMode: _layoutFrames > 0,
                      onTap: _onShutterTap,
                      onLongPress: _onShutterLongPress,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.stackSm),
                  Text(
                    _layoutFrames > 0
                        ? 'Tap to capture each frame'
                        : 'Tap for photo, hold for video',
                    style: AppTypography.bodyMd.copyWith(
                      color: Colors.white70,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpandedPanel() {
    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.containerPadding,
        vertical: AppSpacing.stackSm,
      ),
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.stackMd),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _TabButton(
                label: 'Filters',
                selected: _activeTab == _PanelTab.filters,
                onTap: () => setState(() => _activeTab = _PanelTab.filters),
              ),
              const SizedBox(width: AppSpacing.stackLg),
              _TabButton(
                label: 'Adjust',
                selected: _activeTab == _PanelTab.adjust,
                onTap: () => setState(() => _activeTab = _PanelTab.adjust),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.stackMd),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.15),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            ),
            child: _activeTab == _PanelTab.filters
                ? _FilterStrip(
                    key: const ValueKey('filters'),
                    selected: _filter,
                    onSelected: (f) => setState(() => _filter = f),
                  )
                : _AdjustSliders(
                    key: const ValueKey('adjust'),
                    brightness: _brightness,
                    contrast: _contrast,
                    saturation: _saturation,
                    onBrightnessChanged: (v) => setState(() => _brightness = v),
                    onContrastChanged: (v) => setState(() => _contrast = v),
                    onSaturationChanged: (v) => setState(() => _saturation = v),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreview() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.containerPadding),
          child: Text(
            'Camera unavailable: $_error',
            textAlign: TextAlign.center,
            style: AppTypography.bodyMd.copyWith(color: AppColors.error),
          ),
        ),
      );
    }
    if (_initializeFuture == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return FutureBuilder<void>(
      future: _initializeFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Camera error: ${snapshot.error}',
              style: AppTypography.bodyMd.copyWith(color: AppColors.error),
            ),
          );
        }
        // Preset filter and live adjustments are only previewed here, not
        // yet baked into the saved file — that happens during export
        // (Phase 6), which is where actual pixel processing belongs.
        final filtered = ColorFiltered(
          colorFilter: ColorFilter.matrix(
            buildAdjustmentMatrix(
              brightness: _brightness,
              contrast: _contrast,
              saturation: _saturation,
            ),
          ),
          child: ColorFiltered(
            colorFilter: ColorFilter.matrix(_filter.matrix),
            child: CameraPreview(_controller!),
          ),
        );
        return _RatioFramedPreview(
          ratio: _ratio.ratio,
          previewAspectRatio: _controller!.value.aspectRatio,
          child: filtered,
        );
      },
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

class _RatioFramedPreview extends StatelessWidget {
  const _RatioFramedPreview({
    required this.ratio,
    required this.previewAspectRatio,
    required this.child,
  });

  final double ratio;
  final double previewAspectRatio;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (ratio == 9 / 16) return child;
    return Container(
      color: Colors.black,
      child: Center(
        child: AspectRatio(
          aspectRatio: ratio,
          child: ClipRect(
            child: OverflowBox(
              maxWidth: double.infinity,
              maxHeight: double.infinity,
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: 1000 * previewAspectRatio,
                  height: 1000,
                  child: child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, this.icon, this.iconColor});

  final String text;
  final IconData? icon;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.stackSm,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: iconColor ?? Colors.white),
            const SizedBox(width: 6),
          ],
          Text(
            text,
            style: AppTypography.labelCaps.copyWith(color: Colors.white),
          ),
        ],
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 200),
            style: AppTypography.labelCaps.copyWith(
              color: selected ? AppColors.primaryContainer : Colors.white70,
              fontSize: selected ? 13 : 12,
            ),
            child: Text(label),
          ),
          const SizedBox(height: 3),
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: selected ? 24 : 0,
            height: 2,
            decoration: BoxDecoration(
              color: AppColors.primaryContainer,
              borderRadius: BorderRadius.circular(1),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: AppColors.primaryContainer.withValues(
                          alpha: 0.6,
                        ),
                        blurRadius: 6,
                      ),
                    ]
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _AdjustSliders extends StatelessWidget {
  const _AdjustSliders({
    super.key,
    required this.brightness,
    required this.contrast,
    required this.saturation,
    required this.onBrightnessChanged,
    required this.onContrastChanged,
    required this.onSaturationChanged,
  });

  final double brightness;
  final double contrast;
  final double saturation;
  final ValueChanged<double> onBrightnessChanged;
  final ValueChanged<double> onContrastChanged;
  final ValueChanged<double> onSaturationChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.containerPadding,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _AdjustRow(
            icon: Icons.brightness_6_outlined,
            label: 'Brightness',
            value: brightness,
            min: -1,
            max: 1,
            onChanged: onBrightnessChanged,
          ),
          _AdjustRow(
            icon: Icons.contrast,
            label: 'Contrast',
            value: contrast,
            min: 0,
            max: 2,
            onChanged: onContrastChanged,
          ),
          _AdjustRow(
            icon: Icons.water_drop_outlined,
            label: 'Saturation',
            value: saturation,
            min: 0,
            max: 2,
            onChanged: onSaturationChanged,
          ),
        ],
      ),
    );
  }
}

class _AdjustRow extends StatelessWidget {
  const _AdjustRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final neutral = (min + max) / 2;
    final percent = (((value - neutral) / (max - neutral)) * 100).round();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.white70),
          const SizedBox(width: 6),
          SizedBox(
            width: 68,
            child: Text(
              label,
              style: AppTypography.labelCaps.copyWith(
                color: Colors.white70,
                fontSize: 10,
              ),
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: AppColors.primaryContainer,
                inactiveTrackColor: Colors.white24,
                thumbColor: AppColors.primaryContainer,
                overlayColor: AppColors.primaryContainer.withValues(alpha: 0.2),
                trackHeight: 2,
              ),
              child: Slider(
                value: value,
                min: min,
                max: max,
                onChanged: onChanged,
              ),
            ),
          ),
          SizedBox(
            width: 34,
            child: Text(
              '$percent%',
              textAlign: TextAlign.right,
              style: AppTypography.labelCaps.copyWith(
                color: Colors.white54,
                fontSize: 9,
              ),
            ),
          ),
          GestureDetector(
            onTap: () => onChanged(neutral),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Icon(Icons.refresh, color: Colors.white54, size: 16),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterStrip extends StatelessWidget {
  const _FilterStrip({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final CameraFilterOption selected;
  final ValueChanged<CameraFilterOption> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 72,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.containerPadding,
        ),
        itemCount: CameraFilterOption.all.length,
        separatorBuilder: (context, index) =>
            const SizedBox(width: AppSpacing.stackSm),
        itemBuilder: (context, index) {
          final option = CameraFilterOption.all[index];
          final isSelected = option.name == selected.name;
          return TapScale(
            onTap: () => onSelected(option),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  width: isSelected ? 46 : 40,
                  height: isSelected ? 46 : 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected
                          ? AppColors.primaryContainer
                          : Colors.white38,
                      width: 2,
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: AppColors.primaryContainer.withValues(
                                alpha: 0.5,
                              ),
                              blurRadius: 10,
                            ),
                          ]
                        : null,
                  ),
                  child: ClipOval(
                    child: ColorFiltered(
                      colorFilter: ColorFilter.matrix(option.matrix),
                      child: Container(color: AppColors.surfaceContainerHigh),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 200),
                  style: AppTypography.labelCaps.copyWith(
                    color: isSelected
                        ? AppColors.primaryContainer
                        : Colors.white70,
                    fontSize: isSelected ? 10 : 9,
                  ),
                  child: Text(option.name),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ShutterButton extends StatelessWidget {
  const _ShutterButton({
    required this.onTap,
    required this.onLongPress,
    required this.progress,
    required this.isRecording,
    this.isLayoutMode = false,
  });

  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final double progress;
  final bool isRecording;
  final bool isLayoutMode;

  @override
  Widget build(BuildContext context) {
    return TapScale(
      onTap: onTap,
      onLongPress: onLongPress,
      scale: 0.9,
      child: SizedBox(
        width: 84,
        height: 84,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (isRecording)
              SizedBox(
                width: 84,
                height: 84,
                child: CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 4,
                  backgroundColor: Colors.white24,
                  valueColor: const AlwaysStoppedAnimation(AppColors.hotPink),
                ),
              ),
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                shape: isLayoutMode ? BoxShape.rectangle : BoxShape.circle,
                borderRadius: isLayoutMode
                    ? BorderRadius.circular(AppRadius.md)
                    : null,
                color: isRecording ? AppColors.hotPink : Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({
    required this.icon,
    required this.onTap,
    this.active = false,
    this.enabled = true,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool active;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.35,
      child: Material(
        color: active
            ? AppColors.primaryContainer.withValues(alpha: 0.9)
            : Colors.black45,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.stackSm),
            child: Icon(
              icon,
              color: active ? AppColors.onPrimaryContainer : Colors.white,
              size: 20,
            ),
          ),
        ),
      ),
    );
  }
}
