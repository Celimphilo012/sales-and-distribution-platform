import 'package:flutter/material.dart';

/// The Nocturne design tokens (warehouse-frontend/_ds/nocturne-…/styles.css and
/// the Warehouse Console v2 prototype's light/dark theme table) — the single
/// source of every colour, radius and shadow in this app. Widgets read them
/// through `context.nx` (never a hard-coded Color — CLAUDE.md rule 11).
///
/// Ramps run 100 (lightest on dark / darkest on light) … 900: on the dark
/// theme 700–900 are tinted fills and borders, 500 is the base, 100–300 is
/// text on tints — the light theme mirrors the ramps so the same step keeps
/// the same role. The prototype's OKLCH status colours are converted to sRGB.
@immutable
class Nocturne extends ThemeExtension<Nocturne> {
  const Nocturne({
    required this.brightness,
    required this.bg,
    required this.surface,
    required this.text,
    required this.accent,
    required this.neutral,
    required this.accentRamp,
    required this.ok,
    required this.warn,
    required this.bad,
    required this.shadowSmEdge,
    required this.shadowMdEdge,
    required this.shadowLgEdge,
    required this.shadowInk,
  });

  final Brightness brightness;
  final Color bg;
  final Color surface;
  final Color text;
  final Color accent;

  /// neutral[0] = 100 … neutral[8] = 900.
  final List<Color> neutral;

  /// accentRamp[0] = 100 … accentRamp[8] = 900.
  final List<Color> accentRamp;
  final Color ok;
  final Color warn;
  final Color bad;

  /// The hairline edge of each elevation step (the 0 0 0 1px part).
  final Color shadowSmEdge;
  final Color shadowMdEdge;
  final Color shadowLgEdge;

  /// Ambient darkness for md/lg shadows (black on dark, ink on light).
  final Color shadowInk;

  bool get isDark => brightness == Brightness.dark;

  Color n(int step) => neutral[step ~/ 100 - 1];
  Color a(int step) => accentRamp[step ~/ 100 - 1];

  Color get n100 => neutral[0];
  Color get n200 => neutral[1];
  Color get n300 => neutral[2];
  Color get n400 => neutral[3];
  Color get n500 => neutral[4];
  Color get n600 => neutral[5];
  Color get n700 => neutral[6];
  Color get n800 => neutral[7];
  Color get n900 => neutral[8];
  Color get a100 => accentRamp[0];
  Color get a200 => accentRamp[1];
  Color get a300 => accentRamp[2];
  Color get a400 => accentRamp[3];
  Color get a500 => accentRamp[4];
  Color get a600 => accentRamp[5];
  Color get a700 => accentRamp[6];
  Color get a800 => accentRamp[7];
  Color get a900 => accentRamp[8];

  /// `--color-divider`: the text colour at 16% (dark) / 14% (light).
  Color get divider => text.withValues(alpha: isDark ? 0.16 : 0.14);

  /// `color-mix(in srgb, text X%, transparent)` — hover washes etc.
  Color textAlpha(double fraction) => text.withValues(alpha: fraction);

  /// The muted-text tone used for secondary copy (`--color-neutral-400`).
  Color get muted => n400;

  /// A tone's (foreground, background) pair — tags, badges, icon tiles.
  (Color, Color) tone(Tone t) => switch (t) {
    Tone.ok => (ok, ok.withValues(alpha: 0.15)),
    Tone.warn => (warn, warn.withValues(alpha: 0.15)),
    Tone.bad => (bad, bad.withValues(alpha: 0.16)),
    Tone.info => (a300, a900),
    Tone.neutral => (n300, n900),
    Tone.accent => (a100, a800),
  };

  List<BoxShadow> get shadowSm => [BoxShadow(color: shadowSmEdge, spreadRadius: 1)];
  List<BoxShadow> get shadowMd => [
    BoxShadow(color: shadowMdEdge, spreadRadius: 1),
    BoxShadow(color: shadowInk.withValues(alpha: isDark ? 0.55 : 0.10), blurRadius: 18, offset: const Offset(0, 6)),
  ];
  List<BoxShadow> get shadowLg => [
    BoxShadow(color: shadowLgEdge, spreadRadius: 1),
    BoxShadow(color: shadowInk.withValues(alpha: isDark ? 0.65 : 0.18), blurRadius: 40, offset: const Offset(0, 16)),
  ];

  /// `color-mix(in srgb, a p%, b)`.
  static Color mix(Color a, Color b, double p) => Color.lerp(b, a, p)!;

  static const dark = Nocturne(
    brightness: Brightness.dark,
    bg: Color(0xFF161826),
    surface: Color(0xFF232532),
    text: Color(0xFFE9E9ED),
    accent: Color(0xFF9184D9),
    neutral: [
      Color(0xFFF3F5FE),
      Color(0xFFE4E7F5),
      Color(0xFFCFD3E5),
      Color(0xFFB2B6CA),
      Color(0xFF9397AB),
      Color(0xFF75798C),
      Color(0xFF595D6C),
      Color(0xFF3F424D),
      Color(0xFF292B31),
    ],
    accentRamp: [
      Color(0xFFF5F4FF),
      Color(0xFFE7E5FE),
      Color(0xFFD2CEFD),
      Color(0xFFB5ABFC),
      Color(0xFF968AE0),
      Color(0xFF796CBF),
      Color(0xFF5D5294),
      Color(0xFF423A6A),
      Color(0xFF2B2741),
    ],
    ok: Color(0xFF72D699), // oklch(0.80 0.13 155)
    warn: Color(0xFFF3BD5C), // oklch(0.83 0.13 80)
    bad: Color(0xFFFF7E76), // oklch(0.74 0.16 25)
    shadowSmEdge: Color(0xFF3F424D),
    shadowMdEdge: Color(0xFF595D6C),
    shadowLgEdge: Color(0xFF9397AB),
    shadowInk: Color(0xFF000000),
  );

  static const light = Nocturne(
    brightness: Brightness.light,
    bg: Color(0xFFECEEF7),
    surface: Color(0xFFF8F9FD),
    text: Color(0xFF1F2127),
    accent: Color(0xFF6456B8),
    neutral: [
      Color(0xFF1F2127),
      Color(0xFF292B31),
      Color(0xFF3F424D),
      Color(0xFF555968),
      Color(0xFF6B6F80),
      Color(0xFF9397AB),
      Color(0xFFB9BDD0),
      Color(0xFFD6D9E7),
      Color(0xFFE5E8F3),
    ],
    accentRamp: [
      Color(0xFF241F3D),
      Color(0xFF332B5E),
      Color(0xFF4A3F8F),
      Color(0xFF5A4EAA),
      Color(0xFF6D60C6),
      Color(0xFF9184D9),
      Color(0xFFB5ABFC),
      Color(0xFFDCD8FD),
      Color(0xFFEBE9FE),
    ],
    ok: Color(0xFF007840), // oklch(0.50 0.13 155)
    warn: Color(0xFFA76100), // oklch(0.56 0.13 65)
    bad: Color(0xFFC52B30), // oklch(0.54 0.19 25)
    shadowSmEdge: Color(0xFFD6D9E7),
    shadowMdEdge: Color(0xFFC9CDDD),
    shadowLgEdge: Color(0xFFB9BDD0),
    shadowInk: Color(0xFF1F2127),
  );

  @override
  Nocturne copyWith() => this;

  @override
  Nocturne lerp(ThemeExtension<Nocturne>? other, double t) {
    if (other is! Nocturne) return this;
    Color l(Color x, Color y) => Color.lerp(x, y, t)!;
    List<Color> ll(List<Color> x, List<Color> y) => [for (var i = 0; i < x.length; i++) l(x[i], y[i])];
    return Nocturne(
      brightness: t < 0.5 ? brightness : other.brightness,
      bg: l(bg, other.bg),
      surface: l(surface, other.surface),
      text: l(text, other.text),
      accent: l(accent, other.accent),
      neutral: ll(neutral, other.neutral),
      accentRamp: ll(accentRamp, other.accentRamp),
      ok: l(ok, other.ok),
      warn: l(warn, other.warn),
      bad: l(bad, other.bad),
      shadowSmEdge: l(shadowSmEdge, other.shadowSmEdge),
      shadowMdEdge: l(shadowMdEdge, other.shadowMdEdge),
      shadowLgEdge: l(shadowLgEdge, other.shadowLgEdge),
      shadowInk: l(shadowInk, other.shadowInk),
    );
  }
}

/// The five status tones of the prototype (plus the accent tag).
enum Tone { ok, warn, bad, info, neutral, accent }

extension NocturneContext on BuildContext {
  /// The Nocturne tokens of the current theme.
  Nocturne get nx => Theme.of(this).extension<Nocturne>()!;
}

/// Nocturne's compact type scale (Inter). Body copy is 13px; hierarchy comes
/// from size and space, never weights above 500 for headings.
class NxText {
  const NxText._();

  static const double body = 13;
  static const double small = 12;
  static const double tiny = 11;
  static const double micro = 10;
  static const double h1 = 22;
  static const double h2 = 14;
  static const double sheetTitle = 18;
  static const double dialogTitle = 20;
  static const double stat = 19;
  static const double kpi = 22;

  /// Monospace for codes and SKUs (the prototype's ui-monospace stack).
  static const String mono = 'monospace';
}

/// Radii (`--radius-*`) and the compact spacing scale (density 0.7×).
class NxRadius {
  const NxRadius._();

  static const double sm = 4;
  static const double md = 8;
  static const double lg = 14;
}
