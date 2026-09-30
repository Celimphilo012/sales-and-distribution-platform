import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../app_shell/responsive_app_shell.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/error/app_error.dart';
import '../../../core/theme/nocturne.dart';
import '../../../routing/route_paths.dart';
import '../../../shared/nx/nx_format.dart';
import '../../../shared/nx/nx_list_page.dart';
import '../../../shared/nx/nx_primitives.dart';
import '../../categories/data/categories_providers.dart';
import '../../categories/domain/category.dart';
import '../../locations/data/leaf_locations_provider.dart';
import '../../products/domain/product.dart';
import '../../products/presentation/product_sheet.dart';
import '../../products/presentation/products_list_providers.dart';
import '../../receiving/presentation/receive_sheet.dart';
import '../../stock_adjustments/presentation/adjustment_form_dialog.dart';
import '../../transfers/presentation/transfer_sheet.dart';
import '../../workstreams/data/workstreams_providers.dart';
import '../../workstreams/domain/workstream.dart';
import '../data/inventory_providers.dart';
import '../domain/inventory_balance.dart';

class _Row {
  _Row(this.b, {required this.path, required this.product, required this.wsId});

  final InventoryBalance b;
  final List<String> path;
  final Product? product;
  final String? wsId;

  String get area => path.isEmpty ? b.location.name : path.first;
  String get slotName => path.isEmpty ? b.location.name : path.last;
  String get parents => path.length <= 1 ? '' : path.sublist(0, path.length - 1).join(' › ');
  bool get low => product != null && product!.totalOnHand < product!.minStockLevel;
  double get reservedShare => b.onHand <= 0 ? 0 : b.reserved / b.onHand;
}

/// Inventory (prototype `inventory`) — read-only balances, one row per
/// product × location. Filter by product for "where is it?", or by location
/// for "what's here?". `?productId=` opens it filtered to that product.
class InventoryScreen extends ConsumerStatefulWidget {
  const InventoryScreen({super.key, this.initialProductId});

  final String? initialProductId;

  @override
  ConsumerState<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends ConsumerState<InventoryScreen> {
  @override
  void initState() {
    super.initState();
    final pid = widget.initialProductId;
    if (pid != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(nxListStatesProvider.notifier).preset('inventory', filters: {'pid': pid});
        GoRouter.of(context).go(RoutePaths.inventory);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    final user = ref.watch(authProvider).value?.user;
    final canReceive = user?.can('inventory.receive') ?? false;
    final canTransfer = user?.can('inventory.transfer') ?? false;
    final canAdjust = user?.can('inventory.adjust.request') ?? false;
    final async = ref.watch(allBalancesProvider);
    final leaves = {for (final l in ref.watch(leafLocationsProvider).value ?? const <LeafLocation>[]) l.id: l};
    final products = {for (final p in ref.watch(productsListProvider).value ?? const <Product>[]) p.id: p};
    final catWs = {for (final c in ref.watch(categoriesProvider(true)).value ?? const <Category>[]) c.id: c.workstreamId};
    final workstreams = ref.watch(workstreamsProvider(true)).value ?? const <Workstream>[];

    return NxPageScroll(
      onRefresh: () async => invalidateStockViews(ref),
      child: async.when(
        loading: () => const NxLoading(message: 'Loading balances…'),
        error: (e, _) => NxError(
          message: e is AppError ? e.message : 'Could not load balances.',
          onRetry: () => ref.invalidate(allBalancesProvider),
        ),
        data: (balances) {
          final rows = [
            for (final b in balances.where((b) => b.onHand != 0 || b.reserved != 0))
              () {
                final p = products[b.productId];
                return _Row(
                  b,
                  path: leaves[b.locationId]?.path ?? [b.location.name],
                  product: p,
                  wsId: p == null ? null : (catWs[p.categoryId] ?? p.category?.workstreamId),
                );
              }(),
          ];
          final productOpts = {for (final r in rows) r.b.productId: '${r.b.product.sku} — ${r.b.product.name}'}.entries.toList()
            ..sort((a, b) => a.value.compareTo(b.value));
          final locOpts = {for (final r in rows) r.b.locationId: '${r.b.location.code} — ${[...r.path].join(' › ')}'}.entries.toList()
            ..sort((a, b) => a.value.compareTo(b.value));
          final areas = {for (final r in rows) r.area}.toList()..sort();

          List<NxRowAction> acts(_Row r) => [
            if (canTransfer && r.b.available > 0)
              NxRowAction(
                icon: PhosphorIconsRegular.arrowsLeftRight,
                label: 'Transfer from here',
                onPressed: () => showTransferSheet(context, productId: r.b.productId, fromLocationId: r.b.locationId),
              ),
            if (canAdjust)
              NxRowAction(
                icon: PhosphorIconsRegular.slidersHorizontal,
                label: 'Request adjustment',
                onPressed: () => showAdjustmentForm(context, productId: r.b.productId, locationId: r.b.locationId),
              ),
          ];

          return NxListPage<_Row>(
            stateKey: 'inventory',
            title: 'Inventory',
            sub: 'Read-only balances. Filter by product for “where is it?”, or by location for “what’s here?”.',
            actions: [
              if (canTransfer) NxButton(label: 'Transfer', icon: PhosphorIconsRegular.arrowsLeftRight, onPressed: () => showTransferSheet(context)),
              if (canReceive) NxButton.primary(label: 'Receive', icon: PhosphorIconsRegular.boxArrowDown, onPressed: () => showReceiveSheet(context)),
            ],
            rows: rows,
            search: (r) => '${r.b.product.name} ${r.b.product.sku} ${r.b.location.code} ${r.b.location.name}',
            searchPlaceholder: 'Product, SKU or location code',
            stats: (rs) => [
              NxStat('On hand', fmtNum(rs.fold<double>(0, (s, r) => s + r.b.onHand)), sub: 'units in ${fmtNum({for (final r in rs) r.b.locationId}.length)} locations'),
              NxStat('Reserved', fmtNum(rs.fold<double>(0, (s, r) => s + r.b.reserved)), sub: 'held for orders', color: n.warn),
              NxStat('Available', fmtNum(rs.fold<double>(0, (s, r) => s + r.b.available)), sub: 'can be picked', color: n.a300),
              NxStat(
                'Products',
                fmtNum({for (final r in rs) r.b.productId}.length),
                sub: '${fmtNum({for (final r in rs.where((r) => r.low)) r.b.productId}.length)} below minimum',
              ),
              NxStat('Balances', fmtNum(rs.length), sub: 'product × location'),
            ],
            quick: NxQuick(
              get: (r) => r.b.reserved > 0 ? 'res' : 'free',
              options: const [('', 'All balances'), ('res', 'With reservations'), ('free', 'Unreserved')],
            ),
            filters: [
              NxSelectFilter('pid', 'Product — where is it?', searchable: true, options: [for (final e in productOpts) (e.key, e.value)], get: (r) => r.b.productId),
              NxSelectFilter('loc', 'Location — what’s here?', searchable: true, options: [for (final e in locOpts) (e.key, e.value)], get: (r) => r.b.locationId),
              NxSelectFilter('aisle', 'Area', options: [for (final a in areas) (a, a)], get: (r) => r.area),
              NxSelectFilter('ws', 'Workstream', options: [for (final w in workstreams) (w.id, w.name)], get: (r) => r.wsId),
              NxRangeFilter('onHand', 'On hand', get: (r) => r.b.onHand),
              NxToggleFilter('low', 'Stock level', text: 'Products below minimum', get: (r) => r.low),
            ],
            defaultSort: ('product', 1),
            columns: [
              NxColumn(
                key: 'product',
                label: 'Product',
                sort: (r) => r.b.product.name.toLowerCase(),
                cell: (r) => NxCellText(r.b.product.name, weight: FontWeight.w500, sub: r.b.product.sku),
              ),
              NxColumn(
                key: 'loc',
                label: 'Location',
                sort: (r) => r.b.location.code,
                cell: (r) => NxCellText('${r.slotName} · ${r.b.location.code}', sub: r.parents.isEmpty ? null : r.parents),
              ),
              NxColumn(key: 'onHand', label: 'On hand', align: TextAlign.right, sort: (r) => r.b.onHand, cell: (r) => NxCellText(fmtNum(r.b.onHand), align: TextAlign.right)),
              NxColumn(
                key: 'res',
                label: 'Reserved',
                align: TextAlign.right,
                hide: NxHide.md,
                sort: (r) => r.b.reserved,
                cell: (r) => NxCellText(fmtNum(r.b.reserved), color: r.b.reserved > 0 ? n.warn : n.n500, align: TextAlign.right),
              ),
              NxColumn(
                key: 'avail',
                label: 'Available',
                align: TextAlign.right,
                sort: (r) => r.b.available,
                cell: (r) => NxCellText(fmtNum(r.b.available), color: n.a300, weight: FontWeight.w500, align: TextAlign.right),
              ),
              NxColumn(key: 'share', label: 'Reserved share', width: 130, hide: NxHide.wide, cell: (r) => NxBar(fraction: r.reservedShare, color: n.warn)),
              if (canTransfer || canAdjust) NxColumn(key: 'act', label: '', width: 76, cell: (r) => NxRowActions(acts(r))),
            ],
            listRow: (r) => NxListRowSpec(
              icon: PhosphorIconsDuotone.cube,
              title: r.b.product.name,
              sub: '${r.b.location.code}${r.parents.isEmpty ? '' : ' · ${r.parents}'}',
              right: '${fmtNum(r.b.available)} avail.',
              rightSub: '${fmtNum(r.b.onHand)} on hand · ${fmtNum(r.b.reserved)} res.',
              rightColor: n.a300,
            ),
            card: (r) => NxCardSpec(
              icon: PhosphorIconsDuotone.cube,
              title: r.b.product.name,
              sub: '${r.b.location.code} · ${r.b.product.sku}',
              metrics: [
                ('On hand', fmtNum(r.b.onHand), null),
                ('Reserved', fmtNum(r.b.reserved), r.b.reserved > 0 ? n.warn : null),
                ('Available', fmtNum(r.b.available), n.a300),
              ],
              bar: r.reservedShare,
              barColor: n.warn,
            ),
            onOpen: (r) => showProductSheet(context, r.b.productId),
            emptyTitle: 'No balances match',
            emptyMessage: 'This product or location holds no stock.',
          );
        },
      ),
    );
  }
}
