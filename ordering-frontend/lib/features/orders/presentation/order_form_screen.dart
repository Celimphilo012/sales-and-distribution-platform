import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../app_shell/responsive_app_shell.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/error/app_error.dart';
import '../../../core/theme/nocturne.dart';
import '../../../routing/route_paths.dart';
import '../../../shared/nx/nx_form.dart';
import '../../../shared/nx/nx_format.dart';
import '../../../shared/nx/nx_list_page.dart';
import '../../../shared/nx/nx_overlays.dart';
import '../../../shared/nx/nx_primitives.dart';
import '../../../shared/scan/scan_code.dart';
import '../../../shared/scan/scan_dialog.dart';
import '../../catalogue/data/catalogue_providers.dart';
import '../../catalogue/domain/warehouse_product.dart';
import '../../customers/data/customers_providers.dart';
import '../../customers/domain/customer.dart';
import '../../customers/presentation/customer_form_dialog.dart';
import '../data/orders_providers.dart';
import '../domain/order.dart';
import '../domain/order_item_input.dart';
import '../domain/order_lifecycle.dart';

/// A line while the order is being built — local working state. The unit
/// price is an ESTIMATE from the catalogue for the running total; the real
/// price is what the server snapshots on save (rule 8).
class _DraftLine {
  _DraftLine({required this.productId, required this.name, required this.sku, required this.uom, required this.price, required this.quantity});

  final String productId;
  final String name;
  final String sku;
  final String uom;
  final double price;
  double quantity;

  double get total => price * quantity;
}

/// New order (optionally for `?customer=<id>`) or edit a DRAFT ([orderId]).
/// Editing needs `orders.edit_own_draft`, a DRAFT, and being its consultant —
/// checked here before a form is ever shown (the backend enforces it too).
class OrderFormScreen extends ConsumerWidget {
  const OrderFormScreen({super.key, this.orderId, this.initialCustomerId});

  final String? orderId;
  final String? initialCustomerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider.select((s) => s.value?.user));
    if (orderId == null) {
      if (!(user?.can('orders.create') ?? false)) {
        return const NxPageScroll(child: NxError(message: "You don't have permission to create orders (orders.create)."));
      }
      return _Form(initialOrder: null, initialCustomerId: initialCustomerId);
    }
    final async = ref.watch(orderDetailProvider(orderId!));
    return async.when(
      loading: () => const NxPageScroll(child: NxLoading(message: 'Loading order…')),
      error: (e, _) => NxPageScroll(
        child: NxError(message: e is AppError ? e.message : 'Could not load this order.', onRetry: () => ref.invalidate(orderDetailProvider(orderId!))),
      ),
      data: (order) {
        final isDraft = order.status == OrderStatus.draft;
        final isOwner = user != null && order.consultantId == user.id;
        final canEdit = user?.can('orders.edit_own_draft') ?? false;
        if (!canEdit || !isOwner || !isDraft) {
          final reason = !isDraft
              ? 'This order is no longer a draft (it is now "${order.status.label}") and can no longer be edited.'
              : !isOwner
              ? 'This draft belongs to a different consultant — only its owner can edit it.'
              : "You don't have permission to edit draft orders (orders.edit_own_draft).";
          return NxPageScroll(child: NxError(message: reason, onRetry: () => context.go(RoutePaths.orderDetail(order.id))));
        }
        return _Form(initialOrder: order);
      },
    );
  }
}

class _Form extends ConsumerStatefulWidget {
  const _Form({required this.initialOrder, this.initialCustomerId});

  final Order? initialOrder;
  final String? initialCustomerId;

  @override
  ConsumerState<_Form> createState() => _FormState();
}

class _FormState extends ConsumerState<_Form> {
  late final _delivery = TextEditingController(text: widget.initialOrder?.deliveryInfo ?? '');
  late String? _customerId = widget.initialOrder?.customerId ?? widget.initialCustomerId;
  late final List<_DraftLine> _lines = [
    for (final i in widget.initialOrder?.items ?? const <OrderItem>[])
      _DraftLine(productId: i.productId, name: i.productName ?? '(unknown product)', sku: '', uom: '', price: i.unitPrice, quantity: i.quantityOrdered),
  ];
  final Map<String, TextEditingController> _qty = {};
  bool _saving = false;
  String? _error;

  bool get _editing => widget.initialOrder != null;

  @override
  void dispose() {
    _delivery.dispose();
    for (final c in _qty.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _qtyFor(_DraftLine l) => _qty.putIfAbsent(l.productId, () => TextEditingController(text: fmtPlain(l.quantity)));

  void _add(WarehouseProduct p) => setState(() {
    final i = _lines.indexWhere((l) => l.productId == p.id);
    if (i >= 0) {
      _lines[i].quantity += 1;
      _qty[p.id]?.text = fmtPlain(_lines[i].quantity);
    } else {
      _lines.add(_DraftLine(productId: p.id, name: p.name, sku: p.sku, uom: p.uom, price: p.sellingPrice, quantity: 1));
    }
    _error = null;
  });

  /// Scan products into the order: each scan of a product's QR label (or
  /// its SKU barcode) adds one unit — scanning again adds another.
  Future<void> _scanLines(List<WarehouseProduct> products) => showScanDialog(
    context,
    title: 'Scan products',
    sub: 'Each scan adds one to the order. Change quantities on the lines afterwards.',
    onScan: (code) {
      final p = code.match(ScanKind.product, products, id: (x) => x.id, code: (x) => x.sku);
      if (p == null) {
        return ScanFeedback(
          code.kind == ScanKind.location ? 'That is a warehouse location label, not a product.' : 'No active catalogue product has the code “${code.value}”.',
          ok: false,
        );
      }
      _add(p);
      final qty = _lines.firstWhere((l) => l.productId == p.id).quantity;
      return ScanFeedback('${p.sku} · ${p.name} — ${fmtPlain(qty)} on the order');
    },
  );

  void _remove(_DraftLine l) => setState(() {
    _lines.remove(l);
    _qty.remove(l.productId)?.dispose();
  });

  Future<void> _newCustomer() async {
    final c = await showCustomerFormDialog(context);
    if (c != null) setState(() => _customerId = c.id);
  }

  Future<void> _save({required bool submit}) async {
    final problem = !_editing && _customerId == null
        ? 'Choose a customer.'
        : _lines.isEmpty
        ? 'Add at least one product.'
        : _lines.where((l) => l.quantity <= 0).map((l) => 'Quantity for ${l.name} must be greater than 0.').firstOrNull;
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final api = ref.read(ordersApiProvider);
    final delivery = _delivery.text.trim();
    final items = [for (final l in _lines) OrderItemInput(productId: l.productId, quantity: l.quantity)];
    try {
      var saved = _editing
          ? await api.update(widget.initialOrder!.id, deliveryInfo: delivery.isEmpty ? null : delivery, items: items)
          : await api.create(customerId: _customerId!, deliveryInfo: delivery.isEmpty ? null : delivery, items: items);
      if (submit) saved = await api.transition(saved.id, OrderAction.submit);
      invalidateOrder(ref, saved.id);
      if (!mounted) return;
      NxToast.ok(submit ? 'Order submitted for approval' : (_editing ? 'Draft saved' : 'Draft order created'), '${saved.orderNumber} · ${fmtMoney(saved.total)}');
      context.go(RoutePaths.orderDetail(saved.id));
    } on AppError catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    final canSubmit = ref.watch(authProvider.select((s) => s.value?.user?.can('orders.submit') ?? false));
    final customers = ref.watch(customersListProvider).value ?? const <Customer>[];
    final catalogue = ref.watch(catalogueSearchResultsProvider(''));
    final products = (catalogue.value ?? const <WarehouseProduct>[]).where((p) => p.isActive).toList()..sort((a, b) => a.name.compareTo(b.name));
    final total = _lines.fold<double>(0, (s, l) => s + l.total);
    final units = _lines.fold<double>(0, (s, l) => s + l.quantity);
    final wide = MediaQuery.of(context).size.width >= 1024;

    final order = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NxSection(
          padding: const EdgeInsets.all(14),
          child: NxFormGrid(
            children: [
              NxSpan2(
                child: NxField(
                  label: 'Customer',
                  required: true,
                  hint: _editing ? 'A saved order keeps its customer' : null,
                  child: _editing
                      ? Text(widget.initialOrder!.customer.name, style: TextStyle(fontSize: 14, color: n.text))
                      : Row(
                          children: [
                            Expanded(
                              child: NxSelect<String>(
                                searchable: true,
                                searchPlaceholder: 'Search by name or phone',
                                placeholder: 'Choose a customer',
                                options: [
                                  for (final c in customers) NxOption(c.id, c.name, sub: c.phone, search: c.locationText),
                                ],
                                value: _customerId,
                                onChanged: (v) => setState(() {
                                  _customerId = v;
                                  _error = null;
                                }),
                              ),
                            ),
                            const SizedBox(width: 8),
                            NxButton(label: 'New', icon: PhosphorIconsRegular.userPlus, onPressed: _newCustomer),
                          ],
                        ),
                ),
              ),
              NxSpan2(
                child: NxField(
                  label: 'Delivery info',
                  child: NxInput(controller: _delivery, maxLines: 3, minLines: 2, placeholder: 'Address / delivery instructions'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        NxSection(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Lines', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: n.text)),
              const SizedBox(height: 8),
              ScanPicker(
                tooltip: 'Scan products into the order',
                onScan: products.isEmpty ? null : () => _scanLines(products),
                child: NxSelect<String>(
                  searchable: true,
                  searchPlaceholder: 'Search the catalogue by SKU or name',
                  placeholder: catalogue.isLoading ? 'Loading the catalogue…' : (catalogue.hasError ? 'The catalogue is unavailable right now' : 'Add a product…'),
                  enabled: products.isNotEmpty,
                  options: [
                    for (final p in products)
                      NxOption(
                        p.id,
                        '${p.sku} — ${p.name}',
                        sub: [p.category?.name, p.category?.workstream?.name].whereType<String>().join(' · '),
                        trailing: '${fmtMoney(p.sellingPrice)} / ${p.uom}',
                      ),
                  ],
                  value: null,
                  onChanged: (id) {
                    final p = products.where((x) => x.id == id).firstOrNull;
                    if (p != null) _add(p);
                  },
                ),
              ),
              const SizedBox(height: 10),
              if (_lines.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text('No lines yet — add a product above.', style: TextStyle(fontSize: 12, color: n.n400)),
                )
              else
                for (final l in _lines)
                  Container(
                    key: ValueKey(l.productId),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(border: Border(top: BorderSide(color: n.n900))),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(l.name, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: n.text)),
                              Text(
                                '${l.sku.isEmpty ? '' : '${l.sku} · '}${fmtMoney(l.price)}${l.uom.isEmpty ? '' : ' / ${l.uom}'} (estimate)',
                                style: TextStyle(fontSize: 11, color: n.n500),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 90,
                          child: NxInput(
                            controller: _qtyFor(l),
                            dense: true,
                            textAlign: TextAlign.right,
                            inputFormatters: NxInput.decimals(),
                            onChanged: (v) => setState(() => l.quantity = double.tryParse(v) ?? 0),
                          ),
                        ),
                        SizedBox(
                          width: 110,
                          child: Text(fmtMoney(l.total), textAlign: TextAlign.right, style: TextStyle(fontSize: 13, color: n.text, fontFeatures: tabular)),
                        ),
                        const SizedBox(width: 4),
                        NxIconButton(icon: PhosphorIconsRegular.trash, tooltip: 'Remove', size: 30, iconSize: 15, color: n.n400, onPressed: () => _remove(l)),
                      ],
                    ),
                  ),
            ],
          ),
        ),
      ],
    );

    final summary = NxSection(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NxKicker('Summary', color: n.a300),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: Text('Lines', style: TextStyle(fontSize: 12, color: n.n400))),
              Text(fmtNum(_lines.length), style: TextStyle(fontSize: 13, color: n.text)),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(child: Text('Units', style: TextStyle(fontSize: 12, color: n.n400))),
              Text(fmtNum(units), style: TextStyle(fontSize: 13, color: n.text)),
            ],
          ),
          const SizedBox(height: 10),
          Text('Estimated total', style: TextStyle(fontSize: 11, color: n.n500)),
          Text(fmtMoney(total), style: TextStyle(fontSize: 24, fontWeight: FontWeight.w500, color: n.text, fontFeatures: tabular)),
          const SizedBox(height: 4),
          Text('The server sets the exact prices when you save.', style: TextStyle(fontSize: 11, color: n.n500)),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: TextStyle(fontSize: 12, color: n.bad)),
          ],
          const SizedBox(height: 14),
          if (canSubmit) ...[
            NxButton.primary(
              label: _saving ? 'Saving…' : 'Save & submit for approval',
              icon: PhosphorIconsRegular.paperPlaneTilt,
              expand: true,
              onPressed: _saving ? null : () => _save(submit: true),
            ),
            const SizedBox(height: 8),
          ],
          NxButton(
            label: _editing ? 'Save draft' : 'Save as draft',
            icon: PhosphorIconsRegular.floppyDisk,
            expand: true,
            onPressed: _saving ? null : () => _save(submit: false),
          ),
        ],
      ),
    );

    return NxPageScroll(
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              NxPageHeader(
                title: _editing ? 'Edit ${widget.initialOrder!.orderNumber}' : 'New order',
                sub: 'Choose the customer, add products, then save as a draft or submit it for approval.',
                actions: [
                  NxButton.ghost(
                    label: 'Cancel',
                    color: n.n400,
                    onPressed: () => context.go(_editing ? RoutePaths.orderDetail(widget.initialOrder!.id) : RoutePaths.orders),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (wide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 2, child: order),
                    const SizedBox(width: 12),
                    Expanded(child: summary),
                  ],
                )
              else ...[order, const SizedBox(height: 12), summary],
            ],
          ),
        ),
      ),
    );
  }
}
