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
import '../../products/domain/product.dart';
import '../../products/presentation/products_list_providers.dart';
import '../../workstreams/data/workstreams_providers.dart';
import '../../workstreams/domain/workstream.dart';
import '../data/categories_providers.dart';
import '../domain/category.dart';
import '../domain/category_tree.dart';
import 'category_form_dialog.dart';

class _Row {
  _Row(this.c, {required this.depth, required this.parentName, required this.wsName, required this.nSubs, required this.nProds});

  final Category c;
  final int depth;
  final String parentName;
  final String wsName;
  final int nSubs;
  final int nProds;

  bool get top => depth == 0;
}

/// Categories (prototype `categories`) — category and sub-category, shown in
/// tree order; a sub-category inherits its parent's workstream.
class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = context.nx;
    final canManage = ref.watch(authProvider.select((s) => s.value?.user?.can('products.manage') ?? false));
    final async = ref.watch(categoriesProvider(true));
    final workstreams = ref.watch(workstreamsProvider(true)).value ?? const <Workstream>[];
    final products = ref.watch(productsListProvider).value ?? const <Product>[];

    return NxPageScroll(
      onRefresh: () async => invalidateCategories(ref),
      child: async.when(
        loading: () => const NxLoading(message: 'Loading categories…'),
        error: (e, _) => NxError(
          message: e is AppError ? e.message : 'Could not load categories.',
          onRetry: () => invalidateCategories(ref),
        ),
        data: (all) {
          final byId = {for (final c in all) c.id: c};
          final wsById = {for (final w in workstreams) w.id: w};
          final direct = <String, int>{};
          for (final p in products) {
            direct[p.categoryId] = (direct[p.categoryId] ?? 0) + 1;
          }
          int prodsUnder(CategoryNode node) => (direct[node.category.id] ?? 0) + node.children.fold<int>(0, (s, k) => s + prodsUnder(k));
          final rows = [
            for (final node in flattenCategoryTree(buildCategoryTree(all)))
              _Row(
                node.category,
                depth: node.depth,
                parentName: byId[node.category.parentId]?.name ?? '',
                wsName: node.category.workstream?.name ?? wsById[node.category.workstreamId]?.name ?? '—',
                nSubs: node.children.length,
                nProds: prodsUnder(node),
              ),
          ];
          Iterable<_Row> leafRows(List<_Row> rs) => rs.where((r) => r.nSubs == 0 && !r.top);

          NxTag status(_Row r) => NxTag(r.c.isActive ? 'Active' : 'Inactive', tone: r.c.isActive ? Tone.ok : Tone.neutral);
          void toggle(_Row r) => nxToggleActive(
            context,
            name: r.c.name,
            active: r.c.isActive,
            deactivate: () => ref.read(categoriesApiProvider).deactivate(r.c.id),
            reactivate: () async => ref.read(categoriesApiProvider).update(r.c.id, isActive: true),
            refresh: () => invalidateCategories(ref),
          );
          IconData icon(_Row r) => r.top ? PhosphorIconsDuotone.folderSimple : PhosphorIconsDuotone.tagSimple;

          return NxListPage<_Row>(
            stateKey: 'categories',
            title: 'Categories',
            sub: 'Category and sub-category. A sub-category inherits its parent’s workstream.',
            actions: [
              if (canManage)
                NxButton.primary(label: 'New category', icon: PhosphorIconsRegular.plus, onPressed: () => showCategoryFormDialog(context)),
            ],
            rows: rows,
            search: (r) => '${r.c.name} ${r.parentName}',
            searchPlaceholder: 'Category name',
            stats: (rs) {
              final empty = leafRows(rs).where((r) => r.nProds == 0).length;
              return [
                NxStat('Categories', fmtNum(rs.length), sub: '${rs.where((r) => r.c.isActive).length} active'),
                NxStat('Top level', fmtNum(rs.where((r) => r.top).length)),
                NxStat('Sub-categories', fmtNum(rs.where((r) => !r.top).length)),
                NxStat('Products placed', fmtNum(rs.where((r) => r.top).fold<int>(0, (s, r) => s + r.nProds))),
                NxStat('Empty', fmtNum(empty), sub: 'sub-categories with no products', color: empty > 0 ? n.warn : null),
              ];
            },
            quick: NxQuick(
              get: (r) => r.top ? 'top' : 'sub',
              options: const [('', 'All'), ('top', 'Top level'), ('sub', 'Sub-categories')],
            ),
            filters: [
              NxSelectFilter('ws', 'Workstream', options: [for (final w in workstreams) (w.id, w.name)], get: (r) => r.c.workstreamId),
              NxSelectFilter(
                'parent',
                'Parent',
                searchable: true,
                options: [for (final c in all.where((c) => all.any((k) => k.parentId == c.id))) (c.id, c.name)],
                get: (r) => r.c.parentId,
              ),
              NxSelectFilter('st', 'Status', options: const [('yes', 'Active'), ('no', 'Inactive')], get: (r) => r.c.isActive ? 'yes' : 'no'),
              NxRangeFilter('prods', 'Products', get: (r) => r.nProds),
            ],
            columns: [
              NxColumn(
                key: 'name',
                label: 'Category',
                cell: (r) => Padding(
                  padding: EdgeInsets.only(left: r.depth > 1 ? (r.depth - 1) * 14.0 : 0),
                  child: NxCellText(
                    '${r.top ? '' : '↳ '}${r.c.name}',
                    weight: r.top ? FontWeight.w500 : FontWeight.w400,
                    sub: r.top ? '${r.nSubs} sub-categories' : 'in ${r.parentName}',
                  ),
                ),
              ),
              NxColumn(key: 'ws', label: 'Workstream', hide: NxHide.md, sort: (r) => r.wsName, cell: (r) => NxCellText(r.wsName, color: n.n300)),
              NxColumn(
                key: 'level',
                label: 'Level',
                hide: NxHide.wide,
                cell: (r) => Align(
                  alignment: Alignment.centerLeft,
                  child: NxTag(r.top ? 'Category' : 'Sub-category', tone: r.top ? Tone.info : Tone.neutral),
                ),
              ),
              NxColumn(key: 'prods', label: 'Products', align: TextAlign.right, sort: (r) => r.nProds, cell: (r) => NxCellText(fmtNum(r.nProds), align: TextAlign.right)),
              NxColumn(key: 'status', label: 'Status', cell: (r) => Align(alignment: Alignment.centerLeft, child: status(r))),
              if (canManage)
                NxColumn(
                  key: 'act',
                  label: '',
                  width: 104,
                  cell: (r) => NxRowActions([
                    if (r.c.isActive)
                      NxRowAction(
                        icon: PhosphorIconsRegular.plus,
                        label: 'Add sub-category',
                        onPressed: () => showCategoryFormDialog(context, parentId: r.c.id, workstreamId: r.c.workstreamId),
                      ),
                    NxRowAction(icon: PhosphorIconsRegular.pencilSimple, label: 'Edit', onPressed: () => showCategoryFormDialog(context, category: r.c)),
                    NxRowAction(
                      icon: r.c.isActive ? PhosphorIconsRegular.prohibit : PhosphorIconsRegular.arrowCounterClockwise,
                      label: r.c.isActive ? 'Deactivate' : 'Reactivate',
                      danger: r.c.isActive,
                      onPressed: () => toggle(r),
                    ),
                  ]),
                ),
            ],
            listRow: (r) => NxListRowSpec(
              icon: icon(r),
              iconColor: r.top ? n.a400 : n.n500,
              title: r.top ? r.c.name : '${r.parentName} › ${r.c.name}',
              sub: r.wsName,
              right: '${r.nProds} products',
              tag: status(r),
            ),
            card: (r) => NxCardSpec(
              icon: icon(r),
              title: r.c.name,
              sub: '${r.top ? '' : 'in ${r.parentName} · '}${r.wsName}',
              metrics: [
                ('Products', fmtNum(r.nProds), null),
                (r.top ? 'Sub-categories' : 'Level', r.top ? fmtNum(r.nSubs) : 'Sub', null),
              ],
              tag: status(r),
            ),
            onOpen: canManage ? (r) => showCategoryFormDialog(context, category: r.c) : null,
            emptyTitle: 'No categories',
            emptyMessage: 'Adjust filters or add a category.',
          );
        },
      ),
    );
  }
}
