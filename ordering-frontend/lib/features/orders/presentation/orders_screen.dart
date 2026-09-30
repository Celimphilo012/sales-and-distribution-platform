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
import '../data/orders_providers.dart';
import '../domain/order.dart';
import 'order_status_tone.dart';

class _Row {
  _Row(this.o);

  final Order o;

  OrderStage get stage => orderStage(o.status);
  bool get counts => orderCounts(o.status);
  double get owed => counts ? (o.total - o.amountPaid).clamp(0, double.infinity).toDouble() : 0;
  double get paidShare => o.total <= 0 ? 0 : (o.amountPaid / o.total).clamp(0, 1).toDouble();
  double get units => o.items.fold<double>(0, (s, i) => s + i.quantityOrdered);
}

/// Orders — every order the viewer may see, one [NxListPage]: stages as the
/// quick filter, status / payment / customer / consultant / date / value
/// filters. `?status=<API value>` or `?unpaid=1` (from the notifications bell)
/// opens it pre-filtered.
class OrdersScreen extends ConsumerStatefulWidget {
  const OrdersScreen({super.key, this.initialStatus, this.unpaidOnly = false});

  final String? initialStatus;
  final bool unpaidOnly;

  @override
  ConsumerState<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends ConsumerState<OrdersScreen> {
  @override
  void initState() {
    super.initState();
    if (widget.initialStatus != null || widget.unpaidOnly) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(nxListStatesProvider.notifier).preset('orders', filters: {
          if (widget.initialStatus != null) 'status': {widget.initialStatus!},
          if (widget.unpaidOnly) 'owed': true,
        });
        GoRouter.of(context).go(RoutePaths.orders);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    final user = ref.watch(authProvider).value?.user;
    final canCreate = user?.can('orders.create') ?? false;
    final async = ref.watch(allOrdersProvider);

    return NxPageScroll(
      onRefresh: () async => invalidateOrders(ref),
      child: async.when(
        loading: () => const NxLoading(message: 'Loading orders…'),
        error: (e, _) => NxError(message: e is AppError ? e.message : 'Could not load orders.', onRetry: () => invalidateOrders(ref)),
        data: (orders) {
          final rows = [for (final o in orders) _Row(o)];
          List<(String, String)> opts(Map<String, String> m) => (m.entries.toList()..sort((a, b) => a.value.compareTo(b.value))).map((e) => (e.key, e.value)).toList();
          final customers = opts({for (final o in orders) o.customerId: o.customer.name});
          final consultants = opts({for (final o in orders) if (o.consultant != null) o.consultant!.id: o.consultant!.fullName});
          NxTag status(_Row r) => NxTag(r.o.status.label, tone: orderTone(r.o.status));
          NxTag pay(_Row r) => NxTag(r.o.paymentStatus.label, tone: paymentTone(r.o.paymentStatus), small: true);
          void open(_Row r) => context.go(RoutePaths.orderDetail(r.o.id));

          return NxListPage<_Row>(
            stateKey: 'orders',
            title: 'Orders',
            sub: 'Draft → approval → stock reserved → picked, packed, dispatched → delivered. Payments run separately.',
            actions: [
              if (canCreate) NxButton.primary(label: 'New order', icon: PhosphorIconsRegular.plus, onPressed: () => context.go(RoutePaths.orderNew)),
            ],
            rows: rows,
            search: (r) => '${r.o.orderNumber} ${r.o.customer.name} ${r.o.consultant?.fullName ?? ''}',
            searchPlaceholder: 'Order number or customer',
            stats: (rs) {
              final live = rs.where((r) => r.counts);
              final waiting = rs.where((r) => r.stage == OrderStage.approval).length;
              final owed = live.fold<double>(0, (s, r) => s + r.owed);
              return [
                NxStat('Orders', fmtNum(rs.length), sub: '${rs.where((r) => r.stage == OrderStage.draft).length} drafts'),
                NxStat('Awaiting approval', fmtNum(waiting), color: waiting > 0 ? n.warn : null),
                NxStat('In fulfilment', fmtNum(rs.where((r) => r.stage == OrderStage.fulfilment).length), sub: 'approved → ready', color: n.a300),
                NxStat('Order value', fmtMoney(live.fold<double>(0, (s, r) => s + r.o.total)), sub: 'excl. drafts, rejected, cancelled'),
                NxStat('Still owed', fmtMoney(owed), color: owed > 0 ? n.warn : null),
              ];
            },
            quick: NxQuick(
              get: (r) => r.stage.name,
              options: const [
                ('', 'All'),
                ('draft', 'Drafts'),
                ('approval', 'Approval'),
                ('fulfilment', 'Fulfilment'),
                ('shipped', 'Shipped'),
                ('closed', 'Closed'),
              ],
            ),
            filters: [
              NxMultiFilter('status', 'Status', options: [for (final s in OrderStatus.values) (s.apiValue, s.label)], get: (r) => r.o.status.apiValue),
              NxSelectFilter('pay', 'Payment', options: [for (final p in PaymentStatus.values) (p.name, p.label)], get: (r) => r.o.paymentStatus.name),
              NxSelectFilter('cust', 'Customer', searchable: true, options: customers, get: (r) => r.o.customerId),
              if (consultants.length > 1) NxSelectFilter('cons', 'Consultant', options: consultants, get: (r) => r.o.consultant?.id),
              NxDateFilter('date', 'Order date', get: (r) => r.o.orderDate.toLocal()),
              NxRangeFilter('total', 'Total', get: (r) => r.o.total),
              NxToggleFilter('owed', 'Money', text: 'Still owed money', get: (r) => r.owed > 0),
            ],
            defaultSort: ('date', -1),
            columns: [
              NxColumn(
                key: 'num',
                label: 'Order',
                sort: (r) => r.o.orderNumber,
                cell: (r) => NxCellText(r.o.orderNumber, mono: true, weight: FontWeight.w500, sub: '${r.o.items.length} line${r.o.items.length == 1 ? '' : 's'}'),
              ),
              NxColumn(key: 'cust', label: 'Customer', sort: (r) => r.o.customer.name.toLowerCase(), cell: (r) => NxCellText(r.o.customer.name, sub: r.o.customer.phone)),
              NxColumn(key: 'cons', label: 'Consultant', hide: NxHide.wide, sort: (r) => r.o.consultant?.fullName ?? '', cell: (r) => NxCellText(r.o.consultant?.fullName ?? '—', color: n.n300)),
              NxColumn(key: 'date', label: 'Date', hide: NxHide.md, sort: (r) => r.o.orderDate, cell: (r) => NxCellText(fmtDate(r.o.orderDate.toLocal()), color: n.n300)),
              NxColumn(key: 'total', label: 'Total', align: TextAlign.right, sort: (r) => r.o.total, cell: (r) => NxCellText(fmtMoney(r.o.total), align: TextAlign.right, weight: FontWeight.w500)),
              NxColumn(
                key: 'paid',
                label: 'Paid',
                width: 150,
                hide: NxHide.md,
                sort: (r) => r.paidShare,
                cell: (r) => r.counts
                    ? NxLabeledBar(label: '${(r.paidShare * 100).round()}%', fraction: r.paidShare, color: r.paidShare >= 1 ? n.ok : n.a500)
                    : NxCellText('—', color: n.n500),
              ),
              NxColumn(key: 'status', label: 'Status', sort: (r) => r.o.status.index, cell: (r) => Align(alignment: Alignment.centerLeft, child: status(r))),
              NxColumn(key: 'pay', label: 'Payment', hide: NxHide.wide, sort: (r) => r.o.paymentStatus.index, cell: (r) => Align(alignment: Alignment.centerLeft, child: pay(r))),
            ],
            listRow: (r) => NxListRowSpec(
              icon: PhosphorIconsDuotone.receipt,
              iconColor: n.a400,
              title: '${r.o.orderNumber} · ${r.o.customer.name}',
              sub: '${fmtDate(r.o.orderDate.toLocal())} · ${r.o.items.length} lines · ${r.o.paymentStatus.label}',
              right: fmtMoney(r.o.total),
              rightSub: r.owed > 0 ? '${fmtMoney(r.owed)} owed' : null,
              rightColor: null,
              tag: status(r),
            ),
            card: (r) => NxCardSpec(
              icon: PhosphorIconsDuotone.receipt,
              title: r.o.orderNumber,
              sub: r.o.customer.name,
              metrics: [('Total', fmtMoney(r.o.total), null), ('Owed', r.counts ? fmtMoney(r.owed) : '—', r.owed > 0 ? n.warn : null)],
              tag: status(r),
              bar: r.counts ? r.paidShare : null,
              barColor: r.paidShare >= 1 ? n.ok : n.a500,
            ),
            onOpen: open,
            emptyTitle: 'No orders match',
            emptyMessage: canCreate ? 'Adjust filters, or create an order.' : 'Adjust filters.',
          );
        },
      ),
    );
  }
}
