import 'dart:convert';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

const _defaultIcon = 'favicon.png';

/// Points the page's `<link rel="icon">` at [logo] (a data URL, so no extra
/// request and no auth), or back at the bundled default when there is none.
void applyBrowserFavicon(Uint8List? logo) {
  var link = web.document.querySelector('link[rel~="icon"]') as web.HTMLLinkElement?;
  if (link == null) {
    link = web.document.createElement('link') as web.HTMLLinkElement..rel = 'icon';
    web.document.head?.appendChild(link);
  }
  if (logo == null || logo.isEmpty) {
    link
      ..type = 'image/png'
      ..href = _defaultIcon;
    return;
  }
  final mime = _mimeOf(logo);
  link
    ..type = mime
    ..href = 'data:$mime;base64,${base64Encode(logo)}';
}

/// Tints the mobile browser's toolbar (`<meta name="theme-color">`) with the
/// brand colour; removes the tint when [hex] is null.
void applyBrowserThemeColor(String? hex) {
  var meta = web.document.querySelector('meta[name="theme-color"]') as web.HTMLMetaElement?;
  if (hex == null) {
    meta?.remove();
    return;
  }
  if (meta == null) {
    meta = web.document.createElement('meta') as web.HTMLMetaElement..name = 'theme-color';
    web.document.head?.appendChild(meta);
  }
  meta.content = hex;
}

String _mimeOf(Uint8List b) {
  if (b.length > 3 && b[0] == 0x89 && b[1] == 0x50) return 'image/png';
  if (b.length > 2 && b[0] == 0xFF && b[1] == 0xD8) return 'image/jpeg';
  if (b.length > 11 && b[0] == 0x52 && b[1] == 0x49 && b[8] == 0x57 && b[9] == 0x45) return 'image/webp';
  return 'image/png';
}
