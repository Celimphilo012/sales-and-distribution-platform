import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/error/app_error.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../routing/route_paths.dart';
import '../../../shared/date_format.dart';
import '../../../shared/money_format.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_data_table.dart';
import '../../../shared/widgets/empty_loading_error_states.dart';
import '../../../shared/widgets/kpi_tile.dart';
import '../../../shared/widgets/status_badge.dart';
import '../../orders/domain/order.dart';
import '../../orders/presentation/order_status_tone.dart';
import '../../payments/domain/payment.dart';
import '../data/reports_api.dart';
import '../domain/reports.dart';

/// Reports (`reports.view`): orders (count, value, by status, every order in
/// the period) and money (collected by method, voided, and what customers
/// still owe). One period selector drives both tabs. Read-only.
class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  ReportPeriod _period = ReportPeriod.thisMonth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DefaultTabController(
      length: 2,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              alignment: WrapAlignment.spaceBetween,
              children: [
                Text('Reports', style: theme.textTheme.headlineSmall),
                SegmentedButton<ReportPeriod>(
                  showSelectedIcon: false,
                  segments: [for (final p in ReportPeriod.values) ButtonSegment(value: p, label: Text(p.label))],
                  selected: {_period},
                  onSelectionChanged: (s) => setState(() => _period = s.first),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            const TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                Tab(icon: Icon(Icons.receipt_long_outlined), text: 'Orders'),
                Tab(icon: Icon(Icons.payments_outlined), text: 'Payments'),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Expanded(
              child: TabBarView(
                children: [
                  _OrdersTab(period: _period),
                  _PaymentsTab(period: _period),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OrdersTab extends ConsumerWidget {
  const _OrdersTab({required this.period});

  final ReportPeriod period;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportAsync = ref.watch(ordersReportProvider(period));
    return reportAsync.when(
      loading: () => const LoadingStateView(message: 'Loading orders report…'),
      error: (error, _) => ErrorStateView(
        message: error is AppError ? error.message : 'Could not load the orders report.',
        onRetry: () => ref.invalidate(ordersReportProvider(period)),
      ),
      data: (report) {
        final live = report.byStatus.where(
          (b) => b.status != OrderStatus.rejected && b.status != OrderStatus.cancelled && b.status != OrderStatus.draft,
        );
        final liveValue = live.fold<double>(0, (sum, b) => sum + b.totalValue);
        return ListView(
          children: [
            KpiGrid(
              children: [
                KpiTile(
                  label: 'Orders',
                  value: '${report.count}',
                  icon: Icons.receipt_long_outlined,
                  detail: period.label,
                ),
                KpiTile(
                  label: 'Order value (all)',
                  value: formatMoney(report.totalValue),
                  icon: Icons.stacked_line_chart,
                  tone: StatusTone.info,
                ),
                KpiTile(
                  label: 'Order value (live)',
                  value: formatMoney(liveValue),
                  icon: Icons.task_alt,
                  tone: StatusTone.success,
                  detail: 'Excludes drafts, rejected and cancelled',
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            AppCard(
              title: 'By status',
              child: report.byStatus.isEmpty
                  ? const Text('No orders in this period.')
                  : _StatusBars(buckets: report.byStatus),
            ),
            const SizedBox(height: AppSpacing.md),
            AppCard(
              title: 'Orders in this period',
              child: AppDataTable<OrderSummaryRow>(
                rows: report.orders,
                emptyTitle: 'No orders in this period',
                onRowTap: (o) => context.go(RoutePaths.orderDetail(o.id)),
                columns: [
                  AppDataColumn(label: 'Order', cellBuilder: (o) => Text(o.orderNumber)),
                  AppDataColumn(label: 'Customer', cellBuilder: (o) => Text(o.customerName)),
                  AppDataColumn(label: 'Date', cellBuilder: (o) => Text(formatDateTime(o.orderDate))),
                  AppDataColumn(
                    label: 'Status',
                    cellBuilder: (o) => StatusBadge(label: o.status.label, tone: orderStatusTone(o.status)),
                  ),
                  AppDataColumn(
                    label: 'Payment',
                    cellBuilder: (o) =>
                        StatusBadge(label: o.paymentStatus.label, tone: paymentStatusTone(o.paymentStatus)),
                  ),
                  AppDataColumn(label: 'Total', numeric: true, cellBuilder: (o) => Text(formatMoney(o.total))),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// A horizontal bar per status, scaled to the largest count — no chart dependency.
class _StatusBars extends StatelessWidget {
  const _StatusBars({required this.buckets});

  final List<StatusBucket> buckets;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final max = buckets.map((b) => b.count).fold<int>(1, (a, b) => a > b ? a : b);
    return Column(
      children: [
        for (final b in buckets)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Row(
              children: [
                SizedBox(
                  width: 150,
                  child: StatusBadge(label: b.status.label, tone: orderStatusTone(b.status)),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                    child: LinearProgressIndicator(value: b.count / max, minHeight: 10),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                SizedBox(
                  width: 170,
                  child: Text(
                    '${b.count} · ${formatMoney(b.totalValue)}',
                    textAlign: TextAlign.right,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _PaymentsTab extends ConsumerWidget {
  const _PaymentsTab({required this.period});

  final ReportPeriod period;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final reportAsync = ref.watch(paymentsReportProvider(period));
    return reportAsync.when(
      loading: () => const LoadingStateView(message: 'Loading payments report…'),
      error: (error, _) => ErrorStateView(
        message: error is AppError ? error.message : 'Could not load the payments report.',
        onRetry: () => ref.invalidate(paymentsReportProvider(period)),
      ),
      data: (report) => ListView(
        children: [
          KpiGrid(
            children: [
              KpiTile(
                label: 'Collected',
                value: formatMoney(report.collectedAmount),
                icon: Icons.savings_outlined,
                tone: StatusTone.success,
                detail: '${report.collectedCount} payment${report.collectedCount == 1 ? '' : 's'} · ${period.label}',
              ),
              KpiTile(
                label: 'Still owed (all open orders)',
                value: formatMoney(report.outstandingAmount),
                icon: Icons.hourglass_bottom,
                tone: report.outstandingAmount > 0 ? StatusTone.warning : StatusTone.success,
                detail: '${report.outstandingCount} order${report.outstandingCount == 1 ? '' : 's'} with a balance',
              ),
              KpiTile(
                label: 'Voided',
                value: formatMoney(report.voidedAmount),
                icon: Icons.undo,
                tone: report.voidedCount > 0 ? StatusTone.danger : StatusTone.neutral,
                detail: '${report.voidedCount} payment${report.voidedCount == 1 ? '' : 's'} · ${period.label}',
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          AppCard(
            title: 'Collected by method',
            subtitle: period.label,
            child: report.byMethod.isEmpty
                ? const Text('No payments in this period.')
                : Column(
                    children: [
                      for (final m in report.byMethod)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                          child: Row(
                            children: [
                              SizedBox(width: 170, child: Text(m.method.label, style: theme.textTheme.bodyMedium)),
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                                  child: LinearProgressIndicator(
                                    value: report.collectedAmount <= 0 ? 0 : m.amount / report.collectedAmount,
                                    minHeight: 10,
                                  ),
                                ),
                              ),
                              const SizedBox(width: AppSpacing.md),
                              SizedBox(
                                width: 170,
                                child: Text(
                                  '${formatMoney(m.amount)} (${m.count})',
                                  textAlign: TextAlign.right,
                                  style: theme.textTheme.bodyMedium,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: AppSpacing.md),
          AppCard(
            title: 'Customers still owing',
            subtitle: 'Every open order with a balance due, largest first — not limited to the period.',
            child: AppDataTable<OrderSummaryRow>(
              rows: report.outstandingOrders,
              emptyTitle: 'Nothing owed',
              emptyMessage: 'Every open order is fully paid.',
              onRowTap: (o) => context.go(RoutePaths.orderDetail(o.id)),
              columns: [
                AppDataColumn(label: 'Order', cellBuilder: (o) => Text(o.orderNumber)),
                AppDataColumn(label: 'Customer', cellBuilder: (o) => Text(o.customerName)),
                AppDataColumn(
                  label: 'Status',
                  cellBuilder: (o) => StatusBadge(label: o.status.label, tone: orderStatusTone(o.status)),
                ),
                AppDataColumn(label: 'Total', numeric: true, cellBuilder: (o) => Text(formatMoney(o.total))),
                AppDataColumn(label: 'Paid', numeric: true, cellBuilder: (o) => Text(formatMoney(o.amountPaid ?? 0))),
                AppDataColumn(
                  label: 'Due',
                  numeric: true,
                  cellBuilder: (o) => Text(
                    formatMoney(o.balanceDue ?? 0),
                    style: TextStyle(color: theme.colorScheme.error, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
