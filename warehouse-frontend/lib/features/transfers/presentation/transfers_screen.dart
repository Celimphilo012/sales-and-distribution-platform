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
import 'transfer_sheet.dart';

/// Stock Transfers (prototype `transfers`) — the TRANSFER ledger rows,
/// newest first, with the transfer sheet one click away.
class TransfersScreen extends ConsumerWidget {
  const TransfersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = context.nx;
    final canTransfer = ref.watch(authProvider.select((s) => s.value?.user?.can('inventory.transfer') ?? false));
    final async = ref.watch(ledgerByTypeProvider('TRANSFER'));

    return NxPageScroll(
      onRefresh: () async => ref.invalidate(ledgerByTypeProvider('TRANSFER')),
      child: async.when(
        loading: () => const NxLoading(message: 'Loading transfers…'),
        error: (e, _) => NxError(
          message: e is AppError ? e.message : 'Could not load transfers.',
          onRetry: () => ref.invalidate(ledgerByTypeProvider('TRANSFER')),
        ),
        data: (rows) {
          List<(String, String)> opts(Iterable<String?> values) {
            final set = {for (final v in values) ?v}.toList()..sort();
            return [for (final v in set) (v, v)];
          }

          String route(LedgerEntry r) => '${r.fromCode ?? '—'} → ${r.toCode ?? '—'}';
          final today = DateTime.now();
          bool isToday(DateTime d) => d.year == today.year && d.month == today.month && d.day == today.day;
          final productOpts = {for (final r in rows) r.productId: r.productName}.entries.toList()..sort((a, b) => a.value.compareTo(b.value));

          return NxListPage<LedgerEntry>(
            stateKey: 'transfers',
            title: 'Stock Transfers',
            sub: 'Moves available stock between two locations as one TRANSFER transaction.',
            actions: [
              if (canTransfer)
                NxButton.primary(label: 'Transfer stock', icon: PhosphorIconsRegular.arrowsLeftRight, onPressed: () => showTransferSheet(context)),
            ],
            rows: rows,
            search: (r) => '${r.reference ?? ''} ${r.productName} ${r.productSku} ${route(r)}',
            searchPlaceholder: 'Reference, product or location',
            stats: (rs) => [
              NxStat('Transfers', fmtNum(rs.length), sub: '${rs.where((r) => isToday(r.createdAt.toLocal())).length} today'),
              NxStat('Units moved', fmtNum(rs.fold<double>(0, (s, r) => s + r.quantity))),
              NxStat('Products', fmtNum({for (final r in rs) r.productId}.length)),
              NxStat('Movers', fmtNum({for (final r in rs) ?r.performedByName}.length), color: n.a300),
              NxStat('Routes', fmtNum({for (final r in rs) route(r)}.length)),
            ],
            filters: [
              NxSelectFilter('from', 'From', searchable: true, options: opts(rows.map((r) => r.fromCode)), get: (r) => r.fromCode),
              NxSelectFilter('to', 'To', searchable: true, options: opts(rows.map((r) => r.toCode)), get: (r) => r.toCode),
              NxSelectFilter('pid', 'Product', searchable: true, options: [for (final e in productOpts) (e.key, e.value)], get: (r) => r.productId),
              NxSelectFilter('by', 'Moved by', options: opts(rows.map((r) => r.performedByName)), get: (r) => r.performedByName),
              NxDateFilter('date', 'Date', get: (r) => r.createdAt.toLocal()),
              NxRangeFilter('qty', 'Quantity', get: (r) => r.quantity),
            ],
            defaultSort: ('when', -1),
            columns: [
              NxColumn(key: 'when', label: 'When', sort: (r) => r.createdAt, cell: (r) => NxCellText(fmtTime(r.createdAt.toLocal()), sub: fmtDate(r.createdAt.toLocal()))),
              NxColumn(key: 'ref', label: 'Reference', hide: NxHide.wide, cell: (r) => NxCellText(r.reference ?? '—', mono: true, color: n.n300)),
              NxColumn(key: 'p', label: 'Product', sort: (r) => r.productName.toLowerCase(), cell: (r) => NxCellText(r.productName, weight: FontWeight.w500, sub: r.productSku)),
              NxColumn(key: 'qty', label: 'Qty', align: TextAlign.right, sort: (r) => r.quantity, cell: (r) => NxCellText(fmtNum(r.quantity), align: TextAlign.right)),
              NxColumn(key: 'route', label: 'Route', cell: (r) => NxCellText(route(r), mono: true, sub: r.reason)),
              NxColumn(key: 'by', label: 'By', hide: NxHide.md, cell: (r) => NxCellText(r.performedByName ?? '—', color: n.n300)),
            ],
            listRow: (r) => NxListRowSpec(
              icon: PhosphorIconsDuotone.arrowsLeftRight,
              iconColor: n.a400,
              title: r.productName,
              sub: '${route(r)} · ${r.performedByName ?? '—'}',
              right: fmtNum(r.quantity),
              rightSub: fmtDateTime(r.createdAt.toLocal()),
            ),
            card: (r) => NxCardSpec(
              icon: PhosphorIconsDuotone.arrowsLeftRight,
              title: r.productName,
              sub: r.reference ?? fmtDateTime(r.createdAt.toLocal()),
              metrics: [('Qty', fmtNum(r.quantity), null), ('Route', route(r), null)],
            ),
            onOpen: (r) => showProductSheet(context, r.productId),
            emptyTitle: 'No transfers match',
            emptyMessage: 'Adjust filters, or transfer stock.',
          );
        },
      ),
    );
  }
}
