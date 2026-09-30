import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_semantic_colors.dart';
import 'nocturne.dart';

/// Builds the app's dark and light [ThemeData] from the Nocturne tokens
/// ([Nocturne.dark] / [Nocturne.light]) — the Warehouse Console v2 look: a
/// near-neutral blue-grey ground, Inter at medium weight, soft 8px radii and a
/// violet accent used as a line and a glow rather than a flood.
///
/// This is the ONLY place colours are composed into a theme. Widgets read the
/// tokens via `context.nx` (or the Material [ColorScheme] mapped from them) —
/// never a hard-coded [Color] (CLAUDE.md rule 11).
///
/// Buttons follow Nocturne's direction — the primary action is an accent
/// OUTLINE, never a fill:
///  * [FilledButton]   → `.btn-primary`   (accent border + text, tinted hover)
///  * [OutlinedButton] → `.btn-secondary` (divider border, text colour)
///  * [TextButton]     → `.btn-ghost`     (accent text, no border)
class AppTheme {
  const AppTheme._();

  static ThemeData dark() => _build(Nocturne.dark);

  static ThemeData light() => _build(Nocturne.light);

  static ColorScheme _scheme(Nocturne n) => ColorScheme(
    brightness: n.brightness,
    primary: n.accent,
    onPrimary: n.bg,
    primaryContainer: n.a900,
    onPrimaryContainer: n.a200,
    secondary: n.a400,
    onSecondary: n.bg,
    secondaryContainer: n.a800,
    onSecondaryContainer: n.a100,
    tertiary: n.ok,
    onTertiary: n.bg,
    error: n.bad,
    onError: n.bg,
    errorContainer: Nocturne.mix(n.bad, n.surface, 0.16),
    onErrorContainer: n.bad,
    surface: n.bg,
    onSurface: n.text,
    onSurfaceVariant: n.n400,
    surfaceTint: Colors.transparent,
    surfaceContainerLowest: n.surface,
    surfaceContainerLow: n.surface,
    surfaceContainer: n.surface,
    surfaceContainerHigh: Nocturne.mix(n.surface, n.n800, 0.8),
    surfaceContainerHighest: n.n900,
    outline: n.n700,
    outlineVariant: n.isDark ? n.n800 : n.n800,
    inverseSurface: n.text,
    onInverseSurface: n.bg,
    inversePrimary: n.a600,
    shadow: n.shadowInk,
    scrim: n.n900,
  );

  static AppSemanticColors _semantic(Nocturne n) => AppSemanticColors(
    success: n.ok,
    onSuccess: n.bg,
    successContainer: Nocturne.mix(n.ok, n.surface, 0.15),
    onSuccessContainer: n.ok,
    warning: n.warn,
    onWarning: n.bg,
    warningContainer: Nocturne.mix(n.warn, n.surface, 0.15),
    onWarningContainer: n.warn,
    info: n.a300,
    onInfo: n.bg,
    infoContainer: n.a900,
    onInfoContainer: n.a200,
    // Scanners need dark-on-light whatever the theme.
    qrForeground: n.isDark ? n.n900 : n.n100,
    qrBackground: n.isDark ? n.n100 : n.surface,
  );

  static TextTheme _textTheme(TextTheme base, Nocturne n) {
    final inter = GoogleFonts.interTextTheme(base);
    TextStyle? s(TextStyle? t, double size, {FontWeight weight = FontWeight.w400, double? height, double? spacing}) =>
        t?.copyWith(fontSize: size, fontWeight: weight, height: height, letterSpacing: spacing, color: n.text);
    return inter.copyWith(
      displayLarge: s(inter.displayLarge, 42, weight: FontWeight.w500, height: 1.12, spacing: -0.6),
      displayMedium: s(inter.displayMedium, 32, weight: FontWeight.w500, height: 1.12, spacing: -0.5),
      displaySmall: s(inter.displaySmall, 25, weight: FontWeight.w500, height: 1.12, spacing: -0.4),
      headlineLarge: s(inter.headlineLarge, 22, weight: FontWeight.w500, height: 1.15, spacing: -0.3),
      headlineMedium: s(inter.headlineMedium, 20, weight: FontWeight.w500, height: 1.2, spacing: -0.3),
      headlineSmall: s(inter.headlineSmall, 18, weight: FontWeight.w500, height: 1.2, spacing: -0.2),
      titleLarge: s(inter.titleLarge, 17, weight: FontWeight.w500, height: 1.2),
      titleMedium: s(inter.titleMedium, 14, weight: FontWeight.w500, height: 1.3),
      titleSmall: s(inter.titleSmall, 13, weight: FontWeight.w500, height: 1.35),
      bodyLarge: s(inter.bodyLarge, 14, height: 1.45),
      bodyMedium: s(inter.bodyMedium, 13, height: 1.45),
      bodySmall: s(inter.bodySmall, 12, height: 1.4)?.copyWith(color: n.n400),
      labelLarge: s(inter.labelLarge, 13, weight: FontWeight.w500, height: 1.2),
      labelMedium: s(inter.labelMedium, 12, height: 1.3),
      labelSmall: s(inter.labelSmall, 11, height: 1.3, spacing: 0.2),
    );
  }

  static ThemeData _build(Nocturne n) {
    final scheme = _scheme(n);
    final base = ThemeData(brightness: n.brightness, useMaterial3: true);
    final textTheme = _textTheme(base.textTheme, n);
    final radius = BorderRadius.circular(NxRadius.md);
    final shape = RoundedRectangleBorder(borderRadius: radius);
    final label = textTheme.labelLarge!;
    const padding = EdgeInsets.symmetric(horizontal: 12, vertical: 9);

    WidgetStateProperty<Color?> wash(Color c, {double hover = 0.12, double press = 0.22}) =>
        WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.pressed)) return c.withValues(alpha: press);
          if (states.contains(WidgetState.hovered) || states.contains(WidgetState.focused)) {
            return c.withValues(alpha: hover);
          }
          return null;
        });
    WidgetStateProperty<Color?> fg(Color c) => WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.disabled) ? c.withValues(alpha: 0.45) : c,
    );

    OutlineInputBorder border(Color c, [double w = 1]) =>
        OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: c, width: w));

    return ThemeData(
      useMaterial3: true,
      brightness: n.brightness,
      colorScheme: scheme,
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      fontFamily: GoogleFonts.inter().fontFamily,
      scaffoldBackgroundColor: n.bg,
      canvasColor: n.bg,
      dividerColor: n.n900,
      hoverColor: n.textAlpha(0.04),
      focusColor: n.accent.withValues(alpha: 0.2),
      splashFactory: NoSplash.splashFactory,
      highlightColor: n.textAlpha(0.06),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: n.accent,
        selectionColor: n.accent.withValues(alpha: 0.3),
        selectionHandleColor: n.accent,
      ),
      extensions: [n, _semantic(n)],
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      iconTheme: IconThemeData(color: n.n300, size: 18),
      dividerTheme: DividerThemeData(color: n.n900, thickness: 1, space: 1),
      cardTheme: CardThemeData(
        color: n.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: shape,
        clipBehavior: Clip.antiAlias,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: n.bg,
        foregroundColor: n.text,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: textTheme.titleMedium,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
          foregroundColor: fg(n.accent),
          overlayColor: wash(n.accent),
          side: WidgetStateProperty.resolveWith(
            (s) => BorderSide(color: s.contains(WidgetState.disabled) ? n.accent.withValues(alpha: 0.45) : n.accent),
          ),
          shape: WidgetStatePropertyAll(shape),
          padding: const WidgetStatePropertyAll(padding),
          minimumSize: const WidgetStatePropertyAll(Size(0, 34)),
          textStyle: WidgetStatePropertyAll(label),
          elevation: const WidgetStatePropertyAll(0),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          foregroundColor: fg(n.text),
          overlayColor: wash(n.text, hover: 0.07, press: 0.14),
          side: WidgetStatePropertyAll(BorderSide(color: n.divider)),
          shape: WidgetStatePropertyAll(shape),
          padding: const WidgetStatePropertyAll(padding),
          minimumSize: const WidgetStatePropertyAll(Size(0, 34)),
          textStyle: WidgetStatePropertyAll(label),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          foregroundColor: fg(n.accent),
          overlayColor: wash(n.accent, hover: 0.10, press: 0.18),
          shape: WidgetStatePropertyAll(shape),
          padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 6, vertical: 6)),
          minimumSize: const WidgetStatePropertyAll(Size(0, 30)),
          textStyle: WidgetStatePropertyAll(label),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
          foregroundColor: fg(n.accent),
          overlayColor: wash(n.accent),
          side: WidgetStatePropertyAll(BorderSide(color: n.accent)),
          shape: WidgetStatePropertyAll(shape),
          elevation: const WidgetStatePropertyAll(0),
          padding: const WidgetStatePropertyAll(padding),
          textStyle: WidgetStatePropertyAll(label),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          foregroundColor: fg(n.n300),
          overlayColor: wash(n.text, hover: 0.07, press: 0.14),
          shape: WidgetStatePropertyAll(shape),
          minimumSize: const WidgetStatePropertyAll(Size(30, 30)),
          padding: const WidgetStatePropertyAll(EdgeInsets.all(6)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: n.surface,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        hintStyle: textTheme.bodyMedium?.copyWith(color: n.n500),
        labelStyle: textTheme.bodySmall?.copyWith(color: n.textAlpha(0.7)),
        floatingLabelStyle: textTheme.bodySmall?.copyWith(color: n.a300),
        helperStyle: textTheme.labelSmall?.copyWith(color: n.n500),
        errorStyle: textTheme.labelSmall?.copyWith(color: n.bad),
        prefixIconColor: n.n500,
        suffixIconColor: n.n500,
        border: border(n.divider),
        enabledBorder: border(n.divider),
        hoverColor: Colors.transparent,
        focusedBorder: border(n.accent),
        errorBorder: border(n.bad),
        focusedErrorBorder: border(n.bad),
        disabledBorder: border(n.divider.withValues(alpha: 0.08)),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        textStyle: textTheme.bodyMedium,
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(n.surface),
          shape: WidgetStatePropertyAll(shape),
          side: WidgetStatePropertyAll(BorderSide(color: n.n800)),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: n.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: radius, side: BorderSide(color: n.n700)),
        textStyle: textTheme.bodyMedium,
        elevation: 8,
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(n.surface),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: radius, side: BorderSide(color: n.n700))),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: n.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 12,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(NxRadius.lg),
          side: BorderSide(color: n.shadowLgEdge),
        ),
        titleTextStyle: textTheme.headlineMedium,
        contentTextStyle: textTheme.bodyMedium,
        barrierColor: n.n900.withValues(alpha: 0.5),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: n.surface,
        contentTextStyle: textTheme.bodyMedium,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: radius, side: BorderSide(color: n.shadowMdEdge)),
        actionTextColor: n.accent,
        elevation: 6,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: n.surface,
          borderRadius: BorderRadius.circular(NxRadius.sm),
          border: Border.all(color: n.n700),
        ),
        textStyle: textTheme.labelMedium,
        waitDuration: const Duration(milliseconds: 400),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? n.accent : Colors.transparent),
        checkColor: WidgetStatePropertyAll(n.bg),
        side: BorderSide(color: n.n500, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(NxRadius.sm)),
      ),
      radioTheme: RadioThemeData(fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? n.accent : n.n500)),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? n.bg : n.n400),
        trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? n.accent : n.n800),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: n.accent,
        linearTrackColor: n.n800,
        circularTrackColor: n.n800,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? n.a900 : Colors.transparent),
          foregroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? n.a200 : n.n400),
          side: WidgetStatePropertyAll(BorderSide(color: n.divider)),
          shape: WidgetStatePropertyAll(shape),
          textStyle: WidgetStatePropertyAll(textTheme.labelMedium),
          visualDensity: VisualDensity.compact,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: Colors.transparent,
        selectedColor: n.a900,
        side: BorderSide(color: n.divider),
        labelStyle: textTheme.labelMedium,
        shape: const StadiumBorder(),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: n.n400,
        textColor: n.text,
        dense: true,
        selectedColor: n.text,
        selectedTileColor: n.a900,
        shape: shape,
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: n.text,
        unselectedLabelColor: n.n400,
        indicatorColor: n.accent,
        dividerColor: n.n900,
        labelStyle: textTheme.labelLarge,
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(n.n700.withValues(alpha: 0.7)),
        radius: const Radius.circular(8),
        thickness: const WidgetStatePropertyAll(6),
      ),
      drawerTheme: DrawerThemeData(backgroundColor: n.bg, surfaceTintColor: Colors.transparent),
      bottomSheetTheme: BottomSheetThemeData(backgroundColor: n.bg, surfaceTintColor: Colors.transparent),
      navigationRailTheme: NavigationRailThemeData(backgroundColor: n.bg),
    );
  }
}
