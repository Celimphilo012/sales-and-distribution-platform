import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:warehouse_frontend/core/error/app_error.dart';
import 'package:warehouse_frontend/core/theme/app_theme.dart';
import 'package:warehouse_frontend/core/ui/root_navigator_key.dart';
import 'package:warehouse_frontend/features/inventory/domain/inventory_transaction.dart';
import 'package:warehouse_frontend/features/locations/data/leaf_locations_provider.dart';
import 'package:warehouse_frontend/features/products/domain/product.dart';
import 'package:warehouse_frontend/features/products/presentation/products_list_providers.dart';
import 'package:warehouse_frontend/features/receiving/data/receiving_api.dart';
import 'package:warehouse_frontend/features/receiving/data/receiving_providers.dart';
import 'package:warehouse_frontend/features/receiving/presentation/scan_receive_sheet.dart';
import 'package:warehouse_frontend/shared/nx/nx_form.dart';
import 'package:warehouse_frontend/shared/nx/nx_overlays.dart';

Product _product(String id, String sku, String name, {String trackingMode = 'BULK'}) => Product.fromJson({
  'id': id,
  'sku': sku,
  'name': name,
  'categoryId': 'c1',
  'sellingPrice': 10,
  'uom': 'each',
  'status': 'ACTIVE',
  'trackingMode': trackingMode,
  'createdAt': '2026-09-30T08:00:00Z',
  'updatedAt': '2026-09-30T08:00:00Z',
});

class _FakeReceiving extends Fake implements ReceivingApi {
  final calls = <(String, double, String, String)>[];
  bool failShampoo = true;

  @override
  Future<InventoryTransaction> receive({
    required String supplier,
    required String productId,
    double? quantity,
    List<String>? unitCodes,
    required String toLocationId,
    String? reference,
    String? notes,
  }) async {
    if (productId == 'p2' && failShampoo) {
      failShampoo = false;
      throw const NetworkError('Connection lost');
    }
    final effectiveQty = quantity ?? unitCodes!.length.toDouble();
    calls.add((productId, effectiveQty, toLocationId, supplier));
    return InventoryTransaction.fromJson({
      'id': 't${calls.length}',
      'type': 'RECEIVE',
      'productId': productId,
      'toLocationId': toLocationId,
      'quantity': effectiveQty,
      'performedBy': 'u1',
      'createdAt': '2026-09-30T08:00:00Z',
    });
  }
}

void main() {
  testWidgets('each scan adds 1; Receive records one receipt per product and retries only what failed', (tester) async {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = _FakeReceiving();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          receivingApiProvider.overrideWithValue(api),
          productsListProvider.overrideWith((ref) async => [_product('p1', 'SOAP-1', 'Soap'), _product('p2', 'SHAM-2', 'Shampoo')]),
          leafLocationsProvider.overrideWith((ref) async => const <LeafLocation>[]),
        ],
        child: MaterialApp(
          navigatorKey: rootNavigatorKey,
          theme: AppTheme.dark(),
          builder: (context, child) => NxToastHost(child: child ?? const SizedBox.shrink()),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(onPressed: () => showScanReceiveSheet(context, locationId: 'l1'), child: const Text('open')),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Scan items'));
    await tester.pumpAndSettle();
    Future<void> scan(String code) async {
      await tester.enterText(find.byType(EditableText).last, code);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
    }

    await scan('WH:P:p1');
    await scan('WH:P:p1');
    expect(find.text('SOAP-1 · Soap — 2 each'), findsOneWidget);
    await scan('sham-2');
    await scan('WH:L:l1');
    expect(find.text('That is a location label — scan the products.'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(find.text('2 products · 3 units'), findsOneWidget);
    await tester.tap(find.text('Receive 3 units'));
    await tester.pumpAndSettle();
    // Supplier missing: nothing sent.
    expect(find.text('Supplier is required'), findsOneWidget);
    expect(api.calls, isEmpty);

    await tester.enterText(find.descendant(of: find.ancestor(of: find.text('Required'), matching: find.byType(NxInput)), matching: find.byType(EditableText)), 'Acme');
    await tester.tap(find.text('Receive 3 units'));
    await tester.pump(const Duration(milliseconds: 100));
    // Soap went through; Shampoo failed and stays to retry.
    expect(api.calls, [('p1', 2.0, 'l1', 'Acme')]);
    expect(find.text('Connection lost'), findsOneWidget);
    expect(find.text('SOAP-1 · received'), findsOneWidget);

    await tester.tap(find.text('Receive 1 units'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(api.calls, [('p1', 2.0, 'l1', 'Acme'), ('p2', 1.0, 'l1', 'Acme')]);
    await tester.pump(const Duration(seconds: 6)); // toast timer
    await tester.pumpAndSettle();
    expect(find.text('Scan items'), findsNothing); // sheet closed
  });

  testWidgets('a SERIAL product derives its quantity from distinct unit scans, never a typed number', (tester) async {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = _FakeReceiving()..failShampoo = false;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          receivingApiProvider.overrideWithValue(api),
          productsListProvider.overrideWith((ref) async => [_product('p3', 'SOAP-SER', 'Serial soap', trackingMode: 'SERIAL')]),
          leafLocationsProvider.overrideWith((ref) async => const <LeafLocation>[]),
        ],
        child: MaterialApp(
          navigatorKey: rootNavigatorKey,
          theme: AppTheme.dark(),
          builder: (context, child) => NxToastHost(child: child ?? const SizedBox.shrink()),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(onPressed: () => showScanReceiveSheet(context, locationId: 'l1'), child: const Text('open')),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Scan items'));
    await tester.pumpAndSettle();
    Future<void> scanInto(Finder dialogField, String code) async {
      await tester.enterText(dialogField, code);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
    }

    await scanInto(find.byType(EditableText).last, 'WH:P:p3');
    expect(find.textContaining('opened, use'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    // No manual quantity field for a SERIAL line — only a "Scan units" button.
    expect(find.text('0 scanned'), findsOneWidget);

    await tester.tap(find.text('0 scanned'));
    await tester.pumpAndSettle();
    await scanInto(find.byType(EditableText).last, 'WH:U:unit-a');
    await scanInto(find.byType(EditableText).last, 'WH:U:unit-a'); // duplicate within the same line
    expect(find.text('Already scanned on this line.'), findsOneWidget);
    await scanInto(find.byType(EditableText).last, 'WH:U:unit-b');
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(find.text('2 scanned'), findsOneWidget);

    await tester.enterText(find.descendant(of: find.ancestor(of: find.text('Required'), matching: find.byType(NxInput)), matching: find.byType(EditableText)), 'Acme');
    await tester.tap(find.text('Receive 2 units'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(api.calls, [('p3', 2.0, 'l1', 'Acme')]);
    await tester.pump(const Duration(seconds: 6)); // toast timer
    await tester.pumpAndSettle();
  });
}
