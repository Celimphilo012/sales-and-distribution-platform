import 'package:flutter/material.dart';

import '../../core/responsive/breakpoints.dart';
import '../../core/theme/app_spacing.dart';
import 'empty_loading_error_states.dart';

/// The Grid view every records screen adopting the list/table/grid pattern
/// shares — a browse-by-eye layout: an optional leading visual (an image
/// for screens that have one, like Products/Workstreams; an icon otherwise)
/// over a compact text block. Callers supply just [leadingBuilder] (the
/// square visual) and [contentBuilder] (the text block below it); this owns
/// the grid delegate, spacing, tap handling, and empty state.
class SimpleGridView<T> extends StatelessWidget {
  const SimpleGridView({
    super.key,
    required this.items,
    required this.contentBuilder,
    this.leadingBuilder,
    this.onTap,
    this.emptyTitle = 'No records',
    this.emptyMessage,
    this.maxCrossAxisExtent = 220,
    this.childAspectRatio = 0.9,
  });

  final List<T> items;
  final Widget Function(BuildContext context, T item) contentBuilder;
  final Widget Function(BuildContext context, T item)? leadingBuilder;
  final void Function(T item)? onTap;
  final String emptyTitle;
  final String? emptyMessage;
  final double maxCrossAxisExtent;
  final double childAspectRatio;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (items.isEmpty) {
      return EmptyStateView(title: emptyTitle, message: emptyMessage);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < Breakpoints.dataTableMin;
        return GridView.builder(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: compact ? maxCrossAxisExtent * 0.8 : maxCrossAxisExtent,
            mainAxisSpacing: AppSpacing.sm,
            crossAxisSpacing: AppSpacing.sm,
            childAspectRatio: childAspectRatio,
          ),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            final tile = Container(
              decoration: BoxDecoration(
                border: Border.all(color: theme.colorScheme.outlineVariant),
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (leadingBuilder != null)
                    AspectRatio(
                      aspectRatio: 1.8,
                      child: ClipRRect(
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppSpacing.radiusSm)),
                        child: leadingBuilder!(context, item),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    child: contentBuilder(context, item),
                  ),
                ],
              ),
            );
            return onTap == null ? tile : InkWell(onTap: () => onTap!(item), child: tile);
          },
        );
      },
    );
  }
}
