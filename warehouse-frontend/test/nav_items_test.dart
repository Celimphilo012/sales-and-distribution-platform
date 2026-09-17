import 'package:flutter_test/flutter_test.dart';

import 'package:warehouse_frontend/core/auth/app_user.dart';
import 'package:warehouse_frontend/routing/nav_items.dart';

void main() {
  test('signed-out user sees only permission-free nav items', () {
    final visible = visibleNavItems(null);
    expect(visible.map((i) => i.label), containsAll(['Dashboard', 'Settings']));
    expect(visible.every((i) => i.requiredPermissions.isEmpty), isTrue);
  });

  test('nav table never contains an ordering-side permission key', () {
    for (final item in kNavItems) {
      for (final permission in item.requiredPermissions) {
        expect(permission.startsWith('orders.'), isFalse, reason: '$permission is an ordering-side key');
        expect(permission.startsWith('customers.'), isFalse, reason: '$permission is an ordering-side key');
        expect(permission, isNot('reports.view'), reason: 'reports.view does not exist on the warehouse backend');
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

    expect(visible, {
      'Dashboard',
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
