import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:warehouse_frontend/core/network/otp_interceptor.dart';
import 'package:warehouse_frontend/core/theme/app_theme.dart';
import 'package:warehouse_frontend/shared/widgets/otp_confirm_dialog.dart';

/// The one-time-code prompt appears on every protected action (count submit,
/// approvals, deactivations). It must lay out cleanly on a desktop and a
/// phone, in both themes — with all three channels offered.
void main() {
  const requirement = OtpRequirement(
    action: 'count.submit',
    message: 'Submitting a stock count needs a one-time code.',
    availableChannels: ['EMAIL', 'SMS', 'TOTP'],
    defaultChannel: 'EMAIL',
  );

  Future<void> pump(WidgetTester tester, Size size, ThemeData theme) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<bool>(
                context: context,
                builder: (_) => OtpConfirmDialog(
                  requirement: requirement,
                  requestCode: (c) async => OtpChallenge(challengeId: 'ch1', channel: c, destination: 'n•••a@example.com'),
                  attempt: (id, code) async => null,
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    // Get a code so the code field and its hint show too.
    await tester.tap(find.text('Send code'));
    await tester.pumpAndSettle();
  }

  for (final (name, size) in [('desktop', const Size(1280, 900)), ('phone', const Size(360, 780))]) {
    for (final dark in [false, true]) {
      testWidgets('lays out without overflow on a $name (${dark ? 'dark' : 'light'})', (tester) async {
        await pump(tester, size, dark ? AppTheme.dark() : AppTheme.light());
        expect(tester.takeException(), isNull);
        expect(find.textContaining('Code sent to'), findsOneWidget);
      });
    }
  }
}
