import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../shared/export/report_export.dart';
import '../../settings/data/branding_api.dart';
import '../../warehouses/data/warehouses_providers.dart';

/// The header every export carries: company name + logo (Settings →
/// Branding) and "your warehouses · Generated (when) by (you)".
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
  );
}
