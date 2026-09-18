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
    final theme = Theme.of(context);
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
        AppCard(
          title: 'Orders',
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, color: theme.colorScheme.primary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  "This customer's order history isn't wired up yet — that's step R3. The "
                  'backend already relates orders to customers; this screen will list them once '
                  'the Orders feature exists.',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ),
      ],
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
