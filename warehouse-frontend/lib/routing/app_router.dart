import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../app_shell/responsive_app_shell.dart';
import '../core/auth/auth_provider.dart';
import '../core/auth/auth_state.dart';
import '../features/attribute_types/presentation/attribute_types_screen.dart';
import '../features/audit/presentation/audit_log_screen.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/categories/presentation/categories_screen.dart';
import '../features/inventory/presentation/inventory_screen.dart';
import '../features/locations/presentation/warehouse_structure_screen.dart';
import '../features/products/presentation/product_detail_screen.dart';
import '../features/products/presentation/product_form_screen.dart';
import '../features/products/presentation/products_list_screen.dart';
import '../features/receiving/presentation/receiving_form_screen.dart';
import '../features/roles/presentation/role_detail_screen.dart';
import '../features/roles/presentation/roles_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/stock_adjustments/presentation/stock_adjustments_screen.dart';
import '../features/stock_counts/presentation/stock_count_detail_screen.dart';
import '../features/stock_counts/presentation/stock_counts_screen.dart';
import '../features/transfers/presentation/transfer_form_screen.dart';
import '../features/users/presentation/users_screen.dart';
import '../features/warehouses/presentation/warehouses_list_screen.dart';
import '../features/workstreams/presentation/workstreams_screen.dart';
import '../shared/widgets/coming_soon_view.dart';
import 'component_gallery_screen.dart';
import 'nav_items.dart';
import 'route_paths.dart';
import 'splash_screen.dart';

/// Notifies go_router to re-run [GoRouter.redirect] whenever auth state
/// changes (sign in/out/session-restore), so nav gating and the login/splash
/// gate update without a manual reload.
class _AuthRefreshListenable extends ChangeNotifier {
  _AuthRefreshListenable(Ref ref) {
    ref.listen(authProvider, (previous, next) => notifyListeners());
  }
}

/// Nav-item paths whose sub-routes (list/detail/create/edit) are hand-built
/// below instead of the generic one-`ComingSoonView`-per-item loop.
const _customBuiltPaths = {
  RoutePaths.products,
  RoutePaths.workstreams,
  RoutePaths.categories,
  RoutePaths.attributeTypes,
  RoutePaths.warehouses,
  RoutePaths.locations,
  RoutePaths.inventory,
  RoutePaths.receiving,
  RoutePaths.transfers,
  RoutePaths.stockCounts,
  RoutePaths.stockAdjustments,
  RoutePaths.users,
  RoutePaths.roles,
  RoutePaths.audit,
  RoutePaths.settings,
};

/// The app's single [GoRouter], keyed off [authProvider] for the splash
/// gate (session restore in flight), the signed-in gate, and per-route
/// permission gating (via [navItemForPath], which prefix-matches so e.g.
/// `/products/abc-123/edit` inherits the "Products" nav entry's
/// `catalogue.view` requirement). Every route below the login screen renders
/// inside [ResponsiveAppShell].
///
/// Steps 6b (Products/Categories), 6c (Warehouses/Warehouse Structure), 6d
/// (Inventory — read-only), 6e-1 (Receiving/Transfers), 6e-2 (Stock
/// Counts/Stock Adjustments — the two-step approval workflow, §F), and 6f
/// (Users/Roles/Audit Log/Settings — the admin screens) all make real calls
/// against the warehouse backend, each copying the same data/domain/
/// presentation pattern; 6f completes the warehouse frontend. Users, Roles,
/// and Settings' Profile section are built as a clean, reusable template —
/// the ordering app's own auth/RBAC (copied from this same backend
/// originally) will need near-identical screens later, just re-pointed at
/// its own API base. Audit Log is permission-gated but shows an honest
/// backend-gap notice instead of fake data — the warehouse backend writes
/// audit_logs rows but has no read endpoint yet. Settings' API-key section
/// is warehouse-specific (the ordering app never issues these) and not
/// meant to be copied. Workstreams (a catalogue-organization layer —
/// Warehouse -> Workstream -> Category -> sub-category -> Product, purely
/// reference data, never operational) extends the 6b catalogue screens.
final appRouterProvider = Provider<GoRouter>((ref) {
  final refreshListenable = _AuthRefreshListenable(ref);

  return GoRouter(
    initialLocation: RoutePaths.splash,
    refreshListenable: refreshListenable,
    redirect: (context, state) {
      final path = state.matchedLocation;
      if (path == RoutePaths.componentGallery) return null;

      final authAsync = ref.read(authProvider);
      if (authAsync.isLoading) {
        return path == RoutePaths.splash ? null : RoutePaths.splash;
      }

      final auth = authAsync.value ?? const AuthState.unauthenticated();
      final isLoginRoute = path == RoutePaths.login;
      final isSplashRoute = path == RoutePaths.splash;

      if (!auth.isAuthenticated) {
        if (isLoginRoute) return null;
        return RoutePaths.login;
      }
      if (isLoginRoute || isSplashRoute) return RoutePaths.dashboard;

      final navItem = navItemForPath(path);
      if (navItem != null && navItem.requiredPermissions.isNotEmpty) {
        final allowed = auth.user?.canAny(navItem.requiredPermissions) ?? false;
        if (!allowed) return RoutePaths.dashboard;
      }
      return null;
    },
    routes: [
      GoRoute(path: RoutePaths.splash, builder: (context, state) => const SplashScreen()),
      GoRoute(path: RoutePaths.login, builder: (context, state) => const LoginScreen()),
      GoRoute(
        path: RoutePaths.componentGallery,
        builder: (context, state) => const ComponentGalleryScreen(),
      ),
      ShellRoute(
        builder: (context, state, child) =>
            ResponsiveAppShell(currentPath: state.matchedLocation, child: child),
        routes: [
          for (final item in kNavItems)
            if (!_customBuiltPaths.contains(item.path))
              GoRoute(
                path: item.path,
                builder: (context, state) => ComingSoonView(title: item.label, icon: item.icon),
              ),
          GoRoute(path: RoutePaths.products, builder: (context, state) => const ProductsListScreen()),
          GoRoute(path: RoutePaths.productNew, builder: (context, state) => const ProductFormScreen()),
          GoRoute(
            path: '${RoutePaths.products}/:id',
            builder: (context, state) => ProductDetailScreen(productId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: '${RoutePaths.products}/:id/edit',
            builder: (context, state) => ProductFormScreen(productId: state.pathParameters['id']!),
          ),
          GoRoute(path: RoutePaths.workstreams, builder: (context, state) => const WorkstreamsScreen()),
          GoRoute(path: RoutePaths.categories, builder: (context, state) => const CategoriesScreen()),
          GoRoute(path: RoutePaths.attributeTypes, builder: (context, state) => const AttributeTypesScreen()),
          GoRoute(path: RoutePaths.warehouses, builder: (context, state) => const WarehousesListScreen()),
          GoRoute(
            path: RoutePaths.locations,
            builder: (context, state) =>
                WarehouseStructureScreen(initialWarehouseId: state.uri.queryParameters['warehouseId']),
          ),
          GoRoute(
            path: RoutePaths.inventory,
            builder: (context, state) => InventoryScreen(initialProductId: state.uri.queryParameters['productId']),
          ),
          GoRoute(path: RoutePaths.receiving, builder: (context, state) => const ReceivingFormScreen()),
          GoRoute(path: RoutePaths.transfers, builder: (context, state) => const TransferFormScreen()),
          GoRoute(path: RoutePaths.stockCounts, builder: (context, state) => const StockCountsScreen()),
          GoRoute(
            path: '${RoutePaths.stockCounts}/:id',
            builder: (context, state) => StockCountDetailScreen(countId: state.pathParameters['id']!),
          ),
          GoRoute(path: RoutePaths.stockAdjustments, builder: (context, state) => const StockAdjustmentsScreen()),
          GoRoute(path: RoutePaths.users, builder: (context, state) => const UsersScreen()),
          GoRoute(path: RoutePaths.roles, builder: (context, state) => const RolesScreen()),
          GoRoute(
            path: '${RoutePaths.roles}/:id',
            builder: (context, state) => RoleDetailScreen(roleId: state.pathParameters['id']!),
          ),
          GoRoute(path: RoutePaths.audit, builder: (context, state) => const AuditLogScreen()),
          GoRoute(path: RoutePaths.settings, builder: (context, state) => const SettingsScreen()),
        ],
      ),
    ],
  );
});
