import 'package:flutter/material.dart';

/// Semantic colors (success/warning/info) that Material 3's [ColorScheme]
/// doesn't provide out of the box. Exposed as a [ThemeExtension] so widgets
/// read them the same way they read [ColorScheme] — via `Theme.of(context)`,
/// never as a hard-coded [Color] literal.
class AppSemanticColors extends ThemeExtension<AppSemanticColors> {
  const AppSemanticColors({
    required this.success,
    required this.onSuccess,
    required this.successContainer,
    required this.onSuccessContainer,
    required this.warning,
    required this.onWarning,
    required this.warningContainer,
    required this.onWarningContainer,
    required this.info,
    required this.onInfo,
    required this.infoContainer,
    required this.onInfoContainer,
  });

  final Color success;
  final Color onSuccess;
  final Color successContainer;
  final Color onSuccessContainer;

  final Color warning;
  final Color onWarning;
  final Color warningContainer;
  final Color onWarningContainer;

  final Color info;
  final Color onInfo;
  final Color infoContainer;
  final Color onInfoContainer;

  static const light = AppSemanticColors(
    success: Color(0xFF1C6B3A),
    onSuccess: Color(0xFFFFFFFF),
    successContainer: Color(0xFFE1EFE6),
    onSuccessContainer: Color(0xFF14502B),
    warning: Color(0xFF8A5A00),
    onWarning: Color(0xFFFFFFFF),
    warningContainer: Color(0xFFF6EAD2),
    onWarningContainer: Color(0xFF6B4500),
    // Housekeeping 2a: both darkened along the same hue from 0088B0/006B8C.
    // `info` is used as TEXT (StatusBadge's outline tag reads it straight,
    // not through onInfoContainer) on white/paper — was 3.30:1/2.95:1, a
    // real fail; #006486 clears 4.5:1 against both (5.47 / 4.89). The
    // infoContainer/onInfoContainer pair was marginal at 4.29:1; #005F7F
    // clears it at 5.12:1.
    info: Color(0xFF006486),
    onInfo: Color(0xFFFFFFFF),
    infoContainer: Color(0xFFDCEEF4),
    onInfoContainer: Color(0xFF005F7F),
  );

  static const dark = AppSemanticColors(
    success: Color(0xFF5CC286),
    onSuccess: Color(0xFF0F2A1A),
    successContainer: Color(0xFF15301F),
    onSuccessContainer: Color(0xFF5CC286),
    warning: Color(0xFFE0A640),
    onWarning: Color(0xFF3A2600),
    warningContainer: Color(0xFF3A2C10),
    onWarningContainer: Color(0xFFE0A640),
    // Mirrors AppTheme's nocturne primary/primaryContainer/onPrimaryContainer
    // exactly (deliberate, same as before) — re-verified at 4.5:1+ against
    // the deepened surface/container tones.
    info: Color(0xFF3FC6EA),
    onInfo: Color(0xFF00303D),
    infoContainer: Color(0xFF13333F),
    onInfoContainer: Color(0xFF86D8EE),
  );

  @override
  AppSemanticColors copyWith({
    Color? success,
    Color? onSuccess,
    Color? successContainer,
    Color? onSuccessContainer,
    Color? warning,
    Color? onWarning,
    Color? warningContainer,
    Color? onWarningContainer,
    Color? info,
    Color? onInfo,
    Color? infoContainer,
    Color? onInfoContainer,
  }) {
    return AppSemanticColors(
      success: success ?? this.success,
      onSuccess: onSuccess ?? this.onSuccess,
      successContainer: successContainer ?? this.successContainer,
      onSuccessContainer: onSuccessContainer ?? this.onSuccessContainer,
      warning: warning ?? this.warning,
      onWarning: onWarning ?? this.onWarning,
      warningContainer: warningContainer ?? this.warningContainer,
      onWarningContainer: onWarningContainer ?? this.onWarningContainer,
      info: info ?? this.info,
      onInfo: onInfo ?? this.onInfo,
      infoContainer: infoContainer ?? this.infoContainer,
      onInfoContainer: onInfoContainer ?? this.onInfoContainer,
    );
  }

  @override
  AppSemanticColors lerp(ThemeExtension<AppSemanticColors>? other, double t) {
    if (other is! AppSemanticColors) return this;
    return AppSemanticColors(
      success: Color.lerp(success, other.success, t)!,
      onSuccess: Color.lerp(onSuccess, other.onSuccess, t)!,
      successContainer: Color.lerp(successContainer, other.successContainer, t)!,
      onSuccessContainer: Color.lerp(onSuccessContainer, other.onSuccessContainer, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      onWarning: Color.lerp(onWarning, other.onWarning, t)!,
      warningContainer: Color.lerp(warningContainer, other.warningContainer, t)!,
      onWarningContainer: Color.lerp(onWarningContainer, other.onWarningContainer, t)!,
      info: Color.lerp(info, other.info, t)!,
      onInfo: Color.lerp(onInfo, other.onInfo, t)!,
      infoContainer: Color.lerp(infoContainer, other.infoContainer, t)!,
      onInfoContainer: Color.lerp(onInfoContainer, other.onInfoContainer, t)!,
    );
  }
}

/// Convenience accessor: `context.semanticColors.success`.
extension AppSemanticColorsX on BuildContext {
  AppSemanticColors get semanticColors => Theme.of(this).extension<AppSemanticColors>()!;
}
