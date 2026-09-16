import 'package:flutter/material.dart';

import '../../core/theme/app_spacing.dart';

/// Standard content card: title, optional subtitle/trailing, padded body.
/// Wraps [Card] so every panel in the app shares the same shape/elevation
/// from [ThemeData.cardTheme] instead of redefining it per screen.
class AppCard extends StatelessWidget {
  const AppCard({super.key, this.title, this.subtitle, this.trailing, required this.child, this.padding});

  final String? title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: padding ?? const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title != null)
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title!, style: theme.textTheme.titleMedium),
                        if (subtitle != null)
                          Padding(
                            padding: const EdgeInsets.only(top: AppSpacing.xs),
                            child: Text(
                              subtitle!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  ?trailing,
                ],
              ),
            if (title != null) const SizedBox(height: AppSpacing.md),
            child,
          ],
        ),
      ),
    );
  }
}
