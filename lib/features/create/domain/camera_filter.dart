import 'package:flutter/widgets.dart';

enum FilterCategory { portrait, landscape, food, travel }

/// Real-time preview filters implemented as color matrices over
/// [ColorFiltered], so they apply with zero extra native dependencies.
class CameraFilterOption {
  const CameraFilterOption(this.name, this.matrix, this.categories);

  final String name;
  final List<double> matrix;

  /// Which tabs this shows under in the category-grouped filter picker.
  /// A filter can fit more than one category (e.g. a punchy look works for
  /// both Landscape and Travel) — every filter still shows under "All"
  /// regardless of these tags.
  final Set<FilterCategory> categories;

  static const List<double> identity = [
    1, 0, 0, 0, 0, //
    0, 1, 0, 0, 0, //
    0, 0, 1, 0, 0, //
    0, 0, 0, 1, 0,
  ];

  /// Linearly blends [matrix] toward [identity] — `intensity` 0 is no
  /// effect at all, 100 is the filter at full strength.
  static List<double> withIntensity(List<double> matrix, double intensity) {
    final t = (intensity / 100).clamp(0.0, 1.0);
    return List.generate(
      matrix.length,
      (i) => identity[i] + (matrix[i] - identity[i]) * t,
    );
  }

  static const List<CameraFilterOption> all = [
    CameraFilterOption('Normal', identity, {
      FilterCategory.portrait,
      FilterCategory.travel,
    }),
    CameraFilterOption(
      'Mono',
      [
        0.2126, 0.7152, 0.0722, 0, 0, //
        0.2126, 0.7152, 0.0722, 0, 0, //
        0.2126, 0.7152, 0.0722, 0, 0, //
        0, 0, 0, 1, 0,
      ],
      {FilterCategory.landscape, FilterCategory.travel},
    ),
    CameraFilterOption(
      'Vivid',
      [
        1.3, -0.15, -0.15, 0, 0, //
        -0.15, 1.3, -0.15, 0, 0, //
        -0.15, -0.15, 1.3, 0, 0, //
        0, 0, 0, 1, 0,
      ],
      {FilterCategory.landscape, FilterCategory.travel, FilterCategory.food},
    ),
    CameraFilterOption(
      'Warm',
      [
        1.15, 0, 0, 0, 12, //
        0, 1.05, 0, 0, 4, //
        0, 0, 0.85, 0, -8, //
        0, 0, 0, 1, 0,
      ],
      {FilterCategory.portrait, FilterCategory.food},
    ),
    CameraFilterOption(
      'Cool',
      [
        0.9, 0, 0, 0, -6, //
        0, 1.0, 0, 0, 0, //
        0, 0, 1.2, 0, 14, //
        0, 0, 0, 1, 0,
      ],
      {FilterCategory.landscape, FilterCategory.travel},
    ),
    CameraFilterOption(
      'Vintage',
      [
        0.6, 0.35, 0.15, 0, 12, //
        0.2, 0.55, 0.15, 0, 8, //
        0.15, 0.25, 0.45, 0, 0, //
        0, 0, 0, 1, 0,
      ],
      {FilterCategory.portrait, FilterCategory.travel},
    ),
    CameraFilterOption(
      'Sepia',
      [
        0.393, 0.769, 0.189, 0, 0, //
        0.349, 0.686, 0.168, 0, 0, //
        0.272, 0.534, 0.131, 0, 0, //
        0, 0, 0, 1, 0,
      ],
      {FilterCategory.portrait, FilterCategory.travel},
    ),
    CameraFilterOption(
      'Noir',
      [
        0.2976, 1.0013, 0.1011, 0, -51.2, //
        0.2976, 1.0013, 0.1011, 0, -51.2, //
        0.2976, 1.0013, 0.1011, 0, -51.2, //
        0, 0, 0, 1, 0,
      ],
      {FilterCategory.landscape, FilterCategory.travel},
    ),
    CameraFilterOption(
      'Fade',
      [
        0.85, 0.1, 0.05, 0, 30, //
        0.05, 0.85, 0.1, 0, 30, //
        0.1, 0.05, 0.85, 0, 30, //
        0, 0, 0, 1, 0,
      ],
      {FilterCategory.portrait, FilterCategory.travel},
    ),
    CameraFilterOption(
      'Chrome',
      [
        1.2, -0.05, -0.05, 0, -26, //
        -0.05, 1.2, -0.05, 0, -26, //
        -0.05, -0.02, 1.25, 0, -20, //
        0, 0, 0, 1, 0,
      ],
      {FilterCategory.portrait, FilterCategory.food},
    ),
    CameraFilterOption(
      'Neon',
      [
        1.4, -0.2, -0.1, 0, -10, //
        -0.1, 1.3, -0.1, 0, 0, //
        -0.1, -0.2, 1.5, 0, 10, //
        0, 0, 0, 1, 0,
      ],
      {FilterCategory.landscape, FilterCategory.travel},
    ),
    CameraFilterOption(
      'Invert',
      [
        -1, 0, 0, 0, 255, //
        0, -1, 0, 0, 255, //
        0, 0, -1, 0, 255, //
        0, 0, 0, 1, 0,
      ],
      {FilterCategory.landscape},
    ),
  ];
}
