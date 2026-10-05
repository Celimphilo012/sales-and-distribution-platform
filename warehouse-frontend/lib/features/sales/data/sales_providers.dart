import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/providers.dart';
import '../domain/sale_campaign.dart';
import 'sales_api.dart';

final salesApiProvider = Provider<SalesApi>((ref) => SalesApi(ref.watch(apiClientProvider)));

/// Every campaign the viewer can see, regardless of status — the Sales screen filters client-side
/// (same pattern as stockAdjustmentsListProvider(null)).
final salesListProvider = FutureProvider.autoDispose<List<SaleCampaign>>((ref) {
  return ref.watch(salesApiProvider).list();
});

final saleCampaignProvider = FutureProvider.autoDispose.family<SaleCampaign, String>((ref, id) {
  return ref.watch(salesApiProvider).getById(id);
});
