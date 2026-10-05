import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../app_shell/responsive_app_shell.dart';
import '../../../core/error/app_error.dart';
import '../../../core/theme/nocturne.dart';
import '../../../routing/route_paths.dart';
import '../../../shared/export/report_export.dart';
import '../../../shared/nx/nx_form.dart';
import '../../../shared/nx/nx_format.dart';
import '../../../shared/nx/nx_list_page.dart';
import '../../../shared/nx/nx_overlays.dart';
import '../../../shared/nx/nx_primitives.dart';
import '../../orders/data/orders_providers.dart';
import '../../orders/domain/order.dart';
import '../../orders/presentation/order_status_tone.dart';
import '../../payments/data/payments_api.dart';
import '../../payments/domain/payment.dart';
import '../../settings/data/branding_api.dart';
import '../data/export_branding.dart';

/// The period every report covers (orders by order date, payments by date paid).
enum ReportPeriod { all, thisMonth, last30, thisYear }

extension on ReportPeriod {
  String get label => switch (this) {
    ReportPeriod.all => 'All time',
    ReportPeriod.thisMonth => 'This month',
    ReportPeriod.last30 => 'Last 30 days',
    ReportPeriod.thisYear => 'This year',
  };

  bool includes(DateTime d) {
    final now = DateTime.now();
    final l = d.toLocal();
    return switch (this) {
      ReportPeriod.all => true,
      ReportPeriod.thisMonth => l.year == now.year && l.month == now.month,
      ReportPeriod.last30 => l.isAfter(now.subtract(const Duration(days: 30))),
      ReportPeriod.thisYear => l.year == now.year,
    };
  }
}

/// What the reports are built from — loaded once. A source the viewer may
/// not read comes back empty rather than failing every report.
class ReportSources {
  const ReportSources({required this.orders, required this.payments});

  final List<Order> orders;
  final List<Payment> payments;
}

final reportSourcesProvider = FutureProvider.autoDispose<ReportSources>((ref) async {
  Future<List<T>> orEmpty<T>(Future<List<T>> f) => f.catchError((Object _) => <T>[]);
  final orders = await orEmpty(ref.watch(allOrdersProvider.future));
  final payments = await orEmpty(ref.watch(allPaymentsProvider.future));
  return ReportSources(orders: orders, payments: payments);
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
  ReportDef('orders', 'Orders register', 'Every order in the period with status, total, paid and due', 'Sales', PhosphorIconsDuotone.receipt),
  ReportDef('status', 'Orders by status', 'How many orders sit in each status, and their value', 'Sales', PhosphorIconsDuotone.chartBar),
  ReportDef('customers', 'Sales by customer', 'What each customer bought, paid and still owes', 'Sales', PhosphorIconsDuotone.addressBook),
  ReportDef('consultants', 'Sales by consultant', 'Orders and value per consultant', 'Sales', PhosphorIconsDuotone.userCircle),
  ReportDef('products', 'Sales by product', 'Units and value ordered per product', 'Sales', PhosphorIconsDuotone.package),
  ReportDef('sale-performance', 'Sale performance', 'Units sold at a discount, by campaign, and the revenue given up', 'Sales', PhosphorIconsDuotone.tag),
  ReportDef('payments', 'Payments received', 'Every recorded payment by date, method and reference', 'Money', PhosphorIconsDuotone.wallet),
  ReportDef('owed', 'Outstanding balances', 'Orders still owed money, largest first', 'Money', PhosphorIconsDuotone.coins),
];

ReportData buildReport(ReportDef def, ReportSources s, ReportPeriod period) {
  const t = ColType.text;
  const nu = ColType.num;
  const m = ColType.money;
  final orders = s.orders.where((o) => period.includes(o.orderDate)).toList()..sort((a, b) => b.orderDate.compareTo(a.orderDate));
  final live = orders.where((o) => orderCounts(o.status)).toList();
  double due(Order o) => (o.total - o.amountPaid).clamp(0, double.infinity).toDouble();
  ReportData make(List<ReportColumn> cols, List<List<Object?>> rows, {int? totalsFrom, String? note}) => ReportData(
    title: def.name,
    description: '${def.description} · ${period.label}',
    columns: cols,
    rows: rows,
    totalsFrom: totalsFrom,
    note: note,
  );

  switch (def.id) {
    case 'orders':
      return make([
        const ReportColumn('Order', t, 14),
        const ReportColumn('Date', t, 12),
        const ReportColumn('Customer', t, 26),
        const ReportColumn('Consultant', t, 18),
        const ReportColumn('Status', t, 16),
        const ReportColumn('Payment', t, 14),
        const ReportColumn('Total', m, 13),
        const ReportColumn('Paid', m, 13),
        const ReportColumn('Due', m, 13),
      ], [
        for (final o in orders)
          [
            o.orderNumber,
            fmtDate(o.orderDate.toLocal()),
            o.customer.name,
            o.consultant?.fullName ?? '',
            o.status.label,
            o.paymentStatus.label,
            o.total,
            o.amountPaid,
            orderCounts(o.status) ? due(o) : 0,
          ],
      ], totalsFrom: 6);
    case 'status':
      return make([
        const ReportColumn('Status', t, 22),
        const ReportColumn('Orders', nu, 10),
        const ReportColumn('Value', m, 16),
      ], [
        for (final st in OrderStatus.values)
          if (orders.where((o) => o.status == st).toList() case final list when list.isNotEmpty)
            [st.label, list.length, list.fold<double>(0, (a, o) => a + o.total)],
      ], totalsFrom: 1);
    case 'customers':
      final by = <String, List<Order>>{};
      for (final o in live) {
        by.putIfAbsent(o.customerId, () => []).add(o);
      }
      final rows = [
        for (final list in by.values)
          [
            list.first.customer.name,
            list.first.customer.phone ?? '',
            list.length,
            list.fold<double>(0, (a, o) => a + o.total),
            list.fold<double>(0, (a, o) => a + o.amountPaid),
            list.fold<double>(0, (a, o) => a + due(o)),
          ],
      ]..sort((a, b) => (b[3] as double).compareTo(a[3] as double));
      return make([
        const ReportColumn('Customer', t, 28),
        const ReportColumn('Phone', t, 16),
        const ReportColumn('Orders', nu, 9),
        const ReportColumn('Bought', m, 14),
        const ReportColumn('Paid', m, 14),
        const ReportColumn('Owes', m, 14),
      ], rows, totalsFrom: 2, note: 'Drafts, rejected and cancelled orders excluded.');
    case 'consultants':
      final by = <String, List<Order>>{};
      for (final o in live) {
        by.putIfAbsent(o.consultant?.fullName ?? '—', () => []).add(o);
      }
      final rows = [
        for (final e in by.entries)
          [e.key, e.value.length, e.value.fold<double>(0, (a, o) => a + o.total), e.value.fold<double>(0, (a, o) => a + o.amountPaid)],
      ]..sort((a, b) => (b[2] as double).compareTo(a[2] as double));
      return make([
        const ReportColumn('Consultant', t, 24),
        const ReportColumn('Orders', nu, 9),
        const ReportColumn('Sold', m, 15),
        const ReportColumn('Collected', m, 15),
      ], rows, totalsFrom: 1, note: 'Drafts, rejected and cancelled orders excluded.');
    case 'products':
      final units = <String, double>{};
      final value = <String, double>{};
      for (final o in live) {
        for (final i in o.items) {
          final name = i.productName ?? i.productId;
          units[name] = (units[name] ?? 0) + i.quantityOrdered;
          value[name] = (value[name] ?? 0) + i.lineTotal;
        }
      }
      final rows = [for (final name in units.keys) [name, units[name], value[name]]]..sort((a, b) => (b[2] as double).compareTo(a[2] as double));
      return make([
        const ReportColumn('Product', t, 34),
        const ReportColumn('Units', nu, 10),
        const ReportColumn('Value', m, 15),
      ], rows, totalsFrom: 1, note: 'Drafts, rejected and cancelled orders excluded.');
    case 'sale-performance':
      final units = <String, double>{};
      final revenueGivenUp = <String, double>{};
      final saleRevenue = <String, double>{};
      for (final o in live) {
        for (final i in o.items.where((i) => i.wasDiscounted)) {
          final name = i.saleCampaignName ?? i.saleCampaignId!;
          units[name] = (units[name] ?? 0) + i.quantityOrdered;
          revenueGivenUp[name] = (revenueGivenUp[name] ?? 0) + (i.originalUnitPrice! - i.unitPrice) * i.quantityOrdered;
          saleRevenue[name] = (saleRevenue[name] ?? 0) + i.lineTotal;
        }
      }
      final rows = [for (final name in units.keys) [name, units[name], saleRevenue[name], revenueGivenUp[name]]]
        ..sort((a, b) => (b[2] as double).compareTo(a[2] as double));
      return make(
        [
          const ReportColumn('Campaign', t, 28),
          const ReportColumn('Units sold', nu, 14),
          const ReportColumn('Revenue at sale price', m, 20),
          const ReportColumn('Revenue given up', m, 20),
        ],
        rows,
        totalsFrom: 1,
        note: rows.isEmpty ? 'No discounted lines in this period.' : 'Drafts, rejected and cancelled orders excluded. "Revenue given up" is the discount applied, at the quantities actually ordered.',
      );
    case 'payments':
      final pays = s.payments.where((p) => period.includes(p.paidAt)).toList()..sort((a, b) => b.paidAt.compareTo(a.paidAt));
      final voided = pays.where((p) => p.isVoided).length;
      return make(
        [
          const ReportColumn('Paid on', t, 17),
          const ReportColumn('Order', t, 14),
          const ReportColumn('Customer', t, 24),
          const ReportColumn('Method', t, 18),
          const ReportColumn('Reference', t, 18),
          const ReportColumn('Recorded by', t, 18),
          const ReportColumn('Amount', m, 14),
        ],
        [
          for (final p in pays.where((p) => !p.isVoided))
            [fmtDateTime(p.paidAt.toLocal()), p.orderNumber ?? '', p.customerName ?? '', p.method.label, p.reference ?? '', p.recordedByName, p.amount],
        ],
        totalsFrom: 6,
        note: voided > 0 ? '$voided voided payment${voided == 1 ? '' : 's'} excluded.' : null,
      );
    case 'owed':
      final list = live.where((o) => due(o) > 0).toList()..sort((a, b) => due(b).compareTo(due(a)));
      return make([
        const ReportColumn('Order', t, 14),
        const ReportColumn('Customer', t, 26),
        const ReportColumn('Date', t, 12),
        const ReportColumn('Status', t, 16),
        const ReportColumn('Total', m, 13),
        const ReportColumn('Paid', m, 13),
        const ReportColumn('Due', m, 13),
      ], [
        for (final o in list) [o.orderNumber, o.customer.name, fmtDate(o.orderDate.toLocal()), o.status.label, o.total, o.amountPaid, due(o)],
      ], totalsFrom: 4);
  }
  return make(const [], const []);
}

class _Exports extends Notifier<Map<String, String>> {
  @override
  Map<String, String> build() => const {};

  void mark(String id, String what) => state = {...state, id: what};
}

final _exportsProvider = NotifierProvider<_Exports, Map<String, String>>(_Exports.new);

class _Period extends Notifier<ReportPeriod> {
  @override
  ReportPeriod build() => ReportPeriod.thisMonth;

  void set(ReportPeriod p) => state = p;
}

final _periodProvider = NotifierProvider<_Period, ReportPeriod>(_Period.new);

Future<void> _export(WidgetRef ref, ReportData rep, String id, ReportPeriod period, {required bool pdf}) async {
  NxToast.info('Preparing ${pdf ? 'PDF' : 'Excel'}…', '${rep.title} · ${rep.rows.length} rows');
  try {
    final branding = await loadExportBranding(ref, scope: period.label);
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

/// Reports — seven sales and money reports over live data for a chosen
/// period; each previews in a sheet and exports to PDF and Excel with the
/// company logo and name (Settings → Report branding) in the header.
class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = context.nx;
    final async = ref.watch(reportSourcesProvider);
    final exports = ref.watch(_exportsProvider);
    final period = ref.watch(_periodProvider);
    final branding = ref.watch(brandingProvider).value;

    return NxPageScroll(
      onRefresh: () async {
        invalidateOrders(ref);
        ref.invalidate(allPaymentsProvider);
      },
      child: async.when(
        loading: () => const NxLoading(message: 'Gathering report data…'),
        error: (e, _) => NxError(message: e is AppError ? e.message : 'Could not load report data.', onRetry: () => ref.invalidate(reportSourcesProvider)),
        data: (sources) {
          final rows = [for (final d in kReports) _Row(d, buildReport(d, sources, period), exports[d.id])];
          final cats = {for (final d in kReports) d.category}.toList();
          List<NxRowAction> acts(_Row r) => [
            NxRowAction(icon: PhosphorIconsRegular.filePdf, label: 'PDF', text: 'PDF', onPressed: () => _export(ref, r.data, r.def.id, period, pdf: true)),
            NxRowAction(icon: PhosphorIconsRegular.microsoftExcelLogo, label: 'Excel', text: 'Excel', onPressed: () => _export(ref, r.data, r.def.id, period, pdf: false)),
          ];
          final live = sources.orders.where((o) => orderCounts(o.status) && period.includes(o.orderDate));
          final collected = sources.payments.where((p) => !p.isVoided && period.includes(p.paidAt)).fold<double>(0, (s, p) => s + p.amount);

          return NxListPage<_Row>(
            stateKey: 'reports',
            title: 'Reports',
            sub: 'Every report exports to PDF and Excel with your logo in the header.',
            actions: [
              NxButton(label: 'Branding', icon: PhosphorIconsRegular.image, onPressed: () => context.go('${RoutePaths.settings}?section=branding')),
            ],
            aboveContent: Row(
              children: [
                Text('Period', style: TextStyle(fontSize: 12, color: n.n400)),
                const SizedBox(width: 10),
                Flexible(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: NxSeg<ReportPeriod>(
                      options: [for (final p in ReportPeriod.values) (p, p.label, null)],
                      value: period,
                      onChanged: (p) => ref.read(_periodProvider.notifier).set(p),
                    ),
                  ),
                ),
              ],
            ),
            rows: rows,
            search: (r) => '${r.def.name} ${r.def.description}',
            searchPlaceholder: 'Report name',
            stats: (rs) => [
              NxStat('Orders', fmtNum(live.length), sub: period.label.toLowerCase()),
              NxStat('Sold', fmtMoney(live.fold<double>(0, (s, o) => s + o.total))),
              NxStat('Collected', fmtMoney(collected), color: n.ok),
              NxStat('Exported this session', fmtNum(exports.length), color: n.a300),
              NxStat('Logo', branding?.hasLogo ?? false ? 'Custom' : 'Default', sub: 'change in Settings'),
            ],
            quick: NxQuick(get: (r) => r.def.category, options: [('', 'All'), for (final c in cats) (c, c)]),
            filters: [
              NxRangeFilter('rows', 'Rows', get: (r) => r.data.rows.length),
              NxToggleFilter('exp', 'History', text: 'Exported this session', get: (r) => r.last != null),
            ],
            columns: [
              NxColumn(key: 'name', label: 'Report', sort: (r) => r.def.name, cell: (r) => NxCellText(r.def.name, weight: FontWeight.w500, sub: r.def.description)),
              NxColumn(key: 'cat', label: 'Category', hide: NxHide.md, sort: (r) => r.def.category, cell: (r) => Align(alignment: Alignment.centerLeft, child: NxTag(r.def.category, tone: Tone.info))),
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
            onOpen: (r) => _showReportSheet(context, r.def.id, r.data, period),
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

void _showReportSheet(BuildContext context, String id, ReportData rep, ReportPeriod period) => showNxSheet<void>(
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
          style: TextStyle(fontSize: 10.5, color: head ? _headInk : _ink, fontWeight: head || foot ? FontWeight.w600 : FontWeight.w400, fontFeatures: tabular),
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
              NxButton(label: 'Export Excel', icon: PhosphorIconsRegular.microsoftExcelLogo, onPressed: () => _export(ref, rep, id, period, pdf: false)),
              NxButton.primary(label: 'Export PDF', icon: PhosphorIconsRegular.filePdf, onPressed: () => _export(ref, rep, id, period, pdf: true)),
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
                        child: logo != null ? Image.memory(logo, fit: BoxFit.contain, errorBuilder: (_, _, _) => const _DefaultMark()) : const _DefaultMark(),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(branding?.companyName ?? 'Ordering System', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _ink)),
                            Text('${period.label} · Generated ${exportStamp()}', style: const TextStyle(fontSize: 11, color: _muted)),
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
                  const Text('No rows in this period.', style: TextStyle(fontSize: 11, color: _muted))
                else
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Table(
                      defaultColumnWidth: const IntrinsicColumnWidth(),
                      border: const TableBorder(horizontalInside: BorderSide(color: _grid)),
                      children: [
                        TableRow(children: [for (var i = 0; i < rep.columns.length; i++) cell(rep.columns[i].header, i, head: true)]),
                        for (final r in rep.rows.take(shown)) TableRow(children: [for (var i = 0; i < rep.columns.length; i++) cell(formatCell(r[i], rep.columns[i].type), i)]),
                        if (totals != null)
                          TableRow(
                            children: [
                              for (var i = 0; i < rep.columns.length; i++) cell(totals[i] is num ? formatCell(totals[i], rep.columns[i].type) : '${totals[i]}', i, foot: true),
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
          Text('${fmtNum(rep.rows.length)} rows. Change the logo and company name in Settings › Report branding.', style: TextStyle(fontSize: 11, color: n.n500)),
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
    child: const Icon(PhosphorIconsBold.receipt, size: 18, color: Color(0xFFB5ABFC)),
  );
}
