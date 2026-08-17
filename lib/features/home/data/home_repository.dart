import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_providers.dart';
import '../domain/category.dart';
import '../domain/template.dart';
import '../domain/template_page.dart';

class HomeRepository {
  HomeRepository(this._client);

  final ApiClient _client;

  Future<List<Category>> fetchCategories() async {
    final response = await _client.dio.get('/categories');
    final data = response.data['data'] as List<dynamic>;
    return data
        .map((json) => Category.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<List<Template>> fetchTemplates({
    String? categorySlug,
    int perPage = 20,
  }) async {
    final page = await fetchTemplatePage(
      categorySlug: categorySlug,
      perPage: perPage,
    );
    return page.templates;
  }

  Future<TemplatePage> fetchTemplatePage({
    String? categorySlug,
    TemplateType? type,
    int page = 1,
    int perPage = 20,
  }) async {
    final response = await _client.dio.get(
      '/templates',
      queryParameters: {
        'per_page': perPage,
        'page': page,
        if (categorySlug != null) 'category': categorySlug,
        if (type != null) 'type': type.name,
      },
    );
    return TemplatePage.fromJson(response.data as Map<String, dynamic>);
  }

  Future<Template> fetchTemplate(int id) async {
    final response = await _client.dio.get('/templates/$id');
    return Template.fromJson(response.data['data'] as Map<String, dynamic>);
  }
}

final homeRepositoryProvider = Provider<HomeRepository>(
  (ref) => HomeRepository(ref.watch(apiClientProvider)),
);
