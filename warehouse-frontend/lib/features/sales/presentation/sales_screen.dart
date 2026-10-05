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
import '../data/sales_providers.dart';
import '../domain/sale_campaign.dart';
import 'sale_campaign_form_dialog.dart';
import 'sale_campaign_review_dialog.dart';

class _Row {
  _Row(this.c, {required this.own});

  final SaleCampaign c;

  /// Requested by the signed-in user (they can't review it).
  final bool own;

  int get days => c.status.isPending ? daysSince(c.requestedAt) : 0;
  String get products => c.products.map((p) => p.product.name).join(', ');
}

/// Sale Campaigns — the approval queue first, same shape as Stock Adjustments. Only an approval
/// makes a campaign live; nobody reviews their own request. SCHEDULED -> ACTIVE -> ENDED happen on
/// the server's own schedule, never from a button here.
class SalesScreen extends ConsumerWidget {
  const SalesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = context.nx;
    final user = ref.watch(authProvider).value?.user;
    final canSchedule = user?.can('sales.schedule') ?? false;
    final canApprove = user?.can('sales.approve') ?? false;
    final async = ref.watch(salesListProvider);

    return NxPageScroll(
      onRefresh: () async => ref.invalidate(salesListProvider),
      child: async.when(
        loading: () => const NxLoading(message: 'Loading sale campaigns…'),
        error: (e, _) => NxError(
          message: e is AppError ? e.message : 'Could not load sale campaigns.',
          onRetry: () => ref.invalidate(salesListProvider),
        ),
        data: (list) {
          final rows = [for (final c in list) _Row(c, own: c.requestedBy == user?.id)];
          NxTag status(_Row r) => NxTag(r.c.status.label, tone: campaignStatusTone(r.c.status));
          NxTag? wait(_Row r) => r.c.status.isPending
              ? NxTag(fmtWaiting(r.days), tone: r.days >= 3 ? Tone.bad : r.days >= 1 ? Tone.warn : Tone.neutral)
              : null;
          List<NxRowAction> acts(_Row r) {
            if (r.c.status.isPending && canApprove && !r.own) {
              return [
                NxRowAction(icon: PhosphorIconsRegular.x, label: 'Reject', text: 'Reject', onPressed: () => showSaleCampaignReview(context, r.c, action: 'reject')),
                NxRowAction(icon: PhosphorIconsRegular.check, label: 'Approve', text: 'Approve', primary: true, onPressed: () => showSaleCampaignReview(context, r.c, action: 'approve')),
              ];
            }
            if (r.c.status.canCancel && canApprove) {
              return [NxRowAction(icon: PhosphorIconsRegular.prohibit, label: 'Cancel', text: 'Cancel', onPressed: () => showSaleCampaignReview(context, r.c, action: 'cancel'))];
            }
            return const [];
          }

          final requesters = {for (final c in list) c.requestedByUser.fullName}.toList()..sort();

          return NxListPage<_Row>(
            stateKey: 'sales',
            title: 'Sale Campaigns',
            sub: 'Only an approval makes a campaign live. You can’t approve your own requests.',
            actions: [
              if (canSchedule)
                NxButton.primary(label: 'Schedule campaign', icon: PhosphorIconsRegular.plus, onPressed: () => showSaleCampaignForm(context)),
            ],
            rows: rows,
            search: (r) => '${r.c.name} ${r.products}',
            searchPlaceholder: 'Campaign or product name',
            stats: (rs) {
              final pend = rs.where((r) => r.c.status.isPending).toList();
              final oldest = pend.isEmpty ? null : pend.map((r) => r.days).reduce((a, b) => a > b ? a : b);
              return [
                NxStat('Pending', fmtNum(pend.length), sub: '${pend.where((r) => r.own).length} are yours', color: pend.isNotEmpty ? n.warn : null),
                NxStat('Oldest wait', oldest == null ? '—' : '${oldest}d', color: (oldest ?? 0) >= 3 ? n.bad : null),
                NxStat('Active', fmtNum(rs.where((r) => r.c.status == SaleCampaignStatus.active).length), color: n.ok),
                NxStat('Scheduled', fmtNum(rs.where((r) => r.c.status == SaleCampaignStatus.scheduled).length)),
                NxStat('Ended / cancelled', fmtNum(rs.where((r) => r.c.status == SaleCampaignStatus.ended || r.c.status == SaleCampaignStatus.cancelled).length)),
              ];
            },
            quick: NxQuick(
              defaultValue: '',
              get: (r) => r.c.status.apiValue,
              options: const [
                ('', 'All'),
                ('PENDING_APPROVAL', 'Pending'),
                ('SCHEDULED', 'Scheduled'),
                ('ACTIVE', 'Active'),
                ('ENDED', 'Ended'),
                ('REJECTED', 'Rejected'),
                ('CANCELLED', 'Cancelled'),
              ],
            ),
            filters: [
              NxSelectFilter('by', 'Requested by', options: [for (final x in requesters) (x, x)], get: (r) => r.c.requestedByUser.fullName),
              NxSelectFilter('elig', 'Eligibility', options: [for (final e in SaleEligibility.values) (e.apiValue, e.label)], get: (r) => r.c.eligibility.apiValue),
              NxToggleFilter('mine', 'Ownership', text: 'Hide my own requests', get: (r) => !r.own),
            ],
            defaultView: NxView.list,
            defaultSort: ('when', -1),
            columns: [
              NxColumn(key: 'name', label: 'Campaign', sort: (r) => r.c.name.toLowerCase(), cell: (r) => NxCellText(r.c.name, weight: FontWeight.w500, sub: r.products)),
              NxColumn(
                key: 'window',
                label: 'Window',
                hide: NxHide.md,
                cell: (r) => NxCellText(
                  fmtDate(r.c.startsAt.toLocal()),
                  sub: r.c.isDailyWindow
                      ? '${fmtTime(r.c.dailyWindowStartLocal)}–${fmtTime(r.c.dailyWindowEndLocal)} daily · to ${fmtDate(r.c.endsAt.toLocal())}'
                      : 'to ${fmtDate(r.c.endsAt.toLocal())}',
                ),
              ),
              NxColumn(key: 'elig', label: 'Eligibility', hide: NxHide.wide, cell: (r) => NxCellText(r.c.eligibility.label, color: n.n300)),
              NxColumn(key: 'when', label: 'Requested', hide: NxHide.md, sort: (r) => r.c.requestedAt, cell: (r) => NxCellText(r.c.requestedByUser.fullName, sub: fmtWhen(r.c.requestedAt))),
              NxColumn(key: 'status', label: 'Status', cell: (r) => Align(alignment: Alignment.centerLeft, child: wait(r) ?? status(r))),
              NxColumn(key: 'act', label: '', width: 170, cell: (r) => r.c.status.isPending && r.own ? NxCellText('Needs another reviewer', color: n.n500) : NxRowActions(acts(r), withText: true)),
            ],
            listRow: (r) => NxListRowSpec(
              icon: PhosphorIconsDuotone.tag,
              iconColor: n.a400,
              title: r.c.name,
              sub: '${r.products} · ${r.c.requestedByUser.fullName}${r.own && r.c.status.isPending ? ' (you — another reviewer must approve)' : ''}',
              right: fmtDate(r.c.startsAt.toLocal()),
              rightSub: fmtDate(r.c.endsAt.toLocal()),
              tag: wait(r) ?? status(r),
              actions: acts(r),
            ),
            card: (r) => NxCardSpec(
              icon: PhosphorIconsDuotone.tag,
              iconColor: n.a400,
              title: r.c.name,
              sub: r.products,
              metrics: [
                (
                  'Window',
                  r.c.isDailyWindow
                      ? '${fmtTime(r.c.dailyWindowStartLocal)}–${fmtTime(r.c.dailyWindowEndLocal)} daily, ${fmtDate(r.c.startsAt.toLocal())}–${fmtDate(r.c.endsAt.toLocal())}'
                      : '${fmtDate(r.c.startsAt.toLocal())} – ${fmtDate(r.c.endsAt.toLocal())}',
                  null,
                ),
                ('Eligibility', r.c.eligibility.label, null),
                if (r.c.maxUsesPerCustomer != null) ('Usage cap', '${r.c.maxUsesPerCustomer} per customer', null),
              ],
              tag: wait(r) ?? status(r),
              actions: acts(r),
            ),
            onOpen: (r) => showSaleCampaignDetail(context, r.c),
            emptyTitle: 'No sale campaigns yet',
            emptyMessage: canSchedule ? 'Schedule one to put a product on sale.' : 'Nothing has been scheduled.',
          );
        },
      ),
    );
  }
}
