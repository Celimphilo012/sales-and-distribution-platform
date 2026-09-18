import '../../../core/network/api_client.dart';
import '../domain/customer.dart';
import '../domain/customers_filter.dart';

/// `GET/POST/PATCH/DELETE /customers` (`CustomersController`) — confirmed
/// against the real controller/DTOs. Read is gated `customers.view`; create,
/// update AND delete are all gated the SAME permission, `customers.create`
/// — there is no separate `customers.edit`/`customers.delete` key on this
/// backend (a real difference from assuming edit/delete might need their
/// own keys). No pagination on `findAll` — it returns the full matching
/// list in one response.
class CustomersApi {
  CustomersApi(this._apiClient);

  final ApiClient _apiClient;

  Future<List<Customer>> list(CustomersFilter filter) async {
    final response = await _apiClient.guard(
      (dio) => dio.get<List<dynamic>>('/customers', queryParameters: filter.toQueryParameters()),
    );
    return response.data!.map((e) => Customer.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Customer> getOne(String id) async {
    final response = await _apiClient.guard((dio) => dio.get<Map<String, dynamic>>('/customers/$id'));
    return Customer.fromJson(response.data!);
  }

  Future<Customer> create({
    required String name,
    String? phone,
    String? address,
    String? locationText,
    String? notes,
  }) async {
    final response = await _apiClient.guard(
      (dio) => dio.post<Map<String, dynamic>>(
        '/customers',
        data: {
          'name': name,
          'phone': ?phone,
          'address': ?address,
          'locationText': ?locationText,
          'notes': ?notes,
        },
      ),
    );
    return Customer.fromJson(response.data!);
  }

  Future<Customer> update(
    String id, {
    String? name,
    String? phone,
    String? address,
    String? locationText,
    String? notes,
    CustomerStatus? status,
  }) async {
    final response = await _apiClient.guard(
      (dio) => dio.patch<Map<String, dynamic>>(
        '/customers/$id',
        data: {
          'name': ?name,
          'phone': ?phone,
          'address': ?address,
          'locationText': ?locationText,
          'notes': ?notes,
          'status': ?status?.apiValue,
        },
      ),
    );
    return Customer.fromJson(response.data!);
  }

  /// `DELETE /customers/:id` — soft-deactivates (sets `status: INACTIVE`),
  /// never a hard delete (`CustomersService.remove`).
  Future<Customer> deactivate(String id) async {
    final response = await _apiClient.guard((dio) => dio.delete<Map<String, dynamic>>('/customers/$id'));
    return Customer.fromJson(response.data!);
  }

  /// Reactivates via the same `PATCH` write path `update` uses —
  /// `UpdateCustomerDto.status` is how the backend documents "reactivate".
  Future<Customer> reactivate(String id) => update(id, status: CustomerStatus.active);
}
