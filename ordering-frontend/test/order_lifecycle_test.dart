import 'package:flutter_test/flutter_test.dart';

import 'package:ordering_frontend/core/error/app_error.dart';
import 'package:ordering_frontend/features/orders/domain/order.dart';
import 'package:ordering_frontend/features/orders/domain/order_lifecycle.dart';

void main() {
  group('action table mirrors the backend transition map (ARCHITECTURE.md §I)', () {
    List<OrderAction> actionsFor(OrderStatus s) => kOrderActionsByStatus[s]!;

    test('every status has an entry', () {
      for (final status in OrderStatus.values) {
        expect(kOrderActionsByStatus.containsKey(status), isTrue, reason: '$status is missing');
      }
    });

    test('the happy path offers exactly one forward step per status', () {
      expect(forwardActionFor(OrderStatus.draft), OrderAction.submit);
      expect(forwardActionFor(OrderStatus.pendingApproval), OrderAction.approve);
      expect(forwardActionFor(OrderStatus.approved), OrderAction.reserve);
      expect(forwardActionFor(OrderStatus.stockReserved), OrderAction.pick);
      expect(forwardActionFor(OrderStatus.picking), OrderAction.pack);
      expect(forwardActionFor(OrderStatus.packed), OrderAction.ready);
      expect(forwardActionFor(OrderStatus.readyForDispatch), OrderAction.dispatch);
      expect(forwardActionFor(OrderStatus.dispatched), OrderAction.deliver);
      expect(forwardActionFor(OrderStatus.partiallyFulfilled), OrderAction.deliver);
      expect(forwardActionFor(OrderStatus.delivered), OrderAction.complete);
    });

    test('terminal states offer nothing', () {
      for (final s in [OrderStatus.completed, OrderStatus.rejected, OrderStatus.cancelled]) {
        expect(actionsFor(s), isEmpty, reason: '$s is terminal');
        expect(forwardActionFor(s), isNull);
      }
    });

    test('cancel is offered up to READY_FOR_DISPATCH and never after stock has left', () {
      for (final s in [
        OrderStatus.draft,
        OrderStatus.submitted,
        OrderStatus.pendingApproval,
        OrderStatus.approved,
        OrderStatus.stockReserved,
        OrderStatus.picking,
        OrderStatus.packed,
        OrderStatus.readyForDispatch,
      ]) {
        expect(actionsFor(s), contains(OrderAction.cancel), reason: '$s should allow cancel');
      }
      for (final s in [OrderStatus.dispatched, OrderStatus.partiallyFulfilled, OrderStatus.delivered]) {
        expect(actionsFor(s), isNot(contains(OrderAction.cancel)), reason: '$s must not allow cancel');
      }
    });

    test('reject only exists while pending approval', () {
      for (final s in OrderStatus.values) {
        expect(actionsFor(s).contains(OrderAction.reject), s == OrderStatus.pendingApproval, reason: '$s');
      }
    });
  });

  group('permission gating (hides what the backend would refuse)', () {
    bool Function(String) holding(Set<String> keys) => keys.contains;

    test('without orders.approve there is no approve, reject-less, reserve or cancel', () {
      final can = holding({'orders.submit', 'orders.reject'});
      expect(allowedOrderActions(OrderStatus.pendingApproval, can), [OrderAction.reject]);
      expect(allowedOrderActions(OrderStatus.approved, can), isEmpty); // reserve + cancel both need orders.approve
    });

    test('without fulfilment.pick a reserved order offers no pick', () {
      final can = holding({'orders.approve'});
      expect(allowedOrderActions(OrderStatus.stockReserved, can), [OrderAction.cancel]);
    });

    test('without fulfilment.pack a picking order offers no pack', () {
      final can = holding({'fulfilment.pick', 'fulfilment.dispatch'});
      expect(allowedOrderActions(OrderStatus.picking, can), isEmpty);
    });

    test('the warehouse role can drive fulfilment but cannot approve or reserve', () {
      final can = holding({'fulfilment.pick', 'fulfilment.pack', 'fulfilment.dispatch'});
      expect(allowedOrderActions(OrderStatus.stockReserved, can), [OrderAction.pick]);
      expect(allowedOrderActions(OrderStatus.packed, can), [OrderAction.ready]);
      expect(allowedOrderActions(OrderStatus.approved, can), isEmpty);
    });

    test('a consultant with orders.submit can submit a draft but not cancel it', () {
      final can = holding({'orders.submit', 'orders.create'});
      expect(allowedOrderActions(OrderStatus.draft, can), [OrderAction.submit]);
    });

    test('an admin-equivalent user sees the forward step and the exits', () {
      final can = holding({
        'orders.submit',
        'orders.approve',
        'orders.reject',
        'fulfilment.pick',
        'fulfilment.pack',
        'fulfilment.dispatch',
      });
      expect(allowedOrderActions(OrderStatus.pendingApproval, can), [
        OrderAction.approve,
        OrderAction.reject,
        OrderAction.cancel,
      ]);
    });
  });

  group('insufficient-stock message parsing', () {
    const message =
        'Cannot reserve — insufficient available stock for: '
        'product 11111111-1111-4111-8111-111111111111 at location 22222222-2222-4222-8222-222222222222: need 12, only 4.5 available; '
        'product 33333333-3333-4333-8333-333333333333 at location 44444444-4444-4444-8444-444444444444: need 3, only 0 available';

    test('reads every short line with product, location, requested and available', () {
      final lines = parseInsufficientStock(message)!;
      expect(lines, hasLength(2));
      expect(lines[0].productId, '11111111-1111-4111-8111-111111111111');
      expect(lines[0].locationId, '22222222-2222-4222-8222-222222222222');
      expect(lines[0].requested, 12);
      expect(lines[0].available, 4.5);
      expect(lines[0].shortBy, 7.5);
      expect(lines[1].available, 0);
      expect(lines[1].shortBy, 3);
    });

    test('is null for any other message, so the caller shows it verbatim', () {
      expect(parseInsufficientStock('Cannot transition order from DRAFT to APPROVED'), isNull);
      expect(parseInsufficientStock('Cannot reserve — insufficient available stock for: (garbled)'), isNull);
    });
  });

  group('failure classification', () {
    test('a 409 carrying short lines is an insufficient-stock outcome, not a plain error', () {
      final failure = classifyLifecycleError(
        const ConflictError(
          'Cannot reserve — insufficient available stock for: product 11111111-1111-4111-8111-111111111111 '
          'at location 22222222-2222-4222-8222-222222222222: need 5, only 2 available',
        ),
      );
      expect(failure, isA<InsufficientStockFailure>());
      expect((failure as InsufficientStockFailure).shortLines.single.shortBy, 3);
    });

    test('a 503 is warehouse-unavailable', () {
      expect(classifyLifecycleError(const ServiceUnavailableError()), isA<WarehouseUnavailableFailure>());
    });

    test('an illegal-transition 409 stays a plain error with its message', () {
      final failure = classifyLifecycleError(const ConflictError('Cannot transition order from DRAFT to APPROVED'));
      expect(failure, isA<OtherFailure>());
      expect(failure.message, 'Cannot transition order from DRAFT to APPROVED');
    });

    test('a 400 (e.g. reject without a note) stays a plain error', () {
      expect(classifyLifecycleError(const ValidationError('note must be longer than or equal to 1 characters')),
          isA<OtherFailure>());
    });
  });
}
