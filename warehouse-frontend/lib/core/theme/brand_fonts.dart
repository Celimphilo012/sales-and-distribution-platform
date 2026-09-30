import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// The approved brand fonts (Settings → Branding → Typography) — the same
/// closed list the warehouse server accepts (`modules/branding/fonts.js`,
/// copied: no shared code). Every entry is a Google Font.
const kBrandFonts = [
  'Inter',
  'Roboto',
  'Open Sans',
  'Lato',
  'Montserrat',
  'Poppins',
  'Nunito Sans',
  'Source Sans 3',
  'Work Sans',
  'IBM Plex Sans',
  'DM Sans',
  'Manrope',
  'Merriweather',
  'Playfair Display',
  'Source Serif 4',
];

const kDefaultBrandFont = 'Inter';

/// Serif faces, labelled as such in the picker.
const kSerifBrandFonts = {'Merriweather', 'Playfair Display', 'Source Serif 4'};

String _safe(String? name) => name != null && kBrandFonts.contains(name) ? name : kDefaultBrandFont;

/// [base] set in the brand's [body] font, with headings, titles and display
/// styles in its [heading] font.
TextTheme brandTextTheme(TextTheme base, {String? heading, String? body}) {
  final b = _safe(body);
  final h = _safe(heading);
  final themed = b == kDefaultBrandFont ? GoogleFonts.interTextTheme(base) : GoogleFonts.getTextTheme(b, base);
  if (h == b) return themed;
  TextStyle? hs(TextStyle? s) => s == null ? null : GoogleFonts.getFont(h, textStyle: s);
  return themed.copyWith(
    displayLarge: hs(themed.displayLarge),
    displayMedium: hs(themed.displayMedium),
    displaySmall: hs(themed.displaySmall),
    headlineLarge: hs(themed.headlineLarge),
    headlineMedium: hs(themed.headlineMedium),
    headlineSmall: hs(themed.headlineSmall),
    titleLarge: hs(themed.titleLarge),
  );
}

/// The family name Flutter registered for [name] (for a whole-app default).
String? brandFontFamily(String? name) {
  final n = _safe(name);
  return n == kDefaultBrandFont ? GoogleFonts.inter().fontFamily : GoogleFonts.getFont(n).fontFamily;
}

/// A sample style in [name] (the font picker's previews).
TextStyle brandFontSample(String name, {double size = 14, FontWeight weight = FontWeight.w500, Color? color}) =>
    GoogleFonts.getFont(_safe(name), fontSize: size, fontWeight: weight, color: color);
