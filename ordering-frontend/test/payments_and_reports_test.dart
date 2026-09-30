import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ordering_frontend/core/auth/app_user.dart';
import 'package:ordering_frontend/core/auth/auth_provider.dart';
import 'package:ordering_frontend/core/auth/auth_state.dart';
import 'package:ordering_frontend/core/theme/app_theme.dart';
import 'package:ordering_frontend/features/dashboard/presentation/dashboard_screen.dart';
import 'package:ordering_frontend/features/orders/data/orders_api.dart';
import 'package:ordering_frontend/features/orders/data/orders_providers.dart';
import 'package:ordering_frontend/features/orders/domain/order.dart';
import 'package:ordering_frontend/features/payments/data/payments_api.dart';
import 'package:ordering_frontend/features/payments/domain/payment.dart';
import 'package:ordering_frontend/features/payments/presentation/order_payments_card.dart';
import 'package:ordering_frontend/features/reports/data/reports_api.dart';
import 'package:ordering_frontend/features/reports/domain/reports.dart';
import 'package:ordering_frontend/shared/money_format.dart';

final _now = DateTime(2026, 9, 29, 10);

Order _order(OrderStatus status, {double total = 50, PaymentStatus paymentStatus = PaymentStatus.unpaid}) => Order(
  id: 'o1',
  orderNumber: 'ORD-TEST',
  customerId: 'c1',
  status: status,
  paymentStatus: paymentStatus,
  orderDate: _now,
  total: total,
  createdAt: _now,
  updatedAt: _now,
  customer: const OrderCustomerRef(id: 'c1', name: 'Test Customer'),
  items: const [],
);

Map<String, dynamic> _paymentJson({String id = 'p1', String status = 'RECORDED', String amount = '20'}) => {
  'id': id,
  'orderId': 'o1',
  'amount': amount,
  'method': 'MOBILE_MONEY',
  'reference': 'MP123',
  'notes': null,
  'paidAt': '2026-09-29T08:00:00.000Z',
  'status': status,
  'recordedByUser': {'id': 'u1', 'fullName': 'Cashier One'},
  'voidedByUser': status == 'VOIDED' ? {'id': 'u2', 'fullName': 'Manager Two'} : null,
  'voidedAt': status == 'VOIDED' ? '2026-09-29T09:00:00.000Z' : null,
  'voidReason': status == 'VOIDED' ? 'Typed the wrong amount' : null,
  'order': {'id': 'o1', 'orderNumber': 'ORD-TEST'},
};

class _FakePaymentsApi extends Fake implements PaymentsApi {
  _FakePaymentsApi(this.money);

  final OrderPayments money;
  final recorded = <Map<String, Object?>>[];

  @override
  Future<OrderPayments> forOrder(String orderId) async => money;

  @override
  Future<void> record({
    required String orderId,
    required double amount,
    required PaymentMethod method,
    String? reference,
    String? notes,
    DateTime? paidAt,
  }) async {
    recorded.add({'amount': amount, 'method': method, 'reference': reference});
  }
}

class _FakeUser extends AuthNotifier {
  _FakeUser(this.permissions);

  final Set<String> permissions;

  @override
  Future<AuthState> build() async => AuthState.authenticated(
    AppUser(id: 'u1', name: 'Thandi Dlamini', email: 't@example.com', permissions: permissions),
  );
}

Future<void> _pump(WidgetTester tester, Widget child, {required List<Object> overrides, bool scroll = true}) async {
  tester.view.physicalSize = const Size(1200, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides.cast(),
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: scroll ? SingleChildScrollView(child: child) : child),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('formatMoney', () {
    test('groups thousands and always shows cents', () {
      expect(formatMoney(0), 'E 0.00');
      expect(formatMoney(12.5), 'E 12.50');
      expect(formatMoney(1250), 'E 1,250.00');
      expect(formatMoney(1234567.891), 'E 1,234,567.89');
      expect(formatMoney(-30), '-E 30.00');
    });
  });

  group('parsing', () {
    test('an order payments answer, with a voided payment kept on record', () {
      final money = OrderPayments.fromJson({
        'orderId': 'o1',
        'total': 50,
        'amountPaid': 20,
        'balanceDue': 30,
        'paymentStatus': 'PARTIAL',
        'payments': [_paymentJson(), _paymentJson(id: 'p2', status: 'VOIDED', amount: '5.5')],
      });
      expect(money.paymentStatus, PaymentStatus.partial);
      expect(money.balanceDue, 30);
      expect(money.payments.first.method, PaymentMethod.mobileMoney);
      expect(money.payments.first.recordedByName, 'Cashier One');
      expect(money.payments.last.isVoided, isTrue);
      expect(money.payments.last.amount, 5.5);
      expect(money.payments.last.voidReason, 'Typed the wrong amount');
    });

    test('the dashboard payload', () {
      final d = DashboardSummary.fromJson({
        'ordersByStatus': [
          {'status': 'PENDING_APPROVAL', 'count': 2, 'totalValue': 75},
        ],
        'today': {'orderCount': 1, 'totalValue': 25, 'collected': 10},
        'thisWeek': {'orderCount': 3, 'totalValue': 100, 'collected': 40},
        'awaitingApproval': 2,
        'outstanding': {'orderCount': 4, 'amount': 180.5},
        'recentOrders': [
          {
            'id': 'o1',
            'orderNumber': 'ORD-1',
            'status': 'APPROVED',
            'paymentStatus': 'UNPAID',
            'orderDate': '2026-09-29T08:00:00.000Z',
            'total': '25',
            'customer': {'id': 'c1', 'name': 'Acme'},
          },
        ],
      });
      expect(d.awaitingApproval, 2);
      expect(d.outstandingAmount, 180.5);
      expect(d.weekCollected, 40);
      expect(d.recentOrders.single.customerName, 'Acme');
      expect(d.byStatus.single.status, OrderStatus.pendingApproval);
    });

    test('non-cash methods need a reference, cash does not', () {
      expect(PaymentMethod.cash.needsReference, isFalse);
      expect(PaymentMethod.mobileMoney.needsReference, isTrue);
      expect(PaymentMethod.bankTransfer.apiValue, 'BANK_TRANSFER');
      expect(paymentMethodFromJson('CARD'), PaymentMethod.card);
    });
  });

  group('payments card', () {
    final partial = OrderPayments(
      total: 50,
      amountPaid: 20,
      balanceDue: 30,
      paymentStatus: PaymentStatus.partial,
      payments: [
        Payment.fromJson(_paymentJson()),
        Payment.fromJson(_paymentJson(id: 'p2', status: 'VOIDED', amount: '5')),
      ],
    );

    List<Object> overridesFor(Set<String> permissions, _FakePaymentsApi api) => [
      paymentsApiProvider.overrideWithValue(api),
      authProvider.overrideWith(() => _FakeUser(permissions)),
    ];

    testWidgets('shows paid / due, and voided payments struck through with their reason', (tester) async {
      await _pump(
        tester,
        OrderPaymentsCard(order: _order(OrderStatus.approved, paymentStatus: PaymentStatus.partial)),
        overrides: overridesFor({}, _FakePaymentsApi(partial)),
      );
      expect(find.text('E 50.00'), findsOneWidget);
      expect(find.text('E 20.00'), findsWidgets);
      expect(find.text('E 30.00'), findsOneWidget);
      expect(find.text('Voided'), findsOneWidget);
      expect(find.textContaining('Typed the wrong amount'), findsOneWidget);
      expect(find.text('Record payment'), findsNothing, reason: 'no payments.record, no button');
      expect(find.text('Void'), findsNothing, reason: 'no payments.void, no void');
    });

    testWidgets('a cashier can record; a voider can void only recorded payments', (tester) async {
      await _pump(
        tester,
        OrderPaymentsCard(order: _order(OrderStatus.approved)),
        overrides: overridesFor({'payments.record', 'payments.void'}, _FakePaymentsApi(partial)),
      );
      expect(find.text('Record payment'), findsOneWidget);
      expect(find.text('Void'), findsOneWidget, reason: 'the already-voided payment has no Void button');
    });

    testWidgets('a draft or cancelled order takes no payments', (tester) async {
      const nothing = OrderPayments(total: 50, amountPaid: 0, balanceDue: 50, paymentStatus: PaymentStatus.unpaid);
      await _pump(
        tester,
        OrderPaymentsCard(order: _order(OrderStatus.cancelled)),
        overrides: overridesFor({'payments.record'}, _FakePaymentsApi(nothing)),
      );
      expect(find.text('Record payment'), findsNothing);
      expect(find.textContaining('takes no payments'), findsOneWidget);
    });

    testWidgets('the record dialog pre-fills the balance, refuses overpayment, and needs a MoMo reference', (
      tester,
    ) async {
      final api = _FakePaymentsApi(partial);
      await _pump(
        tester,
        OrderPaymentsCard(order: _order(OrderStatus.approved)),
        overrides: overridesFor({'payments.record'}, api),
      );
      await tester.tap(find.text('Record payment'));
      await tester.pumpAndSettle();

      final amount = find.widgetWithText(TextFormField, 'Amount (E)');
      expect(tester.widget<TextFormField>(amount).controller!.text, '30.00');

      await tester.enterText(amount, '31');
      await tester.tap(find.widgetWithText(FilledButton, 'Record payment').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('More than the balance due'), findsOneWidget);
      expect(api.recorded, isEmpty);

      await tester.enterText(amount, '12.5');
      await tester.tap(find.text('Cash').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mobile money (MoMo)').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Record payment').last);
      await tester.pumpAndSettle();
      expect(find.text('Enter the momo transaction id'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextFormField, 'Reference (required)'), 'MP777');
      await tester.tap(find.widgetWithText(FilledButton, 'Record payment').last);
      await tester.pumpAndSettle();
      expect(api.recorded.single, {'amount': 12.5, 'method': PaymentMethod.mobileMoney, 'reference': 'MP777'});
    });
  });

  group('dashboard', () {
    testWidgets('a manager sees the money and approval tiles', (tester) async {
      final summary = DashboardSummary.fromJson({
        'ordersByStatus': [
          {'status': 'PENDING_APPROVAL', 'count': 2, 'totalValue': 75},
        ],
        'today': {'orderCount': 1, 'totalValue': 25, 'collected': 10},
        'thisWeek': {'orderCount': 3, 'totalValue': 100, 'collected': 40},
        'awaitingApproval': 2,
        'outstanding': {'orderCount': 4, 'amount': 1180.5},
        'recentOrders': const [],
      });
      await _pump(
        tester,
        const DashboardScreen(),
        scroll: false,
        overrides: [
          dashboardProvider.overrideWith((ref) async => summary),
          allOrdersProvider.overrideWith((ref) async => const <Order>[]),
          authProvider.overrideWith(() => _FakeUser({'reports.view', 'orders.create'})),
        ],
      );
      expect(find.textContaining('Thandi'), findsOneWidget);
      expect(find.text('Awaiting approval'), findsWidgets); // KPI tile + queue panel
      expect(find.text('Customers owe'), findsOneWidget);
      expect(find.text('E 1,180.50'), findsOneWidget);
      expect(find.text('New order'), findsOneWidget);
    });

    testWidgets('without reports.view it shows my own latest orders, not an error', (tester) async {
      await _pump(
        tester,
        const DashboardScreen(),
        scroll: false,
        overrides: [
          ordersApiProvider.overrideWithValue(_FakeOrdersApi([_order(OrderStatus.approved)])),
          authProvider.overrideWith(() => _FakeUser({'orders.view_own'})),
        ],
      );
      expect(find.text('Your latest orders'), findsOneWidget);
      expect(find.textContaining('ORD-TEST'), findsOneWidget);
      expect(find.text('Customers owe'), findsNothing); // the team money panels are for reports.view
    });
  });
}

class _FakeOrdersApi extends Fake implements OrdersApi {
  _FakeOrdersApi(this.orders);

  final List<Order> orders;

  @override
  Future<List<Order>> list({OrderStatus? status, String? customerId}) async => orders;
}
