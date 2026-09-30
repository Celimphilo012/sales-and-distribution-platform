import 'package:flutter/painting.dart';

import 'nocturne.dart';

/// Turns ONE brand colour (Settings → Branding) into the console's whole
/// accent palette, for the dark and the light theme.
///
/// Each generated shade takes the brand's hue and a saturation scaled like
/// the built-in palette's, and is then tuned to the SAME LUMINANCE as the
/// built-in shade it replaces — so every contrast pair the design was
/// checked for (accent text on the page, tint fills behind text, the
/// primary outline) stays exactly as readable whatever colour is chosen,
/// even a bright yellow or a very dark navy.
class BrandPalette {
  const BrandPalette._();

  /// The palette for [base] (Nocturne.dark / .light) re-tinted to [seed].
  static ({Color accent, List<Color> ramp}) of(Color seed, Nocturne base) {
    final s = HSLColor.fromColor(seed);
    final ref = HSLColor.fromColor(base.accent);
    // A near-grey brand colour gives a near-grey accent; anything else keeps
    // the built-in palette's saturation curve, shifted by how vivid it is.
    final vivid = ref.saturation == 0 ? 1.0 : (s.saturation / ref.saturation);
    Color shade(Color like) {
      final target = HSLColor.fromColor(like);
      final sat = (target.saturation * vivid).clamp(0.0, 1.0);
      return _toLuminance(s.hue, s.saturation < 0.08 ? s.saturation : sat, like.computeLuminance());
    }

    return (accent: shade(base.accent), ramp: [for (final c in base.accentRamp) shade(c)]);
  }

  /// The lightness (for [hue] / [saturation]) whose colour has [luminance].
  static Color _toLuminance(double hue, double saturation, double luminance) {
    var lo = 0.0;
    var hi = 1.0;
    for (var i = 0; i < 24; i++) {
      final mid = (lo + hi) / 2;
      final l = HSLColor.fromAHSL(1, hue, saturation, mid).toColor().computeLuminance();
      if (l < luminance) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return HSLColor.fromAHSL(1, hue, saturation, (lo + hi) / 2).toColor();
  }

  /// "#0E7C66" → Color; null for anything else.
  static Color? parse(String? hex) {
    final h = hex?.trim().replaceFirst('#', '');
    if (h == null || !RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(h)) return null;
    return Color(0xFF000000 | int.parse(h, radix: 16));
  }

  /// Color → "#0E7C66".
  static String hex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

extension NocturneBrand on Nocturne {
  /// This theme with its accent palette generated from [seed] (unchanged when null).
  Nocturne withBrand(Color? seed) {
    if (seed == null) return this;
    final p = BrandPalette.of(seed, this);
    return Nocturne(
      brightness: brightness,
      bg: bg,
      surface: surface,
      text: text,
      accent: p.accent,
      neutral: neutral,
      accentRamp: p.ramp,
      ok: ok,
      warn: warn,
      bad: bad,
      shadowSmEdge: shadowSmEdge,
      shadowMdEdge: shadowMdEdge,
      shadowLgEdge: shadowLgEdge,
      shadowInk: shadowInk,
    );
  }
}
