import 'package:dio/dio.dart';

/// Wraps a Laravel validation/auth error response into a single readable
/// message — Laravel returns `{"message": "...", "errors": {"field": [...]}}`
/// for 422s (and a plain `{"message": "..."}` for 401s), so the first
/// field error is preferred when present since it's usually more specific
/// than the top-level message (e.g. "The provided credentials are
/// incorrect." vs a generic "The given data was invalid.").
class AuthException implements Exception {
  AuthException(this.message);

  factory AuthException.fromDioException(DioException error) {
    final data = error.response?.data;
    if (data is Map) {
      final errors = data['errors'];
      if (errors is Map && errors.isNotEmpty) {
        final firstField = errors.values.first;
        if (firstField is List && firstField.isNotEmpty) {
          return AuthException(firstField.first.toString());
        }
      }
      final message = data['message'];
      if (message is String && message.isNotEmpty) {
        return AuthException(message);
      }
    }
    return AuthException('Something went wrong. Please try again.');
  }

  final String message;

  @override
  String toString() => message;
}
