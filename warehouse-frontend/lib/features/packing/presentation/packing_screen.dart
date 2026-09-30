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
import '../../../shared/scan/scan_code.dart';
import '../../../shared/scan/scan_dialog.dart';
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
              NxColumn(key: 'act', label: '', width: 52, cell: (r) => NxRowActions([print(r)])),
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

void _showPackingSheet(BuildContext context, WidgetRef ref, PackingOrder o) =>
    showNxSheet<void>(context, kicker: 'Packing', builder: (_) => _PackingSheet(order: o, onPrint: () => _printPickList(ref, [o])));

/// One order's lines to pick. "Scan to check" verifies what goes in the box:
/// each product scan ticks one unit off its line (a location scan lists what
/// to take from there). The ticks live only in this sheet.
class _PackingSheet extends StatefulWidget {
  const _PackingSheet({required this.order, required this.onPrint});

  final PackingOrder order;
  final VoidCallback onPrint;

  @override
  State<_PackingSheet> createState() => _PackingSheetState();
}

class _PackingSheetState extends State<_PackingSheet> {
  /// line id → units scanned.
  final Map<String, double> _scanned = {};

  bool _complete(PackingLine l) => (_scanned[l.id] ?? 0) >= l.quantity;

  ScanFeedback _onScan(ScanCode code) {
    final lines = widget.order.lines;
    if (code.kind == ScanKind.location) {
      final here = lines.where((l) => l.location.id == code.value && !_complete(l)).toList();
      return here.isEmpty
          ? const ScanFeedback('Nothing left to pick from this location.', ok: false)
          : ScanFeedback('Pick here: ${here.map((l) => '${fmtNum(l.quantity - (_scanned[l.id] ?? 0))} × ${l.sku}').join(', ')}');
    }
    final v = code.value.toLowerCase();
    final ofProduct = lines.where((l) => l.productId == code.value || (code.kind == ScanKind.unknown && l.sku.toLowerCase() == v)).toList();
    if (ofProduct.isEmpty) return const ScanFeedback('Not in this order — leave it out.', ok: false);
    final line = ofProduct.where((l) => !_complete(l)).firstOrNull;
    if (line == null) return ScanFeedback('Already have all of ${ofProduct.first.sku} — this one is extra.', ok: false);
    setState(() => _scanned[line.id] = (_scanned[line.id] ?? 0) + 1);
    final left = lines.where((l) => !_complete(l)).length;
    final progress = '${line.sku} · ${fmtNum(_scanned[line.id]!)} of ${fmtNum(line.quantity)}';
    return ScanFeedback(left == 0 ? '$progress — every line checked' : '$progress · $left line(s) to go');
  }

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    final o = widget.order;
    final others = o.totalLineCount - o.lines.length;
    final checked = o.lines.where(_complete).length;
    return NxSheetBody(
      children: [
        Text(o.title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500, color: n.text)),
        const SizedBox(height: 2),
        Text('Reserved ${fmtDateTime(o.reservedAt.toLocal())} · ${o.reference}', style: TextStyle(fontSize: 12, color: n.n400)),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: NxBar(fraction: o.lines.isEmpty ? 0 : checked / o.lines.length, height: 6)),
            const SizedBox(width: 8),
            Text('$checked / ${o.lines.length} checked', style: TextStyle(fontSize: 12, color: n.n400)),
          ],
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: NxButton(
            label: 'Scan to check',
            small: true,
            icon: PhosphorIconsRegular.qrCode,
            onPressed: () => showScanDialog(context, title: 'Scan to check', sub: 'Scan each item as it goes in the box.', onScan: _onScan),
          ),
        ),
        const SizedBox(height: 12),
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
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          NxTag(l.workstream.name, small: true),
                          if (_scanned[l.id] != null) ...[
                            const SizedBox(height: 4),
                            NxTag(
                              _complete(l) ? 'Checked' : '${fmtNum(_scanned[l.id]!)} of ${fmtNum(l.quantity)}',
                              small: true,
                              tone: _complete(l) ? Tone.ok : Tone.warn,
                            ),
                          ],
                        ],
                      ),
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
        Text('Checking here does not move stock. Dispatch still happens in the ordering system.', style: TextStyle(fontSize: 11, color: n.n500)),
        const SizedBox(height: 14),
        Align(
          alignment: Alignment.centerLeft,
          child: NxButton.primary(label: 'Print pick list (PDF)', icon: PhosphorIconsRegular.printer, onPressed: widget.onPrint),
        ),
      ],
    );
  }
}
