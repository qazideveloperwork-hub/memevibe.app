import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/tap_scale.dart';
import '../../../shared/widgets/template_card.dart';
import '../../favorites/data/favorites_controller.dart';
import '../../home/domain/template.dart';
import '../data/template_list_controller.dart';

class TemplateListScreen extends ConsumerStatefulWidget {
  const TemplateListScreen({
    super.key,
    required this.categorySlug,
    this.categoryName,
  });

  final String categorySlug;
  final String? categoryName;

  @override
  ConsumerState<TemplateListScreen> createState() => _TemplateListScreenState();
}

class _TemplateListScreenState extends ConsumerState<TemplateListScreen> {
  TemplateType? _typeFilter;
  final _scrollController = ScrollController();

  TemplateListArgs get _args =>
      TemplateListArgs(categorySlug: widget.categorySlug, type: _typeFilter);

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >
        _scrollController.position.maxScrollExtent - 400) {
      ref.read(templateListControllerProvider(_args).notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(templateListControllerProvider(_args));
    final favorites = ref.watch(favoritesControllerProvider);
    final favoritesController = ref.read(favoritesControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.categoryName ?? 'Templates',
          style: AppTypography.headlineLgMobile,
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: AppSpacing.stackSm),
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.containerPadding,
                ),
                children: [
                  _FilterChip(
                    label: 'All',
                    selected: _typeFilter == null,
                    onTap: () => setState(() => _typeFilter = null),
                  ),
                  const SizedBox(width: AppSpacing.gutter),
                  _FilterChip(
                    label: 'Image',
                    selected: _typeFilter == TemplateType.image,
                    onTap: () =>
                        setState(() => _typeFilter = TemplateType.image),
                  ),
                  const SizedBox(width: AppSpacing.gutter),
                  _FilterChip(
                    label: 'Video',
                    selected: _typeFilter == TemplateType.video,
                    onTap: () =>
                        setState(() => _typeFilter = TemplateType.video),
                  ),
                  const SizedBox(width: AppSpacing.gutter),
                  _FilterChip(
                    label: 'Status',
                    selected: _typeFilter == TemplateType.status,
                    onTap: () =>
                        setState(() => _typeFilter = TemplateType.status),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.stackMd),
            Expanded(
              child: _buildBody(state, favorites, favoritesController.toggle),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(
    TemplateListState state,
    Set<int> favorites,
    ValueChanged<int> onFavoriteTap,
  ) {
    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.error != null && state.templates.isEmpty) {
      return Center(
        child: Text(
          'Couldn\'t load: ${state.error}',
          style: AppTypography.bodyMd.copyWith(color: AppColors.error),
        ),
      );
    }
    if (state.templates.isEmpty) {
      return Center(
        child: Text('No templates yet', style: AppTypography.bodyMd),
      );
    }

    return RefreshIndicator(
      onRefresh: () =>
          ref.read(templateListControllerProvider(_args).notifier).refresh(),
      child: GridView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.containerPadding,
          vertical: AppSpacing.stackSm,
        ),
        itemCount: state.templates.length + (state.hasMore ? 1 : 0),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: AppSpacing.gutter,
          mainAxisSpacing: AppSpacing.gutter,
          childAspectRatio: 0.75,
        ),
        itemBuilder: (context, index) {
          if (index >= state.templates.length) {
            return const Center(child: CircularProgressIndicator());
          }
          final template = state.templates[index];
          return TemplateCard(
            template: template.copyWith(
              isFavorited: favorites.contains(template.id),
            ),
            onTap: () => context.push('/templates/${template.id}'),
            onFavoriteTap: () => onFavoriteTap(template.id),
          );
        },
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
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
              : AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(AppRadius.full),
        ),
        child: Text(
          label,
          style: AppTypography.labelCaps.copyWith(
            color: selected ? AppColors.onPrimaryContainer : AppColors.primary,
          ),
        ),
      ),
    );
  }
}
