import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/app_error.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/empty_loading_error_states.dart';
import '../data/dashboard_api.dart';

/// F2 proof-of-life for real authenticated calls: fetches `GET /dashboard`
/// through the wired-up [ApiClient] and renders the raw numbers. The
/// polished dashboard UI is a later phase.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(dashboardSummaryProvider);

    return summaryAsync.when(
      loading: () => const LoadingStateView(message: 'Loading dashboard…'),
      error: (error, stackTrace) => ErrorStateView(
        message: error is AppError ? error.message : 'Could not load the dashboard.',
        onRetry: () => ref.invalidate(dashboardSummaryProvider),
      ),
      data: (summary) => _DashboardContent(summary: summary),
    );
  }
}

class _DashboardContent extends StatelessWidget {
  const _DashboardContent({required this.summary});

  final Map<String, dynamic> summary;

  @override
  Widget build(BuildContext context) {
    final today = summary['today'] as Map<String, dynamic>? ?? const {};
    final thisWeek = summary['thisWeek'] as Map<String, dynamic>? ?? const {};
    final ordersByStatus = (summary['ordersByStatus'] as List?)?.cast<Map<String, dynamic>>() ?? const [];

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: [
            _StatCard(label: 'Low stock items', value: '${summary['lowStockCount'] ?? '—'}'),
            _StatCard(label: 'Pending adjustments', value: '${summary['pendingAdjustmentsCount'] ?? '—'}'),
            _StatCard(label: "Today's orders", value: '${today['orderCount'] ?? '—'}'),
            _StatCard(label: "Today's value", value: '${today['totalValue'] ?? '—'}'),
            _StatCard(label: "This week's orders", value: '${thisWeek['orderCount'] ?? '—'}'),
            _StatCard(label: "This week's value", value: '${thisWeek['totalValue'] ?? '—'}'),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        AppCard(
          title: 'Orders by status',
          child: ordersByStatus.isEmpty
              ? const Text('No orders yet.')
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final row in ordersByStatus)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs / 2),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('${row['status']}'),
                            Text('${row['count']} orders · ${row['totalValue']}'),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 200,
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: AppSpacing.xs),
            Text(value, style: theme.textTheme.headlineSmall),
          ],
        ),
      ),
    );
  }
}
