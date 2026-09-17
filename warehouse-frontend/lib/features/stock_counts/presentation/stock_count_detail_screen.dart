import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/error/app_error.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../routing/route_paths.dart';
import '../../../shared/date_format.dart';
import '../../../shared/quantity_format.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_number_field.dart';
import '../../../shared/widgets/empty_loading_error_states.dart';
import '../../../shared/widgets/status_badge.dart';
import '../../stock_adjustments/data/stock_adjustments_providers.dart';
import '../../stock_adjustments/domain/stock_adjustment.dart';
import '../../stock_adjustments/presentation/widgets/adjustment_summary_tile.dart';
import '../data/stock_counts_api.dart';
import '../data/stock_counts_providers.dart';
import '../domain/stock_count.dart';

/// One count's working screen: while OPEN, enter counted quantities against
/// the expected-qty snapshot and submit (§ spec step 2-3); once SUBMITTED,
/// a read-only record of what was counted plus the adjustments that count
/// created (matched by `StockAdjustment.reference == count.id`, since
/// `createdAdjustmentIds` is only present on the submit response itself, not
/// on a later `GET`).
class StockCountDetailScreen extends ConsumerWidget {
  const StockCountDetailScreen({super.key, required this.countId});

  final String countId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canCount = ref.watch(authProvider.select((s) => s.value?.user?.can('inventory.count') ?? false));
    if (!canCount) {
      return const EmptyStateView(
        title: "You don't have permission to perform stock counts",
        icon: Icons.lock_outline,
      );
    }

    final theme = Theme.of(context);
    final countAsync = ref.watch(stockCountProvider(countId));

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => context.go(RoutePaths.stockCounts),
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Back to Stock Counts',
              ),
              Text('Stock Count', style: theme.textTheme.headlineSmall),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: countAsync.when(
              loading: () => const LoadingStateView(message: 'Loading count…'),
              error: (error, stackTrace) => ErrorStateView(
                message: error is AppError ? error.message : 'Could not load this count.',
                onRetry: () => ref.invalidate(stockCountProvider(countId)),
              ),
              data: (count) => count.status == StockCountStatus.open
                  ? _OpenCountBody(count: count)
                  : _SubmittedCountBody(count: count),
            ),
          ),
        ],
      ),
    );
  }
}

class _OpenCountBody extends ConsumerStatefulWidget {
  const _OpenCountBody({required this.count});

  final StockCount count;

  @override
  ConsumerState<_OpenCountBody> createState() => _OpenCountBodyState();
}

class _OpenCountBodyState extends ConsumerState<_OpenCountBody> {
  late final Map<String, TextEditingController> _controllers;
  bool _submitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // Prefilled with expectedQty so an unmodified line submits as "no
    // variance" — staff only need to edit the lines that actually differ.
    _controllers = {
      for (final item in widget.count.items)
        item.productId: TextEditingController(text: formatQuantity(item.expectedQty)),
    };
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  double? _countedFor(StockCountItem item) => double.tryParse(_controllers[item.productId]!.text.trim());

  Future<void> _submit() async {
    final items = <SubmitCountItem>[];
    for (final item in widget.count.items) {
      final counted = _countedFor(item);
      if (counted == null || counted < 0) {
        setState(() => _errorMessage = 'Enter a valid counted quantity for ${item.product.name}.');
        return;
      }
      items.add(SubmitCountItem(productId: item.productId, countedQty: counted));
    }

    setState(() {
      _submitting = true;
      _errorMessage = null;
    });
    try {
      final result = await ref.read(stockCountsApiProvider).submit(widget.count.id, items: items);
      ref.invalidate(stockCountProvider(widget.count.id));
      ref.invalidate(stockCountsListProvider(null));
      ref.invalidate(stockAdjustmentsListProvider(null));
      final createdCount = result.createdAdjustmentIds?.length ?? 0;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            createdCount == 0
                ? 'Count submitted — no variances found, nothing to approve.'
                : 'Count submitted — $createdCount variance${createdCount == 1 ? '' : 's'} found → '
                      '$createdCount adjustment${createdCount == 1 ? '' : 's'} created, pending approval.',
          ),
        ),
      );
    } on AppError catch (e) {
      setState(() => _errorMessage = e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppCard(
          title: '${widget.count.location.name} (${widget.count.location.code})',
          subtitle: 'Started by ${widget.count.startedByUser.fullName} · ${widget.count.items.length} item(s)',
          child: Text(
            'Enter the physically counted quantity for each product. Submitting does not move stock — a '
            'nonzero variance creates a PENDING adjustment that a manager must approve before stock moves.',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Expanded(
          child: ListView.separated(
            itemCount: widget.count.items.length,
            separatorBuilder: (context, index) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, index) {
              final item = widget.count.items[index];
              return AppCard(
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.product.name, style: theme.textTheme.bodyMedium),
                          Text(
                            item.product.sku,
                            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'Expected',
                            style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                          ),
                          Text(formatQuantity(item.expectedQty), style: theme.textTheme.titleMedium),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    SizedBox(
                      width: 130,
                      child: AppNumberField(
                        label: 'Counted',
                        controller: _controllers[item.productId],
                        allowDecimal: true,
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    SizedBox(
                      width: 90,
                      child: _VarianceLabel(expected: item.expectedQty, counted: _countedFor(item)),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(_errorMessage!, style: TextStyle(color: theme.colorScheme.error)),
        ],
        const SizedBox(height: AppSpacing.md),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: _submitting ? null : _submit,
            icon: _submitting
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: theme.colorScheme.onPrimary),
                  )
                : const Icon(Icons.check_circle_outline),
            label: Text(_submitting ? 'Submitting…' : 'Submit count'),
          ),
        ),
      ],
    );
  }
}

class _VarianceLabel extends StatelessWidget {
  const _VarianceLabel({required this.expected, required this.counted});

  final double expected;
  final double? counted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (counted == null) {
      return Text('—', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant));
    }
    final variance = counted! - expected;
    if (variance == 0) {
      return Text(
        'No variance',
        textAlign: TextAlign.end,
        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      );
    }
    final sign = variance > 0 ? '+' : '';
    return Text(
      '$sign${formatQuantity(variance)}',
      textAlign: TextAlign.end,
      style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.error, fontWeight: FontWeight.w700),
    );
  }
}

class _SubmittedCountBody extends ConsumerWidget {
  const _SubmittedCountBody({required this.count});

  final StockCount count;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final adjustmentsAsync = ref.watch(stockAdjustmentsListProvider(null));

    return ListView(
      children: [
        AppCard(
          title: '${count.location.name} (${count.location.code})',
          subtitle: 'Started by ${count.startedByUser.fullName} at ${formatDateTime(count.startedAt)}'
              '${count.submittedAt != null ? ' · submitted ${formatDateTime(count.submittedAt!)}' : ''}',
          child: const Align(
            alignment: Alignment.centerLeft,
            child: StatusBadge(label: 'Submitted', tone: StatusTone.success),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text('Counted items', style: theme.textTheme.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        for (final item in count.items) ...[
          AppCard(
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.product.name, style: theme.textTheme.bodyMedium),
                      Text(
                        item.product.sku,
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                _Stat(label: 'Expected', value: formatQuantity(item.expectedQty)),
                const SizedBox(width: AppSpacing.lg),
                _Stat(label: 'Counted', value: item.countedQty == null ? '—' : formatQuantity(item.countedQty!)),
                const SizedBox(width: AppSpacing.lg),
                _Stat(
                  label: 'Variance',
                  value: (item.difference == null || item.difference == 0) ? '0' : formatQuantity(item.difference!),
                  color: (item.difference != null && item.difference != 0) ? theme.colorScheme.error : null,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        const SizedBox(height: AppSpacing.md),
        Text('Adjustments created from this count', style: theme.textTheme.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        adjustmentsAsync.when(
          loading: () => const LoadingStateView(),
          error: (error, stackTrace) => Text(
            error is AppError ? error.message : 'Could not load adjustments.',
            style: TextStyle(color: theme.colorScheme.error),
          ),
          data: (adjustments) {
            final List<StockAdjustment> related = adjustments.where((a) => a.reference == count.id).toList();
            if (related.isEmpty) {
              return Text(
                'No variances were found — nothing to approve.',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              );
            }
            return Column(
              children: [
                for (final adjustment in related) ...[
                  AdjustmentSummaryTile(adjustment: adjustment),
                  const SizedBox(height: AppSpacing.sm),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(label, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        Text(value, style: theme.textTheme.titleMedium?.copyWith(color: color)),
      ],
    );
  }
}
