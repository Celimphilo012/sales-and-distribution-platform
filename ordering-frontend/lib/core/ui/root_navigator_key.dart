import 'package:flutter/widgets.dart';

/// The app's ROOT navigator (handed to go_router). Lets code that runs
/// outside any widget — e.g. the one-time-code prompt raised from inside a
/// network interceptor — show a dialog above whatever screen is open.
final rootNavigatorKey = GlobalKey<NavigatorState>();
