import 'package:flutter_test/flutter_test.dart';

import 'package:ordering_frontend/core/auth/app_user.dart';
import 'package:ordering_frontend/routing/nav_items.dart';

void main() {
  test('signed-out user sees only permission-free nav items', () {
    final visible = visibleNavItems(null);
    expect(visible.map((i) => i.label), containsAll(['Dashboard', 'Settings']));
    expect(visible.every((i) => i.requiredPermissions.isEmpty), isTrue);
  });

  test('nav table never contains a warehouse-side permission key', () {
    const warehouseKeys = {'catalogue.view', 'products.manage', 'inventory.view', 'warehouse.structure.manage'};
    for (final item in kNavItems) {
      for (final key in item.requiredPermissions) {
        expect(warehouseKeys.contains(key), isFalse, reason: '${item.label} references warehouse key $key');
        expect(key.startsWith('inventory.'), isFalse);
        expect(key.startsWith('warehouse.'), isFalse);
      }
    }
  });

  test('CONSULTANT-role permission set (real backend role) sees exactly its ordering sections', () {
    // Mirrors backend/src/permissions/constants/permission-catalog.ts's
    // ROLE_PERMISSION_MAP.CONSULTANT exactly.
    final user = AppUser(
      id: '1',
      name: 'Consultant',
      email: 'consultant@example.com',
      permissions: const {
        'customers.create',
        'customers.view',
        'orders.create',
        'orders.edit_own_draft',
        'orders.submit',
        'orders.view_own',
      },
    );

    final visible = visibleNavItems(user).map((i) => i.label).toSet();

    expect(visible, {'Dashboard', 'Customers', 'Orders', 'Settings'});
    expect(visible.contains('Reports'), isFalse);
    expect(visible.contains('Users'), isFalse);
    expect(visible.contains('Roles'), isFalse);
    expect(visible.contains('Audit Log'), isFalse);
  });

  test('ADMIN-equivalent permission set (every catalog key) sees every nav item', () {
    // Mirrors ROLE_PERMISSION_MAP.ADMIN (every PERMISSION_CATALOG key).
    final user = AppUser(
      id: '1',
      name: 'Admin',
      email: 'admin@example.com',
      permissions: const {
        'customers.create',
        'customers.view',
        'orders.create',
        'orders.edit_own_draft',
        'orders.submit',
        'orders.approve',
        'orders.reject',
        'orders.view_team',
        'orders.view_own',
        'fulfilment.pick',
        'fulfilment.pack',
        'fulfilment.dispatch',
        'users.manage',
        'roles.manage',
        'audit.view',
        'reports.view',
      },
    );

    final visible = visibleNavItems(user).map((i) => i.label).toSet();
    expect(visible, kNavItems.map((i) => i.label).toSet());
  });
}
