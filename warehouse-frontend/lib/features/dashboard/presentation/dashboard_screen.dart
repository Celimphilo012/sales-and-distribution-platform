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
import '../../settings/data/account_api.dart';
import '../data/dashboard_providers.dart';
import '../domain/dashboard_summary.dart';

/// The Warehouse Console dashboard: a KPI strip (each tile opens the list it
/// counts), then Low stock, Pending adjustments and Stock movement side by
/// side, and Recent activity underneath — three columns on desktop, two on a
/// tablet, one on a phone (the prototype's layout "a"). Every figure is a
/// server-side aggregate from `GET /dashboard`.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(dashboardSummaryProvider);
    return NxPageScroll(
      onRefresh: () async => ref.invalidate(dashboardSummaryProvider),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1400),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(loadedAt: async.value == null ? null : DateTime.now()),
            const SizedBox(height: 14),
            async.when(
              loading: () => const NxLoading(message: 'Loading dashboard…'),
              error: (e, _) => NxError(
                message: e is AppError ? e.message : 'Could not load the dashboard.',
                onRetry: () => ref.invalidate(dashboardSummaryProvider),
              ),
              data: (d) => _Body(d: d),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.loadedAt});

  final DateTime? loadedAt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).value?.user;
    final all = user?.can('warehouse.access.all') ?? false;
    final whs = all ? null : ref.watch(myWarehousesProvider).value;
    final scope = all
        ? 'All warehouses'
        : (whs == null || whs.isEmpty ? null : whs.map((w) => '${w.name} (${w.code})').join(', '));
    final sub = [?scope, if (loadedAt != null) 'figures as of ${fmtTime(loadedAt)} today'].join(' · ');
    return NxPageHeader(
      title: 'Dashboard',
      sub: sub.isEmpty ? null : sub,
      actions: [
        NxButton(
          label: 'Refresh',
          icon: PhosphorIconsRegular.arrowsClockwise,
          onPressed: () => ref.invalidate(dashboardSummaryProvider),
        ),
      ],
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.d});

  final DashboardSummary d;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = context.nx;
    final width = MediaQuery.of(context).size.width;
    final cols = width >= 1024 ? 3 : (width >= 600 ? 2 : 1);

    final pending = d.pendingAdjustments;
    final oldest = pending.items.isEmpty ? null : pending.items.map((a) => a.waitingDays).reduce((a, b) => a > b ? a : b);
    final kpis = [
      _Kpi(
        icon: PhosphorIconsDuotone.package,
        label: 'Active products',
        value: fmtNum(d.catalogue.activeProductCount),
        sub: '${d.catalogue.activeCategoryCount} categories · ${d.catalogue.activeWorkstreamCount} workstreams',
        fg: n.a400,
        onTap: () => context.go(RoutePaths.products),
      ),
      _Kpi(
        icon: PhosphorIconsDuotone.warning,
        label: 'Low stock',
        value: fmtNum(d.lowStock.count),
        sub: 'below minimum level',
        fg: n.warn,
        valueColor: d.lowStock.count > 0 ? n.warn : null,
        onTap: () {
          ref.read(nxListStatesProvider.notifier).preset('products', filters: const {'low': true});
          context.go(RoutePaths.products);
        },
      ),
      _Kpi(
        icon: PhosphorIconsDuotone.hourglassMedium,
        label: 'Pending adjustments',
        value: fmtNum(pending.count),
        sub: pending.count > 0 && oldest != null ? 'oldest ${oldest}d waiting' : 'nothing to review',
        fg: n.warn,
        valueColor: pending.count > 0 ? n.warn : null,
        onTap: () => context.go(RoutePaths.stockAdjustments),
      ),
      _Kpi(
        icon: PhosphorIconsDuotone.coins,
        label: 'Inventory valuation',
        value: fmtMoney(d.valuation.total),
        sub: '${d.valuation.excludedProductCount} product${d.valuation.excludedProductCount == 1 ? '' : 's'} without cost excluded',
        fg: n.a400,
        onTap: () => context.go(RoutePaths.reports),
      ),
      _Kpi(
        icon: PhosphorIconsDuotone.listChecks,
        label: 'Open stock counts',
        value: fmtNum(d.openStockCounts.count),
        sub: 'in progress',
        fg: n.a400,
        onTap: () => context.go(RoutePaths.stockCounts),
      ),
    ];

    final kpiStrip = NxSection(
      child: LayoutBuilder(
        builder: (context, box) {
          final perRow = (box.maxWidth / 160).floor().clamp(1, kpis.length);
          final w = box.maxWidth / perRow;
          return Wrap(children: [for (final k in kpis) SizedBox(width: w, child: k)]);
        },
      ),
    );
    final low = _LowStockPanel(summary: d.lowStock);
    final pend = _PendingPanel(summary: pending);
    final move = _MovementPanel(summary: d.stockMovement);
    final act = _ActivityPanel(summary: d.stockMovement);
    const gap = SizedBox(height: 12, width: 12);

    if (cols == 1) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [kpiStrip, gap, low, gap, pend, gap, move, gap, act]);
    }
    if (cols == 2) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          kpiStrip,
          gap,
          _row([low, pend]),
          gap,
          _row([move, act]),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [kpiStrip, gap, _row([low, pend, move]), gap, act],
    );
  }

  Widget _row(List<Widget> children) => IntrinsicHeight(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(width: 12),
          Expanded(child: children[i]),
        ],
      ],
    ),
  );
}

class _Kpi extends StatefulWidget {
  const _Kpi({required this.icon, required this.label, required this.value, required this.sub, required this.fg, required this.onTap, this.valueColor});

  final IconData icon;
  final String label;
  final String value;
  final String sub;
  final Color fg;
  final Color? valueColor;
  final VoidCallback onTap;

  @override
  State<_Kpi> createState() => _KpiState();
}

class _KpiState extends State<_Kpi> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Semantics(
          button: true,
          label: '${widget.label}: ${widget.value}',
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              color: _hover ? Nocturne.mix(n.surface, n.a800, 0.82) : n.surface,
              border: Border(right: BorderSide(color: n.n800), bottom: BorderSide(color: n.n800)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    PhosphorIcon(widget.icon, size: 14, color: widget.fg),
                    const SizedBox(width: 6),
                    Flexible(child: Text(widget.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: n.n400))),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  widget.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -0.2,
                    color: widget.valueColor ?? n.text,
                    fontFeatures: tabular,
                  ),
                ),
                const SizedBox(height: 3),
                Text(widget.sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: n.n500)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A dashboard panel: 14px heading (optional count pill), a right-side link or note.
class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.children, this.count, this.countTone, this.trailing});

  final String title;
  final int? count;
  final Tone? countTone;
  final Widget? trailing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    return NxSection(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: n.text),
                  ),
                ),
                if (count != null) ...[const SizedBox(width: 8), NxTag('$count', tone: countTone ?? Tone.neutral)],
                const Spacer(),
                if (trailing != null) Flexible(flex: 2, child: Align(alignment: Alignment.centerRight, child: trailing)),
              ],
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}

class _LowStockPanel extends StatelessWidget {
  const _LowStockPanel({required this.summary});

  final LowStockSummary summary;

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    return Consumer(
      builder: (context, ref, _) => _Panel(
        title: 'Low stock',
        count: summary.count,
        countTone: Tone.warn,
        trailing: NxButton.ghost(
          label: 'View all',
          small: true,
          trailingIcon: PhosphorIconsRegular.arrowRight,
          onPressed: () {
            ref.read(nxListStatesProvider.notifier).preset('products', filters: const {'low': true});
            context.go(RoutePaths.products);
          },
        ),
        children: [
          if (summary.items.isEmpty)
            _EmptyLine('Every active product is at or above its minimum.')
          else
            for (final p in summary.items)
              NxHoverRow(
                onTap: () => context.go('${RoutePaths.products}?open=${p.productId}'),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: n.text)),
                          Text('${p.sku} · ${fmtNum(p.onHand)} of ${fmtNum(p.minStockLevel)} min', style: TextStyle(fontSize: 11, color: n.n500)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 72,
                      child: NxBar(
                        fraction: p.minStockLevel <= 0 ? 0 : p.onHand / p.minStockLevel,
                        color: n.warn,
                        track: n.n900,
                      ),
                    ),
                    SizedBox(
                      width: 54,
                      child: Text(
                        fmtSigned(-p.shortfall),
                        textAlign: TextAlign.right,
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: n.bad, fontFeatures: tabular),
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

class _PendingPanel extends StatelessWidget {
  const _PendingPanel({required this.summary});

  final PendingAdjustmentsSummary summary;

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    return _Panel(
      title: 'Pending adjustments',
      count: summary.count,
      trailing: NxButton.ghost(
        label: 'Review queue',
        small: true,
        trailingIcon: PhosphorIconsRegular.arrowRight,
        onPressed: () => context.go(RoutePaths.stockAdjustments),
      ),
      children: [
        if (summary.items.isEmpty)
          _EmptyLine('Nothing waiting for review.')
        else
          for (final a in summary.items)
            Builder(
              builder: (context) {
                final inc = a.direction == 'INCREASE';
                final tone = a.waitingDays >= 3 ? Tone.bad : (a.waitingDays >= 1 ? Tone.warn : Tone.neutral);
                return NxHoverRow(
                  onTap: () => context.go(RoutePaths.stockAdjustments),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 44,
                        child: Text(
                          fmtSigned(inc ? a.delta : -a.delta),
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: inc ? n.ok : n.bad, fontFeatures: tabular),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(a.productName, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: n.text)),
                            Text(
                              '${humanEnum(a.bucket)} · ${a.locationCode} · ${a.reason}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 11, color: n.n500),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      NxTag(fmtWaiting(a.waitingDays), tone: tone),
                    ],
                  ),
                );
              },
            ),
      ],
    );
  }
}

/// Bar colours per ledger transaction type — receipts and returns are good
/// news, damage/loss bad, adjustments and counts need attention.
Tone txTone(String type) => switch (type) {
  'RECEIVE' || 'RETURN' => Tone.ok,
  'DAMAGED' || 'LOST' => Tone.bad,
  'ADJUSTMENT' || 'STOCK_COUNT' => Tone.warn,
  _ => Tone.info,
};

class _MovementPanel extends StatelessWidget {
  const _MovementPanel({required this.summary});

  final StockMovementSummary summary;

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    final entries = summary.byType.entries.where((e) => e.value > 0).toList()..sort((a, b) => b.value.compareTo(a.value));
    final total = entries.fold(0, (s, e) => s + e.value);
    final max = entries.isEmpty ? 1 : entries.first.value;
    return NxSection(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(child: Text('Stock movement', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: n.text))),
                Text('${fmtNum(total)} transactions · ${summary.periodDays} days', style: TextStyle(fontSize: 11, color: n.n500)),
              ],
            ),
            const SizedBox(height: 10),
            if (entries.isEmpty)
              Text('No stock moved in this period.', style: TextStyle(fontSize: 12, color: n.n400))
            else
              for (final e in entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 7),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 120,
                        child: Text(humanEnum(e.key), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: n.n300)),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: NxBar(
                          fraction: e.value / max,
                          height: 7,
                          track: n.n900,
                          color: txTone(e.key) == Tone.info ? n.a500 : n.tone(txTone(e.key)).$1,
                        ),
                      ),
                      SizedBox(
                        width: 38,
                        child: Text(fmtNum(e.value), textAlign: TextAlign.right, style: TextStyle(fontSize: 12, color: n.n300, fontFeatures: tabular)),
                      ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _ActivityPanel extends StatelessWidget {
  const _ActivityPanel({required this.summary});

  final StockMovementSummary summary;

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    return _Panel(
      title: 'Recent activity',
      trailing: Text('Latest ledger transactions', style: TextStyle(fontSize: 11, color: n.n500)),
      children: [
        if (summary.recentActivity.isEmpty)
          _EmptyLine('No stock has moved yet.')
        else
          for (final x in summary.recentActivity.take(8))
            NxHoverRow(
              child: Row(
                children: [
                  SizedBox(
                    width: 108,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: NxTag(x.type.replaceAll('_', ' '), tone: txTone(x.type), small: true),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text.rich(
                          TextSpan(
                            text: x.productName,
                            children: [TextSpan(text: '  ${x.productSku}', style: TextStyle(fontSize: 11, color: n.n500))],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13, color: n.text),
                        ),
                        Text(
                          [
                            if (x.fromLocationLabel != null) 'from ${x.fromLocationLabel}',
                            if (x.toLocationLabel != null) 'to ${x.toLocationLabel}',
                            'by ${x.performedByName}',
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11, color: n.n500),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(fmtNum(x.quantity), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: n.text, fontFeatures: tabular)),
                      Text(fmtWhen(x.createdAt), style: TextStyle(fontSize: 11, color: n.n500)),
                    ],
                  ),
                ],
              ),
            ),
      ],
    );
  }
}

class _EmptyLine extends StatelessWidget {
  const _EmptyLine(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: n.n900))),
      child: Text(text, style: TextStyle(fontSize: 12, color: n.n400)),
    );
  }
}
