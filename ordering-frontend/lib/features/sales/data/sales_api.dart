import '../../../core/network/api_client.dart';
import '../domain/sale_campaign_summary.dart';

/// `GET /sales` (relay over the warehouse's `GET /api/v1/sales`), `GET/PUT /sales/:id/
/// eligible-consultants` (ordering-backend's own `sale_campaign_eligible_consultants` table) —
/// confirmed against `ordering-backend/src/modules/sales-eligibility.js`.
class SalesApi {
  SalesApi(this._apiClient);

  final ApiClient _apiClient;

  Future<List<SaleCampaignSummary>> list() async {
    final response = await _apiClient.guard((dio) => dio.get<Map<String, dynamic>>('/sales'));
    final campaigns = response.data!['campaigns'] as List<dynamic>;
    return campaigns.map((e) => SaleCampaignSummary.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<EligibleConsultant>> listEligible(String campaignId) async {
    final response = await _apiClient.guard((dio) => dio.get<List<dynamic>>('/sales/$campaignId/eligible-consultants'));
    return response.data!.map((e) => EligibleConsultant.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Replaces the FULL eligible-consultant list for the campaign.
  Future<List<EligibleConsultant>> setEligible(String campaignId, List<String> consultantIds) async {
    final response = await _apiClient.guard(
      (dio) => dio.put<List<dynamic>>('/sales/$campaignId/eligible-consultants', data: {'consultantIds': consultantIds}),
    );
    return response.data!.map((e) => EligibleConsultant.fromJson(e as Map<String, dynamic>)).toList();
  }
}
