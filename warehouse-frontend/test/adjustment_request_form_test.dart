import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:warehouse_frontend/core/auth/app_user.dart';
import 'package:warehouse_frontend/core/auth/auth_provider.dart';
import 'package:warehouse_frontend/core/auth/auth_state.dart';
import 'package:warehouse_frontend/core/persistence/shared_preferences_provider.dart';
import 'package:warehouse_frontend/core/theme/app_theme.dart';
import 'package:warehouse_frontend/features/inventory/data/inventory_providers.dart';
import 'package:warehouse_frontend/features/inventory/domain/inventory_balance.dart';
import 'package:warehouse_frontend/features/inventory/domain/product_location_stock.dart';
import 'package:warehouse_frontend/features/locations/domain/location.dart';
import 'package:warehouse_frontend/features/products/domain/product.dart';
import 'package:warehouse_frontend/features/products/domain/product_status.dart';
import 'package:warehouse_frontend/features/stock_adjustments/presentation/widgets/adjustment_request_form.dart';

final _now = DateTime(2026, 1, 1);

Location _location(String id, String name, String code) => Location(
  id: id,
  warehouseId: 'w1',
  name: name,
  code: code,
  locationType: 'LEVEL',
  isActive: true,
  createdAt: _now,
  updatedAt: _now,
);

Product _product(String id, String sku, String name) => Product(
  id: id,
  sku: sku,
  name: name,
  categoryId: 'c1',
  sellingPrice: 10,
  uom: 'pcs',
  minStockLevel: 0,
  status: ProductStatus.active,
  createdAt: _now,
  updatedAt: _now,
);

InventoryBalance _balance(Location location, String productId, String sku, String name, {double onHand = 40}) =>
    InventoryBalance(
      id: 'b-$productId-${location.id}',
      productId: productId,
      locationId: location.id,
      onHand: onHand,
      reserved: 0,
      damaged: 0,
      lost: 0,
      expired: 0,
      available: onHand,
      product: InventoryBalanceProductRef(id: productId, sku: sku, name: name, uom: 'pcs'),
      location: InventoryBalanceLocationRef(id: location.id, name: location.name, code: location.code, warehouseId: 'w1'),
    );

ProductLocationStock _stock(Location location, InventoryBalance balance) =>
    ProductLocationStock(balance: balance, warehouseName: 'Main', path: [location]);

const _user = AppUser(id: 'u1', name: 'Stub', email: 'stub@example.com', permissions: {'inventory.adjust.request'});

class _FakeUserNotifier extends AuthNotifier {
  @override
  Future<AuthState> build() async => const AuthState.authenticated(_user);
}

final _levelA = _location('l1', 'Level A', 'L1');
final _levelB = _location('l2', 'Level B', 'L2');
final _soap = _product('p1', 'SOP-1', 'Soap');

Future<void> _pumpForm(WidgetTester tester, {required List<ProductLocationStock> stock}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  tester.view.physicalSize = const Size(1000, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        authProvider.overrideWith(_FakeUserNotifier.new),
        productSearchResultsProvider('soap').overrideWith((ref) async => [_soap]),
        productStockBreakdownProvider('p1').overrideWith((ref) async => stock),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: SingleChildScrollView(child: AdjustmentRequestForm(onSubmitted: () {}))),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _searchAndPickSoap(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField).first, 'soap');
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Soap'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('exactly one stocked location auto-fills the Location field', (tester) async {
    final balance = _balance(_levelA, 'p1', 'SOP-1', 'Soap', onHand: 40);
    await _pumpForm(tester, stock: [_stock(_levelA, balance)]);

    await _searchAndPickSoap(tester);

    expect(find.text('Level A (L1)'), findsOneWidget);
    expect(find.textContaining('Detected automatically'), findsOneWidget);
  });

  testWidgets('several stocked locations are offered as a chooser, not guessed', (tester) async {
    await _pumpForm(
      tester,
      stock: [
        _stock(_levelA, _balance(_levelA, 'p1', 'SOP-1', 'Soap', onHand: 40)),
        _stock(_levelB, _balance(_levelB, 'p1', 'SOP-1', 'Soap', onHand: 5)),
      ],
    );

    await _searchAndPickSoap(tester);

    expect(find.text('Soap is stored in 2 locations'), findsOneWidget);
    expect(find.text('Choose which location to adjust:'), findsOneWidget);
    expect(find.textContaining('Detected automatically'), findsNothing);
    expect(find.text('Not selected'), findsOneWidget); // Location field still unset

    await tester.tap(find.textContaining('Main › Level B'));
    await tester.pumpAndSettle();

    expect(find.text('Level B (L2)'), findsOneWidget);
    expect(find.text('Soap is stored in 2 locations'), findsNothing);
  });

  testWidgets('a product with no stock anywhere falls back to a plain manual picker — not an error', (tester) async {
    await _pumpForm(tester, stock: const []);

    await _searchAndPickSoap(tester);

    expect(find.text('Not selected'), findsOneWidget);
    expect(find.textContaining('Detected automatically'), findsNothing);
    expect(find.textContaining('is stored in'), findsNothing);
    expect(find.text('Choose a location.'), findsNothing); // no proactive error before submit is attempted
  });

  testWidgets('picking a different product resets a previous manual location pick', (tester) async {
    await _pumpForm(tester, stock: [_stock(_levelA, _balance(_levelA, 'p1', 'SOP-1', 'Soap', onHand: 40))]);

    await _searchAndPickSoap(tester);
    expect(find.text('Level A (L1)'), findsOneWidget); // auto-detected

    // Change the product via the picker's "Change" action (the Product
    // field's own — the Location field also shows a "Change" button once
    // auto-filled, hence `.first`: Product renders above Location).
    await tester.tap(find.text('Change').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'soap');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Soap'));
    await tester.pumpAndSettle();

    // Re-detected fresh, not left over from before.
    expect(find.text('Level A (L1)'), findsOneWidget);
    expect(find.textContaining('Detected automatically'), findsOneWidget);
  });
}
