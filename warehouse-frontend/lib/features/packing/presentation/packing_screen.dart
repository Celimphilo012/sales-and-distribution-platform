import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/app_error.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/date_format.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/empty_loading_error_states.dart';
import '../../../shared/widgets/status_badge.dart';
import '../data/packing_api.dart';
import '../domain/packing_order.dart';

/// "What do I pack?" — every open order (stock reserved, not yet dispatched),
/// oldest first, showing only the items this person handles: their
/// warehouses, and their workstreams if they manage specific ones. Read-only;
/// dispatching still happens in the ordering system.
class PackingScreen extends ConsumerWidget {
  const PackingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final ordersAsync = ref.watch(packingOrdersProvider);

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('Packing', style: theme.textTheme.headlineSmall)),
              IconButton(
                tooltip: 'Refresh',
                icon: const Icon(Icons.refresh),
                onPressed: () => ref.invalidate(packingOrdersProvider),
              ),
            ],
          ),
          Text(
            'Open orders with the items you handle, oldest first. An order leaves this list once it is dispatched.',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: ordersAsync.when(
              loading: () => const LoadingStateView(message: 'Loading open orders…'),
              error: (error, _) => ErrorStateView(
                message: error is AppError ? error.message : 'Could not load the packing list.',
                onRetry: () => ref.invalidate(packingOrdersProvider),
              ),
              data: (orders) => orders.isEmpty
                  ? const EmptyStateView(
                      title: 'Nothing to pack',
                      message: 'No open orders include items from your warehouses or workstreams.',
                      icon: Icons.inventory_2_outlined,
                    )
                  : RefreshIndicator(
                      onRefresh: () => ref.refresh(packingOrdersProvider.future),
                      child: ListView.separated(
                        itemCount: orders.length,
                        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
                        itemBuilder: (context, i) => _OrderCard(order: orders[i]),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order});

  final PackingOrder order;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final others = order.totalLineCount - order.lines.length;

    return AppCard(
      title: order.title,
      subtitle: 'Reserved ${formatDateTime(order.reservedAt)}',
      trailing: StatusBadge(
        label: '${order.lines.length} of ${order.totalLineCount} item${order.totalLineCount == 1 ? '' : 's'}',
        tone: others == 0 ? StatusTone.success : StatusTone.info,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final line in order.lines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 72,
                    child: Text(
                      '${_qty(line.quantity)} ${line.uom}',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(line.productName, style: theme.textTheme.bodyMedium),
                        Text(
                          '${line.sku} · pick from ${line.location.name} (${line.location.code}), ${line.warehouse.name}',
                          style: muted,
                        ),
                      ],
                    ),
                  ),
                  StatusBadge(label: line.workstream.name, tone: StatusTone.neutral),
                ],
              ),
            ),
          if (others > 0) ...[
            const Divider(),
            Text(
              '$others more item${others == 1 ? '' : 's'} in this order ${others == 1 ? 'is' : 'are'} packed by other workstreams.',
              style: muted,
            ),
          ],
        ],
      ),
    );
  }

  static String _qty(double q) => q == q.roundToDouble() ? q.toStringAsFixed(0) : q.toString();
}
