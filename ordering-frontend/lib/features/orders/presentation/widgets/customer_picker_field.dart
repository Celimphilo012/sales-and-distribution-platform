import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/app_error.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../../../shared/widgets/empty_loading_error_states.dart';
import '../../../customers/data/customers_providers.dart';
import '../../../customers/domain/customer.dart';
import '../../../customers/domain/customers_filter.dart';

/// Debounced customer search, reusing R2's own `CustomersApi` — the same
/// search-by-name-or-phone the Customers screen itself uses. Active
/// customers only (`CustomerStatusFilter.active`'s default `includeInactive:
/// false`) — an inactive customer shouldn't be selectable for a new order.
class CustomerSearchField extends ConsumerStatefulWidget {
  const CustomerSearchField({super.key, required this.onSelected});

  final ValueChanged<Customer> onSelected;

  @override
  ConsumerState<CustomerSearchField> createState() => _CustomerSearchFieldState();
}

class _CustomerSearchFieldState extends ConsumerState<CustomerSearchField> {
  final _controller = TextEditingController();
  Timer? _debounce;
  String _query = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _query = value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final filter = CustomersFilter(search: _query.trim().isEmpty ? null : _query.trim());
    final resultsAsync = ref.watch(_customerSearchProvider(filter));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppTextField(
          label: 'Search for a customer',
          controller: _controller,
          hintText: 'Name or phone',
          prefixIcon: Icons.search,
          onChanged: _onChanged,
        ),
        const SizedBox(height: AppSpacing.md),
        resultsAsync.when(
          loading: () => const LoadingStateView(),
          error: (error, stackTrace) => ErrorStateView(
            message: error is AppError ? error.message : 'Could not search customers.',
            onRetry: () => ref.invalidate(_customerSearchProvider(filter)),
          ),
          data: (results) {
            if (results.isEmpty) {
              return const EmptyStateView(title: 'No matching customers', icon: Icons.search_off);
            }
            return Card(
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: results.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final customer = results[index];
                  return ListTile(
                    title: Text(customer.name),
                    subtitle: Text(customer.phone ?? 'No phone on file'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => widget.onSelected(customer),
                  );
                },
              ),
            );
          },
        ),
      ],
    );
  }
}

final _customerSearchProvider = FutureProvider.autoDispose.family<List<Customer>, CustomersFilter>((ref, filter) {
  return ref.watch(customersApiProvider).list(filter);
});
