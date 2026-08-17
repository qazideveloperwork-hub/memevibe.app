import '../../create/domain/camera_filter.dart';
import 'audio_track.dart';
import 'canvas_layer.dart';

class EditorCanvas {
  EditorCanvas({
    this.layers = const [],
    CameraFilterOption? filter,
    this.selectedLayerId,
    this.audioTrack,
    this.flipHorizontal = false,
    this.flipVertical = false,
    this.straightenDegrees = 0,
    this.filterIntensity = 100,
    this.rotationQuarterTurns = 0,
    this.videoTrimStartMs = 0,
    this.videoTrimEndMs,
    this.originalAudioVolume = 1.0,
  }) : filter = filter ?? CameraFilterOption.all[0];

  final List<CanvasLayer> layers;
  final CameraFilterOption filter;
  final String? selectedLayerId;
  final AudioTrack? audioTrack;

  /// 0–100 strength of [filter] — lets a filter be dialed back instead of
  /// only ever applying at full effect.
  final double filterIntensity;

  /// Mirrors/rotates the base photo only — layers (text/stickers/overlays)
  /// keep their own orientation, matching how every mainstream photo editor
  /// treats these as a property of the base image, not the whole canvas.
  final bool flipHorizontal;
  final bool flipVertical;

  /// Small-angle rotation to level a tilted horizon, in degrees. Clamped to
  /// [-45, 45] by the slider that drives it — full 90°/180° turns aren't
  /// what "straighten" is for; use [rotationQuarterTurns] instead.
  final double straightenDegrees;

  /// Full 90° turns (0–3), driven by the Rotate button. Unlike straighten,
  /// this needs to actually swap the layout's width/height for 1 and 3 turns
  /// (a sideways photo shouldn't stay squeezed into the un-rotated box), so
  /// it's applied via RotatedBox rather than a paint-only Transform.
  final int rotationQuarterTurns;

  /// Video-source only — ignored for a photo canvas. Mirrors [AudioTrack]'s
  /// trim shape: [videoTrimEndMs] null means "through the end of the clip",
  /// same nullable-end convention as [AudioTrack.trimEndMs].
  final int videoTrimStartMs;
  final int? videoTrimEndMs;

  /// Video-source only. 0–1.5, mirrors [AudioTrack.volume]'s range — 0 is
  /// fully muted, 1.0 is unchanged, independent of whether an [audioTrack]
  /// is also attached (both can be silent, lowered, or mixed together at
  /// export time).
  final double originalAudioVolume;

  int effectiveVideoTrimEndMs(int durationMs) => videoTrimEndMs ?? durationMs;

  EditorCanvas copyWith({
    List<CanvasLayer>? layers,
    CameraFilterOption? filter,
    String? selectedLayerId,
    bool clearSelection = false,
    AudioTrack? audioTrack,
    bool clearAudio = false,
    bool? flipHorizontal,
    bool? flipVertical,
    double? straightenDegrees,
    double? filterIntensity,
    int? rotationQuarterTurns,
    int? videoTrimStartMs,
    int? videoTrimEndMs,
    double? originalAudioVolume,
  }) {
    return EditorCanvas(
      layers: layers ?? this.layers,
      filter: filter ?? this.filter,
      selectedLayerId: clearSelection
          ? null
          : (selectedLayerId ?? this.selectedLayerId),
      audioTrack: clearAudio ? null : (audioTrack ?? this.audioTrack),
      flipHorizontal: flipHorizontal ?? this.flipHorizontal,
      flipVertical: flipVertical ?? this.flipVertical,
      straightenDegrees: straightenDegrees ?? this.straightenDegrees,
      filterIntensity: filterIntensity ?? this.filterIntensity,
      rotationQuarterTurns: rotationQuarterTurns ?? this.rotationQuarterTurns,
      videoTrimStartMs: videoTrimStartMs ?? this.videoTrimStartMs,
      videoTrimEndMs: videoTrimEndMs ?? this.videoTrimEndMs,
      originalAudioVolume: originalAudioVolume ?? this.originalAudioVolume,
    );
  }
}

class EditorState {
  const EditorState({
    required this.canvas,
    this.history = const [],
    this.future = const [],
  });

  factory EditorState.initial() => EditorState(canvas: EditorCanvas());

  final EditorCanvas canvas;
  final List<EditorCanvas> history;
  final List<EditorCanvas> future;

  bool get canUndo => history.isNotEmpty;
  bool get canRedo => future.isNotEmpty;
}
