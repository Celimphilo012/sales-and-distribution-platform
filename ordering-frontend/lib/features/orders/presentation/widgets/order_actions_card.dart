import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/auth_provider.dart';
import '../../../../core/error/app_error.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../core/theme/nocturne.dart';
import '../../../../shared/nx/nx_overlays.dart';
import '../../../../shared/nx/nx_primitives.dart';
import '../../../../shared/quantity_format.dart';
import '../../data/orders_providers.dart';
import '../../domain/order.dart';
import '../../domain/order_lifecycle.dart';
import 'dispatch_order_dialog.dart';
import 'quantity_entry_dialog.dart';
import 'reject_order_dialog.dart';
import 'reserve_stock_dialog.dart';

/// The order detail's lifecycle actions. Which buttons appear is decided by
/// [kOrderActionsByStatus] (status) ∩ the caller's permissions — an action
/// the user may not perform is simply absent, and the backend enforces the
/// same rules regardless. Fulfilment lives here, as actions on the order,
/// rather than as a separate queue screen.
///
/// Payment status is never touched by any action (rule 6).
class OrderActionsCard extends ConsumerWidget {
  const OrderActionsCard({super.key, required this.order});

  final Order order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = context.nx;
    final user = ref.watch(authProvider.select((s) => s.value?.user));
    final actions = allowedOrderActions(order.status, (p) => user?.can(p) ?? false);
    final forward = forwardActionFor(order.status);

    return NxSection(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NxKicker('Next step', color: n.a300),
          const SizedBox(height: 4),
          Text(
            forward == null ? 'Nothing further' : kOrderActionSpecs[forward]!.label,
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: n.text),
          ),
          const SizedBox(height: 10),
          if (actions.isEmpty)
            Text(_idleMessage(forward), style: TextStyle(fontSize: 12, color: n.n400))
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [for (final action in actions) _ActionButton(order: order, action: action, primary: action == forward)],
            ),
        ],
      ),
    );
  }

  /// Why nothing is offered: the order is finished, or the next step needs a
  /// permission this user lacks.
  String _idleMessage(OrderAction? forward) {
    if (forward == null) {
      return 'This order is ${order.status.label.toLowerCase()} — there are no further actions.';
    }
    final spec = kOrderActionSpecs[forward]!;
    return 'That needs the ${spec.permission} permission, which your account does not have.';
  }
}

class _ActionButton extends ConsumerWidget {
  const _ActionButton({required this.order, required this.action, required this.primary});

  final Order order;
  final OrderAction action;
  final bool primary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spec = kOrderActionSpecs[action]!;
    void onPressed() => _run(context, ref);
    if (primary && !spec.destructive) {
      return NxButton.primary(label: spec.label, icon: _iconFor(action), onPressed: onPressed);
    }
    return NxButton(
      label: spec.label,
      icon: _iconFor(action),
      color: spec.destructive ? context.nx.bad : null,
      onPressed: onPressed,
    );
  }

  Future<void> _run(BuildContext context, WidgetRef ref) async {
    void done(String message) {
      invalidateOrder(ref, order.id);
      NxToast.ok(message, order.orderNumber);
    }

    switch (action) {
      case OrderAction.reserve:
        if (await showReserveStockDialog(context, order: order)) {
          done('Stock reserved — the warehouse has set it aside for this order.');
        }
      case OrderAction.pick:
        if (await showQuantityEntryDialog(context, order: order, step: QuantityStep.pick)) done('Picking recorded.');
      case OrderAction.pack:
        if (await showQuantityEntryDialog(context, order: order, step: QuantityStep.pack)) done('Packing recorded.');
      case OrderAction.reject:
        if (await showRejectOrderDialog(context, order: order)) done('Order rejected.');
      case OrderAction.dispatch:
        final updated = await showDispatchOrderDialog(context, order: order);
        if (updated != null) done(_dispatchMessage(updated));
      case OrderAction.submit ||
          OrderAction.approve ||
          OrderAction.cancel ||
          OrderAction.ready ||
          OrderAction.deliver ||
          OrderAction.complete:
        await _confirmAndRun(context, ref, done);
    }
  }

  /// submit / approve / cancel / ready / deliver / complete: confirm, then a
  /// single call. Errors (incl. "warehouse unavailable" on a cancel that must
  /// release stock) come back as a message — the order is unchanged.
  Future<void> _confirmAndRun(BuildContext context, WidgetRef ref, void Function(String) done) async {
    final spec = kOrderActionSpecs[action]!;
    final text = _confirmText(action, order);
    final confirmed = await showNxConfirm(
      context,
      title: text.title,
      body: text.message,
      confirmLabel: spec.label,
      danger: spec.destructive,
    );
    if (!confirmed) return;
    try {
      await ref.read(ordersApiProvider).transition(order.id, action);
      done(text.success);
    } on AppError catch (e) {
      final failure = classifyLifecycleError(e);
      NxToast.error(
        'Not changed',
        failure is WarehouseUnavailableFailure
            ? 'The warehouse is temporarily unavailable — the order was not changed. Safe to try again.'
            : failure.message,
      );
    }
  }
}

IconData _iconFor(OrderAction action) => switch (action) {
  OrderAction.submit => PhosphorIconsRegular.paperPlaneTilt,
  OrderAction.approve => PhosphorIconsRegular.checkCircle,
  OrderAction.reject => PhosphorIconsRegular.thumbsDown,
  OrderAction.reserve => PhosphorIconsRegular.lockKey,
  OrderAction.cancel => PhosphorIconsRegular.xCircle,
  OrderAction.pick => PhosphorIconsRegular.handGrabbing,
  OrderAction.pack => PhosphorIconsRegular.package,
  OrderAction.ready => PhosphorIconsRegular.flag,
  OrderAction.dispatch => PhosphorIconsRegular.truck,
  OrderAction.deliver => PhosphorIconsRegular.houseLine,
  OrderAction.complete => PhosphorIconsRegular.sealCheck,
};

const _statusesHoldingReservation = {
  OrderStatus.stockReserved,
  OrderStatus.picking,
  OrderStatus.packed,
  OrderStatus.readyForDispatch,
};

({String title, String message, String success}) _confirmText(OrderAction action, Order order) => switch (action) {
  OrderAction.submit => (
    title: 'Submit for approval?',
    message: 'The order moves to Pending approval and can no longer be edited.',
    success: 'Order submitted for approval.',
  ),
  OrderAction.approve => (
    title: 'Approve this order?',
    message: 'The order becomes Approved. Stock is not set aside until you reserve it.',
    success: 'Order approved.',
  ),
  OrderAction.cancel => (
    title: 'Cancel this order?',
    message: _statusesHoldingReservation.contains(order.status)
        ? 'This cancels the order and releases its reserved stock back to the warehouse. It cannot be undone.'
        : 'This cancels the order. It cannot be undone.',
    success: 'Order cancelled.',
  ),
  OrderAction.ready => (
    title: 'Mark ready for dispatch?',
    message: 'Confirms the packed order is ready to leave the warehouse.',
    success: 'Order is ready for dispatch.',
  ),
  OrderAction.deliver => (
    title: 'Mark as delivered?',
    message: 'Confirms the customer has received the goods.',
    success: 'Order marked as delivered.',
  ),
  OrderAction.complete => (
    title: 'Complete this order?',
    message: 'Closes the order. Payment is tracked separately and is not affected.',
    success: 'Order completed.',
  ),
  // The remaining actions have their own dialogs and never reach here.
  _ => (title: 'Confirm', message: 'Continue?', success: 'Done.'),
};

/// The outcome of a dispatch, told from the RETURNED order (the backend sets
/// the status and fulfilled quantities from what the warehouse issued).
String _dispatchMessage(Order updated) {
  final ordered = updated.items.fold<double>(0, (sum, i) => sum + i.quantityOrdered);
  final fulfilled = updated.items.fold<double>(0, (sum, i) => sum + i.quantityFulfilled);
  if (updated.status == OrderStatus.partiallyFulfilled) {
    return 'Partially fulfilled — shipped ${formatQuantity(fulfilled)} of ${formatQuantity(ordered)} units; '
        'the shortfall was released back to available stock.';
  }
  return 'Dispatched — all ${formatQuantity(fulfilled)} units shipped.';
}
