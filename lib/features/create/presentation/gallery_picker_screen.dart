import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/tap_scale.dart';
import '../domain/captured_media.dart';

class GalleryPickerScreen extends StatefulWidget {
  const GalleryPickerScreen({super.key});

  @override
  State<GalleryPickerScreen> createState() => _GalleryPickerScreenState();
}

enum _LoadState { loading, denied, ready, error }

class _GalleryPickerScreenState extends State<GalleryPickerScreen> {
  _LoadState _state = _LoadState.loading;
  List<AssetEntity> _assets = [];
  final Set<AssetEntity> _selected = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final permission = await PhotoManager.requestPermissionExtend();
    if (!permission.isAuth && !permission.hasAccess) {
      setState(() => _state = _LoadState.denied);
      return;
    }
    try {
      final paths = await PhotoManager.getAssetPathList(
        onlyAll: true,
        type: RequestType.common,
      );
      if (paths.isEmpty) {
        setState(() {
          _assets = [];
          _state = _LoadState.ready;
        });
        return;
      }
      final assets = await paths.first.getAssetListPaged(page: 0, size: 120);
      setState(() {
        _assets = assets;
        _state = _LoadState.ready;
      });
    } catch (_) {
      setState(() => _state = _LoadState.error);
    }
  }

  void _toggle(AssetEntity asset) {
    setState(() {
      if (_selected.contains(asset)) {
        _selected.remove(asset);
      } else {
        _selected.add(asset);
      }
    });
  }

  Future<void> _continue() async {
    final media = <CapturedMedia>[];
    for (final asset in _selected) {
      final file = await asset.file;
      if (file != null) {
        media.add(
          CapturedMedia(
            path: file.path,
            type: asset.type == AssetType.video
                ? CapturedMediaType.video
                : CapturedMediaType.image,
          ),
        );
      }
    }
    if (!mounted) return;
    context.pop(media);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: false,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(),
        ),
        title: Text('Add Your Media', style: AppTypography.headlineLgMobile),
      ),
      body: _buildBody(),
      bottomNavigationBar: _selected.isEmpty
          ? null
          : SafeArea(
              child: Container(
                margin: const EdgeInsets.all(AppSpacing.containerPadding),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.stackLg,
                  vertical: AppSpacing.stackMd,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(AppRadius.full),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.35),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          alignment: Alignment.center,
                          decoration: const BoxDecoration(
                            color: AppColors.secondary,
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            '${_selected.length}',
                            style: AppTypography.labelCaps.copyWith(
                              color: AppColors.onSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.stackSm),
                        Text(
                          'selected',
                          style: AppTypography.bodyMd.copyWith(
                            color: AppColors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    ElevatedButton.icon(
                      onPressed: _continue,
                      icon: const Icon(Icons.arrow_forward),
                      label: const Text('Continue'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildBody() {
    switch (_state) {
      case _LoadState.loading:
        return const Center(child: CircularProgressIndicator());
      case _LoadState.denied:
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.containerPadding),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.perm_media_outlined,
                  size: 48,
                  color: AppColors.onSurfaceVariant,
                ),
                const SizedBox(height: AppSpacing.stackMd),
                Text(
                  'Photo & video access is needed to pick media.',
                  textAlign: TextAlign.center,
                  style: AppTypography.bodyMd,
                ),
                const SizedBox(height: AppSpacing.stackMd),
                ElevatedButton(
                  onPressed: () => PhotoManager.openSetting(),
                  child: const Text('Open Settings'),
                ),
              ],
            ),
          ),
        );
      case _LoadState.error:
        return Center(
          child: Text(
            'Couldn\'t load your media',
            style: AppTypography.bodyMd.copyWith(color: AppColors.error),
          ),
        );
      case _LoadState.ready:
        if (_assets.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.image_not_supported_outlined,
                  size: 48,
                  color: AppColors.onSurfaceVariant,
                ),
                const SizedBox(height: AppSpacing.stackMd),
                Text('No photos or videos found', style: AppTypography.bodyMd),
              ],
            ),
          );
        }
        return GridView.builder(
          padding: const EdgeInsets.all(AppSpacing.base),
          itemCount: _assets.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: AppSpacing.base,
            mainAxisSpacing: AppSpacing.base,
          ),
          itemBuilder: (context, index) {
            final asset = _assets[index];
            return _AssetTile(
              asset: asset,
              selected: _selected.contains(asset),
              onTap: () => _toggle(asset),
            );
          },
        );
    }
  }
}

class _AssetTile extends StatelessWidget {
  const _AssetTile({
    required this.asset,
    required this.selected,
    required this.onTap,
  });

  final AssetEntity asset;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TapScale(
      onTap: onTap,
      scale: 0.92,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(
            color: selected ? AppColors.secondary : Colors.transparent,
            width: 2,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.sm - 2),
          child: Stack(
            fit: StackFit.expand,
            children: [
              FutureBuilder<Uint8List?>(
                future: asset.thumbnailDataWithSize(
                  const ThumbnailSize(200, 200),
                ),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return Container(color: AppColors.surfaceCard);
                  }
                  return Image.memory(snapshot.data!, fit: BoxFit.cover);
                },
              ),
              AnimatedOpacity(
                duration: const Duration(milliseconds: 150),
                opacity: selected ? 1 : 0,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.background.withValues(alpha: 0.35),
                  ),
                ),
              ),
              if (asset.type == AssetType.video)
                Positioned(
                  bottom: 4,
                  right: 4,
                  child: Row(
                    children: [
                      const Icon(
                        Icons.play_arrow,
                        size: 14,
                        color: Colors.white,
                      ),
                      Text(
                        _formatDuration(asset.videoDuration),
                        style: AppTypography.labelCaps.copyWith(
                          color: Colors.white,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
              Positioned(
                top: 4,
                right: 4,
                child: AnimatedScale(
                  duration: const Duration(milliseconds: 150),
                  scale: selected ? 1 : 0,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.secondary,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.secondary.withValues(alpha: 0.5),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.check,
                      size: 14,
                      color: AppColors.onSecondary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(1, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
