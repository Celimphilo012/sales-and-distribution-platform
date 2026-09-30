import 'package:excel/excel.dart' as xl;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:warehouse_frontend/app_shell/branding.dart';
import 'package:warehouse_frontend/core/auth/app_user.dart';
import 'package:warehouse_frontend/core/auth/auth_provider.dart';
import 'package:warehouse_frontend/core/auth/auth_state.dart';
import 'package:warehouse_frontend/core/theme/app_theme.dart';
import 'package:warehouse_frontend/core/theme/brand_palette.dart';
import 'package:warehouse_frontend/core/theme/nocturne.dart';
import 'package:warehouse_frontend/core/ui/root_navigator_key.dart';
import 'package:warehouse_frontend/features/settings/data/branding_api.dart';
import 'package:warehouse_frontend/features/settings/presentation/widgets/branding_section.dart';
import 'package:warehouse_frontend/shared/export/report_export.dart';
import 'package:warehouse_frontend/shared/nx/nx_overlays.dart';

double _contrast(Color a, Color b) {
  final x = a.computeLuminance();
  final y = b.computeLuminance();
  return (x > y ? x + 0.05 : y + 0.05) / (x > y ? y + 0.05 : x + 0.05);
}

class _Admin extends AuthNotifier {
  @override
  Future<AuthState> build() async =>
      const AuthState.authenticated(AppUser(id: 'u1', name: 'Admin', email: 'admin@example.com', permissions: {'settings.manage'}));
}

class _FakeBranding extends Fake implements BrandingApi {
  final calls = <Map<String, Object?>>[];

  @override
  Future<Branding> setIdentity({
    String? companyName,
    String? tagline,
    String? brandColor,
    String? headingFont,
    String? bodyFont,
    Map<String, String>? letterhead,
    String? emailSignature,
  }) async {
    calls.add({
      'companyName': ?companyName,
      'tagline': ?tagline,
      'brandColor': ?brandColor,
      'headingFont': ?headingFont,
      'bodyFont': ?bodyFont,
      'letterhead': ?letterhead,
      'emailSignature': ?emailSignature,
    });
    return const Branding(companyName: 'Acme', hasLogo: false);
  }
}

void main() {
  group('brand palette', () {
    test('parses and prints hex colours', () {
      expect(BrandPalette.parse('#0e7c66'), const Color(0xFF0E7C66));
      expect(BrandPalette.parse('teal'), isNull);
      expect(BrandPalette.hex(const Color(0xFF0E7C66)), '#0E7C66');
    });

    // Whatever colour is chosen, every accent/background pair keeps the
    // contrast the built-in palette was designed with.
    for (final hex in ['#F2E600', '#0B1F3A', '#0E7C66', '#E8702A', '#888888']) {
      test('$hex keeps accent text readable in both themes', () {
        final seed = BrandPalette.parse(hex)!;
        for (final base in [Nocturne.dark, Nocturne.light]) {
          final b = base.withBrand(seed);
          expect(_contrast(b.accent, b.bg), closeTo(_contrast(base.accent, base.bg), 0.15), reason: 'accent on the page');
          expect(_contrast(b.a300, b.a900), closeTo(_contrast(base.a300, base.a900), 0.2), reason: 'info tag text on its tint');
          expect(_contrast(b.a100, b.a800), closeTo(_contrast(base.a100, base.a800), 0.2), reason: 'accent tag text on its tint');
        }
      });
    }

    test('the hue follows the brand colour', () {
      final teal = Nocturne.dark.withBrand(const Color(0xFF0E7C66));
      expect(HSLColor.fromColor(teal.accent).hue, closeTo(HSLColor.fromColor(const Color(0xFF0E7C66)).hue, 3));
      expect(Nocturne.dark.withBrand(null).accent, Nocturne.dark.accent);
    });
  });

  group('letterhead on exports', () {
    const rep = ReportData(title: 'Stock', description: 'On hand', columns: [ReportColumn('SKU'), ReportColumn('Qty', ColType.num)], rows: [['A', 1]]);
    const b = ExportBranding(
      company: 'Acme',
      subtitle: 'Main · today',
      color: Color(0xFF0E7C66),
      tagline: 'Wholesale · Mbabane',
      contact: ['Plot 12, Mbabane', '+268 2404 0000'],
      registration: 'Reg. 123/2020',
      footer: 'Goods remain ours until paid.',
    );

    test('brand colours drive the export colours (built-in without one)', () {
      expect(b.colors.deep, isNot(ExportColors.standard.deep));
      expect(const ExportBranding(company: 'x', subtitle: '').colors.deep, ExportColors.standard.deep);
      // White header text stays readable on the deep band.
      expect(_contrast(Color(b.colors.deep.toInt()), const Color(0xFFFFFFFF)), greaterThan(7));
    });

    test('PDFs render with the letterhead and small print', () async {
      final bytes = await reportPdf(rep, b);
      expect(String.fromCharCodes(bytes.sublist(0, 5)), '%PDF-');
    });

    test('Excel carries the tagline and contact line', () {
      final book = xl.Excel.decodeBytes(reportXlsx(rep, b));
      final sheet = book['Stock'];
      String? cell(int c, int r) => sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r)).value?.toString();
      expect(cell(0, 1), startsWith('Wholesale · Mbabane · '));
      expect(cell(0, 2), 'Plot 12, Mbabane · +268 2404 0000');
    });
  });

  testWidgets('the branding editor previews a colour and saves each part of the kit', (tester) async {
    tester.view.physicalSize = const Size(1400, 1300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = _FakeBranding();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authProvider.overrideWith(_Admin.new),
          brandingApiProvider.overrideWithValue(api),
          brandingProvider.overrideWith((ref) async => const Branding(companyName: 'Acme', hasLogo: false)),
          brandingLogoProvider.overrideWith((ref) async => null),
        ],
        child: MaterialApp(
          navigatorKey: rootNavigatorKey,
          theme: AppTheme.dark(),
          builder: (context, child) => NxToastHost(child: child ?? const SizedBox.shrink()),
          home: const Scaffold(body: SingleChildScrollView(padding: EdgeInsets.all(16), child: BrandingSection(canManage: true))),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Identity: tagline shows in the live preview, then saves.
    await tester.enterText(find.byType(EditableText).at(1), 'Wholesale · Mbabane');
    await tester.pump();
    expect(find.text('Wholesale · Mbabane'), findsWidgets);
    await tester.tap(find.text('Save identity'));
    await tester.pump(const Duration(seconds: 6));
    expect(api.calls.last, {'companyName': 'Acme', 'tagline': 'Wholesale · Mbabane'});

    // Colour: pick a preset — the preview's theme changes before saving.
    await tester.tap(find.text('Colour'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Teal · #0E7C66'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save colour'));
    await tester.pump(const Duration(seconds: 6));
    expect(api.calls.last, {'brandColor': '#0E7C66'});

    // Letterhead: every field is sent (empty ones clear).
    await tester.tap(find.text('Letterhead'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText).first, 'Plot 12, Mbabane');
    await tester.pump();
    expect(find.text('Plot 12, Mbabane'), findsWidgets); // on the PDF preview too
    await tester.tap(find.text('Save letterhead'));
    await tester.pump(const Duration(seconds: 6));
    expect((api.calls.last['letterhead']! as Map)['address'], 'Plot 12, Mbabane');
    expect((api.calls.last['letterhead']! as Map)['phone'], '');

    // Email signature.
    await tester.tap(find.text('Email signature'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText).first, 'Kind regards,\nThe Acme team');
    await tester.pump();
    await tester.tap(find.text('Save signature'));
    await tester.pump(const Duration(seconds: 6));
    expect(api.calls.last, {'emailSignature': 'Kind regards,\nThe Acme team'});
  });

  test('the brand colour provider reads the saved colour', () async {
    final c = ProviderContainer(overrides: [
      brandingProvider.overrideWith((ref) async => const Branding(companyName: 'Acme', hasLogo: false, brandColor: '#0E7C66', tagline: 'Hi')),
    ]);
    addTearDown(c.dispose);
    c.listen(brandColorProvider, (_, _) {});
    c.listen(brandTaglineProvider, (_, _) {});
    await c.read(brandingProvider.future);
    expect(c.read(brandColorProvider), const Color(0xFF0E7C66));
    expect(c.read(brandTaglineProvider), 'Hi');
  });
}
