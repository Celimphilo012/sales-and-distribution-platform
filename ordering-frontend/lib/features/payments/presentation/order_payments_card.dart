import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/error/app_error.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/date_format.dart';
import '../../../shared/money_format.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/status_badge.dart';
import '../../orders/data/orders_providers.dart';
import '../../orders/domain/order.dart';
import '../../orders/presentation/order_status_tone.dart';
import '../data/payments_api.dart';
import '../domain/payment.dart';
import 'payment_dialogs.dart';

/// Orders in these states take no payments (the backend refuses them too).
const _noPaymentStatuses = {OrderStatus.draft, OrderStatus.rejected, OrderStatus.cancelled};

/// The order's money, next to (never mixed into) its lifecycle — rule 6:
/// how much is paid and still due, every payment (voided ones stay visible,
/// struck through, with the reason), and the record / void actions for
/// holders of `payments.record` / `payments.void`.
class OrderPaymentsCard extends ConsumerWidget {
  const OrderPaymentsCard({super.key, required this.order});

  final Order order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final user = ref.watch(authProvider.select((s) => s.value?.user));
    final canRecord = user?.can('payments.record') ?? false;
    final canVoid = user?.can('payments.void') ?? false;
    final paymentsAsync = ref.watch(orderPaymentsProvider(order.id));

    void refresh() {
      ref.invalidate(orderPaymentsProvider(order.id));
      invalidateOrder(ref, order.id);
    }

    return AppCard(
      title: 'Payments',
      subtitle:
          'Recorded separately from the order status — approving or delivering an order does not mean it is paid.',
      trailing: StatusBadge(label: order.paymentStatus.label, tone: paymentStatusTone(order.paymentStatus)),
      child: paymentsAsync.when(
        loading: () => const Padding(padding: EdgeInsets.all(AppSpacing.md), child: LinearProgressIndicator()),
        error: (error, _) => Text(
          error is AppError ? error.message : 'Could not load payments.',
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
        ),
        data: (money) {
          final canTakePayment = canRecord && !_noPaymentStatuses.contains(order.status) && money.balanceDue > 0;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _MoneySummary(money: money),
              if (canTakePayment || (canRecord && _noPaymentStatuses.contains(order.status))) ...[
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  spacing: AppSpacing.sm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (canTakePayment)
                      FilledButton.icon(
                        onPressed: () async {
                          if (await showRecordPaymentDialog(context, order: order, balanceDue: money.balanceDue)) {
                            refresh();
                          }
                        },
                        icon: const Icon(Icons.payments_outlined),
                        label: const Text('Record payment'),
                      )
                    else
                      Text(
                        order.status == OrderStatus.draft
                            ? 'Payments can be recorded once the order is submitted.'
                            : 'This order is ${order.status.label.toLowerCase()} — it takes no payments.',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              if (money.payments.isEmpty)
                Text(
                  'No payments recorded yet.',
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                )
              else
                for (final payment in money.payments)
                  _PaymentRow(
                    payment: payment,
                    onVoid: canVoid && !payment.isVoided
                        ? () async {
                            if (await showVoidPaymentDialog(context, payment: payment)) refresh();
                          }
                        : null,
                  ),
            ],
          );
        },
      ),
    );
  }
}

class _MoneySummary extends StatelessWidget {
  const _MoneySummary({required this.money});

  final OrderPayments money;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = money.total <= 0 ? 0.0 : (money.amountPaid / money.total).clamp(0.0, 1.0);

    Widget figure(String label, String value, {Color? color}) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(color: color, fontWeight: FontWeight.w600),
        ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: AppSpacing.xl,
          runSpacing: AppSpacing.sm,
          children: [
            figure('Order total', formatMoney(money.total)),
            figure('Paid', formatMoney(money.amountPaid)),
            figure(
              'Balance due',
              formatMoney(money.balanceDue),
              color: money.balanceDue > 0 ? theme.colorScheme.error : null,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          child: LinearProgressIndicator(value: progress, minHeight: 8),
        ),
      ],
    );
  }
}

class _PaymentRow extends StatelessWidget {
  const _PaymentRow({required this.payment, this.onVoid});

  final Payment payment;
  final VoidCallback? onVoid;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final struck = payment.isVoided ? const TextStyle(decoration: TextDecoration.lineThrough) : null;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: theme.colorScheme.outlineVariant)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: AppSpacing.sm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      formatMoney(payment.amount),
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600).merge(struck),
                    ),
                    Text(payment.method.label, style: theme.textTheme.bodyMedium?.merge(struck)),
                    if (payment.isVoided) const StatusBadge(label: 'Voided', tone: StatusTone.danger),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    formatDateTime(payment.paidAt),
                    if (payment.reference != null) 'Ref ${payment.reference}',
                    'recorded by ${payment.recordedByName}',
                  ].join(' · '),
                  style: muted,
                ),
                if (payment.notes != null) Text(payment.notes!, style: muted),
                if (payment.isVoided)
                  Text(
                    'Voided by ${payment.voidedByName ?? '—'}'
                    '${payment.voidedAt != null ? ' on ${formatDateTime(payment.voidedAt!)}' : ''}: ${payment.voidReason ?? ''}',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                  ),
              ],
            ),
          ),
          if (onVoid != null)
            TextButton.icon(
              onPressed: onVoid,
              icon: const Icon(Icons.undo, size: 18),
              label: const Text('Void'),
              style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
            ),
        ],
      ),
    );
  }
}
