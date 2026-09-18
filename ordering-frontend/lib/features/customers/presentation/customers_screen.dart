import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/error/app_error.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../routing/route_paths.dart';
import '../../../shared/widgets/app_data_table.dart';
import '../../../shared/widgets/app_dropdown_field.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/empty_loading_error_states.dart';
import '../../../shared/widgets/status_badge.dart';
import '../data/customers_providers.dart';
import '../domain/customer.dart';
import '../domain/customers_filter.dart';
import 'customer_form_dialog.dart';

/// STEP R2 — CUSTOMERS: the first ordering feature screen, the template R3
/// (Orders) and R4 (Reports) copy. Search + status filter, a responsive
/// [AppDataTable], and a permission-gated "New customer" action — same
/// shape as the warehouse app's step 6b Products screen, re-pointed at
/// `/backend`'s real (unpaginated) `GET /customers`.
class CustomersScreen extends ConsumerStatefulWidget {
  const CustomersScreen({super.key});

  @override
  ConsumerState<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends ConsumerState<CustomersScreen> {
  late final TextEditingController _searchController;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    // Filter state (a non-autoDispose Notifier) survives navigating to a
    // customer and back — seed the field from it so the search text doesn't
    // visually reset even though this State object is fresh.
    _searchController = TextEditingController(text: ref.read(customersFilterProvider).search ?? '');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      ref.read(customersFilterProvider.notifier).setSearch(value.trim().isEmpty ? null : value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canCreate = ref.watch(authProvider.select((s) => s.value?.user?.can('customers.create') ?? false));
    final canView = ref.watch(authProvider.select((s) => s.value?.user?.can('customers.view') ?? false));
    final filter = ref.watch(customersFilterProvider);
    final customersAsync = ref.watch(customersListProvider);

    if (!canView) {
      return const EmptyStateView(
        title: "You don't have permission to view customers",
        message: 'Ask an administrator for the customers.view permission.',
        icon: Icons.lock_outline,
      );
    }

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('Customers', style: theme.textTheme.headlineSmall)),
              if (canCreate)
                FilledButton.icon(
                  onPressed: () => showCustomerFormDialog(context),
                  icon: const Icon(Icons.person_add_outlined),
                  label: const Text('New customer'),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.md,
            children: [
              SizedBox(
                width: 280,
                child: AppTextField(
                  label: 'Search',
                  controller: _searchController,
                  hintText: 'Name or phone',
                  prefixIcon: Icons.search,
                  onChanged: _onSearchChanged,
                ),
              ),
              SizedBox(
                width: 180,
                child: AppDropdownField<CustomerStatusFilter>(
                  label: 'Status',
                  value: filter.statusFilter,
                  items: CustomerStatusFilter.values,
                  itemLabel: (f) => f.label,
                  onChanged: (value) {
                    if (value != null) ref.read(customersFilterProvider.notifier).setStatusFilter(value);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Expanded(
            child: customersAsync.when(
              loading: () => const LoadingStateView(message: 'Loading customers…'),
              error: (error, stackTrace) => ErrorStateView(
                message: error is AppError ? error.message : 'Could not load customers.',
                onRetry: () => ref.invalidate(customersListProvider),
              ),
              data: (customers) {
                final visible = filter.statusFilter == CustomerStatusFilter.inactiveOnly
                    ? customers.where((c) => c.status == CustomerStatus.inactive).toList()
                    : customers;

                return AppDataTable<Customer>(
                  rows: visible,
                  emptyTitle: 'No customers found',
                  emptyMessage: 'Try adjusting your search or filters.',
                  onRowTap: (customer) => context.go(RoutePaths.customerDetail(customer.id)),
                  columns: [
                    AppDataColumn(label: 'Name', cellBuilder: (c) => Text(c.name)),
                    AppDataColumn(label: 'Phone', cellBuilder: (c) => Text(c.phone ?? '—')),
                    AppDataColumn(label: 'Location', cellBuilder: (c) => Text(c.locationText ?? c.address ?? '—')),
                    AppDataColumn(
                      label: 'Status',
                      cellBuilder: (c) => StatusBadge(
                        label: c.status.label,
                        tone: c.status == CustomerStatus.active ? StatusTone.success : StatusTone.neutral,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
