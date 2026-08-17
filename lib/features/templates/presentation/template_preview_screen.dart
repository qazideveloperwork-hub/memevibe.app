import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import '../../../core/network/api_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/template_card.dart';
import '../../create/domain/captured_media.dart';
import '../../favorites/data/favorites_controller.dart';
import '../../home/data/home_repository.dart';
import '../../home/domain/template.dart';
import '../data/template_list_controller.dart';

final _templateProvider = FutureProvider.family<Template, int>(
  (ref, id) => ref.watch(homeRepositoryProvider).fetchTemplate(id),
);

class TemplatePreviewScreen extends ConsumerWidget {
  const TemplatePreviewScreen({super.key, required this.templateId});

  final int templateId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final templateAsync = ref.watch(_templateProvider(templateId));

    return Scaffold(
      backgroundColor: AppColors.background,
      body: templateAsync.when(
        data: (template) => _PreviewBody(template: template),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Text(
            'Couldn\'t load: $error',
            style: AppTypography.bodyMd.copyWith(color: AppColors.error),
          ),
        ),
      ),
    );
  }
}

class _PreviewBody extends ConsumerStatefulWidget {
  const _PreviewBody({required this.template});

  final Template template;

  @override
  ConsumerState<_PreviewBody> createState() => _PreviewBodyState();
}

class _PreviewBodyState extends ConsumerState<_PreviewBody> {
  bool _isLoadingTemplate = false;

  Future<void> _useTemplate(Template template) async {
    // The editor now handles video as a full source (filters, trim, text/
    // sticker overlays, real export) — this used to hard-block anything but
    // TemplateType.image because that support didn't exist yet.
    final isVideo = template.type != TemplateType.image;
    setState(() => _isLoadingTemplate = true);
    try {
      final response = await Dio().get<List<int>>(
        ApiConfig.resolveAssetUrl(template.previewUrl),
        options: Options(responseType: ResponseType.bytes),
      );
      final dir = await getTemporaryDirectory();
      final extension = isVideo ? 'mp4' : 'jpg';
      final file = File(
        '${dir.path}/template_${template.id}_${DateTime.now().microsecondsSinceEpoch}.$extension',
      );
      await file.writeAsBytes(response.data!);
      if (!mounted) return;
      context.push(
        '/editor',
        extra: CapturedMedia(
          path: file.path,
          type: isVideo ? CapturedMediaType.video : CapturedMediaType.image,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Couldn\'t load template: $error')),
      );
    } finally {
      if (mounted) setState(() => _isLoadingTemplate = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final template = widget.template;
    final similarState = ref.watch(
      templateListControllerProvider(
        TemplateListArgs(categorySlug: null, type: template.type),
      ),
    );
    final similar = similarState.templates
        .where((t) => t.id != template.id)
        .take(4)
        .toList();

    return Stack(
      children: [
        ListView(
          padding: EdgeInsets.zero,
          children: [
            AspectRatio(
              aspectRatio: 9 / 16,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _TemplateHeroMedia(template: template),
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(
                        AppSpacing.containerPadding,
                      ),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                            AppColors.background,
                            AppColors.background.withValues(alpha: 0.0),
                          ],
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (template.isPro)
                            Container(
                              margin: const EdgeInsets.only(
                                bottom: AppSpacing.stackSm,
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
                                  color: AppColors.onPrimary,
                                ),
                              ),
                            ),
                          Text(
                            template.name,
                            style: AppTypography.headlineLgMobile,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${template.useCount} uses',
                            style: AppTypography.bodyMd.copyWith(
                              color: AppColors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.containerPadding,
                AppSpacing.stackLg,
                AppSpacing.containerPadding,
                120 + MediaQuery.of(context).padding.bottom,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Similar Vibes', style: AppTypography.headlineLgMobile),
                  const SizedBox(height: AppSpacing.stackMd),
                  if (similar.isEmpty)
                    Text(
                      'No similar templates yet',
                      style: AppTypography.bodyMd,
                    )
                  else
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: similar.length,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: AppSpacing.gutter,
                            mainAxisSpacing: AppSpacing.gutter,
                            childAspectRatio: 1,
                          ),
                      itemBuilder: (context, index) => TemplateCard(
                        template: similar[index],
                        onTap: () => context.pushReplacement(
                          '/templates/${similar[index].id}',
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        Positioned(
          top: AppSpacing.stackMd + MediaQuery.of(context).padding.top,
          left: AppSpacing.containerPadding,
          child: _CircleButton(
            icon: Icons.arrow_back,
            onTap: () => context.pop(),
          ),
        ),
        Positioned(
          top: AppSpacing.stackMd + MediaQuery.of(context).padding.top,
          right: AppSpacing.containerPadding,
          child: Consumer(
            builder: (context, ref, _) {
              final isFavorited = ref.watch(
                favoritesControllerProvider.select(
                  (f) => f.contains(template.id),
                ),
              );
              return _CircleButton(
                icon: isFavorited ? Icons.favorite : Icons.favorite_border,
                iconColor: isFavorited ? AppColors.hotPink : AppColors.primary,
                onTap: () => ref
                    .read(favoritesControllerProvider.notifier)
                    .toggle(template.id),
              );
            },
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.containerPadding),
              decoration: BoxDecoration(
                color: AppColors.background.withValues(alpha: 0.9),
                border: const Border(
                  top: BorderSide(color: AppColors.outlineVariant),
                ),
              ),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isLoadingTemplate
                      ? null
                      : () => _useTemplate(template),
                  icon: _isLoadingTemplate
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.onPrimaryContainer,
                          ),
                        )
                      : const Icon(Icons.bolt),
                  label: Text(
                    _isLoadingTemplate ? 'Loading...' : 'Use This Template',
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Image templates render as before. Video/status templates autoplay
/// (looping, muted) — a static poster on the detail screen would be exactly
/// as ambiguous as the grid thumbnail; this is the one place in the app
/// where actually playing the clip is cheap (a single video, not N of them
/// in a scrolling grid).
class _TemplateHeroMedia extends StatefulWidget {
  const _TemplateHeroMedia({required this.template});

  final Template template;

  @override
  State<_TemplateHeroMedia> createState() => _TemplateHeroMediaState();
}

class _TemplateHeroMediaState extends State<_TemplateHeroMedia> {
  VideoPlayerController? _controller;

  @override
  void initState() {
    super.initState();
    if (widget.template.type != TemplateType.image) {
      final controller = VideoPlayerController.networkUrl(
        Uri.parse(ApiConfig.resolveAssetUrl(widget.template.previewUrl)),
      );
      _controller = controller;
      controller.initialize().then((_) {
        if (!mounted) return;
        controller.setLooping(true);
        controller.setVolume(0);
        controller.play();
        setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Container(
      color: AppColors.surfaceContainerHighest,
      child: (controller == null || !controller.value.isInitialized)
          ? Image.network(
              ApiConfig.resolveAssetUrl(widget.template.displayImageUrl),
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => const Center(
                child: Icon(
                  Icons.broken_image_outlined,
                  size: 48,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            )
          : FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: controller.value.size.width,
                height: controller.value.size.height,
                child: VideoPlayer(controller),
              ),
            ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({
    required this.icon,
    required this.onTap,
    this.iconColor = AppColors.primary,
  });

  final IconData icon;
  final VoidCallback onTap;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceElevated,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.stackSm),
          child: Icon(icon, color: iconColor),
        ),
      ),
    );
  }
}
