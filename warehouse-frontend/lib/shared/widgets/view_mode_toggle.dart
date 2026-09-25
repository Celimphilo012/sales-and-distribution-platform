import 'package:flutter/material.dart';

/// The three ways a records screen can lay out the same underlying rows.
/// [table] is always the existing [AppDataTable] (dense, sortable-feeling,
/// desktop-native); [list] is a denser single-column list than the table's
/// own mobile card fallback; [grid] is for browsing by eye (e.g. a product's
/// image matters more than its raw fields).
enum ViewMode { list, table, grid }

/// A small persisted-per-screen view-mode switcher. Each screen keeps its
/// own [ViewMode] state (a `Notifier` is overkill for something this
/// local) and just renders whichever branch matches — this widget only
/// owns the toggle control itself, not the three render paths.
class ViewModeToggle extends StatelessWidget {
  const ViewModeToggle({super.key, required this.value, required this.onChanged});

  final ViewMode value;
  final ValueChanged<ViewMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<ViewMode>(
      segments: const [
        ButtonSegment(value: ViewMode.list, label: Text('List'), icon: Icon(Icons.view_list_outlined)),
        ButtonSegment(value: ViewMode.table, label: Text('Table'), icon: Icon(Icons.table_rows_outlined)),
        ButtonSegment(value: ViewMode.grid, label: Text('Grid'), icon: Icon(Icons.grid_view_outlined)),
      ],
      selected: {value},
      showSelectedIcon: false,
      onSelectionChanged: (selection) => onChanged(selection.first),
    );
  }
}
