import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/providers.dart';
import '../domain/user.dart';
import 'users_api.dart';

final usersApiProvider = Provider<UsersApi>((ref) => UsersApi(ref.watch(apiClientProvider)));

final usersListProvider = FutureProvider.autoDispose<List<WarehouseUser>>((ref) {
  return ref.watch(usersApiProvider).list();
});

/// For pickers (a customer's assigned consultant, sale-campaign eligibility) — a minimal directory,
/// not full user management (`usersListProvider` needs `users.manage`, this needs `customers.view`).
final consultantsListProvider = FutureProvider.autoDispose<List<ConsultantRef>>((ref) {
  return ref.watch(usersApiProvider).consultants();
});
