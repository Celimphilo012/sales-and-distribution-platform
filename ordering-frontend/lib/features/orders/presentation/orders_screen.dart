import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/error/app_error.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../routing/route_paths.dart';
import '../../../shared/date_format.dart';
import '../../../shared/quantity_format.dart';
import '../../../shared/widgets/app_data_table.dart';
import '../../../shared/widgets/app_dropdown_field.dart';
import '../../../shared/widgets/empty_loading_error_states.dart';
import '../../../shared/widgets/status_badge.dart';
import '../data/orders_providers.dart';
import '../domain/order.dart';
import 'order_status_tone.dart';

/// STEP R3a — ORDERS list, the same responsive-table + filter-bar template
/// R2's Customers screen set. No pagination, no search on the real API —
/// just a single `status` filter (`ListOrdersQueryDto`). `GET /orders` is
/// scoped server-side to the caller's own orders unless they hold
/// `orders.view_team` — this screen has no knowledge of that scoping, it
/// just renders whatever comes back.
class OrdersScreen extends ConsumerWidget {
  const OrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final canCreate = ref.watch(authProvider.select((s) => s.value?.user?.can('orders.create') ?? false));
    final statusFilter = ref.watch(ordersStatusFilterProvider);
    final ordersAsync = ref.watch(ordersListProvider);

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('Orders', style: theme.textTheme.headlineSmall)),
              if (canCreate)
                FilledButton.icon(
                  onPressed: () => context.go(RoutePaths.orderNew),
                  icon: const Icon(Icons.add_shopping_cart_outlined),
                  label: const Text('New order'),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            width: 220,
            child: AppDropdownField<OrderStatus?>(
              label: 'Status',
              value: statusFilter,
              items: [null, ...OrderStatus.values],
              itemLabel: (s) => s?.label ?? 'All statuses',
              onChanged: (value) => ref.read(ordersStatusFilterProvider.notifier).set(value),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Expanded(
            child: ordersAsync.when(
              loading: () => const LoadingStateView(message: 'Loading orders…'),
              error: (error, stackTrace) => ErrorStateView(
                message: error is AppError ? error.message : 'Could not load orders.',
                onRetry: () => ref.invalidate(ordersListProvider),
              ),
              data: (orders) => AppDataTable<Order>(
                rows: orders,
                emptyTitle: 'No orders found',
                emptyMessage: 'Try a different status filter, or create one.',
                onRowTap: (order) => context.go(RoutePaths.orderDetail(order.id)),
                columns: [
                  AppDataColumn(label: 'Order #', cellBuilder: (o) => Text(o.orderNumber)),
                  AppDataColumn(label: 'Customer', cellBuilder: (o) => Text(o.customer.name)),
                  AppDataColumn(label: 'Date', cellBuilder: (o) => Text(formatDateTime(o.orderDate))),
                  AppDataColumn(
                    label: 'Total',
                    numeric: true,
                    cellBuilder: (o) => Text(formatQuantity(o.total)),
                  ),
                  AppDataColumn(
                    label: 'Status',
                    cellBuilder: (o) => StatusBadge(label: o.status.label, tone: orderStatusTone(o.status)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
