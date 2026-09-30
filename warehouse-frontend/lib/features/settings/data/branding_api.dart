import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/providers.dart';

/// Report branding — the company name and logo printed at the top of every
/// PDF / Excel export and pick list (`/settings/branding`).
class Branding {
  const Branding({required this.companyName, required this.hasLogo, this.logoVersion});

  final String companyName;
  final bool hasLogo;

  /// Changes whenever the logo does (cache key for the image bytes).
  final String? logoVersion;

  factory Branding.fromJson(Map<String, dynamic> json) => Branding(
    companyName: json['companyName'] as String? ?? 'Warehouse System',
    hasLogo: json['hasLogo'] as bool? ?? false,
    logoVersion: json['logoVersion'] as String?,
  );
}

class BrandingApi {
  BrandingApi(this._apiClient);

  final ApiClient _apiClient;

  Future<Branding> get() async {
    final response = await _apiClient.guard((dio) => dio.get<Map<String, dynamic>>('/settings/branding'));
    return Branding.fromJson(response.data!);
  }

  Future<Branding> setCompanyName(String name) async {
    final response = await _apiClient.guard(
      (dio) => dio.put<Map<String, dynamic>>('/settings/branding', data: {'companyName': name}),
    );
    return Branding.fromJson(response.data!);
  }

  Future<Branding> uploadLogo(Uint8List bytes, String fileName) async {
    final response = await _apiClient.guard(
      (dio) => dio.post<Map<String, dynamic>>(
        '/settings/branding/logo',
        data: FormData.fromMap({'file': MultipartFile.fromBytes(bytes, filename: fileName)}),
      ),
    );
    return Branding.fromJson(response.data!);
  }

  Future<Branding> clearLogo() async {
    final response = await _apiClient.guard((dio) => dio.delete<Map<String, dynamic>>('/settings/branding/logo'));
    return Branding.fromJson(response.data!);
  }

  Future<Uint8List> logoBytes() async {
    final response = await _apiClient.guard(
      (dio) => dio.get<List<int>>('/settings/branding/logo', options: Options(responseType: ResponseType.bytes)),
    );
    return Uint8List.fromList(response.data!);
  }
}

final brandingApiProvider = Provider<BrandingApi>((ref) => BrandingApi(ref.watch(apiClientProvider)));

final brandingProvider = FutureProvider.autoDispose<Branding>((ref) => ref.watch(brandingApiProvider).get());

/// The uploaded logo's bytes, or null when none is set (the default mark is drawn instead).
final brandingLogoProvider = FutureProvider.autoDispose<Uint8List?>((ref) async {
  final branding = await ref.watch(brandingProvider.future);
  if (!branding.hasLogo) return null;
  return ref.watch(brandingApiProvider).logoBytes();
});
