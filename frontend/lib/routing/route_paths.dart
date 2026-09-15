/// Central route path constants. Every `GoRoute.path` and every
/// `context.go(...)` call should reference these instead of a string
/// literal, so a path never drifts between the router and its callers.
class RoutePaths {
  const RoutePaths._();

  static const splash = '/splash';
  static const login = '/login';
  static const dashboard = '/dashboard';
  static const products = '/products';
  static const productNew = '$products/new';
  static String productDetail(String id) => '$products/$id';
  static String productEdit(String id) => '$products/$id/edit';

  static const categories = '/categories';
  static const warehouses = '/warehouses';
  static const inventory = '/inventory';
  static const orders = '/orders';
  static const fulfilment = '/fulfilment';
  static const users = '/users';
  static const roles = '/roles';
  static const reports = '/reports';
  static const audit = '/audit';
  static const settings = '/settings';

  /// Hidden — not in nav, reachable directly by URL. Demonstrates every
  /// shared widget shell in both themes.
  static const componentGallery = '/dev/components';
}
