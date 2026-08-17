import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';

/// Overridden in `main()` with the real version+build (e.g. "1.0.0+3")
/// resolved via `package_info_plus` before the app starts, mirroring how
/// `sharedPreferencesProvider` is seeded — everything that needs it (just
/// [apiClientProvider] today) can depend on this instead of awaiting
/// `PackageInfo.fromPlatform()` itself.
final appVersionProvider = Provider<String>(
  (ref) => throw UnimplementedError('appVersionProvider not overridden'),
);

final apiClientProvider = Provider<ApiClient>(
  (ref) => ApiClient(appVersion: ref.watch(appVersionProvider)),
);
