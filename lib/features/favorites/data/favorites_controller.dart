import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _prefsKey = 'favorite_template_ids';

/// Favorites are stored on-device for now (auth/Phase 7 isn't built yet, so
/// there's no account to sync them to). Backed by [SharedPreferences] since
/// it's just a small set of template ids — a heavier store like drift isn't
/// warranted for this.
class FavoritesController extends StateNotifier<Set<int>> {
  FavoritesController(this._prefs) : super(_load(_prefs));

  final SharedPreferences _prefs;

  static Set<int> _load(SharedPreferences prefs) {
    final stored = prefs.getStringList(_prefsKey) ?? const [];
    return stored.map(int.parse).toSet();
  }

  Future<void> toggle(int templateId) async {
    final next = Set<int>.from(state);
    if (!next.remove(templateId)) {
      next.add(templateId);
    }
    state = next;
    await _prefs.setStringList(
      _prefsKey,
      next.map((id) => id.toString()).toList(),
    );
  }

  bool isFavorited(int templateId) => state.contains(templateId);
}

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError(
    'overridden in main.dart after awaiting SharedPreferences.getInstance()',
  );
});

final favoritesControllerProvider =
    StateNotifierProvider<FavoritesController, Set<int>>(
      (ref) => FavoritesController(ref.watch(sharedPreferencesProvider)),
    );
