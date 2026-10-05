import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/providers.dart';
import '../domain/sale_campaign_summary.dart';
import 'sales_api.dart';

final salesApiProvider = Provider<SalesApi>((ref) => SalesApi(ref.watch(apiClientProvider)));

final saleCampaignsListProvider = FutureProvider.autoDispose<List<SaleCampaignSummary>>((ref) {
  return ref.watch(salesApiProvider).list();
});

final eligibleConsultantsProvider = FutureProvider.autoDispose.family<List<EligibleConsultant>, String>((ref, campaignId) {
  return ref.watch(salesApiProvider).listEligible(campaignId);
});
