import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/providers.dart';
import '../domain/attribute_type.dart';
import 'attribute_types_api.dart';

final attributeTypesApiProvider =
    Provider<AttributeTypesApi>((ref) => AttributeTypesApi(ref.watch(apiClientProvider)));

/// Keyed by `includeInactive` — the product-form attribute section (active
/// only) and the attribute-types management screen (everything, so it can
/// reactivate) get independent caches, same pattern as
/// `categoriesProvider`/`workstreamsProvider`.
final attributeTypesProvider = FutureProvider.autoDispose.family<List<AttributeType>, bool>((
  ref,
  includeInactive,
) {
  return ref.watch(attributeTypesApiProvider).list(includeInactive: includeInactive);
});

void invalidateAttributeTypes(WidgetRef ref) {
  ref.invalidate(attributeTypesProvider(true));
  ref.invalidate(attributeTypesProvider(false));
}
