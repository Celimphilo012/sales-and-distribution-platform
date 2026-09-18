/// Shared width breakpoints. Keep every responsive decision in the app
/// keyed off these instead of ad-hoc numbers scattered through widgets.
class Breakpoints {
  const Breakpoints._();

  static const double mobileMax = 600;
  static const double tabletMax = 1024;

  static bool isMobile(double width) => width < mobileMax;

  static bool isTablet(double width) => width >= mobileMax && width < tabletMax;

  static bool isDesktop(double width) => width >= tabletMax;
}
