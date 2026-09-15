import 'package:flutter/widgets.dart';

import 'breakpoints.dart';

/// Picks between [mobile], [tablet], and [desktop] builders based on the
/// available width (via [LayoutBuilder], not [MediaQuery] — so it reacts
/// correctly when nested in a constrained parent, e.g. a side panel).
///
/// [tablet] and [desktop] fall back to the next-smaller variant when
/// omitted, so callers only need to supply the layouts that actually differ.
class ResponsiveLayout extends StatelessWidget {
  const ResponsiveLayout({super.key, required this.mobile, this.tablet, this.desktop});

  final WidgetBuilder mobile;
  final WidgetBuilder? tablet;
  final WidgetBuilder? desktop;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        if (Breakpoints.isDesktop(width)) {
          return (desktop ?? tablet ?? mobile)(context);
        }
        if (Breakpoints.isTablet(width)) {
          return (tablet ?? mobile)(context);
        }
        return mobile(context);
      },
    );
  }
}
