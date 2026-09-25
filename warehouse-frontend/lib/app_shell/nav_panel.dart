import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../core/auth/auth_provider.dart';
import '../core/theme/app_semantic_colors.dart';
import '../core/theme/app_spacing.dart';
import '../features/stock_adjustments/data/stock_adjustments_providers.dart';
import '../features/stock_adjustments/domain/stock_adjustment.dart';
import '../routing/nav_items.dart';
import '../routing/route_paths.dart';
import 'nav_expansion_provider.dart';

/// Nav-item paths that carry a live count badge, and how to compute it.
/// Currently just one (Stock Adjustments, for a manager's unattended
/// backlog) — a `Map<String, int>` keeps the door open for more without
/// [NavPanel]'s own layout code needing to know about any of them by name.
Map<String, int> _navBadges(WidgetRef ref) {
  final canApprove = ref.watch(authProvider.select((s) => s.value?.user?.can('inventory.adjust.approve') ?? false));
  if (!canApprove) return const {};
  final pending = ref.watch(stockAdjustmentsListProvider(AdjustmentStatus.pending));
  final count = pending.value?.length ?? 0;
  return count > 0 ? {RoutePaths.stockAdjustments: count} : const {};
}

/// The grouped, collapsible navigation list shared by the desktop sidebar
/// and the mobile/tablet drawer.
///
/// Groups ("Warehousing", "Stock", "User management"…) expand to reveal
/// their items; the group that owns the current route opens automatically.
/// [onNavigate] fires after a destination is chosen so a drawer can close
/// itself.
class NavPanel extends ConsumerStatefulWidget {
  const NavPanel({super.key, required this.groups, required this.activePath, this.onNavigate});

  final List<NavGroup> groups;
  final String activePath;
  final VoidCallback? onNavigate;

  @override
  ConsumerState<NavPanel> createState() => _NavPanelState();
}

class _NavPanelState extends ConsumerState<NavPanel> {
  String? get _activeGroupId {
    final item = navItemMatching(widget.groups.expand((g) => g.items), widget.activePath);
    return navGroupOf(widget.groups, item)?.id;
  }

  @override
  void initState() {
    super.initState();
    _revealActiveGroup();
  }

  @override
  void didUpdateWidget(NavPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Also re-reveal when the visible groups change (e.g. the signed-in
    // user's permissions finish loading after the first frame), since the
    // owning group may only exist now.
    if (oldWidget.activePath != widget.activePath || _itemCount(oldWidget.groups) != _itemCount(widget.groups)) {
      _revealActiveGroup();
    }
  }

  static int _itemCount(List<NavGroup> groups) => groups.fold(0, (sum, g) => sum + g.items.length);

  /// Provider state can't change during build, so open the owning group on
  /// the next frame.
  void _revealActiveGroup() {
    final id = _activeGroupId;
    if (id == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(navExpansionProvider.notifier).open(id);
    });
  }

  void _go(NavItem item) {
    context.go(item.path);
    widget.onNavigate?.call();
  }

  @override
  Widget build(BuildContext context) {
    final expanded = ref.watch(navExpansionProvider);
    final activeItem = navItemMatching(widget.groups.expand((g) => g.items), widget.activePath);
    final activeGroupId = _activeGroupId;
    final badges = _navBadges(ref);

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      children: [
        for (final group in widget.groups)
          if (group.flat)
            _NavRow(
              icon: group.items.first.icon,
              label: group.items.first.label,
              selected: activeItem?.path == group.items.first.path,
              badgeCount: badges[group.items.first.path],
              onTap: () => _go(group.items.first),
            )
          else
            _NavGroupTile(
              group: group,
              expanded: expanded.contains(group.id),
              holdsActiveRoute: activeGroupId == group.id,
              activePath: activeItem?.path,
              badges: badges,
              onToggle: () => ref.read(navExpansionProvider.notifier).toggle(group.id),
              onSelect: _go,
            ),
      ],
    );
  }
}

class _NavGroupTile extends StatelessWidget {
  const _NavGroupTile({
    required this.group,
    required this.expanded,
    required this.holdsActiveRoute,
    required this.activePath,
    required this.badges,
    required this.onToggle,
    required this.onSelect,
  });

  final NavGroup group;
  final bool expanded;
  final bool holdsActiveRoute;
  final String? activePath;
  final Map<String, int> badges;
  final VoidCallback onToggle;
  final ValueChanged<NavItem> onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    // A collapsed group that hides the current page keeps a cyan cue so the
    // user always knows where they are.
    final cue = holdsActiveRoute && !expanded;
    // While collapsed, a badged item's count still needs to surface
    // somewhere — sum onto the group header itself so it's never silently
    // hidden behind a closed group.
    final groupBadgeTotal = group.items.fold(0, (sum, item) => sum + (badges[item.path] ?? 0));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          expanded: expanded,
          label: group.title,
          child: InkWell(
            onTap: onToggle,
            child: Container(
              constraints: const BoxConstraints(minHeight: 42),
              padding: const EdgeInsets.only(left: AppSpacing.md, right: AppSpacing.sm),
              decoration: BoxDecoration(
                border: Border(left: BorderSide(width: 3, color: cue ? scheme.primary : Colors.transparent)),
              ),
              child: Row(
                children: [
                  PhosphorIcon(
                    group.icon,
                    size: 20,
                    color: holdsActiveRoute ? scheme.primary : scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: AppSpacing.sm + 2),
                  Expanded(
                    child: Text(
                      group.title,
                      style: textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                  if (!expanded && groupBadgeTotal > 0) ...[
                    _NavBadge(count: groupBadgeTotal),
                    const SizedBox(width: AppSpacing.xs),
                  ],
                  AnimatedRotation(
                    turns: expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 160),
                    child: PhosphorIcon(PhosphorIconsBold.caretDown, size: 14, color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: expanded
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final item in group.items)
                      _NavRow(
                        icon: item.icon,
                        label: item.label,
                        selected: activePath == item.path,
                        indent: true,
                        badgeCount: badges[item.path],
                        onTap: () => onSelect(item),
                      ),
                    const SizedBox(height: AppSpacing.xs),
                  ],
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

class _NavRow extends StatelessWidget {
  const _NavRow({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.indent = false,
    this.badgeCount,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final bool indent;
  final VoidCallback onTap;

  /// A live count (e.g. unattended pending adjustments) — null/0 shows nothing.
  final int? badgeCount;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Semantics(
      button: true,
      selected: selected,
      label: badgeCount != null && badgeCount! > 0 ? '$label, $badgeCount pending' : label,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 40),
          padding: EdgeInsets.only(
            left: indent ? AppSpacing.xl : AppSpacing.md,
            right: AppSpacing.md,
          ),
          decoration: BoxDecoration(
            color: selected ? scheme.primaryContainer : null,
            border: Border(left: BorderSide(width: 3, color: selected ? scheme.primary : Colors.transparent)),
          ),
          child: Row(
            children: [
              PhosphorIcon(
                icon,
                size: indent ? 18 : 20,
                color: selected ? scheme.primary : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: AppSpacing.sm + 2),
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                    color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (badgeCount != null && badgeCount! > 0) _NavBadge(count: badgeCount!),
            ],
          ),
        ),
      ),
    );
  }
}

/// A small count pill for a nav row/group — warning tone (matches the
/// dashboard's own "pending adjustments" tile) since every current use is an
/// unattended backlog someone needs to act on, not a neutral tally.
class _NavBadge extends StatelessWidget {
  const _NavBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = context.semanticColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      constraints: const BoxConstraints(minWidth: 20),
      decoration: BoxDecoration(color: semantic.warning, borderRadius: BorderRadius.circular(AppSpacing.radiusSm)),
      child: Text(
        count > 99 ? '99+' : '$count',
        textAlign: TextAlign.center,
        style: theme.textTheme.labelSmall?.copyWith(color: semantic.onWarning, fontWeight: FontWeight.w700),
      ),
    );
  }
}
