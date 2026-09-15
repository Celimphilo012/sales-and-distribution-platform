import 'package:flutter_test/flutter_test.dart';

import 'package:distribution_platform/core/auth/app_user.dart';
import 'package:distribution_platform/routing/nav_items.dart';

void main() {
  test('signed-out user sees only permission-free nav items', () {
    final visible = visibleNavItems(null);
    expect(visible.map((i) => i.label), containsAll(['Dashboard', 'Settings']));
    expect(visible.every((i) => i.requiredPermissions.isEmpty), isTrue);
  });

  test('stub manager permission set hides warehouses/fulfilment/users/roles', () {
    final user = AppUser(
      id: '1',
      name: 'Stub',
      email: 'stub@example.com',
      permissions: const {
        'catalogue.view',
        'orders.view_team',
        'inventory.view',
        'reports.view',
        'audit.view',
      },
    );

    final visible = visibleNavItems(user).map((i) => i.label).toSet();

    expect(visible, {'Dashboard', 'Products', 'Categories', 'Inventory', 'Orders', 'Reports', 'Audit Log', 'Settings'});
    expect(visible.contains('Warehouses'), isFalse);
    expect(visible.contains('Fulfilment'), isFalse);
    expect(visible.contains('Users'), isFalse);
    expect(visible.contains('Roles'), isFalse);
  });
}
