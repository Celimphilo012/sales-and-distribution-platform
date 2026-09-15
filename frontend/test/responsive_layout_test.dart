import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:distribution_platform/core/responsive/responsive_layout.dart';

void main() {
  Future<void> pumpAt(WidgetTester tester, double width) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: ResponsiveLayout(
          mobile: (_) => const Text('mobile'),
          tablet: (_) => const Text('tablet'),
          desktop: (_) => const Text('desktop'),
        ),
      ),
    );
  }

  testWidgets('picks mobile below 600', (tester) async {
    await pumpAt(tester, 500);
    expect(find.text('mobile'), findsOneWidget);
  });

  testWidgets('picks tablet between 600 and 1024', (tester) async {
    await pumpAt(tester, 800);
    expect(find.text('tablet'), findsOneWidget);
  });

  testWidgets('picks desktop at 1024 and above', (tester) async {
    await pumpAt(tester, 1200);
    expect(find.text('desktop'), findsOneWidget);
  });

  testWidgets('falls back to mobile when tablet/desktop omitted', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(home: ResponsiveLayout(mobile: (_) => const Text('mobile-only'))),
    );

    expect(find.text('mobile-only'), findsOneWidget);
  });
}
