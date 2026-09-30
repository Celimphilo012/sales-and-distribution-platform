import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/theme/brand_palette.dart';
import '../../../shared/export/report_export.dart';
import '../../settings/data/branding_api.dart';
import '../../warehouses/data/warehouses_providers.dart';

/// The letterhead every export carries (Settings → Branding): company name,
/// tagline, logo, brand colour, contact block and small print — plus "your
/// warehouses · Generated (when) by (you)".
Future<ExportBranding> loadExportBranding(WidgetRef ref) async {
  final branding = await ref.read(brandingProvider.future);
  final logo = branding.hasLogo ? await ref.read(brandingLogoProvider.future).catchError((_) => null) : null;
  final user = ref.read(authProvider).value?.user;
  final warehouses = (await ref.read(warehousesProvider(false).future)).where((w) => w.isActive).toList();
  final scope = warehouses.isEmpty
      ? 'All warehouses'
      : warehouses.length == 1
      ? '${warehouses.first.name} (${warehouses.first.code})'
      : '${warehouses.length} warehouses';
  return ExportBranding(
    company: branding.companyName,
    subtitle: '$scope · Generated ${exportStamp()}${user == null ? '' : ' by ${user.name}'}',
    logo: logo,
    color: BrandPalette.parse(branding.brandColor),
    tagline: branding.tagline,
    contact: branding.letterhead.contactLines,
    registration: branding.letterhead.registration,
    footer: branding.letterhead.footer,
  );
}
