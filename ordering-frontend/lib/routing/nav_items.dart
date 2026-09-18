import 'package:flutter/material.dart';

import '../core/auth/app_user.dart';
import 'route_paths.dart';

/// A single top-level navigation destination.
///
/// [requiredPermissions] is an "any of" list: an empty list means the item
/// is always visible (e.g. Dashboard, Settings); a non-empty list means the
/// signed-in user must hold at least one of those permission strings —
/// mirroring the ORDERING backend's permission catalog
/// (`backend/src/permissions/constants/permission-catalog.ts`), never a role
/// name (rule 1). This app is a standalone client of `/backend` only; it
/// never sees warehouse-side permissions like `catalogue.view`/
/// `inventory.*`/`warehouse.structure.*` — those don't exist on this system
/// (step R1 removed products/categories/warehouses/inventory, which used
/// them, along with the permission strings themselves).
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
/// from the ordering backend's own catalog — there is no `fulfilment.*` item
/// here either; pick/pack/dispatch are actions on an individual order (R2+),
/// not a separate top-level section.
const List<NavItem> kNavItems = [
  NavItem(
    label: 'Dashboard',
    path: RoutePaths.dashboard,
    icon: Icons.dashboard_outlined,
    selectedIcon: Icons.dashboard,
  ),
  NavItem(
    label: 'Customers',
    path: RoutePaths.customers,
    icon: Icons.people_alt_outlined,
    selectedIcon: Icons.people_alt,
    requiredPermissions: ['customers.view', 'customers.create'],
  ),
  NavItem(
    label: 'Orders',
    path: RoutePaths.orders,
    icon: Icons.receipt_long_outlined,
    selectedIcon: Icons.receipt_long,
    requiredPermissions: ['orders.view_team', 'orders.view_own'],
  ),
  NavItem(
    label: 'Reports',
    path: RoutePaths.reports,
    icon: Icons.bar_chart_outlined,
    selectedIcon: Icons.bar_chart,
    requiredPermissions: ['reports.view'],
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
/// prefix match — so a sub-route like `/roles/abc-123` still highlights the
/// "Roles" entry and inherits its permission gate.
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
