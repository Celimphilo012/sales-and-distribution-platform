import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ordering_frontend/app.dart';
import 'package:ordering_frontend/core/auth/auth_provider.dart';
import 'package:ordering_frontend/core/auth/auth_state.dart';
import 'package:ordering_frontend/core/persistence/shared_preferences_provider.dart';

/// Bypasses the real session restore (secure storage + a live `/users/me`
/// call) so this widget test never touches a platform channel or the
/// network — it only exercises routing/rendering.
class _FakeUnauthenticatedNotifier extends AuthNotifier {
  @override
  Future<AuthState> build() async => const AuthState.unauthenticated();
}

void main() {
  testWidgets('Unauthenticated app boots to the real login screen', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final sharedPreferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(sharedPreferences),
          authProvider.overrideWith(_FakeUnauthenticatedNotifier.new),
        ],
        child: const App(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
  });
}
