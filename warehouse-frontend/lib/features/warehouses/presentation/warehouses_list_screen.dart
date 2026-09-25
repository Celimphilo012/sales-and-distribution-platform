import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/error/app_error.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../routing/route_paths.dart';
import '../../../shared/widgets/app_data_table.dart';
import '../../../shared/widgets/app_dialog.dart';
import '../../../shared/widgets/compact_row_list.dart';
import '../../../shared/widgets/empty_loading_error_states.dart';
import '../../../shared/widgets/simple_grid_view.dart';
import '../../../shared/widgets/stat_tile.dart';
import '../../../shared/widgets/status_badge.dart';
import '../../../shared/widgets/view_mode_toggle.dart';
import '../data/warehouses_providers.dart';
import '../domain/warehouse.dart';
import 'warehouse_form_dialog.dart';

/// Warehouses list — search-free (there's rarely more than a handful) plus
/// an active/inactive toggle, a permission-gated "New warehouse" dialog, and
/// a row tap that opens that warehouse's structure view. List/table/grid +
/// stats + compact, matching the Products prototype.
class WarehousesListScreen extends ConsumerStatefulWidget {
  const WarehousesListScreen({super.key});

  @override
  ConsumerState<WarehousesListScreen> createState() => _WarehousesListScreenState();
}

class _WarehousesListScreenState extends ConsumerState<WarehousesListScreen> {
  bool _includeInactive = false;
  ViewMode _view = ViewMode.table;

  // Warehouses are soft-deleted (CLAUDE.md rule 10): locations and the stock
  // ledger reference them historically, so the only "delete" is deactivate.
  Future<void> _deactivate(Warehouse warehouse) async {
    final confirmed = await ConfirmDialog.show(
      context,
      title: 'Deactivate warehouse?',
      message:
          'This marks "${warehouse.name}" (${warehouse.code}) inactive and hides it from the '
          'warehouse pickers. Its locations and stock history are kept — nothing is deleted, and '
          'you can reactivate it later from "Show inactive".',
      confirmLabel: 'Deactivate',
      isDestructive: true,
    );
    if (!confirmed) return;
    await _run(() => ref.read(warehousesApiProvider).deactivate(warehouse.id), 'Warehouse deactivated');
  }

  Future<void> _reactivate(Warehouse warehouse) =>
      _run(() => ref.read(warehousesApiProvider).reactivate(warehouse.id), 'Warehouse reactivated');

  Future<void> _run(Future<void> Function() action, String successMessage) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      invalidateWarehouses(ref);
      messenger.showSnackBar(SnackBar(content: Text(successMessage)));
    } on AppError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  void _open(Warehouse warehouse) => context.go('${RoutePaths.locations}?warehouseId=${warehouse.id}');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canManage = ref.watch(
      authProvider.select((s) => s.value?.user?.can('warehouse.structure.manage') ?? false),
    );
    final warehousesAsync = ref.watch(warehousesProvider(_includeInactive));

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
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
          const SizedBox(height: AppSpacing.sm),
          warehousesAsync.maybeWhen(
            data: (warehouses) => _WarehousesStats(warehouses: warehouses),
            orElse: () => const SizedBox.shrink(),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              FilterChip(
                label: const Text('Show inactive'),
                selected: _includeInactive,
                onSelected: (value) => setState(() => _includeInactive = value),
              ),
              const Spacer(),
              ViewModeToggle(value: _view, onChanged: (mode) => setState(() => _view = mode)),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Expanded(
            child: warehousesAsync.when(
              loading: () => const LoadingStateView(message: 'Loading warehouses…'),
              error: (error, stackTrace) => ErrorStateView(
                message: error is AppError ? error.message : 'Could not load warehouses.',
                onRetry: () => ref.invalidate(warehousesProvider(_includeInactive)),
              ),
              data: (warehouses) => switch (_view) {
                ViewMode.table => _WarehousesTable(warehouses: warehouses, canManage: canManage, onOpen: _open, onEdit: (w) => showWarehouseFormDialog(context, warehouse: w), onToggleActive: (w) => w.isActive ? _deactivate(w) : _reactivate(w)),
                ViewMode.list => CompactRowList<Warehouse>(
                    items: warehouses,
                    onTap: _open,
                    emptyTitle: 'No warehouses yet',
                    rowBuilder: (context, w) => Row(
                      children: [
                        Expanded(flex: 2, child: Text(w.name, style: theme.textTheme.bodyMedium)),
                        Expanded(
                          child: Text(
                            w.code,
                            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                          ),
                        ),
                        StatusBadge(
                          label: w.isActive ? 'Active' : 'Inactive',
                          tone: w.isActive ? StatusTone.success : StatusTone.neutral,
                        ),
                      ],
                    ),
                  ),
                ViewMode.grid => SimpleGridView<Warehouse>(
                    items: warehouses,
                    onTap: _open,
                    emptyTitle: 'No warehouses yet',
                    maxCrossAxisExtent: 240,
                    childAspectRatio: 2.2,
                    contentBuilder: (context, w) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.warehouse_outlined, size: 18, color: theme.colorScheme.primary),
                            const SizedBox(width: AppSpacing.xs),
                            Expanded(
                              child: Text(
                                w.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(w.code, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                        const SizedBox(height: AppSpacing.xs),
                        StatusBadge(
                          label: w.isActive ? 'Active' : 'Inactive',
                          tone: w.isActive ? StatusTone.success : StatusTone.neutral,
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
}

class _WarehousesStats extends StatelessWidget {
  const _WarehousesStats({required this.warehouses});

  final List<Warehouse> warehouses;

  @override
  Widget build(BuildContext context) {
    final active = warehouses.where((w) => w.isActive).length;
    final inactive = warehouses.length - active;

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xs,
      children: [
        StatTile(label: 'shown', value: '${warehouses.length}', icon: Icons.warehouse_outlined),
        StatTile(label: 'active', value: '$active', tone: StatusTone.success, icon: Icons.check_circle_outline),
        if (inactive > 0)
          StatTile(label: 'inactive', value: '$inactive', tone: StatusTone.neutral, icon: Icons.block_outlined),
      ],
    );
  }
}

class _WarehousesTable extends StatelessWidget {
  const _WarehousesTable({
    required this.warehouses,
    required this.canManage,
    required this.onOpen,
    required this.onEdit,
    required this.onToggleActive,
  });

  final List<Warehouse> warehouses;
  final bool canManage;
  final void Function(Warehouse) onOpen;
  final void Function(Warehouse) onEdit;
  final void Function(Warehouse) onToggleActive;

  @override
  Widget build(BuildContext context) {
    return AppDataTable<Warehouse>(
      rows: warehouses,
      emptyTitle: 'No warehouses yet',
      onRowTap: onOpen,
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
            cellBuilder: (w) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(icon: const Icon(Icons.edit_outlined), tooltip: 'Edit', onPressed: () => onEdit(w)),
                IconButton(
                  icon: Icon(w.isActive ? Icons.block_outlined : Icons.restore_outlined),
                  tooltip: w.isActive ? 'Deactivate' : 'Reactivate',
                  onPressed: () => onToggleActive(w),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
