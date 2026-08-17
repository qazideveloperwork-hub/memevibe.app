enum TemplateType { image, video, status }

TemplateType templateTypeFromString(String value) => switch (value) {
  'image' => TemplateType.image,
  'video' => TemplateType.video,
  'status' => TemplateType.status,
  _ => throw ArgumentError('Unknown template type: $value'),
};

class Template {
  const Template({
    required this.id,
    required this.categoryId,
    required this.name,
    required this.type,
    required this.previewUrl,
    this.posterUrl,
    required this.isPro,
    required this.tags,
    required this.useCount,
    required this.isFavorited,
  });

  factory Template.fromJson(Map<String, dynamic> json) => Template(
    id: json['id'] as int,
    categoryId: json['category_id'] as int,
    name: json['name'] as String,
    type: templateTypeFromString(json['type'] as String),
    previewUrl: json['preview_url'] as String,
    posterUrl: json['poster_url'] as String?,
    isPro: json['is_pro'] as bool,
    tags: (json['tags'] as List<dynamic>? ?? []).cast<String>(),
    useCount: json['use_count'] as int,
    isFavorited: json['is_favorited'] as bool? ?? false,
  );

  final int id;
  final int categoryId;
  final String name;
  final TemplateType type;
  final String previewUrl;

  /// Set only for video/status templates — previewUrl points at the actual
  /// video file for those (what "Use This Template" loads into the editor),
  /// which an Image widget can't decode, so this still frame is what grid/
  /// detail screens should display instead. Image templates leave this
  /// null and just display previewUrl directly — see [displayImageUrl].
  final String? posterUrl;
  final bool isPro;
  final List<String> tags;
  final int useCount;
  final bool isFavorited;

  /// Whatever should actually be decoded as an `Image` — never previewUrl
  /// directly for a video/status template.
  String get displayImageUrl => posterUrl ?? previewUrl;

  Template copyWith({bool? isFavorited}) => Template(
    id: id,
    categoryId: categoryId,
    name: name,
    type: type,
    previewUrl: previewUrl,
    posterUrl: posterUrl,
    isPro: isPro,
    tags: tags,
    useCount: useCount,
    isFavorited: isFavorited ?? this.isFavorited,
  );
}
