import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:warehouse_frontend/core/auth/auth_provider.dart';
import 'package:warehouse_frontend/core/auth/auth_state.dart';
import 'package:warehouse_frontend/core/theme/app_theme.dart';
import 'package:warehouse_frontend/features/auth/presentation/login_screen.dart';

class _FakeUnauthenticated extends AuthNotifier {
  @override
  Future<AuthState> build() async => const AuthState.unauthenticated();
}

Future<void> _pump(WidgetTester tester, Size size) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [authProvider.overrideWith(_FakeUnauthenticated.new)],
      child: MaterialApp(theme: AppTheme.light(), home: const LoginScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('wide: masthead + credentials side by side', (tester) async {
    await _pump(tester, const Size(1280, 800));
    expect(find.text('SALES & DISTRIBUTION'), findsOneWidget); // masthead only exists on wide
    expect(find.text('Sign in'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow: single column, no masthead, scrolls instead of overflowing', (tester) async {
    await _pump(tester, const Size(360, 640));
    expect(find.text('SALES & DISTRIBUTION'), findsNothing);
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('short landscape phone (640x360) stays usable', (tester) async {
    await _pump(tester, const Size(640, 360));
    expect(find.text('Sign in'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
