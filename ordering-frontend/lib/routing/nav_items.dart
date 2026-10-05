import 'package:flutter/widgets.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../core/auth/app_user.dart';
import 'route_paths.dart';

/// A single navigation destination (one routed screen).
///
/// [requiredPermissions] is an "any of" list: an empty list means the item
/// is always visible (Dashboard, Settings); otherwise the signed-in user must
/// hold at least one of those keys — the ORDERING backend's own permission
/// catalog (`ordering-backend/src/catalog/permission-catalog.js`), never a
/// role name (rule 1) and never a warehouse-side key.
class NavItem {
  const NavItem({required this.label, required this.path, required this.icon, this.requiredPermissions = const []});

  final String label;
  final String path;

  /// A Phosphor duotone glyph (render with `PhosphorIcon` for both layers).
  final IconData icon;
  final List<String> requiredPermissions;
}

/// A titled group of [NavItem]s the sidebar/drawer expands and collapses. A
/// [flat] group (Dashboard) is one plain row. [shortLabel] captions the icon
/// in the tablet rail and phone bottom bar.
class NavGroup {
  const NavGroup({required this.id, required this.title, required this.shortLabel, required this.icon, required this.items, this.flat = false});

  final String id;
  final String title;
  final String shortLabel;
  final IconData icon;
  final List<NavItem> items;
  final bool flat;
}

/// The nav table, grouped. Order here is display order in every layout.
/// Pick / pack / dispatch are actions on an order, not a section.
const List<NavGroup> kNavGroups = [
  NavGroup(
    id: 'overview',
    title: 'Dashboard',
    shortLabel: 'Home',
    icon: PhosphorIconsDuotone.gauge,
    flat: true,
    items: [NavItem(label: 'Dashboard', path: RoutePaths.dashboard, icon: PhosphorIconsDuotone.gauge)],
  ),
  NavGroup(
    id: 'sales',
    title: 'Sales',
    shortLabel: 'Sales',
    icon: PhosphorIconsDuotone.shoppingCart,
    items: [
      NavItem(
        label: 'Orders',
        path: RoutePaths.orders,
        icon: PhosphorIconsDuotone.receipt,
        requiredPermissions: ['orders.view_team', 'orders.view_own'],
      ),
      NavItem(
        label: 'Customers',
        path: RoutePaths.customers,
        icon: PhosphorIconsDuotone.addressBook,
        requiredPermissions: ['customers.view', 'customers.create'],
      ),
      NavItem(label: 'Payments', path: RoutePaths.payments, icon: PhosphorIconsDuotone.wallet, requiredPermissions: ['reports.view']),
      NavItem(label: 'Finances', path: RoutePaths.finances, icon: PhosphorIconsDuotone.chartLineUp, requiredPermissions: ['finances.view']),
    ],
  ),
  NavGroup(
    id: 'user-management',
    title: 'User management',
    shortLabel: 'Users',
    icon: PhosphorIconsDuotone.usersThree,
    items: [
      NavItem(label: 'Users', path: RoutePaths.users, icon: PhosphorIconsDuotone.users, requiredPermissions: ['users.manage']),
      NavItem(label: 'Roles', path: RoutePaths.roles, icon: PhosphorIconsDuotone.lockKey, requiredPermissions: ['roles.manage']),
    ],
  ),
  NavGroup(
    id: 'system',
    title: 'System',
    shortLabel: 'System',
    icon: PhosphorIconsDuotone.gearSix,
    items: [
      NavItem(
        label: 'Sale Campaigns',
        path: RoutePaths.saleCampaigns,
        icon: PhosphorIconsDuotone.tag,
        requiredPermissions: ['sales.view', 'sales.eligibility.manage'],
      ),
      NavItem(label: 'Reports', path: RoutePaths.reports, icon: PhosphorIconsDuotone.chartBar, requiredPermissions: ['reports.view']),
      NavItem(label: 'Audit Log', path: RoutePaths.audit, icon: PhosphorIconsDuotone.listMagnifyingGlass, requiredPermissions: ['audit.view']),
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

/// [kNavGroups] filtered to what [user] may see; a group left empty disappears.
List<NavGroup> visibleNavGroups(AppUser? user) => [
  for (final g in kNavGroups)
    if (g.items.where((i) => _isVisible(i, user)).toList() case final items when items.isNotEmpty)
      NavGroup(id: g.id, title: g.title, shortLabel: g.shortLabel, icon: g.icon, items: items, flat: g.flat),
];

/// The visible destinations for [user], flattened in display order.
List<NavItem> visibleNavItems(AppUser? user) => [for (final group in visibleNavGroups(user)) ...group.items];

/// The item whose path matches [path] exactly or is its longest prefix — so
/// `/orders/abc/edit` still highlights "Orders" and inherits its gate.
NavItem? navItemMatching(Iterable<NavItem> items, String path) {
  NavItem? best;
  for (final item in items) {
    final matches = path == item.path || path.startsWith('${item.path}/');
    if (matches && (best == null || item.path.length > best.path.length)) best = item;
  }
  return best;
}

/// The nav item (from the full [kNavItems]) that governs [path] — the router's gate.
NavItem? navItemForPath(String path) => navItemMatching(kNavItems, path);
