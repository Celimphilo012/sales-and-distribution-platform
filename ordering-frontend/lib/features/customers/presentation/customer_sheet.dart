import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/error/app_error.dart';
import '../../../core/theme/nocturne.dart';
import '../../../routing/route_paths.dart';
import '../../../shared/nx/nx_actions.dart';
import '../../../shared/nx/nx_format.dart';
import '../../../shared/nx/nx_overlays.dart';
import '../../../shared/nx/nx_primitives.dart';
import '../../orders/data/orders_providers.dart';
import '../../orders/domain/order.dart';
import '../../orders/presentation/order_status_tone.dart';
import '../data/customers_providers.dart';
import '../domain/customer.dart';
import 'customer_form_dialog.dart';

/// One customer: contact facts, what they have bought and still owe, their
/// orders (tap to open), and — for `customers.create` — edit / deactivate;
/// for `orders.create` — a new order already addressed to them.
Future<void> showCustomerSheet(BuildContext context, String customerId) =>
    showNxSheet<void>(context, kicker: 'Customer', builder: (_) => _CustomerSheet(customerId: customerId));

class _CustomerSheet extends ConsumerWidget {
  const _CustomerSheet({required this.customerId});

  final String customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = context.nx;
    final user = ref.watch(authProvider).value?.user;
    final canEdit = user?.can('customers.create') ?? false;
    final canOrder = user?.can('orders.create') ?? false;
    final async = ref.watch(customerDetailProvider(customerId));
    final orders = ref.watch(customerOrdersProvider(customerId));

    return async.when(
      loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
      error: (e, _) => Padding(padding: const EdgeInsets.all(16), child: Text(e is AppError ? e.message : 'Could not load this customer.', style: TextStyle(color: n.bad))),
      data: (c) {
        final active = c.status == CustomerStatus.active;
        final list = [...orders.value ?? const <Order>[]]..sort((a, b) => b.orderDate.compareTo(a.orderDate));
        final live = list.where((o) => orderCounts(o.status));
        final bought = live.fold<double>(0, (s, o) => s + o.total);
        final owed = live.fold<double>(0, (s, o) => s + (o.total - o.amountPaid).clamp(0, double.infinity));
        Widget fact(String l, String? v) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 90, child: Text(l, style: TextStyle(fontSize: 12, color: n.n500))),
              Expanded(child: Text((v == null || v.isEmpty) ? '—' : v, style: TextStyle(fontSize: 13, color: n.text))),
            ],
          ),
        );
        Widget figure(String l, String v, {Color? color}) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l, style: TextStyle(fontSize: 11, color: n.n500)),
              Text(v, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: color ?? n.text, fontFeatures: tabular)),
            ],
          ),
        );

        return NxSheetBody(
          children: [
            Row(
              children: [
                NxAvatar(name: c.name, size: 40, accent: true),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(c.name, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500, color: n.text)),
                      Text('Customer since ${fmtDate(c.createdAt.toLocal())}', style: TextStyle(fontSize: 12, color: n.n400)),
                    ],
                  ),
                ),
                NxTag(c.status.label, tone: active ? Tone.ok : Tone.neutral),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (canOrder && active)
                  NxButton.primary(
                    label: 'New order',
                    icon: PhosphorIconsRegular.plus,
                    small: true,
                    onPressed: () {
                      final router = GoRouter.of(context);
                      Navigator.of(context).pop();
                      router.go('${RoutePaths.orderNew}?customer=${c.id}');
                    },
                  ),
                if (canEdit) NxButton(label: 'Edit', icon: PhosphorIconsRegular.pencilSimple, small: true, onPressed: () => showCustomerFormDialog(context, customer: c)),
                if (canEdit)
                  NxButton(
                    label: active ? 'Deactivate' : 'Reactivate',
                    icon: active ? PhosphorIconsRegular.prohibit : PhosphorIconsRegular.arrowCounterClockwise,
                    small: true,
                    color: active ? n.bad : null,
                    onPressed: () => nxToggleActive(
                      context,
                      name: c.name,
                      active: active,
                      deactivate: () => ref.read(customersApiProvider).deactivate(c.id),
                      reactivate: () => ref.read(customersApiProvider).reactivate(c.id),
                      refresh: () => invalidateCustomer(ref, c.id),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            NxSection(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  figure('Orders', fmtNum(list.length)),
                  figure('Bought', fmtMoney(bought)),
                  figure('Owes', fmtMoney(owed), color: owed > 0 ? n.warn : null),
                ],
              ),
            ),
            const SizedBox(height: 14),
            fact('Phone', c.phone),
            fact('Address', c.address),
            fact('Location', c.locationText),
            fact('Notes', c.notes),
            const SizedBox(height: 10),
            Text('Orders', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: n.text)),
            const SizedBox(height: 6),
            if (orders.isLoading && list.isEmpty)
              Text('Loading…', style: TextStyle(fontSize: 12, color: n.n400))
            else if (list.isEmpty)
              Text('No orders yet.', style: TextStyle(fontSize: 12, color: n.n400))
            else
              NxSection(
                child: Column(
                  children: [
                    for (final o in list)
                      NxHoverRow(
                        onTap: () {
                          final router = GoRouter.of(context);
                          Navigator.of(context).pop();
                          router.go(RoutePaths.orderDetail(o.id));
                        },
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(o.orderNumber, style: TextStyle(fontSize: 13, fontFamily: 'monospace', color: n.text)),
                                  Text('${fmtDate(o.orderDate.toLocal())} · ${o.paymentStatus.label}', style: TextStyle(fontSize: 11, color: n.n500)),
                                ],
                              ),
                            ),
                            Text(fmtMoney(o.total), style: TextStyle(fontSize: 13, color: n.text, fontFeatures: tabular)),
                            const SizedBox(width: 10),
                            NxTag(o.status.label, tone: orderTone(o.status), small: true),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}
