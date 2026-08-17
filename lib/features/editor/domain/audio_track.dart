enum AudioSourceType { myAudio, recordedVoice, appSound }

/// A single audio layer attached to the creation — either picked from the
/// device, freshly recorded as a voice-over, or one of the app's bundled
/// sound effects. Trim/volume are stored as fractions of the source file's
/// own duration so they stay valid regardless of playback engine.
class AudioTrack {
  const AudioTrack({
    required this.path,
    required this.label,
    required this.sourceType,
    required this.durationMs,
    this.trimStartMs = 0,
    this.trimEndMs,
    this.volume = 1.0,
  });

  final String path;
  final String label;
  final AudioSourceType sourceType;
  final int durationMs;
  final int trimStartMs;
  final int? trimEndMs;
  final double volume;

  int get effectiveEndMs => trimEndMs ?? durationMs;

  AudioTrack copyWith({int? trimStartMs, int? trimEndMs, double? volume}) {
    return AudioTrack(
      path: path,
      label: label,
      sourceType: sourceType,
      durationMs: durationMs,
      trimStartMs: trimStartMs ?? this.trimStartMs,
      trimEndMs: trimEndMs ?? this.trimEndMs,
      volume: volume ?? this.volume,
    );
  }
}
