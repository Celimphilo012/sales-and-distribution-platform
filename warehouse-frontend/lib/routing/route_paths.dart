/// Central route path constants. Every `GoRoute.path` and every
/// `context.go(...)` call should reference these instead of a string
/// literal, so a path never drifts between the router and its callers.
///
/// This is the WAREHOUSE app's nav table (ARCHITECTURE.md §A2) — there is no
/// orders/customers/fulfilment section here; those belong to the separate
/// ordering frontend talking to /ordering-backend. (Reports here are the
/// warehouse's own stock reports.)
class RoutePaths {
  const RoutePaths._();

  static const splash = '/splash';
  static const login = '/login';
  static const dashboard = '/dashboard';
  static const products = '/products';
  static const productNew = '$products/new';
  static const productImport = '$products/import';
  static String productDetail(String id) => '$products/$id';
  static String productEdit(String id) => '$products/$id/edit';

  static const workstreams = '/workstreams';
  static const categories = '/categories';
  static const attributeTypes = '/attribute-types';
  static const warehouses = '/warehouses';
  static const locations = '/locations';
  static const inventory = '/inventory';
  static const receiving = '/receiving';
  static const transfers = '/transfers';
  static const stockCounts = '/stock-counts';
  static String stockCountDetail(String id) => '$stockCounts/$id';
  static const stockAdjustments = '/stock-adjustments';
  static const packing = '/packing';
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
