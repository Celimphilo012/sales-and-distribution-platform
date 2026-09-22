import 'dart:typed_data';

/// Non-web fallback for [browser_download.dart]'s conditional export. This
/// app only ever ships/runs as Flutter web (see dev-run docs) — this stub
/// exists purely so the VM target (used by `flutter test`, which has no
/// `dart:js_interop`) can still compile the app's full import graph; it is
/// never actually reached at runtime.
void triggerBrowserDownload(Uint8List bytes, String fileName, {required String mimeType}) {
  throw UnsupportedError('File download is only supported when running as a Flutter web app.');
}
