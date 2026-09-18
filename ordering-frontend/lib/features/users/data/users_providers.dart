import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/providers.dart';
import '../domain/user.dart';
import 'users_api.dart';

final usersApiProvider = Provider<UsersApi>((ref) => UsersApi(ref.watch(apiClientProvider)));

final usersListProvider = FutureProvider.autoDispose<List<WarehouseUser>>((ref) {
  return ref.watch(usersApiProvider).list();
});
