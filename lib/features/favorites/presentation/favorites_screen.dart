import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/template_card.dart';
import '../../home/data/home_repository.dart';
import '../../home/domain/template.dart';
import '../data/favorites_controller.dart';

final _favoritedTemplatesProvider = FutureProvider<List<Template>>((ref) async {
  final ids = ref.watch(favoritesControllerProvider);
  final repository = ref.watch(homeRepositoryProvider);
  final templates = await Future.wait(ids.map(repository.fetchTemplate));
  return templates;
});

class FavoritesScreen extends ConsumerWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favoritesAsync = ref.watch(_favoritedTemplatesProvider);
    final favoritesController = ref.read(favoritesControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: Text('Favorites', style: AppTypography.headlineLgMobile),
      ),
      body: SafeArea(
        top: false,
        child: favoritesAsync.when(
          data: (templates) {
            if (templates.isEmpty) {
              return _EmptyState();
            }
            return RefreshIndicator(
              onRefresh: () => ref.refresh(_favoritedTemplatesProvider.future),
              child: GridView.builder(
                padding: const EdgeInsets.all(AppSpacing.containerPadding),
                itemCount: templates.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: AppSpacing.gutter,
                  mainAxisSpacing: AppSpacing.gutter,
                  childAspectRatio: 0.75,
                ),
                itemBuilder: (context, index) {
                  final template = templates[index];
                  return TemplateCard(
                    template: template.copyWith(isFavorited: true),
                    onTap: () => context.push('/templates/${template.id}'),
                    onFavoriteTap: () =>
                        favoritesController.toggle(template.id),
                  );
                },
              ),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(
            child: Text(
              'Couldn\'t load favorites: $error',
              style: AppTypography.bodyMd.copyWith(color: AppColors.error),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.containerPadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.favorite_border,
              size: 48,
              color: AppColors.onSurfaceVariant,
            ),
            const SizedBox(height: AppSpacing.stackMd),
            Text(
              'No favorites yet',
              style: AppTypography.headlineLgMobile,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.stackSm),
            Text(
              'Tap the heart on any template to save it here.',
              style: AppTypography.bodyMd.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
