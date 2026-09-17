import 'package:flutter/material.dart';

import '../../core/responsive/responsive_layout.dart';
import '../../core/theme/app_spacing.dart';
import 'app_card.dart';
import 'empty_loading_error_states.dart';

/// One column of an [AppDataTable]: a header label plus how to render a
/// cell for a given row of [T].
class AppDataColumn<T> {
  const AppDataColumn({required this.label, required this.cellBuilder, this.numeric = false});

  final String label;
  final Widget Function(T row) cellBuilder;
  final bool numeric;
}

/// A list of records rendered as a [DataTable] on tablet/desktop and as a
/// stack of [AppCard]s on mobile — the same data, laid out per
/// ARCHITECTURE.md §L ("Desktop = data tables ... Mobile = cards").
///
/// Feature screens supply [columns] once; this widget owns the
/// responsive switch so no screen has to build two separate layouts.
class AppDataTable<T> extends StatelessWidget {
  const AppDataTable({
    super.key,
    required this.rows,
    required this.columns,
    this.emptyTitle = 'No records',
    this.emptyMessage,
    this.onRowTap,
  });

  final List<T> rows;
  final List<AppDataColumn<T>> columns;
  final String emptyTitle;
  final String? emptyMessage;
  final void Function(T row)? onRowTap;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return EmptyStateView(title: emptyTitle, message: emptyMessage);
    }

    return ResponsiveLayout(
      mobile: (context) => _MobileCardList(rows: rows, columns: columns, onRowTap: onRowTap),
      desktop: (context) => _DesktopTable(rows: rows, columns: columns, onRowTap: onRowTap),
    );
  }
}

class _DesktopTable<T> extends StatelessWidget {
  const _DesktopTable({required this.rows, required this.columns, required this.onRowTap});

  final List<T> rows;
  final List<AppDataColumn<T>> columns;
  final void Function(T row)? onRowTap;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: [for (final column in columns) DataColumn(label: Text(column.label), numeric: column.numeric)],
        rows: [
          for (final row in rows)
            DataRow(
              onSelectChanged: onRowTap == null ? null : (_) => onRowTap!(row),
              cells: [for (final column in columns) DataCell(column.cellBuilder(row))],
            ),
        ],
      ),
    );
  }
}

class _MobileCardList<T> extends StatelessWidget {
  const _MobileCardList({required this.rows, required this.columns, required this.onRowTap});

  final List<T> rows;
  final List<AppDataColumn<T>> columns;
  final void Function(T row)? onRowTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView.separated(
      // shrinkWrap (matching AppTreeView's own list) lets this size itself
      // to its content instead of demanding a bounded viewport height, so a
      // caller can embed an AppDataTable inside an already-scrolling
      // ancestor (e.g. a detail panel's outer SingleChildScrollView)
      // without a "vertical viewport was given unbounded height" crash —
      // while a bounded ancestor (the common case) still scrolls normally.
      shrinkWrap: true,
      padding: const EdgeInsets.all(AppSpacing.md),
      itemCount: rows.length,
      separatorBuilder: (context, index) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (context, index) {
        final row = rows[index];
        return InkWell(
          onTap: onRowTap == null ? null : () => onRowTap!(row),
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          child: AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final column in columns)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs / 2),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 120,
                          child: Text(
                            column.label,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        Expanded(child: column.cellBuilder(row)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
