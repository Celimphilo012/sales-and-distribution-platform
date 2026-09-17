import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/providers.dart';
import '../domain/api_key.dart';
import 'api_keys_api.dart';

final apiKeysApiProvider = Provider<ApiKeysApi>((ref) => ApiKeysApi(ref.watch(apiClientProvider)));

final apiKeysListProvider = FutureProvider.autoDispose<List<ApiKeyRecord>>((ref) {
  return ref.watch(apiKeysApiProvider).list();
});
