import 'package:flutter/material.dart';

import '../../core/theme/app_semantic_colors.dart';
import '../../core/theme/app_spacing.dart';
import 'status_badge.dart';

/// One headline number (dashboard / report summary): an icon, a big value,
/// a label and an optional detail line. [onTap] makes the whole tile a link.
class KpiTile extends StatelessWidget {
  const KpiTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.detail,
    this.tone = StatusTone.neutral,
    this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final String? detail;
  final StatusTone tone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = context.semanticColors;
    final (accent, ground) = switch (tone) {
      StatusTone.success => (semantic.success, semantic.successContainer),
      StatusTone.warning => (semantic.warning, semantic.warningContainer),
      StatusTone.danger => (theme.colorScheme.error, theme.colorScheme.errorContainer),
      StatusTone.info => (semantic.info, semantic.infoContainer),
      StatusTone.neutral => (theme.colorScheme.primary, theme.colorScheme.primaryContainer),
    };

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: ground, borderRadius: BorderRadius.circular(AppSpacing.radiusMd)),
                child: Icon(icon, color: accent),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(value, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                    ),
                    if (detail != null)
                      Text(
                        detail!,
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              if (onTap != null) Icon(Icons.chevron_right, color: theme.colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

/// Lays [children] out in as many equal columns as fit (min [minTileWidth] each).
class KpiGrid extends StatelessWidget {
  const KpiGrid({super.key, required this.children, this.minTileWidth = 240});

  final List<Widget> children;
  final double minTileWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = (constraints.maxWidth / minTileWidth).floor().clamp(1, children.length);
        final width = (constraints.maxWidth - (columns - 1) * AppSpacing.sm) / columns;
        return Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [for (final child in children) SizedBox(width: width, child: child)],
        );
      },
    );
  }
}
