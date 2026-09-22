import '../../../core/network/api_client.dart';
import '../domain/warehouse_product.dart';

/// `GET /catalogue` — STEP R3a's new frontend-facing relay (`/backend`'s
/// `CatalogueController`, gated `orders.create`, JWT not API-key). ALWAYS
/// active-only server-side (`CatalogueService.list` hard-codes
/// `status: 'ACTIVE'`) — this app never offers an inactive product in the
/// picker. The frontend never calls the warehouse directly (ARCHITECTURE.md
/// §A2) — this is the one path to it.
class CatalogueApi {
  CatalogueApi(this._apiClient);

  final ApiClient _apiClient;

  Future<List<WarehouseProduct>> search(String? search) async {
    final response = await _apiClient.guard(
      (dio) => dio.get<Map<String, dynamic>>('/catalogue', queryParameters: {'search': ?search}),
    );
    final products = response.data!['products'] as List<dynamic>;
    return products.map((e) => WarehouseProduct.fromJson(e as Map<String, dynamic>)).toList();
  }
}
