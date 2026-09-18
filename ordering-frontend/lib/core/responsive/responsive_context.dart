import 'package:flutter/widgets.dart';

import 'breakpoints.dart';

/// `context.isMobile` / `context.isTablet` / `context.isDesktop`, keyed off
/// the current [MediaQuery] width and the shared [Breakpoints].
extension ResponsiveContextX on BuildContext {
  double get _width => MediaQuery.sizeOf(this).width;

  bool get isMobile => Breakpoints.isMobile(_width);

  bool get isTablet => Breakpoints.isTablet(_width);

  bool get isDesktop => Breakpoints.isDesktop(_width);
}
