/// Saves bytes as a browser file download. Real implementation lives in
/// `browser_download_web.dart` (uses `package:web`, which needs
/// `dart:js_interop` — unavailable when this package compiles for the VM,
/// e.g. under `flutter test`). Conditional export picks the VM-safe stub
/// there instead, so the whole app's import graph still compiles for tests
/// even though this feature is only ever exercised on the real web target.
library;

export 'browser_download_stub.dart' if (dart.library.js_interop) 'browser_download_web.dart';
