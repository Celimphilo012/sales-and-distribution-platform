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
import '../../../shared/nx/nx_overlays.dart';
import '../../../shared/nx/nx_primitives.dart';
import '../../categories/data/categories_providers.dart';
import '../../categories/domain/category.dart';
import '../../workstreams/data/workstreams_providers.dart';
import '../../workstreams/domain/workstream.dart';
import '../data/products_providers.dart';
import '../domain/product.dart';
import '../domain/product_status.dart';
import '../../scan/qr_label_dialog.dart';
import 'product_form_dialog.dart';
import 'product_sheet.dart';
import 'products_list_providers.dart';
import 'widgets/product_image_view.dart';

/// A product plus what the list shows about it.
class _Row {
  _Row(this.p, {required this.parentName, required this.subName, required this.workstream});

  final Product p;
  final String parentName;
  final String subName;
  final Workstream? workstream;

  bool get active => p.status == ProductStatus.active;
  bool get low => active && p.totalOnHand < p.minStockLevel;
  double get value => p.costPrice == null ? 0 : p.costPrice! * p.totalOnHand;

  /// Stock-vs-min bar: scaled to twice the minimum, so the minimum sits at 50%.
  double get fill => p.minStockLevel <= 0 ? (p.totalOnHand > 0 ? 1 : 0) : p.totalOnHand / (p.minStockLevel * 2);
}

/// Products — the catalogue across every workstream (prototype `products`).
/// `/products?open=<id>` opens that product's sheet on arrival.
class ProductsListScreen extends ConsumerStatefulWidget {
  const ProductsListScreen({super.key, this.openProductId});

  final String? openProductId;

  @override
  ConsumerState<ProductsListScreen> createState() => _ProductsListScreenState();
}

class _ProductsListScreenState extends ConsumerState<ProductsListScreen> {
  @override
  void initState() {
    super.initState();
    final id = widget.openProductId;
    if (id != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        GoRouter.of(context).go(RoutePaths.products);
        showProductSheet(context, id);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    final user = ref.watch(authProvider).value?.user;
    final canManage = user?.can('products.manage') ?? false;
    final productsAsync = ref.watch(productsListProvider);
    final categories = ref.watch(categoriesProvider(true)).value ?? const <Category>[];
    final workstreams = ref.watch(workstreamsProvider(true)).value ?? const <Workstream>[];
    final catById = {for (final c in categories) c.id: c};
    final wsById = {for (final w in workstreams) w.id: w};

    return NxPageScroll(
      onRefresh: () async => ref.invalidate(productsListProvider),
      child: productsAsync.when(
        loading: () => const NxLoading(message: 'Loading products…'),
        error: (e, _) => NxError(
          message: e is AppError ? e.message : 'Could not load products.',
          onRetry: () => ref.invalidate(productsListProvider),
        ),
        data: (products) {
          final rows = [
            for (final p in products)
              () {
                final c = catById[p.categoryId];
                final parent = c?.parentId == null ? null : catById[c!.parentId];
                final wsId = c?.workstreamId ?? p.category?.workstreamId;
                return _Row(
                  p,
                  parentName: parent?.name ?? p.category?.parent?.name ?? (c?.name ?? p.category?.name ?? '—'),
                  subName: c?.name ?? p.category?.name ?? '—',
                  workstream: wsId == null ? null : wsById[wsId],
                );
              }(),
          ];
          final uoms = {for (final r in rows) r.p.uom}.toList()..sort();

          Future<void> setStatus(_Row r, bool reactivate) async {
            if (!reactivate) {
              final ok = await showNxConfirm(
                context,
                title: 'Deactivate product?',
                body: 'This marks "${r.p.name}" inactive. It stays visible in historical inventory records — it is not deleted.',
                confirmLabel: 'Deactivate',
                danger: true,
              );
              if (!ok) return;
            }
            try {
              final api = ref.read(productsApiProvider);
              reactivate ? await api.reactivate(r.p.id) : await api.deactivate(r.p.id);
              invalidateProduct(ref, r.p.id);
              NxToast.ok(
                reactivate ? 'Product reactivated' : 'Product deactivated',
                r.p.name,
                reactivate
                    ? null
                    : NxToastAction('Undo', () async {
                        await api.reactivate(r.p.id);
                        invalidateProduct(ref, r.p.id);
                      }),
              );
            } on AppError catch (e) {
              NxToast.error('Not changed', e.message);
            }
          }

          NxTag status(_Row r) => NxTag(r.active ? 'Active' : 'Inactive', tone: r.active ? Tone.ok : Tone.neutral);
          Widget thumb(_Row r, double size) {
            final img = r.p.images.where((i) => i.isPrimary).firstOrNull ?? r.p.images.firstOrNull;
            if (img == null) return NxIconTile(icon: PhosphorIconsDuotone.package, size: size, iconSize: size * 0.55, radius: 6);
            return ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(width: size, height: size, child: ProductImageView(image: img, productId: r.p.id)),
            );
          }

          List<NxRowAction> actions(_Row r) => [
            if (canManage) NxRowAction(icon: PhosphorIconsRegular.pencilSimple, label: 'Edit', onPressed: () => showProductForm(context, product: r.p)),
            if (canManage && r.active)
              NxRowAction(icon: PhosphorIconsRegular.prohibit, label: 'Deactivate', danger: true, onPressed: () => setStatus(r, false)),
            if (canManage && !r.active)
              NxRowAction(icon: PhosphorIconsRegular.arrowCounterClockwise, label: 'Reactivate', onPressed: () => setStatus(r, true)),
          ];

          return NxListPage<_Row>(
            stateKey: 'products',
            title: 'Products',
            sub: 'Catalogue items across every workstream',
            actions: [
              NxButton(
                label: 'QR labels',
                icon: PhosphorIconsRegular.qrCode,
                onPressed: () => printQrLabels(ref, [for (final r in rows) if (r.active) productLabel(r.p)], name: 'product labels'),
              ),
              if (canManage)
                NxButton(label: 'Import', icon: PhosphorIconsRegular.uploadSimple, onPressed: () => context.go(RoutePaths.productImport)),
              if (canManage)
                NxButton.primary(label: 'New product', icon: PhosphorIconsRegular.plus, onPressed: () => showProductForm(context)),
            ],
            rows: rows,
            search: (r) => '${r.p.sku} ${r.p.name}',
            searchPlaceholder: 'SKU or name',
            stats: (rs) {
              final lowCount = rs.where((r) => r.low).length;
              return [
                NxStat('Products', fmtNum(rs.length), sub: '${rs.where((r) => r.active).length} active'),
                NxStat('Below minimum', fmtNum(lowCount), sub: 'need reordering', color: lowCount > 0 ? n.warn : null),
                NxStat('Units on hand', fmtNum(rs.fold<double>(0, (s, r) => s + r.p.totalOnHand)), sub: 'all locations'),
                NxStat('Stock value', fmtMoney(rs.fold<double>(0, (s, r) => s + r.value)), sub: 'at cost price'),
                NxStat(
                  'Avg. price',
                  rs.isEmpty ? '—' : fmtMoney(rs.fold<double>(0, (s, r) => s + r.p.sellingPrice) / rs.length),
                  sub: 'selling',
                ),
              ];
            },
            quick: NxQuick(
              get: (r) => r.active ? 'ACTIVE' : 'INACTIVE',
              options: const [('', 'All'), ('ACTIVE', 'Active'), ('INACTIVE', 'Inactive')],
            ),
            filters: [
              NxSelectFilter('ws', 'Workstream', options: [for (final w in workstreams) (w.id, w.name)], get: (r) => r.workstream?.id),
              NxSelectFilter(
                'cat',
                'Category',
                searchable: true,
                options: [for (final c in categories.where((c) => c.parentId == null)) (c.name, c.name)],
                get: (r) => r.parentName,
              ),
              NxMultiFilter('uom', 'Unit of measure', options: [for (final u in uoms) (u, u)], get: (r) => r.p.uom),
              NxRangeFilter('price', 'Selling price', get: (r) => r.p.sellingPrice),
              NxRangeFilter('stock', 'On hand', get: (r) => r.p.totalOnHand),
              NxToggleFilter('low', 'Stock level', text: 'Below minimum only', get: (r) => r.low),
            ],
            defaultSort: ('sku', 1),
            columns: [
              NxColumn(key: 'thumb', label: '', width: 44, cell: (r) => thumb(r, 28)),
              NxColumn(key: 'sku', label: 'SKU', sort: (r) => r.p.sku, cell: (r) => NxCellText(r.p.sku, mono: true, color: n.n300)),
              NxColumn(
                key: 'name',
                label: 'Name',
                sort: (r) => r.p.name.toLowerCase(),
                cell: (r) => NxCellText(r.p.name, weight: FontWeight.w500, sub: r.parentName == r.subName ? r.subName : '${r.parentName} › ${r.subName}'),
              ),
              NxColumn(
                key: 'ws',
                label: 'Workstream',
                hide: NxHide.wide,
                sort: (r) => r.workstream?.name ?? '',
                cell: (r) => NxCellText(r.workstream?.name ?? '—', color: n.n300),
              ),
              NxColumn(key: 'uom', label: 'UOM', hide: NxHide.wide, cell: (r) => NxCellText(r.p.uom, color: n.n400)),
              NxColumn(
                key: 'price',
                label: 'Price',
                align: TextAlign.right,
                sort: (r) => r.p.sellingPrice,
                cell: (r) => NxCellText(fmtMoney(r.p.sellingPrice), align: TextAlign.right),
              ),
              NxColumn(
                key: 'stock',
                label: 'Stock vs min',
                width: 170,
                sort: (r) => r.fill,
                cell: (r) => NxLabeledBar(
                  label: fmtNum(r.p.totalOnHand),
                  labelColor: r.low ? n.bad : null,
                  fraction: r.fill,
                  color: r.low ? n.bad : n.a500,
                  marker: true,
                ),
              ),
              NxColumn(key: 'status', label: 'Status', sort: (r) => r.active ? 0 : 1, cell: (r) => Align(alignment: Alignment.centerLeft, child: status(r))),
              if (canManage) NxColumn(key: 'act', label: '', width: 76, cell: (r) => NxRowActions(actions(r))),
            ],
            listRow: (r) => NxListRowSpec(
              icon: PhosphorIconsDuotone.package,
              leading: thumb(r, 32),
              title: r.p.name,
              sub: '${r.p.sku} · ${r.subName} · ${fmtMoney(r.p.sellingPrice)}',
              right: '${fmtNum(r.p.totalOnHand)} / ${fmtNum(r.p.minStockLevel)}',
              rightSub: r.p.uom,
              rightColor: r.low ? n.bad : null,
              tag: status(r),
            ),
            card: (r) => NxCardSpec(
              icon: PhosphorIconsDuotone.package,
              iconColor: n.n400,
              leading: r.p.images.isEmpty ? null : thumb(r, 34),
              title: r.p.name,
              sub: '${r.p.sku} · ${r.subName}',
              metrics: [('Price', fmtMoney(r.p.sellingPrice), null), ('On hand', '${fmtNum(r.p.totalOnHand)} ${r.p.uom}', r.low ? n.bad : null)],
              tag: status(r),
              bar: r.fill,
              barColor: r.low ? n.bad : n.a500,
            ),
            onOpen: (r) => showProductSheet(context, r.p.id),
            emptyTitle: 'No products found',
          );
        },
      ),
    );
  }
}
