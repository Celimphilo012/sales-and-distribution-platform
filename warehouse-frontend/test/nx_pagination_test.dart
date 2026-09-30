import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:warehouse_frontend/core/theme/app_theme.dart';
import 'package:warehouse_frontend/shared/nx/nx_list_page.dart';

void main() {
  final rows = [for (var i = 1; i <= 45; i++) 'Item ${i.toString().padLeft(2, '0')}'];

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1300, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: NxListPage<String>(
                stateKey: 'paging-test',
                title: 'Things',
                rows: rows,
                stats: (rs) => [NxStat('Things', '${rs.length}')],
                search: (r) => r,
                defaultSort: ('name', 1),
                columns: [NxColumn(key: 'name', label: 'Name', sort: (r) => r, cell: (r) => Text(r))],
                listRow: (r) => NxListRowSpec(icon: Icons.inbox, title: r),
                card: (r) => NxCardSpec(icon: Icons.inbox, title: r),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('long lists show 20 rows a page; stats still count every row', (tester) async {
    await pump(tester);
    expect(find.text('Item 01'), findsOneWidget);
    expect(find.text('Item 20'), findsOneWidget);
    expect(find.text('Item 21'), findsNothing);
    expect(find.text('1–20 of 45'), findsOneWidget);
    expect(find.text('45'), findsOneWidget); // the stat, over all rows

    await tester.tap(find.byTooltip('Next page'));
    await tester.pumpAndSettle();
    expect(find.text('Item 21'), findsOneWidget);
    expect(find.text('Item 01'), findsNothing);
    expect(find.text('21–40 of 45'), findsOneWidget);

    await tester.tap(find.text('3'));
    await tester.pumpAndSettle();
    expect(find.text('Item 45'), findsOneWidget);
    expect(find.text('41–45 of 45'), findsOneWidget);
  });

  testWidgets('searching goes back to the first page', (tester) async {
    await pump(tester);
    await tester.tap(find.byTooltip('Next page'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText).first, 'Item');
    await tester.pumpAndSettle();
    expect(find.text('Item 01'), findsOneWidget);
    expect(find.text('1–20 of 45'), findsOneWidget);
  });
}
