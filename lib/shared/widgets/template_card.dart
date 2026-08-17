import 'package:flutter/material.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../features/home/domain/template.dart';
import 'tap_scale.dart';

class TemplateCard extends StatelessWidget {
  const TemplateCard({
    super.key,
    required this.template,
    this.onTap,
    this.onFavoriteTap,
  });

  final Template template;
  final VoidCallback? onTap;
  final VoidCallback? onFavoriteTap;

  @override
  Widget build(BuildContext context) {
    return TapScale(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(
              color: AppColors.surfaceCard,
              child: Image.network(
                ApiConfig.resolveAssetUrl(template.displayImageUrl),
                fit: BoxFit.cover,
                loadingBuilder: (context, child, progress) => progress == null
                    ? child
                    : const Center(child: CircularProgressIndicator()),
                errorBuilder: (context, error, stackTrace) => const Center(
                  child: Icon(
                    Icons.broken_image_outlined,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      AppColors.background.withValues(alpha: 0.85),
                      AppColors.background.withValues(alpha: 0.0),
                    ],
                    stops: const [0, 0.5],
                  ),
                ),
              ),
            ),
            // Grid thumbnails are static posters even for video templates
            // (playing N videos at once in a scrolling grid isn't
            // reasonable) — this badge is the cheap signal that there's
            // real motion once you open it, real playback happens on the
            // template detail screen instead.
            if (template.type != TemplateType.image)
              const Center(
                child: Icon(
                  Icons.play_circle_fill,
                  size: 44,
                  color: Colors.white70,
                ),
              ),
            Positioned(
              top: AppSpacing.stackSm,
              right: AppSpacing.stackSm,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.stackSm,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: template.isPro
                      ? AppColors.statusPro
                      : AppColors.primaryContainer,
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (template.isPro) ...[
                      const Icon(
                        Icons.workspace_premium,
                        size: 11,
                        color: AppColors.onPrimary,
                      ),
                      const SizedBox(width: 2),
                    ],
                    Text(
                      template.isPro ? 'PRO' : 'FREE',
                      style: AppTypography.labelCaps.copyWith(
                        color: AppColors.onPrimary,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (onFavoriteTap != null)
              Positioned(
                top: AppSpacing.stackSm,
                left: AppSpacing.stackSm,
                child: GestureDetector(
                  onTap: onFavoriteTap,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.background.withValues(alpha: 0.45),
                    ),
                    child: Icon(
                      template.isFavorited
                          ? Icons.favorite
                          : Icons.favorite_border,
                      size: 18,
                      color: template.isFavorited
                          ? AppColors.hotPink
                          : Colors.white,
                    ),
                  ),
                ),
              ),
            Positioned(
              left: AppSpacing.stackSm,
              right: AppSpacing.stackSm,
              bottom: AppSpacing.stackSm,
              child: Text(
                template.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.bodyMd.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
