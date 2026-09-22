import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../core/theme/app_spacing.dart';
import '../routing/nav_items.dart';

/// The tablet navigation rail: one entry per nav GROUP (icon + short
/// caption). A single-destination group navigates straight away; a
/// multi-destination group opens a small menu beside the rail listing its
/// items — so the grouping carries over from the sidebar without a 16-icon
/// column. The hamburger in the top bar opens the full grouped drawer.
class GroupedNavRail extends StatelessWidget {
  const GroupedNavRail({super.key, required this.groups, required this.activePath});

  static const double width = 76;

  final List<NavGroup> groups;
  final String activePath;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final activeItem = navItemMatching(groups.expand((g) => g.items), activePath);
    final activeGroup = navGroupOf(groups, activeItem);

    return Container(
      width: width,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        border: Border(right: BorderSide(color: scheme.outlineVariant)),
      ),
      child: ListView(
        padding: const EdgeInsets.only(top: AppSpacing.sm),
        children: [
          for (final group in groups)
            _RailEntry(group: group, selected: group.id == activeGroup?.id, activePath: activeItem?.path),
        ],
      ),
    );
  }
}

class _RailEntry extends StatelessWidget {
  const _RailEntry({required this.group, required this.selected, required this.activePath});

  final NavGroup group;
  final bool selected;
  final String? activePath;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final face = Container(
      width: GroupedNavRail.width,
      padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 2),
      decoration: BoxDecoration(
        color: selected ? scheme.primaryContainer : null,
        border: Border(left: BorderSide(width: 3, color: selected ? scheme.primary : Colors.transparent)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PhosphorIcon(group.icon, size: 22, color: selected ? scheme.primary : scheme.onSurfaceVariant),
          const SizedBox(height: 3),
          Text(
            group.shortLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: textTheme.labelSmall?.copyWith(
              fontSize: 10,
              color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );

    if (group.items.length == 1) {
      return Semantics(
        button: true,
        selected: selected,
        label: group.title,
        child: InkWell(onTap: () => context.go(group.items.first.path), child: face),
      );
    }

    return PopupMenuButton<NavItem>(
      tooltip: group.title,
      position: PopupMenuPosition.over,
      offset: const Offset(GroupedNavRail.width, 0),
      onSelected: (item) => context.go(item.path),
      itemBuilder: (context) => [
        for (final item in group.items)
          PopupMenuItem<NavItem>(
            value: item,
            child: Row(
              children: [
                PhosphorIcon(
                  item.icon,
                  size: 18,
                  color: item.path == activePath ? scheme.primary : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: AppSpacing.sm + 2),
                Flexible(
                  child: Text(
                    item.label,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodyMedium?.copyWith(
                      fontWeight: item.path == activePath ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
      child: face,
    );
  }
}
