import 'package:flutter/widgets.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../core/auth/app_user.dart';
import 'route_paths.dart';

/// A single navigation destination (one routed screen).
///
/// [requiredPermissions] is an "any of" list: an empty list means the item
/// is always visible (e.g. Dashboard, Settings); a non-empty list means the
/// signed-in user must hold at least one of those permission strings —
/// mirroring the WAREHOUSE backend's permission catalog (never a role name,
/// and never an ordering-side key like `orders.*`/`customers.*` — those
/// don't exist on this system).
class NavItem {
  const NavItem({
    required this.label,
    required this.path,
    required this.icon,
    this.requiredPermissions = const [],
  });

  final String label;
  final String path;

  /// A Phosphor duotone glyph. Render it with `PhosphorIcon(...)` so the
  /// secondary layer shows; a plain `Icon` draws the primary layer only.
  final IconData icon;
  final List<String> requiredPermissions;
}

/// A titled group of [NavItem]s — the unit the sidebar/drawer expands and
/// collapses ("Warehousing" → Warehouses + Warehouse Structure).
///
/// A [flat] group (Dashboard) has one item and renders as a plain row with
/// no expander. [shortLabel] is the tiny caption used under the icon in the
/// tablet rail and the phone bottom bar.
class NavGroup {
  const NavGroup({
    required this.id,
    required this.title,
    required this.shortLabel,
    required this.icon,
    required this.items,
    this.flat = false,
  });

  final String id;
  final String title;
  final String shortLabel;
  final IconData icon;
  final List<NavItem> items;
  final bool flat;
}

/// The nav table, grouped. Order here is display order in every layout.
/// Every permission key below is a real key from the warehouse's own catalog
/// (warehouse/src/permissions/constants/permission-catalog.ts).
const List<NavGroup> kNavGroups = [
  NavGroup(
    id: 'overview',
    title: 'Dashboard',
    shortLabel: 'Home',
    icon: PhosphorIconsDuotone.gauge,
    flat: true,
    items: [
      NavItem(
        label: 'Dashboard',
        path: RoutePaths.dashboard,
        icon: PhosphorIconsDuotone.gauge,
        requiredPermissions: ['reports.view'],
      ),
    ],
  ),
  NavGroup(
    id: 'catalogue',
    title: 'Catalogue',
    shortLabel: 'Catalogue',
    icon: PhosphorIconsDuotone.folders,
    items: [
      NavItem(
        label: 'Products',
        path: RoutePaths.products,
        icon: PhosphorIconsDuotone.package,
        requiredPermissions: ['catalogue.view'],
      ),
      NavItem(
        label: 'Workstreams',
        path: RoutePaths.workstreams,
        icon: PhosphorIconsDuotone.flowArrow,
        requiredPermissions: ['catalogue.view'],
      ),
      NavItem(
        label: 'Categories',
        path: RoutePaths.categories,
        icon: PhosphorIconsDuotone.squaresFour,
        requiredPermissions: ['catalogue.view'],
      ),
      NavItem(
        label: 'Attribute Types',
        path: RoutePaths.attributeTypes,
        icon: PhosphorIconsDuotone.tag,
        requiredPermissions: ['catalogue.view'],
      ),
    ],
  ),
  NavGroup(
    id: 'warehousing',
    title: 'Warehousing',
    shortLabel: 'Warehouse',
    icon: PhosphorIconsDuotone.warehouse,
    items: [
      NavItem(
        label: 'Warehouses',
        path: RoutePaths.warehouses,
        icon: PhosphorIconsDuotone.buildings,
        requiredPermissions: ['warehouse.structure.manage'],
      ),
      NavItem(
        label: 'Warehouse Structure',
        path: RoutePaths.locations,
        icon: PhosphorIconsDuotone.treeStructure,
        requiredPermissions: ['warehouse.structure.manage'],
      ),
    ],
  ),
  NavGroup(
    id: 'stock',
    title: 'Stock',
    shortLabel: 'Stock',
    icon: PhosphorIconsDuotone.stack,
    items: [
      NavItem(
        label: 'Inventory',
        path: RoutePaths.inventory,
        icon: PhosphorIconsDuotone.cube,
        requiredPermissions: ['inventory.view'],
      ),
      NavItem(
        label: 'Stock Receiving',
        path: RoutePaths.receiving,
        icon: PhosphorIconsDuotone.boxArrowDown,
        requiredPermissions: ['inventory.receive'],
      ),
      NavItem(
        label: 'Stock Transfers',
        path: RoutePaths.transfers,
        icon: PhosphorIconsDuotone.arrowsLeftRight,
        requiredPermissions: ['inventory.transfer'],
      ),
      NavItem(
        label: 'Stock Counts',
        path: RoutePaths.stockCounts,
        icon: PhosphorIconsDuotone.listChecks,
        requiredPermissions: ['inventory.count'],
      ),
      NavItem(
        label: 'Stock Adjustments',
        path: RoutePaths.stockAdjustments,
        icon: PhosphorIconsDuotone.slidersHorizontal,
        requiredPermissions: ['inventory.adjust.request', 'inventory.adjust.approve'],
      ),
      NavItem(
        label: 'Packing',
        path: RoutePaths.packing,
        icon: PhosphorIconsDuotone.package,
        requiredPermissions: ['packing.view'],
      ),
    ],
  ),
  NavGroup(
    id: 'user-management',
    title: 'User management',
    shortLabel: 'Users',
    icon: PhosphorIconsDuotone.usersThree,
    items: [
      NavItem(
        label: 'Users',
        path: RoutePaths.users,
        icon: PhosphorIconsDuotone.users,
        requiredPermissions: ['users.manage'],
      ),
      NavItem(
        label: 'Roles',
        path: RoutePaths.roles,
        icon: PhosphorIconsDuotone.lockKey,
        requiredPermissions: ['roles.manage'],
      ),
    ],
  ),
  NavGroup(
    id: 'system',
    title: 'System',
    shortLabel: 'System',
    icon: PhosphorIconsDuotone.gearSix,
    items: [
      NavItem(
        label: 'Audit Log',
        path: RoutePaths.audit,
        icon: PhosphorIconsDuotone.listMagnifyingGlass,
        requiredPermissions: ['audit.view'],
      ),
      NavItem(label: 'Settings', path: RoutePaths.settings, icon: PhosphorIconsDuotone.sliders),
    ],
  ),
];

/// Every destination, flattened in display order. The router builds its
/// routes from this and gates sub-routes with [navItemForPath].
final List<NavItem> kNavItems = [for (final group in kNavGroups) ...group.items];

bool _isVisible(NavItem item, AppUser? user) {
  if (item.requiredPermissions.isEmpty) return true;
  return user?.canAny(item.requiredPermissions) ?? false;
}

/// [kNavGroups] filtered to what [user] may see: hidden items are dropped
/// and a group left with no visible items disappears entirely. A `null`
/// user (signed out) sees only items with no required permission.
List<NavGroup> visibleNavGroups(AppUser? user) {
  final result = <NavGroup>[];
  for (final group in kNavGroups) {
    final items = group.items.where((item) => _isVisible(item, user)).toList();
    if (items.isEmpty) continue;
    result.add(NavGroup(
      id: group.id,
      title: group.title,
      shortLabel: group.shortLabel,
      icon: group.icon,
      items: items,
      flat: group.flat,
    ));
  }
  return result;
}

/// The visible destinations for [user], flattened in display order.
List<NavItem> visibleNavItems(AppUser? user) => [for (final group in visibleNavGroups(user)) ...group.items];

/// The item in [items] whose path matches [path] exactly, or is the longest
/// prefix match — so a sub-route like `/products/abc-123/edit` still
/// highlights the "Products" entry and inherits its permission gate.
NavItem? navItemMatching(Iterable<NavItem> items, String path) {
  NavItem? best;
  for (final item in items) {
    final matches = path == item.path || path.startsWith('${item.path}/');
    if (matches && (best == null || item.path.length > best.path.length)) best = item;
  }
  return best;
}

/// The nav item (from the full, unfiltered [kNavItems]) that governs [path]
/// — used by the router's redirect to gate sub-routes the same way as their
/// parent nav entry.
NavItem? navItemForPath(String path) => navItemMatching(kNavItems, path);

/// The group that owns [item] (by identity of its path), or null.
NavGroup? navGroupOf(Iterable<NavGroup> groups, NavItem? item) {
  if (item == null) return null;
  for (final group in groups) {
    if (group.items.any((candidate) => candidate.path == item.path)) return group;
  }
  return null;
}
