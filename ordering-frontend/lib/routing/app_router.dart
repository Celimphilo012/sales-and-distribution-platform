import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../app_shell/responsive_app_shell.dart';
import '../core/ui/root_navigator_key.dart';
import '../core/auth/auth_provider.dart';
import '../core/auth/auth_state.dart';
import '../features/audit/presentation/audit_log_screen.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/customers/presentation/customer_detail_screen.dart';
import '../features/customers/presentation/customers_screen.dart';
import '../features/dashboard/presentation/dashboard_screen.dart';
import '../features/reports/presentation/reports_screen.dart';
import '../features/orders/presentation/order_detail_screen.dart';
import '../features/orders/presentation/order_form_screen.dart';
import '../features/orders/presentation/orders_screen.dart';
import '../features/roles/presentation/role_detail_screen.dart';
import '../features/roles/presentation/roles_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/users/presentation/users_screen.dart';
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
  RoutePaths.customers,
  RoutePaths.orders,
  RoutePaths.users,
  RoutePaths.roles,
  RoutePaths.audit,
  RoutePaths.settings,
  RoutePaths.reports,
};

/// The app's single [GoRouter], keyed off [authProvider] for the splash
/// gate (session restore in flight), the signed-in gate, and per-route
/// permission gating (via [navItemForPath], which prefix-matches so e.g.
/// `/roles/abc-123` inherits the "Roles" nav entry's `roles.manage`
/// requirement). Every route below the login screen renders inside
/// [ResponsiveAppShell].
///
/// STEP R1 (retrofit `/frontend` → `/ordering-frontend`): Dashboard (F2) and
/// Users/Roles/Audit Log/Settings (brought over from the warehouse app's
/// step 6f admin template, Audit Log now backed by `/backend`'s REAL
/// `GET /audit-logs`) make real calls. STEP R2 added Customers — the first
/// ordering feature screen, the template this and R4 (Reports) copy. STEP
/// R3a adds Orders: list/create/edit-draft/detail, including the novel
/// cross-system catalogue picker (`/backend`'s new `GET /catalogue` relay
/// over the internal `WarehouseApiClient`, JWT-guarded — the frontend never
/// calls the warehouse directly, ARCHITECTURE.md §A2). No lifecycle actions
/// beyond DRAFT yet (submit/approve/reserve/pick/pack/dispatch are R3b,
/// even though the backend already supports all of them). Reports is still
/// a [ComingSoonView] placeholder. Products/Categories/Warehouses/Inventory
/// (F3-era) were removed entirely in R1; that catalogue's MANAGEMENT lives
/// in `/warehouse-frontend` talking to `/warehouse-node` — this app only ever
/// READS it, to build an order.
final appRouterProvider = Provider<GoRouter>((ref) {
  final refreshListenable = _AuthRefreshListenable(ref);

  return GoRouter(
    // The one-time-code prompt (raised from a network interceptor) shows above whatever is open.
    navigatorKey: rootNavigatorKey,
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
                builder: (context, state) => item.path == RoutePaths.dashboard
                    ? const DashboardScreen()
                    : ComingSoonView(title: item.label, icon: item.icon),
              ),
          GoRoute(path: RoutePaths.customers, builder: (context, state) => const CustomersScreen()),
          GoRoute(
            path: '${RoutePaths.customers}/:id',
            builder: (context, state) => CustomerDetailScreen(customerId: state.pathParameters['id']!),
          ),
          GoRoute(path: RoutePaths.orders, builder: (context, state) => const OrdersScreen()),
          GoRoute(path: RoutePaths.orderNew, builder: (context, state) => const OrderFormScreen()),
          GoRoute(
            path: '${RoutePaths.orders}/:id/edit',
            builder: (context, state) => OrderFormScreen(orderId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: '${RoutePaths.orders}/:id',
            builder: (context, state) => OrderDetailScreen(orderId: state.pathParameters['id']!),
          ),
          GoRoute(path: RoutePaths.reports, builder: (context, state) => const ReportsScreen()),
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
