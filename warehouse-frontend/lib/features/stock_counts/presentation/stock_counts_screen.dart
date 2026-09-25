import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/error/app_error.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../routing/route_paths.dart';
import '../../../shared/date_format.dart';
import '../../../shared/widgets/app_data_table.dart';
import '../../../shared/widgets/app_dialog.dart';
import '../../../shared/widgets/compact_row_list.dart';
import '../../../shared/widgets/empty_loading_error_states.dart';
import '../../../shared/widgets/simple_grid_view.dart';
import '../../../shared/widgets/stat_tile.dart';
import '../../../shared/widgets/status_badge.dart';
import '../../../shared/widgets/view_mode_toggle.dart';
import '../../locations/domain/location.dart';
import '../../locations/presentation/widgets/leaf_location_field.dart';
import '../data/stock_counts_providers.dart';
import '../domain/stock_count.dart';

/// STEP 6e-2 — STOCK COUNTS history + "start a count" entry point. A count
/// only snapshots `expected_qty` (`StockCountsService.create` — read-only
/// against `inventory_balances`); entering physical counts and submitting
/// happens on [StockCountDetailScreen]. List/table/grid + stats + compact,
/// matching the Products prototype.
class StockCountsScreen extends ConsumerStatefulWidget {
  const StockCountsScreen({super.key});

  @override
  ConsumerState<StockCountsScreen> createState() => _StockCountsScreenState();
}

class _StockCountsScreenState extends ConsumerState<StockCountsScreen> {
  ViewMode _view = ViewMode.table;

  @override
  Widget build(BuildContext context) {
    final canCount = ref.watch(authProvider.select((s) => s.value?.user?.can('inventory.count') ?? false));
    if (!canCount) {
      return const EmptyStateView(
        title: "You don't have permission to perform stock counts",
        message: 'Ask an administrator for the inventory.count permission.',
        icon: Icons.lock_outline,
      );
    }

    final theme = Theme.of(context);
    final countsAsync = ref.watch(stockCountsListProvider(null));

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('Stock Counts', style: theme.textTheme.headlineSmall)),
              FilledButton.icon(
                onPressed: () => _startCount(context, ref),
                icon: const Icon(Icons.playlist_add_check_outlined),
                label: const Text('Start count'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          countsAsync.maybeWhen(data: (counts) => _StockCountsStats(counts: counts), orElse: () => const SizedBox.shrink()),
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerRight,
            child: ViewModeToggle(value: _view, onChanged: (mode) => setState(() => _view = mode)),
          ),
          const SizedBox(height: AppSpacing.sm),
          Expanded(
            child: countsAsync.when(
              loading: () => const LoadingStateView(message: 'Loading stock counts…'),
              error: (error, stackTrace) => ErrorStateView(
                message: error is AppError ? error.message : 'Could not load stock counts.',
                onRetry: () => ref.invalidate(stockCountsListProvider(null)),
              ),
              data: (counts) => switch (_view) {
                ViewMode.table => _StockCountsTable(counts: counts),
                ViewMode.list => CompactRowList<StockCount>(
                    items: counts,
                    onTap: (c) => context.go(RoutePaths.stockCountDetail(c.id)),
                    emptyTitle: 'No stock counts yet',
                    emptyMessage: 'Start a count to snapshot expected quantities at a location.',
                    rowBuilder: (context, c) => Row(
                      children: [
                        Expanded(flex: 2, child: Text('${c.location.name} (${c.location.code})', overflow: TextOverflow.ellipsis)),
                        Expanded(child: Text('${c.items.length} items', style: theme.textTheme.bodySmall)),
                        Expanded(
                          flex: 2,
                          child: Text(
                            c.startedByUser.fullName,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(formatDateTime(c.startedAt), style: theme.textTheme.bodySmall),
                        ),
                        StatusBadge(
                          label: c.status.label,
                          tone: c.status == StockCountStatus.submitted ? StatusTone.success : StatusTone.info,
                        ),
                      ],
                    ),
                  ),
                ViewMode.grid => SimpleGridView<StockCount>(
                    items: counts,
                    onTap: (c) => context.go(RoutePaths.stockCountDetail(c.id)),
                    emptyTitle: 'No stock counts yet',
                    emptyMessage: 'Start a count to snapshot expected quantities at a location.',
                    maxCrossAxisExtent: 220,
                    childAspectRatio: 1.3,
                    contentBuilder: (context, c) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.playlist_add_check_outlined, size: 18, color: theme.colorScheme.primary),
                            const SizedBox(width: AppSpacing.xs),
                            Expanded(
                              child: Text(
                                '${c.location.name} (${c.location.code})',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${c.items.length} items · ${c.startedByUser.fullName}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                        Text(formatDateTime(c.startedAt), style: theme.textTheme.bodySmall),
                        const SizedBox(height: AppSpacing.xs),
                        StatusBadge(
                          label: c.status.label,
                          tone: c.status == StockCountStatus.submitted ? StatusTone.success : StatusTone.info,
                        ),
                      ],
                    ),
                  ),
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _startCount(BuildContext context, WidgetRef ref) async {
    final started = await AppDialog.show<StockCount>(
      context,
      title: 'Start a stock count',
      content: const _StartCountForm(),
    );
    if (started != null && context.mounted) {
      ref.invalidate(stockCountsListProvider(null));
      context.go(RoutePaths.stockCountDetail(started.id));
    }
  }
}

class _StartCountForm extends ConsumerStatefulWidget {
  const _StartCountForm();

  @override
  ConsumerState<_StartCountForm> createState() => _StartCountFormState();
}

class _StartCountFormState extends ConsumerState<_StartCountForm> {
  Location? _location;
  bool _saving = false;
  String? _errorMessage;

  Future<void> _submit() async {
    if (_location == null) {
      setState(() => _errorMessage = 'Choose a location.');
      return;
    }
    setState(() {
      _saving = true;
      _errorMessage = null;
    });
    try {
      final count = await ref.read(stockCountsApiProvider).start(locationId: _location!.id);
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop(count);
    } on AppError catch (e) {
      setState(() => _errorMessage = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Snapshots the current on-hand quantity for every product with a balance at the chosen location. '
          'Only a LEAF location can be counted.',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpacing.md),
        LeafLocationField(label: 'Location', value: _location, onChanged: (l) => setState(() => _location = l)),
        if (_errorMessage != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(_errorMessage!, style: TextStyle(color: theme.colorScheme.error)),
        ],
        const SizedBox(height: AppSpacing.lg),
        Align(
          alignment: Alignment.centerRight,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: AppSpacing.sm),
              FilledButton(
                onPressed: _saving ? null : _submit,
                child: _saving
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Start'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StockCountsStats extends StatelessWidget {
  const _StockCountsStats({required this.counts});

  final List<StockCount> counts;

  @override
  Widget build(BuildContext context) {
    final submitted = counts.where((c) => c.status == StockCountStatus.submitted).length;
    final inProgress = counts.length - submitted;

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xs,
      children: [
        StatTile(label: 'counts', value: '${counts.length}', icon: Icons.playlist_add_check_outlined),
        StatTile(label: 'submitted', value: '$submitted', tone: StatusTone.success, icon: Icons.check_circle_outline),
        if (inProgress > 0)
          StatTile(label: 'in progress', value: '$inProgress', tone: StatusTone.info, icon: Icons.pending_outlined),
      ],
    );
  }
}

class _StockCountsTable extends StatelessWidget {
  const _StockCountsTable({required this.counts});

  final List<StockCount> counts;

  @override
  Widget build(BuildContext context) {
    return AppDataTable<StockCount>(
      rows: counts,
      emptyTitle: 'No stock counts yet',
      emptyMessage: 'Start a count to snapshot expected quantities at a location.',
      onRowTap: (count) => context.go(RoutePaths.stockCountDetail(count.id)),
      columns: [
        AppDataColumn(
          label: 'Location',
          cellBuilder: (c) => Text('${c.location.name} (${c.location.code})'),
        ),
        AppDataColumn(label: 'Items', numeric: true, cellBuilder: (c) => Text('${c.items.length}')),
        AppDataColumn(label: 'Started by', cellBuilder: (c) => Text(c.startedByUser.fullName)),
        AppDataColumn(label: 'Started', cellBuilder: (c) => Text(formatDateTime(c.startedAt))),
        AppDataColumn(
          label: 'Status',
          cellBuilder: (c) => StatusBadge(
            label: c.status.label,
            tone: c.status == StockCountStatus.submitted ? StatusTone.success : StatusTone.info,
          ),
        ),
      ],
    );
  }
}
