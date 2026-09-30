import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/providers.dart';
import '../domain/order.dart';
import 'orders_api.dart';

final ordersApiProvider = Provider<OrdersApi>((ref) => OrdersApi(ref.watch(apiClientProvider)));

/// Status filter for the Orders list — `null` means "all statuses" (the
/// real API omits the param entirely in that case). A plain
/// (non-autoDispose) `Notifier` so it survives navigating to an order and
/// back, matching R2's `CustomersFilter` pattern.
class OrdersStatusFilterNotifier extends Notifier<OrderStatus?> {
  @override
  OrderStatus? build() => null;

  void set(OrderStatus? status) => state = status;
}

final ordersStatusFilterProvider = NotifierProvider<OrdersStatusFilterNotifier, OrderStatus?>(
  OrdersStatusFilterNotifier.new,
);

final ordersListProvider = FutureProvider.autoDispose<List<Order>>((ref) {
  final status = ref.watch(ordersStatusFilterProvider);
  return ref.watch(ordersApiProvider).list(status: status);
});

/// Every order the viewer may see (all statuses) — the Orders list, the
/// dashboard panels and the notifications bell filter this client-side.
final allOrdersProvider = FutureProvider.autoDispose<List<Order>>((ref) {
  return ref.watch(ordersApiProvider).list();
});

final orderDetailProvider =FutureProvider.autoDispose.family<Order, String>((ref, id) {
  return ref.watch(ordersApiProvider).getOne(id);
});

/// A specific customer's orders — independent of the main list's status
/// filter. Powers the R2 customer-detail screen's "orders" section, wired
/// up for real in R3a.
final customerOrdersProvider = FutureProvider.autoDispose.family<List<Order>, String>((ref, customerId) {
  return ref.watch(ordersApiProvider).list(customerId: customerId);
});

void invalidateOrders(WidgetRef ref) {
  ref.invalidate(ordersListProvider);
  ref.invalidate(allOrdersProvider);
  ref.invalidate(customerOrdersProvider);
}

void invalidateOrder(WidgetRef ref, String id) {
  ref.invalidate(orderDetailProvider(id));
  invalidateOrders(ref);
}
