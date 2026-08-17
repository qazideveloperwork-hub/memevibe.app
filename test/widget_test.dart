import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:creator_app/features/favorites/data/favorites_controller.dart';
import 'package:creator_app/features/home/presentation/home_providers.dart';
import 'package:creator_app/main.dart';

void main() {
  testWidgets('App boots to the home tab', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          categoriesProvider.overrideWith((ref) async => []),
          trendingTemplatesProvider.overrideWith((ref) async => []),
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
        child: const CreatorApp(),
      ),
    );
    await tester.pump();

    expect(find.text('VibeShift'), findsOneWidget);
    expect(find.byIcon(Icons.home), findsOneWidget);
  });
}
