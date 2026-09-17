import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/error/app_error.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../routing/route_paths.dart';
import '../../../shared/widgets/app_data_table.dart';
import '../../../shared/widgets/empty_loading_error_states.dart';
import '../../../shared/widgets/status_badge.dart';
import '../data/warehouses_providers.dart';
import '../domain/warehouse.dart';
import 'warehouse_form_dialog.dart';

/// Warehouses list — search-free (there's rarely more than a handful) plus
/// an active/inactive toggle, a permission-gated "New warehouse" dialog, and
/// a row tap that opens that warehouse's structure view.
class WarehousesListScreen extends ConsumerStatefulWidget {
  const WarehousesListScreen({super.key});

  @override
  ConsumerState<WarehousesListScreen> createState() => _WarehousesListScreenState();
}

class _WarehousesListScreenState extends ConsumerState<WarehousesListScreen> {
  bool _includeInactive = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canManage = ref.watch(
      authProvider.select((s) => s.value?.user?.can('warehouse.structure.manage') ?? false),
    );
    final warehousesAsync = ref.watch(warehousesProvider(_includeInactive));

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('Warehouses', style: theme.textTheme.headlineSmall)),
              if (canManage)
                FilledButton.icon(
                  onPressed: () => showWarehouseFormDialog(context),
                  icon: const Icon(Icons.add),
                  label: const Text('New warehouse'),
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
            child: warehousesAsync.when(
              loading: () => const LoadingStateView(message: 'Loading warehouses…'),
              error: (error, stackTrace) => ErrorStateView(
                message: error is AppError ? error.message : 'Could not load warehouses.',
                onRetry: () => ref.invalidate(warehousesProvider(_includeInactive)),
              ),
              data: (warehouses) => AppDataTable<Warehouse>(
                rows: warehouses,
                emptyTitle: 'No warehouses yet',
                onRowTap: (warehouse) =>
                    context.go('${RoutePaths.locations}?warehouseId=${warehouse.id}'),
                columns: [
                  AppDataColumn(label: 'Name', cellBuilder: (w) => Text(w.name)),
                  AppDataColumn(label: 'Code', cellBuilder: (w) => Text(w.code)),
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
                      cellBuilder: (w) => IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        tooltip: 'Edit',
                        onPressed: () => showWarehouseFormDialog(context, warehouse: w),
                      ),
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
