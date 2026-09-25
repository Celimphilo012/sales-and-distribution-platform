import 'package:flutter/material.dart';

import 'empty_loading_error_states.dart';

/// The List view every records screen adopting the list/table/grid pattern
/// shares — denser than [AppDataTable]'s own mobile card fallback (no card
/// chrome, a hairline between rows, everything on one line). Callers supply
/// just the per-row content via [rowBuilder]; this owns the empty state,
/// separators, and tap handling.
class CompactRowList<T> extends StatelessWidget {
  const CompactRowList({
    super.key,
    required this.items,
    required this.rowBuilder,
    this.onTap,
    this.emptyTitle = 'No records',
    this.emptyMessage,
  });

  final List<T> items;
  final Widget Function(BuildContext context, T item) rowBuilder;
  final void Function(T item)? onTap;
  final String emptyTitle;
  final String? emptyMessage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (items.isEmpty) {
      return EmptyStateView(title: emptyTitle, message: emptyMessage);
    }

    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (context, index) => Divider(height: 1, color: theme.colorScheme.outlineVariant),
      itemBuilder: (context, index) {
        final item = items[index];
        final row = Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: rowBuilder(context, item),
        );
        if (onTap == null) return row;
        return InkWell(onTap: () => onTap!(item), child: row);
      },
    );
  }
}
