/// Shared width breakpoints. Keep every responsive decision in the app
/// keyed off these instead of ad-hoc numbers scattered through widgets.
class Breakpoints {
  const Breakpoints._();

  static const double mobileMax = 600;
  static const double tabletMax = 1024;

  /// Minimum CONTENT width (the space beside the nav, not the window) at
  /// which record lists render as a table; narrower falls back to cards.
  /// Deliberately lower than [tabletMax]: the sidebar and page padding eat
  /// ~300px, so keying off the window breakpoint left 1280px monitors on the
  /// phone-style card list.
  static const double dataTableMin = 720;

  static bool isMobile(double width) => width < mobileMax;

  static bool isTablet(double width) => width >= mobileMax && width < tabletMax;

  static bool isDesktop(double width) => width >= tabletMax;
}
