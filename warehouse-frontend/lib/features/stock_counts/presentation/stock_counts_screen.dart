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
import '../../locations/data/leaf_locations_provider.dart';
import '../data/stock_counts_providers.dart';
import '../domain/stock_count.dart';
import 'count_sheet.dart';

class _Row {
  _Row(this.c, {required this.locName, required this.counted, required this.variance});

  final StockCount c;
  final String locName;
  final int counted;
  final double variance;

  bool get done => c.status == StockCountStatus.submitted;
  int get items => c.items.length;
  double get progress => items == 0 ? (done ? 1 : 0) : counted / items;
}

/// Stock Counts (prototype `counts`) — a count snapshots expected quantities
/// at a slot; variances go to adjustment review. `/stock-counts?open=<id>`
/// opens that count's sheet.
class StockCountsScreen extends ConsumerStatefulWidget {
  const StockCountsScreen({super.key, this.openCountId});

  final String? openCountId;

  @override
  ConsumerState<StockCountsScreen> createState() => _StockCountsScreenState();
}

class _StockCountsScreenState extends ConsumerState<StockCountsScreen> {
  @override
  void initState() {
    super.initState();
    final id = widget.openCountId;
    if (id != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        GoRouter.of(context).go(RoutePaths.stockCounts);
        showCountSheet(context, id);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    final canCount = ref.watch(authProvider.select((s) => s.value?.user?.can('inventory.count') ?? false));
    final async = ref.watch(stockCountsListProvider(null));
    final leaves = {for (final l in ref.watch(leafLocationsProvider).value ?? const <LeafLocation>[]) l.id: l};
    final drafts = ref.watch(countDraftsProvider);

    return NxPageScroll(
      onRefresh: () async => ref.invalidate(stockCountsListProvider),
      child: async.when(
        loading: () => const NxLoading(message: 'Loading stock counts…'),
        error: (e, _) => NxError(
          message: e is AppError ? e.message : 'Could not load stock counts.',
          onRetry: () => ref.invalidate(stockCountsListProvider),
        ),
        data: (counts) {
          final rows = [
            for (final c in counts)
              () {
                if (c.status == StockCountStatus.submitted) {
                  return _Row(
                    c,
                    locName: countLocationName(c, leaves),
                    counted: c.items.length,
                    variance: c.items.fold<double>(0, (s, i) => s + (i.difference ?? 0)),
                  );
                }
                final draft = drafts[c.id] ?? const {};
                var counted = 0;
                var variance = 0.0;
                for (final i in c.items) {
                  final v = double.tryParse(draft[i.productId]?.trim() ?? '');
                  if (v == null) continue;
                  counted++;
                  variance += v - i.expectedQty;
                }
                return _Row(c, locName: countLocationName(c, leaves), counted: counted, variance: variance);
              }(),
          ];
          NxTag status(_Row r) => NxTag(r.done ? 'Submitted' : 'In progress', tone: r.done ? Tone.ok : Tone.info);
          Color? varColor(double v) => v == 0 ? n.n400 : (v > 0 ? n.ok : n.bad);
          final locCodes = {for (final c in counts) c.location.code}.toList()..sort();
          final starters = {for (final c in counts) c.startedByUser.fullName}.toList()..sort();

          return NxListPage<_Row>(
            stateKey: 'counts',
            title: 'Stock Counts',
            sub: 'A count snapshots expected quantities at a storage slot; variances go to adjustment review.',
            actions: [
              if (canCount)
                NxButton.primary(label: 'Start count', icon: PhosphorIconsRegular.listChecks, onPressed: () => showStartCountDialog(context)),
            ],
            rows: rows,
            search: (r) => '${r.c.location.code} ${r.locName} ${r.c.startedByUser.fullName}',
            searchPlaceholder: 'Count or location',
            stats: (rs) {
              final net = rs.fold<double>(0, (s, r) => s + r.variance);
              return [
                NxStat('Counts', fmtNum(rs.length)),
                NxStat('In progress', fmtNum(rs.where((r) => !r.done).length), color: n.a300),
                NxStat('Submitted', fmtNum(rs.where((r) => r.done).length), color: n.ok),
                NxStat('Items counted', '${fmtNum(rs.fold<int>(0, (s, r) => s + r.counted))} / ${fmtNum(rs.fold<int>(0, (s, r) => s + r.items))}'),
                NxStat('Net variance', fmtSigned(net), sub: 'units', color: net < 0 ? n.bad : null),
              ];
            },
            quick: NxQuick(
              get: (r) => r.done ? 'done' : 'open',
              options: const [('', 'All'), ('open', 'In progress'), ('done', 'Submitted')],
            ),
            filters: [
              NxSelectFilter('loc', 'Location', searchable: true, options: [for (final c in locCodes) (c, c)], get: (r) => r.c.location.code),
              NxSelectFilter('by', 'Started by', options: [for (final s in starters) (s, s)], get: (r) => r.c.startedByUser.fullName),
              NxRangeFilter('var', 'Variance', get: (r) => r.variance),
              NxDateFilter('date', 'Started', get: (r) => r.c.startedAt),
            ],
            defaultSort: ('started', -1),
            columns: [
              NxColumn(
                key: 'loc',
                label: 'Location',
                sort: (r) => r.c.location.code,
                cell: (r) => NxCellText(r.locName, weight: FontWeight.w500, sub: r.c.location.code),
              ),
              NxColumn(
                key: 'prog',
                label: 'Progress',
                width: 160,
                sort: (r) => r.progress,
                cell: (r) => NxLabeledBar(label: '${r.counted}/${r.items}', fraction: r.progress),
              ),
              NxColumn(
                key: 'var',
                label: 'Variance',
                align: TextAlign.right,
                sort: (r) => r.variance,
                cell: (r) => NxCellText(fmtSigned(r.variance), color: varColor(r.variance), align: TextAlign.right),
              ),
              NxColumn(key: 'by', label: 'Started by', hide: NxHide.wide, cell: (r) => NxCellText(r.c.startedByUser.fullName)),
              NxColumn(
                key: 'started',
                label: 'Started',
                hide: NxHide.md,
                sort: (r) => r.c.startedAt,
                cell: (r) => NxCellText(fmtDateTime(r.c.startedAt), color: n.n400),
              ),
              NxColumn(key: 'status', label: 'Status', sort: (r) => r.done ? 1 : 0, cell: (r) => Align(alignment: Alignment.centerLeft, child: status(r))),
            ],
            listRow: (r) => NxListRowSpec(
              icon: PhosphorIconsDuotone.listChecks,
              iconColor: n.a400,
              title: r.locName,
              sub: '${r.c.location.code} · ${r.c.startedByUser.fullName} · ${fmtDateTime(r.c.startedAt)}',
              right: '${r.counted}/${r.items}',
              rightSub: 'variance ${fmtSigned(r.variance)}',
              tag: status(r),
            ),
            card: (r) => NxCardSpec(
              icon: PhosphorIconsDuotone.listChecks,
              title: r.locName,
              sub: r.c.location.code,
              metrics: [('Counted', '${r.counted}/${r.items}', null), ('Variance', fmtSigned(r.variance), r.variance == 0 ? null : varColor(r.variance))],
              tag: status(r),
              bar: r.progress,
              barColor: n.a500,
            ),
            onOpen: (r) => showCountSheet(context, r.c.id),
            emptyTitle: 'No counts match',
            emptyMessage: 'Start a count to snapshot a location.',
          );
        },
      ),
    );
  }
}
