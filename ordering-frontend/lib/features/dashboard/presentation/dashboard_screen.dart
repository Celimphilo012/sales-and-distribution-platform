import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../app_shell/responsive_app_shell.dart';
import '../../../core/auth/app_user.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/error/app_error.dart';
import '../../../core/theme/nocturne.dart';
import '../../../routing/route_paths.dart';
import '../../../shared/nx/nx_format.dart';
import '../../../shared/nx/nx_list_page.dart';
import '../../../shared/nx/nx_primitives.dart';
import '../../orders/data/orders_providers.dart';
import '../../orders/domain/order.dart';
import '../../orders/presentation/order_status_tone.dart';
import '../../reports/data/reports_api.dart';
import '../../reports/domain/reports.dart';

/// Home. Holders of `reports.view` get the sales dashboard — orders and money
/// today / this week, what waits for approval, who still owes, orders by
/// status and the latest orders (SQL aggregates from `GET /dashboard`, plus
/// the order list for the two queues). Everyone else sees their own orders.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider.select((s) => s.value?.user));
    if (user == null) return const SizedBox.shrink();
    final manager = user.can('reports.view');
    return NxPageScroll(
      onRefresh: () async {
        ref.invalidate(dashboardProvider);
        invalidateOrders(ref);
      },
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1400),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(user: user),
            const SizedBox(height: 14),
            if (manager) const _ManagerBody() else _PersonalBody(user: user),
          ],
        ),
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hour = DateTime.now().hour;
    final part = hour < 12 ? 'morning' : (hour < 17 ? 'afternoon' : 'evening');
    return NxPageHeader(
      title: 'Good $part, ${user.name.split(' ').first}',
      sub: '${fmtDate(DateTime.now())} · ${user.can('reports.view') ? 'sales across the team' : 'your orders'}',
      actions: [
        NxButton(
          label: 'Refresh',
          icon: PhosphorIconsRegular.arrowsClockwise,
          onPressed: () {
            ref.invalidate(dashboardProvider);
            invalidateOrders(ref);
          },
        ),
        if (user.can('orders.create')) NxButton.primary(label: 'New order', icon: PhosphorIconsRegular.plus, onPressed: () => context.go(RoutePaths.orderNew)),
      ],
    );
  }
}

// ─── Manager ────────────────────────────────────────────────────────────────

class _ManagerBody extends ConsumerWidget {
  const _ManagerBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = context.nx;
    final async = ref.watch(dashboardProvider);
    final orders = ref.watch(allOrdersProvider).value ?? const <Order>[];
    return async.when(
      loading: () => const NxLoading(message: 'Loading dashboard…'),
      error: (e, _) => NxError(message: e is AppError ? e.message : 'Could not load the dashboard.', onRetry: () => ref.invalidate(dashboardProvider)),
      data: (d) {
        final kpis = [
          _Kpi(icon: PhosphorIconsDuotone.receipt, label: 'Orders today', value: fmtNum(d.todayCount), sub: fmtMoney(d.todayValue), fg: n.a400, onTap: () => context.go(RoutePaths.orders)),
          _Kpi(icon: PhosphorIconsDuotone.calendarBlank, label: 'This week', value: fmtNum(d.weekCount), sub: fmtMoney(d.weekValue), fg: n.a400, onTap: () => context.go(RoutePaths.orders)),
          _Kpi(
            icon: PhosphorIconsDuotone.wallet,
            label: 'Collected this week',
            value: fmtMoney(d.weekCollected),
            sub: '${fmtMoney(d.todayCollected)} today',
            fg: n.ok,
            onTap: () => context.go(RoutePaths.payments),
          ),
          _Kpi(
            icon: PhosphorIconsDuotone.hourglassMedium,
            label: 'Awaiting approval',
            value: fmtNum(d.awaitingApproval),
            sub: d.awaitingApproval > 0 ? 'orders to review' : 'nothing waiting',
            fg: n.warn,
            valueColor: d.awaitingApproval > 0 ? n.warn : null,
            onTap: () => context.go('${RoutePaths.orders}?status=${OrderStatus.pendingApproval.apiValue}'),
          ),
          _Kpi(
            icon: PhosphorIconsDuotone.coins,
            label: 'Still owed',
            value: fmtMoney(d.outstandingAmount),
            sub: '${d.outstandingCount} order${d.outstandingCount == 1 ? '' : 's'}',
            fg: n.bad,
            valueColor: d.outstandingAmount > 0 ? n.warn : null,
            onTap: () => context.go('${RoutePaths.orders}?unpaid=1'),
          ),
        ];
        final approval = orders.where((o) => o.status == OrderStatus.pendingApproval).toList()..sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
        final owed = orders.where((o) => orderCounts(o.status) && o.total > o.amountPaid).toList()
          ..sort((a, b) => (b.total - b.amountPaid).compareTo(a.total - a.amountPaid));

        final approvalPanel = _Panel(
          title: 'Awaiting approval',
          count: approval.length,
          countTone: approval.isEmpty ? Tone.neutral : Tone.warn,
          trailing: NxButton.ghost(
            label: 'Review queue',
            small: true,
            onPressed: () => context.go('${RoutePaths.orders}?status=${OrderStatus.pendingApproval.apiValue}'),
          ),
          children: [
            if (approval.isEmpty)
              const _EmptyLine('Nothing waiting for approval.')
            else
              for (final o in approval.take(5))
                _OrderLine(
                  title: '${o.orderNumber} · ${o.customer.name}',
                  sub: '${o.consultant?.fullName ?? '—'} · waiting ${fmtWhen(o.updatedAt).toLowerCase()}',
                  right: fmtMoney(o.total),
                  onTap: () => context.go(RoutePaths.orderDetail(o.id)),
                ),
          ],
        );
        final owedPanel = _Panel(
          title: 'Customers owe',
          count: owed.length,
          countTone: owed.isEmpty ? Tone.neutral : Tone.bad,
          trailing: NxButton.ghost(label: 'View all', small: true, onPressed: () => context.go('${RoutePaths.orders}?unpaid=1')),
          children: [
            if (owed.isEmpty)
              const _EmptyLine('Every order is paid up.')
            else
              for (final o in owed.take(5))
                _OrderLine(
                  title: o.customer.name,
                  sub: '${o.orderNumber} · ${o.status.label} · paid ${fmtMoney(o.amountPaid)} of ${fmtMoney(o.total)}',
                  right: fmtMoney(o.total - o.amountPaid),
                  rightColor: n.warn,
                  bar: o.total <= 0 ? null : (o.amountPaid / o.total).clamp(0, 1).toDouble(),
                  onTap: () => context.go(RoutePaths.orderDetail(o.id)),
                ),
          ],
        );
        final statusPanel = _StatusPanel(buckets: d.byStatus);
        final recentPanel = _Panel(
          title: 'Latest orders',
          trailing: Text('Newest first', style: TextStyle(fontSize: 11, color: n.n500)),
          children: [
            if (d.recentOrders.isEmpty)
              const _EmptyLine('No orders yet.')
            else
              for (final o in d.recentOrders.take(8))
                _OrderLine(
                  title: '${o.orderNumber} · ${o.customerName}',
                  sub: '${fmtDate(o.orderDate.toLocal())} · ${o.paymentStatus.label}',
                  right: fmtMoney(o.total),
                  tag: NxTag(o.status.label, tone: orderTone(o.status), small: true),
                  onTap: () => context.go(RoutePaths.orderDetail(o.id)),
                ),
          ],
        );
        return _Grid(kpis: kpis, panels: [approvalPanel, owedPanel, statusPanel], wide: recentPanel);
      },
    );
  }
}

class _StatusPanel extends StatelessWidget {
  const _StatusPanel({required this.buckets});

  final List<StatusBucket> buckets;

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    final list = buckets.where((b) => b.count > 0).toList()..sort((a, b) => a.status.index.compareTo(b.status.index));
    final max = list.isEmpty ? 1 : list.map((b) => b.count).reduce((a, b) => a > b ? a : b);
    return _Panel(
      title: 'Orders by status',
      trailing: Text('${fmtNum(list.fold<int>(0, (s, b) => s + b.count))} orders', style: TextStyle(fontSize: 11, color: n.n500)),
      children: [
        if (list.isEmpty)
          const _EmptyLine('No orders yet.')
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
            child: Column(
              children: [
                for (final b in list)
                  InkWell(
                    onTap: () => context.go('${RoutePaths.orders}?status=${b.status.apiValue}'),
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 7),
                      child: Row(
                        children: [
                          SizedBox(width: 120, child: Text(b.status.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: n.n300))),
                          const SizedBox(width: 8),
                          Expanded(
                            child: NxBar(
                              fraction: b.count / max,
                              height: 7,
                              track: n.n900,
                              color: orderTone(b.status) == Tone.info ? n.a500 : n.tone(orderTone(b.status)).$1,
                            ),
                          ),
                          SizedBox(width: 34, child: Text(fmtNum(b.count), textAlign: TextAlign.right, style: TextStyle(fontSize: 12, color: n.n300, fontFeatures: tabular))),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

// ─── Personal ───────────────────────────────────────────────────────────────

class _PersonalBody extends ConsumerWidget {
  const _PersonalBody({required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = context.nx;
    if (!user.canAny(const ['orders.view_own', 'orders.view_team'])) {
      return const _EmptyLine('Welcome — your role has no order screens. Use the menu to get to what you need.');
    }
    final async = ref.watch(allOrdersProvider);
    return async.when(
      loading: () => const NxLoading(message: 'Loading your orders…'),
      error: (e, _) => NxError(message: e is AppError ? e.message : 'Could not load your orders.', onRetry: () => invalidateOrders(ref)),
      data: (all) {
        // The server already scopes GET /orders to the viewer (own orders without orders.view_team).
        final mine = [...all]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        int at(OrderStage s) => mine.where((o) => orderStage(o.status) == s).length;
        final month = DateTime.now();
        final monthValue = mine.where((o) => orderCounts(o.status) && o.orderDate.year == month.year && o.orderDate.month == month.month).fold<double>(0, (s, o) => s + o.total);
        final kpis = [
          _Kpi(icon: PhosphorIconsDuotone.notePencil, label: 'Drafts', value: fmtNum(at(OrderStage.draft)), sub: 'not yet submitted', fg: n.n400, onTap: () => context.go(RoutePaths.orders)),
          _Kpi(icon: PhosphorIconsDuotone.hourglassMedium, label: 'Awaiting approval', value: fmtNum(at(OrderStage.approval)), sub: 'with a manager', fg: n.warn, onTap: () => context.go(RoutePaths.orders)),
          _Kpi(icon: PhosphorIconsDuotone.package, label: 'In fulfilment', value: fmtNum(at(OrderStage.fulfilment)), sub: 'approved → ready', fg: n.a400, onTap: () => context.go(RoutePaths.orders)),
          _Kpi(icon: PhosphorIconsDuotone.truck, label: 'Shipped', value: fmtNum(at(OrderStage.shipped)), sub: 'on the way or delivered', fg: n.ok, onTap: () => context.go(RoutePaths.orders)),
          _Kpi(icon: PhosphorIconsDuotone.coins, label: 'This month', value: fmtMoney(monthValue), sub: 'value of your orders', fg: n.a400, onTap: () => context.go(RoutePaths.orders)),
        ];
        final recent = _Panel(
          title: 'Your latest orders',
          trailing: NxButton.ghost(label: 'All orders', small: true, onPressed: () => context.go(RoutePaths.orders)),
          children: [
            if (mine.isEmpty)
              const _EmptyLine('No orders yet — start one with “New order”.')
            else
              for (final o in mine.take(10))
                _OrderLine(
                  title: '${o.orderNumber} · ${o.customer.name}',
                  sub: '${fmtDate(o.orderDate.toLocal())} · ${o.paymentStatus.label}',
                  right: fmtMoney(o.total),
                  tag: NxTag(o.status.label, tone: orderTone(o.status), small: true),
                  onTap: () => context.go(RoutePaths.orderDetail(o.id)),
                ),
          ],
        );
        return _Grid(kpis: kpis, panels: const [], wide: recent);
      },
    );
  }
}

// ─── Layout pieces ──────────────────────────────────────────────────────────

class _Grid extends StatelessWidget {
  const _Grid({required this.kpis, required this.panels, required this.wide});

  final List<_Kpi> kpis;
  final List<Widget> panels;
  final Widget wide;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final cols = width >= 1024 ? 3 : (width >= 600 ? 2 : 1);
    const gap = SizedBox(height: 12, width: 12);
    final strip = NxSection(
      child: LayoutBuilder(
        builder: (context, box) {
          final perRow = (box.maxWidth / 170).floor().clamp(1, kpis.length);
          final w = box.maxWidth / perRow;
          return Wrap(children: [for (final k in kpis) SizedBox(width: w, child: k)]);
        },
      ),
    );
    final rows = <Widget>[];
    for (var i = 0; i < panels.length; i += cols) {
      final chunk = panels.sublist(i, (i + cols).clamp(0, panels.length));
      rows
        ..add(
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var j = 0; j < cols; j++) ...[
                  if (j > 0) gap,
                  Expanded(child: j < chunk.length ? chunk[j] : const SizedBox.shrink()),
                ],
              ],
            ),
          ),
        )
        ..add(gap);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [strip, gap, ...rows, wide]);
  }
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
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w500, letterSpacing: -0.2, color: widget.valueColor ?? n.text, fontFeatures: tabular),
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
                Flexible(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: n.text))),
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

class _OrderLine extends StatelessWidget {
  const _OrderLine({required this.title, required this.sub, required this.right, required this.onTap, this.rightColor, this.tag, this.bar});

  final String title;
  final String sub;
  final String right;
  final Color? rightColor;
  final NxTag? tag;
  final double? bar;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    return NxHoverRow(
      onTap: onTap,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: n.text)),
                Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: n.n500)),
                if (bar != null) ...[const SizedBox(height: 4), NxBar(fraction: bar!, height: 3)],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(right, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: rightColor ?? n.text, fontFeatures: tabular)),
              ?tag,
            ],
          ),
        ],
      ),
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
