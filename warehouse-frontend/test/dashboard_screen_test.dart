import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:warehouse_frontend/core/auth/app_user.dart';
import 'package:warehouse_frontend/core/auth/auth_provider.dart';
import 'package:warehouse_frontend/core/auth/auth_state.dart';
import 'package:warehouse_frontend/core/persistence/shared_preferences_provider.dart';
import 'package:warehouse_frontend/core/theme/app_theme.dart';
import 'package:warehouse_frontend/features/dashboard/data/dashboard_providers.dart';
import 'package:warehouse_frontend/features/dashboard/domain/dashboard_summary.dart';
import 'package:warehouse_frontend/features/dashboard/presentation/dashboard_screen.dart';

class _FakeUserNotifier extends AuthNotifier {
  _FakeUserNotifier(this.user);

  final AppUser user;

  @override
  Future<AuthState> build() async => AuthState.authenticated(user);
}

const _manager = AppUser(id: 'u2', name: 'Manager', email: 'm@example.com', permissions: {'reports.view'});

final _now = DateTime(2026, 1, 1, 12, 0);

final _fakeSummary = DashboardSummary(
  catalogue: const CatalogueSummary(
    activeProductCount: 25,
    activeCategoryCount: 12,
    activeWorkstreamCount: 2,
    activeWarehouseCount: 1,
  ),
  lowStock: const LowStockSummary(
    count: 2,
    items: [
      LowStockItem(productId: 'p1', sku: 'SOP-1', name: 'Soap', onHand: 0, minStockLevel: 10, shortfall: 10),
      LowStockItem(productId: 'p2', sku: 'SHM-1', name: 'Shampoo', onHand: 2, minStockLevel: 5, shortfall: 3),
    ],
  ),
  pendingAdjustments: PendingAdjustmentsSummary(
    count: 1,
    items: [
      PendingAdjustmentItem(
        id: 'a1',
        productId: 'p1',
        productSku: 'SOP-1',
        productName: 'Soap',
        locationName: 'Bin A',
        locationCode: 'BINA',
        bucket: 'ON_HAND',
        delta: 5,
        direction: 'DECREASE',
        reason: 'damaged carton',
        requestedBy: const AdjustmentUserRef(id: 'u9', fullName: 'Warehouse Staff'),
        requestedAt: _now,
        waitingDays: 4,
      ),
    ],
  ),
  valuation: const ValuationSummary(
    total: 31514,
    excludedProductCount: 9,
    topProducts: [
      ValuationProduct(productId: 'p3', sku: 'TOT-1', name: 'Tote Bag', onHand: 967, costPrice: 32, value: 30944),
    ],
  ),
  stockMovement: StockMovementSummary(
    periodDays: 7,
    byType: const {'RECEIVE': 12, 'ISSUE': 8, 'TRANSFER': 0},
    recentActivity: [
      StockMovementActivity(
        id: 't1',
        type: 'RECEIVE',
        productSku: 'TOT-1',
        productName: 'Tote Bag',
        quantity: 967,
        fromLocationLabel: null,
        toLocationLabel: 'Bin B01 (BB01)',
        performedByName: 'Warehouse Administrator',
        createdAt: _now,
      ),
    ],
  ),
  openStockCounts: const OpenStockCountsSummary(count: 0),
);

Future<void> _pump(WidgetTester tester, AppUser user) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  tester.view.physicalSize = const Size(1200, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        authProvider.overrideWith(() => _FakeUserNotifier(user)),
        dashboardSummaryProvider.overrideWith((ref) async => _fakeSummary),
      ],
      child: MaterialApp(theme: AppTheme.light(), home: const Scaffold(body: DashboardScreen())),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  // Who may open the dashboard is the router's job (reports.view on the nav item).

  testWidgets('a reports.view user sees real KPI tiles and preview panels', (tester) async {
    await _pump(tester, _manager);

    expect(find.text('25'), findsOneWidget); // active products
    expect(find.textContaining('31,514'), findsOneWidget); // valuation total
    expect(find.textContaining('without cost excluded'), findsOneWidget);

    // Low stock panel.
    expect(find.text('Soap'), findsWidgets); // in both low-stock and pending panels
    expect(find.text('Shampoo'), findsOneWidget);

    // Pending adjustments panel.
    expect(find.textContaining('damaged carton'), findsOneWidget);

    // Recent activity.
    expect(find.textContaining('Tote Bag'), findsWidgets);
    expect(find.textContaining('Warehouse Administrator'), findsOneWidget);
  });

  testWidgets('an empty low-stock/adjustments state renders a plain message, not an empty list', (tester) async {
    final emptySummary = DashboardSummary(
      catalogue: _fakeSummary.catalogue,
      lowStock: const LowStockSummary(count: 0, items: []),
      pendingAdjustments: const PendingAdjustmentsSummary(count: 0, items: []),
      valuation: _fakeSummary.valuation,
      stockMovement: StockMovementSummary(periodDays: 7, byType: const {}, recentActivity: const []),
      openStockCounts: const OpenStockCountsSummary(count: 0),
    );

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    tester.view.physicalSize = const Size(1200, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          authProvider.overrideWith(() => _FakeUserNotifier(_manager)),
          dashboardSummaryProvider.overrideWith((ref) async => emptySummary),
        ],
        child: MaterialApp(theme: AppTheme.light(), home: const Scaffold(body: DashboardScreen())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Every active product is at or above its minimum.'), findsOneWidget);
    expect(find.text('Nothing waiting for review.'), findsOneWidget);
    expect(find.text('No stock moved in this period.'), findsOneWidget);
    expect(find.text('No stock has moved yet.'), findsOneWidget);
  });
}
