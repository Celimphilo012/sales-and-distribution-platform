/// Puts the company's logo on the browser tab (favicon). Real implementation
/// in `browser_branding_web.dart`; elsewhere (mobile / desktop builds, tests)
/// it does nothing — native app icons are fixed at build time.
library;

export 'browser_branding_stub.dart' if (dart.library.js_interop) 'browser_branding_web.dart';
