import '../../../core/error/app_error.dart';
import 'order.dart';

/// Every lifecycle action the backend exposes as `POST /orders/:id/<path>`.
enum OrderAction { submit, approve, reject, reserve, cancel, pick, pack, ready, dispatch, deliver, complete }

/// What an [OrderAction] is and who may do it.
///
/// [permission] is the exact key the backend's controller guards the route
/// with (`OrdersController`), so the UI hides precisely what the server would
/// reject — never a role name (CLAUDE.md rule 1). Note the backend reuses
/// `orders.approve` for reserve and cancel, and `fulfilment.dispatch` for
/// ready/dispatch/deliver/complete; there are no separate keys for those.
class OrderActionSpec {
  const OrderActionSpec({
    required this.label,
    required this.path,
    required this.permission,
    this.destructive = false,
    this.crossesWarehouse = false,
  });

  final String label;
  final String path;
  final String permission;
  final bool destructive;

  /// True when the backend calls the warehouse as part of this action
  /// (reserve, dispatch, and cancel-with-a-reservation), so it can fail with
  /// "warehouse unavailable" and must be safe to retry.
  final bool crossesWarehouse;
}

const Map<OrderAction, OrderActionSpec> kOrderActionSpecs = {
  OrderAction.submit: OrderActionSpec(label: 'Submit for approval', path: 'submit', permission: 'orders.submit'),
  OrderAction.approve: OrderActionSpec(label: 'Approve', path: 'approve', permission: 'orders.approve'),
  OrderAction.reject: OrderActionSpec(label: 'Reject', path: 'reject', permission: 'orders.reject', destructive: true),
  OrderAction.reserve: OrderActionSpec(
    label: 'Reserve stock',
    path: 'reserve',
    permission: 'orders.approve',
    crossesWarehouse: true,
  ),
  OrderAction.cancel: OrderActionSpec(
    label: 'Cancel order',
    path: 'cancel',
    permission: 'orders.approve',
    destructive: true,
    crossesWarehouse: true,
  ),
  OrderAction.pick: OrderActionSpec(label: 'Record picking', path: 'pick', permission: 'fulfilment.pick'),
  OrderAction.pack: OrderActionSpec(label: 'Record packing', path: 'pack', permission: 'fulfilment.pack'),
  OrderAction.ready: OrderActionSpec(label: 'Mark ready for dispatch', path: 'ready', permission: 'fulfilment.dispatch'),
  OrderAction.dispatch: OrderActionSpec(
    label: 'Dispatch',
    path: 'dispatch',
    permission: 'fulfilment.dispatch',
    crossesWarehouse: true,
  ),
  OrderAction.deliver: OrderActionSpec(label: 'Mark delivered', path: 'deliver', permission: 'fulfilment.dispatch'),
  OrderAction.complete: OrderActionSpec(label: 'Complete order', path: 'complete', permission: 'fulfilment.dispatch'),
};

/// Which actions are valid in each status — the frontend mirror of the
/// backend's `ORDER_STATUS_TRANSITIONS` map (ARCHITECTURE.md §I). The
/// backend does NOT return "available transitions" with an order, so this is
/// derived here; it stays in one config map (rule 7), never scattered `if`s.
/// The first entry is the forward step; anything after it is a side exit.
///
/// The backend remains the authority: if this ever drifts, the server rejects
/// the call (409) and the UI surfaces that cleanly.
const Map<OrderStatus, List<OrderAction>> kOrderActionsByStatus = {
  OrderStatus.draft: [OrderAction.submit, OrderAction.cancel],
  // Submit performs DRAFT → SUBMITTED → PENDING_APPROVAL in one call, so an
  // order should not normally rest at SUBMITTED; cancel is the only exit.
  OrderStatus.submitted: [OrderAction.cancel],
  OrderStatus.pendingApproval: [OrderAction.approve, OrderAction.reject, OrderAction.cancel],
  OrderStatus.approved: [OrderAction.reserve, OrderAction.cancel],
  OrderStatus.stockReserved: [OrderAction.pick, OrderAction.cancel],
  OrderStatus.picking: [OrderAction.pack, OrderAction.cancel],
  OrderStatus.packed: [OrderAction.ready, OrderAction.cancel],
  OrderStatus.readyForDispatch: [OrderAction.dispatch, OrderAction.cancel],
  // Stock has physically left — no cancel from here on.
  OrderStatus.dispatched: [OrderAction.deliver],
  OrderStatus.partiallyFulfilled: [OrderAction.deliver],
  OrderStatus.delivered: [OrderAction.complete],
  OrderStatus.completed: [],
  OrderStatus.rejected: [],
  OrderStatus.cancelled: [],
};

/// The actions valid for [status] that the caller is permitted to perform,
/// in display order (forward step first). [can] is `AppUser.can`.
List<OrderAction> allowedOrderActions(OrderStatus status, bool Function(String permission) can) => [
  for (final action in kOrderActionsByStatus[status] ?? const <OrderAction>[])
    if (can(kOrderActionSpecs[action]!.permission)) action,
];

/// The next forward step for [status], or null in a terminal state — used
/// to tell a user who lacks permission what the order is waiting on.
OrderAction? forwardActionFor(OrderStatus status) {
  final actions = kOrderActionsByStatus[status] ?? const <OrderAction>[];
  if (actions.isEmpty) return null;
  final first = actions.first;
  return first == OrderAction.cancel ? null : first;
}

/// One line the warehouse could not fully reserve.
class StockShortLine {
  const StockShortLine({
    required this.productId,
    required this.locationId,
    required this.requested,
    required this.available,
  });

  final String productId;
  final String locationId;
  final double requested;
  final double available;

  double get shortBy => requested - available;
}

final _shortLinePattern = RegExp(
  r'product ([0-9a-fA-F-]{36}) at location ([0-9a-fA-F-]{36}): need ([0-9.]+), only ([0-9.]+) available',
);

/// Reads the short lines out of the backend's insufficient-stock 409.
///
/// The backend (`OrdersService.reserve`) flattens the warehouse's structured
/// `shortLines` into the message text —
/// "Cannot reserve — insufficient available stock for: product ID at
/// location ID: need N, only M available; …" — instead of returning them as
/// a body field, so this parses that text. Returns null when [message] isn't
/// an insufficient-stock message or no line can be read, so the caller falls
/// back to showing the message verbatim rather than an empty panel.
List<StockShortLine>? parseInsufficientStock(String message) {
  if (!message.contains('insufficient available stock')) return null;
  final lines = [
    for (final m in _shortLinePattern.allMatches(message))
      StockShortLine(
        productId: m.group(1)!,
        locationId: m.group(2)!,
        requested: double.parse(m.group(3)!),
        available: double.parse(m.group(4)!),
      ),
  ];
  return lines.isEmpty ? null : lines;
}

/// How a lifecycle call failed, sorted into the cases the UI treats
/// differently. Reserve, dispatch and cancel cross into the warehouse, so
/// they can fail in the two ways below in addition to an ordinary error.
sealed class LifecycleFailure {
  const LifecycleFailure(this.message);

  /// The backend's own message — always safe to show verbatim as a fallback.
  final String message;
}

/// The warehouse doesn't have enough available stock. A normal business
/// outcome, not an error: nothing was reserved and the order did not move.
class InsufficientStockFailure extends LifecycleFailure {
  const InsufficientStockFailure(super.message, this.shortLines);

  final List<StockShortLine> shortLines;
}

/// The warehouse couldn't be reached (HTTP 503). Nothing was attempted on
/// either side, so the same call can safely be repeated.
class WarehouseUnavailableFailure extends LifecycleFailure {
  const WarehouseUnavailableFailure(super.message);
}

/// Anything else: validation (400), an illegal transition (409), a missing
/// permission (403), a bad-gateway from the warehouse (502), …
class OtherFailure extends LifecycleFailure {
  const OtherFailure(super.message);
}

LifecycleFailure classifyLifecycleError(Object error) {
  if (error is ServiceUnavailableError) return WarehouseUnavailableFailure(error.message);
  if (error is ConflictError) {
    final shortLines = parseInsufficientStock(error.message);
    if (shortLines != null) return InsufficientStockFailure(error.message, shortLines);
  }
  if (error is AppError) return OtherFailure(error.message);
  return const OtherFailure('An unexpected error occurred.');
}
