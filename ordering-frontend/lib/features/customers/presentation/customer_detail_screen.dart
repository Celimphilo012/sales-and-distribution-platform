import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/error/app_error.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../routing/route_paths.dart';
import '../../../shared/date_format.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_dialog.dart';
import '../../../shared/widgets/empty_loading_error_states.dart';
import '../../../shared/widgets/status_badge.dart';
import '../../orders/data/orders_providers.dart';
import '../../orders/domain/order.dart';
import '../../orders/presentation/order_status_tone.dart';
import '../data/customers_providers.dart';
import '../domain/customer.dart';
import 'customer_form_dialog.dart';

/// Read-only customer detail: every §E field, a status badge, edit
/// (permission-gated), and soft-delete/reactivate via [ConfirmDialog] (the
/// R1 `rootNavigator: true` fix — confirming here does not crash under
/// go_router's ShellRoute). Order history is a placeholder — the backend's
/// `findOne`/`findAll` don't include the `orders` relation yet; that's R3.
class CustomerDetailScreen extends ConsumerWidget {
  const CustomerDetailScreen({super.key, required this.customerId});

  final String customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canView = ref.watch(authProvider.select((s) => s.value?.user?.can('customers.view') ?? false));
    if (!canView) {
      return const EmptyStateView(
        title: "You don't have permission to view customers",
        icon: Icons.lock_outline,
      );
    }

    final theme = Theme.of(context);
    final customerAsync = ref.watch(customerDetailProvider(customerId));

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => context.go(RoutePaths.customers),
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Back to Customers',
              ),
              Text('Customer', style: theme.textTheme.headlineSmall),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: customerAsync.when(
              loading: () => const LoadingStateView(message: 'Loading customer…'),
              error: (error, stackTrace) => ErrorStateView(
                message: error is AppError ? error.message : 'Could not load this customer.',
                onRetry: () => ref.invalidate(customerDetailProvider(customerId)),
              ),
              data: (customer) => _CustomerDetailBody(customer: customer),
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomerDetailBody extends ConsumerStatefulWidget {
  const _CustomerDetailBody({required this.customer});

  final Customer customer;

  @override
  ConsumerState<_CustomerDetailBody> createState() => _CustomerDetailBodyState();
}

class _CustomerDetailBodyState extends ConsumerState<_CustomerDetailBody> {
  bool _working = false;

  Future<void> _deactivate() async {
    final confirmed = await ConfirmDialog.show(
      context,
      title: 'Deactivate ${widget.customer.name}?',
      message: 'This soft-deletes the customer — their record and any historical orders stay intact, '
          'but they will no longer be selectable for new orders.',
      confirmLabel: 'Deactivate',
      isDestructive: true,
    );
    if (!confirmed) return;
    setState(() => _working = true);
    try {
      await ref.read(customersApiProvider).deactivate(widget.customer.id);
      invalidateCustomer(ref, widget.customer.id);
    } on AppError catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _reactivate() async {
    setState(() => _working = true);
    try {
      await ref.read(customersApiProvider).reactivate(widget.customer.id);
      invalidateCustomer(ref, widget.customer.id);
    } on AppError catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final customer = widget.customer;
    final canManage = ref.watch(authProvider.select((s) => s.value?.user?.can('customers.create') ?? false));

    return ListView(
      children: [
        AppCard(
          title: customer.name,
          subtitle: 'Added ${formatDateTime(customer.createdAt)} · updated ${formatDateTime(customer.updatedAt)}',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              StatusBadge(
                label: customer.status.label,
                tone: customer.status == CustomerStatus.active ? StatusTone.success : StatusTone.neutral,
              ),
              if (canManage) ...[
                const SizedBox(width: AppSpacing.sm),
                IconButton(
                  tooltip: 'Edit',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => showCustomerFormDialog(context, customer: customer),
                ),
                if (customer.status == CustomerStatus.active)
                  IconButton(
                    tooltip: 'Deactivate',
                    icon: _working
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.block),
                    onPressed: _working ? null : _deactivate,
                  )
                else
                  IconButton(
                    tooltip: 'Reactivate',
                    icon: _working
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.check_circle_outline),
                    onPressed: _working ? null : _reactivate,
                  ),
              ],
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DetailRow(label: 'Phone', value: customer.phone),
              _DetailRow(label: 'Address', value: customer.address),
              _DetailRow(label: 'Location', value: customer.locationText),
              _DetailRow(label: 'Notes', value: customer.notes),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _CustomerOrdersSection(customerId: customer.id),
      ],
    );
  }
}

/// STEP R3a: wires up what was a placeholder in R2 — `GET /orders?
/// customerId=` (`ListOrdersQueryDto.customerId`) now shows this customer's
/// real order history. Row tap opens the order (no lifecycle actions here
/// either — R3b).
class _CustomerOrdersSection extends ConsumerWidget {
  const _CustomerOrdersSection({required this.customerId});

  final String customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final canViewOrders = ref.watch(
      authProvider.select((s) => s.value?.user?.canAny(['orders.view_own', 'orders.view_team']) ?? false),
    );

    if (!canViewOrders) {
      return AppCard(
        title: 'Orders',
        child: Text(
          "You don't have permission to view orders.",
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      );
    }

    final ordersAsync = ref.watch(customerOrdersProvider(customerId));

    return AppCard(
      title: 'Orders',
      child: ordersAsync.when(
        loading: () => const LoadingStateView(message: 'Loading orders…'),
        error: (error, stackTrace) => Text(
          error is AppError ? error.message : 'Could not load orders.',
          style: TextStyle(color: theme.colorScheme.error),
        ),
        data: (orders) {
          if (orders.isEmpty) {
            return Text(
              'No orders yet for this customer.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            );
          }
          return Column(
            children: [
              for (final order in orders) ...[
                InkWell(
                  onTap: () => context.go(RoutePaths.orderDetail(order.id)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(order.orderNumber, style: theme.textTheme.bodyMedium),
                              Text(
                                formatDateTime(order.orderDate),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(order.total.toStringAsFixed(2), style: theme.textTheme.bodyMedium),
                        const SizedBox(width: AppSpacing.md),
                        StatusBadge(label: order.status.label, tone: orderStatusTone(order.status)),
                      ],
                    ),
                  ),
                ),
                const Divider(),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          Expanded(child: Text((value?.isEmpty ?? true) ? '—' : value!, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
