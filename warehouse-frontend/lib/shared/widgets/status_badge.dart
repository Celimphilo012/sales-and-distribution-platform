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

    // Outlined tag (Broadsheet): a 1px rule and text in the tone color on a
    // transparent ground — status reads as a stamp, not a filled pill.
    final foreground = switch (tone) {
      StatusTone.neutral => theme.colorScheme.onSurfaceVariant,
      StatusTone.success => semantic.success,
      StatusTone.warning => semantic.warning,
      StatusTone.danger => theme.colorScheme.error,
      StatusTone.info => semantic.info,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: foreground),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(color: foreground, fontWeight: FontWeight.w600),
      ),
    );
  }
}
