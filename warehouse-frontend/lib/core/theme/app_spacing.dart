/// Shared spacing scale. Use these instead of hard-coded numeric padding so
/// spacing stays consistent across the app.
class AppSpacing {
  const AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;

  // Broadsheet look: near-square corners everywhere (a hairline of softening
  // only so edges don't alias) — hierarchy comes from rules and space.
  static const double radiusSm = 2;
  static const double radiusMd = 2;
  static const double radiusLg = 2;
}
