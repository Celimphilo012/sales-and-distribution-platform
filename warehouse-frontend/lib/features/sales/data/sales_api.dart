import '../../../core/network/api_client.dart';
import '../domain/sale_campaign.dart';

/// A campaign-product line for `POST /sales` — never sent standalone.
class SaleCampaignProductInput {
  const SaleCampaignProductInput({
    required this.productId,
    required this.discountType,
    required this.discountValue,
    this.minQuantity,
  });

  final String productId;
  final SaleDiscountType discountType;
  final double discountValue;
  final double? minQuantity;

  Map<String, dynamic> toJson() => {
    'productId': productId,
    'discountType': discountType.apiValue,
    'discountValue': discountValue,
    'minQuantity': ?minQuantity,
  };
}

/// `GET/POST /sales`, `POST /sales/:id/{approve,reject,cancel}` — confirmed against
/// warehouse-node's `sales` module. Approve/reject/cancel are each confirmed with a one-time code
/// automatically (the shared `OtpInterceptor` — see core/network/api_client.dart), same as every
/// other protected action in this app.
/// A full term set for create/edit/reopen — same shape the backend's `termsFields` expects, each
/// time a full replace, never a partial patch.
class SaleCampaignTerms {
  const SaleCampaignTerms({
    required this.name,
    this.description,
    required this.startsAt,
    required this.endsAt,
    this.eligibility = SaleEligibility.allCustomers,
    this.dailyWindowStart,
    this.dailyWindowEnd,
    this.maxUsesPerCustomer,
    required this.products,
  });

  final String name;
  final String? description;
  final DateTime startsAt;
  final DateTime endsAt;
  final SaleEligibility eligibility;

  /// The viewer's LOCAL picked time-of-day (only the time component is used) — converted to UTC
  /// "HH:MM:SS" on the wire, same convention as every datetime field. Both set or both left out.
  final DateTime? dailyWindowStart;
  final DateTime? dailyWindowEnd;

  /// Null = unlimited.
  final int? maxUsesPerCustomer;
  final List<SaleCampaignProductInput> products;

  static String _hms(DateTime d) => d.toUtc().toIso8601String().substring(11, 19);

  Map<String, dynamic> toJson() => {
    'name': name,
    'description': ?description,
    'startsAt': startsAt.toUtc().toIso8601String(),
    'endsAt': endsAt.toUtc().toIso8601String(),
    'eligibility': eligibility.apiValue,
    'dailyWindowStart': ?(dailyWindowStart == null ? null : _hms(dailyWindowStart!)),
    'dailyWindowEnd': ?(dailyWindowEnd == null ? null : _hms(dailyWindowEnd!)),
    'maxUsesPerCustomer': ?maxUsesPerCustomer,
    'products': products.map((p) => p.toJson()).toList(),
  };
}

class SalesApi {
  SalesApi(this._apiClient);

  final ApiClient _apiClient;

  Future<List<SaleCampaign>> list({SaleCampaignStatus? status}) async {
    final response = await _apiClient.guard(
      (dio) => dio.get<List<dynamic>>('/sales', queryParameters: {'status': ?status?.apiValue}),
    );
    return response.data!.map((e) => SaleCampaign.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<SaleCampaign> getById(String id) async {
    final response = await _apiClient.guard((dio) => dio.get<Map<String, dynamic>>('/sales/$id'));
    return SaleCampaign.fromJson(response.data!);
  }

  Future<SaleCampaign> create(SaleCampaignTerms terms) async {
    final response = await _apiClient.guard((dio) => dio.post<Map<String, dynamic>>('/sales', data: terms.toJson()));
    return SaleCampaign.fromJson(response.data!);
  }

  /// Free edit of your own still-PENDING_APPROVAL campaign — no one-time code (nothing's live yet).
  Future<SaleCampaign> editPending(String id, SaleCampaignTerms terms) async {
    final response = await _apiClient.guard((dio) => dio.patch<Map<String, dynamic>>('/sales/$id', data: terms.toJson()));
    return SaleCampaign.fromJson(response.data!);
  }

  /// Brings a decided campaign back to PENDING_APPROVAL for a fresh approval — confirmed with a
  /// one-time code automatically (OtpInterceptor), same as approve/reject/cancel. `terms` is
  /// optional: given, it replaces the campaign's terms at the same time; omitted, they're resubmitted
  /// unchanged.
  Future<SaleCampaign> reopen(String id, {SaleCampaignTerms? terms}) async {
    final response = await _apiClient.guard((dio) => dio.post<Map<String, dynamic>>('/sales/$id/reopen', data: terms?.toJson() ?? {}));
    return SaleCampaign.fromJson(response.data!);
  }

  Future<SaleCampaign> approve(String id, {String? reviewNote}) async {
    final response = await _apiClient.guard(
      (dio) => dio.post<Map<String, dynamic>>('/sales/$id/approve', data: {'reviewNote': ?reviewNote}),
    );
    return SaleCampaign.fromJson(response.data!);
  }

  Future<SaleCampaign> reject(String id, {required String reviewNote}) async {
    final response = await _apiClient.guard(
      (dio) => dio.post<Map<String, dynamic>>('/sales/$id/reject', data: {'reviewNote': reviewNote}),
    );
    return SaleCampaign.fromJson(response.data!);
  }

  Future<SaleCampaign> cancel(String id, {String? reviewNote}) async {
    final response = await _apiClient.guard(
      (dio) => dio.post<Map<String, dynamic>>('/sales/$id/cancel', data: {'reviewNote': ?reviewNote}),
    );
    return SaleCampaign.fromJson(response.data!);
  }
}
