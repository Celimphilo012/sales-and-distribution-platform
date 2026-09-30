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

  // Nocturne radii (`--radius-sm/md/lg`): soft 8px corners on controls and
  // cards, 14px on sheets and dialogs.
  static const double radiusSm = 4;
  static const double radiusMd = 8;
  static const double radiusLg = 14;
}
