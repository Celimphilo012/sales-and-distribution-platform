import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:warehouse_frontend/core/auth/app_user.dart';
import 'package:warehouse_frontend/core/auth/auth_provider.dart';
import 'package:warehouse_frontend/core/auth/auth_state.dart';
import 'package:warehouse_frontend/core/persistence/shared_preferences_provider.dart';
import 'package:warehouse_frontend/core/theme/app_theme.dart';
import 'package:warehouse_frontend/features/audit/data/audit_logs_providers.dart';
import 'package:warehouse_frontend/features/audit/domain/audit_log.dart';
import 'package:warehouse_frontend/features/audit/presentation/audit_log_screen.dart';

class _FakeUserNotifier extends AuthNotifier {
  _FakeUserNotifier(this.user);

  final AppUser user;

  @override
  Future<AuthState> build() async => AuthState.authenticated(user);
}

const _viewer = AppUser(id: 'u1', name: 'Viewer', email: 'v@example.com', permissions: {});
const _auditor = AppUser(id: 'u2', name: 'Auditor', email: 'a@example.com', permissions: {'audit.view'});

final _now = DateTime(2026, 1, 1, 12, 30);

final _fakePage = AuditLogPage(
  data: [
    AuditLog(
      id: 'a1',
      userId: 'u9',
      user: const AuditLogUserRef(id: 'u9', fullName: 'Warehouse Administrator', email: 'admin@example.com'),
      action: 'CREATE',
      entity: 'products',
      entityId: 'p1',
      newValue: const {'sku': 'ABC-1'},
      createdAt: _now,
    ),
    AuditLog(
      id: 'a2',
      apiKeyId: 'k1',
      apiKey: const AuditLogApiKeyRef(id: 'k1', name: 'Ordering integration'),
      action: 'UPDATE',
      entity: 'inventory_balances',
      entityId: 'b1',
      createdAt: _now,
    ),
  ],
  page: 1,
  pageSize: 20,
  total: 2,
  totalPages: 1,
);

Future<void> _pump(WidgetTester tester, AppUser user) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        authProvider.overrideWith(() => _FakeUserNotifier(user)),
        auditLogsPageProvider.overrideWith((ref) async => _fakePage),
      ],
      child: MaterialApp(theme: AppTheme.light(), home: Scaffold(body: AuditLogScreen())),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a user without audit.view sees a permission gate, not the log', (tester) async {
    await _pump(tester, _viewer);

    expect(find.text("You don't have permission to view the audit log"), findsOneWidget);
    expect(find.text('CREATE'), findsNothing);
  });

  testWidgets('an audit.view user sees real rows, attributed to a user or an API key', (tester) async {
    await _pump(tester, _auditor);

    expect(find.text('Warehouse Administrator'), findsOneWidget); // user-attributed row
    expect(find.text('Ordering integration (API key)'), findsOneWidget); // key-attributed row
    // 'CREATE' also matches the Action filter field's hint text, so scope to
    // the table's own cell instead of the bare, ambiguous string.
    expect(find.text('CREATE'), findsNWidgets(2)); // table cell + filter hint
    expect(find.text('UPDATE'), findsOneWidget);
    expect(find.textContaining('2 total'), findsOneWidget);
  });

  testWidgets('tapping a row opens a detail dialog with old/new values', (tester) async {
    await _pump(tester, _auditor);

    // 'CREATE' also matches the Action filter field's hint text — tap the
    // row via its unambiguous "who" cell instead.
    await tester.tap(find.text('Warehouse Administrator'));
    await tester.pumpAndSettle();

    expect(find.text('CREATE · products (p1)'), findsOneWidget);
    expect(find.textContaining('Warehouse Administrator'), findsWidgets);
    expect(find.textContaining('"sku": "ABC-1"'), findsOneWidget);
  });
}
