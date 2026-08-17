import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/tap_scale.dart';
import '../domain/captured_media.dart';

class CreateScreen extends StatelessWidget {
  const CreateScreen({super.key});

  void _openEditor(BuildContext context, CapturedMedia? media) {
    if (media == null) return;
    context.push('/editor', extra: media);
  }

  void _openEditorForFirst(BuildContext context, List<CapturedMedia>? media) {
    if (media == null || media.isEmpty) return;
    if (media.length > 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Editing one item at a time for now — using your first pick',
          ),
        ),
      );
    }
    context.push('/editor', extra: media.first);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Create New', style: AppTypography.headlineLgMobile),
      ),
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.containerPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Select your starting point.',
              style: AppTypography.bodyMd.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.stackLg),
            Expanded(
              child: _StartCard(
                icon: Icons.photo_camera,
                label: 'Camera',
                description: 'Take a fresh photo or video',
                gradient: const [AppColors.primaryContainer, Color(0xFF6FDB00)],
                onTap: () async {
                  final media = await context.push<CapturedMedia>(
                    '/create/camera',
                  );
                  if (context.mounted) _openEditor(context, media);
                },
              ),
            ),
            const SizedBox(height: AppSpacing.gutter),
            Expanded(
              child: _StartCard(
                icon: Icons.perm_media,
                label: 'Gallery',
                description: 'Pick something you already shot',
                gradient: const [AppColors.secondary, Color(0xFF8B6BFF)],
                onTap: () async {
                  final media = await context.push<List<CapturedMedia>>(
                    '/create/gallery',
                  );
                  if (context.mounted) _openEditorForFirst(context, media);
                },
              ),
            ),
            const SizedBox(height: AppSpacing.gutter),
            Expanded(
              child: _StartCard(
                icon: Icons.view_cozy,
                label: 'Template',
                description: 'Start from a ready-made design',
                gradient: const [AppColors.hotPink, Color(0xFFFF7A9C)],
                onTap: () => context.go('/categories'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StartCard extends StatelessWidget {
  const _StartCard({
    required this.icon,
    required this.label,
    required this.description,
    required this.gradient,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String description;
  final List<Color> gradient;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TapScale(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceCard,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: gradient.first.withValues(alpha: 0.35)),
          boxShadow: [
            BoxShadow(
              color: gradient.first.withValues(alpha: 0.12),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.stackLg),
          child: Row(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: gradient,
                  ),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  boxShadow: [
                    BoxShadow(
                      color: gradient.first.withValues(alpha: 0.45),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(
                  icon,
                  size: 28,
                  color: AppColors.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: AppSpacing.stackMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: AppTypography.headlineLgMobile.copyWith(
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      description,
                      style: AppTypography.bodyMd.copyWith(
                        color: AppColors.onSurfaceVariant,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: AppColors.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
