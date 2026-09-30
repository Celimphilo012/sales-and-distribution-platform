import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../app_shell/responsive_app_shell.dart';
import '../../../core/error/app_error.dart';
import '../../../core/theme/nocturne.dart';
import '../../../routing/route_paths.dart';
import '../../../shared/export/report_export.dart';
import '../../../shared/nx/nx_format.dart';
import '../../../shared/nx/nx_list_page.dart';
import '../../../shared/nx/nx_overlays.dart';
import '../../../shared/nx/nx_primitives.dart';
import '../../inventory/data/inventory_providers.dart';
import '../../inventory/domain/inventory_balance.dart';
import '../../inventory/domain/ledger_entry.dart';
import '../../locations/data/leaf_locations_provider.dart';
import '../../products/domain/product.dart';
import '../../products/domain/product_status.dart';
import '../../products/presentation/products_list_providers.dart';
import '../../settings/data/branding_api.dart';
import '../../stock_adjustments/data/stock_adjustments_providers.dart';
import '../../stock_adjustments/domain/stock_adjustment.dart';
import '../../stock_counts/data/stock_counts_providers.dart';
import '../../stock_counts/domain/stock_count.dart';
import '../data/export_branding.dart';

/// Everything the reports are built from — loaded once for the screen. A
/// source the viewer may not read comes back empty rather than failing all.
class ReportSources {
  const ReportSources({
    required this.balances,
    required this.products,
    required this.leaves,
    required this.receipts,
    required this.transfers,
    required this.adjustments,
    required this.counts,
  });

  final List<InventoryBalance> balances;
  final List<Product> products;
  final List<LeafLocation> leaves;
  final List<LedgerEntry> receipts;
  final List<LedgerEntry> transfers;
  final List<StockAdjustment> adjustments;
  final List<StockCount> counts;
}

Future<List<T>> _orEmpty<T>(Future<List<T>> f) => f.catchError((Object _) => <T>[]);

final reportSourcesProvider = FutureProvider.autoDispose<ReportSources>((ref) async {
  final results = await Future.wait<List<Object?>>([
    _orEmpty(ref.watch(allBalancesProvider.future)),
    _orEmpty(ref.watch(productsListProvider.future)),
    _orEmpty(ref.watch(leafLocationsProvider.future)),
    _orEmpty(ref.watch(ledgerByTypeProvider('RECEIVE').future)),
    _orEmpty(ref.watch(ledgerByTypeProvider('TRANSFER').future)),
    _orEmpty(ref.watch(stockAdjustmentsListProvider(null).future)),
    _orEmpty(ref.watch(stockCountsListProvider(null).future)),
  ]);
  return ReportSources(
    balances: results[0].cast<InventoryBalance>(),
    products: results[1].cast<Product>(),
    leaves: results[2].cast<LeafLocation>(),
    receipts: results[3].cast<LedgerEntry>(),
    transfers: results[4].cast<LedgerEntry>(),
    adjustments: results[5].cast<StockAdjustment>(),
    counts: results[6].cast<StockCount>(),
  );
});

class ReportDef {
  const ReportDef(this.id, this.name, this.description, this.category, this.icon);

  final String id;
  final String name;
  final String description;
  final String category;
  final IconData icon;
}

const kReports = [
  ReportDef('soh', 'Stock on hand', 'Every product balance by location with reserved and available', 'Stock', PhosphorIconsDuotone.cube),
  ReportDef('low', 'Low stock', 'Active products below their minimum level, with shortfall', 'Stock', PhosphorIconsDuotone.warning),
  ReportDef('val', 'Inventory valuation', 'On-hand quantity × cost price per product, with total', 'Finance', PhosphorIconsDuotone.coins),
  ReportDef('mov', 'Stock movements', 'Receipts and transfers, newest first', 'Movements', PhosphorIconsDuotone.arrowsLeftRight),
  ReportDef('adj', 'Adjustments register', 'Pending, approved and rejected adjustments with reviewers', 'Control', PhosphorIconsDuotone.slidersHorizontal),
  ReportDef('cnt', 'Stock count variances', 'Counts by location with counted items and net variance', 'Control', PhosphorIconsDuotone.listChecks),
  ReportDef('util', 'Location utilisation', 'Units and fill against capacity for every storage slot', 'Warehouse', PhosphorIconsDuotone.treeStructure),
];

ReportData buildReport(ReportDef def, ReportSources s) {
  const t = ColType.text;
  const nu = ColType.num;
  final leaves = {for (final l in s.leaves) l.id: l};
  String pathOf(String locationId, String fallback) => leaves[locationId]?.pathLabel ?? fallback;
  ReportData make(List<ReportColumn> cols, List<List<Object?>> rows, {int? totalsFrom, String? note}) =>
      ReportData(title: def.name, description: def.description, columns: cols, rows: rows, totalsFrom: totalsFrom, note: note);
  final active = s.products.where((p) => p.status == ProductStatus.active).toList()..sort((a, b) => a.sku.compareTo(b.sku));

  switch (def.id) {
    case 'soh':
      final rows = [
        for (final b in s.balances.where((b) => b.onHand != 0 || b.reserved != 0))
          [b.product.sku, b.product.name, b.location.code, pathOf(b.locationId, b.location.name), b.onHand, b.reserved, b.available],
      ]..sort((a, b) => '${a[0]}${a[2]}'.compareTo('${b[0]}${b[2]}'));
      return make([
        const ReportColumn('SKU', t, 12),
        const ReportColumn('Product', t, 28),
        const ReportColumn('Location', t, 12),
        const ReportColumn('Path', t, 34),
        const ReportColumn('On hand', nu, 10),
        const ReportColumn('Reserved', nu, 10),
        const ReportColumn('Available', nu, 10),
      ], rows, totalsFrom: 4);
    case 'low':
      return make([
        const ReportColumn('SKU', t, 12),
        const ReportColumn('Product', t, 30),
        const ReportColumn('UOM', t, 8),
        const ReportColumn('On hand', nu, 10),
        const ReportColumn('Minimum', nu, 10),
        const ReportColumn('Shortfall', nu, 10),
      ], [
        for (final p in active.where((p) => p.totalOnHand < p.minStockLevel))
          [p.sku, p.name, p.uom, p.totalOnHand, p.minStockLevel, p.minStockLevel - p.totalOnHand],
      ], totalsFrom: 5);
    case 'val':
      final costed = active.where((p) => p.costPrice != null).toList();
      final missing = active.length - costed.length;
      return make(
        [
          const ReportColumn('SKU', t, 12),
          const ReportColumn('Product', t, 30),
          const ReportColumn('On hand', nu, 10),
          const ReportColumn('Cost price', ColType.money, 12),
          const ReportColumn('Value', ColType.money, 14),
        ],
        [for (final p in costed) [p.sku, p.name, p.totalOnHand, p.costPrice, p.totalOnHand * p.costPrice!]],
        totalsFrom: 4,
        note: missing > 0 ? '$missing product(s) without a cost price excluded.' : null,
      );
    case 'mov':
      final all = [...s.receipts, ...s.transfers]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return make([
        const ReportColumn('Date', t, 17),
        const ReportColumn('Type', t, 10),
        const ReportColumn('Reference', t, 16),
        const ReportColumn('Product', t, 26),
        const ReportColumn('Qty', nu, 8),
        const ReportColumn('From', t, 12),
        const ReportColumn('To', t, 12),
        const ReportColumn('By', t, 16),
      ], [
        for (final m in all)
          [fmtDateTime(m.createdAt.toLocal()), m.type, m.reference ?? '', m.productName, m.quantity, m.fromCode ?? '', m.toCode ?? '', m.performedByName ?? ''],
      ]);
    case 'adj':
      final list = [...s.adjustments]..sort((a, b) => b.requestedAt.compareTo(a.requestedAt));
      return make([
        const ReportColumn('Requested', t, 17),
        const ReportColumn('Product', t, 26),
        const ReportColumn('Change', nu, 9),
        const ReportColumn('Bucket', t, 10),
        const ReportColumn('Location', t, 12),
        const ReportColumn('Status', t, 10),
        const ReportColumn('Requested by', t, 16),
        const ReportColumn('Reviewer', t, 16),
      ], [
        for (final a in list)
          [
            fmtDateTime(a.requestedAt.toLocal()),
            a.product.name,
            a.direction == AdjustmentDirection.increase ? a.delta : -a.delta,
            a.bucket.label.toLowerCase(),
            a.location.code,
            a.status.label,
            a.requestedByUser.fullName,
            a.reviewedByUser?.fullName ?? '',
          ],
      ]);
    case 'cnt':
      final list = [...s.counts]..sort((a, b) => b.startedAt.compareTo(a.startedAt));
      return make([
        const ReportColumn('Location', t, 12),
        const ReportColumn('Path', t, 30),
        const ReportColumn('Started', t, 17),
        const ReportColumn('Started by', t, 16),
        const ReportColumn('Items', nu, 8),
        const ReportColumn('Counted', nu, 8),
        const ReportColumn('Variance', nu, 9),
        const ReportColumn('Status', t, 12),
      ], [
        for (final c in list)
          () {
            final done = c.status == StockCountStatus.submitted;
            return [
              c.location.code,
              pathOf(c.locationId, c.location.name),
              fmtDateTime(c.startedAt.toLocal()),
              c.startedByUser.fullName,
              c.items.length,
              done ? c.items.length : 0,
              done ? c.items.fold<double>(0, (x, i) => x + (i.difference ?? 0)) : 0,
              done ? 'Submitted' : 'In progress',
            ];
          }(),
      ], totalsFrom: 4);
    case 'util':
      final units = <String, double>{};
      for (final b in s.balances) {
        units[b.locationId] = (units[b.locationId] ?? 0) + b.onHand;
      }
      return make([
        const ReportColumn('Code', t, 12),
        const ReportColumn('Location', t, 34),
        const ReportColumn('Warehouse', t, 18),
        const ReportColumn('Type', t, 10),
        const ReportColumn('Units', nu, 10),
        const ReportColumn('Capacity', nu, 10),
        const ReportColumn('Fill %', ColType.pct, 9),
      ], [
        for (final l in s.leaves)
          () {
            final u = units[l.id] ?? 0;
            final c = (l.location.capacity ?? 0).toDouble();
            return [l.code, l.pathLabel, l.warehouse.name, l.location.locationType, u, c, c > 0 ? u / c : 0];
          }(),
      ], totalsFrom: 4);
  }
  return make(const [], const []);
}

/// "When was each report last exported" for this session.
class _Exports extends Notifier<Map<String, String>> {
  @override
  Map<String, String> build() => const {};

  void mark(String id, String what) => state = {...state, id: what};
}

final _exportsProvider = NotifierProvider<_Exports, Map<String, String>>(_Exports.new);

Future<void> _export(WidgetRef ref, ReportData rep, String id, {required bool pdf}) async {
  NxToast.info('Preparing ${pdf ? 'PDF' : 'Excel'}…', '${rep.title} · ${rep.rows.length} rows');
  try {
    final branding = await loadExportBranding(ref);
    final name = await downloadReport(rep, branding, pdf: pdf);
    ref.read(_exportsProvider.notifier).mark(id, '${pdf ? 'PDF' : 'Excel'} · ${fmtTime(DateTime.now())}');
    NxToast.ok('${pdf ? 'PDF' : 'Excel'} downloaded', name);
  } on AppError catch (e) {
    NxToast.error('Export failed', e.message);
  } catch (e) {
    NxToast.error('Export failed', '$e');
  }
}

class _Row {
  _Row(this.def, this.data, this.last);

  final ReportDef def;
  final ReportData data;
  final String? last;
}

/// Reports (prototype `reports`) — seven reports over live data; each
/// previews in a sheet and exports to PDF and Excel with the company logo
/// and name (Settings → Report branding) in the header.
class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = context.nx;
    final async = ref.watch(reportSourcesProvider);
    final exports = ref.watch(_exportsProvider);
    final branding = ref.watch(brandingProvider).value;

    return NxPageScroll(
      onRefresh: () async => invalidateStockViews(ref),
      child: async.when(
        loading: () => const NxLoading(message: 'Gathering report data…'),
        error: (e, _) => NxError(
          message: e is AppError ? e.message : 'Could not load report data.',
          onRetry: () => ref.invalidate(reportSourcesProvider),
        ),
        data: (sources) {
          final rows = [for (final d in kReports) _Row(d, buildReport(d, sources), exports[d.id])];
          final cats = {for (final d in kReports) d.category}.toList();
          List<NxRowAction> acts(_Row r) => [
            NxRowAction(icon: PhosphorIconsRegular.filePdf, label: 'PDF', text: 'PDF', onPressed: () => _export(ref, r.data, r.def.id, pdf: true)),
            NxRowAction(icon: PhosphorIconsRegular.microsoftExcelLogo, label: 'Excel', text: 'Excel', onPressed: () => _export(ref, r.data, r.def.id, pdf: false)),
          ];

          return NxListPage<_Row>(
            stateKey: 'reports',
            title: 'Reports',
            sub: 'Every report exports to PDF and Excel with your logo in the header.',
            actions: [
              NxButton(label: 'Branding', icon: PhosphorIconsRegular.image, onPressed: () => context.go('${RoutePaths.settings}?section=branding')),
            ],
            rows: rows,
            search: (r) => '${r.def.name} ${r.def.description}',
            searchPlaceholder: 'Report name',
            stats: (rs) => [
              NxStat('Reports', fmtNum(rs.length)),
              NxStat('Rows available', fmtNum(rs.fold<int>(0, (s, r) => s + r.data.rows.length))),
              NxStat('Exported this session', fmtNum(exports.length), color: n.a300),
              const NxStat('Formats', 'PDF · Excel'),
              NxStat('Logo', branding?.hasLogo ?? false ? 'Custom' : 'Default', sub: 'change in Settings'),
            ],
            quick: NxQuick(get: (r) => r.def.category, options: [('', 'All'), for (final c in cats) (c, c)]),
            filters: [
              NxMultiFilter('cat', 'Category', options: [for (final c in cats) (c, c)], get: (r) => r.def.category),
              NxRangeFilter('rows', 'Rows', get: (r) => r.data.rows.length),
              NxToggleFilter('exp', 'History', text: 'Exported this session', get: (r) => r.last != null),
            ],
            columns: [
              NxColumn(key: 'name', label: 'Report', sort: (r) => r.def.name, cell: (r) => NxCellText(r.def.name, weight: FontWeight.w500, sub: r.def.description)),
              NxColumn(
                key: 'cat',
                label: 'Category',
                hide: NxHide.md,
                sort: (r) => r.def.category,
                cell: (r) => Align(alignment: Alignment.centerLeft, child: NxTag(r.def.category, tone: Tone.info)),
              ),
              NxColumn(key: 'rows', label: 'Rows', align: TextAlign.right, sort: (r) => r.data.rows.length, cell: (r) => NxCellText(fmtNum(r.data.rows.length), align: TextAlign.right)),
              NxColumn(key: 'last', label: 'Last export', hide: NxHide.wide, cell: (r) => NxCellText(r.last ?? 'Not yet', color: r.last == null ? n.n500 : null)),
              NxColumn(key: 'act', label: '', width: 170, cell: (r) => NxRowActions(acts(r), withText: true)),
            ],
            listRow: (r) => NxListRowSpec(
              icon: r.def.icon,
              iconColor: n.a400,
              title: r.def.name,
              sub: r.def.description,
              right: '${r.data.rows.length} rows',
              rightSub: r.last ?? r.def.category,
              actions: acts(r),
            ),
            card: (r) => NxCardSpec(
              icon: r.def.icon,
              title: r.def.name,
              sub: r.def.description,
              metrics: [('Rows', fmtNum(r.data.rows.length), null), ('Category', r.def.category, null)],
              actions: acts(r),
            ),
            onOpen: (r) => _showReportSheet(context, ref, r.def.id, r.data),
            emptyTitle: 'No reports match',
            emptyMessage: 'Try adjusting your search or filters.',
          );
        },
      ),
    );
  }
}

// ─── Preview sheet ──────────────────────────────────────────────────────────

// The preview is drawn as the printed page looks — light, whatever the theme.
const _paper = Color(0xFFF8F9FD);
const _ink = Color(0xFF1F2127);
const _muted = Color(0xFF6B6F80);
const _grid = Color(0xFFE2E5F0);
const _head = Color(0xFF2B2741);
const _headInk = Color(0xFFF5F4FF);
const _foot = Color(0xFFECEEF7);

void _showReportSheet(BuildContext context, WidgetRef ref, String id, ReportData rep) => showNxSheet<void>(
  context,
  kicker: 'Report',
  wide: true,
  builder: (ctx) => Consumer(
    builder: (ctx, ref, _) {
      final n = ctx.nx;
      final branding = ref.watch(brandingProvider).value;
      final logo = ref.watch(brandingLogoProvider).value;
      final totals = rep.totals;
      Alignment al(int i) => rep.columns[i].type == ColType.text ? Alignment.centerLeft : Alignment.centerRight;
      Widget cell(String v, int i, {bool head = false, bool foot = false}) => Container(
        alignment: al(i),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        color: head ? _head : (foot ? _foot : null),
        child: Text(
          v,
          maxLines: 1,
          style: TextStyle(
            fontSize: 10.5,
            color: head ? _headInk : _ink,
            fontWeight: head || foot ? FontWeight.w600 : FontWeight.w400,
            fontFeatures: tabular,
          ),
        ),
      );
      const shown = 14;
      return NxSheetBody(
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 180),
                child: Text(rep.title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500, color: n.text)),
              ),
              NxButton(label: 'Export Excel', icon: PhosphorIconsRegular.microsoftExcelLogo, onPressed: () => _export(ref, rep, id, pdf: false)),
              NxButton.primary(label: 'Export PDF', icon: PhosphorIconsRegular.filePdf, onPressed: () => _export(ref, rep, id, pdf: true)),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
            decoration: BoxDecoration(color: _paper, borderRadius: BorderRadius.circular(6), boxShadow: n.shadowMd),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.only(bottom: 10),
                  decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFD6D9E7)))),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 34,
                        height: 34,
                        child: logo != null
                            ? Image.memory(logo, fit: BoxFit.contain, errorBuilder: (_, _, _) => const _DefaultMark())
                            : const _DefaultMark(),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(branding?.companyName ?? 'Warehouse System', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _ink)),
                            Text('Generated ${exportStamp()}', style: const TextStyle(fontSize: 11, color: _muted)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(rep.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: _ink)),
                Text('${rep.description}${rep.note == null ? '' : ' ${rep.note}'}', style: const TextStyle(fontSize: 11, color: _muted)),
                const SizedBox(height: 10),
                if (rep.rows.isEmpty)
                  const Text('No rows.', style: TextStyle(fontSize: 11, color: _muted))
                else
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Table(
                      defaultColumnWidth: const IntrinsicColumnWidth(),
                      border: const TableBorder(horizontalInside: BorderSide(color: _grid)),
                      children: [
                        TableRow(children: [for (var i = 0; i < rep.columns.length; i++) cell(rep.columns[i].header, i, head: true)]),
                        for (final r in rep.rows.take(shown))
                          TableRow(children: [for (var i = 0; i < rep.columns.length; i++) cell(formatCell(r[i], rep.columns[i].type), i)]),
                        if (totals != null)
                          TableRow(
                            children: [
                              for (var i = 0; i < rep.columns.length; i++)
                                cell(totals[i] is num ? formatCell(totals[i], rep.columns[i].type) : '${totals[i]}', i, foot: true),
                            ],
                          ),
                      ],
                    ),
                  ),
                if (rep.rows.length > shown) ...[
                  const SizedBox(height: 8),
                  Text('+ ${rep.rows.length - shown} more rows in the export', style: const TextStyle(fontSize: 11, color: _muted)),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '${fmtNum(rep.rows.length)} rows. Change the logo and company name in Settings › Report branding.',
            style: TextStyle(fontSize: 11, color: n.n500),
          ),
        ],
      );
    },
  ),
);

class _DefaultMark extends StatelessWidget {
  const _DefaultMark();

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(color: _head, borderRadius: BorderRadius.circular(8)),
    alignment: Alignment.center,
    child: const Icon(PhosphorIconsBold.warehouse, size: 18, color: Color(0xFFB5ABFC)),
  );
}
