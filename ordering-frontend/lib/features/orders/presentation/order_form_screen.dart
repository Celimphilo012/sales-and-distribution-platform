import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/error/app_error.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../routing/route_paths.dart';
import '../../../shared/quantity_format.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_number_field.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/empty_loading_error_states.dart';
import '../../catalogue/presentation/widgets/product_picker_dialog.dart';
import '../../customers/domain/customer.dart';
import '../data/orders_providers.dart';
import '../domain/order.dart';
import '../domain/order_item_input.dart';
import 'widgets/customer_picker_dialog.dart';

/// One line while the form is being built — a local, editable draft. Not
/// the same as [OrderItem]: this is client-side working state, never
/// treated as authoritative. `estimatedUnitPrice` is exactly that — an
/// ESTIMATE for the running total shown while composing the order; the real
/// price is whatever the server snapshots at save time (rule 8), which is
/// why saving always lands on the read-only detail screen showing the
/// server's own numbers, never this draft's.
class _DraftLine {
  _DraftLine({required this.productId, required this.productName, required this.estimatedUnitPrice, required this.quantity});

  final String productId;
  final String productName;
  final double estimatedUnitPrice;
  double quantity;

  double get estimatedLineTotal => estimatedUnitPrice * quantity;
}

/// Create (no [orderId]) or edit a DRAFT (pass [orderId]) — one routed
/// screen for both, same split as the warehouse app's ProductFormScreen.
/// Editing is gated on THREE things per the real backend
/// (`OrdersService.update`): `orders.edit_own_draft`, the order still being
/// DRAFT, and the caller being the order's own `consultantId` — a 409/403
/// otherwise, so this screen checks all three before ever showing an
/// editable form.
class OrderFormScreen extends ConsumerWidget {
  const OrderFormScreen({super.key, this.orderId});

  final String? orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider.select((s) => s.value?.user));
    final canCreate = user?.can('orders.create') ?? false;

    if (orderId == null) {
      if (!canCreate) {
        return const EmptyStateView(
          title: "You don't have permission to create orders",
          message: 'Ask an administrator for the orders.create permission.',
          icon: Icons.lock_outline,
        );
      }
      return const _OrderFormBody(initialOrder: null);
    }

    final orderAsync = ref.watch(orderDetailProvider(orderId!));
    return orderAsync.when(
      loading: () => const LoadingStateView(message: 'Loading order…'),
      error: (error, stackTrace) => ErrorStateView(
        message: error is AppError ? error.message : 'Could not load this order.',
        onRetry: () => ref.invalidate(orderDetailProvider(orderId!)),
      ),
      data: (order) {
        final canEdit = user?.can('orders.edit_own_draft') ?? false;
        final isOwner = user != null && order.consultantId == user.id;
        final isDraft = order.status == OrderStatus.draft;

        if (!canEdit || !isOwner || !isDraft) {
          final reason = !isDraft
              ? 'This order is no longer a draft (it is now "${order.status.label}") and can no longer be edited.'
              : !isOwner
              ? "This draft belongs to a different consultant — only its owner can edit it."
              : "You don't have permission to edit draft orders (orders.edit_own_draft).";
          return EmptyStateView(
            title: "Can't edit this order",
            message: reason,
            icon: Icons.lock_outline,
            action: OutlinedButton.icon(
              onPressed: () => context.go(RoutePaths.orderDetail(order.id)),
              icon: const Icon(Icons.visibility_outlined),
              label: const Text('View order'),
            ),
          );
        }
        return _OrderFormBody(initialOrder: order);
      },
    );
  }
}

class _OrderFormBody extends ConsumerStatefulWidget {
  const _OrderFormBody({required this.initialOrder});

  final Order? initialOrder;

  @override
  ConsumerState<_OrderFormBody> createState() => _OrderFormBodyState();
}

class _OrderFormBodyState extends ConsumerState<_OrderFormBody> {
  late final TextEditingController _deliveryInfoController;
  Customer? _customer;
  String? _lockedCustomerName;
  late List<_DraftLine> _lines;
  bool _saving = false;
  String? _error;

  // Keyed by productId, NOT recreated on every rebuild (matches the
  // warehouse app's stock-count-entry pattern) — a fresh controller per
  // build would reset cursor position/typed-but-not-yet-parsed text on
  // every keystroke, since typing a quantity triggers a parent setState.
  final Map<String, TextEditingController> _quantityControllers = {};

  bool get _isEditing => widget.initialOrder != null;

  @override
  void initState() {
    super.initState();
    final order = widget.initialOrder;
    _deliveryInfoController = TextEditingController(text: order?.deliveryInfo ?? '');
    _lockedCustomerName = order?.customer.name;
    _lines = [
      for (final item in order?.items ?? const <OrderItem>[])
        _DraftLine(
          productId: item.productId,
          productName: item.productName ?? '(unknown product)',
          estimatedUnitPrice: item.unitPrice,
          quantity: item.quantityOrdered,
        ),
    ];
  }

  @override
  void dispose() {
    _deliveryInfoController.dispose();
    for (final controller in _quantityControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  TextEditingController _quantityControllerFor(_DraftLine line) {
    return _quantityControllers.putIfAbsent(
      line.productId,
      () => TextEditingController(text: formatQuantity(line.quantity)),
    );
  }

  double get _estimatedTotal => _lines.fold(0, (sum, l) => sum + l.estimatedLineTotal);

  Future<void> _pickCustomer() async {
    final picked = await showCustomerPickerDialog(context);
    if (picked != null) setState(() => _customer = picked);
  }

  Future<void> _addProduct() async {
    final product = await showProductPickerDialog(context);
    if (product == null) return;
    setState(() {
      final existing = _lines.indexWhere((l) => l.productId == product.id);
      if (existing != -1) {
        _lines[existing].quantity += 1;
        _quantityControllers[product.id]?.text = formatQuantity(_lines[existing].quantity);
      } else {
        _lines.add(
          _DraftLine(productId: product.id, productName: product.name, estimatedUnitPrice: product.sellingPrice, quantity: 1),
        );
      }
    });
  }

  void _removeLine(_DraftLine line) => setState(() {
    _lines.remove(line);
    _quantityControllers.remove(line.productId)?.dispose();
  });

  Future<void> _save() async {
    if (!_isEditing && _customer == null) {
      setState(() => _error = 'Choose a customer.');
      return;
    }
    if (_lines.isEmpty) {
      setState(() => _error = 'Add at least one product.');
      return;
    }
    for (final line in _lines) {
      if (line.quantity <= 0) {
        setState(() => _error = 'Quantity for ${line.productName} must be greater than 0.');
        return;
      }
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final deliveryInfo = _deliveryInfoController.text.trim();
    final items = [for (final line in _lines) OrderItemInput(productId: line.productId, quantity: line.quantity)];
    try {
      final Order saved;
      if (_isEditing) {
        saved = await ref
            .read(ordersApiProvider)
            .update(widget.initialOrder!.id, deliveryInfo: deliveryInfo.isEmpty ? null : deliveryInfo, items: items);
        invalidateOrder(ref, saved.id);
      } else {
        saved = await ref
            .read(ordersApiProvider)
            .create(customerId: _customer!.id, deliveryInfo: deliveryInfo.isEmpty ? null : deliveryInfo, items: items);
        invalidateOrders(ref);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_isEditing ? 'Draft saved' : 'Draft order created')));
      context.go(RoutePaths.orderDetail(saved.id));
    } on AppError catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back),
              tooltip: 'Back',
              onPressed: () => context.go(
                _isEditing ? RoutePaths.orderDetail(widget.initialOrder!.id) : RoutePaths.orders,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(_isEditing ? 'Edit draft order' : 'New order', style: theme.textTheme.headlineSmall),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: AppCard(
            title: 'Customer',
            child: _isEditing
                ? Text(_lockedCustomerName ?? '—', style: theme.textTheme.bodyLarge)
                : Row(
                    children: [
                      Expanded(
                        child: Text(
                          _customer?.name ?? 'No customer chosen',
                          style: _customer == null
                              ? theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)
                              : theme.textTheme.bodyLarge,
                        ),
                      ),
                      TextButton(onPressed: _pickCustomer, child: Text(_customer == null ? 'Choose' : 'Change')),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: AppCard(
            child: AppTextField(
              label: 'Delivery info (optional)',
              controller: _deliveryInfoController,
              maxLines: 2,
              hintText: 'Address / delivery instructions',
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: AppCard(
            title: 'Order lines',
            subtitle: 'Prices shown are an estimate from the catalogue — the server snapshots the exact '
                'price for each line when you save.',
            trailing: TextButton.icon(
              onPressed: _addProduct,
              icon: const Icon(Icons.add),
              label: const Text('Add product'),
            ),
            child: _lines.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                    child: Text(
                      'No lines yet — add a product to get started.',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  )
                : Column(
                    children: [
                      for (final line in _lines) ...[
                        _OrderLineRow(
                          key: ValueKey(line.productId),
                          line: line,
                          controller: _quantityControllerFor(line),
                          onQuantityChanged: (qty) => setState(() => line.quantity = qty),
                          onRemove: () => _removeLine(line),
                        ),
                        const Divider(),
                      ],
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.sm),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(
                              'Estimated total: ',
                              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                            ),
                            Text(formatQuantity(_estimatedTotal), style: theme.textTheme.titleMedium),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: AppSpacing.md),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              ),
              child: Text(_error!, style: TextStyle(color: theme.colorScheme.onErrorContainer)),
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: theme.colorScheme.onPrimary),
                )
              : const Icon(Icons.save_outlined),
          label: Text(_saving ? 'Saving…' : 'Save draft'),
        ),
      ],
    );
  }
}

class _OrderLineRow extends StatelessWidget {
  const _OrderLineRow({super.key, required this.line, required this.controller, required this.onQuantityChanged, required this.onRemove});

  final _DraftLine line;
  final TextEditingController controller;
  final ValueChanged<double> onQuantityChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(line.productName, style: theme.textTheme.bodyMedium),
                Text(
                  '${formatQuantity(line.estimatedUnitPrice)} each (estimated)',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 100,
            child: AppNumberField(
              label: 'Qty',
              controller: controller,
              allowDecimal: true,
              onChanged: (value) {
                final n = double.tryParse(value);
                if (n != null && n > 0) onQuantityChanged(n);
              },
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          SizedBox(
            width: 90,
            child: Text(
              formatQuantity(line.estimatedLineTotal),
              textAlign: TextAlign.end,
              style: theme.textTheme.bodyMedium,
            ),
          ),
          IconButton(iconSize: 18, tooltip: 'Remove', icon: const Icon(Icons.delete_outline), onPressed: onRemove),
        ],
      ),
    );
  }
}
