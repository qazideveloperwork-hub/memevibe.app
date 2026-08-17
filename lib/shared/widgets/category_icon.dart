import 'package:flutter/material.dart';

/// Maps the backend's free-text `icon` key (seeded in
/// backend/database/seeders/CategorySeeder.php) to a Material icon.
IconData categoryIconFor(String? key) => switch (key) {
  'flame' => Icons.local_fire_department,
  'laugh' => Icons.sentiment_very_satisfied,
  'video' => Icons.videocam,
  'moon-star' => Icons.nightlight_round,
  'trophy' => Icons.emoji_events,
  'graduation-cap' => Icons.school,
  'heart' => Icons.favorite,
  'star-and-crescent' => Icons.mosque,
  'rocket' => Icons.rocket_launch,
  'smile' => Icons.mood,
  _ => Icons.grid_view,
};
