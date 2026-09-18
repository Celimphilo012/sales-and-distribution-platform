import 'package:flutter/material.dart';

import '../../core/theme/app_semantic_colors.dart';
import '../../core/theme/app_spacing.dart';

/// Semantic tone a [StatusBadge] renders in. Maps onto [ColorScheme] /
/// [AppSemanticColors] tokens — never a literal [Color].
enum StatusTone { neutral, success, warning, danger, info }

/// A small pill label for record status (order status, approval state,
/// stock-count status, etc). Callers choose a [StatusTone]; this widget
/// owns the color mapping so every status pill in the app looks consistent.
class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.label, this.tone = StatusTone.neutral});

  final String label;
  final StatusTone tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = context.semanticColors;

    final (background, foreground) = switch (tone) {
      StatusTone.neutral => (theme.colorScheme.surfaceContainerHighest, theme.colorScheme.onSurfaceVariant),
      StatusTone.success => (semantic.successContainer, semantic.onSuccessContainer),
      StatusTone.warning => (semantic.warningContainer, semantic.onWarningContainer),
      StatusTone.danger => (theme.colorScheme.errorContainer, theme.colorScheme.onErrorContainer),
      StatusTone.info => (semantic.infoContainer, semantic.onInfoContainer),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(AppSpacing.radiusLg)),
      child: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(color: foreground, fontWeight: FontWeight.w600),
      ),
    );
  }
}
