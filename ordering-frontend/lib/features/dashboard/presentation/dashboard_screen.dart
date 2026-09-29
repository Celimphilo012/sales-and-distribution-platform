import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/app_user.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/error/app_error.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../routing/route_paths.dart';
import '../../../shared/date_format.dart';
import '../../../shared/money_format.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/empty_loading_error_states.dart';
import '../../../shared/widgets/kpi_tile.dart';
import '../../../shared/widgets/status_badge.dart';
import '../../orders/data/orders_providers.dart';
import '../../orders/domain/order.dart';
import '../../orders/presentation/order_status_tone.dart';
import '../../reports/data/reports_api.dart';
import '../../reports/domain/reports.dart';

/// The home screen. Holders of `reports.view` get the manager dashboard —
/// orders and money today / this week, what is awaiting approval, what
/// customers still owe, orders by status and the latest orders (all SQL
/// aggregates from `GET /dashboard`). Everyone else gets their own latest
/// orders (`GET /orders` is already scoped to "mine" server-side).
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider.select((s) => s.value?.user));
    if (user == null) return const SizedBox.shrink();

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        _Greeting(user: user),
        const SizedBox(height: AppSpacing.lg),
        if (user.can('reports.view')) const _ManagerDashboard() else _PersonalDashboard(user: user),
      ],
    );
  }
}

class _Greeting extends StatelessWidget {
  const _Greeting({required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hour = DateTime.now().hour;
    final part = hour < 12 ? 'morning' : (hour < 17 ? 'afternoon' : 'evening');
    final first = user.name.split(' ').first;

    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      alignment: WrapAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Good $part, $first', style: theme.textTheme.headlineSmall),
            Text(
              formatDateTime(DateTime.now()).substring(0, 10),
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
        if (user.can('orders.create'))
          FilledButton.icon(
            onPressed: () => context.go(RoutePaths.orderNew),
            icon: const Icon(Icons.add),
            label: const Text('New order'),
          ),
      ],
    );
  }
}

class _ManagerDashboard extends ConsumerWidget {
  const _ManagerDashboard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboardAsync = ref.watch(dashboardProvider);

    return dashboardAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(AppSpacing.xl),
        child: LoadingStateView(message: 'Loading dashboard…'),
      ),
      error: (error, _) => ErrorStateView(
        message: error is AppError ? error.message : 'Could not load the dashboard.',
        onRetry: () => ref.invalidate(dashboardProvider),
      ),
      data: (d) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          KpiGrid(
            children: [
              KpiTile(
                label: 'Awaiting approval',
                value: '${d.awaitingApproval}',
                icon: Icons.pending_actions_outlined,
                tone: d.awaitingApproval > 0 ? StatusTone.warning : StatusTone.success,
                detail: d.awaitingApproval > 0 ? 'Tap to review' : 'Nothing waiting',
                onTap: () {
                  ref.read(ordersStatusFilterProvider.notifier).set(OrderStatus.pendingApproval);
                  context.go(RoutePaths.orders);
                },
              ),
              KpiTile(
                label: 'Orders today',
                value: '${d.todayCount}',
                icon: Icons.today_outlined,
                tone: StatusTone.info,
                detail: formatMoney(d.todayValue),
              ),
              KpiTile(
                label: 'Orders this week',
                value: '${d.weekCount}',
                icon: Icons.date_range_outlined,
                tone: StatusTone.info,
                detail: formatMoney(d.weekValue),
              ),
              KpiTile(
                label: 'Collected today',
                value: formatMoney(d.todayCollected),
                icon: Icons.savings_outlined,
                tone: StatusTone.success,
                detail: 'This week: ${formatMoney(d.weekCollected)}',
              ),
              KpiTile(
                label: 'Still owed',
                value: formatMoney(d.outstandingAmount),
                icon: Icons.hourglass_bottom,
                tone: d.outstandingAmount > 0 ? StatusTone.warning : StatusTone.success,
                detail: '${d.outstandingCount} order${d.outstandingCount == 1 ? '' : 's'} with a balance',
                onTap: () => context.go(RoutePaths.reports),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          LayoutBuilder(
            builder: (context, constraints) {
              final status = AppCard(
                title: 'Orders by status',
                child: _StatusList(buckets: d.byStatus),
              );
              final recent = AppCard(
                title: 'Latest orders',
                trailing: TextButton(onPressed: () => context.go(RoutePaths.orders), child: const Text('All orders')),
                child: _RecentOrders(rows: d.recentOrders),
              );
              if (constraints.maxWidth < 900) {
                return Column(
                  children: [
                    recent,
                    const SizedBox(height: AppSpacing.md),
                    status,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: recent),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(flex: 2, child: status),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _StatusList extends StatelessWidget {
  const _StatusList({required this.buckets});

  final List<StatusBucket> buckets;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (buckets.isEmpty) return const Text('No orders yet.');
    final max = buckets.map((b) => b.count).fold<int>(1, (a, b) => a > b ? a : b);
    return Column(
      children: [
        for (final b in buckets)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    StatusBadge(label: b.status.label, tone: orderStatusTone(b.status)),
                    const Spacer(),
                    Text('${b.count} · ${formatMoney(b.totalValue)}', style: theme.textTheme.bodySmall),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  child: LinearProgressIndicator(value: b.count / max, minHeight: 6),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _RecentOrders extends StatelessWidget {
  const _RecentOrders({required this.rows});

  final List<OrderSummaryRow> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (rows.isEmpty) return const Text('No orders yet.');
    return Column(
      children: [
        for (final o in rows)
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            onTap: () => context.go(RoutePaths.orderDetail(o.id)),
            title: Text('${o.orderNumber} · ${o.customerName}', maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(formatDateTime(o.orderDate), style: theme.textTheme.bodySmall),
            trailing: Wrap(
              spacing: AppSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                StatusBadge(label: o.status.label, tone: orderStatusTone(o.status)),
                StatusBadge(label: o.paymentStatus.label, tone: paymentStatusTone(o.paymentStatus)),
                SizedBox(width: 96, child: Text(formatMoney(o.total), textAlign: TextAlign.right)),
              ],
            ),
          ),
      ],
    );
  }
}

/// `GET /orders` — the server scopes it to the caller's own orders unless they hold orders.view_team.
final _myOrdersProvider = FutureProvider.autoDispose<List<Order>>((ref) async {
  final orders = await ref.watch(ordersApiProvider).list();
  return orders.take(8).toList();
});

class _PersonalDashboard extends ConsumerWidget {
  const _PersonalDashboard({required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    if (!user.can('orders.view_own')) {
      return AppCard(
        title: 'Welcome',
        child: Text('Use the menu to get to your work.', style: theme.textTheme.bodyMedium),
      );
    }
    final ordersAsync = ref.watch(_myOrdersProvider);
    return AppCard(
      title: 'My latest orders',
      trailing: TextButton(onPressed: () => context.go(RoutePaths.orders), child: const Text('All my orders')),
      child: ordersAsync.when(
        loading: () => const LinearProgressIndicator(),
        error: (error, _) => Text(error is AppError ? error.message : 'Could not load your orders.'),
        data: (orders) => _RecentOrders(
          rows: [
            for (final o in orders)
              OrderSummaryRow(
                id: o.id,
                orderNumber: o.orderNumber,
                status: o.status,
                paymentStatus: o.paymentStatus,
                orderDate: o.orderDate,
                total: o.total,
                customerName: o.customer.name,
              ),
          ],
        ),
      ),
    );
  }
}
