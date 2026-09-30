import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:warehouse_frontend/core/theme/app_theme.dart';
import 'package:warehouse_frontend/core/ui/root_navigator_key.dart';
import 'package:warehouse_frontend/shared/export/label_export.dart';
import 'package:warehouse_frontend/shared/export/report_export.dart';
import 'package:warehouse_frontend/shared/scan/scan_code.dart';
import 'package:warehouse_frontend/shared/scan/scan_dialog.dart';

typedef _Item = ({String id, String code});

void main() {
  group('ScanCode', () {
    test('reads our product and location labels', () {
      final p = ScanCode.parse(' WH:P:abc-123 ');
      expect(p.kind, ScanKind.product);
      expect(p.value, 'abc-123');
      final l = ScanCode.parse('wh:l:slot-9');
      expect(l.kind, ScanKind.location);
      expect(l.value, 'slot-9');
      expect(ScanCode.parse(ScanCode.forProduct('x')).value, 'x');
    });

    test('anything else is unknown and matches by id or by code, case-insensitively', () {
      const items = <_Item>[(id: 'id-1', code: 'PC-001'), (id: 'id-2', code: 'PC-002')];
      _Item? m(String raw, ScanKind want) => ScanCode.parse(raw).match(want, items, id: (x) => x.id, code: (x) => x.code);
      expect(m('pc-002', ScanKind.product)?.id, 'id-2');
      expect(m('id-1', ScanKind.product)?.id, 'id-1');
      expect(m('WH:P:id-2', ScanKind.product)?.id, 'id-2');
      // A label keeps working after a SKU rename: it carries the id, not the SKU.
      expect(m('WH:P:PC-001', ScanKind.product), isNull);
      // A location label never matches a product (and vice versa).
      expect(m('WH:L:id-1', ScanKind.product), isNull);
      expect(m('nope', ScanKind.product), isNull);
    });
  });

  group('scan dialog', () {
    Future<BuildContext> pump(WidgetTester tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: rootNavigatorKey,
          theme: AppTheme.dark(),
          home: Scaffold(body: Builder(
            builder: (c) {
              ctx = c;
              return const SizedBox();
            },
          )),
        ),
      );
      return ctx;
    }

    testWidgets('a handheld scanner (typed code + Enter) returns the parsed code', (tester) async {
      final ctx = await pump(tester);
      ScanCode? got;
      showScanDialog(ctx).then((c) => got = c);
      await tester.pumpAndSettle();
      expect(find.text('Ready for a handheld scanner'), findsOneWidget);
      await tester.enterText(find.byType(EditableText), 'WH:L:slot-1');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(got?.kind, ScanKind.location);
      expect(got?.value, 'slot-1');
    });

    testWidgets('continuous mode stays open and shows each result', (tester) async {
      final ctx = await pump(tester);
      final seen = <String>[];
      showScanDialog(
        ctx,
        onScan: (c) {
          seen.add(c.value);
          return c.value == 'PC-001' ? const ScanFeedback('PC-001 · 1 of 2') : const ScanFeedback('Not in this order', ok: false);
        },
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(EditableText), 'PC-001');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text('PC-001 · 1 of 2'), findsOneWidget);
      await tester.enterText(find.byType(EditableText), 'XX-9');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text('Not in this order'), findsOneWidget);
      expect(seen, ['PC-001', 'XX-9']);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.text('Scan a code'), findsNothing);
    });
  });

  test('label sheets are a PDF, repeated per copy', () async {
    const b = ExportBranding(company: 'Acme', subtitle: '');
    const l = QrLabel(payload: 'WH:P:abc', code: 'PC-001', title: 'Body lotion', sub: 'Skin care · bottle');
    final bytes = await labelsPdf([l], b, copies: 25);
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    final one = await labelsPdf([l], b);
    expect(bytes.length, greaterThan(one.length));
  });
}
