import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_providers.dart';
import '../../favorites/data/favorites_controller.dart' show sharedPreferencesProvider;
import '../domain/auth_user.dart';
import 'auth_repository.dart';

const _tokenPrefsKey = 'auth_token';

enum AuthStatus { authenticated, unauthenticated }

class AuthState {
  const AuthState({required this.status, this.user});

  const AuthState.unauthenticated() : status = AuthStatus.unauthenticated, user = null;

  final AuthStatus status;
  final AuthUser? user;

  bool get isAuthenticated => status == AuthStatus.authenticated;
}

/// Session lives for the app's lifetime: token persisted to
/// [SharedPreferences] so login survives an app restart, and mirrored onto
/// [ApiClient] so every other repository's requests are authenticated
/// automatically without each one knowing about auth.
class AuthController extends StateNotifier<AuthState> {
  AuthController(this._repository, this._client, this._prefs)
    : super(const AuthState.unauthenticated()) {
    _restoreSession();
  }

  final AuthRepository _repository;
  final ApiClient _client;
  final SharedPreferences _prefs;

  void _restoreSession() {
    final token = _prefs.getString(_tokenPrefsKey);
    if (token == null) return;
    _client.setAuthToken(token);
    // Optimistic: authenticated with no user yet while /auth/me resolves,
    // rather than bouncing through unauthenticated first (avoids a
    // logged-out flash on every app start for someone who's already
    // signed in).
    state = const AuthState(status: AuthStatus.authenticated);
    _repository
        .me()
        .then((user) {
          if (mounted) state = AuthState(status: AuthStatus.authenticated, user: user);
        })
        .catchError((_) {
          // Token expired/revoked server-side — nothing to recover, drop
          // back to a clean logged-out state.
          if (mounted) _clearSession();
        });
  }

  Future<void> register({
    required String name,
    required String email,
    required String password,
  }) async {
    final result = await _repository.register(
      name: name,
      email: email,
      password: password,
    );
    await _setSession(result);
  }

  Future<void> login({required String email, required String password}) async {
    final result = await _repository.login(email: email, password: password);
    await _setSession(result);
  }

  Future<void> logout() async {
    await _repository.logout();
    await _clearSession();
  }

  Future<void> _setSession(AuthResult result) async {
    await _prefs.setString(_tokenPrefsKey, result.token);
    _client.setAuthToken(result.token);
    state = AuthState(status: AuthStatus.authenticated, user: result.user);
  }

  Future<void> _clearSession() async {
    await _prefs.remove(_tokenPrefsKey);
    _client.setAuthToken(null);
    state = const AuthState.unauthenticated();
  }
}

final authControllerProvider = StateNotifierProvider<AuthController, AuthState>(
  (ref) => AuthController(
    ref.watch(authRepositoryProvider),
    ref.watch(apiClientProvider),
    ref.watch(sharedPreferencesProvider),
  ),
);
