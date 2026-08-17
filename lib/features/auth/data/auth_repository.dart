import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_providers.dart';
import '../domain/auth_exception.dart';
import '../domain/auth_user.dart';

class AuthResult {
  const AuthResult({required this.user, required this.token});

  final AuthUser user;
  final String token;
}

class AuthRepository {
  AuthRepository(this._client);

  final ApiClient _client;

  Future<AuthResult> register({
    required String name,
    required String email,
    required String password,
  }) async {
    try {
      final response = await _client.dio.post(
        '/auth/register',
        data: {'name': name, 'email': email, 'password': password},
      );
      return AuthResult(
        user: AuthUser.fromJson(response.data['user'] as Map<String, dynamic>),
        token: response.data['token'] as String,
      );
    } on DioException catch (error) {
      throw AuthException.fromDioException(error);
    }
  }

  Future<AuthResult> login({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _client.dio.post(
        '/auth/login',
        data: {'email': email, 'password': password},
      );
      return AuthResult(
        user: AuthUser.fromJson(response.data['user'] as Map<String, dynamic>),
        token: response.data['token'] as String,
      );
    } on DioException catch (error) {
      throw AuthException.fromDioException(error);
    }
  }

  Future<void> logout() async {
    try {
      await _client.dio.post('/auth/logout');
    } on DioException {
      // Token may already be invalid/expired server-side — local logout
      // should proceed regardless, there's nothing left to reconcile.
    }
  }

  Future<AuthUser> me() async {
    final response = await _client.dio.get('/auth/me');
    return AuthUser.fromJson(response.data['user'] as Map<String, dynamic>);
  }
}

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.watch(apiClientProvider)),
);
