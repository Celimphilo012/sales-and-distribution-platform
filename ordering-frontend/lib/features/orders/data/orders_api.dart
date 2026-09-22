import '../../../core/network/api_client.dart';
import '../domain/order.dart';
import '../domain/order_item_input.dart';
import '../domain/order_lifecycle.dart';

/// `GET/POST/PATCH /orders` (`OrdersController`) — confirmed against the
/// real controller/DTOs/service. No pagination, no search — just `status`
/// and `customerId` filters (same no-pagination trait R2's Customers found).
/// `GET` is scoped server-side to the caller's own orders unless they hold
/// `orders.view_team` (`OrdersController.findAll`'s in-service check) — this
/// client has no knowledge of that scoping, it just gets back whatever the
/// server decides to include.
class OrdersApi {
  OrdersApi(this._apiClient);

  final ApiClient _apiClient;

  Future<List<Order>> list({OrderStatus? status, String? customerId}) async {
    final response = await _apiClient.guard(
      (dio) => dio.get<List<dynamic>>(
        '/orders',
        queryParameters: {'status': ?status?.apiValue, 'customerId': ?customerId},
      ),
    );
    return response.data!.map((e) => Order.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Order> getOne(String id) async {
    final response = await _apiClient.guard((dio) => dio.get<Map<String, dynamic>>('/orders/$id'));
    return Order.fromJson(response.data!);
  }

  /// Creates a DRAFT order. Only `customerId` + `items` (`productId` +
  /// `quantity` each) are ever sent — no price, no product name, no status
  /// (the server always starts a new order at DRAFT).
  Future<Order> create({required String customerId, String? deliveryInfo, required List<OrderItemInput> items}) async {
    final response = await _apiClient.guard(
      (dio) => dio.post<Map<String, dynamic>>(
        '/orders',
        data: {
          'customerId': customerId,
          'deliveryInfo': ?deliveryInfo,
          'items': items.map((i) => i.toJson()).toList(),
        },
      ),
    );
    return Order.fromJson(response.data!);
  }

  /// DRAFT-only, owner-only (`OrdersService.update` — a 409 if not DRAFT, a
  /// 403 if the caller isn't the order's `consultantId`). `items`, when
  /// supplied, REPLACES the full line set — there is no add/remove-one-line
  /// endpoint, matching the `AssignPermissionsDto`/`UpdateUserDto.roleIds`
  /// "replace, don't patch individual rows" convention elsewhere on this
  /// backend. `customerId` cannot be changed after creation — the DTO has
  /// no field for it.
  Future<Order> update(String id, {String? deliveryInfo, List<OrderItemInput>? items}) async {
    final response = await _apiClient.guard(
      (dio) => dio.patch<Map<String, dynamic>>(
        '/orders/$id',
        data: {'deliveryInfo': ?deliveryInfo, 'items': ?items?.map((i) => i.toJson()).toList()},
      ),
    );
    return Order.fromJson(response.data!);
  }

  // ---------------------------------------------------------------------
  // STEP R3b — lifecycle. Every action is ONE `POST /orders/:id/<action>`
  // that returns the whole updated order (`OrdersService.getExisting`). The
  // frontend never orchestrates several calls: reserve/dispatch/cancel do
  // their warehouse round-trip inside the backend.
  // ---------------------------------------------------------------------

  Future<Order> _post(String id, OrderAction action, Map<String, dynamic> body) async {
    final response = await _apiClient.guard(
      (dio) => dio.post<Map<String, dynamic>>('/orders/$id/${kOrderActionSpecs[action]!.path}', data: body),
    );
    return Order.fromJson(response.data!);
  }

  /// submit / approve / cancel / ready / dispatch / deliver / complete: the
  /// backend takes only an optional `note` for the history row. (`submit`
  /// performs DRAFT → SUBMITTED → PENDING_APPROVAL in one call, writing two
  /// history rows.) `dispatch` takes NO quantities — it ships what `pack`
  /// recorded and reads the fulfilled amounts back from the warehouse.
  Future<Order> transition(String id, OrderAction action, {String? note}) =>
      _post(id, action, {'note': ?note});

  /// `note` is mandatory on the backend (400 without one).
  Future<Order> reject(String id, {required String note}) => _post(id, OrderAction.reject, {'note': note});

  /// APPROVED → STOCK_RESERVED. [allocations] maps every order line's id to
  /// the leaf location to reserve it from — it must cover exactly the
  /// order's lines. Throws a `ConflictError` (409) carrying the short lines
  /// when the warehouse lacks stock, and `ServiceUnavailableError` (503) when
  /// the warehouse can't be reached; the order stays APPROVED either way.
  Future<Order> reserve(String id, {required Map<String, String> allocations}) => _post(id, OrderAction.reserve, {
    'allocations': [
      for (final entry in allocations.entries) {'orderItemId': entry.key, 'locationId': entry.value},
    ],
  });

  /// STOCK_RESERVED → PICKING. [pickedQty] maps every line id to the quantity
  /// picked (0 ≤ picked ≤ ordered; the backend enforces it).
  Future<Order> pick(String id, {required Map<String, double> pickedQty}) => _post(id, OrderAction.pick, {
    'items': [
      for (final entry in pickedQty.entries) {'orderItemId': entry.key, 'pickedQty': entry.value},
    ],
  });

  /// PICKING → PACKED. [packedQty] maps every line id to the quantity packed
  /// (0 ≤ packed ≤ picked).
  Future<Order> pack(String id, {required Map<String, double> packedQty}) => _post(id, OrderAction.pack, {
    'items': [
      for (final entry in packedQty.entries) {'orderItemId': entry.key, 'packedQty': entry.value},
    ],
  });
}
