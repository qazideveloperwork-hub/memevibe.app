/// Spacing & radius tokens transcribed 1:1 from
/// stitch_dynamic_animated_mobile_ui/vibeshift/DESIGN.md
abstract final class AppSpacing {
  static const base = 4.0;
  static const containerPadding = 20.0;
  static const gutter = 12.0;
  static const stackSm = 8.0;
  static const stackMd = 16.0;
  static const stackLg = 32.0;

  const AppSpacing._();
}

/// Maps to DESIGN.md `rounded` scale: sm / DEFAULT / md / lg / xl / full.
abstract final class AppRadius {
  static const sm = 4.0;
  static const dflt = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const full = 9999.0;

  const AppRadius._();
}
