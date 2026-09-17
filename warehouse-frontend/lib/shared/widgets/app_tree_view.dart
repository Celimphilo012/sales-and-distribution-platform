import 'package:flutter/material.dart';

import '../../core/theme/app_spacing.dart';

/// A generic, self-contained expandable tree — reusable for ANY tree-shaped
/// domain data (locations today; a future feature can pass its own node type
/// without touching this widget). The caller supplies how to read a node's
/// id and children; this widget owns indentation, the expand/collapse
/// chevron, and expansion state. Rows are just `contentBuilder(node)` — the
/// caller decides what a row looks like (icon, label, status badge,
/// trailing actions), this widget only decides where it sits in the tree.
///
/// Depth is NOT assumed to be bounded — [roots] can nest arbitrarily deep
/// (CLAUDE.md rule 5: never hard-code a location hierarchy depth).
class AppTreeView<T> extends StatefulWidget {
  const AppTreeView({
    super.key,
    required this.roots,
    required this.childrenOf,
    required this.idOf,
    required this.contentBuilder,
    this.selectedId,
    this.initiallyCollapsedIds = const {},
  });

  final List<T> roots;
  final List<T> Function(T node) childrenOf;
  final String Function(T node) idOf;
  final Widget Function(BuildContext context, T node, {required bool isSelected}) contentBuilder;
  final String? selectedId;

  /// Node ids that start collapsed. Everything else starts expanded — for a
  /// structure tree, seeing the whole hierarchy immediately is more useful
  /// than a fully-collapsed default.
  final Set<String> initiallyCollapsedIds;

  @override
  State<AppTreeView<T>> createState() => _AppTreeViewState<T>();
}

class _AppTreeViewState<T> extends State<AppTreeView<T>> {
  late Set<String> _collapsedIds;

  @override
  void initState() {
    super.initState();
    _collapsedIds = {...widget.initiallyCollapsedIds};
  }

  void _toggle(String id) {
    setState(() {
      if (!_collapsedIds.add(id)) _collapsedIds.remove(id);
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      shrinkWrap: true,
      children: [for (final root in widget.roots) ..._buildNode(root, 0)],
    );
  }

  List<Widget> _buildNode(T node, int depth) {
    final id = widget.idOf(node);
    final children = widget.childrenOf(node);
    final hasChildren = children.isNotEmpty;
    final isCollapsed = _collapsedIds.contains(id);
    final isSelected = id == widget.selectedId;

    return [
      Padding(
        padding: EdgeInsets.only(left: AppSpacing.lg * depth),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 28,
              height: 28,
              child: hasChildren
                  ? IconButton(
                      padding: EdgeInsets.zero,
                      iconSize: 18,
                      icon: Icon(isCollapsed ? Icons.chevron_right : Icons.expand_more),
                      tooltip: isCollapsed ? 'Expand' : 'Collapse',
                      onPressed: () => _toggle(id),
                    )
                  : null,
            ),
            Expanded(child: widget.contentBuilder(context, node, isSelected: isSelected)),
          ],
        ),
      ),
      if (hasChildren && !isCollapsed)
        for (final child in children) ..._buildNode(child, depth + 1),
    ];
  }
}
