import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_providers.dart';
import '../domain/app_sound.dart';

class AppSoundRepository {
  AppSoundRepository(this._client);

  final ApiClient _client;

  Future<List<AppSoundOption>> fetchAppSounds() async {
    final response = await _client.dio.get(
      '/app-sounds',
      queryParameters: {'per_page': 500},
    );
    final data = response.data['data'] as List<dynamic>;
    return data
        .map((json) => AppSoundOption.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<List<SoundCategory>> fetchSoundCategories() async {
    final response = await _client.dio.get('/sound-categories');
    final data = response.data['data'] as List<dynamic>;
    return data
        .map((json) => SoundCategory.fromJson(json as Map<String, dynamic>))
        .toList();
  }
}

final appSoundRepositoryProvider = Provider<AppSoundRepository>(
  (ref) => AppSoundRepository(ref.watch(apiClientProvider)),
);

final appSoundsProvider = FutureProvider<List<AppSoundOption>>(
  (ref) => ref.watch(appSoundRepositoryProvider).fetchAppSounds(),
);

final soundCategoriesProvider = FutureProvider<List<SoundCategory>>(
  (ref) => ref.watch(appSoundRepositoryProvider).fetchSoundCategories(),
);
