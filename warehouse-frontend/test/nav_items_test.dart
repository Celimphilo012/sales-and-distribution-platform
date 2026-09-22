import 'package:flutter_test/flutter_test.dart';

import 'package:warehouse_frontend/core/auth/app_user.dart';
import 'package:warehouse_frontend/routing/nav_items.dart';

void main() {
  groupingTests();
  test('signed-out user sees only permission-free nav items', () {
    final visible = visibleNavItems(null);
    // Settings is the only nav item with no permission requirement — Dashboard
    // now requires `reports.view` (added alongside the reports/dashboard
    // feature), so a signed-out/no-permission user no longer sees it.
    expect(visible.map((i) => i.label).toList(), ['Settings']);
    expect(visible.every((i) => i.requiredPermissions.isEmpty), isTrue);
  });

  test('nav table never contains an ordering-side permission key', () {
    for (final item in kNavItems) {
      for (final permission in item.requiredPermissions) {
        expect(permission.startsWith('orders.'), isFalse, reason: '$permission is an ordering-side key');
        expect(permission.startsWith('customers.'), isFalse, reason: '$permission is an ordering-side key');
      }
    }
    expect(kNavItems.map((i) => i.label), isNot(contains('Orders')));
    expect(kNavItems.map((i) => i.label), isNot(contains('Fulfilment')));
  });

  test('WAREHOUSE-role permission set sees exactly its warehouse sections', () {
    final user = AppUser(
      id: '1',
      name: 'Stub Warehouse Staff',
      email: 'stub@example.com',
      permissions: const {
        'catalogue.view',
        'inventory.view',
        'inventory.receive',
        'inventory.transfer',
        'inventory.count',
        'inventory.adjust.request',
      },
    );

    final visible = visibleNavItems(user).map((i) => i.label).toSet();

    // No `reports.view` in this permission set — WAREHOUSE doesn't hold it
    // (see permission-catalog.ts), so no Dashboard either.
    expect(visible, {
      'Products',
      'Workstreams',
      'Categories',
      'Attribute Types',
      'Inventory',
      'Stock Receiving',
      'Stock Transfers',
      'Stock Counts',
      'Stock Adjustments',
      'Settings',
    });
    expect(visible.contains('Dashboard'), isFalse);
    expect(visible.contains('Warehouses'), isFalse);
    expect(visible.contains('Warehouse Structure'), isFalse);
    expect(visible.contains('Users'), isFalse);
    expect(visible.contains('Roles'), isFalse);
    expect(visible.contains('Audit Log'), isFalse);
  });

  test('ADMIN-equivalent permission set (every catalog key) sees every nav item', () {
    final user = AppUser(
      id: '2',
      name: 'Stub Admin',
      email: 'admin@example.com',
      permissions: const {
        'users.manage',
        'roles.manage',
        'audit.view',
        'reports.view',
        'catalogue.view',
        'products.manage',
        'warehouse.structure.manage',
        'inventory.view',
        'inventory.receive',
        'inventory.transfer',
        'inventory.count',
        'inventory.adjust.request',
        'inventory.adjust.approve',
      },
    );

    final visible = visibleNavItems(user).map((i) => i.label).toSet();
    expect(visible, kNavItems.map((i) => i.label).toSet());
  });
}

void groupingTests() {
  AppUser userWith(Set<String> permissions) =>
      AppUser(id: 'g', name: 'Stub', email: 'stub@example.com', permissions: permissions);

  test('Warehouses + Warehouse Structure are grouped under "Warehousing"', () {
    final groups = visibleNavGroups(userWith(const {'warehouse.structure.manage'}));
    final warehousing = groups.firstWhere((g) => g.id == 'warehousing');
    expect(warehousing.items.map((i) => i.label), ['Warehouses', 'Warehouse Structure']);
  });

  test('Users + Roles are grouped under "User management"', () {
    final groups = visibleNavGroups(userWith(const {'users.manage', 'roles.manage'}));
    final group = groups.firstWhere((g) => g.title == 'User management');
    expect(group.items.map((i) => i.label), ['Users', 'Roles']);
  });

  test('the five stock screens are grouped under "Stock"', () {
    final groups = visibleNavGroups(userWith(const {
      'inventory.view',
      'inventory.receive',
      'inventory.transfer',
      'inventory.count',
      'inventory.adjust.approve',
    }));
    final stock = groups.firstWhere((g) => g.title == 'Stock');
    expect(stock.items.length, 5);
  });

  test('a group with no visible items disappears entirely', () {
    final groups = visibleNavGroups(userWith(const {'inventory.view'}));
    final ids = groups.map((g) => g.id).toSet();
    expect(ids, containsAll(['stock', 'system']));
    // 'overview' (Dashboard) now requires `reports.view`, which this user
    // doesn't have — it disappears too, same as any other empty group.
    expect(ids, isNot(contains('overview')));
    expect(ids, isNot(contains('warehousing')));
    expect(ids, isNot(contains('user-management')));
    expect(ids, isNot(contains('catalogue')));
  });

  test('every item belongs to exactly one group and paths are unique', () {
    final paths = kNavItems.map((i) => i.path).toList();
    expect(paths.toSet().length, paths.length);
    for (final item in kNavItems) {
      expect(kNavGroups.where((g) => g.items.contains(item)).length, 1);
    }
  });
}
