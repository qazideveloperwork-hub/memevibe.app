import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/home_repository.dart';
import '../domain/category.dart';
import '../domain/template.dart';

final categoriesProvider = FutureProvider<List<Category>>(
  (ref) => ref.watch(homeRepositoryProvider).fetchCategories(),
);

final trendingTemplatesProvider = FutureProvider<List<Template>>(
  (ref) => ref.watch(homeRepositoryProvider).fetchTemplates(),
);
