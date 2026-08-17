import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/level.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';

import '../domain/audio_track.dart';

const _outputWidth = 1080;
const _outputHeight = 1920;

/// Turns a blended (post-[CameraFilterOption.withIntensity]) 20-element
/// color matrix into an ffmpeg `geq` filter. Every filter in this app is a
/// plain 3x3-linear-plus-offset matrix with an identity alpha row (verified
/// against `camera_filter.dart`), so one generic expression exactly
/// replicates any of them — no per-filter hand translation needed. `clip()`
/// mirrors the implicit 0-255 clamping `ColorFilter.matrix` does.
String _colorMatrixGeq(List<double> m) {
  String expr(int base) =>
      "clip(${m[base]}*r(X,Y)+${m[base + 1]}*g(X,Y)+${m[base + 2]}*b(X,Y)+${m[base + 4]},0,255)";
  return "geq=r='${expr(0)}':g='${expr(5)}':b='${expr(10)}'";
}

Future<bool> _hasAudioStream(String path) async {
  final session = await FFprobeKit.getMediaInformation(path);
  final info = session.getMediaInformation();
  final streams = info?.getStreams() ?? const [];
  return streams.any((s) => s.getType() == 'audio');
}

/// Exports a trimmed, filtered, flipped/rotated video with an optional
/// burned-in overlay (text/stickers) and an optional added [AudioTrack],
/// mixed with or replacing the source clip's own audio.
///
/// Unlike [exportImageWithAudioToVideo] (which loops a single still frame),
/// this re-encodes real motion, so it follows the same
/// Completer/statistics-progress/error-log pattern but with a genuinely
/// frame-by-frame ffmpeg filter graph.
Future<File> exportVideoProject({
  required String sourceVideoPath,
  required int trimStartMs,
  required int trimEndMs,
  required List<double> filterMatrix,
  required bool isIdentityFilter,
  required bool flipHorizontal,
  required bool flipVertical,
  required double straightenDegrees,
  required int rotationQuarterTurns,
  String? overlayPngPath,
  String? overlaySequencePattern,
  double overlaySequenceFramerate = 10,
  required double originalAudioVolume,
  AudioTrack? addedAudio,
  required bool isPro,
  required String outputPath,
  void Function(double progress)? onProgress,
  void Function(int sessionId)? onSessionId,
}) async {
  final trimStartSec = trimStartMs / 1000;
  final durationSec = (trimEndMs - trimStartMs) / 1000;
  if (durationSec <= 0) {
    throw ArgumentError('Video has no playable duration after trim');
  }

  final hasSourceAudio =
      originalAudioVolume > 0 && await _hasAudioStream(sourceVideoPath);

  // --- video filter chain (order mirrors the live preview's widget tree:
  // RotatedBox(quarterTurns) -> ColorFiltered(matrix) -> Transform(straighten+flip)) ---
  final videoFilters = <String>[];
  if (!isIdentityFilter) {
    videoFilters.add('format=rgba');
    videoFilters.add(_colorMatrixGeq(filterMatrix));
    videoFilters.add('format=yuv420p');
  }
  // transpose=1 is a 90 deg clockwise turn (and swaps w/h), matching
  // RotatedBox's clockwise quarterTurns convention when chained N times.
  for (var i = 0; i < rotationQuarterTurns % 4; i++) {
    videoFilters.add('transpose=1');
  }
  if (straightenDegrees != 0) {
    final radians = straightenDegrees * math.pi / 180;
    videoFilters.add(
      "rotate=$radians:fillcolor=black@0:ow=rotw($radians):oh=roth($radians)",
    );
  }
  if (flipHorizontal) videoFilters.add('hflip');
  if (flipVertical) videoFilters.add('vflip');
  // Fit into the fixed 9:16 output frame with black bars, same idea as the
  // preview's letterboxing (a plain pad here rather than the preview's
  // blurred-backdrop treatment — see PROJECT_PLAN notes on this tradeoff).
  videoFilters.add(
    'scale=$_outputWidth:$_outputHeight:force_original_aspect_ratio=decrease',
  );
  videoFilters.add(
    'pad=$_outputWidth:$_outputHeight:(ow-iw)/2:(oh-ih)/2:color=black',
  );

  final hasOverlay = overlayPngPath != null || overlaySequencePattern != null;
  final filterComplexParts = <String>[
    '[0:v]${videoFilters.join(',')}${hasOverlay ? '[base]' : '[outv]'}',
    if (hasOverlay) '[1:v]scale=$_outputWidth:$_outputHeight[ovl]',
    if (hasOverlay) '[base][ovl]overlay=0:0[outv]',
  ];

  // --- inputs ---
  // An animated overlay (emoji bounce) is a short looping frame sequence
  // instead of one static image — everything downstream (the scale+overlay
  // above) treats it identically to the static case once decoded, ffmpeg
  // doesn't need to know the difference. Critically, -stream_loop -1 never
  // emits its own EOF, so without an explicit -t bound here the overlay
  // filter graph never converges once the (correctly bounded) base video
  // ends — ffmpeg just keeps duplicating frames indefinitely instead of
  // finishing, which is what "stuck at 100%" turned out to actually be.
  final String? overlayInput = overlaySequencePattern != null
      ? '-stream_loop -1 -framerate $overlaySequenceFramerate -t $durationSec -i "$overlaySequencePattern"'
      : overlayPngPath != null
      ? '-loop 1 -t $durationSec -i "$overlayPngPath"'
      : null;
  final inputs = <String>[
    '-ss $trimStartSec -t $durationSec -i "$sourceVideoPath"',
    ?overlayInput,
    if (addedAudio != null)
      '-ss ${addedAudio.trimStartMs / 1000} -t $durationSec -i "${addedAudio.path}"',
  ];
  final audioInputIndex = hasOverlay ? 2 : 1;

  // --- audio graph ---
  // The camera plugin has no exposed option to record through Android's
  // VoIP-tuned audio source (unlike the voice-over recorder, which uses
  // AndroidAudioSource.voiceCommunication for real-time noise suppression)
  // — afftdn is the practical substitute: an FFT-based denoiser applied to
  // the clip's own audio at export time. Only the source video's audio is
  // denoised, never an added music/sound-effect track.
  if (hasSourceAudio) {
    filterComplexParts.add(
      '[0:a]afftdn=nf=-25,volume=$originalAudioVolume[denoised]',
    );
  }

  final String audioMap;
  if (hasSourceAudio && addedAudio != null) {
    filterComplexParts.add(
      '[$audioInputIndex:a]volume=${addedAudio.volume}[added]',
    );
    filterComplexParts.add(
      '[denoised][added]amix=inputs=2:duration=first[outa]',
    );
    audioMap = '-map [outa]';
  } else if (hasSourceAudio) {
    audioMap = '-map [denoised]';
  } else if (addedAudio != null) {
    filterComplexParts.add(
      '[$audioInputIndex:a]volume=${addedAudio.volume}[outa]',
    );
    audioMap = '-map [outa]';
  } else {
    audioMap = '-an';
  }

  final commonArgs =
      '-y ${inputs.join(' ')} '
      '-filter_complex "${filterComplexParts.join(';')}" '
      '-map [outv] $audioMap ';

  // Pro exports target a real 4000kbps — visually close to source quality
  // at 1080x1920. Free exports are capped well below that; an explicit
  // bitrate (rather than CRF) is what makes the cap actually hold on both
  // the hardware and software encoder paths, since h264_mediacodec has no
  // CRF-equivalent rate control at all.
  final bitrateK = isPro ? 4000 : 1500;
  final bufsizeK = bitrateK * 2;

  // Software x264 (even at "veryfast") is genuinely slow encoding 1080x1920
  // on mid-range phone CPUs — a several-second clip can take well over a
  // minute, which reads as "stuck" even though it's progressing. ffmpeg-kit
  // full-gpl bundles Android's MediaCodec hardware encoder, so try that
  // first; if it's unsupported on this device (or this build doesn't
  // actually carry the encoder patch), fall straight back to libx264 rather
  // than surfacing an error the user can't act on.
  final hwCommand =
      '$commonArgs'
      '-c:v h264_mediacodec -b:v ${bitrateK}k -c:a aac -b:a 192k -pix_fmt yuv420p '
      '-r 30 -shortest "$outputPath"';
  final swCommand =
      '$commonArgs'
      '-c:v libx264 -b:v ${bitrateK}k -maxrate ${bitrateK}k -bufsize ${bufsizeK}k '
      '-preset veryfast -c:a aac -b:a 192k -pix_fmt yuv420p '
      '-r 30 -shortest "$outputPath"';

  try {
    return await _runFfmpeg(
      hwCommand,
      durationSec: durationSec,
      outputPath: outputPath,
      onProgress: onProgress,
      onSessionId: onSessionId,
    );
  } on _ExportCancelled {
    rethrow;
  } catch (_) {
    onProgress?.call(0);
    return _runFfmpeg(
      swCommand,
      durationSec: durationSec,
      outputPath: outputPath,
      onProgress: onProgress,
      onSessionId: onSessionId,
    );
  }
}

class _ExportCancelled implements Exception {
  @override
  String toString() => 'Export cancelled';
}

/// Runs one ffmpeg command through to completion, translating its
/// Completer/statistics-callback/error-log plumbing into a plain
/// `Future<File>` — shared by [exportVideoProject]'s hardware-encode
/// attempt and its software fallback so both get identical stall
/// protection and error formatting.
Future<File> _runFfmpeg(
  String command, {
  required double durationSec,
  required String outputPath,
  void Function(double progress)? onProgress,
  void Function(int sessionId)? onSessionId,
}) async {
  final completer = Completer<File>();
  // ffmpeg gives no built-in "I've hung" signal — a genuinely stuck session
  // (e.g. a device-specific encoder/filter stall) otherwise sits forever
  // with the progress dialog frozen and no way out. Rearm this on every
  // statistics tick; if none arrive for a while, treat it as stalled and
  // cancel the underlying session so the completer always eventually
  // resolves one way or another.
  Timer? watchdog;
  int? sessionId;
  void armWatchdog() {
    watchdog?.cancel();
    watchdog = Timer(const Duration(seconds: 30), () {
      if (completer.isCompleted) return;
      if (sessionId != null) FFmpegKit.cancel(sessionId);
      completer.completeError(
        Exception(
          'Export stalled: no progress for 30s. This usually means the '
          'device is struggling to encode — try a shorter clip or close '
          'other apps and try again.',
        ),
      );
    });
  }

  final session = await FFmpegKit.executeAsync(
    command,
    (session) async {
      watchdog?.cancel();
      if (completer.isCompleted) return;
      final returnCode = await session.getReturnCode();
      if (ReturnCode.isSuccess(returnCode)) {
        completer.complete(File(outputPath));
      } else if (ReturnCode.isCancel(returnCode)) {
        completer.completeError(_ExportCancelled());
      } else {
        final logs = await session.getLogs();
        final relevant = logs
            .where((log) => log.getLevel() <= Level.avLogError)
            .map((log) => log.getMessage().trim())
            .where((message) => message.isNotEmpty)
            .join('\n');
        completer.completeError(
          Exception(
            'ffmpeg failed (code $returnCode)\n\n'
            '${relevant.isEmpty ? 'No detailed ffmpeg error output was captured.' : relevant}',
          ),
        );
      }
    },
    // Piping this through print() (visible in logcat under the "flutter"
    // tag) is the only way to see what ffmpeg is actually doing on-device —
    // with a null callback here, ffmpeg's own log lines never reach logcat
    // at all, which is why every past attempt at diagnosing a stuck export
    // via `adb logcat` came back empty regardless of buffer timing.
    (log) {
      if (log.getLevel() <= Level.avLogInfo) {
        debugPrint('[ffmpeg] ${log.getMessage().trim()}');
      }
    },
    (statistics) {
      armWatchdog();
      final elapsedSec = statistics.getTime() / 1000;
      onProgress?.call((elapsedSec / durationSec).clamp(0.0, 1.0));
    },
  );
  sessionId = session.getSessionId();
  if (sessionId != null) onSessionId?.call(sessionId);
  armWatchdog();
  return completer.future;
}
