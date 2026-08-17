/// Admin-managed via the backend's Sound Categories resource — not a fixed
/// set. New categories (e.g. "Laugh") show up automatically once created,
/// no app update needed.
class SoundCategory {
  const SoundCategory({
    required this.id,
    required this.name,
    required this.slug,
    required this.sortOrder,
  });

  factory SoundCategory.fromJson(Map<String, dynamic> json) => SoundCategory(
    id: json['id'] as int,
    name: json['name'] as String,
    slug: json['slug'] as String,
    sortOrder: json['sort_order'] as int,
  );

  final int id;
  final String name;
  final String slug;
  final int sortOrder;
}

class AppSoundOption {
  const AppSoundOption({
    required this.id,
    required this.name,
    required this.categories,
    required this.audioUrl,
    required this.isPro,
    required this.useCount,
    this.durationMs,
  });

  factory AppSoundOption.fromJson(Map<String, dynamic> json) => AppSoundOption(
    id: json['id'] as int,
    name: json['name'] as String,
    categories: (json['categories'] as List<dynamic>)
        .map((c) => SoundCategory.fromJson(c as Map<String, dynamic>))
        .toList(),
    audioUrl: json['audio_url'] as String,
    durationMs: json['duration_ms'] as int?,
    isPro: json['is_pro'] as bool,
    useCount: json['use_count'] as int,
  );

  final int id;
  final String name;
  final List<SoundCategory> categories;
  final String audioUrl;
  final int? durationMs;
  final bool isPro;
  final int useCount;
}
