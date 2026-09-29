/// Central route path constants. Every `GoRoute.path` and every
/// `context.go(...)` call should reference these instead of a string
/// literal, so a path never drifts between the router and its callers.
///
/// This is the ORDERING app's nav table (ARCHITECTURE.md §A2) — there is no
/// products/categories/warehouses/inventory section here; those belong to
/// the separate `/warehouse-frontend` app talking to `/warehouse-node`. Step R1
/// stripped them from here.
class RoutePaths {
  const RoutePaths._();

  static const splash = '/splash';
  static const login = '/login';
  static const dashboard = '/dashboard';
  static const customers = '/customers';
  static String customerDetail(String id) => '$customers/$id';
  static const orders = '/orders';
  static const orderNew = '$orders/new';
  static String orderDetail(String id) => '$orders/$id';
  static String orderEdit(String id) => '$orders/$id/edit';
  static const users = '/users';
  static const roles = '/roles';
  static String roleDetail(String id) => '$roles/$id';
  static const reports = '/reports';
  static const audit = '/audit';
  static const settings = '/settings';

  /// Hidden — not in nav, reachable directly by URL. Demonstrates every
  /// shared widget shell in both themes.
  static const componentGallery = '/dev/components';
}
