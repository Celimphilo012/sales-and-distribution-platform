import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/error/app_error.dart';
import '../../../core/theme/nocturne.dart';
import '../../../shared/nx/nx_format.dart';
import '../../../shared/nx/nx_primitives.dart';
import '../../orders/data/orders_providers.dart';
import '../../orders/domain/order.dart';
import '../../orders/presentation/order_status_tone.dart';
import '../data/payments_api.dart';
import '../domain/payment.dart';
import 'payment_dialogs.dart';

/// Orders in these states take no payments (the backend refuses them too).
const _noPaymentStatuses = {OrderStatus.draft, OrderStatus.rejected, OrderStatus.cancelled};

/// The order's money, beside (never mixed into) its lifecycle — rule 6: paid
/// and still due, every payment (voided ones stay, struck through, with the
/// reason), and record / void for holders of `payments.record` / `.void`.
class OrderPaymentsCard extends ConsumerWidget {
  const OrderPaymentsCard({super.key, required this.order});

  final Order order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = context.nx;
    final user = ref.watch(authProvider.select((s) => s.value?.user));
    final canRecord = user?.can('payments.record') ?? false;
    final canVoid = user?.can('payments.void') ?? false;
    final paymentsAsync = ref.watch(orderPaymentsProvider(order.id));

    void refresh() {
      ref.invalidate(orderPaymentsProvider(order.id));
      ref.invalidate(allPaymentsProvider);
      invalidateOrder(ref, order.id);
    }

    return NxSection(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: paymentsAsync.when(
        loading: () => const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
        error: (e, _) => Text(e is AppError ? e.message : 'Could not load payments.', style: TextStyle(fontSize: 12, color: n.bad)),
        data: (money) {
          final canTake = canRecord && !_noPaymentStatuses.contains(order.status) && money.balanceDue > 0;
          final share = money.total <= 0 ? 0.0 : (money.amountPaid / money.total).clamp(0.0, 1.0).toDouble();
          Widget figure(String l, String v, {Color? c}) => Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l, style: TextStyle(fontSize: 11, color: n.n500)),
                Text(v, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: c ?? n.text, fontFeatures: tabular)),
              ],
            ),
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: NxKicker('Payments', color: n.a300)),
                  NxTag(order.paymentStatus.label, tone: paymentTone(order.paymentStatus), small: true),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  figure('Total', fmtMoney(money.total)),
                  figure('Paid', fmtMoney(money.amountPaid), c: n.ok),
                  figure('Due', fmtMoney(money.balanceDue), c: money.balanceDue > 0 ? n.warn : null),
                ],
              ),
              const SizedBox(height: 8),
              NxBar(fraction: share, height: 6, color: share >= 1 ? n.ok : n.a500),
              const SizedBox(height: 12),
              if (canTake)
                Align(
                  alignment: Alignment.centerLeft,
                  child: NxButton.primary(
                    label: 'Record payment',
                    icon: PhosphorIconsRegular.wallet,
                    onPressed: () async {
                      if (await showRecordPaymentDialog(context, order: order, balanceDue: money.balanceDue)) refresh();
                    },
                  ),
                )
              else if (canRecord && _noPaymentStatuses.contains(order.status))
                Text(
                  order.status == OrderStatus.draft
                      ? 'Payments can be recorded once the order is submitted.'
                      : 'This order is ${order.status.label.toLowerCase()} — it takes no payments.',
                  style: TextStyle(fontSize: 12, color: n.n400),
                ),
              const SizedBox(height: 6),
              if (money.payments.isEmpty)
                Text('No payments recorded yet.', style: TextStyle(fontSize: 12, color: n.n500))
              else
                for (final p in money.payments)
                  _PaymentRow(
                    payment: p,
                    onVoid: canVoid && !p.isVoided
                        ? () async {
                            if (await showVoidPaymentDialog(context, payment: p)) refresh();
                          }
                        : null,
                  ),
              const SizedBox(height: 8),
              Text(
                'Separate from the order status — approving or delivering an order does not mean it is paid.',
                style: TextStyle(fontSize: 11, color: n.n500),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PaymentRow extends StatelessWidget {
  const _PaymentRow({required this.payment, this.onVoid});

  final Payment payment;
  final VoidCallback? onVoid;

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    final struck = payment.isVoided ? TextDecoration.lineThrough : null;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: n.n900))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      fmtMoney(payment.amount),
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: n.text, decoration: struck, fontFeatures: tabular),
                    ),
                    Text(payment.method.label, style: TextStyle(fontSize: 12, color: n.n300, decoration: struck)),
                    if (payment.isVoided) const NxTag('Voided', tone: Tone.bad, small: true),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  [fmtDateTime(payment.paidAt.toLocal()), if (payment.reference != null) 'Ref ${payment.reference}', 'by ${payment.recordedByName}'].join(' · '),
                  style: TextStyle(fontSize: 11, color: n.n500),
                ),
                if (payment.notes != null) Text(payment.notes!, style: TextStyle(fontSize: 11, color: n.n400)),
                if (payment.isVoided)
                  Text(
                    'Voided by ${payment.voidedByName ?? '—'}${payment.voidedAt != null ? ' on ${fmtDateTime(payment.voidedAt!.toLocal())}' : ''}: ${payment.voidReason ?? ''}',
                    style: TextStyle(fontSize: 11, color: n.bad),
                  ),
              ],
            ),
          ),
          if (onVoid != null) NxButton.ghost(label: 'Void', icon: PhosphorIconsRegular.arrowCounterClockwise, small: true, color: n.bad, onPressed: onVoid),
        ],
      ),
    );
  }
}
