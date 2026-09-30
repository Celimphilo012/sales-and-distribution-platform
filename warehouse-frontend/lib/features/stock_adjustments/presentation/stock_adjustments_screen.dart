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
import '../data/stock_adjustments_providers.dart';
import '../domain/stock_adjustment.dart';
import 'adjustment_form_dialog.dart';
import 'adjustment_review_dialog.dart';

class _Row {
  _Row(this.a, {required this.own});

  final StockAdjustment a;

  /// Requested by the signed-in user (they can't review it).
  final bool own;

  bool get inc => a.direction == AdjustmentDirection.increase;
  bool get pending => a.status == AdjustmentStatus.pending;
  double get signed => inc ? a.delta : -a.delta;
  int get days => pending ? daysSince(a.requestedAt) : 0;
  String get bucketS => a.bucket.label.toLowerCase();
}

/// Stock Adjustments (prototype `adjustments`) — the approval queue first.
/// Only an approval moves stock; nobody reviews their own request. Requests
/// can carry an evidence photo, shown to the reviewer.
class StockAdjustmentsScreen extends ConsumerWidget {
  const StockAdjustmentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = context.nx;
    final user = ref.watch(authProvider).value?.user;
    final canRequest = user?.can('inventory.adjust.request') ?? false;
    final canApprove = user?.can('inventory.adjust.approve') ?? false;
    final async = ref.watch(stockAdjustmentsListProvider(null));

    return NxPageScroll(
      onRefresh: () async => ref.invalidate(stockAdjustmentsListProvider),
      child: async.when(
        loading: () => const NxLoading(message: 'Loading adjustments…'),
        error: (e, _) => NxError(
          message: e is AppError ? e.message : 'Could not load adjustments.',
          onRetry: () => ref.invalidate(stockAdjustmentsListProvider),
        ),
        data: (list) {
          final rows = [for (final a in list) _Row(a, own: a.requestedBy == user?.id)];
          NxTag status(_Row r) => NxTag(r.a.status.label, tone: switch (r.a.status) {
            AdjustmentStatus.pending => Tone.warn,
            AdjustmentStatus.approved => Tone.ok,
            AdjustmentStatus.rejected => Tone.bad,
          });
          NxTag? wait(_Row r) => r.pending
              ? NxTag(fmtWaiting(r.days), tone: r.days >= 3 ? Tone.bad : r.days >= 1 ? Tone.warn : Tone.neutral)
              : null;
          List<NxRowAction> acts(_Row r) => !r.pending || r.own || !canApprove
              ? const []
              : [
                  NxRowAction(icon: PhosphorIconsRegular.x, label: 'Reject', text: 'Reject', onPressed: () => showAdjustmentReview(context, r.a, approve: false)),
                  NxRowAction(icon: PhosphorIconsRegular.check, label: 'Approve', text: 'Approve', primary: true, onPressed: () => showAdjustmentReview(context, r.a, approve: true)),
                ];
          final requesters = {for (final a in list) a.requestedByUser.fullName}.toList()..sort();
          final locs = {for (final a in list) a.location.code}.toList()..sort();
          String photo(_Row r) => r.a.hasPhoto ? ' · photo attached' : '';

          return NxListPage<_Row>(
            stateKey: 'adjustments',
            title: 'Stock Adjustments',
            sub: 'Only an approval moves stock. You can’t approve your own requests.',
            actions: [
              if (canRequest)
                NxButton.primary(label: 'Request adjustment', icon: PhosphorIconsRegular.plus, onPressed: () => showAdjustmentForm(context)),
            ],
            rows: rows,
            search: (r) => '${r.a.product.name} ${r.a.product.sku} ${r.a.reference ?? ''} ${r.a.reason}',
            searchPlaceholder: 'Product, reference or reason',
            stats: (rs) {
              final pend = rs.where((r) => r.pending).toList();
              final oldest = pend.isEmpty ? null : pend.map((r) => r.days).reduce((a, b) => a > b ? a : b);
              final net = pend.fold<double>(0, (s, r) => s + r.signed);
              return [
                NxStat('Pending', fmtNum(pend.length), sub: '${pend.where((r) => r.own).length} are yours', color: pend.isNotEmpty ? n.warn : null),
                NxStat('Oldest wait', oldest == null ? '—' : '${oldest}d', color: (oldest ?? 0) >= 3 ? n.bad : null),
                NxStat('Approved', fmtNum(rs.where((r) => r.a.status == AdjustmentStatus.approved).length), color: n.ok),
                NxStat('Rejected', fmtNum(rs.where((r) => r.a.status == AdjustmentStatus.rejected).length)),
                NxStat('Net pending', fmtSigned(net), sub: 'units if all approved'),
              ];
            },
            quick: NxQuick(
              defaultValue: 'PENDING',
              get: (r) => r.a.status.apiValue,
              options: const [('PENDING', 'Queue'), ('APPROVED', 'Approved'), ('REJECTED', 'Rejected'), ('', 'All')],
            ),
            filters: [
              NxMultiFilter('bucket', 'Bucket', options: [for (final b in AdjustmentBucket.values) (b.apiValue, b.label)], get: (r) => r.a.bucket.apiValue),
              NxSelectFilter('dir', 'Direction', options: const [('INCREASE', 'Increase'), ('DECREASE', 'Decrease')], get: (r) => r.a.direction.apiValue),
              NxSelectFilter('by', 'Requested by', options: [for (final x in requesters) (x, x)], get: (r) => r.a.requestedByUser.fullName),
              NxSelectFilter('loc', 'Location', searchable: true, options: [for (final x in locs) (x, x)], get: (r) => r.a.location.code),
              NxRangeFilter('days', 'Waiting (days)', get: (r) => r.days),
              NxToggleFilter('photo', 'Evidence', text: 'With a photo', get: (r) => r.a.hasPhoto),
              NxToggleFilter('mine', 'Ownership', text: 'Hide my own requests', get: (r) => !r.own),
            ],
            defaultView: NxView.list,
            defaultSort: ('when', -1),
            columns: [
              NxColumn(
                key: 'chg',
                label: 'Change',
                sort: (r) => r.signed,
                cell: (r) => NxCellText(adjustmentDelta(r.a), color: r.inc ? n.ok : n.bad, weight: FontWeight.w500, sub: r.bucketS),
              ),
              NxColumn(
                key: 'p',
                label: 'Product',
                sort: (r) => r.a.product.name.toLowerCase(),
                cell: (r) => NxCellText(r.a.product.name, weight: FontWeight.w500, sub: '${r.a.location.code}${photo(r)}'),
              ),
              NxColumn(key: 'reason', label: 'Reason', hide: NxHide.wide, cell: (r) => NxCellText('“${r.a.reason}”', color: n.n300)),
              NxColumn(
                key: 'when',
                label: 'Requested',
                hide: NxHide.md,
                sort: (r) => r.a.requestedAt,
                cell: (r) => NxCellText(r.a.requestedByUser.fullName, sub: fmtWhen(r.a.requestedAt)),
              ),
              NxColumn(
                key: 'wait',
                label: 'Waiting',
                sort: (r) => r.days,
                cell: (r) => wait(r) != null
                    ? Align(alignment: Alignment.centerLeft, child: wait(r))
                    : NxCellText(r.a.reviewedByUser == null ? '—' : 'by ${r.a.reviewedByUser!.fullName}', color: n.n400),
              ),
              NxColumn(key: 'status', label: 'Status', cell: (r) => Align(alignment: Alignment.centerLeft, child: status(r))),
              NxColumn(
                key: 'act',
                label: '',
                width: 170,
                cell: (r) => r.pending && r.own
                    ? NxCellText('Needs another reviewer', color: n.n500)
                    : NxRowActions(acts(r), withText: true),
              ),
            ],
            listRow: (r) => NxListRowSpec(
              icon: r.inc ? PhosphorIconsDuotone.plusCircle : PhosphorIconsDuotone.minusCircle,
              iconColor: r.inc ? n.ok : n.bad,
              title: '${adjustmentDelta(r.a)} ${r.bucketS} · ${r.a.product.name}',
              sub:
                  '${r.a.location.code} · “${r.a.reason}” · ${r.a.requestedByUser.fullName}${r.own && r.pending ? ' (you — another reviewer must approve)' : ''}${photo(r)}',
              tag: wait(r) ?? status(r),
              actions: acts(r),
            ),
            card: (r) => NxCardSpec(
              icon: r.inc ? PhosphorIconsDuotone.plusCircle : PhosphorIconsDuotone.minusCircle,
              iconColor: r.inc ? n.ok : n.bad,
              title: r.a.product.name,
              sub: '${r.a.location.code} · ${r.a.requestedByUser.fullName}${photo(r)}',
              metrics: [('Change', adjustmentDelta(r.a), r.inc ? n.ok : n.bad), ('Bucket', r.bucketS, null)],
              tag: wait(r) ?? status(r),
              actions: acts(r),
            ),
            onOpen: (r) => showAdjustmentDetail(context, r.a),
            emptyTitle: 'Nothing here',
            emptyMessage: 'No adjustments match — the queue may be clear.',
          );
        },
      ),
    );
  }
}
