import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../../core/network/api_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/tap_scale.dart';
import '../data/app_sound_repository.dart';
import '../domain/app_sound.dart';
import '../domain/audio_track.dart';

/// What [showAudioSheet] resolved to: either a track to attach (new or
/// re-trimmed/re-volumed), an explicit removal, or nothing (user dismissed).
class AudioSheetResult {
  const AudioSheetResult.track(AudioTrack this.track) : removed = false;
  const AudioSheetResult.removed() : track = null, removed = true;

  final AudioTrack? track;
  final bool removed;
}

Future<AudioSheetResult?> showAudioSheet(
  BuildContext context, {
  AudioTrack? existing,
}) {
  return showModalBottomSheet<AudioSheetResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.35,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.lg),
          ),
        ),
        child: AudioSheet(
          existing: existing,
          scrollController: scrollController,
        ),
      ),
    ),
  );
}

class AudioSheet extends ConsumerStatefulWidget {
  const AudioSheet({super.key, this.existing, required this.scrollController});

  final AudioTrack? existing;
  final ScrollController scrollController;

  @override
  ConsumerState<AudioSheet> createState() => _AudioSheetState();
}

class _AudioSheetState extends ConsumerState<AudioSheet> {
  int _tab = 0;
  int? _selectedCategoryId;
  AudioTrack? _picked;
  bool _loadingDuration = false;

  final _recorder = AudioRecorder();
  bool _isRecording = false;
  Duration _recordElapsed = Duration.zero;
  Timer? _recordTicker;

  final _previewPlayer = AudioPlayer();
  bool _isPreviewPlaying = false;
  StreamSubscription<Duration>? _positionSub;

  // Separate player for the App Sounds list rows — lets someone preview a
  // sound by streaming it directly, without first downloading/attaching it
  // the way tapping the row itself does. A fresh AudioPlayer is created per
  // tap (not reused across stop/play) — calling stop() on a player whose
  // previous play() is still mid-prepare throws "Stream closed before it
  // got prepared" and leaves that player wedged, which is what made rapid
  // taps across rows stop working.
  AudioPlayer? _listPreviewPlayer;
  int? _listPreviewingId;
  StreamSubscription<void>? _listPreviewCompleteSub;

  late double _trimStart;
  late double _trimEnd;
  late double _volume;

  @override
  void initState() {
    super.initState();
    _picked = widget.existing;
    _trimStart = (widget.existing?.trimStartMs ?? 0).toDouble();
    _trimEnd = (widget.existing?.effectiveEndMs ?? 0).toDouble();
    _volume = widget.existing?.volume ?? 1.0;
    if (widget.existing != null) {
      _tab = switch (widget.existing!.sourceType) {
        AudioSourceType.myAudio => 0,
        AudioSourceType.recordedVoice => 1,
        AudioSourceType.appSound => 2,
      };
    }
  }

  @override
  void dispose() {
    _recordTicker?.cancel();
    _recorder.dispose();
    _positionSub?.cancel();
    _previewPlayer.dispose();
    _listPreviewCompleteSub?.cancel();
    _listPreviewPlayer?.dispose();
    super.dispose();
  }

  // Always tear down whatever list-preview playback was in flight before
  // starting (or simply abandoning) anything new — never stop() a player
  // and immediately reuse it for a new play(), that race is what caused
  // the "stream closed before it got prepared" crash.
  Future<void> _stopListPreview() async {
    final previousPlayer = _listPreviewPlayer;
    if (previousPlayer == null) return;
    _listPreviewCompleteSub?.cancel();
    _listPreviewCompleteSub = null;
    _listPreviewPlayer = null;
    if (mounted) setState(() => _listPreviewingId = null);
    await previousPlayer.stop();
    await previousPlayer.dispose();
  }

  Future<void> _toggleListPreview(AppSoundOption sound) async {
    final wasPlayingThis = _listPreviewingId == sound.id;
    await _stopListPreview();

    // Tapping the row that was already playing just stops it.
    if (wasPlayingThis) return;

    final player = AudioPlayer();
    _listPreviewPlayer = player;
    try {
      await player.play(UrlSource(ApiConfig.resolveAssetUrl(sound.audioUrl)));
    } catch (error) {
      if (identical(_listPreviewPlayer, player)) {
        _listPreviewPlayer = null;
      }
      await player.dispose();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Couldn\'t play "${sound.name}": $error')),
        );
      }
      return;
    }
    // A newer tap may have already replaced this player while awaiting
    // play() above — if so, this one is stale and shouldn't take over.
    if (!mounted || !identical(_listPreviewPlayer, player)) {
      await player.stop();
      await player.dispose();
      return;
    }
    setState(() => _listPreviewingId = sound.id);
    _listPreviewCompleteSub = player.onPlayerComplete.listen((_) {
      if (mounted && identical(_listPreviewPlayer, player)) {
        setState(() => _listPreviewingId = null);
      }
    });
  }

  Future<void> _loadPicked(
    String path,
    String label,
    AudioSourceType type,
  ) async {
    setState(() => _loadingDuration = true);
    final probe = AudioPlayer();
    Duration duration = Duration.zero;
    try {
      await probe.setSourceDeviceFile(path);
      duration = await probe.getDuration() ?? Duration.zero;
    } catch (_) {
      duration = Duration.zero;
    } finally {
      await probe.dispose();
    }
    if (!mounted) return;
    setState(() {
      _picked = AudioTrack(
        path: path,
        label: label,
        sourceType: type,
        durationMs: duration.inMilliseconds,
      );
      _trimStart = 0;
      _trimEnd = duration.inMilliseconds.toDouble();
      _volume = 1.0;
      _loadingDuration = false;
    });
  }

  Future<void> _pickFromDevice() async {
    final file = await FilePicker.pickFile(type: FileType.audio);
    if (file?.path == null) return;
    await _loadPicked(file!.path!, file.name, AudioSourceType.myAudio);
  }

  Future<void> _pickAppSound(AppSoundOption sound) async {
    await _stopListPreview();
    setState(() => _loadingDuration = true);
    try {
      // Keyed by sound id (not a timestamp) so re-picking the same app
      // sound reuses the cached file instead of re-downloading it.
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/app_sound_${sound.id}.mp3');
      if (!await file.exists()) {
        final response = await Dio().get<List<int>>(
          ApiConfig.resolveAssetUrl(sound.audioUrl),
          options: Options(responseType: ResponseType.bytes),
        );
        await file.writeAsBytes(response.data!);
      }
      await _loadPicked(file.path, sound.name, AudioSourceType.appSound);
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadingDuration = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Couldn\'t load "${sound.name}": $error')),
      );
    }
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      final path = await _recorder.stop();
      _recordTicker?.cancel();
      setState(() => _isRecording = false);
      if (path != null) {
        await _loadPicked(
          path,
          'Voice recording',
          AudioSourceType.recordedVoice,
        );
      }
      return;
    }

    if (!await _recorder.hasPermission()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Microphone permission is needed to record a voice-over',
          ),
        ),
      );
      return;
    }

    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/voice_${DateTime.now().microsecondsSinceEpoch}.m4a';
    // Voice-over recording benefits from the device's built-in speech
    // processing — noise suppression, echo cancellation and auto gain are
    // hardware/OS effects applied at capture time (not simulated), so
    // quality depends on what the specific device/OEM supports.
    // `voiceCommunication` is Android's dedicated VoIP audio source — OEMs
    // are required to tune it for background-noise suppression, so it's
    // noticeably more consistent across devices than the plain mic source
    // plus effect flags alone.
    await _recorder.start(
      const RecordConfig(
        noiseSuppress: true,
        echoCancel: true,
        autoGain: true,
        androidConfig: AndroidRecordConfig(
          audioSource: AndroidAudioSource.voiceCommunication,
        ),
      ),
      path: path,
    );
    setState(() {
      _isRecording = true;
      _recordElapsed = Duration.zero;
    });
    _recordTicker = Timer.periodic(const Duration(milliseconds: 200), (_) {
      setState(() => _recordElapsed += const Duration(milliseconds: 200));
    });
  }

  Future<void> _togglePreview() async {
    final track = _picked;
    if (track == null) return;
    if (_isPreviewPlaying) {
      await _previewPlayer.pause();
      setState(() => _isPreviewPlaying = false);
      return;
    }
    await _previewPlayer.setVolume(_volume.clamp(0.0, 1.0));
    await _previewPlayer.play(
      DeviceFileSource(track.path),
      position: Duration(milliseconds: _trimStart.round()),
    );
    setState(() => _isPreviewPlaying = true);
    _positionSub?.cancel();
    _positionSub = _previewPlayer.onPositionChanged.listen((position) {
      if (position.inMilliseconds >= _trimEnd) {
        _previewPlayer.pause();
        if (mounted) setState(() => _isPreviewPlaying = false);
      }
    });
  }

  String _formatMs(int ms) {
    final total = Duration(milliseconds: ms);
    final minutes = total.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = total.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    // Header (handle/title/tabs) is fixed; the tab body fills whatever
    // space is left, so dragging the sheet taller reveals more of the
    // sound list instead of leaving dead space below a capped-height one.
    // Each branch still attaches widget.scrollController to a scrollable
    // so dragging the handle and scrolling content stay the same gesture.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(
            left: AppSpacing.containerPadding,
            right: AppSpacing.containerPadding,
            top: AppSpacing.stackSm,
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
              Text('Audio', style: AppTypography.headlineLgMobile),
              const SizedBox(height: AppSpacing.stackMd),
              Row(
                children: [
                  _AudioTab(
                    label: 'My Audio',
                    selected: _tab == 0,
                    onTap: () => setState(() => _tab = 0),
                  ),
                  const SizedBox(width: AppSpacing.stackSm),
                  _AudioTab(
                    label: 'Record Voice',
                    selected: _tab == 1,
                    onTap: () => setState(() => _tab = 1),
                  ),
                  const SizedBox(width: AppSpacing.stackSm),
                  _AudioTab(
                    label: 'App Sounds',
                    selected: _tab == 2,
                    onTap: () => setState(() => _tab = 2),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.stackMd),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.containerPadding,
            ),
            child: switch (_tab) {
              2 => _buildAppSoundsTab(),
              _ => SingleChildScrollView(
                controller: widget.scrollController,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_tab == 0) _buildMyAudioTab(),
                    if (_tab == 1) _buildRecordTab(),
                    if (_picked != null) ...[
                      const SizedBox(height: AppSpacing.stackLg),
                      const Divider(color: AppColors.outlineVariant),
                      const SizedBox(height: AppSpacing.stackSm),
                      _buildAdjustSection(),
                    ],
                    SizedBox(
                      height:
                          MediaQuery.of(context).viewInsets.bottom +
                          MediaQuery.of(context).padding.bottom +
                          AppSpacing.containerPadding,
                    ),
                  ],
                ),
              ),
            },
          ),
        ),
        if (_tab == 2 && _picked != null)
          Padding(
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
                const Divider(color: AppColors.outlineVariant),
                const SizedBox(height: AppSpacing.stackSm),
                _buildAdjustSection(),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildMyAudioTab() {
    return TapScale(
      onTap: _loadingDuration ? null : _pickFromDevice,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.stackLg),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainer,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.outlineVariant),
        ),
        child: Center(
          child: _loadingDuration
              ? const CircularProgressIndicator(strokeWidth: 2)
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.folder_open_outlined,
                      color: AppColors.primary,
                      size: 28,
                    ),
                    const SizedBox(height: AppSpacing.stackSm),
                    Text(
                      'Choose audio from your device',
                      style: AppTypography.bodyMd,
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildRecordTab() {
    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            _formatMs(_recordElapsed.inMilliseconds),
            style: AppTypography.headlineLgMobile.copyWith(
              color: _isRecording
                  ? AppColors.error
                  : AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.stackMd),
          TapScale(
            onTap: _loadingDuration ? null : _toggleRecording,
            child: Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _isRecording
                    ? AppColors.error
                    : AppColors.primaryContainer,
                boxShadow: [
                  BoxShadow(
                    color:
                        (_isRecording
                                ? AppColors.error
                                : AppColors.primaryContainer)
                            .withValues(alpha: 0.45),
                    blurRadius: 18,
                  ),
                ],
              ),
              child: Icon(
                _isRecording ? Icons.stop_rounded : Icons.mic,
                color: _isRecording
                    ? Colors.white
                    : AppColors.onPrimaryContainer,
                size: 32,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.stackSm),
          Text(
            _isRecording ? 'Tap to stop' : 'Tap to record a voice-over',
            style: AppTypography.bodyMd.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppSoundsTab() {
    final categoriesAsync = ref.watch(soundCategoriesProvider);
    final soundsAsync = ref.watch(appSoundsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSpacing.stackSm),
        categoriesAsync.when(
          loading: () => const SizedBox(
            height: 32,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
          error: (error, _) => Text(
            'Couldn\'t load categories: $error',
            style: AppTypography.bodyMd.copyWith(color: AppColors.error),
          ),
          data: (categories) {
            _selectedCategoryId ??= categories.isEmpty
                ? null
                : categories.first.id;
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final category in categories) ...[
                    _MoodChip(
                      label: category.name,
                      selected: _selectedCategoryId == category.id,
                      onTap: () =>
                          setState(() => _selectedCategoryId = category.id),
                    ),
                    const SizedBox(width: AppSpacing.stackSm),
                  ],
                ],
              ),
            );
          },
        ),
        const SizedBox(height: AppSpacing.stackMd),
        Expanded(
          child: soundsAsync.when(
            loading: () =>
                const Center(child: CircularProgressIndicator(strokeWidth: 2)),
            error: (error, _) => Center(
              child: Text(
                'Couldn\'t load app sounds: $error',
                textAlign: TextAlign.center,
                style: AppTypography.bodyMd.copyWith(color: AppColors.error),
              ),
            ),
            data: (sounds) {
              final filtered = sounds
                  .where(
                    (s) => s.categories.any((c) => c.id == _selectedCategoryId),
                  )
                  .toList();
              if (filtered.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.containerPadding,
                    ),
                    child: Text(
                      'No sounds in this category yet — check back once more are added.',
                      textAlign: TextAlign.center,
                      style: AppTypography.bodyMd.copyWith(
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                  ),
                );
              }
              return ListView.separated(
                controller: widget.scrollController,
                padding: EdgeInsets.only(
                  bottom:
                      MediaQuery.of(context).viewInsets.bottom +
                      MediaQuery.of(context).padding.bottom +
                      AppSpacing.containerPadding,
                ),
                itemCount: filtered.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: AppSpacing.stackSm),
                itemBuilder: (context, index) {
                  final sound = filtered[index];
                  final isPreviewing = _listPreviewingId == sound.id;
                  // The whole row selects the sound now — previously only
                  // the name text itself was tappable for that, which made
                  // for a narrow, easy-to-miss target especially with the
                  // duration/PRO badge sitting outside it. The preview icon
                  // is a nested tap target so it still gets its own tap
                  // (Flutter's gesture arena resolves to the innermost
                  // match, not both at once) without needing to first
                  // select the sound.
                  return TapScale(
                    onTap: _loadingDuration ? null : () => _pickAppSound(sound),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.stackMd,
                        vertical: AppSpacing.stackSm,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainer,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        border: Border.all(color: AppColors.outlineVariant),
                      ),
                      child: Row(
                        children: [
                          TapScale(
                            onTap: () => _toggleListPreview(sound),
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: const BoxDecoration(
                                color: AppColors.primaryContainer,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                isPreviewing
                                    ? Icons.stop_rounded
                                    : Icons.play_arrow,
                                color: AppColors.onPrimaryContainer,
                                size: 18,
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.stackSm),
                          Expanded(
                            child: Text(sound.name, style: AppTypography.bodyMd),
                          ),
                          if (sound.isPro)
                            Container(
                              margin: const EdgeInsets.only(
                                right: AppSpacing.stackSm,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.stackSm,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.statusPro,
                                borderRadius: BorderRadius.circular(
                                  AppRadius.full,
                                ),
                              ),
                              child: Text(
                                'PRO',
                                style: AppTypography.labelCaps.copyWith(
                                  fontSize: 9,
                                  color: AppColors.onPrimary,
                                ),
                              ),
                            ),
                          if (sound.durationMs != null)
                            Text(
                              _formatMs(sound.durationMs!),
                              style: AppTypography.labelCaps.copyWith(
                                color: AppColors.onSurfaceVariant,
                                fontSize: 11,
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAdjustSection() {
    final track = _picked!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            TapScale(
              onTap: track.durationMs > 0 ? _togglePreview : null,
              child: Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  color: AppColors.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _isPreviewPlaying ? Icons.pause : Icons.play_arrow,
                  color: AppColors.onPrimaryContainer,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.stackSm),
            Expanded(
              child: Text(
                track.label,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.bodyMd,
              ),
            ),
            Text(
              '${_formatMs(_trimStart.round())} – ${_formatMs(_trimEnd.round())}',
              style: AppTypography.labelCaps.copyWith(
                color: AppColors.onSurfaceVariant,
                fontSize: 11,
              ),
            ),
          ],
        ),
        if (track.durationMs > 0) ...[
          const SizedBox(height: AppSpacing.stackSm),
          Text(
            'Trim',
            style: AppTypography.labelCaps.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
          RangeSlider(
            min: 0,
            max: track.durationMs.toDouble(),
            values: RangeValues(_trimStart, _trimEnd),
            activeColor: AppColors.primary,
            onChanged: (values) => setState(() {
              _trimStart = values.start;
              _trimEnd = values.end;
            }),
          ),
        ],
        Text(
          'Volume',
          style: AppTypography.labelCaps.copyWith(
            color: AppColors.onSurfaceVariant,
          ),
        ),
        Row(
          children: [
            const Icon(
              Icons.volume_down,
              color: AppColors.onSurfaceVariant,
              size: 18,
            ),
            Expanded(
              child: Slider(
                min: 0,
                max: 1.5,
                value: _volume,
                activeColor: AppColors.primary,
                onChanged: (v) => setState(() => _volume = v),
              ),
            ),
            const Icon(
              Icons.volume_up,
              color: AppColors.onSurfaceVariant,
              size: 18,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.stackMd),
        Row(
          children: [
            if (widget.existing != null) ...[
              TapScale(
                onTap: () =>
                    Navigator.of(context).pop(const AudioSheetResult.removed()),
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: AppColors.errorContainer.withValues(alpha: 0.18),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.error.withValues(alpha: 0.6),
                    ),
                  ),
                  child: const Icon(
                    Icons.delete_outline,
                    color: AppColors.error,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.stackMd),
            ],
            Expanded(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(
                  AudioSheetResult.track(
                    track.copyWith(
                      trimStartMs: _trimStart.round(),
                      trimEndMs: _trimEnd.round(),
                      volume: _volume,
                    ),
                  ),
                ),
                child: Text(
                  widget.existing != null ? 'Update' : 'Add to Creation',
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _AudioTab extends StatelessWidget {
  const _AudioTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: TapScale(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.stackSm),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primaryContainer
                : AppColors.surfaceContainer,
            borderRadius: BorderRadius.circular(AppRadius.full),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: AppTypography.labelCaps.copyWith(
              fontSize: 10,
              color: selected
                  ? AppColors.onPrimaryContainer
                  : AppColors.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

/// Like [_AudioTab] but doesn't self-wrap in [Expanded] — that only works
/// inside a fixed-width Row. This one lives in a horizontally scrolling
/// Row (the mood chips), where Expanded on a scrollable's child throws
/// ("incoming width constraints are unbounded").
class _MoodChip extends StatelessWidget {
  const _MoodChip({
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
          vertical: AppSpacing.stackSm,
        ),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primaryContainer
              : AppColors.surfaceContainer,
          borderRadius: BorderRadius.circular(AppRadius.full),
        ),
        child: Text(
          label,
          style: AppTypography.labelCaps.copyWith(
            fontSize: 10,
            color: selected
                ? AppColors.onPrimaryContainer
                : AppColors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
