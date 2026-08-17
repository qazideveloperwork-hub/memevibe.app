import 'template.dart';

class TemplatePage {
  const TemplatePage({required this.templates, required this.hasMore});

  factory TemplatePage.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as List<dynamic>;
    final meta = json['meta'] as Map<String, dynamic>;
    return TemplatePage(
      templates: data
          .map((json) => Template.fromJson(json as Map<String, dynamic>))
          .toList(),
      hasMore: (meta['current_page'] as int) < (meta['last_page'] as int),
    );
  }

  final List<Template> templates;
  final bool hasMore;
}
