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
import '../domain/sale_campaign_summary.dart';
import 'eligible_consultants_dialog.dart';

/// Read-only relay of the warehouse's SCHEDULED/ACTIVE sale campaigns, plus the one piece this
/// system actually owns for a RESTRICTED campaign: which local customers are eligible. Campaigns
/// themselves are scheduled/approved in the warehouse console, not here.
class SalesScreen extends ConsumerWidget {
  const SalesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = context.nx;
    final user = ref.watch(authProvider).value?.user;
    final canManage = user?.can('sales.eligibility.manage') ?? false;
    final async = ref.watch(saleCampaignsListProvider);

    return NxPageScroll(
      onRefresh: () async => ref.invalidate(saleCampaignsListProvider),
      child: async.when(
        loading: () => const NxLoading(message: 'Loading sale campaigns…'),
        error: (e, _) => NxError(
          message: e is AppError ? e.message : 'Could not load sale campaigns.',
          onRetry: () => ref.invalidate(saleCampaignsListProvider),
        ),
        data: (list) => NxListPage<SaleCampaignSummary>(
          stateKey: 'sale-campaigns',
          title: 'Sale Campaigns',
          sub: 'Scheduled and live sale campaigns from the warehouse. For a restricted one, choose which customers may buy at its price.',
          rows: list,
          search: (c) => '${c.name} ${c.products.map((p) => p.name).join(' ')}',
          searchPlaceholder: 'Campaign or product name',
          stats: (rs) => [
            NxStat('Campaigns', fmtNum(rs.length)),
            NxStat('Active', fmtNum(rs.where((c) => c.status == 'ACTIVE').length), color: n.ok),
            NxStat('Restricted', fmtNum(rs.where((c) => c.isRestricted).length)),
          ],
          filters: [
            NxSelectFilter('status', 'Status', options: const [('SCHEDULED', 'Scheduled'), ('ACTIVE', 'Active')], get: (c) => c.status),
            NxToggleFilter('restricted', 'Eligibility', text: 'Restricted only', get: (c) => c.isRestricted),
          ],
          defaultSort: ('starts', 1),
          columns: [
            NxColumn(key: 'name', label: 'Campaign', sort: (c) => c.name.toLowerCase(), cell: (c) => NxCellText(c.name, weight: FontWeight.w500, sub: c.products.map((p) => p.name).join(', '))),
            NxColumn(key: 'starts', label: 'Window', hide: NxHide.md, sort: (c) => c.startsAt, cell: (c) => NxCellText(fmtDate(c.startsAt.toLocal()), sub: 'to ${fmtDate(c.endsAt.toLocal())}')),
            NxColumn(key: 'status', label: 'Status', cell: (c) => Align(alignment: Alignment.centerLeft, child: NxTag(c.status == 'ACTIVE' ? 'Active' : 'Scheduled', tone: c.status == 'ACTIVE' ? Tone.ok : Tone.info))),
            NxColumn(
              key: 'elig',
              label: 'Eligibility',
              cell: (c) => c.isRestricted
                  ? (canManage
                        ? NxButton(label: 'Eligible consultants', small: true, icon: PhosphorIconsRegular.users, onPressed: () => showEligibleConsultantsDialog(context, c))
                        : NxTag('Restricted', tone: Tone.warn))
                  : NxTag('Every customer', tone: Tone.neutral),
            ),
          ],
          listRow: (c) => NxListRowSpec(
            icon: PhosphorIconsDuotone.tag,
            iconColor: n.a400,
            title: c.name,
            sub: c.products.map((p) => p.name).join(', '),
            right: fmtDate(c.startsAt.toLocal()),
            rightSub: fmtDate(c.endsAt.toLocal()),
            tag: NxTag(c.status == 'ACTIVE' ? 'Active' : 'Scheduled', tone: c.status == 'ACTIVE' ? Tone.ok : Tone.info),
          ),
          card: (c) => NxCardSpec(
            icon: PhosphorIconsDuotone.tag,
            iconColor: n.a400,
            title: c.name,
            sub: c.products.map((p) => p.name).join(', '),
            metrics: [('Window', '${fmtDate(c.startsAt.toLocal())} – ${fmtDate(c.endsAt.toLocal())}', null), ('Eligibility', c.isRestricted ? 'Restricted' : 'Everyone', null)],
            tag: NxTag(c.status == 'ACTIVE' ? 'Active' : 'Scheduled', tone: c.status == 'ACTIVE' ? Tone.ok : Tone.info),
          ),
          onOpen: canManage ? (c) { if (c.isRestricted) showEligibleConsultantsDialog(context, c); } : null,
          emptyTitle: 'No sale campaigns right now',
          emptyMessage: 'Scheduled and live campaigns are managed from the warehouse console.',
        ),
      ),
    );
  }
}
