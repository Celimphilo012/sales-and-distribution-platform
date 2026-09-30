import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ordering_frontend/core/auth/app_user.dart';
import 'package:ordering_frontend/core/auth/auth_provider.dart';
import 'package:ordering_frontend/core/auth/auth_state.dart';
import 'package:ordering_frontend/core/persistence/shared_preferences_provider.dart';
import 'package:ordering_frontend/core/theme/app_theme.dart';
import 'package:ordering_frontend/features/orders/data/orders_providers.dart';
import 'package:ordering_frontend/features/orders/domain/order.dart';
import 'package:ordering_frontend/features/orders/presentation/orders_screen.dart';
import 'package:ordering_frontend/features/payments/data/payments_api.dart';
import 'package:ordering_frontend/features/payments/domain/payment.dart';
import 'package:ordering_frontend/features/payments/presentation/payments_screen.dart';
import 'package:ordering_frontend/features/reports/presentation/reports_screen.dart';
import 'package:ordering_frontend/shared/export/report_export.dart';

class _FakeUser extends AuthNotifier {
  _FakeUser(this.permissions);

  final Set<String> permissions;

  @override
  Future<AuthState> build() async => AuthState.authenticated(AppUser(id: 'u1', name: 'Thandi Dlamini', email: 't@example.com', permissions: permissions));
}

Order _order(String number, String status, {required double total, double paid = 0, String customer = 'Acme Store', String payment = 'UNPAID'}) {
  final now = DateTime.now().toIso8601String();
  return Order.fromJson({
    'id': 'id-$number',
    'orderNumber': number,
    'customerId': 'c-$customer',
    'consultantId': 'u1',
    'status': status,
    'paymentStatus': payment,
    'orderDate': now,
    'total': total,
    'amountPaid': paid,
    'createdAt': now,
    'updatedAt': now,
    'customer': {'id': 'c-$customer', 'name': customer},
    'consultant': {'id': 'u1', 'fullName': 'Thandi Dlamini', 'email': 't@example.com'},
    'items': [
      {
        'id': 'l-$number',
        'orderId': 'id-$number',
        'productId': 'p1',
        'productName': 'Soap',
        'quantityOrdered': 2,
        'quantityFulfilled': 0,
        'quantityPicked': 0,
        'quantityPacked': 0,
        'unitPrice': total / 2,
        'lineTotal': total,
      },
    ],
  });
}

Payment _payment(String id, double amount, {bool voided = false}) => Payment.fromJson({
  'id': id,
  'amount': amount,
  'method': 'MOBILE_MONEY',
  'reference': 'MP-$id',
  'paidAt': DateTime.now().toIso8601String(),
  'status': voided ? 'VOIDED' : 'RECORDED',
  'recordedByUser': {'fullName': 'Thandi Dlamini'},
  'voidReason': voided ? 'typed twice' : null,
  'order': {'id': 'id-ORD-1', 'orderNumber': 'ORD-1'},
  'customer': {'id': 'c-Acme Store', 'name': 'Acme Store'},
});

final _orders = [
  _order('ORD-1', 'DELIVERED', total: 100, paid: 40, payment: 'PARTIAL'),
  _order('ORD-2', 'PENDING_APPROVAL', total: 50, customer: 'Bongani Spaza'),
  _order('ORD-3', 'DRAFT', total: 30),
  _order('ORD-4', 'CANCELLED', total: 80),
];

Future<void> _pump(WidgetTester tester, Widget screen, {Set<String> permissions = const {'orders.view_team', 'orders.create', 'reports.view', 'payments.void'}, List overrides = const []}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  tester.view.physicalSize = const Size(1280, 1300);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: '/x',
    routes: [
      GoRoute(path: '/x', builder: (context, state) => Scaffold(body: screen)),
      GoRoute(path: '/orders/:id', builder: (context, state) => Text('order:${state.pathParameters['id']}')),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        authProvider.overrideWith(() => _FakeUser(permissions)),
        allOrdersProvider.overrideWith((ref) async => _orders),
        ...overrides.cast(),
      ],
      child: MaterialApp.router(theme: AppTheme.dark(), routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('orders list', () {
    testWidgets('shows every order with value and still-owed stats that skip drafts and dead orders', (tester) async {
      await _pump(tester, const OrdersScreen());
      for (final n in ['ORD-1', 'ORD-2', 'ORD-3', 'ORD-4']) {
        expect(find.text(n), findsOneWidget);
      }
      expect(find.text('E 150.00'), findsOneWidget); // value: 100 + 50 (no draft, no cancelled)
      expect(find.text('E 110.00'), findsOneWidget); // owed: 60 + 50
    });

    testWidgets('the Approval stage narrows to orders waiting for a manager', (tester) async {
      await _pump(tester, const OrdersScreen());
      await tester.tap(find.text('Approval'));
      await tester.pumpAndSettle();
      expect(find.text('ORD-2'), findsOneWidget);
      expect(find.text('ORD-1'), findsNothing);
    });

    testWidgets('opening a row goes to the order', (tester) async {
      await _pump(tester, const OrdersScreen());
      await tester.tap(find.text('ORD-2'));
      await tester.pumpAndSettle();
      expect(find.text('order:id-ORD-2'), findsOneWidget);
    });
  });

  group('payments ledger', () {
    testWidgets('collected excludes voided payments, which stay listed', (tester) async {
      await _pump(
        tester,
        const PaymentsScreen(),
        overrides: [allPaymentsProvider.overrideWith((ref) async => [_payment('p1', 40), _payment('p2', 40, voided: true)])],
      );
      expect(find.text('Collected'), findsOneWidget);
      expect(find.text('E 40.00'), findsWidgets);
      expect(find.text('Voided'), findsWidgets);
      expect(find.text('ORD-1'), findsNWidgets(2));
    });
  });

  group('reports', () {
    final sources = ReportSources(orders: _orders, payments: [_payment('p1', 40), _payment('p2', 40, voided: true)]);
    ReportData report(String id) => buildReport(kReports.firstWhere((r) => r.id == id), sources, ReportPeriod.all);

    test('outstanding balances list only live orders still owed, with a totals row', () {
      final rep = report('owed');
      expect(rep.rows.map((r) => r[0]), ['ORD-1', 'ORD-2']);
      expect(rep.totals!.last, 110);
    });

    test('payments received leave out voided payments and say so', () {
      final rep = report('payments');
      expect(rep.rows.length, 1);
      expect(rep.totals!.last, 40);
      expect(rep.note, contains('1 voided payment'));
    });

    test('sales by customer rank by what they bought', () {
      final rep = report('customers');
      expect(rep.rows.first[0], 'Acme Store');
      expect(rep.rows.first[3], 100);
      expect(rep.rows.first[5], 60);
    });
  });
}
