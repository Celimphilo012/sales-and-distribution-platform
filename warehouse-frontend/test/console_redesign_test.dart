import 'dart:typed_data';

import 'package:excel/excel.dart' as xl;
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
import 'package:warehouse_frontend/features/locations/data/leaf_locations_provider.dart';
import 'package:warehouse_frontend/features/locations/domain/location.dart';
import 'package:warehouse_frontend/features/products/domain/product.dart';
import 'package:warehouse_frontend/features/products/domain/product_status.dart';
import 'package:warehouse_frontend/features/products/presentation/products_list_providers.dart';
import 'package:warehouse_frontend/features/stock_adjustments/presentation/adjustment_form_dialog.dart';
import 'package:warehouse_frontend/features/stock_counts/presentation/count_sheet.dart';
import 'package:warehouse_frontend/features/warehouses/domain/warehouse.dart';
import 'package:warehouse_frontend/shared/export/report_export.dart';
import 'package:warehouse_frontend/shared/nx/nx_form.dart';

const _staff = AppUser(id: 'u1', name: 'Staff', email: 's@example.com', permissions: {'inventory.adjust.request'});

class _FakeUser extends AuthNotifier {
  @override
  Future<AuthState> build() async => const AuthState.authenticated(_staff);
}

final _now = DateTime(2026, 9, 30);

Product _p(String sku, String name) => Product(
  id: sku,
  sku: sku,
  name: name,
  categoryId: 'c1',
  sellingPrice: 10,
  uom: 'each',
  minStockLevel: 0,
  status: ProductStatus.active,
  createdAt: _now,
  updatedAt: _now,
);

LeafLocation _leaf(String id, String code, List<String> path) => LeafLocation(
  location: Location(
    id: id,
    warehouseId: 'w1',
    name: path.last,
    code: code,
    locationType: 'BIN',
    isActive: true,
    createdAt: _now,
    updatedAt: _now,
  ),
  warehouse: const Warehouse(id: 'w1', name: 'Main', code: 'WH-1', isActive: true),
  path: path,
);

Future<SharedPreferences> _prefs() async {
  SharedPreferences.setMockInitialValues({});
  return SharedPreferences.getInstance();
}

Future<void> _pumpApp(WidgetTester tester, Widget home, {List overrides = const []}) async {
  final prefs = await _prefs();
  tester.view.physicalSize = const Size(1280, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        authProvider.overrideWith(_FakeUser.new),
        ...overrides.cast(),
      ],
      child: MaterialApp(theme: AppTheme.dark(), home: Scaffold(body: home)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('searchable pickers', () {
    testWidgets('typing in a searchable select narrows the options', (tester) async {
      String? picked;
      await _pumpApp(
        tester,
        StatefulBuilder(
          builder: (context, setState) => Padding(
            padding: const EdgeInsets.all(20),
            child: SizedBox(
              width: 360,
              child: NxSelect<String>(
                searchable: true,
                placeholder: 'Choose a product',
                options: const [
                  NxOption('p1', 'SKU-1 — Soap'),
                  NxOption('p2', 'SKU-2 — Shampoo'),
                  NxOption('p3', 'SKU-3 — Candle', search: 'wax'),
                ],
                value: picked,
                onChanged: (v) => setState(() => picked = v),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Choose a product'));
      await tester.pumpAndSettle();
      expect(find.text('SKU-2 — Shampoo'), findsOneWidget);

      await tester.enterText(find.byType(TextField).last, 'wax'); // matches the extra search text
      await tester.pumpAndSettle();
      expect(find.text('SKU-3 — Candle'), findsOneWidget);
      expect(find.text('SKU-1 — Soap'), findsNothing);

      await tester.tap(find.text('SKU-3 — Candle'));
      await tester.pumpAndSettle();
      expect(picked, 'p3');
    });
  });

  group('adjustment request', () {
    testWidgets('has searchable product and location pickers and an optional photo', (tester) async {
      await _pumpApp(
        tester,
        Builder(builder: (context) => TextButton(onPressed: () => showAdjustmentForm(context), child: const Text('open'))),
        overrides: [
          productsListProvider.overrideWith((ref) async => [_p('SKU-1', 'Soap'), _p('SKU-2', 'Shampoo')]),
          leafLocationsProvider.overrideWith((ref) async => [_leaf('l1', 'A-01', ['Aisle A', 'Bin 01'])]),
          allBalancesProvider.overrideWith((ref) async => const <InventoryBalance>[]),
        ],
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Request adjustment'), findsOneWidget);
      expect(find.text('Add a photo'), findsOneWidget); // the evidence photo the old screen had
      expect(find.text('Photo (optional)'), findsOneWidget);

      // Nothing chosen yet → the request is refused with field errors, not sent.
      await tester.tap(find.text('Send for approval'));
      await tester.pumpAndSettle();
      expect(find.text('Choose a product'), findsWidgets);
      expect(find.text('Say what happened, and how you know'), findsOneWidget);
    });
  });

  group('report exports', () {
    const rep = ReportData(
      title: 'Low stock',
      description: 'Active products below minimum',
      columns: [
        ReportColumn('SKU'),
        ReportColumn('Product', ColType.text, 28),
        ReportColumn('On hand', ColType.num),
        ReportColumn('Shortfall', ColType.num),
      ],
      rows: [
        ['SKU-1', 'Soap › bar', 2, 8],
        ['SKU-2', 'Shampoo — 500ml', 1, 4],
      ],
      totalsFrom: 3,
    );
    const branding = ExportBranding(company: 'Acme Distribution', subtitle: 'Main (WH-1) · Generated today by Staff');

    test('totals sum the numeric columns from totalsFrom', () {
      expect(rep.totals, ['Total', '', '', 12.0]);
    });

    test('the PDF is a real PDF (and survives typographic characters)', () async {
      final bytes = await reportPdf(rep, branding);
      expect(String.fromCharCodes(bytes.sublist(0, 5)), '%PDF-');
      expect(bytes.length, greaterThan(1000));
    });

    test('the Excel file has the header, the rows and a totals row', () {
      final Uint8List bytes = reportXlsx(rep, branding);
      final book = xl.Excel.decodeBytes(bytes);
      final sheet = book['Low stock'];
      String? cell(int c, int r) => sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r)).value?.toString();
      expect(cell(0, 0), 'Acme Distribution');
      expect(cell(0, 3), 'Low stock');
      expect(cell(1, 5), 'Product');
      expect(cell(1, 6), 'Soap › bar');
      expect(cell(0, 8), 'Total');
      expect(num.parse(cell(3, 8)!), 12);
    });

    test('a pick list PDF renders', () async {
      final bytes = await pickListPdf([
        const PickOrder(title: 'ORD-0012 · Customer', subtitle: '2 of 3 items', lines: [('3 each', 'Soap', 'SKU-1', 'A-01 — Bin 01, Main')]),
      ], branding);
      expect(String.fromCharCodes(bytes.sublist(0, 5)), '%PDF-');
    });
  });

  group('count drafts', () {
    test('typed counts are kept on the device until the count is submitted', () async {
      final prefs = await _prefs();
      final c1 = ProviderContainer(overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
      c1.read(countDraftsProvider.notifier).set('count-1', 'p1', '7');
      c1.dispose();

      // A fresh app (same device) still has it.
      final c2 = ProviderContainer(overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
      expect(c2.read(countDraftsProvider)['count-1'], {'p1': '7'});
      c2.read(countDraftsProvider.notifier).clear('count-1');
      expect(c2.read(countDraftsProvider)['count-1'], isNull);
      c2.dispose();
    });
  });
}
