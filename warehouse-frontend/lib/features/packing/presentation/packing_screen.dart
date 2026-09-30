import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../app_shell/responsive_app_shell.dart';
import '../../../core/theme/nocturne.dart';
import '../../../core/error/app_error.dart';
import '../../../shared/export/report_export.dart';
import '../../../shared/nx/nx_format.dart';
import '../../../shared/nx/nx_list_page.dart';
import '../../../shared/nx/nx_overlays.dart';
import '../../../shared/nx/nx_primitives.dart';
import '../../reports/data/export_branding.dart';
import '../data/packing_api.dart';
import '../domain/packing_order.dart';

class _Row {
  _Row(this.o);

  final PackingOrder o;

  int get mine => o.lines.length;
  int get others => o.totalLineCount - o.lines.length;
  double get units => o.lines.fold<double>(0, (s, l) => s + l.quantity);
  List<String> get locs => {for (final l in o.lines) l.location.code}.toList()..sort();
  List<String> get workstreams => {for (final l in o.lines) l.workstream.name}.toList()..sort();
  List<String> get workstreamIds => {for (final l in o.lines) l.workstream.id}.toList();
}

PickOrder _pickOrder(PackingOrder o) => PickOrder(
  title: o.title,
  subtitle: 'reserved ${fmtDateTime(o.reservedAt)} · ${o.lines.length} of ${o.totalLineCount} items',
  lines: [
    for (final l in o.lines) ('${fmtNum(l.quantity)} ${l.uom}', l.productName, l.sku, '${l.location.code} — ${l.location.name}, ${l.warehouse.name}'),
  ],
);

Future<void> _printPickList(WidgetRef ref, List<PackingOrder> orders) async {
  if (orders.isEmpty) return;
  NxToast.info('Preparing pick list…', '${orders.length} order${orders.length == 1 ? '' : 's'}');
  try {
    final branding = await loadExportBranding(ref);
    final name = await downloadPickList([for (final o in orders) _pickOrder(o)], branding);
    NxToast.ok('Pick list downloaded', name);
  } on AppError catch (e) {
    NxToast.error('Export failed', e.message);
  } catch (e) {
    NxToast.error('Export failed', '$e');
  }
}

/// Packing (prototype `packing`) — open orders (reserved, not dispatched)
/// with the lines this person handles, oldest first; each prints as a pick
/// list PDF. Read-only: dispatch happens in the ordering system.
class PackingScreen extends ConsumerWidget {
  const PackingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = context.nx;
    final async = ref.watch(packingOrdersProvider);

    return NxPageScroll(
      onRefresh: () async => ref.invalidate(packingOrdersProvider),
      child: async.when(
        loading: () => const NxLoading(message: 'Loading open orders…'),
        error: (e, _) => NxError(
          message: e is AppError ? e.message : 'Could not load the packing list.',
          onRetry: () => ref.invalidate(packingOrdersProvider),
        ),
        data: (orders) {
          final rows = [for (final o in orders) _Row(o)];
          NxTag items(_Row r) => NxTag('${r.mine} of ${r.o.totalLineCount} items', tone: r.others > 0 ? Tone.info : Tone.ok);
          final wsOpts = {for (final o in orders) for (final l in o.lines) l.workstream.id: l.workstream.name}.entries.toList()
            ..sort((a, b) => a.value.compareTo(b.value));
          final locOpts = {for (final o in orders) for (final l in o.lines) l.location.code}.toList()..sort();
          NxRowAction print(_Row r, {bool text = false}) => NxRowAction(
            icon: PhosphorIconsRegular.printer,
            label: 'Print pick list',
            text: text ? 'Pick list' : null,
            onPressed: () => _printPickList(ref, [r.o]),
          );

          return NxListPage<_Row>(
            stateKey: 'packing',
            title: 'Packing',
            sub: 'Open orders with the items you handle, oldest first. An order leaves this list once dispatched.',
            actions: [
              NxButton(
                label: 'Print all pick lists',
                icon: PhosphorIconsRegular.printer,
                onPressed: orders.isEmpty ? null : () => _printPickList(ref, orders),
              ),
            ],
            rows: rows,
            search: (r) => '${r.o.title} ${r.o.reference}',
            searchPlaceholder: 'Order or customer',
            stats: (rs) => [
              NxStat('Open orders', fmtNum(rs.length)),
              NxStat('Lines to pick', fmtNum(rs.fold<int>(0, (s, r) => s + r.mine))),
              NxStat('Units', fmtNum(rs.fold<double>(0, (s, r) => s + r.units))),
              NxStat('Shared orders', fmtNum(rs.where((r) => r.others > 0).length), sub: 'other workstreams pack the rest', color: n.a300),
              NxStat('Pick locations', fmtNum({for (final r in rs) ...r.locs}.length)),
            ],
            quick: NxQuick(
              get: (r) => r.others > 0 ? 'shared' : 'mine',
              options: const [('', 'All'), ('mine', 'Only my items'), ('shared', 'Shared')],
            ),
            filters: [
              NxSelectFilter('ws', 'Workstream', options: [for (final e in wsOpts) (e.key, e.value)], get: (r) => r.workstreamIds),
              NxSelectFilter('loc', 'Pick location', searchable: true, options: [for (final l in locOpts) (l, l)], get: (r) => r.locs),
              NxDateFilter('date', 'Reserved', get: (r) => r.o.reservedAt.toLocal()),
              NxRangeFilter('units', 'Units', get: (r) => r.units),
            ],
            defaultSort: ('res', 1),
            columns: [
              NxColumn(key: 'order', label: 'Order', sort: (r) => r.o.title, cell: (r) => NxCellText(r.o.title, weight: FontWeight.w500, sub: r.o.reference)),
              NxColumn(
                key: 'res',
                label: 'Reserved',
                hide: NxHide.md,
                sort: (r) => r.o.reservedAt,
                cell: (r) => NxCellText(fmtDateTime(r.o.reservedAt.toLocal()), color: n.n300),
              ),
              NxColumn(key: 'items', label: 'Items', cell: (r) => Align(alignment: Alignment.centerLeft, child: items(r))),
              NxColumn(key: 'units', label: 'Units', align: TextAlign.right, sort: (r) => r.units, cell: (r) => NxCellText(fmtNum(r.units), align: TextAlign.right)),
              NxColumn(
                key: 'locs',
                label: 'Pick from',
                hide: NxHide.wide,
                cell: (r) => Wrap(spacing: 4, runSpacing: 4, children: [for (final l in r.locs) NxTag(l, small: true, mono: true)]),
              ),
              NxColumn(
                key: 'ws',
                label: 'Workstreams',
                hide: NxHide.wide,
                cell: (r) => Wrap(spacing: 4, runSpacing: 4, children: [for (final w in r.workstreams) NxTag(w, small: true, tone: Tone.accent)]),
              ),
              NxColumn(key: 'act', label: '', width: 44, cell: (r) => NxRowActions([print(r)])),
            ],
            listRow: (r) => NxListRowSpec(
              icon: PhosphorIconsDuotone.package,
              iconColor: n.a400,
              title: r.o.title,
              sub: 'Reserved ${fmtDateTime(r.o.reservedAt.toLocal())} · pick from ${r.locs.join(', ')}',
              right: '${fmtNum(r.units)} units',
              tag: items(r),
            ),
            card: (r) => NxCardSpec(
              icon: PhosphorIconsDuotone.package,
              title: r.o.title,
              sub: 'Reserved ${fmtDateTime(r.o.reservedAt.toLocal())}',
              metrics: [('Lines', fmtNum(r.mine), null), ('Units', fmtNum(r.units), null), ('Locations', fmtNum(r.locs.length), null)],
              tag: items(r),
              actions: [print(r, text: true)],
            ),
            onOpen: (r) => _showPackingSheet(context, ref, r.o),
            emptyTitle: 'Nothing to pack',
            emptyMessage: 'No open orders include items from your warehouses or workstreams.',
          );
        },
      ),
    );
  }
}

void _showPackingSheet(BuildContext context, WidgetRef ref, PackingOrder o) => showNxSheet<void>(
  context,
  kicker: 'Packing',
  builder: (ctx) {
    final n = ctx.nx;
    final others = o.totalLineCount - o.lines.length;
    return NxSheetBody(
      children: [
        Text(o.title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500, color: n.text)),
        const SizedBox(height: 2),
        Text('Reserved ${fmtDateTime(o.reservedAt.toLocal())} · ${o.reference}', style: TextStyle(fontSize: 12, color: n.n400)),
        const SizedBox(height: 14),
        NxSection(
          child: Column(
            children: [
              for (final l in o.lines)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(border: Border(bottom: BorderSide(color: n.n900))),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 76,
                        child: Text('${fmtNum(l.quantity)} ${l.uom}', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: n.text, fontFeatures: tabular)),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(l.productName, style: TextStyle(fontSize: 13, color: n.text)),
                            Text(
                              '${l.sku} · pick from ${l.location.code} · ${l.location.name}, ${l.warehouse.name}',
                              style: TextStyle(fontSize: 11, color: n.n500),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      NxTag(l.workstream.name, small: true),
                    ],
                  ),
                ),
            ],
          ),
        ),
        if (others > 0) ...[
          const SizedBox(height: 10),
          Text(
            '$others more item${others == 1 ? '' : 's'} in this order ${others == 1 ? 'is' : 'are'} packed by other workstreams.',
            style: TextStyle(fontSize: 12, color: n.n400),
          ),
        ],
        const SizedBox(height: 10),
        Text('Read-only. Dispatch still happens in the ordering system.', style: TextStyle(fontSize: 11, color: n.n500)),
        const SizedBox(height: 14),
        Align(
          alignment: Alignment.centerLeft,
          child: NxButton.primary(label: 'Print pick list (PDF)', icon: PhosphorIconsRegular.printer, onPressed: () => _printPickList(ref, [o])),
        ),
      ],
    );
  },
);
