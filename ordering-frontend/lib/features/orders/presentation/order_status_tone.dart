import '../../../core/theme/nocturne.dart';
import '../../../shared/widgets/status_badge.dart';
import '../domain/order.dart';

/// Shared [StatusTone] mapping for [OrderStatus] — used by both the Orders
/// list and the order detail screen so the two never drift.
StatusTone orderStatusTone(OrderStatus status) => switch (status) {
  OrderStatus.draft => StatusTone.neutral,
  OrderStatus.submitted || OrderStatus.pendingApproval => StatusTone.info,
  OrderStatus.rejected || OrderStatus.cancelled => StatusTone.danger,
  OrderStatus.partiallyFulfilled => StatusTone.warning,
  OrderStatus.delivered || OrderStatus.completed || OrderStatus.dispatched => StatusTone.success,
  _ => StatusTone.info,
};

StatusTone paymentStatusTone(PaymentStatus status) => switch (status) {
  PaymentStatus.unpaid => StatusTone.neutral,
  PaymentStatus.partial => StatusTone.warning,
  PaymentStatus.paid => StatusTone.success,
};

/// The console's [Tone] for an order status (tags, icons, bars).
Tone orderTone(OrderStatus status) => switch (status) {
  OrderStatus.draft => Tone.neutral,
  OrderStatus.submitted || OrderStatus.pendingApproval => Tone.warn,
  OrderStatus.rejected || OrderStatus.cancelled => Tone.bad,
  OrderStatus.partiallyFulfilled => Tone.warn,
  OrderStatus.delivered || OrderStatus.completed => Tone.ok,
  OrderStatus.dispatched => Tone.accent,
  _ => Tone.info,
};

Tone paymentTone(PaymentStatus status) => switch (status) {
  PaymentStatus.unpaid => Tone.neutral,
  PaymentStatus.partial => Tone.warn,
  PaymentStatus.paid => Tone.ok,
};

/// Where an order is in its life, as the Orders list's quick filter groups it.
enum OrderStage { draft, approval, fulfilment, shipped, closed }

OrderStage orderStage(OrderStatus s) => switch (s) {
  OrderStatus.draft => OrderStage.draft,
  OrderStatus.submitted || OrderStatus.pendingApproval => OrderStage.approval,
  OrderStatus.approved ||
  OrderStatus.stockReserved ||
  OrderStatus.picking ||
  OrderStatus.packed ||
  OrderStatus.readyForDispatch => OrderStage.fulfilment,
  OrderStatus.dispatched || OrderStatus.partiallyFulfilled || OrderStatus.delivered => OrderStage.shipped,
  OrderStatus.completed || OrderStatus.rejected || OrderStatus.cancelled => OrderStage.closed,
};

/// Orders that count toward sales and money owed (not drafts, not dead ones).
bool orderCounts(OrderStatus s) => s != OrderStatus.draft && s != OrderStatus.rejected && s != OrderStatus.cancelled;
