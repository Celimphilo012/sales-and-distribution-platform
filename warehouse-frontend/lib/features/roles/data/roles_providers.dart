import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/providers.dart';
import '../domain/permission.dart';
import '../domain/role.dart';
import 'permissions_api.dart';
import 'roles_api.dart';

final rolesApiProvider = Provider<RolesApi>((ref) => RolesApi(ref.watch(apiClientProvider)));
final permissionsApiProvider = Provider<PermissionsApi>((ref) => PermissionsApi(ref.watch(apiClientProvider)));

final rolesListProvider = FutureProvider.autoDispose<List<Role>>((ref) {
  return ref.watch(rolesApiProvider).list();
});

final roleDetailProvider = FutureProvider.autoDispose.family<Role, String>((ref, id) {
  return ref.watch(rolesApiProvider).getOne(id);
});

final permissionsCatalogProvider = FutureProvider.autoDispose<List<Permission>>((ref) {
  return ref.watch(permissionsApiProvider).list();
});

void invalidateRoles(WidgetRef ref) {
  ref.invalidate(rolesListProvider);
}
