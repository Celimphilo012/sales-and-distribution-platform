import '../../../core/network/api_client.dart';
import '../../inventory/domain/inventory_transaction.dart';

/// `POST /inventory/transfers` — confirmed against `TransfersController`'s
/// `@Controller('inventory/transfers')`. Emits ONE TRANSFER transaction
/// (-qty at `fromLocationId`, +qty at `toLocationId`), atomically. The
/// backend rejects `fromLocationId == toLocationId` with a 400 ("TRANSFER
/// requires two different locations") and re-asserts both ends are leaf
/// locations — the picker already prevents both client-side.
class TransfersApi {
  TransfersApi(this._apiClient);

  final ApiClient _apiClient;

  Future<InventoryTransaction> transfer({
    required String productId,
    required double quantity,
    required String fromLocationId,
    required String toLocationId,
    String? reason,
    String? reference,
  }) async {
    final response = await _apiClient.guard(
      (dio) => dio.post<Map<String, dynamic>>(
        '/inventory/transfers',
        data: {
          'productId': productId,
          'quantity': quantity,
          'fromLocationId': fromLocationId,
          'toLocationId': toLocationId,
          'reason': ?reason,
          'reference': ?reference,
        },
      ),
    );
    return InventoryTransaction.fromJson(response.data!);
  }
}
