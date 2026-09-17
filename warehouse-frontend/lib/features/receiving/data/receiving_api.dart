import '../../../core/network/api_client.dart';
import '../../inventory/domain/inventory_transaction.dart';

/// `POST /inventory/receiving` — the real endpoint (NOT `/receiving`,
/// confirmed against `ReceivingController`'s `@Controller('inventory/
/// receiving')`). `supplier` is REQUIRED on the real `CreateReceivingDto`
/// (free text, no supplier module yet) — not optional as one might assume.
/// Emits one RECEIVE transaction (+on_hand at `toLocationId`); the backend
/// re-asserts `toLocationId` is a leaf regardless of what the picker already
/// enforced client-side.
class ReceivingApi {
  ReceivingApi(this._apiClient);

  final ApiClient _apiClient;

  Future<InventoryTransaction> receive({
    required String supplier,
    required String productId,
    required double quantity,
    required String toLocationId,
    String? reference,
    String? notes,
  }) async {
    final response = await _apiClient.guard(
      (dio) => dio.post<Map<String, dynamic>>(
        '/inventory/receiving',
        data: {
          'supplier': supplier,
          'productId': productId,
          'quantity': quantity,
          'toLocationId': toLocationId,
          'reference': ?reference,
          'notes': ?notes,
        },
      ),
    );
    return InventoryTransaction.fromJson(response.data!);
  }
}
