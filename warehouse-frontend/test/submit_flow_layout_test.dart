import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:warehouse_frontend/core/auth/app_user.dart';
import 'package:warehouse_frontend/core/auth/auth_provider.dart';
import 'package:warehouse_frontend/core/auth/auth_state.dart';
import 'package:warehouse_frontend/core/persistence/shared_preferences_provider.dart';
import 'package:warehouse_frontend/core/theme/app_theme.dart';
import 'package:warehouse_frontend/features/locations/data/leaf_locations_provider.dart';
import 'package:warehouse_frontend/features/stock_counts/data/stock_counts_api.dart';
import 'package:warehouse_frontend/features/stock_counts/data/stock_counts_providers.dart';
import 'package:warehouse_frontend/features/stock_counts/domain/stock_count.dart';
import 'package:warehouse_frontend/features/stock_counts/presentation/count_sheet.dart';
import 'package:warehouse_frontend/shared/nx/nx_overlays.dart';

class _Counter extends AuthNotifier {
  @override
  Future<AuthState> build() async =>
      const AuthState.authenticated(AppUser(id: 'u1', name: 'Counter', email: 'c@example.com', permissions: {'inventory.count', 'inventory.view'}));
}

Map<String, dynamic> _countJson({required bool submitted}) => {
  'id': 'count-1',
  'warehouseId': 'w1',
  'locationId': 'l1',
  'status': submitted ? 'SUBMITTED' : 'OPEN',
  'startedBy': 'u1',
  'startedAt': DateTime(2026, 9, 30, 9).toIso8601String(),
  'submittedAt': submitted ? DateTime(2026, 9, 30, 10).toIso8601String() : null,
  'location': {'id': 'l1', 'name': 'Level 03 of rack 02 in aisle A — the long one near the dock', 'code': 'A-02-03-LONG', 'warehouseId': 'w1'},
  'startedByUser': {'id': 'u1', 'fullName': 'Counter With A Rather Long Name', 'email': 'c@example.com'},
  'items': [
    for (final (i, name) in ['Soap', 'Shampoo 500ml with a very long product name that keeps going', 'Candle'].indexed)
      {
        'id': 'it$i',
        'stockCountId': 'count-1',
        'productId': 'p$i',
        'locationId': 'l1',
        'expectedQty': '12',
        'countedQty': submitted ? '${10 + i}' : null,
        'difference': submitted ? '${i - 2}' : null,
        'product': {'id': 'p$i', 'sku': 'SKU-$i', 'name': name},
      },
  ],
};

class _FakeCounts extends Fake implements StockCountsApi {
  @override
  Future<StockCount> submit(String id, {required List<SubmitCountItem> items}) async => StockCount.fromJson(_countJson(submitted: true));
}

void main() {
  for (final (name, size) in [('desktop', const Size(1280, 900)), ('tablet', const Size(820, 1000)), ('phone', const Size(360, 780))]) {
    testWidgets('submitting a count lays out cleanly on a $name (sheet, busy state, toast)', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            authProvider.overrideWith(_Counter.new),
            stockCountsApiProvider.overrideWithValue(_FakeCounts()),
            stockCountProvider('count-1').overrideWith((ref) async => StockCount.fromJson(_countJson(submitted: false))),
            stockCountsListProvider.overrideWith((ref, status) async => const <StockCount>[]),
            leafLocationsProvider.overrideWith((ref) async => const <LeafLocation>[]),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            builder: (context, child) => NxToastHost(child: child ?? const SizedBox.shrink()),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(onPressed: () => showCountSheet(context, 'count-1'), child: const Text('open')),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'the open sheet');

      final inputs = find.byType(EditableText);
      for (var i = 0; i < 3; i++) {
        await tester.enterText(inputs.at(i), '${10 + i}');
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'the filled sheet');

      await tester.tap(find.text('Submit count'));
      await tester.pump(); // busy state
      expect(tester.takeException(), isNull, reason: 'while submitting');
      // Not pumpAndSettle: that would wait out the toast's whole 5-second life.
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(tester.takeException(), isNull, reason: 'after submitting (toast)');
      expect(find.text('Stock count submitted'), findsOneWidget);
      await tester.pump(const Duration(seconds: 6)); // let the toast expire
    });
  }
}
