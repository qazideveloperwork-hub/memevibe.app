import 'dart:async';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/level.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';

import '../domain/audio_track.dart';

/// Muxes a still image (or, when [imageSequencePattern] is given, a short
/// looping frame sequence — needed so an animated emoji layer actually
/// bounces in the export instead of freezing at whatever phase the single
/// snapshot happened to catch) with a trimmed/volume-adjusted audio track
/// into an mp4 — the "photo + voice-over" status format.
///
/// [onProgress] receives a 0.0–1.0 fraction, derived from ffmpeg's own
/// statistics callback (processed-time / target-duration), so it tracks the
/// actual encode, not a fake timer.
Future<File> exportImageWithAudioToVideo({
  required String imagePath,
  String? imageSequencePattern,
  double imageSequenceFramerate = 10,
  required AudioTrack audio,
  required String outputPath,
  void Function(double progress)? onProgress,
  void Function(int sessionId)? onSessionId,
}) async {
  final trimStartSec = audio.trimStartMs / 1000;
  final durationSec = (audio.effectiveEndMs - audio.trimStartMs) / 1000;
  if (durationSec <= 0) {
    throw ArgumentError('Audio track has no playable duration after trim');
  }

  // -stream_loop -1 never emits its own EOF, so without an explicit -t
  // bound here ffmpeg has no reason to ever stop reading it — -shortest on
  // the output isn't enough to make that converge (confirmed by the
  // identical bug in exportVideoProject's overlay input: progress reports
  // "100%" once the bounded audio track ends, but the session just keeps
  // duplicating frames indefinitely instead of finishing).
  final isAnimated = imageSequencePattern != null;
  final videoInput = isAnimated
      ? '-stream_loop -1 -framerate $imageSequenceFramerate -t $durationSec -i "$imageSequencePattern"'
      : '-loop 1 -i "$imagePath"';

  // Explicit -map avoids ffmpeg's automatic stream-selection guessing wrong
  // when one input is a looped image and the other is audio-only. The scale
  // filter rounds width/height down to even numbers — libx264 with yuv420p
  // (4:2:0 chroma subsampling) rejects odd dimensions outright, and a
  // RepaintBoundary snapshot has no reason to land on an even height; it
  // crops at most 1px off either edge, which is imperceptible.
  //
  // crf 16 (near-visually-lossless) costs almost nothing for the true
  // still-image case since the frame never changes — stillimage tuning
  // means libx264 is really only ever encoding one real frame and
  // duplicating it. Skipped for the animated sequence, since that tuning
  // hint would be actively wrong when the frame does change.
  final command =
      '-y $videoInput -ss $trimStartSec -t $durationSec -i "${audio.path}" '
      '-map 0:v:0 -map 1:a:0 -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" '
      '-filter:a "volume=${audio.volume}" '
      '-c:v libx264 ${isAnimated ? '' : '-tune stillimage '}-crf 16 -c:a aac -b:a 192k -pix_fmt yuv420p '
      '-r 24 -shortest "$outputPath"';

  final completer = Completer<File>();
  // See exportVideoProject's identical watchdog for why this exists: ffmpeg
  // has no "I've hung" signal of its own, so a stalled session would
  // otherwise freeze the progress dialog forever with no way out.
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
        completer.completeError(Exception('Export cancelled'));
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
    null,
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
