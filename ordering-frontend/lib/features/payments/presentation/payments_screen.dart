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
import '../../orders/data/orders_providers.dart';
import '../data/payments_api.dart';
import '../domain/payment.dart';
import 'payment_dialogs.dart';

IconData _methodIcon(PaymentMethod m) => switch (m) {
  PaymentMethod.cash => PhosphorIconsDuotone.money,
  PaymentMethod.mobileMoney => PhosphorIconsDuotone.deviceMobile,
  PaymentMethod.bankTransfer => PhosphorIconsDuotone.bank,
  PaymentMethod.card => PhosphorIconsDuotone.creditCard,
};

/// Payments (reports.view) — every payment against every order, newest
/// first. A mistake is voided (kept, struck through, with the reason) — never
/// edited or deleted. Opening a row goes to its order.
class PaymentsScreen extends ConsumerWidget {
  const PaymentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = context.nx;
    final canVoid = ref.watch(authProvider.select((s) => s.value?.user?.can('payments.void') ?? false));
    final async = ref.watch(allPaymentsProvider);

    return NxPageScroll(
      onRefresh: () async => ref.invalidate(allPaymentsProvider),
      child: async.when(
        loading: () => const NxLoading(message: 'Loading payments…'),
        error: (e, _) => NxError(message: e is AppError ? e.message : 'Could not load payments.', onRetry: () => ref.invalidate(allPaymentsProvider)),
        data: (payments) {
          List<(String, String)> opts(Map<String, String> m) => (m.entries.toList()..sort((a, b) => a.value.compareTo(b.value))).map((e) => (e.key, e.value)).toList();
          final customers = opts({for (final p in payments) if (p.customerId != null) p.customerId!: p.customerName ?? '—'});
          final recorders = opts({for (final p in payments) p.recordedByName: p.recordedByName});
          final today = DateTime.now();
          bool thisMonth(DateTime d) => d.year == today.year && d.month == today.month;
          NxTag state(Payment p) => NxTag(p.isVoided ? 'Voided' : 'Recorded', tone: p.isVoided ? Tone.bad : Tone.ok, small: true);
          List<NxRowAction> acts(Payment p) => [
            if (canVoid && !p.isVoided)
              NxRowAction(
                icon: PhosphorIconsRegular.arrowCounterClockwise,
                label: 'Void',
                danger: true,
                onPressed: () async {
                  if (await showVoidPaymentDialog(context, payment: p)) {
                    ref.invalidate(allPaymentsProvider);
                    invalidateOrders(ref);
                  }
                },
              ),
          ];

          return NxListPage<Payment>(
            stateKey: 'payments',
            title: 'Payments',
            sub: 'Money received against orders. A mistake is voided — kept with the reason — never edited or deleted.',
            rows: payments,
            search: (p) => '${p.orderNumber ?? ''} ${p.customerName ?? ''} ${p.reference ?? ''}',
            searchPlaceholder: 'Order, customer or reference',
            stats: (rs) {
              final live = rs.where((p) => !p.isVoided);
              return [
                NxStat('Collected', fmtMoney(live.fold<double>(0, (s, p) => s + p.amount)), sub: '${live.length} payments', color: n.ok),
                NxStat('This month', fmtMoney(live.where((p) => thisMonth(p.paidAt.toLocal())).fold<double>(0, (s, p) => s + p.amount))),
                for (final m in [PaymentMethod.cash, PaymentMethod.mobileMoney])
                  NxStat(m == PaymentMethod.cash ? 'Cash' : 'MoMo', fmtMoney(live.where((p) => p.method == m).fold<double>(0, (s, p) => s + p.amount))),
                NxStat('Voided', fmtNum(rs.where((p) => p.isVoided).length), color: rs.any((p) => p.isVoided) ? n.bad : null),
              ];
            },
            quick: NxQuick(get: (p) => p.isVoided ? 'void' : 'ok', options: const [('', 'All'), ('ok', 'Recorded'), ('void', 'Voided')]),
            filters: [
              NxMultiFilter('method', 'Method', options: [for (final m in PaymentMethod.values) (m.apiValue, m.label)], get: (p) => p.method.apiValue),
              NxSelectFilter('cust', 'Customer', searchable: true, options: customers, get: (p) => p.customerId),
              NxSelectFilter('by', 'Recorded by', options: recorders, get: (p) => p.recordedByName),
              NxDateFilter('date', 'Paid on', get: (p) => p.paidAt.toLocal()),
              NxRangeFilter('amount', 'Amount', get: (p) => p.amount),
            ],
            defaultSort: ('when', -1),
            columns: [
              NxColumn(key: 'when', label: 'Paid', sort: (p) => p.paidAt, cell: (p) => NxCellText(fmtDate(p.paidAt.toLocal()), sub: fmtTime(p.paidAt.toLocal()))),
              NxColumn(key: 'order', label: 'Order', sort: (p) => p.orderNumber ?? '', cell: (p) => NxCellText(p.orderNumber ?? '—', mono: true, sub: p.customerName)),
              NxColumn(
                key: 'method',
                label: 'Method',
                hide: NxHide.md,
                sort: (p) => p.method.index,
                cell: (p) => NxCellText(p.method.label, sub: p.reference == null ? null : 'Ref ${p.reference}'),
              ),
              NxColumn(
                key: 'amount',
                label: 'Amount',
                align: TextAlign.right,
                sort: (p) => p.amount,
                cell: (p) => Text(
                  fmtMoney(p.amount),
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: p.isVoided ? n.n500 : n.ok,
                    decoration: p.isVoided ? TextDecoration.lineThrough : null,
                    fontFeatures: tabular,
                  ),
                ),
              ),
              NxColumn(key: 'by', label: 'Recorded by', hide: NxHide.wide, cell: (p) => NxCellText(p.recordedByName, color: n.n300)),
              NxColumn(
                key: 'state',
                label: 'Status',
                cell: (p) => Align(alignment: Alignment.centerLeft, child: state(p)),
              ),
              if (canVoid) NxColumn(key: 'act', label: '', width: 52, cell: (p) => NxRowActions(acts(p))),
            ],
            listRow: (p) => NxListRowSpec(
              icon: _methodIcon(p.method),
              iconColor: p.isVoided ? n.n500 : n.ok,
              title: '${p.orderNumber ?? '—'} · ${p.customerName ?? '—'}',
              sub: [p.method.label, if (p.reference != null) 'Ref ${p.reference}', p.recordedByName, if (p.isVoided) 'voided: ${p.voidReason ?? ''}'].join(' · '),
              right: fmtMoney(p.amount),
              rightSub: fmtDate(p.paidAt.toLocal()),
              rightColor: p.isVoided ? n.n500 : n.ok,
              tag: p.isVoided ? state(p) : null,
              actions: acts(p),
            ),
            card: (p) => NxCardSpec(
              icon: _methodIcon(p.method),
              iconColor: p.isVoided ? n.n500 : n.ok,
              title: fmtMoney(p.amount),
              sub: '${p.orderNumber ?? '—'} · ${p.customerName ?? '—'}',
              metrics: [('Method', p.method.label, null), ('Paid', fmtDate(p.paidAt.toLocal()), null)],
              tag: state(p),
              actions: acts(p),
            ),
            onOpen: (p) {
              if (p.orderId != null) context.go(RoutePaths.orderDetail(p.orderId!));
            },
            emptyTitle: 'No payments match',
            emptyMessage: 'Payments are recorded from an order.',
          );
        },
      ),
    );
  }
}
