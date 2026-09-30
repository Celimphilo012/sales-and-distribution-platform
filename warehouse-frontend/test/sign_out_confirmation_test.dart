import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:warehouse_frontend/app_shell/responsive_app_shell.dart';
import 'package:warehouse_frontend/core/auth/app_user.dart';
import 'package:warehouse_frontend/core/auth/auth_provider.dart';
import 'package:warehouse_frontend/core/auth/auth_state.dart';
import 'package:warehouse_frontend/core/persistence/shared_preferences_provider.dart';
import 'package:warehouse_frontend/core/theme/app_theme.dart';
import 'package:warehouse_frontend/routing/nav_items.dart';

const _admin = AppUser(
  id: '1',
  name: 'Warehouse Administrator',
  email: 'admin@example.com',
  permissions: {'inventory.view'},
);

/// Tracks whether the real [AuthNotifier.logout] was actually invoked,
/// without making the real network call it normally would.
class _TrackingAuthNotifier extends AuthNotifier {
  bool loggedOut = false;

  @override
  Future<AuthState> build() async => const AuthState.authenticated(_admin);

  @override
  Future<void> logout() async {
    loggedOut = true;
    state = const AsyncValue.data(AuthState.unauthenticated());
  }
}

Future<_TrackingAuthNotifier> _pump(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final notifier = _TrackingAuthNotifier();
  final router = GoRouter(
    initialLocation: '/inventory',
    routes: [
      ShellRoute(
        builder: (context, state, child) => ResponsiveAppShell(currentPath: state.matchedLocation, child: child),
        routes: [
          for (final item in kNavItems)
            GoRoute(path: item.path, builder: (context, state) => Center(child: Text('page:${item.path}'))),
        ],
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        authProvider.overrideWith(() => notifier),
      ],
      child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return notifier;
}

void main() {
  testWidgets('tapping Sign out asks for confirmation before actually signing out', (tester) async {
    final notifier = await _pump(tester);

    await tester.tap(find.byTooltip('Sign out'));
    await tester.pumpAndSettle();

    expect(find.text('Sign out?'), findsOneWidget);
    expect(notifier.loggedOut, isFalse); // not yet — only asked
  });

  testWidgets('cancelling the confirmation leaves the user signed in', (tester) async {
    final notifier = await _pump(tester);

    await tester.tap(find.byTooltip('Sign out'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Sign out?'), findsNothing);
    expect(notifier.loggedOut, isFalse);
  });

  testWidgets('confirming actually signs out', (tester) async {
    final notifier = await _pump(tester);

    await tester.tap(find.byTooltip('Sign out'));
    await tester.pumpAndSettle();
    // The dialog's confirm button (the trigger is an icon, so this is the only "Sign out" text).
    await tester.tap(find.text('Sign out').last);
    await tester.pumpAndSettle();

    expect(notifier.loggedOut, isTrue);
  });
}
