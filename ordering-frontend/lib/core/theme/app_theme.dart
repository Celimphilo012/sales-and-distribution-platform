import 'package:flutter/material.dart';

import 'app_semantic_colors.dart';
import 'app_spacing.dart';

/// Builds the app's light and dark [ThemeData] from a single seed color and
/// the shared [AppSemanticColors] token sets.
///
/// This is the ONLY place `Color`/`ColorScheme` literals should be composed
/// into a theme. Every widget elsewhere must read colors via
/// `Theme.of(context)` (or `context.semanticColors`) — never hard-code a
/// [Color] value.
class AppTheme {
  const AppTheme._();

  static const _seedColor = Color(0xFF1E5FA8);

  static ThemeData light() => _build(brightness: Brightness.light, semanticColors: AppSemanticColors.light);

  static ThemeData dark() => _build(brightness: Brightness.dark, semanticColors: AppSemanticColors.dark);

  static ThemeData _build({required Brightness brightness, required AppSemanticColors semanticColors}) {
    final colorScheme = ColorScheme.fromSeed(seedColor: _seedColor, brightness: brightness);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.surface,
      extensions: [semanticColors],
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 1,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: colorScheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(backgroundColor: colorScheme.surfaceContainerLow),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.radiusSm)),
        filled: true,
        fillColor: colorScheme.surfaceContainerLowest,
      ),
      dividerTheme: DividerThemeData(color: colorScheme.outlineVariant, space: 1),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.radiusLg)),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      dataTableTheme: DataTableThemeData(
        headingRowColor: WidgetStateProperty.all(colorScheme.surfaceContainerLow),
      ),
    );
  }
}
