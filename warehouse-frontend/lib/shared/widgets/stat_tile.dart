import 'package:flutter/material.dart';

import '../../core/theme/app_semantic_colors.dart';
import '../../core/theme/app_spacing.dart';
import 'status_badge.dart';

/// One compact stat for a list screen's summary row — e.g. Products' "25
/// active", "3 below minimum". Deliberately tighter than the dashboard's own
/// KPI tile (this sits ABOVE a records list, not as the page's whole
/// content), so every page that adopts the list/table/grid pattern gets a
/// consistent, un-bloated stats strip regardless of how many rows the list
/// itself has.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.tone = StatusTone.neutral,
    this.icon,
  });

  final String label;
  final String value;
  final StatusTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = context.semanticColors;
    final accent = switch (tone) {
      StatusTone.warning => semantic.warning,
      StatusTone.danger => theme.colorScheme.error,
      StatusTone.success => semantic.success,
      StatusTone.info => semantic.info,
      StatusTone.neutral => theme.colorScheme.onSurfaceVariant,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 15, color: accent),
            const SizedBox(width: AppSpacing.xs),
          ],
          Text(value, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: accent)),
          const SizedBox(width: AppSpacing.xs),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
