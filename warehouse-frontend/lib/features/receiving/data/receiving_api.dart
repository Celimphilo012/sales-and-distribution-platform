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

  /// Exactly one of [quantity] / [unitCodes] — the backend derives the ledger quantity from
  /// [unitCodes].length when given (it refuses a BULK product with [unitCodes] and a SERIAL one
  /// with [quantity], matching the product's `trackingMode`).
  Future<InventoryTransaction> receive({
    required String supplier,
    required String productId,
    double? quantity,
    List<String>? unitCodes,
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
          'quantity': ?quantity,
          'unitCodes': ?unitCodes,
          'toLocationId': toLocationId,
          'reference': ?reference,
          'notes': ?notes,
        },
      ),
    );
    return InventoryTransaction.fromJson(response.data!);
  }
}
