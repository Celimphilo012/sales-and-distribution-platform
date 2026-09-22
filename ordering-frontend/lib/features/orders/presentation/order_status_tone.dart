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
