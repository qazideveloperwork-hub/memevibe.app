import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../create/domain/camera_filter.dart';
import '../domain/audio_track.dart';
import '../domain/canvas_layer.dart';
import '../domain/editor_state.dart';

class EditorController extends StateNotifier<EditorState> {
  EditorController() : super(EditorState.initial());

  int _nextLayerId = 0;

  void _commit(EditorCanvas next) {
    state = EditorState(
      canvas: next,
      history: [...state.history, state.canvas],
      future: const [],
    );
  }

  void _addLayer(CanvasLayer layer) {
    _commit(
      state.canvas.copyWith(
        layers: [...state.canvas.layers, layer],
        selectedLayerId: layer.id,
      ),
    );
  }

  void addText(
    String text, {
    double fontSize = 32,
    Color color = Colors.white,
    bool bold = true,
    bool italic = false,
    TextFontFamily fontFamily = TextFontFamily.sora,
  }) {
    _addLayer(
      TextCanvasLayer(
        id: 'text_${_nextLayerId++}',
        text: text,
        position: const Offset(0.3, 0.45),
        fontSize: fontSize,
        color: color,
        bold: bold,
        italic: italic,
        fontFamily: fontFamily,
      ),
    );
  }

  /// Updates an existing text layer's content/style in place (does not
  /// affect its position, size, or rotation).
  void editText(
    String id, {
    required String text,
    required double fontSize,
    required Color color,
    required bool bold,
    required bool italic,
    required TextFontFamily fontFamily,
  }) {
    final layers = state.canvas.layers
        .map(
          (l) => l.id == id && l is TextCanvasLayer
              ? l.withStyle(
                  text: text,
                  fontSize: fontSize,
                  color: color,
                  bold: bold,
                  italic: italic,
                  fontFamily: fontFamily,
                )
              : l,
        )
        .toList();
    _commit(state.canvas.copyWith(layers: layers));
  }

  void addEmoji(String emoji) {
    _addLayer(
      TextCanvasLayer(
        id: 'emoji_${_nextLayerId++}',
        text: emoji,
        position: const Offset(0.4, 0.4),
        fontSize: 56,
        animated: true,
      ),
    );
  }

  void addImage(String path) {
    _addLayer(
      ImageCanvasLayer(
        id: 'image_${_nextLayerId++}',
        path: path,
        position: const Offset(0.25, 0.35),
      ),
    );
  }

  /// Called once when a drag/pinch/rotate gesture ends. Live movement during
  /// the gesture is handled entirely in the layer widget's local state (so
  /// it doesn't rebuild the whole editor on every frame); this just commits
  /// the final result as a single undo step.
  void transformLayer(
    String id,
    Offset position,
    double scaleMultiplier,
    double rotationDelta,
  ) {
    final layers = state.canvas.layers
        .map(
          (l) => l.id == id
              ? l.transformed(
                  position: position,
                  scaleMultiplier: scaleMultiplier,
                  rotationDelta: rotationDelta,
                )
              : l,
        )
        .toList();
    _commit(state.canvas.copyWith(layers: layers));
  }

  void selectLayer(String? id) {
    state = EditorState(
      canvas: state.canvas.copyWith(
        selectedLayerId: id,
        clearSelection: id == null,
      ),
      history: state.history,
      future: state.future,
    );
  }

  void removeLayer(String id) {
    _commit(
      state.canvas.copyWith(
        layers: state.canvas.layers.where((l) => l.id != id).toList(),
        clearSelection: true,
      ),
    );
  }

  void setFilter(CameraFilterOption filter) {
    _commit(state.canvas.copyWith(filter: filter, filterIntensity: 100));
  }

  /// Live preview while dragging the filter-intensity slider — see
  /// [setStraightenLive] for why this skips undo history.
  void setFilterIntensityLive(double intensity) {
    state = EditorState(
      canvas: state.canvas.copyWith(
        filterIntensity: intensity.clamp(0.0, 100.0),
      ),
      history: state.history,
      future: state.future,
    );
  }

  void commitFilterIntensity(double startIntensity) {
    final before = state.canvas.copyWith(filterIntensity: startIntensity);
    state = EditorState(
      canvas: state.canvas,
      history: [...state.history, before],
      future: const [],
    );
  }

  void toggleFlipHorizontal() {
    _commit(
      state.canvas.copyWith(flipHorizontal: !state.canvas.flipHorizontal),
    );
  }

  void toggleFlipVertical() {
    _commit(state.canvas.copyWith(flipVertical: !state.canvas.flipVertical));
  }

  void rotate90() {
    _commit(
      state.canvas.copyWith(
        rotationQuarterTurns: (state.canvas.rotationQuarterTurns + 1) % 4,
      ),
    );
  }

  /// Live preview while dragging the straighten slider — deliberately does
  /// NOT touch undo history, otherwise every pixel of drag would become its
  /// own undo step. Pair with [commitStraighten] once the drag ends.
  void setStraightenLive(double degrees) {
    state = EditorState(
      canvas: state.canvas.copyWith(
        straightenDegrees: degrees.clamp(-45.0, 45.0),
      ),
      history: state.history,
      future: state.future,
    );
  }

  /// Records a single undo step for the whole drag, from [startDegrees] to
  /// wherever the slider ended up.
  void commitStraighten(double startDegrees) {
    final before = state.canvas.copyWith(straightenDegrees: startDegrees);
    state = EditorState(
      canvas: state.canvas,
      history: [...state.history, before],
      future: const [],
    );
  }

  /// Live preview while dragging the trim range slider — see
  /// [setStraightenLive] for why this skips undo history.
  void setVideoTrimLive(int startMs, int endMs) {
    state = EditorState(
      canvas: state.canvas.copyWith(
        videoTrimStartMs: startMs,
        videoTrimEndMs: endMs,
      ),
      history: state.history,
      future: state.future,
    );
  }

  /// Records a single undo step for the whole drag.
  void commitVideoTrim(int startStartMs, int startEndMs) {
    final before = state.canvas.copyWith(
      videoTrimStartMs: startStartMs,
      videoTrimEndMs: startEndMs,
    );
    state = EditorState(
      canvas: state.canvas,
      history: [...state.history, before],
      future: const [],
    );
  }

  /// Live preview while dragging the original-audio volume slider — see
  /// [setStraightenLive] for why this skips undo history.
  void setOriginalAudioVolumeLive(double volume) {
    state = EditorState(
      canvas: state.canvas.copyWith(
        originalAudioVolume: volume.clamp(0.0, 1.5),
      ),
      history: state.history,
      future: state.future,
    );
  }

  /// Records a single undo step for the whole drag.
  void commitOriginalAudioVolume(double startVolume) {
    final before = state.canvas.copyWith(originalAudioVolume: startVolume);
    state = EditorState(
      canvas: state.canvas,
      history: [...state.history, before],
      future: const [],
    );
  }

  void setAudioTrack(AudioTrack track) {
    _commit(state.canvas.copyWith(audioTrack: track));
  }

  void updateAudioTrim(int trimStartMs, int trimEndMs) {
    final track = state.canvas.audioTrack;
    if (track == null) return;
    _commit(
      state.canvas.copyWith(
        audioTrack: track.copyWith(
          trimStartMs: trimStartMs,
          trimEndMs: trimEndMs,
        ),
      ),
    );
  }

  void updateAudioVolume(double volume) {
    final track = state.canvas.audioTrack;
    if (track == null) return;
    _commit(state.canvas.copyWith(audioTrack: track.copyWith(volume: volume)));
  }

  void removeAudioTrack() {
    _commit(state.canvas.copyWith(clearAudio: true));
  }

  void undo() {
    if (!state.canUndo) return;
    final previous = state.history.last;
    state = EditorState(
      canvas: previous,
      history: state.history.sublist(0, state.history.length - 1),
      future: [state.canvas, ...state.future],
    );
  }

  void redo() {
    if (!state.canRedo) return;
    final next = state.future.first;
    state = EditorState(
      canvas: next,
      history: [...state.history, state.canvas],
      future: state.future.sublist(1),
    );
  }
}

final editorControllerProvider =
    StateNotifierProvider.autoDispose<EditorController, EditorState>(
      (ref) => EditorController(),
    );
