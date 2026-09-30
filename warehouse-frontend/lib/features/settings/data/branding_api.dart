import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/providers.dart';

/// Company branding (`/settings/branding`): the company name, tagline, brand
/// colour and logo — on the browser tab, the top bar, the sign-in page, the
/// console's accent colour, and every PDF / Excel export, pick list and label.
/// The letterhead printed on PDF documents (and the contact line under emails).
class Letterhead {
  const Letterhead({this.address, this.phone, this.email, this.website, this.registration, this.footer});

  final String? address;
  final String? phone;
  final String? email;
  final String? website;

  /// Company registration / VAT number line.
  final String? registration;

  /// Small print at the foot of every document page.
  final String? footer;

  static const fields = ['address', 'phone', 'email', 'website', 'registration', 'footer'];

  String? operator [](String field) => switch (field) {
    'address' => address,
    'phone' => phone,
    'email' => email,
    'website' => website,
    'registration' => registration,
    'footer' => footer,
    _ => null,
  };

  /// Address, phone, email and website — the contact block.
  List<String> get contactLines => [?address, ?phone, ?email, ?website];

  bool get isEmpty => fields.every((f) => (this[f] ?? '').isEmpty);

  factory Letterhead.fromJson(Map<String, dynamic>? json) => Letterhead(
    address: json?['address'] as String?,
    phone: json?['phone'] as String?,
    email: json?['email'] as String?,
    website: json?['website'] as String?,
    registration: json?['registration'] as String?,
    footer: json?['footer'] as String?,
  );
}

class Branding {
  const Branding({
    required this.companyName,
    required this.hasLogo,
    this.logoVersion,
    this.tagline,
    this.brandColor,
    this.headingFont,
    this.bodyFont,
    this.letterhead = const Letterhead(),
    this.emailSignature,
  });

  final String companyName;
  final bool hasLogo;

  /// A short line under the name ("Wholesale · Mbabane"), or null.
  final String? tagline;

  /// "#RRGGBB", or null for the built-in accent.
  final String? brandColor;

  /// Approved brand fonts (null = Inter).
  final String? headingFont;
  final String? bodyFont;

  final Letterhead letterhead;

  /// Sign-off appended to every email the system sends.
  final String? emailSignature;

  /// Changes whenever the logo does (cache key for the image bytes).
  final String? logoVersion;

  factory Branding.fromJson(Map<String, dynamic> json) => Branding(
    companyName: json['companyName'] as String? ?? 'Warehouse System',
    hasLogo: json['hasLogo'] as bool? ?? false,
    logoVersion: json['logoVersion'] as String?,
    tagline: json['tagline'] as String?,
    brandColor: json['brandColor'] as String?,
    headingFont: json['headingFont'] as String?,
    bodyFont: json['bodyFont'] as String?,
    letterhead: Letterhead.fromJson(json['letterhead'] as Map<String, dynamic>?),
    emailSignature: json['emailSignature'] as String?,
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

  /// Changes only the fields given; '' clears a field (the brand colour and
  /// fonts go back to the built-in ones). [letterhead] is field → text.
  Future<Branding> setIdentity({
    String? companyName,
    String? tagline,
    String? brandColor,
    String? headingFont,
    String? bodyFont,
    Map<String, String>? letterhead,
    String? emailSignature,
  }) async {
    final response = await _apiClient.guard(
      (dio) => dio.put<Map<String, dynamic>>(
        '/settings/branding',
        data: {
          'companyName': ?companyName,
          'tagline': ?tagline,
          'brandColor': ?brandColor,
          'headingFont': ?headingFont,
          'bodyFont': ?bodyFont,
          'letterhead': ?letterhead,
          'emailSignature': ?emailSignature,
        },
      ),
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
