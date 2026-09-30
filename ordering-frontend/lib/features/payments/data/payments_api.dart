import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/providers.dart';
import '../domain/payment.dart';

/// `/payments` — recording and voiding payments against orders. Payment
/// status is derived by the server from the recorded payments; this client
/// only ever reads it back.
class PaymentsApi {
  PaymentsApi(this._apiClient);

  final ApiClient _apiClient;

  Future<OrderPayments> forOrder(String orderId) async {
    final response = await _apiClient.guard(
      (dio) => dio.get<Map<String, dynamic>>('/payments', queryParameters: {'orderId': orderId}),
    );
    return OrderPayments.fromJson(response.data!);
  }

  /// `GET /payments` — every payment (reports.view), each naming its order
  /// and customer: the Payments ledger.
  Future<List<Payment>> all({DateTime? from, DateTime? to}) async {
    final response = await _apiClient.guard(
      (dio) => dio.get<List<dynamic>>(
        '/payments',
        queryParameters: {'from': ?from?.toUtc().toIso8601String(), 'to': ?to?.toUtc().toIso8601String()},
      ),
    );
    return response.data!.map((e) => Payment.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// `POST /payments`. The server refuses overpayment (409, with `balanceDue`),
  /// a missing reference for non-cash methods (400), and a future [paidAt].
  Future<void> record({
    required String orderId,
    required double amount,
    required PaymentMethod method,
    String? reference,
    String? notes,
    DateTime? paidAt,
  }) async {
    await _apiClient.guard(
      (dio) => dio.post<Map<String, dynamic>>(
        '/payments',
        data: {
          'orderId': orderId,
          'amount': amount,
          'method': method.apiValue,
          'reference': ?reference,
          'notes': ?notes,
          'paidAt': ?paidAt?.toUtc().toIso8601String(),
        },
      ),
    );
  }

  /// `POST /payments/:id/void` — confirmed with a one-time code; the API
  /// client's OTP prompt appears automatically.
  Future<void> voidPayment(String id, {required String reason}) async {
    await _apiClient.guard((dio) => dio.post<Map<String, dynamic>>('/payments/$id/void', data: {'reason': reason}));
  }
}

final paymentsApiProvider = Provider<PaymentsApi>((ref) => PaymentsApi(ref.watch(apiClientProvider)));

final orderPaymentsProvider = FutureProvider.autoDispose.family<OrderPayments, String>((ref, orderId) {
  return ref.watch(paymentsApiProvider).forOrder(orderId);
});

/// Every payment the viewer may see (reports.view) — the Payments ledger.
final allPaymentsProvider = FutureProvider.autoDispose<List<Payment>>((ref) {
  return ref.watch(paymentsApiProvider).all();
});
