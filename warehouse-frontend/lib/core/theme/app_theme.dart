import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_semantic_colors.dart';
import 'app_spacing.dart';

/// Builds the app's light and dark [ThemeData] from the "Broadsheet" design
/// tokens (paper ground, ink text, cyan accent, magenta as the rare second
/// spot color, Source Serif 4 throughout, square corners, hairline rules).
///
/// This is the ONLY place `Color`/`ColorScheme` literals should be composed
/// into a theme. Every widget elsewhere must read colors via
/// `Theme.of(context)` (or `context.semanticColors`) — never hard-code a
/// [Color] value.
///
/// Token → [ColorScheme] mapping (so widgets never need a custom palette):
///  * paper            → `surface` (scaffold ground)
///  * white card face  → `surfaceContainerLowest` / `surfaceContainerLow`
///  * recessed fill    → `surfaceContainer` / `surfaceContainerHigh`
///  * hairline rule    → `outlineVariant`, stronger rule → `outline`
///  * top bar          → `inverseSurface` / `onInverseSurface`
///  * selected tint    → `primaryContainer`
class AppTheme {
  const AppTheme._();

  static ThemeData light() => _build(_lightScheme, AppSemanticColors.light);

  static ThemeData dark() => _build(_darkScheme, AppSemanticColors.dark);

  static const _lightScheme = ColorScheme(
    brightness: Brightness.light,
    primary: Color(0xFF0088B0),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFDCEEF4),
    onPrimaryContainer: Color(0xFF006B8C),
    secondary: Color(0xFFD6006C),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFFBE0EC),
    onSecondaryContainer: Color(0xFF8A0047),
    error: Color(0xFFA3231B),
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFFF6DCDA),
    onErrorContainer: Color(0xFF7A1A14),
    surface: Color(0xFFF3F2F2),
    onSurface: Color(0xFF201E1D),
    onSurfaceVariant: Color(0xFF5D5854),
    surfaceTint: Colors.transparent,
    surfaceContainerLowest: Color(0xFFFFFFFF),
    surfaceContainerLow: Color(0xFFFFFFFF),
    surfaceContainer: Color(0xFFE9E7E6),
    surfaceContainerHigh: Color(0xFFE9E7E6),
    surfaceContainerHighest: Color(0xFFDEDBD9),
    outline: Color(0xFFB3AEAA),
    outlineVariant: Color(0xFFC9C5C2),
    inverseSurface: Color(0xFF201E1D),
    onInverseSurface: Color(0xFFF3F2F2),
    inversePrimary: Color(0xFF4CB8D8),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
  );

  // "Nocturne" — deepened from the original dark scheme (surface 0x17191A ->
  // 0x0D1013, genuinely near-black rather than dark grey) with richer,
  // slightly more saturated accent colors so they read as glowing against
  // the deeper ground. Every text/icon-on-background pair here was checked
  // against WCAG AA (relative-luminance contrast ratio, the same method
  // used for the info-tone fixes) before landing — darkening a surface
  // while keeping light foreground colors unchanged can only raise the
  // ratio, never lower it, but the container pairs (onPrimaryContainer on
  // primaryContainer, etc.) needed an explicit re-check since both sides
  // moved. All pairs clear 4.5:1 (text) / 3:1 (large text/icons) with
  // margin to spare.
  static const _darkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFF3FC6EA),
    onPrimary: Color(0xFF00303D),
    primaryContainer: Color(0xFF13333F),
    onPrimaryContainer: Color(0xFF86D8EE),
    secondary: Color(0xFFFF6BAE),
    onSecondary: Color(0xFF4A0026),
    secondaryContainer: Color(0xFF431A2E),
    onSecondaryContainer: Color(0xFFFFC2DE),
    error: Color(0xFFF2756B),
    onError: Color(0xFF3F0906),
    errorContainer: Color(0xFF4A1F1B),
    onErrorContainer: Color(0xFFF7B3AD),
    surface: Color(0xFF0D1013),
    onSurface: Color(0xFFE9E7E5),
    onSurfaceVariant: Color(0xFFA6A29E),
    surfaceTint: Colors.transparent,
    surfaceContainerLowest: Color(0xFF171B1E),
    surfaceContainerLow: Color(0xFF171B1E),
    surfaceContainer: Color(0xFF20252A),
    surfaceContainerHigh: Color(0xFF20252A),
    surfaceContainerHighest: Color(0xFF2B3238),
    outline: Color(0xFF4C5359),
    outlineVariant: Color(0xFF383F45),
    inverseSurface: Color(0xFF0A0C0E),
    onInverseSurface: Color(0xFFE9E7E5),
    inversePrimary: Color(0xFF0088B0),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
  );

  static ThemeData _build(ColorScheme scheme, AppSemanticColors semanticColors) {
    const square = RoundedRectangleBorder();
    final base = ThemeData(brightness: scheme.brightness, useMaterial3: true);
    final textTheme = _textTheme(base.textTheme, scheme);
    final hairline = BorderSide(color: scheme.outlineVariant);

    final buttonText = textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600, letterSpacing: 0.2);
    const buttonPadding = EdgeInsets.symmetric(horizontal: 18, vertical: 12);

    return ThemeData(
      useMaterial3: true,
      brightness: scheme.brightness,
      colorScheme: scheme,
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      scaffoldBackgroundColor: scheme.surface,
      canvasColor: scheme.surface,
      extensions: [semanticColors],
      focusColor: scheme.primary.withValues(alpha: 0.12),
      hoverColor: scheme.onSurface.withValues(alpha: 0.05),
      splashFactory: InkRipple.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.inverseSurface,
        foregroundColor: scheme.onInverseSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: textTheme.titleMedium?.copyWith(color: scheme.onInverseSurface, fontWeight: FontWeight.w700),
        iconTheme: IconThemeData(color: scheme.onInverseSurface),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          side: hairline,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(shape: square, padding: buttonPadding, textStyle: buttonText),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(shape: square, padding: buttonPadding, textStyle: buttonText, elevation: 0),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: square,
          padding: buttonPadding,
          textStyle: buttonText,
          foregroundColor: scheme.onSurface,
          side: BorderSide(color: scheme.outline),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(shape: square, textStyle: buttonText, foregroundColor: scheme.primary),
      ),
      iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(shape: square)),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          shape: square,
          side: BorderSide(color: scheme.outline),
          selectedBackgroundColor: scheme.primary,
          selectedForegroundColor: scheme.onPrimary,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        shape: square,
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 2,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLowest,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          borderSide: BorderSide(color: scheme.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          borderSide: BorderSide(color: scheme.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          borderSide: BorderSide(color: scheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          borderSide: BorderSide(color: scheme.error, width: 2),
        ),
        labelStyle: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        hintStyle: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant.withValues(alpha: 0.8)),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        menuStyle: MenuStyle(
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(side: BorderSide(color: scheme.outline))),
          backgroundColor: WidgetStatePropertyAll(scheme.surfaceContainerLowest),
        ),
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1, thickness: 1),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          side: BorderSide(color: scheme.outline),
        ),
        side: BorderSide(color: scheme.outline),
        backgroundColor: Colors.transparent,
        selectedColor: scheme.primaryContainer,
        labelStyle: textTheme.labelMedium,
      ),
      dataTableTheme: DataTableThemeData(
        headingRowColor: WidgetStateProperty.all(scheme.surfaceContainer),
        headingTextStyle: textTheme.labelSmall?.copyWith(
          color: scheme.onSurfaceVariant,
          letterSpacing: 1.1,
          fontWeight: FontWeight.w600,
        ),
        dividerThickness: 1,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        elevation: 6,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          side: hairline,
        ),
        titleTextStyle: textTheme.titleLarge,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: scheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(side: BorderSide(color: scheme.outline)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(),
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: scheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: scheme.onInverseSurface),
        shape: square,
        behavior: SnackBarBehavior.floating,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(color: scheme.inverseSurface),
        textStyle: textTheme.bodySmall?.copyWith(color: scheme.onInverseSurface),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: scheme.primary,
        unselectedLabelColor: scheme.onSurfaceVariant,
        indicatorColor: scheme.primary,
        dividerColor: scheme.outlineVariant,
        labelStyle: textTheme.titleSmall,
      ),
      listTileTheme: ListTileThemeData(
        shape: square,
        selectedColor: scheme.onSurface,
        selectedTileColor: scheme.primaryContainer,
        iconColor: scheme.onSurfaceVariant,
      ),
      navigationRailTheme: NavigationRailThemeData(backgroundColor: scheme.surfaceContainerLowest),
      badgeTheme: BadgeThemeData(backgroundColor: scheme.secondary, textColor: scheme.onSecondary),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: scheme.primary),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(scheme.outline),
        radius: Radius.zero,
      ),
    );
  }

  /// Source Serif 4 for everything — "the serif is the chrome". Headings are
  /// bold with slightly tight tracking; small caps-style labels get extra
  /// letter-spacing where the components ask for it.
  static TextTheme _textTheme(TextTheme base, ColorScheme scheme) {
    final serif = GoogleFonts.sourceSerif4TextTheme(base).apply(
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    );
    TextStyle? bold(TextStyle? s) => s?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.2);
    return serif.copyWith(
      displayLarge: bold(serif.displayLarge),
      displayMedium: bold(serif.displayMedium),
      displaySmall: bold(serif.displaySmall),
      headlineLarge: bold(serif.headlineLarge),
      headlineMedium: bold(serif.headlineMedium),
      headlineSmall: bold(serif.headlineSmall),
      titleLarge: bold(serif.titleLarge),
      titleMedium: serif.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      titleSmall: serif.titleSmall?.copyWith(fontWeight: FontWeight.w600),
    );
  }
}
