import 'package:dio/dio.dart';

/// Live production backend (memevibe.hireqai.com), deployed during this
/// session — see the "MemeVibe production server" project notes for
/// server/deploy details.
///
/// Local dev alternative, if ever needed again: Android can't resolve the
/// `video_creater.local` nginx vhost (that hostname only exists in the
/// Windows hosts file), so local dev instead talks to `php artisan serve
/// --host=0.0.0.0 --port=8010` via `http://127.0.0.1:8010/api/v1`, relying
/// on `adb reverse tcp:8010 tcp:8010` to tunnel the device's localhost:8010
/// to the dev machine over USB (re-run that command after every `adb`
/// reconnect). Android emulator would instead use 10.0.2.2, which aliases
/// the host loopback automatically with no adb command needed.
abstract final class ApiConfig {
  static const baseUrl = 'https://memevibe.hireqai.com/api/v1';

  /// Bare host, no `/api/v1` suffix — needed because asset URLs returned by
  /// the API (template previews, app sound audio files) are host-relative
  /// (e.g. `/storage/...`, from Laravel's `Storage::url()`), not the full
  /// API base.
  static const origin = 'https://memevibe.hireqai.com';

  /// Resolves a URL that may be either already-absolute (seeded/dev data
  /// sometimes points straight at an external host like picsum.photos) or
  /// host-relative (real admin-uploaded assets via `Storage::url()`).
  static String resolveAssetUrl(String url) {
    return url.startsWith('http://') || url.startsWith('https://')
        ? url
        : '$origin$url';
  }

  const ApiConfig._();
}

class ApiClient {
  ApiClient({String? baseUrl, String? appVersion})
    : dio = Dio(
        BaseOptions(
          baseUrl: baseUrl ?? ApiConfig.baseUrl,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
          headers: {
            'Accept': 'application/json',
            // Lets the backend track which app version each user is on
            // (surfaced in the admin Users list) — cheap support signal,
            // no separate telemetry needed.
            if (appVersion != null) 'X-App-Version': appVersion,
          },
        ),
      );

  final Dio dio;

  String? _authToken;

  void setAuthToken(String? token) {
    _authToken = token;
    if (token == null) {
      dio.options.headers.remove('Authorization');
    } else {
      dio.options.headers['Authorization'] = 'Bearer $token';
    }
  }

  String? get authToken => _authToken;
}
