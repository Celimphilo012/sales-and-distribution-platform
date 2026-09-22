import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:warehouse_frontend/core/theme/app_theme.dart';
import 'package:warehouse_frontend/shared/widgets/app_data_table.dart';

Widget _table(int count, {required double width, required double height}) => MaterialApp(
  theme: AppTheme.light(),
  home: Scaffold(
    body: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: width,
        height: height,
        child: AppDataTable<int>(
          rows: List.generate(count, (i) => i + 1),
          columns: [AppDataColumn(label: 'Name', cellBuilder: (i) => Text('Row $i'))],
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('a long table scrolls vertically so every row is reachable', (tester) async {
    await tester.pumpWidget(_table(40, width: 1000, height: 400));

    expect(find.text('Row 1'), findsOneWidget);
    expect(find.text('Row 40', skipOffstage: false), findsOneWidget);
    expect(tester.getBottomLeft(find.text('Row 40', skipOffstage: false)).dy, greaterThan(400),
        reason: 'row 40 starts below the visible area');

    await tester.drag(find.text('Row 1'), const Offset(0, -3000)); // start from a visible row
    await tester.pumpAndSettle();

    expect(tester.getBottomLeft(find.text('Row 40')).dy, lessThanOrEqualTo(400),
        reason: 'after scrolling, the last row is inside the visible area');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a short table hugs its rows instead of stretching to the available height', (tester) async {
    await tester.pumpWidget(_table(3, width: 1000, height: 600));
    expect(tester.getSize(find.byType(DataTable)).height, lessThan(300));
  });

  testWidgets('narrow width falls back to cards', (tester) async {
    await tester.pumpWidget(_table(3, width: 400, height: 600));
    expect(find.byType(DataTable), findsNothing);
    expect(find.text('Row 1'), findsOneWidget);
  });
}
