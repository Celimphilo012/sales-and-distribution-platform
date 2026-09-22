import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ordering_frontend/core/auth/app_user.dart';
import 'package:ordering_frontend/core/auth/auth_provider.dart';
import 'package:ordering_frontend/core/auth/auth_state.dart';
import 'package:ordering_frontend/core/error/app_error.dart';
import 'package:ordering_frontend/core/theme/app_theme.dart';
import 'package:ordering_frontend/features/orders/data/orders_api.dart';
import 'package:ordering_frontend/features/orders/data/orders_providers.dart';
import 'package:ordering_frontend/features/orders/domain/order.dart';
import 'package:ordering_frontend/features/orders/domain/order_lifecycle.dart';
import 'package:ordering_frontend/features/orders/presentation/widgets/dispatch_order_dialog.dart';
import 'package:ordering_frontend/features/orders/presentation/widgets/order_actions_card.dart';
import 'package:ordering_frontend/features/orders/presentation/widgets/quantity_entry_dialog.dart';
import 'package:ordering_frontend/features/orders/presentation/widgets/reserve_stock_dialog.dart';
import 'package:ordering_frontend/features/warehouse_locations/data/warehouse_locations_providers.dart';
import 'package:ordering_frontend/features/warehouse_locations/domain/warehouse_locations.dart';

final _now = DateTime(2026, 1, 1);
const _pShampoo = '11111111-1111-4111-8111-111111111111';
const _pSoap = '33333333-3333-4333-8333-333333333333';
const _locA = '22222222-2222-4222-8222-222222222222';
const _locB = '44444444-4444-4444-8444-444444444444';

OrderItem _item(
  String id,
  String productId,
  String name, {
  double ordered = 10,
  double picked = 0,
  double packed = 0,
  double fulfilled = 0,
}) => OrderItem(
  id: id,
  orderId: 'o1',
  productId: productId,
  productName: name,
  quantityOrdered: ordered,
  quantityFulfilled: fulfilled,
  quantityPicked: picked,
  quantityPacked: packed,
  unitPrice: 5,
  lineTotal: ordered * 5,
);

Order _order(OrderStatus status, List<OrderItem> items) => Order(
  id: 'o1',
  orderNumber: 'ORD-TEST',
  customerId: 'c1',
  status: status,
  paymentStatus: PaymentStatus.unpaid,
  orderDate: _now,
  total: 100,
  createdAt: _now,
  updatedAt: _now,
  customer: const OrderCustomerRef(id: 'c1', name: 'Test Customer'),
  items: items,
);

/// Records every lifecycle call and can be told to fail the next one.
class _FakeOrdersApi extends Fake implements OrdersApi {
  final calls = <String>[];
  Map<String, double>? lastQuantities;
  Map<String, String>? lastAllocations;
  Object? failWith;
  Order? dispatchResult;

  void _maybeFail() {
    final error = failWith;
    if (error != null) {
      failWith = null; // fail once, so "Retry" can succeed
      throw error;
    }
  }

  @override
  Future<Order> pick(String id, {required Map<String, double> pickedQty}) async {
    calls.add('pick');
    lastQuantities = pickedQty;
    _maybeFail();
    return _order(OrderStatus.picking, const []);
  }

  @override
  Future<Order> pack(String id, {required Map<String, double> packedQty}) async {
    calls.add('pack');
    lastQuantities = packedQty;
    _maybeFail();
    return _order(OrderStatus.packed, const []);
  }

  @override
  Future<Order> reserve(String id, {required Map<String, String> allocations}) async {
    calls.add('reserve');
    lastAllocations = allocations;
    _maybeFail();
    return _order(OrderStatus.stockReserved, const []);
  }

  @override
  Future<Order> transition(String id, OrderAction action, {String? note}) async {
    calls.add(action.name);
    _maybeFail();
    return dispatchResult ?? _order(OrderStatus.dispatched, const []);
  }
}

class _FakeUser extends AuthNotifier {
  _FakeUser(this.permissions);

  final Set<String> permissions;

  @override
  Future<AuthState> build() async => AuthState.authenticated(
    AppUser(id: 'u1', name: 'Tester', email: 't@example.com', permissions: permissions),
  );
}

final _locations = WarehouseLocations(
  warehouses: const [WarehouseRef(id: 'w1', name: 'Main WH', code: 'MW', isActive: true)],
  locations: const [
    WarehouseLocation(id: _locA, warehouseId: 'w1', parentId: null, name: 'Shelf A', code: 'A', locationType: 'SHELF', isActive: true),
    WarehouseLocation(id: _locB, warehouseId: 'w1', parentId: null, name: 'Shelf B', code: 'B', locationType: 'SHELF', isActive: true),
  ],
);

/// Hosts the widget under test (built by [launcher]) under the real theme,
/// with the fake API and a signed-in user holding [permissions].
Future<void> _pump(
  WidgetTester tester, {
  required _FakeOrdersApi api,
  required Widget Function(BuildContext context, void Function(Object?) setResult) launcher,
  Set<String> permissions = const {},
  Brightness brightness = Brightness.light,
}) async {
  tester.view.physicalSize = const Size(900, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ordersApiProvider.overrideWithValue(api),
        warehouseLocationsProvider.overrideWith((ref) async => _locations),
        authProvider.overrideWith(() => _FakeUser(permissions)),
      ],
      child: MaterialApp(
        theme: brightness == Brightness.dark ? AppTheme.dark() : AppTheme.light(),
        home: Scaffold(
          body: Builder(builder: (context) => launcher(context, (_) {})),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('pick / pack quantity entry', () {
    final order = _order(OrderStatus.stockReserved, [
      _item('i1', _pShampoo, 'Shampoo', ordered: 10),
      _item('i2', _pSoap, 'Soap', ordered: 4),
    ]);

    Future<void> open(WidgetTester tester, _FakeOrdersApi api, Order o, QuantityStep step) async {
      await _pump(
        tester,
        api: api,
        launcher: (context, _) => Center(
          child: TextButton(
            onPressed: () => showQuantityEntryDialog(context, order: o, step: step),
            child: const Text('open'),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('pick defaults each line to the ordered quantity', (tester) async {
      await open(tester, _FakeOrdersApi(), order, QuantityStep.pick);
      final fields = tester.widgetList<TextFormField>(find.byType(TextFormField)).toList();
      expect(fields.map((f) => f.controller!.text), ['10', '4']);
    });

    testWidgets('picking more than ordered is refused and never reaches the API', (tester) async {
      final api = _FakeOrdersApi();
      await open(tester, api, order, QuantityStep.pick);

      await tester.enterText(find.byType(TextFormField).first, '11');
      await tester.tap(find.text('Save picking'));
      await tester.pumpAndSettle();

      expect(find.text('Cannot exceed 10'), findsOneWidget);
      expect(api.calls, isEmpty);
    });

    testWidgets('a short pick is sent as entered, per line', (tester) async {
      final api = _FakeOrdersApi();
      await open(tester, api, order, QuantityStep.pick);

      await tester.enterText(find.byType(TextFormField).first, '7.5');
      await tester.pumpAndSettle();
      expect(find.text('Short pick — 2.5 below ordered'), findsOneWidget);

      await tester.tap(find.text('Save picking'));
      await tester.pumpAndSettle();

      expect(api.calls, ['pick']);
      expect(api.lastQuantities, {'i1': 7.5, 'i2': 4.0});
    });

    testWidgets('typing in one field survives edits to another (controllers live in parent state)', (tester) async {
      await open(tester, _FakeOrdersApi(), order, QuantityStep.pick);

      await tester.enterText(find.byType(TextFormField).at(0), '6');
      await tester.enterText(find.byType(TextFormField).at(1), '2');
      await tester.enterText(find.byType(TextFormField).at(1), '3');
      await tester.pumpAndSettle();

      final fields = tester.widgetList<TextFormField>(find.byType(TextFormField)).toList();
      expect(fields.map((f) => f.controller!.text), ['6', '3']);
    });

    testWidgets('pack defaults to the PICKED quantity and cannot exceed it', (tester) async {
      final picked = _order(OrderStatus.picking, [
        _item('i1', _pShampoo, 'Shampoo', ordered: 10, picked: 8),
        _item('i2', _pSoap, 'Soap', ordered: 4, picked: 4),
      ]);
      final api = _FakeOrdersApi();
      await open(tester, api, picked, QuantityStep.pack);

      final fields = tester.widgetList<TextFormField>(find.byType(TextFormField)).toList();
      expect(fields.map((f) => f.controller!.text), ['8', '4']);

      await tester.enterText(find.byType(TextFormField).first, '9');
      await tester.tap(find.text('Save packing'));
      await tester.pumpAndSettle();
      expect(find.text('Cannot exceed 8'), findsOneWidget);
      expect(api.calls, isEmpty);
    });
  });

  group('reserve — the three outcomes', () {
    final order = _order(OrderStatus.approved, [_item('i1', _pShampoo, 'Shampoo', ordered: 12)]);

    Future<void> open(WidgetTester tester, _FakeOrdersApi api, {void Function(bool)? onResult}) async {
      await _pump(
        tester,
        api: api,
        launcher: (context, _) => Center(
          child: TextButton(
            onPressed: () async {
              // Evaluate the dialog FIRST: `onResult?.call(await x)` would skip x when onResult is null.
              final r = await showReserveStockDialog(context, order: order);
              onResult?.call(r);
            },
            child: const Text('open'),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    Future<void> chooseLocation(WidgetTester tester, String label) async {
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
    }

    testWidgets('reserve is disabled until every line has a location', (tester) async {
      await open(tester, _FakeOrdersApi());
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Reserve stock')).onPressed, isNull);

      await chooseLocation(tester, 'Shelf A (A)');
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Reserve stock')).onPressed, isNotNull);
    });

    testWidgets('SUCCESS sends the chosen location per line and closes with true', (tester) async {
      final api = _FakeOrdersApi();
      bool? result;
      await open(tester, api, onResult: (r) => result = r);

      await chooseLocation(tester, 'Shelf B (B)');
      await tester.tap(find.widgetWithText(FilledButton, 'Reserve stock'));
      await tester.pumpAndSettle();

      expect(api.calls, ['reserve']);
      expect(api.lastAllocations, {'i1': _locB});
      expect(result, isTrue);
      expect(find.byType(ReserveStockDialog), findsNothing); // dialog closed
    });

    testWidgets('INSUFFICIENT STOCK shows which line is short and by how much, and stays open', (tester) async {
      final api = _FakeOrdersApi()
        ..failWith = const ConflictError(
          'Cannot reserve — insufficient available stock for: product $_pShampoo at location $_locA: need 12, only 4 available',
        );
      bool? result;
      await open(tester, api, onResult: (r) => result = r);

      await chooseLocation(tester, 'Shelf A (A)');
      await tester.tap(find.widgetWithText(FilledButton, 'Reserve stock'));
      await tester.pumpAndSettle();

      expect(find.text('Not enough stock — nothing was reserved'), findsOneWidget);
      expect(find.text('Shampoo'), findsWidgets); // product NAME, not the id
      expect(find.text('Main WH › Shelf A'), findsWidgets); // location PATH, not the id
      expect(find.text('Requested: 12'), findsOneWidget);
      expect(find.text('Available: 4'), findsOneWidget);
      expect(find.text('Short by: 8'), findsOneWidget);
      expect(find.textContaining('The order stays Approved'), findsOneWidget);
      expect(find.textContaining('product $_pShampoo'), findsNothing); // never the raw message
      expect(result, isNull); // dialog still open — order did not advance
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('WAREHOUSE UNAVAILABLE shows a calm safe-to-retry note; Retry then succeeds', (tester) async {
      final api = _FakeOrdersApi()..failWith = const ServiceUnavailableError('Warehouse API is unreachable');
      bool? result;
      await open(tester, api, onResult: (r) => result = r);

      await chooseLocation(tester, 'Shelf A (A)');
      await tester.tap(find.widgetWithText(FilledButton, 'Reserve stock'));
      await tester.pumpAndSettle();

      expect(find.text('Warehouse temporarily unavailable'), findsOneWidget);
      expect(find.textContaining("safe to try again"), findsOneWidget);
      expect(result, isNull);

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(api.calls, ['reserve', 'reserve']);
      expect(result, isTrue);
    });

    testWidgets('an unrelated failure is shown verbatim', (tester) async {
      final api = _FakeOrdersApi()..failWith = const ConflictError('Cannot transition order from DRAFT to STOCK_RESERVED');
      await open(tester, api);

      await chooseLocation(tester, 'Shelf A (A)');
      await tester.tap(find.widgetWithText(FilledButton, 'Reserve stock'));
      await tester.pumpAndSettle();

      expect(find.text('Cannot transition order from DRAFT to STOCK_RESERVED'), findsOneWidget);
    });
  });

  group('dispatch preview', () {
    Future<void> open(WidgetTester tester, Order order, {_FakeOrdersApi? api, Brightness brightness = Brightness.light}) async {
      await _pump(
        tester,
        api: api ?? _FakeOrdersApi(),
        brightness: brightness,
        launcher: (context, _) => Center(
          child: TextButton(onPressed: () => showDispatchOrderDialog(context, order: order), child: const Text('open')),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('everything packed → expects DISPATCHED', (tester) async {
      await open(tester, _order(OrderStatus.readyForDispatch, [_item('i1', _pShampoo, 'Shampoo', ordered: 10, packed: 10)]));
      expect(find.text('ships 10 of 10'), findsOneWidget);
      expect(find.textContaining('the order becomes Dispatched'), findsOneWidget);
    });

    testWidgets('packed short → warns it will be PARTIALLY FULFILLED and names the shortfall', (tester) async {
      await open(tester, _order(OrderStatus.readyForDispatch, [_item('i1', _pShampoo, 'Shampoo', ordered: 10, packed: 6)]));
      expect(find.text('ships 6 of 10'), findsOneWidget);
      expect(find.textContaining('Partially fulfilled'), findsOneWidget);
      expect(find.textContaining('released back to available'), findsWidgets);
    });

    testWidgets('warehouse unavailable on dispatch → retry note, dialog stays', (tester) async {
      final api = _FakeOrdersApi()..failWith = const ServiceUnavailableError('down');
      await open(tester, _order(OrderStatus.readyForDispatch, [_item('i1', _pShampoo, 'Shampoo', packed: 10)]), api: api);
      await tester.tap(find.widgetWithText(FilledButton, 'Dispatch'));
      await tester.pumpAndSettle();
      expect(find.text('Warehouse temporarily unavailable'), findsOneWidget);
      expect(find.text('Dispatch order'), findsOneWidget);
    });

    testWidgets('renders in dark mode without layout errors', (tester) async {
      await open(
        tester,
        _order(OrderStatus.readyForDispatch, [_item('i1', _pShampoo, 'Shampoo', ordered: 10, packed: 6)]),
        brightness: Brightness.dark,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('actions card', () {
    Future<void> show(WidgetTester tester, Order order, Set<String> permissions) => _pump(
      tester,
      api: _FakeOrdersApi(),
      permissions: permissions,
      launcher: (context, _) => SingleChildScrollView(child: OrderActionsCard(order: order)),
    );

    testWidgets('a pending order shows Approve / Reject / Cancel to a manager', (tester) async {
      await show(tester, _order(OrderStatus.pendingApproval, []), {'orders.approve', 'orders.reject'});
      expect(find.text('Approve'), findsOneWidget);
      expect(find.text('Reject'), findsOneWidget);
      expect(find.text('Cancel order'), findsOneWidget);
    });

    testWidgets('without orders.approve the Approve button is absent, with an explanation', (tester) async {
      await show(tester, _order(OrderStatus.pendingApproval, []), {'orders.submit'});
      expect(find.text('Approve'), findsNothing);
      expect(find.textContaining('needs the orders.approve permission'), findsOneWidget);
    });

    final reserved = _order(OrderStatus.stockReserved, [_item('i1', _pShampoo, 'Shampoo')]);

    testWidgets('a reserved order shows Record picking to someone with fulfilment.pick', (tester) async {
      await show(tester, reserved, {'fulfilment.pick'});
      expect(find.text('Record picking'), findsOneWidget);
    });

    testWidgets('a reserved order hides Record picking from someone without fulfilment.pick', (tester) async {
      await show(tester, reserved, {'orders.approve'});
      expect(find.text('Record picking'), findsNothing);
    });

    testWidgets('a finished order offers nothing', (tester) async {
      await show(tester, _order(OrderStatus.completed, []), {'orders.approve', 'fulfilment.dispatch'});
      expect(find.textContaining('no further actions'), findsOneWidget);
    });

    testWidgets('after dispatch there is no Cancel (stock has left)', (tester) async {
      await show(tester, _order(OrderStatus.dispatched, []), {'orders.approve', 'fulfilment.dispatch'});
      expect(find.text('Cancel order'), findsNothing);
      expect(find.text('Mark delivered'), findsOneWidget);
    });
  });
}
