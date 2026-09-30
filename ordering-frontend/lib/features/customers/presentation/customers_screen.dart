import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../app_shell/responsive_app_shell.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/error/app_error.dart';
import '../../../core/theme/nocturne.dart';
import '../../../routing/route_paths.dart';
import '../../../shared/nx/nx_actions.dart';
import '../../../shared/nx/nx_format.dart';
import '../../../shared/nx/nx_list_page.dart';
import '../../../shared/nx/nx_primitives.dart';
import '../../orders/data/orders_providers.dart';
import '../../orders/domain/order.dart';
import '../../orders/presentation/order_status_tone.dart';
import '../data/customers_providers.dart';
import '../domain/customer.dart';
import 'customer_form_dialog.dart';
import 'customer_sheet.dart';

class _Row {
  _Row(this.c, this.orders);

  final Customer c;
  final List<Order> orders;

  bool get active => c.status == CustomerStatus.active;
  Iterable<Order> get live => orders.where((o) => orderCounts(o.status));
  double get bought => live.fold<double>(0, (s, o) => s + o.total);
  double get owed => live.fold<double>(0, (s, o) => s + (o.total - o.amountPaid).clamp(0, double.infinity));
  DateTime? get lastOrder => orders.isEmpty ? null : orders.map((o) => o.orderDate).reduce((a, b) => a.isAfter(b) ? a : b);
}

/// Customers — the people the business sells to, with what each has bought
/// and still owes (from the orders the viewer can see). `?open=<id>` opens
/// that customer's sheet.
class CustomersScreen extends ConsumerStatefulWidget {
  const CustomersScreen({super.key, this.openCustomerId});

  final String? openCustomerId;

  @override
  ConsumerState<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends ConsumerState<CustomersScreen> {
  @override
  void initState() {
    super.initState();
    final id = widget.openCustomerId;
    if (id != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        GoRouter.of(context).go(RoutePaths.customers);
        showCustomerSheet(context, id);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    final user = ref.watch(authProvider).value?.user;
    final canEdit = user?.can('customers.create') ?? false;
    final async = ref.watch(allCustomersProvider);
    final orders = user?.canAny(const ['orders.view_team', 'orders.view_own']) ?? false
        ? ref.watch(allOrdersProvider).value ?? const <Order>[]
        : const <Order>[];

    return NxPageScroll(
      onRefresh: () async => invalidateCustomers(ref),
      child: async.when(
        loading: () => const NxLoading(message: 'Loading customers…'),
        error: (e, _) => NxError(message: e is AppError ? e.message : 'Could not load customers.', onRetry: () => invalidateCustomers(ref)),
        data: (customers) {
          final byCustomer = <String, List<Order>>{};
          for (final o in orders) {
            byCustomer.putIfAbsent(o.customerId, () => []).add(o);
          }
          final rows = [for (final c in customers) _Row(c, byCustomer[c.id] ?? const [])];
          NxTag status(_Row r) => NxTag(r.c.status.label, tone: r.active ? Tone.ok : Tone.neutral);
          List<NxRowAction> acts(_Row r) => [
            if (canEdit) NxRowAction(icon: PhosphorIconsRegular.pencilSimple, label: 'Edit', onPressed: () => showCustomerFormDialog(context, customer: r.c)),
            if (canEdit)
              NxRowAction(
                icon: r.active ? PhosphorIconsRegular.prohibit : PhosphorIconsRegular.arrowCounterClockwise,
                label: r.active ? 'Deactivate' : 'Reactivate',
                danger: r.active,
                onPressed: () => nxToggleActive(
                  context,
                  name: r.c.name,
                  active: r.active,
                  deactivate: () => ref.read(customersApiProvider).deactivate(r.c.id),
                  reactivate: () => ref.read(customersApiProvider).reactivate(r.c.id),
                  refresh: () => invalidateCustomer(ref, r.c.id),
                ),
              ),
          ];

          return NxListPage<_Row>(
            stateKey: 'customers',
            title: 'Customers',
            sub: 'Who you sell to — what each has bought and still owes.',
            actions: [
              if (canEdit) NxButton.primary(label: 'New customer', icon: PhosphorIconsRegular.userPlus, onPressed: () => showCustomerFormDialog(context)),
            ],
            rows: rows,
            search: (r) => '${r.c.name} ${r.c.phone ?? ''} ${r.c.locationText ?? ''}',
            searchPlaceholder: 'Name, phone or location',
            stats: (rs) {
              final owed = rs.fold<double>(0, (s, r) => s + r.owed);
              return [
                NxStat('Customers', fmtNum(rs.length), sub: '${rs.where((r) => r.active).length} active'),
                NxStat('With orders', fmtNum(rs.where((r) => r.orders.isNotEmpty).length)),
                NxStat('Sold', fmtMoney(rs.fold<double>(0, (s, r) => s + r.bought))),
                NxStat('Owed to us', fmtMoney(owed), color: owed > 0 ? n.warn : null),
                NxStat('Owing customers', fmtNum(rs.where((r) => r.owed > 0).length)),
              ];
            },
            quick: NxQuick(
              get: (r) => r.active ? 'active' : 'inactive',
              defaultValue: 'active',
              options: const [('active', 'Active'), ('inactive', 'Inactive'), ('', 'All')],
            ),
            filters: [
              NxToggleFilter('owes', 'Money', text: 'Owes money', get: (r) => r.owed > 0),
              NxToggleFilter('phone', 'Contact', text: 'Has a phone number', get: (r) => (r.c.phone ?? '').isNotEmpty),
              NxRangeFilter('orders', 'Orders', get: (r) => r.orders.length),
              NxRangeFilter('owed', 'Amount owed', get: (r) => r.owed),
              NxDateFilter('since', 'Customer since', get: (r) => r.c.createdAt.toLocal()),
            ],
            defaultSort: ('name', 1),
            columns: [
              NxColumn(
                key: 'name',
                label: 'Customer',
                sort: (r) => r.c.name.toLowerCase(),
                cell: (r) => Row(
                  children: [
                    NxAvatar(name: r.c.name),
                    const SizedBox(width: 9),
                    Expanded(child: NxCellText(r.c.name, weight: FontWeight.w500, sub: r.c.phone)),
                  ],
                ),
              ),
              NxColumn(key: 'loc', label: 'Location', hide: NxHide.wide, cell: (r) => NxCellText(r.c.locationText ?? r.c.address ?? '—', color: n.n300)),
              NxColumn(key: 'orders', label: 'Orders', align: TextAlign.right, sort: (r) => r.orders.length, cell: (r) => NxCellText(fmtNum(r.orders.length), align: TextAlign.right)),
              NxColumn(key: 'bought', label: 'Bought', align: TextAlign.right, hide: NxHide.md, sort: (r) => r.bought, cell: (r) => NxCellText(fmtMoney(r.bought), align: TextAlign.right)),
              NxColumn(
                key: 'owed',
                label: 'Owes',
                align: TextAlign.right,
                sort: (r) => r.owed,
                cell: (r) => NxCellText(r.owed > 0 ? fmtMoney(r.owed) : '—', align: TextAlign.right, color: r.owed > 0 ? n.warn : n.n500),
              ),
              NxColumn(
                key: 'last',
                label: 'Last order',
                hide: NxHide.wide,
                sort: (r) => r.lastOrder,
                cell: (r) => NxCellText(r.lastOrder == null ? '—' : fmtDate(r.lastOrder!.toLocal()), color: n.n300),
              ),
              NxColumn(key: 'status', label: 'Status', cell: (r) => Align(alignment: Alignment.centerLeft, child: status(r))),
              if (canEdit) NxColumn(key: 'act', label: '', width: 76, cell: (r) => NxRowActions(acts(r))),
            ],
            listRow: (r) => NxListRowSpec(
              icon: PhosphorIconsDuotone.user,
              leading: NxAvatar(name: r.c.name, size: 32),
              title: r.c.name,
              sub: [r.c.phone, r.c.locationText].whereType<String>().where((s) => s.isNotEmpty).join(' · '),
              right: r.owed > 0 ? fmtMoney(r.owed) : '${r.orders.length} orders',
              rightSub: r.owed > 0 ? 'owed' : null,
              rightColor: r.owed > 0 ? n.warn : null,
              tag: r.active ? null : status(r),
            ),
            card: (r) => NxCardSpec(
              icon: PhosphorIconsDuotone.userCircle,
              leading: NxAvatar(name: r.c.name, size: 34),
              title: r.c.name,
              sub: r.c.phone,
              metrics: [('Orders', fmtNum(r.orders.length), null), ('Owes', fmtMoney(r.owed), r.owed > 0 ? n.warn : null)],
              tag: status(r),
            ),
            onOpen: (r) => showCustomerSheet(context, r.c.id),
            emptyTitle: 'No customers match',
            emptyMessage: canEdit ? 'Adjust filters, or add a customer.' : 'Adjust filters.',
          );
        },
      ),
    );
  }
}
