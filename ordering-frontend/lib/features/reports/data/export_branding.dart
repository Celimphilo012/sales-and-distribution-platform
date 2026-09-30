import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../shared/export/report_export.dart';
import '../../settings/data/branding_api.dart';

/// The header every export carries: company name + logo (Settings → Report
/// branding) and "[period] · Generated (when) by (you)".
Future<ExportBranding> loadExportBranding(WidgetRef ref, {String? scope}) async {
  final branding = await ref.read(brandingProvider.future);
  final logo = branding.hasLogo ? await ref.read(brandingLogoProvider.future).catchError((_) => null) : null;
  final user = ref.read(authProvider).value?.user;
  return ExportBranding(
    company: branding.companyName,
    subtitle: '${scope ?? 'Ordering System'} · Generated ${exportStamp()}${user == null ? '' : ' by ${user.name}'}',
    logo: logo,
  );
}
