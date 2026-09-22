import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/error/app_error.dart';
import '../../../core/theme/app_semantic_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../routing/route_paths.dart';
import '../../../shared/date_format.dart';
import '../../../shared/quantity_format.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/empty_loading_error_states.dart';
import '../../../shared/widgets/status_badge.dart';
import '../data/orders_providers.dart';
import '../domain/order.dart';
import 'order_status_tone.dart';
import 'widgets/order_actions_card.dart';

/// Read-only order detail: customer, lines (product name snapshot,
/// quantity, unit price, line total — all server values, never
/// recomputed), order total, status badge, payment status (shown
/// separately — rule 6, never conflated with order status), dates, and
/// status history, plus (STEP R3b) the status-driven lifecycle actions —
/// see [OrderActionsCard]. Fulfilment lives here, not in a separate queue.
class OrderDetailScreen extends ConsumerWidget {
  const OrderDetailScreen({super.key, required this.orderId});

  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final orderAsync = ref.watch(orderDetailProvider(orderId));

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => context.go(RoutePaths.orders),
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Back to Orders',
              ),
              Text('Order', style: theme.textTheme.headlineSmall),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: orderAsync.when(
              loading: () => const LoadingStateView(message: 'Loading order…'),
              error: (error, stackTrace) => ErrorStateView(
                message: error is AppError ? error.message : 'Could not load this order.',
                onRetry: () => ref.invalidate(orderDetailProvider(orderId)),
              ),
              data: (order) => _OrderDetailBody(order: order),
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderDetailBody extends ConsumerWidget {
  const _OrderDetailBody({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final user = ref.watch(authProvider.select((s) => s.value?.user));
    final canEditDraft = user?.can('orders.edit_own_draft') ?? false;
    final isOwner = user != null && order.consultantId == user.id;
    final canEdit = order.status == OrderStatus.draft && canEditDraft && isOwner;

    return ListView(
      children: [
        AppCard(
          title: order.orderNumber,
          subtitle: 'Customer: ${order.customer.name}${order.customer.phone != null ? ' · ${order.customer.phone}' : ''}',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              StatusBadge(label: order.status.label, tone: orderStatusTone(order.status)),
              const SizedBox(width: AppSpacing.sm),
              StatusBadge(label: order.paymentStatus.label, tone: paymentStatusTone(order.paymentStatus)),
              if (canEdit) ...[
                const SizedBox(width: AppSpacing.sm),
                IconButton(
                  tooltip: 'Edit draft',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => context.go(RoutePaths.orderEdit(order.id)),
                ),
              ],
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DetailRow(label: 'Order date', value: formatDateTime(order.orderDate)),
              _DetailRow(label: 'Consultant', value: order.consultant?.fullName),
              _DetailRow(label: 'Delivery info', value: order.deliveryInfo),
              _DetailRow(label: 'Last updated', value: formatDateTime(order.updatedAt)),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        OrderActionsCard(order: order),
        const SizedBox(height: AppSpacing.md),
        AppCard(
          title: 'Lines',
          subtitle: 'Product name and unit price are snapshots taken when the line was added — never a live lookup.',
          child: Column(
            children: [
              for (final item in order.items) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Text(item.productName ?? '(unknown product)', style: theme.textTheme.bodyMedium),
                      ),
                      _Stat(label: 'Qty', value: formatQuantity(item.quantityOrdered)),
                      // Fulfilment progress appears as each step records it.
                      if (item.quantityPicked > 0 || item.quantityPacked > 0 || item.quantityFulfilled > 0) ...[
                        const SizedBox(width: AppSpacing.lg),
                        _Stat(label: 'Picked', value: formatQuantity(item.quantityPicked)),
                        const SizedBox(width: AppSpacing.lg),
                        _Stat(label: 'Packed', value: formatQuantity(item.quantityPacked)),
                        const SizedBox(width: AppSpacing.lg),
                        _Stat(label: 'Shipped', value: formatQuantity(item.quantityFulfilled)),
                      ],
                      const SizedBox(width: AppSpacing.lg),
                      _Stat(label: 'Unit price', value: formatQuantity(item.unitPrice)),
                      const SizedBox(width: AppSpacing.lg),
                      _Stat(label: 'Line total', value: formatQuantity(item.lineTotal), emphasize: true),
                    ],
                  ),
                ),
                const Divider(),
              ],
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text('Order total: ', style: theme.textTheme.bodyMedium),
                    Text(
                      formatQuantity(order.total),
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (order.status == OrderStatus.partiallyFulfilled) ...[
          const SizedBox(height: AppSpacing.md),
          _PartialFulfilmentNote(order: order),
        ],
        if (order.statusHistory.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          AppCard(
            title: 'Status history',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final entry in order.statusHistory)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                    child: Text(
                      '${entry.fromStatus != null ? '${entry.fromStatus!.label} → ' : ''}${entry.toStatus.label} '
                      '· ${entry.changedByName} · ${formatDateTime(entry.createdAt)}'
                      '${entry.note != null && entry.note!.isNotEmpty ? ' — "${entry.note}"' : ''}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          Expanded(child: Text((value?.isEmpty ?? true) ? '—' : value!, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.emphasize = false});

  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(label, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(fontWeight: emphasize ? FontWeight.w700 : FontWeight.w400),
        ),
      ],
    );
  }
}

/// Shown for PARTIALLY_FULFILLED: what actually shipped versus what was
/// ordered, per line, so the shortfall is impossible to miss (this status must
/// never read like an ordinary dispatch).
class _PartialFulfilmentNote extends StatelessWidget {
  const _PartialFulfilmentNote({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = context.semanticColors;
    final short = [
      for (final item in order.items)
        if (item.quantityFulfilled < item.quantityOrdered) item,
    ];

    // Same 4px outer margin a Card carries, so it lines up with its neighbours.
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(AppSpacing.xs),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: semantic.warningContainer,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Partially fulfilled',
            style: theme.textTheme.titleSmall?.copyWith(color: semantic.onWarningContainer),
          ),
          Text(
            'Some lines shipped less than ordered. The shortfall was released back to available stock.',
            style: theme.textTheme.bodyMedium?.copyWith(color: semantic.onWarningContainer),
          ),
          for (final item in short)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                '${item.productName ?? item.productId}: shipped ${formatQuantity(item.quantityFulfilled)} of '
                '${formatQuantity(item.quantityOrdered)} '
                '(short ${formatQuantity(item.quantityOrdered - item.quantityFulfilled)})',
                style: theme.textTheme.bodyMedium?.copyWith(color: semantic.onWarningContainer),
              ),
            ),
        ],
      ),
    );
  }
}
