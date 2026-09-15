import 'package:flutter/material.dart';

import '../../core/theme/app_spacing.dart';

/// Generic placeholder for a nav destination whose feature hasn't been
/// built yet. One shared widget so `features/*` stay empty until each
/// feature actually gets built, instead of a throwaway screen file per
/// section.
class ComingSoonView extends StatelessWidget {
  const ComingSoonView({super.key, required this.title, this.icon = Icons.construction_outlined});

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: AppSpacing.md),
            Text(title, style: theme.textTheme.headlineSmall),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'This section is coming soon.',
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
