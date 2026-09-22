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
import '../data/dashboard_providers.dart';
import '../domain/dashboard_summary.dart';

/// STEP — WAREHOUSE DASHBOARD, the last placeholder nav item. Read-only
/// summary of `GET /dashboard` (`DashboardController`, gated `reports.view`):
/// KPI tiles, a low-stock preview, a pending-adjustments preview, a recent
/// activity feed, and a simple stock-movement bar list. Every number is a
/// DB-level aggregate the backend computed — nothing here recomputes stock.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final canView = ref.watch(authProvider.select((s) => s.value?.user?.can('reports.view') ?? false));
    if (!canView) {
      return const EmptyStateView(
        title: "You don't have permission to view the dashboard",
        message: 'Ask an administrator for the reports.view permission.',
        icon: Icons.lock_outline,
      );
    }

    final summaryAsync = ref.watch(dashboardSummaryProvider);

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(dashboardSummaryProvider),
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Row(
            children: [
              Expanded(child: Text('Dashboard', style: theme.textTheme.headlineSmall)),
              IconButton(
                tooltip: 'Refresh',
                icon: const Icon(Icons.refresh),
                onPressed: () => ref.invalidate(dashboardSummaryProvider),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          summaryAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.only(top: AppSpacing.xl),
              child: LoadingStateView(message: 'Loading dashboard…'),
            ),
            error: (error, stackTrace) => ErrorStateView(
              message: error is AppError ? error.message : 'Could not load the dashboard.',
              onRetry: () => ref.invalidate(dashboardSummaryProvider),
            ),
            data: (summary) => _DashboardBody(summary: summary),
          ),
        ],
      ),
    );
  }
}

class _DashboardBody extends StatelessWidget {
  const _DashboardBody({required this.summary});

  final DashboardSummary summary;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _KpiRow(summary: summary),
        const SizedBox(height: AppSpacing.lg),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 900;
            final lowStock = _LowStockCard(summary: summary.lowStock);
            final pending = _PendingAdjustmentsCard(summary: summary.pendingAdjustments);
            if (!wide) {
              return Column(
                children: [lowStock, const SizedBox(height: AppSpacing.lg), pending],
              );
            }
            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: lowStock),
                  const SizedBox(width: AppSpacing.lg),
                  Expanded(child: pending),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: AppSpacing.lg),
        _StockMovementCard(summary: summary.stockMovement),
        const SizedBox(height: AppSpacing.lg),
        _RecentActivityCard(activity: summary.stockMovement.recentActivity),
        const SizedBox(height: AppSpacing.lg),
        _OpenStockCountsCard(summary: summary.openStockCounts),
      ],
    );
  }
}

class _KpiRow extends StatelessWidget {
  const _KpiRow({required this.summary});

  final DashboardSummary summary;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.md,
      children: [
        _KpiCard(
          icon: Icons.inventory_2_outlined,
          label: 'Active products',
          value: '${summary.catalogue.activeProductCount}',
        ),
        _KpiCard(
          icon: Icons.warning_amber_outlined,
          label: 'Low stock',
          value: '${summary.lowStock.count}',
          tone: summary.lowStock.count > 0 ? StatusTone.warning : StatusTone.neutral,
        ),
        _KpiCard(
          icon: Icons.pending_actions_outlined,
          label: 'Pending adjustments',
          value: '${summary.pendingAdjustments.count}',
          tone: summary.pendingAdjustments.count > 0 ? StatusTone.warning : StatusTone.neutral,
        ),
        _KpiCard(
          icon: Icons.payments_outlined,
          label: 'Inventory valuation',
          value: summary.valuation.total.toStringAsFixed(2),
          subtitle: summary.valuation.excludedProductCount > 0
              ? '${summary.valuation.excludedProductCount} costed-missing product${summary.valuation.excludedProductCount == 1 ? '' : 's'} excluded'
              : null,
        ),
      ],
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.icon,
    required this.label,
    required this.value,
    this.subtitle,
    this.tone = StatusTone.neutral,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? subtitle;
  final StatusTone tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = context.semanticColors;
    final accent = switch (tone) {
      StatusTone.warning => semantic.warning,
      StatusTone.danger => theme.colorScheme.error,
      StatusTone.success => semantic.success,
      StatusTone.info => semantic.info,
      StatusTone.neutral => theme.colorScheme.primary,
    };

    return SizedBox(
      width: 220,
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: accent, size: 20),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    label,
                    style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(value, style: theme.textTheme.headlineMedium),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(
                subtitle!,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LowStockCard extends StatelessWidget {
  const _LowStockCard({required this.summary});

  final LowStockSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      title: 'Low stock',
      subtitle: summary.count == 0
          ? 'Nothing below its minimum level'
          : '${summary.count} product${summary.count == 1 ? '' : 's'} below minimum level',
      child: summary.items.isEmpty
          ? Text('All active products meet their minimum stock level.', style: theme.textTheme.bodySmall)
          : Column(
              children: [
                for (final item in summary.items)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('${item.name} (${item.sku})'),
                    subtitle: Text(
                      '${formatQuantity(item.onHand)} on hand · minimum ${formatQuantity(item.minStockLevel)}',
                    ),
                    trailing: StatusBadge(label: '−${formatQuantity(item.shortfall)}', tone: StatusTone.warning),
                    onTap: () => context.go('${RoutePaths.inventory}?productId=${item.productId}'),
                  ),
              ],
            ),
    );
  }
}

class _PendingAdjustmentsCard extends StatelessWidget {
  const _PendingAdjustmentsCard({required this.summary});

  final PendingAdjustmentsSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      title: 'Pending adjustments',
      subtitle: summary.count == 0
          ? 'Nothing waiting for review'
          : '${summary.count} waiting for review, oldest first',
      trailing: summary.count > 0
          ? TextButton(onPressed: () => context.go(RoutePaths.stockAdjustments), child: const Text('View queue'))
          : null,
      child: summary.items.isEmpty
          ? Text('No adjustment requests are pending approval.', style: theme.textTheme.bodySmall)
          : Column(
              children: [
                for (final item in summary.items)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('${item.productName} (${item.productSku})'),
                    subtitle: Text(
                      '${item.direction == 'INCREASE' ? '+' : '−'}${formatQuantity(item.delta)} '
                      '${item.bucket.toLowerCase().replaceAll('_', ' ')} at ${item.locationName} — ${item.reason}',
                    ),
                    trailing: StatusBadge(
                      label: item.waitingDays == 0 ? 'today' : '${item.waitingDays}d',
                      tone: item.waitingDays >= 3 ? StatusTone.danger : StatusTone.warning,
                    ),
                    onTap: () => context.go(RoutePaths.stockAdjustments),
                  ),
              ],
            ),
    );
  }
}

const _typeToneMap = {
  'RECEIVE': StatusTone.success,
  'RETURN': StatusTone.success,
  'DAMAGED': StatusTone.danger,
  'LOST': StatusTone.danger,
  'ADJUSTMENT': StatusTone.warning,
  'STOCK_COUNT': StatusTone.warning,
  'TRANSFER': StatusTone.info,
  'RESERVATION': StatusTone.info,
  'RELEASE_RESERVATION': StatusTone.info,
};

StatusTone _toneForType(String type) => _typeToneMap[type] ?? StatusTone.neutral;

class _StockMovementCard extends StatelessWidget {
  const _StockMovementCard({required this.summary});

  final StockMovementSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries = summary.byType.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final maxCount = entries.isEmpty ? 0 : entries.map((e) => e.value).reduce((a, b) => a > b ? a : b);

    return AppCard(
      title: 'Stock movement',
      subtitle: 'Transaction counts, last ${summary.periodDays} days',
      child: maxCount == 0
          ? Text('No inventory transactions in this period.', style: theme.textTheme.bodySmall)
          : Column(
              children: [
                for (final entry in entries)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 140,
                          child: Text(entry.key, style: theme.textTheme.bodySmall, overflow: TextOverflow.ellipsis),
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                            child: FractionallySizedBox(
                              alignment: Alignment.centerLeft,
                              widthFactor: maxCount == 0 ? 0 : entry.value / maxCount,
                              child: Container(
                                height: 10,
                                decoration: BoxDecoration(
                                  color: _toneColor(context, _toneForType(entry.key)),
                                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                                ),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 32,
                          child: Text(
                            '${entry.value}',
                            textAlign: TextAlign.right,
                            style: theme.textTheme.labelMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }

  Color _toneColor(BuildContext context, StatusTone tone) {
    final theme = Theme.of(context);
    final semantic = context.semanticColors;
    return switch (tone) {
      StatusTone.success => semantic.success,
      StatusTone.warning => semantic.warning,
      StatusTone.danger => theme.colorScheme.error,
      StatusTone.info => semantic.info,
      StatusTone.neutral => theme.colorScheme.onSurfaceVariant,
    };
  }
}

class _RecentActivityCard extends StatelessWidget {
  const _RecentActivityCard({required this.activity});

  final List<StockMovementActivity> activity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      title: 'Recent activity',
      subtitle: 'Most recent ledger transactions, regardless of period',
      child: activity.isEmpty
          ? Text('No inventory transactions yet.', style: theme.textTheme.bodySmall)
          : Column(
              children: [
                for (final a in activity)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: StatusBadge(label: a.type.replaceAll('_', ' '), tone: _toneForType(a.type)),
                    title: Text('${a.productName} (${a.productSku})'),
                    subtitle: Text(_movementSubtitle(a)),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(formatQuantity(a.quantity), style: theme.textTheme.labelLarge),
                        Text(
                          formatDateTime(a.createdAt),
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }

  String _movementSubtitle(StockMovementActivity a) {
    final where = [
      if (a.fromLocationLabel != null) 'from ${a.fromLocationLabel}',
      if (a.toLocationLabel != null) 'to ${a.toLocationLabel}',
    ].join(' ');
    final by = 'by ${a.performedByName}';
    return where.isEmpty ? by : '$where · $by';
  }
}

class _OpenStockCountsCard extends StatelessWidget {
  const _OpenStockCountsCard({required this.summary});

  final OpenStockCountsSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      child: InkWell(
        onTap: () => context.go(RoutePaths.stockCounts),
        child: Row(
          children: [
            Icon(Icons.fact_check_outlined, color: theme.colorScheme.primary),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                summary.count == 0
                    ? 'No stock counts currently open'
                    : '${summary.count} stock count${summary.count == 1 ? '' : 's'} currently open',
                style: theme.textTheme.bodyLarge,
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}
