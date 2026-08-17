import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../home/data/home_repository.dart';
import '../../home/domain/template.dart';

class TemplateListArgs {
  const TemplateListArgs({this.categorySlug, this.type});

  final String? categorySlug;
  final TemplateType? type;

  @override
  bool operator ==(Object other) =>
      other is TemplateListArgs &&
      other.categorySlug == categorySlug &&
      other.type == type;

  @override
  int get hashCode => Object.hash(categorySlug, type);
}

class TemplateListState {
  const TemplateListState({
    this.templates = const [],
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.error,
    this.page = 1,
  });

  final List<Template> templates;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final Object? error;
  final int page;

  TemplateListState copyWith({
    List<Template>? templates,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    Object? error,
    bool clearError = false,
    int? page,
  }) {
    return TemplateListState(
      templates: templates ?? this.templates,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      error: clearError ? null : (error ?? this.error),
      page: page ?? this.page,
    );
  }
}

class TemplateListController extends StateNotifier<TemplateListState> {
  TemplateListController(this._repository, this._args)
    : super(const TemplateListState(isLoading: true)) {
    _load();
  }

  final HomeRepository _repository;
  final TemplateListArgs _args;

  Future<void> _load() async {
    try {
      final result = await _repository.fetchTemplatePage(
        categorySlug: _args.categorySlug,
        type: _args.type,
        page: 1,
      );
      state = state.copyWith(
        templates: result.templates,
        hasMore: result.hasMore,
        isLoading: false,
        page: 1,
        clearError: true,
      );
    } catch (error) {
      state = state.copyWith(isLoading: false, error: error);
    }
  }

  Future<void> refresh() async {
    state = const TemplateListState(isLoading: true);
    await _load();
  }

  Future<void> loadMore() async {
    if (state.isLoadingMore || !state.hasMore || state.isLoading) return;
    state = state.copyWith(isLoadingMore: true);
    try {
      final nextPage = state.page + 1;
      final result = await _repository.fetchTemplatePage(
        categorySlug: _args.categorySlug,
        type: _args.type,
        page: nextPage,
      );
      state = state.copyWith(
        templates: [...state.templates, ...result.templates],
        hasMore: result.hasMore,
        isLoadingMore: false,
        page: nextPage,
      );
    } catch (error) {
      state = state.copyWith(isLoadingMore: false, error: error);
    }
  }
}

final templateListControllerProvider =
    StateNotifierProvider.family<
      TemplateListController,
      TemplateListState,
      TemplateListArgs
    >(
      (ref, args) =>
          TemplateListController(ref.watch(homeRepositoryProvider), args),
    );
