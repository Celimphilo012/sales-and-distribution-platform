import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../app_shell/responsive_app_shell.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/error/app_error.dart';
import '../../../core/theme/nocturne.dart';
import '../../../routing/route_paths.dart';
import '../../../shared/nx/nx_actions.dart';
import '../../../shared/nx/nx_format.dart';
import '../../../shared/nx/nx_list_page.dart';
import '../../../shared/nx/nx_primitives.dart';
import '../data/warehouses_providers.dart';
import '../domain/warehouse.dart';
import 'warehouse_form_dialog.dart';

/// Warehouses (prototype `warehouses`) — each owns its location tree and
/// workstreams. Totals come from the list read's `summary`.
class WarehousesListScreen extends ConsumerWidget {
  const WarehousesListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = context.nx;
    final canManage = ref.watch(authProvider.select((s) => s.value?.user?.can('warehouse.structure.manage') ?? false));
    final async = ref.watch(warehousesProvider(true));

    return NxPageScroll(
      onRefresh: () async => invalidateWarehouses(ref),
      child: async.when(
        loading: () => const NxLoading(message: 'Loading warehouses…'),
        error: (e, _) => NxError(
          message: e is AppError ? e.message : 'Could not load warehouses.',
          onRetry: () => invalidateWarehouses(ref),
        ),
        data: (rows) {
          WarehouseSummary s(Warehouse w) => w.summary ?? const WarehouseSummary();
          void open(Warehouse w) => context.go('${RoutePaths.locations}?warehouseId=${w.id}');
          NxTag status(Warehouse w) => NxTag(w.isActive ? 'Active' : 'Inactive', tone: w.isActive ? Tone.ok : Tone.neutral);
          String util(Warehouse w) => s(w).capacity > 0 ? '${(s(w).utilisation * 100).round()}%' : '—';
          void toggle(Warehouse w) => nxToggleActive(
            context,
            name: w.name,
            active: w.isActive,
            deactivate: () => ref.read(warehousesApiProvider).deactivate(w.id),
            reactivate: () => ref.read(warehousesApiProvider).reactivate(w.id),
            refresh: () => invalidateWarehouses(ref),
          );

          return NxListPage<Warehouse>(
            stateKey: 'warehouses',
            title: 'Warehouses',
            sub: 'Each warehouse owns its location tree and workstreams.',
            actions: [
              if (canManage)
                NxButton.primary(label: 'New warehouse', icon: PhosphorIconsRegular.plus, onPressed: () => showWarehouseFormDialog(context)),
            ],
            rows: rows,
            search: (w) => '${w.name} ${w.code}',
            searchPlaceholder: 'Name or code',
            stats: (rs) {
              final cap = rs.fold<double>(0, (a, w) => a + s(w).capacity);
              final units = rs.fold<double>(0, (a, w) => a + s(w).units);
              final bare = rs.where((w) => s(w).locations == 0);
              return [
                NxStat('Warehouses', fmtNum(rs.length), sub: '${rs.where((w) => w.isActive).length} active'),
                NxStat('Locations', fmtNum(rs.fold<int>(0, (a, w) => a + s(w).locations)), sub: '${fmtNum(rs.fold<int>(0, (a, w) => a + s(w).slots))} storage slots'),
                NxStat('Units on hand', fmtNum(units)),
                NxStat('Utilisation', cap > 0 ? '${(units / cap * 100).round()}%' : '—', sub: 'of slot capacity'),
                NxStat('Not structured', fmtNum(bare.length), sub: 'no locations yet', color: bare.any((w) => w.isActive) ? n.warn : null),
              ];
            },
            quick: NxQuick(
              get: (w) => w.isActive ? 'yes' : 'no',
              options: const [('', 'All'), ('yes', 'Active'), ('no', 'Inactive')],
            ),
            filters: [
              NxToggleFilter('struct', 'Structure', text: 'Has locations', get: (w) => s(w).locations > 0),
              NxRangeFilter('util', 'Utilisation %', get: (w) => (s(w).utilisation * 100).round()),
            ],
            defaultSort: ('name', 1),
            columns: [
              NxColumn(key: 'name', label: 'Warehouse', sort: (w) => w.name.toLowerCase(), cell: (w) => NxCellText(w.name, weight: FontWeight.w500, sub: w.code)),
              NxColumn(
                key: 'ws',
                label: 'Workstreams',
                align: TextAlign.right,
                hide: NxHide.md,
                sort: (w) => s(w).workstreams,
                cell: (w) => NxCellText(fmtNum(s(w).workstreams), align: TextAlign.right),
              ),
              NxColumn(
                key: 'locs',
                label: 'Locations',
                align: TextAlign.right,
                sort: (w) => s(w).locations,
                cell: (w) => s(w).locations > 0
                    ? NxCellText(fmtNum(s(w).locations), align: TextAlign.right)
                    : NxCellText('None yet', color: n.n500, align: TextAlign.right),
              ),
              NxColumn(
                key: 'units',
                label: 'Units',
                align: TextAlign.right,
                hide: NxHide.md,
                sort: (w) => s(w).units,
                cell: (w) => NxCellText(fmtNum(s(w).units), align: TextAlign.right),
              ),
              NxColumn(
                key: 'util',
                label: 'Utilisation',
                width: 170,
                sort: (w) => s(w).utilisation,
                cell: (w) => s(w).capacity > 0
                    ? NxLabeledBar(label: util(w), fraction: s(w).utilisation, color: s(w).utilisation > 0.9 ? n.warn : n.a500)
                    : NxCellText('—', color: n.n500),
              ),
              NxColumn(key: 'status', label: 'Status', cell: (w) => Align(alignment: Alignment.centerLeft, child: status(w))),
              NxColumn(
                key: 'act',
                label: '',
                width: canManage ? 104 : 40,
                cell: (w) => NxRowActions([
                  NxRowAction(icon: PhosphorIconsRegular.treeStructure, label: 'Open structure', onPressed: () => open(w)),
                  if (canManage) ...[
                    NxRowAction(icon: PhosphorIconsRegular.pencilSimple, label: 'Edit', onPressed: () => showWarehouseFormDialog(context, warehouse: w)),
                    NxRowAction(
                      icon: w.isActive ? PhosphorIconsRegular.prohibit : PhosphorIconsRegular.arrowCounterClockwise,
                      label: w.isActive ? 'Deactivate' : 'Reactivate',
                      danger: w.isActive,
                      onPressed: () => toggle(w),
                    ),
                  ],
                ]),
              ),
            ],
            listRow: (w) => NxListRowSpec(
              icon: PhosphorIconsDuotone.buildings,
              iconColor: n.a400,
              title: w.name,
              sub: '${w.code} · ${s(w).locations} locations · ${s(w).workstreams} workstreams',
              right: util(w),
              rightSub: 'utilised',
              tag: status(w),
            ),
            card: (w) => NxCardSpec(
              icon: PhosphorIconsDuotone.buildings,
              title: w.name,
              sub: w.code,
              metrics: [('Locations', fmtNum(s(w).locations), null), ('Units', fmtNum(s(w).units), null), ('Utilised', util(w), null)],
              tag: status(w),
              bar: s(w).capacity > 0 ? s(w).utilisation : null,
              barColor: n.a500,
            ),
            onOpen: open,
            emptyTitle: 'No warehouses',
            emptyMessage: 'Adjust filters or add one.',
          );
        },
      ),
    );
  }
}
