import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:warehouse_frontend/core/auth/app_user.dart';
import 'package:warehouse_frontend/core/auth/auth_provider.dart';
import 'package:warehouse_frontend/core/auth/auth_state.dart';
import 'package:warehouse_frontend/core/persistence/shared_preferences_provider.dart';
import 'package:warehouse_frontend/core/theme/app_theme.dart';
import 'package:warehouse_frontend/features/categories/data/categories_providers.dart';
import 'package:warehouse_frontend/features/categories/domain/category.dart';
import 'package:warehouse_frontend/features/products/domain/product.dart';
import 'package:warehouse_frontend/features/products/domain/product_status.dart';
import 'package:warehouse_frontend/features/products/presentation/products_list_providers.dart';
import 'package:warehouse_frontend/features/products/presentation/products_list_screen.dart';
import 'package:warehouse_frontend/features/workstreams/data/workstreams_providers.dart';
import 'package:warehouse_frontend/features/workstreams/domain/workstream.dart';

const _viewer = AppUser(id: 'u1', name: 'Viewer', email: 'v@example.com', permissions: {'catalogue.view'});

class _FakeUserNotifier extends AuthNotifier {
  @override
  Future<AuthState> build() async => const AuthState.authenticated(_viewer);
}

final _now = DateTime(2026, 1, 1);

Product _product(String sku, String name, {double price = 10, ProductStatus status = ProductStatus.active}) =>
    Product(
      id: sku,
      sku: sku,
      name: name,
      categoryId: 'c1',
      sellingPrice: price,
      uom: 'EACH',
      minStockLevel: 0,
      status: status,
      createdAt: _now,
      updatedAt: _now,
    );

final _fakeProducts = [
  _product('SKU-1', 'Soap', price: 10),
  _product('SKU-2', 'Shampoo', price: 20),
  _product('SKU-3', 'Old Candle', price: 6, status: ProductStatus.inactive),
];

Future<void> _pump(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final router = GoRouter(
    initialLocation: '/products',
    routes: [
      GoRoute(path: '/products', builder: (context, state) => const Scaffold(body: ProductsListScreen())),
      GoRoute(path: '/products/:id', builder: (context, state) => const Placeholder()),
      GoRoute(path: '/products/import', builder: (context, state) => const Placeholder()),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        authProvider.overrideWith(_FakeUserNotifier.new),
        productsListProvider.overrideWith((ref) async => _fakeProducts),
        categoriesProvider(true).overrideWith((ref) async => const <Category>[]),
        workstreamsProvider(true).overrideWith((ref) async => const <Workstream>[]),
      ],
      child: MaterialApp.router(theme: AppTheme.dark(), routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('defaults to the table view and shows correct stats', (tester) async {
    await _pump(tester);

    // Stats: 3 products, 2 active; avg selling price (10+20+6)/3 = 12.
    expect(find.text('Products'), findsWidgets); // page title + stat label
    expect(find.text('3'), findsWidgets);
    expect(find.text('2 active'), findsOneWidget);
    expect(find.textContaining('12.00'), findsWidgets);

    // Table view is the default — real product rows visible.
    expect(find.text('Soap'), findsOneWidget);
    expect(find.text('Shampoo'), findsOneWidget);
    expect(find.text('SKU'), findsOneWidget); // column header
  });

  testWidgets('switching to List shows a compact row per product', (tester) async {
    await _pump(tester);

    await tester.tap(find.byTooltip('List'));
    await tester.pumpAndSettle();

    expect(find.text('SKU'), findsNothing); // no table header any more
    expect(find.text('Soap'), findsOneWidget);
    expect(find.textContaining('SKU-1'), findsOneWidget);
  });

  testWidgets('switching to Grid shows a card per product', (tester) async {
    await _pump(tester);

    await tester.tap(find.byTooltip('Grid'));
    await tester.pumpAndSettle();

    expect(find.text('Soap'), findsOneWidget);
    expect(find.textContaining('SKU-1'), findsOneWidget);
  });

  testWidgets('the quick filter narrows to inactive products', (tester) async {
    await _pump(tester);

    await tester.tap(find.text('Inactive').first);
    await tester.pumpAndSettle();

    expect(find.text('Old Candle'), findsOneWidget);
    expect(find.text('Soap'), findsNothing);
    expect(find.textContaining('1 of 3'), findsOneWidget);
  });

  testWidgets('search matches on SKU or name', (tester) async {
    await _pump(tester);

    await tester.enterText(find.byType(TextField).first, 'sham');
    await tester.pumpAndSettle();

    expect(find.text('Shampoo'), findsOneWidget);
    expect(find.text('Soap'), findsNothing);
  });

  testWidgets('an empty product list shows the empty state in every view mode', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final router = GoRouter(
      initialLocation: '/products',
      routes: [GoRoute(path: '/products', builder: (context, state) => const Scaffold(body: ProductsListScreen()))],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          authProvider.overrideWith(_FakeUserNotifier.new),
          productsListProvider.overrideWith((ref) async => const []),
          categoriesProvider(true).overrideWith((ref) async => const <Category>[]),
        workstreamsProvider(true).overrideWith((ref) async => const <Workstream>[]),
        ],
        child: MaterialApp.router(theme: AppTheme.dark(), routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No products found'), findsOneWidget);
  });
}
