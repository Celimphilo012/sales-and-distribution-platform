import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:warehouse_frontend/core/auth/app_user.dart';
import 'package:warehouse_frontend/core/auth/auth_provider.dart';
import 'package:warehouse_frontend/core/auth/auth_state.dart';
import 'package:warehouse_frontend/core/persistence/shared_preferences_provider.dart';
import 'package:warehouse_frontend/core/theme/app_theme.dart';
import 'package:warehouse_frontend/features/product_import/presentation/product_import_screen.dart';

class _FakeUserNotifier extends AuthNotifier {
  _FakeUserNotifier(this.user);

  final AppUser user;

  @override
  Future<AuthState> build() async => AuthState.authenticated(user);
}

const _manager = AppUser(id: 'u1', name: 'Manager', email: 'm@example.com', permissions: {'products.manage'});
const _viewer = AppUser(id: 'u2', name: 'Viewer', email: 'v@example.com', permissions: {});

Future<void> _pump(WidgetTester tester, AppUser user) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  tester.view.physicalSize = const Size(1200, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        authProvider.overrideWith(() => _FakeUserNotifier(user)),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: ProductImportScreen()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a user without products.manage sees a permission gate, not the wizard', (tester) async {
    await _pump(tester, _viewer);

    expect(find.text("You don't have permission to manage products"), findsOneWidget);
    expect(find.text('Step 1 of 3 — Upload a file'), findsNothing);
  });

  testWidgets('a products.manage user lands on step 1: template + file picker, upload disabled until a file is chosen', (
    tester,
  ) async {
    await _pump(tester, _manager);

    expect(find.text('Import products'), findsOneWidget);
    expect(find.text('Step 1 of 3 — Upload a file'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Download template (.xlsx)'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Choose file'), findsOneWidget);
    expect(find.text('No file chosen — .xlsx or .csv'), findsOneWidget);

    final uploadButton = tester.widget<FilledButton>(
      find.ancestor(of: find.text('Upload & preview'), matching: find.byType(FilledButton)),
    );
    expect(uploadButton.onPressed, isNull); // no file picked yet
  });
}
