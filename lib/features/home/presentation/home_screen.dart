import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/tap_scale.dart';
import '../../../shared/widgets/template_card.dart';
import '../../favorites/data/favorites_controller.dart';
import '../domain/category.dart';
import '../domain/template.dart';
import 'home_providers.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(categoriesProvider);
    final templatesAsync = ref.watch(trendingTemplatesProvider);
    final favorites = ref.watch(favoritesControllerProvider);
    final favoritesController = ref.read(favoritesControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: Image.asset(
          'assets/branding/logo.png',
          height: 32,
          fit: BoxFit.contain,
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(categoriesProvider);
          ref.invalidate(trendingTemplatesProvider);
        },
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.stackMd),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.containerPadding,
              ),
              child: Text('Categories', style: AppTypography.headlineLgMobile),
            ),
            const SizedBox(height: AppSpacing.stackSm),
            SizedBox(
              height: 44,
              child: categoriesAsync.when(
                data: (categories) => _CategoryChips(categories: categories),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => _ErrorText(message: '$error'),
              ),
            ),
            const SizedBox(height: AppSpacing.stackLg),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.containerPadding,
              ),
              child: Text(
                'Trending Templates',
                style: AppTypography.headlineLgMobile,
              ),
            ),
            const SizedBox(height: AppSpacing.stackSm),
            templatesAsync.when(
              data: (templates) => _TemplateGrid(
                templates: templates,
                favorites: favorites,
                onFavoriteTap: favoritesController.toggle,
              ),
              loading: () => const Padding(
                padding: EdgeInsets.all(AppSpacing.stackLg),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, _) => Padding(
                padding: const EdgeInsets.all(AppSpacing.containerPadding),
                child: _ErrorText(message: '$error'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryChips extends StatelessWidget {
  const _CategoryChips({required this.categories});

  final List<Category> categories;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.containerPadding,
      ),
      itemCount: categories.length,
      separatorBuilder: (context, index) =>
          const SizedBox(width: AppSpacing.gutter),
      itemBuilder: (context, index) {
        final category = categories[index];
        return TapScale(
          onTap: () => context.push(
            '/categories/${category.slug}',
            extra: category.name,
          ),
          child: Chip(
            label: Text(category.name),
            backgroundColor: AppColors.surfaceElevated,
            labelStyle: AppTypography.bodyMd,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.stackMd),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(9999),
            ),
          ),
        );
      },
    );
  }
}

class _TemplateGrid extends StatelessWidget {
  const _TemplateGrid({
    required this.templates,
    required this.favorites,
    required this.onFavoriteTap,
  });

  final List<Template> templates;
  final Set<int> favorites;
  final ValueChanged<int> onFavoriteTap;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.containerPadding,
      ),
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
          template: template.copyWith(
            isFavorited: favorites.contains(template.id),
          ),
          onTap: () => context.push('/templates/${template.id}'),
          onFavoriteTap: () => onFavoriteTap(template.id),
        );
      },
    );
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.containerPadding,
      ),
      child: Text(
        'Couldn\'t load: $message',
        style: AppTypography.bodyMd.copyWith(color: AppColors.error),
      ),
    );
  }
}
