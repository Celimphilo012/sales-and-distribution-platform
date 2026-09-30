import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../app_shell/responsive_app_shell.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/error/app_error.dart';
import '../../../core/theme/nocturne.dart';
import '../../../shared/nx/nx_format.dart';
import '../../../shared/nx/nx_list_page.dart';
import '../../../shared/nx/nx_primitives.dart';
import '../../inventory/data/inventory_providers.dart';
import '../../inventory/domain/ledger_entry.dart';
import '../../products/presentation/product_sheet.dart';
import 'receive_sheet.dart';

/// Stock Receiving (prototype `receiving`) — the RECEIVE ledger rows, newest
/// first, with the receive sheet one click away.
class ReceivingScreen extends ConsumerWidget {
  const ReceivingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = context.nx;
    final canReceive = ref.watch(authProvider.select((s) => s.value?.user?.can('inventory.receive') ?? false));
    final async = ref.watch(ledgerByTypeProvider('RECEIVE'));

    return NxPageScroll(
      onRefresh: () async => ref.invalidate(ledgerByTypeProvider('RECEIVE')),
      child: async.when(
        loading: () => const NxLoading(message: 'Loading receipts…'),
        error: (e, _) => NxError(
          message: e is AppError ? e.message : 'Could not load receipts.',
          onRetry: () => ref.invalidate(ledgerByTypeProvider('RECEIVE')),
        ),
        data: (rows) {
          List<(String, String)> opts(Iterable<String?> values) {
            final set = {for (final v in values) ?v}.toList()..sort();
            return [for (final v in set) (v, v)];
          }

          final today = DateTime.now();
          bool isToday(DateTime d) => d.year == today.year && d.month == today.month && d.day == today.day;
          final productOpts = {for (final r in rows) r.productId: r.productName}.entries.toList()..sort((a, b) => a.value.compareTo(b.value));

          return NxListPage<LedgerEntry>(
            stateKey: 'receiving',
            title: 'Stock Receiving',
            sub: 'Each receipt is a RECEIVE transaction that increases on-hand at its destination.',
            actions: [
              if (canReceive)
                NxButton.primary(label: 'Receive stock', icon: PhosphorIconsRegular.boxArrowDown, onPressed: () => showReceiveSheet(context)),
            ],
            rows: rows,
            search: (r) => '${r.reference ?? ''} ${r.productName} ${r.productSku} ${r.supplier ?? ''}',
            searchPlaceholder: 'Reference, product or supplier',
            stats: (rs) => [
              NxStat('Receipts', fmtNum(rs.length), sub: '${rs.where((r) => isToday(r.createdAt.toLocal())).length} today'),
              NxStat('Units received', fmtNum(rs.fold<double>(0, (s, r) => s + r.quantity))),
              NxStat('Suppliers', fmtNum({for (final r in rs) ?r.supplier}.length)),
              NxStat('Products', fmtNum({for (final r in rs) r.productId}.length)),
              NxStat('Destinations', fmtNum({for (final r in rs) ?r.toCode}.length), sub: 'slots received into', color: n.a300),
            ],
            filters: [
              NxSelectFilter('sup', 'Supplier', searchable: true, options: opts(rows.map((r) => r.supplier)), get: (r) => r.supplier),
              NxSelectFilter('pid', 'Product', searchable: true, options: [for (final e in productOpts) (e.key, e.value)], get: (r) => r.productId),
              NxSelectFilter('to', 'Destination', searchable: true, options: opts(rows.map((r) => r.toCode)), get: (r) => r.toCode),
              NxSelectFilter('by', 'Received by', options: opts(rows.map((r) => r.performedByName)), get: (r) => r.performedByName),
              NxDateFilter('date', 'Date', get: (r) => r.createdAt.toLocal()),
              NxRangeFilter('qty', 'Quantity', get: (r) => r.quantity),
            ],
            defaultSort: ('when', -1),
            columns: [
              NxColumn(key: 'when', label: 'When', sort: (r) => r.createdAt, cell: (r) => NxCellText(fmtTime(r.createdAt.toLocal()), sub: fmtDate(r.createdAt.toLocal()))),
              NxColumn(key: 'ref', label: 'Reference', hide: NxHide.md, cell: (r) => NxCellText(r.reference ?? '—', mono: true, color: n.n300)),
              NxColumn(key: 'p', label: 'Product', sort: (r) => r.productName.toLowerCase(), cell: (r) => NxCellText(r.productName, weight: FontWeight.w500, sub: r.productSku)),
              NxColumn(
                key: 'qty',
                label: 'Qty',
                align: TextAlign.right,
                sort: (r) => r.quantity,
                cell: (r) => NxCellText('+${fmtNum(r.quantity)}', color: n.ok, align: TextAlign.right),
              ),
              NxColumn(key: 'to', label: 'To', sort: (r) => r.toCode ?? '', cell: (r) => NxCellText(r.toCode ?? '—', mono: true, sub: r.toName)),
              NxColumn(key: 'sup', label: 'Supplier', hide: NxHide.wide, sort: (r) => r.supplier ?? '', cell: (r) => NxCellText(r.supplier ?? '—')),
              NxColumn(key: 'by', label: 'By', hide: NxHide.wide, cell: (r) => NxCellText(r.performedByName ?? '—', color: n.n300)),
            ],
            listRow: (r) => NxListRowSpec(
              icon: PhosphorIconsDuotone.boxArrowDown,
              iconColor: n.ok,
              title: r.productName,
              sub: [r.reference, r.supplier, if (r.toCode != null) 'to ${r.toCode}'].whereType<String>().join(' · '),
              right: '+${fmtNum(r.quantity)}',
              rightSub: fmtDateTime(r.createdAt.toLocal()),
              rightColor: n.ok,
            ),
            card: (r) => NxCardSpec(
              icon: PhosphorIconsDuotone.boxArrowDown,
              iconColor: n.ok,
              title: r.productName,
              sub: r.reference ?? fmtDateTime(r.createdAt.toLocal()),
              metrics: [('Qty', '+${fmtNum(r.quantity)}', n.ok), ('To', r.toCode ?? '—', null), ('Supplier', r.supplier ?? '—', null)],
            ),
            onOpen: (r) => showProductSheet(context, r.productId),
            emptyTitle: 'No receipts match',
            emptyMessage: 'Adjust filters, or receive stock.',
          );
        },
      ),
    );
  }
}
