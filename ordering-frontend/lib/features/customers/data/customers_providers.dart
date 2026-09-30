import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/providers.dart';
import '../domain/customer.dart';
import '../domain/customers_filter.dart';
import 'customers_api.dart';

final customersApiProvider = Provider<CustomersApi>((ref) => CustomersApi(ref.watch(apiClientProvider)));

/// Search/status filter state — a plain (non-autoDispose) `Notifier` so it
/// survives navigating to a customer and back, matching the pre-R1
/// `ProductsFilter` pattern this app used for the catalogue.
class CustomersFilterNotifier extends Notifier<CustomersFilter> {
  @override
  CustomersFilter build() => const CustomersFilter();

  void setSearch(String? search) => state = state.copyWith(search: search, clearSearch: search == null);

  void setStatusFilter(CustomerStatusFilter filter) => state = state.copyWith(statusFilter: filter);
}

final customersFilterProvider = NotifierProvider<CustomersFilterNotifier, CustomersFilter>(
  CustomersFilterNotifier.new,
);

final customersListProvider = FutureProvider.autoDispose<List<Customer>>((ref) {
  final filter = ref.watch(customersFilterProvider);
  return ref.watch(customersApiProvider).list(filter);
});

/// Every customer, active and inactive — the Customers list filters it client-side.
final allCustomersProvider = FutureProvider.autoDispose<List<Customer>>((ref) {
  return ref.watch(customersApiProvider).list(const CustomersFilter(statusFilter: CustomerStatusFilter.all));
});

final customerDetailProvider = FutureProvider.autoDispose.family<Customer, String>((ref, id) {
  return ref.watch(customersApiProvider).getOne(id);
});

void invalidateCustomers(WidgetRef ref) {
  ref.invalidate(customersListProvider);
  ref.invalidate(allCustomersProvider);
}

void invalidateCustomer(WidgetRef ref, String id) {
  ref.invalidate(customerDetailProvider(id));
  invalidateCustomers(ref);
}
