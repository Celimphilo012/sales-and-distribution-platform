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
import '../../payments/presentation/order_payments_card.dart';
import '../data/orders_providers.dart';
import '../domain/order.dart';
import 'order_status_tone.dart';
import 'widgets/order_actions_card.dart';

/// The happy path, in order — the progress strip across the top.
const _path = [
  (OrderStatus.draft, 'Draft'),
  (OrderStatus.pendingApproval, 'Approval'),
  (OrderStatus.approved, 'Approved'),
  (OrderStatus.stockReserved, 'Reserved'),
  (OrderStatus.picking, 'Picked'),
  (OrderStatus.packed, 'Packed'),
  (OrderStatus.readyForDispatch, 'Ready'),
  (OrderStatus.dispatched, 'Dispatched'),
  (OrderStatus.delivered, 'Delivered'),
  (OrderStatus.completed, 'Completed'),
];

int _stepOf(OrderStatus s) => switch (s) {
  OrderStatus.submitted => 1,
  OrderStatus.partiallyFulfilled => 7,
  _ => _path.indexWhere((p) => p.$1 == s),
};

/// One order: where it is in its life, its lines (server snapshots — never
/// recomputed), history, and beside them the next step (lifecycle actions for
/// this user's permissions), the money (rule 6: separate from the status) and
/// the facts. Fulfilment lives here, as actions on the order.
class OrderDetailScreen extends ConsumerWidget {
  const OrderDetailScreen({super.key, required this.orderId});

  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(orderDetailProvider(orderId));
    return NxPageScroll(
      onRefresh: () async => invalidateOrder(ref, orderId),
      child: async.when(
        loading: () => const NxLoading(message: 'Loading order…'),
        error: (e, _) => NxError(
          message: e is AppError ? e.message : 'Could not load this order.',
          onRetry: () => ref.invalidate(orderDetailProvider(orderId)),
        ),
        data: (order) => _Body(order: order),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = context.nx;
    final user = ref.watch(authProvider.select((s) => s.value?.user));
    final canEdit = order.status == OrderStatus.draft && (user?.can('orders.edit_own_draft') ?? false) && order.consultantId == user?.id;
    final width = MediaQuery.of(context).size.width;
    final wide = width >= 1024;

    final main = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Lines(order: order),
        if (order.status == OrderStatus.partiallyFulfilled) ...[const SizedBox(height: 12), _PartialNote(order: order)],
        if (order.statusHistory.isNotEmpty) ...[const SizedBox(height: 12), _History(order: order)],
      ],
    );
    final side = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OrderActionsCard(order: order),
        const SizedBox(height: 12),
        OrderPaymentsCard(order: order),
        const SizedBox(height: 12),
        _Facts(order: order),
      ],
    );

    return Align(
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1400),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: NxButton.ghost(
                  label: 'All orders',
                  icon: PhosphorIconsRegular.arrowLeft,
                  small: true,
                  color: n.n400,
                  onPressed: () => context.go(RoutePaths.orders),
                ),
              ),
            ),
            NxPageHeader(
              title: order.orderNumber,
              sub: '${order.customer.name} · ${fmtDate(order.orderDate.toLocal())} · ${order.items.length} line${order.items.length == 1 ? '' : 's'} · ${fmtMoney(order.total)}',
              actions: [
                NxTag(order.status.label, tone: orderTone(order.status)),
                NxTag(order.paymentStatus.label, tone: paymentTone(order.paymentStatus)),
                if (canEdit) NxButton(label: 'Edit draft', icon: PhosphorIconsRegular.pencilSimple, onPressed: () => context.go(RoutePaths.orderEdit(order.id))),
              ],
            ),
            const SizedBox(height: 12),
            _Progress(status: order.status),
            const SizedBox(height: 12),
            if (wide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 16, child: main),
                  const SizedBox(width: 12),
                  Expanded(flex: 10, child: side),
                ],
              )
            else ...[side, const SizedBox(height: 12), main],
          ],
        ),
      ),
    );
  }
}

/// Draft → … → Completed, done steps ticked; a rejected / cancelled order
/// shows where it stopped.
class _Progress extends StatelessWidget {
  const _Progress({required this.status});

  final OrderStatus status;

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    final stopped = status == OrderStatus.rejected || status == OrderStatus.cancelled;
    final at = _stepOf(status);
    return NxSection(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: stopped
          ? Row(
              children: [
                Icon(PhosphorIconsFill.xCircle, color: n.bad, size: 18),
                const SizedBox(width: 8),
                Text('This order was ${status.label.toLowerCase()}.', style: TextStyle(fontSize: 13, color: n.text)),
              ],
            )
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var i = 0; i < _path.length; i++) ...[
                    if (i > 0) Container(width: 22, height: 1, color: i <= at ? n.accent : n.divider),
                    _Step(
                      label: i == 7 && status == OrderStatus.partiallyFulfilled ? 'Part-shipped' : _path[i].$2,
                      done: i < at || (i == at && status == OrderStatus.completed),
                      current: i == at && status != OrderStatus.completed,
                      warn: i == 7 && status == OrderStatus.partiallyFulfilled,
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.label, required this.done, required this.current, this.warn = false});

  final String label;
  final bool done;
  final bool current;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    final c = warn ? n.warn : n.accent;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 18,
          height: 18,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: done ? c : (current ? Nocturne.mix(c, n.surface, 0.18) : Colors.transparent),
            border: Border.all(color: done || current ? c : n.divider, width: current ? 2 : 1),
          ),
          child: done ? Icon(PhosphorIconsBold.check, size: 10, color: n.surface) : null,
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: current ? n.text : (done ? n.n300 : n.n500), fontWeight: current ? FontWeight.w500 : FontWeight.w400),
        ),
      ],
    );
  }
}

class _Lines extends StatelessWidget {
  const _Lines({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    final fulfilment = order.items.any((i) => i.quantityPicked > 0 || i.quantityPacked > 0 || i.quantityFulfilled > 0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NxTable<OrderItem>(
          rows: order.items,
          columns: [
            NxColumn(
              key: 'p',
              label: 'Product',
              cell: (i) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          i.productName ?? '(unknown product)',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: n.text),
                        ),
                      ),
                      if (i.wasDiscounted) ...[
                        const SizedBox(width: 6),
                        NxTag(i.saleCampaignName ?? 'Sale', tone: Tone.accent, small: true),
                      ],
                    ],
                  ),
                  if (i.allocations.isNotEmpty)
                    Text(
                      'Reserved at ${i.allocations.map((a) => '${a.locationLabel ?? 'location'} × ${fmtNum(a.quantity)}').join(' · ')}',
                      style: TextStyle(fontSize: 11, color: n.n500),
                    ),
                ],
              ),
            ),
            NxColumn(key: 'q', label: 'Qty', align: TextAlign.right, cell: (i) => NxCellText(fmtNum(i.quantityOrdered), align: TextAlign.right)),
            if (fulfilment) ...[
              NxColumn(key: 'pk', label: 'Picked', align: TextAlign.right, hide: NxHide.md, cell: (i) => NxCellText(fmtNum(i.quantityPicked), align: TextAlign.right, color: n.n300)),
              NxColumn(key: 'pa', label: 'Packed', align: TextAlign.right, hide: NxHide.md, cell: (i) => NxCellText(fmtNum(i.quantityPacked), align: TextAlign.right, color: n.n300)),
              NxColumn(
                key: 'sh',
                label: 'Shipped',
                align: TextAlign.right,
                cell: (i) => NxCellText(
                  fmtNum(i.quantityFulfilled),
                  align: TextAlign.right,
                  color: i.quantityFulfilled < i.quantityOrdered && order.status == OrderStatus.partiallyFulfilled ? n.warn : n.n300,
                ),
              ),
            ],
            NxColumn(
              key: 'u',
              label: 'Unit price',
              align: TextAlign.right,
              hide: NxHide.md,
              cell: (i) => i.wasDiscounted
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          fmtMoney(i.originalUnitPrice!),
                          style: TextStyle(fontSize: 11, color: n.n500, decoration: TextDecoration.lineThrough),
                        ),
                        Text(fmtMoney(i.unitPrice), style: TextStyle(fontSize: 13, color: n.warn, fontWeight: FontWeight.w600)),
                      ],
                    )
                  : NxCellText(fmtMoney(i.unitPrice), align: TextAlign.right, color: n.n300),
            ),
            NxColumn(key: 't', label: 'Line total', align: TextAlign.right, cell: (i) => NxCellText(fmtMoney(i.lineTotal), align: TextAlign.right, weight: FontWeight.w500)),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                'Names and prices are snapshots taken when each line was added.',
                style: TextStyle(fontSize: 11, color: n.n500),
              ),
            ),
            Text('Order total  ', style: TextStyle(fontSize: 12, color: n.n400)),
            Text(fmtMoney(order.total), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500, color: n.text, fontFeatures: tabular)),
          ],
        ),
      ],
    );
  }
}

class _Facts extends StatelessWidget {
  const _Facts({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    Widget row(String l, String? v) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 100, child: Text(l, style: TextStyle(fontSize: 12, color: n.n500))),
          Expanded(child: Text((v == null || v.isEmpty) ? '—' : v, style: TextStyle(fontSize: 13, color: n.text))),
        ],
      ),
    );
    return NxSection(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NxKicker('Details', color: n.a300),
          const SizedBox(height: 8),
          InkWell(
            onTap: () => context.go(RoutePaths.customerDetail(order.customerId)),
            child: row('Customer', '${order.customer.name}${order.customer.phone != null ? ' · ${order.customer.phone}' : ''}'),
          ),
          row('Consultant', order.consultant?.fullName),
          row('Order date', fmtDateTime(order.orderDate.toLocal())),
          row('Delivery', order.deliveryInfo),
          row('Updated', fmtDateTime(order.updatedAt.toLocal())),
        ],
      ),
    );
  }
}

class _History extends StatelessWidget {
  const _History({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    final entries = [...order.statusHistory]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return NxSection(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('History', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: n.text)),
          const SizedBox(height: 8),
          for (final e in entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: n.tone(orderTone(e.toStatus)).$1)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${e.fromStatus != null ? '${e.fromStatus!.label} → ' : ''}${e.toStatus.label}',
                          style: TextStyle(fontSize: 13, color: n.text),
                        ),
                        Text('${e.changedByName} · ${fmtDateTime(e.createdAt.toLocal())}', style: TextStyle(fontSize: 11, color: n.n500)),
                        if (e.note != null && e.note!.isNotEmpty) Text('“${e.note}”', style: TextStyle(fontSize: 12, color: n.n300)),
                      ],
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

/// PARTIALLY_FULFILLED: what shipped vs what was ordered, so the shortfall is
/// impossible to miss.
class _PartialNote extends StatelessWidget {
  const _PartialNote({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    final short = order.items.where((i) => i.quantityFulfilled < i.quantityOrdered);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: n.warn.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(NxRadius.md)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Partially fulfilled', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: n.warn)),
          Text('Some lines shipped less than ordered. The shortfall was released back to available stock.', style: TextStyle(fontSize: 12, color: n.text)),
          for (final i in short)
            Text(
              '${i.productName ?? i.productId}: shipped ${fmtNum(i.quantityFulfilled)} of ${fmtNum(i.quantityOrdered)} (short ${fmtNum(i.quantityOrdered - i.quantityFulfilled)})',
              style: TextStyle(fontSize: 12, color: n.text),
            ),
        ],
      ),
    );
  }
}
