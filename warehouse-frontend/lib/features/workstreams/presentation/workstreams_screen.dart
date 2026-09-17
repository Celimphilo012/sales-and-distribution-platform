import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/error/app_error.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/app_data_table.dart';
import '../../../shared/widgets/empty_loading_error_states.dart';
import '../../../shared/widgets/status_badge.dart';
import '../../warehouses/data/warehouses_providers.dart';
import '../data/workstreams_providers.dart';
import '../domain/workstream.dart';
import 'workstream_form_dialog.dart';

/// Workstreams management — a catalogue-organization layer (Warehouse ->
/// Workstream -> Category -> sub-category -> Product), purely reference
/// data: create/edit/deactivate here, never anything operational. Gated the
/// same way as Categories: visible with `catalogue.view`, manage actions
/// need `products.manage`.
class WorkstreamsScreen extends ConsumerStatefulWidget {
  const WorkstreamsScreen({super.key});

  @override
  ConsumerState<WorkstreamsScreen> createState() => _WorkstreamsScreenState();
}

class _WorkstreamsScreenState extends ConsumerState<WorkstreamsScreen> {
  bool _includeInactive = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canManage = ref.watch(authProvider.select((s) => s.value?.user?.can('products.manage') ?? false));
    final workstreamsAsync = ref.watch(workstreamsProvider(_includeInactive));
    final warehousesAsync = ref.watch(warehousesProvider(true));

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('Workstreams', style: theme.textTheme.headlineSmall)),
              if (canManage)
                FilledButton.icon(
                  onPressed: () => showWorkstreamFormDialog(context),
                  icon: const Icon(Icons.add),
                  label: const Text('New workstream'),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          FilterChip(
            label: const Text('Show inactive'),
            selected: _includeInactive,
            onSelected: (value) => setState(() => _includeInactive = value),
          ),
          const SizedBox(height: AppSpacing.lg),
          Expanded(
            child: workstreamsAsync.when(
              loading: () => const LoadingStateView(message: 'Loading workstreams…'),
              error: (error, stackTrace) => ErrorStateView(
                message: error is AppError ? error.message : 'Could not load workstreams.',
                onRetry: () => ref.invalidate(workstreamsProvider(_includeInactive)),
              ),
              data: (workstreams) {
                final warehouseNames = {
                  for (final w in warehousesAsync.value ?? const []) w.id: w.name,
                };
                return AppDataTable<Workstream>(
                  rows: workstreams,
                  emptyTitle: 'No workstreams yet',
                  columns: [
                    AppDataColumn(label: 'Name', cellBuilder: (w) => Text(w.name)),
                    AppDataColumn(label: 'Code', cellBuilder: (w) => Text(w.code)),
                    AppDataColumn(
                      label: 'Warehouse',
                      cellBuilder: (w) => Text(warehouseNames[w.warehouseId] ?? w.warehouseId),
                    ),
                    AppDataColumn(
                      label: 'Status',
                      cellBuilder: (w) => StatusBadge(
                        label: w.isActive ? 'Active' : 'Inactive',
                        tone: w.isActive ? StatusTone.success : StatusTone.neutral,
                      ),
                    ),
                    if (canManage)
                      AppDataColumn(
                        label: '',
                        cellBuilder: (w) => Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_outlined),
                              tooltip: 'Edit',
                              onPressed: () => showWorkstreamFormDialog(context, workstream: w),
                            ),
                            if (w.isActive)
                              IconButton(
                                icon: const Icon(Icons.block),
                                tooltip: 'Deactivate',
                                onPressed: () => _deactivate(context, w),
                              )
                            else
                              IconButton(
                                icon: const Icon(Icons.check_circle_outline),
                                tooltip: 'Reactivate',
                                onPressed: () => _reactivate(context, w),
                              ),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _deactivate(BuildContext context, Workstream workstream) async {
    try {
      await ref.read(workstreamsApiProvider).deactivate(workstream.id);
      invalidateWorkstreams(ref);
    } on AppError catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _reactivate(BuildContext context, Workstream workstream) async {
    try {
      await ref.read(workstreamsApiProvider).reactivate(workstream.id);
      invalidateWorkstreams(ref);
    } on AppError catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}
