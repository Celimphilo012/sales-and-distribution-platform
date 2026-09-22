import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:warehouse_frontend/app_shell/responsive_app_shell.dart';
import 'package:warehouse_frontend/core/auth/app_user.dart';
import 'package:warehouse_frontend/core/auth/auth_provider.dart';
import 'package:warehouse_frontend/core/auth/auth_state.dart';
import 'package:warehouse_frontend/core/persistence/shared_preferences_provider.dart';
import 'package:warehouse_frontend/core/theme/app_theme.dart';
import 'package:warehouse_frontend/routing/nav_items.dart';

const _admin = AppUser(
  id: '1',
  name: 'Warehouse Administrator',
  email: 'admin@example.com',
  roles: [AppUserRoleRef(id: 'r1', name: 'ADMIN')],
  permissions: {
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

class _FakeAdminNotifier extends AuthNotifier {
  @override
  Future<AuthState> build() async => const AuthState.authenticated(_admin);
}

/// Pumps the real shell (real nav table, real groups) inside a throwaway
/// router where every nav path renders a plain `page:<path>` marker.
Future<void> _pumpShell(WidgetTester tester, Size size, {ThemeData? theme}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();

  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final router = GoRouter(
    initialLocation: '/inventory',
    routes: [
      ShellRoute(
        builder: (context, state, child) => ResponsiveAppShell(currentPath: state.matchedLocation, child: child),
        routes: [
          for (final item in kNavItems)
            GoRoute(path: item.path, builder: (context, state) => Center(child: Text('page:${item.path}'))),
        ],
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        authProvider.overrideWith(_FakeAdminNotifier.new),
      ],
      child: MaterialApp.router(theme: theme ?? AppTheme.light(), routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('desktop (1280 wide)', () {
    testWidgets('shows the grouped sidebar; groups expand, collapse and navigate', (tester) async {
      await _pumpShell(tester, const Size(1280, 800));

      expect(find.text('SIGNED IN AS'), findsOneWidget);
      // The current route's group (Stock) is open on arrival…
      expect(find.text('Stock Receiving'), findsOneWidget);
      // …while other groups are collapsed until tapped.
      expect(find.text('Warehouse Structure'), findsNothing);

      await tester.tap(find.text('Warehousing'));
      await tester.pumpAndSettle();
      expect(find.text('Warehouses'), findsOneWidget);
      expect(find.text('Warehouse Structure'), findsOneWidget);

      await tester.tap(find.text('Warehouse Structure'));
      await tester.pumpAndSettle();
      expect(find.text('page:/locations'), findsWidgets);

      // Collapsing a group hides its items again.
      await tester.tap(find.text('Warehousing'));
      await tester.pumpAndSettle();
      expect(find.text('Warehouses'), findsNothing);
    });

    testWidgets('renders in the dark theme without layout errors', (tester) async {
      await _pumpShell(tester, const Size(1280, 800), theme: AppTheme.dark());
      expect(find.text('Warehouse System'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });

  group('tablet (820 wide)', () {
    testWidgets('shows a rail with one entry per group; multi-item groups open a menu', (tester) async {
      await _pumpShell(tester, const Size(820, 900));

      expect(find.text('SIGNED IN AS'), findsNothing); // no sidebar
      expect(find.text('Stock'), findsOneWidget); // rail caption for the Stock group
      expect(find.text('Stock Receiving'), findsNothing); // items live in the menu/drawer

      await tester.tap(find.text('Warehouse')); // rail caption for "Warehousing"
      await tester.pumpAndSettle();
      expect(find.text('Warehouse Structure'), findsOneWidget);

      await tester.tap(find.text('Warehouse Structure'));
      await tester.pumpAndSettle();
      expect(find.text('page:/locations'), findsWidgets);
    });

    testWidgets('the menu button opens the full grouped drawer', (tester) async {
      await _pumpShell(tester, const Size(820, 900));

      await tester.tap(find.byTooltip('Menu'));
      await tester.pumpAndSettle();
      expect(find.text('User management'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('phone (390 wide)', () {
    testWidgets('bottom bar shortcuts + a Menu button that opens the grouped drawer', (tester) async {
      await _pumpShell(tester, const Size(390, 800));

      for (final label in ['Home', 'Products', 'Inventory', 'Receive', 'Menu']) {
        expect(find.text(label), findsWidgets, reason: 'bottom bar entry $label');
      }

      await tester.tap(find.text('Menu'));
      await tester.pumpAndSettle();
      expect(find.text('Warehousing'), findsOneWidget);
      expect(find.text('User management'), findsOneWidget);

      await tester.tap(find.text('Warehousing'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Warehouses'));
      await tester.pumpAndSettle();
      expect(find.text('page:/warehouses'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });
}
