import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../app_shell/responsive_app_shell.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/error/app_error.dart';
import '../../../core/theme/nocturne.dart';
import '../../../shared/nx/nx_actions.dart';
import '../../../shared/nx/nx_format.dart';
import '../../../shared/nx/nx_list_page.dart';
import '../../../shared/nx/nx_primitives.dart';
import '../../categories/data/categories_providers.dart';
import '../../categories/domain/category.dart';
import '../../products/domain/product.dart';
import '../../products/presentation/products_list_providers.dart';
import '../../warehouses/data/warehouses_providers.dart';
import '../../warehouses/domain/warehouse.dart';
import '../data/workstreams_providers.dart';
import '../domain/workstream.dart';
import 'workstream_form_dialog.dart';

class _Row {
  _Row(this.w, {required this.warehouse, required this.nCats, required this.nProds, required this.units});

  final Workstream w;
  final Warehouse? warehouse;
  final int nCats;
  final int nProds;
  final double units;

  List<String> get managers => [for (final m in w.managers) m.fullName];
}

/// Workstreams (prototype `workstreams`) — Warehouse → Workstream → Category
/// → Product. Organisational only; never affects stock. Editing needs
/// `workstreams.manage`; choosing scoped managers (in the form) also needs
/// `workstreams.assign`.
class WorkstreamsScreen extends ConsumerWidget {
  const WorkstreamsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = context.nx;
    final canManage = ref.watch(authProvider.select((s) => s.value?.user?.can('workstreams.manage') ?? false));
    final async = ref.watch(workstreamsProvider(true));
    final warehouses = ref.watch(warehousesProvider(true)).value ?? const <Warehouse>[];
    final categories = ref.watch(categoriesProvider(true)).value ?? const <Category>[];
    final products = ref.watch(productsListProvider).value ?? const <Product>[];

    return NxPageScroll(
      onRefresh: () async => ref.invalidate(workstreamsProvider(true)),
      child: async.when(
        loading: () => const NxLoading(message: 'Loading workstreams…'),
        error: (e, _) => NxError(
          message: e is AppError ? e.message : 'Could not load workstreams.',
          onRetry: () => ref.invalidate(workstreamsProvider(true)),
        ),
        data: (list) {
          final whById = {for (final w in warehouses) w.id: w};
          final catWs = {for (final c in categories) c.id: c.workstreamId};
          final rows = [
            for (final w in list)
              () {
                final prods = products.where((p) => (catWs[p.categoryId] ?? p.category?.workstreamId) == w.id);
                return _Row(
                  w,
                  warehouse: whById[w.warehouseId],
                  nCats: categories.where((c) => c.workstreamId == w.id).length,
                  nProds: prods.length,
                  units: prods.fold<double>(0, (s, p) => s + p.totalOnHand),
                );
              }(),
          ];
          final allManagers = {for (final r in rows) ...r.managers}.toList()..sort();
          NxTag status(_Row r) => NxTag(r.w.isActive ? 'Active' : 'Inactive', tone: r.w.isActive ? Tone.ok : Tone.neutral);
          void toggle(_Row r) => nxToggleActive(
            context,
            name: r.w.name,
            active: r.w.isActive,
            deactivate: () => ref.read(workstreamsApiProvider).deactivate(r.w.id),
            reactivate: () => ref.read(workstreamsApiProvider).reactivate(r.w.id),
            refresh: () => invalidateWorkstreams(ref),
          );

          return NxListPage<_Row>(
            stateKey: 'workstreams',
            title: 'Workstreams',
            sub: 'Warehouse → Workstream → Category → Product. Organisational only — never affects stock.',
            actions: [
              if (canManage)
                NxButton.primary(label: 'New workstream', icon: PhosphorIconsRegular.plus, onPressed: () => showWorkstreamFormDialog(context)),
            ],
            rows: rows,
            search: (r) => '${r.w.name} ${r.w.code}',
            searchPlaceholder: 'Name or code',
            stats: (rs) => [
              NxStat('Workstreams', fmtNum(rs.length), sub: '${rs.where((r) => r.w.isActive).length} active'),
              NxStat('Categories', fmtNum(rs.fold<int>(0, (s, r) => s + r.nCats)), sub: 'incl. sub-categories'),
              NxStat('Products', fmtNum(rs.fold<int>(0, (s, r) => s + r.nProds))),
              NxStat('Units on hand', fmtNum(rs.fold<double>(0, (s, r) => s + r.units))),
              NxStat('Scoped managers', fmtNum({for (final r in rs) ...r.managers}.length), sub: 'limited to their workstreams'),
            ],
            quick: NxQuick(
              get: (r) => r.w.isActive ? 'yes' : 'no',
              options: const [('', 'All'), ('yes', 'Active'), ('no', 'Inactive')],
            ),
            filters: [
              NxSelectFilter('wh', 'Warehouse', options: [for (final w in warehouses) (w.id, w.name)], get: (r) => r.w.warehouseId),
              NxSelectFilter('mgr', 'Manager', options: [for (final m in allManagers) (m, m)], get: (r) => r.managers),
              NxRangeFilter('prods', 'Products', get: (r) => r.nProds),
              NxToggleFilter('contact', 'Contact', text: 'Has contact details', get: (r) => r.w.hasContactInfo),
            ],
            defaultSort: ('name', 1),
            columns: [
              NxColumn(
                key: 'name',
                label: 'Workstream',
                sort: (r) => r.w.name.toLowerCase(),
                cell: (r) => NxCellText(r.w.name, weight: FontWeight.w500, sub: '${r.w.code} · ${r.w.description ?? 'No description'}'),
              ),
              NxColumn(
                key: 'wh',
                label: 'Warehouse',
                hide: NxHide.md,
                sort: (r) => r.warehouse?.code ?? '',
                cell: (r) => NxCellText(r.warehouse?.code ?? '—', mono: true, color: n.n300),
              ),
              NxColumn(key: 'cats', label: 'Categories', align: TextAlign.right, sort: (r) => r.nCats, cell: (r) => NxCellText(fmtNum(r.nCats), align: TextAlign.right)),
              NxColumn(key: 'prods', label: 'Products', align: TextAlign.right, sort: (r) => r.nProds, cell: (r) => NxCellText(fmtNum(r.nProds), align: TextAlign.right)),
              NxColumn(
                key: 'mgr',
                label: 'Managers',
                hide: NxHide.wide,
                cell: (r) => r.managers.isEmpty
                    ? NxCellText('Everyone with catalogue access', color: n.n500)
                    : Wrap(spacing: 4, runSpacing: 4, children: [for (final m in r.managers) NxTag(m, small: true)]),
              ),
              NxColumn(
                key: 'contact',
                label: 'Contact',
                hide: NxHide.wide,
                cell: (r) => r.w.contactName != null
                    ? NxCellText(r.w.contactName!, sub: r.w.contactEmail ?? r.w.contactPhone)
                    : NxCellText('—', color: n.n500),
              ),
              NxColumn(key: 'status', label: 'Status', sort: (r) => r.w.isActive ? 0 : 1, cell: (r) => Align(alignment: Alignment.centerLeft, child: status(r))),
              if (canManage)
                NxColumn(
                  key: 'act',
                  label: '',
                  width: 76,
                  cell: (r) => NxRowActions([
                    NxRowAction(icon: PhosphorIconsRegular.pencilSimple, label: 'Edit', onPressed: () => showWorkstreamFormDialog(context, workstream: r.w)),
                    NxRowAction(
                      icon: r.w.isActive ? PhosphorIconsRegular.prohibit : PhosphorIconsRegular.arrowCounterClockwise,
                      label: r.w.isActive ? 'Deactivate' : 'Reactivate',
                      danger: r.w.isActive,
                      onPressed: () => toggle(r),
                    ),
                  ]),
                ),
            ],
            listRow: (r) => NxListRowSpec(
              icon: PhosphorIconsDuotone.flowArrow,
              iconColor: n.a400,
              title: r.w.name,
              sub: '${r.w.code} · ${r.warehouse?.name ?? '—'} · ${r.managers.isEmpty ? 'no scoped managers' : r.managers.join(', ')}',
              right: '${r.nProds} products',
              rightSub: '${r.nCats} categories',
              tag: status(r),
            ),
            card: (r) => NxCardSpec(
              icon: PhosphorIconsDuotone.flowArrow,
              title: r.w.name,
              sub: '${r.w.code} · ${r.warehouse?.name ?? '—'}',
              metrics: [('Categories', fmtNum(r.nCats), null), ('Products', fmtNum(r.nProds), null), ('Units', fmtNum(r.units), null)],
              tag: status(r),
            ),
            onOpen: canManage ? (r) => showWorkstreamFormDialog(context, workstream: r.w) : null,
            emptyTitle: 'No workstreams',
            emptyMessage: 'Create one to organise the catalogue.',
          );
        },
      ),
    );
  }
}
