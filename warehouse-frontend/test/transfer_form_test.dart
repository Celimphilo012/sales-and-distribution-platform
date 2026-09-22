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
import 'package:warehouse_frontend/features/transfers/presentation/transfer_form_screen.dart';
import 'package:warehouse_frontend/features/transfers/presentation/widgets/transfer_product_field.dart';

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

InventoryBalance _balance(
  Location location,
  String productId,
  String sku,
  String name, {
  double onHand = 40,
  double reserved = 0,
}) => InventoryBalance(
  id: 'b-$productId-${location.id}',
  productId: productId,
  locationId: location.id,
  onHand: onHand,
  reserved: reserved,
  damaged: 0,
  lost: 0,
  expired: 0,
  available: onHand - reserved,
  product: InventoryBalanceProductRef(id: productId, sku: sku, name: name, uom: 'pcs'),
  location: InventoryBalanceLocationRef(id: location.id, name: location.name, code: location.code, warehouseId: 'w1'),
);

ProductLocationStock _stock(Location location, InventoryBalance balance) =>
    ProductLocationStock(balance: balance, warehouseName: 'Main', path: [location]);

const _transferUser = AppUser(
  id: 'u1',
  name: 'Stub',
  email: 'stub@example.com',
  permissions: {'inventory.transfer'},
);

class _FakeUserNotifier extends AuthNotifier {
  @override
  Future<AuthState> build() async => const AuthState.authenticated(_transferUser);
}

final _levelA = _location('l1', 'Level A', 'L1');
final _levelB = _location('l2', 'Level B', 'L2');
final _shampoo = _product('p1', 'SHP-1', 'Shampoo');

Future<void> _pumpScreen(WidgetTester tester, {required List<ProductLocationStock> stock}) async {
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
        productSearchResultsProvider('sham').overrideWith((ref) async => [_shampoo]),
        productStockBreakdownProvider('p1').overrideWith((ref) async => stock),
        locationBalancesProvider('l1').overrideWith(
          (ref) async => [_balance(_levelA, 'p1', 'SHP-1', 'Shampoo', onHand: 40, reserved: 10)],
        ),
        locationBalancesProvider('l2').overrideWith(
          (ref) async => [_balance(_levelB, 'p1', 'SHP-1', 'Shampoo', onHand: 5)],
        ),
      ],
      child: MaterialApp(theme: AppTheme.light(), home: const Scaffold(body: TransferFormScreen())),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _searchAndPickShampoo(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField).first, 'sham');
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Shampoo'));
  await tester.pumpAndSettle();
}

void main() {
  group('product first → From is detected', () {
    testWidgets('exactly one stocked location fills From automatically, with an available hint', (tester) async {
      final balance = _balance(_levelA, 'p1', 'SHP-1', 'Shampoo', onHand: 40, reserved: 10);
      await _pumpScreen(tester, stock: [_stock(_levelA, balance)]);

      await _searchAndPickShampoo(tester);

      expect(find.text('Level A (L1)'), findsOneWidget); // the From field
      expect(find.textContaining('Detected automatically'), findsOneWidget);
      expect(find.text('Available here: 30 pcs'), findsOneWidget); // 40 on hand − 10 reserved
    });

    testWidgets('several stocked locations are offered to choose from', (tester) async {
      await _pumpScreen(
        tester,
        stock: [
          _stock(_levelA, _balance(_levelA, 'p1', 'SHP-1', 'Shampoo', onHand: 40, reserved: 10)),
          _stock(_levelB, _balance(_levelB, 'p1', 'SHP-1', 'Shampoo', onHand: 5)),
        ],
      );

      await _searchAndPickShampoo(tester);

      expect(find.text('Shampoo is stored in 2 locations'), findsOneWidget);
      expect(find.textContaining('Detected automatically'), findsNothing);
      expect(find.text('Not selected'), findsWidgets); // From still unset

      await tester.tap(find.textContaining('Main › Level B'));
      await tester.pumpAndSettle();

      expect(find.text('Level B (L2)'), findsOneWidget);
      expect(find.text('Available here: 5 pcs'), findsOneWidget);
      expect(find.text('Shampoo is stored in 2 locations'), findsNothing);
    });

    testWidgets('a product with no stock anywhere says so', (tester) async {
      await _pumpScreen(tester, stock: const []);

      await _searchAndPickShampoo(tester);

      expect(find.textContaining('No stock of this item on hand in any location'), findsOneWidget);
    });
  });

  group('From first → the product field lists that location\'s items', () {
    Future<void> pumpList(WidgetTester tester, ValueChanged<InventoryBalanceProductRef> onSelected) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            locationBalancesProvider('l1').overrideWith(
              (ref) async => [
                _balance(_levelA, 'p2', 'CRM-1', 'Face Cream'),
                _balance(_levelA, 'p1', 'SHP-1', 'Shampoo', onHand: 40, reserved: 10),
                _balance(_levelA, 'p3', 'SOP-1', 'Soap', onHand: 8, reserved: 8),
                _balance(_levelA, 'p4', 'OLD-1', 'Empty Item', onHand: 0),
              ],
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              body: SingleChildScrollView(
                child: LocationItemsList(location: _levelA, onSelected: onSelected),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('lists every item with stock (alphabetically), shows availability, hides empty ones', (tester) async {
      await pumpList(tester, (_) {});

      expect(find.text('3 items in this location'), findsOneWidget);
      expect(find.text('Empty Item'), findsNothing); // on hand 0 → nothing to move
      expect(find.text('SHP-1 · 30 pcs available (10 reserved)'), findsOneWidget);
      expect(find.text('SOP-1 · all 8 pcs reserved'), findsOneWidget);

      final names = ['Face Cream', 'Shampoo', 'Soap'];
      final tops = [for (final n in names) tester.getTopLeft(find.text(n)).dy];
      expect(tops, [...tops]..sort(), reason: 'items should be alphabetical');
    });

    testWidgets('the search box filters by name or SKU', (tester) async {
      await pumpList(tester, (_) {});

      await tester.enterText(find.byType(TextField), 'sham');
      await tester.pumpAndSettle();
      expect(find.text('1 of 3 items match'), findsOneWidget);
      expect(find.text('Shampoo'), findsOneWidget);
      expect(find.text('Face Cream'), findsNothing);

      await tester.enterText(find.byType(TextField), 'crm-1'); // by SKU
      await tester.pumpAndSettle();
      expect(find.text('Face Cream'), findsOneWidget);
      expect(find.text('Shampoo'), findsNothing);

      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pumpAndSettle();
      expect(find.text('No matching items in this location'), findsOneWidget);
    });

    testWidgets('tapping an item selects it; a fully-reserved item cannot be picked', (tester) async {
      InventoryBalanceProductRef? picked;
      await pumpList(tester, (p) => picked = p);

      await tester.tap(find.text('Soap'));
      await tester.pumpAndSettle();
      expect(picked, isNull);

      await tester.tap(find.text('Shampoo'));
      await tester.pumpAndSettle();
      expect(picked?.id, 'p1');
      expect(picked?.uom, 'pcs');
    });
  });
}
