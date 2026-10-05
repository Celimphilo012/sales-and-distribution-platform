import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/error/app_error.dart';
import '../../../core/theme/nocturne.dart';
import '../../../routing/route_paths.dart';
import '../../../shared/nx/nx_format.dart';
import '../../../shared/nx/nx_list_page.dart';
import '../../../shared/nx/nx_overlays.dart';
import '../../../shared/nx/nx_primitives.dart';
import '../../dashboard/presentation/dashboard_screen.dart' show txTone;
import '../../inventory/data/inventory_providers.dart';
import '../../receiving/presentation/receive_sheet.dart';
import '../../sales/domain/sale_campaign.dart' show SaleDiscountType, SaleEligibility;
import '../../scan/qr_label_dialog.dart';
import '../data/products_providers.dart';
import '../domain/active_sale.dart';
import '../domain/product.dart';
import '../domain/product_status.dart';
import '../domain/tracking_mode.dart';
import 'generate_unit_labels_dialog.dart';
import 'product_form_dialog.dart';
import 'product_units_sheet.dart';
import 'products_list_providers.dart';
import 'widgets/product_image_view.dart';

/// The product sheet (right-hand panel): identity, actions (edit, receive,
/// where is it?, deactivate), key figures, stock by location, recent ledger
/// movements — and the product's attributes, description and images.
Future<void> showProductSheet(BuildContext context, String productId) =>
    showNxSheet<void>(context, kicker: 'Product', builder: (_) => _ProductSheet(productId: productId));

class _ProductSheet extends ConsumerWidget {
  const _ProductSheet({required this.productId});

  final String productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(productDetailProvider(productId));
    return async.when(
      loading: () => const NxLoading(message: 'Loading product…'),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(16),
        child: NxError(message: e is AppError ? e.message : 'Could not load this product.'),
      ),
      data: (p) => _Body(product: p),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = context.nx;
    final p = product;
    final user = ref.watch(authProvider).value?.user;
    final canManage = user?.can('products.manage') ?? false;
    final active = p.status == ProductStatus.active;
    final low = active && p.totalOnHand < p.minStockLevel;
    final cat = p.category;
    final catS = [cat?.parent?.name, cat?.name].whereType<String>().join(' › ');
    final margin = p.costPrice != null && p.sellingPrice > 0 ? '${((p.sellingPrice - p.costPrice!) / p.sellingPrice * 100).round()}%' : '—';
    final primary = p.images.where((i) => i.isPrimary).firstOrNull ?? p.images.firstOrNull;
    final stock = ref.watch(productStockBreakdownProvider(p.id));
    final moves = ref.watch(productLedgerProvider(p.id));

    Future<void> setStatus(bool reactivate) async {
      if (!reactivate) {
        final ok = await showNxConfirm(
          context,
          title: 'Deactivate product?',
          body: 'This marks "${p.name}" inactive. It stays visible in historical inventory records — it is not deleted.',
          confirmLabel: 'Deactivate',
          danger: true,
        );
        if (!ok) return;
      }
      try {
        final api = ref.read(productsApiProvider);
        reactivate ? await api.reactivate(p.id) : await api.deactivate(p.id);
        invalidateProduct(ref, p.id);
        NxToast.ok(
          reactivate ? 'Product reactivated' : 'Product deactivated',
          p.name,
          reactivate
              ? null
              : NxToastAction('Undo', () async {
                  await api.reactivate(p.id);
                  invalidateProduct(ref, p.id);
                }),
        );
      } on AppError catch (e) {
        NxToast.error('Not changed', e.message);
      }
    }

    return NxSheetBody(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                gradient: RadialGradient(center: const Alignment(0, -0.2), colors: [n.n800, n.n900]),
              ),
              clipBehavior: Clip.antiAlias,
              alignment: Alignment.center,
              child: primary == null
                  ? PhosphorIcon(PhosphorIconsDuotone.package, size: 24, color: n.n500)
                  : SizedBox.expand(child: ProductImageView(image: primary, productId: p.id)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.name, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500, color: n.text, height: 1.2)),
                  const SizedBox(height: 2),
                  Text([p.sku, if (catS.isNotEmpty) catS, p.uom].join(' · '), style: TextStyle(fontSize: 12, color: n.n400)),
                  const SizedBox(height: 6),
                  NxTag(active ? 'Active' : 'Inactive', tone: active ? Tone.ok : Tone.neutral),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            if (canManage)
              NxButton(label: 'Edit', small: true, icon: PhosphorIconsRegular.pencilSimple, onPressed: () => showProductForm(context, product: p)),
            if (active && (user?.can('inventory.receive') ?? false))
              NxButton(label: 'Receive', small: true, icon: PhosphorIconsRegular.boxArrowDown, onPressed: () => showReceiveSheet(context, productId: p.id)),
            if (user?.can('inventory.view') ?? false)
              NxButton(
                label: 'Where is it?',
                small: true,
                icon: PhosphorIconsRegular.mapPin,
                onPressed: () {
                  ref.read(nxListStatesProvider.notifier).preset('inventory', filters: {'pid': p.id});
                  final router = GoRouter.of(context);
                  Navigator.of(context).pop();
                  router.go(RoutePaths.inventory);
                },
              ),
            NxButton(label: 'QR label', small: true, icon: PhosphorIconsRegular.qrCode, onPressed: () => showQrLabelDialog(context, productLabel(p))),
            if (canManage && p.trackingMode == TrackingMode.serial)
              NxButton(
                label: 'Unit labels',
                small: true,
                icon: PhosphorIconsRegular.stackPlus,
                onPressed: () => showGenerateUnitLabelsDialog(context, p),
              ),
            if (p.trackingMode == TrackingMode.serial && (user?.can('inventory.view') ?? false))
              NxButton(
                label: 'View units',
                small: true,
                icon: PhosphorIconsRegular.listChecks,
                onPressed: () => showProductUnitsSheet(context, p),
              ),
            if (canManage && active)
              NxButton(label: 'Deactivate', small: true, icon: PhosphorIconsRegular.prohibit, color: n.bad, onPressed: () => setStatus(false)),
            if (canManage && !active)
              NxButton.primary(label: 'Reactivate', small: true, icon: PhosphorIconsRegular.checkCircle, onPressed: () => setStatus(true)),
          ],
        ),
        const SizedBox(height: 14),
        Container(
          decoration: BoxDecoration(color: n.surface, borderRadius: BorderRadius.circular(NxRadius.md)),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              Row(
                children: [
                  _Fact(label: 'On hand', value: '${fmtNum(p.totalOnHand)} ${p.uom}', color: low ? n.bad : null),
                  _Fact(label: 'Minimum', value: fmtNum(p.minStockLevel)),
                ],
              ),
              Row(
                children: [
                  _Fact(label: 'Selling price', value: fmtMoney(p.sellingPrice)),
                  _Fact(label: 'Cost · margin', value: '${p.costPrice == null ? '—' : fmtMoney(p.costPrice)} · $margin'),
                ],
              ),
            ],
          ),
        ),
        if (p.sale != null) ...[const SizedBox(height: 10), _SaleBanner(sale: p.sale!)],
        const SizedBox(height: 16),
        _H3('Stock by location'),
        stock.when(
          loading: () => const LinearProgressIndicator(minHeight: 2),
          error: (e, _) => Text(e is AppError ? e.message : 'Could not load stock.', style: TextStyle(fontSize: 12, color: n.bad)),
          data: (rows) => rows.isEmpty
              ? Text('No stock yet — receive some to place it.', style: TextStyle(fontSize: 12, color: n.n400))
              : Container(
                  decoration: BoxDecoration(color: n.surface, borderRadius: BorderRadius.circular(NxRadius.md)),
                  child: Column(
                    children: [
                      for (final r in rows)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: n.n900))),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      r.path.length > 2 ? r.path.sublist(r.path.length - 2).map((l) => l.name).join(' › ') : r.path.map((l) => l.name).join(' › '),
                                      style: TextStyle(fontSize: 13, color: n.text),
                                    ),
                                    Text('${r.balance.location.code} · ${r.warehouseName}', style: TextStyle(fontSize: 11, color: n.n500, fontFamily: NxText.mono)),
                                  ],
                                ),
                              ),
                              Text('${fmtNum(r.balance.reserved)} res.', style: TextStyle(fontSize: 12, color: n.n400, fontFeatures: tabular)),
                              const SizedBox(width: 14),
                              Text(fmtNum(r.balance.onHand), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: n.text, fontFeatures: tabular)),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
        ),
        const SizedBox(height: 16),
        _H3('Recent movements'),
        moves.when(
          loading: () => const LinearProgressIndicator(minHeight: 2),
          error: (e, _) => Text(e is AppError ? e.message : 'Could not load movements.', style: TextStyle(fontSize: 12, color: n.bad)),
          data: (rows) => rows.isEmpty
              ? Text('No movements on record.', style: TextStyle(fontSize: 12, color: n.n400))
              : Column(
                  children: [
                    for (final x in rows)
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 7),
                        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: n.n900))),
                        child: Row(
                          children: [
                            NxTag(x.type.replaceAll('_', ' '), tone: txTone(x.type), small: true),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                [
                                  if (x.fromCode != null && x.toCode != null) '${x.fromCode} → ${x.toCode}' else if (x.toCode != null) 'to ${x.toCode}' else if (x.fromCode != null) 'from ${x.fromCode}',
                                  ?x.performedByName,
                                  fmtDate(x.createdAt),
                                ].join(' · '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 12, color: n.n400),
                              ),
                            ),
                            Text(
                              x.type == 'RECEIVE' || x.type == 'RETURN' ? '+${fmtNum(x.quantity)}' : fmtNum(x.quantity),
                              style: TextStyle(fontSize: 13, color: n.text, fontFeatures: tabular),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
        if (p.attributes.isNotEmpty) ...[
          const SizedBox(height: 16),
          _H3('Attributes'),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final a in p.attributes)
                NxTag(
                  '${a.attributeType.name}: ${a.value}${a.attributeType.unit == null || a.attributeType.unit!.isEmpty ? '' : ' ${a.attributeType.unit}'}',
                  tone: Tone.neutral,
                ),
            ],
          ),
        ],
        if ((p.description ?? '').isNotEmpty) ...[
          const SizedBox(height: 16),
          _H3('Description'),
          Text(p.description!, style: TextStyle(fontSize: 13, color: n.n300, height: 1.5)),
        ],
        if (p.images.length > 1) ...[
          const SizedBox(height: 16),
          _H3('Images'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final img in p.images)
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: n.n900,
                    borderRadius: BorderRadius.circular(NxRadius.md),
                    border: Border.all(color: img.isPrimary ? n.accent : n.n800),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: ProductImageView(image: img, productId: p.id),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(border: Border(right: BorderSide(color: n.n800), bottom: BorderSide(color: n.n800))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 11, color: n.n400)),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: color ?? n.text, fontFeatures: tabular),
            ),
          ],
        ),
      ),
    );
  }
}

class _H3 extends StatelessWidget {
  const _H3(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(text, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: context.nx.text)),
  );
}

/// On the product sheet when `p.sale` is set — the campaign terms, read-only (managed from the
/// Sale Campaigns screen, not here).
class _SaleBanner extends StatelessWidget {
  const _SaleBanner({required this.sale});

  final ActiveSale sale;

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    final discount = switch (sale.discountType) {
      SaleDiscountType.percent => '${fmtPlain(sale.discountValue)}% off',
      SaleDiscountType.fixedAmount => '${fmtMoney(sale.discountValue)} off',
      SaleDiscountType.fixedPrice => 'now ${fmtMoney(sale.discountValue)}',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: n.warn.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(NxRadius.md)),
      child: Row(
        children: [
          PhosphorIcon(PhosphorIconsFill.tag, size: 18, color: n.warn),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('On sale — ${sale.campaignName}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: n.text)),
                Text(
                  [discount, if (sale.minQuantity > 1) 'min ${fmtNum(sale.minQuantity)}', if (sale.eligibility == SaleEligibility.restricted) 'restricted'].join(' · ') +
                      (sale.effectivePrice != null ? ' → ${fmtMoney(sale.effectivePrice!)}' : ''),
                  style: TextStyle(fontSize: 11, color: n.n400),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
