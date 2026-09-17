import 'package:flutter/material.dart';

import '../core/auth/app_user.dart';
import 'route_paths.dart';

/// A single top-level navigation destination.
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
    required this.selectedIcon,
    this.requiredPermissions = const [],
  });

  final String label;
  final String path;
  final IconData icon;
  final IconData selectedIcon;
  final List<String> requiredPermissions;
}

/// The full nav table. Order here determines display order in every layout
/// (sidebar, rail, and bottom nav). Every key below is a real permission
/// from the warehouse's own catalog (warehouse/src/permissions/constants/
/// permission-catalog.ts) — there is no `reports.view` key on this system,
/// so there is no Reports item.
const List<NavItem> kNavItems = [
  NavItem(
    label: 'Dashboard',
    path: RoutePaths.dashboard,
    icon: Icons.dashboard_outlined,
    selectedIcon: Icons.dashboard,
  ),
  NavItem(
    label: 'Products',
    path: RoutePaths.products,
    icon: Icons.inventory_2_outlined,
    selectedIcon: Icons.inventory_2,
    requiredPermissions: ['catalogue.view'],
  ),
  NavItem(
    label: 'Workstreams',
    path: RoutePaths.workstreams,
    icon: Icons.workspaces_outlined,
    selectedIcon: Icons.workspaces,
    requiredPermissions: ['catalogue.view'],
  ),
  NavItem(
    label: 'Categories',
    path: RoutePaths.categories,
    icon: Icons.category_outlined,
    selectedIcon: Icons.category,
    requiredPermissions: ['catalogue.view'],
  ),
  NavItem(
    label: 'Attribute Types',
    path: RoutePaths.attributeTypes,
    icon: Icons.label_outline,
    selectedIcon: Icons.label,
    requiredPermissions: ['catalogue.view'],
  ),
  NavItem(
    label: 'Warehouses',
    path: RoutePaths.warehouses,
    icon: Icons.warehouse_outlined,
    selectedIcon: Icons.warehouse,
    requiredPermissions: ['warehouse.structure.manage'],
  ),
  NavItem(
    label: 'Warehouse Structure',
    path: RoutePaths.locations,
    icon: Icons.account_tree_outlined,
    selectedIcon: Icons.account_tree,
    requiredPermissions: ['warehouse.structure.manage'],
  ),
  NavItem(
    label: 'Inventory',
    path: RoutePaths.inventory,
    icon: Icons.inventory_outlined,
    selectedIcon: Icons.inventory,
    requiredPermissions: ['inventory.view'],
  ),
  NavItem(
    label: 'Stock Receiving',
    path: RoutePaths.receiving,
    icon: Icons.move_to_inbox_outlined,
    selectedIcon: Icons.move_to_inbox,
    requiredPermissions: ['inventory.receive'],
  ),
  NavItem(
    label: 'Stock Transfers',
    path: RoutePaths.transfers,
    icon: Icons.swap_horiz_outlined,
    selectedIcon: Icons.swap_horiz,
    requiredPermissions: ['inventory.transfer'],
  ),
  NavItem(
    label: 'Stock Counts',
    path: RoutePaths.stockCounts,
    icon: Icons.checklist_outlined,
    selectedIcon: Icons.checklist,
    requiredPermissions: ['inventory.count'],
  ),
  NavItem(
    label: 'Stock Adjustments',
    path: RoutePaths.stockAdjustments,
    icon: Icons.tune_outlined,
    selectedIcon: Icons.tune,
    requiredPermissions: ['inventory.adjust.request', 'inventory.adjust.approve'],
  ),
  NavItem(
    label: 'Users',
    path: RoutePaths.users,
    icon: Icons.people_outline,
    selectedIcon: Icons.people,
    requiredPermissions: ['users.manage'],
  ),
  NavItem(
    label: 'Roles',
    path: RoutePaths.roles,
    icon: Icons.admin_panel_settings_outlined,
    selectedIcon: Icons.admin_panel_settings,
    requiredPermissions: ['roles.manage'],
  ),
  NavItem(
    label: 'Audit Log',
    path: RoutePaths.audit,
    icon: Icons.history_outlined,
    selectedIcon: Icons.history,
    requiredPermissions: ['audit.view'],
  ),
  NavItem(
    label: 'Settings',
    path: RoutePaths.settings,
    icon: Icons.settings_outlined,
    selectedIcon: Icons.settings,
  ),
];

/// Filters [kNavItems] down to what [user] is permitted to see. A `null`
/// user (signed out) sees only items with no required permission.
List<NavItem> visibleNavItems(AppUser? user) {
  return kNavItems.where((item) {
    if (item.requiredPermissions.isEmpty) return true;
    return user?.canAny(item.requiredPermissions) ?? false;
  }).toList();
}

/// Index into [items] whose path matches [path] exactly, or is the longest
/// prefix match — so a sub-route like `/products/abc-123/edit` still
/// highlights the "Products" entry and inherits its permission gate.
int navIndexForPath(List<NavItem> items, String path) {
  var bestIndex = -1;
  var bestLength = -1;
  for (var i = 0; i < items.length; i++) {
    final itemPath = items[i].path;
    final matches = path == itemPath || path.startsWith('$itemPath/');
    if (matches && itemPath.length > bestLength) {
      bestIndex = i;
      bestLength = itemPath.length;
    }
  }
  return bestIndex;
}

/// The nav item (from the full, unfiltered [kNavItems]) that governs [path]
/// — used by the router's redirect to gate sub-routes the same way as their
/// parent nav entry.
NavItem? navItemForPath(String path) {
  final index = navIndexForPath(kNavItems, path);
  return index == -1 ? null : kNavItems[index];
}
