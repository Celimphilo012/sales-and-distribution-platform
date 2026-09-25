import 'package:flutter/material.dart';

import '../../domain/product.dart';

/// Renders a product's category as the parent category's name, with the
/// sub-category (if any) shown as a small tag just below it — rather than
/// inline "Parent (Sub-category)" parentheses — so the two levels read as
/// distinct pieces of information at a glance. A top-level category (no
/// parent) just shows its own name, nothing below it.
class CategoryDisplay extends StatelessWidget {
  const CategoryDisplay({super.key, required this.category, this.compact = false});

  final ProductCategoryRef? category;

  /// Smaller text for tight spaces (the products table, a compact list row).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final category = this.category;
    if (category == null) {
      return Text('—', style: compact ? theme.textTheme.bodySmall : null);
    }

    final parentName = category.parent?.name;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          parentName ?? category.name,
          overflow: TextOverflow.ellipsis,
          style: compact ? theme.textTheme.bodySmall : theme.textTheme.bodyMedium,
        ),
        if (parentName != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: theme.colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                category.name,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSecondaryContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
