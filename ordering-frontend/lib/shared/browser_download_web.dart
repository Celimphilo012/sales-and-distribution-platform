import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Saves [bytes] as a file download in the browser — used for the product
/// import template (an `.xlsx` the warehouse backend generates and streams
/// back as a byte response, not a URL). This app runs as a Flutter web app
/// only (see dev-run docs), so a direct `package:web` call is fine here —
/// no platform-conditional split needed.
void triggerBrowserDownload(Uint8List bytes, String fileName, {required String mimeType}) {
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: mimeType),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..style.display = 'none'
    ..download = fileName;
  web.document.body!.appendChild(anchor);
  anchor.click();
  anchor.remove();
  web.URL.revokeObjectURL(url);
}
